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
! *                Modified by: Mika Malinen
! *
! *       Date of modification: 29 Sep 2004
! *
! ****************************************************************************/

!------------------------------------------------------------------------------
SUBROUTINE AcousticsSolver( Model,Solver,dt,TransientSimulation )
  !DEC$ATTRIBUTES DLLEXPORT :: AcousticsSolver
!------------------------------------------------------------------------------
!******************************************************************************
!
!  Solve the time-harmonic, generalized NS-equations!
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
  ! Local variables related to the block preconditioning...
  !------------------------------------------------------------------------------
  TYPE(Matrix_t),POINTER  :: SMatrix, AMatrix, A1Matrix, A2Matrix, A3Matrix, &
      Grad1Matrix, Grad2Matrix, Grad3Matrix
  LOGICAL :: ComponentwisePreconditioning = .TRUE., &
      BlockPreconditioning = .FALSE., OptimizeBW, NormalTractionBoundary, &
      AllocatedGradMatrices 
  CHARACTER(LEN=MAX_NAME_LEN) :: OuterIterationMethod
  INTEGER :: MaxIterations, dim, SolverCalls = 0, NumberOfNormalTractionNodes
  COMPLEX(kind=dp) :: ChiConst
  COMPLEX(kind=dp), ALLOCATABLE :: NormalSurfaceForce(:) 
  REAL(KIND=dp) :: Tolerance, ToleranceRatio
  REAL(KIND=dp), ALLOCATABLE :: SLocal(:,:), ALocal(:,:), AnLocal(:,:), GradLocal(:,:)
  INTEGER, ALLOCATABLE :: NormalTractionNodes(:)
  SAVE SMatrix, AMatrix, A1Matrix, A2Matrix, A3Matrix, SLocal, ALocal, AnLocal, &
      Grad1Matrix, Grad2Matrix, Grad3Matrix, GradLocal, SolverCalls, &
      NormalTractionNodes, NormalSurfaceForce
  !------------------------------------------------------------------------------
  ! Other local variables
  !------------------------------------------------------------------------------
  TYPE(Matrix_t),POINTER  :: StiffMatrix
  TYPE(Nodes_t) :: ElementNodes
  TYPE(Element_t),POINTER :: CurrentElement, Parent
  TYPE(ValueList_t), POINTER :: Material

  INTEGER, POINTER :: NodeIndexes(:), FlowPerm(:)
  INTEGER :: i, j, k, m, n, t, istat, LocalNodes, Dofs, &
      VelocityComponents, VelocityDofs, CoordSys

  LOGICAL :: AllocationsDone = .FALSE., Bubbles, GotIt, GotIt2, stat, &
      VisitedNodes(Model % NumberOfNodes), SlipBoundary, UtilizePreviousSolution
  CHARACTER(LEN=MAX_NAME_LEN) :: EquationName, VariableName
  CHARACTER(LEN=MAX_NAME_LEN) :: VersionID = "$Id: Acoustics.f90,v 1.18 2005/04/20 09:58:54 mmalinen Exp $"

  COMPLEX(KIND=dp) :: A 

  REAL(KIND=dp), POINTER :: Flow(:), ForceVector(:)
  REAL(KIND=dp) :: Norm, PrevNorm, RelativeChange, AngularFrequency, &
      SlipCoefficient1, SlipCoefficient2
  REAL(KIND=dp) :: NonlinearTol, at, at0, totat, st, totst, CPUTime, RealTime

  REAL(KIND=dp), ALLOCATABLE :: LocalStiffMatrix(:,:), Load(:,:), &
      HeatSource(:,:), temp(:), &
      LocalForce(:), SpecificHeat(:), HeatRatio(:), &
      Density(:), Pressure(:), Temperature(:), Conductivity(:), &
      Viscosity(:), Lambda(:), BulkViscosity(:), Impedance(:,:), &
      WallTemperature(:), WallVelocity(:,:), AcImpedances(:,:)

  INTEGER :: AcousticI
  INTEGER, ALLOCATABLE :: Bndries(:)

  SAVE LocalStiffMatrix, temp, Load, HeatSource,  LocalForce, ElementNodes, &
       SpecificHeat, HeatRatio, Density, Pressure, &
       Temperature, Conductivity, Viscosity, Lambda, BulkViscosity, &
       Impedance, WallTemperature, WallVelocity, AllocationsDone 

  !------------------------------------------------------------------------------
  !    Check if version number output is requested
  !------------------------------------------------------------------------------
  IF ( .NOT. AllocationsDone ) THEN
    IF ( ListGetLogical( GetSimulation(), 'Output Version Numbers', GotIt ) ) THEN
      CALL Info( 'AcousticsSolver', 'Acoustics version:', Level = 0 ) 
      CALL Info( 'AcousticsSolver', VersionID, Level = 0 ) 
      CALL Info( 'AcousticsSolver', ' ', Level = 0 ) 
    END IF
  END IF

  !------------------------------------------------------------------------------
  ! Get variables needed for solution
  !------------------------------------------------------------------------------
  IF ( .NOT. ASSOCIATED( Solver % Matrix ) ) RETURN
  Solver % Matrix % COMPLEX = .TRUE.

  Flow     => Solver % Variable % Values
  FlowPerm => Solver % Variable % Perm

  LocalNodes = COUNT( FlowPerm > 0 )
  IF ( LocalNodes <= 0 ) RETURN

  StiffMatrix => Solver % Matrix
  ForceVector => StiffMatrix % RHS
  Norm = Solver % Variable % Norm
  Dofs = Solver % Variable % DOFs
  VelocityComponents = CoordinateSystemDimension()
  VelocityDofs = VelocityComponents*2
  IF (Dofs /= VelocityDofs + 4) THEN
    CALL Warn('AcousticsSolver', 'Inconsistent number of Variable Dofs')
  END IF

  !------------------------------------------------------------------------------
  ! Find out whether the block preconditioning is used...
  !------------------------------------------------------------------------------
  dim = CoordinateSystemDimension() 
  BlockPreconditioning = ListGetLogical( Solver % Values, 'Block Preconditioning', GotIt )
  
  IF (BlockPreconditioning) THEN
    CALL Info('AcousticsSolver', 'Block preconditioning will be used.')
    !---------------------------------------------------------------------------
    ! Check out whether component-wise preconditioning for velocities is used...
    !---------------------------------------------------------------------------
    ComponentwisePreconditioning = ListGetLogical( Solver % Values, &
        'Componentwise Preconditioning', GotIt )
    IF (.NOT. GotIt) ComponentwisePreconditioning = .TRUE.
    AllocatedGradMatrices = .FALSE.

    OuterIterationMethod = ListGetString(Solver % Values, 'Outer Iteration Method', GotIt)
    IF ( .NOT. GotIt ) OuterIterationMethod = 'bicgstab'     
    ToleranceRatio = ListGetConstReal( Solver % Values, &
        'Ratio of Convergence Tolerances', GotIt )
    IF (GotIt) THEN
      Tolerance = ToleranceRatio * ListGetConstReal( Solver % Values, &
          'Linear System Convergence Tolerance' )
    ELSE
      Tolerance = ListGetConstReal( Solver % Values, &
          'Linear System Convergence Tolerance' )
    END IF
    MaxIterations = ListGetInteger( Solver % Values, &
        'Max Outer Iterations', GotIt )
!    MaxIterations = MaxIterations + SolverCalls
!    SolverCalls = SolverCalls + 1 
!    MaxIterations = SolverCalls * 10
    IF ( .NOT. GotIt ) MaxIterations = ListGetInteger( Solver % Values, &
        'Linear System Max Iterations')    
  END IF

  !------------------------------------------------------------------------------
  ! Allocate some permanent storage, this is done first time only
  !------------------------------------------------------------------------------
  IF ( .NOT. AllocationsDone .OR. Solver % Mesh % Changed ) THEN
    N = Solver % Mesh % MaxElementNodes
    
    IF ( AllocationsDone ) THEN
      DEALLOCATE(                 &
          ElementNodes % x,      &
          ElementNodes % y,      &
          ElementNodes % z,      &
          LocalForce,            &
          temp,                  &
          LocalStiffMatrix,      &
          Load,                  &
          HeatSource,            &
          SpecificHeat,          &
          HeatRatio,             &
          Density,               &
          Pressure,              &
          Temperature,           &
          Conductivity,          &
          Viscosity,             &
          Lambda,                &
          BulkViscosity,         &
          Impedance,             &
          WallTemperature,       &
          WallVelocity)           
    END IF

    !-----------------------------------------------------------------
    ! Create new matrices for the block preconditioning...
    !------------------------------------------------------------------
    IF (BlockPreconditioning) THEN
      !---------------------------------------------------------------------------
      ! Make sure that the new matrices are optimized as the primary one.
      !---------------------------------------------------------------------------
      OptimizeBW = ListGetLogical(Solver % Values,'Bandwidth Optimize',gotIt)
      IF(.NOT. GotIt) OptimizeBW = .TRUE.
      IF (ComponentwisePreconditioning) THEN
        A1Matrix => CreateMatrix( Model, Solver % Mesh, Solver % Variable % Perm, &
            2, MATRIX_CRS, OptimizeBW, ListGetString( Solver % Values, 'Equation' ) )
        A2Matrix => CreateMatrix( Model, Solver % Mesh, Solver % Variable % Perm, &
            2, MATRIX_CRS, OptimizeBW, ListGetString( Solver % Values, 'Equation' ) )
        IF (dim > 2) &
            A3Matrix => CreateMatrix( Model, Solver % Mesh, Solver % Variable % Perm, &
            2, MATRIX_CRS, OptimizeBW, ListGetString( Solver % Values, 'Equation' ) )  
      ELSE
        AMatrix => CreateMatrix( Model, Solver % Mesh, FlowPerm, 2*dim, &
            MATRIX_CRS, OptimizeBW, ListGetString( Solver % Values, 'Equation' ) )
      END IF

      SMatrix => CreateMatrix( Model, Solver % Mesh, Solver % Variable % Perm, &
          4, MATRIX_CRS, OptimizeBW, ListGetString( Solver % Values, 'Equation' ) )
      ALLOCATE(SMatrix % RHS( SMatrix % NumberOfRows ) )
      SMatrix % RHS = 0.0d0

      IF (AllocatedGradMatrices) THEN
        Grad1Matrix => CreateMatrix( Model, Solver % Mesh, Solver % Variable % Perm, &
            2, MATRIX_CRS, OptimizeBW, ListGetString( Solver % Values, 'Equation' ) )
        Grad2Matrix => CreateMatrix( Model, Solver % Mesh, Solver % Variable % Perm, &
            2, MATRIX_CRS, OptimizeBW, ListGetString( Solver % Values, 'Equation' ) )
        IF (dim > 2) THEN
          Grad3Matrix => CreateMatrix( Model, Solver % Mesh, Solver % Variable % Perm, &
              2, MATRIX_CRS, OptimizeBW, ListGetString( Solver % Values, 'Equation' ) )
        END IF
      END IF

      ALLOCATE( SLocal(4*n,4*n), ALocal(2*dim*n,2*dim*n), AnLocal(2*n,2*n), &
          GradLocal(2*n,2*n), STAT=istat )
      IF ( istat /= 0 ) THEN
        CALL Fatal( 'AcousticsSolver', 'Memory allocation error.' )
      END IF

      !---------------------------------------------------------------------------------
      ! Allocate additional arrays for saving the normal surface force at nodes
      !---------------------------------------------------------------------------------
      NumberOfNormalTractionNodes = 0
      DO t = Solver % Mesh % NumberOfBulkElements + 1,  &
          Solver % Mesh % NumberOfBulkElements + Solver % Mesh % NumberOfBoundaryElements
        !------------------------------------------------------------------------------
        CurrentElement => Solver % Mesh % Elements(t)
        Model % CurrentElement => CurrentElement
        !------------------------------------------------------------------------------
        DO i=1,Model % NumberOfBCs
          IF ( CurrentElement % BoundaryInfo % Constraint == Model % BCs(i) % Tag ) THEN
            NodeIndexes => CurrentElement % NodeIndexes
            NormalTractionBoundary = ListGetLogical( Model % BCs(i) % Values, &
                'Prescribed Normal Traction', GotIt )
            IF ( .NOT. NormalTractionBoundary) CYCLE            
            IF ( ANY( FlowPerm(NodeIndexes) == 0 ) ) CYCLE
            NumberOfNormalTractionNodes = NumberOfNormalTractionNodes + &
                CurrentElement % TYPE % NumberOfNodes
          END IF
        END DO
      END DO
      IF (NumberOfNormalTractionNodes > 0) THEN
        ALLOCATE( NormalTractionNodes(NumberOfNormalTractionNodes), &
            NormalSurfaceForce(NumberOfNormalTractionNodes), &            
            STAT=istat )
        IF ( istat /= 0 ) &
            CALL Fatal( 'AcousticsSolver', 'Memory allocation error.' )
      END IF

    END IF
    
    ALLOCATE( ElementNodes % x( N ), &
        ElementNodes % y( N ),       &
        ElementNodes % z( N ),       &
        LocalForce( Dofs*N ),        &
        temp( N ),                   &
        LocalStiffMatrix( Dofs*N,Dofs*N ), &
        Load( 6,N ),   &
        HeatSource(2,N),               &
        SpecificHeat(N),             &
        HeatRatio(N),                &
        Density(N),                  &
        Pressure(N),        &
        Temperature(N),              &
        Conductivity(N),             &
        Viscosity(N),                &
        Lambda(N),                   &
        BulkViscosity(N),            &
        Impedance( 4,N ),            &
        WallTemperature(N),          &
        WallVelocity(6,N),           &
        STAT=istat )

    IF ( istat /= 0 ) THEN
      CALL Fatal( 'AcousticsSolver', 'Memory allocation error.' )
    END IF

    AllocationsDone = .TRUE.
  END IF

  !---------------------------------------------------------------------------
  ! Initialization related to the block preconditioning
  !---------------------------------------------------------------------------
  IF (BlockPreconditioning) THEN
    IF (ComponentwisePreconditioning) THEN
      CALL CRS_ZeroMatrix( A1Matrix )
      CALL CRS_ZeroMatrix( A2Matrix )
      IF (dim > 2) CALL CRS_ZeroMatrix( A3Matrix )
    ELSE
      CALL CRS_ZeroMatrix( AMatrix ) 
    END IF
    CALL CRS_ZeroMatrix( SMatrix )
    IF (AllocatedGradMatrices) THEN
      CALL CRS_ZeroMatrix( Grad1Matrix )
      CALL CRS_ZeroMatrix( Grad2Matrix )
      IF (dim > 2) CALL CRS_ZeroMatrix( Grad3Matrix )
    END IF
  END IF

  !------------------------------------------------------------------------------
  ! Do some additional initialization and start assembly
  !------------------------------------------------------------------------------
  EquationName = ListGetString( Solver % Values, 'Equation' )
  Bubbles = ListGetLogical( Solver % Values, 'Bubbles', GotIt )
  CoordSys = CurrentCoordinateSystem()
  IF (.NOT. (CoordSys==Cartesian .OR. CoordSys==AxisSymmetric) ) THEN
    CALL Fatal('AcousticsSolver',&
        'Currently only Cartesian or cylindrical coordinates are allowed')
  END IF

  !------------------------------------------------------------------------------
  ! Figure out angular frequency 
  !------------------------------------------------------------------------------
  AngularFrequency = 0.0d0
  CurrentElement => GetActiveElement(1)
  n = GetElementNOFNodes()
  temp(1:n) =  GetReal( Model % Simulation,  'Angular Frequency', GotIt )
  IF ( GotIt ) THEN
    AngularFrequency = temp(1)
  ELSE
    temp(1:n) = GetReal( Model % Simulation,  'Frequency')
    AngularFrequency = 2*PI*temp(1)
  END IF

  !------------------------------------------------------------------------------
  ! In the case of pseudo time-stepping the nodal values of the approximations of 
  ! div(v)-type term and the scaled temperature may be overwritten in such a way 
  ! the previous solution is used as an initial guess.
  !----------------------------------------------------------------------------- 
  UtilizePreviousSolution = ListGetLogical( Solver % Values, &
      'Utilize Previous Solution', GotIt )
  IF (.NOT. GotIt) UtilizePreviousSolution = .FALSE.

  IF (UtilizePreviousSolution) THEN
    VisitedNodes = .FALSE.
    DO t=1,Solver % Mesh % NumberOfBulkElements
      CurrentElement => Solver % Mesh % Elements(t)
      IF ( .NOT. CheckElementEquation( Model, &
          CurrentElement, EquationName ) ) CYCLE
      Model % CurrentElement => CurrentElement
      n = CurrentElement % TYPE % NumberOfNodes
      NodeIndexes => CurrentElement % NodeIndexes
      !------------------------------------------------------------------------------
      !   Get equation & material parameters
      !------------------------------------------------------------------------------
      k = ListGetInteger( Model % Bodies( CurrentElement % &
          Bodyid ) % Values, 'Material' )
      Material => Model % Materials(k) % Values

      SpecificHeat(1:n) = ListGetReal( Material, 'Specific Heat', &
          n, NodeIndexes )
      HeatRatio(1:n) = ListGetReal( Material, 'Specific Heat Ratio', &
          n, NodeIndexes )
      Density(1:n) = ListGetReal( Material, 'Equilibrium Density', &
          n, NodeIndexes )    
      Temperature(1:n) = ListGetReal( Material, 'Equilibrium Temperature', &
          n, NodeIndexes )        
      Viscosity(1:n) = ListGetReal( Material, 'Viscosity', &
          n, NodeIndexes )   
      Lambda = -2.0d0/3.0d0 * Viscosity
      BulkViscosity(1:n) = ListGetReal( Material, 'Bulk Viscosity', &
          n, NodeIndexes, GotIt )
      IF (GotIt) Lambda = BulkViscosity - 2.0d0/3.0d0 * Viscosity

      DO i=1,n
        j = NodeIndexes(i)
        IF ( .NOT. VisitedNodes(j) ) THEN
          VisitedNodes(j) = .TRUE.
          !-------------------------------------
          ! Rescaling of the temperature...
          !--------------------------------------
          A = (HeatRatio(i)-1.0d0) * SpecificHeat(i) / AngularFrequency * &
              DCMPLX( Flow( (j-1)*Dofs+VelocityDofs+1 ), &
              Flow( (j-1)*Dofs+VelocityDofs+2 ) )
          Flow( (j-1)*Dofs+VelocityDofs+1 ) = REAL(A)
          Flow( (j-1)*Dofs+VelocityDofs+2 ) = AIMAG(A)
          !-------------------------------------
          ! Rescaling of the pressure...
          !--------------------------------------
          A = DCMPLX( 1.0d0, (Lambda(i)+Viscosity(i))*AngularFrequency/  &
              ( (HeatRatio(i)-1.0d0) * SpecificHeat(i) * Density(i) * Temperature(i) ) ) * &              
              (1.0d0/(AngularFrequency * Density(i)) * &
              DCMPLX( Flow( (j-1)*Dofs+VelocityDofs+3 ), Flow( (j-1)*Dofs+VelocityDofs+4 ) ) - &
              DCMPLX( Flow( (j-1)*Dofs+VelocityDofs+1 ), Flow( (j-1)*Dofs+VelocityDofs+2 ) ) )
          Flow( (j-1)*Dofs+VelocityDofs+3 ) = REAL(A)
          Flow( (j-1)*Dofs+VelocityDofs+4 ) = AIMAG(A)
        END IF
      END DO
    END DO
  END IF

  totat = 0.0d0
  totst = 0.0d0
  at  = CPUTime()
  at0 = RealTime()

  CALL Info( 'AcousticsSolver', ' ', Level=4 )
  CALL Info( 'AcousticsSolver', '-------------------------------------', &
      Level=4 )
  WRITE( Message, * ) 'Frequency (Hz): ', AngularFrequency/(2*PI)
  CALL Info( 'AcousticsSolver', Message, Level=4 )
  CALL Info( 'AcousticsSolver', '-------------------------------------', &
      Level=4 )
  CALL Info( 'AcousticsSolver', ' ', Level=4 )
  CALL Info( 'AcousticsSolver', 'Starting Assembly', Level=4 )
  
  CALL InitializeToZero( StiffMatrix, ForceVector )

  !------------------------------------------------------------------------------
  DO t=1,Solver % Mesh % NumberOfBulkElements
  !------------------------------------------------------------------------------
    IF ( RealTime() - at0 > 1.0 ) THEN
      WRITE(Message,'(a,i3,a)' ) '   Assembly: ', INT(100.0 - 100.0 * &
          (Solver % Mesh % NumberOfBulkElements-t) / &
          (Solver % Mesh % NumberOfBulkElements)), ' % done'
      CALL Info( 'AcousticsSolver', Message, Level=5 )
      at0 = RealTime()
    END IF
    !------------------------------------------------------------------------------
    ! Check if this element belongs to a body where this equation
    ! should be computed
    !------------------------------------------------------------------------------
    CurrentElement => Solver % Mesh % Elements(t)
    IF ( .NOT. CheckElementEquation( Model, &
        CurrentElement, EquationName ) ) CYCLE
    !------------------------------------------------------------------------------

    Model % CurrentElement => CurrentElement
    n = CurrentElement % TYPE % NumberOfNodes
    NodeIndexes => CurrentElement % NodeIndexes
 
    ElementNodes % x(1:n) = Solver % Mesh % Nodes % x(NodeIndexes)
    ElementNodes % y(1:n) = Solver % Mesh % Nodes % y(NodeIndexes)
    ElementNodes % z(1:n) = Solver % Mesh % Nodes % z(NodeIndexes)

    !------------------------------------------------------------------------------
    ! Get equation & material parameters
    !------------------------------------------------------------------------------
    k = ListGetInteger( Model % Bodies( CurrentElement % &
        Bodyid ) % Values, 'Material' )
    Material => Model % Materials(k) % Values

    SpecificHeat(1:n) = ListGetReal( Material, 'Specific Heat', &
        n, NodeIndexes )
    HeatRatio(1:n) = ListGetReal( Material, 'Specific Heat Ratio', &
        n, NodeIndexes )
    Density(1:n) = ListGetReal( Material, 'Equilibrium Density', &
        n, NodeIndexes )
    Temperature(1:n) = ListGetReal( Material, 'Equilibrium Temperature', &
        n, NodeIndexes )        
    Conductivity(1:n) = ListGetReal( Material, 'Heat Conductivity', &
        n, NodeIndexes )   
    Viscosity(1:n) = ListGetReal( Material, 'Viscosity', &
        n, NodeIndexes )   
    Lambda = -2.0d0/3.0d0 * Viscosity
    BulkViscosity(1:n) = ListGetReal( Material, ' Bulk Viscosity', &
        n, NodeIndexes, GotIt )
    IF (GotIt) Lambda = BulkViscosity - 2.0d0/3.0d0 * Viscosity
    Pressure(1:n) = (HeatRatio-1.0d0)* SpecificHeat * Density * Temperature

    !------------------------------------------------------------------------------
    !   The heat source and body force at nodes
    !------------------------------------------------------------------------------
    Load = 0.0d0
    HeatSource = 0.0d0
    k = ListGetInteger( Model % Bodies( CurrentElement % BodyId ) % &
                       Values, 'Body Force', GotIt )
    IF ( k > 0 ) THEN
      HeatSource(1,1:n) = ListGetReal( Model % BodyForces(k) % Values, &
          'Re Heat Source', n, NodeIndexes, GotIt )
      HeatSource(2,1:n) = ListGetReal( Model % BodyForces(k) % Values, &
          'Im Heat Source', n, NodeIndexes, GotIt )
      Load(1,1:n) = ListGetReal( Model % BodyForces(k) % Values, &
          'Re Body Force 1', n, NodeIndexes, GotIt )
      Load(2,1:n) = ListGetReal( Model % BodyForces(k) % Values, &
          'Im Body Force 1', n, NodeIndexes, GotIt )
      Load(3,1:n) = ListGetReal( Model % BodyForces(k) % Values, &
          'Re Body Force 2', n, NodeIndexes, GotIt )
      Load(4,1:n) = ListGetReal( Model % BodyForces(k) % Values, &
          'Im Body Force 2', n, NodeIndexes, GotIt )
      Load(5,1:n) = ListGetReal( Model % BodyForces(k) % Values, &
          'Re Body Force 3', n, NodeIndexes, GotIt )
      Load(6,1:n) = ListGetReal( Model % BodyForces(k) % Values, &
          'Im Body Force 3', n, NodeIndexes, GotIt )
    END IF

    !------------------------------------------------------------------------------
    !   Get element local matrix and rhs vector
    !------------------------------------------------------------------------------
    IF (CoordSys==Cartesian) THEN
      CALL LocalMatrix(  LocalStiffMatrix, LocalForce, AngularFrequency, &
          SpecificHeat, HeatRatio, Density,                    &
          Temperature, Conductivity, Viscosity, Lambda,                  &
          HeatSource, Load, Bubbles, CurrentElement, n, ElementNodes,    &
          Dofs)
    ELSE
      CALL LocalMatrix2(  LocalStiffMatrix, LocalForce, AngularFrequency, &
          SpecificHeat, HeatRatio, Density,                     &
          Temperature, Conductivity, Viscosity, Lambda,                   &
          HeatSource, Load, Bubbles, CurrentElement, n, ElementNodes,     &
          Dofs)      
    END IF
    !------------------------------------------------------------------------------
    !   Update global matrix and rhs vector from local matrix & vector
    !------------------------------------------------------------------------------
    CALL UpdateGlobalEquations( StiffMatrix, LocalStiffMatrix, &
        ForceVector, LocalForce, n, Dofs, FlowPerm(NodeIndexes) )

    !-----------------------------------------------------------------------------
    ! Do the assembly for the preconditioners...
    !----------------------------------------------------------------------------
    IF (BlockPreconditioning) THEN
      IF (ComponentwisePreconditioning) THEN
        CALL VelocityMatrix( AnLocal, Viscosity, AngularFrequency, Density, &
            CurrentElement, n, dim)
        CALL UpdateGlobalPreconditioner( A1Matrix, AnLocal, n, 2, &
            Solver % Variable % Perm( CurrentElement % NodeIndexes ) )
        CALL UpdateGlobalPreconditioner( A2Matrix, AnLocal, n, 2, &
            Solver % Variable % Perm( CurrentElement % NodeIndexes ) )  
        IF (dim > 2) &
            CALL UpdateGlobalPreconditioner( A3Matrix, AnLocal, n, 2, &
            Solver % Variable % Perm( CurrentElement % NodeIndexes ) )
      ELSE
        CALL CoupledVelocityMatrix( ALocal, Viscosity, AngularFrequency, Density, &
            CurrentElement, n, dim)
        CALL UpdateGlobalPreconditioner( AMatrix, ALocal, n, 2*dim, &
            Solver % Variable % Perm( CurrentElement % NodeIndexes ) )
      END IF

      IF (.FALSE.) THEN
        CALL SchurComplementMatrix( SLocal, AngularFrequency, SpecificHeat, &
            HeatRatio, Density, Pressure, Temperature, Conductivity, Viscosity, Lambda, &
            CurrentElement, n, dim)
      ELSE
        !---------------------------------------------------------------------------------
        ! An alternative formulation for the Schur complement to facilitate the treatment
        ! of general boundary conditions. Constant viscosity is assumed here.
        !---------------------------------------------------------------------------------
        ChiConst = DCMPLX( 1.0d0, AngularFrequency/Pressure(1)*( Lambda(1) ) ) /  &
            DCMPLX( 1.0d0, AngularFrequency/Pressure(1)*( 2.0d0*Viscosity(1)+Lambda(1) ) )
        CALL SchurComplementMatrix2( SLocal, AngularFrequency, SpecificHeat, &
            HeatRatio, Density, Pressure, Temperature, Conductivity, Viscosity, Lambda, &
            CurrentElement, n, dim)
      END IF

      CALL UpdateGlobalPreconditioner( SMatrix, SLocal, n, 4, &
          Solver % Variable % Perm( CurrentElement % NodeIndexes ) )
        
      IF (AllocatedGradMatrices) THEN
        CALL GradientMatrix( GradLocal, Viscosity, AngularFrequency, Density, &
            Pressure, HeatRatio, Lambda, CurrentElement, 1, n, dim)
        CALL UpdateGlobalPreconditioner( Grad1Matrix, GradLocal, n, 2, &
            Solver % Variable % Perm( CurrentElement % NodeIndexes ) )
        CALL GradientMatrix( GradLocal, Viscosity, AngularFrequency, Density, &
            Pressure, HeatRatio, Lambda, CurrentElement, 2, n, dim)
        CALL UpdateGlobalPreconditioner( Grad2Matrix, GradLocal, n, 2, &
            Solver % Variable % Perm( CurrentElement % NodeIndexes ) )
        IF (dim > 2) THEN
          CALL GradientMatrix( GradLocal, Viscosity, AngularFrequency, Density, &
              Pressure, HeatRatio, Lambda, CurrentElement, 3, n, dim)
          CALL UpdateGlobalPreconditioner( Grad3Matrix, GradLocal, n, 2, &
              Solver % Variable % Perm( CurrentElement % NodeIndexes ) )
        END IF
      END IF
    END IF
  !------------------------------------------------------------------------------
  END DO
  !------------------------------------------------------------------------------


  !------------------------------------------------------------------------------
  ! Compute the matrix corresponding to the integral over boundaries:
  !------------------------------------------------------------------------------
  DO t = Solver % Mesh % NumberOfBulkElements + 1,  &
      Solver % Mesh % NumberOfBulkElements + Solver % Mesh % NumberOfBoundaryElements
    CurrentElement => Solver % Mesh % Elements(t)
    Model % CurrentElement => CurrentElement
    !------------------------------------------------------------------------------
    ! Skip point elements (element type 101) 
    !------------------------------------------------------------------------------
    IF ( CurrentElement % TYPE % ElementCode == 101 ) CYCLE
    !------------------------------------------------------------------------------
    ! Extract the parent element to find its material parameters... 
    !----------------------------------------------------------------------------- 
    Parent => CurrentELement % BoundaryInfo % Left
    stat = ASSOCIATED( Parent )
    IF (stat) stat = ALL(FlowPerm(Parent % NodeIndexes) > 0)
    IF ( .NOT. stat) THEN
      Parent => CurrentELement % BoundaryInfo % Right
      stat = ASSOCIATED( Parent )
      IF (stat) stat = ALL(FlowPerm(Parent % NodeIndexes) > 0)
      IF ( .NOT. stat )  CALL Fatal( 'AcousticsSolver', &
          'No parent element can be found for given boundary element' )
    END IF
    IF ( .NOT. CheckElementEquation( Model, Parent, EquationName ) ) CYCLE

    DO i=1,Model % NumberOfBCs
      IF ( CurrentElement % BoundaryInfo % Constraint == &
          Model % BCs(i) % Tag ) THEN
        n = CurrentElement % TYPE % NumberOfNodes
        NodeIndexes => CurrentElement % NodeIndexes
        ElementNodes % x(1:n) = Solver % Mesh % Nodes % x(NodeIndexes)
        ElementNodes % y(1:n) = Solver % Mesh % Nodes % y(NodeIndexes)
        ElementNodes % z(1:n) = Solver % Mesh % Nodes % z(NodeIndexes)

        k = ListGetInteger( Model % Bodies(Parent % Bodyid) % Values, &
            'Material' )
        Material => Model % Materials(k) % Values
        
        SpecificHeat(1:n) = ListGetReal( Material, 'Specific Heat', &
            n, NodeIndexes )
        HeatRatio(1:n) = ListGetReal( Material, 'Specific Heat Ratio', &
            n, NodeIndexes )
        Density(1:n) = ListGetReal( Material, 'Equilibrium Density', &
            n, NodeIndexes )
        Temperature(1:n) = ListGetReal( Material, &
            'Equilibrium Temperature', n, NodeIndexes )        
        Conductivity(1:n) = ListGetReal( Material, 'Heat Conductivity', &
            n, NodeIndexes )   
        Pressure(1:n) = (HeatRatio(1:n)-1.0d0)* SpecificHeat(1:n) * Density(1:n) * Temperature(1:n)

        Impedance(1,1:n) = ListGetReal( Model % BCs(i) % Values, &
            'Re Specific Acoustic Impedance', n, NodeIndexes, GotIt )
        Impedance(2,1:n) = ListGetReal( Model % BCs(i) % Values, &
            'Im Specific Acoustic Impedance', n, NodeIndexes, GotIt )
        Impedance(3,1:n) = ListGetReal( Model % BCs(i) % Values, &
            'Re Specific Thermal Impedance', n, NodeIndexes, GotIt )
        Impedance(4,1:n) = ListGetReal( Model % BCs(i) % Values, &
            'Im Specific Thermal Impedance', n, NodeIndexes, GotIt )

        Load(1,1:n) = ListGetReal( Model % BCs(i) % Values, &
            'Re Surface Traction 1', n, NodeIndexes, GotIt )
        Load(2,1:n) = ListGetReal( Model % BCs(i) % Values, &
            'Im Surface Traction 1', n, NodeIndexes, GotIt )
        Load(3,1:n) = ListGetReal( Model % BCs(i) % Values, &
            'Re Surface Traction 2', n, NodeIndexes, GotIt )
        Load(4,1:n) = ListGetReal( Model % BCs(i) % Values, &
            'Im Surface Traction 2', n, NodeIndexes, GotIt )
        Load(5,1:n) = ListGetReal( Model % BCs(i) % Values, &
            'Re Surface Traction 3', n, NodeIndexes, GotIt )
        Load(6,1:n) = ListGetReal( Model % BCs(i) % Values, &
            'Im Surface Traction 3', n, NodeIndexes, GotIt )
        !------------------------------------------------------------------------------
        ! Get element local matrix and rhs vector
        !------------------------------------------------------------------------------
        IF (CoordSys==Cartesian) THEN
          CALL LocalMatrixBoundary(  LocalStiffMatrix, LocalForce, &
              AngularFrequency , SpecificHeat, HeatRatio, Density, &
              Pressure, Temperature, Conductivity,     &
              Impedance, Load, CurrentElement, n, ElementNodes, Dofs)
        ELSE
          CALL LocalMatrixBoundary2(  LocalStiffMatrix, LocalForce, &
              AngularFrequency , SpecificHeat, HeatRatio, Density, &
              Pressure, Temperature, Conductivity,     &
              Impedance, Load, CurrentElement, n, ElementNodes, Dofs)
        END IF
        !------------------------------------------------------------------------------
        ! Update global matrix and rhs vector from local matrix & vector
        !------------------------------------------------------------------------------
        CALL UpdateGlobalEquations( StiffMatrix, LocalStiffMatrix, &
            ForceVector, LocalForce, n, Dofs, FlowPerm(NodeIndexes) )
        !------------------------------------------------------------------------------

        !-----------------------------------------------------------------------------
        ! Do additional assembly for the preconditioners in the case of impedance BC
        !----------------------------------------------------------------------------
        IF (BlockPreconditioning .AND. (ANY(Impedance(1:4,1:n) /= 0.0d0)) ) THEN
          IF (ComponentwisePreconditioning) THEN
            CALL Fatal('AcousticsSolver',&
                'Componentwise Preconditioning cannot be used in the case of impedance BC') 
          ELSE
            CALL VelocityImpedanceMatrix(  ALocal, AngularFrequency, Density, &
                Impedance, CurrentElement, n, ElementNodes, dim)
            CALL UpdateGlobalPreconditioner( AMatrix, ALocal, n, 2*dim, &
                Solver % Variable % Perm( CurrentElement % NodeIndexes ) )
          END IF
          !------------------------------------------------------------------------
          ! Impedance BC's for the Schur complement
          !------------------------------------------------------------------------
          CALL SchurComplementImpedanceMatrix( SLocal, Impedance, AngularFrequency, &
              SpecificHeat, HeatRatio, Density, Conductivity, &
              CurrentElement, n, ElementNodes, dim)
          CALL UpdateGlobalPreconditioner( SMatrix, SLocal, n, 4, &
              Solver % Variable % Perm( CurrentElement % NodeIndexes ) )
        END IF
      END IF
    END DO
  !------------------------------------------------------------------------------
  END DO
  !------------------------------------------------------------------------------

  !------------------------------------------------------------------------------
  !    Slip boundary conditions
  !------------------------------------------------------------------------------
  DO t = Solver % Mesh % NumberOfBulkElements + 1,  &
      Solver % Mesh % NumberOfBulkElements +  &
      Solver % Mesh % NumberOfBoundaryElements
    CurrentElement => Solver % Mesh % Elements(t)
    Model % CurrentElement => CurrentElement
    !------------------------------------------------------------------------------
    ! Skip point elements (element type 101) 
    !------------------------------------------------------------------------------
    IF ( CurrentElement % TYPE % ElementCode == 101 ) CYCLE
    !------------------------------------------------------------------------------
    ! Extract the parent element to find its material parameters... 
    !----------------------------------------------------------------------------- 
    Parent => CurrentELement % BoundaryInfo % Left
    stat = ASSOCIATED( Parent )
    IF (stat) stat = ALL(FlowPerm(Parent % NodeIndexes) > 0)
    IF ( .NOT. stat) THEN
      Parent => CurrentELement % BoundaryInfo % Right
      stat = ASSOCIATED( Parent )
      IF (stat) stat = ALL(FlowPerm(Parent % NodeIndexes) > 0)
      IF ( .NOT. stat )  CALL Fatal( 'AcousticsSolver', &
          'No parent element can be found for given boundary element' )
    END IF
    IF ( .NOT. CheckElementEquation( Model, &
        Parent, EquationName ) ) CYCLE
    !------------------------------------------------------------------------------
    DO i=1,Model % NumberOfBCs
      IF ( CurrentElement % BoundaryInfo % Constraint == &
          Model % BCs(i) % Tag ) THEN
        !------------------------------------------------------------------------------
        SlipBoundary = ListGetLogical( Model % BCs(i) % Values, &
            'Slip Boundary', GotIt )
        IF ( .NOT. SlipBoundary) CYCLE
        
        n = CurrentElement % TYPE % NumberOfNodes
        NodeIndexes => CurrentElement % NodeIndexes
        ElementNodes % x(1:n) = Solver % Mesh % Nodes % x(NodeIndexes)
        ElementNodes % y(1:n) = Solver % Mesh % Nodes % y(NodeIndexes)
        ElementNodes % z(1:n) = Solver % Mesh % Nodes % z(NodeIndexes)

        k = ListGetInteger( Model % Bodies(Parent % Bodyid) % Values, &
            'Material' )
        Material => Model % Materials(k) % Values
        SpecificHeat(1:n) = ListGetReal( Material, 'Specific Heat', &
            n, NodeIndexes )
        HeatRatio(1:n) = ListGetReal( Material, 'Specific Heat Ratio', &
            n, NodeIndexes )
        Density(1:n) = ListGetReal( Material, 'Equilibrium Density', &
            n, NodeIndexes )
        Conductivity(1:n) = ListGetReal( Material, 'Heat Conductivity', &
            n, NodeIndexes )   
        Temperature(1:n) = ListGetReal( Material, &
            'Equilibrium Temperature', n, NodeIndexes )
        Pressure(1:n) = (HeatRatio-1.0d0)* SpecificHeat * Density * Temperature
    
        WallTemperature(1:n) = ListGetReal(Model % BCs(i) % Values, &
            'Reference Wall Temperature', n, NodeIndexes )
        WallVelocity(1,1:n) = ListGetReal(Model % BCs(i) % Values, & 
            'Re Reference Wall Velocity 1', n, NodeIndexes, GotIt)
        WallVelocity(2,1:n) = ListGetReal(Model % BCs(i) % Values, & 
            'Im Reference Wall Velocity 1', n, NodeIndexes, GotIt )
        WallVelocity(3,1:n) = ListGetReal(Model % BCs(i) % Values, & 
            'Re Reference Wall Velocity 2', n, NodeIndexes, GotIt )
        WallVelocity(4,1:n) = ListGetReal(Model % BCs(i) % Values, & 
            'Im Reference Wall Velocity 2', n, NodeIndexes, GotIt )
        WallVelocity(5,1:n) = ListGetReal(Model % BCs(i) % Values, & 
            'Re Reference Wall Velocity 3', n, NodeIndexes, GotIt )
        WallVelocity(6,1:n) = ListGetReal(Model % BCs(i) % Values, & 
            'Im Reference Wall Velocity 3', n, NodeIndexes, GotIt )
        
        SlipCoefficient1 = ListGetConstReal( Model % BCs(i) % Values, &
            'Momentum Accommodation Coefficient')
        SlipCoefficient2 = ListGetConstReal( Model % BCs(i) % Values, &
            'Energy Accommodation Coefficient')
        !------------------------------------------------------------------------------
        !  Get element local matrix and rhs vector
        !------------------------------------------------------------------------------
        IF (CoordSys==Cartesian .OR. CoordSys==AxisSymmetric) THEN
          CALL SlipMatrix(  LocalStiffMatrix, LocalForce, SpecificHeat, &
              HeatRatio, Density, Conductivity, Pressure, Temperature, &
              AngularFrequency, WallTemperature, WallVelocity, SlipCoefficient1, &
              SlipCoefficient2, CurrentElement, n, ElementNodes, Dofs)
        END IF
        !------------------------------------------------------------------------------
        !          Update global matrix and rhs vector from local matrix & vector
        !------------------------------------------------------------------------------
        CALL UpdateGlobalEquations( StiffMatrix, LocalStiffMatrix, &
            ForceVector, LocalForce, n, Dofs, FlowPerm(NodeIndexes) )
        !------------------------------------------------------------------------------

        !-----------------------------------------------------------------------------
        ! Do an additional assembly for the preconditioners
        !----------------------------------------------------------------------------
        IF (BlockPreconditioning) THEN
          IF (ComponentwisePreconditioning) THEN
            CALL Fatal('AcousticsSolver',&
                'Componentwise Preconditioning cannot be used in the case of slip BC') 
          ELSE
            CALL VelocitySlipMatrix(  ALocal, SpecificHeat, &
                HeatRatio, Density, Temperature, &
                AngularFrequency, WallTemperature, SlipCoefficient1, &
                CurrentElement, n, ElementNodes, dim )
            CALL UpdateGlobalPreconditioner( AMatrix, ALocal, n, 2*dim, &
                Solver % Variable % Perm( CurrentElement % NodeIndexes ) )
          END IF
          !------------------------------------------------------------------------
          ! Slip BC for the Schur complement
          !------------------------------------------------------------------------
          CALL SchurComplementSlipMatrix( SLocal, SpecificHeat, &
              HeatRatio, Density, Temperature, AngularFrequency, Conductivity, & 
              WallTemperature, SlipCoefficient2, &
              CurrentElement, n, ElementNodes, dim)
          CALL UpdateGlobalPreconditioner( SMatrix, SLocal, n, 4, &
              Solver % Variable % Perm( CurrentElement % NodeIndexes ) )
        END IF
      END IF
    END DO
  !------------------------------------------------------------------------------
  END DO
  !------------------------------------------------------------------------------

  !------------------------------------------------------------------------------
  !     CALL FinishAssembly( Solver, ForceVector )
  !------------------------------------------------------------------------------
  !    Dirichlet BCs:
  !------------------------------------------------------------------------------
  DO i = 1, VelocityComponents
    WRITE(VariableName,'(A,A,I1)') 'Re Velocity',' ', i
    CALL SetDirichletBoundaries( Model, StiffMatrix, ForceVector, &
        VariableName, (i-1)*2+1, Dofs, FlowPerm )
    WRITE(VariableName,'(A,A,I1)') 'Im Velocity',' ', i
    CALL SetDirichletBoundaries( Model, StiffMatrix, ForceVector, &
        VariableName, (i-1)*2+2, Dofs, FlowPerm )
  END DO

  CALL SetDirichletBoundaries( Model, StiffMatrix, ForceVector, & 
      'Re Temperature', Dofs-3, Dofs, FlowPerm )
  CALL SetDirichletBoundaries( Model, StiffMatrix, ForceVector, & 
      'Im Temperature', Dofs-2, Dofs, FlowPerm )
  
  CALL Info( 'AcousticsSolver', 'Assembly done', Level=4 )

  !------------------------------------------------------------------------------
  ! Set Dirichlet BCs for the normal velocity on the slip boundary:
  ! Nothing is done in the current implementation as it is assumed that 
  ! the user specifies explicitly the boundary condition for the normal 
  ! velocity. 
  !----------------------------------------------------------------------------- 

  !-------------------------------------------------------------------------
  ! Set boundary conditions for the preconditioners...
  !-------------------------------------------------------------------------
     
  IF (BlockPreconditioning) THEN
    IF (ComponentwisePreconditioning) THEN
      CALL SetBoundaryConditions(Model, A1Matrix, 'Re Velocity 1', 1, 2,  &
          Solver % Variable % Perm)        
      CALL SetBoundaryConditions(Model, A1Matrix, 'Im Velocity 1', 2, 2,  &
          Solver % Variable % Perm)        
      CALL SetBoundaryConditions(Model, A2Matrix, 'Re Velocity 2', 1, 2,  &
          Solver % Variable % Perm)        
      CALL SetBoundaryConditions(Model, A2Matrix, 'Im Velocity 2', 2, 2,  &
          Solver % Variable % Perm)      
      IF (dim > 2) THEN
        CALL SetBoundaryConditions(Model, A3Matrix, 'Re Velocity 3', 1, 2,  &
            Solver % Variable % Perm)        
        CALL SetBoundaryConditions(Model, A3Matrix, 'Im Velocity 3', 2, 2,  &
            Solver % Variable % Perm)  
      END IF

      IF (AllocatedGradMatrices) THEN
        CALL SetBoundaryConditions2(Model, Grad1Matrix, 'Re Velocity 1', 1, 2,  &
            Solver % Variable % Perm)        
        CALL SetBoundaryConditions2(Model, Grad1Matrix, 'Im Velocity 1', 2, 2,  &
            Solver % Variable % Perm)        
        CALL SetBoundaryConditions2(Model, Grad2Matrix, 'Re Velocity 2', 1, 2,  &
            Solver % Variable % Perm)        
        CALL SetBoundaryConditions2(Model, Grad2Matrix, 'Im Velocity 2', 2, 2,  &
            Solver % Variable % Perm)
        IF (dim > 2) THEN
          CALL SetBoundaryConditions2(Model, Grad3Matrix, 'Re Velocity 3', 1, 2,  &
              Solver % Variable % Perm)        
          CALL SetBoundaryConditions2(Model, Grad3Matrix, 'Im Velocity 3', 2, 2,  &
              Solver % Variable % Perm) 
        END IF
      END IF
    ELSE
      CALL SetBoundaryConditions(Model, AMatrix, 'Re Velocity 1', 1, dim*2,  &
          Solver % Variable % Perm)        
      CALL SetBoundaryConditions(Model, AMatrix, 'Im Velocity 1', 2, dim*2,  &
          Solver % Variable % Perm)        
      CALL SetBoundaryConditions(Model, AMatrix, 'Re Velocity 2', 3, dim*2,  &
          Solver % Variable % Perm)        
      CALL SetBoundaryConditions(Model, AMatrix, 'Im Velocity 2', 4, dim*2,  &
          Solver % Variable % Perm)      
      IF (dim > 2) THEN
        CALL SetBoundaryConditions(Model, AMatrix, 'Re Velocity 3', 5, dim*2,  &
            Solver % Variable % Perm)        
        CALL SetBoundaryConditions(Model, AMatrix, 'Im Velocity 3', 6, dim*2,  &
            Solver % Variable % Perm)  
      END IF
    END IF

    CALL SetBoundaryConditions(Model, SMatrix, 'Re Temperature', 1, 4,  &
        Solver % Variable % Perm)
    CALL SetBoundaryConditions(Model, SMatrix, 'Im Temperature', 2, 4,  &
        Solver % Variable % Perm)

    !-----------------------------------------------------------------------------
    ! Boundary conditions for the Schur complement on the part of the boundary where 
    ! the normal component of the surface force vector is given  
    !-----------------------------------------------------------------------------
    IF (NumberOfNormalTractionNodes > 0) THEN
      m = 0
      DO t = Solver % Mesh % NumberOfBulkElements + 1,  &
          Solver % Mesh % NumberOfBulkElements + Solver % Mesh % NumberOfBoundaryElements
        !------------------------------------------------------------------------------
        CurrentElement => Solver % Mesh % Elements(t)
        Model % CurrentElement => CurrentElement
        !------------------------------------------------------------------------------
        DO i=1,Model % NumberOfBCs
          IF ( CurrentElement % BoundaryInfo % Constraint == &
              Model % BCs(i) % Tag ) THEN
            n = CurrentElement % TYPE % NumberOfNodes
            NodeIndexes => CurrentElement % NodeIndexes
            NormalTractionBoundary = ListGetLogical( Model % BCs(i) % Values, &
                'Prescribed Normal Traction', GotIt )
            IF ( .NOT. NormalTractionBoundary) CYCLE            
            IF ( ANY( FlowPerm(NodeIndexes) == 0 ) ) CYCLE

            k = ListGetInteger( Model % Bodies(Parent % Bodyid) % Values, &
                'Material' )
            Material => Model % Materials(k) % Values
            Density(1:n) = ListGetReal( Material, 'Equilibrium Density', &
                n, NodeIndexes )
            
            Load(1,1:n) = ListGetReal( Model % BCs(i) % Values, &
                'Re Normal Surface Force', n, NodeIndexes, GotIt )
            Load(2,1:n) = ListGetReal( Model % BCs(i) % Values, &
                'Im Normal Surface Force', n, NodeIndexes, GotIt )

            DO j=1,n
              k = FlowPerm(NodeIndexes(j))
              NormalTractionNodes(m+j) = k
              CALL ZeroRow( SMatrix,4*(k-1)+3 )
              CALL SetMatrixElement( SMatrix, 4*(k-1)+3, 4*(k-1)+3, 1.0d0 )
              CALL ZeroRow( SMatrix,4*k )
              CALL SetMatrixElement( SMatrix, 4*k, 4*k, 1.0d0 )
              
              NormalSurfaceForce(m+j) = -1.0d0/(AngularFrequency*Density(j)) * &
                  DCMPLX( Load(1,j),Load(2,j) )
            END DO
            m = m + n
          END IF
        END DO
      END DO
    END IF
  END IF

  !------------------------------------------------------------------------------
  !    Solve the linear system...
  !------------------------------------------------------------------------------
  !     PrevNorm = Norm
  at = CPUTime() - at
  st = CPUTime()

  IF ( BlockPreconditioning ) THEN
    IF (ComponentwisePreconditioning) THEN
      m = A1Matrix % NumberOfRows
    ELSE
      m = AMatrix % NumberOfRows / dim
    END IF
    SELECT CASE(OuterIterationMethod)
    CASE ('gcr')
      CALL GCROuterIteration( Solver % Matrix % NumberOfRows, Solver % Matrix, &
          m, A1Matrix, A2Matrix, A3Matrix, AMatrix, &
          SMatrix, Grad1Matrix, Grad2Matrix, Grad3Matrix, &
          Solver % Variable % Values, &
          Solver % Matrix % RHS, MaxIterations, Tolerance, dim )
    CASE('bicgstab')
      CALL OuterIteration( Solver % Matrix % NumberOfRows, Solver % Matrix, &
          m, A1Matrix, A2Matrix, A3Matrix, AMatrix, &
          SMatrix, Grad1Matrix, Grad2Matrix, Grad3Matrix, ChiConst, &
          Solver % Variable % Values, &
          Solver % Matrix % RHS, MaxIterations, Tolerance, dim )
    CASE DEFAULT
      CALL Fatal('AcousticsSolver', 'Unknown iteration method')         
    END SELECT
  ELSE
    CALL SolveSystem( StiffMatrix, ParMatrix, ForceVector, &
        Flow, Norm, Dofs, Solver )
