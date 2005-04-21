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
! *                Modified by:      Leila Puska, Antti Pursula, Peter R�back
! *
! *       Date of modification:      20 Jun 2002
! *
! *****************************************************************************/
    
!------------------------------------------------------------------------------
    SUBROUTINE StatElecSolver( Model,Solver,dt,TransientSimulation )
!DEC$ATTRIBUTES DLLEXPORT :: StatElecSolver
!------------------------------------------------------------------------------
!******************************************************************************
!
!  Solve the Poisson equation for the electric potential and compute the 
!  electric field, flux, energy and capacitance
!
!  NOTE: The permittivity of vacuum is divided into the right hand side of the 
!        equation. This has to be accounted for in setting the body forces and
!        assigning flux boundary conditions
!
!
!  ARGUMENTS:
!
!  TYPE(Model_t) :: Model,  
!     INPUT: All model information (mesh, materials, BCs, etc...)
!
!  TYPE(Solver_t) :: Solver
!     INPUT: Linear equation solver options
!
!  DOUBLE PRECISION :: dt,
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

     USE Differentials
 
     USE SolverUtils
     USE ElementUtils

     USE Adaptive
     USE DefUtils

     IMPLICIT NONE
!------------------------------------------------------------------------------
 
     TYPE(Model_t) :: Model
     TYPE(Solver_t), TARGET:: Solver
 
     REAL (KIND=DP) :: dt
     LOGICAL :: TransientSimulation
 
!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------
     TYPE(Matrix_t), POINTER  :: StiffMatrix
     TYPE(Element_t), POINTER :: CurrentElement
     TYPE(Solver_t), POINTER :: PSolver 
     TYPE(Variable_t), POINTER :: TimeVar, Var
     TYPE(Nodes_t) :: ElementNodes

     REAL (KIND=DP), POINTER :: ForceVector(:), Potential(:), Displacement(:,:)
     REAL (KIND=DP), POINTER :: FieldOne(:), FieldTwo(:), FieldThree(:)
     REAL (KIND=DP), POINTER :: FieldOneTemp(:), FieldTwoTemp(:), FieldThreeTemp(:)
     REAL (KIND=DP), POINTER :: FluxOne(:), FluxTwo(:), FluxThree(:)
     REAL (KIND=DP), POINTER :: FluxOneTemp(:), FluxTwoTemp(:), FluxThreeTemp(:)
     REAL (KIND=DP), POINTER :: Ex(:), Ey(:), Ez(:), Dx(:), Dy(:), Dz(:)
     REAL (KIND=DP), POINTER :: We(:), WeTemp(:), Energy(:)
     REAL (KIND=DP), POINTER :: Pwrk(:,:,:)
     REAL (KIND=DP), ALLOCATABLE :: CapB(:), CapX(:), CapA(:,:), CapMatrix(:,:)
     REAL (KIND=DP), ALLOCATABLE ::  Permittivity(:,:,:), PiezoCoeff(:,:,:), &
       LocalStiffMatrix(:,:), Load(:), LocalForce(:), PotDiff(:)

     REAL(KIND=dp) :: Alpha, Beta, LayerH, Voltage, NominalPD, RelPerm1, RelPerm2
     REAL(KIND=dp) :: PermittivityOfVacuum

     REAL (KIND=DP) :: Norm, Wetot, at0, RealTime
     REAL (KIND=DP) :: at, st, CPUTime, PotentialDifference, Capacitance
     REAL (KIND=DP) :: CoEnergy, MinCoEnergy, MinPotential, MaxPotential

     INTEGER, POINTER :: NodeIndexes(:)
     INTEGER, POINTER :: PotentialPerm(:), EnergyPerm(:)
     INTEGER, POINTER :: FieldPermOne(:), FieldPermTwo(:), FieldPermThree(:)
     INTEGER, POINTER :: FluxPermOne(:), FluxPermTwo(:), FluxPermThree(:)
     INTEGER :: CapBodies, CapBody, CapNo, CapPerms, Permi, Permj
     INTEGER :: i, j, k, n, t, istat, bf_id, LocalNodes, DIM
 
     LOGICAL :: AllocationsDone = .FALSE., gotIt
     LOGICAL :: CalculateField, CalculateFlux, CalculateEnergy 
     LOGICAL :: CalculateCapMatrix, ConstantWeights
     LOGICAL :: PiezoMaterial

     CHARACTER(LEN=MAX_NAME_LEN) :: EquationName, CapMatrixFile, Name
     CHARACTER(LEN=MAX_NAME_LEN) :: VersionID = "$Id: StatElecSolve.f90,v 1.45 2005/04/13 11:43:50 apursula Exp $"


     SAVE LocalStiffMatrix, Load, LocalForce, Pwrk, PotDiff, &
          ElementNodes, CalculateFlux, CalculateEnergy, &
          AllocationsDone, FieldOne, FieldTwo, FieldThree, &
          FluxOne, FluxTwo, FluxThree, We, Permittivity, &
          CapBodies, CalculateCapMatrix, CapA, CapB, CapX, CapPerms, &
          CapMatrix, CalculateField, CapMatrixFile, ConstantWeights, &
          PiezoCoeff, PiezoMaterial, Displacement


     INTERFACE
        FUNCTION ElectricBoundaryResidual( Model,Edge,Mesh,Quant,Perm,Gnorm ) RESULT(Indicator)
          USE Types
          TYPE(Element_t), POINTER :: Edge
          TYPE(Model_t) :: Model
          TYPE(Mesh_t), POINTER :: Mesh
          REAL(KIND=dp) :: Quant(:), Indicator(2), Gnorm
          INTEGER :: Perm(:)
        END FUNCTION ElectricBoundaryResidual

        FUNCTION ElectricEdgeResidual( Model,Edge,Mesh,Quant,Perm ) RESULT(Indicator)
          USE Types
          TYPE(Element_t), POINTER :: Edge
          TYPE(Model_t) :: Model
          TYPE(Mesh_t), POINTER :: Mesh
          REAL(KIND=dp) :: Quant(:), Indicator(2)
          INTEGER :: Perm(:)
        END FUNCTION ElectricEdgeResidual

        FUNCTION ElectricInsideResidual( Model,Element,Mesh,Quant,Perm, Fnorm ) RESULT(Indicator)
          USE Types
          TYPE(Element_t), POINTER :: Element
          TYPE(Model_t) :: Model
          TYPE(Mesh_t), POINTER :: Mesh
          REAL(KIND=dp) :: Quant(:), Indicator(2), Fnorm
          INTEGER :: Perm(:)
        END FUNCTION ElectricInsideResidual
     END INTERFACE

!------------------------------------------------------------------------------
 
!------------------------------------------------------------------------------
!    Check if version number output is requested
!------------------------------------------------------------------------------
     IF ( .NOT. AllocationsDone ) THEN
       IF ( ListGetLogical( GetSimulation(), 'Output Version Numbers', GotIt ) ) THEN
         CALL Info( 'StatElecSolve', 'StatElecSolve version:', Level = 0 ) 
         CALL Info( 'StatElecSolve', VersionID, Level = 0 ) 
         CALL Info( 'StatElecSolve', ' ', Level = 0 ) 
       END IF
     END IF

!------------------------------------------------------------------------------
!    Get variables needed for solution
!------------------------------------------------------------------------------
     Potential     => Solver % Variable % Values
     PotentialPerm => Solver % Variable % Perm
 
     StiffMatrix => Solver % Matrix
     ForceVector => StiffMatrix % RHS

     Norm = Solver % Variable % Norm
     DIM = CoordinateSystemDimension()

!------------------------------------------------------------------------------
!    Allocate some permanent storage, this is done first time only
!------------------------------------------------------------------------------
     IF ( .NOT. AllocationsDone ) THEN
       N = Model % MaxElementNodes
 
       ALLOCATE( ElementNodes % x(N),   &
                 ElementNodes % y(N),   &
                 ElementNodes % z(N),   &
                 Permittivity(3,3,N),       &
                 LocalForce(N),         &
                 LocalStiffMatrix(N,N), &
                 Load(N),               &
                 PotDiff(N),            &
                 Displacement(N,Dim),            &
                 STAT=istat )
 
       IF ( istat /= 0 ) THEN
         CALL Fatal( 'StatElecSolve', 'Memory allocation error 1' )
       END IF
 
       IF ( DIM == 2 ) THEN
          ALLOCATE( PiezoCoeff(2,4,N), STAT=istat )
          IF ( istat /= 0 ) THEN
             CALL Fatal( 'StatElecSolve', 'Memory allocation error 1a' )
          END IF
       ELSE
          ALLOCATE( PiezoCoeff(3,6,N), STAT=istat )
          IF ( istat /= 0 ) THEN
             CALL Fatal( 'StatElecSolve', 'Memory allocation error 1b' )
          END IF
       END IF

       CalculateField = ListGetLogical( Solver % Values, &
           'Calculate Electric Field', GotIt )
       IF ( .NOT. GotIt )  CalculateField = .TRUE.
       IF ( CalculateField )  &
           ALLOCATE( FieldOneTemp( Model % NumberOfNodes ), &
                     FieldTwoTemp( Model % NumberOfNodes ), &
                     FieldThreeTemp( Model % NumberOfNodes ), &
                     STAT=istat )
       IF ( istat /= 0 ) THEN
         CALL Fatal( 'StatElecSolve', 'Memory allocation error 2' )
       END IF

       CalculateFlux = ListGetLogical( Solver % Values, &
           'Calculate Electric Flux', GotIt )
       IF ( .NOT. GotIt )  CalculateFlux = .TRUE.
       IF ( CalculateFlux )  &
            ALLOCATE( FluxOneTemp( Model % NumberOfNodes ), &
                      FluxTwoTemp( Model % NumberOfNodes ), &
                      FluxThreeTemp( Model % NumberOfNodes ), &
                      STAT=istat )
      IF ( istat /= 0 ) THEN
         CALL Fatal( 'StatElecSolve', 'Memory allocation error 3' )
       END IF

       DO i = 1, Model % NumberOfEquations
         CalculateEnergy = ListGetLogical( Model % Equations(i) % Values, &
             'Calculate Electric Energy', GotIt )
         IF ( GotIt ) EXIT
       END DO
       IF ( .NOT. GotIt )  CalculateEnergy = ListGetLogical( Solver % Values, &
           'Calculate Electric Energy', GotIt )
       IF ( CalculateEnergy )  &
           ALLOCATE( WeTemp( Model%NumberOfNodes ), STAT=istat )
       IF ( istat /= 0 ) THEN
         CALL Fatal( 'StatElecSolve', 'Memory allocation error 4' )
       END IF

       DO i = 1, Model % NumberOfEquations 
         CalculateCapMatrix = ListGetLogical( Model % Equations(i) % Values, &
             'Calculate Capacitance Matrix', GotIt )
         IF ( GotIt ) EXIT
       END DO
       IF ( .NOT. GotIt )  CalculateCapMatrix = ListGetLogical( Solver % Values, &
           'Calculate Capacitance Matrix', GotIt )

       ConstantWeights = ListGetLogical( Solver % Values, &
           'Constant Weights', GotIt )

       IF(CalculateCapMatrix) THEN
         CapBodies = ListGetInteger( Solver % Values, 'Capacitance Bodies')
         MinCoEnergy = ListGetConstReal( Solver % Values,'Minimum CoEnergy',gotIt)
         IF(.NOT. gotIt) MinCoEnergy = 1.0d-10
         CapMatrixFile = ListGetString(Solver % Values,'Capacitance Matrix Filename',GotIt )
         IF(.NOT. GotIt) CapMatrixFile = 'cmatrix.dat'

         CapPerms = CapBodies*(CapBodies+1)/2
         ALLOCATE( CapA(CapPerms,CapPerms), CapB(CapPerms), CapX(CapPerms), &
             CapMatrix(CapBodies,CapBodies),STAT=istat)
         IF ( istat /= 0 ) THEN
           CALL Fatal( 'StatElecSolve', 'Memory allocation error 5' )
         END IF
         CapA = 0.0d0
         CapB = 0.0d0
         CapX = 0.0d0
       END IF
         
