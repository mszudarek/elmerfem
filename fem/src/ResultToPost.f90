! *****************************************************************************/
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
! *  ELMER/FEM Results file to post processing file converter
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
   PROGRAM ResultToPost
!------------------------------------------------------------------------------

     USE MainUtils

!------------------------------------------------------------------------------
     IMPLICIT NONE
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------

     INTEGER :: i,j,k,n,l,t,k1,k2,iter,Ndeg,Time,istat,nproc

     REAL(KIND=dp) :: s,dt,Work(MAX_NODES)
     REAL(KIND=dp), TARGET :: SimulationTime(1)

     TYPE(Element_t),POINTER :: CurrentElement
     REAL(KIND=dp), POINTER ::  TimeVariable(:)

     LOGICAL :: GotIt,TransientSimulation,LastSaved

     INTEGER :: TimeIntervals,interval,timestep,SavedSteps,TimeStepMaxIter

     REAL(KIND=dp), POINTER :: TimestepSizes(:,:)
     INTEGER, POINTER :: Timesteps(:),OutputIntervals(:)

     LOGICAL :: KEModelSolved = .FALSE., SteadyStateReached = .FALSE.

     TYPE(ElementType_t),POINTER :: elmt

     TYPE(ParEnv_t), POINTER :: ParallelEnv

     CHARACTER(LEN=512) :: ModelName, eq
     CHARACTER(LEN=512) :: OutputFile, PostFile, RestartFile, OutputName,PostName

     TYPE(Mesh_t), POINTER :: Mesh
     TYPE(Variable_t), POINTER :: Var
     TYPE(Solver_t), POINTER :: Solver

!------------------------------------------------------------------------------
!    For sgi machines reset the output unit to line buffering, so that
!    Elmercadi, etc, can follow progress, even if output is to a file.
!------------------------------------------------------------------------------
#ifdef SGI
     CALL SetLineBuf(6)
#endif
!------------------------------------------------------------------------------
!    Read input file name and whether parallel execution is requested
!------------------------------------------------------------------------------

     OPEN( 1,file='ELMERSOLVER_STARTINFO')
       READ(1,'(a)') ModelName
     CLOSE(1)

!------------------------------------------------------------------------------
!    If parallel execution requested, initialize parallel environment
!------------------------------------------------------------------------------
     ParEnv % PEs  = 1 
     ParEnv % MyPE = 0

!------------------------------------------------------------------------------
!    Read element definition file, and initialize element types
!------------------------------------------------------------------------------
     CALL InitializeElementDescriptions
!------------------------------------------------------------------------------
!    Read Model and mesh from Elmer mesh data base
!------------------------------------------------------------------------------
     IF ( ParEnv % MyPE == 0 ) THEN
       PRINT*, ' '
       PRINT*, ' '
       PRINT*, '-----------------------'
       PRINT*,'Reading Model ...       '
     END IF

     CurrentModel => LoadModel( ModelName,.FALSE.,ParEnv % PEs,ParEnv % MyPE )

     IF ( ParEnv % MyPE == 0 ) THEN
       PRINT*,'... Done               '
       PRINT*, '-----------------------'
     END IF

