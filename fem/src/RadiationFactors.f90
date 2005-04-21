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
! * Solve for Gebhardt factors inside the Elmer code
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
! *                Modified by: Peter R�back
! *
! *       Date of modification: 10.8.2004
! *
! *****************************************************************************/


   MODULE RadiationFactorGlobals

      USE CRSMatrix
      USE IterSolve
 
      DOUBLE PRECISION, ALLOCATABLE :: GFactorFull(:,:)
      TYPE(Matrix_t), POINTER :: GFactorSP

   END MODULE RadiationFactorGlobals


   SUBROUTINE RadiationFactors( TSolver, FirstTime)
     DLLEXPORT RadiationFactors

     USE RadiationFactorGlobals
     USE Types
     USE Lists
     USE CoordinateSystems
     USE SolverUtils
     USE MainUtils
     USE ModelDescription
     USE ElementDescription
     USE ElementUtils
     USE GeneralUtils

     IMPLICIT NONE

     TYPE(Solver_t) :: TSolver
     LOGICAL :: FirstTime

!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------
     TYPE(Model_t), POINTER :: Model
     TYPE(Mesh_t), POINTER :: Mesh
     TYPE(Solver_t), POINTER :: Solver
     TYPE(Element_t), POINTER :: CurrentElement
     TYPE(Factors_t), POINTER :: ViewFactors, GebhardtFactors
     TYPE(Matrix_t), POINTER :: Amatrix

     INTEGER :: i,j,k,l,t,n,istat,Colj,j0,couplings, sym 

     REAL (KIND=dp) :: SimulationTime,dt,MinFactor,MaxOmittedFactor, ConsideredSum
     REAL (KIND=dp) :: s,Norm,PrevNorm,Emissivity,maxds,refds,ds,x,y,z,&
         dx,dy,dz,x0(2),y0(2),MeshU(TSolver % Mesh % MaxElementNodes)
     REAL (KIND=dp), POINTER :: Vals(:)
     REAL (KIND=dp), ALLOCATABLE :: SOL(:), RHS(:), Fac(:)
     REAL (KIND=dp) :: MinSum, MaxSum, SolSum, PrevSelf, FactorSum, &
         ImplicitSum, ImplicitLimit, NeglectLimit
     REAL (KIND=dp) :: at, at0, st, RealTime, CPUTime
     INTEGER :: BandSize,SubbandSize,RadiationSurfaces, GeometryFixedAfter, &
         Row,Col,MatrixElements, MatrixFormat, maxind, TimesVisited=0, &
         RadiationBody, MaxRadiationBody, MatrixEntries, ImplicitEntries
     INTEGER, POINTER :: Cols(:), NodeIndexes(:), TempPerm(:), NewPerm(:)
     INTEGER, ALLOCATABLE :: FacPerm(:)
     INTEGER, ALLOCATABLE, TARGET :: RowSpace(:),Reorder(:),ElementNumbers(:), &
         InvElementNumbers(:)

     CHARACTER(LEN=MAX_NAME_LEN) :: RadiationFlag, GebhardtFactorsFile, &
         ViewFactorsFile,OutputName, OutputName2
     CHARACTER(LEN=100) :: cmd

     LOGICAL :: GotIt, SaveFactors, UpdateViewFactors, UpdateGebhardtFactors, &
         ComputeViewFactors, OptimizeBW, TopologyTest, TopologyFixed, &
         FilesExist, FullMatrix, ImplicitLimitIs
     LOGICAL, POINTER :: ActiveNodes(:)

     SAVE TimesVisited 

     Model => CurrentModel
     Mesh => TSolver % Mesh
     CALL SetCurrentMesh( Model, Mesh )

     IF (.NOT. ASSOCIATED(Model)) THEN
       CALL Fatal('RadiationFactors','No pointer to model')
     END IF
     IF (.NOT. ASSOCIATED(Mesh) ) THEN
       CALL Fatal('RadiationFactors','No pointer to mesh')
     END IF

     at0 = CPUTime()

     FullMatrix =  ListGetLogical( TSolver % Values,  &
         'Gebhardt Factors Solver Full',GotIt) 

     UpdateGebhardtFactors = ListGetLogical( TSolver % Values,  &
         'Update Gebhardt Factors',GotIt )
     UpdateViewFactors = ListGetLogical( TSolver % Values,  &
         'Update View Factors',GotIt )
     ComputeViewFactors = ListGetLogical( TSolver % Values,  &
         'Compute View Factors',GotIt )
     IF(.NOT. FirstTime) TimesVisited = TimesVisited + 1
     GeometryFixedAfter = ListGetInteger(TSolver % Values, &
         'View Factors Fixed After Iterations',GotIt)
     IF(.NOT. GotIt) GeometryFixedAfter = HUGE(GeometryFixedAfter)

     IF(GeometryFixedAfter < TimesVisited) UpdateViewFactors = .FALSE.
 
     ! check if nothing to do
     IF(.NOT. (FirstTime .OR. UpdateViewFactors .OR. UpdateGebhardtFactors)) THEN
       RETURN
     END IF

     CALL Info('RadiationFactors','----------------------------------------------------',LEVEL=4)
     CALL Info('RadiationFactors','Computing radiation factors as needed',LEVEL=4)
     CALL Info('RadiationFactors','----------------------------------------------------',LEVEL=4)

     IF(GeometryFixedAfter == TimesVisited) THEN
       x0(1) = 0.0
       x0(2) = 1.0
       y0(1) = 0.0
       y0(2) = 1.0
     END IF

