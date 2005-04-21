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
! * Module containing a solver for helmholtz equation using BEM
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
! *                       Date: 2002
! *
! *                Modified by:
! *
! *       Date of modification:
! *
! *****************************************************************************/

!------------------------------------------------------------------------------
   MODULE GlobMat
!------------------------------------------------------------------------------
      USE Types
      COMPLEX(KIND=dp), POINTER :: Matrix(:,:)
!------------------------------------------------------------------------------
   END MODULE GlobMat
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   SUBROUTINE HelmholtzBEMSolver( Model,Solver,dt,TransientSimulation )
   !DEC$ATTRIBUTES DLLEXPORT :: HelmholtzBEMSolver
!------------------------------------------------------------------------------
!******************************************************************************
!
!  Solve the Helmholtz equation using BEM!
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
     USE GlobMat

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
     INTEGER :: i,j,k,n,t,istat,bf_id,BoundaryNodes
 
     TYPE(Matrix_t),POINTER  :: STIFF
     TYPE(Nodes_t)   :: ElementNodes
     TYPE(Element_t),POINTER :: CurrentElement
 
     REAL(KIND=dp) :: Norm, PrevNorm
     INTEGER, POINTER :: NodeIndexes(:)

     LOGICAL :: AllocationsDone = .FALSE., GotIt
 
     COMPLEX(KIND=dp), POINTER :: Potential(:),ForceVector(:), &
               Diagonal(:)
     INTEGER, POINTER :: PotentialPerm(:), BoundaryPerm(:)

     LOGICAL, ALLOCATABLE :: PotentialKnown(:)
 
     COMPLEX(KIND=dp), ALLOCATABLE ::  Flx(:), Pot(:), VolumeForce(:), &
                       Load(:)

     REAL(KIND=dp), ALLOCATABLE :: P1(:), P2(:)
 
     REAL(KIND=dp) :: at,st,CPUTime,s, AngularFrequency, Work(1)
     TYPE(Variable_t), POINTER :: Var

     CHARACTER(LEN=MAX_NAME_LEN) :: EquationName

     SAVE Load, ElementNodes, AllocationsDone, &
        PotentialKnown, PotentialPerm, BoundaryPerm, BoundaryNodes, &
           Pot, Flx, P1, P2, Potential, ForceVector, Diagonal

     CHARACTER(LEN=MAX_NAME_LEN) :: VersionID = "$Id: HelmholtzBEM.f90,v 1.15 2004/06/18 10:57:36 jpr Exp $"

!------------------------------------------------------------------------------
!    Check if version numer output is requested
!------------------------------------------------------------------------------
     IF ( .NOT. AllocationsDone ) THEN
        IF ( ListGetLogical( GetSimulation(), 'Output Version Numbers', GotIt ) ) THEN
           CALL Info( 'HelmholtzBEM', 'HelmholtzBEM Solver version:', Level = 0 ) 
           CALL Info( 'HelmholtzBEM', VersionID, Level = 0 ) 
           CALL Info( 'HelmholtzBEM', ' ', Level = 0 ) 
        END IF
     END IF

!------------------------------------------------------------------------------
     IF ( .NOT. AllocationsDone ) THEN
