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
! ******************************************************************************
! *
! *                    Author:       Juha Ruokolainen
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
!/******************************************************************************
! *
! *                         ========================================
! *                         THE REISSNER-MINDLIN PLATE SOLVER MODULE
! *                         ========================================
! *
! *                     Author:           Mikko Lyly
! *
! *                    Address: Center for Scientific Computing
! *                                Tietotie 6, P.O. BOX 405
! *                                  02101 Espoo, Finland
! *                                  Tel. +358 0 457 2723
! *                                Telefax: +358 0 457 2302
! *                              EMail: Mikko.Lyly@csc.fi
! *
! *                       Date: 09 Apr 2000
! *
! *                Modified by:
! *
! *       Date of modification:
! *
! *****************************************************************************/
 
!------------------------------------------------------------------------------
 SUBROUTINE SmitcSolver( Model,Solver,dt,TransientSimulation )
!DEC$ATTRIBUTES DLLEXPORT :: SmitcSolver
!------------------------------------------------------------------------------
!******************************************************************************
!
!  Solve the Reissner-Mindlin equations!
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
!  LOGICAL :: TransientSimulation
!     INPUT: Steady state or transient simulation
!
!******************************************************************************
     USE DefUtils

     IMPLICIT NONE
!------------------------------------------------------------------------------
 
     TYPE(Model_t) :: Model
     TYPE(Solver_t):: Solver
 
     REAL(KIND=dp) :: dt
     LOGICAL :: TransientSimulation
 
!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------
     INTEGER :: k,n,t,bf_id,mat_id,istat,LocalNodes
 
     TYPE(Matrix_t),POINTER  :: StiffMatrix
     TYPE(Nodes_t)   :: ElementNodes
     TYPE(Element_t),POINTER :: CurrentElement
     TYPE(ValueList_t), POINTER :: Material
 
     REAL(KIND=dp) :: Norm,PrevNorm
     INTEGER, POINTER :: NodeIndexes(:)
 
     LOGICAL :: AllocationsDone = .FALSE., HoleCorrection, &
         got_mat_id, got_bf_id, NeglectSprings
 
     INTEGER, POINTER :: DeflectionPerm(:)
     REAL(KIND=dp), POINTER :: Deflection(:), ForceVector(:) 
 
     REAL(KIND=dp), ALLOCATABLE :: &
                     LocalStiffMatrix(:,:), Load(:), Load2(:), LocalForce(:), &
                     Poisson(:), Thickness(:), Young(:), Tension(:), &
                     LocalMassMatrix(:,:), LocalDampMatrix(:,:), Density(:), &
                     DampingCoef(:), HoleFraction(:), HoleSize(:), SpringCoef(:)

     CHARACTER(LEN=MAX_NAME_LEN) :: HoleType
     CHARACTER(LEN=MAX_NAME_LEN) :: VersionID = "$Id: Smitc.f90,v 1.30 2004/07/30 07:39:30 jpr Exp $"
 
     REAL(KIND=dp) :: at,st,CPUTime

     LOGICAL :: GotIt, GotHoleType

     SAVE LocalStiffMatrix, LocalMassMatrix, Load, Load2, LocalForce, ElementNodes, &
          Poisson, Density, Young, Thickness, Tension, AllocationsDone, &
          LocalDampMatrix, DampingCoef, HoleFraction, HoleSize, SpringCoef

!------------------------------------------------------------------------------
!    Check if version number output is requested
!------------------------------------------------------------------------------
     IF ( .NOT. AllocationsDone ) THEN
       IF ( ListGetLogical( GetSimulation(), 'Output Version Numbers', GotIt ) ) THEN
         CALL Info( 'SmitcSolver', 'Smitc version:', Level = 0 ) 
         CALL Info( 'SmitcSolver', VersionID, Level = 0 ) 
         CALL Info( 'SmitcSolver', ' ', Level = 0 ) 
       END IF
     END IF

!------------------------------------------------------------------------------
!    Get variables needed for solution
!------------------------------------------------------------------------------
     LocalNodes = Model % NumberOfNodes
     Norm = Solver % Variable % Norm
