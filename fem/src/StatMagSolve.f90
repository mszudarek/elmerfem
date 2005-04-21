!/******************************************************************************
! *
! *       ELMER, A Computational Fluid Dynamics Program.
! *
! *       Copyright 1st April 1995 - , Center for Scientific Computing,
! *                                    Finland.
! *
! *       All rights reserved. No part of this program may be used,
! *       reproduced or transmitted in any form or by any means
! *       without the written permission of CSC.
! *
! *****************************************************************************/
!
!/******************************************************************************
! *
! * File containing a solver for static axisymmetric magnetic field with vector
! * potential formulation.
! *
! ******************************************************************************/



!------------------------------------------------------------------------------
   SUBROUTINE StatMagSolver( Model, Solver, dt, Transient )
!DEC$ATTRIBUTES DLLEXPORT :: StatMagSolver
!------------------------------------------------------------------------------
!******************************************************************************
!
!  Solve magnetic field for one time step
!
!  ARGUMENTS:
!
!  TYPE(Model_t) :: Model,  
!     INPUT: All model information (mesh,materials,BCs,etc...)
!
!  TYPE(Solver_t) :: Solver
!     INPUT: Linear equation solver options
!
!  REAL (KIND=DP) :: dt,
!     INPUT: Timestep size for time dependent simulations
!
!  LOGICAL :: Transient
!     INPUT: Flag for time dependent simulation
!
!******************************************************************************


    USE DefUtils
    USE Differentials
    
    IMPLICIT NONE
    
    TYPE(Model_t) :: Model
    TYPE(Solver_t), TARGET :: Solver
    REAL (KIND=DP) :: dt 
    LOGICAL :: Transient

!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------

    TYPE(Matrix_t),POINTER :: StiffMatrix
    REAL (KIND=DP), POINTER :: ForceVector(:),MVP(:),MFD(:), PhaseAngle(:)
    REAL (KIND=DP), POINTER :: A(:), Br(:), Bz(:), Bp(:), Brim(:), Bzim(:), &
        Joule(:), absJoule(:)
    
    TYPE(ValueList_t),POINTER :: Material
    TYPE(Nodes_t) :: ElementNodes
    TYPE(Element_t),POINTER :: CurrentElement

    TYPE(Variable_t), POINTER :: MagneticSol, BVar

    INTEGER, POINTER :: NodeIndexes(:),MagneticPerm(:)

    REAL (KIND=DP), ALLOCATABLE :: Reluctivity(:), CurrentDensity(:), &
        LocalMassMatrix(:,:),LocalStiffMatrix(:,:),LocalForce(:), &
        Ap(:),Permeability(:), Conductivity(:), Ae(:),VecLoadVector(:,:)

    REAL (KIND=DP) :: UNorm,PrevUNorm,NonlinearTol,RelativeChange, &
        at,at0,RealTime,CPUTime, AngularFrequency, jc, jre, jim, &
        TotalHeating, DesiredHeating, TotalVolume

    INTEGER :: body_id, eq_id, bf_id, LocalNodes, NonlinearIter
    INTEGER :: t,n,k,istat,i,iter,nedges,nfaces,q,j,dofs,dim

    TYPE(Solver_t), POINTER :: PSolver

    LOGICAL :: GotIt, HarmonicSimulation, CalculateJouleHeating, &
        CalculateMagneticFlux, AllocationsDone = .FALSE.

    CHARACTER(LEN=MAX_NAME_LEN) :: EquationName
    CHARACTER(LEN=MAX_NAME_LEN) :: VersionID = "$Id: StatMagSolve.f90,v 1.25 2004/07/30 07:39:30 jpr Exp $"

    SAVE LocalMassMatrix,LocalStiffMatrix,CurrentDensity,LocalForce, &
        ElementNodes,Reluctivity,AllocationsDone,Ap,MFD, &
        Permeability, Conductivity, Ae, VecLoadVector, Joule, &
        PhaseAngle, Br, Bz, Bp, Brim, Bzim

!------------------------------------------------------------------------------
!    Check if version number output is requested
!------------------------------------------------------------------------------
    IF ( .NOT. AllocationsDone ) THEN
      IF ( ListGetLogical( GetSimulation(), 'Output Version Numbers', GotIt ) ) THEN
        CALL Info( 'StatMagSolve', 'StatMagSolve version:', Level = 0 ) 
        CALL Info( 'StatMagSolve', VersionID, Level = 0 ) 
        CALL Info( 'StatMagSolve', ' ', Level = 0 ) 
      END IF
    END IF
 !------------------------------------------------------------------------------
!    Get variables needed for solving the system
!------------------------------------------------------------------------------
    IF ( .NOT. ASSOCIATED( Solver % Matrix ) ) RETURN

    dim = CoordinateSystemDimension()

    MagneticSol => Solver % Variable 
    MagneticPerm  => MagneticSol % Perm
    MVP => MagneticSol % Values

    LocalNodes = COUNT( MagneticPerm > 0 )
    IF ( LocalNodes <= 0 ) RETURN

    StiffMatrix => Solver % Matrix
    ForceVector => StiffMatrix % RHS

    UNorm = Solver % Variable % Norm

    HarmonicSimulation = ListGetLogical( Solver % Values, &      
              'Harmonic Simulation',gotIt )
    IF (.NOT.gotIt) HarmonicSimulation = .FALSE.
    IF ( Solver % Variable % DOFs == 2 ) HarmonicSimulation = .TRUE.

    IF(HarmonicSimulation) THEN
      dofs = 2
      Solver % Matrix % Complex = .TRUE.
      AngularFrequency = ListGetConstReal( Solver % Values, 'Angular Frequency')
      CalculateJouleHeating = &
          ListGetLogical( Solver % Values, 'Calculate Joule Heating', GotIt )
      IF(.Not. GotIt) CalculateJouleHeating = .True.
    ELSE
      dofs = 1
    END IF

    CalculateMagneticFlux = &
        ListGetLogical( Solver % Values, 'Calculate Magnetic Flux', GotIt )
    IF(.NOT. GotIt) CalculateMagneticFlux = .True.

!------------------------------------------------------------------------------
!    Allocate some permanent storage, this is done first time only
!------------------------------------------------------------------------------

    IF (.NOT. AllocationsDone) THEN

      IF ( dim == 3 ) THEN
! Hack for tetras
        nedges=6 ! 12 for bricks
        nfaces=4 !  6 for bricks
      ELSE
        nedges=0
      END IF
      
      N = Model % MaxElementNodes

      ALLOCATE(Reluctivity(N), &
          Permeability(N), &
          Conductivity(N), &
          ElementNodes % x( N ), &
          ElementNodes % y( N ), &
          ElementNodes % z( N ), &
          CurrentDensity(N), &
          PhaseAngle(N), &
          LocalMassMatrix(dofs*N,dofs*N), &
          LocalStiffMatrix(dofs*N,dofs*N), &
          LocalForce(dofs*N), &
          Ap(n), &
          Ae(n), &
          VecLoadVector(3,n), & !only n-nedges corner nodes used
          STAT=istat)

