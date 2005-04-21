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
! *                This solver may be used for optmization 
! *
! *                    Solver Author: Peter R�back
! *
! *                    Address: CSC - Scientific Computing Ltd. 
! *                             Tietotie 6, P.O. BOX 405
! *                             02101 Espoo, Finland
! *                             Tel. +358 0 457 2080
! *                             Telefax: +358 0 457 2302
! *                             EMail: Peter.Raback@csc.fi
! *
! *                       Date: 26 Mar 2003
! *
! *                Modified by: 
! *
! *       Date of modification: 
! *
! ******************************************************************************/
 
!------------------------------------------------------------------------------
! Subroutines Parameteri are for cases where the parameter directly
! is associated to some coefficient. Then the paremeter is constant 
! and may be fetched with these following 5 subroutines.

FUNCTION Parameter1( Model, n, x ) RESULT( param )
!DEC$ATTRIBUTES DLLEXPORT :: Parameter1
  USE Types
  USE Lists

  TYPE(Model_t) :: Model
  INTEGER :: n
  REAL(KIND=dp) :: x,param
  
  param = ListGetConstReal(Model % Simulation,'Parameter 1')

END FUNCTION Parameter1
!------------------------------------------------------------------------------
FUNCTION Parameter2( Model, n, x ) RESULT( param )
!DEC$ATTRIBUTES DLLEXPORT :: Parameter2
  USE Types
  USE Lists

  TYPE(Model_t) :: Model
  INTEGER :: n
  REAL(KIND=dp) :: x,param
  
  param = ListGetConstReal(Model % Simulation,'Parameter 2')

END FUNCTION Parameter2
!------------------------------------------------------------------------------
FUNCTION Parameter3( Model, n, x ) RESULT( param )
!DEC$ATTRIBUTES DLLEXPORT :: Parameter3
  USE Types
  USE Lists

  TYPE(Model_t) :: Model
  INTEGER :: n
  REAL(KIND=dp) :: x,param
  
  param = ListGetConstReal(Model % Simulation,'Parameter 3')

END FUNCTION Parameter3
!------------------------------------------------------------------------------
FUNCTION Parameter4( Model, n, x ) RESULT( param )
!DEC$ATTRIBUTES DLLEXPORT :: Parameter4
  USE Types
  USE Lists

  TYPE(Model_t) :: Model
  INTEGER :: n
  REAL(KIND=dp) :: x,param
  
  param = ListGetConstReal(Model % Simulation,'Parameter 4')

END FUNCTION Parameter4
!------------------------------------------------------------------------------
FUNCTION Parameter5( Model, n, x ) RESULT( param )
!DEC$ATTRIBUTES DLLEXPORT :: Parameter5
  USE Types
  USE Lists

  TYPE(Model_t) :: Model
  INTEGER :: n
  REAL(KIND=dp) :: x,param
  
  param = ListGetConstReal(Model % Simulation,'Parameter 5')

END FUNCTION Parameter5
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
! This subroutine could be used "before all" in order to initialize
! the parameters. The parameters may be given or also read from a file
! that has previously been saved by the optimization routine.
!
SUBROUTINE GuessOptimum( Model,Solver,dt,TransientSimulation )
  !DEC$ATTRIBUTES DLLEXPORT :: GuessOptimum
!------------------------------------------------------------------------------

  USE Types
  USE Lists
  USE MeshUtils
  USE Integration
  USE ElementDescription
  USE SolverUtils

  IMPLICIT NONE
!------------------------------------------------------------------------------
  TYPE(Solver_t), TARGET :: Solver
  TYPE(Model_t) :: Model
  REAL(KIND=dp) :: dt
  LOGICAL :: TransientSimulation
  
  INTEGER :: i,n
  REAL(KIND=dp) :: parami
  REAL(KIND=dp), ALLOCATABLE :: param(:)
  CHARACTER(LEN=MAX_NAME_LEN) :: Name
  LOGICAL :: fileis, GotIt
  CHARACTER(LEN=MAX_NAME_LEN) :: GuessFile

  GuessFile = ListGetString(Solver % Values,'Filename',GotIt )
  IF(.NOT. GotIt) GuessFile = 'optimize-best.dat'

  INQUIRE (FILE=GuessFile, EXIST=fileis)

  IF(fileis) THEN
    OPEN(10,FILE=GuessFile)
    READ (10,*) n
    ALLOCATE (param(n))
    DO i=1,n
      READ (10,*) param(i)
    END DO
    CLOSE(10)

#if 0
    PRINT *,'Initial Guess for parameters',param
