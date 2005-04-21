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
! *****************************************************************************
! *
! *                    Author:       Juha Ruokolainen
! *
! *                 Address: Center for Scientific Computing
! *                        Tietotie 6, P.O. BOX 405
! *                          02101 Espoo, Finland
! *                          Tel. +358 0 457 2723
! *                        Telefax: +358 0 457 2302
! *                      EMail: Juha.Ruokolainen@csc.fi
! *
! *                       Date: 04 Oct 2000
! *
! *                Modified by:
! *
! *       Date of modification:
! *
! ****************************************************************************/

!------------------------------------------------------------------------------
SUBROUTINE HelmholtzSolver( Model,Solver,dt,TransientSimulation )
  !DEC$ATTRIBUTES DLLEXPORT :: HelmholtzSolver
!------------------------------------------------------------------------------
!******************************************************************************
!
!  Solve the Helmholtz equation!
!
!  ARGUMENTS:
!
!  TYPE(Model_t) :: Model,  
!     INPUT: All model information (mesh, materials, BCs, etc...)
!
!  TYPE(Solver_t) :: Solver
!     INPUT: Linear & nonlinear equation solver options
!
!  REAL(KIND=dp) :: dt,
!     INPUT: Timestep size for time dependent simulations
!
!  LOGICAL :: TransientSimulation
!     INPUT: Steady state or transient simulation
!
! $Log: HelmholtzSolve.f90,v $
! Revision 1.53  2005/04/19 08:53:46  jpr
! Renamed module LUDecomposition as LinearAlgebra.
!
! Revision 1.52  2005/04/04 06:18:28  jpr
! *** empty log message ***
!
!
! Revision 1.48  2004/03/30 12:02:45  jpr
! Changes due to changed interface for complex system in DefUtils.
!
! Revision 1.47  2004/03/05 12:28:04  jpr
! Trying to figure out frequency at the start of the execution, even if
! given in equation section. Writes the frequency of the domain of the
! first active element to stdout.
!
! Revision 1.46  2004/03/03 11:27:12  jpr
! Started log.
!
!
!******************************************************************************
  USE DefUtils
  IMPLICIT NONE
!------------------------------------------------------------------------------
  TYPE(Solver_t) :: Solver
  TYPE(Model_t) :: Model

  REAL(KIND=dp) :: dt
  LOGICAL :: TransientSimulation
!------------------------------------------------------------------------------
! Local variables
!------------------------------------------------------------------------------
  TYPE(Element_t),POINTER :: Element

  LOGICAL :: AllocationsDone = .FALSE., Bubbles, Found

  INTEGER :: iter, i, j, k, n, t, istat, eq, LocalNodes
  REAL(KIND=dp) :: Norm, PrevNorm, RelativeChange, AngularFrequency

  TYPE(ValueList_t), POINTER :: Equation, Material, BodyForce, &
             BC, SolverParams, Simulation

  INTEGER :: NonlinearIter
  REAL(KIND=dp) :: NonlinearTol,s

  REAL(KIND=dp), ALLOCATABLE :: Load(:,:), Work(:), &
       SoundSpeed(:), Damping(:), Impedance(:,:), ConvVelo(:,:)

  COMPLEX(KIND=dp), ALLOCATABLE :: STIFF(:,:), FORCE(:)

  SAVE STIFF, Work, Load, FORCE, &
       SoundSpeed, Damping, Impedance, AllocationsDone, ConvVelo

  REAL(KIND=dp) :: at,at0,totat,st,totst,t1,CPUTime,RealTime
!------------------------------------------------------------------------------
     CHARACTER(LEN=MAX_NAME_LEN) :: VersionID = "$Id: HelmholtzSolve.f90,v 1.53 2005/04/19 08:53:46 jpr Exp $"

