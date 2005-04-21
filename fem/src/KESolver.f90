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
! * Module containing a solver for the KE-turbulence model.
! *
! ******************************************************************************
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
! *                       Date: 08 Jun 1997
! *
! *                Modified by:
! *
! *       Date of modification:
! *
! *****************************************************************************/

!------------------------------------------------------------------------------
   SUBROUTINE KESolver( Model,Solver,dt,TransientSimulation )
!DEC$ATTRIBUTES DLLEXPORT :: KESolver
!------------------------------------------------------------------------------
     USE DefUtils

     IMPLICIT NONE
!------------------------------------------------------------------------------
!******************************************************************************
!
!  Solve the K-Epsilon model equations !
!
!  ARGUMENTS:
!
!  TYPE(Model_t) :: Model,  
!     INPUT: All model information (mesh, materials, BCs, etc...)
!
!  TYPE(Solver_t) :: Solver
!     INPUT: Linear equation solver options
!
!  REAL(KIND=dp) :: dt,
!     INPUT: Timestep size for time dependent simulations
!
! CAVEAT: only Implicit Euler timestepping method currently usable.
!
!******************************************************************************
     TYPE(Model_t)  :: Model
     TYPE(Solver_t) :: Solver

     REAL(KIND=dp) :: dt
     LOGICAL :: TransientSimulation
!------------------------------------------------------------------------------
!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------
     TYPE(Matrix_t),POINTER  :: StiffMatrix
     INTEGER :: i,j,k,l,n,t,iter,k1,k2,body_id,eq_id,istat,LocalNodes,bf_id,DOFs

     TYPE(Nodes_t)   :: ElementNodes
     TYPE(Element_t),POINTER :: CurrentElement

     REAL(KIND=dp) :: RelativeChange,Norm,PrevNorm,S,C

     INTEGER, POINTER :: NodeIndexes(:)
     LOGICAL :: Stabilize = .TRUE.,NewtonLinearization = .FALSE.,gotIt
!
     LOGICAL :: AllocationsDone = .FALSE.

     CHARACTER(LEN=MAX_NAME_LEN) :: KEModel

     TYPE(Variable_t), POINTER :: FlowSol, KE

     INTEGER, POINTER :: FlowPerm(:),KinPerm(:)

     INTEGER :: NSDOFs,NewtonIter,NonlinearIter
     REAL(KIND=dp) :: NonlinearTol,NewtonTol, Clip

     REAL(KIND=dp), POINTER :: KEpsilon(:),KineticDissipation(:), &
                   FlowSolution(:), ElectricCurrent(:), ForceVector(:)

     REAL(KIND=dp), ALLOCATABLE :: MASS(:,:), &
       STIFF(:,:),LayerThickness(:), &
         LOAD(:,:),FORCE(:),U(:),V(:),W(:), &
           Density(:),Viscosity(:),EffectiveVisc(:,:),Work(:),  &
              TurbulentViscosity(:),LocalDissipation(:), &
                 LocalKinEnergy(:),KESigmaK(:),KESigmaE(:),KECmu(:),KEC1(:),&
                   KEC2(:),C0(:,:), SurfaceRoughness(:), TimeForce(:)

     TYPE(ValueList_t), POINTER :: BC, Equation, Material

     SAVE U,V,W,MASS,STIFF,LOAD,FORCE, &
       ElementNodes,LayerThickness,Density,&
         AllocationsDone,Viscosity,LocalNodes,Work,TurbulentViscosity, &
           LocalDissipation,LocalKinEnergy,KESigmaK,KESigmaE,KECmu,C0, &
             SurfaceRoughness, TimeForce, KEC1, KEC2, EffectiveVisc

     REAL(KIND=dp), POINTER :: SecInv(:)
     SAVE SecInv

     REAL(KIND=dp) :: at,at0,CPUTime,RealTime, KMax, EMax, KVal, EVal
!------------------------------------------------------------------------------
     CHARACTER(LEN=MAX_NAME_LEN) :: VersionID = "$Id: KESolver.f90,v 1.12 2004/08/19 08:23:35 jpr Exp $"