#endif

    DO i=1,n
      WRITE (Name,'(A,I2)') 'Parameter',i          
      CALL ListAddConstReal(Model % Simulation,TRIM(Name),param(i))
    END DO
  ELSE
    i = 0
    GotIt = .TRUE.
    DO WHILE(GotIt) 
      i = i+1
      WRITE (Name,'(A,I2)') 'Initial Parameter',i
      Parami = ListGetConstReal(Solver % Values,TRIM(Name),GotIt)
      WRITE (Name,'(A,I2)') 'Parameter',i
      CALL ListAddConstReal(Model % Simulation,TRIM(Name),Parami)
    END DO
  END IF

END SUBROUTINE GuessOptimum


!------------------------------------------------------------------------------
SUBROUTINE FindOptimum( Model,Solver,dt,TransientSimulation )
  !DEC$ATTRIBUTES DLLEXPORT :: FindOptimum
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
  USE MeshUtils
  USE Integration
  USE ElementDescription
  USE SolverUtils

  IMPLICIT NONE
!------------------------------------------------------------------------------
  TYPE(Solver_t), TARGET :: Solver
  TYPE(Model_t) :: Model
  REAL(KIND=dp) :: dt
  LOGICAL :: TransientSimulation

!------------------------------------------------------------------------------
! Local variables
!------------------------------------------------------------------------------
  LOGICAL :: gotIt, SubroutineVisited=.FALSE.
  LOGICAL, ALLOCATABLE :: FixedParam(:)
  INTEGER :: i,j,k,l,NoParam, NoValues, NoFreeParam, OptimizationsDone=0, Direction=1
  REAL(KIND=dp), ALLOCATABLE :: Param(:), MinParam(:), MaxParam(:), PrevParam(:,:), &
      PrevCost(:), BestParam(:)
  REAL(KIND=dp) :: Cost, SCALE, Step, Eps, MinCost, x(10), c(10)
  CHARACTER(LEN=MAX_NAME_LEN) :: Name, Method
  CHARACTER(LEN=MAX_NAME_LEN) :: BestFile, HistoryFile
  
  SAVE SubroutineVisited, Param, MinParam, MaxParam, PrevParam, NoParam, &
      OptimizationsDone, Method, Direction, x, c, PrevCost, Eps, &
      FixedParam, NoFreeParam, MinCost, BestParam