!------------------------------------------------------------------------------
!    Add magnetic flux density to variables
!------------------------------------------------------------------------------        
       
      IF(CalculateMagneticFlux) THEN
        
        ALLOCATE( MFD(3*Model%NumberofNodes), STAT=istat)

        PSolver => Solver
        Br => MFD(1:3*LocalNodes-2:3) !Bx
        CALL VariableAdd(Solver % Mesh % Variables, Solver % Mesh, PSolver, &
            'Magnetic Flux Density 1', 1, Br, MagneticPerm)
        
        Bz => MFD(2:3*LocalNodes-1:3) !By
        CALL VariableAdd(Solver % Mesh % Variables, Solver % Mesh, PSolver, &
            'Magnetic Flux Density 2', 1, Bz, MagneticPerm)
        
        Bp => MFD(3:3*LocalNodes:3)   !Bz
        CALL VariableAdd(Solver % Mesh % Variables, Solver % Mesh, PSolver, &
            'Magnetic Flux Density 3', 1, Bp, MagneticPerm)
        
        CALL VariableAdd(Solver % Mesh % Variables, Solver % Mesh, PSolver, &
            'Magnetic Flux Density', 3, MFD, MagneticPerm)
      END IF

      IF(HarmonicSimulation) THEN
        IF ( CalculateJouleHeating )  THEN
          ALLOCATE( Joule( Model%NumberOfNodes ), STAT=istat )
          IF ( istat /= 0 ) CALL Fatal( 'StatMagSolve', 'Memory allocation error.' )
          CALL VariableAdd(Solver % Mesh % Variables, Solver % Mesh, PSolver, &
              'Joule Heating', 1, Joule, MagneticPerm)
        END IF
        IF(CalculateMagneticFlux) THEN
          ALLOCATE( Brim( Model%NumberOfNodes ), Bzim( Model%NumberOfNodes ), STAT=istat )
          IF ( istat /= 0 ) CALL Fatal( 'StatMagSolve', 'Memory allocation error.' )
        END IF
        IF(CalculateJouleHeating) THEN
          ALLOCATE( absJoule( Model%NumberOfNodes ), STAT=istat )
          IF ( istat /= 0 ) CALL Fatal( 'StatMagSolve', 'Memory allocation error.' )
          absJoule = 0.0d0
          CALL VariableAdd(Solver % Mesh % Variables, Solver % Mesh, PSolver, &
              'Joule Field', 1, absJoule, MagneticPerm)
        END IF
      END IF

      AllocationsDone = .TRUE.
    END IF

    IF( HarmonicSimulation .AND. CalculateJouleHeating) THEN
      Joule = 0.0d0
    END IF

!--------------------------------------------------------------

    NonlinearTol = ListGetConstReal( Solver % Values, &
        'Nonlinear System Convergence Tolerance' )

    NonlinearIter = ListGetInteger( Solver % Values, &
        'Nonlinear System Max Iterations' )

    EquationName = ListGetString( Solver % Values, 'Equation' )

!---------------------------------------------------------------

    DO iter=1,NonlinearIter

       at  = CPUTime()
       at0 = RealTime()

       CALL Info( 'StatMagSolve', ' ', Level=4 )
       CALL Info( 'StatMagSolve', ' ', Level=4 )
       CALL Info( 'StatMagSolve', &
               '-------------------------------------', Level=4 )
       IF(HarmonicSimulation) THEN
         WRITE( Message, * ) 'Harmonic Magnetic Field Iteration: ', iter
       ELSE
         WRITE( Message, * ) 'Static Magnetic Field Iteration: ', iter
       END IF
       CALL Info( 'StatMagSolve', Message, Level=4 )
       CALL Info( 'StatMagSolve', &
               '-------------------------------------', Level=4 )
       CALL Info( 'StatMagSolve', ' ', Level=4 )

       CALL DefaultInitialize()
       
       DO t=1, Model % NumberOfBulkElements 
         IF ( RealTime() - at0 > 1.0 ) THEN
           WRITE(Message,'(a,i3,a)' ) '   Assembly: ', INT(100.0 - 100.0 * &
               (Model % NumberOfBulkElements-t) / &
               (1.0*Model % NumberOfBulkElements)), ' % done'
           
           CALL Info( 'StatMagSolve', Message, Level=5 )
           at0 = RealTime()
         END IF
     
!------------------------------------------------------------------------------
!        Check if this element belongs to a body where the equations
!        should be calculated
!------------------------------------------------------------------------------

         CurrentElement => Solver % Mesh % Elements(t)
         
         NodeIndexes => CurrentElement % NodeIndexes
         
         IF ( .NOT.CheckElementEquation( Model, &
             CurrentElement,EquationName ) ) CYCLE

!------------------------------------------------------------------------------
!        ok, we�ve got one for Maxwell equations
!------------------------------------------------------------------------------
!
!------------------------------------------------------------------------------
!        Set also the current element pointer in the model structure to
!        reflect the element being processed
!------------------------------------------------------------------------------
         Model % CurrentElement => CurrentElement

         body_id = CurrentElement % BodyId
         
         n = CurrentElement % TYPE % NumberOfNodes
         
         ElementNodes % x(1:n) = Model % Nodes % x(NodeIndexes(1:n))
         ElementNodes % y(1:n) = Model % Nodes % y(NodeIndexes(1:n))
         ElementNodes % z(1:n) = Model % Nodes % z(NodeIndexes(1:n))
         
         k = ListGetInteger( Model % Bodies(body_id) % Values, 'Material', &
                  minv=1, maxv=Model % NumberOFMaterials )
         Material => Model % Materials(k) % Values
         
         Permeability(1:n) = ListGetReal(Material, &
             'Magnetic Permeability',n,NodeIndexes,GotIt)
         IF(.NOT. GotIt) Permeability = PI*4.0d-7
         Reluctivity(1:n) = 1.0/Permeability(1:n)
         
         IF(HarmonicSimulation) THEN
           Conductivity(1:n) = ListGetReal(Material, &
               'Electrical Conductivity',n,NodeIndexes)
         END IF
         
!------------------------------------------------------------------------------
!        Set body forces (applied current densities)
!------------------------------------------------------------------------------
  
         bf_id = ListGetInteger( Model % Bodies(body_id) % Values, &
             'Body Force',gotIt, minv=1, maxv=Model % NumberOFBodyForces )


         IF( dim < 3) THEN
           IF ( bf_id > 0  ) THEN
             CurrentDensity(1:n) = ListGetReal( &
                 Model % BodyForces(bf_id) % Values,'Current Density',n,NodeIndexes,GotIt )
           ELSE 
             CurrentDensity(1:n) = 0.0d0
           END IF
           
           IF(HarmonicSimulation) THEN
             IF(bf_id > 0) THEN
               PhaseAngle(1:n) = ListGetReal( &
                   Model % BodyForces(bf_id) % Values,'Current Phase Angle',n,NodeIndexes,GotIt )
             ELSE
               PhaseAngle(1:n) = 0.0d0
             END IF
           END IF
         END IF

         IF ( dim == 3) THEN
