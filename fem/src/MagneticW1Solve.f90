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
! * Module containing a solver for the MHD Maxwell equations (induction
! * equation or eddy current equation) with Whitney elements
! * (cartesian 3D coordinates) in terms of H
! *
! ******************************************************************************
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
! *                       Date: 08 Jun 1997
! *
! *                Modified by: Ville Savolainen
! *
! *       Date of modification: 19 Feb 2001
! *
! *****************************************************************************/



!------------------------------------------------------------------------------
   SUBROUTINE MagneticW1Solver( Model,Solver,dt,TransientSimulation )
!DLLEXPORT MagneticW1Solver
!------------------------------------------------------------------------------
!******************************************************************************
!
!  Solve Maxwell equations for one timestep
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
!     INPUT: Timestep size for time dependent simulations
!
!******************************************************************************

    USE Types
    USE Lists

    USE CoordinateSystems

    USE ElementDescription
    USE BandwidthOptimize

    USE ElementUtils
    USE TimeIntegrate
    USE Integration

    USE Differentials
    USE FreeSurface

    USE IterSolve
    USE DirectSolve

    USE SolverUtils
!------------------------------------------------------------------------------

    IMPLICIT NONE

     TYPE(Model_t)  :: Model
     TYPE(Solver_t), TARGET :: Solver

     LOGICAL :: TransientSimulation
     REAL(KIND=dp) :: dt

!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------
     TYPE(Matrix_t),POINTER :: StiffMatrix
     INTEGER :: i,j,k,l,n,t,iter,LocalNodes,k1,k2,istat

     TYPE(ValueList_t),POINTER :: Material
     TYPE(Nodes_t) :: ElementNodes
     TYPE(Element_t),POINTER :: CurrentElement

     REAL(KIND=dp) :: RelativeChange,UNorm,PrevUNorm,Gravity(3), &
         Tdiff,Normal(3),s,r,NewtonTol,NonlinearTol

     INTEGER :: NSDOFs,NewtonIter,NonlinearIter,dim

     TYPE(Variable_t), POINTER :: MagneticSol, ElectricSol, FlowSol, &
         ExMagSol, MeshSol
     INTEGER, POINTER :: MagneticPerm(:),FlowPerm(:),ExMagPerm(:),MeshPerm(:)

     REAL(KIND=dp), POINTER :: MagneticField(:),ElectricCurrent(:), &
      FlowSolution(:),Work(:,:), M1(:),M2(:),M3(:),E1(:),E2(:),E3(:), &
      ForceVector(:), ExB(:), MeshVelocity(:)

     LOGICAL :: Stabilize,NewtonLinearization = .FALSE.,GotForceBC,GotIt

     INTEGER :: body_id,bf_id,eq_id
     INTEGER, POINTER :: NodeIndexes(:)
!
     LOGICAL :: AllocationsDone = .FALSE., FreeSurfaceFlag

     REAL(KIND=dp),ALLOCATABLE:: LocalMassMatrix(:,:),LocalStiffMatrix(:,:),&
       LoadVector(:,:),LocalForce(:), &
          Conductivity(:),Mx(:),My(:),Mz(:),U(:),V(:),W(:),Alpha(:),Beta(:), &
            Permeability(:),ExBx(:),ExBy(:),ExBz(:),B1(:),B2(:),B3(:)

     SAVE Mx,My,Mz,U,V,W,LocalMassMatrix,LocalStiffMatrix,LoadVector, &
       LocalForce,ElementNodes,Alpha,Beta, &
         Conductivity, AllocationsDone,LocalNodes, &
           Permeability, ExBx,ExBy,ExBz,B1,B2,B3
!------------------------------------------------------------------------------
     INTEGER :: NumberOfBoundaryNodes
     INTEGER, POINTER :: BoundaryReorder(:)

     REAL(KIND=dp) :: Bu,Bv,Bw,RM(3,3)
     REAL(KIND=dp), POINTER :: BoundaryNormals(:,:), &
           BoundaryTangent1(:,:), BoundaryTangent2(:,:)

     TYPE(Solver_t), POINTER :: SolverPointer

     SAVE NumberOfBoundaryNodes,BoundaryReorder,BoundaryNormals, &
              BoundaryTangent1, BoundaryTangent2

     REAL(KIND=dp) :: at,at0,totat,st,totst,t1,CPUTime,RealTime
!------------------------------------------------------------------------------
!    New variables for Whitney formulation
!------------------------------------------------------------------------------
     INTEGER :: nedges=6, nbulk
     REAL(KIND=dp), POINTER :: H(:),Hx(:),Hy(:),Hz(:),MFD(:)
     REAL (KIND=DP), ALLOCATABLE :: He(:)
     TYPE(Element_t), POINTER :: Parent
     INTEGER, ALLOCATABLE :: BulkNodeIndexes(:)
     SAVE He, MFD, BulkNodeIndexes
     TYPE(Solver_t), POINTER :: PSolver


!------------------------------------------------------------------------------
!    Get variables needed for solving the system
!------------------------------------------------------------------------------
!W1 VariableAdd done already: Does it matter for Perm that (Bx,By,Bz) -> He?

     IF ( .NOT. ASSOCIATED( Solver % Matrix ) ) RETURN

     dim = CoordinateSystemDimension()

     dim = CoordinateSystemDimension()

     MagneticSol => Solver % Variable
     MagneticPerm  => MagneticSol % Perm
     MagneticField => MagneticSol % Values

     LocalNodes = COUNT( MagneticPerm > 0 )
     IF ( LocalNodes <= 0 ) RETURN

     ExMagSol => VariableGet( Model % Variables, &
         'Magnetic Flux Density' )
     IF ( ASSOCIATED( ExMagSol ) ) THEN
       ExMagPerm => ExMagSol % Perm
       ExB => ExMagSol % Values
     END IF

     FlowSol => VariableGet( Model % Variables, 'Flow Solution' )
     IF ( ASSOCIATED( FlowSol ) ) THEN
       NSDOFs       =  FlowSol % DOFs
       FlowPerm     => FlowSol % Perm
       FlowSolution => FlowSol % Values
     END IF

     MeshSol => VariableGet( Solver % Mesh % Variables, 'Mesh Velocity' )
     NULLIFY( MeshVelocity )
     IF ( ASSOCIATED( MeshSol ) ) THEN
       MeshPerm => MeshSol % Perm
       MeshVelocity => MeshSol % Values
     END IF

     StiffMatrix => Solver % Matrix
     ForceVector => StiffMatrix % RHS
 
     UNorm = Solver % Variable % Norm