!------------------------------------------------------------------------------



  OptimizationsDone = OptimizationsDone + 1

  IF(.NOT. SubroutineVisited) THEN
    SubroutineVisited = .TRUE.
    NoParam = ListGetInteger(Solver % Values,'No Parameter')

    IF(NoParam == 0) THEN
      CALL Warn('FindOptimum','There are no parameters to optimize!')
      RETURN
    END IF

    NoValues = ListGetInteger(Model % Simulation,'Steady State Max Iterations')
    ALLOCATE( Param(NoParam), MinParam(NoParam), BestParam(NoParam), MaxParam(NoParam), &
        PrevParam(NoValues,NoParam), PrevCost(NoValues), FixedParam(NoParam))

    NoFreeParam = 0
    DO i=1,NoParam
      IF(i < 10) THEN
        WRITE (Name,'(A,I2)') 'Min Parameter',i
        MinParam(i) = ListGetConstReal(Solver % Values,TRIM(Name))

        WRITE (Name,'(A,I2)') 'Max Parameter',i
        MaxParam(i) = ListGetConstReal(Solver % Values,TRIM(Name))

        WRITE (Name,'(A,I2)') 'Parameter',i
        Param(i) = ListGetConstReal(Model % Simulation,TRIM(Name),GotIt)

        WRITE (Name,'(A,I2)') 'Fixed Parameter',i
        FixedParam(i) = ListGetLogical(Solver % Values,TRIM(Name),GotIt)        
        IF(.NOT. FixedParam(i)) NoFreeParam = NoFreeParam + 1
      ELSE
        CALL Warn('FindOptimum','Code the case for NoParam > 10 as well!')
        RETURN
      END IF
    END DO

    MinCost = HUGE(MinCost)
    Method = ListGetString(Solver % Values,'Optimization Method')
  END IF

  Cost = ListGetConstReal(Model % Simulation,'Cost Function',GotIt)
  IF(.NOT. GotIt) THEN
    Name = ListGetString(Solver % Values,'Cost Function Name',GotIt)
    IF(.NOT. GotIt) CALL Fatal('FindOptimum','Give Cost Function or its name')
    Cost = ListGetConstReal(Model % Simulation,TRIM(Name),GotIt)
    IF(.NOT. GotIt) CALL Fatal('FindOptimum','Cost with the given name was not found')
  END IF

  IF(Cost < MinCost) THEN
    MinCost = Cost
    BestParam(1:NoParam) = Param(1:NoParam)

    WRITE(Message,'(A,ES15.6E3)') 'Found New Minimum Set',MinCost
    CALL Info('FindOptimum',Message,Level=4)

    BestFile = ListGetString(Solver % Values,'Filename',GotIt )
    IF(.NOT. GotIt) BestFile = 'optimize-best.dat'

    OPEN (10, FILE=BestFile, STATUS='REPLACE')
    WRITE (10,'(I)') NoParam
    DO i=1,NoParam
      WRITE (10,'(ES17.8E3)') Param(i)
    END DO
    WRITE (10,'(ES17.8E3)') Cost
    CLOSE(10)
  END IF


  PrevParam(OptimizationsDone,1:NoParam) = Param(1:NoParam)
  PrevCost(OptimizationsDone) = Cost

  HistoryFile = ListGetString(Solver % Values,'History File',GotIt )
  IF(.NOT. GotIt) HistoryFile = 'optimize.dat'

  IF(OptimizationsDone == 1) THEN
    OPEN (10, FILE=HistoryFile)
  ELSE
    OPEN (10, FILE=HistoryFile,POSITION='APPEND')
  END IF
  
  WRITE (10,'(ES17.8E3)',advance='no') Cost
  DO i=1,NoParam
    WRITE (10,'(ES17.8E3)',advance='no') Param(i)
  END DO
  
  WRITE(10,'(A)') ' '
  CLOSE(10)


  CALL Info( 'FindOptimum', '-----------------------------------------', Level=4 )
  WRITE( Message, '(A,I2,A,A)' ) 'Manipulating',NoFreeParam,' parameters using ',TRIM(Method) 
  CALL Info( 'FindOptimum', Message, Level=4 )
  WRITE( Message, '(A,ES15.6E3)' ) 'Lowest cost so far is ',MinCost
  CALL Info( 'FindOptimum', Message, Level=4 )
  CALL Info( 'FindOptimum', '-----------------------------------------', Level=4 )


  SELECT CASE(Method)
    
  CASE ('random')
    DO i=1,NoParam
      CALL RANDOM_NUMBER(SCALE)
      Param(i) = MinParam(i) + (MaxParam(i)-MinParam(i)) * SCALE
    END DO
    
  CASE ('scan')
    IF(NoFreeParam /= 1) CALL Fatal('FindOptimum',&
        'Option scan implemented only for one parameter')
    DO i=1,NoParam
      IF(.NOT. FixedParam(i)) EXIT
    END DO
    PRINT *,'Active Parameter',i
    SCALE = (OptimizationsDone+1)*1.0d0/(NoValues-1)
    Param(i) = MinParam(i) + (MaxParam(i)-MinParam(i)) * SCALE
    
  CASE ('genetic')
    CALL GeneticOptimize(NoParam, OptimizationsDone, Param, Cost)
    DO i=1,NoParam 
      Param(i) = MAX(MinParam(i),Param(i))
      Param(i) = MIN(MaxParam(i),Param(i))
    END DO

  CASE ('bisect')    
    IF(NoFreeParam /= 1) CALL Fatal('FindOptimum',&
        'Option bisect implemented only for one parameter')
    Eps = ListGetConstReal(Solver % Values,'Optimization Accuracy')
    DO j=1,NoParam
      IF(.NOT. FixedParam(j)) EXIT
    END DO
    PRINT *,'Active Parameter For Bisection Search',j
    CALL BisectOptimize(OptimizationsDone)
    
  END SELECT


  DO i=1,NoParam
    WRITE (Name,'(A,I2)') 'Parameter',i          
    CALL ListAddConstReal(Model % Simulation,TRIM(Name),Param(i))
  END DO

#if 0
  WRITE (*,'(A,ES12.4)') 'Minimum Cost',MinCost
  WRITE (*,'(A,4ES12.4)') 'Best set',BestParam
  WRITE (*,'(A,4ES12.4)') 'Test set',Param
#endif

CONTAINS

!-------------------------------------------------------------------------------

  FUNCTION rnd(n)
    IMPLICIT NONE
    INTEGER, INTENT(IN) :: n
    REAL(KIND=dp), DIMENSION(n) :: rnd
    CALL RANDOM_NUMBER(rnd)
  END FUNCTION rnd

!-------------------------------------------------------------------------------

  INTEGER FUNCTION idx(n)
    IMPLICIT NONE
    INTEGER, INTENT(IN) :: n
    REAL(KIND=dp) :: x
    CALL RANDOM_NUMBER(x)
    idx = n*x + 1
  END FUNCTION idx