!------------------------------------------------------------------------------
!    Compute the number of elements at the surface and check if the 
!    geometry has really changed.
!------------------------------------------------------------------------------

     RadiationSurfaces = 0
     MaxRadiationBody = 1
     ALLOCATE( ActiveNodes(Model % NumberOfNodes ), STAT=istat )
     IF ( istat /= 0 ) CALL Fatal('RadiationFactors','Memory allocation error 1.')
     ActiveNodes = .FALSE.

     DO t=Model % NumberOfBulkElements+1, &
         Model % NumberOfBulkElements + Model % NumberOfBoundaryElements
       
       CurrentElement => Model % Elements(t)
       k = CurrentElement % BoundaryInfo % Constraint
       
       IF ( CurrentElement % TYPE % ElementCode /= 101 ) THEN
         DO i=1,Model % NumberOfBCs
           IF ( Model % BCs(i) % Tag == k ) THEN
             IF ( ListGetLogical( Model % BCs(i) % Values,'Heat Flux BC', GotIt) ) THEN
               RadiationFlag = ListGetString( Model % BCs(i) % Values, &
                   'Radiation', GotIt )
               
               IF ( RadiationFlag(1:12) == 'diffuse gray' ) THEN
                 
                 l = MAX(1, ListGetInteger( Model % BCs(i) % Values,'Radiation Boundary',GotIt) )

                 MaxRadiationBody = MAX(l, MaxRadiationBody)
                 
                 NodeIndexes =>  CurrentElement % NodeIndexes
                 n = CurrentElement % TYPE % NumberOfNodes

                 ActiveNodes(NodeIndexes) = .TRUE.
                 RadiationSurfaces = RadiationSurfaces + 1
                 
                 IF(GeometryFixedAfter == TimesVisited) THEN
                   MeshU(1:n) = ListGetReal(Model % BCs(i) % Values,'Mesh Update 1',n,NodeIndexes,GotIt)
                   IF(.NOT. GotIt) THEN
                     WRITE (Message,'(A,I3)') 'Freezing Mesh Update 1 for bc',i
                     CALL Info('RadiationFactors',Message)
                     CALL ListAddDepReal( Model % BCs(i) % Values,'Mesh Update 1', &
                         'Mesh Update 1',2, x0, y0 )
                   END IF
                   MeshU(1:n) = ListGetReal(Model % BCs(i) % Values,'Mesh Update 2',n,NodeIndexes,GotIt)
                   IF(.NOT. GotIt) THEN
                     WRITE (Message,'(A,I3)') 'Freezing Mesh Update 2 for bc',i
                     CALL Info('RadiationFactors',Message)
                     CALL ListAddDepReal( Model % BCs(i) % Values,'Mesh Update 2', &
                         'Mesh Update 2',2, x0, y0 )
                   END IF
                 END IF

               END IF
             END IF
           END IF
         END DO
       END IF
     END DO

     IF ( RadiationSurfaces == 0 ) THEN
       CALL Info('RadiationFactors','No surfaces participating in radiation',LEVEL=4)
       DEALLOCATE(ActiveNodes)
       RETURN
     ELSE
       WRITE (Message,'(A,I9,A,I9)') 'Total number of Radiation Surfaces',RadiationSurfaces,' of',&
           Model % NumberOfBoundaryElements
       CALL Info('RadiationFactors',Message,LEVEL=4)
     END IF

     
     ! Check that the geometry has really changed before computing the viewfactors 
     IF(.NOT. FirstTime .AND. UpdateViewFactors) THEN

       ! This is a dirty thrick where the input file is stampered
       CALL Info('RadiationFactors','Checking changes in mesh.nodes file!',LEVEL=4)
       
       OutputName = TRIM(OutputPath) // '/' // TRIM(Mesh % Name) // '/mesh.nodes.new'
       
       INQUIRE(FILE=TRIM(OutputName),EXIST=GotIt)
       IF(.NOT. GotIt) THEN
         OutputName = TRIM(OutputPath) // '/' // TRIM(Mesh % Name) // '/mesh.nodes'
       END IF

       OPEN( 10,File=TRIM(OutputName) )
       dx = MAXVAL(Mesh % Nodes % x) - MINVAL(Mesh % Nodes % x)
       dy = MAXVAL(Mesh % Nodes % y) - MINVAL(Mesh % Nodes % y)
       dz = MAXVAL(Mesh % Nodes % z) - MINVAL(Mesh % Nodes % z)
       refds = SQRT(dx*dx+dy*dy+dz*dz)
       
       maxds = 0.0       
       maxind = 0
       GotIt = .FALSE.

       DO i=1,Mesh % NumberOfNodes
         READ(10,*,ERR=10,END=10) j,k,x,y,z
         IF(i == Mesh % NumberOfNodes) GotIt = .TRUE.
         IF(ActiveNodes(i)) THEN
           dx = Mesh % Nodes % x(i) - x
           dy = Mesh % Nodes % y(i) - y
           dz = Mesh % Nodes % z(i) - z
           ds = SQRT(dx*dx+dy*dy+dz*dz)
           IF(ds > maxds) THEN
             maxds = ds
             maxind = i
           END IF
         END IF
       END DO