!------------------------------------------------------------------------------
!    Allocate some permanent storage, this is done first time only
!------------------------------------------------------------------------------

     IF ( .NOT.AllocationsDone ) THEN

       N = Model % MaxElementNodes

       ALLOCATE( U(N), V(N), W(N), MX(N), MY(N), MZ(N), &
                 ExBx(N),ExBy(N),ExBz(N), &
                 ElementNodes % x( N ), &
                 ElementNodes % y( N ), &
                 ElementNodes % z( N ), &
                 Conductivity( N ),  &
                 Permeability( N ),  &
                 LocalForce( N ), &
                 LocalMassMatrix(  N,N ),  &
                 LocalStiffMatrix( N,N ),  &
                 MFD(3*Model % NumberOfNodes), &
                 B1(LocalNodes), &
                 B2(LocalNodes), &
                 B3(LocalNodes), &
                 LoadVector( 3,N ), Alpha( N ), Beta( N ), &
                 He(n), &
                 BulkNodeIndexes(n), &
                 STAT=istat )

       IF ( istat /= 0 ) THEN
         CALL Fatal( 'MagneticW1Solve', 'Memory allocation error.' )
       END IF

!------------------------------------------------------------------------------
!    Add magnetic flux density to variables
!    To hold vector components of H
!------------------------------------------------------------------------------
       
      PSolver => Solver
      Hx => MFD(1:3*LocalNodes-2:3)
      CALL VariableAdd(Solver % Mesh % Variables, Solver % Mesh, PSolver, &
          'Magnetic Flux Density 1', 1, Hx, MagneticPerm)

      Hy => MFD(2:3*LocalNodes-1:3)
      CALL VariableAdd(Solver % Mesh % Variables, Solver % Mesh, PSolver, &
          'Magnetic Flux Density 2', 1, Hy, MagneticPerm)

      Hz => MFD(3:3*LocalNodes:3)
      CALL VariableAdd(Solver % Mesh % Variables, Solver % Mesh, PSolver, &
          'Magnetic Flux Density 3', 1, Hz, MagneticPerm)

      CALL VariableAdd(Solver % Mesh % Variables, Solver % Mesh, PSolver, &
          'Magnetic Flux Density', 3, MFD, MagneticPerm)

!------------------------------------------------------------------------------
!    Check for normal/tangetial coordinate system defined velocities
!------------------------------------------------------------------------------
       CALL CheckNormalTangentialBoundary( Model, &
           'Normal-Tangential Magnetic Field', NumberOfBoundaryNodes, &
          BoundaryReorder,BoundaryNormals,BoundaryTangent1, &
             BoundaryTangent2, dim )
!------------------------------------------------------------------------------

       AllocationsDone = .TRUE.
     END IF

!------------------------------------------------------------------------------

     Stabilize = ListGetLogical( Solver % Values,'Stabilize',GotIt )
     IF ( .NOT.GotIt ) Stabilize = .TRUE.

     NonlinearTol = ListGetConstReal( Solver % Values, &
        'Nonlinear System Convergence Tolerance' )

     NewtonTol = ListGetConstReal( Solver % Values, &
        'Nonlinear System Newton After Tolerance' )

     NewtonIter = ListGetInteger( Solver % Values, &
        'Nonlinear System Newton After Iterations' )

     NonlinearIter = ListGetInteger( Solver % Values, &
        'Nonlinear System Max Iterations' )

!------------------------------------------------------------------------------
!    Check if free surfaces present
!------------------------------------------------------------------------------
     FreeSurfaceFlag = .FALSE.
     DO i=1,Model % NumberOfBCs
       FreeSurfaceFlag = FreeSurfaceFlag.OR. ListGetLogical( Model % BCs(i) % Values, &
                         'Free Surface', GotIt )

       IF ( FreeSurfaceFlag ) EXIT
     END DO
!------------------------------------------------------------------------------

     totat = 0.0d0
     totst = 0.0d0

     DO iter=1,NonlinearIter

       at  = CPUTime()
       at0 = RealTime()

       CALL Info( 'MagneticW1Solve', ' ', Level=4 )
       CALL Info( 'MagneticW1Solve', ' ', Level=4 )
       CALL Info( 'MagneticW1Solve', &
            '-------------------------------------', Level=4 )
       WRITE( Message, * ) 'Magnetic induction iteration: ', iter
       CALL Info( 'MagneticW1Solve', Message, Level=4 )
       CALL Info( 'MagneticW1Solve', &
            '-------------------------------------', Level=4 )
       CALL Info( 'MagneticW1Solve', ' ', Level=4 )
!------------------------------------------------------------------------------
!      Compute average normals for boundaries having the normal & tangetial
!      field components specified on the boundaries
!------------------------------------------------------------------------------
       IF ( (iter == 1 .OR. FreeSurfaceFlag) .AND. NumberOfBoundaryNodes > 0 ) THEN
          CALL AverageBoundaryNormals( Model, &
             'Normal-Tangential Magnetic Field',NumberOfBoundaryNodes, &
            BoundaryReorder, BoundaryNormals, BoundaryTangent1, &
               BoundaryTangent2, dim )
       END IF
!------------------------------------------------------------------------------

       CALL InitializeToZero( StiffMatrix, ForceVector )

       t = 1
       DO WHILE( t <= Model % NumberOfBulkElements )

         IF ( RealTime() - at0 > 1.0 ) THEN
           WRITE(Message,'(a,i3,a)' ) '   Assembly: ', INT(100.0 - 100.0 * &
            (Model % NumberOfBulkElements-t) / &
               (1.0*Model % NumberOfBulkElements)), ' % done'
                       
           CALL Info( 'MagneticW1Solve', Message, Level=5 )
           at0 = RealTime()
         END IF
