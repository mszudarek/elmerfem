!/*****************************************************************************
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
! ****************************************************************************/
!
!/*****************************************************************************
! *
! * Module containing a solver for mesh update
! *
! *****************************************************************************
! *
! *                     Author:       Juha Ruokolainen
! *
! *                    Address: Center for Scientific Computing
! *                            Tietotie 6, P.O. Box 405
! *                              02101 Espoo, Finland
! *                              Tel. +358 0 457 2723
! *                            Telefax: +358 0 457 2302
! *                          EMail: Juha.Ruokolainen@csc.fi
! *
! *                       Date: 10 May 2000
! *
! *                Modified by:
! *
! *       Date of modification:
! *
! ****************************************************************************/

!------------------------------------------------------------------------------
 SUBROUTINE MeshSolver( Model,Solver,dt,TransientSimulation )
DLLEXPORT MeshSolver
!------------------------------------------------------------------------------
  USE CoordinateSystems

  USE SolverUtils
  USE Differentials
  USE DefUtils

  IMPLICIT NONE
!------------------------------------------------------------------------------
!******************************************************************************
!
!  Solve stress equations for mesh update
!
!  ARGUMENTS:
!
!  TYPE(Model_t) :: Model,  
!     INPUT: All model information (mesh,materials,BCs,etc...)
!
!  TYPE(Solver_t) :: Solver
!     INPUT: Linear equation solver options
!
!  REAL(KIND=dp) :: dt,
!     INPUT: Timestep size for time dependent simulations (NOTE: Not used
!            currently)
!
!******************************************************************************
  TYPE(Model_t)  :: Model
  TYPE(Solver_t), TARGET :: Solver

  LOGICAL ::  TransientSimulation
  REAL(KIND=dp) :: dt
!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------
  TYPE(Matrix_t),POINTER :: StiffMatrix

  INTEGER :: i,j,k,l,n,t,iter,NDeg,k1,k2,STDOFs,LocalNodes,istat

  TYPE(ValueList_t),POINTER :: Material
  TYPE(Nodes_t) :: ElementNodes
  TYPE(Element_t),POINTER :: CurrentElement

  REAL(KIND=dp) :: RelativeChange,UNorm,PrevUNorm,Gravity(3), &
       Tdiff,Normal(3),NewtonTol,NonlinearTol,s, maxu

  INTEGER :: NewtonIter,NonlinearIter

  TYPE(Variable_t), POINTER :: StressSol, MeshSol

  REAL(KIND=dp), POINTER :: MeshUpdate(:),Displacement(:),Work(:,:), &
       ForceVector(:), MeshVelocity(:), Velo(:), Density(:)

  INTEGER, POINTER :: TPerm(:),MeshPerm(:),StressPerm(:),NodeIndexes(:)

  INTEGER :: body_id
!
  LOGICAL :: AllocationsDone = .FALSE., Isotropic = .TRUE., &
            GotForceBC, Found, ComputeMeshVelocity

  TYPE(Solver_t), POINTER :: PSolver

  REAL(KIND=dp),ALLOCATABLE:: LocalMassMatrix(:,:),LocalStiffMatrix(:,:),&
       LoadVector(:,:),LocalForce(:), &
       LocalTemperature(:),ElasticModulus(:,:,:),PoissonRatio(:), &
       HeatExpansionCoeff(:,:,:), Alpha(:,:), Beta(:), PrevUpdate(:)

  SAVE LocalMassMatrix,LocalStiffMatrix,LoadVector, &
       LocalForce,ElementNodes, MeshVelocity, &
       LocalTemperature,AllocationsDone, Density, PrevUpdate, &
       ElasticModulus, PoissonRatio,HeatExpansionCoeff, TPerm, Alpha, Beta

!------------------------------------------------------------------------------
  INTEGER :: NumberOfBoundaryNodes
  INTEGER, POINTER :: BoundaryReorder(:)

  REAL(KIND=dp) :: Bu,Bv,Bw,RM(3,3)
  REAL(KIND=dp), POINTER :: BoundaryNormals(:,:), &
       BoundaryTangent1(:,:), BoundaryTangent2(:,:)

  CHARACTER(LEN=MAX_NAME_LEN) :: VersionID = "$Id: MeshSolve.f90,v 1.39 2004/12/16 08:43:06 jpr Exp $"

  SAVE NumberOfBoundaryNodes,BoundaryReorder,BoundaryNormals, &
       BoundaryTangent1, BoundaryTangent2