!------------------------------------------------------------------------------
!       Allocate some permanent storage, this is done first time only
!------------------------------------------------------------------------------
!
!       Get permutation of mesh nodes, so that boundary nodes get
!       numbered from 1..nb:
!       ---------------------------------------------------------
        ALLOCATE( PotentialPerm( Solver % Mesh % NumberOfNodes ), &
                   BoundaryPerm( Solver % Mesh % NumberOfNodes ), STAT=istat)

        IF ( istat /= 0 ) THEN
           CALL Fatal( 'HelmholtzBEMSolver', 'Memory allocation error 1.' )
        END IF

        PotentialPerm = 0
        BoundaryPerm  = 0
        BoundaryNodes = 0

        DO t=1,Solver % NumberOfActiveElements
           CurrentElement => Solver % Mesh % Elements( Solver % ActiveElements(t) )

           IF ( .NOT. ASSOCIATED( CurrentElement % BoundaryInfo ) ) CYCLE
           IF (CurrentElement % Type % ElementCode == 101 ) CYCLE

           DO j=1, CurrentElement % Type % NumberOfNodes
              k = CurrentElement % NodeIndexes(j)
              IF ( PotentialPerm(k) == 0 ) THEN
                 BoundaryNodes = BoundaryNodes + 1
                 BoundaryPerm(BoundaryNodes) = k
                 PotentialPerm(k) = BoundaryNodes
              END IF
           END DO
        END DO

        N = Model % MaxElementNodes
 
        ALLOCATE( ElementNodes % x( N ),                  &
                  ElementNodes % y( N ),                  &
                  ElementNodes % z( N ),                  &
                  Flx( BoundaryNodes ),                   &
                  Pot( BoundaryNodes ),                   &
                  Load( BoundaryNodes ),                  &
                  Diagonal( BoundaryNodes ),              &
                  PotentialKnown( BoundaryNodes ),        &
                  Matrix( BoundaryNodes, BoundaryNodes ), STAT=istat )

        IF ( istat /= 0 ) THEN
           CALL Fatal( 'HelmholtzBEMSolver', 'Memory allocation error 2.' )
        END IF

        ALLOCATE( Potential( Solver % Mesh % NumberOfNodes ), P1(n), P2(n), &
             ForceVector( Solver % Mesh % NumberOfNodes ),STAT=istat ) 

        IF ( istat /= 0 ) THEN
           CALL Fatal( 'HelmholtzBEMSolver', 'Memory allocation error 3.' )
        END IF
 
        AllocationsDone = .TRUE.
     END IF

!
!------------------------------------------------------------------------------
! Figure out angular frequency:
!------------------------------------------------------------------------------
  AngularFrequency = 0.0d0

  NodeIndexes => Solver % Mesh % Elements(1) % NodeIndexes

  Work(1:1) = ListGetReal( Model % Simulation, &
     'Angular Frequency', 1, NodeIndexes, GotIt )

  AngularFrequency = Work(1)

  IF ( .NOT. GotIt ) THEN
     Work(1:1) = ListGetReal( Model % Simulation, 'Frequency', 1, NodeIndexes )
     AngularFrequency = 2*PI*Work(1)
  END IF


!------------------------------------------------------------------------------
!    Do some additional initialization, and go for it
!------------------------------------------------------------------------------
     at = CPUTime()
     EquationName = ListGetString( Model % Solver % Values, 'Equation' )

     Matrix      = 0.0d0
     Load        = 0.0d0
     Diagonal    = 0.0d0
     ForceVector = 0.0d0

     DO i=1,Solver % Mesh % NumberOfNodes
        Potential(i) = DCMPLX( Solver % Variable % Values(2*(i-1)+1), &
                              Solver % Variable % Values(2*(i-1)+2)  )
     END DO