!------------------------------------------------------------------------------
!    Check if version number output is requested
!------------------------------------------------------------------------------
     IF ( .NOT. AllocationsDone ) THEN
        IF ( ListGetLogical( GetSimulation(), 'Output Version Numbers', Found ) ) THEN
           CALL Info( 'HelmholtzSolve', 'HelmholtzSolver version:', Level = 0 ) 
           CALL Info( 'HelmholtzSolve', VersionID, Level = 0 ) 
           CALL Info( 'HelmholtzSolve', ' ', Level = 0 ) 
        END IF
     END IF


!------------------------------------------------------------------------------
! Allocate some permanent storage, this is done first time only
!------------------------------------------------------------------------------
  IF ( .NOT. AllocationsDone .OR. Solver % Mesh % Changed ) THEN
     N = Solver % Mesh % MaxElementNodes

     IF ( AllocationsDone ) THEN
        DEALLOCATE(            &
             Impedance,        &
             Work,             &
             FORCE,  STIFF,    &
             SoundSpeed, ConvVelo, Damping, Load )
     END IF

     ALLOCATE( &
          Impedance( 2,N ),    &
          Work( N ),           &
          FORCE( 2*N ),        &
          STIFF( 2*N,2*N ),    &
          SoundSpeed( N ), ConvVelo(3,N), Damping( N ), Load( 2,N ), STAT=istat )

     IF ( istat /= 0 ) THEN
        CALL Fatal( 'HelmholzSolve', 'Memory allocation error.' )
     END IF

     AllocationsDone = .TRUE.
  END IF
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
! Do some additional initialization, and go for it
!------------------------------------------------------------------------------
  SolverParams => GetSolverParams()
  NonlinearTol = GetConstReal( SolverParams, &
       'Nonlinear System Convergence Tolerance', Found )

  NonlinearIter = GetInteger( SolverParams, &
       'Nonlinear System Max Iterations', Found )

  IF ( .NOT.Found ) NonlinearIter = 1
  Bubbles = GetLogical( SolverParams, 'Bubbles', Found )
!
! Figure out angular frequency:
!------------------------------
  AngularFrequency = 0.0d0

  Element => GetActiveElement(1)
  n = GetElementNOFNodes()
  Simulation => GetSimulation()
  Work(1:n) = GetReal( Simulation, 'Angular Frequency', Found )

  IF ( Found ) THEN
     AngularFrequency = Work(1)
  ELSE
     Work(1:n) = GetReal( GetSimulation(), 'Frequency', Found )
     IF ( Found ) THEN
        AngularFrequency = 2*PI*Work(1)
     ELSE
        Work(1:n) = GetReal( GetEquation(), 'Angular Frequency', Found )
        IF (  Found ) THEN
           AngularFrequency = Work(1)
        ELSE
           Work(1:n) = GetReal( GetEquation(), 'Frequency', Found )
           AngularFrequency = 2*PI*Work(1)
        END IF
     END IF
  END IF

  Solver % Matrix % Complex = .TRUE.

!------------------------------------------------------------------------------
! Iterate over any nonlinearity of material or source
!------------------------------------------------------------------------------
  Norm = Solver % Variable % Norm
  totat = 0.0d0
  totst = 0.0d0

  DO iter=1,NonlinearIter
!------------------------------------------------------------------------------
     at  = CPUTime()
     at0 = RealTime()

     CALL Info( 'HelmholtzSolve', ' ', Level=4 )
     CALL Info( 'HelmholtzSolve', '-------------------------------------', Level=4 )
     WRITE( Message, * ) 'Helmholtz iteration', iter
     CALL Info( 'HelmholtzSolve', Message, Level=4 )
     WRITE( Message, * ) 'Frequency (Hz): ', AngularFrequency/(2*PI)
     CALL Info( 'HelmholtzSolve', Message, Level=4 )
     CALL Info( 'HelmholtzSolve', '-------------------------------------', Level=4 )
     CALL Info( 'HelmholtzSolve', ' ', Level=4 )
     CALL Info( 'HelmholtzSolve', 'Starting Assembly', Level=4 )

     CALL DefaultInitialize()