!------------------------------------------------------------------------------
!    Check if version number output is requested
!------------------------------------------------------------------------------
     IF ( .NOT. AllocationsDone ) THEN
        IF ( ListGetLogical( GetSimulation(), 'Output Version Numbers', GotIt ) ) THEN
           CALL Info( 'KESolver', 'K-Epsilon Solver version:', Level = 0 ) 
           CALL Info( 'KESolver', VersionID, Level = 0 ) 
           CALL Info( 'KESolver', ' ', Level = 0 ) 
        END IF
     END IF

!------------------------------------------------------------------------------
!    Get variables needed for solution
!------------------------------------------------------------------------------
     IF ( .NOT. ASSOCIATED( Solver % Matrix ) ) RETURN

     KE => Solver % Variable
     IF ( ASSOCIATED( KE ) ) THEN
       DOFs     =  KE % DOFs
       KinPerm  => KE % Perm
       KEpsilon => KE % Values
     END IF

     LocalNodes = COUNT( KinPerm > 0 )
     IF ( LocalNodes <= 0 ) RETURN

     FlowSol => VariableGet( Model % Variables, 'Flow Solution' )
     IF ( ASSOCIATED( FlowSol ) ) THEN
       FlowPerm     => FlowSol % Perm
       NSDOFs       =  FlowSol % DOFs
       FlowSolution => FlowSol % Values
     END IF

     StiffMatrix => Solver % Matrix
     ForceVector => StiffMatrix % RHS
     Norm = KE % Norm
!------------------------------------------------------------------------------
!    Allocate some permanent storage, this is done first time only
!------------------------------------------------------------------------------
     IF ( .NOT. AllocationsDone ) THEN
       N = Model % MaxElementNodes

       ALLOCATE( U( N ), V( N ), W( N ),  &
                 Density( N ),Work( N ),  &
                 Viscosity(N), &
                 EffectiveVisc(2,N), &
                 TurbulentViscosity(N), C0(DOFs,N), &
                 LayerThickness(N), &
                 SurfaceRoughness(N), &
                 KEC1(N), KEC2(N),      &
                 KESigmaK(N), KESigmaE(N),KECmu(N), &
                 LocalKinEnergy( N ),     &
                 LocalDissipation( N ),&
                 MASS( 2*DOFs*N,2*DOFs*N ), &
                 STIFF( 2*DOFs*N,2*DOFs*N ),LOAD( DOFs,N ), &
                 FORCE( 2*DOFs*N ), TimeForce( 2*DOFs*N ), STAT=istat )

       IF ( istat /= 0 ) THEN
         CALL Fatal( 'KESolver', 'Memory allocation error.' )
       END IF

       nullify(SecInv)
       AllocationsDone = .TRUE.
     END IF

!------------------------------------------------------------------------------
!    Do some additional initialization, and go for it
!------------------------------------------------------------------------------
!    Stabilize = ListGetLogical( Solver % Values,'Stabilize',GotIt )
     Stabilize = .FALSE.

     NonlinearTol = ListGetConstReal( Solver % Values, &
        'Nonlinear System Convergence Tolerance',gotIt )

     NewtonTol = ListGetConstReal( Solver % Values, &
        'Nonlinear System Newton After Tolerance',gotIt )

     NewtonIter = ListGetInteger( Solver % Values, &
        'Nonlinear System Newton After Iterations',gotIt )

     NonlinearIter = ListGetInteger( Solver % Values, &
         'Nonlinear System Max Iterations',GotIt )

     IF ( .NOT.GotIt ) NonlinearIter = 1

!------------------------------------------------------------------------------

     DO iter=1,NonlinearIter

       at  = CPUTime()
       at0 = RealTime()

       CALL Info( 'KESolver', ' ', Level=4 )
       CALL Info( 'KESolver', ' ', Level=4 )
       CALL Info( 'KESolver', &
          '-------------------------------------', Level=4 )
       WRITE( Message, * ) 'KEpsilon iteration: ', iter
       CALL Info( 'KESolver', Message, Level=4 )
       CALL Info( 'KESolver', &
          '-------------------------------------', Level=4 )
       CALL Info( 'KESolver', ' ', Level=4 )
       CALL Info( 'KESolver', 'Starting Assembly...', Level=4 )

       CALL DefaultInitialize()