!------------------------------------------------------------------------------
  REAL(KIND=dp) :: at,at0,CPUTime,RealTime
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
!    Check if version number output is requested
!------------------------------------------------------------------------------
  IF ( .NOT. AllocationsDone ) THEN
    IF ( ListGetLogical( GetSimulation(), 'Output Version Numbers', Found ) ) THEN
      CALL Info( 'MeshSolve', 'MeshSolve version:', Level = 0 ) 
      CALL Info( 'MeshSolve', VersionID, Level = 0 ) 
      CALL Info( 'MeshSolve', ' ', Level = 0 ) 
    END IF
  END IF

!------------------------------------------------------------------------------
! Get variables needed for solution
!------------------------------------------------------------------------------
  IF ( .NOT. ASSOCIATED( Solver % Matrix ) ) RETURN

  IF ( TransientSimulation ) THEN
     MeshSol      => VariableGet( Solver % Mesh % Variables, 'Mesh Velocity' )
     MeshVelocity => MeshSol % Values
  END IF

  MeshSol => VariableGet( Solver % Mesh % Variables, 'Mesh Update' )
  MeshPerm      => MeshSol % Perm
  STDOFs        =  MeshSol % DOFs
  MeshUpdate    => MeshSol % Values

  LocalNodes = COUNT( MeshPerm > 0 )
  IF ( LocalNodes <= 0 ) RETURN

!------------------------------------------------------------------------------

  StressSol => VariableGet( Solver % Mesh % Variables, 'Displacement' )
  IF ( ASSOCIATED( StressSol ) )  THEN
     StressPerm   => StressSol % Perm
     STDOFs       =  StressSol % DOFs
     Displacement => StressSol % Values

     IF( .NOT.AllocationsDone .OR. Solver % Mesh % Changed ) THEN
        IF ( AllocationsDone ) DEALLOCATE( TPerm )

        ALLOCATE( TPerm( SIZE(MeshPerm) ), STAT=istat )
        IF ( istat /= 0 ) THEN
           CALL Fatal( 'MeshSolve', 'Memory allocation error.' )
        END IF
     END IF

     TPerm = MeshPerm
     DO i=1,SIZE( MeshPerm )
        IF ( StressPerm(i) /= 0 .AND. MeshPerm(i) /= 0 ) TPerm(i) = 0
     END DO

     IF ( AllocationsDone ) THEN
        CALL DisplaceMesh( Solver % Mesh, MeshUpdate, -1, TPerm,   STDOFs )
     END IF
     CALL DisplaceMesh( Solver % Mesh, Displacement,  -1, StressPerm, STDOFs )
  ELSE
     IF ( AllocationsDone ) THEN
        CALL DisplaceMesh( Solver % Mesh, MeshUpdate, -1, MeshPerm, STDOFs )
     END IF
  END IF


!------------------------------------------------------------------------------

  StiffMatrix => Solver % Matrix
  ForceVector => StiffMatrix % RHS
  UNorm = Solver % Variable % Norm

!------------------------------------------------------------------------------
! Allocate some permanent storage, this is done first time only
!------------------------------------------------------------------------------
  IF ( .NOT. AllocationsDone .OR. Solver % Mesh % Changed ) THEN
     N = Solver % Mesh % MaxElementNodes

     IF ( AllocationsDone ) THEN
        DEALLOCATE( ElementNodes % x, &
             ElementNodes % y, &
             ElementNodes % z, &
             HeatExpansionCoeff,   &
             LocalTemperature, &
             Density, &
             ElasticModulus, PoissonRatio, &
             LocalForce, &
             Alpha, Beta, &
             LocalMassMatrix,  &
             LocalStiffMatrix,  &
             LoadVector,STAT=istat )
     END IF

     ALLOCATE( ElementNodes % x( N ), &
          ElementNodes % y( N ), &
          ElementNodes % z( N ), &
          HeatExpansionCoeff( 3,3,N ),   &
          LocalTemperature( N ), &
          Density( N ), Alpha(3,N), Beta(N), &
          ElasticModulus( 6,6,N ), PoissonRatio( N ), &
          LocalForce( STDOFs*N ), &
          LocalMassMatrix(  STDOFs*N,STDOFs*N ),  &
          LocalStiffMatrix( STDOFs*N,STDOFs*N ),  &
          LoadVector( 4,N ),STAT=istat )

     maxu = ListGetConstReal( Solver % Values, 'Max Mesh Update', Found )
     IF ( Found ) ALLOCATE( PRevUpdate( SIZE(MeshUpdate) ) )

     IF ( istat /= 0 ) THEN
        CALL Fatal( 'MeshSolve', 'Memory allocation error.' )
     END IF