!
!    Do the bulk assembly:
!    ---------------------

!------------------------------------------------------------------------------
     DO t=1,Solver % NumberOfActiveElements
!------------------------------------------------------------------------------
        IF ( RealTime() - at0 > 1.0 ) THEN
          WRITE(Message,'(a,i3,a)' ) '   Assembly: ', INT(100.0 - 100.0 * &
           (Solver % NumberOfActiveElements-t) / &
              (1.0*Solver % NumberOfActiveElements)), ' % done'
          CALL Info( 'HelmholtzSolve', Message, Level=5 )
                      
          at0 = RealTime()
        END IF
!------------------------------------------------------------------------------
        Element => GetActiveElement(t)
        n = GetElementNOFNodes()

!       Get equation & material parameters:
!       -----------------------------------
        Equation => GetEquation()
        Work(1:n) = GetReal( Equation, 'Angular Frequency', Found )
        IF ( Found ) THEN
           AngularFrequency = Work(1)
        ELSE
           Work(1:n) = GetReal(  Equation, 'Frequency', Found )
           Work(1:n) = 2 * PI * Work(1:n)
        END IF

        Material => GetMaterial()
        Damping(1:n)    = GetReal( Material, 'Sound Damping', Found )
        SoundSpeed(1:n) = GetReal( Material, 'Sound Speed', Found )
        ConvVelo(1,1:n) = GetReal( Material, 'Convection Velocity 1', Found )
        ConvVelo(2,1:n) = GetReal( Material, 'Convection Velocity 2', Found )
        ConvVelo(3,1:n) = GetReal( Material, 'Convection Velocity 3', Found )

!       The source term on nodes:
!       -------------------------
        BodyForce => GetBodyForce()
        Load(1,1:n) = GetReal( BodyForce, 'Pressure Source 1', Found )
        Load(2,1:n) = GetReal( BodyForce, 'Pressure Source 2', Found )

!       Get element local matrix and rhs vector:
!       ----------------------------------------
        CALL LocalMatrix(  STIFF, FORCE, AngularFrequency, &
           SoundSpeed, ConvVelo, Damping, Load, Bubbles, Element, n )

!       Update global matrix and rhs vector from local matrix & vector:
!       ---------------------------------------------------------------
        CALL DefaultUpdateEquations( STIFF, FORCE )
     END DO
!------------------------------------------------------------------------------
!
!    Neumann & Newton BCs:
!    ---------------------
     DO t=1, Solver % Mesh % NumberOfBoundaryElements
        Element => GetBoundaryElement(t)
        IF ( .NOT.ActiveBoundaryElement() ) CYCLE

        n = GetElementNOFNodes()
        IF ( GetElementFamily() == 1 ) CYCLE

        BC => GetBC()
        IF ( ASSOCIATED( BC ) ) THEN
          Load(1,1:n) = GetReal( BC, 'Wave Flux 1', Found )
          Load(2,1:n) = GetReal( BC, 'Wave Flux 2', Found )
          Impedance(1,1:n) = GetReal( BC, 'Wave Impedance 1', Found )
          Impedance(2,1:n) = GetReal( BC, 'Wave Impedance 2', Found )

          CALL LocalMatrixBoundary(  STIFF, FORCE, AngularFrequency, &
                  Impedance, Load, Element, n, ConvVelo )

          CALL DefaultUpdateEquations( STIFF, FORCE )
        END IF
     END DO
!------------------------------------------------------------------------------

     CALL DefaultFinishAssembly()
     CALL DefaultDirichletBCs()

     CALL Info( 'HelmholtzSolve', 'Assembly done', Level=4 )