!------------------------------------------------------------------------------
!      Bulk elements
!------------------------------------------------------------------------------
       body_id = -1
       DO t=1,Solver % NumberOfActiveElements

         IF ( RealTime() - at0 > 1.0 ) THEN
           WRITE(Message,'(a,i3,a)' ) '   Assembly: ', INT(100.0 - 100.0 * &
            (Solver % NumberOfActiveElements-t) / &
               (1.0*Solver % NumberOfActiveElements)), ' % done'

           CALL Info( 'KESolver', Message, Level=5 )
           at0 =RealTime()
         END IF
!------------------------------------------------------------------------------
!        Check if this element belongs to a body where kinetic energy
!        should be calculated
!------------------------------------------------------------------------------
         CurrentElement => GetActiveElement(t)
         IF ( CurrentElement % BodyId /= body_id ) THEN
            Material => GetMaterial()
            Equation => GetEquation()

            Clip = GetConstReal( Material, 'KE Clip', GotIt )
            IF ( .NOT.GotIt ) Clip = 1.0d-6

            KEModel = GetString( Material, 'KE Model', GotIt )
            IF ( .NOT. GotIt ) KEModel = 'standard'
         END IF
!------------------------------------------------------------------------------
         CALL GetElementNodes( ElementNodes )
         n = GetElementNOFNodes()
         NodeIndexes => CurrentElement % NodeIndexes
!------------------------------------------------------------------------------

         KESigmaK(1:n) = GetReal( Material, 'KE SigmaK', GotIt )
         IF ( .NOT. GotIt ) THEN
            KESigmaK = 1.0d0
            CALL ListAddConstReal( Material, 'KE SigmaK', KESigmaK(1) )
          END IF

         KESigmaE(1:n) = GetReal( Material, 'KE SigmaE', GotIt )
         IF ( .NOT. GotIt ) THEN
            SELECT CASE( KEModel )
            CASE( 'standard' )
              KESigmaE = 1.3d0
            CASE( 'rng' )
              KESigmaE = 1.0d0
            CASE DEFAULT
               CALL Fatal( 'KESolver', 'Unkown K-Epsilon model' )
            END SELECT
            CALL ListAddConstReal( Material, 'KE SigmaE', KESigmaE(1) )
         END IF

         KECmu(1:n) = ListGetConstReal( Material, 'KE Cmu', GotIt )
         IF ( .NOT. GotIt ) THEN
            SELECT CASE( KEModel )
            CASE( 'standard' )
              KECmu = 0.09d0
            CASE( 'rng' )
              KECmu = 0.0845d0
            CASE DEFAULT
               CALL Fatal( 'KESolver', 'Unkown K-Epsilon model' )
            END SELECT
            CALL ListAddConstReal( Material, 'KE Cmu', KECmu(1) )
         END IF

         KEC1(1:n) = GetReal( Material, 'KE C1', GotIt )
         IF ( .NOT. GotIt ) THEN
            SELECT CASE( KEModel )
            CASE( 'standard' )
              KEC1 = 1.44d0
            CASE( 'rng' )
              KEC1 = 1.42d0
            CASE DEFAULT
               CALL Fatal( 'KESolver', 'Unkown K-Epsilon model' )
            END SELECT
            CALL ListAddConstReal( Material, 'KE C1', KEC1(1) )
         END IF

         KEC2(1:n) = GetReal( Material, 'KE C2', GotIt )
         IF ( .NOT. GotIt ) THEN
            SELECT CASE( KEModel )
            CASE( 'standard' )
              KEC2 = 1.92d0
            CASE( 'rng' )
              KEC2 = 1.68d0
            CASE DEFAULT
               CALL Fatal( 'KESolver', 'Unkown K-Epsilon model' )
            END SELECT
            CALL ListAddConstReal( Material, 'KE C2', KEC2(1) )
         END IF
!------------------------------------------------------------------------------
         Density(1:n)   = GetReal( Material,'Density' )
         Viscosity(1:n) = GetReal( Material,'Viscosity' )
