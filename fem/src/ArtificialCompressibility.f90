!------------------------------------------------------------------------------
SUBROUTINE ArtificialCompressibilitySolve( Model,Solver,dt,TransientSimulation )
!DEC$ATTRIBUTES DLLEXPORT :: ArtificialCompressibilitySolve
!------------------------------------------------------------------------------
!******************************************************************************
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
  USE Types
  USE Lists
  USE Integration
  USE ElementDescription
  USE SolverUtils


  IMPLICIT NONE
!------------------------------------------------------------------------------
  TYPE(Solver_t) :: Solver
  TYPE(Model_t) :: Model
  REAL(KIND=dp) :: dt
  LOGICAL :: TransientSimulation
!------------------------------------------------------------------------------
! Local variables
!------------------------------------------------------------------------------
  REAL(KIND=dp), ALLOCATABLE :: Pressure(:), &
      Displacement(:,:), Compressibility(:)
  TYPE(Solver_t), POINTER :: FlowSolver
  REAL(KIND=dp) :: SideVolume, SidePressure, SideArea, TotalVolume, &
      InitVolume, TotalVolumeCompress, CompressSuggest, &
      CompressScale, CompressScaleOld, Relax, Norm, &
      Time, PrevTime=0.0d0, MinimumSideVolume=1.0d10, &
      TransitionVolume, dVolume
  LOGICAL :: Stat, GotIt, SubroutineVisited=.False., &
      ScaleCompressibility
  INTEGER :: i,j,k,n,pn,t,DIM,mat_id,TimeStepVisited
  INTEGER, POINTER :: NodeIndexes(:)
  TYPE(Variable_t), POINTER :: Var,Dvar
  TYPE(Mesh_t), POINTER :: Mesh
  TYPE(ValueList_t), POINTER :: Material
  TYPE(Nodes_t) :: ElementNodes
  TYPE(Element_t), POINTER   :: CurrentElement
  CHARACTER(LEN=MAX_NAME_LEN) :: EquationName
!------------------------------------------------------------------------------

  SAVE SubroutineVisited, TimeStepVisited, PrevTime, InitVolume, &
      MinimumSideVolume

  Time = Solver % DoneTime
  IF(ABS(Time-PrevTime) > 1.0d-20) THEN 
    TimeStepVisited = 0
    PrevTime = Time
  END IF

  DO i=1,Model % NumberOfSolvers
    FlowSolver => Model % Solvers(i)
    IF ( ListGetString( FlowSolver % Values, 'Equation' ) == 'navier-stokes' ) EXIT
  END DO

  Mesh => Model % Meshes
  DO WHILE( ASSOCIATED(Mesh) )
    IF ( Mesh % OutputActive ) EXIT 
    Mesh => Mesh % Next
  END DO


  CALL SetCurrentMesh( Model, Mesh )
  Var => VariableGet( Mesh % Variables, 'Flow Solution', .TRUE. )
  Dvar => VariableGet( Mesh % Variables, 'Displacement', .TRUE.)

  ALLOCATE( ElementNodes % x(Mesh % MaxElementNodes) )
  ALLOCATE( ElementNodes % y(Mesh % MaxElementNodes) )
  ALLOCATE( ElementNodes % z(Mesh % MaxElementNodes) )
  ALLOCATE( Compressibility(   Mesh % MaxElementNodes ) )
  ALLOCATE( Pressure(   Mesh % MaxElementNodes ) )
  ALLOCATE( Displacement( 3,Mesh % MaxElementNodes ) )

  TotalVolume = 0.0d0
  TotalVolumeCompress = 0.0d0
  SidePressure = 0.0d0
  SideVolume = 0.0d0
  SideArea = 0.0d0
  
  DIM = CoordinateSystemDimension()
  EquationName = ListGetString( Solver % Values, 'Equation' )