!
!    Solve the system and we are done:
!    ---------------------------------
     at = CPUTime() - at
     st = CPUTime()
     PrevNorm = Norm
     Norm = DefaultSolve()

     st = CPUTIme()-st
     totat = totat + at
     totst = totst + st
     WRITE( Message, '(a,i4,a,F8.2,F8.2)') 'iter: ',iter,' Assembly: (s)', at, totat
     CALL Info( 'HelmholtzSolve', Message, Level=4 )
     WRITE( Message, '(a,i4,a,F8.2,F8.2)') 'iter: ',iter,' Solve:    (s)', st, totst
     CALL Info( 'HelmholtzSolve', Message, Level=4 )

!------------------------------------------------------------------------------
     IF ( PrevNorm + Norm /= 0.0d0 ) THEN
        RelativeChange = 2*ABS(PrevNorm - Norm) / (PrevNorm + Norm)
     ELSE
        RelativeChange = 0.0d0
     END IF

     CALL Info( 'HelmholtzSolve', ' ', Level=4 )
     WRITE( Message, * ) 'Result Norm    : ',Norm
     CALL Info( 'HelmholtzSolve', Message, Level=4 )
     WRITE( Message, * ) 'Relative Change: ',RelativeChange
     CALL Info( 'HelmholtzSolve', Message, Level=4 )

     IF ( RelativeChange < NonlinearTol ) EXIT
!------------------------------------------------------------------------------
  END DO ! of nonlinear iteration
!------------------------------------------------------------------------------


CONTAINS


!------------------------------------------------------------------------------
  SUBROUTINE LocalMatrix(  STIFF, FORCE, AngularFrequency, SoundSpeed, &
       ConvVelo, Damping, Load, Bubbles, Element, n )
!------------------------------------------------------------------------------
    REAL(KIND=dp) ::  AngularFrequency, &
         SoundSpeed(:), Damping(:), Load(:,:), ConvVelo(:,:)
    COMPLEX(KIND=dp) :: STIFF(:,:), FORCE(:)
    LOGICAL :: Bubbles
    INTEGER :: n
    TYPE(Element_t), POINTER :: Element
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: Basis(2*n),dBasisdx(2*n,3),ddBasisddx(n,3,3)
    REAL(KIND=dp) :: SqrtElementMetric,U,V,W,S,WaveNumber,M,D,L1,L2
    REAL(KIND=dp) :: DiffCoef(3,3), Velo(3)
    COMPLEX(KIND=dp) :: A, ConvCoef
    LOGICAL :: Stat
    INTEGER :: i,p,q,t,dim, NBasis, CoordSys
    TYPE(GaussIntegrationPoints_t) :: IntegStuff
    REAL(KIND=dp) :: X,Y,Z,Metric(3,3),SqrtMetric,Symb(3,3,3),dSymb(3,3,3,3)

    TYPE(Nodes_t) :: Nodes
    SAVE Nodes
!------------------------------------------------------------------------------
    dim = CoordinateSystemDimension()
    CoordSys = CurrentCoordinateSystem()

    Metric = 0.0d0
    Metric(1,1) = 1.0d0
    Metric(2,2) = 1.0d0
    Metric(3,3) = 1.0d0

    STIFF = 0.0d0
    FORCE = 0.0d0
!------------------------------------------------------------------------------
!   Numerical integration
!------------------------------------------------------------------------------
    CALL GetElementNodes( Nodes )

    IF ( Bubbles ) THEN
       IntegStuff = GaussPoints( Element, Element % TYPE % GaussPoints2 )
       NBasis = 2*n
    ELSE
       NBasis = n
       IntegStuff = GaussPoints( Element )
    END IF
!------------------------------------------------------------------------------
    DO t=1,IntegStuff % n
       U = IntegStuff % u(t)
       V = IntegStuff % v(t)
       W = IntegStuff % w(t)
       S = IntegStuff % s(t)