!------------------------------------------------------------------------------
!    Allocate some permanent storage, this is done first time only
!------------------------------------------------------------------------------

     IF ( .NOT. AllocationsDone ) THEN
       N = Model % MaxElementNodes
 
       ALLOCATE( ElementNodes % x( N ),   &
                 ElementNodes % y( N ),   &
                 ElementNodes % z( N ),   &
                 LocalForce( 3*N ),         &
                 LocalStiffMatrix( 3*N, 3*N ), &
                 LocalMassMatrix( 3*N, 3*N ), &
                 LocalDampMatrix( 3*N, 3*N ), &
                 Load( N ), Load2(N), Poisson( N ), Young( N ), &
                 Density ( N ), Thickness( N ), DampingCoef( N ), &
                 Tension( N ), HoleFraction( N ), HoleSize( N ), &
                 SpringCoef( N ), STAT=istat )
 
       IF ( istat /= 0 ) THEN
         CALL FATAL('SmitcSolver','Memory allocation error')
       END IF
 
       AllocationsDone = .TRUE.
     END IF

!------------------------------------------------------------------------------
!    Do some additional initialization, and go for it
!------------------------------------------------------------------------------

     at = CPUTime()
     CALL DefaultInitialize()

     ! These keywords enable that the use of a second paramter set
     ! for the same elements where the material properties are given in an
     ! additional body. May be used to model microphone and its backplate, for example.

     mat_id = ListGetInteger( Solver % Values, 'Material Index',got_mat_id, &
               minv=1, maxv=Model % NumberOFMaterials )
     IF(got_mat_id) THEN
       Material => Model % Materials(mat_id) % Values
     END IF

     bf_id = ListGetInteger( Solver % Values, 'Body Force Index',got_bf_id, &
               minv=1, maxv=Model % NumberOFBodyForces )
     HoleCorrection = ListGetLogical( Solver % Values, 'Hole Correction',gotIt )

!------------------------------------------------------------------------------
!    Do the assembly
!------------------------------------------------------------------------------

     DO t=1,Solver % NumberOfActiveElements
       CurrentElement => GetActiveElement(t)
       n = GetElementNOFNodes()
       NodeIndexes => CurrentElement % NodeIndexes
  
       ElementNodes % x(1:n) = Solver % Mesh % Nodes % x(NodeIndexes)
       ElementNodes % y(1:n) = Solver % Mesh % Nodes % y(NodeIndexes)
       ElementNodes % z(1:n) = Solver % Mesh % Nodes % z(NodeIndexes)

       IF(.NOT. got_bf_id) THEN
         bf_id = ListGetInteger( Model % Bodies( CurrentElement % BodyId ) % Values, &
             'Body Force', gotIt, minv=1, maxv=Model % NumberOFBodyForces )
       END IF

       Load = 0.0d0
       Load2 = 0.0d0
       ! There may be three forces, which should be introduced in the following order
       IF(bf_id > 0) THEN
         Load(1:n) = ListGetReal( Model % BodyForces( bf_id ) % Values, &
             'Pressure', n, NodeIndexes, GotIt)
         IF(GotIt) THEN
           Load2(1:n) = ListGetReal( Model % BodyForces( bf_id ) % Values, &
               'Pressure B', n, NodeIndexes, GotIt)
           IF(GotIt) THEN
             Load(1:n) = Load(1:n) + Load2(1:n)
             Load2(1:n) = ListGetReal( Model % BodyForces( bf_id ) % Values, &
                 'Pressure C', n, NodeIndexes, GotIt)
             IF(GotIt) Load(1:n) = Load(1:n) + Load2(1:n)
           END IF
         END IF
       END IF

       IF(.NOT. got_mat_id) THEN
         mat_id = ListGetInteger( Model % Bodies( CurrentElement % BodyId ) % Values, &
             'Material', minv=1, maxv=Model % NumberOFMaterials )
         Material => Model % Materials(mat_id) % Values
       END IF

       Density(1:n) = ListGetReal( Material, 'Density', n, NodeIndexes )
       Poisson(1:n) = ListGetReal( Material, 'Poisson ratio', n, NodeIndexes )
       Young(1:n) = ListGetReal( Material,'Youngs modulus', n, NodeIndexes )
       Thickness(1:n) = ListGetReal( Material,'Thickness', n, NodeIndexes )
       Tension(1:n) = ListGetReal( Material, 'Tension', n, NodeIndexes, GotIt)

       ! In some cases it is preferable that the damping and spring coefficients are related
       ! to the body force.

       IF ( Model % NumberOfBodyForces > 0 .AND. bf_id > 0 )  THEN
          DampingCoef(1:n) = ListGetReal( Model % BodyForces( bf_id ) % Values, &
               'Damping', n, NodeIndexes, GotIt )
       ELSE
          GotIt = .FALSE.
       END IF

       IF(.NOT. GotIt) DampingCoef(1:n) = ListGetReal( Material,&
           'Damping', n, NodeIndexes, GotIt )
       IF (.NOT. GotIt ) DampingCoef(1:n) = 0.0d0

       IF ( Model % NumberOfBodyForces > 0 .AND. bf_id > 0 )  THEN
          SpringCoef(1:n) = ListGetReal( Model % BodyForces( bf_id ) % Values, &
               'Spring', n, NodeIndexes, GotIt)
       ELSE
          GotIt = .FALSE.
       END IF

       IF(.NOT. GotIt) SpringCoef(1:n) = ListGetReal( Material, &
           'Spring', n, NodeIndexes, GotIt)
       IF (.NOT. GotIt ) SpringCoef(1:n) = 0.0d0

       IF(HoleCorrection) THEN
         HoleType = ListGetString(Material,'Hole Type',GotHoleType)
         IF(GotHoleType) THEN
           HoleSize(1:n) = ListGetReal( Material, &
               'Hole Size', n, NodeIndexes,minv=0.0d0)
           HoleFraction(1:n) = ListGetReal( Material, &
               'Hole Fraction', n, NodeIndexes,minv=0.0d0,maxv=1.0d0)
         END IF
       END IF
 