!------------------------------------------------------------------------------
! Check for normal/tangetial coordinate system defined velocities
!------------------------------------------------------------------------------
     CALL CheckNormalTangentialBoundary( Model, &
          'Normal-Tangential Mesh Update', NumberOfBoundaryNodes, &
          BoundaryReorder, BoundaryNormals, BoundaryTangent1, &
          BoundaryTangent2, CoordinateSystemDimension() )

!------------------------------------------------------------------------------
     Density = 0.0d0
     LocalTemperature   = 0.0d0
     HeatExpansionCoeff = 0.0d0
     AllocationsDone = .TRUE.
!------------------------------------------------------------------------------
  END IF
!------------------------------------------------------------------------------

  IF ( NumberOfBoundaryNodes >  0 ) THEN
     CALL AverageBoundaryNormals( Model, &
          'Normal-Tangential Mesh Update', NumberOfBoundaryNodes, &
          BoundaryReorder, BoundaryNormals, BoundaryTangent1, &
          BoundaryTangent2, CoordinateSystemDimension() )
  END IF

!------------------------------------------------------------------------------
! Do some additional initialization, and go for it
!------------------------------------------------------------------------------
  at  = CPUTime()
  at0 = RealTime()

  CALL Info( 'MeshSolve', ' ', Level=4 )
  CALL Info( 'MeshSolve', '-------------------------------------', Level=4 )
  CALL Info( 'MeshSolve', 'MESH UPDATE SOLVER:', Level=4 )
  CALL Info( 'MeshSolve', '-------------------------------------', Level=4 )
  CALL Info( 'MeshSolve', ' ', Level=4 )
  CALL Info( 'MeshSolve', 'Starting assembly...', Level=4 )
!------------------------------------------------------------------------------
  CALL InitializeToZero( StiffMatrix, ForceVector )
!------------------------------------------------------------------------------
  DO t=1,Solver % NumberOfActiveElements

     IF ( RealTime() - at0 > 1.0 ) THEN
        WRITE(Message,'(a,i3,a)' ) '   Assembly: ', INT(100.0 - 100.0 * &
             (Solver % NumberOfActiveElements-t) / &
             (1.0*Solver % NumberOfActiveElements)), ' % done'

        CALL Info( 'MeshSolve', Message, Level=5 )
                     
        at0 = RealTime()
     END IF
!------------------------------------------------------------------------------
!    Check if this element belongs to a body where mesh update
!    should be calculated
!------------------------------------------------------------------------------
     CurrentElement => Solver % Mesh % Elements( Solver % ActiveElements(t) )
     NodeIndexes => CurrentElement % NodeIndexes

!    IF ( .NOT.CheckElementEquation( Model, &
!         CurrentElement,'Mesh Update' ) ) CYCLE
!------------------------------------------------------------------------------
!    Ok, we have got one for mesh computations
!------------------------------------------------------------------------------
!------------------------------------------------------------------------------
!    Set the current element pointer in the model structure to
!    reflect the element being processed
!------------------------------------------------------------------------------
     Model % CurrentElement => CurrentElement
!------------------------------------------------------------------------------
     body_id = CurrentElement % BodyId
     n = CurrentElement % Type % NumberOfNodes

     ElementNodes % x(1:n) = Model % Nodes % x(NodeIndexes)
     ElementNodes % y(1:n) = Model % Nodes % y(NodeIndexes)
     ElementNodes % z(1:n) = Model % Nodes % z(NodeIndexes)

     k = ListGetInteger( Model % Bodies(body_id) % Values,'Material', &
           minv=1, maxv=Model % NumberOfMaterials )
        
     Material => Model % Materials(k) % Values

     ElasticModulus(1,1,1:n) = ListGetReal( Material, &
          'Mesh Elastic Modulus',n,NodeIndexes, Found )
     IF ( .NOT. Found ) THEN
        ElasticModulus(1,1,1:n) = ListGetReal( Material, &
             'Youngs Modulus',n,NodeIndexes, Found )
     END IF
     IF ( .NOT. Found ) ElasticModulus(1,1,1:n) = 1.0d0

     PoissonRatio(1:n) = ListGetReal( Material, &
          'Mesh Poisson Ratio', n, NodeIndexes, Found )
     IF ( .NOT. Found ) THEN
        PoissonRatio(1:n) = ListGetReal( Material, &
          'Poisson Ratio', n, NodeIndexes, Found )
     END IF
     IF ( .NOT. Found ) PoissonRatio(1:n) = 0.25d0