! Get VecLoadVector in 3D
           VecLoadVector=0.0_dp
           IF ( bf_id > 0  ) THEN
             VecLoadVector(1,1:n) = VecLoadVector(1,1:n) + ListGetReal( &
                 Model % BodyForces(bf_id) % Values, &
                 'Current Density 1',n,NodeIndexes,gotIt )
             
             VecLoadVector(2,1:n) = VecLoadVector(2,1:n) + ListGetReal( &
                 Model % BodyForces(bf_id) % Values, &
                 'Current Density 2',n,NodeIndexes,gotIt )
             
             VecLoadVector(3,1:n) = VecLoadVector(3,1:n) + ListGetReal( &
                 Model % BodyForces(bf_id) % Values, &
                 'Current Density 3',n,NodeIndexes,gotIt )
           END IF
         END IF

         IF (iter==1) THEN
           IF ( dim == 3) THEN
             Ae(:)=0._dp
           ELSE
             Ap(:)=0
           END IF
         ELSE
!#if 0
!         IF (dim == 3) THEN
!! For W1
!           DO i=n-nedges+1,n
!             Ae(i) = MVP(MagneticPerm(NodeIndexes(i)))
!           END DO
!         ELSE
!           DO i=1,n
!             Ap(i) = MVP(MagneticPerm(NodeIndexes(i)))
!           END DO
!         END IF
!#endif
       END IF

!------------------------------------------------------------------------------
!        Get element local stiffness & mass matrices
!------------------------------------------------------------------------------
       IF ( dim < 3 ) THEN
! For axisymmetric problem, use regular elements
         IF(HarmonicSimulation) THEN
           CALL HarmMagAxisCompose( &
               LocalStiffMatrix,LocalForce,CurrentDensity,PhaseAngle,Reluctivity, &
               Conductivity,AngularFrequency,CurrentElement,n,ElementNodes )
         ELSE
           CALL StatMagAxisCompose( &
               LocalMassMatrix,LocalStiffMatrix,LocalForce, &
               CurrentDensity,Reluctivity,Ap,CurrentElement,n,ElementNodes )
         END IF
         
! For 3D problem, use Whitney elements
       ELSE
! W1 and edge DOFs
         CALL StatMagCompose( &
             LocalMassMatrix,LocalStiffMatrix,LocalForce, &
             VecLoadVector(:,1:n-nedges),Reluctivity,Ae,CurrentElement,&
             n-nedges,nedges,ElementNodes )
! W2 and face DOFs
!        CALL StatMagCompose2( &
!            LocalMassMatrix,LocalStiffMatrix,LocalForce, &
!            VecLoadVector,Reluctivity,Ae,CurrentElement,&
!            n-nfaces,nfaces,ElementNodes )
       END IF
!------------------------------------------------------------------------------
!        If time dependent simulation, add mass matrix to global 
!        matrix and global RHS vector
!------------------------------------------------------------------------------
!      IF ( Transient ) THEN
!------------------------------------------------------------------------------
!          NOTE: This will replace LocalStiffMatrix and LocalForce with the
!                combined information...
!------------------------------------------------------------------------------
!        CALL Add1stOrderTime( LocalMassMatrix, LocalStiffMatrix, &
!            LocalForce,dt,n,1,MagneticPerm(NodeIndexes),Solver )
!      END IF

!      CALL UpdateGlobalEquations( StiffMatrix, LocalStiffMatrix, &
!          ForceVector, LocalForce, n, Solver % Variable % DOFs, &
!          MagneticPerm(NodeIndexes) )
       CALL DefaultUpdateEquations( LocalStiffMatrix, LocalForce )
       
     END DO
      
     CALL Info( 'StatMagSolve', 'Assembly done', Level=4 )

!    CALL FinishAssembly( Solver,ForceVector )
     CALL DefaultFinishAssembly()

!------------------------------------------------------------------------------
!     Dirichlet boundary conditions
!------------------------------------------------------------------------------
!    IF(HarmonicSimulation) THEN
!      CALL SetDirichletBoundaries( Model, StiffMatrix, ForceVector, &
!          TRIM(Solver % Variable % Name) // ' 1', 1, &
!          Solver % Variable % DOFs, MagneticPerm )
!      CALL SetDirichletBoundaries( Model, StiffMatrix, ForceVector, &
!          TRIM(Solver % Variable % Name) // ' 2', 2, &
!          Solver % Variable % DOFs, MagneticPerm )
!    ELSE
!      CALL SetDirichletBoundaries( Model, StiffMatrix, ForceVector, &
!          TRIM(Solver % Variable % Name), 1, &
!          Solver % Variable % DOFs, MagneticPerm )
!    END IF
     CALL DefaultDirichletBCs()
     
     CALL Info( 'StatMagSolve', 'Set boundaries done', Level=4 )
!------------------------------------------------------------------------------
!     Solve the system and check for convergence
!------------------------------------------------------------------------------
     PrevUNorm = UNorm
     
!    CALL SolveSystem( StiffMatrix, ParMatrix, ForceVector, &
!        MVP, UNorm, Solver % Variable % DOFs, Solver )
     UNorm = DefaultSolve()
     
     IF ( PrevUNorm + UNorm /= 0.0d0 ) THEN
       RelativeChange = 2.0d0 * ABS(PrevUNorm-UNorm)/ (PrevUNorm + UNorm)
     ELSE
       RelativeChange = 0.0d0
     END IF
     
     WRITE( Message, * ) 'RelativeChange',RelativeChange,PrevUNorm,UNorm,NonLinearTol
     CALL Info( 'StatMagSolve', Message, Level = 4 )
     
     IF ( RelativeChange < NonLinearTol ) THEN
       WRITE( Message, * ) 'Convergence after ',iter,' iterations'
       CALL Info( 'StatMagSolve', Message, Level = 4 )
       EXIT
     END IF
     
   END DO

!---------------------------------------------------------------------
! Compute the magnetic flux density from the potential: B = curl A
! Here A = A_phi e_phi and B = B_rho e_rho + B_z e_z due to axisymmetry
!---------------------------------------------------------------------


   IF(CalculateMagneticFlux) THEN
     
     MFD = 0.0d0
     IF(HarmonicSimulation) THEN
       A => MVP(2:2*LocalNodes:2)     
       CALL AxiSCurl(Bp,Bp,A,Brim,Bzim,Bp,MagneticPerm)

       A => MVP(1:2*LocalNodes-1:2)
       CALL AxiSCurl(Bp,Bp,A,Br,Bz,Bp,MagneticPerm)
       
       DO i=1, Model%NumberofNodes
         IF(MagneticPerm(i) > 0) THEN
           Br(MagneticPerm(i)) = SQRT( Br(MagneticPerm(i))**2.0 + Brim(MagneticPerm(i))**2.0 )
           Bz(MagneticPerm(i)) = SQRT( Bz(MagneticPerm(i))**2.0 + Bzim(MagneticPerm(i))**2.0 )
           Brim(MagneticPerm(i)) = 0.0d0
           Bzim(MagneticPerm(i)) = 0.0d0
         END IF
       END DO
     ELSE
       IF ( dim < 3 ) THEN
         A => MVP
         CALL AxiSCurl(Bp,Bp,A,Br,Bz,Bp,MagneticPerm)
       ELSE
         Br=0
         Bz=0
         Bp=0
         CALL WhitneyCurl( A,Br,Bz,Bp,MagneticPerm,nedges )