! /* Compute the volume and compressibility over it. */
  DO t=1,Solver % Mesh % NumberOfBulkElements

    CurrentElement => Solver % Mesh % Elements(t)
    
    IF ( .NOT. CheckElementEquation( Model, CurrentElement, EquationName ) &
        .AND. .NOT. CheckElementEquation( Model, CurrentElement, 'navier-stokes' ) ) &
        CYCLE
    
    n = CurrentElement % TYPE % NumberOfNodes
    NodeIndexes => CurrentElement % NodeIndexes

    ElementNodes % x(1:n) = Solver % Mesh % Nodes % x(NodeIndexes)
    ElementNodes % y(1:n) = Solver % Mesh % Nodes % y(NodeIndexes)
    ElementNodes % z(1:n) = Solver % Mesh % Nodes % z(NodeIndexes)
    
    mat_id = ListGetInteger( Model % Bodies(CurrentElement % BodyId) % &
        Values, 'Material',minv=1,maxv=Model % NumberOfMaterials )
    
    Material => Model % Materials(mat_id) % Values

    Compressibility(1:n) = &
        ListGetReal(Material,'Artificial Compressibility',n,NodeIndexes,gotIt)
    IF(.NOT. gotIt) Compressibility(1:n) = 0.0d0

    CALL CompressibilityIntegrate(CurrentElement, n, ElementNodes, &
        Compressibility, TotalVolume, TotalVolumeCompress)
  END DO

  ! Compute the force acting on the boundary
  DO t = Mesh % NumberOfBulkElements + 1, &
            Mesh % NumberOfBulkElements + &
               Mesh % NumberOfBoundaryElements

!------------------------------------------------------------------------------
     CurrentElement => Mesh % Elements(t)
     IF ( CurrentElement % TYPE % ElementCode == 101 ) CYCLE

!------------------------------------------------------------------------------
!    Set the current element pointer in the model structure to 
!    reflect the element being processed
!------------------------------------------------------------------------------
     Model % CurrentElement => Mesh % Elements(t)
!------------------------------------------------------------------------------
     n = CurrentElement % TYPE % NumberOfNodes
     NodeIndexes => CurrentElement % NodeIndexes

     DO k=1, Model % NumberOfBCs
        IF ( Model % BCs(k) % Tag /= CurrentElement % BoundaryInfo % Constraint ) CYCLE
        IF ( .NOT.ListGetLogical(Model % BCs(k) % Values,'Force BC',stat ) ) CYCLE

        ElementNodes % x(1:n) = Mesh % Nodes % x(NodeIndexes)
        ElementNodes % y(1:n) = Mesh % Nodes % y(NodeIndexes)
        ElementNodes % z(1:n) = Mesh % Nodes % z(NodeIndexes)

        Pressure(1:n) = Var % Values(Var % DOFs * Var % Perm(NodeIndexes))

        Displacement = 0.0d0
        DO i=1,n
          DO j=1,DIM
            Displacement(j,i) = &
                DVar % Values(DVar % DOFs * (DVar % Perm(NodeIndexes(i))-1)+j)
           END DO
         END DO

        CALL PressureIntegrate(CurrentElement, n, ElementNodes)
     END DO
  END DO

  IF(ABS(SideVolume) < MinimumSideVolume) THEN
    MinimumSideVolume = ABS(SideVolume)
    InitVolume = TotalVolume-SideVolume 
  END IF

  CompressScaleOld = ListGetConstReal( Model % Simulation, &
      'Artificial Compressibility Scaling',GotIt)
  IF(.NOT. GotIt) CompressScaleOld = 1.0

  Relax = ListGetConstReal( &
      Solver % Values, 'Nonlinear System Relaxation Factor',gotIt )
  IF(.NOT. gotIt) Relax = 1.0;

  TransitionVolume = ListGetConstReal( &
      Solver % Values, 'Artificial Compressibility Critical Volume',gotIt )
  IF(.NOT. gotIt) TransitionVolume = 0.01;
 
  ScaleCompressibility = ListGetLogical( &
      Solver % Values, 'Artificial Compressibility Scale',gotIt )
  IF(.NOT. gotIt) ScaleCompressibility = .TRUE.


  IF(SideVolume/TotalVolume > TransitionVolume) THEN
    dVolume = TotalVolume-InitVolume
  ELSE
    dVolume = SideVolume
  END IF
  CompressSuggest = (dVolume/TotalVolume)/(SidePressure * SideArea) 
  CompressScale = CompressSuggest*TotalVolume/ (TotalVolumeCompress*Relax)


  Norm = CompressScale
  IF(TimeStepVisited == 0) Norm = Norm * 2.0
  Solver % Variable % Norm = Norm

  TimeStepVisited = TimeStepVisited + 1

  IF(ScaleCompressibility) THEN
    CALL ListAddConstReal( Model % Simulation, &
        'Artificial Compressibility Scaling',CompressScale)
  END IF

  CALL ListAddConstReal( Model % Simulation, &
      'res: Relative Volume Change',dVolume/InitVolume)
  CALL ListAddConstReal( Model % Simulation, &
      'res: Mean Pressure on Surface',SidePressure/SideArea)
  CALL ListAddConstReal( Model % Simulation, &
      'res: Suggested Compressibility',CompressSuggest)
  CALL ListAddConstReal( Model % Simulation, &
      'res: Iterations',1.0d0*TimeStepVisited)

  WRITE(Message,'(A,T25,E15.4)') 'Relative Volume Change',dVolume/InitVolume
  CALL Info('ArtificialCompressibility',Message,Level=5)
  WRITE(Message,'(A,T25,E15.4)') 'Mean Pressure on Surface',SidePressure/SideArea
  CALL Info('ArtificialCompressibility',Message,Level=5)
  WRITE(Message,'(A,T25,E15.4)') 'Suggested Compressibility',CompressSuggest
  CALL Info('ArtificialCompressibility',Message,Level=5)
  WRITE(Message,'(A,T25,E15.4)') 'Compressibility Scaling Factor',&
      CompressScale/CompressScaleOld
  CALL Info('ArtificialCompressibility',Message,Level=5)

  