!    CALL MonolithicSolve( Solver % Matrix % NumberOfRows, Solver % Matrix, &
!        Flow, ForceVector )
  END IF
  st = CPUTime() - st

!     IF ( PrevNorm + Norm /= 0.0d0 ) THEN
!        RelativeChange = 2*ABS(PrevNorm - Norm) / (PrevNorm + Norm)
!     ELSE
!        RelativeChange = 0.0d0
!     END IF

!     CALL Info( 'AcousticsSolver', ' ', Level=4 )
!     WRITE( Message, * ) 'Result Norm    : ', Norm
!     CALL Info( 'AcousticsSolver', Message, Level=4 )
!     WRITE( Message, * ) 'Relative Change: ', RelativeChange
!     CALL Info( 'AcousticsSolver', Message, Level=4 )

  WRITE(Message,'(a,F8.2)') ' Assembly: (s)', at  
  CALL Info( 'AcousticsSolver', Message, Level=4 )
  WRITE(Message,'(a,F8.2)') ' Solve:    (s)', st
  CALL Info( 'AcousticsSolver', Message, Level=4 )

  !------------------------------------------------------------------------------
  ! Overwrite the nodal values of the approximations of the div(v)-type term 
  ! and the scaled temperature in such a way that the resulting nodal values 
  ! are approximations to the true pressure and the temperature.
  !----------------------------------------------------------------------------- 
  VisitedNodes = .FALSE.
  DO t=1,Solver % Mesh % NumberOfBulkElements
    CurrentElement => Solver % Mesh % Elements(t)
    IF ( .NOT. CheckElementEquation( Model, &
        CurrentElement, EquationName ) ) CYCLE
    Model % CurrentElement => CurrentElement
    n = CurrentElement % TYPE % NumberOfNodes
    NodeIndexes => CurrentElement % NodeIndexes
    !------------------------------------------------------------------------------
    ! Get equation & material parameters
    !------------------------------------------------------------------------------
    k = ListGetInteger( Model % Bodies( CurrentElement % &
        Bodyid ) % Values, 'Material' )
    Material => Model % Materials(k) % Values

    SpecificHeat(1:n) = ListGetReal( Material, 'Specific Heat', &
        n, NodeIndexes )
    HeatRatio(1:n) = ListGetReal( Material, 'Specific Heat Ratio', &
        n, NodeIndexes )
    Temperature(1:n) = ListGetReal( Material, 'Equilibrium Temperature', &
        n, NodeIndexes )        
    Density(1:n) = ListGetReal( Material, 'Equilibrium Density', &
        n, NodeIndexes )
    Viscosity(1:n) = ListGetReal( Material, 'Viscosity', &
        n, NodeIndexes )   
    Lambda = -2.0d0/3.0d0 * Viscosity
    BulkViscosity(1:n) = ListGetReal( Material, ' Bulk Viscosity', &
        n, NodeIndexes, GotIt )
    IF (GotIt) Lambda = BulkViscosity - 2.0d0/3.0d0 * Viscosity
    Pressure(1:n) = (HeatRatio-1.0d0)* SpecificHeat * Density * Temperature
    
    DO i=1,n
      j = NodeIndexes(i)
      IF ( .NOT. VisitedNodes(j) ) THEN
        VisitedNodes(j) = .TRUE.
        !-------------------------------------
        ! Rescaling of the pressure...
        !--------------------------------------
        A = AngularFrequency * Density(i) * ( DCMPLX( Flow( (j-1)*Dofs+VelocityDofs+1 ), &
            Flow( (j-1)*Dofs+VelocityDofs+2 ) ) + &
            1.0d0/DCMPLX( 1.0d0, Lambda(i)*AngularFrequency/Pressure(i) ) * &
            DCMPLX( Flow( (j-1)*Dofs+VelocityDofs+3 ), &
            Flow( (j-1)*Dofs+VelocityDofs+4 ) ) )
        Flow( (j-1)*Dofs+VelocityDofs+3 ) = REAL(A)
        Flow( (j-1)*Dofs+VelocityDofs+4 ) = AIMAG(A)
        !-------------------------------------
        ! Rescaling of the temperature...
        !--------------------------------------
        A = AngularFrequency * Density(i) * Temperature(i)/Pressure(i) * &
            DCMPLX( Flow( (j-1)*Dofs+VelocityDofs+1 ), &
            Flow( (j-1)*Dofs+VelocityDofs+2 ) )
        Flow( (j-1)*Dofs+VelocityDofs+1 ) = REAL(A)
        Flow( (j-1)*Dofs+VelocityDofs+2 ) = AIMAG(A)
      END IF
    END DO
  END DO

  !------------------------------------------------------------------------------
  ! Check if computing acoustic impedance required
  !------------------------------------------------------------------------------
  ALLOCATE( Bndries( Model % NumberOfBCs ) )
  Bndries = 0
  
  AcousticI = 0
  DO i = 1, Model % NumberOfBCs
    IF ( ListGetLogical( Model % BCs(i) % Values, &
        'Calculate Acoustic Impedance', GotIt ) ) THEN
      AcousticI = 1
      Bndries(1) = i
      EXIT
    END IF
  END DO

  IF ( AcousticI > 0 ) THEN
    j = 1
    DO i = 1, Model % NumberOfBCs
      IF ( ListGetLogical( Model % BCs(i) % Values, &
          'Impedance Target Boundary', GotIt ) ) THEN
        AcousticI = AcousticI + 1
        j = j + 1
        Bndries(j) = i
      END IF
    END DO

    ALLOCATE( AcImpedances( AcousticI, 2 ) )
    CALL ComputeAcousticImpedance( AcousticI, Bndries, AcImpedances )

    WRITE( Message, * ) 'Self specific acoustic impedance on bc ', &
        Bndries(1)
    CALL INFO( 'Acoustics', Message, LEVEL=5 )
    WRITE( Message, * ) '  In-phase with velocity:     ', &
        AcImpedances(1,1)
    CALL INFO( 'Acoustics', Message, LEVEL=5 )
    WRITE( Message, * ) '  Out-of-phase with velocity: ', &
        AcImpedances(1,2)
    CALL INFO( 'Acoustics', Message, LEVEL=5 )

    DO i = 2, AcousticI
      WRITE( Message, * ) 'Cross specific acoustic impedance, bcs ', &
          Bndries(i), ' , ', Bndries(1)
      CALL INFO( 'Acoustics', Message, LEVEL=5 )
      WRITE( Message, * ) '  In-phase with velocity:     ', &
          AcImpedances(i,1)
      CALL INFO( 'Acoustics', Message, LEVEL=5 )
      WRITE( Message, * ) '  Out-of-phase with velocity: ', &
          AcImpedances(i,2)
      CALL INFO( 'Acoustics', Message, LEVEL=5 )
    END DO

    DO i = 2, AcousticI
      WRITE( Message, '(A,I1,A,I1)' ) &
          'res: out-of-phase cross acoustic impedance ', &
          Bndries(AcousticI - i + 2), ' , ', Bndries(1)
      CALL ListAddConstReal( Model % Simulation, Message, &
          AcImpedances(AcousticI - i + 2,2) )
      WRITE( Message, '(A,I1,A,I1)' ) &
          'res: in-phase cross acoustic impedance ', &
          Bndries(AcousticI - i + 2), ' , ', Bndries(1)
      CALL ListAddConstReal( Model % Simulation, Message, &
          AcImpedances(AcousticI - i + 2,1) )
    END DO

    WRITE( Message, '(A,I1)' ) &
        'res: out-of-phase self acoustic impedance ', &
        Bndries(1)
    CALL ListAddConstReal( Model % Simulation, Message, &
        AcImpedances(1,2) )
    WRITE( Message, '(A,I1)' ) &
        'res: in-phase self acoustic impedance ', &
        Bndries(1)
    CALL ListAddConstReal( Model % Simulation, Message, &
        AcImpedances(1,1) )
    
    DEALLOCATE( AcImpedances )
  END IF

  DEALLOCATE( Bndries )