!------------------------------------------------------------------------------
         LocalKinEnergy(1:n)   = KEpsilon(DOFs*(KinPerm(NodeIndexes)-1)+1)
         LocalDissipation(1:n) = KEpsilon(DOFs*(KinPerm(NodeIndexes)-1)+2)
!------------------------------------------------------------------------------
         TurbulentViscosity(1:n) = Density(1:n) * KECmu(1:n) *  &
            LocalKinEnergy(1:n)**2 / LocalDissipation(1:n)

         EffectiveVisc(1,1:n) = Viscosity(1:n) + &
                         TurbulentViscosity(1:n) / KESigmaK(1:n)
         EffectiveVisc(2,1:n) = Viscosity(1:n) + &
                         TurbulentViscosity(1:n) / KESigmaE(1:n)
!------------------------------------------------------------------------------
         C0(1,1:n) = Density(1:n)
         C0(2,1:n) = Density(1:n) * LocalDissipation(1:n) / LocalKinEnergy(1:n)
!------------------------------------------------------------------------------
         DO i=1,n
            k = FlowPerm(NodeIndexes(i))
            IF ( k > 0 ) THEN
              SELECT CASE( NSDOFs )
                CASE(3)
                  U(i) = FlowSolution( NSDOFs*k-2 )
                  V(i) = FlowSolution( NSDOFs*k-1 )
                  W(i) = 0.0D0

                CASE(4)
                  U(i) = FlowSolution( NSDOFs*k-3 )
                  V(i) = FlowSolution( NSDOFs*k-2 )
                  W(i) = FlowSolution( NSDOFs*k-1 )
              END SELECT
            ELSE
              U(i) = 0.0d0
              V(i) = 0.0d0
              W(i) = 0.0d0
            END IF
         END DO

!------------------------------------------------------------------------------
!        Add body forces
!------------------------------------------------------------------------------
         LOAD(1,1:n) = TurbulentViscosity(1:n)
         LOAD(2,1:n) = KEC1(1:n) * LocalDissipation(1:n) * &
           TurbulentViscosity(1:n) / LocalKinEnergy(1:n)
!------------------------------------------------------------------------------
!        Get element local matrices, and RHS vectors
!------------------------------------------------------------------------------
         CALL LocalMatrix( MASS,STIFF,FORCE,LOAD, Density,C0,Density, &
           EffectiveVisc, U,V,W, Stabilize,CurrentElement,n,ElementNodes )
!------------------------------------------------------------------------------
         TimeForce = FORCE
         IF ( TransientSimulation ) THEN
            FORCE = 0.0d0
            CALL Default1stOrderTime( MASS, STIFF, FORCE )
         END IF
!------------------------------------------------------------------------------
!        Update global matrices from local matrices
!------------------------------------------------------------------------------
         CALL Condensate( DOFs*N, STIFF, FORCE, TimeForce )
         IF ( TransientSimulation ) CALL DefaultUpdateForce( TimeForce )
         CALL DefaultUpdateEquations( STIFF, FORCE )
!------------------------------------------------------------------------------
      END DO     !  Bulk elements
      CALL Info( 'KESolver', 'Assembly done', Level=4 )

!------------------------------------------------------------------------------
      DO t = 1, Solver % Mesh % NumberOfBoundaryElements
        CurrentElement => GetBoundaryElement(t)
        IF ( .NOT. ActiveBoundaryElement() ) CYCLE
!------------------------------------------------------------------------------
        n = GetElementNOFNodes()
        NodeIndexes => CurrentElement % NodeIndexes

        BC => GetBC()

        IF ( ASSOCIATED( BC ) ) THEN
          IF ( GetLogical( BC, 'Wall Law',gotIt ) ) THEN