!------------------------------------------------------------------------------
!        Check if this element belongs to a body where the MHD equations
!        should be calculated
!------------------------------------------------------------------------------
!
!
         DO WHILE( t <= Model % NumberOfBulkElements )
           CurrentElement => Model % Elements(t)

           IF ( CheckElementEquation( Model, &
                              CurrentElement,'Whitney MHD' ) ) EXIT

           t = t + 1
         END DO

         IF ( t > Model % NumberOfBulkElements ) EXIT

!------------------------------------------------------------------------------
!        ok, we�ve got one for Maxwell equations
!------------------------------------------------------------------------------
!
!------------------------------------------------------------------------------
!        Set also the current element pointer in the model structure to
!        reflect the element being processed
!------------------------------------------------------------------------------
         Model % CurrentElement => Model % Elements(t)
!------------------------------------------------------------------------------
         body_id = CurrentElement % BodyId

         n = CurrentElement % TYPE % NumberOfNodes
         NodeIndexes => CurrentElement % NodeIndexes

         eq_id = ListGetInteger( Model % Bodies(body_id) % Values, 'Equation', &
                     minv=1, maxv=Model % NumberOfEquations )

         ElementNodes % x(1:n) = Model % Nodes % x(NodeIndexes)
         ElementNodes % y(1:n) = Model % Nodes % y(NodeIndexes)
         ElementNodes % z(1:n) = Model % Nodes % z(NodeIndexes)

         k = ListGetInteger( Model % Bodies(body_id) % Values, 'Material', &
                     minv=1, maxv=Model % NumberOfMaterials )
         Material => Model % Materials(k) % Values

         Conductivity(1:n) = ListGetReal(Material, &
                 'Electrical Conductivity',n,NodeIndexes)

         Permeability(1:n) = ListGetReal(Material, &
                 'Magnetic Permeability',n,NodeIndexes)

         Mx = ListGetReal( Material,  &
                'Applied Magnetic Field 1',n,NodeIndexes, Gotit )

         My = ListGetReal( Material,  &
                'Applied Magnetic Field 2',n,NodeIndexes, Gotit )

         Mz = ListGetReal( Material,  &
                'Applied Magnetic Field 3',n,NodeIndexes, Gotit )

         ExBx=0
         ExBy=0
         ExBz=0

         IF ( ASSOCIATED( ExMagSol ) ) THEN
           ExBx(1:n) = ExB(3*ExMagPerm(NodeIndexes)-2)
           ExBy(1:n) = ExB(3*ExMagPerm(NodeIndexes)-1)
           ExBz(1:n) = ExB(3*ExMagPerm(NodeIndexes))
         END IF

         Mx(1:n) = Mx(1:n) + ExBx(1:n)
         My(1:n) = My(1:n) + ExBy(1:n)
         Mz(1:n) = Mz(1:n) + ExBz(1:n)

         U = 0.0D0
         V = 0.0D0
         W = 0.0D0
         IF ( ASSOCIATED( FlowSol ) ) THEN
           DO i=1,n
             k = FlowPerm(NodeIndexes(i))
             IF ( k > 0 ) THEN
               SELECT CASE( NSDOFs )
                 CASE(3)
                   U(i) = FlowSolution( NSDOFs*k-2 )
                   V(i) = FlowSolution( NSDOFs*k-1 )
                   W(i) = 0.0D0
                   IF ( ASSOCIATED( MeshVelocity ) ) THEN
                     IF ( MeshPerm(NodeIndexes(i)) > 0 ) THEN
                       U(i) = U(i) - MeshVelocity( 2*MeshPerm(NodeIndexes(i))-1 )
                       V(i) = V(i) - MeshVelocity( 2*MeshPerm(NodeIndexes(i))-0 )
                     END IF
                   END IF

                 CASE(4)
                   U(i) = FlowSolution( NSDOFs*k-3 )
                   V(i) = FlowSolution( NSDOFs*k-2 )
                   W(i) = FlowSolution( NSDOFs*k-1 )
                   IF ( ASSOCIATED( MeshVelocity ) ) THEN
                     IF ( MeshPerm(NodeIndexes(i)) > 0 ) THEN
                       U(i) = U(i) - MeshVelocity( 3*MeshPerm(NodeIndexes(i))-2 )
                       V(i) = V(i) - MeshVelocity( 3*MeshPerm(NodeIndexes(i))-1 )
                       W(i) = W(i) - MeshVelocity( 3*MeshPerm(NodeIndexes(i))-0 )
                     END IF
                   END IF
               END SELECT
             END IF
           END DO
         END IF

!------------------------------------------------------------------------------
!        Set body forces
!------------------------------------------------------------------------------
         bf_id = ListGetInteger( Model % Bodies(body_id) % Values, &
           'Body Force',gotIt, 1, Model % NumberOfBodyForces )

         LoadVector = 0.0D0
         IF ( bf_id > 0  ) THEN
           LoadVector(1,1:n) = LoadVector(1,1:n) + ListGetReal( &
            Model % BodyForces(bf_id) % Values, &
                       'Magnetic Bodyforce 1',n,NodeIndexes,gotIt )

           LoadVector(2,1:n) = LoadVector(2,1:n) + ListGetReal( &
            Model % BodyForces(bf_id) % Values, &
                       'Magnetic Bodyforce 2',n,NodeIndexes,gotIt )

           LoadVector(3,1:n) = LoadVector(3,1:n) + ListGetReal( &
            Model % BodyForces(bf_id) % Values, &
                     'Magnetic Bodyforce 3',n,NodeIndexes,gotIt )
           

         END IF
!------------------------------------------------------------------------------
!        Get element local stiffness & mass matrices
!------------------------------------------------------------------------------
         IF ( CurrentCoordinateSystem() == Cartesian ) THEN
           CALL MaxwellW1Compose( &
               LocalMassMatrix,LocalStiffMatrix,LocalForce, &
               LoadVector,Conductivity*Permeability,Mx,My,Mz,U,V,W, &
               CurrentElement,n-nedges,nedges,ElementNodes )
         ELSE 
           CALL Fatal( 'MagneticW1Solve', &
               'Only Cartesian coordinates implemented for Whitney elements.' )
         END IF