!------------------------------------------------------------------------------
  CALL ListAddConstReal( Model % Simulation, 'res: frequency', &
      AngularFrequency / (2*PI) )
!------------------------------------------------------------------------------



CONTAINS

!-----------------------------------------------------------------------------------
  SUBROUTINE MonolithicSolve( n, A, x, b)
!-----------------------------------------------------------------------------------
    INTEGER :: n
    TYPE(Matrix_t), POINTER :: A
    REAL(KIND=dp) :: x(n), b(n)
    !------------------------------------------------------------------------------
    REAL(KIND=dp) :: Tol
    INTEGER :: Rounds, m, IluOrder, PrecondType
    COMPLEX(KIND=dp) :: y(n/2), f(n/2)
    LOGICAL :: Condition, GotIt    
    CHARACTER(LEN=MAX_NAME_LEN) :: str
    !------------------------------------------------------------------------------
    Tol = ListGetConstReal( Solver % Values, &
        'Linear System Convergence Tolerance' )
    Rounds = ListGetInteger( Solver % Values, &
        'Linear System Max Iterations')
    m = n/2
    str = ListGetString( Solver % Values, &
      'Linear System Preconditioning',GotIt )

    IF (GotIt .AND. str(1:3) == 'ilu') THEN
      IluOrder = ICHAR(str(4:4)) - ICHAR('0')
      IF ( IluOrder  < 0 .OR. IluOrder > 9 ) IluOrder = 0
      Condition = CRS_ComplexIncompleteLU( A, IluOrder )
      PrecondType = 1
    ELSE
      PrecondType = 0
    END IF
    !----------------------------------------------------------------------------
    ! Transform the solution vector x and the right-hand side vector b to 
    ! complex-valued vectors y and f
    !---------------------------------------------------------------------------
    DO i=1,m
      y(i) = DCMPLX( x(2*i-1), x(2*i) )
      f(i) = DCMPLX( b(2*i-1), b(2*i) )
    END DO
    CALL ComplexBiCGStab( n, A, y, f, Rounds, Tol, PrecondType) 
!-----------------------------------------------------------------------------------
  END SUBROUTINE MonolithicSolve
!-----------------------------------------------------------------------------------

!------------------------------------------------------------------------------
  SUBROUTINE OuterIteration( n, A, q, PA1, PA2, PA3, PA, PS, Grad1, Grad2, Grad3, &
      ChiConst, x, b, Rounds, TOL, dim )
!------------------------------------------------------------------------------
!   This is a block preconditioned BiCGStab iteration for the complex linear 
!   system Ax=b. The preconditioner is constructed by using inner iterations 
!   for systems M*y=f and PS*z=g with either M = diag(PA1,PA2,PA3) or M = PA. 
!------------------------------------------------------------------------------  
    TYPE(Matrix_t), POINTER :: A, PA1, PA2, PA3, PA, PS, Grad1, Grad2, Grad3
    INTEGER :: n, q, Rounds, dim
    COMPLEX(KIND=dp) :: ChiConst
    REAL(KIND=dp) :: x(n), b(n), TOL
    !-------------------------------------------------------------------------------
    INTEGER :: i, j, k, m, InnerRounds, Ptr, Deg, MaxDeg=10, IluOrder, &
        VelocityPrecond = 1, ne
    LOGICAL :: Condition, TrivialCase, PressureBasedCriterion, GotIt, &
        ComputeTrueResiduals
    REAL(KIND=dp) :: res, tottime, res0, const, stime, norm, InnerTol, &
        PresChange(10), TrueRes
    COMPLEX(KIND=dp) :: r(n/2),Ri(n/2),P(n/2),V(n/2),T(n/2),T1(n/2),T2(n/2),S(n/2), &
        y(n/2), f(n/2), z(q/2), g(q/2), e(n/2), w(q), Pres(q/2), PrevPres(q/2), &
        h(q), Vel(dim*q/2), VelRhs(dim*q/2)
    COMPLEX(KIND=dp) :: alpha,beta,omega,rho,oldrho,complexconst
    !------------------------------------------------------------------------------

    !-------------------------------------------------------------------------------
    ! Compute ILU factorizations for the preconditioner matrices. 
    ! This needs to be done only once. 
    !-------------------------------------------------------------------------------
    IluOrder = ListGetInteger( Solver % Values, 'ILU Order for Schur Complement') 

    CALL Info( 'AcousticsSolver', ' ', Level=4)
    CALL Info( 'AcousticsSolver', 'ILU factorization for the Schur complement preconditioner', &
        Level=4)
    CALL Info( 'AcousticsSolver', ' ', Level=4)
    Condition = CRS_ComplexIncompleteLU( PS, IluOrder )

    IluOrder = ListGetInteger( Solver % Values, 'ILU Order for Velocities', GotIt)     
    IF (GotIt) THEN
      IF (ComponentwisePreconditioning) THEN
        CALL Info( 'AcousticsSolver', ' ', Level=4)
        CALL Info( 'AcousticsSolver', 'ILU factorization for the Velocity 1 preconditioner', &
            Level=4)
        CALL Info( 'AcousticsSolver', ' ', Level=4)
        Condition = CRS_ComplexIncompleteLU( PA1, IluOrder )

        CALL Info( 'AcousticsSolver', ' ', Level=4)
        CALL Info( 'AcousticsSolver', 'ILU factorization for the Velocity 2 preconditioner', &
            Level=4)
        CALL Info( 'AcousticsSolver', ' ', Level=4)
        Condition = CRS_ComplexIncompleteLU( PA2, IluOrder )

        IF (dim > 2) THEN
          CALL Info( 'AcousticsSolver', ' ', Level=4)
          CALL Info( 'AcousticsSolver', 'ILU factorization for the Velocity 3 preconditioner', &
              Level=4)
          CALL Info( 'AcousticsSolver', ' ', Level=4)
          Condition = CRS_ComplexIncompleteLU( PA3, IluOrder )
        END IF
      ELSE
        CALL Info( 'AcousticsSolver', ' ', Level=4)
        CALL Info( 'AcousticsSolver', 'ILU factorization for the Velocity preconditioner', &
            Level=4)
        CALL Info( 'AcousticsSolver', ' ', Level=4)
        Condition = CRS_ComplexIncompleteLU( PA, IluOrder )
      END IF
    ELSE
      VelocityPrecond = 0
    END IF

    !----------------------------------------------------------------------------
    ! Some initializations
    !----------------------------------------------------------------------------  
    ComputeTrueResiduals = .FALSE.
    PressureBasedCriterion = .FALSE.
    PressureBasedCriterion = ListGetLogical( Solver % Values, &
        'Pressure-Based Convergence Criterion')    
    IF (PressureBasedCriterion) THEN
      Deg = ListGetInteger( Solver % Values, 'Degree of Averaging', GotIt, 1, MaxDeg)
      IF (.NOT. GotIt) Deg = 1
      Pres(1:q/2) = DCMPLX( 0.0d0, 0.0d0)
      PrevPres(1:q/2) = DCMPLX( 0.0d0, 0.0d0)
      PresChange(1:MaxDeg) = 0.0d0
    END IF

    InnerTol = ListGetConstReal( Solver % Values, &
        'Linear System Convergence Tolerance' )
    InnerRounds = ListGetInteger( Solver % Values, &
        'Linear System Max Iterations') 

    !--------------------------------------------------------------------------------
    ! The solution of an initial guess
    !-------------------------------------------------------------------------------- 
    IF (NumberOfNormalTractionNodes > 0) THEN
      x(1:n) = 0.0d0
      V(1:n/2) = DCMPLX( 0.0d0,0.0d0 )
      IF ( ANY( NormalSurfaceForce /= CMPLX( 0.0d0,0.0d0 ) ) ) THEN
        !-----------------------------------------------------------------
        ! The solution of the Schur complement equation...
        !------------------------------------------------------------------ 
        w(1:q) = DCMPLX( 0.0d0,0.0d0 )
        h(1:q) = DCMPLX( 0.0d0,0.0d0 )
        !-----------------------------------------------------------------------
        ! Modify the right-hand side vector h so that the boundary condition 
        ! for the normal surface force will be satisfied
        !-----------------------------------------------------------------------
        DO k=1,NumberOfNormalTractionNodes
          m = NormalTractionNodes(k)
          h(2*m) = NormalSurfaceForce(k)
        END DO
        !-----------------------------------------------------------------
        CALL Info( 'AcousticssSolver', ' ', Level=4)
        CALL Info( 'AcousticsSolver', &
            'Solving initial guess for the pressure', Level=4)
        CALL Info( 'AcousticsSolver', ' ', Level=4)
        !-------------------------------------------------------------------
        CALL ComplexBiCGStab( 2*q, PS, w, h, InnerRounds, InnerTol )
        DO j=1,q/2
          x(2*(dim+2)*(j-1)+dim*2+1) = REAL(w(2*j-1))
          x(2*(dim+2)*(j-1)+dim*2+2) = AIMAG(w(2*j-1))
          complexconst = ChiConst*( w(2*j) - w(2*j-1) )
          x(2*(dim+2)*(j-1)+dim*2+3) = REAL(complexconst)
          x(2*(dim+2)*(j-1)+dim*2+4) = AIMAG(complexconst)  
        END DO

        !-------------------------------------------------------
        ! The computation of the specific matrix vector products
        !-------------------------------------------------------
        IF (.NOT. AllocatedGradMatrices) THEN
          DO i=1,n/2
            y(i) = DCMPLX( x(2*i-1), x(2*i) )
          END DO
          CALL ComplexMatrixVectorProduct2(A,y,V,dim)          
        ELSE
          DO j=1,q/2
            g(j) = DCMPLX( x(2*(dim+2)*j-1),x(2*(dim+2)*j) )
          END DO
          CALL ComplexMatrixVectorProduct( Grad1,g,z )
          DO j=1,q/2
            V((dim+2)*(j-1)+1) =  V((dim+2)*(j-1)+1) - z(j)        
          END DO
          CALL ComplexMatrixVectorProduct( Grad2,g,z )
          DO j=1,q/2
            V((dim+2)*(j-1)+2) =  V((dim+2)*(j-1)+2) - z(j)        
          END DO
          IF (dim > 2) THEN
            CALL ComplexMatrixVectorProduct( Grad3,g,z )
            DO j=1,q/2
              V((dim+2)*(j-1)+3) =  V((dim+2)*(j-1)+3) - z(j)        
            END DO
          END IF

          DO j=1,q/2
            g(j) = DCMPLX( x(2*(dim+2)*j-3),x(2*(dim+2)*j)-2 )       
          END DO
          CALL ComplexMatrixVectorProduct( Grad1,g,z )
          DO j=1,q/2
            V((dim+2)*(j-1)+1) =  V((dim+2)*(j-1)+1) - z(j)        
          END DO
          CALL ComplexMatrixVectorProduct( Grad2,g,z )
          DO j=1,q/2
            V((dim+2)*(j-1)+2) =  V((dim+2)*(j-1)+2) - z(j)        
          END DO
          IF (dim > 2) THEN
            CALL ComplexMatrixVectorProduct( Grad3,g,z )
            DO j=1,q/2
              V((dim+2)*(j-1)+3) =  V((dim+2)*(j-1)+3) - z(j)        
            END DO
          END IF
        END IF
      END IF
      !---------------------------------------------------------
      ! The computation of the velocities
      !---------------------------------------------------------
      IF (ComponentwisePreconditioning) THEN
        z(1:q/2) = DCMPLX( 0.0d0,0.0d0 )
        TrivialCase = .TRUE.
        DO j=1,q/2
          g(j) = DCMPLX( b(2*(dim+2)*(j-1)+1),b(2*(dim+2)*(j-1)+2) ) + &
              V((dim+2)*(j-1)+1)
          IF (CDABS(g(j)) > AEPS) TrivialCase = .FALSE.
        END DO
        IF ( .NOT. TrivialCase ) THEN
          !-----------------------------------------------------------------
          CALL Info( 'AcousticsSolver', ' ', Level=4)
          CALL Info( 'AcousticsSolver', &
              'Solving initial guess for Velocity 1', Level=4)
          CALL Info( 'AcousticsSolver', ' ', Level=4)
          !------------------------------------------------------------------
          CALL ComplexBiCGStab( q, PA1, z, g, InnerRounds, InnerTol, VelocityPrecond)
        END IF
        DO j=1,q/2
          x(2*(dim+2)*(j-1)+1) = REAL(z(j))
          x(2*(dim+2)*(j-1)+2) = AIMAG(z(j))
        END DO

        z(1:q/2) = DCMPLX( 0.0d0,0.0d0 )
        TrivialCase = .TRUE.
        DO j=1,q/2
          g(j) =  DCMPLX( b(2*(dim+2)*(j-1)+3),b(2*(dim+2)*(j-1)+4) ) + &
              V((dim+2)*(j-1)+2)            
          IF (CDABS(g(j)) > AEPS) TrivialCase = .FALSE.
        END DO
        IF ( .NOT. TrivialCase ) THEN
          !-----------------------------------------------------------------
          CALL Info( 'AcousticsSolver', ' ', Level=4)
          CALL Info( 'AcosuticsSolver', &
              'Solving initial guess for Velocity 2', Level=4)
          CALL Info( 'AcousticsSolver', ' ', Level=4)
          !------------------------------------------------------------------
          CALL ComplexBiCGStab( q, PA2, z, g, InnerRounds, InnerTol, VelocityPrecond )
        END IF
        DO j=1,q/2
          x(2*(dim+2)*(j-1)+3) = REAL(z(j))
          x(2*(dim+2)*(j-1)+4) = AIMAG(z(j)) 
        END DO

        IF (dim > 2) THEN
          z(1:q/2) = DCMPLX( 0.0d0,0.0d0 )
          TrivialCase = .TRUE.
          DO j=1,q/2
            g(j) =  DCMPLX( b(2*(dim+2)*(j-1)+5),b(2*(dim+2)*(j-1)+6) ) + &
                V((dim+2)*(j-1)+3)            
            IF (CDABS(g(j)) > AEPS) TrivialCase = .FALSE.
          END DO
          IF ( .NOT. TrivialCase ) THEN
            !-----------------------------------------------------------------
            CALL Info( 'AcousticsSolver', ' ', Level=4)
            CALL Info( 'AcosuticsSolver', &
                'Solving initial guess for Velocity 3', Level=4)
            CALL Info( 'AcousticsSolver', ' ', Level=4)
            !------------------------------------------------------------------
            CALL ComplexBiCGStab( q, PA3, z, g, InnerRounds, InnerTol, VelocityPrecond )
          END IF
          DO j=1,q/2
            x(2*(dim+2)*(j-1)+5) = REAL(z(j))
            x(2*(dim+2)*(j-1)+6) = AIMAG(z(j)) 
          END DO
        END IF
      ELSE
        Vel(1:dim*q/2) = DCMPLX( 0.0d0,0.0d0 )
        TrivialCase = .TRUE.
        DO i=1,dim
          DO j=1,q/2
            VelRhs((j-1)*dim+i) = DCMPLX( b(2*(dim+2)*(j-1)+2*i-1), &
                b(2*(dim+2)*(j-1)+2*i) ) + V((dim+2)*(j-1)+i)
            IF ( CDABS(VelRhs((j-1)*dim+i)) > AEPS ) TrivialCase = .FALSE.
          END DO
        END DO
        IF ( .NOT. TrivialCase ) THEN
          !-----------------------------------------------------------------
          CALL Info( 'AcousticsSolver', ' ', Level=4)
          CALL Info( 'AcousticsSolver', &
              'Solving initial guess for Velocities', Level=4)
          CALL Info( 'AcousticsSolver', ' ', Level=4)
          !------------------------------------------------------------------
          CALL ComplexBiCGStab( q*dim, PA, Vel, VelRhs, InnerRounds, InnerTol, VelocityPrecond )
        END IF
        DO j=1,q/2
          DO i=1,dim
            x(2*(dim+2)*(j-1)+2*i-1) = REAL(Vel((j-1)*dim+i))
            x(2*(dim+2)*(j-1)+2*i) = AIMAG(Vel((j-1)*dim+i))
          END DO
        END DO
      END IF
    ELSE
      !------------------------------------------------------------------------------------
      ! This branch is for computing the initial guess in the case of pure velocity BC 
      !------------------------------------------------------------------------------------
      x(1:n) = 0.0d0 ! This prevents the use previous solution as the initial guess       
      IF (ComponentwisePreconditioning) THEN
        z(1:q/2) = DCMPLX( 0.0d0,0.0d0 )
        TrivialCase = .TRUE.
        DO j=1,q/2
          g(j) = DCMPLX( b(2*(dim+2)*(j-1)+1),b(2*(dim+2)*(j-1)+2) )
          IF (CDABS(g(j)) > AEPS) TrivialCase = .FALSE.
        END DO
        IF ( .NOT. TrivialCase ) THEN
          !-----------------------------------------------------------------
          CALL Info( 'AcousticsSolver', ' ', Level=4)
          CALL Info( 'AcousticsSolver', &
              'Solving initial guess for Velocity 1', Level=4)
          CALL Info( 'AcousticsSolver', ' ', Level=4)
          !------------------------------------------------------------------
          CALL ComplexBiCGStab( q, PA1, z, g, InnerRounds, InnerTol, VelocityPrecond )
        END IF
        DO j=1,q/2
          x(2*(dim+2)*(j-1)+1) = REAL(z(j))
          x(2*(dim+2)*(j-1)+2) = AIMAG(z(j))
        END DO

        TrivialCase = .TRUE.
        z(1:q/2) = DCMPLX( 0.0d0,0.0d0 )
        DO j=1,q/2
          g(j) =  DCMPLX( b(2*(dim+2)*(j-1)+3),b(2*(dim+2)*(j-1)+4) )
          IF (CDABS(g(j)) > AEPS) TrivialCase = .FALSE.
        END DO
        IF ( .NOT. TrivialCase ) THEN
          !-----------------------------------------------------------------
          CALL Info( 'AcousticsSolver', ' ', Level=4)
          CALL Info( 'AcousticsSolver', &
              'Solving initial guess for Velocity 2', Level=4)
          CALL Info( 'AcousticsSolver', ' ', Level=4)
          !------------------------------------------------------------------
          CALL ComplexBiCGStab( q, PA2, z, g, InnerRounds, InnerTol, VelocityPrecond )
        END IF
        DO j=1,q/2
          x(2*(dim+2)*(j-1)+3) = REAL(z(j))
          x(2*(dim+2)*(j-1)+4) = AIMAG(z(j)) 
        END DO

        IF (dim > 2) THEN
          z(1:q/2) = DCMPLX( 0.0d0,0.0d0 )
          TrivialCase = .TRUE.
          DO j=1,q/2
            g(j) =  DCMPLX( b(2*(dim+2)*(j-1)+5),b(2*(dim+2)*(j-1)+6) )
            IF (CDABS(g(j)) > AEPS) TrivialCase = .FALSE.
          END DO
          IF ( .NOT. TrivialCase ) THEN
            !-----------------------------------------------------------------
            CALL Info( 'AcousticsSolver', ' ', Level=4)
            CALL Info( 'AcosuticsSolver', &
                'Solving initial guess for Velocity 3', Level=4)
            CALL Info( 'AcousticsSolver', ' ', Level=4)
            !------------------------------------------------------------------
            CALL ComplexBiCGStab( q, PA3, z, g, InnerRounds, InnerTol, VelocityPrecond )
          END IF
          DO j=1,q/2
            x(2*(dim+2)*(j-1)+5) = REAL(z(j))
            x(2*(dim+2)*(j-1)+6) = AIMAG(z(j)) 
          END DO
        END IF
      ELSE
        Vel(1:dim*q/2) = DCMPLX( 0.0d0,0.0d0 )
        TrivialCase = .TRUE.
        DO i=1,dim
          DO j=1,q/2
            VelRhs((j-1)*dim+i) = DCMPLX( b(2*(dim+2)*(j-1)+2*i-1), &
                b(2*(dim+2)*(j-1)+2*i) )
            IF ( CDABS(VelRhs((j-1)*dim+i)) > AEPS ) TrivialCase = .FALSE.
          END DO
        END DO
        IF ( .NOT. TrivialCase ) THEN
          !-----------------------------------------------------------------
          CALL Info( 'AcousticsSolver', ' ', Level=4)
          CALL Info( 'AcousticsSolver', &
              'Solving initial guess for Velocities', Level=4)
          CALL Info( 'AcousticsSolver', ' ', Level=4)
          !------------------------------------------------------------------
          CALL ComplexBiCGStab( q*dim, PA, Vel, VelRhs, InnerRounds, InnerTol, VelocityPrecond )
        END IF
        DO j=1,q/2
          DO i=1,dim
            x(2*(dim+2)*(j-1)+2*i-1) = REAL(Vel((j-1)*dim+i))
            x(2*(dim+2)*(j-1)+2*i) = AIMAG(Vel((j-1)*dim+i))
          END DO
        END DO
      END IF
    END IF
    !--------------------------------------------------------------------------------
    ! The start of the BiCGStab iteration... 
    !--------------------------------------------------------------------------------     
    m = n/2
    !----------------------------------------------------------------------------
    ! Transform the solution vector x and the right-hand side vector b to 
    ! complex-valued vectors y and f
    !---------------------------------------------------------------------------
    DO i=1,m
      y(i) = DCMPLX( x(2*i-1), x(2*i) )
      f(i) = DCMPLX( b(2*i-1), b(2*i) )
    END DO

    CALL ComplexMatrixVectorProduct( A, y, r )
    r(1:m) = f(1:m) - r(1:m)
!    res0 = ComplexNorm(m,f)

    IF (PressureBasedCriterion) THEN
      WRITE(*,'(a,I4,ES12.3,ES12.3)') 'OuterIteration residuals for iterate', 0, 1.0d0, &
          StoppingCriterion( m, A, y, f, r )
    ELSE
      WRITE(*,'(a,I4,ES12.3)') 'OuterIteration residual for iterate', 0, &
          StoppingCriterion( m, A, y, f, r )
    END IF
    
    Ri(1:m) = r(1:m)
    P(1:m) = DCMPLX( 0.0d0, 0.0d0)
    V(1:m) = DCMPLX( 0.0d0, 0.0d0)
    omega  = DCMPLX( 1.0d0, 0.0d0)
    alpha  = DCMPLX( 0.0d0, 0.0d0)
    oldrho = DCMPLX( 1.0d0, 0.0d0)
    tottime = CPUTime()

    DO i=1,Rounds
      rho = ComplexDotProduct( m, Ri, r )
      beta = alpha * rho / ( oldrho * omega )
      P(1:m) = r(1:m) + beta * (P(1:m) - omega*V(1:m))
      V(1:m) = P(1:m)
      !----------------------------------------------------------
      ! Perform the preconditioning...
      !---------------------------------------------------------------
      CALL InnerPreconditioningIteration( n, A, q, PA1, PA2, PA3, PA, &
          PS, Grad1, Grad2, Grad3, ChiConst, V, dim, Solver, VelocityPrecond )
      !--------------------------------------------------------------
      T1(1:m) = V(1:m)
      CALL ComplexMatrixVectorProduct( A, T1, V )
      alpha = rho / ComplexDotProduct( m, Ri, V )
      S(1:m) = r(1:m) - alpha * V(1:m)
      
      !---------------------------------------------------------------------------------
      ! The update of the solution and the computation of the residual-based error indicator  
      !---------------------------------------------------------------------------------
      IF (PressureBasedCriterion) THEN
        IF (i==1) THEN
          y(1:m) = y(1:m) + alpha*T1(1:m)
        ELSE
          DO j=1,q/2 
            PrevPres(j) = y((dim+2)*j-1) + y((dim+2)*j) 
          END DO
          y(1:m) = y(1:m) + alpha*T1(1:m)
        END IF
      ELSE
        y(1:m) = y(1:m) + alpha*T1(1:m)
        ! res = ComplexNorm(m,S)/res0
        res = StoppingCriterion( m, A, y, f, S )
        IF ( res < TOL ) THEN
          WRITE(*,'(a,I4,ES12.3)') 'OuterIteration residual for iterate', i, res
          WRITE(*,'(a,ES12.3)') 'An approximate lower bound for the condition number: ', &
              ConditionEstimate( m, A, y, f, S )
          EXIT
        END IF
      END IF

      T(1:m) = S(1:m)
      !----------------------------------------------------------
      ! Perform the preconditioning...
      !-----------------------------------------------------------------         
      CALL InnerPreconditioningIteration( n, A, q, PA1, PA2, PA3, PA, &
          PS, Grad1, Grad2, Grad3, ChiConst, T, dim, Solver, VelocityPrecond )
      !-----------------------------------------------------------------
      T2(1:m) = T(1:m)
      CALL ComplexMatrixVectorProduct( A, T2, T )
      omega = ComplexDotProduct( m,T,S ) / ComplexDotProduct( m,T,T )
      oldrho = rho
      r(1:m) = S(1:m) - omega*T(1:m)
      y(1:m) = y(1:m) + omega*T2(1:m)

      !------------------------------------------
      ! Check the accuracy of the residual
      !------------------------------------------
      IF (ComputeTrueResiduals) THEN
        e(1:m) = DCMPLX( 0.0d0,0.0d0 )
        CALL ComplexMatrixVectorProduct( A, y, e )
        e(1:m) = f(1:m) - e(1:m)
        norm = ComplexNorm(m,e(1:m)-r(1:m))/ComplexNorm(m,e(1:m))
        WRITE(*,'(a,ES12.3)') 'Relative error of the residual: ', norm
      END IF
      !---------------------------------------------- 

      IF (PressureBasedCriterion) THEN
        IF (i==1) THEN
          IF ( Rounds==1 ) THEN
            WRITE(*,'(a)') 'The error indicator cannot be computed using one iterate'
            EXIT
          ELSE
            WRITE(*,'(a,I4,ES12.3,ES12.3)') 'OuterIteration residuals for iterate', i, 1.0d0, &
                StoppingCriterion( m, A, y, f, r )
            CYCLE
          END IF
        ELSE
          !-----------------------------------------
          ! Compute the new pressure-like solution
          !-----------------------------------------          
          DO j=1,q/2
            Pres(j) = y((dim+2)*j-1) + y((dim+2)*j) 
          END DO          
          !------------------------------------------------------------
          ! Save the relative change in the solution in an array and 
          ! compute the error indicator
          !------------------------------------------------------------
          Ptr = MOD(i-1,Deg)
          IF (Ptr==0) Ptr = Deg
          PresChange(Ptr) = ComplexNorm(q/2,Pres-PrevPres)/ComplexNorm(q/2,Pres)
          IF ( (i-1) < Deg) THEN
            res = SUM(PresChange(1:Ptr))/Ptr
          ELSE
            res = SUM(PresChange(1:Deg))/Deg 
          END IF
        END IF
      ELSE
        !  res = ComplexNorm(m,r)/res0
        res = StoppingCriterion( m, A, y, f, r ) 
      END IF

      IF (PressureBasedCriterion) THEN
        TrueRes = StoppingCriterion( m, A, y, f, r )
        WRITE(*,'(a,I4,ES12.3,ES12.3)') 'OuterIteration residuals for iterate', i, res, TrueRes
      ELSE
        WRITE(*,'(a,I4,ES12.3)') 'OuterIteration residual for iterate', i, res
      END IF

      IF ( res < TOL .OR. i==Rounds) THEN
        WRITE(*,'(a,ES12.3)') 'An approximate lower bound for the condition number: ', &
            ConditionEstimate( m, A, y, f, r )
        EXIT
      END IF
    END DO

    ! Return the solution as a real vector...
    DO i=1,m
      x( 2*i-1 ) = REAL( y(i) )
      x( 2*i ) = AIMAG( y(i) )
    END DO

!------------------------------------------------------------------------------
   END SUBROUTINE OuterIteration
!------------------------------------------------------------------------------




!------------------------------------------------------------------------------
  SUBROUTINE GCROuterIteration( n, A, q, PA1, PA2, PA3, PA, PS, Grad1, Grad2, Grad3, &
      x, b, Rounds, TOL, dim )
!------------------------------------------------------------------------------
!    This is the preconditioned GCR iteration for the complex linear system Ax=b.
!    The preconditioning strategy is based on block factorization.
!------------------------------------------------------------------------------  
    TYPE(Matrix_t), POINTER :: A, PA1, PA2, PA3, PA, PS, Grad1, Grad2, Grad3
    INTEGER :: n, q, Rounds, dim
    REAL(KIND=dp) :: x(n), b(n), TOL
!-------------------------------------------------------------------------------
    INTEGER :: i, j, k, m, InnerRounds, IluOrder
    LOGICAL :: Condition, TrivialCase
    REAL(KIND=dp) :: res, tottime, res0, const, stime, norm, InnerTol, alpha, Pnorm
    COMPLEX(KIND=dp) :: r(n/2),P(n/2),T(n/2),T1(n/2),T2(n/2), &
        S(n/2,Rounds), V(n/2,Rounds), y(n/2), f(n/2), z(q/2), g(q/2),e(n/2)
    COMPLEX(KIND=dp) :: beta 
!------------------------------------------------------------------------------


