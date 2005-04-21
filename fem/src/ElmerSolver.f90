!/*****************************************************************************/
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
! *  ELMER/FEM Solver main program
! *
! ******************************************************************************
! *
! *                     Author:       Juha Ruokolainen
! *
! *                    Address: Center for Scientific Computing
! *                                Tietotie 6, P.O. BOX 405
! *                                  02
! *                                  Tel. +358 0 457 2723
! *                                Telefax: +358 0 457 2302
! *                              EMail: Juha.Ruokolainen@csc.fi
! *
! *                       Date: 02 Jun 1997
! *
! *                Modified by: jpr
! *
! *       Date of modification: 14 Oct 1998
! *
! *****************************************************************************/



!------------------------------------------------------------------------------
   SUBROUTINE ElmerSolver
DLLEXPORT ElmerSolver
!------------------------------------------------------------------------------

     USE MainUtils

!------------------------------------------------------------------------------
     IMPLICIT NONE
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------

     INTEGER :: i,j,k,n,l,t,k1,k2,iter,Ndeg,Time,istat,nproc

     REAL(KIND=dp) :: s,dt,dtfunc,Work(MAX_NODES)
     REAL(KIND=dp), TARGET :: SimulationTime(1)
     REAL(KIND=dP), POINTER :: WorkA(:,:,:) => NULL()

     TYPE(Element_t),POINTER :: CurrentElement
     REAL(KIND=dp), POINTER ::  TimeVariable(:)

     LOGICAL :: GotIt,TransientSimulation,LastSaved

     INTEGER :: TimeIntervals,interval,timestep, &
       TotalTimesteps,SavedSteps,CoupledMaxIter,CoupledMinIter

     REAL(KIND=dp), POINTER :: TimestepSizes(:,:)
     INTEGER, POINTER :: Timesteps(:),OutputIntervals(:),OutputMask(:),ActiveSolvers(:)

     INTEGER(KIND=AddrInt) :: ControlProcedure

     LOGICAL :: KEModelSolved = .FALSE., SteadyStateReached = .FALSE., InitDirichlet

     TYPE(ElementType_t),POINTER :: elmt

     TYPE(ParEnv_t), POINTER :: ParallelEnv

     CHARACTER(LEN=MAX_NAME_LEN) :: ModelName, eq, ExecCommand
     CHARACTER(LEN=MAX_NAME_LEN) :: OutputFile, PostFile, RestartFile, &
                OutputName,PostName, When

     TYPE(Mesh_t), POINTER :: Mesh
     TYPE(Variable_t), POINTER :: Var
     TYPE(Solver_t), POINTER :: Solver

     REAL(KIND=dp) :: RealTime,tt

     REAL(KIND=dp) :: CumTime, ddt, MaxErr, AdaptiveLimit, &
           AdaptiveMinTimestep, AdaptiveMaxTimestep
     INTEGER :: SmallestCount, AdaptiveKeepSmallest, StepControl=-1
     LOGICAL :: AdaptiveTime = .TRUE., FirstLoad = .TRUE.
     REAL(KIND=dp), POINTER :: xx(:,:), xxnrm(:), yynrm(:), PrevXX(:,:,:)

     INTEGER :: iargc

     !
     ! If parallel execution requested, initialize parallel environment:
     !------------------------------------------------------------------
     ParallelEnv => ParCommInit()
     OutputPE = ParEnv % MyPE

     !
     ! Print banner to output:
     ! -----------------------
     CALL Info( 'MAIN', ' ', Level=3 )
     CALL Info( 'MAIN', '===========================================================', Level=3 )
     CALL Info( 'MAIN', ' E L M E R   S O L V E R   S T A R T I N G,  W E L C O M E',  Level=3  )
     CALL Info( 'MAIN', '===========================================================', Level=3 )
     !
     ! Read input file name:
     !----------------------
     IF ( ParEnv % PEs <= 1 ) THEN
       IF ( IARGC() > 0 ) THEN
         CALL getarg( 1,ModelName )
         IF ( IARGC() > 1 ) CALL getarg( 2,eq )
       ELSE
         OPEN( 1, File='ELMERSOLVER_STARTINFO', STATUS='OLD', ERR=10 )
         READ(1,'(a)') ModelName
         CLOSE(1)
       END IF
     ELSE
       OPEN( 1, File='ELMERSOLVER_STARTINFO', STATUS='OLD', ERR=10 )
       READ(1,'(a)') ModelName
       CLOSE(1)
     END IF

!------------------------------------------------------------------------------
!    Read element definition file, and initialize element types
!------------------------------------------------------------------------------
     CALL InitializeElementDescriptions