!------------------------------------------------------------------------------
!        If time dependent simulation, add mass matrix to global 
!        matrix and global RHS vector
!------------------------------------------------------------------------------
         IF ( TransientSimulation ) THEN
!------------------------------------------------------------------------------
!          NOTE: This will replace LocalStiffMatrix and LocalForce with the
!                combined information...
!------------------------------------------------------------------------------
            CALL Add1stOrderTime(LocalMassMatrix, LocalStiffMatrix, LocalForce, &
                    dt, n, 1, MagneticPerm(NodeIndexes), Solver )
         END IF

!------------------------------------------------------------------------------
!        If boundary fields have been defined in normal/tangetial
!        coordinate systems, we�ll have to rotate the matrix & force vector
!        to that coordinate system
!------------------------------------------------------------------------------
         IF ( NumberOfBoundaryNodes > 0 ) THEN
           CALL RotateMatrix( LocalStiffMatrix,LocalForce,n,3,3, &
            BoundaryReorder(NodeIndexes),BoundaryNormals,BoundaryTangent1,   &
                              BoundaryTangent2 )
         END IF

!------------------------------------------------------------------------------
!        Update global matrices from local matrices
!------------------------------------------------------------------------------
         CALL UpdateGlobalEquations( StiffMatrix, LocalStiffMatrix, &
           ForceVector, LocalForce, n, 1, MagneticPerm(NodeIndexes) )