!------------------------------------------------------------------------------
!      Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
       stat = ElementInfo( Element, Nodes, U, V, W, SqrtElementMetric, &
            Basis, dBasisdx, ddBasisddx, .FALSE., Bubbles )

       s = s * SqrtElementMetric
       IF ( CoordSys /= Cartesian ) THEN
          X = SUM( Nodes % X(1:n) * Basis(1:n) )
          Y = SUM( Nodes % Y(1:n) * Basis(1:n) )
          Z = SUM( Nodes % Z(1:n) * Basis(1:n) )
          CALL CoordinateSystemInfo( Metric,SqrtMetric,Symb,dSymb,X,Y,Z )
          s = s * SqrtMetric
       END IF
!------------------------------------------------------------------------------
!      The source term and the coefficient of the time derivative and 
!      diffusion terms at the integration point
!------------------------------------------------------------------------------
       WaveNumber = AngularFrequency / SUM( SoundSpeed(1:n) * Basis(1:n) )

       D  =  WaveNumber * SUM( Damping(1:n) * Basis(1:n) )
       M  = -WaveNumber**2

       L1 = SUM( Load(1,1:n) * Basis(1:n) )
       L2 = SUM( Load(2,1:n) * Basis(1:n) )

!      Scaled convection velocity
!      --------------------------
       Velo(1) = SUM( ConvVelo(1,1:n) * Basis(1:n) )
       Velo(2) = SUM( ConvVelo(2,1:n) * Basis(1:n) )
       Velo(3) = SUM( ConvVelo(3,1:n) * Basis(1:n) )
       Velo = Velo / SUM( SoundSpeed(1:n) * Basis(1:n) )

!      Diffusion and convection coefficients
!      -------------------------------------
       DO i = 1,dim
          DO j = 1,dim
             DiffCoef(i,j) = - Velo(i)*Velo(j)
          END DO
          DiffCoef(i,i) = DiffCoef(i,i) + 1.0D0
       END DO
       ConvCoef = 2.0D0 * SQRT((-1.0D0,0.0D0)) * WaveNumber

!      Stiffness matrix and load vector
!      --------------------------------
       DO p=1,NBasis
          DO q=1,NBasis
             A = DCMPLX( M, D ) * Basis(q) * Basis(p)
             DO i=1,dim
                A = A + ConvCoef * Velo(i) * dBasisdx(q,i) * Basis(p)
                DO j=1,dim
                   DO k = 1,dim
                      A = A + Metric(i,j) * DiffCoef(i,k) * dBasisdx(q,k) * dBasisdx(p,j)
                   END DO
                END DO
             END DO
             STIFF(p,q) = STIFF(p,q) + s*A
          END DO
          FORCE(p) = FORCE(p) + s * Basis(p) * DCMPLX( L1,L2 )
       END DO
    END DO
!------------------------------------------------------------------------------

    IF ( Bubbles ) THEN
       CALL LCondensate( n,STIFF,FORCE )
    END IF
!------------------------------------------------------------------------------
  END SUBROUTINE LocalMatrix
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE LocalMatrixBoundary(  STIFF, FORCE, AngularFrequency, &
              Impedance, Load, Element, n, ConvVelo )
!------------------------------------------------------------------------------
    COMPLEX(KIND=dp) :: STIFF(:,:), FORCE(:)
    REAL(KIND=dp) :: Impedance(:,:),Load(:,:)
    REAL(KIND=dp) :: AngularFrequency, ConvVelo(:,:)
    INTEGER :: n
    TYPE(Element_t), POINTER :: Element
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: SqrtElementMetric,U,V,W,S,Impedance1,Impedance2,L1,L2
    REAL(KIND=dp) :: Basis(n),dBasisdx(n,3),ddBasisddx(n,3,3),X,Y,Z
    REAL(KIND=dp) :: Normal(3), Velo(3), NormVelo, TangVelo(3)
    COMPLEX(KIND=dp) :: A, Admittance
    LOGICAL :: Stat
    INTEGER :: i,p,q,t,dim,CoordSys
    TYPE(GaussIntegrationPoints_t) :: IntegStuff

    TYPE(Nodes_t) :: Nodes
    SAVE Nodes