!             /*
!              * NOTE: that the following is not really valid, the pointer to
!              * the Material structure is from the remains of the last of the
!              * bulk elements.
!              */
              Density(1:n)   = GetReal( Material,'Density' )
              Viscosity(1:n) = GetReal( Material,'Viscosity' )

              SurfaceRoughness(1:n) = GetReal( BC, 'Surface Roughness' )
              LayerThickness(1:n)   = GetReal( BC, 'Boundary Layer Thickness' )

              DO j=1,n
                k = FlowPerm(NodeIndexes(j))
                IF ( k > 0 ) THEN
                  SELECT CASE( NSDOFs )
                    CASE(3)
                      U(j) = FlowSolution( NSDOFs*k-2 )
                      V(j) = FlowSolution( NSDOFs*k-1 )
                      W(j) = 0.0D0

                    CASE(4)
                      U(j) = FlowSolution( NSDOFs*k-3 )
                      V(j) = FlowSolution( NSDOFs*k-2 )
                      W(j) = FlowSolution( NSDOFs*k-1 )
                  END SELECT
                ELSE
                  U(j) = 0.0d0
                  V(j) = 0.0d0
                  W(j) = 0.0d0
                END IF
              END DO

              DO j=1,n
                CALL KEWall( Work(1), Work(2), SQRT(U(j)**2+V(j)**2+W(j)**2), &
                 LayerThickness(j), SurfaceRoughness(j), Viscosity(j), &
                   Density(j) )

                k = DOFs*(KinPerm(NodeIndexes(j))-1)
                ForceVector(k+1) = Work(1)
                CALL ZeroRow( StiffMatrix,k+1 )
                CALL SetMatrixElement( StiffMatrix,k+1,k+1,1.0d0 )

                ForceVector(k+2) = Work(2)
                CALL ZeroRow( StiffMatrix,k+2 )
                CALL SetMatrixElement( StiffMatrix,k+2,k+2,1.0d0 )
              END DO
            END IF
        END IF
      END DO
!------------------------------------------------------------------------------

      CALL DefaultFinishAssembly()
!------------------------------------------------------------------------------
!     Dirichlet boundary conditions
!------------------------------------------------------------------------------
      CALL DefaultDirichletBCs()
!------------------------------------------------------------------------------
      CALL Info( 'KESolver', 'Set boundaries done', Level=4 )
!------------------------------------------------------------------------------
!     Solve the system and check for convergence
!------------------------------------------------------------------------------
      PrevNorm = Norm

      Norm = DefaultSolve()
!------------------------------------------------------------------------------
!      Kinetic Energy Solution should be positive
!------------------------------------------------------------------------------
      n = SIZE( Solver % Variable % Values)
      Kmax = MAXVAL( Solver % Variable % Values(1:n:2) )
      Emax = MAXVAL( Solver % Variable % Values(2:n:2) )
      DO i=1,SIZE(Solver % Variable % Perm)
         k = Solver % Variable % Perm(i)
         IF ( k <= 0 ) CYCLE

         Kval = Solver % Variable % Values(2*k-1)
         Eval = Solver % Variable % Values(2*k-0)

         IF ( KVal < Clip*Kmax ) Kval = Clip*KMax

         IF ( Eval < Clip*EMax ) THEN
            KVal = Clip*EMax
            Eval = MAX(Density(1)*KECmu(1)*KVal**2/Viscosity(1),Clip*EMax)
         END IF

         Solver % Variable % Values(2*k-1) = KVal
         Solver % Variable % Values(2*k-0) = EVal
      END DO
!------------------------------------------------------------------------------
      IF ( PrevNorm + Norm /= 0.0d0 ) THEN
         RelativeChange = 2.0d0 * ABS(PrevNorm-Norm) / (PrevNorm + Norm)
      ELSE
         RelativeChange = 0.0d0
      END IF

      WRITE( Message,* ) 'Result Norm   : ',Norm
      CALL Info( 'KESolver', Message, Level = 4 )
      WRITE( Message,* ) 'Relative Change : ',RelativeChange
      CALL Info( 'KESolver', Message, Level = 4 )

      IF ( RelativeChange < NewtonTol .OR. &
              iter > NewtonIter ) NewtonLinearization = .TRUE.

      IF ( RelativeChange < NonlinearTol ) EXIT
!------------------------------------------------------------------------------
    END DO