!------------------------------------------------------------------------------
!    1 point integration rule is not enough for complete integration of
!    time derivative terms (or any other zeroth order space derivative terms for
!    that  matter, .i.e. the KE model) for linear elements. It is enough
!    (for the time derivative term), if mass matrix  lumping is used though.
!    Anyway, to be on the safe side, if the simulation  is time dependent,
!    change the number of integration points  here.
!
!    NOTE: THIS DOESN�T FIX THE PROBLEM FOR THE KE Model
!------------------------------------------------------------------------------
     eq = ListGetString( CurrentModel % Simulation, 'Simulation Type' )
     TransientSimulation = .FALSE.

     IF ( eq(1:9) == 'transient' ) THEN
       TransientSimulation= .TRUE.

       elmt => GetElementType( 303 )
       IF ( elmt % GaussPoints == 1 ) elmt % GaussPoints = 3

       elmt => GetElementType( 504 )
       IF ( elmt % GaussPoints == 1 ) elmt % GaussPoints = 4
     END IF
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
!    Figure out requested coordinate system
!------------------------------------------------------------------------------
     eq = ListGetString( CurrentModel % Simulation, 'Coordinate System', GotIt )

     Coordinates = Cartesian
     IF ( eq(1:12) == 'cartesian 2d' ) THEN

       CurrentModel % DIMENSION = 2
       Coordinates = Cartesian

     ELSE IF ( eq(1:12) == 'cartesian 3d' ) THEN

       CurrentModel % DIMENSION = 3
       Coordinates = Cartesian

     ELSE IF ( eq(1:13) == 'axi symmetric' ) THEN

       CurrentModel % DIMENSION = 2
       Coordinates = AxisSymmetric

     ELSE IF( eq(1:19) == 'cylindric symmetric' ) THEN

       CurrentModel % DIMENSION = 2
       Coordinates = CylindricSymmetric

     ELSE IF( eq(1:11) == 'cylindrical' ) THEN

       CurrentModel % DIMENSION = 3
       Coordinates = Cylindric

     ELSE IF( eq(1:8) == 'polar 2d' ) THEN

       CurrentModel % DIMENSION = 2
       Coordinates = Polar

     ELSE IF( eq(1:8) == 'polar 3d' ) THEN

       CurrentModel % DIMENSION = 3
       Coordinates = Polar

     ELSE

       PRINT*,'Solver: ERROR: Unknown global coordinate system: ',eq(1:20),' Aborting'
       STOP

     END IF

!------------------------------------------------------------------------------
!   Figure out what (flow,heat,stress,...) should be computed, and get
!   memory for the dofs
!------------------------------------------------------------------------------
     DO i=1,CurrentModel % NumberOfSolvers
       eq = ListGetString( CurrentModel % Solvers(i) % Values,'Equation' )

       Solver => CurrentModel % Solvers(i)
       CALL AddEquation( Solver, eq, TransientSimulation )
     END DO

!------------------------------------------------------------------------------
!    Add coordinates to list of variables so that coordinate dependent
!    parameter computing routines can ask for them...
!------------------------------------------------------------------------------
     TimeVariable => SimulationTime
     Mesh => CurrentModel % Meshes 
     DO WHILE( ASSOCIATED( Mesh ) )
       CALL VariableAdd(Mesh % Variables,Mesh,NULL(),'Coordinate 1',1,Mesh % Nodes % x )
       CALL VariableAdd(Mesh % Variables,Mesh,NULL(),'Coordinate 2',1,Mesh % Nodes % y )
       CALL VariableAdd(Mesh % Variables,Mesh,NULL(),'Coordinate 3',1,Mesh % Nodes % z )
       CALL VariableAdd( Mesh % Variables,Mesh, NULL(),'Time',1,TimeVariable )
       Mesh => Mesh % Next
     END DO


!------------------------------------------------------------------------------
!    Convert results file to post processing file, if requested
!------------------------------------------------------------------------------
     PostFile = ListGetString( CurrentModel % Simulation,'Post File',GotIt )
     OutputFile = ListGetString(CurrentModel % Simulation,'Output File',GotIt)
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
         IF ( LEN_TRIM( Mesh % Name ) > 0 )  THEN
           OutputName = TRIM(Mesh % Name) // '/' // TRIM(OutputFile)
           PostName   = TRIM(Mesh % Name) // '/' // TRIM(PostFile)
         ELSE
           PostName   = PostFile
           OutputName = OutputFile
         END IF
         CALL SetCurrentMesh( CurrentModel, Mesh )
         CALL WritePostFile( PostName,OutputName,CurrentModel,10000 )
         Mesh => Mesh % Next
       END DO
     END IF
!------------------------------------------------------------------------------
!  THIS IS THE END (...,at last, the end, my friend,...)
!------------------------------------------------------------------------------
     PRINT*,'*** Result To Post: ALL DONE ***'

!------------------------------------------------------------------------------
  END PROGRAM ResultToPost
!------------------------------------------------------------------------------