!------------------------------------------------------------------------------
!    Check the bndry conditions. For each node either flux or potential must be
!    given and the other is the unknown! After the loop a logical variable
!    PotentialKnown will be true if flux is the unknown and false if potential
!    is the unknown for each node. Also vector Load will contain the known value
!    for each node.
!------------------------------------------------------------------------------
     DO t=1,Solver % NumberOfActiveElements
        CurrentElement => Solver % Mesh % Elements( Solver % ActiveElements(t) )
        IF ( .NOT. ASSOCIATED( CurrentElement % BoundaryInfo ) ) CYCLE
        IF ( CurrentElement % Type % ElementCode == 101 ) CYCLE

        n = CurrentElement % Type % NumberOfNodes
        NodeIndexes => CurrentElement % NodeIndexes

        DO i=1,Model % NumberOfBCs
          IF ( CurrentElement % BoundaryInfo % Constraint /= Model % BCs(i) % Tag ) CYCLE

          
          P1(1:n) = ListGetReal( Model % BCs(i) % Values, &
               TRIM(Solver % Variable % Name)//' 1', n, NodeIndexes, GotIt )

          IF ( .NOT. GotIt ) THEN
             P1(1:n) = ListGetReal( Model % BCs(i) % Values, 'Potential 1' , n, NodeIndexes, GotIt )
          END IF

          P2(1:n) = ListGetReal( Model % BCs(i) % Values, &
               TRIM(Solver % Variable % Name)//' 2', n, NodeIndexes, GotIt )

          IF ( .NOT. GotIt ) THEN
             P2(1:n) = ListGetReal( Model % BCs(i) % Values, 'Potential 2' , n, NodeIndexes, GotIt )
          END IF

          Load( PotentialPerm(NodeIndexes) ) = DCMPLX( P1(1:n),P2(1:n) )

          IF ( .NOT. GotIt ) THEN
             PotentialKnown( PotentialPerm(NodeIndexes) ) = .FALSE.

             P1(1:n) = ListGetReal( Model % BCs(i) % Values, 'Flux 1', n, NodeIndexes, GotIt )
             P2(1:n) = ListGetReal( Model % BCs(i) % Values, 'Flux 2', n, NodeIndexes, GotIt )
             Load( PotentialPerm(NodeIndexes) ) = DCMPLX( P1(1:n),P2(1:n) )
          ELSE
             PotentialKnown( PotentialPerm(NodeIndexes) ) = .TRUE.
          END IF
          EXIT
        END DO
     END DO
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
!
!    Matrix assembly:
!    ----------------
     DO t=1,Solver % NumberOfActiveElements
        CurrentElement => Solver % Mesh % Elements( Solver % ActiveElements(t) )

        IF ( .NOT. ASSOCIATED( CurrentElement % BoundaryInfo ) ) CYCLE
        IF ( CurrentElement % Type % ElementCode == 101 ) CYCLE

        n = CurrentElement % Type % NumberOfNodes
        NodeIndexes => CurrentElement % NodeIndexes
 
        ElementNodes % x(1:n) = Solver % Mesh % Nodes % x( NodeIndexes )
        ElementNodes % y(1:n) = Solver % Mesh % Nodes % y( NodeIndexes )
        ElementNodes % z(1:n) = Solver % Mesh % Nodes % z( NodeIndexes )

        CALL IntegrateMatrix( Matrix, Diagonal, ForceVector, Load, &
             PotentialKnown, CurrentElement, n, ElementNodes )
     END DO

!------------------------------------------------------------------------------
     DO i=1,BoundaryNodes
        IF ( PotentialKnown(i) ) THEN
           ForceVector(i) = ForceVector(i) - Load(i)*Diagonal(i)
        ELSE
           Matrix(i,i) = Diagonal(i)
        END IF
     END DO

!------------------------------------------------------------------------------

     at = CPUTime() - at
     PRINT*,'Assembly (s): ',at

!------------------------------------------------------------------------------
!    Solve the system and we are done.
!------------------------------------------------------------------------------
     st = CPUTime()
!
!    Solve system:
!    -------------
     CALL SolveFull( BoundaryNodes, Matrix, Potential, ForceVector, Solver )
!
!    Extract potential and fluxes for the boundary nodes:
!    ----------------------------------------------------
     DO i=1,BoundaryNodes
        IF ( PotentialKnown(i) ) THEN
           Flx(i) = Potential(i)
           Pot(i) = Load(i)
        ELSE
           Flx(i) = Load(i)
           Pot(i) = Potential(i)
        END IF
     END DO
     st = CPUTime() - st
     PRINT*,'Solve (s):    ',st
!
     st = CPUTime()
!    Now compute potential for all mesh points:
!    ------------------------------------------
     Potential = 0.0d0
     DO i=1,BoundaryNodes
        Potential(BoundaryPerm(i)) = Pot(i)
     END DO

     DO t=1,Solver % NumberOfActiveElements
        CurrentElement => Solver % Mesh % Elements( Solver % ActiveElements(t) )
        IF ( .NOT. ASSOCIATED( CurrentElement % BoundaryInfo ) ) CYCLE

        IF ( CurrentElement % Type % ElementCode == 101 ) CYCLE

        n = CurrentElement % Type % NumberOfNodes
        NodeIndexes => CurrentElement % NodeIndexes

        ElementNodes % x(1:n) = Solver % Mesh % Nodes % x( NodeIndexes )
        ElementNodes % y(1:n) = Solver % Mesh % Nodes % y( NodeIndexes )
        ElementNodes % z(1:n) = Solver % Mesh % Nodes % z( NodeIndexes )

        CALL ComputePotential( Potential, Pot, Flx, CurrentElement, n, ElementNodes )
     END DO

     Solver % Variable % Values = 0.0d0
     DO i=1,Solver % Mesh % NumberOfNodes
        j = Solver % Variable % Perm(i)
        IF ( j > 0 ) THEN
           Solver % Variable % Values( 2*(j-1) + 1 ) =  REAL( Potential(i) )
           Solver % Variable % Values( 2*(j-1) + 2 ) = AIMAG( Potential(i) )
        END IF
     END DO

     Var => VariableGet( Solver % Mesh % Variables, 'Flux' )
     IF ( ASSOCIATED( Var ) ) THEN
        Var % Values = 0.0d0
        DO i=1,BoundaryNodes
           k = BoundaryPerm(i)
           Var % Values(2*(k-1)+1) =  REAL( Flx(i) )
           Var % Values(2*(k-1)+2) = AIMAG( Flx(i) )
        END DO
     END IF
!
!    All done, finalize:
!    -------------------
     Solver % Variable % Norm = SQRT( SUM( ABS(Potential)**2 ) ) / &
                Solver % Mesh % NumberOfNodes 

     CALL InvalidateVariable( Model % Meshes, &
                  Solver % Mesh, Solver % Variable % Name )
!------------------------------------------------------------------------------
     st = CPUTime() - st
     PRINT*,'Post Processing (s):    ',st
!------------------------------------------------------------------------------
 

   CONTAINS


!------------------------------------------------------------------------------
     SUBROUTINE IntegrateMatrix( STIFF, ADiagonal, Force, Source, &
                    PotentialKnown, Element, n, Nodes )
!------------------------------------------------------------------------------
       COMPLEX(KIND=dp) :: STIFF(:,:), ADiagonal(:)
       COMPLEX(KIND=dp) :: FORCE(:), Source(:)
       INTEGER :: n
       LOGICAL :: PotentialKnown(:)
       TYPE(Nodes_t) :: Nodes
       TYPE(Element_t), POINTER :: Element
!------------------------------------------------------------------------------
       REAL(KIND=dp) :: Basis(n),dBasisdx(n,3),ddBasisddx(n,3,3)
       REAL(KIND=dp) :: LX,LY,LZ,x,y,z
       LOGICAL :: Stat, CheckNormals
       COMPLEX(KIND=dp) :: R, dGdN, G, GradG(3), i
       REAL(KIND=dp) :: detJ,U,V,W,S,A,L,Normal(3),rad

       INTEGER :: j,k,p,q,t,dim
 
       TYPE(GaussIntegrationPoints_t) :: IntegStuff
!------------------------------------------------------------------------------
       dim = CoordinateSystemDimension()
!------------------------------------------------------------------------------
!      Numerical integration
!------------------------------------------------------------------------------
       i = DCMPLX( 0.0d0, 1.0d0 )

       SELECT CASE( Element % Type % ElementCode / 100 )
       CASE(2)
          IntegStuff = GaussPoints( Element,4 )
       CASE(3)
          IntegStuff = GaussPoints( Element,6 )
       CASE(4)
          IntegStuff = GaussPoints( Element,16 )
       END SELECT

       CheckNormals = ASSOCIATED( Element % BoundaryInfo )
       IF ( CheckNormals ) THEN
          CheckNormals = ASSOCIATED( Element % BoundaryInfo % Left  ) .OR. &
                         ASSOCIATED( Element % BoundaryInfo % Right )
       END IF

       DO t=1,IntegStuff % n
          U = IntegStuff % u(t)
          V = IntegStuff % v(t)
          W = IntegStuff % w(t)
          S = IntegStuff % s(t)
!------------------------------------------------------------------------------
!         Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
          stat = ElementInfo( Element, Nodes, U, V, W, detJ, &
                 Basis, dBasisdx, ddBasisddx, .FALSE. )
 
          S = S * detJ

          Normal = NormalVector( Element, Nodes, u,v, CheckNormals )

          LX = SUM( Nodes % x(1:n) * Basis )
          LY = SUM( Nodes % y(1:n) * Basis )
          LZ = SUM( Nodes % z(1:n) * Basis )

          DO p=1,BoundaryNodes
             k = BoundaryPerm(p)

             x = LX - Solver % Mesh % Nodes % x(k)
             y = LY - Solver % Mesh % Nodes % y(k)
             z = LZ - Solver % Mesh % Nodes % z(k)

             CALL Green( dim,AngularFrequency,x,y,z,G,GradG )
             dGdN = SUM( GradG * Normal )

             DO j=1,N
                q = PotentialPerm( Element % NodeIndexes(j) )

                IF ( PotentialKnown(q) ) THEN
                   IF ( p /= q ) THEN
                      FORCE(p) = FORCE(p) - s * Source(q) * Basis(j) * dGdN
                   END IF
                   STIFF(p,q) = STIFF(p,q) - s * Basis(j) * G
                ELSE
                   FORCE(p) = FORCE(p) + s * Source(q) * Basis(j) * G
                   IF ( p /= q ) THEN
                      STIFF(p,q) = STIFF(p,q) + s * Basis(j) * dGdN
                   END IF
                END IF

                R = -AngularFrequency * SIN( AngularFrequency*x ) * G * Normal(1)
                IF ( p /= q ) THEN
                   R = R - COS( AngularFrequency*x ) * dGdN
                END IF
                ADiagonal(p) = ADiagonal(p) - s * Basis(j)  * R
             END DO
          END DO
!------------------------------------------------------------------------------
       END DO
!------------------------------------------------------------------------------
     END SUBROUTINE IntegrateMatrix
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
     SUBROUTINE Green( dim,k,x,y,z,W,GradW )
!------------------------------------------------------------------------------
       IMPLICIT NONE
!------------------------------------------------------------------------------
       REAL(KIND=dp) :: x,y,z
       INTEGER :: dim
       REAL(KIND=dp) :: k
       COMPLEX(KIND=dp) :: W
       COMPLEX(KIND=dp), OPTIONAL :: GradW(:)
!------------------------------------------------------------------------------
       COMPLEX(KIND=dp) :: i,dWdR
       REAL(KIND=dp) :: r,J0,Y0,dJ0,dY0
!------------------------------------------------------------------------------
       R = SQRT( X**2 + Y**2 + Z**2 )
       i = DCMPLX( 0.0d0,1.0d0 )

       SELECT CASE(dim)
       CASE(2)
          CALL Bessel( k*R, j0, y0, dj0, dy0 )
          W = (J0 - i*Y0) / (i*4)
          dWdR = k * (dJ0 - i*dY0) / (i*4)

       CASE(3)
          W = EXP(-i*k*R) / (4*PI*R)
          dWdR = (-i*k - 1/R) * W
       END SELECT

       IF ( PRESENT(GradW) ) THEN
          GradW(1) = x * dWdR / R
          GradW(2) = y * dWdR / R
          GradW(3) = z * dWdR / R
       END IF
!------------------------------------------------------------------------------
     END SUBROUTINE Green
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
     SUBROUTINE Bessel( x, j0, y0, dj0, dy0 )
!------------------------------------------------------------------------------
       IMPLICIT NONE

       INTEGER, PARAMETER          :: maxrounds = 1000
       DOUBLE PRECISION, PARAMETER :: polylimit = 10.0d0
       DOUBLE PRECISION, PARAMETER :: accuracy  = 1.0d-8
       DOUBLE PRECISION, PARAMETER :: gamma = 0.577215664901532860606512090082D0

       INTEGER :: i, k
       REAL(KIND=dp) :: hk
       REAL(kind=dp) :: x, j0, y0, dj0, dy0, phi, res, p, f
       
       DOUBLE PRECISION :: A(7) = &
          (/ 0.79788456D0, -0.00000077D0, -0.00552740D0,  &
             0.00009512D0,  0.00137237D0, -0.00072805D0,  &
             0.00014476D0 /)

       DOUBLE PRECISION :: B(7) = &
          (/ -0.78539816D0, -0.04166397D0, -0.00003954D0, &
              0.00262573D0, -0.00054125D0, -0.00029333D0, &
              0.00013558D0 /)

       DOUBLE PRECISION :: C(7) = &
          (/ 0.79788456D0,  0.00000156D0, 0.01659667D0,   &
             0.00017105D0, -0.00249511D0, 0.00113653D0,   &
            -0.0020033D0 /)

       DOUBLE PRECISION :: D(7) = &
          (/ -2.35619449D0, 0.12499612D0, 0.00005650D0,   &
             -0.00637879D0, 0.00074348D0, 0.00079824D0,   &
             -0.00029166D0 /)

       IF ( ABS(x) > polylimit ) THEN
!         Use polynomials
!         ---------------
          P = x
          F = 0.0d0
          DO k=1,7 
             F = F + A(k)*(3/x)**(k-1.0d0)
             P = P + B(k)*(3/x)**(k-1.0d0)
          END DO
          
          j0 = F * COS(P) / SQRT(x)
          y0 = F * SIN(P) / SQRT(x)
          
          P = x
          F = 0.0d0
          DO k=1,7 
             F = F + C(k)*(3/x)**(k-1.0d0)
             P = P + D(k)*(3/x)**(k-1.0d0)
          END DO
          
          dj0 = -F * COS(P) / SQRT(x)
          dy0 = -F * SIN(P) / SQRT(x)
       ELSE
!         Use series
!         ----------
          j0 = 1.0d0
          y0 = 0.0d0
          
          dj0 = 0.0d0 ! = - j1
          dy0 = 0.0d0 ! = - y1
          
          hk = 0.0d0
          
          DO k = 1,maxrounds
             hk = hk + 1.0d0 / k
             
             res = 1.0d0
             DO i = 1,k
                res = res * ( x / (2.0d0 * i) )**2
             END DO
             
             j0 = j0 + (-1)**k * res
             y0 = y0 + (-1)**(k+1) * hk * res
             
             dj0 = dj0 + (-1)**k * k / (0.5d0 * x) * res
             dy0 = dy0 + (-1)**(k+1) * hk * k / (0.5d0 * x) * res
             
             IF ( ABS(k / (0.5d0 * x) * res) < accuracy ) EXIT
          END DO
          
          IF ( k >= maxrounds ) STOP 'Error in evaluating Bessel functions'

          y0 = y0 + ( LOG(0.5d0 * x) + gamma ) * j0
          y0 = y0 * 2.0d0 / PI
          
          dy0 = dy0 + (1.0d0 / x) * j0 + ( LOG(0.5d0 * x) + gamma ) * dj0
          dy0 = dy0 * 2.0d0 / PI
       END IF
!------------------------------------------------------------------------------       
     END SUBROUTINE Bessel
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
     SUBROUTINE ComputePotential( Potential, Pot, Flx, Element, n, Nodes )
!------------------------------------------------------------------------------
       COMPLEX(KIND=dp) :: Pot(:), Flx(:), Potential(:)
       INTEGER :: n
       TYPE(Nodes_t) :: Nodes
       TYPE(Element_t), POINTER :: Element
!------------------------------------------------------------------------------
       REAL(KIND=dp) :: Basis(n),dBasisdx(n,3),ddBasisddx(n,3,3)
       REAL(KIND=dp) :: LX,LY,LZ,x,y,z
       LOGICAL :: Stat, CheckNormals
       REAL(KIND=dp) :: detJ,U,V,W,S,A,L,Normal(3)

       COMPLEX(KIND=dp) :: dGdN, G, GradG(3)

       INTEGER :: i,j,k,p,q,t,dim
 
       TYPE(GaussIntegrationPoints_t) :: IntegStuff
!------------------------------------------------------------------------------
       dim = CoordinateSystemDimension()
!------------------------------------------------------------------------------
!      Numerical integration
!------------------------------------------------------------------------------
       SELECT CASE( Element % Type % ElementCode / 100 )
       CASE(2)
          IntegStuff = GaussPoints( Element,4 )
       CASE(3)
          IntegStuff = GaussPoints( Element,6 )
       CASE(4)
          IntegStuff = GaussPoints( Element,16 )
       END SELECT

       CheckNormals = ASSOCIATED( Element % BoundaryInfo )
       IF ( CheckNormals ) THEN
          CheckNormals = ASSOCIATED( Element % BoundaryInfo % Left  ) .OR. &
                         ASSOCIATED( Element % BoundaryInfo % Right )
       END IF

       DO t=1,IntegStuff % n
          U = IntegStuff % u(t)
          V = IntegStuff % v(t)
          W = IntegStuff % w(t)
          S = IntegStuff % s(t)
!------------------------------------------------------------------------------
!         Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
          stat = ElementInfo( Element, Nodes, U, V, W, detJ, &
                 Basis, dBasisdx, ddBasisddx, .FALSE. )

          S = S * detJ
          Normal = NormalVector( Element, Nodes, u,v, CheckNormals )

          LX = SUM( Nodes % x(1:n) * Basis )
          LY = SUM( Nodes % y(1:n) * Basis )
          LZ = SUM( Nodes % z(1:n) * Basis )

          DO i=1,Solver % Mesh % NumberOfNodes
             IF ( PotentialPerm(i) > 0 ) CYCLE
             IF ( Solver % Variable % Perm(i) <= 0 ) CYCLE

             x = LX - Solver % Mesh % Nodes % x(i)
             y = LY - Solver % Mesh % Nodes % y(i)
             z = LZ - Solver % Mesh % Nodes % z(i)

             CALL Green( dim,AngularFrequency,x,y,z,G,GradG )
             dGdN = SUM( GradG * Normal )

             DO j=1,n
                q = PotentialPerm( Element % NodeIndexes(j) )
                Potential(i) = Potential(i) - s * Basis(j) * &
                      ( Pot(q) * dGdN - Flx(q) * G )
             END DO
          END DO
!------------------------------------------------------------------------------
       END DO
!------------------------------------------------------------------------------
     END SUBROUTINE ComputePotential
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
     SUBROUTINE SolveFull( N,A,x,b,Solver )
!------------------------------------------------------------------------------
       TYPE(Solver_t) :: Solver
!------------------------------------------------------------------------------
       INTERFACE SolveLapack_cmplx
          SUBROUTINE SolveLapack_cmplx( N,A,x )
             INTEGER N
             DOUBLE COMPLEX a(n*n), x(n)
           END SUBROUTINE SolveLapack_cmplx
        END INTERFACE
!------------------------------------------------------------------------------
       INTEGER ::  N
 
       COMPLEX(KIND=dp) ::  A(n*n),x(n),b(n)
!------------------------------------------------------------------------------

       SELECT CASE( ListGetString( Solver % Values, 'Linear System Solver' ) )

       CASE( 'direct' )
          CALL SolveLapack_cmplx( N, A, b )
          x(1:n) = b(1:n)

       CASE( 'iterative' )
          CALL FullIterSolver( N, x, b, Solver )

       CASE DEFAULT
          CALL Fatal( 'SolveFull', 'Unknown solver type.' )

       END SELECT
!------------------------------------------------------------------------------
     END SUBROUTINE SolveFull
!------------------------------------------------------------------------------


#include "huti_fdefs.h"
!------------------------------------------------------------------------------
     SUBROUTINE FullIterSolver( N,x,b,SolverParam )
!------------------------------------------------------------------------------
       IMPLICIT NONE
!------------------------------------------------------------------------------
       TYPE(Solver_t) :: SolverParam
       INTEGER :: N
       COMPLEX(KIND=dp), DIMENSION(N) :: x,b
!------------------------------------------------------------------------------
       REAL(KIND=dp) :: dpar(50)

       INTEGER :: ipar(50),wsize
       REAL(KIND=dp), ALLOCATABLE :: Work(:,:)

       COMPLEX :: s

       EXTERNAL Matvec, Precond
       LOGICAL :: AbortNotConverged
!------------------------------------------------------------------------------
       ipar = 0; dpar = 0

       HUTI_WRKDIM = HUTI_BICGSTAB_WORKSIZE
       wsize = HUTI_WRKDIM
       HUTI_NDIM = N
       ALLOCATE( Work(wsize,2*N) )

       IF ( ALL(x == 0.0) ) THEN
          HUTI_INITIALX = HUTI_RANDOMX
       ELSE
          HUTI_INITIALX = HUTI_USERSUPPLIEDX
       END IF

       HUTI_TOLERANCE = ListGetConstReal( Solver % Values, &
            'Linear System Convergence Tolerance' )

       HUTI_MAXIT = ListGetInteger( Solver % Values, &
            'Linear System Max Iterations' )

       HUTI_DBUGLVL  = ListGetInteger( SolverParam % Values, &
            'Linear System Residual Output', GotIt )

       IF ( .NOT.Gotit ) HUTI_DBUGLVL = 1

       AbortNotConverged = ListGetLogical( SolverParam % Values, &
            'Linear System Abort Not Converged', GotIt )
       IF ( .NOT. GotIt ) AbortNotConverged = .TRUE.

!------------------------------------------------------------------------------
       CALL HUTI_Z_BICGSTAB( x,b,ipar,dpar,work,matvec,Precond,0,0,0,0 )
!------------------------------------------------------------------------------

       DEALLOCATE( Work )

       IF ( HUTI_INFO /= HUTI_CONVERGENCE ) THEN
          IF ( AbortNotConverged ) THEN
             CALL Fatal( 'IterSolve', 'Failed convergence tolerances.' )
          ELSE
             CALL Error( 'IterSolve', 'Failed convergence tolerances.' )
          END IF
       END IF
!------------------------------------------------------------------------------
     END SUBROUTINE FullIterSolver 
!------------------------------------------------------------------------------
!------------------------------------------------------------------------------
   END SUBROUTINE HelmholtzBEMSolver
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE Precond( u,v,ipar )
!------------------------------------------------------------------------------
     USE GlobMat
!------------------------------------------------------------------------------
     COMPLEX(KIND=dp) :: u(*),v(*)
     INTEGER :: ipar(*)
!------------------------------------------------------------------------------
     DO i=1,HUTI_NDIM
        u(i) = v(i) / Matrix(i,i)
     END DO
!------------------------------------------------------------------------------
   END SUBROUTINE Precond
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   SUBROUTINE Matvec( u,v,ipar )
!------------------------------------------------------------------------------
      USE GlobMat
!------------------------------------------------------------------------------
      COMPLEX(KIND=dp) :: u(*),v(*)
      INTEGER :: ipar(*)
!------------------------------------------------------------------------------
      v(1:HUTI_NDIM) = MATMUL( Matrix, u(1:HUTI_NDIM) )

!     DO i=1,HUTI_NDIM
!        v(i) = ( 0.0d0, 0.0d0 )
!        DO j=1,HUTI_NDIM
!           v(i) = v(i) + Matrix(i,j) * u(j)
!        END DO
!     END DO
!------------------------------------------------------------------------------
   END SUBROUTINE Matvec
!------------------------------------------------------------------------------