!-------------------------------------------------------------------------------

  SUBROUTINE GeneticOptimize(parsize, no, parameters, func)

    INTEGER :: parsize, no
    REAL (KIND=dp) :: parameters(parsize), func

    INTEGER :: popsize, i0, i1, i2, i3 
    REAL(KIND=dp) :: popcoeff, popcross
    REAL(KIND=dp), ALLOCATABLE :: pars(:,:), vals(:) 
    LOGICAL, ALLOCATABLE :: mask(:)

    SAVE i0, pars, vals, mask, popsize, popcoeff, popcross
        
    IF(no == 1) THEN
      popsize = ListGetInteger(Solver % Values,'Populazation Size',GotIt)
      IF(.NOT. GotIt) popsize = 5 * parsize
      popcoeff = ListGetConstReal(Solver % Values,'Population Coefficient',GotIt)
      IF(.NOT. GotIt) popcoeff = 0.7
      popcross = ListGetConstReal(Solver % Values,'Population Crossover',GotIt)
      IF(.NOT. GotIt) popcross = 0.1
      ALLOCATE(pars(parsize,popsize),vals(popsize),mask(parsize))
#if 0
      PRINT *,'popsize',popsize,'parsize',parsize
      PRINT *,'popcoeff',popcoeff,'popcross',popcross
#endif
    END IF
    
    ! Read the cases into the population
    IF(no <= popsize) THEN
      pars(1:parsize,no) = parameters(1:parsize)
      vals(no) = func
    ELSE   
      IF(func < vals(i0)) THEN
        pars(1:parsize,i0) = parameters(1:parsize) 
        vals(i0) = func
      END IF
    END IF

    ! The first cases are just random
    IF(no < popsize) THEN
      pars(1:parsize,no) = parameters(1:parsize)
      vals(no) = func
      Param = MinParam + (MaxParam-MinParam) * rnd(parsize)
    END IF

    ! Here use genetic algoritms 
    IF(no >= popsize) THEN
      /* Find the three vectors to recombine */
      i0 = MOD(no,popsize) + 1 
      DO
        i1 = idx(popsize)
        IF (i1 /= i0) EXIT
      END DO
      DO
        i2 = idx(popsize)
        IF (i2 /= i0.AND. i2 /= i1) EXIT
      END DO
      DO
        i3 = idx(popsize)
        IF (ALL(i3 /= (/i0,i1,i2/))) EXIT
      END DO
      
      mask = (rnd(parsize) < popcross)
      
      WHERE (mask)
        parameters = pars(:,i3) + popcoeff*(pars(:,i1)-pars(:,i2))
      ELSEWHERE
        parameters = pars(:,i0)
      END WHERE
    END IF

  END SUBROUTINE GeneticOptimize

!-------------------------------------------------------------------------------



  SUBROUTINE BisectOptimize(no)

    INTEGER :: no

    IF(no == 1) THEN
      step = ListGetConstReal(Solver % Values,'Step Size',GotIt)
      IF(.NOT. GotIt) step = (MaxParam(j)-Param(j))/2.0
      step = MIN((MaxParam(j)-Param(j))/2.0,step)
    END IF
    
    IF(no <= 3) THEN
      Param(j) = Param(j) + step
    ELSE IF(ABS(Step) > Eps) THEN
      IF(no == 4) THEN
        x(1) = PrevParam(1,j)
        x(2) = PrevParam(2,j)
        x(3) = PrevParam(3,j)
        c(1) = PrevCost(1)
        c(2) = PrevCost(2)
        c(3) = PrevCost(3)
      ELSE
        x(3) = Param(j)
        c(3) = Cost
      END IF

      ! Order the previous points so that x1 < x2 < x3
      DO k=1,2 
        DO i=k+1,3
          IF(x(i) < x(k)) THEN
            x(4) = x(k)
            x(k) = x(i)
            x(i) = x(4)
            c(4) = c(k)
            c(k) = c(i)
            c(i) = c(4)
          END IF
        END DO
      END DO

      ! Monotonic line segment
      IF( (c(2)-c(1))*(c(3)-c(2)) > 0.0) THEN
        IF(c(3) < c(1)) THEN
          Param(j) = x(3) + SIGN(step,x(3)-x(1))
          c(1) = c(3)
          x(1) = x(3)
        ELSE
          Param(j) = x(1) + SIGN(step,x(1)-x(3))
        END IF
      ELSE IF(c(2) < c(1) .OR. c(2) < c(3)) THEN 
        IF(c(3) < c(1)) THEN
          c(1) = c(3)
          x(1) = x(3)
        END IF
        step = (x(2)-x(1))/2.0d0
        Param(j) = x(1) + SIGN(step,x(2)-x(1))
      ELSE
        CALL Fatal('FindOptimum','This method cannot handle local maxima')
      END IF

    END IF

  END SUBROUTINE BisectOptimize


END SUBROUTINE FindOptimum