! Bx=Br, By=Bz, Bz=Bp
! Compute (Ax,Ay,Az) [or (Bx,By,Bz)] for visualization
!      CALL CompVecPot( A,Br,Bz,Bp,n-nfaces,nfaces,2 )
       END IF
     END IF

     CALL InvalidateVariable( Model % Meshes, Solver % Mesh, &
         'Magnetic Flux Density')
   END IF


!---------------------------------------------------------------------
! In case of harmonic simulation it is possible to compute the Joule losses
!---------------------------------------------------------------------

   IF(HarmonicSimulation .AND. CalculateJouleHeating) THEN
    
     jc = 0.5d0 * (2.0*PI*AngularFrequency)**2.0
     
     DO i=1, Model%NumberofNodes
       IF(MagneticPerm(i) > 0) THEN
         jre = MVP(2*MagneticPerm(i)-1)
         jim = MVP(2*MagneticPerm(i))
         absJoule(MagneticPerm(i)) = jc * (jre*jre+jim*jim)
       END IF
     END DO
     
     TotalHeating = 0.0d0
     TotalVolume = 0.0d0
     
     DO t=1, Model % NumberOfBulkElements 
       
       CurrentElement => Solver % Mesh % Elements(t)
       
       NodeIndexes => CurrentElement % NodeIndexes
       
       IF ( .NOT.CheckElementEquation( Model, &
           CurrentElement,EquationName ) ) CYCLE
       
       Model % CurrentElement => CurrentElement
       body_id = CurrentElement % BodyId
       n = CurrentElement % TYPE % NumberOfNodes
       
       ElementNodes % x(1:n) = Model % Nodes % x(NodeIndexes)
       ElementNodes % y(1:n) = Model % Nodes % y(NodeIndexes)
       ElementNodes % z(1:n) = Model % Nodes % z(NodeIndexes)
       
       k = ListGetInteger( Model % Bodies(body_id) % Values, 'Material', &
               minv=1, maxv=Model % NumberOFMaterials )
       Material => Model % Materials(k) % Values
       
       Conductivity(1:n) = ListGetReal(Material, &
           'Electrical Conductivity',n,NodeIndexes)
       
       Ae(1:n) = absJoule(MagneticPerm(NodeIndexes(1:n)))
       CALL JouleIntegrate(Ae,Conductivity,TotalHeating,TotalVolume,&
           CurrentElement,n,ElementNodes )
       
       DO i=1,n
         j = MagneticPerm(NodeIndexes(i))
         IF(j > 0) THEN
           jc = Conductivity(i) * absJoule(j)
           IF(jc > Joule(j)) Joule(j) = jc
         END IF
       END DO
       
     END DO
    
     DesiredHeating = ListGetConstReal( Solver % Values, 'Desired Heating Power',gotIt)
     IF(gotIt .AND. TotalHeating > 0.0d0) THEN
       absJoule = (DesiredHeating/TotalHeating) * absJoule
       Joule = (DesiredHeating/TotalHeating) * Joule
     END IF
     
     WRITE(Message,'(A,ES15.4)') 'Joule Heating (W): ',TotalHeating
     CALL Info('StatMagSolve',Message,Level=4)
     CALL ListAddConstReal( Model % Simulation, 'res: Joule heating',TotalHeating)
   END IF


CONTAINS

!/*******************************************************************************
! *
! * Subroutine for computing local matrices for static magnetic field
! *in cylindrical coordinates with axisymmetry.

! *                     Author:       Jussi Heikonen
! *
! ******************************************************************************/

!------------------------------------------------------------------------------
    SUBROUTINE StatMagAxisCompose( &
        MassMatrix,StiffMatrix,ForceVector,LoadVector,NodalReluctivity, &
        Ap,Element,n,Nodes)

!------------------------------------------------------------------------------
!******************************************************************************
!
!  Return element local matrices and RHS vector for static magnetic field
!
!  ARGUMENTS:
!
!  REAL (KIND=DP) :: MassMatrix(:,:)
!     OUTPUT: time derivative coefficient matrix
!
!  REAL (KIND=DP) :: StiffMatrix(:,:)
!     OUTPUT: rest of the equation coefficients
!
!  REAL (KIND=DP) :: ForceVector(:)
!     OUTPUT: RHS vector
!
!  REAL (KIND=DP) :: LoadVector(:)
!     INPUT:
!
!  REAL (KIND=DP) :: NodalReluctivity(:)
!     INPUT: Nodal values of relucitivity ( 1 / permeability )
!
!  REAL (KIND=DP) :: Ap(:)
!     INPUT: Vector potential from the previous iteration for computing
!            the "reluctivity" in a nonlinear material

!  TYPE(Element_t) :: Element
!       INPUT: Structure describing the element (dimension,nof nodes,
!               interpolation degree, etc...)
!
!  INTEGER :: n
!       INPUT: Number of element nodes
!
!  TYPE(Nodes_t) :: Nodes
!       INPUT: Element node coordinates
!
!******************************************************************************
!------------------------------------------------------------------------------
      USE Types
      USE Integration
      USE ElementDescription

      IMPLICIT NONE
     
      REAL (KIND=DP),TARGET :: MassMatrix(:,:),StiffMatrix(:,:),&
          ForceVector(:)
      REAL (KIND=DP) :: NodalReluctivity(:), Reluctivity
      REAL (KIND=DP) :: LoadVector(:),Ap(:)

      INTEGER :: n

      TYPE(Nodes_t) :: Nodes
      TYPE(Element_t) :: Element

!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------

      REAL (KIND=DP) :: Basis(n),dBasisdx(n,3),ddBasisddx(n,3,3)
      REAL (KIND=DP) :: SqrtElementMetric

      REAL (KIND=DP) :: Force,r,Br,Bz,Babs,mat

      REAL (KIND=DP), POINTER :: A(:,:),M(:,:),Load(:)

      INTEGER :: DIM,t,i,j,p,q

      REAL (KIND=DP) :: s,u,v,w

      TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff
      INTEGER :: N_Integ
      REAL (KIND=DP), DIMENSION(:), POINTER :: U_Integ,V_Integ,W_Integ,&
          S_Integ

      LOGICAL :: stat

!***********************************************************************!

     DIM = 2

     ForceVector = 0.0D0
     MassMatrix  = 0.0D0
     StiffMatrix = 0.0D0

!------------------------------------------------------------------------------
!    Integration stuff
!------------------------------------------------------------------------------

     IntegStuff = GaussPoints( element )
     U_Integ => IntegStuff % u
     V_Integ => IntegStuff % v
     W_Integ => IntegStuff % w
     S_Integ => IntegStuff % s
     N_Integ =  IntegStuff % n