!------------------------------------------------------------------------------

       IF ( .NOT.ASSOCIATED( StiffMatrix % MassValues ) ) THEN
         ALLOCATE( StiffMatrix % Massvalues( Model % NumberOfNodes ) )
         StiffMatrix % MassValues = 0.0d0
       END IF

!------------------------------------------------------------------------------
!      Add electric field to the variable list
!------------------------------------------------------------------------------
       PSolver => Solver
       IF(CalculateField) THEN         
         Ex => FieldOneTemp
         CALL VariableAdd( Solver % Mesh % Variables, Solver % Mesh, PSolver, &
               'Electric Field 1', 1, Ex, PotentialPerm)
           
         Ey => FieldTwoTemp
         CALL VariableAdd( Solver % Mesh % Variables, Solver % Mesh, PSolver, &
             'Electric Field 2', 1, Ey, PotentialPerm)
         
         IF(DIM == 3) THEN
           Ez => FieldThreeTemp
           CALL VariableAdd( Solver % Mesh % Variables, Solver % Mesh, PSolver, &
               'Electric Field 3', 1, Ez, PotentialPerm)
         END IF
       END IF
       
!------------------------------------------------------------------------------
!      Add electric flux to the variable list
!------------------------------------------------------------------------------

       IF ( CalculateFlux ) THEN
          Dx => FluxOneTemp
          CALL VariableAdd( Solver % Mesh % Variables, Solver % Mesh, &
               PSolver, 'Electric Flux 1', 1, Dx, PotentialPerm)

          Dy => FluxTwoTemp
          CALL VariableAdd( Solver % Mesh % Variables, Solver % Mesh, &
               PSolver, 'Electric Flux 2', 1, Dy, PotentialPerm)

          IF(DIM == 3) THEN
            Dz => FluxThreeTemp
            CALL VariableAdd( Solver % Mesh % Variables, Solver % Mesh, &
                PSolver, 'Electric Flux 3', 1, Dz, PotentialPerm)
          END IF
       END IF
          
       IF ( CalculateEnergy ) THEN
          WeTemp = 0.0d0
          Energy => WeTemp(:)
          CALL VariableAdd( Solver % Mesh % Variables, Solver % Mesh, &
               PSolver, 'Electric Energy Density', 1, Energy, PotentialPerm )
       END IF

       NULLIFY( Pwrk )
   
       AllocationsDone = .TRUE.
     END IF

!---------------------------------------------------------------------------------
!    Update arrays for derived vars. Rather cumbersome due to possible adaptivity
!---------------------------------------------------------------------------------

     IF ( CalculateEnergy ) THEN
        Var => VariableGet( Model % Variables, 'Electric Energy Density' )
        We => Var % Values
        EnergyPerm => Var % Perm
        We = 0.0d0
     END IF

     IF ( CalculateField ) THEN
        Var => VariableGet( Model % Variables, 'Electric Field 1' )
        FieldOne => Var % Values
        FieldPermOne => Var % Perm
        FieldOne = 0.0d0

        Var => VariableGet( Model % Variables, 'Electric Field 2' )
        FieldTwo => Var % Values
        FieldPermTwo => Var % Perm
        FieldTwo = 0.0d0

        IF ( DIM == 3 ) THEN
           Var => VariableGet( Model % Variables, 'Electric Field 3' )
           FieldThree => Var % Values
           FieldPermThree => Var % Perm
           FieldThree = 0.0d0
        END IF

     END IF

     IF ( CalculateFlux ) THEN
        Var => VariableGet( Model % Variables, 'Electric Flux 1' )
        FluxOne => Var % Values
        FluxPermOne => Var % Perm
        FluxOne = 0.0d0

        Var => VariableGet( Model % Variables, 'Electric Flux 2' )
        FluxTwo => Var % Values
        FluxPermTwo => Var % Perm
        FluxTwo = 0.0d0

        IF ( DIM == 3 ) THEN
           Var => VariableGet( Model % Variables, 'Electric Flux 3' )
           FluxThree => Var % Values
           FluxPermThree => Var % Perm
           FluxThree = 0.0d0
        END IF

     END IF

!------------------------------------------------------------------------------
!    Do some additional initialization, and go for it
!------------------------------------------------------------------------------

     NominalPD = -1.0d0

     PermittivityOfVacuum = ListGetConstReal( Model % Constants, &
          'Permittivity Of Vacuum',gotIt )
     IF ( .NOT.gotIt ) PermittivityOfVacuum = 1.0d0

     IF(CalculateCapMatrix) THEN
        TimeVar => VariableGet( Model % Variables, 'Time' )
        CapNo = NINT( TimeVar % Values(1) )
     END IF
     
     EquationName = ListGetString( Solver % Values, 'Equation' )
     
     at  = CPUTime()
     at0 = RealTime()
     CALL InitializeToZero( StiffMatrix, ForceVector )
!------------------------------------------------------------------------------
     CALL Info( 'StatElecSolve', '-------------------------------------',Level=4 )
     CALL Info( 'StatElecSolve', 'STATELEC SOLVER:  ', Level=4 )
     CALL Info( 'StatElecSolve', '-------------------------------------',Level=4 )
     CALL Info( 'StatElecSolve', 'Starting Assembly...', Level=4 )

!------------------------------------------------------------------------------
!    Do the assembly
!------------------------------------------------------------------------------
     DO t = 1, Solver % Mesh % NumberOfBulkElements

        IF ( RealTime() - at0 > 1.0 ) THEN
           WRITE(Message,'(a,i3,a)' ) '   Assembly: ', INT(100.0 - 100.0 * &
            (Solver % Mesh % NumberOfBulkElements-t) / &
               (1.0*Solver % Mesh % NumberOfBulkElements)), ' % done'
                       
           CALL Info( 'StatElecSolve', Message, Level=5 )

           at0 = RealTime()
        END IF

!------------------------------------------------------------------------------
!        Check if this element belongs to a body where potential
!        should be calculated
!------------------------------------------------------------------------------
       CurrentElement => Solver % Mesh % Elements(t)
       NodeIndexes => CurrentElement % NodeIndexes

       IF ( .NOT.CheckElementEquation( Model, CurrentElement, &
                 EquationName  ) ) CYCLE

       n = CurrentElement % TYPE % NumberOfNodes
 
       ElementNodes % x(1:n) = Solver % Mesh % Nodes % x(NodeIndexes)
       ElementNodes % y(1:n) = Solver % Mesh % Nodes % y(NodeIndexes)
       ElementNodes % z(1:n) = Solver % Mesh % Nodes % z(NodeIndexes)
!------------------------------------------------------------------------------

       bf_id = ListGetInteger( Model % Bodies(CurrentElement % BodyId) % &
               Values, 'Body Force',gotIt, minv=1, maxv=Model % NumberOfBodyForces )

       Load  = 0.0d0
       PiezoMaterial = .FALSE.
       IF ( gotIt ) THEN
          Load(1:n) = ListGetReal( Model % BodyForces(bf_id) % Values, &
               'Source',n,NodeIndexes, gotIt )
          IF ( .NOT. gotIt )  Load(1:n) = &
               ListGetReal( Model % BodyForces(bf_id) % Values, &
               'Charge Density', n, NodeIndexes, GotIt )

          Load(1:n) = Load(1:n) / PermittivityOfVacuum

          IF ( GetLogical( Model % BodyForces(bf_id) % Values, 'Piezo Material', &
               GotIt ) )  PiezoMaterial = .TRUE.
       END IF

       k = ListGetInteger( Model % Bodies(CurrentElement % BodyId) % &
            Values, 'Material', minv=1, maxv=Model % NumberOfMaterials )

!------------------------------------------------------------------------------
!      Read permittivity values (might be a tensor)
!------------------------------------------------------------------------------

       CALL ListGetRealArray( Model % Materials(k) % Values, &
            'Relative Permittivity', Pwrk,n,NodeIndexes, gotIt )
       IF ( .NOT. gotIt ) &
            CALL ListGetRealArray( Model % Materials(k) % Values, &
            'Permittivity', Pwrk, n, NodeIndexes, gotIt )

       IF ( .NOT. gotIt ) CALL Fatal( 'StatElecSolve', &
            'No relative permittivity found' )
       
       Permittivity = 0.0d0
       IF ( SIZE(Pwrk,1) == 1 ) THEN
          DO i=1,3
             Permittivity( i,i,1:n ) = Pwrk( 1,1,1:n )
          END DO
       ELSE IF ( SIZE(Pwrk,2) == 1 ) THEN
          DO i=1,MIN(3,SIZE(Pwrk,1))
             Permittivity(i,i,1:n) = Pwrk(i,1,1:n)
          END DO
       ELSE
          DO i=1,MIN(3,SIZE(Pwrk,1))
             DO j=1,MIN(3,SIZE(Pwrk,2))
                Permittivity( i,j,1:n ) = Pwrk(i,j,1:n)
             END DO
          END DO
       END IF

!------------------------------------------------------------------------------
!      Read piezo material coefficients if applicable
!------------------------------------------------------------------------------
       PiezoCoeff = 0.0d0
       Displacement = 0.0d0
       IF ( PiezoMaterial ) THEN
          PiezoCoeff = 0.0d0
          CALL GetRealArray( Model % Materials(k) % Values, Pwrk, &
               'Piezo Material Coefficients', gotIt, CurrentElement )
          IF ( .NOT. GotIt )  CALL Fatal( 'StatElecSolve', &
               'No Piezo Material Coefficients defined' )

          DO i=1, Dim
             DO j=1, 2*Dim
                PiezoCoeff( i,j,1:n ) = Pwrk(i,j,1:n)
             END DO
          END DO