!------------------------------------------------------------------------------

    n = SIZE( Solver % Variable % Values )
    KE => VariableGet( Solver % Mesh % Variables, 'Kinetic Energy' )
    IF (ASSOCIATED(KE)) KE % Values = Solver % Variable % Values(1:n:2)

    KE => VariableGet( Solver % Mesh % Variables, 'Kinetic Dissipation' )
    IF (ASSOCIATED(KE)) KE % Values = Solver % Variable % Values(2:n:2)

CONTAINS

!------------------------------------------------------------------------------
   SUBROUTINE LocalMatrix( MASS,STIFF,FORCE, &
         LOAD,NodalCT,NodalC0,NodalC1,NodalC2, &
             UX,UY,UZ,Stabilize,Element,n,Nodes )
!------------------------------------------------------------------------------
!******************************************************************************
!
!  Return element local matrices and RSH vector for diffusion-convection
!  equation: 
!
!  ARGUMENTS:
!
!  REAL(KIND=dp) :: MASS(:,:)
!     OUTPUT: time derivative coefficient matrix
!
!  REAL(KIND=dp) :: STIFF(:,:)
!     OUTPUT: rest of the equation coefficients
!
!  REAL(KIND=dp) :: FORCE(:)
!     OUTPUT: RHS vector
!
!  REAL(KIND=dp) :: LOAD(:)
!     INPUT:
!
!  REAL(KIND=dp) :: NodalCT,NodalC0,NodalC1
!     INPUT: Coefficient of the time derivative term, 0 degree term, and
!            the convection term respectively
!
!  REAL(KIND=dp) :: NodalC2(:)
!     INPUT: Nodal values of the diffusion term coefficient tensor
!
!  REAL(KIND=dp) :: UX(:),UY(:),UZ(:)
!     INPUT: Nodal values of velocity components from previous iteration
!           used only if coefficient of the convection term (C1) is nonzero
!
!  LOGICAL :: Stabilize
!     INPUT: Should stabilzation be used ? Used only if coefficient of the
!            convection term (C1) is nonzero
!
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
     USE MaterialModels

     IMPLICIT NONE

     REAL(KIND=dp), DIMENSION(:)   :: FORCE,UX,UY,UZ
     REAL(KIND=dp), DIMENSION(:,:) :: MASS,STIFF,LOAD
     REAL(KIND=dp) :: NodalC0(:,:),NodalC1(:),NodalCT(:),NodalC2(:,:)

     LOGICAL :: Stabilize

     INTEGER :: n

     TYPE(Nodes_t) :: Nodes
     TYPE(Element_t) :: Element

!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------
!
     REAL(KIND=dp) :: ddBasisddx(2*n,3,3)
     REAL(KIND=dp) :: Basis(2*n)
     REAL(KIND=dp) :: dBasisdx(2*n,3),detJ

     REAL(KIND=dp) :: Velo(3),dVelodx(3,3)

     REAL(KIND=dp) :: A(2,2),M(2,2)
     REAL(KIND=dp) :: LoadatIp(2),Cmu,Rho
     INTEGER :: i,j,c,p,q,t,dim,N_Integ,NBasis

     REAL(KIND=dp) :: s,u,v,w, K,E,Eta,Strain(3,3), alpha,oldalpha,dalpha,err,ww,olderr,derr

     TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff

     REAL(KIND=dp) :: C0(2),C1,CT,C2(2),dC2dx(3),SecInv,X,Y,Z
     REAL(KIND=dp) :: Metric(3,3),Symb(3,3,3),dSymb(3,3,3,3),SqrtMetric

     REAL(KIND=dp), DIMENSION(:), POINTER :: U_Integ,V_Integ,W_Integ,S_Integ

     LOGICAL :: stat,Convection, Bubbles, UseRNGModel

!------------------------------------------------------------------------------

     dim = CoordinateSystemDimension()

     FORCE = 0.0D0
     STIFF = 0.0D0
     MASS  = 0.0D0

     NBasis = 2*n
     Bubbles = .TRUE.

     UseRNGModel = KEModel == 'rng'