!------------------------------------------------------------------------------
!   Now we start integrating
!------------------------------------------------------------------------------
     DO t=1,N_Integ

       u = U_Integ(t)
       v = V_Integ(t)
       w = W_Integ(t)

!------------------------------------------------------------------------------
!     Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
       stat = ElementInfo( Element,Nodes,u,v,w,SqrtElementMetric, &
                 Basis,dBasisdx,ddBasisddx,.FALSE. )

       r = SUM( Basis(1:n) * Nodes%x(1:n))

       s = SqrtElementMetric * S_Integ(t)
       
!------------------------------------------------------------------------------
!     Values at integration point
!------------------------------------------------------------------------------

       Force = SUM( LoadVector(1:n) * Basis(1:n) )

       Reluctivity = SUM( NodalReluctivity(1:n) * Basis(1:n) )

!------------------------------------------------------------------------------
!    Loop over basis functions (of both unknowns and weights)
!------------------------------------------------------------------------------
       DO p=1,N
         DO q=1,N
!------------------------------------------------------------------------------
!      The equation for the vector potential
!------------------------------------------------------------------------------
!------------------------------------------------------------------------------
!      Mass matrix:
!------------------------------------------------------------------------------
!           MassMatrix(p,q) = MassMatrix(p,q) + Basis(p)*Basis(q)*s*r

!------------------------------------------------------------------------------
!      Stiffness matrix:
!------------------------------

           mat = r*dBasisdx(p,1)*dBasisdx(q,1) + &
               r*dBasisdx(p,2)*dBasisdx(q,2) + &
               Basis(p)*dBasisdx(q,1) + &
               Basis(q)*dBasisdx(p,1) + &
               Basis(p)*Basis(q)/r 
           mat = mat * Reluctivity * s

           StiffMatrix(p,q) = StiffMatrix(p,q) + mat

         END DO
       END DO

!------------------------------------------------------------------------------
!    The righthand side...
!------------------------------------------------------------------------------
       DO p=1,N

         ForceVector(p) = ForceVector(p) + Force*Basis(p)*r*s

       END DO

     END DO

   END SUBROUTINE StatMagAxisCompose


!/*******************************************************************************
! *
! * Subroutine for computing local matrices for harmonic magnetic field
! * in cylindrical coordinates with axisymmetry.
! *
! *                     Author: Peter R�back
! *
! ******************************************************************************/

!------------------------------------------------------------------------------
   SUBROUTINE HarmMagAxisCompose( &
       StiffMatrix,ForceVector,CurrentDensity,NodalAngle,NodalReluctivity, NodalConductivity,&
       Frequency,Element,n,Nodes)

!------------------------------------------------------------------------------

     USE Types
     USE Integration
     USE ElementDescription
     
     IMPLICIT NONE
     
     REAL (KIND=DP),TARGET :: StiffMatrix(:,:), ForceVector(:)
     REAL (KIND=DP) :: NodalReluctivity(:), NodalAngle(:), Reluctivity, &
         NodalConductivity(:), Conductivity, Angle
     REAL (KIND=DP) :: CurrentDensity(:), Frequency
     
     INTEGER :: n
     
     TYPE(Nodes_t) :: Nodes
     TYPE(Element_t) :: Element
     
!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------

     REAL (KIND=DP) :: Basis(n),dBasisdx(n,3),ddBasisddx(n,3,3)
     REAL (KIND=DP) :: SqrtElementMetric
     
     REAL (KIND=DP) :: Force,r,wang,a11,a21,a12,a22
     REAL (KIND=DP), POINTER :: A(:,:),M(:,:),Load(:)
     
     INTEGER :: DIM,t,i,j,p,q
     
     REAL (KIND=DP) :: s,u,v,w

     TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff
     INTEGER :: N_Integ
     REAL (KIND=DP), DIMENSION(:), POINTER :: U_Integ,V_Integ,W_Integ,&
         S_Integ
     
     LOGICAL :: stat

!***********************************************************************!

     DIM = 2

     ForceVector = 0.0D0
     StiffMatrix = 0.0D0

     wang = 2.0*PI*Frequency

!------------------------------------------------------------------------------
!    Integration stuff
!------------------------------------------------------------------------------

     IntegStuff = GaussPoints( element )
     U_Integ => IntegStuff % u
     V_Integ => IntegStuff % v
     W_Integ => IntegStuff % w
     S_Integ => IntegStuff % s
     N_Integ =  IntegStuff % n

!------------------------------------------------------------------------------
!   Now we start integrating
!------------------------------------------------------------------------------
     DO t=1,N_Integ

       u = U_Integ(t)
       v = V_Integ(t)
       w = W_Integ(t)

!------------------------------------------------------------------------------
!     Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
       stat = ElementInfo( Element,Nodes,u,v,w,SqrtElementMetric, &
                 Basis,dBasisdx,ddBasisddx,.FALSE. )

       r = SUM( basis*nodes%x(1:n))

       s = SqrtElementMetric * S_Integ(t)
       
!------------------------------------------------------------------------------
!     Force at integration point
!------------------------------------------------------------------------------
       Force = 0.0D0
       Force = SUM( CurrentDensity(1:n)*Basis )

       Reluctivity = SUM( NodalReluctivity(1:n)*Basis(1:n) )
       Conductivity = SUM( NodalConductivity(1:n)*Basis(1:n) )
       Angle = (PI/180.0d0) * SUM( NodalAngle(1:n)*Basis(1:n) )

!------------------------------------------------------------------------------
!    Loop over basis functions (of both unknowns and weights)
!------------------------------------------------------------------------------
       DO p=1,N
         DO q=1,N
!------------------------------------------------------------------------------
!      The equation for the vector potential
!      Stiffness matrix:
!------------------------------

           a11 = dBasisdx(p,1)*dBasisdx(q,1)*r + &
               dBasisdx(p,2)*dBasisdx(q,2)*r + &
               Basis(p)*dBasisdx(q,1) + &
               Basis(q)*dBasisdx(p,1) + &
               Basis(p)*Basis(q)/r 
           a11 = Reluctivity * s * a11
           a22 = a11

           a21 = -Conductivity * wang * s * r * Basis(q) * Basis(p) 
           a12 = -a21

           StiffMatrix(2*p-1,2*q-1) = StiffMatrix(2*p-1,2*q-1) + a11
           StiffMatrix(2*p,2*q)     = StiffMatrix(2*p,2*q) + a22

           StiffMatrix(2*p,2*q-1) = StiffMatrix(2*p,2*q-1) + a21
           StiffMatrix(2*p-1,2*q) = StiffMatrix(2*p-1,2*q) + a12

         END DO
       END DO

!       IF(Force > 0.0) THEN
!         PRINT *,'Force',Force,'w',wang,'cond',conductivity
!         PRINT *,'Angle',Angle,'sin',SIN(Angle),'cos',COS(Angle)
!       END IF

!------------------------------------------------------------------------------
!    The righthand side...
!------------------------------------------------------------------------------
       DO p=1,N

         ForceVector(2*p-1) = ForceVector(2*p-1) + Force * COS(Angle) * Basis(p) * r * s
         ForceVector(2*p)   = ForceVector(2*p) + Force * SIN(Angle) * Basis(p) * r * s         

       END DO

     END DO

   END SUBROUTINE HarmMagAxisCompose