!------------------------------------------------------------------------------
!      Get element local matrix, and rhs vector
!------------------------------------------------------------------------------

       CALL LocalMatrix(  LocalStiffMatrix, LocalDampMatrix, LocalMassMatrix, &
            LocalForce,Load, CurrentElement,n,ElementNodes, DampingCoef, SpringCoef )

       IF( TransientSimulation ) THEN
          CALL Default2ndOrderTime( LocalMassMatrix,LocalDampMatrix, &
                       LocalStiffMatrix, LocalForce )
       END IF

!------------------------------------------------------------------------------
!      Update global matrix and rhs vector from local matrix & vector
!------------------------------------------------------------------------------
       CALL DefaultUpdateEquations( LocalStiffMatrix, LocalForce )

       IF ( Solver % NOFEigenValues > 0 ) THEN
          CALL DefaultUpdateMass( LocalMassMatrix )
          CALL DefaultUpdateDamp( LocalDampMatrix )
       END IF
!------------------------------------------------------------------------------

     END DO

!------------------------------------------------------------------------------
!    FinishAssemebly must be called after all other assembly steps, but before
!    Dirichlet boundary settings. Actually no need to call it except for
!    transient simulations.
!------------------------------------------------------------------------------
     CALL DefaultFinishAssembly()
!------------------------------------------------------------------------------
!    Dirichlet boundary conditions
!------------------------------------------------------------------------------
     CALL DefaultDirichletBCs()

     at = CPUTime() - at

     WRITE (Message,*) 'Assembly (s): ',at
     CALL Info('SmitcSolver',Message,Level=4)
!------------------------------------------------------------------------------
!    Solve the system and we are done.
!------------------------------------------------------------------------------
     st = CPUTime()
     Norm =  DefaultSolve()

     st = CPUTime() - st
     WRITE (Message,*) 'Solve (s): ',st
     CALL Info('SmitcSolver',Message,Level=4)
!------------------------------------------------------------------------------
 
   CONTAINS

!------------------------------------------------------------------------------
     SUBROUTINE LocalMatrix( StiffMatrix, DampMatrix, MassMatrix, &
          Force, Load, Element, n, Nodes, DampingCoef, SpringCoef )
!------------------------------------------------------------------------------
       REAL(KIND=dp) :: StiffMatrix(:,:), DampMatrix(:,:), &
            MassMatrix(:,:), Force(:), Load(:), DampingCoef(:), SpringCoef(:)
       INTEGER :: n
       TYPE(Nodes_t) :: Nodes
       TYPE(Element_t), POINTER :: Element
!------------------------------------------------------------------------------
       REAL(KIND=dp) :: Basis(n),dBasisdx(n,3),ddBasisddx(n,3,3), &
                           Curvature(3,100), ShearStrain(2,100), &
                           Ematrix(3,3), Gmatrix(2,2), Tmatrix(2,2)
       REAL(KIND=dp) :: SqrtElementMetric,U,V,W,S,Kappa,rho,h,qeff
       REAL(KIND=dp) :: Pressure, DampCoef, WinklerCoef
       LOGICAL :: Stat
       INTEGER :: i,j,p,q,t
       TYPE(GaussIntegrationPoints_t) :: IntegStuff
!------------------------------------------------------------------------------

       Force = 0.0d0
       StiffMatrix = 0.0d0
       DampMatrix = 0.0d0
       MassMatrix = 0.0d0
       Curvature = 0.0d0
       ShearStrain = 0.0d0