!------------------------------------------------------------------------------
!    Set body forces
!------------------------------------------------------------------------------
     LoadVector = 0.0d0
!------------------------------------------------------------------------------
!    Get element local stiffness & mass matrices
!------------------------------------------------------------------------------
     CALL LocalMatrix( LocalMassMatrix, &
          LocalStiffMatrix, LocalForce, LoadVector, ElasticModulus, &
          PoissonRatio, Density, .FALSE., Isotropic, HeatExpansionCoeff, &
          LocalTemperature, CurrentElement, n, ElementNodes )

     IF ( TransientSimulation ) THEN
!------------------------------------------------------------------------------
!        NOTE: This will replace LocalStiffMatrix and LocalForce with the
!              combined information...
!------------------------------------------------------------------------------
!        CALL Add2ndOrderTime( LocalMassMatrix, 0*LocalMassMatrix, &
!             LocalStiffMatrix, LocalForce, dt, n, STDOFs, &
!                 MeshPerm(NodeIndexes), Solver )
!------------------------------------------------------------------------------
!        Update global matrices from local matrices
!------------------------------------------------------------------------------
     END IF
!------------------------------------------------------------------------------
!    If boundary fields have been defined in normal/tangential coordinate
!    systems, we will have to rotate the matrix & force vector to that
!    coordinate system
!------------------------------------------------------------------------------
     IF ( NumberOfBoundaryNodes > 0 ) THEN
        CALL RotateMatrix( LocalStiffMatrix,LocalForce,n,STDOFs,STDOFs, &
             BoundaryReorder(NodeIndexes),BoundaryNormals,BoundaryTangent1, &
             BoundaryTangent2 )
     END IF

!------------------------------------------------------------------------------
!    Update global matrices from local matrices 
!------------------------------------------------------------------------------
     CALL UpdateGlobalEquations( StiffMatrix, LocalStiffMatrix, &
          ForceVector, LocalForce, n, STDOFs, MeshPerm(NodeIndexes) )
  END DO


!------------------------------------------------------------------------------
!     Neumann & Newton boundary conditions
!------------------------------------------------------------------------------
  DO t = Model % NumberOfBulkElements+1, &
            Model % NumberOfBulkElements + Model % NumberOfBoundaryElements

    CurrentElement => Model % Elements(t)
!------------------------------------------------------------------------------
!   Set also the current element pointer in the model structure to
!   reflect the element being processed
!------------------------------------------------------------------------------
    Model % CurrentElement => Model % Elements(t)
!------------------------------------------------------------------------------
    n = CurrentElement % Type % NumberOfNodes
    NodeIndexes => CurrentElement % NodeIndexes
    IF ( ANY( MeshPerm(NodeIndexes) <= 0 ) ) CYCLE
!
!   The element type 101 (point element) can only be used
!   to set Dirichlet BCs, so skip �em.

    IF ( CurrentElement % Type % ElementCode == 101 ) CYCLE

    ElementNodes % x(1:n) = Model % Nodes % x(NodeIndexes)
    ElementNodes % y(1:n) = Model % Nodes % y(NodeIndexes)
    ElementNodes % z(1:n) = Model % Nodes % z(NodeIndexes)

    DO i=1,Model % NumberOfBCs
      IF ( CurrentElement % BoundaryInfo % Constraint == &
               Model % BCs(i) % Tag ) THEN