!------------------------------------------------------------------------------
!    Read Model and mesh from Elmer mesh data base
!------------------------------------------------------------------------------
     DO WHILE( .TRUE. )

       IF ( FirstLoad ) THEN
          CALL Info( 'MAIN', ' ', Level = 3 )
          CALL Info( 'MAIN', ' ', Level = 3 )
          CALL Info( 'MAIN', '-----------------------', Level = 3 )
          CALL Info( 'MAIN', 'Reading Model ... ', Level = 3 )

          OPEN( Unit=InFileUnit, Action='Read', File=ModelName,Status='OLD', ERR=20 )
          CurrentModel => LoadModel( ModelName,.FALSE.,ParEnv % PEs,ParEnv % MyPE )

          CALL Info( 'MAIN', 'Done               ', Level = 3 )
          CALL Info( 'MAIN', '-----------------------', Level = 3 )
       ELSE
          IF ( .NOT. ReloadInputFile( CurrentModel ) ) EXIT
          Mesh => CurrentModel % Meshes
          DO WHILE( ASSOCIATED(Mesh) )
             Mesh % SavesDone = 0
             Mesh => Mesh % Next
          END DO
       END IF

       CALL ListAddLogical( CurrentModel % Simulation, &
             'Initialization Phase', .TRUE. )

!------------------------------------------------------------------------------
!    Check for transient case
!------------------------------------------------------------------------------
     eq = ListGetString( CurrentModel % Simulation, 'Simulation Type', GotIt )
     TransientSimulation = .FALSE.
     IF ( eq == 'transient' ) TransientSimulation= .TRUE.

!------------------------------------------------------------------------------
!      Initialize the log file output system
!------------------------------------------------------------------------------
       MinOutputLevel = ListGetInteger( CurrentModel % Simulation, &
                 'Min Output Level', GotIt )

       MaxOutputLevel = ListGetInteger( CurrentModel % Simulation, &
                 'Max Output Level', GotIt )

       IF ( .NOT. GotIt ) MaxOutputLevel = 32

       OutputMask => ListGetIntegerArray( CurrentModel % Simulation, &
                    'Output Level', GotIt )

       IF ( GotIt ) THEN
          DO i=1,SIZE(OutputMask)
             OutputLevelMask(i-1) = OutputMask(i) /= 0
          END DO
       END IF

       DO i=0,31
          OutputLevelMask(i) = OutputLevelMask(i) .AND. &
           i >= MinOutputLevel .AND. i <= MaxOutputLevel
       END DO

       OutputPrefix = ListGetLogical( CurrentModel % Simulation, &
                      'Output Prefix', GotIt )
       IF ( .NOT. GotIt ) OutputPrefix = .FALSE.

       OutputCaller = ListGetLogical( CurrentModel % Simulation, &
                      'Output Caller', GotIt )
       IF ( .NOT. GotIt ) OutputCaller = .TRUE.
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
!      Figure out what (flow,heat,stress,...) should be computed, and get
!      memory for the dofs
!------------------------------------------------------------------------------
       CALL AddSolvers

!------------------------------------------------------------------------------
!      Time integration and/or steady state steps
!------------------------------------------------------------------------------
       IF ( TransientSimulation ) THEN
         Timesteps => ListGetIntegerArray( CurrentModel % Simulation, &
                       'Timestep Intervals', GotIt )

         IF ( .NOT.GotIt ) THEN
           CALL Fatal( ' ', 'Keyword [Timestep Intervals] MUST be ' //  &
                   'defined for time dependent simulations' )
         END IF 

         TimestepSizes => ListGetConstRealArray( CurrentModel % Simulation, &
                               'Timestep Sizes', GotIt )

         IF ( .NOT.GotIt ) THEN
           CALL Fatal( ' ', 'Keyword [Timestep Sizes] MUST be ' //  &
                   'defined for time dependent simulations' )
           STOP
         END IF 

         TimeIntervals = SIZE(Timesteps)

         CoupledMaxIter = ListGetInteger( CurrentModel % Simulation, &
               'Steady State Max Iterations', GotIt, minv=1 )
         IF ( .NOT. GotIt ) CoupledMaxIter = 1
!------------------------------------------------------------------------------
       ELSE
!------------------------------------------------------------------------------
!        Steady state
!------------------------------------------------------------------------------
         ALLOCATE( Timesteps(1) )

         Timesteps(1) = ListGetInteger( CurrentModel % Simulation, &
               'Steady State Max Iterations', GotIt,minv=1 )
         IF ( .NOT. GotIt ) Timesteps(1)=1
  
         ALLOCATE( TimestepSizes(1,1) )
         TimestepSizes(1,1) = 1.0D0

         TimeIntervals   = 1
         CoupledMaxIter = 1
       END IF

       SimulationTime(1) = 0.0d0
       Time = 0
       dt   = 0.0d0

       CoupledMinIter = ListGetInteger( CurrentModel % Simulation, &
                  'Steady State Min Iterations', GotIt )

!------------------------------------------------------------------------------
!      Add coordinates and simulation time to list of variables so that coordinate dependent
!      parameter computing routines can ask for them...
!------------------------------------------------------------------------------
       IF ( FirstLoad ) CALL AddMeshCoordinatesAndTime