!------------------------------------------------------------------------------
!      Read also the local displacement
!------------------------------------------------------------------------------

          NULLIFY (Var)
          Var => VariableGet( Model % Variables, 'Displacement' )
          IF ( .NOT. ASSOCIATED( Var ) )  CALL Fatal('StatElecSolve', &
               'No displacements' )

          DO i = 1, Var % DOFs
             Displacement(1:n,i) = &
                  Var % Values( Var % DOFs * ( Var % Perm( NodeIndexes ) - 1 ) + i )
          END DO
       END IF

!------------------------------------------------------------------------------
!      Get element local matrix, and rhs vector
!------------------------------------------------------------------------------
       CALL StatElecCompose( LocalStiffMatrix,LocalForce, PiezoMaterial, &
            PiezoCoeff, Permittivity,Load,CurrentElement,n,ElementNodes, &
            Displacement )
!------------------------------------------------------------------------------
!      Update global matrix and rhs vector from local matrix & vector
!------------------------------------------------------------------------------
       CALL UpdateGlobalEquations( StiffMatrix,LocalStiffMatrix, &
            ForceVector, LocalForce,n,1,PotentialPerm(NodeIndexes) )
!------------------------------------------------------------------------------
    END DO

!------------------------------------------------------------------------------
!     Neumann boundary conditions
!------------------------------------------------------------------------------
      DO t=Solver % Mesh % NumberOfBulkElements + 1, &
         Solver % Mesh % NumberOfBulkElements + &
         Solver % Mesh % NumberOfBoundaryElements

        CurrentElement => Solver % Mesh % Elements(t)
!------------------------------------------------------------------------------
!       the element type 101 (point element) can only be used
!       to set Dirichlet BCs, so skip em.
!------------------------------------------------------------------------------
        IF ( CurrentElement % TYPE % ElementCode == 101 ) CYCLE
!------------------------------------------------------------------------------
        DO i=1,Model % NumberOfBCs
          IF ( CurrentElement % BoundaryInfo % Constraint == &
                 Model % BCs(i) % Tag ) THEN

            IF ( .NOT. ListGetLogical(Model % BCs(i) % Values, &
                 'Electric Flux BC',gotIt) ) CYCLE
!------------------------------------------------------------------------------
!             Set the current element pointer in the model structure to
!             reflect the element being processed
!------------------------------------------------------------------------------
              Model % CurrentElement => Solver % Mesh % Elements(t)
!------------------------------------------------------------------------------
              n = CurrentElement % TYPE % NumberOfNodes
              NodeIndexes => CurrentElement % NodeIndexes
              IF ( ANY( PotentialPerm(NodeIndexes) <= 0 ) ) CYCLE

              ElementNodes % x(1:n) = Solver % Mesh % Nodes % x(NodeIndexes)
              ElementNodes % y(1:n) = Solver % Mesh % Nodes % y(NodeIndexes)
              ElementNodes % z(1:n) = Solver % Mesh % Nodes % z(NodeIndexes)

              Load = 0.0d0
!------------------------------------------------------------------------------
!             BC: epsilon@Phi/@n = g
!------------------------------------------------------------------------------
              Load(1:n) = Load(1:n) + &
                ListGetReal( Model % BCs(i) % Values,'Electric Flux', &
                          n,NodeIndexes,gotIt )
              IF ( .NOT. gotit )  Load(1:n) = Load(1:n) + &
                   ListGetReal( Model % BCs(i) % Values, &
                   'Surface Charge Density', n,NodeIndexes,gotIt )
              Load(1:n) = Load(1:n) / PermittivityOfVacuum

!------------------------------------------------------------------------------
!             BC: -epsilon@Phi/@n = -alpha Phi + beta
!------------------------------------------------------------------------------
              Alpha = 0.0d0
              Beta = 0.0d0

              NominalPD = GetConstReal( Model % BCs(i) % Values, &
                   'Nominal Potential Difference', gotit )
              IF ( .NOT. Gotit )  NominalPD = -1.0d0

              Alpha = GetConstReal( Model % BCs(i) % Values, & 
                   'Layer Relative Permittivity', gotit )
              IF ( Gotit ) THEN
                LayerH = GetConstReal( Model % BCs(i) % Values, &
                      'Layer Thickness', gotit )
                 IF ( (.NOT. gotit) .OR. LayerH < 1e-12 ) THEN
                    CALL Warn( 'StatElecSolve', &
                         'Charge layer thickness not given or too small. Using 1e-8 m')
                    LayerH = 1e-8
                 END IF
                 Alpha = Alpha / LayerH

                 Voltage = GetConstReal( Model % BCs(i) % Values, &
                      'Electrode Potential', gotit )
                 Beta = GetConstReal( Model % BCs(i) % Values, &
                      'Layer Charge Density', gotit )
                 Beta = Alpha*Voltage + 0.5d0*Beta*LayerH / PermittivityOfVacuum

              END IF

!------------------------------------------------------------------------------
!             Get element matrix and rhs due to boundary conditions ...
!------------------------------------------------------------------------------
              CALL StatElecBoundary( LocalStiffMatrix, LocalForce,  &
                  Load, Alpha, Beta, CurrentElement, n, ElementNodes )
!------------------------------------------------------------------------------
!             Update global matrices from local matrices
!------------------------------------------------------------------------------
              CALL UpdateGlobalEquations( StiffMatrix, LocalStiffMatrix, &
                ForceVector, LocalForce, n, 1, PotentialPerm(NodeIndexes) )
!------------------------------------------------------------------------------
           END IF ! of currentelement bc == bcs(i)
        END DO ! of i=1,model bcs
      END DO   ! Neumann BCs
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
!    FinishAssembly must be called after all other assembly steps, but before
!    Dirichlet boundary settings. Actually no need to call it except for
!    transient simulations.
!------------------------------------------------------------------------------
     CALL FinishAssembly( Solver,ForceVector )
!------------------------------------------------------------------------------
!    Dirichlet boundary conditions
!------------------------------------------------------------------------------
     CALL SetDirichletBoundaries( Model,StiffMatrix,ForceVector, &
               Solver % Variable % Name,1,1,PotentialPerm )

     IF(CalculateCapMatrix) THEN 
       CALL SetPermutationBoundaries( Model, StiffMatrix, ForceVector, &
           'Capacitance Body',1,1,PotentialPerm, CapNo, CapBodies )
     END IF

     at = CPUTime() - at
     WRITE( Message, * ) 'Assembly (s)          :',at
     CALL Info( 'StatElecSolve', Message, Level=4 )
!------------------------------------------------------------------------------
!    Solve the system and we are done.
!------------------------------------------------------------------------------
     st = CPUTime()
     CALL SolveSystem( StiffMatrix, ParMatrix, ForceVector, &
                  Potential, Norm, 1, Solver )
     st = CPUTime() - st
     WRITE( Message, * ) 'Solve (s)             :',st
     CALL Info( 'StatElecSolve', Message, Level=4 )

!------------------------------------------------------------------------------
!    Compute the electric field from the potential: E = -grad Phi
!------------------------------------------------------------------------------
!------------------------------------------------------------------------------
!    Compute the electric flux: D = epsilon (-grad Phi)
!------------------------------------------------------------------------------
!------------------------------------------------------------------------------
!    Compute the total electric energy: W_e,tot = Integral (E . D)dV
!------------------------------------------------------------------------------

     IF ( CalculateField .OR. CalculateFlux .OR. CalculateEnergy .OR. CalculateCapMatrix) THEN 
       CALL GeneralElectricFlux( Model, Potential, PotentialPerm )
     END IF

     IF ( CalculateEnergy ) THEN
       WRITE( Message, * ) 'Tot. Electric Energy  :', Wetot
       CALL Info( 'StatElecSolve', Message, Level=4 )
       CALL ListAddConstReal( Model % Simulation, &
           'RES: Electric Energy', Wetot )
     END IF

!------------------------------------------------------------------------------
!    Try to find a potential difference for scalar capacitance calculation
!------------------------------------------------------------------------------

     IF ( .NOT. CalculateCapMatrix ) THEN

       PotentialDifference = ListGetConstReal( Solver % Values, &
           'Potential Difference',gotIt )
       IF ( .NOT.gotIt )  PotentialDifference = ListGetConstReal( &
           Model % Simulation, 'Potential Difference',gotIt )
       IF ( .NOT. gotIt ) THEN
         DO i = 1, Model % NumberOfMaterials
           PotentialDifference = &
               ListGetConstReal( Model % Materials(i) % Values, &
               'Potential Difference', GotIt )
           IF ( GotIt )  EXIT
         END DO
       END IF

       IF(.NOT. GotIt) THEN
         MinPotential = HUGE(MinPotential)
         MaxPotential = -HUGE(MaxPotential)

         DO i = 1, Model % NumberOfNodes
           j = PotentialPerm(i)
           IF( j > 0) THEN
             MinPotential = MIN(MinPotential, Potential(j))
             MaxPotential = MAX(MaxPotential, Potential(j))             
           END IF
         END DO
           
         PotentialDifference = MaxPotential - MinPotential
       END IF

       IF(PotentialDifference > TINY(PotentialDifference)) THEN

         IF ( NominalPD > 0.0 ) THEN

            WRITE( Message,* ) 'Nominal potential difference :',NominalPD
            CALL Info( 'StatElecSolve', Message, Level=8 )
            WRITE( Message,* ) 'True potential difference    :',PotentialDifference
            CALL Info( 'StatElecSolve', Message, Level=8 )
         
            Capacitance = 2*Wetot / ( NominalPD * NominalPD )
            WRITE( Message, * ) 'Effective capacitance        :', Capacitance
            CALL Info( 'StatElecSolve', Message, Level=4 )

            CALL ListAddConstReal( Model % Simulation, &
                 'RES: Capacitance', Capacitance )
!            CALL ListAddConstReal( Model % Simulation, &
!                 'RES: Potential Difference', PotentialDifference )

            Capacitance = 2*Wetot / (PotentialDifference*PotentialDifference)
            WRITE( Message, * ) 'True capacitance             :', Capacitance
            CALL Info( 'StatElecSolve', Message, Level=4 )

         ELSE
            Capacitance = 2*Wetot / (PotentialDifference*PotentialDifference)
            WRITE( Message,* ) 'Potential difference: ',PotentialDifference
            CALL Info( 'StatElecSolve', Message, Level=8 )
         
            WRITE( Message, * ) 'Capacitance           :', Capacitance
            CALL Info( 'StatElecSolve', Message, Level=4 )

            CALL ListAddConstReal( Model % Simulation, &
                 'RES: Capacitance', Capacitance )
            CALL ListAddConstReal( Model % Simulation, &
                 'RES: Potential Difference', PotentialDifference )
         END IF
       END IF
     END IF

