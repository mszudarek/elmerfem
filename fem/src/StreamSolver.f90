SUBROUTINE StreamSolver( Model,Solver,dt,TransientSimulation )
!DEC$ATTRIBUTES DLLEXPORT :: StreamSolver
!------------------------------------------------------------------------------
!******************************************************************************
!
!  Solve the StreamFunction of the flow field.
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
  TYPE(Matrix_t), POINTER  :: StiffMatrix
  TYPE(Variable_t), POINTER :: FlowSol
  TYPE(Element_t), POINTER :: CurrentElement

  CHARACTER(LEN=MAX_NAME_LEN) :: FlowVariableName

  REAL(KIND=dp), POINTER :: StreamFunction(:), FlowSolValues(:)
  REAL(KIND=dp), ALLOCATABLE :: STIFF(:,:), LOAD(:), FORCE(:)
  REAL(KIND=dp) :: Norm

  INTEGER, POINTER :: NodeIndexes(:), Perm(:), FlowSolPerm(:)
  INTEGER :: k, t, i, n, istat, NSDOFs, FirstNode

  TYPE(ValueList_t), POINTER :: SolverParams

  LOGICAL :: AllocationsDone = .FALSE., Found, Shifting, Scaling, StokesStream

  SAVE STIFF, FORCE, LOAD, AllocationsDone

  CALL Info('StreamSolver',' ')
  CALL Info('StreamSolver','----------------------------')
  CALL Info('StreamSolver','STREAMSOLVER')
  CALL Info('StreamSolver','----------------------------')
  CALL Info('StreamSolver',' ')

!------------------------------------------------------------------------------
! Get variables needed for solution
!------------------------------------------------------------------------------
  IF ( .NOT.ASSOCIATED( Solver % Matrix ) ) RETURN

  StreamFunction => Solver % Variable % Values
  Perm => Solver % Variable % Perm

  StiffMatrix => Solver % Matrix
!------------------------------------------------------------------------------
! Get initial values ( Default is FlowSolvers 'Flow Solution' )
!------------------------------------------------------------------------------
  SolverParams => GetSolverParams()
  FlowVariableName = GetString( SolverParams, &
     'Stream Function Velocity Variable', Found )
  IF ( .NOT. Found ) THEN
     CALL Info( 'StreamSolver', 'Stream Function Velocity Variable set to Flow Solution' )
     FlowVariableName = 'Flow Solution'
  END IF

  FlowSol => VariableGet( Solver % Mesh % Variables, FlowVariableName )
  IF ( ASSOCIATED( FlowSol ) ) THEN
     FlowSolPerm => FlowSol % Perm
     FlowSolValues => FlowSol % Values
     NSDOFs = FlowSol % DOFs
  ELSE
     CALL Warn( 'StreamSolver', 'No variable for velocity associated.' )
     CALL Warn( 'StreamSolver', 'Quitting execution of StreamSolver.' ) 
     RETURN
  END IF

!------------------------------------------------------------------------------
! Get keyword values
!------------------------------------------------------------------------------
  FirstNode = GetInteger( SolverParams, 'Stream Function First Node', Found )
  IF ( .NOT. Found ) THEN
     CALL Info( 'StreamSolver', 'Stream Function First Node set to 1.' )
     FirstNode = 1
  END IF

  IF ( FirstNode < 1 ) THEN
     CALL Warn( 'StreamSolver', 'Given Stream Function First Node is non-positive.' )
     CALL Info( 'StreamSolver', 'Stream Function First Node set to 1.' )
     FirstNode = 1
  END IF

  n = Solver % Mesh % NumberOfNodes
  IF ( FirstNode > n ) THEN
     CALL Warn( 'StreamSolver', 'Given Stream Function First Node is too big.' )
     WRITE( Message, *) 'Stream Function First Node set to ', n
     CALL Info( 'StreamSolver', Message )
     FirstNode = n
  END IF

  Shifting = GetLogical( SolverParams, 'Stream Function Shifting', Found )
  IF ( .NOT. Found ) THEN
     CALL Info( 'StreamSolver', 'Stream Function Shifting set to .TRUE.' )
     Shifting = .TRUE.
  END IF

  Scaling = GetLogical( SolverParams, 'Stream Function Scaling', Found )
  IF ( .NOT. Found ) THEN
     CALL Info( 'StreamSolver', 'Stream Function Scaling set to .FALSE.' )
     Scaling = .FALSE.
  END IF

  StokesStream = GetLogical( SolverParams, 'Stokes Stream Function', Found )
  IF ( .NOT. Found ) THEN
     IF ( CurrentCoordinateSystem() == AxisSymmetric ) THEN
        CALL Info( 'StreamSolver', 'Stokes Stream Function set to .TRUE.' )
        StokesStream = .TRUE.
     ELSE
        CALL Info( 'StreamSolver', 'Stokes Stream Function set to .FALSE.' )
        StokesStream = .FALSE.
     END IF
  END IF

  IF ( CurrentCoordinateSystem() == AxisSymmetric .AND. .NOT. StokesStream ) THEN
     CALL Warn( 'StreamSolver', 'Using normal stream function in axis symmetric case.' )
  ELSE IF ( CurrentCoordinateSystem() == Cartesian .AND. StokesStream ) THEN
     CALL Warn( 'StreamSolver', 'Using Stokes stream function in cartesian case.' )
  END IF
  
!------------------------------------------------------------------------------
! Allocate some permanent storage, this is done first time only
!------------------------------------------------------------------------------
  IF ( .NOT. AllocationsDone ) THEN
     N = Solver % Mesh % MaxElementNodes ! just big enough for elemental arrays

     ALLOCATE( FORCE( N ),   LOAD( 2*N ), STIFF(N,N), STAT=istat ) 

     IF ( istat /= 0 ) CALL Fatal( 'PoissonSolve', 'Memory allocation error.' )
     AllocationsDone = .TRUE.
  END IF