!
!      Numerical integration:
!      ----------------------

       IntegStuff = GaussPoints( Element, 3 )

       DO t = 1,IntegStuff % n
         U = IntegStuff % u(t)
         V = IntegStuff % v(t)
         W = IntegStuff % w(t)
         S = IntegStuff % s(t)
!
!------------------------------------------------------------------------------
!        Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------

         stat = ElementInfo( Element,Nodes,U,V,W,SqrtElementMetric, &
                    Basis,dBasisdx,ddBasisddx,.FALSE. )

         S = S * SqrtElementMetric

         Pressure = SUM( Load(1:n)*Basis(1:n) )
         h = SUM( Thickness(1:n)*Basis(1:n) )
         DampCoef = SUM( DampingCoef(1:n) * Basis(1:n) )
         WinklerCoef = SUM( SpringCoef(1:N) * Basis(1:N) )

         IF(HoleCorrection .AND. GotHoleType) THEN
           CALL PerforatedElasticity(Ematrix,Gmatrix, &
               Poisson,Young,Thickness,HoleFraction,HoleSize,Basis,n)
           qeff = SUM(HoleFraction(1:n)*Basis(1:n))
           rho = (1.0d0-qeff) * SUM( Density(1:n)*Basis(1:n) )
           Tmatrix = 0.0d0
           Tmatrix(1,1) = SQRT(1.0d0-qeff**2.0d0) * SUM( Tension(1:n)*Basis(1:n) ) * h
           Tmatrix(2,2) = Tmatrix(1,1)
         ELSE
           CALL IsotropicElasticity(Ematrix,Gmatrix, &
               Poisson,Young,Thickness,Basis,n)
           rho = SUM( Density(1:n)*Basis(1:n) )
           Tmatrix = 0.0d0
           Tmatrix(1,1) = SUM( Tension(1:n)*Basis(1:n) ) * h
           Tmatrix(2,2) = SUM( Tension(1:n)*Basis(1:n) ) * h
         END IF


!
!        The degrees-of-freedom are  (u_x, u_y, u_z, r_x, r_y, r_z)
!        where u_i is the displacement [m] and r_i the rotation [1]
!        ----------------------------------------------------------

!        Bending stiffness:
!        ------------------
         DO p=1,n
            Curvature(1,3*p-1) = dBasisdx(p,1)
            Curvature(2,3*p  ) = dBasisdx(p,2)
            Curvature(3,3*p-1) = dBasisdx(p,2)
            Curvature(3,3*p  ) = dBasisdx(p,1)
         END DO

         CALL AddInnerProducts(StiffMatrix,Ematrix,Curvature,3,3*n,s)

!        In-plane stiffness:
!        -------------------

!
!        Shear stiffness:
!        ----------------
         CALL CovariantInterpolation(ShearStrain, &
              Basis, Nodes % x(1:n),Nodes % y(1:n),U,V,n)

         CALL ShearCorrectionFactor(Kappa, h, &
              Nodes % x(1:n), Nodes % y(1:n), n)

         DO p=1,n
            ShearStrain(1,3*p-2) = dBasisdx(p,1)
            ShearStrain(2,3*p-2) = dBasisdx(p,2)
         END DO 

         CALL AddInnerProducts(StiffMatrix, &
              Gmatrix,ShearStrain,2,3*n,Kappa*s)
!
!        Tensile stiffness:
!        ------------------
         ShearStrain = 0.0d0
         DO p=1,n
            ShearStrain(1,3*p-2) = dBasisdx(p,1)
            ShearStrain(2,3*p-2) = dBasisdx(p,2)
         END DO 

         CALL AddInnerProducts(StiffMatrix, &
                 Tmatrix,ShearStrain,2,3*n,s)

!        Spring Coeffficient:
!        -------------------
         DO p = 1,n
            DO q = 1,n
               StiffMatrix(3*p-2,3*q-2) = StiffMatrix(3*p-2,3*q-2) &
                    + WinklerCoef * Basis(p) * Basis(q) * s
            END DO
         END DO

!
!        Load vector:
!        ------------
         DO p=1,n
            Force(3*p-2) = Force(3*p-2) + Pressure * Basis(p) * s
         END DO
!
!        Mass matrix:
!        ------------
         DO p = 1,n
            DO q = 1,n
               MassMatrix(3*p-2,3*q-2) = MassMatrix(3*p-2,3*q-2) &
                    + rho * h * Basis(p) * Basis(q) * s
            END DO
         END DO

!
!        Damping matrix:
!        ---------------
         DO p = 1,n
            DO q = 1,n
               DampMatrix(3*p-2,3*q-2) = DampMatrix(3*p-2,3*q-2) &
                    + DampCoef * Basis(p) * Basis(q) * s
            END DO
         END DO