!------------------------------------------------------------------------------
!    Integration stuff
!------------------------------------------------------------------------------
     IF ( Bubbles ) THEN
        IntegStuff = GaussPoints( element, element % Type % GaussPoints2 )
     ELSE
        IntegStuff = GaussPoints( element )
     END IF

     U_Integ => IntegStuff % u
     V_Integ => IntegStuff % v
     W_Integ => IntegStuff % w
     S_Integ => IntegStuff % s
     N_Integ =  IntegStuff % n

!------------------------------------------------------------------------------
!    Now we start integrating
!------------------------------------------------------------------------------
     DO t=1,N_Integ
       u = U_Integ(t)
       v = V_Integ(t)
       w = W_Integ(t)
!------------------------------------------------------------------------------
!      Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
       stat = ElementInfo( Element,Nodes,u,v,w,detJ, &
             Basis,dBasisdx,ddBasisddx,Stabilize,Bubbles )
!------------------------------------------------------------------------------
!      Coordinatesystem dependent info
!------------------------------------------------------------------------------
       X = SUM( Nodes % x(1:n)*Basis(1:n) )
       Y = SUM( Nodes % y(1:n)*Basis(1:n) )
       Z = SUM( nodes % z(1:n)*Basis(1:n) )
       CALL CoordinateSystemInfo(Metric,SqrtMetric,Symb,dSymb,X,Y,Z)

       s = SqrtMetric * detJ * S_Integ(t)

!      Velocity from previous iteration at the integration point
!------------------------------------------------------------------------------
       Velo = 0.0D0
       Velo(1) = SUM( UX(1:n)*Basis(1:n) )
       Velo(2) = SUM( UY(1:n)*Basis(1:n) )
       Velo(3) = SUM( UZ(1:n)*Basis(1:n) )

       dVelodx = 0.0d0
       DO i=1,dim
         dVelodx(1,i) = SUM( UX(1:n)*dBasisdx(1:n,i) )
         dVelodx(2,i) = SUM( UY(1:n)*dBasisdx(1:n,i) )
         dVelodx(3,i) = SUM( UZ(1:n)*dBasisdx(1:n,i) )
       END DO

       IF ( CurrentCoordinateSystem() == Cartesian ) THEN
          Strain = 0.5d0 * ( dVelodx + TRANSPOSE(dVelodx) )
          Secinv = 2 * SUM( Strain * Strain )
       ELSE
          SecInv = SecondInvariant( Velo,dVelodx ) / 2
       END IF
!------------------------------------------------------------------------------
!      Coefficient of the convection and time derivative terms
!      at the integration point
!------------------------------------------------------------------------------
       K = SUM( LocalKinEnergy(1:n) * Basis(1:n) )
       E = SUM( LocalDissipation(1:n) * Basis(1:n) )
       Eta =  SQRT(SecInv) * K / E

       Cmu = SUM( KECMu(1:n) * Basis(1:n) )
       Rho = SUM( Density(1:n) * Basis(1:n) )

       C0(1) = SUM( NodalC0(1,1:n)*Basis(1:n) )
       C0(2) = SUM( NodalC0(2,1:n)*Basis(1:n) )
       C0(2) = C0(2) * SUM( Basis(1:n) * KEC2(1:n) )

! moved to ---> rhs
!      C0(2) = C0(2) + Cmu*Rho*Eta**3*(1-Eta/4.38d0) / &
!                 (1.0d0 + 0.012d0*Eta**3) * E / K

       C1 = Rho
       CT = Rho