!------------------------------------------------------------------------------
! Initialize the system and do the assembly
!------------------------------------------------------------------------------
  CALL DefaultInitialize()
  
  DO t=1,Solver % NumberOfActiveElements
     CurrentElement => GetActiveElement(t)
     n = GetElementNOFNodes()
     NodeIndexes => CurrentElement % NodeIndexes
!------------------------------------------------------------------------------
     LOAD = 0.0d0
     DO i = 1,n
        k = FlowSolPerm( NodeIndexes(i) )
        k = (k-1) * NSDOFs
        LOAD( (i-1)*2 +1 ) = -FlowSolValues( k+2 )
        LOAD( (i-1)*2 +2 ) =  FlowSolValues( k+1 )
     END DO
!------------------------------------------------------------------------------
!     Get element local matrix and rhs vector
!------------------------------------------------------------------------------
     CALL LocalMatrix(  STIFF, FORCE, LOAD, CurrentElement, n, StokesStream )
!------------------------------------------------------------------------------
!     Update global matrix and rhs vector from local matrix & vector
!------------------------------------------------------------------------------
      CALL DefaultUpdateEquations( STIFF, FORCE )
   END DO! <- elements
!------------------------------------------------------------------------------
   CALL DefaultFinishAssembly()
!------------------------------------------------------------------------------
!  Zero the row corresponding to the 'FirstNode':
!------------------------------------------------------------------------------
   k = Solver % Variable % Perm( FirstNode )
   CALL ZeroRow( StiffMatrix, k )
   CALL SetMatrixElement( StiffMatrix, k, k, MAXVAL(StiffMatrix % Values) )
   StiffMatrix % RHS(k) = MAXVAL( StiffMatrix % RHS )
!------------------------------------------------------------------------------
!  Solve the system:
!------------------------------------------------------------------------------
   Norm = DefaultSolve()
!------------------------------------------------------------------------------
! Do Shifting and Scaling if needed
!------------------------------------------------------------------------------

  IF ( Shifting ) THEN
     StreamFunction = StreamFunction - MINVAL( StreamFunction )
  END IF

  IF ( Scaling ) THEN
     IF ( MAXVAL( ABS( StreamFunction ) ) < AEPS ) THEN
        CALL Warn( 'StreamSolver', &
             'Maximum absolut value smaller than machine epsilon; cannot scale.' )
     ELSE
        StreamFunction = StreamFunction / MAXVAL( ABS( StreamFunction ) )
     END IF
  END IF
!------------------------------------------------------------------------------

CONTAINS

!------------------------------------------------------------------------------
  SUBROUTINE LocalMatrix(  STIFF, FORCE, LOAD, Element, n,StokesStream )
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: STIFF(:,:), FORCE(:), LOAD(:)
    INTEGER :: n
    TYPE(Element_t), POINTER :: Element
    LOGICAL :: StokesStream
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: Basis(n), dBasisdx(n,3), ddBasisddx(n,3,3), LoadAtIp(2)
    REAL(KIND=dp) :: DetJ, U, V, W, S, Radius
    LOGICAL :: Stat
    INTEGER :: t, p, q, dim, NBasis, k
    TYPE(GaussIntegrationPoints_t) :: IntegStuff
    TYPE(Nodes_t) :: Nodes
    SAVE Nodes
!------------------------------------------------------------------------------
    dim = CoordinateSystemDimension()
    STIFF  = 0.0d0
    FORCE  = 0.0d0
    CALL GetElementNodes( Nodes )
!------------------------------------------------------------------------------
!   Numerical integration
!------------------------------------------------------------------------------
    NBasis = n
    IntegStuff = GaussPoints( Element )

    DO t=1,IntegStuff % n
       U = IntegStuff % u(t)
       V = IntegStuff % v(t)
       W = IntegStuff % w(t)
       S = IntegStuff % s(t)
       
!------------------------------------------------------------------------------
!      Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
       stat = ElementInfo( Element, Nodes, U, V, W, DetJ, &
            Basis, dBasisdx, ddBasisddx, .FALSE. )
       s = s * DetJ
       
!------------------------------------------------------------------------------
!      Load at the integration point
!------------------------------------------------------------------------------
       LoadAtIP(1) = SUM( Basis(1:n) * LOAD(1:2*n:2) )
       LoadAtIP(2) = SUM( Basis(1:n) * LOAD(2:2*n:2) )
!------------------------------------------------------------------------------
!      Finally, the elemental matrix & vector
!------------------------------------------------------------------------------       
       DO p=1,NBasis
          DO q=1,NBasis             
             STIFF(p,q) = STIFF(p,q) &
                  + s * SUM( dBasisdx( q,1:dim ) * dBasisdx( p,1:dim ) )
          END DO
       END DO

       IF ( StokesStream ) THEN
          Radius = SUM( Nodes % x(1:n) * Basis(1:n) )

          DO p = 1, NBasis
             FORCE(p) = FORCE(p) + s * SUM( LoadAtIP * dBasisdx(p,1:dim) ) * Radius
          END DO
       ELSE
          DO p = 1, NBasis
             FORCE(p) = FORCE(p) + s * SUM( LoadAtIP * dBasisdx(p,1:dim) )
          END DO
       END IF
       
    END DO! <- t eli integraatiopisteet

!------------------------------------------------------------------------------
  END SUBROUTINE LocalMatrix
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
END SUBROUTINE StreamSolver
!------------------------------------------------------------------------------