!------------------------------------------------------------------------------

     IF(CalculateCapMatrix) THEN
       IF(CapNo <= CapPerms) THEN
         CALL CapacitancePermutation(CapBodies,CapNo,Permi,Permj)

         CapB(CapNo) = CapB(CapNo) + Wetot

         IF(Permi == Permj) THEN
           CoEnergy = 1.0
         ELSE
           CoEnergy = (Wetot-CapB(Permi)-CapB(Permj))/(CapB(Permi)+CapB(Permj)) 
         END IF

         IF(CoEnergy > MinCoEnergy) THEN
           DO k=1,CapPerms
             CALL CapacitancePermutation(CapBodies,k,i,j)
             IF(i==j .AND. (i == Permi .OR. j == Permj)) THEN
               CapA(CapNo,k) = CapA(CapNo,k) + 1.0
             ELSE IF(i == Permi .AND. j == Permj) THEN 
               CapA(CapNo,k) = CapA(CapNo,k) + 4.0 
             ELSE IF(i == Permi .OR. i == Permj) THEN
               CapA(CapNo,k) = CapA(CapNo,k) + 1.0 
             ELSE IF(j == Permi .OR. j == Permj) THEN
               CapA(CapNo,k) = CapA(CapNo,k) + 1.0 
             END IF
           END DO
         ELSE
           CapB(CapNo) = 0.0d0
           DO k=1,CapPerms
             CapA(CapNo,k) = 0.0d0
             CapA(k,CapNo) = 0.0d0
           END DO
           CapA(CapNo,CapNo) = 1.0d0
         END IF
       END IF

       IF(CapNo == CapPerms) THEN

         CALL InvertMatrix(CapA,CapPerms)
         CapX(1:CapPerms) = 2.0 * MATMUL(CapA(1:CapPerms,1:CapPerms),CapB(1:CapPerms))

         CALL Info('StatElecSolve','Capacitance matrix computation performed (i,j,C_ij)',Level=4)

         DO k=1,CapPerms
           CALL CapacitancePermutation(CapBodies,k,i,j)
           CapMatrix(i,j) = CapX(k)
           CapMatrix(j,i) = CapX(k)
           WRITE( Message, '(I3,I3,ES15.5)' ) i,j,CapX(k)
           CALL Info( 'StatElecSolve', Message, Level=4 )
         END DO

         OPEN (10, FILE=CapMatrixFile)
         DO i=1,CapBodies
           DO j=1,CapBodies
             WRITE (10,'(ES17.9)',advance='no') CapMatrix(i,j)
           END DO
           WRITE(10,'(A)') ' '
         END DO
         CLOSE(10)

         WRITE(Message,'(A,A)') 'Capacitance matrix was saved to file ',CapMatrixFile
         CALL Info('StatElecSolve',Message)
       END IF

       IF ( CapNo < CapPerms )  Solver % Variable % Norm = CapNo

     END IF

     IF ( ListGetLogical( Solver % Values, 'Adaptive Mesh Refinement', GotIt ) ) &
          CALL RefineMesh( Model, Solver, Potential, PotentialPerm, &
          ElectricInsideResidual, ElectricEdgeResidual, ElectricBoundaryResidual )

!     CALL InvalidateVariable( Model, Solver % Mesh, 'EField')

!------------------------------------------------------------------------------
 
   CONTAINS

!------------------------------------------------------------------------------
! Compute the Electric Flux, Electric Field and Electric Energy at model nodes
!------------------------------------------------------------------------------
  SUBROUTINE GeneralElectricFlux( Model, Potential, Reorder )
!DLLEXPORT GeneralElectricFlux
!------------------------------------------------------------------------------
    TYPE(Model_t) :: Model
    REAL(KIND=dp) :: Potential(:)
    INTEGER :: Reorder(:)
!------------------------------------------------------------------------------
    TYPE(Element_t), POINTER :: Element
    TYPE(Nodes_t) :: Nodes 
    TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff

    REAL(KIND=dp), POINTER :: U_Integ(:), V_Integ(:), W_Integ(:), S_Integ(:)
    REAL(KIND=DP), POINTER :: Pwrk(:,:,:)
    REAL(KIND=dp), ALLOCATABLE :: SumOfWeights(:)
    REAL(KIND=dp) :: PermittivityOfVacuum
    REAL(KIND=dp) :: Permittivity(3,3,Model % MaxElementNodes)
    REAL(KIND=dp) :: ddBasisddx(Model % MaxElementNodes,3,3)
    REAL(KIND=dp) :: Basis(Model % MaxElementNodes)
    REAL(KIND=dp) :: dBasisdx(Model % MaxElementNodes,3)
    REAL(KIND=DP) :: SqrtElementMetric
    REAL(KIND=dp) :: ElementPot(Model % MaxElementNodes)
    REAL(KIND=dp) :: EnergyDensity
    REAL(KIND=dp) :: Flux(3), Field(3), ElemVol
    REAL(KIND=dp) :: s, ug, vg, wg, Grad(3), EpsGrad(3)
    REAL(KIND=dp) :: SqrtMetric, Metric(3,3), Symb(3,3,3), dSymb(3,3,3,3)
    REAL(KIND=dp) :: x, y, z
    INTEGER, POINTER :: NodeIndexes(:)
    INTEGER :: n, N_Integ, t, tg, i, j, k, DIM
    LOGICAL :: Stat


!------------------------------------------------------------------------------

    ALLOCATE( Nodes % x( Model % MaxElementNodes ) )
    ALLOCATE( Nodes % y( Model % MaxElementNodes ) )
    ALLOCATE( Nodes % z( Model % MaxElementNodes ) )
    ALLOCATE( SumOfWeights( Model % NumberOfNodes ) )

    SumOfWeights = 0.0d0

    Wetot = 0.0d0

    PermittivityOfVacuum = ListGetConstReal( Model % Constants, &
        'Permittivity Of Vacuum',gotIt )
    IF ( .NOT.gotIt ) PermittivityOfVacuum = 1

     DIM = CoordinateSystemDimension()

!------------------------------------------------------------------------------
!   Go through model elements, we will compute on average of elementwise
!   fluxes to nodes of the model
!------------------------------------------------------------------------------
    DO t=1,Model % NumberOfBulkElements
!------------------------------------------------------------------------------
!        Check if this element belongs to a body where electrostatics
!        should be calculated
!------------------------------------------------------------------------------
      Element => Model % Elements(t)
      NodeIndexes => Element % NodeIndexes
      IF ( .NOT. CheckElementEquation( Model, Element, EquationName ) ) CYCLE

      n = Element % TYPE % NumberOfNodes

      IF ( ANY(Reorder(NodeIndexes) == 0) ) CYCLE

      ElementPot(1:n) = Potential( Reorder( NodeIndexes(1:n) ) )

      Nodes % x(1:n) = Model % Nodes % x( NodeIndexes )
      Nodes % y(1:n) = Model % Nodes % y( NodeIndexes )
      Nodes % z(1:n) = Model % Nodes % z( NodeIndexes )

!------------------------------------------------------------------------------
!    Gauss integration stuff
!------------------------------------------------------------------------------
      IntegStuff = GaussPoints( Element )
      U_Integ => IntegStuff % u
      V_Integ => IntegStuff % v
      W_Integ => IntegStuff % w
      S_Integ => IntegStuff % s
      N_Integ =  IntegStuff % n

!------------------------------------------------------------------------------

      k = ListGetInteger( Model % Bodies( Element % BodyId ) % &
               Values, 'Material', minv=1, maxv=Model % NumberOfMaterials )

      CALL ListGetRealArray( Model % Materials(k) % Values, &
          'Relative Permittivity', Pwrk, n, NodeIndexes, gotIt )
      IF ( .NOT. gotIt ) &
          CALL ListGetRealArray( Model % Materials(k) % Values, &
          'Permittivity', Pwrk, n, NodeIndexes, gotIt )
      
      Permittivity = 0.0d0
      IF ( SIZE(Pwrk,1) == 1 ) THEN
        DO i=1,3
          Permittivity( i,i,1:n ) = Pwrk( 1,1,1:n )
        END DO
      ELSE IF ( SIZE(Pwrk,2) == 1 ) THEN
        DO i=1,MIN(3,SIZE(Pwrk,1))
          Permittivity(i,i,1:n) = Pwrk(i,1,1:n)
        END DO
      ELSE
        DO i=1,MIN(3,SIZE(Pwrk,1))
          DO j=1,MIN(3,SIZE(Pwrk,2))
            Permittivity( i,j,1:n ) = Pwrk(i,j,1:n)
          END DO
        END DO
      END IF
      
      EnergyDensity = 0.0d0
      Flux = 0.0d0
      Field = 0.0d0
      ElemVol = 0.0d0

!------------------------------------------------------------------------------
! Loop over Gauss integration points
!------------------------------------------------------------------------------
      DO tg=1,N_Integ
        
        ug = U_Integ(tg)
        vg = V_Integ(tg)
        wg = W_Integ(tg)
        
!------------------------------------------------------------------------------
! Need SqrtElementMetric and Basis at the integration point
!------------------------------------------------------------------------------
        stat = ElementInfo( Element, Nodes,ug,vg,wg, &
            SqrtElementMetric,Basis,dBasisdx,ddBasisddx,.FALSE. )
        
!------------------------------------------------------------------------------
!      Coordinatesystem dependent info
!------------------------------------------------------------------------------
        s = 1
        IF ( CurrentCoordinateSystem() /= Cartesian ) THEN
          x = SUM( Nodes % x(1:n)*Basis(1:n) )
          y = SUM( Nodes % y(1:n)*Basis(1:n) )
          z = SUM( Nodes % z(1:n)*Basis(1:n) )
          s = 2*PI
        END IF
        
        CALL CoordinateSystemInfo( Metric,SqrtMetric,Symb,dSymb,x,y,z )
        
        s = s * SqrtMetric * SqrtElementMetric * S_Integ(tg)

!------------------------------------------------------------------------------

        EpsGrad = 0.0d0
        DO j = 1, DIM
          Grad(j) = SUM( dBasisdx(1:n,j) * ElementPot(1:n) )
          DO i = 1, DIM
            EpsGrad(j) = EpsGrad(j) + SUM( Permittivity(j,i,1:n) * &
                 Basis(1:n) ) * SUM( dBasisdx(1:n,i) * ElementPot(1:n) )
          END DO
        END DO
        
        Wetot = Wetot + s * SUM( Grad(1:DIM) * EpsGrad(1:DIM) )
        
        EnergyDensity = EnergyDensity + &
             s * SUM(Grad(1:DIM) * EpsGrad(1:DIM))
        DO j = 1,DIM
          Flux(j) = Flux(j) - EpsGrad(j) * s
          Field(j) = Field(j) - Grad(j) * s
        END DO

        ElemVol = ElemVol + s
      END DO