!------------------------------------------------------------------------------
!      Coefficient of the diffusion term &
!------------------------------------------------------------------------------
       Alpha = 1.0d0

       IF ( UseRNGModel ) THEN
          ww = SUM( Viscosity(1:n) * Basis(1:n) ) / &
               SUM( EffectiveVisc(1,1:n) * Basis(1:n) )
          alpha = 1.3929d0
          oldalpha = 1

          olderr = ABS((oldalpha-1.3929d0)/(1.0d0-1.3929d0))**0.6321d0
          olderr = olderr * ABS((oldalpha+2.3929d0)/(1.0d0+2.3929d0))**0.3679d0
          olderr = olderr - ww

          DO i=1,100
             err = ABS((alpha-1.3929d0)/(1.0d0-1.3929d0))**0.6321d0
             err = err * ABS((alpha+2.3929d0)/(1.0d0+2.3929d0))**0.3679d0
             err = err - ww
             derr = olderr - err
             olderr = err
             dalpha = oldalpha - alpha
             oldalpha = alpha
             alpha = alpha - 0.5 * err * dalpha / derr
             IF ( ABS(err) < 1.0d-8 ) EXIT
          END DO

          IF ( ABS(err) > 1.0d-8 ) THEN
             print*,'huh: ', alpha
             alpha = 1.3929d0
          END IF
       END IF

       C2(1) = Alpha * SUM( NodalC2(1,1:n) * Basis(1:n) )
       C2(2) = Alpha * SUM( NodalC2(2,1:n) * Basis(1:n) )
!------------------------------------------------------------------------------
!       Loop over basis functions of both unknowns and weights
!------------------------------------------------------------------------------
       DO p=1,NBasis
       DO q=1,NBasis
!------------------------------------------------------------------------------
!         The diffusive-convective equation without stabilization
!------------------------------------------------------------------------------
          M = 0.0d0
          A = 0.0d0

          M(1,1) = CT * Basis(q) * Basis(p)
          M(2,2) = CT * Basis(q) * Basis(p)

          A(1,2) = C0(1) * Basis(q) * Basis(p)
          A(2,2) = C0(2) * Basis(q) * Basis(p)
!------------------------------------------------------------------------------
!         The diffusion term
!------------------------------------------------------------------------------
          IF ( CurrentCoordinateSystem() == Cartesian ) THEN
             DO i=1,dim
               A(1,1) = A(1,1) + C2(1) * dBasisdx(q,i) * dBasisdx(p,i)
               A(2,2) = A(2,2) + C2(2) * dBasisdx(q,i) * dBasisdx(p,i)
             END DO
          ELSE
             DO i=1,dim
               DO j=1,dim
                  A(1,1) = A(1,1) + Metric(i,j) * C2(1) * &
                       dBasisdx(q,i) * dBasisdx(p,i)

                  A(2,2) = A(2,2) + Metric(i,j) * C2(2) * &
                       dBasisdx(q,i) * dBasisdx(p,i)
               END DO
             END DO
          END IF

!------------------------------------------------------------------------------
!           The convection term
!------------------------------------------------------------------------------
          DO i=1,dim
            A(1,1) = A(1,1) + C1 * Velo(i) * dBasisdx(q,i) * Basis(p)
            A(2,2) = A(2,2) + C1 * Velo(i) * dBasisdx(q,i) * Basis(p)
          END DO

          DO i=1,2
             DO j=1,2
               STIFF(2*(p-1)+i,2*(q-1)+j) = STIFF(2*(p-1)+i,2*(q-1)+j)+s*A(i,j)
               MASS(2*(p-1)+i,2*(q-1)+j)  = MASS(2*(p-1)+i,2*(q-1)+j) +s*M(i,j)
             END DO
          END DO
       END DO
       END DO

      ! Load at the integration point:
      !-------------------------------
       LoadAtIP(1) = SUM( LOAD(1,1:n)*Basis(1:n) ) * SecInv
       LoadAtIP(2) = SUM( LOAD(2,1:n)*Basis(1:n) ) * SecInv

       IF ( UseRNGModel ) &
          LoadatIP(2) = LoadatIP(2) - Cmu*Rho*Eta**3*(1-Eta/4.38d0) / &
                     (1.0d0 + 0.012d0*Eta**3) * E**2 / K
!------------------------------------------------------------------------------
        DO p=1,NBasis
           FORCE(2*(p-1)+1) = FORCE(2*(p-1)+1)+s*LoadAtIp(1)*Basis(p)
           FORCE(2*(p-1)+2) = FORCE(2*(p-1)+2)+s*LoadAtIp(2)*Basis(p)
        END DO
      END DO
!------------------------------------------------------------------------------
   END SUBROUTINE LocalMatrix
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
  END SUBROUTINE KESolver
!------------------------------------------------------------------------------