!------------------------------------------------------------------------------
   SUBROUTINE JouleIntegrate( &
       NodalField,NodalConductivity,TotalHeating,TotalVolume,Element,n,Nodes)

!------------------------------------------------------------------------------

     USE Types
     USE Integration
     USE ElementDescription
     
     IMPLICIT NONE
     
     REAL (KIND=DP) :: NodalConductivity(:), NodalField(:)
     REAL (KIND=DP) :: TotalHeating, TotalVolume, Conductivity, Field

     INTEGER :: n
     
     TYPE(Nodes_t) :: Nodes
     TYPE(Element_t) :: Element
     
!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------

     REAL (KIND=DP) :: Basis(n),dBasisdx(n,3),ddBasisddx(n,3,3)
     REAL (KIND=DP) :: SqrtElementMetric
     
     INTEGER :: DIM,t,i,j,p,q
     
     REAL (KIND=DP) :: r,s,u,v,w

     TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff
     INTEGER :: N_Integ
     REAL (KIND=DP), DIMENSION(:), POINTER :: U_Integ,V_Integ,W_Integ,S_Integ
     
     LOGICAL :: stat

!***********************************************************************!

     DIM = 2

!------------------------------------------------------------------------------
!    Integration stuff
!------------------------------------------------------------------------------

     IntegStuff = GaussPoints( element )
     U_Integ => IntegStuff % u
     V_Integ => IntegStuff % v
     W_Integ => IntegStuff % w
     S_Integ => IntegStuff % s
     N_Integ =  IntegStuff % n

!------------------------------------------------------------------------------
!   Now we start integrating
!------------------------------------------------------------------------------
     DO t=1,N_Integ

       u = U_Integ(t)
       v = V_Integ(t)
       w = W_Integ(t)

!------------------------------------------------------------------------------
!     Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
       stat = ElementInfo( Element,Nodes,u,v,w,SqrtElementMetric, &
                 Basis,dBasisdx,ddBasisddx,.FALSE. )

       r = SUM( basis*nodes%x(1:n))

       s = SqrtElementMetric * S_Integ(t)
       
!------------------------------------------------------------------------------
!     Force at integration point
!------------------------------------------------------------------------------

       Field = SUM( NodalField(1:n)*Basis(1:n) )
       Conductivity = SUM( NodalConductivity(1:n)*Basis(1:n) )

       DO p=1,N

         TotalVolume = TotalVolume + 2.0d0 * PI * r * s * Basis(p) 
         TotalHeating = TotalHeating + 2.0d0 * PI * r * s * Basis(p) * Field * Conductivity

       END DO

     END DO

   END SUBROUTINE JouleIntegrate



!/*******************************************************************************
! *
! * Subroutine for computing local matrices for static magnetic field
! * in cartesian 3D coordinates with Whitney elements
! *
! *                     Author:       Ville Savolainen
! *
! ******************************************************************************/

!------------------------------------------------------------------------------
    SUBROUTINE StatMagCompose( &
        MassMatrix,StiffMatrix,ForceVector,LoadVector,NodalReluctivity, &
        Ae,ElementOrig,n,nedges,Nodes)

!------------------------------------------------------------------------------
!******************************************************************************
!
!  Return element local matrices and RHS vector for static magnetic field
!
!  ARGUMENTS:
!
!  REAL (KIND=DP) :: MassMatrix(:,:)
!     OUTPUT: time derivative coefficient matrix
!
!  REAL (KIND=DP) :: StiffMatrix(:,:)
!     OUTPUT: rest of the equation coefficients
!
!  REAL (KIND=DP) :: ForceVector(:)
!     OUTPUT: RHS vector
!
!  REAL (KIND=DP) :: LoadVector(:)
!     INPUT:
!
!  REAL (KIND=DP) :: NodalReluctivity(:)
!     INPUT: Nodal values of relucitivity ( 1 / permeability )
!
!  REAL (KIND=DP) :: Ae(:)
!     INPUT: Vector potential (edge degrees of freedom)
!            from the previous iteration for computing
!            the "reluctivity" in a nonlinear material

!  TYPE(Element_t) :: Element
!       INPUT: Structure describing the element (dimension,nof nodes,
!               interpolation degree, etc...)
!
!  INTEGER :: n
!       INPUT: Number of element corner nodes
!
!  INTEGER :: nedges
!       INPUT: Number of element edges
!
!  TYPE(Nodes_t) :: Nodes
!       INPUT: Element node coordinates
!
!******************************************************************************
!------------------------------------------------------------------------------
      USE Types
      USE Integration
      USE ElementDescription

      IMPLICIT NONE
     
      REAL (KIND=DP),TARGET :: MassMatrix(:,:),StiffMatrix(:,:),&
          ForceVector(:)
      REAL (KIND=DP) :: NodalReluctivity(:), Reluctivity
      REAL (KIND=DP) :: LoadVector(:,:),Ae(:)

      INTEGER :: n,nedges

      TYPE(Nodes_t) :: Nodes
      TYPE(Element_t) :: ElementOrig, Element

!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------

      REAL (KIND=DP) :: Basis(n),dBasisdx(n,3),ddBasisddx(n,3,3)
      REAL (KIND=DP) :: SqrtElementMetric
      REAL (KIND=DP) :: WhitneyBasis(nedges,3), &
          dWhitneyBasisdx(nedges,3,3)

      REAL (KIND=DP) :: Force(3)

      INTEGER :: DIM,t,i,j,p,q,k

      REAL (KIND=DP) :: s,u,v,w

      TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff
      INTEGER :: N_Integ
      REAL (KIND=DP), DIMENSION(:), POINTER :: U_Integ,V_Integ,W_Integ,&
          S_Integ

      LOGICAL :: stat

!***********************************************************************!

     DIM=3

     ForceVector = 0.0D0
     MassMatrix  = 0.0D0
     StiffMatrix = 0.0D0

!------------------------------------------------------------------------------
!    Integration stuff
!------------------------------------------------------------------------------
     Element = ElementOrig
     IF (nedges == 6) THEN
       Element % TYPE => GetElementType( 504 )
     ELSE
       IF (nedges == 12) THEN
         Element % TYPE => GetElementType( 808 )
       ELSE
         CALL Fatal( 'StatMagCompose', &
             'Not appropriate number of edges for Whitney elements' )
       END IF
     END IF
! N.B. Have integration pts appropriate for linear elements
     IntegStuff = GaussPoints( Element )
     U_Integ => IntegStuff % u
     V_Integ => IntegStuff % v
     W_Integ => IntegStuff % w
     S_Integ => IntegStuff % s
     N_Integ =  IntegStuff % n

!------------------------------------------------------------------------------
!   Now we start integrating
!------------------------------------------------------------------------------
     DO t=1,N_Integ

       u = U_Integ(t)
       v = V_Integ(t)
       w = W_Integ(t)