!------------------------------------------------------------------------------
!   Weight with element area if required
!------------------------------------------------------------------------------

       IF ( ConstantWeights ) THEN
         EnergyDensity = EnergyDensity / ElemVol
         Flux(1:DIM) = Flux(1:DIM) / ElemVol
         Field(1:DIM) = Field(1:DIM) / ElemVol
         SumOfWeights( Reorder( NodeIndexes(1:n) ) ) = &
             SumOfWeights( Reorder( NodeIndexes(1:n) ) ) + 1
       ELSE
         SumOfWeights( Reorder( NodeIndexes(1:n) ) ) = &
             SumOfWeights( Reorder( NodeIndexes(1:n) ) ) + ElemVol
       END IF

!------------------------------------------------------------------------------

      IF(CalculateEnergy) THEN
        We( EnergyPerm(NodeIndexes(1:n)) ) = &
            We( EnergyPerm(NodeIndexes(1:n)) ) + EnergyDensity
      END IF
      
      IF(CalculateFlux) THEN
         Flux = Flux * PermittivityOfVacuum
         FluxOne( FluxPermOne( NodeIndexes(1:n) ) ) = &
              FluxOne( FluxPermOne( NodeIndexes(1:n) ) ) + Flux(1)
         FluxTwo( FluxPermTwo( NodeIndexes(1:n) ) ) = &
              FluxTwo( FluxPermTwo( NodeIndexes(1:n) ) ) + Flux(2)
         IF ( DIM == 3 )  &
              FluxThree( FluxPermThree( NodeIndexes(1:n) ) ) = &
              FluxThree( FluxPermThree( NodeIndexes(1:n) ) ) + Flux(3)
      END IF

      IF(CalculateField) THEN
         FieldOne( FieldPermOne( NodeIndexes(1:n) ) ) = &
              FieldOne( FieldPermOne( NodeIndexes(1:n) ) ) + Field(1)
         FieldTwo( FieldPermTwo( NodeIndexes(1:n) ) ) = &
              FieldTwo( FieldPermTwo( NodeIndexes(1:n) ) ) + Field(2)
         IF ( DIM == 3 )  &
              FieldThree( FieldPermThree( NodeIndexes(1:n) ) ) = &
              FieldThree( FieldPermThree( NodeIndexes(1:n) ) ) + Field(3)
      END IF

    END DO

! of the bulk elements

!------------------------------------------------------------------------------
!   Finally, compute average of the fluxes at nodes
!------------------------------------------------------------------------------

   DO i = 1, Model % NumberOfNodes
     IF ( Reorder(i) == 0 )  CYCLE
     IF ( ABS( SumOfWeights(Reorder(i)) ) > AEPS ) THEN
       IF ( CalculateEnergy )  We(EnergyPerm(i)) = &
            We(EnergyPerm(i)) / SumOfWeights(Reorder(i))

       IF ( CalculateField ) THEN
          FieldOne( FieldPermOne(i) ) = FieldOne( FieldPermOne(i) ) / &
               SumOfWeights( Reorder(i) )
          FieldTwo( FieldPermTwo(i) ) = FieldTwo( FieldPermTwo(i) ) / &
               SumOfWeights( Reorder(i) )
          IF ( DIM == 3 )  &
               FieldThree( FieldPermThree(i) ) = FieldThree( FieldPermThree(i) ) / &
               SumOfWeights( Reorder(i) )
       END IF

       IF ( CalculateFlux ) THEN
          FluxOne( FluxPermOne(i) ) = FluxOne( FluxPermOne(i) ) / &
               SumOfWeights( Reorder(i) )
          FluxTwo( FluxPermTwo(i) ) = FluxTwo( FluxPermTwo(i) ) / &
               SumOfWeights( Reorder(i) )
          IF ( DIM == 3 )  &
               FluxThree( FluxPermThree(i) ) = FluxThree( FluxPermThree(i) ) / &
               SumOfWeights( Reorder(i) )
       END IF

     END IF
   END DO

   Wetot = PermittivityOfVacuum * Wetot / 2.0d0
   IF(CalculateEnergy) We = PermittivityOfVacuum * We / 2.0d0
   
   DEALLOCATE( Nodes % x, &
       Nodes % y, &
       Nodes % z, &
       SumOfWeights)


!------------------------------------------------------------------------------
  END SUBROUTINE GeneralElectricFlux
!------------------------------------------------------------------------------

 
!------------------------------------------------------------------------------
     SUBROUTINE StatElecCompose( StiffMatrix,Force,PiezoMaterial, PiezoCoeff, &
                            Permittivity, Load,Element,n,Nodes, Displacement )
!------------------------------------------------------------------------------
       REAL(KIND=dp) :: StiffMatrix(:,:),Force(:),Load(:), Permittivity(:,:,:)
       REAL(KIND=dp) :: PiezoCoeff(:,:,:), Displacement(:,:)
       INTEGER :: n
       TYPE(Nodes_t) :: Nodes
       TYPE(Element_t), POINTER :: Element
       LOGICAL :: PiezoMaterial
!------------------------------------------------------------------------------
 
       REAL(KIND=dp) :: SqrtMetric,Metric(3,3),Symb(3,3,3),dSymb(3,3,3,3)
       REAL(KIND=dp) :: Basis(n),dBasisdx(n,3),ddBasisddx(n,3,3)
       REAL(KIND=dp) :: SqrtElementMetric,U,V,W,S,A,L,C(3,3),x,y,z
       REAL(KIND=dp) :: PiezoForce(n), LocalStrain(6), PiezoLoad(3)

       LOGICAL :: Stat

       INTEGER :: i,j,p,q,t,DIM
 
       TYPE(GaussIntegrationPoints_t) :: IntegStuff
 
!------------------------------------------------------------------------------

       DIM = CoordinateSystemDimension()

       PiezoForce = 0.0d0
       Force = 0.0d0
       StiffMatrix = 0.0d0
!------------------------------------------------------------------------------
 
!------------------------------------------------------------------------------
!      Numerical integration
!------------------------------------------------------------------------------
       IntegStuff = GaussPoints( Element )
 
       DO t=1,IntegStuff % n
         U = IntegStuff % u(t)
         V = IntegStuff % v(t)
         W = IntegStuff % w(t)
         S = IntegStuff % s(t)
!------------------------------------------------------------------------------
!        Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
         stat = ElementInfo( Element,Nodes,U,V,W,SqrtElementMetric, &
                    Basis,dBasisdx,ddBasisddx,.FALSE. )
!------------------------------------------------------------------------------
!      Coordinatesystem dependent info
!------------------------------------------------------------------------------
         IF ( CurrentCoordinateSystem() /= Cartesian ) THEN
           x = SUM( ElementNodes % x(1:n)*Basis(1:n) )
           y = SUM( ElementNodes % y(1:n)*Basis(1:n) )
           z = SUM( ElementNodes % z(1:n)*Basis(1:n) )
         END IF

         CALL CoordinateSystemInfo( Metric,SqrtMetric,Symb,dSymb,x,y,z )
 
         S = S * SqrtElementMetric * SqrtMetric
!------------------------------------------------------------------------------
!        The piezo force term
!------------------------------------------------------------------------------

         PiezoLoad = 0.0d0
         IF ( PiezoMaterial ) THEN

! So far only plane strain in 2D  (LocalStrain(3) = 0)

            LocalStrain = 0.0d0
            DO i = 1, Dim
               LocalStrain(i) = SUM( dBasisdx(1:n,i) * Displacement(1:n,i) )
            END DO
            LocalStrain(4) = 0.5d0 * ( SUM( dBasisdx(1:n,1) * Displacement(1:n,2) ) &
                 + SUM( dBasisdx(1:n,2) * Displacement(1:n,1) ) )
            IF ( Dim == 3 ) THEN
               LocalStrain(5) = 0.5d0 * ( SUM( dBasisdx(1:n,2) * Displacement(1:n,3) ) &
                    + SUM( dBasisdx(1:n,3) * Displacement(1:n,2) ) )
               LocalStrain(6) = 0.5d0 * ( SUM( dBasisdx(1:n,1) * Displacement(1:n,3) ) &
                    + SUM( dBasisdx(1:n,3) * Displacement(1:n,1) ) )
            END IF

            DO i = 1, Dim
               DO j = 1, 2*Dim
                  PiezoLoad(i) = PiezoLoad(i) + SUM( Basis(1:n) * PiezoCoeff(i,j,1:n) ) * &
                       LocalStrain(j)
               END DO
            END DO

         END IF

!------------------------------------------------------------------------------
         L = SUM( Load(1:n) * Basis )
         DO i=1,DIM
            DO j=1,DIM
               C(i,j) = SUM( Permittivity(i,j,1:n) * Basis(1:n) )
            END DO
          END DO
!------------------------------------------------------------------------------
!        The Poisson equation
!------------------------------------------------------------------------------
         DO p=1,N
           DO q=1,N
             A = 0.d0
             DO i=1,DIM
               DO J=1,DIM
                 A = A + C(i,j) * dBasisdx(p,i) * dBasisdx(q,j)
               END DO
             END DO
             StiffMatrix(p,q) = StiffMatrix(p,q) + S*A
           END DO
           Force(p) = Force(p) + S*L*Basis(p)
           IF ( PiezoMaterial )  &
                PiezoForce(p) = PiezoForce(p) + S * SUM( dBasisdx(p,1:3) * PiezoLoad(1:3) )
        END DO
!------------------------------------------------------------------------------
       END DO
       IF ( PiezoMaterial )  Force = Force + PiezoForce

!------------------------------------------------------------------------------
     END SUBROUTINE StatElecCompose
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE SetPermutationBoundaries( Model, StiffMatrix, ForceVector, &
      Name, DOF, NDOFs, Perm, Permutation, Bodies )
!------------------------------------------------------------------------------
!  To compute the capacitance matrix for m bodies, m*(m+1)/2
! different permutations are required. This subroutine makes different
! permutation every time when its called.
!------------------------------------------------------------------------------

    TYPE(Model_t) :: Model
    TYPE(Matrix_t), POINTER :: StiffMatrix
    REAL(KIND=dp) :: ForceVector(:)
    CHARACTER(LEN=*) :: Name 
    INTEGER :: DOF, NDOFs, Perm(:), Permutation, Bodies