!------------------------------------------------------------------------------
       END DO
!------------------------------------------------------------------------------
     END SUBROUTINE LocalMatrix


!==============================================================================


     SUBROUTINE IsotropicElasticity(Ematrix, &
          Gmatrix,Poisson,Young,Thickness,Basis,n)
!------------------------------------------------------------------------------
     REAL(KIND=dp) :: Ematrix(:,:), Gmatrix(:,:), Basis(:)
     REAL(KIND=dp) :: Poisson(:), Young(:), Thickness(:)
     REAL(KIND=dp) :: Euvw, Puvw, Guvw, Tuvw
     INTEGER :: n
!------------------------------------------------------------------------------
       Euvw = SUM( Young(1:n)*Basis(1:n) )
       Puvw = SUM( Poisson(1:n)*Basis(1:n) )
       Tuvw = SUM( Thickness(1:n)*Basis(1:n) )
       Guvw = Euvw/(2.0d0*(1.0d0 + Puvw))

       Ematrix = 0.0d0
       Ematrix(1,1) = 1.0d0
       Ematrix(1,2) = Puvw
       Ematrix(2,1) = Puvw
       Ematrix(2,2) = 1.0d0
       Ematrix(3,3) = (1.0d0-Puvw)/2.0d0

       Ematrix = Ematrix* Euvw * (Tuvw**3) / (12.0d0*(1.0d0-Puvw**2))

       Gmatrix = 0.0d0
       Gmatrix(1,1) = Guvw*Tuvw
       Gmatrix(2,2) = Guvw*Tuvw
!------------------------------------------------------------------------------
     END SUBROUTINE IsotropicElasticity


!==============================================================================
! The elastic model for perforated plates is taken directly from
! M. Pedersen, W. Olthuis, P. BergWald:
! 'On the mechanical behavior of thin perforated plates and their application
!  in silicon condenser microphones', Sensors and Actuators A 54 (1996) 499-504.
! The model in verified in the special assignment of Jani Paavilainen 

     SUBROUTINE PerforatedElasticity(Ematrix, &
         Gmatrix,Poisson,Young,Thickness,HoleFraction, &
         HoleSize, Basis,n)
!------------------------------------------------------------------------------
     REAL(KIND=dp) :: Ematrix(:,:), Gmatrix(:,:), Basis(:), HoleSize(:)
     REAL(KIND=dp) :: Poisson(:), Young(:), Thickness(:), HoleFraction(:)
     REAL(KIND=dp) :: Euvw, Puvw, Guvw, Tuvw, q, a, b, k, sq

     INTEGER :: n
!------------------------------------------------------------------------------
       Euvw = SUM( Young(1:n)*Basis(1:n) )
       Puvw = SUM( Poisson(1:n)*Basis(1:n) )
       Tuvw = SUM( Thickness(1:n)*Basis(1:n) )

       q = SUM( HoleFraction(1:n)*Basis(1:n) )
       a = SUM( HoleSize(1:n)*Basis(1:n))
       sq = SQRT(q)
       b = 2*a/sq

       IF(Tuvw > b-2*a) THEN
         k = (Tuvw-0.63*(b-2*a)) * (b-2*a)**3.0d0 / 3.0d0
       ELSE
         k = ((b-2*a)-0.63*Tuvw) * Tuvw**3.0d0 / 3.0d0
       END IF

       Ematrix = 0.0d0
       Ematrix(1,1) = (1.0d0-sq)/(1.0d0-Puvw**2.0d0) + 0.5d0*sq * (1.0d0-sq)**2.0d0
       Ematrix(2,2) = Ematrix(1,1)
       Ematrix(1,2) = Puvw * (1.0d0-sq)/(1.0-Puvw**2.0d0)
       Ematrix(2,1) = Ematrix(1,2)
       Ematrix(3,3) = 0.5d0*(1.0d0-sq)/(1.0d0+Puvw) + &
           1.5d0*k*sq*(1-sq)/(b*(1.0d0+Puvw)*Tuvw**3.0d0)

       Guvw = Euvw * Ematrix(3,3) ! * 2.0d0? 

       Ematrix = Ematrix * Euvw * (Tuvw**3) / 12.0d0

       Gmatrix = 0.0d0
       Gmatrix(1,1) = Guvw * Tuvw
       Gmatrix(2,2) = Gmatrix(1,1)
!------------------------------------------------------------------------------
     END SUBROUTINE PerforatedElasticity

!==============================================================================


     SUBROUTINE ShearCorrectionFactor(Kappa,Thickness,x,y,n)