!------------------------------------------------------------------------------
!     Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
! N.B. Use _linear_ tetra/brick element data for next two calls
       stat = ElementInfo( Element,Nodes,u,v,w,SqrtElementMetric, &
                 Basis,dBasisdx,ddBasisddx,.FALSE. )

       stat = WhitneyElementInfo( Element,Basis,dBasisdx,&
                 nedges,WhitneyBasis,dWhitneyBasisdx )

       s = SqrtElementMetric * S_Integ(t)
       
!------------------------------------------------------------------------------
!     Force at integration point
!------------------------------------------------------------------------------
       Force = 0.0_dp
       DO i=1,DIM
         Force(i) = SUM( LoadVector(i,1:n)*Basis(1:n) )
       END DO

       Reluctivity = SUM( NodalReluctivity(1:n)*Basis )
!------------------------------------------------------------------------------
!    Negative reluctivity indicates nonlinear material: reluctivity = H / B is
!    then computed from the previous value of B with using a given function 
!    Rel
!----------------------------------------------------------------------------

       IF (Reluctivity<0) THEN
         CALL Fatal( 'StatMagCompose', 'Iron permeability not implemented for 3D' )
! Either change the hack to include 3D fields, or omit altogether
       END IF

!------------------------------------------------------------------------------
!    Loop over edge basis functions (of both unknowns and weights)
!------------------------------------------------------------------------------
       DO p=1,nedges
         DO q=1,nedges
!------------------------------------------------------------------------------
!      The equation for the vector potential
!------------------------------------------------------------------------------
!------------------------------------------------------------------------------
!      Mass matrix:
!------------------------------------------------------------------------------
! This is not used for anything in static solver
!           DO i=1,dim
!             MassMatrix(n+p,n+q) = MassMatrix(n+p,n+q) + & 
!                 WhitneyBasis(p,i)*WhitneyBasis(q,i) * s
!           END DO

!------------------------------------------------------------------------------
!      Stiffness matrix:
!------------------------------
           DO i=1,DIM
             DO j=1,DIM
               StiffMatrix(n+p,n+q) = StiffMatrix(n+p,n+q) + Reluctivity* & 
                   (dWhitneyBasisdx(p,i,j)*dWhitneyBasisdx(q,i,j)) * s
             END DO
           END DO

         END DO
       END DO

!------------------------------------------------------------------------------
!    The righthand side...
!------------------------------------------------------------------------------
       DO p=1,nedges

         ForceVector(n+p) = ForceVector(n+p) + &
             s * DOT_PRODUCT(Force,WhitneyBasis(p,:))
       END DO

     END DO

     DO i=1,n
!       MassMatrix(i,i) = 1.0_dp
       StiffMatrix(i,i) = 1.0_dp
       ForceVector(i) = 0._dp
     END DO

!     PRINT*,SIZE(StiffMatrix)
!     DO i=1,10
!       PRINT*,'Matrix:',StiffMatrix(i,:)
!     END DO
!     PRINT*,'Force:',Forcevector
!     STOP

   END SUBROUTINE StatMagCompose

!------------------------------------------------------------------------------
   SUBROUTINE StatMagCompose2( MassMatrix,StiffMatrix,ForceVector,LoadVector, &
       NodalReluctivity,Ae,ElementOrig,n,nfaces,Nodes )
!------------------------------------------------------------------------------
!******************************************************************************
!
!  Return element local matrices and RHS vector for static magnetic field
!
!  ARGUMENTS:
!
!  REAL (KIND=DP) :: MassMatrix(:,:)
!     OUTPUT: time derivative coefficient matrix
!
!  REAL (KIND=DP) :: StiffMatrix(:,:)
!     OUTPUT: rest of the equation coefficients
!
!  REAL (KIND=DP) :: ForceVector(:)
!     OUTPUT: RHS vector
!
!  REAL (KIND=DP) :: LoadVector(:)
!     INPUT:
!
!  REAL (KIND=DP) :: NodalReluctivity(:)
!     INPUT: Nodal values of relucitivity ( 1 / permeability )
!
!  REAL (KIND=DP) :: Ae(:)
!     INPUT: Vector potential (edge degrees of freedom)
!            from the previous iteration for computing
!            the "reluctivity" in a nonlinear material

!  TYPE(Element_t) :: Element
!       INPUT: Structure describing the element (dimension,nof nodes,
!               interpolation degree, etc...)
!
!  INTEGER :: n
!       INPUT: Number of element corner nodes
!
!  INTEGER :: nedges
!       INPUT: Number of element edges
!
!  TYPE(Nodes_t) :: Nodes
!       INPUT: Element node coordinates
!
!******************************************************************************
!------------------------------------------------------------------------------
      USE Types
      USE Integration
      USE ElementDescription

      IMPLICIT NONE
     
      REAL (KIND=DP),TARGET :: MassMatrix(:,:),StiffMatrix(:,:),&
          ForceVector(:)
      REAL (KIND=DP) :: NodalReluctivity(:), Reluctivity
      REAL (KIND=DP) :: LoadVector(:,:),Ae(:)

      INTEGER :: n,nfaces

      TYPE(Nodes_t) :: Nodes
      TYPE(Element_t) :: ElementOrig,Element

!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------

      REAL (KIND=DP) :: Basis(n),dBasisdx(n,3),ddBasisddx(n,3,3)
      REAL (KIND=DP) :: SqrtElementMetric
      REAL (KIND=DP) :: WhitneyBasis(nfaces,3),dWhitneyBasisdx(nfaces,3,3)

      REAL (KIND=DP) :: Force(3)

      INTEGER :: DIM,t,i,j,p,q,k

      REAL (KIND=DP) :: s,u,v,w

      TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff
      INTEGER :: N_Integ
      REAL (KIND=DP), DIMENSION(:), POINTER :: U_Integ, V_Integ, W_Integ, &
          S_Integ

      LOGICAL :: stat

!***********************************************************************!

     DIM=3

     ForceVector = 0.0d0
     MassMatrix  = 0.0d0
     StiffMatrix = 0.0d0

!------------------------------------------------------------------------------
!    Integration stuff
!------------------------------------------------------------------------------
     Element = ElementOrig
     Element % TYPE => GetElementType( 504 )

! N.B. Have integration pts appropriate for linear elements
     IntegStuff = GaussPoints( Element,4 )
     U_Integ => IntegStuff % u
     V_Integ => IntegStuff % v
     W_Integ => IntegStuff % w
     S_Integ => IntegStuff % s
     N_Integ =  IntegStuff % n

!------------------------------------------------------------------------------
!   Now we start integrating
!------------------------------------------------------------------------------
     DO t=1,N_Integ

       u = U_Integ(t)
       v = V_Integ(t)
       w = W_Integ(t)

!------------------------------------------------------------------------------
!     Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
! N.B. Use _linear_ tetra/brick element data for next two calls
       stat = ElementInfo( Element, Nodes, u, v, w, SqrtElementMetric, &
                 Basis, dBasisdx, ddBasisddx, .FALSE. )

       stat = Whitney2ElementInfo( Element, Basis, dBasisdx, &
              nfaces, WhitneyBasis, dWhitneyBasisdx )

       s = SqrtElementMetric * S_Integ(t)