10     CONTINUE

       CLOSE(10)

       IF(.NOT. GotIt) THEN
         UpdateViewFactors = .TRUE.        
         WRITE(Message,'(A,A)') 'Mismatch in coordinates compared to file ',TRIM(OutputName)
         CALL Info('RadiationFactors',Message)
       ELSE
         WRITE(Message,'(A,E15.5)') 'Maximum geometry alteration on radiation BCs:',maxds
         CALL Info('RadiationFactors',Message)
         
         x = ListGetConstReal(TSolver % Values,'View Factors Geometry Tolerance',GotIt)
         IF(.NOT. GotIt) x = 1.0d-8
         
         IF(maxds <= refds * x) THEN
           CALL Info('RadiationFactors','Geometry change is neglected and old view factors are used')
           UpdateViewFactors = .FALSE.
         ELSE
           CALL Info('RadiationFactors','Geometry change requires recomputation of view factors')
         END IF
       END IF
     END IF
     
     DEALLOCATE(ActiveNodes)

     ! If the geometry has not changed and Gebhardt factors are fine return
     IF(.NOT. (FirstTime .OR. UpdateViewFactors .OR. UpdateGebhardtFactors)) THEN
       RETURN
     END IF     

!------------------------------------------------------------------------------
!    Check that the needed files exist if os assumed, if not recompute view factors
!------------------------------------------------------------------------------

     FilesExist = .TRUE.
     DO RadiationBody = 1, MaxRadiationBody 

       ViewFactorsFile = ListGetString(Model % Simulation,'View Factors',GotIt)
       
       IF ( .NOT.GotIt ) THEN
         ViewFactorsFile = 'ViewFactors.dat'
       END IF
       
       IF ( LEN_TRIM(Model % Mesh % Name) > 0 ) THEN
         OutputName = TRIM(OutputPath) // '/' // TRIM(Model % Mesh % Name) &
             // '/' // TRIM(ViewFactorsFile)
       ELSE
         OutputName = TRIM(ViewFactorsFile)
       END IF
       IF(RadiationBody > 1) THEN
         WRITE(OutputName,'(A,I1)') TRIM(OutputName),RadiationBody
       END IF
       INQUIRE(FILE=TRIM(OutputName),EXIST=GotIt)
       IF(.NOT. GotIt) FilesExist = .FALSE.
     END DO
     IF(.NOT. FilesExist) ComputeViewFactors = .TRUE.

!------------------------------------------------------------------------------
!    Rewrite the nodes for view factor computations if they have changed
!    and compute the ViewFactors with an external function call.
!------------------------------------------------------------------------------

     IF(ComputeViewFactors .OR. (.NOT. FirstTime .AND. UpdateViewFactors)) THEN
       
       ! This is a dirty thrick where the input file is stampered
       IF(.NOT. FirstTime) THEN
         CALL Info('RadiationFactors','Temporarely updating the mesh.nodes file!',LEVEL=4)

         OutputName = TRIM(OutputPath) // '/' // TRIM(Mesh % Name) // '/mesh.nodes'         
         OutputName2 = TRIM(OutputPath) // '/' // TRIM(Mesh % Name) // '/mesh.nodes.orig'         
         CALL Rename(OutputName, OutputName2)
         
         OPEN( 10,FILE=TRIM(OutputName), STATUS='unknown' )                 
         DO i=1,Mesh % NumberOfNodes
           WRITE( 10,'(i7,i3,f20.12,f20.12,f20.12)' ) i,-1,  &
               Mesh % Nodes % x(i), Mesh % Nodes % y(i), Mesh % Nodes % z(i)
         END DO
         CLOSE(10)
       END IF
       
       ! Compute the factors using an external program call
       CALL SystemCommand( 'ViewFactors' )
       
       ! Set back the original node coordinates to prevent unwanted user errors
       IF(.NOT. FirstTime) THEN
         OutputName = TRIM(OutputPath) // '/' // TRIM(Mesh % Name) // '/mesh.nodes'         
         OutputName2 = TRIM(OutputPath) // '/' // TRIM(Mesh % Name) // '/mesh.nodes.new'         
         CALL Rename(OutputName, OutputName2)
         
         OutputName = TRIM(OutputPath) // '/' // TRIM(Mesh % Name) // '/mesh.nodes.orig'         
         OutputName2 = TRIM(OutputPath) // '/' // TRIM(Mesh % Name) // '/mesh.nodes'         
         CALL Rename(OutputName, OutputName2)
       END IF
     END IF


!------------------------------------------------------------------------------
!    Load the different view factors
!------------------------------------------------------------------------------

     TopologyFixed = ListGetLogical( TSolver % Values, &
         'Matrix Topology Fixed',GotIt)

     MinFactor = ListGetConstReal( TSolver % Values, &
         'Minimum Gebhardt Factor',GotIt )
     IF(.NOT. GotIt) MinFactor = 1.0d-20
     
     SaveFactors = ListGetLogical( TSolver % Values, &
         'Save Gebhardt Factors',GotIt )
   
     MaxOmittedFactor = 0.0d0   
     TopologyTest = .TRUE.
     IF(FirstTime) TopologyTest = .FALSE. 

     RadiationBody = 0
     ALLOCATE( ElementNumbers(Model % NumberOfBoundaryElements), STAT=istat )
     IF ( istat /= 0 ) CALL Fatal('RadiationFactors','Memory allocation error 2.')