!------------------------------------------------------------------------------
       REAL(KIND=dp) :: Kappa,Thickness,x(:),y(:)
       INTEGER :: n
!------------------------------------------------------------------------------
       REAL(KIND=dp) :: x21,x32,x43,x13,x14,y21,y32,y43,y13,y14, &
            l21,l32,l43,l13,l14,alpha,h
!------------------------------------------------------------------------------
       Kappa = 1.0d0
       SELECT CASE(n)
          CASE(3)
             alpha = 0.20d0
             x21 = x(2)-x(1)
             x32 = x(3)-x(2)
             x13 = x(1)-x(1)
             y21 = y(2)-y(1)
             y32 = y(3)-y(2)
             y13 = y(1)-y(1)
             l21 = SQRT(x21**2 + y21**2)
             l32 = SQRT(x32**2 + y32**2)
             l13 = SQRT(x13**2 + y13**2)
             h = MAX(l21,l32,l13)
             Kappa = (Thickness**2)/(Thickness**2 + alpha*(h**2))
          CASE(4)
             alpha = 0.10d0
             x21 = x(2)-x(1)
             x32 = x(3)-x(2)
             x43 = x(4)-x(3)
             x14 = x(1)-x(4)
             y21 = y(2)-y(1)
             y32 = y(3)-y(2)
             y43 = y(4)-y(3)
             y14 = y(1)-y(4)
             l21 = SQRT(x21**2 + y21**2)
             l32 = SQRT(x32**2 + y32**2)
             l43 = SQRT(x43**2 + y43**2)
             l14 = SQRT(x14**2 + y14**2)
             h = MAX(l21,l32,l43,l14)
             Kappa = (Thickness**2)/(Thickness**2 + alpha*(h**2))
          CASE DEFAULT
            CALL WARN('SmitcSolver','Illegal number of nodes for Smitc elements')
          END SELECT
!------------------------------------------------------------------------------
     END SUBROUTINE ShearCorrectionFactor


!==============================================================================


     SUBROUTINE AddInnerProducts(A,B,C,m,n,s)
!------------------------------------------------------------------------------
!      Performs the operation
!
!         A = A + C' * B * C * s
!
!      with
!
!         Size( A ) = n x n
!         Size( B ) = m x m
!         Size( C ) = m x n
!------------------------------------------------------------------------------
       REAL(KIND=dp) :: A(:,:),B(:,:),C(:,:),s
       INTEGER :: m,n
!------------------------------------------------------------------------------
       INTEGER :: i,j,k,l
!------------------------------------------------------------------------------
       DO i=1,n
          DO j=1,n
             DO k=1,m
                DO l=1,m
                   A(i,j) = A(i,j) + C(k,i)*B(k,l)*C(l,j) * s
                END DO
             END DO
          END DO
       END DO
!------------------------------------------------------------------------------
     END SUBROUTINE AddInnerProducts


!==============================================================================


     SUBROUTINE CovariantInterpolation(ShearStrain,Basis,X,Y,U,V,n)
!------------------------------------------------------------------------------
       REAL(KIND=dp) :: ShearStrain(:,:),Basis(:),X(:),Y(:),U,V
       INTEGER :: n
!------------------------------------------------------------------------------
       REAL(KIND=dp) :: detJ,Jmat(2,2),invJ(2,2),ShearRef(2,100)
       REAL(KIND=dp) :: Tau(2),Sdofs(100)
       INTEGER :: j

       SELECT CASE(n)

!      The SMITC3 element
!      ==================
       CASE(3)
          CALL Jacobi3(Jmat,invJ,detJ,x,y)
          ShearRef = 0.0d0
          ShearStrain = 0.0d0

!         Compute the shear-dofs for edge 12:
!         ===================================
          Tau(1) = 1.0d0
          Tau(2) = 0.0d0
          Tau = (/ 1.0d0, 0.0d0/)

          Sdofs = 0.0d0
          Sdofs(2) = (Tau(1)*Jmat(1,1)+Tau(2)*Jmat(2,1))/2.0d0
          Sdofs(3) = (Tau(1)*Jmat(1,2)+Tau(2)*Jmat(2,2))/2.0d0
          Sdofs(5) = (Tau(1)*Jmat(1,1)+Tau(2)*Jmat(2,1))/2.0d0
          Sdofs(6) = (Tau(1)*Jmat(1,2)+Tau(2)*Jmat(2,2))/2.0d0
           
          DO j = 1,9
             ShearRef(1,j) = ShearRef(1,j) + (1+V)*Sdofs(j)
             ShearRef(2,j) = ShearRef(2,j) + ( -U)*Sdofs(j)
          END DO