!------------------------------------------------------------------------------

    TYPE(Element_t), POINTER :: CurrentElement
    INTEGER, POINTER :: NodeIndexes(:)
    INTEGER :: i,j,k,n,t,k1,k2, Body, Bodyi, Bodyj
    LOGICAL :: GotIt
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
      NodeIndexes => CurrentElement % NodeIndexes

      DO i=1,Model % NumberOfBCs
        IF ( CurrentElement % BoundaryInfo % Constraint == &
            Model % BCs(i) % Tag ) THEN
          
          Body = ListGetInteger( Model % BCs(i) % Values, Name, gotIt )
          
          IF ( gotIt ) THEN
            
            IF(Body > 0) THEN
              CALL CapacitancePermutation(Bodies,Permutation,Bodyi,Bodyj)
              
              Work(1:n) = 0.0d0
              IF(Body == Bodyi) THEN
                Work(1:n) = 1.0d0
              ELSE IF (Body == Bodyj) THEN
                Work(1:n) = -1.0d0
              ELSE
                Work(1:n) = 0.0d0
              END IF
            ELSE 
              Work(1:n) = 0.0d0
            END IF

            DO j=1,n
              k = Perm(NodeIndexes(j))
              IF ( k > 0 ) THEN
                k = NDOFs * (k-1) + DOF
                
                IF ( StiffMatrix % FORMAT == MATRIX_SBAND ) THEN
                  
                  CALL SBand_SetDirichlet( StiffMatrix,ForceVector,k,Work(j) )
                  
                ELSE IF ( StiffMatrix % FORMAT == MATRIX_CRS .AND. &
                    StiffMatrix % Symmetric ) THEN
                  
                  CALL CRS_SetSymmDirichlet(StiffMatrix,ForceVector,k,Work(j))
                  
                ELSE
                  
                  s = StiffMatrix % Values(StiffMatrix % Diag(k))
                  ForceVector(k) = Work(j) * s
                  CALL ZeroRow( StiffMatrix,k )
                  CALL SetMatrixElement( StiffMatrix,k,k,1.0d0*s )
                  
                END IF
              END IF
            END DO

          END IF
         END IF
       END DO
     END DO
!------------------------------------------------------------------------------
   END SUBROUTINE SetPermutationBoundaries
!------------------------------------------------------------------------------


   SUBROUTINE CapacitancePermutation(n,m,i,j)
!------------------------------------------------------------------------------
! n=number of bodies
! m=number of permutation
! i,j=resulting indexes

     INTEGER :: n,m,i,j,a,b
     
     IF(n <= 1) THEN
       i=1
       j=1
     ELSE IF(m <= n) THEN
       i=m
       j=m
     ELSE IF(m > n*(n+1)/2) THEN
       i = n-1
       j = n
     ELSE IF(m > n) THEN
       j=m
       i=0
       DO 
         j=j-(n-i)
         i=i+1
         IF(j <= n-i) THEN
           j = j+i
           EXIT
         END IF
       END DO
     ELSE
       CALL Warn('CapcacitancePermutation','Unknown case!') 
     END IF

  END SUBROUTINE CapacitancePermutation
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   SUBROUTINE StatElecBoundary( BoundaryMatrix, BoundaryVector, &
        LoadVector, Alpha, Beta, Element, n, Nodes )
!DLLEXPORT StatElecBoundary
!------------------------------------------------------------------------------
!******************************************************************************
!
!  Return element local matrices and RSH vector for boundary conditions
!  of diffusion equation: 
!
!  ARGUMENTS:
!
!  REAL(KIND=dp) :: BoundaryVector(:)
!     OUTPUT: RHS vector
!
!  REAL(KIND=dp) :: LoadVector(:)
!     INPUT: coefficient of the force term
!
!  REAL(KIND=dp) :: Alpha, Beta
!     INPUT: coefficients of the Robin BC: g = alpha * u + beta
!
!  TYPE(Element_t) :: Element
!       INPUT: Structure describing the element (dimension,nof nodes,
!               interpolation degree, etc...)
!
!   INTEGER :: n
!       INPUT: Number  of element nodes
!
!  TYPE(Nodes_t) :: Nodes
!       INPUT: Element node coordinates
!
!******************************************************************************

     REAL(KIND=dp) :: BoundaryMatrix(:,:), BoundaryVector(:), LoadVector(:)

     TYPE(Nodes_t)   :: Nodes
     TYPE(Element_t) :: Element

     INTEGER :: n

     REAL(KIND=dp) :: ddBasisddx(n,3,3)
     REAL(KIND=dp) :: Basis(n)
     REAL(KIND=dp) :: dBasisdx(n,3),SqrtElementMetric
     REAL(KIND=dp) :: SqrtMetric,Metric(3,3),Symb(3,3,3),dSymb(3,3,3,3)

     REAL(KIND=dp) :: u,v,w,s,x,y,z
     REAL(KIND=dp) :: Force, Alpha, Beta
     REAL(KIND=dp), POINTER :: U_Integ(:),V_Integ(:),W_Integ(:),S_Integ(:)

     INTEGER :: t,p,q,N_Integ

     TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff

     LOGICAL :: stat
!------------------------------------------------------------------------------

     BoundaryVector = 0.0d0
     BoundaryMatrix = 0.0d0
!------------------------------------------------------------------------------
!    Integration stuff
!------------------------------------------------------------------------------
     IntegStuff = GaussPoints( Element )
     U_Integ => IntegStuff % u
     V_Integ => IntegStuff % v
     W_Integ => IntegStuff % w
     S_Integ => IntegStuff % s
     N_Integ =  IntegStuff % n

!------------------------------------------------------------------------------
!   Now we start integrating
!------------------------------------------------------------------------------
     DO t=1,N_Integ
       u = U_Integ(t)
       v = V_Integ(t)
       w = W_Integ(t)
!------------------------------------------------------------------------------
!     Basis function values & derivates at the integration point
!------------------------------------------------------------------------------
      stat = ElementInfo( Element,Nodes,u,v,w,SqrtElementMetric, &
                 Basis,dBasisdx,ddBasisddx,.FALSE. )

!------------------------------------------------------------------------------
!      Coordinatesystem dependent info
!------------------------------------------------------------------------------
         IF ( CurrentCoordinateSystem() /= Cartesian ) THEN
           x = SUM( ElementNodes % x(1:n)*Basis(1:n) )
           y = SUM( ElementNodes % y(1:n)*Basis(1:n) )
           z = SUM( ElementNodes % z(1:n)*Basis(1:n) )
         END IF

         CALL CoordinateSystemInfo( Metric,SqrtMetric,Symb,dSymb,x,y,z )
 
         s = S_Integ(t) * SqrtElementMetric * SqrtMetric

!------------------------------------------------------------------------------
       Force = SUM( LoadVector(1:n)*Basis )
       Force = Force + Beta
       DO p=1,N
         DO q=1,N
           BoundaryMatrix(p,q) = BoundaryMatrix(p,q) + &
              s * Alpha * Basis(q) * Basis(p)
         END DO
       END DO

       DO q=1,N
         BoundaryVector(q) = BoundaryVector(q) + s * Basis(q) * Force
       END DO
     END DO
   END SUBROUTINE StatElecBoundary
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
 END SUBROUTINE StatElecSolver
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  FUNCTION ElectricBoundaryResidual( Model, Edge, Mesh, Quant, Perm, Gnorm ) &
       RESULT( Indicator )
!------------------------------------------------------------------------------
     USE ElementDescription
     IMPLICIT NONE
!------------------------------------------------------------------------------
     TYPE(Model_t) :: Model
     INTEGER :: Perm(:)
     REAL(KIND=dp) :: Quant(:), Indicator(2), Gnorm
     TYPE( Mesh_t ), POINTER    :: Mesh
     TYPE( Element_t ), POINTER :: Edge
!------------------------------------------------------------------------------

     TYPE(Nodes_t) :: Nodes, EdgeNodes
     TYPE(Element_t), POINTER :: Element


     INTEGER :: i,j,k,n,l,t,DIM,Pn,En
     LOGICAL :: stat, Found

     REAL(KIND=dp), POINTER :: Hwrk(:,:,:)

     REAL(KIND=dp) :: SqrtMetric, Metric(3,3), Symb(3,3,3), dSymb(3,3,3,3)

     REAL(KIND=dp) :: NodalPermittivity(MAX_NODES), Permittivity

     REAL(KIND=dp) :: Grad(3,3), Normal(3), EdgeLength, &
          x(MAX_NODES), y(MAX_NODES), z(MAX_NODES)

     REAL(KIND=dp) :: u, v, w, s, detJ, EdgeBasis(MAX_NODES), Basis(MAX_NODES), &
         dBasisdx(MAX_NODES,3), ddBasisddx(MAX_NODES,3,3), Potential(MAX_NODES)

     REAL(KIND=dp) :: Residual, ResidualNorm, Flux(MAX_NODES)

     TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff

     LOGICAL :: First = .TRUE., Dirichlet

     SAVE Hwrk, First
!------------------------------------------------------------------------------

!    Initialize:
!    -----------
     IF ( First ) THEN
        First = .FALSE.
        NULLIFY( Hwrk )
     END IF

     Gnorm     = 0.0d0

     Metric = 0.0d0
     DO i=1,3
        Metric(i,i) = 1.0d0
     END DO

     SELECT CASE( CurrentCoordinateSystem() )
        CASE( AxisSymmetric, CylindricSymmetric )
           DIM = 3
        CASE DEFAULT
           DIM = CoordinateSystemDimension()
     END SELECT
!    
!    ---------------------------------------------

     Element => Edge % BoundaryInfo % Left

     IF ( .NOT. ASSOCIATED( Element ) ) THEN

        Element => Edge % BoundaryInfo % Right

     ELSE IF ( ANY( Perm( Element % NodeIndexes ) <= 0 ) ) THEN

        Element => Edge % BoundaryInfo % Right

     END IF

     IF ( .NOT. ASSOCIATED( Element ) ) RETURN
     IF ( ANY( Perm( Element % NodeIndexes ) <= 0 ) ) RETURN

     En = Edge % TYPE % NumberOfNodes
     Pn = Element % TYPE % NumberOfNodes

     ALLOCATE( EdgeNodes % x(En), EdgeNodes % y(En), EdgeNodes % z(En) )

     EdgeNodes % x = Mesh % Nodes % x(Edge % NodeIndexes)
     EdgeNodes % y = Mesh % Nodes % y(Edge % NodeIndexes)
     EdgeNodes % z = Mesh % Nodes % z(Edge % NodeIndexes)

     ALLOCATE( Nodes % x(Pn), Nodes % y(Pn), Nodes % z(Pn) )

     Nodes % x = Mesh % Nodes % x(Element % NodeIndexes)
     Nodes % y = Mesh % Nodes % y(Element % NodeIndexes)
     Nodes % z = Mesh % Nodes % z(Element % NodeIndexes)

     DO l = 1,En
       DO k = 1,Pn
          IF ( Edge % NodeIndexes(l) == Element % NodeIndexes(k) ) THEN
             x(l) = Element % TYPE % NodeU(k)
             y(l) = Element % TYPE % NodeV(k)
             z(l) = Element % TYPE % NodeW(k)
             EXIT
          END IF
       END DO
     END DO