!-------------------------------------------------------------------------------
!    Compute ILU factorizations for the preconditioner matrices. 
!    This needs to be done only once. 
!-------------------------------------------------------------------------------

    IluOrder = ListGetInteger( Solver % Values, 'ILU Order for Schur Complement') 

    CALL Info( 'AcousticsSolver', ' ', Level=4)
    CALL Info( 'AcousticsSolver', 'ILU factorization for the Schur complement preconditioner', &
        Level=4)
    CALL Info( 'AcousticsSolver', ' ', Level=4)
    Condition = CRS_ComplexIncompleteLU( PS, IluOrder )

    IluOrder = ListGetInteger( Solver % Values, 'ILU Order for Velocities') 

    CALL Info( 'AcousticsSolver', ' ', Level=4)
    CALL Info( 'AcousticsSolver', 'ILU factorization for the Velocity 1 preconditioner', &
        Level=4)
    CALL Info( 'AcousticsSolver', ' ', Level=4)
    Condition = CRS_ComplexIncompleteLU( PA1, IluOrder )

    CALL Info( 'AcousticsSolver', ' ', Level=4)
    CALL Info( 'AcousticsSolver', 'ILU factorization for the Velocity 2 preconditioner', &
        Level=4)
    CALL Info( 'AcousticsSolver', ' ', Level=4)
    Condition = CRS_ComplexIncompleteLU( PA2, IluOrder )

    IF (dim > 2) THEN
      CALL Info( 'AcousticsSolver', ' ', Level=4)
      CALL Info( 'AcousticsSolver', 'ILU factorization for the Velocity 3 preconditioner', &
        Level=4)
      CALL Info( 'AcousticsSolver', ' ', Level=4)
      Condition = CRS_ComplexIncompleteLU( PA3, IluOrder )
    END IF

!--------------------------------------------------------------------------------
!   The solution of an initial guess
!-------------------------------------------------------------------------------- 
    InnerTol = ListGetConstReal( Solver % Values, &
        'Linear System Convergence Tolerance' )
    InnerRounds = ListGetInteger( Solver % Values, &
        'Linear System Max Iterations') 

    z(1:q/2) = DCMPLX( 0.0d0,0.0d0 )
    TrivialCase = .TRUE.
    DO j=1,q/2
      g(j) = DCMPLX( b(2*(dim+2)*(j-1)+1),b(2*(dim+2)*(j-1)+2) )
      IF (CDABS(g(j)) > AEPS) TrivialCase = .FALSE.
    END DO
    IF ( .NOT. TrivialCase ) THEN
      !-----------------------------------------------------------------
      CALL Info( 'AcousticsSolver', ' ', Level=4)
      CALL Info( 'AcousticsSolver', &
          'Solving initial guess for Velocity 1', Level=4)
      CALL Info( 'AcousticsSolver', ' ', Level=4)
      !------------------------------------------------------------------
      CALL ComplexBiCGStab( q, PA1, z, g, InnerRounds, InnerTol )
    END IF
    DO j=1,q/2
      x(2*(dim+2)*(j-1)+1) = REAL(z(j))
      x(2*(dim+2)*(j-1)+2) = AIMAG(z(j))
    END DO

    TrivialCase = .TRUE.
    z(1:q/2) = DCMPLX( 0.0d0,0.0d0 )
    DO j=1,q/2
      g(j) =  DCMPLX( b(2*(dim+2)*(j-1)+3),b(2*(dim+2)*(j-1)+4) )
      IF (CDABS(g(j)) > AEPS) TrivialCase = .FALSE.
    END DO
    IF ( .NOT. TrivialCase ) THEN
      !-----------------------------------------------------------------
      CALL Info( 'AcousticsSolver', ' ', Level=4)
      CALL Info( 'AcousticsSolver', &
          'Solving initial guess for Velocity 2', Level=4)
      CALL Info( 'AcousticsSolver', ' ', Level=4)
      !------------------------------------------------------------------
      CALL ComplexBiCGStab( q, PA2, z, g, InnerRounds, InnerTol )
    END IF
    DO j=1,q/2
      x(2*(dim+2)*(j-1)+3) = REAL(z(j))
      x(2*(dim+2)*(j-1)+4) = AIMAG(z(j)) 
    END DO

!--------------------------------------------------------------------------------
!    The start of the GCR iteration... 
!--------------------------------------------------------------------------------     
    tottime = CPUTime()
    m = n/2
    IF ( ALL(x == 0.0d0) ) x = 1.0d-8

    !----------------------------------------------------------------------------
    ! Transform the solution vector x and the right-hand side vector b to 
    ! complex-valued vectors y and f
    !---------------------------------------------------------------------------

    DO i=1,m
      y(i) = DCMPLX( x(2*i-1), x(2*i) )
      f(i) = DCMPLX( b(2*i-1), b(2*i) )
    END DO

    ! DO j=1,...   BEGIN RESTART LOOP
    CALL ComplexMatrixVectorProduct( A, y, r )
    r(1:m) = f(1:m) - r(1:m)
    res0 = ComplexNorm(m,f)

    V(1:m,1:Rounds) = DCMPLX( 0.0d0, 0.0d0)
    S(1:m,1:Rounds) = DCMPLX( 0.0d0, 0.0d0)

    Pnorm = 0.0d0

    DO k=1,Rounds
      !----------------------------------------------------------
      ! Perform the preconditioning...
      !---------------------------------------------------------------
      T1(1:m) = r(1:m)
      CALL InnerPreconditioningIteration( n, A, q, PA1, PA2, PA3, PA, &
          PS, Grad1, Grad2, Grad3, ChiConst, T1, dim, Solver )
      CALL ComplexMatrixVectorProduct( A, T1, T2 )  
      
      !--------------------------------------------------------------
      ! Perform the orthogonalisation of the search directions....
      !--------------------------------------------------------------
      DO i=1,k-1
        beta = ComplexDotProduct( m, V(1:m,i), T2(1:m) )
        T1(1:m) = T1(1:m) - beta * S(1:m,i)
        T2(1:m) = T2(1:m) - beta * V(1:m,i)        
      END DO
      alpha = ComplexNorm(m,T2)
      T1(1:m) = DCMPLX( 1.0d0, 0.0d0)/DCMPLX( alpha, 0.0d0) * T1(1:m)
      T2(1:m) = DCMPLX( 1.0d0, 0.0d0)/DCMPLX( alpha, 0.0d0) * T2(1:m)

      !-------------------------------------------------------------
      ! The update of the solution and save the search data...
      !------------------------------------------------------------- 
      beta = ComplexDotProduct(m, T2, r)
      y(1:m) = y(1:m) + beta * T1(1:m)      
      r(1:m) = r(1:m) - beta * T2(1:m)
      S(1:m,k) = T1(1:m)
      V(1:m,k) = T2(1:m) 

      ! Check the accuracy of the residual
      !----------------------------------------
      e(1:m) = DCMPLX( 0.0d0,0.0d0 )
      CALL ComplexMatrixVectorProduct( A, y, e )
      e(1:m) = f(1:m) - e(1:m)
      norm = ComplexNorm(m,e(1:m)-r(1:m))/ComplexNorm(m,e(1:m))
      PRINT *, 'Relative error of the residual: ', norm 
      !---------------------------------------------- 

      !--------------------------------------------------------------
      ! Check whether the convergence criterion is met 
      !--------------------------------------------------------------
!      res = ComplexNorm(m,r)/res0
      res = StoppingCriterion( m, A, y, f, r ) 
      PRINT *,'OuterIteration ',i,res, CPUTime() - tottime
      IF ( res < TOL) THEN
!           WRITE( Message, *) 'Outer iteration converged after step ', i
!           CALL Info( 'AcousticsSolver', Message, Level=4)
!           PRINT *, 'InnerIteration converged'
        PRINT *, 'Estimated cond ', ConditionEstimate( m, A, y, f, r )
        EXIT
      END IF
    END DO
    ! END DO       END RESTART LOOP 

    ! Return the solution as a real vector...
    DO i=1,m
      x( 2*i-1 ) = REAL( y(i) )
      x( 2*i ) = AIMAG( y(i) )
    END DO

!------------------------------------------------------------------------------
   END SUBROUTINE GCROuterIteration
!------------------------------------------------------------------------------




!------------------------------------------------------------------------------
  FUNCTION StoppingCriterion( n, A, x, b, res ) RESULT(err)
!------------------------------------------------------------------------------
    INTEGER :: i, j, n
    TYPE(Matrix_t), POINTER :: A

    COMPLEX(KIND=dp) :: x(n), b(n), res(n)
    REAL(kind=dp) :: err, norm, tmp, normb, normres, normx
    INTEGER, POINTER :: Cols(:), Rows(:)
    REAL(KIND=dp), POINTER :: Values(:)

    Rows   => A % Rows
    Cols   => A % Cols
    Values => A % Values

    norm = 0.0d0
    normb = 0.0d0
    normres = 0.0d0
    normx = 0.0d0
    DO i=1,n
      tmp = 0.0d0
      DO j=Rows(2*i-1),Rows(2*i)-1,2
        tmp = tmp + CDABS( DCMPLX( Values(j), -Values(j+1) ) )
      END DO
      IF (tmp > norm) norm = tmp
      normb = MAX( normb, CDABS(b(i)) )
      normres = MAX( normres, CDABS(res(i)) )
      normx = MAX( normx, CDABS(x(i)) )
    END DO

!     err = ComplexNorm(n,res)/(SQRT(SUM(A % Values**2)) * ComplexNorm(n,x) + &
!         ComplexNorm(n,b) ) 

    err = normres / (norm * normx + normb)

!------------------------------------------------------------------------------
  END FUNCTION StoppingCriterion
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
  FUNCTION ConditionEstimate( n, A, x, b, res ) RESULT(err)
!------------------------------------------------------------------------------
    INTEGER :: i, j, n
    TYPE(Matrix_t), POINTER :: A

    COMPLEX(KIND=dp) :: x(n), b(n), res(n)
    REAL(kind=dp) :: err, norm, tmp, normb, normres, normx
    INTEGER, POINTER :: Cols(:), Rows(:)
    REAL(KIND=dp), POINTER :: Values(:)

    Rows   => A % Rows
    Cols   => A % Cols
    Values => A % Values

    norm = 0.0d0
    normb = 0.0d0
    normres = 0.0d0
    normx = 0.0d0
    DO i=1,n
      tmp = 0.0d0
      DO j=Rows(2*i-1),Rows(2*i)-1,2
        tmp = tmp + CDABS( DCMPLX( Values(j), -Values(j+1) ) )
      END DO
      IF (tmp > norm) norm = tmp
      normb = MAX( normb, CDABS(b(i)) )
      normres = MAX( normres, CDABS(res(i)) )
      normx = MAX( normx, CDABS(x(i)) )
    END DO

!     err = SQRT(SUM( res(1:n)**2) ) /  &
!        ( SQRT(SUM(A % Values**2)) * SQRT(SUM(x(1:n)**2)) + SQRT(SUM(b(1:n)**2)) )

    err = norm*normx/normb 
!------------------------------------------------------------------------------
  END FUNCTION ConditionEstimate
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
  SUBROUTINE ComplexMatrixVectorProduct( A,u,v )
!------------------------------------------------------------------------------
!   Matrix vector product (v = Au) for a matrix given in CRS format.
!------------------------------------------------------------------------------
    COMPLEX(KIND=dp), DIMENSION(*) :: u,v
    TYPE(Matrix_t), POINTER :: A
!------------------------------------------------------------------------------
    INTEGER, POINTER :: Cols(:),Rows(:)
    REAL(KIND=dp), POINTER :: Values(:)

    INTEGER :: i,j,n
    COMPLEX(KIND=dp) :: s
!------------------------------------------------------------------------------

    n = A % NumberOfRows / 2
    Rows   => A % Rows
    Cols   => A % Cols
    Values => A % Values

    v(1:n) = DCMPLX( 0.0d0, 0.0d0 )
    DO i=1,n
       DO j=Rows(2*i-1),Rows(2*i)-1,2
          s = DCMPLX( Values(j), -Values(j+1) )
          v(i) = v(i) + s * u((Cols(j)+1)/2)
       END DO
    END DO
!------------------------------------------------------------------------------
  END SUBROUTINE ComplexMatrixVectorProduct
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    FUNCTION ComplexNorm( n, x ) RESULT(s)
!------------------------------------------------------------------------------
       INTEGER :: n, i
       REAL(KIND=dp) :: s
       COMPLEX(KIND=dp) :: r, x(:)
!------------------------------------------------------------------------------
       s =  SQRT( REAL( DOT_PRODUCT( x(1:n), x(1:n) ) ) )
!       s = 0.0d0
!       DO i=1,n
!         s = MAX(s, CDABS(x(i)) )
!       END DO
!------------------------------------------------------------------------------
    END FUNCTION ComplexNorm
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    FUNCTION ComplexDotProduct( n, x, y ) RESULT(s)
!------------------------------------------------------------------------------
       INTEGER :: n
       COMPLEX(KIND=dp) :: s, x(:), y(:)
!------------------------------------------------------------------------------
       s = DOT_PRODUCT( x(1:n), y(1:n) )
!------------------------------------------------------------------------------
    END FUNCTION ComplexDotProduct
!------------------------------------------------------------------------------




!------------------------------------------------------------------------------
     SUBROUTINE InnerPreconditioningIteration( n, A, q, PA1, PA2, PA3, PA, PS, &
         Grad1, Grad2, Grad3, ChiConst, V, dim, Solver, VelocityPrecond)
!------------------------------------------------------------------------------
!     This subroutine solves iteratively the preconditioning equation P*z = V.
!     The building blocks of P are contained in the matrices PA1, PA2, 
!     PA3, PS, Grad1, Grad2 and Grad3. The vector V is overwritten by the solution z.
!------------------------------------------------------------------------------  
      TYPE(Solver_t), TARGET :: Solver
      TYPE(Matrix_t), POINTER :: A, PA1, PA2, PA3, PA, PS, Grad1, Grad2, Grad3 
      INTEGER :: n, q, dim
      COMPLEX(KIND=dp) :: V(n/2), ChiConst
      INTEGER, OPTIONAL :: VelocityPrecond
!--------------------------------------------------------------------------------
      TYPE(Element_t), POINTER :: CurrentElement
      INTEGER, POINTER :: NodeIndexes(:), Perm(:)
      REAL(KIND=dp) :: InnerTol
      INTEGER :: i, j, k, m, InnerRounds, t, nn
      LOGICAL :: TrivialCase
      COMPLEX(kind=dp) :: z(n/2), y(q/2), f(q/2), w(q), g(q), Const, &
          Vel(dim*q/2), VelRhs(dim*q/2)
!------------------------------------------------------------------------------
      Perm => Solver % Variable % Perm
      InnerTol = ListGetConstReal( Solver % Values, &
          'Linear System Convergence Tolerance' )
      InnerRounds = ListGetInteger( Solver % Values, &
          'Linear System Max Iterations') 

      !------------------------------------------------------------------------
      ! The preconditioning by the block upper triangular part....
      !------------------------------------------------------------------------
      z(1:n/2) = DCMPLX( 0.0d0,0.0d0 )
      !-----------------------------------------------------------------
      ! The solution of the Schur complement equation...
      !------------------------------------------------------------------ 
      w(1:q) = DCMPLX( 0.0d0,0.0d0 )
      DO j=1,q/2
        g(2*j-1) = V((dim+2)*j-1)
        g(2*j) = V((dim+2)*j)
      END DO
      !-----------------------------------------------------------------------
      ! Modify the right-hand side vector in the case of normal traction BCs 
      !-----------------------------------------------------------------------
      DO k=1,NumberOfNormalTractionNodes
        m = NormalTractionNodes(k)
        g(2*m) = DCMPLX( 0.0d0,0.0d0 ) 
      END DO

      IF ( ANY( g /= CMPLX( 0.0d0,0.0d0 ) ) ) THEN     
        !-----------------------------------------------------------------
        CALL Info( 'AcousticsSolver', ' ', Level=4)
        CALL Info( 'AcousticsSolver', &
            'Iteration for the Schur complement preconditioner', Level=4)
        CALL Info( 'AcousticsSolver', ' ', Level=4)
        !-------------------------------------------------------------------
        CALL ComplexBiCGStab( 2*q, PS, w, g, InnerRounds, InnerTol )
      END IF

      DO j=1,q/2
        V((dim+2)*j-1) = w(2*j-1) 
!        V((dim+2)*j) = w(2*j)
        V((dim+2)*j) = ChiConst*( w(2*j) - w(2*j-1) )        
      END DO

      !------------------------------------------------------------------------------
      ! In the case of quadratic approximation project the temparature and div-fields
      ! onto the sapce of linear finite element functions
      !-------------------------------------------------------------------------------
      IF (.FALSE.) THEN
        DO t=1,Solver % Mesh % NumberOfBulkElements
          CurrentElement => Solver % Mesh % Elements(t)
          IF (  CurrentElement % TYPE % ElementCode == 306 .OR. &
              CurrentElement % TYPE % ElementCode == 408 ) THEN
            IF ( .NOT. CheckElementEquation( Model, &
                CurrentElement, EquationName ) ) CYCLE
            NodeIndexes => CurrentElement % NodeIndexes
            IF (CurrentElement % TYPE % ElementCode == 306) THEN
              !            PRINT *, 'Projection for triangles'
              i = Perm(NodeIndexes(4))
              j = Perm(NodeIndexes(1))
              k = Perm(NodeIndexes(2)) 
              V((dim+2)*i-1) = 5.0d-1*( V((dim+2)*j-1) + V((dim+2)*k-1 ) )
              V((dim+2)*i) = 5.0d-1*( V((dim+2)*j) + V((dim+2)*k ) )
              i =  Perm(NodeIndexes(5))
              j =  Perm(NodeIndexes(2))
              k =  Perm(NodeIndexes(3)) 
              V((dim+2)*i-1) = 5.0d-1*( V((dim+2)*j-1) + V((dim+2)*k-1 ) )
              V((dim+2)*i) = 5.0d-1*( V((dim+2)*j) + V((dim+2)*k ) )      
              i =  Perm(NodeIndexes(6))
              j =  Perm(NodeIndexes(3))
              k =  Perm(NodeIndexes(1)) 
              V((dim+2)*i-1) = 5.0d-1*( V((dim+2)*j-1) + V((dim+2)*k-1 ) )      
              V((dim+2)*i) = 5.0d-1*( V((dim+2)*j) + V((dim+2)*k )  )
            ELSE
              !            PRINT *, 'Projection for quadrilaterals'
              i = Perm(NodeIndexes(5))
              j = Perm(NodeIndexes(1))
              k = Perm(NodeIndexes(2)) 
              V((dim+2)*i-1) = 5.0d-1*( V((dim+2)*j-1) + V((dim+2)*k-1 ) ) 
              V((dim+2)*i) = 5.0d-1*( V((dim+2)*j) + V((dim+2)*k )  )    
              i = Perm(NodeIndexes(6))
              j = Perm(NodeIndexes(2))
              k = Perm(NodeIndexes(3)) 
              V((dim+2)*i-1) = 5.0d-1*( V((dim+2)*j-1) + V((dim+2)*k-1 ) ) 
              V((dim+2)*i) = 5.0d-1*( V((dim+2)*j) + V((dim+2)*k ))    
              i = Perm(NodeIndexes(7))
              j = Perm(NodeIndexes(3))
              k = Perm(NodeIndexes(4)) 
              V((dim+2)*i-1) = 5.0d-1*( V((dim+2)*j-1) + V((dim+2)*k-1 ) ) 
              V((dim+2)*i) = 5.0d-1*( V((dim+2)*j) + V((dim+2)*k )  )
              i = Perm(NodeIndexes(8))
              j = Perm(NodeIndexes(4))
              k = Perm(NodeIndexes(1)) 
              V((dim+2)*i-1) = 5.0d-1*( V((dim+2)*j-1) + V((dim+2)*k-1 ) )
              V((dim+2)*i) = 5.0d-1*( V((dim+2)*j) + V((dim+2)*k ) )
            END IF
          END IF
        END DO
      END IF
      !---------------------------------------------------------------------------------
      ! The computation of the specific matrix vector products related to preconditining
      !---------------------------------------------------------------------------------

      IF (.NOT. AllocatedGradMatrices) THEN
        CALL ComplexMatrixVectorProduct2( A, V, z, dim )
      ELSE
        z(1:n/2) = V(1:n/2)
        DO j=1,q/2
          f(j) = V((dim+2)*j)
        END DO
        CALL ComplexMatrixVectorProduct( Grad1,f,y )
        DO j=1,q/2
          z((dim+2)*(j-1)+1) =  z((dim+2)*(j-1)+1) - y(j)        
        END DO
        CALL ComplexMatrixVectorProduct( Grad2,f,y )
        DO j=1,q/2
          z((dim+2)*(j-1)+2) =  z((dim+2)*(j-1)+2) - y(j)        
        END DO
        IF (dim > 2) THEN
          CALL ComplexMatrixVectorProduct( Grad3,f,y )
          DO j=1,q/2
            z((dim+2)*(j-1)+3) =  z((dim+2)*(j-1)+3) - y(j)        
          END DO
        END IF

        DO j=1,q/2
          f(j) = V((dim+2)*j-1)
        END DO
        CALL ComplexMatrixVectorProduct( Grad1,f,y )
        DO j=1,q/2
          z((dim+2)*(j-1)+1) =  z((dim+2)*(j-1)+1) - y(j)        
        END DO
        CALL ComplexMatrixVectorProduct( Grad2,f,y )
        DO j=1,q/2
          z((dim+2)*(j-1)+2) =  z((dim+2)*(j-1)+2) - y(j)        
        END DO
        IF (dim > 2) THEN
          CALL ComplexMatrixVectorProduct( Grad3,f,y )
          DO j=1,q/2
            z((dim+2)*(j-1)+3) =  z((dim+2)*(j-1)+3) - y(j)        
          END DO
        END IF
      END IF

      !--------------------------------------------------------
      ! The solution of the velocity preconditioning equation
      !--------------------------------------------------------
      IF (ComponentwisePreconditioning) THEN
        y(1:q/2) = DCMPLX( 0.0d0,0.0d0 )
        DO j=1,q/2
          f(j) = z((dim+2)*(j-1)+1)
        END DO
        !-----------------------------------------------------------------
        CALL Info( 'AcousticsSolver', ' ', Level=4)
        CALL Info( 'AcousticsSolver', &
            'Iteration for the Velocity 1 preconditioner', Level=4)
        CALL Info( 'AcousticsSolver', ' ', Level=4)
        !------------------------------------------------------------------
        CALL ComplexBiCGStab( q, PA1, y, f, InnerRounds, InnerTol, VelocityPrecond)
        DO j=1,q/2
          z((dim+2)*(j-1)+1) = y(j)
        END DO
        y(1:q/2) = DCMPLX( 0.0d0,0.0d0 )
        DO j=1,q/2
          f(j) = z((dim+2)*(j-1)+2)
        END DO
        !-----------------------------------------------------------------
        CALL Info( 'AcousticsSolver', ' ', Level=4)
        CALL Info( 'AcousticsSolver', &
            'Iteration for the Velocity 2 preconditioner', Level=4)
        CALL Info( 'AcousticsSolver', ' ', Level=4)
        !------------------------------------------------------------------
        CALL ComplexBiCGStab( q, PA2, y, f, InnerRounds, InnerTol, VelocityPrecond)
        DO j=1,q/2
          z((dim+2)*(j-1)+2) = y(j)
        END DO
        
        IF (dim > 2) THEN
          y(1:q/2) = DCMPLX( 0.0d0,0.0d0 )
          DO j=1,q/2
            f(j) = z((dim+2)*(j-1)+3)
          END DO
          !-----------------------------------------------------------------
          CALL Info( 'AcousticsSolver', ' ', Level=4)
          CALL Info( 'AcousticsSolver', &
              'Iteration for the Velocity 3 preconditioner', Level=4)
          CALL Info( 'AcousticsSolver', ' ', Level=4)
          !------------------------------------------------------------------
          CALL ComplexBiCGStab( q, PA3, y, f, InnerRounds, InnerTol, VelocityPrecond)
          DO j=1,q/2
            z((dim+2)*(j-1)+3) = y(j)
          END DO
        END IF
      ELSE
        Vel(1:dim*q/2) = DCMPLX( 0.0d0,0.0d0 )
        TrivialCase = .TRUE.
        DO i=1,dim
          DO j=1,q/2
            VelRhs((j-1)*dim+i) = z((dim+2)*(j-1)+i)
            IF ( CDABS(VelRhs((j-1)*dim+i)) > AEPS ) TrivialCase = .FALSE.
          END DO
        END DO
        IF ( .NOT. TrivialCase ) THEN
          !-----------------------------------------------------------------
          CALL Info( 'AcousticsSolver', ' ', Level=4)
          CALL Info( 'AcousticsSolver', &
              'Preconditioning iteration for velocities', Level=4)
          CALL Info( 'AcousticsSolver', ' ', Level=4)
          !------------------------------------------------------------------
          CALL ComplexBiCGStab( q*dim, PA, Vel, VelRhs, InnerRounds, InnerTol, VelocityPrecond )
        END IF
        DO j=1,q/2
          DO i=1,dim
            z((dim+2)*(j-1)+i) = Vel((j-1)*dim+i)
          END DO
        END DO        
      END IF
      V(1:n/2)=z(1:n/2)
!------------------------------------------------------------------------------
     END SUBROUTINE InnerPreconditioningIteration
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    SUBROUTINE ComplexBiCGStab( n, A, x, b, Rounds, TOL, PrecondType )
!------------------------------------------------------------------------------
!   This is the ILU or Jacobi preconditioned BiCGStab method for complex systems 
!------------------------------------------------------------------------------
       TYPE(Matrix_t), POINTER :: A
       INTEGER :: n, Rounds
       REAL(KIND=dp) :: TOL
       COMPLEX(kind=dp) :: x(n/2), b(n/2)
       INTEGER, OPTIONAL :: PrecondType 
!------------------------------------------------------------------------------
       INTEGER :: i, m, k
       LOGICAL :: Condition
       REAL(KIND=dp) :: res, tottime, res0, const
       COMPLEX(KIND=dp) :: r(n/2),Ri(n/2),P(n/2),V(n/2),T(n/2),T1(n/2),T2(n/2),&
           S(n/2)
       COMPLEX(KIND=dp) :: alpha,beta,omega,rho,oldrho
!------------------------------------------------------------------------------

       Condition = .TRUE.
       IF ( PRESENT(PrecondType) ) THEN
         IF ( PrecondType == 0) Condition = .FALSE.
       END IF

       IF ( ALL(x == DCMPLX(0.0d0,0.0d0)) ) x = b
       m = n/2

       CALL ComplexMatrixVectorProduct( A, x, r )
       r(1:m) = b(1:m) - r(1:m)
!       res0 = ComplexNorm(m,b)

       Ri(1:m) = r(1:m)
       P(1:m) = DCMPLX( 0.0d0, 0.0d0)
       V(1:m) = DCMPLX( 0.0d0, 0.0d0)
       omega  = DCMPLX( 1.0d0, 0.0d0)
       alpha  = DCMPLX( 0.0d0, 0.0d0)
       oldrho = DCMPLX( 1.0d0, 0.0d0)
       tottime = CPUTime()

       DO i=1,Rounds
         rho = ComplexDotProduct( m, Ri, r )
         beta = alpha * rho / ( oldrho * omega )
         P(1:m) = r(1:m) + beta * (P(1:m) - omega*V(1:m))
         V(1:m) = P(1:m)

         IF (Condition) THEN
           CALL CRS_ComplexLUSolve2( m, A, V )
         ELSE
           ! Preconditioning by diagonal elements
           DO k=1,m
             V(k) = V(k)/DCMPLX( A % Values(A % Diag(2*k-1)), -A % Values(A % Diag(2*k-1)+1) )
           END DO
         END IF

         T1(1:m) = V(1:m)
         CALL ComplexMatrixVectorProduct( A, T1, V )
         alpha = rho / ComplexDotProduct( m, Ri, V )
         S(1:m) = r(1:m) - alpha * V(1:m)
         x(1:m) = x(1:m) + alpha*T1(1:m) 
         res = StoppingCriterion( m, A, x, b, S )
!         res = ComplexNorm(m,S)/res0
         IF ( res < TOL ) THEN
           WRITE(*,'(I4,ES12.3)') i, res
           WRITE(*,'(a,F8.2)') 'Solution time (s):    ', CPUTime() - tottime
           WRITE(*,'(a,ES12.3)') 'An approximate lower bound for the condition number ', &
               ConditionEstimate( m, A, x, b, S )   
           EXIT
         END IF

         T(1:m) = S(1:m)

         IF (Condition) THEN
           CALL CRS_ComplexLUSolve2( m, A, T )
         ELSE
           ! Preconditioning by diagonal elements
           DO k=1,m
             T(k) = T(k)/DCMPLX( A % Values(A % Diag(2*k-1)), -A % Values(A % Diag(2*k-1)+1) )
           END DO           
         END IF
           
         T2(1:m) = T(1:m)
         CALL ComplexMatrixVectorProduct( A, T2, T )
         omega = ComplexDotProduct( m,T,S ) / ComplexDotProduct( m,T,T )
         oldrho = rho
         r(1:m) = S(1:m) - omega*T(1:m)
         x(1:m) = x(1:m) + omega*T2(1:m)

!         res = ComplexNorm(m,r)/res0
         res = StoppingCriterion( m, A, x, b, r )
         ! PRINT *, i, res, CPUTime() - tottime
         WRITE(*,'(I4,ES12.3)') i, res
         IF ( res < TOL ) THEN
           WRITE(*,'(a,F8.2)') 'Solution time (s):    ', CPUTime() - tottime
           WRITE(*,'(a,ES12.3)') 'An approximate lower bound for the condition number ', &
               ConditionEstimate( m, A, x, b, S )   
           EXIT
         END IF
       END DO