!------------------------------------------------------------------------------
!      Get Output File Options
!------------------------------------------------------------------------------
       OutputFile = ListGetString(CurrentModel % Simulation,'Output File',GotIt)
       IF ( .NOT.GotIt ) OutputFile = 'Result.dat'
       IF ( ParEnv % PEs > 1 ) THEN
         DO i=1,MAX_NAME_LEN
           IF ( OutputFile(i:i) == ' ' ) EXIT
         END DO
         OutputFile(i:i) = '.'
         IF ( ParEnv % MyPE < 10 ) THEN
           WRITE( OutputFile(i+1:), '(i1)' ) ParEnv % MyPE
         ELSE IF ( ParEnv % MyPE < 100 ) THEN
           WRITE( OutputFile(i+1:), '(i2)' ) ParEnv % MyPE
         ELSE
           WRITE( OutputFile(i+1:), '(i3)' ) ParEnv % MyPE
         END IF
       END IF

       OutputIntervals => ListGetIntegerArray( CurrentModel % Simulation, &
                       'Output Intervals', GotIt )
       IF ( .NOT. GotIt ) THEN
         ALLOCATE( OutputIntervals(SIZE(TimeSteps)) )
         OutputIntervals = 1
       END IF

       ! Initial Conditions:
       ! -------------------
       IF ( FirstLoad ) CALL SetInitialConditions

       TotalTimesteps = 0
       DO interval=1,TimeIntervals
         DO timestep = 1,Timesteps(interval)
           LastSaved = .FALSE.
           IF ( MOD(Timestep-1, OutputIntervals(Interval))==0 ) THEN
              LastSaved = .TRUE.
              TotalTimesteps = TotalTimesteps + 1
           END IF
         END DO
       END DO

       DO i=1,CurrentModel % NumberOfSolvers
          Solver => CurrentModel % Solvers(i)
          When = ListGetString( Solver % Values, 'Exec Solver', GotIt )
          IF ( GotIt ) THEN
             IF ( When == 'after simulation' .OR. When == 'after all' ) THEN
                LastSaved = .FALSE.
             END IF
          ELSE
           IF ( Solver % SolverExecWhen == SOLVER_EXEC_AFTER_ALL ) THEN
              LastSaved = .FALSE.
           END IF
          END IF
       END DO

       IF ( .NOT.LastSaved ) TotalTimesteps = TotalTimesteps + 1

       CALL ListAddLogical( CurrentModel % Simulation,  &
            'Initialization Phase', .FALSE. )
!------------------------------------------------------------------------------
!      Here we actually start the simulation ....
!      First go trough timeintervals
!------------------------------------------------------------------------------
       ExecCommand = ListGetString( CurrentModel % Simulation, &
                 'Control Procedure', GotIt )
       IF ( GotIt ) THEN
          ControlProcedure = GetProcAddr( ExecCommand )
          CALL ExecSimulationProc( ControlProcedure, CurrentModel )
       ELSE
          CALL ExecSimulation
       END IF
       FirstLoad = .FALSE.
!------------------------------------------------------------------------------
!    Always save the last step to output
!------------------------------------------------------------------------------
       IF ( .NOT.LastSaved ) CALL SaveCurrent( Timestep )
     END DO
!------------------------------------------------------------------------------
!    THIS IS THE END (...,at last, the end, my friend,...)
!------------------------------------------------------------------------------
     CALL Info( '', '*** Elmer Solver: ALL DONE ***' )
     IF ( ParEnv % PEs > 1 ) CALL ParEnvFinalize()

     RETURN

10   CONTINUE
     CALL Fatal( 'ElmerSolver', 'Unable to find ELMERSOLVER_STARTINFO, can not execute.' )