!------------------------------------------------------------------------------
         t = t + 1
      END DO

      CALL Info( 'MagneticW1Solve', Assembly done', Level=4 )

      at = CPUTime() - at
      st = CPUTime()

!------------------------------------------------------------------------------
!     Neumann & Newton boundary conditions
!------------------------------------------------------------------------------
      DO t = Model % NumberOfBulkElements+1, &
                Model % NumberOfBulkElements + Model % NumberOfBoundaryElements

        CurrentElement => Model % Elements(t)
!------------------------------------------------------------------------------
!        Set also the current element pointer in the model structure to 
!        reflect the element being processed
!------------------------------------------------------------------------------
        Model % CurrentElement => Model % Elements(t)
!------------------------------------------------------------------------------
        n = CurrentElement % TYPE % NumberOfNodes
        NodeIndexes => CurrentElement % NodeIndexes

        Parent => CurrentElement % BoundaryInfo % Left
        IF ( .NOT.ASSOCIATED(Parent) ) &
            Parent => CurrentElement % BoundaryInfo % Right
        IF ( .NOT.ASSOCIATED(Parent) ) STOP
        nbulk = Parent % Type % NumberOfNodes
        BulkNodeIndexes = Parent % NodeIndexes
!
!       The element type 101 (point element) can only be used
!       to set Dirichlet BCs, so skip �em at this stage.
!
        IF ( CurrentElement % TYPE % ElementCode /= 101 ) THEN

        ElementNodes % x(1:n) = Model % Nodes % x(NodeIndexes)
        ElementNodes % y(1:n) = Model % Nodes % y(NodeIndexes)
        ElementNodes % z(1:n) = Model % Nodes % z(NodeIndexes)

        DO i=1,Model % NumberOfBCs
          IF ( CurrentElement % BoundaryInfo % Constraint == &
                 Model % BCs(i) % Tag ) THEN
!------------------------------------------------------------------------------
!           (at the moment the following is done...)
!           BC: \tau \cdot n = \alpha n +  @\beta/@t + F
!------------------------------------------------------------------------------
            LoadVector = 0.0D0
            Alpha      = 0.0D0
            Beta       = 0.0D0

            GotForceBC = ListGetLogical(Model % BCs(i) % Values, &
                       'Magnetic Force BC',gotIt )
            IF ( GotForceBC ) THEN
!------------------------------------------------------------------------------
!             normal force BC: \tau\cdot n = \alpha n
!------------------------------------------------------------------------------
!------------------------------------------------------------------------------
!             tangential force BC:
!             \tau\cdot n = @\beta/@t (tangential derivative of something)
!------------------------------------------------------------------------------
!------------------------------------------------------------------------------
!            force in given direction BC: \tau\cdot n = F
!------------------------------------------------------------------------------

              LoadVector = 0._dp

              LoadVector(1,1:n) =  ListGetReal( Model % BCs(i) % Values, &
                        'Current Density 1',n,NodeIndexes,GotIt )

              LoadVector(2,1:n) =  ListGetReal( Model % BCs(i) % Values, &
                        'Current Density 2',n,NodeIndexes,GotIt )

              LoadVector(3,1:n) =  ListGetReal( Model % BCs(i) % Values, &
                        'Current Density 3',n,NodeIndexes,GotIt )

!              Conductivity(1:n) = ListGetReal(Model % BCs(i) % Values, &
!                  'Electrical Conductivity',n,NodeIndexes,GotIt)
!              IF (.NOT.(GotIt)) Conductivity = 1._dp
!
!              Permeability(1:n) = ListGetReal(Model % BCs(i) % Values, &
!                  'Magnetic Permeability',n,NodeIndexes,GotIt)
!              IF (.NOT.(GotIt)) Permeability = 1._dp


!------------------------------------------------------------------------------
              IF ( CurrentCoordinateSystem() == Cartesian ) THEN
                CALL MaxwellW1Boundary( LocalStiffMatrix,LocalForce, &
                    LoadVector,CurrentElement,Parent, &
                    nbulk-nedges,nedges,ElementNodes,Model )
              ELSE
                CALL Fatal( 'MagneticW1Solve', &
                   'Only Cartesian coordinates implemented for Whitney elements.')
              END IF

!------------------------------------------------------------------------------
!             If boundary field components have been defined in normal/tangetial
!             coordinate systems, we�ll have to rotate the matrix & force vector
!             to that coordinate system
!------------------------------------------------------------------------------

              IF ( NumberOfBoundaryNodes > 0 ) THEN
                CALL RotateMatrix( LocalStiffMatrix,LocalForce,n,3,3, &
                 BoundaryReorder(NodeIndexes),BoundaryNormals,BoundaryTangent1,&
                                   BoundaryTangent2 )
              END IF

!------------------------------------------------------------------------------
!             Update global matrices from local matrices
!------------------------------------------------------------------------------
              IF ( TransientSimulation ) THEN
                LocalMassMatrix = 0.0d0
!                CALL Add1stOrderTime(LocalMassMatrix, LocalStiffMatrix, &
!                    LocalForce, dt, n, 1, MagneticPerm(NodeIndexes), Solver )
                CALL Add1stOrderTime(LocalMassMatrix, LocalStiffMatrix, &
                    LocalForce, dt, nbulk, 1, MagneticPerm(BulkNodeIndexes), &
                    Solver )
              END IF
!              CALL UpdateGlobalEquations( StiffMatrix, LocalStiffMatrix, &
!                ForceVector, LocalForce, n, 1, MagneticPerm(NodeIndexes) )
              CALL UpdateGlobalEquations( StiffMatrix, LocalStiffMatrix, &
                ForceVector, LocalForce, nbulk, 1, MagneticPerm(BulkNodeIndexes) )

!------------------------------------------------------------------------------
            END IF
!------------------------------------------------------------------------------
          END IF
        END DO
        END IF
      END DO
!------------------------------------------------------------------------------

      CALL FinishAssembly( Solver,ForceVector )

!------------------------------------------------------------------------------
!     Dirichlet boundary conditions
!------------------------------------------------------------------------------
      CALL SetDirichletBoundaries( Model, StiffMatrix, ForceVector, &
               'Magnetic Field', 1, 1, MagneticPerm )

!------------------------------------------------------------------------------


      CALL Info( 'MagneticW1Solve', 'Set boundaries done', Level= 4)
!------------------------------------------------------------------------------
!     Solve the system and check for convergence
!------------------------------------------------------------------------------
      PrevUNorm = UNorm

      CALL SolveSystem( StiffMatrix, ParMatrix, ForceVector, &
                   MagneticField, UNorm, 3, Solver )

      st = CPUTIme()-st
      totat = totat + at
      totst = totst + st
      WRITE(*,'(a,i4,a,F8.2,F8.2)') 'iter: ',iter,' Assembly: (s)', at, totat
      WRITE(*,'(a,i4,a,F8.2,F8.2)') 'iter: ',iter,' Solve:    (s)', st, totst

!------------------------------------------------------------------------------
!     If boundary fields have been defined in normal/tangetial coordinate
!     systems, we�ll have to rotate the solution back to coordinate axis
!     directions
!------------------------------------------------------------------------------
      IF ( NumberOfBoundaryNodes > 0 ) THEN
        DO i=1,Model % NumberOfNodes
          k = BoundaryReorder(i)

          IF ( k > 0 ) THEN
            j = MagneticPerm(i)

            IF ( j > 0 ) THEN
              Bu = MagneticField( 3*(j-1)+1 )
              Bv = MagneticField( 3*(j-1)+2 )
              Bw = MagneticField( 3*(j-1)+3 )

              RM(1,:) = BoundaryNormals(k,:)
              RM(2,:) = BoundaryTangent1(k,:)
              RM(3,:) = BoundaryTangent2(k,:)
              CALL InvertMatrix( RM,3 )

              MagneticField(3*(j-1)+1) = RM(1,1)*Bu+RM(2,1)*Bv+RM(3,1)*Bw
              MagneticField(3*(j-1)+2) = RM(1,2)*Bu+RM(2,2)*Bv+RM(2,2)*Bw
              MagneticField(3*(j-1)+3) = RM(1,3)*Bu+RM(2,3)*Bv+RM(3,3)*Bw
            END IF
          END IF
        END DO 
      END IF
!------------------------------------------------------------------------------
      IF ( PrevUNorm + UNorm /= 0.0d0 ) THEN
         RelativeChange = 2 * ABS(PrevUNorm-UNorm)/(UNorm + PrevUNorm)
      ELSE
         RelativeChange = 0.0d0
      END IF

      WRITE( Message, * ) 'Result Norm     : ',UNorm
      CALL Info( 'MagneticW1Solve', Message, Level=4 )
      WRITE( Message, * ) 'Relative Change : ',RelativeChange
      CALL Info( 'MagneticW1Solve', Message, Level=4 )

      IF ( RelativeChange < NewtonTol .OR. &
             iter > NewtonIter ) NewtonLinearization = .TRUE.

     IF ( RelativeChange < NonLinearTol ) EXIT
    END DO

!
    M1 => MagneticField(1:3*LocalNodes-2:3)
    M2 => MagneticField(2:3*LocalNodes-1:3)
    M3 => MagneticField(3:3*LocalNodes-0:3)

!------------------------------------------------------------------------------
!   Compute the magnetic flux density from the vector potential: B = curl A
!------------------------------------------------------------------------------
    MFD=0.0d0
    H => MagneticField
    Hx => MFD(1:3*LocalNodes-2:3)
    Hy => MFD(2:3*LocalNodes-1:3)
    Hz => MFD(3:3*LocalNodes:3)

!#if 1
! Compute (Hx,Hy,Hz) for visualization
    CALL CompVecPot( H,Hx,Hy,Hz,nbulk-nedges,nedges,1 )
!#endif

    CALL InvalidateVariable( Model % Meshes, Solver % Mesh, &
               'Magnetic Flux Density')

  CONTAINS

!/*****************************************************************************
! *
! * Subroutines computing MHD Maxwell equations (induction equation) local
! * matrices (cartesian 3D coordinates) with Whitney elements in terms of H
! *
! *****************************************************************************
! *
! *                     Author:       Juha Ruokolainen
! *
! *                    Address: Center for Scientific Computing
! *                                Tietotie 6, P.O. BOX 405
! *                                  02101 Espoo, Finland
! *                                  Tel. +358 0 457 2723
! *                                Telefax: +358 0 457 2302
! *                              EMail: Juha.Ruokolainen@csc.fi
! *
! *                       Date: 01 Oct 1996
! *
! *                Modified by: Ville Savolainen
! *
! *       Date of modification: 14 Feb 2001
! *
! ****************************************************************************/



!------------------------------------------------------------------------------
  SUBROUTINE MaxwellW1Compose  (                                         &
       MassMatrix,StiffMatrix,ForceVector,LoadVector,NodalConductivity, &
                  Bx,By,Bz,Ux,Uy,Uz,ElementOrig,n,nedges,Nodes )
!DLLEXPORT MaxwellW1Compose
!------------------------------------------------------------------------------
!******************************************************************************
!
!  Return element local matrices and RHS vector for the MHD Maxwell equation.
!  If U=0, this is the eddy current equation.
!
!  ARGUMENTS:
!
!  REAL(KIND=dp) :: MassMatrix(:,:)
!     OUTPUT: time derivative coefficient matrix
!
!  REAL(KIND=dp) :: StiffMatrix(:,:)
!     OUTPUT: rest of the equation coefficients
!
!  REAL(KIND=dp) :: ForceVector(:)
!     OUTPUT: RHS vector
!
!  REAL(KIND=dp) :: LoadVector(:)
!     INPUT:
!
!  REAL(KIND=dp) :: NodalConductivity(:)
!     INPUT: Nodal values of electrical conductivity (times the magnetic
!            permeability)
!
!  REAL(KIND=dp) :: Bx(:),By(:),Bz(:)
!     INPUT: Nodal values of applied magnetic field components
!
!  REAL(KIND=dp) :: Ux(:),Uy(:),Uz(:)
!     INPUT: Nodal values of velocity components from previous iteration
!
!  TYPE(Element_t) :: Element
!       INPUT: Structure describing the element (dimension,nof nodes,
!               interpolation degree, etc...)
!
!  INTEGER :: n
!       INPUT: Number of element nodes
!
!  INTEGER :: nedges
!       INPUT: Number of element edges
!
!  TYPE(Nodes_t) :: Nodes
!       INPUT: Element node coordinates
!
!******************************************************************************
!------------------------------------------------------------------------------

    REAL(KIND=dp),TARGET :: MassMatrix(:,:),StiffMatrix(:,:),ForceVector(:)
    REAL(KIND=dp), DIMENSION(:) :: Ux,Uy,Uz,Bx,By,Bz
    REAL(KIND=dp) :: NodalConductivity(:),LoadVector(:,:)

    INTEGER :: n,nedges

    TYPE(Nodes_t) :: Nodes
    TYPE(Element_t) :: ElementOrig,Element

!------------------------------------------------------------------------------
!   Local variables
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: Basis(n),dBasisdx(n,3),ddBasisddx(n,3,3)
    REAL(KIND=dp) :: SqrtElementMetric
    REAL (KIND=dp) :: WhitneyBasis(nedges,3), dWhitneyBasisdx(nedges,3,3)

    REAL(KIND=dp) :: Velo(3),dVelodx(3,3),Force(3),Metric(3,3),Symb(3,3,3)
    REAL(KIND=dp) :: MField(3),dMFielddx(3,3)

    REAL(KIND=dp) :: Conductivity,dConductivitydx(3)

    INTEGER :: i,j,k,c,p,q,t,dim

    REAL(KIND=dp) :: s,u,v,w
  
    TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff
    INTEGER :: N_Integ
    REAL(KIND=dp), DIMENSION(:), POINTER :: U_Integ,V_Integ,W_Integ,S_Integ

    LOGICAL :: stat
!------------------------------------------------------------------------------

    dim = 3

    ForceVector = 0.0D0
    MassMatrix  = 0.0D0
    StiffMatrix = 0.0D0
!------------------------------------------------------------------------------
!   Integration stuff
!------------------------------------------------------------------------------
    Element = ElementOrig
    IF (nedges == 6) THEN
      Element % Type => GetElementType( 504 )
    ELSE
      IF (nedges == 12) THEN
        Element % Type => GetElementType( 808 )
      ELSE
        CALL Fatal( 'MagneticW1Solve', &
            'Not appropriate number of edges for Whitney elements.' )
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
!      Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
       stat = ElementInfo( Element,Nodes,u,v,w,SqrtElementMetric, &
            Basis,dBasisdx,ddBasisddx,.FALSE. )

       stat = WhitneyElementInfo( Element,Basis,dBasisdx,&
                 nedges,WhitneyBasis,dWhitneyBasisdx )

       s = SqrtElementMetric * S_Integ(t)
!------------------------------------------------------------------------------
!      Applied magnetic field
!------------------------------------------------------------------------------
       MField    = 0.0_dp
       MField(1) = SUM( Bx(1:n)*Basis )
       MField(2) = SUM( By(1:n)*Basis )
       MField(3) = SUM( Bz(1:n)*Basis )

       dMFielddx = 0.0D0
       DO i=1,3
          dMFielddx(1,i) = SUM( Bx(1:n)*dBasisdx(1:n,i) )
          dMFielddx(2,i) = SUM( By(1:n)*dBasisdx(1:n,i) )
          dMFielddx(3,i) = SUM( Bz(1:n)*dBasisdx(1:n,i) )
       END DO
!------------------------------------------------------------------------------
!      Velocity from previous iteration at the integration point
!------------------------------------------------------------------------------
       Velo = 0.0_dp
       Velo(1) = SUM( Ux(1:n)*Basis )
       Velo(2) = SUM( Uy(1:n)*Basis )
       Velo(3) = SUM( Uz(1:n)*Basis )

       dVelodx = 0.0_dp
       DO i=1,3
          dVelodx(1,i) = SUM( Ux(1:n)*dBasisdx(1:n,i) )
          dVelodx(2,i) = SUM( Uy(1:n)*dBasisdx(1:n,i) )
          dVelodx(3,i) = SUM( Uz(1:n)*dBasisdx(1:n,i) )
       END DO
!------------------------------------------------------------------------------
!      Force at integration point
!------------------------------------------------------------------------------
       DO i=1,dim
          Force(i) = SUM( LoadVector(i,1:n)*Basis(1:n) )
       END DO
!------------------------------------------------------------------------------
!      Effective conductivity
!------------------------------------------------------------------------------
       Conductivity = SUM( NodalConductivity(1:n)*Basis )
!------------------------------------------------------------------------------
!      Loop over edge basis functions (of both unknowns and weights)
!------------------------------------------------------------------------------
       DO p=1,nedges
       DO q=1,nedges
!------------------------------------------------------------------------------
!      The MHD Maxwell equations
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
!         Mass matrix:
!------------------------------------------------------------------------------
          DO i=1,dim
            MassMatrix(n+p,n+q) = MassMatrix(n+p,n+q) + & 
                WhitneyBasis(p,i)*WhitneyBasis(q,i) * s * Conductivity
          END DO

!------------------------------------------------------------------------------
!         Stiffness matrix:
!------------------------------
!         Diffusive terms
!------------------------------------------------------------------------------
          DO i=1,dim
             DO j = 1,dim
               StiffMatrix(n+p,n+q) = StiffMatrix(n+p,n+q) + & 
                   (dWhitneyBasisdx(p,i,j)*dWhitneyBasisdx(q,i,j)) * s
               StiffMatrix(n+p,n+q) = StiffMatrix(n+p,n+q) - & 
                   (dWhitneyBasisdx(q,j,i)*dWhitneyBasisdx(p,i,j)) * s
             END DO
          END DO
!------------------------------------------------------------------------------
!         The curl(u x B) terms from B=mu*H_i
!------------------------------------------------------------------------------
          DO i=1,dim
             DO j=1,dim
! u (nabla.B) (should be zero)
! B (nabla.U) (should be zero for incompressible flow)
! B . (nabla U)
               StiffMatrix(n+p,n+q) = StiffMatrix(n+p,n+q) + &
                   WhitneyBasis(q,j) * dVelodx(i,j) * WhitneyBasis(p,i) * &
                   Conductivity
! u . (nabla B)
               StiffMatrix(n+p,n+q) = StiffMatrix(n+p,n+q) - &
                   Velo(j) * dWhitneyBasisdx(q,i,j) * WhitneyBasis(p,i) * &
                   Conductivity
             END DO
          END DO
       END DO
       END DO

!------------------------------------------------------------------------------
!      The righthand side...
!------------------------------------------------------------------------------
       DO p=1,nedges

         ForceVector(n+p) = ForceVector(n+p) + &
             s * DOT_PRODUCT(Force,WhitneyBasis(p,:))

!------------------------------------------------------------------------------
!         The curl(u x B_ext) terms (MField should be H and not B?)
!------------------------------------------------------------------------------
          DO i=1,dim
             DO j=1,dim
! u (nabla.B) (should be zero)
! B (nabla.U) (should be zero for incompressible flow)
! B . (nabla U)
               ForceVector(n+p) = ForceVector(n+p) - s * &
                   MField(i) * dVelodx(j,i) * WhitneyBasis(p,j) * &
                   Conductivity
! u . (nabla B)
               ForceVector(n+p) = ForceVector(n+p) + s * &
                   Velo(i) * dMFielddx(j,i) * WhitneyBasis(p,j) * &
                   Conductivity
             END DO
          END DO
       END DO

       DO i=1,n
         MassMatrix(i,i) = 0._dp
         StiffMatrix(i,i) = 1.0_dp
         ForceVector(i) = 0._dp
       END DO

    END DO

  END SUBROUTINE MaxwellW1Compose
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
 SUBROUTINE MaxwellW1Boundary( BoundaryMatrix,BoundaryVector,LoadVector, &
                     ElementOrig,ParentOrig,n,nedges,Nodes,Model )
!DLLEXPORT MaxwellW1Boundary
!------------------------------------------------------------------------------
!******************************************************************************
!
!  Return element local matrices and RSH vector for the MHD Maxwell equation
!
!  ARGUMENTS:
!
!  REAL(KIND=dp) :: BoundaryMatrix(:,:)
!     OUTPUT: time derivative coefficient matrix
!
!  REAL(KIND=dp) :: BoundaryVector(:)
!     OUTPUT: RHS vector
!
!  REAL(KIND=dp) :: LoadVector(:,:)
!     INPUT: Nodal values force in coordinate directions
!            Or rather, pass the current density vector here?
!
!  TYPE(Element_t) :: ElementOrig
!       INPUT: Structure describing the original W1 element
!               (formally a quadratic element)
!
!  INTEGER :: n
!       INPUT: Number of parent element corner nodes
!
!  INTEGER :: nedges
!       INPUT: Number of parent element edges
!  
!  TYPE(Nodes_t) :: Nodes
!       INPUT: Element node coordinates
!
!******************************************************************************
!------------------------------------------------------------------------------

   IMPLICIT NONE

   REAL(KIND=dp) :: BoundaryMatrix(:,:),BoundaryVector(:),LoadVector(:,:)
!   REAL(KIND=dp) :: NodalConductivity(:)

   INTEGER :: n,nedges,bnodes,bedges

   TYPE(Element_t) :: ElementOrig, ParentOrig, Parent
   TYPE(Element_t), TARGET :: Element
   TYPE(Element_t), POINTER :: El_ptr
   TYPE(Nodes_t)    :: Nodes
   TYPE(Nodes_t) :: ParentNodes
   TYPE(Model_t) :: Model

!------------------------------------------------------------------------------
!  Local variables
!------------------------------------------------------------------------------
   REAL(KIND=dp) :: Basis(n),dBasisdx(n,3),ddBasisddx(n,3,3),BoundaryBasis(n)
   REAL(KIND=dp) :: SqrtElementMetric
   REAL (KIND=dp) :: WhitneyBasis(nedges,3), dWhitneyBasisdx(nedges,3,3)

   REAL(KIND=dp) :: u,v,w,s
   REAL(KIND=dp) :: Force(3),Normal(3),CurlWeq(3),x(n),y(n),z(n),Conductivity
   REAL(KIND=dp), POINTER :: U_Integ(:),V_Integ(:),W_Integ(:),S_Integ(:)

   INTEGER :: i,j,t,q,p,c,dim,N_Integ

   LOGICAL :: stat

   TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff

!------------------------------------------------------------------------------
   dim = 3
   BoundaryVector = 0.0D0
   BoundaryMatrix = 0.0D0
!
!------------------------------------------------------------------------------
!  Integration stuff
!------------------------------------------------------------------------------
! Use Element to get the integration points and boundary element normal
   Element = ElementOrig
! Use Parent to get Basis and WhitneyBasis
   Parent = ParentOrig

   ALLOCATE( ParentNodes % x(n), ParentNodes % y(n), ParentNodes % z(n) )
   ParentNodes % x(1:n) = Model % Nodes % x(Parent % NodeIndexes(1:n))
   ParentNodes % y(1:n) = Model % Nodes % y(Parent % NodeIndexes(1:n))
   ParentNodes % z(1:n) = Model % Nodes % z(Parent % NodeIndexes(1:n))

! Use linear elements for integration
   IF (nedges == 6) THEN
     Element % Type => GetElementType( 303 )
     bedges = 3
     bnodes = 3
     Parent % Type => GetElementType( 504 )
   ELSE
     IF (nedges == 12) THEN
       Element % Type => GetElementType( 404 )
       bedges = 4
       bnodes = 4
       Parent % Type => GetElementType( 808 )
     ELSE
       CALL Fatal( 'MagneticW1Solve', &
             'Not appropriate number of edges for Whitney elements.' )
     END IF
   END IF

   DO i = 1,bnodes
     DO j = 1,n
       IF ( Element % NodeIndexes(i) == Parent % NodeIndexes(j) ) THEN
         x(i) = Parent % Type % NodeU(j)
         y(i) = Parent % Type % NodeV(j)
         z(i) = Parent % Type % NodeW(j)
         EXIT
       END IF
     END DO
   END DO


   IntegStuff = GaussPoints( element )
   U_Integ => IntegStuff % u
   V_Integ => IntegStuff % v
   W_Integ => IntegStuff % w
   S_Integ => IntegStuff % s
   N_Integ =  IntegStuff % n

!------------------------------------------------------------------------------
!  Now we start integrating
!------------------------------------------------------------------------------
   DO t=1,N_Integ


     u = U_Integ(t)
     v = V_Integ(t)
     w = W_Integ(t)

     El_ptr => Element
     Normal = NormalVector( El_ptr,Nodes,u,v,.TRUE. )

     stat = ElementInfo( Element,Nodes,u,v,w,SqrtElementMetric, &
         BoundaryBasis(1:bnodes),dBasisdx,ddBasisddx,.FALSE. )

     u = SUM( BoundaryBasis(1:bnodes)*x(1:bnodes) )
     v = SUM( BoundaryBasis(1:bnodes)*y(1:bnodes) )
     w = SUM( BoundaryBasis(1:bnodes)*z(1:bnodes) )

!------------------------------------------------------------------------------
!    Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
! Get Basis for the parent element
     stat = ElementInfo( Parent,ParentNodes,u,v,w,SqrtElementMetric, &
         Basis,dBasisdx,ddBasisddx,.FALSE. )

! Whitney basis of the parent element at the boundary element's int. pts
     stat = WhitneyElementInfo( Parent,Basis,dBasisdx,&
         nedges,WhitneyBasis,dWhitneyBasisdx )

     s = SqrtElementMetric * S_Integ(t)

!------------------------------------------------------------------------------
!    Add to load: given force in coordinate directions
!------------------------------------------------------------------------------
     Force = 0._dp

!------------------------------------------------------------------------------
!    Effective conductivity
!------------------------------------------------------------------------------
!     Conductivity = SUM(NodalConductivity(1:bnodes)*BoundaryBasis(1:bnodes))

! If given current density, load = j x n...
     IF ( ANY(LoadVector /= 0._dp) ) THEN

! Load from boundary element corner nodes to the integration point
       DO i=1,dim
         Force(i) = SUM( LoadVector(i,1:bnodes)*BoundaryBasis(1:bnodes) )
       END DO

       Force = CrossProduct(Force,Normal)

! Only boundary edge WhitneyBasis contribute, but it's easier to go through all
! and update the global matrix based on the bulk edge index permutation
       DO q=1,nedges
         DO i=1,dim
           BoundaryVector(n+q) = &
               BoundaryVector(n+q) + s * WhitneyBasis(q,i) * Force(i)
         END DO
       END DO

     END IF

! ...anyway contribution to BoundaryMatrix
! Only boundary edge WhitneyBasis contribute, but...
     DO p=1,nedges
       DO q=1,nedges
         CurlWeq(1) = dWhitneyBasisdx(q,3,2) - dWhitneyBasisdx(q,2,3)
         CurlWeq(2) = dWhitneyBasisdx(q,1,3) - dWhitneyBasisdx(q,3,1)
         CurlWeq(3) = dWhitneyBasisdx(q,2,1) - dWhitneyBasisdx(q,1,2)

         BoundaryMatrix(n+p,n+q) = BoundaryMatrix(n+p,n+q) + &
             s * SUM(CrossProduct(CurlWeq,Normal)*WhitneyBasis(p,:))
       END DO
     END DO

     DO i=1,n
       BoundaryMatrix(i,i) = 1.0_dp
       BoundaryVector(i) = 0._dp
     END DO

   END DO
   DEALLOCATE( ParentNodes % x, ParentNodes % y, ParentNodes % z )

 END SUBROUTINE MaxwellW1Boundary
!------------------------------------------------------------------------------

 FUNCTION CrossProduct(Vector1,Vector2) RESULT(Vector)
   IMPLICIT NONE
   REAL(KIND=dp) :: Vector1(3),Vector2(3),Vector(3)

   Vector(1) = Vector1(2)*Vector2(3) - Vector1(3)*Vector2(2)
   Vector(2) = -Vector1(1)*Vector2(3) + Vector1(3)*Vector2(1)
   Vector(3) = Vector1(1)*Vector2(2)-Vector1(2)*Vector2(1)

 END FUNCTION CrossProduct

!------------------------------------------------------------------------------
   SUBROUTINE CompVecPot( A,Ax,Ay,Az,n,nedges,w12 )
!------------------------------------------------------------------------------
     IMPLICIT NONE

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

      INTEGER :: dim,t,i,j,p,q

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
        Element % Type => GetElementType( 504 )

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
  END SUBROUTINE MagneticW1Solver
!------------------------------------------------------------------------------