!------------------------------------------------------------------------------
    END SUBROUTINE ComplexBiCGStab
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE CRS_ComplexLUSolve2( N,A,b )
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Solve a (complex9 system (Ax=b) after factorization A=LUD has been
!    done. This routine is meant as a part of  a preconditioner for an
!    iterative solver.
!
!  ARGUMENTS:
!
!    INTEGER :: N
!      INPUT: Size of the system
!
!    TYPE(Matrix_t) :: A
!      INPUT: Structure holding input matrix
!
!    DOUBLE PRECISION :: b
!      INOUT: on entry the RHS vector, on exit the solution vector.
!
!******************************************************************************
!------------------------------------------------------------------------------
 
    TYPE(Matrix_t), POINTER :: A
    INTEGER :: N
    COMPLEX(KIND=dp) :: b(N)

!------------------------------------------------------------------------------

    COMPLEX(KIND=dp), POINTER :: Values(:)
    INTEGER :: i,j
    COMPLEX(KIND=dp) :: x, s
    INTEGER, POINTER :: Cols(:),Rows(:),Diag(:)
    
!------------------------------------------------------------------------------

    Diag => A % ILUDiag
    Rows => A % ILURows
    Cols => A % ILUCols
    Values => A % CILUValues

!
!   if no ilu provided do diagonal solve:
!   -------------------------------------
    IF ( .NOT. ASSOCIATED( Values ) ) THEN
       Diag => A % Diag

       DO i=1,n/2
          x = DCMPLX( A % Values(Diag(2*i-1)), -A % Values(Diag(2*i-1)+1) )
          b(i) = b(i) / x
       END DO
       RETURN
    END IF

    IF (.FALSE.) THEN
      CALL ComplexLUSolve( n,SIZE(Cols),Rows,Cols,Diag,Values,b )
    ELSE
      ! Forward substitute
      DO i=1,n
        s = b(i)
        DO j=Rows(i),Diag(i)-1
          s = s - Values(j) * b(Cols(j))
        END DO
        b(i) = s
      END DO
      !
      ! Backward substitute
      DO i=n,1,-1
        s = b(i)
        DO j=Diag(i)+1,Rows(i+1)-1
          s = s - Values(j) * b(Cols(j))
        END DO
        b(i) = Values(Diag(i)) * s
      END DO
    END IF
!------------------------------------------------------------------------------
  END SUBROUTINE CRS_ComplexLUSolve2
!------------------------------------------------------------------------------

!-----------------------------------------------------------------------------
  SUBROUTINE ComplexLUSolve( n,m,Rows,Cols,Diag,Values,b )
!-----------------------------------------------------------------------------
    INTEGER :: n,m,Rows(n+1),Cols(m),Diag(n)
    COMPLEX(KIND=dp) :: Values(m),b(n)
    INTEGER :: i,j


    ! Forward substitute
    DO i=1,n
      DO j=Rows(i),Diag(i)-1
        b(i) = b(i) - Values(j) * b(Cols(j))
      END DO
    END DO

    ! Backward substitute
    DO i=n,1,-1
      DO j=Diag(i)+1,Rows(i+1)-1
        b(i) = b(i) - Values(j) * b(Cols(j))
      END DO
      b(i) = Values(Diag(i)) * b(i)
    END DO
!-----------------------------------------------------------------------------
  END SUBROUTINE ComplexLUSolve
!------------------------------------------------------------------------------




!-------------------------------------------------------------------------------
  SUBROUTINE ComplexMatrixVectorProduct2( A,u,v,dim )
!------------------------------------------------------------------------------
!
!   The computation of a specific matrix-vector product for preconditioning  
!
!------------------------------------------------------------------------------

    COMPLEX(KIND=dp), DIMENSION(*) :: u,v
    TYPE(Matrix_t), POINTER :: A
    INTEGER :: dim
!------------------------------------------------------------------------------
    INTEGER, POINTER :: Cols(:), Rows(:), Diag(:)
    REAL(KIND=dp), POINTER :: Values(:)

    INTEGER :: i,j,k,n,p,q
    COMPLEX(KIND=dp) :: s
!------------------------------------------------------------------------------

    n = A % NumberOfRows / 2
    q = n/(dim+2)

    Rows   => A % Rows
    Cols   => A % Cols
    Diag   => A % Diag 
    Values => A % Values

    v(1:n) = u(1:n) 

    DO k=1,q
      DO p=1,dim
        i = (k-1)*(dim+2)+p
        DO j = Rows(2*i-1)+2*dim, Rows(2*i)-1, 2*(dim+2)       
          s = DCMPLX( Values(j), -Values(j+1) )
          v(i) = v(i) - s * u((Cols(j)+1)/2)
        END DO
        DO j = Rows(2*i-1)+2*(dim+1), Rows(2*i)-1, 2*(dim+2)       
          s = DCMPLX( Values(j), -Values(j+1) )
          v(i) = v(i) - s * u((Cols(j)+1)/2)
        END DO
      END DO
    END DO

!-----------------------------------------------------------------------------
   END SUBROUTINE ComplexMatrixVectorProduct2
!------------------------------------------------------------------------------


!-------------------------------------------------------------------------------
  SUBROUTINE ComplexMatrixVectorProduct3( A,u,v,dim )
!------------------------------------------------------------------------------
!
!   The computation of a specific matrix-vector product for preconditioning  
!   
!------------------------------------------------------------------------------

    COMPLEX(KIND=dp), DIMENSION(*) :: u,v
    TYPE(Matrix_t), POINTER :: A
    INTEGER :: dim
!------------------------------------------------------------------------------
    INTEGER, POINTER :: Cols(:), Rows(:), Diag(:)
    REAL(KIND=dp), POINTER :: Values(:)

    INTEGER :: i,j,k,m,n,p,q
    COMPLEX(KIND=dp) :: s
!------------------------------------------------------------------------------

    n = A % NumberOfRows / 2
    q = n/(dim+2)

    Rows   => A % Rows
    Cols   => A % Cols
    Diag   => A % Diag 
    Values => A % Values

    v(1:dim*q) = DCMPLX( 0.0d0,0.0d0 ) 

    DO k=1,q
      DO p=1,dim
        i = (k-1)*(dim+2)+p
        DO m=1,dim
          DO j = Rows(2*i-1)+2*(m-1), Rows(2*i)-1, 2*(dim+2)         
            s = DCMPLX( Values(j), -Values(j+1) )
            v((k-1)*dim+p) = v((k-1)*dim+p) + s * u((Cols(j)+1)/2)
          END DO
        END DO
      END DO
    END DO

!-----------------------------------------------------------------------------
   END SUBROUTINE ComplexMatrixVectorProduct3
!------------------------------------------------------------------------------




!------------------------------------------------------------------------------
    SUBROUTINE VelocityMatrix(  StiffMatrix, Viscosity, AngularFrequency, &
        Density, Element, n, dim)
!------------------------------------------------------------------------------
      REAL(KIND=dp), TARGET :: StiffMatrix(:,:)
      REAL(KIND=dp) :: Viscosity(:), AngularFrequency, Density(:)
      INTEGER :: dim, n
      TYPE(Element_t), POINTER :: Element
!------------------------------------------------------------------------------
      COMPLEX(kind=dp) :: CStiff(n,n)
      REAL(KIND=dp) :: Basis(n), dBasisdx(n,3), ddBasisddx(n,3,3), DetJ, r
      LOGICAL :: Stat
      INTEGER :: t, i, j, k, l, p, q
      TYPE(GaussIntegrationPoints_t) :: IP

      REAL(KIND=dp) :: mu, rho0, s

      TYPE(Nodes_t) :: Nodes
      SAVE Nodes
!------------------------------------------------------------------------------
      CALL GetElementNodes( Nodes )
      StiffMatrix = 0.0d0
      CStiff = DCMPLX(0.0d0,0.0d0)
      !-------------------------
      ! Numerical integration:
      !-------------------------
      IP = GaussPoints( Element,n)
      DO t=1,IP % n
        !--------------------------------------------------------------
        ! Basis function values & derivatives at the integration point:
        !--------------------------------------------------------------
        stat = ElementInfo( Element, Nodes, IP % U(t), IP % V(t), &
            IP % W(t), detJ, Basis, dBasisdx, ddBasisddx, .FALSE. )

        s = IP % s(t) * detJ
        IF (CoordSys == AxisSymmetric) THEN
          r = SUM( Basis * Nodes % x(1:n) )
          s = r * s
        END IF

        !-----------------------------------------------
        ! Material parameters at the integration point:
        !----------------------------------------------
        mu  = SUM( Basis(1:n) * Viscosity(1:n) )
        rho0 = SUM( Density(1:n) * Basis(1:n) )
        !---------------------------------------------
        ! the stiffness matrix...
        !---------------------------------------------
        DO p=1,n
          DO q=1,n
            DO j = 1,dim
              CStiff(p,q) = CStiff(p,q) + s * DCMPLX( 0.0d0, -mu/(AngularFrequency*rho0) ) * &
                  dBasisdx(q,j) * dBasisdx(p,j)
            END DO
            CStiff(p,q) = CStiff(p,q) + s * DCMPLX(1.0d0, 0.0d0) * Basis(q) * Basis(p)             
          END DO
        END DO
      END DO

      DO i=1,n
        DO j=1,n
          StiffMatrix( 2*(i-1)+1, 2*(j-1)+1 ) =  REAL( CStiff(i,j) )
          StiffMatrix( 2*(i-1)+1, 2*(j-1)+2 ) = -AIMAG( CStiff(i,j) )
          StiffMatrix( 2*(i-1)+2, 2*(j-1)+1 ) =  AIMAG( CStiff(i,j) )
          StiffMatrix( 2*(i-1)+2, 2*(j-1)+2 ) =  REAL( CStiff(i,j) )
        END DO
      END DO
!------------------------------------------------------------------------------
  END SUBROUTINE VelocityMatrix
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE CoupledVelocityMatrix(  StiffMatrix, Viscosity, AngularFrequency, &
        Density, Element, n, dim)
!------------------------------------------------------------------------------
      REAL(KIND=dp), TARGET :: StiffMatrix(:,:)
      REAL(KIND=dp) :: Viscosity(:), AngularFrequency, Density(:)
      INTEGER :: dim, n
      TYPE(Element_t), POINTER :: Element
!------------------------------------------------------------------------------
      COMPLEX(kind=dp) :: CStiff(dim*n,dim*n)
      REAL(KIND=dp) :: Basis(n), dBasisdx(n,3), ddBasisddx(n,3,3), DetJ, r
      LOGICAL :: Stat
      INTEGER :: t, i, j, k, l, p, q
      TYPE(GaussIntegrationPoints_t) :: IP

      REAL(KIND=dp) :: mu, rho0, s

      TYPE(Nodes_t) :: Nodes
      SAVE Nodes
!------------------------------------------------------------------------------
      CALL GetElementNodes( Nodes )
      StiffMatrix = 0.0d0
      CStiff = DCMPLX(0.0d0,0.0d0)
      !-------------------------
      ! Numerical integration:
      !-------------------------
      IP = GaussPoints( Element,n)
      DO t=1,IP % n
        !--------------------------------------------------------------
        ! Basis function values & derivatives at the integration point:
        !--------------------------------------------------------------
        stat = ElementInfo( Element, Nodes, IP % U(t), IP % V(t), &
            IP % W(t), detJ, Basis, dBasisdx, ddBasisddx, .FALSE. )

        s = IP % s(t) * detJ
        IF (CoordSys == AxisSymmetric) THEN
          r = SUM( Basis * Nodes % x(1:n) )
          s = r * s
        END IF

        !-----------------------------------------------
        ! Material parameters at the integration point:
        !----------------------------------------------
        mu  = SUM( Basis(1:n) * Viscosity(1:n) )
        rho0 = SUM( Density(1:n) * Basis(1:n) )
        !---------------------------------------------
        ! the stiffness matrix...
        !---------------------------------------------
        DO i=1,dim
          DO p=1,n
            DO q=1,n
              DO j = 1,dim
                CStiff((p-1)*dim+i,(q-1)*dim+i) = CStiff((p-1)*dim+i,(q-1)*dim+i) + &
                    s * DCMPLX( 0.0d0, -mu/(AngularFrequency*rho0) ) * &
                    dBasisdx(q,j) * dBasisdx(p,j)
                CStiff((p-1)*dim+i, (q-1)*dim+j) = &
                   CStiff((p-1)*dim+i, (q-1)*dim+j) + &
                   DCMPLX( 0.0d0, -mu/(AngularFrequency*rho0) ) * &
                   dBasisdx(q,i) * dBasisdx(p,j) * s
              END DO

              IF ( (i==1) .AND. (CoordSys == AxisSymmetric) ) THEN
                CStiff((p-1)*dim+i, (q-1)*dim+i) = &
                    CStiff((p-1)*dim+i, (q-1)*dim+i) + &
                    DCMPLX( 0.0d0, -2*mu/(AngularFrequency*rho0) ) * 1/r**2 * Basis(q) * Basis(p) * s  
              END IF

              CStiff((p-1)*dim+i,(q-1)*dim+i) = CStiff((p-1)*dim+i,(q-1)*dim+i) + &
                  s * DCMPLX(1.0d0, 0.0d0) * Basis(q) * Basis(p)             
            END DO
          END DO
        END DO
      END DO

      DO p=1,n
        DO i=1,DIM
          DO q=1,n
            DO j=1,DIM
              StiffMatrix( 2*DIM*(p-1)+2*i-1, 2*DIM*(q-1)+2*j-1 ) =  &
                  REAL( CSTIFF(DIM*(p-1)+i,DIM*(q-1)+j) )
              StiffMatrix( 2*DIM*(p-1)+2*i-1, 2*DIM*(q-1)+2*j ) =  &
                  -AIMAG( CSTIFF(DIM*(p-1)+i,DIM*(q-1)+j) )
              StiffMatrix( 2*DIM*(p-1)+2*i, 2*DIM*(q-1)+2*j-1 ) =  &
                  AIMAG( CSTIFF(DIM*(p-1)+i,DIM*(q-1)+j) )
              StiffMatrix( 2*DIM*(p-1)+2*i, 2*DIM*(q-1)+2*j ) =  &
                  REAL( CSTIFF(DIM*(p-1)+i,DIM*(q-1)+j) )
            END DO
          END DO
        END DO
      END DO
!------------------------------------------------------------------------------
  END SUBROUTINE CoupledVelocityMatrix
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE SchurComplementMatrix(  StiffMatrix, AngularFrequency , &
      SpecificHeat, HeatRatio, Density, Pressure,               &
      Temperature, Conductivity, Viscosity, Lambda,             &
      Element, n, dim)
!------------------------------------------------------------------------------
    REAL(KIND=dp), TARGET :: StiffMatrix(:,:)
    REAL(KIND=dp) :: AngularFrequency, SpecificHeat(:), HeatRatio(:), Density(:), &
        Pressure(:),  Temperature(:), Conductivity(:), Viscosity(:), Lambda(:) 
    TYPE(Element_t), POINTER :: Element
    INTEGER :: n, dim
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: Basis(n),dBasisdx(n,3), ddBasisddx(n,3,3), DetJ, r
    COMPLEX(kind=dp) :: CStiff(2*n,2*n), C1, C2, C3, C4
    LOGICAL :: Stat
    INTEGER :: t, i, j, k, l, p, q
    TYPE(GaussIntegrationPoints_t) :: IP

    REAL(KIND=dp) :: CV, kappa, mu, rho0, P0, gamma, la, K1, K2, s

    TYPE(Nodes_t) :: Nodes
    SAVE Nodes
!------------------------------------------------------------------------------
    CALL GetElementNodes( Nodes )
    StiffMatrix = 0.0d0
    CStiff = DCMPLX( 0.0d0,0.0d0 )
    !-------------------------
    ! Numerical integration:
    !-------------------------
    IP = GaussPoints( Element,n)
    DO t=1,IP % n
      !--------------------------------------------------------------
      ! Basis function values & derivatives at the integration point:
      !--------------------------------------------------------------
      stat = ElementInfo( Element, Nodes, IP % U(t), IP % V(t), &
          IP % W(t), detJ, Basis, dBasisdx, ddBasisddx, .FALSE. )

      s = IP % s(t) * detJ
      IF (CoordSys == AxisSymmetric) THEN
        r = SUM( Basis * Nodes % x(1:n) )
        s = r * s
      END IF

      !-----------------------------------------------
      ! Material parameters at the integration point:
      !----------------------------------------------
      CV = SUM( SpecificHeat(1:n) * Basis(1:n) )       
      kappa = SUM( Conductivity(1:n) * Basis(1:n) )
      mu  = SUM( Basis(1:n) * Viscosity(1:n) )
      rho0  = SUM( Basis(1:n) * Density(1:n) )
      P0  = SUM( Basis(1:n) * Pressure(1:n) )
      gamma  = SUM( Basis(1:n) * HeatRatio(1:n) )
      la = SUM( Basis(1:n) * Lambda(1:n) )

      C1 = DCMPLX( 1.0d0,AngularFrequency/P0*(2.0d0*mu+la) ) / &
          DCMPLX( 1.0d0,AngularFrequency/P0*(la) )  

      C2 = DCMPLX( rho0*AngularFrequency,0.0d0)/DCMPLX( P0/AngularFrequency, la )
      C3 = DCMPLX( 1.0d0, 0.0d0)
      C4 = DCMPLX( 1.0d0,0.0d0)/DCMPLX( 1.0d0, AngularFrequency/P0*(la) )


!      K1 = kappa*AngularFrequency/(CV*(gamma-1.0d0)*P0)
!      K2 = AngularFrequency**2*rho0/(P0*(gamma-1.0d0)) 
       K1 = kappa/(rho0*AngularFrequency*(gamma-1.0d0)*CV)
       K2 = 1.0d0/(gamma-1.0d0)

      !---------------------------------------------
      ! the stiffness matrix...
      !----------------------------------------
      DO p=1,n
        DO q=1,n
          DO i=1,dim

            CStiff((p-1)*2+1,(q-1)*2+1) = CStiff((p-1)*2+1,(q-1)*2+1) + &
                s * DCMPLX( 0.0d0,K1) * dBasisdx(q,i) * dBasisdx(p,i)

            CStiff((p-1)*2+2,(q-1)*2+1) = CStiff((p-1)*2+2,(q-1)*2+1) + &
                s * C3 * dBasisdx(q,i) * dBasisdx(p,i)

            CStiff((p-1)*2+2,(q-1)*2+2) = CStiff((p-1)*2+2,(q-1)*2+2) + &
                s * C1 * dBasisdx(q,i) * dBasisdx(p,i)
          END DO
          CStiff((p-1)*2+1,(q-1)*2+1) = CStiff((p-1)*2+1,(q-1)*2+1) + &
              s * DCMPLX(-K2,0.0d0) * Basis(q) * Basis(p)

          CStiff((p-1)*2+1,(q-1)*2+2) = CStiff((p-1)*2+1,(q-1)*2+2) + &
              s * C4 * Basis(q) * Basis(p)

          CStiff((p-1)*2+2,(q-1)*2+2) = CStiff((p-1)*2+2,(q-1)*2+2) - &
              s * C2 * Basis(q) * Basis(p)
        END DO
      END DO
    END DO

    DO p=1,n
      DO i=1,2
        DO q=1,n
          DO j=1,2
            StiffMatrix( 4*(p-1)+2*i-1, 4*(q-1)+2*j-1 ) =  &
                REAL( CStiff(2*(p-1)+i,2*(q-1)+j) )
            StiffMatrix( 4*(p-1)+2*i-1, 4*(q-1)+2*j ) =  &
                -AIMAG( CStiff(2*(p-1)+i,2*(q-1)+j) )
            StiffMatrix( 4*(p-1)+2*i, 4*(q-1)+2*j-1 ) =  &
                AIMAG( CStiff(2*(p-1)+i,2*(q-1)+j) )
            StiffMatrix( 4*(p-1)+2*i, 4*(q-1)+2*j ) =  &
                REAL( CStiff(2*(p-1)+i,2*(q-1)+j) )
          END DO
        END DO
      END DO
    END DO

!------------------------------------------------------------------------------
  END SUBROUTINE SchurComplementMatrix
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE SchurComplementMatrix2(  StiffMatrix, AngularFrequency , &
      SpecificHeat, HeatRatio, Density, Pressure,               &
      Temperature, Conductivity, Viscosity, Lambda,             &
      Element, n, dim)
!------------------------------------------------------------------------------
    REAL(KIND=dp), TARGET :: StiffMatrix(:,:)
    REAL(KIND=dp) :: AngularFrequency, SpecificHeat(:), HeatRatio(:), Density(:), &
        Pressure(:),  Temperature(:), Conductivity(:), Viscosity(:), Lambda(:) 
    TYPE(Element_t), POINTER :: Element
    INTEGER :: n, dim
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: Basis(n),dBasisdx(n,3), ddBasisddx(n,3,3), DetJ, r
    COMPLEX(kind=dp) :: CStiff(2*n,2*n), C1, C2, C3, C4, K2
    LOGICAL :: Stat
    INTEGER :: t, i, j, k, l, p, q
    TYPE(GaussIntegrationPoints_t) :: IP

    REAL(KIND=dp) :: CV, kappa, mu, rho0, P0, gamma, la, K1, s

    TYPE(Nodes_t) :: Nodes
    SAVE Nodes
!------------------------------------------------------------------------------
    CALL GetElementNodes( Nodes )
    StiffMatrix = 0.0d0
    CStiff = DCMPLX( 0.0d0,0.0d0 )
    !-------------------------
    ! Numerical integration:
    !-------------------------
    IP = GaussPoints( Element,n)
    DO t=1,IP % n
      !--------------------------------------------------------------
      ! Basis function values & derivatives at the integration point:
      !--------------------------------------------------------------
      stat = ElementInfo( Element, Nodes, IP % U(t), IP % V(t), &
          IP % W(t), detJ, Basis, dBasisdx, ddBasisddx, .FALSE. )

      s = IP % s(t) * detJ
      IF (CoordSys == AxisSymmetric) THEN
        r = SUM( Basis * Nodes % x(1:n) )
        s = r * s
      END IF

      !-----------------------------------------------
      ! Material parameters at the integration point:
      !----------------------------------------------
      CV = SUM( SpecificHeat(1:n) * Basis(1:n) )       
      kappa = SUM( Conductivity(1:n) * Basis(1:n) )
      mu  = SUM( Basis(1:n) * Viscosity(1:n) )
      rho0  = SUM( Basis(1:n) * Density(1:n) )
      P0  = SUM( Basis(1:n) * Pressure(1:n) )
      gamma  = SUM( Basis(1:n) * HeatRatio(1:n) )
      la = SUM( Basis(1:n) * Lambda(1:n) )

      C1 = DCMPLX( 1.0d0, 0.0d0 )
      C2 = DCMPLX( rho0*AngularFrequency,0.0d0)/DCMPLX( P0/AngularFrequency, la+2.0d0*mu )
      C4 = DCMPLX( 1.0d0,0.0d0)/DCMPLX( 1.0d0, AngularFrequency/P0*(la+2.0d0*mu) )

      K1 = kappa/(rho0*AngularFrequency*(gamma-1.0d0)*CV)
      K2 = 1.0d0/(gamma-1.0d0) * DCMPLX( gamma, AngularFrequency/P0*(la+2.0d0*mu) ) / &
          DCMPLX( 1.0d0, AngularFrequency/P0*(la+2.0d0*mu) )   

      !---------------------------------------------
      ! the stiffness matrix...
      !----------------------------------------
      DO p=1,n
        DO q=1,n

          DO i=1,dim
            CStiff((p-1)*2+1,(q-1)*2+1) = CStiff((p-1)*2+1,(q-1)*2+1) + &
                s * DCMPLX( 0.0d0,K1) * dBasisdx(q,i) * dBasisdx(p,i)

            CStiff((p-1)*2+2,(q-1)*2+2) = CStiff((p-1)*2+2,(q-1)*2+2) + &
                s * C1 * dBasisdx(q,i) * dBasisdx(p,i)
          END DO

          CStiff((p-1)*2+1,(q-1)*2+1) = CStiff((p-1)*2+1,(q-1)*2+1) - &
              s * K2 * Basis(q) * Basis(p)

          CStiff((p-1)*2+1,(q-1)*2+2) = CStiff((p-1)*2+1,(q-1)*2+2) + &
              s * C4 * Basis(q) * Basis(p)

          CStiff((p-1)*2+2,(q-1)*2+2) = CStiff((p-1)*2+2,(q-1)*2+2) - &
              s * C2 * Basis(q) * Basis(p)

          CStiff((p-1)*2+2,(q-1)*2+1) = CStiff((p-1)*2+2,(q-1)*2+1) + &
              s * C2 * Basis(q) * Basis(p)
        END DO
      END DO
    END DO

    DO p=1,n
      DO i=1,2
        DO q=1,n
          DO j=1,2
            StiffMatrix( 4*(p-1)+2*i-1, 4*(q-1)+2*j-1 ) =  &
                REAL( CStiff(2*(p-1)+i,2*(q-1)+j) )
            StiffMatrix( 4*(p-1)+2*i-1, 4*(q-1)+2*j ) =  &
                -AIMAG( CStiff(2*(p-1)+i,2*(q-1)+j) )
            StiffMatrix( 4*(p-1)+2*i, 4*(q-1)+2*j-1 ) =  &
                AIMAG( CStiff(2*(p-1)+i,2*(q-1)+j) )
            StiffMatrix( 4*(p-1)+2*i, 4*(q-1)+2*j ) =  &
                REAL( CStiff(2*(p-1)+i,2*(q-1)+j) )
          END DO
        END DO
      END DO
    END DO

!------------------------------------------------------------------------------
  END SUBROUTINE SchurComplementMatrix2
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE GradientMatrix(  StiffMatrix, Viscosity, AngularFrequency, &
      Density, Pressure, HeatRatio, Lambda, Element, comp, n, dim)
!------------------------------------------------------------------------------
    REAL(KIND=dp), TARGET :: StiffMatrix(:,:)
    REAL(KIND=dp) :: Viscosity(:), AngularFrequency, Density(:), Pressure(:), &
        HeatRatio(:), Lambda(:) 
    INTEGER :: dim, n, comp
    TYPE(Element_t), POINTER :: Element
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: Basis(n),dBasisdx(n,3), ddBasisddx(n,3,3), DetJ, r
    COMPLEX(kind=dp) :: CStiff(n,n), C1, C2, Alpha
    LOGICAL :: Stat
    INTEGER :: t, i, j, k, l, p, q
    TYPE(GaussIntegrationPoints_t) :: IP

    REAL(KIND=dp) :: mu, rho0, P0, gamma, la, s

    TYPE(Nodes_t) :: Nodes
    SAVE Nodes
!------------------------------------------------------------------------------
    CALL GetElementNodes( Nodes )
    StiffMatrix = 0.0d0
    CStiff =  DCMPLX(0.0d0,0.0d0)
    !-------------------------
    ! Numerical integration:
    !-------------------------
    IP = GaussPoints( Element,n)
    DO t=1,IP % n
      !--------------------------------------------------------------
      ! Basis function values & derivatives at the integration point:
      !--------------------------------------------------------------
      stat = ElementInfo( Element, Nodes, IP % U(t), IP % V(t), &
          IP % W(t), detJ, Basis, dBasisdx, ddBasisddx, .FALSE. )

      s = IP % s(t) * detJ
      IF (CoordSys == AxisSymmetric) THEN
        r = SUM( Basis * Nodes % x(1:n) )
        s = r * s
      END IF

      !-----------------------------------------------
      ! Material parameters at the integration point:
      !----------------------------------------------
      mu  = SUM( Basis(1:n) * Viscosity(1:n) )
      rho0  = SUM( Basis(1:n) * Density(1:n) )
      P0  = SUM( Basis(1:n) * Pressure(1:n) )
      gamma  = SUM( Basis(1:n) * HeatRatio(1:n) )
      la = SUM( Basis(1:n) * Lambda(1:n) )

!      Alpha = DCMPLX( 0.0d0,-1.0d0) * DCMPLX( gamma,AngularFrequency/P0 * (la+mu) ) / &
!          DCMPLX( 1.0d0,AngularFrequency/P0 * la )
      Alpha = DCMPLX( 0.0d0,-1.0d0) 
      !---------------------------------------------
      ! the stiffness matrix...
      !----------------------------------------
      DO p=1,n
        DO q=1,n
!          CStiff(p,q) = CStiff(p,q) + s * Alpha * dBasisdx(q,comp) * Basis(p)
          CStiff(p,q) = CStiff(p,q) - s * Alpha * dBasisdx(p,comp) * Basis(q)
          IF ( (comp==1) .AND. (CoordSys == AxisSymmetric) ) THEN
            CStiff(p,q) = CStiff(p,q) - s * Alpha * 1/r * Basis(p) * Basis(q)
          END IF
        END DO
      END DO
    END DO

    DO i=1,n
      DO j=1,n
        StiffMatrix( 2*(i-1)+1, 2*(j-1)+1 ) =  REAL( CStiff(i,j) )
        StiffMatrix( 2*(i-1)+1, 2*(j-1)+2 ) = -AIMAG( CStiff(i,j) )
        StiffMatrix( 2*(i-1)+2, 2*(j-1)+1 ) =  AIMAG( CStiff(i,j) )
        StiffMatrix( 2*(i-1)+2, 2*(j-1)+2 ) =  REAL( CStiff(i,j) )
      END DO
    END DO

!------------------------------------------------------------------------------
  END SUBROUTINE GradientMatrix
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE VelocityImpedanceMatrix(  StiffMatrix, AngularFrequency, &
      Density, Impedance, Element, n, Nodes, dim)
!------------------------------------------------------------------------------
    REAL(KIND=dp), TARGET :: StiffMatrix(:,:)
    REAL(KIND=dp) :: AngularFrequency, Density(:), Impedance(:,:)
    INTEGER :: dim, n
    TYPE(Element_t), POINTER :: Element
    TYPE(Nodes_t) :: Nodes
!------------------------------------------------------------------------------
    COMPLEX(kind=dp) :: CStiff(dim*n,dim*n)
    REAL(KIND=dp) :: Basis(n), dBasisdx(n,3), ddBasisddx(n,3,3), DetJ, r, &
        Normal(3), Impedance1, Impedance2
    LOGICAL :: Stat
    INTEGER :: t, i, j, k, l, p, q
    TYPE(GaussIntegrationPoints_t) :: IP
    REAL(KIND=dp) :: rho0, s
!------------------------------------------------------------------------------
    StiffMatrix = 0.0d0
    CStiff = DCMPLX(0.0d0,0.0d0)
    !-------------------------
    ! Numerical integration:
    !-------------------------
    IP = GaussPoints( Element,n)
    DO t=1,IP % n
      !--------------------------------------------------------------
      ! Basis function values & derivatives at the integration point:
      !--------------------------------------------------------------
      stat = ElementInfo( Element, Nodes, IP % U(t), IP % V(t), &
          IP % W(t), detJ, Basis, dBasisdx, ddBasisddx, .FALSE. )
      s = IP % s(t) * detJ
      IF (CoordSys == AxisSymmetric) THEN
        r = SUM( Basis * Nodes % x(1:n) )
        s = r * s
      END IF
      !-----------------------------------------------
      ! Material parameters etc. at the integration point:
      !----------------------------------------------
      rho0 = SUM( Density(1:n) * Basis(1:n) )
      Normal = Normalvector(Element, Nodes, IP % U(t), IP % V(t), .TRUE.)
      Impedance1 = 1.0d0/(AngularFrequency*rho0) * SUM( Impedance(1,1:n) * Basis(1:n) )
      Impedance2 = 1.0d0/(AngularFrequency*rho0) * SUM( Impedance(2,1:n) * Basis(1:n) ) 
      !---------------------------------------------
      ! the stiffness matrix...
      !---------------------------------------------
      DO p=1,n
        DO i=1,dim
          DO q=1,n
            DO j=1,dim
              CStiff( (p-1)*DIM+i, (q-1)*DIM+j) = &
                  CStiff( (p-1)*DIM+i, (q-1)*DIM+j) + &  
                  DCMPLX(-Impedance2, Impedance1) * &
                  Basis(q) * Normal(j) * Basis(p) * Normal(i) * s
            END DO
          END DO
        END DO
      END DO
    END DO   ! Loop over integration points

    DO p=1,n
      DO i=1,DIM
        DO q=1,n
          DO j=1,DIM
            StiffMatrix( 2*DIM*(p-1)+2*i-1, 2*DIM*(q-1)+2*j-1 ) =  &
                REAL( CSTIFF(DIM*(p-1)+i,DIM*(q-1)+j) )
            StiffMatrix( 2*DIM*(p-1)+2*i-1, 2*DIM*(q-1)+2*j ) =  &
                -AIMAG( CSTIFF(DIM*(p-1)+i,DIM*(q-1)+j) )
            StiffMatrix( 2*DIM*(p-1)+2*i, 2*DIM*(q-1)+2*j-1 ) =  &
                AIMAG( CSTIFF(DIM*(p-1)+i,DIM*(q-1)+j) )
            StiffMatrix( 2*DIM*(p-1)+2*i, 2*DIM*(q-1)+2*j ) =  &
                REAL( CSTIFF(DIM*(p-1)+i,DIM*(q-1)+j) )
          END DO
        END DO
      END DO
    END DO
!------------------------------------------------------------------------------
  END SUBROUTINE VelocityImpedanceMatrix
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE SchurComplementImpedanceMatrix( StiffMatrix, Impedance, &
      AngularFrequency, SpecificHeat, HeatRatio, Density, Conductivity, &
      Element, n, Nodes, dim)
!------------------------------------------------------------------------------
    REAL(KIND=dp), TARGET :: StiffMatrix(:,:)
    REAL(KIND=dp) :: Impedance(:,:), AngularFrequency, SpecificHeat(:), &
        HeatRatio(:), Density(:), Conductivity(:)
    INTEGER :: dim, n
    TYPE(Element_t), POINTER :: Element
    TYPE(Nodes_t) :: Nodes
!------------------------------------------------------------------------------
    COMPLEX(kind=dp) :: CStiff(2*n,2*n), K1, G1, ZT
    REAL(KIND=dp) :: Basis(n), dBasisdx(n,3), ddBasisddx(n,3,3), DetJ, r, &
        Normal(3), Impedance1, Impedance2
    LOGICAL :: Stat
    INTEGER :: t, i, j, k, l, p, q
    TYPE(GaussIntegrationPoints_t) :: IP
    REAL(KIND=dp) :: CV, kappa, rho0, gamma, s
!------------------------------------------------------------------------------
    StiffMatrix = 0.0d0
    CStiff = DCMPLX(0.0d0,0.0d0)
    !-------------------------
    ! Numerical integration:
    !-------------------------
    IP = GaussPoints( Element,n)
    DO t=1,IP % n
      !--------------------------------------------------------------
      ! Basis function values & derivatives at the integration point:
      !--------------------------------------------------------------
      stat = ElementInfo( Element, Nodes, IP % U(t), IP % V(t), &
          IP % W(t), detJ, Basis, dBasisdx, ddBasisddx, .FALSE. )

      s = IP % s(t) * detJ
      IF (CoordSys == AxisSymmetric) THEN
        r = SUM( Basis * Nodes % x(1:n) )
        s = r * s
      END IF

      !-----------------------------------------------
      ! Material parameters at the integration point:
      !----------------------------------------------
      CV = SUM( SpecificHeat(1:n) * Basis(1:n) )       
      kappa = SUM( Conductivity(1:n) * Basis(1:n) )
      rho0  = SUM( Basis(1:n) * Density(1:n) )
      gamma  = SUM( Basis(1:n) * HeatRatio(1:n) )

      K1 = DCMPLX( 0.0d0, kappa/(rho0*AngularFrequency*(gamma-1.0d0)*CV) )
      ZT = DCMPLX( SUM( Impedance(3,1:n) * Basis(1:n) ), SUM( Impedance(4,1:n) * Basis(1:n) ) )
      G1 = DCMPLX( 0.0d0, AngularFrequency*rho0 ) / &
          DCMPLX(  SUM( Impedance(1,1:n) * Basis(1:n) ), SUM( Impedance(2,1:n) * Basis(1:n) ) )
      
      DO p=1,n
        DO q=1,n
          CStiff((p-1)*2+1,(q-1)*2+1) = CStiff((p-1)*2+1,(q-1)*2+1) - &
              s * K1 * ZT * Basis(q) * Basis(p)
          CStiff((p-1)*2+2,(q-1)*2+2) = CStiff((p-1)*2+2,(q-1)*2+2) - &
              s * G1 * Basis(q) * Basis(p)
        END DO
      END DO
    END DO
   
    DO p=1,n
      DO i=1,2
        DO q=1,n
          DO j=1,2
            StiffMatrix( 4*(p-1)+2*i-1, 4*(q-1)+2*j-1 ) =  &
                REAL( CStiff(2*(p-1)+i,2*(q-1)+j) )
            StiffMatrix( 4*(p-1)+2*i-1, 4*(q-1)+2*j ) =  &
                -AIMAG( CStiff(2*(p-1)+i,2*(q-1)+j) )
            StiffMatrix( 4*(p-1)+2*i, 4*(q-1)+2*j-1 ) =  &
                AIMAG( CStiff(2*(p-1)+i,2*(q-1)+j) )
            StiffMatrix( 4*(p-1)+2*i, 4*(q-1)+2*j ) =  &
                REAL( CStiff(2*(p-1)+i,2*(q-1)+j) )
          END DO
        END DO
      END DO
    END DO

!------------------------------------------------------------------------------
  END SUBROUTINE SchurComplementImpedanceMatrix
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
  SUBROUTINE VelocitySlipMatrix(  StiffMatrix, SpecificHeat, &
      HeatRatio, Density, Temperature, &
      AngularFrequency, WallTemperature, SlipCoefficient1, &
      Element, n, Nodes, dim)
!------------------------------------------------------------------------------
    REAL(KIND=dp), TARGET :: StiffMatrix(:,:)
    REAL(KIND=dp) :: SpecificHeat(:), HeatRatio(:), Density(:), &
        Temperature(:), AngularFrequency, WallTemperature(:), SlipCoefficient1
    INTEGER :: dim, n
    TYPE(Element_t), POINTER :: Element
    TYPE(Nodes_t) :: Nodes
!------------------------------------------------------------------------------
    COMPLEX(kind=dp) :: CStiff(dim*n,dim*n)    
    REAL(KIND=dp) :: Basis(n), dBasisdx(n,3), ddBasisddx(n,3,3), DetJ, r, &
        CV, gamma, rho0, T0, WallT0, C1, s, &
        Normal(3), Tangent1(3), Tangent2(3)
    LOGICAL :: Stat
    INTEGER :: t, i, j, k, l, p, q
    TYPE(GaussIntegrationPoints_t) :: IP
!------------------------------------------------------------------------------
    StiffMatrix = 0.0d0
    CStiff = DCMPLX(0.0d0,0.0d0)
    !-------------------------
    ! Numerical integration:
    !-------------------------
    IP = GaussPoints( Element,n)
    DO t=1,IP % n
      !--------------------------------------------------------------
      ! Basis function values & derivatives at the integration point:
      !--------------------------------------------------------------
      stat = ElementInfo( Element, Nodes, IP % U(t), IP % V(t), &
          IP % W(t), detJ, Basis, dBasisdx, ddBasisddx, .FALSE. )
      s = IP % s(t) * detJ
      IF (CoordSys == AxisSymmetric) THEN
        r = SUM( Basis * Nodes % x(1:n) )
        s = r * s
      END IF
      !-----------------------------------------------
      ! Material parameters etc. at the integration point:
      !----------------------------------------------
      CV = SUM( SpecificHeat(1:n) * Basis(1:n) )       
      gamma = SUM( HeatRatio(1:n) * Basis(1:n) )
      rho0 = SUM( Density(1:n) * Basis(1:n) )
      T0 =  SUM( Temperature(1:n) * Basis(1:n) )
      WallT0 = SUM( WallTemperature(1:n) * Basis(1:n) )

      C1 = -SlipCoefficient1/(2.0d0-SlipCoefficient1) * &
          rho0*SQRT(2.0d0*(gamma-1.0d0)*CV* &
          (T0+WallT0)/PI)

      Normal = Normalvector(Element, Nodes, IP % U(t), IP % V(t), .TRUE.)
      CALL TangentDirections(Normal, Tangent1, Tangent2)

      DO p=1,n
        DO i=1,dim
          DO j=1,dim
            DO q=1,n
              CStiff( (p-1)*DIM+i, (q-1)*DIM+j) = &
                  CStiff( (p-1)*DIM+i, (q-1)*DIM+j) + &
                  DCMPLX(0.0d0, C1) * 1.0d0/(AngularFrequency*rho0) * &
                  Basis(q) * Tangent1(j) * Basis(p) * Tangent1(i) * s
            END DO
          END DO
        END DO
      END DO

      IF (dim > 2) THEN
        DO p=1,n
          DO i=1,dim
            DO j=1,dim
              DO q=1,n
                CStiff( (p-1)*DIM+i, (q-1)*DIM+j) = &
                    CStiff( (p-1)*DIM+i, (q-1)*DIM+j) + &
                    DCMPLX(0.0d0, C1) * 1.0d0/(AngularFrequency*rho0) * &
                    Basis(q) * Tangent2(j) * Basis(p) * Tangent2(i) * s
              END DO
            END DO
          END DO
        END DO
      END IF
    END DO

    DO p=1,n
      DO i=1,DIM
        DO q=1,n
          DO j=1,DIM
            StiffMatrix( 2*DIM*(p-1)+2*i-1, 2*DIM*(q-1)+2*j-1 ) =  &
                REAL( CSTIFF(DIM*(p-1)+i,DIM*(q-1)+j) )
            StiffMatrix( 2*DIM*(p-1)+2*i-1, 2*DIM*(q-1)+2*j ) =  &
                -AIMAG( CSTIFF(DIM*(p-1)+i,DIM*(q-1)+j) )
            StiffMatrix( 2*DIM*(p-1)+2*i, 2*DIM*(q-1)+2*j-1 ) =  &
                AIMAG( CSTIFF(DIM*(p-1)+i,DIM*(q-1)+j) )
            StiffMatrix( 2*DIM*(p-1)+2*i, 2*DIM*(q-1)+2*j ) =  &
                REAL( CSTIFF(DIM*(p-1)+i,DIM*(q-1)+j) )
          END DO
        END DO
      END DO
    END DO
!------------------------------------------------------------------------------
  END SUBROUTINE VelocitySlipMatrix
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE SchurComplementSlipMatrix( StiffMatrix, SpecificHeat, &
      HeatRatio, Density, Temperature, AngularFrequency, Conductivity, & 
      WallTemperature, SlipCoefficient2, &
      Element, n, Nodes, dim)
!------------------------------------------------------------------------------
    REAL(KIND=dp), TARGET :: StiffMatrix(:,:)
    REAL(KIND=dp) :: SpecificHeat(:), HeatRatio(:), Density(:), Temperature(:), &
        AngularFrequency, Conductivity(:), WallTemperature(:), SlipCoefficient2
    INTEGER :: dim, n
    TYPE(Element_t), POINTER :: Element
    TYPE(Nodes_t) :: Nodes
!------------------------------------------------------------------------------
    COMPLEX(kind=dp) :: CStiff(2*n,2*n)
    REAL(KIND=dp) :: Basis(n), dBasisdx(n,3), ddBasisddx(n,3,3), DetJ, r, &
        Normal(3), Impedance1, Impedance2
    LOGICAL :: Stat
    INTEGER :: t, i, j, k, l, p, q
    TYPE(GaussIntegrationPoints_t) :: IP
    REAL(KIND=dp) :: CV, kappa, rho0, gamma, T0, WallT0, K1, C2, s
!------------------------------------------------------------------------------
    StiffMatrix = 0.0d0
    CStiff = DCMPLX(0.0d0,0.0d0)
    !-------------------------
    ! Numerical integration:
    !-------------------------
    IP = GaussPoints( Element,n)
    DO t=1,IP % n
      !--------------------------------------------------------------
      ! Basis function values & derivatives at the integration point:
      !--------------------------------------------------------------
      stat = ElementInfo( Element, Nodes, IP % U(t), IP % V(t), &
          IP % W(t), detJ, Basis, dBasisdx, ddBasisddx, .FALSE. )

      s = IP % s(t) * detJ
      IF (CoordSys == AxisSymmetric) THEN
        r = SUM( Basis * Nodes % x(1:n) )
        s = r * s
      END IF

      !-----------------------------------------------
      ! Material parameters at the integration point:
      !----------------------------------------------
      CV = SUM( SpecificHeat(1:n) * Basis(1:n) )       
      gamma = SUM( HeatRatio(1:n) * Basis(1:n) )
      rho0 = SUM( Density(1:n) * Basis(1:n) )
      kappa = SUM( Conductivity(1:n) * Basis(1:n) )
      T0 =  SUM( Temperature(1:n) * Basis(1:n) )
      WallT0 = SUM( WallTemperature(1:n) * Basis(1:n) )

      K1 = kappa/(rho0*AngularFrequency*(gamma-1.0d0)*CV)
      C2 = 1/kappa*SlipCoefficient2/(2.0d0-SlipCoefficient2) * &
          (gamma+1.0d0)/(2.0d0*(gamma-1.0d0))*rho0*(gamma-1.0d0)*CV * &
          SQRT(2.0d0*(gamma-1.0d0)*CV*(T0+WallT0)/PI)
      
      DO p=1,n
        DO q=1,n
          CStiff((p-1)*2+1,(q-1)*2+1) = CStiff((p-1)*2+1,(q-1)*2+1) + &
              s * DCMPLX(0.0d0, K1) * DCMPLX(C2, 0.0d0) * Basis(q) * Basis(p)
        END DO
      END DO
    END DO
   
    DO p=1,n
      DO i=1,2
        DO q=1,n
          DO j=1,2
            StiffMatrix( 4*(p-1)+2*i-1, 4*(q-1)+2*j-1 ) =  &
                REAL( CStiff(2*(p-1)+i,2*(q-1)+j) )
            StiffMatrix( 4*(p-1)+2*i-1, 4*(q-1)+2*j ) =  &
                -AIMAG( CStiff(2*(p-1)+i,2*(q-1)+j) )
            StiffMatrix( 4*(p-1)+2*i, 4*(q-1)+2*j-1 ) =  &
                AIMAG( CStiff(2*(p-1)+i,2*(q-1)+j) )
            StiffMatrix( 4*(p-1)+2*i, 4*(q-1)+2*j ) =  &
                REAL( CStiff(2*(p-1)+i,2*(q-1)+j) )
          END DO
        END DO
      END DO
    END DO

!------------------------------------------------------------------------------
  END SUBROUTINE SchurComplementSlipMatrix
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
  SUBROUTINE UpdateGlobalPreconditioner( StiffMatrix, LocalStiffMatrix, &
      n, NDOFs, NodeIndexes )
!------------------------------------------------------------------------------
! 
! Add element matrices to global matrices
!
! TYPE(Matrix_t), POINTER :: StiffMatrix
!   INOUT: The global matrix
!
! REAL(KIND=dp) :: LocalStiffMatrix(:,:)
!   INPUT: Local matrix to be added to the global matrix
!
! INTEGER :: n, NDOFs
!   INPUT :: number of nodes / element and number of DOFs / node
!
! INTEGER :: NodeIndexes(:)
!   INPUT: Element node to global node numbering mapping
! 
!------------------------------------------------------------------------------
     TYPE(Matrix_t), POINTER :: StiffMatrix

     REAL(KIND=dp) :: LocalStiffMatrix(:,:)

     INTEGER :: n, NDOFs, NodeIndexes(:)
!------------------------------------------------------------------------------
     INTEGER :: i,j,k
!------------------------------------------------------------------------------
!    Update global matrix .
!------------------------------------------------------------------------------
     SELECT CASE( StiffMatrix % FORMAT )
     CASE( MATRIX_CRS )
       CALL CRS_GlueLocalMatrix( StiffMatrix,n,NDOFs, NodeIndexes, &
           LocalStiffMatrix )
     END SELECT

!------------------------------------------------------------------------------
   END SUBROUTINE UpdateGlobalPreconditioner
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   SUBROUTINE SetBoundaryConditions( Model, StiffMatrix, &
                   Name, DOF, NDOFs, Perm )
!------------------------------------------------------------------------------
!
! Set dirichlet boundary condition for given dof
!
! TYPE(Model_t) :: Model
!   INPUT: the current model structure
!
! TYPE(Matrix_t), POINTER :: StiffMatrix
!   INOUT: The global matrix
!
! CHARACTER(LEN=*) :: Name
!   INPUT: name of the dof to be set
!
! INTEGER :: DOF, NDOFs
!   INPUT: The order number of the dof and the total number of DOFs for
!          this equation
!
! INTEGER :: Perm(:)
!   INPUT: The node reordering info, this has been generated at the
!          beginning of the simulation for bandwidth optimization
!******************************************************************************
!------------------------------------------------------------------------------
    TYPE(Model_t) :: Model
    TYPE(Matrix_t), POINTER :: StiffMatrix

    CHARACTER(LEN=*) :: Name 
    INTEGER :: DOF, NDOFs, Perm(:)
!------------------------------------------------------------------------------

    TYPE(Element_t), POINTER :: CurrentElement
    INTEGER, POINTER :: NodeIndexes(:)
    INTEGER :: i,j,k,n,t,k1,k2
    LOGICAL :: GotIt, periodic
    REAL(KIND=dp) :: Work(Model % MaxElementNodes),s

!------------------------------------------------------------------------------

    DO t = Model % NumberOfBulkElements + 1, &
        Model % NumberOfBulkElements + Model % NumberOfBoundaryElements

      CurrentElement => Model % Elements(t)
!------------------------------------------------------------------------------
!      Set the current element pointer in the model structure to
!      reflect the element being processed
!------------------------------------------------------------------------------
      Model % CurrentElement => Model % Elements(t)
!------------------------------------------------------------------------------
      n = CurrentElement % TYPE % NumberOfNodes
      NodeIndexes => CurrentElement % NodeIndexes(1:n)

      DO i=1,Model % NumberOfBCs
        IF ( CurrentElement % BoundaryInfo % Constraint == &
            Model % BCs(i) % Tag ) THEN

          Work(1:n) = ListGetReal( Model % BCs(i) % Values, &
              Name,n,NodeIndexes, gotIt )
          IF ( gotIt ) THEN
            DO j=1,n
              k = Perm(NodeIndexes(j))
              IF ( k > 0 ) THEN
                k = NDOFs * (k-1) + DOF
                s = 1.0d0 
                CALL ZeroRow( StiffMatrix,k )
                CALL SetMatrixElement( StiffMatrix,k,k, 1.0d0 * s )
              END IF
            END DO
          END IF
        END IF
      END DO
    END DO
!------------------------------------------------------------------------------
   END SUBROUTINE SetBoundaryConditions
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
   SUBROUTINE SetBoundaryConditions2( Model, StiffMatrix, &
                   Name, DOF, NDOFs, Perm )
!------------------------------------------------------------------------------
!
! Set dirichlet boundary condition for given dof
!
! TYPE(Model_t) :: Model
!   INPUT: the current model structure
!
! TYPE(Matrix_t), POINTER :: StiffMatrix
!   INOUT: The global matrix
!
! CHARACTER(LEN=*) :: Name
!   INPUT: name of the dof to be set
!
! INTEGER :: DOF, NDOFs
!   INPUT: The order number of the dof and the total number of DOFs for
!          this equation
!
! INTEGER :: Perm(:)
!   INPUT: The node reordering info, this has been generated at the
!          beginning of the simulation for bandwidth optimization
!******************************************************************************
!------------------------------------------------------------------------------
    TYPE(Model_t) :: Model
    TYPE(Matrix_t), POINTER :: StiffMatrix

    CHARACTER(LEN=*) :: Name 
    INTEGER :: DOF, NDOFs, Perm(:)
!------------------------------------------------------------------------------

    TYPE(Element_t), POINTER :: CurrentElement
    INTEGER, POINTER :: NodeIndexes(:)
    INTEGER :: i,j,k,n,t,k1,k2
    LOGICAL :: GotIt, periodic
    REAL(KIND=dp) :: Work(Model % MaxElementNodes),s

!------------------------------------------------------------------------------

    DO t = Model % NumberOfBulkElements + 1, &
        Model % NumberOfBulkElements + Model % NumberOfBoundaryElements

      CurrentElement => Model % Elements(t)
!------------------------------------------------------------------------------
!      Set the current element pointer in the model structure to
!      reflect the element being processed
!------------------------------------------------------------------------------
      Model % CurrentElement => Model % Elements(t)
!------------------------------------------------------------------------------
      n = CurrentElement % TYPE % NumberOfNodes
      NodeIndexes => CurrentElement % NodeIndexes(1:n)

      DO i=1,Model % NumberOfBCs
        IF ( CurrentElement % BoundaryInfo % Constraint == &
            Model % BCs(i) % Tag ) THEN

          Work(1:n) = ListGetReal( Model % BCs(i) % Values, &
              Name,n,NodeIndexes, gotIt )
          IF ( gotIt ) THEN
            DO j=1,n
              k = Perm(NodeIndexes(j))
              IF ( k > 0 ) THEN
                k = NDOFs * (k-1) + DOF
!                s = 1.0d0 
                CALL ZeroRow( StiffMatrix,k )
!                CALL SetMatrixElement( StiffMatrix,k,k, 1.0d0 * s )
              END IF
            END DO
          END IF
        END IF
      END DO
    END DO
!------------------------------------------------------------------------------
   END SUBROUTINE SetBoundaryConditions2
!------------------------------------------------------------------------------





!------------------------------------------------------------------------------
  SUBROUTINE LocalMatrix(  StiffMatrix, Force, AngularFrequency , &
      SpecificHeat, HeatRatio, Density,               &
      Temperature, Conductivity, Viscosity, Lambda,             &
      HeatSource, Load, Bubbles, Element, n, Nodes, Dofs )
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: StiffMatrix(:,:), Force(:), AngularFrequency, &
        SpecificHeat(:), HeatRatio(:), Density(:),    &       
        Temperature(:), Conductivity(:), Viscosity(:), Lambda(:),  &
        HeatSource(:,:), Load(:,:)
    LOGICAL :: Bubbles
    INTEGER :: n, Dofs
    TYPE(Nodes_t) :: Nodes
    TYPE(Element_t), POINTER :: Element
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: Basis(2*n), dBasisdx(2*n,3), ddBasisddx(n,3,3)
    REAL(KIND=dp) :: SqrtElementMetric, U, V, W, S, L(6), &
        CV, gamma, rho0, P0, T0, kappa, mu, la, f1, f2, K1, K2, K3  
    COMPLEX(KIND=dp) :: LSTIFF(n*(Dofs-2),n*(Dofs-2)), LFORCE(n*(Dofs-2)), A

    INTEGER :: i, j, p, q, t, DIM, NBasis, CoordSys, VelocityDofs, & 
        VelocityComponents
    TYPE(GaussIntegrationPoints_t) :: IntegStuff

    REAL(KIND=dp) :: X, Y, Z, Metric(3,3), SqrtMetric, Symb(3,3,3), &
        dSymb(3,3,3,3)
!------------------------------------------------------------------------------

    DIM = CoordinateSystemDimension()

    Metric = 0.0d0
    Metric(1,1) = 1.0d0
    Metric(2,2) = 1.0d0
    Metric(3,3) = 1.0d0

    LSTIFF = DCMPLX(0.0d0,0.0d0)
    LFORCE = DCMPLX(0.0d0,0.0d0)
!------------------------------------------------------------------------------
!   Numerical integration
!------------------------------------------------------------------------------
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
!------------------------------------------------------------------------------
!     Problem parameters and the real and imaginary part of the 
!     load at the integration point
!------------------------------------------------------------------------------
       CV = SUM( SpecificHeat(1:n) * Basis(1:n) )       
       gamma = SUM( HeatRatio(1:n) * Basis(1:n) )
       rho0 = SUM( Density(1:n) * Basis(1:n) )
!       P0 = SUM( Pressure(1:n) * Basis(1:n) )
       T0 = SUM( Temperature(1:n) * Basis(1:n) )
       kappa = SUM( Conductivity(1:n) * Basis(1:n) )
       mu = SUM( Viscosity(1:n) * Basis(1:n) )
       la = SUM( Lambda(1:n) * Basis(1:n) )

       P0 = (gamma-1.0d0)*CV*rho0*T0
!       K1 = kappa*AngularFrequency/(CV*(gamma-1.0d0)*P0)
       K1 = kappa/(rho0*AngularFrequency*(gamma-1.0d0)*CV)
!       K2 = AngularFrequency**2*rho0/(P0*(gamma-1.0d0))
       K2 = 1.0d0/(gamma-1.0d0)
       K3 = 1.0d0/AngularFrequency**2

       f1 = K3*SUM( HeatSource(1,1:n) * Basis(1:n) )
       f2 = K3*SUM( HeatSource(2,1:n) * Basis(1:n) )
       DO i=1,2*DIM
         L(i) = 1.0d0/AngularFrequency*SUM( Load(i,1:n) * Basis(1:n) )
       END DO

!------------------------------------------------------------------------------
!      The stiffness matrix and load vector...
!      The following is the contribution from the heat equation and pressure
!      equation, i.e. the part arising from the loop over the test functions 
!      for temperature and pressure 
!------------------------------------------------------------------------------

       DO p=1,N
         DO q=1,N
           A = DCMPLX( -K2, 0.0d0 ) * Basis(q) * Basis(p)
           DO i=1,DIM
!------------------------------------------------------------------------------
!             Coefficients for the nodal velocities...
!------------------------------------------------------------------------------
             LSTIFF( p*(DIM+2), (q-1)*(DIM+2)+i) =  &
                 LSTIFF( p*(DIM+2), (q-1)*(DIM+2)+i) + &
                 DCMPLX(0.0d0, 1.0d0) * dBasisdx(q,i) * Basis(p) * s 
             DO j=1,DIM
               A = A + Metric(i,j) * DCMPLX( 0.0d0, K1 ) * &
                   dBasisdx(q,i) * dBasisdx(p,j)
             END DO
           END DO
!------------------------------------------------------------------------------
!          Coefficients for the nodal temperatures
!------------------------------------------------------------------------------
           LSTIFF( (p-1)*(DIM+2)+DIM+1, (q-1)*(DIM+2)+DIM+1 ) = &
               LSTIFF( (p-1)*(DIM+2)+DIM+1, (q-1)*(DIM+2)+DIM+1 ) + s*A
!------------------------------------------------------------------------------
!          Coefficients for the nodal pressures
!------------------------------------------------------------------------------

           LSTIFF( (p-1)*(DIM+2)+DIM+1, (q-1)*(DIM+2)+DIM+2) =  &
               LSTIFF( (p-1)*(DIM+2)+DIM+1, (q-1)*(DIM+2)+DIM+2) + &
                s * 1.0d0/DCMPLX( 1.0d0, AngularFrequency/P0*la ) * &
                Basis(q) * Basis(p)

           LSTIFF( p*(DIM+2), q*(DIM+2) ) = &
                LSTIFF( p*(DIM+2), q*(DIM+2) ) - &
                s * rho0*AngularFrequency/DCMPLX( P0/AngularFrequency, la ) * &
                Basis(q) * Basis(p)
         END DO
         LFORCE( (p-1)*(DIM+2)+DIM+1 ) = &
             LFORCE( (p-1)*(DIM+2)+DIM+1 ) + s * Basis(p) * DCMPLX( -f2,f1 )
       END DO

       IF ( Bubbles ) THEN
         DO p=1,n
           DO q=n+1,NBasis
             DO i=1,DIM
!------------------------------------------------------------------------------
!          Coefficients for the nodal velocities
!------------------------------------------------------------------------------
               LSTIFF( p*(DIM+2), (q-1)*DIM+2*n+i) = &
                   LSTIFF( p*(DIM+2), (q-1)*DIM+2*n+i) + &
                   DCMPLX( 0.0d0, 1.0d0 ) * dBasisdx(q,i) * Basis(p) * s 
             END DO
           END DO
         END DO
       END IF

!------------------------------------------------------------------------------
!      The following is the contribution from the NS-equation, i.e. the 
!      part arising from the loop over the test functions for velocity 
!------------------------------------------------------------------------------

       DO i=1,DIM
         DO p=1,n
           DO q=1,n
!------------------------------------------------------------------------------
!            Coefficients for the nodal temperatures...               
!------------------------------------------------------------------------------
             LSTIFF( (p-1)*(DIM+2)+i, (q-1)*(DIM+2)+DIM+1 ) = &
                 LSTIFF( (p-1)*(DIM+2)+i, (q-1)*(DIM+2)+DIM+1 ) + &
                 DCMPLX( 0.0d0, 1.0d0 ) * dBasisdx(p,i) * Basis(q) * s
!------------------------------------------------------------------------------
!            Coefficients for the nodal pressures...               
!------------------------------------------------------------------------------
             LSTIFF( (p-1)*(DIM+2)+i, q*(DIM+2) ) = &
                 LSTIFF( (p-1)*(DIM+2)+i, q*(DIM+2) ) + &
                 DCMPLX( 0.0d0, 1.0d0 ) * dBasisdx(p,i) * Basis(q) * s
!------------------------------------------------------------------------------
!            Coefficients for the nodal velocities...             
!------------------------------------------------------------------------------
             LSTIFF( (p-1)*(DIM+2)+i, (q-1)*(DIM+2)+i) = &
                 LSTIFF( (p-1)*(DIM+2)+i,(q-1)*(DIM+2)+i) + &
                 DCMPLX(1.0d0, 0.0d0 ) * &
                 Basis(q) * Basis(p) * s
                
             DO j=1,DIM
!------------------------------------------------------------------------------
!              grad(v)grav(w)-type terms
!------------------------------------------------------------------------------
               LSTIFF((p-1)*(DIM+2)+i, (q-1)*(DIM+2)+i) = &
                   LSTIFF((p-1)*(DIM+2)+i, (q-1)*(DIM+2)+i) + &
                   DCMPLX( 0.0d0, -mu/(AngularFrequency*rho0) ) * dBasisdx(q,j) * dBasisdx(p,j) * s
               LSTIFF((p-1)*(DIM+2)+i, (q-1)*(DIM+2)+j) = &
                   LSTIFF((p-1)*(DIM+2)+i, (q-1)*(DIM+2)+j) + &
                   DCMPLX( 0.0d0, -mu/(AngularFrequency*rho0) ) * dBasisdx(q,i) * dBasisdx(p,j) * s
             END DO
           END DO
!------------------------------------------------------------------------------
!          The components of force vector... 
!------------------------------------------------------------------------------
           LFORCE( (p-1)*(DIM+2)+i) = LFORCE( (p-1)*(DIM+2)+i ) - &
               s * Basis(p) * DCMPLX( -L((i-1)*2+2), L((i-1)*2+1)  )
         END DO
       END DO

       IF ( Bubbles ) THEN
         DO i=1,DIM
           DO p=1,n
             DO q=n+1,NBasis
!------------------------------------------------------------------------------
!            coefficients for the nodal velocities             
!------------------------------------------------------------------------------
               LSTIFF( (p-1)*(DIM+2)+i, (q-1)*DIM+2*n+i) = &
                   LSTIFF( (p-1)*(DIM+2)+i,(q-1)*DIM+2*n+i) + &
                   DCMPLX( 1.0d0, 0.0d0 ) * &
                   Basis(q) * Basis(p) * s
                
               DO j=1,DIM
!------------------------------------------------------------------------------
!                grad(v)grav(w)-type terms
!------------------------------------------------------------------------------
                 LSTIFF((p-1)*(DIM+2)+i, (q-1)*DIM+2*n+i) = &
                     LSTIFF((p-1)*(DIM+2)+i, (q-1)*DIM+2*n+i) + &
                     DCMPLX( 0.0d0, -mu/(AngularFrequency*rho0) ) * dBasisdx(q,j) * dBasisdx(p,j) * s
                 LSTIFF((p-1)*(DIM+2)+i, (q-1)*DIM+2*n+j) = &
                     LSTIFF((p-1)*(DIM+2)+i, (q-1)*DIM+2*n+j) + &
                     DCMPLX( 0.0d0, -mu/(AngularFrequency*rho0) ) * dBasisdx(q,i) * dBasisdx(p,j) * s
               END DO
             END DO
           END DO
         END DO

         DO i=1,DIM
           DO p=n+1,NBasis
             DO q=1,n
!------------------------------------------------------------------------------
!              Coefficients for the nodal temperatures               
!------------------------------------------------------------------------------
               LSTIFF( (p-1)*DIM+2*n+i, (q-1)*(DIM+2)+DIM+1 ) = &
                   LSTIFF( (p-1)*DIM+2*n+i, (q-1)*(DIM+2)+DIM+1 ) + &
                   DCMPLX( 0.0d0, 1.0d0) * dBasisdx(p,i) * Basis(q) * s
!------------------------------------------------------------------------------
!            Coefficients for the nodal pressures...               
!------------------------------------------------------------------------------
               LSTIFF( (p-1)*DIM+2*n+i, q*(DIM+2) ) = &
                   LSTIFF( (p-1)*DIM+2*n+i, q*(DIM+2) ) + &
                   DCMPLX( 0.0d0, 1.0d0 ) * dBasisdx(p,i) * Basis(q) * s
!------------------------------------------------------------------------------
!              coefficients for the nodal velocities 
!------------------------------------------------------------------------------
               LSTIFF( (p-1)*DIM+2*n+i, (q-1)*(DIM+2)+i) = &
                   LSTIFF( (p-1)*DIM+2*n+i,(q-1)*(DIM+2)+i) + &
                   DCMPLX( 1.0d0, 0.0d0 ) * &
                   Basis(q) * Basis(p) * s
                
               DO j=1,DIM
!------------------------------------------------------------------------------
!                grad(v)grav(w)-type terms
!------------------------------------------------------------------------------
                 LSTIFF( (p-1)*DIM+2*n+i, (q-1)*(DIM+2)+i) = &
                     LSTIFF( (p-1)*DIM+2*n+i, (q-1)*(DIM+2)+i) + &
                     DCMPLX( 0.0d0, -mu/(AngularFrequency*rho0) ) * dBasisdx(q,j) * dBasisdx(p,j) * s
                 LSTIFF( (p-1)*DIM+2*n+i, (q-1)*(DIM+2)+j) = &
                     LSTIFF( (p-1)*DIM+2*n+i, (q-1)*(DIM+2)+j) + &
                     DCMPLX( 0.0d0, -mu/(AngularFrequency*rho0) ) * dBasisdx(q,i) * dBasisdx(p,j) * s
               END DO
             END DO
!------------------------------------------------------------------------------
!            The components of force vector... 
!------------------------------------------------------------------------------
             LFORCE( (p-1)*DIM+2*n+i ) = LFORCE( (p-1)*DIM+2*n+i ) - &
                 s * Basis(p) * DCMPLX( -L((i-1)*2+2), L((i-1)*2+1) )
           END DO
         END DO

         DO i=1,DIM
           DO p=n+1,NBasis
             DO q=n+1,NBasis
!------------------------------------------------------------------------------
!              coefficients for the nodal velocities 
!------------------------------------------------------------------------------
               LSTIFF( (p-1)*DIM+2*n+i, (q-1)*DIM+2*n+i) = &
                   LSTIFF( (p-1)*DIM+2*n+i,(q-1)*DIM+2*n+i) + &
                   DCMPLX( 1.0d0, 0.0d0 ) * &
                   Basis(q) * Basis(p) * s
                
               DO j=1,DIM
!------------------------------------------------------------------------------
!                grad(v)grav(w)-type terms
!------------------------------------------------------------------------------
                 LSTIFF( (p-1)*DIM+2*n+i, (q-1)*DIM+2*n+i) = &
                     LSTIFF( (p-1)*DIM+2*n+i, (q-1)*DIM+2*n+i) + &
                     DCMPLX( 0.0d0, -mu/(AngularFrequency*rho0) ) * dBasisdx(q,j) * dBasisdx(p,j) * s
                 LSTIFF( (p-1)*DIM+2*n+i, (q-1)*DIM+2*n+j) = &
                     LSTIFF( (p-1)*DIM+2*n+i, (q-1)*DIM+2*n+j) + &
                     DCMPLX( 0.0d0, -mu/(AngularFrequency*rho0) ) * dBasisdx(q,i) * dBasisdx(p,j) * s
               END DO
             END DO
           END DO
         END DO         
!------------------------------------------------------------------------------
       END IF   ! IF (Bubbles)...
!------------------------------------------------------------------------------
    END DO      ! Loop over integration points
!------------------------------------------------------------------------------

    IF ( Bubbles ) THEN
      CALL LCondensate( n, dim, LSTIFF, LFORCE )
    END IF

    DO p=1,n
      DO i=1,DIM+2
        Force( 2*(DIM+2)*(p-1)+2*i-1 ) = REAL(LFORCE( (p-1)*(DIM+2)+i ))
        Force( 2*(DIM+2)*(p-1)+2*i ) = AIMAG(LFORCE( (p-1)*(DIM+2)+i ))
        DO q=1,n
          DO j=1,DIM+2
            StiffMatrix( 2*(DIM+2)*(p-1)+2*i-1, 2*(DIM+2)*(q-1)+2*j-1 ) =  &
                REAL( LSTIFF((DIM+2)*(p-1)+i,(DIM+2)*(q-1)+j) )
            StiffMatrix( 2*(DIM+2)*(p-1)+2*i-1, 2*(DIM+2)*(q-1)+2*j ) =  &
                -AIMAG( LSTIFF((DIM+2)*(p-1)+i,(DIM+2)*(q-1)+j) )
            StiffMatrix( 2*(DIM+2)*(p-1)+2*i, 2*(DIM+2)*(q-1)+2*j-1 ) =  &
                AIMAG( LSTIFF((DIM+2)*(p-1)+i,(DIM+2)*(q-1)+j) )
            StiffMatrix( 2*(DIM+2)*(p-1)+2*i, 2*(DIM+2)*(q-1)+2*j ) =  &
                REAL( LSTIFF((DIM+2)*(p-1)+i,(DIM+2)*(q-1)+j) )
          END DO
        END DO
      END DO
    END DO

   
!------------------------------------------------------------------------------
  END SUBROUTINE LocalMatrix
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE LocalMatrixBoundary(  StiffMatrix, Force, AngularFrequency, &
      SpecificHeat, HeatRatio, Density, Pressure,               &
      Temperature, Conductivity, Impedance, Load, &
      Element, n, Nodes, Dofs )
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: StiffMatrix(:,:), Force(:), AngularFrequency, & 
        SpecificHeat(:), HeatRatio(:), Density(:), Pressure(:),    &
        Temperature(:), Conductivity(:), Impedance(:,:), &
        Load(:,:)
    INTEGER :: n, Dofs
    TYPE(Nodes_t) :: Nodes
    TYPE(Element_t), POINTER :: Element
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: SqrtElementMetric, U, V, W, S, Impedance1, Impedance2, &
        Impedance3, Impedance4, CV, gamma, rho0, P0, T0, kappa, K1, L(6),   & 
        Basis(n), dBasisdx(n,3), ddBasisddx(n,3,3), X, Y, Z, Normal(3)
    COMPLEX(KIND=dp) :: LSTIFF(n*(Dofs-2),n*(Dofs-2)), LFORCE(n*(Dofs-2))
    LOGICAL :: Stat
    INTEGER :: i, j, p, q, t, DIM
    TYPE(GaussIntegrationPoints_t) :: IntegStuff
!------------------------------------------------------------------------------
    DIM = CoordinateSystemDimension()
    CoordSys = CurrentCoordinateSystem()
    LSTIFF = DCMPLX(0.0d0,0.0d0)
    LFORCE = DCMPLX(0.0d0,0.0d0)
!------------------------------------------------------------------------------
!   Numerical integration
!------------------------------------------------------------------------------
    IntegStuff = GaussPoints( Element )
!------------------------------------------------------------------------------
    DO t=1, IntegStuff % n
      U = IntegStuff % u(t)
      V = IntegStuff % v(t)
      W = IntegStuff % w(t)
      S = IntegStuff % s(t)
!------------------------------------------------------------------------------
!     Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
      stat = ElementInfo( Element, Nodes, U, V, W, SqrtElementMetric, &
          Basis, dBasisdx, ddBasisddx, .FALSE., .FALSE. )
      s = s * SqrtElementMetric
!------------------------------------------------------------------------------
!     Problem parameters at the integration point
!------------------------------------------------------------------------------
      CV = SUM( SpecificHeat(1:n) * Basis(1:n) )       
      gamma = SUM( HeatRatio(1:n) * Basis(1:n) )
      rho0 = SUM( Density(1:n) * Basis(1:n) )
      P0 = SUM( Pressure(1:n) * Basis(1:n) )
      T0 = SUM( Temperature(1:n) * Basis(1:n) )
      kappa = SUM( Conductivity(1:n) * Basis(1:n) )
!      K1 = kappa*AngularFrequency/(CV*(gamma-1.0d0)*P0)
      K1 = kappa/(rho0*AngularFrequency*(gamma-1.0d0)*CV)
      Normal = Normalvector(Element, Nodes, U, V, .TRUE.)

      Impedance1 = 1.0d0/(AngularFrequency*rho0) * SUM( Impedance(1,1:n) * Basis(1:n) )
      Impedance2 = 1.0d0/(AngularFrequency*rho0) * SUM( Impedance(2,1:n) * Basis(1:n) ) 
      Impedance3 = SUM( Impedance(3,1:n) * Basis(1:n) ) 
      Impedance4 = SUM( Impedance(4,1:n) * Basis(1:n) ) 

      DO i=1,2*DIM
        L(i) = 1.0d0/(AngularFrequency*rho0) * SUM( Load(i,1:n) * Basis(1:n) )
      END DO

      DO p=1,n
        DO i=1,dim
          DO q=1,n
            DO j=1,dim
              LSTIFF( (p-1)*(DIM+2)+i, (q-1)*(DIM+2)+j) = &
                  LSTIFF( (p-1)*(DIM+2)+i, (q-1)*(DIM+2)+j) + &  
                  DCMPLX(-Impedance2, Impedance1) * &
                  Basis(q) * Normal(j) * Basis(p) * Normal(i) * s
            END DO
          END DO
          LFORCE( (p-1)*(DIM+2)+i) = LFORCE( (p-1)*(DIM+2)+i ) - &
              s * Basis(p) * DCMPLX( -L((i-1)*2+2), L((i-1)*2+1)  )
        END DO
      END DO

      DO p=1,n
        DO q=1,n
          LSTIFF( (p-1)*(DIM+2)+DIM+1, (q-1)*(DIM+2)+DIM+1) = &
              LSTIFF( (p-1)*(DIM+2)+DIM+1, (q-1)*(DIM+2)+DIM+1) - & 
              DCMPLX(0.0d0, K1) * DCMPLX(Impedance3, Impedance4) * &
              Basis(q) * Basis(p) * s
        END DO
      END DO

    END DO   ! Loop over integration points

    DO p=1,n
      DO i=1,DIM+2
        Force( 2*(DIM+2)*(p-1)+2*i-1 ) = REAL(LFORCE( (p-1)*(DIM+2)+i ))
        Force( 2*(DIM+2)*(p-1)+2*i ) = AIMAG(LFORCE( (p-1)*(DIM+2)+i ))
        DO q=1,n
          DO j=1,DIM+2
            StiffMatrix( 2*(DIM+2)*(p-1)+2*i-1, 2*(DIM+2)*(q-1)+2*j-1 ) =  &
                REAL( LSTIFF((DIM+2)*(p-1)+i,(DIM+2)*(q-1)+j) )
            StiffMatrix( 2*(DIM+2)*(p-1)+2*i-1, 2*(DIM+2)*(q-1)+2*j ) =  &
                -AIMAG( LSTIFF((DIM+2)*(p-1)+i,(DIM+2)*(q-1)+j) )
            StiffMatrix( 2*(DIM+2)*(p-1)+2*i, 2*(DIM+2)*(q-1)+2*j-1 ) =  &
                AIMAG( LSTIFF((DIM+2)*(p-1)+i,(DIM+2)*(q-1)+j) )
            StiffMatrix( 2*(DIM+2)*(p-1)+2*i, 2*(DIM+2)*(q-1)+2*j ) =  &
                REAL( LSTIFF((DIM+2)*(p-1)+i,(DIM+2)*(q-1)+j) )
          END DO
        END DO
      END DO
    END DO
!------------------------------------------------------------------------------
  END SUBROUTINE LocalMatrixBoundary
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
  SUBROUTINE LCondensate( n, dim, K, F )
!------------------------------------------------------------------------------
    USE LinearAlgebra
!------------------------------------------------------------------------------
    INTEGER :: n, dim
    COMPLEX(KIND=dp) :: K(:,:), F(:), Kbb(dim*n,dim*n), &
         Kbl(dim*n,(dim+2)*n), Klb((dim+2)*n,dim*n), Fb(n*dim)

    INTEGER :: i, Ldofs((dim+2)*n), Bdofs(dim*n)

    Ldofs = (/ (i, i=1,(dim+2)*n) /)
    Bdofs = (/ ((dim+2)*n+i, i=1, dim*n) /)

    Kbb = K(Bdofs,Bdofs)
    Kbl = K(Bdofs,Ldofs)
    Klb = K(Ldofs,Bdofs)
    Fb  = F(Bdofs)

    CALL ComplexInvertMatrix( Kbb,n*dim )

    F(1:(dim+2)*n) = F(1:(dim+2)*n) - MATMUL( Klb, MATMUL( Kbb, Fb  ) )
    K(1:(dim+2)*n,1:(dim+2)*n) = &
         K(1:(dim+2)*n,1:(dim+2)*n) - MATMUL( Klb, MATMUL( Kbb, Kbl ) )
!------------------------------------------------------------------------------
  END SUBROUTINE LCondensate
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
! The element matrices in the case of axial symmetry...
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
  SUBROUTINE LocalMatrix2(  StiffMatrix, Force, AngularFrequency , &
      SpecificHeat, HeatRatio, Density,               &
      Temperature, Conductivity, Viscosity, Lambda,             &
      HeatSource, Load, Bubbles, Element, n, Nodes, Dofs )
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: StiffMatrix(:,:), Force(:), AngularFrequency, &
        SpecificHeat(:), HeatRatio(:), Density(:),    &       
        Temperature(:), Conductivity(:), Viscosity(:), Lambda(:),  &
        HeatSource(:,:), Load(:,:)
    LOGICAL :: Bubbles
    INTEGER :: n, Dofs
    TYPE(Nodes_t) :: Nodes
    TYPE(Element_t), POINTER :: Element
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: Basis(2*n), dBasisdx(2*n,3), ddBasisddx(n,3,3)
    REAL(KIND=dp) :: SqrtElementMetric, U, V, W, S, L(6), &
        CV, gamma, rho0, P0, T0, kappa, mu, la, f1, f2, K1, K2, K3, r  
    COMPLEX(KIND=dp) :: LSTIFF(n*(Dofs-2),n*(Dofs-2)), LFORCE(n*(Dofs-2)), A

    INTEGER :: i, j, p, q, t, DIM, NBasis, VelocityDofs, & 
        VelocityComponents
    TYPE(GaussIntegrationPoints_t) :: IntegStuff

    REAL(KIND=dp) :: X, Y, Z, Metric(3,3), SqrtMetric, Symb(3,3,3), &
        dSymb(3,3,3,3)
!------------------------------------------------------------------------------

    DIM = CoordinateSystemDimension()

    Metric = 0.0d0
    Metric(1,1) = 1.0d0
    Metric(2,2) = 1.0d0
    Metric(3,3) = 1.0d0

    LSTIFF = DCMPLX(0.0d0,0.0d0)
    LFORCE = DCMPLX(0.0d0,0.0d0)
!------------------------------------------------------------------------------
!   Numerical integration
!------------------------------------------------------------------------------
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

       r = SUM( Basis(1:n) * Nodes % x(1:n) )
       s = r * s * SqrtElementMetric

!------------------------------------------------------------------------------
!     Problem parameters and the real and imaginary part of the 
!     load at the integration point
!------------------------------------------------------------------------------
       CV = SUM( SpecificHeat(1:n) * Basis(1:n) )       
       gamma = SUM( HeatRatio(1:n) * Basis(1:n) )
       rho0 = SUM( Density(1:n) * Basis(1:n) )
!       P0 = SUM( Pressure(1:n) * Basis(1:n) )
       T0 = SUM( Temperature(1:n) * Basis(1:n) )
       kappa = SUM( Conductivity(1:n) * Basis(1:n) )
       mu = SUM( Viscosity(1:n) * Basis(1:n) )
       la = SUM( Lambda(1:n) * Basis(1:n) )

       P0 = (gamma-1.0d0)*CV*rho0*T0
!       K1 = kappa*AngularFrequency/(CV*(gamma-1.0d0)*P0)
       K1 = kappa/(rho0*AngularFrequency*(gamma-1.0d0)*CV)
!       K2 = AngularFrequency**2*rho0/(P0*(gamma-1.0d0))
       K2 = 1.0d0/(gamma-1.0d0)
       K3 = 1.0d0/AngularFrequency**2

       f1 = K3*SUM( HeatSource(1,1:n) * Basis(1:n) )
       f2 = K3*SUM( HeatSource(2,1:n) * Basis(1:n) )
       DO i=1,2*DIM
         L(i) = 1.0d0/AngularFrequency*SUM( Load(i,1:n) * Basis(1:n) )
       END DO

!------------------------------------------------------------------------------
!      The stiffness matrix and load vector...
!      The following is the contribution from the heat equation and pressure
!      equation, i.e. the part arising from the loop over the test functions 
!      for temperature and pressure 
!------------------------------------------------------------------------------
       DO p=1,N
         DO q=1,N
           A = DCMPLX( -K2, 0.0d0 ) * Basis(q) * Basis(p)
           DO i=1,DIM
!------------------------------------------------------------------------------
!            Coefficients for the nodal velocities...
!------------------------------------------------------------------------------
             LSTIFF( p*(DIM+2), (q-1)*(DIM+2)+i) =  &
                 LSTIFF( p*(DIM+2), (q-1)*(DIM+2)+i) + &
                 DCMPLX(0.0d0, 1.0d0) * dBasisdx(q,i) * Basis(p) * s 

             IF (i==1) THEN
               LSTIFF( p*(DIM+2), (q-1)*(DIM+2)+i) =  &
                   LSTIFF( p*(DIM+2), (q-1)*(DIM+2)+i) + &
                   DCMPLX(0.0d0, 1.0d0) * 1/r * Basis(q) * Basis(p) * s 
             END IF

             DO j=1,DIM
               A = A + Metric(i,j) * DCMPLX( 0.0d0, K1 ) * &
                   dBasisdx(q,i) * dBasisdx(p,j)
             END DO
           END DO
!------------------------------------------------------------------------------
!          Coefficients for the nodal temperatures
!------------------------------------------------------------------------------
           LSTIFF( (p-1)*(DIM+2)+DIM+1, (q-1)*(DIM+2)+DIM+1 ) = &
               LSTIFF( (p-1)*(DIM+2)+DIM+1, (q-1)*(DIM+2)+DIM+1 ) + s*A
!------------------------------------------------------------------------------
!          Coefficients for the nodal pressures
!------------------------------------------------------------------------------

           LSTIFF( (p-1)*(DIM+2)+DIM+1, (q-1)*(DIM+2)+DIM+2) =  &
               LSTIFF( (p-1)*(DIM+2)+DIM+1, (q-1)*(DIM+2)+DIM+2) + &
                s * 1.0d0/DCMPLX( 1.0d0, AngularFrequency/P0*la ) * &
                Basis(q) * Basis(p)

           LSTIFF( p*(DIM+2), q*(DIM+2) ) = &
                LSTIFF( p*(DIM+2), q*(DIM+2) ) - &
                s * rho0*AngularFrequency/DCMPLX( P0/AngularFrequency, la ) * &
                Basis(q) * Basis(p)

         END DO
         LFORCE( (p-1)*(DIM+2)+DIM+1 ) = &
             LFORCE( (p-1)*(DIM+2)+DIM+1 ) + s * Basis(p) * DCMPLX( -f2,f1 )
       END DO

       IF ( Bubbles ) THEN
         DO p=1,n
           DO q=n+1,NBasis
             DO i=1,DIM
!------------------------------------------------------------------------------
!          Coefficients for the nodal velocities
!------------------------------------------------------------------------------
               LSTIFF( p*(DIM+2), (q-1)*DIM+2*n+i) = &
                   LSTIFF( p*(DIM+2), (q-1)*DIM+2*n+i) + &
                   DCMPLX( 0.0d0, 1.0d0 ) * dBasisdx(q,i) * Basis(p) * s

               IF (i==1) THEN
                 LSTIFF( p*(DIM+2), (q-1)*DIM+2*n+i) = &
                     LSTIFF( p*(DIM+2), (q-1)*DIM+2*n+i) + &
                     DCMPLX( 0.0d0, 1.0d0 ) * 1/r * Basis(q) * Basis(p) * s  
               END IF
             END DO
           END DO
         END DO
       END IF

!------------------------------------------------------------------------------
!      The following is the contribution from the NS-equation, i.e. the 
!      part arising from the loop over the test functions for velocity 
!------------------------------------------------------------------------------

       DO i=1,DIM
         DO p=1,n
           DO q=1,n
!------------------------------------------------------------------------------
!            Coefficients for the nodal temperatures...               
!------------------------------------------------------------------------------
             LSTIFF( (p-1)*(DIM+2)+i, (q-1)*(DIM+2)+DIM+1 ) = &
                 LSTIFF( (p-1)*(DIM+2)+i, (q-1)*(DIM+2)+DIM+1 ) + &
                 DCMPLX( 0.0d0, 1.0d0 ) * dBasisdx(p,i) * Basis(q) * s
             IF (i==1) THEN
               LSTIFF( (p-1)*(DIM+2)+i, (q-1)*(DIM+2)+DIM+1 ) = &
                   LSTIFF( (p-1)*(DIM+2)+i, (q-1)*(DIM+2)+DIM+1 ) + &
                   DCMPLX( 0.0d0, 1.0d0 ) * 1/r * Basis(p) * Basis(q) * s
             END IF
!------------------------------------------------------------------------------
!            Coefficients for the nodal pressures...               
!------------------------------------------------------------------------------
             LSTIFF( (p-1)*(DIM+2)+i, q*(DIM+2) ) = &
                 LSTIFF( (p-1)*(DIM+2)+i, q*(DIM+2) ) + &
                 DCMPLX( 0.0d0, 1.0d0 ) * dBasisdx(p,i) * Basis(q) * s
             IF (i==1) THEN
               LSTIFF( (p-1)*(DIM+2)+i, q*(DIM+2) ) = &
                   LSTIFF( (p-1)*(DIM+2)+i, q*(DIM+2) ) + &
                   DCMPLX( 0.0d0, 1.0d0 ) * 1/r * Basis(p) * Basis(q) * s  
             END IF
!------------------------------------------------------------------------------
!            Coefficients for the nodal velocities...             
!------------------------------------------------------------------------------
             LSTIFF( (p-1)*(DIM+2)+i, (q-1)*(DIM+2)+i) = &
                 LSTIFF( (p-1)*(DIM+2)+i,(q-1)*(DIM+2)+i) + &
                 DCMPLX( 1.0d0, 0.0d0 ) * &
                 Basis(q) * Basis(p) * s
                
             DO j=1,DIM
!------------------------------------------------------------------------------
!              grad(v)grav(w)-type terms
!------------------------------------------------------------------------------
               LSTIFF((p-1)*(DIM+2)+i, (q-1)*(DIM+2)+i) = &
                   LSTIFF((p-1)*(DIM+2)+i, (q-1)*(DIM+2)+i) + &
                   DCMPLX( 0.0d0, -mu/(AngularFrequency*rho0) ) * &
                   dBasisdx(q,j) * dBasisdx(p,j) * s
               LSTIFF((p-1)*(DIM+2)+i, (q-1)*(DIM+2)+j) = &
                   LSTIFF((p-1)*(DIM+2)+i, (q-1)*(DIM+2)+j) + &
                   DCMPLX( 0.0d0, -mu/(AngularFrequency*rho0) ) * &
                   dBasisdx(q,i) * dBasisdx(p,j) * s
             END DO

             IF (i==1) THEN
               LSTIFF((p-1)*(DIM+2)+i, (q-1)*(DIM+2)+i) = &
                   LSTIFF((p-1)*(DIM+2)+i, (q-1)*(DIM+2)+i) + &
                   DCMPLX( 0.0d0, -2*mu/(AngularFrequency*rho0) ) * 1/r**2 * Basis(q) * Basis(p) * s  
             END IF
           END DO
!------------------------------------------------------------------------------
!          The components of force vector...
!------------------------------------------------------------------------------
           LFORCE( (p-1)*(DIM+2)+i) = LFORCE( (p-1)*(DIM+2)+i ) - &
               s * Basis(p) * DCMPLX( -L((i-1)*2+2), L((i-1)*2+1)  )
         END DO
       END DO

       IF ( Bubbles ) THEN
         DO i=1,DIM
           DO p=1,n
             DO q=n+1,NBasis
!------------------------------------------------------------------------------
!            coefficients for the nodal velocities             
!------------------------------------------------------------------------------
               LSTIFF( (p-1)*(DIM+2)+i, (q-1)*DIM+2*n+i) = &
                   LSTIFF( (p-1)*(DIM+2)+i,(q-1)*DIM+2*n+i) + &
                   DCMPLX( 1.0d0, 0.0d0 ) * &
                   Basis(q) * Basis(p) * s
                
               DO j=1,DIM
!------------------------------------------------------------------------------
!                grad(v)grav(w)-type terms
!------------------------------------------------------------------------------
                 LSTIFF((p-1)*(DIM+2)+i, (q-1)*DIM+2*n+i) = &
                     LSTIFF((p-1)*(DIM+2)+i, (q-1)*DIM+2*n+i) + &
                     DCMPLX( 0.0d0, -mu/(AngularFrequency*rho0) ) * &
                     dBasisdx(q,j) * dBasisdx(p,j) * s
                 LSTIFF((p-1)*(DIM+2)+i, (q-1)*DIM+2*n+j) = &
                     LSTIFF((p-1)*(DIM+2)+i, (q-1)*DIM+2*n+j) + &
                     DCMPLX( 0.0d0, -mu/(AngularFrequency*rho0) ) * &
                     dBasisdx(q,i) * dBasisdx(p,j) * s
               END DO

               IF (i==1) THEN
                 LSTIFF((p-1)*(DIM+2)+i, (q-1)*DIM+2*n+i) = &
                     LSTIFF((p-1)*(DIM+2)+i, (q-1)*DIM+2*n+i) + &
                     DCMPLX( 0.0d0, -2*mu/(AngularFrequency*rho0) ) * 1/r**2 * Basis(q) * Basis(p) * s 
               END IF
             END DO
           END DO
         END DO

         DO i=1,DIM
           DO p=n+1,NBasis
             DO q=1,n
!------------------------------------------------------------------------------
!              Coefficients for the nodal temperatures               
!------------------------------------------------------------------------------
               LSTIFF( (p-1)*DIM+2*n+i, (q-1)*(DIM+2)+DIM+1 ) = &
                   LSTIFF( (p-1)*DIM+2*n+i, (q-1)*(DIM+2)+DIM+1 ) + &
                   DCMPLX( 0.0d0, 1.0d0) * dBasisdx(p,i) * Basis(q) * s
               IF (i==1) THEN
                 LSTIFF( (p-1)*DIM+2*n+i, (q-1)*(DIM+2)+DIM+1 ) = &
                     LSTIFF( (p-1)*DIM+2*n+i, (q-1)*(DIM+2)+DIM+1 ) + &
                     DCMPLX( 0.0d0, 1.0d0) * 1/r * Basis(p) * Basis(q) * s
               END IF
!------------------------------------------------------------------------------
!            Coefficients for the nodal pressures...               
!------------------------------------------------------------------------------
               LSTIFF( (p-1)*DIM+2*n+i, q*(DIM+2) ) = &
                   LSTIFF( (p-1)*DIM+2*n+i, q*(DIM+2) ) + &
                   DCMPLX( 0.0d0, 1.0d0 ) * dBasisdx(p,i) * Basis(q) * s
               IF (i==1) THEN
                 LSTIFF( (p-1)*DIM+2*n+i, q*(DIM+2) ) = &
                     LSTIFF( (p-1)*DIM+2*n+i, q*(DIM+2) ) + &
                     DCMPLX( 0.0d0, 1.0d0 ) * 1/r * Basis(p) * Basis(q) * s  
               END IF
!------------------------------------------------------------------------------
!              coefficients for the nodal velocities 
!------------------------------------------------------------------------------
               LSTIFF( (p-1)*DIM+2*n+i, (q-1)*(DIM+2)+i) = &
                   LSTIFF( (p-1)*DIM+2*n+i,(q-1)*(DIM+2)+i) + &
                   DCMPLX( 1.0d0, 0.0d0 ) * &
                   Basis(q) * Basis(p) * s
                
               DO j=1,DIM
!------------------------------------------------------------------------------
!                grad(v)grav(w)-type terms
!------------------------------------------------------------------------------
                 LSTIFF( (p-1)*DIM+2*n+i, (q-1)*(DIM+2)+i) = &
                     LSTIFF( (p-1)*DIM+2*n+i, (q-1)*(DIM+2)+i) + &
                     DCMPLX( 0.0d0, -mu/(AngularFrequency*rho0)) * dBasisdx(q,j) * dBasisdx(p,j) * s
                 LSTIFF( (p-1)*DIM+2*n+i, (q-1)*(DIM+2)+j) = &
                     LSTIFF( (p-1)*DIM+2*n+i, (q-1)*(DIM+2)+j) + &
                     DCMPLX( 0.0d0, -mu/(AngularFrequency*rho0)) * dBasisdx(q,i) * dBasisdx(p,j) * s
               END DO

               IF (i==1) THEN
                 LSTIFF( (p-1)*DIM+2*n+i, (q-1)*(DIM+2)+i) = &
                     LSTIFF( (p-1)*DIM+2*n+i, (q-1)*(DIM+2)+i) + &
                     DCMPLX( 0.0d0, -2*mu/(AngularFrequency*rho0)) * 1/r**2 * Basis(q) * Basis(p) * s
               END IF
             END DO
!------------------------------------------------------------------------------
!            The components of force vector...
!------------------------------------------------------------------------------
             LFORCE( (p-1)*DIM+2*n+i ) = LFORCE( (p-1)*DIM+2*n+i ) - &
                 s * Basis(p) * DCMPLX( -L((i-1)*2+2), L((i-1)*2+1) )
           END DO
         END DO

         DO i=1,DIM
           DO p=n+1,NBasis
             DO q=n+1,NBasis
!------------------------------------------------------------------------------
!              coefficients for the nodal velocities 
!------------------------------------------------------------------------------
               LSTIFF( (p-1)*DIM+2*n+i, (q-1)*DIM+2*n+i) = &
                   LSTIFF( (p-1)*DIM+2*n+i,(q-1)*DIM+2*n+i) + &
                   DCMPLX( 1.0d0, 0.0d0 ) * &
                   Basis(q) * Basis(p) * s
                
               DO j=1,DIM
!------------------------------------------------------------------------------
!                grad(v)grav(w)-type terms
!------------------------------------------------------------------------------
                 LSTIFF( (p-1)*DIM+2*n+i, (q-1)*DIM+2*n+i) = &
                     LSTIFF( (p-1)*DIM+2*n+i, (q-1)*DIM+2*n+i) + &
                     DCMPLX( 0.0d0, -mu/(AngularFrequency*rho0) ) * dBasisdx(q,j) * dBasisdx(p,j) * s
                 LSTIFF( (p-1)*DIM+2*n+i, (q-1)*DIM+2*n+j) = &
                     LSTIFF( (p-1)*DIM+2*n+i, (q-1)*DIM+2*n+j) + &
                     DCMPLX( 0.0d0, -mu/(AngularFrequency*rho0) ) * dBasisdx(q,i) * dBasisdx(p,j) * s
               END DO
               IF (i==1) THEN
                 LSTIFF( (p-1)*DIM+2*n+i, (q-1)*DIM+2*n+i) = &
                     LSTIFF( (p-1)*DIM+2*n+i, (q-1)*DIM+2*n+i) + &
                     DCMPLX( 0.0d0, -2*mu/(AngularFrequency*rho0)) * 1/r**2 * Basis(q) * Basis(p) * s
               END IF
            END DO
           END DO
         END DO         
!------------------------------------------------------------------------------
       END IF   ! IF (Bubbles)...
!------------------------------------------------------------------------------
    END DO      ! Loop over integration points
!------------------------------------------------------------------------------

    IF ( Bubbles ) THEN
      CALL LCondensate( n, dim, LSTIFF, LFORCE )
    END IF

    DO p=1,n
      DO i=1,DIM+2
        Force( 2*(DIM+2)*(p-1)+2*i-1 ) = REAL(LFORCE( (p-1)*(DIM+2)+i ))
        Force( 2*(DIM+2)*(p-1)+2*i ) = AIMAG(LFORCE( (p-1)*(DIM+2)+i ))
        DO q=1,n
          DO j=1,DIM+2
            StiffMatrix( 2*(DIM+2)*(p-1)+2*i-1, 2*(DIM+2)*(q-1)+2*j-1 ) =  &
                REAL( LSTIFF((DIM+2)*(p-1)+i,(DIM+2)*(q-1)+j) )
            StiffMatrix( 2*(DIM+2)*(p-1)+2*i-1, 2*(DIM+2)*(q-1)+2*j ) =  &
                -AIMAG( LSTIFF((DIM+2)*(p-1)+i,(DIM+2)*(q-1)+j) )
            StiffMatrix( 2*(DIM+2)*(p-1)+2*i, 2*(DIM+2)*(q-1)+2*j-1 ) =  &
                AIMAG( LSTIFF((DIM+2)*(p-1)+i,(DIM+2)*(q-1)+j) )
            StiffMatrix( 2*(DIM+2)*(p-1)+2*i, 2*(DIM+2)*(q-1)+2*j ) =  &
                REAL( LSTIFF((DIM+2)*(p-1)+i,(DIM+2)*(q-1)+j) )
          END DO
        END DO
      END DO
    END DO

   
!------------------------------------------------------------------------------
  END SUBROUTINE LocalMatrix2
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE LocalMatrixBoundary2(  StiffMatrix, Force, AngularFrequency, &
      SpecificHeat, HeatRatio, Density, Pressure,               &
      Temperature, Conductivity, Impedance, Load, &
      Element, n, Nodes, Dofs )
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: StiffMatrix(:,:), Force(:), AngularFrequency, & 
        SpecificHeat(:), HeatRatio(:), Density(:), Pressure(:),    &
        Temperature(:), Conductivity(:), Impedance(:,:), &
        Load(:,:)
    INTEGER :: n, Dofs
    TYPE(Nodes_t) :: Nodes
    TYPE(Element_t), POINTER :: Element
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: SqrtElementMetric, U, V, W, S, Impedance1, Impedance2, &
        Impedance3, Impedance4, CV, gamma, rho0, P0, T0, kappa, K1, L(6),   & 
        Basis(n), dBasisdx(n,3), ddBasisddx(n,3,3), X, Y, Z, Normal(3), r
    COMPLEX(KIND=dp) :: LSTIFF(n*(Dofs-2),n*(Dofs-2)), LFORCE(n*(Dofs-2))
    LOGICAL :: Stat
    INTEGER :: i, j, p, q, t, DIM
    TYPE(GaussIntegrationPoints_t) :: IntegStuff
!------------------------------------------------------------------------------
    DIM = CoordinateSystemDimension()
    LSTIFF = DCMPLX(0.0d0,0.0d0)
    LFORCE = DCMPLX(0.0d0,0.0d0)
!------------------------------------------------------------------------------
!   Numerical integration
!------------------------------------------------------------------------------
    IntegStuff = GaussPoints( Element )
!------------------------------------------------------------------------------
    DO t=1, IntegStuff % n
      U = IntegStuff % u(t)
      V = IntegStuff % v(t)
      W = IntegStuff % w(t)
      S = IntegStuff % s(t)
!------------------------------------------------------------------------------
!     Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
      stat = ElementInfo( Element, Nodes, U, V, W, SqrtElementMetric, &
          Basis, dBasisdx, ddBasisddx, .FALSE., .FALSE. )
      r = SUM( Basis * Nodes % x(1:n) )
      s = r * s * SqrtElementMetric
!------------------------------------------------------------------------------
!     Problem parameters at the integration point
!------------------------------------------------------------------------------
      CV = SUM( SpecificHeat(1:n) * Basis(1:n) )       
      gamma = SUM( HeatRatio(1:n) * Basis(1:n) )
      rho0 = SUM( Density(1:n) * Basis(1:n) )
      P0 = SUM( Pressure(1:n) * Basis(1:n) )
      T0 = SUM( Temperature(1:n) * Basis(1:n) )
      kappa = SUM( Conductivity(1:n) * Basis(1:n) )
!      K1 = kappa*AngularFrequency/(CV*(gamma-1.0d0)*P0)
      K1 = kappa/(rho0*AngularFrequency*(gamma-1.0d0)*CV)

      Normal = Normalvector(Element, Nodes, U, V, .TRUE.)

      Impedance1 = 1.0d0/(AngularFrequency*rho0) * SUM( Impedance(1,1:n) * Basis(1:n) )
      Impedance2 = 1.0d0/(AngularFrequency*rho0) * SUM( Impedance(2,1:n) * Basis(1:n) ) 
      Impedance3 = SUM( Impedance(3,1:n) * Basis(1:n) ) 
      Impedance4 = SUM( Impedance(4,1:n) * Basis(1:n) ) 

      DO i=1,2*DIM
        L(i) = 1.0d0/(AngularFrequency*rho0) * SUM( Load(i,1:n) * Basis(1:n) )
      END DO

      DO p=1,n
        DO i=1,dim
          DO q=1,n
            DO j=1,dim
              LSTIFF( (p-1)*(DIM+2)+i, (q-1)*(DIM+2)+j) = &
                  LSTIFF( (p-1)*(DIM+2)+i, (q-1)*(DIM+2)+j) + &
                  DCMPLX(-Impedance2, Impedance1) * &
                  Basis(q) * Normal(j) * Basis(p) * Normal(i) * s
            END DO
          END DO
          LFORCE( (p-1)*(DIM+2)+i) = LFORCE( (p-1)*(DIM+2)+i ) - &
              s * Basis(p) * DCMPLX( -L((i-1)*2+2), L((i-1)*2+1)  )
        END DO
      END DO

      DO p=1,n
        DO q=1,n
          LSTIFF( (p-1)*(DIM+2)+DIM+1, (q-1)*(DIM+2)+DIM+1) = &
              LSTIFF( (p-1)*(DIM+2)+DIM+1, (q-1)*(DIM+2)+DIM+1) - &
              DCMPLX(0.0d0, K1) * DCMPLX(Impedance3, Impedance4) * &
              Basis(q) * Basis(p) * s
        END DO
      END DO

    END DO   ! Loop over integration points

    DO p=1,n
      DO i=1,DIM+2
        Force( 2*(DIM+2)*(p-1)+2*i-1 ) = REAL(LFORCE( (p-1)*(DIM+2)+i ))
        Force( 2*(DIM+2)*(p-1)+2*i ) = AIMAG(LFORCE( (p-1)*(DIM+2)+i ))
        DO q=1,n
          DO j=1,DIM+2
            StiffMatrix( 2*(DIM+2)*(p-1)+2*i-1, 2*(DIM+2)*(q-1)+2*j-1 ) =  &
                REAL( LSTIFF((DIM+2)*(p-1)+i,(DIM+2)*(q-1)+j) )
            StiffMatrix( 2*(DIM+2)*(p-1)+2*i-1, 2*(DIM+2)*(q-1)+2*j ) =  &
                -AIMAG( LSTIFF((DIM+2)*(p-1)+i,(DIM+2)*(q-1)+j) )
            StiffMatrix( 2*(DIM+2)*(p-1)+2*i, 2*(DIM+2)*(q-1)+2*j-1 ) =  &
                AIMAG( LSTIFF((DIM+2)*(p-1)+i,(DIM+2)*(q-1)+j) )
            StiffMatrix( 2*(DIM+2)*(p-1)+2*i, 2*(DIM+2)*(q-1)+2*j ) =  &
                REAL( LSTIFF((DIM+2)*(p-1)+i,(DIM+2)*(q-1)+j) )
          END DO
        END DO
      END DO
    END DO
!------------------------------------------------------------------------------
  END SUBROUTINE LocalMatrixBoundary2
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE SlipMatrix(  StiffMatrix, Force, SpecificHeat, HeatRatio, &
      Density, Conductivity, Pressure, Temperature, &
      AngularFrequency, WallTemperature, &
      WallVelocity, SlipCoefficient1, SlipCoefficient2, &
      Element, n, Nodes, Dofs )
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: StiffMatrix(:,:), Force(:), & 
        SpecificHeat(:), HeatRatio(:), Density(:), Conductivity(:), &
        Pressure(:), Temperature(:), AngularFrequency, WallTemperature(:), &
        WallVelocity(:,:), SlipCoefficient1, SlipCoefficient2
    INTEGER :: n, Dofs
    TYPE(Nodes_t) :: Nodes
    TYPE(Element_t), POINTER :: Element
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: SqrtElementMetric, U, V, W, S, Impedance1, Impedance2, &
        Impedance3, Impedance4, CV, gamma, rho0, P0, T0, ReV0(3), ImV0(3), &
        WallT0, kappa, K1, L(6),C1, C2, & 
        Basis(n), dBasisdx(n,3), ddBasisddx(n,3,3), X, Y, Z, Normal(3), r,  &
        Tangent1(3), Tangent2(3)
    COMPLEX(KIND=dp) :: LSTIFF(n*(Dofs-2),n*(Dofs-2)), LFORCE(n*(Dofs-2))
    LOGICAL :: Stat
    INTEGER :: i, j, p, q, t, DIM
    TYPE(GaussIntegrationPoints_t) :: IntegStuff
!------------------------------------------------------------------------------
    DIM = CoordinateSystemDimension()
    CoordSys = CurrentCoordinateSystem()
    LSTIFF = DCMPLX(0.0d0,0.0d0)
    LFORCE = DCMPLX(0.0d0,0.0d0)
!------------------------------------------------------------------------------
!   Numerical integration
!------------------------------------------------------------------------------
    IntegStuff = GaussPoints( Element )
!------------------------------------------------------------------------------
    DO t=1, IntegStuff % n
      U = IntegStuff % u(t)
      V = IntegStuff % v(t)
      W = IntegStuff % w(t)
      S = IntegStuff % s(t)
!------------------------------------------------------------------------------
!     Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
      stat = ElementInfo( Element, Nodes, U, V, W, SqrtElementMetric, &
          Basis, dBasisdx, ddBasisddx, .FALSE., .FALSE. )
      IF (CoordSys == Cartesian) THEN
        s = s * SqrtElementMetric
      ELSE
        r = SUM( Basis * Nodes % x(1:n) )
        s = r * s * SqrtElementMetric
      END IF
!------------------------------------------------------------------------------
!     Problem parameters at the integration point
!------------------------------------------------------------------------------
      CV = SUM( SpecificHeat(1:n) * Basis(1:n) )       
      gamma = SUM( HeatRatio(1:n) * Basis(1:n) )
      rho0 = SUM( Density(1:n) * Basis(1:n) )
      kappa = SUM( Conductivity(1:n) * Basis(1:n) )
      P0 =  SUM( Pressure(1:n) * Basis(1:n) )
      T0 =  SUM( Temperature(1:n) * Basis(1:n) )
      WallT0 = SUM( WallTemperature(1:n) * Basis(1:n) )
      
      DO i=1,3
        ReV0(i) = SUM( WallVelocity((i-1)*2+1,1:n) * Basis(1:n) )
        ImV0(i) = SUM( WallVelocity((i-1)*2+2,1:n) * Basis(1:n) )
      END DO

      K1 = kappa/(rho0*AngularFrequency*(gamma-1.0d0)*CV)

      C1 = -SlipCoefficient1/(2.0d0-SlipCoefficient1) * &
          rho0*SQRT(2.0d0*(gamma-1.0d0)*CV* &
          (T0+WallT0)/PI)

      C2 = 1/kappa*SlipCoefficient2/(2.0d0-SlipCoefficient2) * &
          (gamma+1.0d0)/(2.0d0*(gamma-1.0d0))*rho0*(gamma-1.0d0)*CV * &
          SQRT(2.0d0*(gamma-1.0d0)*CV*(T0+WallT0)/PI)

      Normal = Normalvector(Element, Nodes, U, V, .TRUE.)

      CALL TangentDirections(Normal, Tangent1, Tangent2)

      DO p=1,n
        DO i=1,dim
          DO j=1,dim
            DO q=1,n
              LSTIFF( (p-1)*(DIM+2)+i, (q-1)*(DIM+2)+j) = &
                  LSTIFF( (p-1)*(DIM+2)+i, (q-1)*(DIM+2)+j) + &
                  DCMPLX(0.0d0, C1) * 1.0d0/(AngularFrequency*rho0) * &
                  Basis(q) * Tangent1(j) * Basis(p) * Tangent1(i) * s
            END DO

            LFORCE( (p-1)*(DIM+2)+i) = LFORCE( (p-1)*(DIM+2)+i) + &
                DCMPLX(0.0d0, C1) * 1.0d0/(AngularFrequency*rho0) * &
                DCMPLX(ReV0(j),ImV0(j)) * &
                Tangent1(j) * Basis(p) * Tangent1(i) * s 
          END DO
        END DO
      END DO

      IF (dim > 2) THEN
        DO p=1,n
          DO i=1,dim
            DO j=1,dim
              DO q=1,n
                LSTIFF( (p-1)*(DIM+2)+i, (q-1)*(DIM+2)+j) = &
                    LSTIFF( (p-1)*(DIM+2)+i, (q-1)*(DIM+2)+j) + &
                    DCMPLX(0.0d0, C1) * 1.0d0/(AngularFrequency*rho0) * &
                    Basis(q) * Tangent2(j) * Basis(p) * Tangent2(i) * s
              END DO

              LFORCE( (p-1)*(DIM+2)+i) = LFORCE( (p-1)*(DIM+2)+i) + &
                  DCMPLX(0.0d0, C1) * 1.0d0/(AngularFrequency*rho0) * &
                  DCMPLX(ReV0(j),ImV0(j)) * &
                  Tangent2(j) * Basis(p) * Tangent2(i) * s 
            END DO
          END DO
        END DO
      END IF

      DO p=1,n
        DO q=1,n
          LSTIFF( (p-1)*(DIM+2)+DIM+1, (q-1)*(DIM+2)+DIM+1) = &
              LSTIFF( (p-1)*(DIM+2)+DIM+1, (q-1)*(DIM+2)+DIM+1) + &
              DCMPLX(0.0d0, K1) * DCMPLX(C2, 0.0d0) * &
              Basis(q) * Basis(p) * s
        END DO
        LFORCE( (p-1)*(DIM+2)+DIM+1) = LFORCE( (p-1)*(DIM+2)+DIM+1) + &
            DCMPLX(0.0d0, K1) * DCMPLX(C2, 0.0d0) * &
            WallT0 * Basis(p) * s
      END DO

    END DO  ! Loop over integration points

    DO p=1,n
      DO i=1,DIM+2
        Force( 2*(DIM+2)*(p-1)+2*i-1 ) = REAL(LFORCE( (p-1)*(DIM+2)+i ))
        Force( 2*(DIM+2)*(p-1)+2*i ) = AIMAG(LFORCE( (p-1)*(DIM+2)+i ))
        DO q=1,n
          DO j=1,DIM+2
            StiffMatrix( 2*(DIM+2)*(p-1)+2*i-1, 2*(DIM+2)*(q-1)+2*j-1 ) =  &
                REAL( LSTIFF((DIM+2)*(p-1)+i,(DIM+2)*(q-1)+j) )
            StiffMatrix( 2*(DIM+2)*(p-1)+2*i-1, 2*(DIM+2)*(q-1)+2*j ) =  &
                -AIMAG( LSTIFF((DIM+2)*(p-1)+i,(DIM+2)*(q-1)+j) )
            StiffMatrix( 2*(DIM+2)*(p-1)+2*i, 2*(DIM+2)*(q-1)+2*j-1 ) =  &
                AIMAG( LSTIFF((DIM+2)*(p-1)+i,(DIM+2)*(q-1)+j) )
            StiffMatrix( 2*(DIM+2)*(p-1)+2*i, 2*(DIM+2)*(q-1)+2*j ) =  &
                REAL( LSTIFF((DIM+2)*(p-1)+i,(DIM+2)*(q-1)+j) )
          END DO
        END DO
      END DO
    END DO
!------------------------------------------------------------------------------
  END SUBROUTINE SlipMatrix
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
  SUBROUTINE ComputeAcousticImpedance( AcousticI, Bndries, AcImpedances )
!------------------------------------------------------------------------------

    INTEGER :: AcousticI, Bndries(:)
    REAL(KIND=dp) :: AcImpedances(:,:)
!------------------------------------------------------------------------------

    TYPE(Element_t), POINTER :: CurrentElement
    TYPE(GaussIntegrationPoints_t) :: IntegStuff
    REAL(KIND=dp), ALLOCATABLE :: PressureData(:,:), VelocityData(:)
    REAL(KIND=dp) :: ElementPresRe, ElementPresIm
    REAL(KIND=dp) :: ElementVeloRe, ElementVeloIm
    REAL(KIND=dp) :: u, v, w, s, xpos, ypos, zpos
    REAL(KIND=dp) :: SqrtMetric, SqrtElementMetric
    REAL(KIND=dp) :: Basis(Model % MaxElementNodes), Metric(3,3), &
         dBasisdx(Model % MaxElementNodes,3), Symb(3,3,3), &
         ddBasisddx(Model % MaxElementNodes,3,3), dSymb(3,3,3,3)
    REAL(KIND=dp) :: Normal(3), VReal(3), VIm(3), Preal, PIm
    REAL(KIND=dp) :: AbsNormalVelo, InPhasePres, OutPhasePres
    INTEGER, POINTER :: NodeIndexes(:)
    INTEGER :: i, j, k, n, t
    LOGICAL :: stat
!------------------------------------------------------------------------------

    ALLOCATE( PressureData( AcousticI, 2 ) )
    PressureData = 0.0d0
    ALLOCATE( VelocityData( 2 ) )
    VelocityData = 0.0d0

    VReal = 0.0d0
    VIm = 0.0d0

    DO t = Model % NumberOfBulkElements +1, &
         Model % NumberOfBulkElements + Model % NumberOfBoundaryElements

       CurrentElement => Solver % Mesh % Elements(t)
       n = CurrentElement % TYPE % NumberOfNodes
       NodeIndexes => CurrentElement % NodeIndexes

       DO i = 1, AcousticI
          IF ( CurrentElement % BoundaryInfo % Constraint == &
               Model % BCs(Bndries(i)) % Tag ) THEN

             ElementPresRe = 0.0d0
             ElementPresIm = 0.0d0
             ElementVeloRe = 0.0d0
             ElementVeloIm = 0.0d0

             ElementNodes % x(1:n) = Solver % Mesh % Nodes % x(NodeIndexes)
             ElementNodes % y(1:n) = Solver % Mesh % Nodes % y(NodeIndexes)
             ElementNodes % z(1:n) = Solver % Mesh % Nodes % z(NodeIndexes)
!------------------------------------------------------------------------------
!      Numerical integration
!------------------------------------------------------------------------------

             IntegStuff = GaussPoints( CurrentElement )
             DO j = 1, IntegStuff % n
                u = IntegStuff % u(j)
                v = IntegStuff % v(j)
                w = IntegStuff % w(j)

!------------------------------------------------------------------------------
!      Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
               
                stat = ElementInfo( CurrentElement, ElementNodes, u, v, w, &
                     SqrtElementMetric, Basis, dBasisdx, ddBasisddx, &
                     .FALSE., .FALSE. )

!------------------------------------------------------------------------------
!      Coordinatesystem dependent info
!------------------------------------------------------------------------------
                s = 1.0d0
                IF ( CurrentCoordinateSystem() /= Cartesian ) THEN
                   xpos = SUM( ElementNodes % x(1:n) * Basis(1:n) )
                   ypos = SUM( ElementNodes % y(1:n) * Basis(1:n) )
                   zpos = SUM( ElementNodes % z(1:n) * Basis(1:n) )
                   s = 2*PI
                END IF
         
                CALL CoordinateSystemInfo( Metric, SqrtMetric, Symb, dSymb, &
                     xpos, ypos, zpos)
 
                s = s * SqrtMetric * SqrtElementMetric * IntegStuff % s(j)
        
!------------------------------------------------------------------------------

                PReal = SUM( Flow( DOFs * ( FlowPerm(NodeIndexes) ) &
                     - 1 ) * Basis(1:n) )
                PIm = SUM( Flow( DOFs * ( FlowPerm(NodeIndexes) ) ) &
                     * Basis(1:n) )


                ElementPresRe = ElementPresRe + s * PReal
                ElementPresIm = ElementPresIm + s * PIm

!------------------------------------------------------------------------------
!   The normal velocity is needed only for the transmitting boundary i = 1
!------------------------------------------------------------------------------

                IF ( i == 1 ) THEN
                   Normal = Normalvector( CurrentElement, ElementNodes, &
                        u, v, .TRUE. )
                   Normal = -Normal   ! use inward normal vector

                   DO k = 1, VelocityComponents
                      VReal(k) = SUM( Flow( DOFs * ( FlowPerm(NodeIndexes)-1 ) &
                           + 2 * k - 1 ) * Basis(1:n) )
                      VIm(k) = SUM( Flow( DOFs * ( FlowPerm(NodeIndexes)-1 ) &
                           + 2 * k ) * Basis(1:n) )
                   END DO

                   ElementVeloRe = ElementVeloRe + s * &
                        SUM( VReal(1:3) * Normal(1:3) )
                   ElementVeloIm = ElementVeloIm + s * &
                        SUM( VIm(1:3) * Normal(1:3) )
                END IF

!------------------------------------------------------------------------------

             END DO

          PressureData(i,1) = PressureData(i,1) + ElementPresRe
          PressureData(i,2) = PressureData(i,2) + ElementPresIm
          VelocityData(1) = VelocityData(1) + ElementVeloRe
          VelocityData(2) = VelocityData(2) + ElementVeloIm

          END IF

       END DO
    END DO

!------------------------------------------------------------------------------

    DO i = 1, AcousticI
       AcImpedances(i,1) = ( PressureData(i,1) * VelocityData(1) + &
            PressureData(i,2) * VelocityData(2) ) / &
            SUM( VelocityData**2 )
       AcImpedances(i,2) = ( PressureData(i,2) * VelocityData(1) - &
            PressureData(i,1) * VelocityData(2) ) / &
            SUM( VelocityData**2 )
    END DO

    DEALLOCATE( PressureData )
    DEALLOCATE( VelocityData )

!------------------------------------------------------------------------------
  END SUBROUTINE ComputeAcousticImpedance
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
END SUBROUTINE AcousticsSolver
!------------------------------------------------------------------------------