20   RadiationBody = RadiationBody + 1
     RadiationSurfaces = 0
     ElementNumbers = 0


     DO t=Model % NumberOfBulkElements+1, &
            Model % NumberOfBulkElements + Model % NumberOfBoundaryElements

       CurrentElement => Model % Elements(t)
       k = CurrentElement % BoundaryInfo % Constraint
       
       IF ( CurrentElement % TYPE % ElementCode /= 101 ) THEN
         DO i=1,Model % NumberOfBCs
           IF ( Model % BCs(i) % Tag == k ) THEN
             IF ( ListGetLogical( Model % BCs(i) % Values,'Heat Flux BC', GotIt) ) THEN
               RadiationFlag = ListGetString( Model % BCs(i) % Values, &
                   'Radiation', GotIt )

               IF ( RadiationFlag(1:12) == 'diffuse gray' ) THEN
                 
                 l = MAX(1, ListGetInteger( Model % BCs(i) % Values,'Radiation Boundary',GotIt) )
                 NodeIndexes =>  CurrentElement % NodeIndexes
                 n = CurrentElement % TYPE % NumberOfNodes

                 IF(l == RadiationBody) THEN
                   RadiationSurfaces = RadiationSurfaces + 1
                   ElementNumbers(RadiationSurfaces) = t
                 END IF

               END IF
             END IF
           END IF
         END DO
       END IF
     END DO

     IF(MaxRadiationBody > 1) THEN
       WRITE (Message,'(A,I9,A,I9)') 'Number of Radiation Surfaces',RadiationSurfaces,&
           ' for boundary',RadiationBody
       CALL Info('RadiationFactors',Message,LEVEL=4)
       IF(RadiationSurfaces == 0) GOTO 30
     END IF

     ALLOCATE( RowSpace( RadiationSurfaces ), Reorder( RadiationSurfaces ), &
         InvElementNumbers(Model % NumberOfBoundaryElements), STAT=istat )
     IF ( istat /= 0 ) CALL Fatal('RadiationFactors','Memory allocation error 3.')

     ! Make the inverse of the list of element numbers of boundaries
     InvElementNumbers = 0
     j0 = Model % NumberOfBulkElements
     DO i=1,RadiationSurfaces
       InvElementNumbers(ElementNumbers(i)-j0) = i
     END DO

     ! Open the file for ViewFactors
     IF(FirstTime .OR. UpdateViewFactors) THEN

       ViewFactorsFile = ListGetString(Model % Simulation,'View Factors',GotIt)
       
       IF ( .NOT.GotIt ) THEN
         ViewFactorsFile = 'ViewFactors.dat'
       END IF
       
       IF ( LEN_TRIM(Model % Mesh % Name) > 0 ) THEN
         OutputName = TRIM(OutputPath) // '/' // TRIM(Model % Mesh % Name) &
             // '/' // TRIM(ViewFactorsFile)
       ELSE
         OutputName = TRIM(ViewFactorsFile)
       END IF
       IF(RadiationBody > 1) THEN
         WRITE(OutputName,'(A,I1)') TRIM(OutputName),RadiationBody
       END IF

       INQUIRE(FILE=TRIM(OutputName),EXIST=GotIt)
       IF(.NOT. GotIt) THEN
         WRITE(Message,*) 'View Factors File does NOT exist:',TRIM(OutputName)
         CALL Info('RadiationFactors','Message')
         GOTO 30
       END IF

       OPEN( 10,File=TRIM(OutputName) )

       ! Read in the ViewFactors
       DO i=1,RadiationSurfaces
         READ( 10,* ) n

         CurrentElement => Model % Elements(ElementNumbers(i))
         ViewFactors => CurrentElement % BoundaryInfo % ViewFactors

         IF(FirstTime) THEN
           ViewFactors % NumberOfFactors = n
           ALLOCATE( ViewFactors % Elements(n) )
           ALLOCATE( ViewFactors % Factors(n) )
         ELSE IF(n /=  ViewFactors % NumberOfFactors) THEN
           DEALLOCATE( ViewFactors % Elements )
           DEALLOCATE( ViewFactors % Factors )
           ViewFactors % NumberOfFactors = n
           ALLOCATE( ViewFactors % Elements(n) )
           ALLOCATE( ViewFactors % Factors(n) )
         END IF

         Vals => ViewFactors % Factors
         Cols => ViewFactors % Elements
         
         DO j=1,n
           READ(10,*) t,Cols(j),Vals(j)         
           Cols(j) = ElementNumbers(Cols(j))
         END DO

       END DO
       CLOSE(10)
     END IF


     ! Check whether the element already sees itself, it will when 
     ! gebhardt factors are computed. Also compute matrix size.
     DO i=1,RadiationSurfaces
       
       CurrentElement => Model % Elements(ElementNumbers(i))
       ViewFactors => CurrentElement % BoundaryInfo % ViewFactors
       Cols => ViewFactors % Elements
       n = ViewFactors % NumberOfFactors
       Rowspace(i) = n
       
       k = 0
       DO j=1,n
         IF ( Cols(j) == ElementNumbers(i) ) THEN
           k = 1
           EXIT
         END IF
       END DO
       IF ( k == 0 ) THEN
         RowSpace(i) = RowSpace(i) + 1
       END IF
       
     END DO
     MatrixElements = SUM(RowSpace(1:RadiationSurfaces))

     ALLOCATE( RHS(RadiationSurfaces), SOL(RadiationSurfaces),&
         Fac(RadiationSurfaces), FacPerm(RadiationSurfaces), STAT=istat )
     IF ( istat /= 0 ) CALL Fatal('RadiationFactors','Memory allocation error 4.')

     ! The coefficient matrix 
     CALL Info('RadiationFactors','Computing factors...',LEVEL=4)

     IF(FullMatrix) THEN
       ALLOCATE(GFactorFull(RadiationSurfaces,RadiationSurfaces),STAT=istat)
       IF ( istat /= 0 ) CALL Fatal('RadiationFactors','Memory allocation error 5.')
       GFactorFull = 0.0d0
     ELSE 
       ! Assembly the matrix form
       DO i=1,RadiationSurfaces
         Reorder(i) = i
       END DO
       GFactorSP => CRS_CreateMatrix( RadiationSurfaces, &
           MatrixElements,RowSpace,1,Reorder,.TRUE. )

       DO t=1,RadiationSurfaces
         CurrentElement => Model % Elements(ElementNumbers(t))
         
         ViewFactors => CurrentElement % BoundaryInfo % ViewFactors
         
         Cols => ViewFactors % Elements
         
         DO j=1,ViewFactors % NumberOfFactors
           Colj = InvElementNumbers(Cols(j)-j0)
           CALL CRS_MakeMatrixIndex( GFactorSP,t,Colj )
         END DO
         
         CALL CRS_MakeMatrixIndex( GFactorSP,t,t )
       END DO

       CALL CRS_SortMatrix( GFactorSP )
       CALL CRS_ZeroMatrix( GFactorSP )
       MatrixEntries = SIZE(GFactorSP % Cols)
       WRITE(Message,'(A,T35,ES15.4)') 'View factors filling (%)',(100.0 * MatrixEntries) / &
           (RadiationSurfaces**2.0)
       CALL Info('RadiationFactors',Message,LEVEL=4)
     END IF

     MatrixEntries = 0
     ImplicitEntries = 0


     ! Fill the matrix for gebhardt factors
     DO t=1,RadiationSurfaces

       CurrentElement => Model % Elements(ElementNumbers(t))
       n = CurrentElement % TYPE % NumberOfNodes
       k = CurrentElement % BoundaryInfo % Constraint
       NodeIndexes => CurrentElement % NodeIndexes

       DO i=1,Model % NumberOfBCs
         IF ( Model % BCs(i) % Tag  == k ) THEN

           Emissivity = SUM( ListGetReal( Model % BCs(i) % Values, &
                    'Emissivity', n, NodeIndexes ) ) / n

           ViewFactors => CurrentElement % BoundaryInfo % ViewFactors
           Vals => ViewFactors % Factors
           Cols => ViewFactors % Elements

           DO j=1,ViewFactors % NumberOfFactors

             Colj = InvElementNumbers(Cols(j)-j0)

             IF(FullMatrix) THEN
               GFactorFull(t,Colj) = GFactorFull(t,Colj) - &
                   (1-Emissivity)*Vals(j)
             ELSE
               CALL CRS_AddToMatrixElement( GFactorSP,t,Colj, &
                   -(1-Emissivity)*Vals(j) )
             END IF
           END DO

           IF(FullMatrix) THEN
             GFactorFull(t,t) = GFactorFull(t,t) + 1.0D0
           ELSE
             CALL CRS_AddToMatrixElement( GFactorSP,t,t,1.0D0 )
           END IF

           EXIT
         END IF
       END DO
     END DO


     ALLOCATE( Solver )
     CALL InitFactorSolver(Solver)
     
     RHS = 0.0D0
     SOL = 1.0D-4

     MinSum = HUGE(MinSum)
     MaxSum = -HUGE(MaxSum)
          
     st = RealTime()
     
     DO t=1,RadiationSurfaces
       RHS    = 0.0D0
       RHS(t) = 1.0D0

       ! It may be a good initial start that the Gii is 
       ! the same as previously
       IF(t > 1) THEN
         PrevSelf = SOL(t)
         SOL(t) = SOL(t-1)
         SOL(t-1) = PrevSelf
       END IF

       IF(FullMatrix) THEN
         CALL FIterSolver( RadiationSurfaces, SOL, RHS, Solver )
       ELSE
         IF(ListGetLogical( TSolver % Values,'Gebhardt Factors Solver Iterative',GotIt)) THEN
           CALL IterSolver( GFactorSP, SOL, RHS, Solver )
         ELSE           
           IF(t == 1) THEN
             CALL ListAddLogical( Solver % Values, &
                 'umf factorize', .TRUE. )
           ELSE IF(t==2) THEN
             CALL ListAddLogical( Solver % Values, &
                 'umf factorize', .FALSE. )
           END IF
           CALL DirectSolver( GFactorSP, SOL, RHS, Solver )
         END IF
       END IF

       SolSum = SUM(SOL)
       MinSum = MIN(MinSum,SolSum)
       MaxSum = MAX(MaxSum,SolSum)

       CurrentElement => Model % Elements(ElementNumbers(t))
       n = CurrentElement % TYPE % NumberOfNodes
       NodeIndexes => CurrentElement % NodeIndexes
       
       k = CurrentElement % BoundaryInfo % Constraint
       DO j=1,Model % NumberOfBCs
         IF ( Model % BCs(j) % Tag == k ) THEN
           Emissivity = SUM(ListGetReal( Model % BCs(j) % Values, &
               'Emissivity', n, NodeIndexes)) / n
           EXIT
         END IF
       END DO
       
       n = 0
       DO i=1,RadiationSurfaces
         CurrentElement => Model % Elements(ElementNumbers(i))
         
         ViewFactors => CurrentElement % BoundaryInfo % ViewFactors
         Vals => ViewFactors % Factors
         Cols => ViewFactors % Elements
         
         s = 0.0d0
         DO k=1,ViewFactors % NumberOfFactors
           Colj = InvElementNumbers(Cols(k)-j0)
           s = s + Vals(k) * SOL(Colj)
         END DO
         Fac(i) = Emissivity * s
         IF ( Fac(i) > MinFactor ) THEN
           n = n + 1
         END IF
       END DO

       FactorSum = SUM(Fac)
       ConsideredSum = 0.0d0

       
       ImplicitLimit = ListGetConstReal( TSolver % Values, &
           'Implicit Gebhardt Factor Fraction', ImplicitLimitIs) 

       NeglectLimit = ListGetConstReal( TSolver % Values, &
           'Neglected Gebhardt Factor Fraction', GotIt) 
       IF(.NOT. GotIt) NeglectLimit = 1.0d-6
       
       IF(ImplicitLimitIs) THEN
         DO i=1,RadiationSurfaces
           FacPerm(i) = i
         END DO
         ! Ensure that the self vision is always implicit to avoid trouble in the future!
         Fac(t) = Fac(t) + FactorSum
         CALL SortR( RadiationSurfaces, FacPerm, Fac) 
         Fac(1) = Fac(1) - FactorSum        

         ConsideredSum = 0.0d0
         n = 0
         DO i=1,RadiationSurfaces
           IF(ConsideredSum < (1.0-NeglectLimit) * FactorSum) THEN
             ConsideredSum = ConsideredSum + Fac(i)
             n = i
           END IF           
         END DO
       ELSE
         n = 0
         DO i=1,RadiationSurfaces
           IF ( Fac(i) > MinFactor ) THEN
             n = n + 1
           END IF
         END DO
       END IF
       

       MatrixEntries = MatrixEntries + n
       CurrentElement => Model % Elements(ElementNumbers(t))
       GebhardtFactors => CurrentElement % BoundaryInfo % GebhardtFactors       


       IF(FirstTime) THEN
         GebhardtFactors % NumberOfFactors = n
         GebhardtFactors % NumberOfImplicitFactors = n
         ALLOCATE( GebhardtFactors % Elements(n), GebhardtFactors % Factors(n) )
       ELSE IF(ImplicitLimitIs) THEN 
         TopologyFixed = .FALSE.
         TopologyTest = .FALSE.
         DEALLOCATE( GebhardtFactors % Elements, GebhardtFactors % Factors )
         GebhardtFactors % NumberOfFactors = n
         ALLOCATE( GebhardtFactors % Elements(n), GebhardtFactors % Factors(n) )
         GebhardtFactors % NumberOfImplicitFactors = 0
       ELSE IF(GebhardtFactors % NumberOfFactors /= n .AND. .NOT. TopologyFixed) THEN         
         TopologyTest = .FALSE.
         DEALLOCATE( GebhardtFactors % Elements, GebhardtFactors % Factors )
         GebhardtFactors % NumberOfFactors = n
         ALLOCATE( GebhardtFactors % Elements(n), GebhardtFactors % Factors(n) )
         GebhardtFactors % NumberOfImplicitFactors = n
       END IF
       
       Vals => GebhardtFactors % Factors
       Cols => GebhardtFactors % Elements


       IF( ImplicitLimitIs ) THEN

         ImplicitSum = 0.0d0
         DO i=1,n
           Cols(i) = ElementNumbers(FacPerm(i)) 
           Vals(i) = Fac(i)

           IF(ImplicitSum < ImplicitLimit * FactorSum) THEN
             ImplicitSum = ImplicitSum + Fac(i)
             GebhardtFactors % NumberOfImplicitFactors = i
           END IF
         END DO
         Vals(2:n) = Vals(2:n) * (FactorSum - Vals(1)) / (ConsideredSum - Vals(1))

         IF(ImplicitLimit < TINY(ImplicitLimit)) GebhardtFactors % NumberOfImplicitFactors = 0       
         ImplicitEntries = ImplicitEntries + GebhardtFactors % NumberOfImplicitFactors

       ELSE IF(FirstTime .OR. .NOT. TopologyFixed) THEN
         n = 0
         DO i=1,RadiationSurfaces
           IF ( Fac(i) > MinFactor ) THEN
             n = n + 1
             IF(TopologyTest .AND. Cols(n) /= ElementNumbers(i)) TopologyTest = .FALSE.
             Cols(n) = ElementNumbers(i) 
             Vals(n) = Fac(i)
             ConsideredSum = ConsideredSum + Fac(i)
           END IF
         END DO
       ELSE
         ! If the topology is fixed the values are put only according to the existing structure
         ! and others are neglected
         n = GebhardtFactors % NumberOfFactors         
         Vals => GebhardtFactors % Factors
         Cols => GebhardtFactors % Elements
         
         DO i=1,n
           j = InvElementNumbers(Cols(i)-j0)
           Vals(i) = Fac(j)
           ConsideredSum = ConsideredSum + Fac(j)
         END DO
       END IF
       
       MaxOmittedFactor = MAX(MaxOmittedFactor,(FactorSum-ConsideredSum)/FactorSum) 
       
       IF(t < 10 .OR. MOD(t,RadiationSurfaces/20) == 0) THEN
         IF ( RealTime() - st > 1.0 ) THEN
           WRITE(Message,'(a,i3,a)' ) '   Solution: ', &
               INT((100.0*t)/RadiationSurfaces),' % done'
           CALL Info( 'RadiationFactors', Message, Level=5 )
           st = RealTime()
         END IF
       END IF

     END DO

     WRITE(Message,'(A,T35,ES15.4)') 'Minimum Gebhardt factors sum',MinSum
     CALL Info('RadiationFactors',Message,LEVEL=4)
     WRITE(Message,'(A,T35,ES15.4)') 'Maximum Gebhardt factors sum',MaxSum
     CALL Info('RadiationFactors',Message,LEVEL=4)
     WRITE(Message,'(A,T35,ES15.4)') 'Maximum share of omitted factors',MaxOmittedFactor
     CALL Info('RadiationFactors',Message,LEVEL=4)
     WRITE(Message,'(A,T35,ES15.4)') 'Gebhardt factors filling (%)',(100.0 * MatrixEntries) / &
         (RadiationSurfaces**2.0)
     CALL Info('RadiationFactors',Message,LEVEL=4)
     IF(ImplicitEntries > 0) THEN
       WRITE(Message,'(A,T35,ES15.4)') 'Implicit factors filling (%)',(100.0 * ImplicitEntries) / &
           (RadiationSurfaces**2.0)
       CALL Info('RadiationFactors',Message,LEVEL=4)
     END IF


     ! Save factors is mainly for debugging purposes
     IF(SaveFactors) THEN
       GebhardtFactorsFile = ListGetString(Model % Simulation, &
           'Gebhardt Factors',GotIt )
       
       IF ( .NOT.GotIt ) THEN
         GebhardtFactorsFile = 'GebhardtFactors.dat'
       END IF
       
       IF ( LEN_TRIM(Model % Mesh % Name) > 0 ) THEN
         OutputName = TRIM(OutputPath) // '/' // TRIM(Model % Mesh % Name) // &
             '/' // TRIM(GebhardtFactorsFile)
       ELSE
         OutputName = TRIM(GebhardtFactorsFile) 
       END IF

       IF(RadiationBody > 1) THEN
         WRITE(OutputName,'(A,I1)') TRIM(OutputName), RadiationBody
       END IF

       OPEN( 10,File=TRIM(OutputName) )
       
       WRITE (Message,'(A,A)') 'Writing Gephardt Factors to file: ',TRIM(OutputName)
       CALL Info('RadiationFactors',Message,LEVEL=4)
       
       WRITE( 10,* ) RadiationSurfaces
       
       DO t=1,RadiationSurfaces
         WRITE(10,*) t,ElementNumbers(t)
       END DO
       
       DO t=1,RadiationSurfaces
         CurrentElement => Model % Elements(ElementNumbers(t))
         GebhardtFactors => CurrentElement % BoundaryInfo % GebhardtFactors
         
         n = GebhardtFactors % NumberOfFactors 
         Vals => GebhardtFactors % Factors
         Cols => GebhardtFactors % Elements
         
         WRITE( 10,* ) n
         DO i=1,n
           WRITE(10,*) t,InvElementNumbers(Cols(i)-j0),Vals(i)
         END DO
       END DO
       
       CLOSE(10)
     END IF

     DEALLOCATE(Solver, InvElementNumbers,RowSpace,Reorder,RHS,SOL,Fac,FacPerm)
     IF(FullMatrix) THEN
       DEALLOCATE(GFactorFull)
     ELSE
       CALL FreeMatrix( GFactorSP )     
     END IF

     WRITE (Message,'(A,T35,ES15.4)') 'Gebhardt factors determined (s)',CPUTime()-at0
     CALL Info('RadiationFactors',Message)