!         Compute the shear-dofs for edge 23:
!         ===================================
          Tau(1) = -1.0d0/SQRT(2.0d0)
          Tau(2) =  1.0d0/SQRT(2.0d0)

          Sdofs = 0.0d0
          Sdofs(5) = (Tau(1)*Jmat(1,1)+Tau(2)*Jmat(2,1))/SQRT(2.0d0)
          Sdofs(6) = (Tau(1)*Jmat(1,2)+Tau(2)*Jmat(2,2))/SQRT(2.0d0)
          Sdofs(8) = (Tau(1)*Jmat(1,1)+Tau(2)*Jmat(2,1))/SQRT(2.0d0)
          Sdofs(9) = (Tau(1)*Jmat(1,2)+Tau(2)*Jmat(2,2))/SQRT(2.0d0)

          DO j = 1,9
             ShearRef(1,j) = ShearRef(1,j) + ( V)*Sdofs(j)
             ShearRef(2,j) = ShearRef(2,j) + (-U)*Sdofs(j)
          END DO

!         Compute the shear-dofs for edge 31:
!         ===================================
          Tau(1) =  0.0d0
          Tau(2) = -1.0d0

          Sdofs = 0.0d0
          Sdofs(2) = (Tau(1)*Jmat(1,1)+Tau(2)*Jmat(2,1))/2.0d0
          Sdofs(3) = (Tau(1)*Jmat(1,2)+Tau(2)*Jmat(2,2))/2.0d0
          Sdofs(8) = (Tau(1)*Jmat(1,1)+Tau(2)*Jmat(2,1))/2.0d0
          Sdofs(9) = (Tau(1)*Jmat(1,2)+Tau(2)*Jmat(2,2))/2.0d0

          DO j = 1,9
             ShearRef(1,j) = ShearRef(1,j) + (  V )*Sdofs(j)
             ShearRef(2,j) = ShearRef(2,j) + (-1-U)*Sdofs(j)
          END DO

!         Compute the final reduced shear strain
!         ======================================
          ShearStrain(1:2,1:9) = MATMUL(invJ,ShearRef(1:2,1:9))


!      The SMITC4 element
!      ==================
       CASE(4)
          ShearRef = 0.0d0
          ShearStrain = 0.0d0

!         Compute the shear-dofs for edge 12:
!         ===================================
          Tau(1) = 1.0d0
          Tau(2) = 0.0d0

          CALL Jacobi4(Jmat,invJ,detJ,0.0d0,-1.0d0,x,y)
          
          Sdofs = 0.0d0
          Sdofs(2) = (Tau(1)*Jmat(1,1)+Tau(2)*Jmat(2,1))
          Sdofs(3) = (Tau(1)*Jmat(1,2)+Tau(2)*Jmat(2,2))
          Sdofs(5) = (Tau(1)*Jmat(1,1)+Tau(2)*Jmat(2,1))
          Sdofs(6) = (Tau(1)*Jmat(1,2)+Tau(2)*Jmat(2,2))

          DO j = 1,12
             ShearRef(1,j) = ShearRef(1,j) + (1-V)/4.0d0*Sdofs(j)
          END DO

!         Compute the shear-dofs for edge 23:
!         ===================================
          Tau(1) = 0.0d0
          Tau(2) = 1.0d0

          CALL Jacobi4(Jmat,invJ,detJ,1.0d0,0.0d0,x,y)

          Sdofs = 0.0d0
          Sdofs(5) = (Tau(1)*Jmat(1,1)+Tau(2)*Jmat(2,1))
          Sdofs(6) = (Tau(1)*Jmat(1,2)+Tau(2)*Jmat(2,2))
          Sdofs(8) = (Tau(1)*Jmat(1,1)+Tau(2)*Jmat(2,1))
          Sdofs(9) = (Tau(1)*Jmat(1,2)+Tau(2)*Jmat(2,2))

          DO j = 1,12
             ShearRef(2,j) = ShearRef(2,j) + (1+U)/4.0d0*Sdofs(j)
          END DO

!         Compute the shear-dofs for edge 34:
!         ===================================
          Tau(1) = -1.0d0
          Tau(2) =  0.0d0

          CALL Jacobi4(Jmat,invJ,detJ,0.0d0,1.0d0,x,y)

          Sdofs = 0.0d0
          Sdofs(8)  = (Tau(1)*Jmat(1,1)+Tau(2)*Jmat(2,1))
          Sdofs(9)  = (Tau(1)*Jmat(1,2)+Tau(2)*Jmat(2,2))
          Sdofs(11) = (Tau(1)*Jmat(1,1)+Tau(2)*Jmat(2,1))
          Sdofs(12) = (Tau(1)*Jmat(1,2)+Tau(2)*Jmat(2,2))

          DO j = 1,12
             ShearRef(1,j) = ShearRef(1,j) + (-1-V)/4.0d0*Sdofs(j)
          END DO