!
!    Integrate square of residual over boundary element:
!    ---------------------------------------------------

     Indicator    = 0.0d0
     EdgeLength   = 0.0d0
     ResidualNorm = 0.0d0

     DO j=1,Model % NumberOfBCs
        IF ( Edge % BoundaryInfo % Constraint /= Model % BCs(j) % Tag ) CYCLE

!       IF ( .NOT. ListGetLogical( Model % BCs(j) % Values, &
!                 'Heat Flux BC', Found ) ) CYCLE

!
!       Check if dirichlet BC given:
!       ----------------------------
        s = ListGetConstReal( Model % BCs(j) % Values, Model % Solver % Variable % Name, &
             Dirichlet )

!       Get various flux bc options:
!       ----------------------------

!       ...given flux:
!       --------------
        Flux(1:En) = ListGetReal( Model % BCs(j) % Values, &
          'Electric Flux', En, Edge % NodeIndexes, Found )


!       get material parameters:
!       ------------------------
        k = ListGetInteger(Model % Bodies(Element % BodyId) % Values,'Material', &
                    minv=1, maxv=Model % NumberOFMaterials)

        CALL ListGetRealArray( Model % Materials(k) % Values, &
               'Relative Permittivity', Hwrk, En, Edge % NodeIndexes,stat )
        IF ( .NOT. stat )  &
             CALL ListGetRealArray( Model % Materials(k) % Values, &
             'Permittivity', Hwrk, En, Edge % NodeIndexes )

        NodalPermittivity( 1:En ) = Hwrk( 1,1,1:En )

!       elementwise nodal solution:
!       ---------------------------
        Potential(1:Pn) = Quant( Perm(Element % NodeIndexes) )

!       do the integration:
!       -------------------
        EdgeLength   = 0.0d0
        ResidualNorm = 0.0d0

        IntegStuff = GaussPoints( Edge )

        DO t=1,IntegStuff % n
           u = IntegStuff % u(t)
           v = IntegStuff % v(t)
           w = IntegStuff % w(t)

           stat = ElementInfo( Edge, EdgeNodes, u, v, w, detJ, &
               EdgeBasis, dBasisdx, ddBasisddx, .FALSE., .FALSE. )

           Normal = NormalVector( Edge, EdgeNodes, u, v, .TRUE. )

           IF ( CurrentCoordinateSystem() == Cartesian ) THEN
              s = IntegStuff % s(t) * detJ
           ELSE
              u = SUM( EdgeBasis(1:En) * EdgeNodes % x(1:En) )
              v = SUM( EdgeBasis(1:En) * EdgeNodes % y(1:En) )
              w = SUM( EdgeBasis(1:En) * EdgeNodes % z(1:En) )
      
              CALL CoordinateSystemInfo( Metric, SqrtMetric, &
                         Symb, dSymb, u, v, w )

              s = IntegStuff % s(t) * detJ * SqrtMetric
           END IF

!
!          Integration point in parent element local
!          coordinates:
!          -----------------------------------------
           u = SUM( EdgeBasis(1:En) * x(1:En) )
           v = SUM( EdgeBasis(1:En) * y(1:En) )
           w = SUM( EdgeBasis(1:En) * z(1:En) )

           stat = ElementInfo( Element, Nodes, u, v, w, detJ, &
                 Basis, dBasisdx, ddBasisddx, .FALSE., .FALSE. )
!
!          Heat conductivity at the integration point:
!          --------------------------------------------
           Permittivity = SUM( NodalPermittivity(1:En) * EdgeBasis(1:En) )
!
!          given flux at integration point:
!          --------------------------------
           Residual = -SUM( Flux(1:En) * EdgeBasis(1:En) )


!          flux given by the computed solution, and 
!          force norm for scaling the residual:
!          -----------------------------------------
           IF ( CurrentCoordinateSystem() == Cartesian ) THEN
              DO k=1,DIM
                 Residual = Residual + Permittivity  * &
                    SUM( dBasisdx(1:Pn,k) * Potential(1:Pn) ) * Normal(k)

                 Gnorm = Gnorm + s * (Permittivity * &
                       SUM(dBasisdx(1:Pn,k) * Potential(1:Pn)) * Normal(k))**2
              END DO
           ELSE
              DO k=1,DIM
                 DO l=1,DIM
                    Residual = Residual + Metric(k,l) * Permittivity  * &
                       SUM( dBasisdx(1:Pn,k) * Potential(1:Pn) ) * Normal(l)

                    Gnorm = Gnorm + s * (Metric(k,l) * Permittivity * &
                      SUM(dBasisdx(1:Pn,k) * Potential(1:Pn) ) * Normal(l))**2
                 END DO
              END DO
           END IF

           EdgeLength   = EdgeLength + s
           IF ( .NOT. Dirichlet ) THEN
              ResidualNorm = ResidualNorm + s * Residual ** 2
           END IF
        END DO
        EXIT
     END DO

     IF ( CoordinateSystemDimension() == 3 ) THEN
        EdgeLength = SQRT(EdgeLength)
     END IF

!    Gnorm = EdgeLength * Gnorm
     Indicator = EdgeLength * ResidualNorm

     DEALLOCATE( Nodes % x, Nodes % y, Nodes % z)
     DEALLOCATE( EdgeNodes % x, EdgeNodes % y, EdgeNodes % z)
!------------------------------------------------------------------------------
  END FUNCTION ElectricBoundaryResidual
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
  FUNCTION ElectricEdgeResidual( Model, Edge, Mesh, Quant, Perm ) RESULT( Indicator )
!------------------------------------------------------------------------------
     USE ElementDescription
     IMPLICIT NONE

     TYPE(Model_t) :: Model
     INTEGER :: Perm(:)
     REAL(KIND=dp) :: Quant(:), Indicator(2)
     TYPE( Mesh_t ), POINTER    :: Mesh
     TYPE( Element_t ), POINTER :: Edge
!------------------------------------------------------------------------------

     TYPE(Nodes_t) :: Nodes, EdgeNodes
     TYPE(Element_t), POINTER :: Element

     INTEGER :: i,j,k,l,n,t,DIM,En,Pn
     LOGICAL :: stat, Found
     REAL(KIND=dp), POINTER :: Hwrk(:,:,:)

     REAL(KIND=dp) :: SqrtMetric, Metric(3,3), Symb(3,3,3), dSymb(3,3,3,3)

     REAL(KIND=dp) :: NodalPermittivity(MAX_NODES), Permittivity

     REAL(KIND=dp) :: Grad(3,3), Normal(3), EdgeLength, Jump, &
                x(MAX_NODES),y(MAX_NODES),z(MAX_NODES)

     REAL(KIND=dp) :: u, v, w, s, detJ, EdgeBasis(MAX_NODES), &
          Basis(MAX_NODES), dBasisdx(MAX_NODES,3), &
             ddBasisddx(MAX_NODES,3,3), Potential(MAX_NODES)

     REAL(KIND=dp) :: Residual, ResidualNorm

     TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff

     LOGICAL :: First = .TRUE.

     SAVE Hwrk, First

!------------------------------------------------------------------------------

!    Initialize:
!    -----------

     IF ( First ) THEN
        First = .FALSE.
        NULLIFY( Hwrk )
     END IF

     SELECT CASE( CurrentCoordinateSystem() )
        CASE( AxisSymmetric, CylindricSymmetric )
           DIM = 3
        CASE DEFAULT
           DIM = CoordinateSystemDimension()
     END SELECT

     Metric = 0.0d0
     DO i = 1,3
        Metric(i,i) = 1.0d0
     END DO

     Grad = 0.0d0
!
!    ---------------------------------------------

     Element => Edge % BoundaryInfo % Left
     n = Element % TYPE % NumberOfNodes

     Element => Edge % BoundaryInfo % Right
     n = MAX( n, Element % TYPE % NumberOfNodes )

     ALLOCATE( Nodes % x(n), Nodes % y(n), Nodes % z(n) )

     En = Edge % TYPE % NumberOfNodes
     ALLOCATE( EdgeNodes % x(En), EdgeNodes % y(En), EdgeNodes % z(En) )

     EdgeNodes % x = Mesh % Nodes % x(Edge % NodeIndexes)
     EdgeNodes % y = Mesh % Nodes % y(Edge % NodeIndexes)
     EdgeNodes % z = Mesh % Nodes % z(Edge % NodeIndexes)

!    Integrate square of jump over edge:
!    -----------------------------------
     ResidualNorm = 0.0d0
     EdgeLength   = 0.0d0
     Indicator    = 0.0d0

     IntegStuff = GaussPoints( Edge )

     DO t=1,IntegStuff % n

        u = IntegStuff % u(t)
        v = IntegStuff % v(t)
        w = IntegStuff % w(t)

        stat = ElementInfo( Edge, EdgeNodes, u, v, w, detJ, &
             EdgeBasis, dBasisdx, ddBasisddx, .FALSE., .FALSE. )

        Normal = NormalVector( Edge, EdgeNodes, u, v, .FALSE. )

        IF ( CurrentCoordinateSystem() == Cartesian ) THEN
           s = IntegStuff % s(t) * detJ
        ELSE
           u = SUM( EdgeBasis(1:En) * EdgeNodes % x(1:En) )
           v = SUM( EdgeBasis(1:En) * EdgeNodes % y(1:En) )
           w = SUM( EdgeBasis(1:En) * EdgeNodes % z(1:En) )

           CALL CoordinateSystemInfo( Metric, SqrtMetric, &
                      Symb, dSymb, u, v, w )
           s = IntegStuff % s(t) * detJ * SqrtMetric
        END IF

        ! 
        ! Compute flux over the edge as seen by elements
        ! on both sides of the edge:
        ! ----------------------------------------------
        DO i = 1,2
           SELECT CASE(i)
              CASE(1)
                 Element => Edge % BoundaryInfo % Left
              CASE(2)
                 Element => Edge % BoundaryInfo % Right
           END SELECT
!
!          Can this really happen (maybe it can...)  ?      
!          -------------------------------------------
           IF ( ANY( Perm( Element % NodeIndexes ) <= 0 ) ) CYCLE
!
!          Next, get the integration point in parent
!          local coordinates:
!          -----------------------------------------
           Pn = Element % TYPE % NumberOfNodes

           DO j = 1,En
              DO k = 1,Pn
                 IF ( Edge % NodeIndexes(j) == Element % NodeIndexes(k) ) THEN
                    x(j) = Element % TYPE % NodeU(k)
                    y(j) = Element % TYPE % NodeV(k)
                    z(j) = Element % TYPE % NodeW(k)
                    EXIT
                 END IF
              END DO
           END DO

           u = SUM( EdgeBasis(1:En) * x(1:En) )
           v = SUM( EdgeBasis(1:En) * y(1:En) )
           w = SUM( EdgeBasis(1:En) * z(1:En) )