30   IF(RadiationBody < MaxRadiationBody) GOTO 20
     
     DEALLOCATE(ElementNumbers) 


     IF(.NOT. (FirstTime .OR. TopologyTest .OR. TopologyFixed) ) THEN

       CALL Info('RadiationFactors','Reorganizing the matrix structure',LEVEL=4)

       MatrixFormat =  Tsolver % Matrix % FORMAT
       OptimizeBW = ListGetLogical(TSolver % Values,'Optimize Bandwidth',GotIt) 
       IF(.NOT. GotIt) OptimizeBW = .TRUE.

       CALL FreeMatrix( TSolver % Matrix)

       CALL Info('RadiationFactors','Creating new matrix topology')

       IF ( OptimizeBW ) THEN
         ALLOCATE( NewPerm( SIZE(Tsolver % Variable % Perm)) )
         TempPerm => Tsolver % Variable % Perm         
       ELSE
         NewPerm => Tsolver % Variable % Perm
       END IF

       AMatrix => CreateMatrix( CurrentModel,TSolver % Mesh, &
           NewPerm, 1, MatrixFormat, OptimizeBW, 'Heat Equation',.FALSE.)       
       
       ! Reorder the primary variable for bandwidth optimization:
       ! --------------------------------------------------------
       IF ( OptimizeBW ) THEN
         WHERE( NewPerm > 0 )
           TSolver % Variable % Values( NewPerm ) = &
               TSolver % Variable % Values( TempPerm )
         END WHERE
         
         IF ( ASSOCIATED( TSolver % Variable % PrevValues ) ) THEN
           DO j=1,SIZE( TSolver % Variable % PrevValues,2 )
             WHERE( NewPerm > 0 )
               TSolver % Variable % PrevValues( NewPerm,j) = &
                   TSolver % Variable % PrevValues(TempPerm,j)
             END WHERE
           END DO
         END IF
         Tsolver % Variable % Perm = NewPerm
         DEALLOCATE( NewPerm )
       END IF
       
       ! TODO: CreateMatrix should do these:
       ! -----------------------------------
       AMatrix % Lumped    = ListGetLogical( TSolver % Values, &
           'Lumped Mass Matrix', GotIt )
       AMatrix % Symmetric = ListGetLogical( TSolver % Values, &
           'Linear System Symmetric', GotIt )       
       
       n = AMatrix % NumberOFRows
       ALLOCATE( AMatrix % RHS(n) )

       ! Transient case additional allocations:
       ! --------------------------------------
       IF ( ListGetString( CurrentModel % Simulation,'Simulation Type' ) == 'transient' ) THEN
         ALLOCATE( Amatrix % Force(n, TSolver % TimeOrder+1) )
         Amatrix % Force = 0.0d0
         ALLOCATE( Amatrix % MassValues(n) )
         Amatrix % MassValues(:) = 1.0d0
       END IF

       TSolver % Matrix => Amatrix
       CALL ParallelInitMatrix( TSolver, AMatrix )
     END IF

     WRITE (Message,'(A,T35,ES15.4)') 'All done time (s)',CPUTime()-at0
     CALL Info('RadiationFactors',Message)
     CALL Info('RadiationFactors','----------------------------------------------------',LEVEL=4)
     
     
   CONTAINS