!#if 0
!  IF(SubroutineVisited) THEN
!    OPEN (10, FILE="fsistuff.dat", POSITION='APPEND')
!  ELSE
!    OPEN (10, FILE="fsistuff.dat")
!  END IF
!  SubroutineVisited = .TRUE.
!
!  WRITE (10,'(6e15.7)') SidePressure, TotalVolume, SideVolume, SideArea, &
!      CompressSuggest, CompressScale/CompressScaleOld
!  CLOSE(10)
!#endif

  DEALLOCATE( ElementNodes % x )
  DEALLOCATE( ElementNodes % y )
  DEALLOCATE( ElementNodes % z )
  DEALLOCATE( Pressure, Displacement, Compressibility)

CONTAINS

!------------------------------------------------------------------------------
  SUBROUTINE PressureIntegrate(Element, n, Nodes)
!------------------------------------------------------------------------------
    INTEGER :: n
    TYPE(Nodes_t) :: Nodes
    TYPE(Element_t), POINTER :: Element

!------------------------------------------------------------------------------
    REAL(KIND=dp) :: Basis(n),dBasisdx(n,3),ddBasisddx(n,3,3)
    REAL(KIND=dp) :: u,v,w,s,x,y,z, Pres
    REAL(KIND=dp) :: Grad(3,3), Stress(3,3), Normal(3), Ident(3,3)
    REAL(KIND=dp) :: NormalDisplacement,Symb(3,3,3),dSymb(3,3,3,3)
    REAL(KIND=dp) :: SqrtElementMetric, SqrtMetric, Metric(3,3)
    
    INTEGER :: N_Integ, CoordSys
    
    LOGICAL :: stat
    INTEGER :: i,t
    TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff
    
    Ident = 0.0d0
    DO i=1,3
      Ident(i,i) = 1.0d0
    END DO
    
!------------------------------------------------------------------------------
!    Integration stuff
!------------------------------------------------------------------------------
    IntegStuff = GaussPoints( Element )
    
    CoordSys = CurrentCoordinateSystem()
    

!------------------------------------------------------------------------------
    DO t=1,IntegStuff % n
!------------------------------------------------------------------------------
       u = IntegStuff % u(t)
       v = IntegStuff % v(t)
       w = IntegStuff % w(t)