!         Compute the shear-dofs for edge 41:
!         ===================================
          Tau(1) =  0.0d0
          Tau(2) = -1.0d0

          CALL Jacobi4(Jmat,invJ,detJ,-1.0d0,0.0d0,x,y)

          Sdofs = 0.0d0
          Sdofs(2)  = (Tau(1)*Jmat(1,1)+Tau(2)*Jmat(2,1))
          Sdofs(3)  = (Tau(1)*Jmat(1,2)+Tau(2)*Jmat(2,2))
          Sdofs(11) = (Tau(1)*Jmat(1,1)+Tau(2)*Jmat(2,1))
          Sdofs(12) = (Tau(1)*Jmat(1,2)+Tau(2)*Jmat(2,2))

          DO j = 1,12
             ShearRef(2,j) = ShearRef(2,j) + (-1+U)/4.0d0*Sdofs(j)
          END DO

!         Compute the final reduced shear strain
!         ======================================
          CALL Jacobi4(Jmat,invJ,detJ,U,V,x,y)
          ShearStrain(1:2,1:12) = MATMUL(invJ,ShearRef(1:2,1:12))

       CASE DEFAULT
         CALL WARN('SmitcSolver','Illegal number of nodes for Smitc elements.')

       END SELECT
!------------------------------------------------------------------------------
     END SUBROUTINE CovariantInterpolation


!==============================================================================


     SUBROUTINE Jacobi3(Jmat,invJ,detJ,x,y)
!------------------------------------------------------------------------------
       REAL(KIND=dp) :: Jmat(:,:),invJ(:,:),detJ,x(:),y(:)
!------------------------------------------------------------------------------
       Jmat(1,1) = x(2)-x(1)
       Jmat(2,1) = x(3)-x(1)
       Jmat(1,2) = y(2)-y(1)
       Jmat(2,2) = y(3)-y(1)

       detJ = Jmat(1,1)*Jmat(2,2)-Jmat(1,2)*Jmat(2,1)

       invJ(1,1) =  Jmat(2,2)/detJ
       invJ(2,2) =  Jmat(1,1)/detJ
       invJ(1,2) = -Jmat(1,2)/detJ
       invJ(2,1) = -Jmat(2,1)/detJ
!------------------------------------------------------------------------------
     END SUBROUTINE Jacobi3


!==============================================================================


     SUBROUTINE Jacobi4(Jmat,invJ,detJ,xi,eta,x,y)
!------------------------------------------------------------------------------
       REAL(KIND=dp) :: Jmat(:,:),invJ(:,:),detJ,xi,eta,x(:),y(:)
!------------------------------------------------------------------------------
       REAL(KIND=dp) :: dNdxi(4), dNdeta(4)
       INTEGER :: i

       dNdxi(1) = -(1-eta)/4.0d0
       dNdxi(2) =  (1-eta)/4.0d0
       dNdxi(3) =  (1+eta)/4.0d0
       dNdxi(4) = -(1+eta)/4.0d0
       dNdeta(1) = -(1-xi)/4.0d0
       dNdeta(2) = -(1+xi)/4.0d0
       dNdeta(3) =  (1+xi)/4.0d0
       dNdeta(4) =  (1-xi)/4.0d0
       
       Jmat = 0.0d0
       DO i=1,4
          Jmat(1,1) = Jmat(1,1) + dNdxi(i)*x(i)
          Jmat(1,2) = Jmat(1,2) + dNdxi(i)*y(i)
          Jmat(2,1) = Jmat(2,1) + dNdeta(i)*x(i)
          Jmat(2,2) = Jmat(2,2) + dNdeta(i)*y(i)
       END DO

       detJ = Jmat(1,1)*Jmat(2,2)-Jmat(1,2)*Jmat(2,1)

       invJ(1,1) = Jmat(2,2)/detJ
       invJ(2,2) = Jmat(1,1)/detJ
       invJ(1,2) = -Jmat(1,2)/detJ
       invJ(2,1) = -Jmat(2,1)/detJ
!------------------------------------------------------------------------------
     END SUBROUTINE Jacobi4

!==============================================================================


   END SUBROUTINE SmitcSolver
!------------------------------------------------------------------------------