!
!          Get parent element basis & derivatives at the integration point:
!          -----------------------------------------------------------------
           Nodes % x(1:Pn) = Mesh % Nodes % x(Element % NodeIndexes)
           Nodes % y(1:Pn) = Mesh % Nodes % y(Element % NodeIndexes)
           Nodes % z(1:Pn) = Mesh % Nodes % z(Element % NodeIndexes)

           stat = ElementInfo( Element, Nodes, u, v, w, detJ, &
             Basis, dBasisdx, ddBasisddx, .FALSE., .FALSE. )
!
!          Material parameters:
!          --------------------
           k = ListGetInteger( Model % Bodies( &
                    Element % BodyId) % Values, 'Material', &
                     minv=1, maxv=Model % NumberOFMaterials )

           CALL ListGetRealArray( Model % Materials(k) % Values, &
                'Relative Permittivity', Hwrk, En, Edge % NodeIndexes,stat )
           IF ( .NOT. stat )  &
                CALL ListGetRealArray( Model % Materials(k) % Values, &
                'Permittivity', Hwrk, En, Edge % NodeIndexes )

           NodalPermittivity( 1:En ) = Hwrk( 1,1,1:En )
           Permittivity = SUM( NodalPermittivity(1:En) * EdgeBasis(1:En) )
!
!          Potential at element nodal points:
!          ------------------------------------
           Potential(1:Pn) = Quant( Perm(Element % NodeIndexes) )
!
!          Finally, the flux:
!          ------------------
           DO j=1,DIM
              Grad(j,i) = Permittivity * SUM( dBasisdx(1:Pn,j) * Potential(1:Pn) )
           END DO
        END DO

!       Compute square of the flux jump:
!       -------------------------------   
        EdgeLength  = EdgeLength + s
        Jump = 0.0d0
        DO k=1,DIM
           IF ( CurrentCoordinateSystem() == Cartesian ) THEN
              Jump = Jump + (Grad(k,1) - Grad(k,2)) * Normal(k)
           ELSE
              DO l=1,DIM
                 Jump = Jump + &
                       Metric(k,l) * (Grad(k,1) - Grad(k,2)) * Normal(l)
              END DO
           END IF
        END DO
        ResidualNorm = ResidualNorm + s * Jump ** 2
     END DO

     IF ( CoordinateSystemDimension() == 3 ) THEN
        EdgeLength = SQRT(EdgeLength)
     END IF
     Indicator = EdgeLength * ResidualNorm

     DEALLOCATE( Nodes % x, Nodes % y, Nodes % z)
     DEALLOCATE( EdgeNodes % x, EdgeNodes % y, EdgeNodes % z)
!------------------------------------------------------------------------------
  END FUNCTION ElectricEdgeResidual
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   FUNCTION ElectricInsideResidual( Model, Element, Mesh, &
        Quant, Perm, Fnorm ) RESULT( Indicator )
!------------------------------------------------------------------------------
     USE CoordinateSystems
     USE ElementDescription
!------------------------------------------------------------------------------
     IMPLICIT NONE
!------------------------------------------------------------------------------
     TYPE(Model_t) :: Model
     INTEGER :: Perm(:)
     REAL(KIND=dp) :: Quant(:), Indicator(2), Fnorm
     TYPE( Mesh_t ), POINTER    :: Mesh
     TYPE( Element_t ), POINTER :: Element
!------------------------------------------------------------------------------

     TYPE(Nodes_t) :: Nodes

     INTEGER :: i,j,k,l,n,t,DIM
     REAL(KIND=dp), TARGET :: x(MAX_NODES), y(MAX_NODES), z(MAX_NODES)

     LOGICAL :: stat, Found

     REAL(KIND=dp), POINTER :: Hwrk(:,:,:)

     REAL(KIND=dp) :: SqrtMetric, Metric(3,3), Symb(3,3,3), dSymb(3,3,3,3)

     REAL(KIND=dp) :: Permittivity, NodalPermittivity(MAX_NODES)

     REAL(KIND=dp) :: u, v, w, s, detJ, Basis(MAX_NODES), &
                dBasisdx(MAX_NODES,3), ddBasisddx(MAX_NODES,3,3)

     REAL(KIND=dp) :: Source, Residual, ResidualNorm, Area

     REAL(KIND=dp) :: NodalSource(MAX_NODES), Potential(MAX_NODES), &
                      PrevPot(MAX_NODES)

     TYPE( ValueList_t ), POINTER :: Material

     TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff

     LOGICAL :: First = .TRUE.

     SAVE Hwrk, First

!------------------------------------------------------------------------------

!    Initialize:
!    -----------
     Indicator = 0.0d0
     Fnorm     = 0.0d0
!
!    Check if this eq. computed in this element:
!    -------------------------------------------
     IF ( ANY( Perm( Element % NodeIndexes ) <= 0 ) ) RETURN

     IF ( First ) THEN
        First = .FALSE.
        NULLIFY( Hwrk )
     END IF

     Metric = 0.0d0
     DO i=1,3
        Metric(i,i) = 1.0d0
     END DO

     SELECT CASE( CurrentCoordinateSystem() )
        CASE( AxisSymmetric, CylindricSymmetric )
           DIM = 3
        CASE DEFAULT
           DIM = CoordinateSystemDimension()
     END SELECT
!
!    Element nodal points:
!    ---------------------
     n = Element % TYPE % NumberOfNodes

     Nodes % x => x(1:n)
     Nodes % y => y(1:n)
     Nodes % z => z(1:n)

     Nodes % x = Mesh % Nodes % x(Element % NodeIndexes)
     Nodes % y = Mesh % Nodes % y(Element % NodeIndexes)
     Nodes % z = Mesh % Nodes % z(Element % NodeIndexes)
!
!    Elementwise nodal solution:
!    ---------------------------
     Potential(1:n) = Quant( Perm(Element % NodeIndexes) )
!
!    Material parameters: relative permittivity
!    ------------------------------------------
     k = ListGetInteger( Model % Bodies(Element % BodyId) % Values, 'Material', &
                     minv=1, maxv=Model % NumberOfMaterials )

     Material => Model % Materials(k) % Values

     CALL ListGetRealArray( Model % Materials(k) % Values, &
          'Relative Permittivity', Hwrk, n, Element % NodeIndexes,stat )
     IF ( .NOT. stat )  &
          CALL ListGetRealArray( Model % Materials(k) % Values, &
          'Permittivity', Hwrk, n, Element % NodeIndexes )

     NodalPermittivity( 1:n ) = Hwrk( 1,1,1:n )

!
!    Charge density (source):
!    ------------------------
!
     k = ListGetInteger( &
         Model % Bodies(Element % BodyId) % Values,'Body Force',Found, &
                 1, Model % NumberOFBodyForces)

     NodalSource = 0.0d0
     IF ( Found .AND. k > 0  ) THEN
        NodalSource(1:n) = ListGetReal( Model % BodyForces(k) % Values, &
             'Charge Density', n, Element % NodeIndexes, stat )
        IF ( .NOT. stat )  &
             NodalSource(1:n) = ListGetReal( Model % BodyForces(k) % Values, &
             'Source', n, Element % NodeIndexes )
     END IF
!
!    Integrate square of residual over element:
!    ------------------------------------------

     ResidualNorm = 0.0d0
     Area = 0.0d0

     IntegStuff = GaussPoints( Element )

     DO t=1,IntegStuff % n
        u = IntegStuff % u(t)
        v = IntegStuff % v(t)
        w = IntegStuff % w(t)

        stat = ElementInfo( Element, Nodes, u, v, w, detJ, &
            Basis, dBasisdx, ddBasisddx, .TRUE., .FALSE. )

        IF ( CurrentCoordinateSystem() == Cartesian ) THEN
           s = IntegStuff % s(t) * detJ
        ELSE
           u = SUM( Basis(1:n) * Nodes % x(1:n) )
           v = SUM( Basis(1:n) * Nodes % y(1:n) )
           w = SUM( Basis(1:n) * Nodes % z(1:n) )

           CALL CoordinateSystemInfo( Metric, SqrtMetric, &
                       Symb, dSymb, u, v, w )
           s = IntegStuff % s(t) * detJ * SqrtMetric
        END IF

        Permittivity = SUM( NodalPermittivity(1:n) * Basis(1:n) )
!
!       Residual of the electrostatic equation:
!
!        R = -div(e grad(u)) - s
!       ---------------------------------------------------
!
!       or more generally:
!
!        R = -g^{jk} (C T_{,j}}_{,k} - s
!       ---------------------------------------------------
!
        Residual = -SUM( NodalSource(1:n) * Basis(1:n) )

        IF ( CurrentCoordinateSystem() == Cartesian ) THEN
           DO j=1,DIM
!
!             - grad(e).grad(T):
!             --------------------
!
              Residual = Residual - &
                 SUM( Potential(1:n) * dBasisdx(1:n,j) ) * &
                 SUM( NodalPermittivity(1:n) * dBasisdx(1:n,j) )

!
!             - e div(grad(u)):
!             -------------------
!
              Residual = Residual - Permittivity * &
                 SUM( Potential(1:n) * ddBasisddx(1:n,j,j) )
           END DO
        ELSE
           DO j=1,DIM
              DO k=1,DIM
!
!                - g^{jk} C_{,k}T_{j}:
!                ---------------------
!
                 Residual = Residual - Metric(j,k) * &
                    SUM( Potential(1:n) * dBasisdx(1:n,j) ) * &
                    SUM( NodalPermittivity(1:n) * dBasisdx(1:n,k) )

!
!                - g^{jk} C T_{,jk}:
!                -------------------
!
                 Residual = Residual - Metric(j,k) * Permittivity * &
                    SUM( Potential(1:n) * ddBasisddx(1:n,j,k) )
!
!                + g^{jk} C {_jk^l} T_{,l}:
!                ---------------------------
                 DO l=1,DIM
                    Residual = Residual + Metric(j,k) * Permittivity * &
                      Symb(j,k,l) * SUM( Potential(1:n) * dBasisdx(1:n,l) )
                 END DO
              END DO
           END DO
        END IF

!
!       Compute also force norm for scaling the residual:
!       -------------------------------------------------
        DO i=1,DIM
           Fnorm = Fnorm + s * ( SUM( NodalSource(1:n) * Basis(1:n) ) ) ** 2
        END DO

        Area = Area + s
        ResidualNorm = ResidualNorm + s *  Residual ** 2
     END DO

!    Fnorm = Element % hk**2 * Fnorm
     Indicator = Element % hK**2 * ResidualNorm
!------------------------------------------------------------------------------
  END FUNCTION ElectricInsideResidual
!------------------------------------------------------------------------------

!==============================================================================