!------------------------------------------------------------------------------
!        Force in given direction BC: \tau\cdot n = F
!------------------------------------------------------------------------------
         LoadVector = 0.0D0
         Alpha      = 0.0D0
         Beta       = 0.0D0

         GotForceBC = .FALSE.
         LoadVector(1,1:n) =  ListGetReal( Model % BCs(i) % Values, &
                   'Mesh Force 1',n,NodeIndexes,Found )
         GotForceBC = GotForceBC.OR.Found

         LoadVector(2,1:n) =  ListGetReal( Model % BCs(i) % Values, &
                   'Mesh Force 2',n,NodeIndexes,Found )
         GotForceBC = GotForceBC.OR.Found

         LoadVector(3,1:n) =  ListGetReal( Model % BCs(i) % Values, &
                   'Mesh Force 3',n,NodeIndexes,Found )
         GotForceBC = GotForceBC.OR.Found

         Beta(1:n) =  ListGetReal( Model % BCs(i) % Values, &
                   'Mesh Normal Force',n,NodeIndexes,Found )
         GotForceBC = GotForceBC.OR.Found

         IF ( .NOT.GotForceBC ) CYCLE
!------------------------------------------------------------------------------
         CALL MeshBoundary( LocalStiffMatrix,LocalForce, &
               LoadVector,Alpha,Beta,CurrentElement,n,ElementNodes )
!------------------------------------------------------------------------------
!        If boundary fields have been defined in normal/tangetial coordinate
!        systems, we�ll have to rotate the matrix & force vector to that
!        coordinate system
!------------------------------------------------------------------------------
         IF ( NumberOfBoundaryNodes > 0 ) THEN
            CALL RotateMatrix( LocalStiffMatrix,LocalForce,n,STDOFs,STDOFs, &
             BoundaryReorder(NodeIndexes),BoundaryNormals,BoundaryTangent1, &
                               BoundaryTangent2 )
         END IF
!------------------------------------------------------------------------------
         CALL UpdateGlobalEquations( StiffMatrix, LocalStiffMatrix, &
           ForceVector, LocalForce, n, STDOFs, MeshPerm(NodeIndexes) )
!------------------------------------------------------------------------------
       END IF
     END DO
  END DO
!------------------------------------------------------------------------------

  CALL Info( 'MeshSolve', 'Assembly done', Level=4 )
!------------------------------------------------------------------------------
!
! CALL FinishAssembly( Solver, ForceVector )
!
!------------------------------------------------------------------------------
! Dirichlet boundary conditions
!------------------------------------------------------------------------------
  CALL SetDirichletBoundaries( Model, StiffMatrix, ForceVector, &
       'Mesh Update 1', 1, STDOFs, MeshPerm )

  CALL SetDirichletBoundaries( Model, StiffMatrix, ForceVector, &
       'Mesh Update 2', 2, STDOFs,MeshPerm )

  IF ( STDOFs >= 3 ) THEN
     CALL SetDirichletBoundaries( Model, StiffMatrix, ForceVector, &
          'Mesh Update 3', 3, STDOFs, MeshPerm )
  END IF
!------------------------------------------------------------------------------

  CALL Info( 'MeshSolve', 'Set boundaries done', Level=4 )

!------------------------------------------------------------------------------
! Solve the system and check for convergence
!------------------------------------------------------------------------------
  PrevUNorm = UNorm

  maxu = ListGetConstReal( Solver % Values, 'Max Mesh Update', Found )
  IF ( Found ) THEN
     PrevUpdate = MeshUpdate
  END IF

  CALL SolveSystem( StiffMatrix, ParMatrix, ForceVector, &
           MeshUpdate, UNorm, STDOFs, Solver )

  IF ( UNorm + PrevUNorm  /= 0.0d0 ) THEN
     RelativeChange = 2*ABS( PrevUNorm - UNorm ) / (PrevUNorm + UNorm)
  ELSE
     RelativeChange = 0.0d0
  END IF

  WRITE( Message, * ) 'Result Norm   : ',UNorm
  CALL Info( 'MeshSolve', Message, Level=4 )
  WRITE( Message, * ) 'Relative Change : ',RelativeChange
  CALL Info( 'MeshSolve', Message, Level=4 )