!------------------------------------------------------------------------------
!     Force at integration point
!------------------------------------------------------------------------------
       Force = 0.0_dp
       DO i=1,DIM
          Force(i) = SUM( LoadVector(i,1:n)*Basis(1:n) )
       END DO

       Reluctivity = SUM( NodalReluctivity(1:n)*Basis )
!------------------------------------------------------------------------------
!    Negative reluctivity indicates nonlinear material: reluctivity = H / B is
!    then computed from the previous value of B with using a given function 
!    Rel
!----------------------------------------------------------------------------

       IF ( Reluctivity < 0 ) THEN
         CALL Fatal( 'StatMagCompose', 'Iron permeability not implemented for 3D' )
! Either change the hack to include 3D fields, or omit altogether
       END IF

!------------------------------------------------------------------------------
!    Loop over edge basis functions (of both unknowns and weights)
!------------------------------------------------------------------------------
       DO p=1,nfaces
         DO q=1,nfaces
!------------------------------------------------------------------------------
!      The equation for the vector potential
!------------------------------------------------------------------------------
!------------------------------------------------------------------------------
!      Mass matrix:
!------------------------------------------------------------------------------
! This is not used for anything in static solver
!           DO i=1,dim
!             MassMatrix(n,n) = MassMatrix(n,n) + & 
!                 WhitneyBasis(p,i)*WhitneyBasis(q,i) * s
!           END DO
!
!------------------------------------------------------------------------------
!      Stiffness matrix:
!------------------------------
!#if 0
!           StiffMatrix(p+n,q+n) = StiffMatrix(p+n,q+n) + &
!               s * SUM( WhitneyBasis(p,:) * WhitneyBasis(q,:) )
!#else
           StiffMatrix(p,q) = StiffMatrix(p,q) + &
               s * (dWhitneyBasisdx(p,2,3)-dWhitneyBasisdx(p,3,2)) &
                      * WhitneyBasis(q,1)

           StiffMatrix(p,q) = StiffMatrix(p,q) + &
               s * (dWhitneyBasisdx(p,3,1)-dWhitneyBasisdx(p,1,3)) &
                      * WhitneyBasis(q,2)

           StiffMatrix(p,q) = StiffMatrix(p,q) + &
               s * (dWhitneyBasisdx(p,1,2)-dWhitneyBasisdx(p,2,1)) &
                      * WhitneyBasis(q,3)
!#endif

         END DO
       END DO

!------------------------------------------------------------------------------
!    The righthand side...
!------------------------------------------------------------------------------
       DO p=1,n
          ForceVector(p+n) = ForceVector(p+n) + &
              s * SUM( Force * WhitneyBasis(p,:) )
       END DO

     END DO

     DO i=1,n
        StiffMatrix(i,i) = 1.0d0
        ForceVector(i)   = 0.0d0
     END DO

   END SUBROUTINE StatMagCompose2


!------------------------------------------------------------------------------
   FUNCTION Rel(b) RESULT(r)
!------------------------------------------------------------------------------
!  Rel returns reluctivity = H / B for a nonlinear material
!
!  REAL (KIND=DP) :: b
!    INPUT: Absolute value of magnetic flux density
!
!  REAL (KIND=DP) :: r
!    INPUT: reluctivity = H / B for a nonlinear material
!------------------------------------------------------------------------------
     IMPLICIT NONE
     REAL (KIND=DP) :: b,r
!------------------------------------------------------------------------------

     r=0.3188d4*b**6 &
         -1.7109d4*b**5+ &
         3.8493d4*b**4 &
         -4.5478d4*b**3+ &
         2.92d4*b**2 &
         -0.9509d4*b+ &
         0.1631d4

!     r=1000

!------------------------------------------------------------------------------
   END FUNCTION rel
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
   SUBROUTINE CompVecPot( A,Ax,Ay,Az,n,nedges,w12 )
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: A(:),Ax(:),Ay(:),Az(:)

    INTEGER :: n,nedges,w12
    INTEGER, ALLOCATABLE :: Visited(:)

!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------

      REAL (KIND=DP) :: Basis(n),dBasisdx(n,3),ddBasisddx(n,3,3)
      REAL (KIND=DP) :: SqrtElementMetric
      REAL (KIND=DP) :: WhitneyBasis(NEdges,3), &
          dWhitneyBasisdx(NEdges,3,3)

      INTEGER :: DIM,t,i,j,p,q

      REAL (KIND=DP) :: s,u,v,w

      LOGICAL :: stat

      TYPE(Element_t) :: Element

      ALLOCATE (Visited(Model % NumberOfNodes))
      Visited = 0

      ElementNodes % x = 0
      ElementNodes % y = 0
      ElementNodes % z = 0

      DO t=1, Model % NumberOfBulkElements 
        Element = Model % Elements (t)
        Element % TYPE => GetElementType( 504 )

        ElementNodes % x(1:n) = Model % Nodes % x(Element % NodeIndexes(1:n))
        ElementNodes % y(1:n) = Model % Nodes % y(Element % NodeIndexes(1:n))
        ElementNodes % z(1:n) = Model % Nodes % z(Element % NodeIndexes(1:n))

        stat = ElementInfo( Element, ElementNodes, 0.25d0,0.25d0,0.25d0, &
              SqrtElementMetric, Basis, dBasisdx, ddBasisddx, .FALSE. )

        IF ( w12 == 1 ) THEN
           stat = WhitneyElementInfo( Element, Basis, dBasisdx,&
                 Nedges, WhitneyBasis, dWhitneyBasisdx )
        ELSE
           stat = Whitney2ElementInfo( Element, Basis, dBasisdx,&
                 Nedges, WhitneyBasis, dWhitneyBasisdx )
        END IF

        Ax(MagneticPerm(Element % NodeIndexes)) = &
            Ax(MagneticPerm(Element % NodeIndexes)) + &
            SUM( WhitneyBasis(:,1) * A( MagneticPerm( &
            Element % NodeIndexes(n+1:n+nedges) ) ) )
        
        Ay(MagneticPerm(Element % NodeIndexes)) = &
            Ay(MagneticPerm(Element % NodeIndexes)) + &
            SUM( WhitneyBasis(:,2) * A( MagneticPerm( &
            Element % NodeIndexes(n+1:n+nedges) ) ) )
        
        Az(MagneticPerm(Element % NodeIndexes)) = &
            Az(MagneticPerm(Element % NodeIndexes)) + &
            SUM( WhitneyBasis(:,3) * A( MagneticPerm( &
            Element % NodeIndexes(n+1:n+nedges) ) ) )
        
        Visited(MagneticPerm(Element % NodeIndexes)) = &
            Visited(MagneticPerm(Element % NodeIndexes)) + 1
     END DO

     WHERE( Visited > 1 )
       Ax = Ax / Visited
       Ay = Ay / Visited
       Az = Az / Visited
     END WHERE

     DEALLOCATE (Visited)

   END SUBROUTINE CompVecPot

!------------------------------------------------------------------------------
  END SUBROUTINE StatMagSolver
!------------------------------------------------------------------------------