!------------------------------------------------------------------------------
!      Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
       stat = ElementInfo( Element, Nodes, u, v, w, &
           SqrtElementMetric, Basis, dBasisdx, ddBasisddx, .FALSE., .FALSE. )
       
       s = SqrtElementMetric * IntegStuff % s(t)

       IF ( CoordSys /= Cartesian ) THEN
         X = SUM( Nodes % X(1:n) * Basis(1:n) )
         Y = SUM( Nodes % Y(1:n) * Basis(1:n) )
         Z = SUM( Nodes % Z(1:n) * Basis(1:n) )
         CALL CoordinateSystemInfo( Metric,SqrtMetric,Symb,dSymb,X,Y,Z )
         s = s * SqrtMetric
       END IF
       
       Normal = Normalvector( Element,Nodes, u,v, .TRUE. )
       
       NormalDisplacement = 0.0
       DO i=1,DIM
         NormalDisplacement = NormalDisplacement + &
             SUM(Basis(1:n) * Displacement(i,1:n)) * Normal(i)
       END DO
       
       Pres = SUM( Basis(1:n) * Pressure(1:n))

       SideVolume = SideVolume + s * ABS(NormalDisplacement)
       SidePressure = SidePressure + s * ABS(Pres)
       SideArea = SideArea + s
        
!------------------------------------------------------------------------------
     END DO
!------------------------------------------------------------------------------
  END SUBROUTINE PressureIntegrate
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE CompressibilityIntegrate(Element, n, Nodes, &
      Compressibility, TotalVolume, TotalVolumeCompress)
!------------------------------------------------------------------------------
    INTEGER :: n
    TYPE(Nodes_t) :: Nodes
    TYPE(Element_t), POINTER :: Element
    REAL(KIND=dp) :: Compressibility(:), TotalVolume, TotalVolumeCompress
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: Basis(n),dBasisdx(n,3),ddBasisddx(n,3,3)
    REAL(KIND=dp) :: SqrtElementMetric, U, V, W, S, C
    LOGICAL :: Stat
    INTEGER :: i,p,q,t,DIM, NBasis, CoordSys
    TYPE(GaussIntegrationPoints_t) :: IntegStuff
    REAL(KIND=dp) :: X,Y,Z,Metric(3,3),SqrtMetric,Symb(3,3,3),dSymb(3,3,3,3)

!------------------------------------------------------------------------------
    DIM = CoordinateSystemDimension()
    CoordSys = CurrentCoordinateSystem()

    Metric = 0.0d0
    Metric(1,1) = 1.0d0
    Metric(2,2) = 1.0d0
    Metric(3,3) = 1.0d0

!------------------------------------------------------------------------------
!   Numerical integration
!------------------------------------------------------------------------------

    NBasis = n
    IntegStuff = GaussPoints( Element )

!------------------------------------------------------------------------------
    DO t=1,IntegStuff % n
      U = IntegStuff % u(t)
      V = IntegStuff % v(t)
      W = IntegStuff % w(t)

!------------------------------------------------------------------------------
!      Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
      stat = ElementInfo( Element, Nodes, U, V, W, SqrtElementMetric, &
          Basis, dBasisdx, ddBasisddx, .FALSE., .FALSE. )
      s = IntegStuff % s(t) * SqrtElementMetric

      IF ( CoordSys /= Cartesian ) THEN
        X = SUM( Nodes % X(1:n) * Basis(1:n) )
        Y = SUM( Nodes % Y(1:n) * Basis(1:n) )
        Z = SUM( Nodes % Z(1:n) * Basis(1:n) )
        CALL CoordinateSystemInfo( Metric,SqrtMetric,Symb,dSymb,X,Y,Z )
        s = s * SqrtMetric
      END IF
 
      C = SUM(Basis(1:n) * Compressibility(1:n))

      TotalVolume = TotalVolume + s
      TotalVolumeCompress = TotalVolumeCompress + s*C
    END DO

!------------------------------------------------------------------------------
  END SUBROUTINE CompressibilityIntegrate
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
END SUBROUTINE ArtificialCompressibilitySolve
!------------------------------------------------------------------------------