!------------------------------------------------------------------------------
! If boundary fields have been defined in normal/tangential coordinate
! systems, we will have to rotate the solution back to coordinate axis
! directions
!------------------------------------------------------------------------------
  IF ( NumberOfBoundaryNodes > 0 ) THEN
     DO i=1,Solver % Mesh % NumberOfNodes
        k = BoundaryReorder(i)

        IF ( k > 0 ) THEN
           j = MeshPerm(i)

           IF ( j > 0 ) THEN
              IF ( STDOFs < 3 ) THEN
                 Bu = MeshUpdate( STDOFs*(j-1)+1 )
                 Bv = MeshUpdate( STDOFs*(j-1)+2 )

                 MeshUpdate( STDOFs*(j-1)+1) = BoundaryNormals(k,1) * Bu - &
                      BoundaryNormals(k,2) * Bv

                 MeshUpdate( STDOFs*(j-1)+2) = BoundaryNormals(k,2) * Bu + &
                      BoundaryNormals(k,1) * Bv
              ELSE
                 Bu = MeshUpdate( STDOFs*(j-1) + 1 )
                 Bv = MeshUpdate( STDOFs*(j-1) + 2 )
                 Bw = MeshUpdate( STDOFs*(j-1) + 3 )
 
                 RM(1,:) = BoundaryNormals(k,:)
                 RM(2,:) = BoundaryTangent1(k,:)
                 RM(3,:) = BoundaryTangent2(k,:)
                 CALL InvertMatrix( RM,3 )

                 MeshUpdate(STDOFs*(j-1)+1) = RM(1,1)*Bu+RM(1,2)*Bv+RM(1,3)*Bw
                 MeshUpdate(STDOFs*(j-1)+2) = RM(2,1)*Bu+RM(2,2)*Bv+RM(2,3)*Bw
                 MeshUpdate(STDOFs*(j-1)+3) = RM(3,1)*Bu+RM(3,2)*Bv+RM(3,3)*Bw
              END IF
           END IF
        END IF
     END DO
  END IF

  IF ( TransientSimulation ) THEN
      ComputeMeshVelocity = ListGetLogical( Solver % Values, 'Compute Mesh Velocity', Found )
      IF ( .NOT. Found ) ComputeMeshVelocity = .TRUE.

      IF ( ComputeMeshVelocity ) THEN
         k = MIN( SIZE(Solver % Variable % PrevValues,2), Solver % DoneTime )
         SELECT CASE(k)
         CASE(1)
            MeshVelocity = ( MeshUpdate - Solver % Variable % PrevValues(:,1) ) / dt
         CASE(2)
            MeshVelocity = ( &
                MeshUpdate - (4.0d0/3.0d0)*Solver % Variable % PrevValues(:,1) &
                           + (1.0d0/3.0d0)*Solver % Variable % PrevValues(:,2) ) / dt
         CASE DEFAULT
            MeshVelocity = ( &
                MeshUpdate - (18.0d0/11.0d0)*Solver % Variable % PrevValues(:,1) &
                           + ( 9.0d0/11.0d0)*Solver % Variable % PrevValues(:,2) &
                           - ( 2.0d0/11.0d0)*Solver % Variable % PrevValues(:,3) ) / dt
          END SELECT
      ELSE
         MeshVelocity = 0.0d0
      END IF
  END IF
#if 0
  maxu = ListGetConstReal( Solver % Values, 'Max Mesh Update', Found )
  IF ( gotit ) THEN
#if 0
     DO i=1,SIZE(MeshUpdate)
       IF ( ABS( PrevUpdate(i)-MeshUpdate(i) ) > maxu ) THEN
          IF ( MeshUpdate(i) > PrevUpdate(i) ) THEN
             MeshUpdate(i) = PrevUpdate(i) + maxu
          ELSE
             MeshUpdate(i) = PrevUpdate(i) - maxu
          END IF
       END IF
     END DO
#else
     DO i=1,SIZE(MeshUpdate)
       IF ( ABS( MeshUpdate(i) ) > maxu ) THEN
          IF ( MeshUpdate(i) > 0 ) THEN
             MeshUpdate(i) =  maxu
          ELSE
             MeshUpdate(i) = -maxu
          END IF
       END IF
     END DO
#endif
  END IF
#endif

  IF ( ASSOCIATED( StressSol ) ) THEN
     CALL DisplaceMesh( Solver % Mesh, MeshUpdate,   1, TPerm,      STDOFs )
     CALL DisplaceMesh( Solver % Mesh, Displacement, 1, StressPerm, STDOFs, .FALSE.)
  ELSE
     CALL DisplaceMesh( Solver % Mesh, MeshUpdate,   1, MeshPerm,   STDOFs )
  END IF

  CONTAINS

!------------------------------------------------------------------------------
   SUBROUTINE LocalMatrix( MassMatrix,StiffMatrix,ForceVector,LoadVector,  &
     NodalYoung, NodalPoisson, NodalDensity, PlaneStress, Isotropic, &
          NodalHeatExpansion, NodalTemperature, Element,n,Nodes )