!------------------------------------------------------------------------------
    dim = CoordinateSystemDimension()
    CoordSys = CurrentCoordinateSystem()

    STIFF = 0.0d0
    FORCE = 0.0d0
!------------------------------------------------------------------------------
!   Numerical integration
!------------------------------------------------------------------------------
    CALL GetElementNodes( Nodes )
    IntegStuff = GaussPoints( Element )
!------------------------------------------------------------------------------
    DO t=1,IntegStuff % n
       U = IntegStuff % u(t)
       V = IntegStuff % v(t)
       W = IntegStuff % w(t)
       S = IntegStuff % s(t)
!------------------------------------------------------------------------------
!      Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
       stat = ElementInfo( Element, Nodes, U, V, W, SqrtElementMetric, &
              Basis, dBasisdx, ddBasisddx, .FALSE., .FALSE. )

       s = s * SqrtElementMetric

       Normal = Normalvector(Element, Nodes, U, V, .TRUE.)

       Impedance1 = SUM( Impedance(1,1:n) * Basis(1:n) )
       Impedance2 = SUM( Impedance(2,1:n) * Basis(1:n) ) 
       IF ( ABS(Impedance1) < AEPS .AND. ABS(Impedance2) < AEPS) THEN
         Admittance = DCMPLX(0.0d0,0.0d0)
       ELSE         
         Admittance = AngularFrequency / DCMPLX(Impedance1, Impedance2)
       END IF

!      Scaled convection velocity
!      --------------------------
       Velo(1) = SUM( ConvVelo(1,1:n) * Basis(1:n) )
       Velo(2) = SUM( ConvVelo(2,1:n) * Basis(1:n) )
       Velo(3) = SUM( ConvVelo(3,1:n) * Basis(1:n) )
       Velo = Velo / SUM( SoundSpeed(1:n) * Basis(1:n) )
       NormVelo = SUM( Normal(1:dim) * Velo(1:dim) )
       TangVelo = Velo - Normal * NormVelo

!------------------------------------------------------------------------------
       L1 = SUM( Load(1,1:n) * Basis )
       L2 = SUM( Load(2,1:n) * Basis )
!------------------------------------------------------------------------------
       DO p=1,n
          DO q=1,n
             A = (1.0d0-NormVelo) * Admittance * Basis(q)*Basis(p)
             A = A + SUM( TangVelo(1:dim) * dBasisdx(q,1:dim) ) * Basis(p)
             STIFF(p,q) = STIFF(p,q) + s * A
          END DO
          FORCE(p) = FORCE(p) + s * Basis(p) * DCMPLX(L1,L2) 
       END DO
!------------------------------------------------------------------------------
    END DO
!------------------------------------------------------------------------------
  END SUBROUTINE LocalMatrixBoundary
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE LCondensate( n, K, F )
!------------------------------------------------------------------------------
    USE LinearAlgebra
!------------------------------------------------------------------------------
    INTEGER :: n
    COMPLEX(KIND=dp) :: K(:,:), F(:), Kbb(n,n), &
         Kbl(n,n), Klb(n,n), Fb(n)

    INTEGER :: i, Ldofs(n), Bdofs(n)

    Ldofs = (/ (i, i=1,n) /)
    Bdofs = Ldofs + n

    Kbb = K(Bdofs,Bdofs)
    Kbl = K(Bdofs,Ldofs)
    Klb = K(Ldofs,Bdofs)
    Fb  = F(Bdofs)

    CALL ComplexInvertMatrix( Kbb,n )
    F(1:n) = F(1:n) - MATMUL( Klb, MATMUL( Kbb, Fb  ) )
    K(1:n,1:n) = &
         K(1:n,1:n) - MATMUL( Klb, MATMUL( Kbb, Kbl ) )
!------------------------------------------------------------------------------
  END SUBROUTINE LCondensate
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
END SUBROUTINE HelmholtzSolver
!------------------------------------------------------------------------------