20   CONTINUE
     CALL Fatal( 'ElmerSolver', 'Unable to find input file [' // &
              TRIM(Modelname) // '], can not execute.' )

   CONTAINS 

!------------------------------------------------------------------------------
    SUBROUTINE AddSolvers
!------------------------------------------------------------------------------
      INTEGER :: i,j,k
      LOGICAL :: InitSolver, Found
!------------------------------------------------------------------------------
      DO i=1,CurrentModel % NumberOfSolvers
        eq = ListGetString( CurrentModel % Solvers(i) % Values,'Equation', Found )
     
       IF ( Found ) THEN
          DO j=1,CurrentModel % NumberOFEquations
             ActiveSolvers => ListGetIntegerArray( CurrentModel % Equations(j) % Values, &
                                'Active Solvers', Found )
             IF ( Found ) THEN
                DO k=1,SIZE(ActiveSolvers)
                   IF ( ActiveSolvers(k) == i ) THEN
                      CALL ListAddLogical( CurrentModel % Equations(j) % Values, TRIM(eq), .TRUE. )
                      EXIT
                   END IF
                END DO
             END IF
          END DO
       END IF
     END DO

     DO i=1,CurrentModel % NumberOfSolvers
        eq = ListGetString( CurrentModel % Solvers(i) % Values,'Equation', Found )
        Solver => CurrentModel % Solvers(i)
        InitSolver = ListGetLogical( Solver % Values, 'Initialize', Found )
        IF ( Found .AND. InitSolver ) THEN
          CALL FreeMatrix( Solver % Matrix )
          CALL ListAddLogical( Solver % Values, 'Initialize', .FALSE. )
        END IF

        IF ( Solver % Procedure == 0 .OR. InitSolver ) THEN
           IF ( .NOT. ASSOCIATED( Solver % Mesh ) ) THEN
              Solver % Mesh => CurrentModel % Meshes
           END IF
           CurrentModel % Solver => Solver
           CALL AddEquation( Solver, eq, TransientSimulation )
        END IF
     END DO
!------------------------------------------------------------------------------
  END SUBROUTINE AddSolvers
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE AddMeshCoordinatesAndTime
!------------------------------------------------------------------------------
     TimeVariable => SimulationTime
     NULLIFY( Solver )

     Mesh => CurrentModel % Meshes 
     DO WHILE( ASSOCIATED( Mesh ) )
       CALL VariableAdd( Mesh % Variables, Mesh,Solver, &
             'Coordinate 1',1,Mesh % Nodes % x )

       CALL VariableAdd(Mesh % Variables,Mesh,Solver, &
             'Coordinate 2',1,Mesh % Nodes % y )

       CALL VariableAdd(Mesh % Variables,Mesh,Solver, &
             'Coordinate 3',1,Mesh % Nodes % z )

       CALL VariableAdd( Mesh % Variables,Mesh,Solver,'Time',1,TimeVariable )
       Mesh => Mesh % Next
     END DO
!------------------------------------------------------------------------------
  END SUBROUTINE AddMeshCoordinatesAndTime
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   SUBROUTINE SetInitialConditions
!------------------------------------------------------------------------------
     DO i=1,CurrentModel % NumberOfBodies
       Mesh => CurrentModel % Meshes
       DO WHILE( ASSOCIATED( Mesh ) )
         CALL SetCurrentMesh( CurrentModel, Mesh )

         DO t=1, Mesh % NumberOfBulkElements+Mesh % NumberOfBoundaryElements
           CurrentElement =>  Mesh % Elements(t)
           CurrentModel % CurrentElement => CurrentElement
           n = CurrentElement % Type % NumberOfNodes

           IF ( CurrentElement % BodyId == i ) THEN
             j = ListGetInteger(CurrentModel % Bodies(i) % Values, &
                'Initial Condition',GotIt, 1, CurrentModel % NumberOfICs )

             IF ( GotIt ) THEN
               Var => Mesh % Variables
               DO WHILE( ASSOCIATED(Var) ) 
                 IF ( Var % DOFs <= 1 ) THEN
                    Work(1:n) = ListGetReal( CurrentModel % ICs(j) % Values, &
                      Var % Name, n, CurrentElement % NodeIndexes, gotIt )
                    IF ( GotIt ) THEN
                      DO k=1,n
                        k1 = CurrentElement % NodeIndexes(k)
                        IF ( ASSOCIATED(Var % Perm) ) k1 = Var % Perm(k1)
                        IF ( k1>0 ) Var % Values(k1) = Work(k)
                      END DO
                    END IF
                 ELSE
                    CALL ListGetRealArray( CurrentModel % ICs(j) % Values, &
                      Var % Name, WorkA, n, CurrentElement % NodeIndexes, gotIt )

                    IF ( GotIt ) THEN
                      DO k=1,n
                        k1 = CurrentElement % NodeIndexes(k)
                        DO l=1,MIN(SIZE(WorkA,1),Var % DOFs)
                          IF ( ASSOCIATED(Var % Perm) ) k1 = Var % Perm(k1)
                          IF ( k1>0 ) Var % Values(Var % DOFs*(k1-1)+l) = WorkA(l,1,k)
                        END DO
                      END DO
                    END IF
                 END IF
                 Var => Var % Next
               END DO
             END IF
           END IF
         END DO
         Mesh => Mesh % Next
       END DO
     END DO

!------------------------------------------------------------------------------
!    Check if we are restarting
!------------------------------------------------------------------------------
     RestartFile = ListGetString( CurrentModel % Simulation, &
                 'Restart File', GotIt )

     IF ( GotIt ) THEN
       k = ListGetInteger( CurrentModel % Simulation,'Restart Position',GotIt, &
                  minv=0 )

       Mesh => CurrentModel % Meshes
       DO WHILE( ASSOCIATED(Mesh) ) 
         IF ( LEN_TRIM(Mesh % Name) > 0 ) THEN
           OutputName = TRIM(Mesh % Name) // '/' // TRIM(RestartFile)
         ELSE
           OutputName = TRIM(RestartFile)
         END IF

         IF ( ParEnv % PEs > 1 ) THEN
            IF ( ParEnv % MyPE < 10 ) THEN
               WRITE( OutputName, '(a,i1)' ) TRIM(OutputName) // '.',ParEnv % MyPe
            ELSE IF ( ParEnv % MyPE < 100 ) THEN
               WRITE( OutputName, '(a,i2)' ) TRIM(OutputName) // '.',ParEnv % MyPE
            ELSE IF ( ParENv % MyPe < 1000 ) THEN
               WRITE( OutputName, '(a,i3)' ) TRIM(OutputName) // '.',ParEnv % MyPE
            ELSE
               WRITE( OutputName, '(a,i4)' ) TRIM(OutputName) // '.',ParEnv % MyPE
            END IF
         END IF

         CALL SetCurrentMesh( CurrentModel, Mesh )
         CALL LoadRestartFile( OutputName,k,Mesh )
         Mesh => Mesh % Next
       END DO
     END IF

!------------------------------------------------------------------------------
!    Make sure that initial values at boundaries are set correctly.
!    TODO: does not handle normal-tangential vector values correctly.
!    NOTE: This overrides the initial condition setting for field variables!!!!
!-------------------------------------------------------------------------------
     InitDirichlet = ListGetLogical( CurrentModel % Simulation, &
            'Initialize Dirichlet Conditions', GotIt ) 
     IF ( .NOT. GotIt ) InitDirichlet = .TRUE.

     IF ( InitDirichlet ) THEN
       Mesh => CurrentModel % Meshes
       DO WHILE( ASSOCIATED(Mesh) )
         CALL SetCurrentMesh( CurrentModel, Mesh )
         DO t = Mesh % NumberOfBulkElements + 1, &
                 Mesh % NumberOfBulkElements + Mesh % NumberOfBoundaryElements

           CurrentElement => Mesh % Elements(t)

           ! Set also the current element pointer in the model structure to
           ! reflect the element being processed:
           ! ---------------------------------------------------------------
           CurrentModel % CurrentElement => CurrentElement
           n = CurrentElement % TYPE % NumberOfNodes

           DO i=1,CurrentModel % NumberOfBCs
             IF ( CurrentElement % BoundaryInfo % Constraint == &
                        CurrentModel % BCs(i) % Tag ) THEN

               Var => Mesh % Variables
               DO WHILE( ASSOCIATED(Var) )
                 IF ( Var % DOFs <= 1 ) THEN
                   Work(1:n) = ListGetReal( CurrentModel % BCs(i) % Values, &
                     Var % Name, n, CurrentElement % NodeIndexes, gotIt )
                   IF ( GotIt ) THEN
                     DO j=1,n
                       k = CurrentElement % NodeIndexes(j)
                       IF ( ASSOCIATED(Var % Perm) ) k = Var % Perm(k)
                       IF ( k>0 ) Var % Values(k) = Work(j)
                     END DO
                   END IF
                 ELSE
                   CALL ListGetRealArray( CurrentModel % BCs(i) % Values, &
                     Var % Name, WorkA, n, CurrentElement % NodeIndexes, gotIt )
                   IF ( GotIt ) THEN
                     DO j=1,n
                       k = CurrentElement % NodeIndexes(j)
                       DO l=1,MIN(SIZE(WorkA,1),Var % DOFs)
                         IF ( ASSOCIATED(Var % Perm) ) k = Var % Perm(k)
                         IF ( k>0 ) Var % Values(Var % DOFs*(k-1)+l) = WorkA(l,1,j)
                       END DO
                     END DO
                   END IF
                 END IF
                 Var => Var % Next
               END DO
             END IF
           END DO
         END DO
         Mesh => Mesh % Next
       END DO
     END IF
!------------------------------------------------------------------------------
   END SUBROUTINE SetInitialConditions
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   SUBROUTINE ExecSimulation
!------------------------------------------------------------------------------
     DO i=1,CurrentModel % NumberOfSolvers
        Solver => CurrentModel % Solvers(i)
        IF ( Solver % SolverExecWhen == SOLVER_EXEC_AHEAD_ALL ) THEN
           CALL SolverActivate( CurrentModel,Solver,dt,TransientSimulation )
        END IF
     END DO

     ddt = 0.0d0
     DO interval = 1,TimeIntervals
!------------------------------------------------------------------------------
       IF ( TransientSimulation ) THEN
         dt = TimestepSizes(interval,1)
       ELSE
         dt = 1
       END IF
!------------------------------------------------------------------------------
!      go trough number of timesteps within an interval
!------------------------------------------------------------------------------
       DO timestep = 1,Timesteps(interval)

         dtfunc = ListGetConstReal( CurrentModel % Simulation, &
                  'Timestep Function', gotIt)
         IF(GotIt) dt = dtfunc

!------------------------------------------------------------------------------
         SimulationTime(1) = SimulationTime(1) + dt
         Time = Time + 1
!------------------------------------------------------------------------------
         IF ( ParEnv % MyPE == 0 ) THEN
           CALL Info( 'MAIN', ' ', Level=3 )
           CALL Info( 'MAIN', '-------------------------------------', Level=3 )

           IF ( TransientSimulation ) THEN
             WRITE( Message, * ) 'Time: ',Time,SimulationTime(1)
             CALL Info( 'MAIN', Message, Level=3 )
           ELSE
             WRITE( Message, * ) 'Steady state iteration: ',Time
             CALL Info( 'MAIN', Message, Level=3 )
           END IF

           CALL Info( 'MAIN', '-------------------------------------', Level=3 )
           CALL Info( 'MAIN', ' ', Level=3 )
         END IF

!------------------------------------------------------------------------------
!        Solve any and all governing equations in the system
!------------------------------------------------------------------------------
         AdaptiveTime = ListGetLogical( CurrentModel % Simulation, &
                  'Adaptive Timestepping', GotIt )

         IF ( TransientSimulation .AND. AdaptiveTime ) THEN
            AdaptiveLimit = ListGetConstReal( CurrentModel % Simulation, &
                        'Adaptive Time Error', GotIt )
 
            IF ( .NOT. GotIt ) THEN 
               WRITE( Message, * ) 'Adaptive Time Limit must be given for' // &
                        'adaptive stepping scheme.'
               CALL Fatal( 'ElmerSolver', Message )
            END IF

            AdaptiveMaxTimestep = ListGetConstReal( CurrentModel % Simulation, &
                     'Adaptive Max Timestep', GotIt )
            IF ( .NOT. GotIt ) AdaptiveMaxTimestep =  dt
            AdaptiveMaxTimestep =  MIN(AdaptiveMaxTimeStep, dt)

            AdaptiveMinTimestep = ListGetConstReal( CurrentModel % Simulation, &
                     'Adaptive Min Timestep', GotIt )

            AdaptiveKeepSmallest = ListGetInteger( CurrentModel % Simulation, &
                       'Adaptive Keep Smallest', GotIt, minv=0  )

            n = CurrentModel % NumberOfSolvers
            j = 0
            k = 0
            DO i=1,n
               Solver => CurrentModel % Solvers(i)
               IF ( ASSOCIATED( Solver % Variable  % Values ) ) THEN
                  IF ( ASSOCIATED( Solver % Variable % PrevValues ) ) THEN
                     j = MAX( j, SIZE( Solver % Variable % PrevValues,2 ) )
                  END IF
                  k = MAX( k, SIZE( Solver % Variable % Values ) )
               END IF
            END DO
            ALLOCATE( xx(n,k), yynrm(n), xxnrm(n), prevxx( n,k,j ) )

            CumTime = 0.0d0
            IF ( ddt == 0.0d0 .OR. ddt > AdaptiveMaxTimestep ) ddt = AdaptiveMaxTimestep

            s = SimulationTime(1) - dt
            SmallestCount = 0
            DO WHILE( CumTime < dt-1.0d-12 )
               ddt = MIN( dt - CumTime, ddt )

               DO i=1,CurrentModel % NumberOFSolvers
                  Solver => CurrentModel % Solvers(i)
                  IF ( ASSOCIATED( Solver % Variable % Values ) ) THEN
                     n = SIZE( Solver % Variable % Values )
                     xx(i,1:n) = Solver % Variable % Values
                     xxnrm(i) = Solver % Variable % Norm
                     IF ( ASSOCIATED( Solver % Variable % PrevValues ) ) THEN
                        DO j=1,SIZE( Solver % Variable % PrevValues,2 )
                           prevxx(i,1:n,j) = Solver % Variable % PrevValues(:,j)
                        END DO
                     END IF
                  END IF
               END DO

               SimulationTime(1) = s + CumTime + ddt
               CALL SolveEquations( CurrentModel, ddt, TransientSimulation, &
                 CoupledMinIter, CoupledMaxIter, SteadyStateReached )

               MaxErr = ListGetConstReal( CurrentModel % Simulation, &
                          'Adaptive Error Measure', GotIt )

               DO i=1,CurrentModel % NumberOFSolvers
                  Solver => CurrentModel % Solvers(i)
                  IF ( ASSOCIATED( Solver % Variable % Values ) ) THEN
                     n = SIZE(Solver % Variable % Values)
                     yynrm(i) = Solver % Variable % Norm
                     Solver % Variable % Values = xx(i,1:n)
                     IF ( ASSOCIATED( Solver % Variable % PrevValues ) ) THEN
                        DO j=1,SIZE( Solver % Variable % PrevValues,2 )
                           Solver % Variable % PrevValues(:,j) = prevxx(i,1:n,j)
                        END DO
                     END IF
                  END IF
               END DO

               SimulationTime(1) = s + CumTime + ddt/2
               CALL SolveEquations( CurrentModel, ddt/2, TransientSimulation, &
                  CoupledMinIter, CoupledMaxIter, SteadyStateReached )

               SimulationTime(1) = s + CumTime + ddt
               CALL SolveEquations( CurrentModel, ddt/2, TransientSimulation, &
                  CoupledMinIter, CoupledMaxIter, SteadyStateReached )

               MaxErr = ABS( MaxErr - ListGetConstReal( CurrentModel % Simulation, &
                           'Adaptive Error Measure', GotIt ) )

               IF ( .NOT. GotIt ) THEN
                  MaxErr = 0.0d0
                  DO i=1,CurrentModel % NumberOFSolvers
                     Solver => CurrentModel % Solvers(i)
                     IF ( ASSOCIATED( Solver % Variable % Values ) ) THEN
                        IF ( yynrm(i) /= Solver % Variable % Norm ) THEN
                           Maxerr = MAX(Maxerr,ABS(yynrm(i)-Solver % Variable % Norm)/yynrm(i))
                        END IF
                     END IF
                  END DO
               END IF

               IF ( MaxErr < AdaptiveLimit .OR. ddt <= AdaptiveMinTimestep ) THEN
                 CumTime = CumTime + ddt
                 IF ( SmallestCount >= AdaptiveKeepSmallest .OR. StepControl > 0 ) THEN
                    ddt = MIN( 2*ddt, AdaptiveMaxTimeStep )
                    StepControl   = 1
                    SmallestCount = 0
                  ELSE
                    StepControl   = 0
                    SmallestCount = SmallestCount + 1
                  END IF
               ELSE
                  DO i=1,CurrentModel % NumberOFSolvers
                     Solver => CurrentModel % Solvers(i)
                     IF ( ASSOCIATED( Solver % Variable % Values ) ) THEN
                        n = SIZE(Solver % Variable % Values)
                        Solver % Variable % Norm = xxnrm(i)
                        Solver % Variable % Values = xx(i,1:n)
                        IF ( ASSOCIATED( Solver % Variable % PrevValues ) ) THEN
                           DO j=1,SIZE( Solver % Variable % PrevValues,2 )
                              Solver % Variable % PrevValues(:,j) = prevxx(i,1:n,j)
                           END DO
                        END IF
                     END IF
                  END DO
                  ddt = ddt / 2
                  StepControl = -1
               END IF
               WRITE(*,'(a,3e20.12)') 'Adaptive(cum,ddt,err): ', cumtime, ddt, maxerr
            END DO
            SimulationTime(1) = s + dt
  
            DEALLOCATE( xx, xxnrm, yynrm )
         ELSE ! Adaptive timestepping
            CALL SolveEquations( CurrentModel, dt, TransientSimulation, &
               CoupledMinIter, CoupledMaxIter, SteadyStateReached )
         END IF
!------------------------------------------------------------------------------
!        Save results to disk, if requested
!------------------------------------------------------------------------------
         IF ( CurrentModel % Meshes % SavesDone == 0 ) THEN
            CALL SaveToPost( 0 )
         END IF

         k = MOD( Timestep-1, OutputIntervals(Interval) )
         LastSaved = .FALSE.
         IF ( k == 0 .OR. SteadyStateReached ) THEN
           CALL SaveCurrent( Timestep )
           LastSaved = .TRUE.
         END IF
!------------------------------------------------------------------------------
         IF ( SteadyStateReached .AND. .NOT. TransientSimulation ) THEN
            IF ( Timestep >= CoupledMinIter ) EXIT
         END IF
!------------------------------------------------------------------------------
       END DO ! timestep within an iterval
!------------------------------------------------------------------------------
     END DO ! timestep intervals, i.e. the simulation
!------------------------------------------------------------------------------

     DO i=1,CurrentModel % NumberOfSolvers
        Solver => CurrentModel % Solvers(i)
        When = ListGetString( Solver % Values, 'Exec Solver', GotIt )
        IF ( GotIt ) THEN
           IF ( When == 'after simulation' .OR. When == 'after all' ) THEN
              CALL SolverActivate( CurrentModel,Solver,dt,TransientSimulation )
              LastSaved = .FALSE.
           END IF
        ELSE
           IF ( Solver % SolverExecWhen == SOLVER_EXEC_AFTER_ALL ) THEN
              CALL SolverActivate( CurrentModel,Solver,dt,TransientSimulation )
              LastSaved = .FALSE.
           END IF
        END IF
     END DO
!------------------------------------------------------------------------------
   END SUBROUTINE ExecSimulation
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE SaveCurrent( CurrentStep )
!------------------------------------------------------------------------------
    INTEGER :: i, CurrentStep
    TYPE(Variable_t), POINTER :: Var
    LOGICAL :: EigAnal, GotIt
    CHARACTER(LEN=MAX_NAME_LEN) :: Simul
    
    Simul = ListGetString( CurrentModel % Simulation, &
         'Simulation Type' )
    
    Mesh => CurrentModel % Meshes
    DO WHILE( ASSOCIATED( Mesh ) ) 
       IF ( Mesh % OutputActive ) THEN
          IF ( LEN_TRIM(Mesh % Name) > 0 ) THEN
             OutputName = TRIM(Mesh % Name) // '/' // TRIM(OutputFile)
          ELSE
             OutputName = OutputFile
          END IF

          EigAnal = .FALSE.
          DO i=1,CurrentModel % NumberOfSolvers
             IF ( ASSOCIATED( CurrentModel % Solvers(i) % Mesh, Mesh ) ) THEN
                EigAnal = ListGetLogical( CurrentModel % Solvers(i) % Values, &
                            'Eigen Analysis', GotIt )

                IF ( EigAnal ) THEN
                   Var => CurrentModel % Solvers(i) % Variable
                   IF ( ASSOCIATED(Var % EigenValues) ) THEN
                      IF ( TotalTimesteps == 1 ) THEN
                         DO j=1,CurrentModel % Solvers(i) % NOFEigenValues
                           IF ( CurrentModel % Solvers(i) % Matrix % Complex ) THEN
                              DO k=1,SIZE(Var % Values)/2
                                 Var % Values(2*k-1) = REAL( Var % EigenVectors(j,k) )
                                 Var % Values(2*k-0) = AIMAG( Var % EigenVectors(j,k) )
                               END DO
                            ELSE
                               Var % Values = REAL( Var % EigenVectors(j,:) )
                            END IF
                            SavedSteps = SaveResult( OutputName, Mesh, &
                                   j, SimulationTime(1) )
                         END DO
                      ELSE
                         j = MIN( CurrentStep, SIZE( Var % EigenVectors,1 ) )
                         IF ( CurrentModel % Solvers(i) % Matrix % Complex ) THEN
                           DO k=1,SIZE(Var % Values)/2
                              Var % Values(2*k-1) = REAL( Var % EigenVectors(j,k) )
                              Var % Values(2*k-0) = AIMAG( Var % EigenVectors(j,k) )
                            END DO
                         ELSE
                            Var % Values = REAL(Var % EigenVectors(j,:))
                         END IF
                         SavedSteps = SaveResult( OutputName, Mesh, &
                              CurrentStep, SimulationTime(1) )
                      END IF
                      Var % Values = 0.0d0
                   END IF
                END IF
             END IF
          END DO

          IF ( .NOT. EigAnal ) THEN
             SavedSteps = SaveResult( OutputName,Mesh,Time,SimulationTime(1) )
          END IF
       END IF
       Mesh => Mesh % Next
    END DO
    CALL SaveToPost( CurrentStep )
!------------------------------------------------------------------------------
  END SUBROUTINE SaveCurrent
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
  SUBROUTINE SaveToPost( CurrentStep ) 
!------------------------------------------------------------------------------
!    Convert results file to post processing file, if requested
!------------------------------------------------------------------------------
    TYPE(Variable_t), POINTER :: Var
    INTEGER :: i, CurrentStep
    LOGICAL :: EigAnal = .FALSE.
    CHARACTER(LEN=MAX_NAME_LEN) :: Simul
    
    Simul = ListGetString( CurrentModel % Simulation,  'Simulation Type' )
    
    PostFile = ListGetString( CurrentModel % Simulation,'Post File',GotIt )
    IF ( GotIt ) THEN
       IF ( ParEnv % PEs > 1 ) THEN
          DO i=1,MAX_NAME_LEN
             IF ( PostFile(i:i) == ' ' ) EXIT
          END DO
          PostFile(i:i) = '.'
          IF ( ParEnv % MyPE < 10 ) THEN
             WRITE( PostFile(i+1:), '(i1)' ) ParEnv % MyPE
          ELSE IF ( ParEnv % MyPE < 100 ) THEN
             WRITE( PostFile(i+1:), '(i2)' ) ParEnv % MyPE
          ELSE
             WRITE( PostFile(i+1:), '(i3)' ) ParEnv % MyPE
          END IF
       END IF
       
       Mesh => CurrentModel % Meshes
       DO WHILE( ASSOCIATED( Mesh ) )
          IF ( Mesh % OutputActive ) THEN
             IF ( LEN_TRIM( Mesh % Name ) > 0 )  THEN
                OutputName = TRIM(Mesh % Name) // '/' // TRIM(OutputFile)
                Postname   = TRIM(Mesh % Name) // '/' // TRIM(PostFile)
             ELSE
                PostName   = PostFile
                OutputName = OutputFile
             END IF
             CALL SetCurrentMesh( CurrentModel, Mesh )

             EigAnal = .FALSE.
             IF ( CurrentStep /= 0 ) THEN
               DO i=1,CurrentModel % NumberOfSolvers
                  IF (ASSOCIATED(CurrentModel % Solvers(i) % Mesh, Mesh)) THEN
                     EigAnal = ListGetLogical( CurrentModel % &
                         Solvers(i) % Values, 'Eigen Analysis', GotIt )

                     IF ( EigAnal ) THEN
                        Var => CurrentModel % Solvers(i) %  Variable
                        IF ( TotalTimesteps == 1 ) THEN
                           DO j=1,CurrentModel % Solvers(i) % NOFEigenValues
                              IF ( CurrentModel % Solvers(i) % Matrix % Complex ) THEN
                                 DO k=1,SIZE(Var % Values)/2
                                    Var % Values(2*k-1) = REAL( Var % EigenVectors(j,k) )
                                    Var % Values(2*k-0) = AIMAG( Var % EigenVectors(j,k) )
                                 END DO
                              ELSE
                                 Var % Values = Var % EigenVectors(j,:)
                              END IF

                              IF ( Mesh % SavesDone /= 0 ) Mesh % SavesDone = j
                              CALL WritePostFile( PostName,OutputName, CurrentModel, &
                                 CurrentModel % Solvers(i) % NOFEigenValues, .TRUE. )
                           END DO
                        ELSE
                           j = MIN( CurrentStep, SIZE( Var % EigenVectors,1 ) )
                           IF ( CurrentModel % Solvers(i) % Matrix % Complex ) THEN
                              DO k=1,SIZE(Var % Values)/2
                                 Var % Values(2*k-1) = REAL( Var % EigenVectors(j,k) )
                                 Var % Values(2*k-0) = AIMAG( Var % EigenVectors(j,k) )
                              END DO
                           ELSE
                              Var % Values = Var % EigenVectors(j,:)
                           END IF

                           IF ( Mesh % SavesDone /= 0 ) Mesh % SavesDone = CurrentStep
                           CALL WritePostFile( PostName,OutputName, CurrentModel, &
                             CurrentModel % Solvers(i) % NOFEigenValues, .TRUE. )
                        END IF
                        Var % Values = 0.0d0
                        EXIT
                     END IF
                  END IF
               END DO
             END IF

             IF ( .NOT. EigAnal ) THEN
                IF ( CurrentModel % Solvers(1) % NOFEigenValues > 0 ) THEN
                   CALL WritePostFile( PostName, OutputName, CurrentModel, &
                      CurrentModel % Solvers(1) % NOFEigenValues, .TRUE. )
                ELSE
                   CALL WritePostFile( PostName, OutputName, &
                      CurrentModel, TotalTimesteps, .TRUE. )
                END IF
             END IF
          END IF
          Mesh => Mesh % Next
       END DO
    END IF
!------------------------------------------------------------------------------
  END SUBROUTINE SaveToPost
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
  END SUBROUTINE ElmerSolver
!------------------------------------------------------------------------------