!------------------------------------------------------------------------------

     REAL(KIND=dp) :: StiffMatrix(:,:),MassMatrix(:,:),NodalHeatExpansion(:,:,:)
     REAL(KIND=dp) :: NodalTemperature(:),LoadVector(:,:),NodalYoung(:,:,:)
     REAL(KIND=dp), DIMENSION(:) :: ForceVector,NodalPoisson, &
                     NodalDensity

     LOGICAL :: PlaneStress, Isotropic

     TYPE(Element_t) :: Element
     TYPE(Nodes_t) :: Nodes

     INTEGER :: n
!------------------------------------------------------------------------------
!
     REAL(KIND=dp) :: Basis(n),ddBasisddx(1,1,1)
     REAL(KIND=dp) :: dBasisdx(n,3),SqrtElementMetric

     REAL(KIND=dp) :: Force(3),NodalLame1(n),NodalLame2(n),Lame1,Lame2, &
                      Poisson, Young

     REAL(KIND=dp), DIMENSION(3,3) :: A,M,HeatExpansion
     REAL(KIND=dp) :: Load(3),Temperature,Density, C(6,6)

     INTEGER :: i,j,k,p,q,t,dim, ind(3)

     REAL(KIND=dp) :: s,u,v,w
  
     REAL(KIND=dp) :: dDispldx(3,3)
     TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff

     INTEGER :: N_Integ

     REAL(KIND=dp), DIMENSION(:), POINTER :: U_Integ,V_Integ,W_Integ,S_Integ

     LOGICAL :: stat
!------------------------------------------------------------------------------

     dim = CoordinateSystemDimension()

     IF ( PlaneStress ) THEN
        NodalLame1(1:n) = NodalYoung(1,1,1:n) * NodalPoisson(1:n) / &
               ((1.0d0 - NodalPoisson(1:n)**2))
     ELSE
        NodalLame1(1:n) = NodalYoung(1,1,1:n) * NodalPoisson(1:n) /  &
           ((1.0d0 + NodalPoisson(1:n)) * (1.0d0 - 2.0d0*NodalPoisson(1:n)))
     END IF

     NodalLame2(1:n) = NodalYoung(1,1,1:n) / (2* (1.0d0 + NodalPoisson(1:n)))

     ForceVector = 0.0D0
     StiffMatrix = 0.0D0
     MassMatrix  = 0.0D0

!    
!    Integration stuff
!    
     IntegStuff = GaussPoints( element )
     U_Integ => IntegStuff % u
     V_Integ => IntegStuff % v
     W_Integ => IntegStuff % w
     S_Integ => IntegStuff % s
     N_Integ =  IntegStuff % n
!
!   Now we start integrating
!
    DO t=1,N_Integ

      u = U_Integ(t)
      v = V_Integ(t)
      w = W_Integ(t)

!------------------------------------------------------------------------------
!     Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
      stat = ElementInfo( Element,Nodes,u,v,w,SqrtElementMetric, &
                 Basis,dBasisdx,ddBasisddx,.FALSE. )

      s = SqrtElementMetric * S_Integ(t)
!------------------------------------------------------------------------------
!  
!     Force at integration point
!   
      Force = 0.0d0
      DO i=1,dim
         Force(i) = SUM( LoadVector(i,1:n)*Basis(1:n) )
      END DO
!
!     Lame parameters at the integration point
!
      Lame1 = SUM( NodalLame1(1:n)*Basis(1:n) )
      Lame2 = SUM( NodalLame2(1:n)*Basis(1:n) )

!
!     Coefficient Matrix:
!
      Density = SUM( Basis(1:n) * NodalDensity(1:n) )
!
!    Loop over basis functions (of both unknowns and weights)
!
     DO p=1,N
     DO q=1,N
        A = 0.0
        M = 0.0

        DO i=1,dim
           M(i,i) = Density * Basis(p) * Basis(q)
        END DO
!
!      Stiffness matrix:
!------------------------------
        DO i=1,dim
           DO j = 1,dim
              A(i,j) = A(i,j) + Lame1 * dBasisdx(q,j) * dBasisdx(p,i)
              A(i,i) = A(i,i) + Lame2 * dBasisdx(q,j) * dBasisdx(p,j)
              A(i,j) = A(i,j) + Lame2 * dBasisdx(q,i) * dBasisdx(p,j)
           END DO
        END DO