#include <huti_fdefs.h>
     SUBROUTINE FIterSolver( N,x,b,SolverParam )
  
       IMPLICIT NONE
       
       TYPE(Solver_t) :: SolverParam
       
       REAL (KIND=dp), DIMENSION(:) :: x,b
       REAL (KIND=dp) :: dpar(50)
       
       INTEGER :: ipar(50),wsize,N
       REAL (KIND=dp), ALLOCATABLE :: work(:,:)
       
       EXTERNAL RMatvec
       
       ipar = 0
       dpar = 0.0D0
       
       HUTI_WRKDIM = HUTI_CGS_WORKSIZE
       wsize = HUTI_WRKDIM
       
       HUTI_NDIM     = N
       HUTI_DBUGLVL  = 0
       HUTI_MAXIT    = 100
       
       ALLOCATE( work(wsize,N) )
       
       IF ( ALL(x == 0.0) ) THEN
         HUTI_INITIALX = HUTI_RANDOMX
       ELSE
         HUTI_INITIALX = HUTI_USERSUPPLIEDX
       END IF
       
       HUTI_TOLERANCE = 1.0d-10
       
       CALL huti_d_cgs( x,b,ipar,dpar,work,Rmatvec,0,0,0,0,0 )
       
       DEALLOCATE( work )
       
     END SUBROUTINE FIterSolver
     

     SUBROUTINE InitFactorSolver(Solver)
       
       TYPE(Solver_t) :: Solver
       
       NULLIFY( Solver % Values )
       
       CALL ListAddString( Solver % Values, &
           'Linear System Iterative Method', 'CGS' )

       CALL ListAddString( Solver % Values, &
           'Linear System Direct Method', 'umfpack' )

       CALL ListAddInteger( Solver % Values, &
           'Linear System Max Iterations', 100 )
       
       CALL ListAddConstReal( Solver % Values, &
           'Linear System Convergence Tolerance', 1.0D-9 )
       
       CALL ListAddString( Solver % Values, &
           'Linear System Preconditioning', 'None' )
       
       CALL ListAddInteger( Solver % Values, &
           'Linear System Residual Output', 0 )
       
     END SUBROUTINE InitFactorSolver

   END SUBROUTINE RadiationFactors


   SUBROUTINE RMatvec( u,v,ipar )
     
     USE RadiationFactorGlobals
     
     REAL (KIND=dp) :: u(*),v(*)
     INTEGER :: ipar(*)
     
     INTEGER :: i,j,n
     REAL (KIND=dp) :: s
     
     n = HUTI_NDIM
     
     DO i=1,n
       s = 0.0D0
       DO j=1,n
         s = s + GFactorFull(i,j) * u(j)
       END DO
       v(i) = s
     END DO
     
   END SUBROUTINE RMatvec