!
! Add nodal matrix to element matrix
!
        DO i=1,dim
           DO j=1,dim
              StiffMatrix( dim*(p-1)+i,dim*(q-1)+j ) =  &
                  StiffMatrix( dim*(p-1)+i,dim*(q-1)+j ) + s*A(i,j)

              MassMatrix( dim*(p-1)+i,dim*(q-1)+j ) =  &
                  MassMatrix( dim*(p-1)+i,dim*(q-1)+j ) + s*M(i,j)
           END DO
        END DO
     END DO
     END DO
!
! The righthand side...
!
     DO p=1,N
       Load = 0.0d0
  
       DO i=1,dim
          Load(i) = Load(i) + Force(i) * Basis(p)
       END DO

       DO i=1,dim
         ForceVector(dim*(p-1)+i) = ForceVector(dim*(p-1)+i) + s*Load(i)
       END DO
     END DO

   END DO 
!------------------------------------------------------------------------------
 END SUBROUTINE LocalMatrix
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
 SUBROUTINE MeshBoundary( BoundaryMatrix,BoundaryVector,LoadVector, &
                      NodalAlpha,NodalBeta,Element,n,Nodes )
!------------------------------------------------------------------------------
   REAL(KIND=dp) :: BoundaryMatrix(:,:),BoundaryVector(:)
   REAL(KIND=dp) :: NodalAlpha(:,:),NodalBeta(:),LoadVector(:,:)
   TYPE(Element_t),POINTER  :: Element
   TYPE(Nodes_t)    :: Nodes

   INTEGER :: n
!------------------------------------------------------------------------------
   REAL(KIND=dp) :: Basis(n),ddBasisddx(1,1,1)
   REAL(KIND=dp) :: dBasisdx(n,3),SqrtElementMetric

   REAL(KIND=dp) :: u,v,w,s
   REAL(KIND=dp) :: Force(3),Alpha(3),Beta,Normal(3)
   REAL(KIND=dp), POINTER :: U_Integ(:),V_Integ(:),W_Integ(:),S_Integ(:)

   INTEGER :: i,t,q,p,dim,N_Integ

   LOGICAL :: stat

   TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff
!------------------------------------------------------------------------------

   dim = Element % Type % Dimension + 1

   BoundaryVector = 0.0D0
   BoundaryMatrix = 0.0D0
!
!  Integration stuff
!
   IntegStuff = GaussPoints( element )
   U_Integ => IntegStuff % u
   V_Integ => IntegStuff % v
   W_Integ => IntegStuff % w
   S_Integ => IntegStuff % s
   N_Integ =  IntegStuff % n
!
!  Now we start integrating
!
   DO t=1,N_Integ

     u = U_Integ(t)
     v = V_Integ(t)
     w = W_Integ(t)

!------------------------------------------------------------------------------
!     Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
      stat = ElementInfo( Element, Nodes, u, v, w, SqrtElementMetric, &
                 Basis, dBasisdx, ddBasisddx, .FALSE. )

      s = SqrtElementMetric * S_Integ(t)
!------------------------------------------------------------------------------
     Force = 0.0D0
     DO i=1,dim
       Force(i) = SUM( LoadVector(i,1:n)*Basis )
       Alpha(i) = SUM( NodalAlpha(i,1:n)*Basis )
     END DO

     Normal = NormalVector( Element,Nodes,u,v,.TRUE. )
     Force = Force + SUM( NodalBeta(1:n)*Basis ) * Normal

     DO p=1,N
       DO q=1,N
         DO i=1,dim
           BoundaryMatrix((p-1)*dim+i,(q-1)*dim+i) =  &
             BoundaryMatrix((p-1)*dim+i,(q-1)*dim+i) + &
               s * Alpha(i) * Basis(q) * Basis(p)
         END DO
       END DO
     END DO

     DO q=1,N
       DO i=1,dim
         BoundaryVector((q-1)*dim+i) = BoundaryVector((q-1)*dim+i) + &
                   s * Basis(q) * Force(i)
       END DO
     END DO

   END DO

!------------------------------------------------------------------------------
 END SUBROUTINE MeshBoundary
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
END SUBROUTINE MeshSolver
!------------------------------------------------------------------------------
