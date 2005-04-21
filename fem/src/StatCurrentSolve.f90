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
! *       Date of modification:      01 Aug 2002
! *
! *****************************************************************************/
    
!------------------------------------------------------------------------------
  SUBROUTINE StatCurrentSolver( Model,Solver,dt,TransientSimulation )
!DEC$ATTRIBUTES DLLEXPORT :: StatCurrentSolver
!------------------------------------------------------------------------------
!******************************************************************************
!
!  Solve the Poisson equation for the electric potential and compute the 
!  volume current and Joule heating
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
     USE DefUtils
 
     USE SolverUtils
     USE ElementUtils


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
     TYPE(Nodes_t) :: ElementNodes

     REAL (KIND=DP), POINTER :: ForceVector(:), Potential(:), Density(:)
     REAL (KIND=DP), POINTER :: ElField(:), VolCurrent(:)
     REAL (KIND=DP), POINTER :: Ex(:), Ey(:), Ez(:), Cx(:), Cy(:), Cz(:)
     REAL (KIND=DP), POINTER :: Heating(:), JouleH(:)
     REAL (KIND=DP), POINTER :: ElectricCond(:), EleC(:)
     REAL (KIND=DP), POINTER :: Cwrk(:,:,:)
     REAL (KIND=DP), ALLOCATABLE ::  Conductivity(:,:,:), &
       LocalStiffMatrix(:,:), Load(:), LocalForce(:)

     REAL (KIND=DP) :: Norm, Heatingtot
     REAL (KIND=DP) :: at, st, at0, CPUTime, RealTime

     INTEGER, POINTER :: NodeIndexes(:)
     INTEGER, POINTER :: PotentialPerm(:)
     INTEGER :: i, j, k, n, t, istat, bf_id, LocalNodes, Dim
 
     LOGICAL :: AllocationsDone = .FALSE., gotIt
     LOGICAL :: CalculateField = .FALSE., ConstantWeights
     LOGICAL :: CalculateCurrent, CalculateHeating, CalculateConductivity

     CHARACTER(LEN=MAX_NAME_LEN) :: EquationName
     CHARACTER(LEN=MAX_NAME_LEN) :: VersionID = "$Id: StatCurrentSolve.f90,v 1.9 2004/07/30 07:39:30 jpr Exp $"


     SAVE LocalStiffMatrix, Load, LocalForce, Density, &
          ElementNodes, CalculateCurrent, CalculateHeating, &
          AllocationsDone, VolCurrent, Heating, Conductivity, &
          CalculateField, ConstantWeights, CalculateConductivity, &
          ElectricCond, Cwrk
     
!------------------------------------------------------------------------------
!    Check if version number output is requested
!------------------------------------------------------------------------------
     IF ( .NOT. AllocationsDone ) THEN
       IF ( ListGetLogical( GetSimulation(), 'Output Version Numbers', GotIt ) ) THEN
         CALL Info( 'StatCurrentSolve', 'StatCurrentSolve version:', Level = 0 ) 
         CALL Info( 'StatCurrentSolve', VersionID, Level = 0 ) 
         CALL Info( 'StatCurrentSolve', ' ', Level = 0 ) 
       END IF
     END IF
 
!------------------------------------------------------------------------------
!    Get variables needed for solution
!------------------------------------------------------------------------------
     Potential     => Solver % Variable % Values
     PotentialPerm => Solver % Variable % Perm
 
     LocalNodes = Model % NumberOfNodes
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
                 Conductivity(3,3,N),   &
                 Density(N),            &
                 LocalForce(N),         &
                 LocalStiffMatrix(N,N), &
                 Load(N),               &
                 STAT=istat )
 
       IF ( istat /= 0 ) THEN
         CALL Fatal( 'StatCurrentSolve', 'Memory allocation error.' )
       END IF

       NULLIFY( Cwrk )
 
       CalculateCurrent = ListGetLogical( Solver % Values, &
           'Calculate Volume Current', GotIt )
       IF ( .NOT. GotIt )  CalculateCurrent = .TRUE.
       IF ( CalculateCurrent )  &
           ALLOCATE( VolCurrent( DIM*Model%NumberOfNodes ), STAT=istat )
       IF ( istat /= 0 ) THEN
          CALL Fatal( 'StatCurrentSolve', 'Memory allocation error.' )
       END IF

       CalculateConductivity = ListGetLogical( Solver % Values, &
           'Calculate Electric Conductivity', GotIt )
       IF ( .NOT. GotIt )  CalculateConductivity = .FALSE.
       IF ( CalculateConductivity )  &
           ALLOCATE( ElectricCond( Model%NumberOfNodes ), STAT=istat )
       IF ( istat /= 0 ) THEN
          CALL Fatal( 'StatCurrentSolve', 'Memory allocation error.' )
       END IF

       DO i = 1, Model % NumberOfEquations
         CalculateHeating = ListGetLogical( Model % Equations(i) % Values, &
             'Calculate Joule heating', GotIt )
         IF ( GotIt ) EXIT
       END DO
       IF ( .NOT. GotIt )  &
            CalculateHeating = ListGetLogical( Solver % Values, &
            'Calculate Joule Heating', GotIt )
       IF ( .NOT. GotIt )  CalculateHeating = .TRUE.
       IF ( CalculateHeating )  &
           ALLOCATE( Heating( Model%NumberOfNodes ), STAT=istat )
       IF ( istat /= 0 ) THEN
         CALL Fatal( 'StatCurrentSolve', 'Memory allocation error.' )
       END IF

       ConstantWeights = ListGetLogical( Solver % Values, &
           'Constant Weights', GotIt )

!------------------------------------------------------------------------------

       IF ( .NOT.ASSOCIATED( StiffMatrix % MassValues ) ) THEN
         ALLOCATE( StiffMatrix % Massvalues( LocalNodes ) )
         StiffMatrix % MassValues = 0.0d0
       END IF

!------------------------------------------------------------------------------
!      Add electric field to the variable list (disabled)
!------------------------------------------------------------------------------
       PSolver => Solver
       IF ( CalculateField ) THEN         
          Ex => ElField(1:Dim*LocalNodes-Dim+1:Dim)
          CALL VariableAdd( Solver % Mesh % Variables, Solver % Mesh, PSolver, &
               'Electric Field 1', 1, Ex, PotentialPerm)
           
          Ey => ElField(2:Dim*LocalNodes-Dim+2:Dim)
          CALL VariableAdd( Solver % Mesh % Variables, Solver % Mesh, PSolver, &
               'Electric Field 2', 1, Ey, PotentialPerm)
           
          IF ( Dim == 3 ) THEN
             Ez => ElField(3:Dim*LocalNodes:Dim)
             CALL VariableAdd( Solver % Mesh % Variables, Solver % Mesh, PSolver, &
                  'Electric Field 3', 1, Ez, PotentialPerm)
          END IF
       END IF

!------------------------------------------------------------------------------
!      Add volume current to the variable list
!------------------------------------------------------------------------------

       IF ( CalculateCurrent ) THEN
          Cx => VolCurrent(1:Dim*LocalNodes-Dim+1:Dim)
          CALL VariableAdd( Solver % Mesh % Variables, Solver % Mesh, &
               PSolver, 'Volume Current 1', 1, Cx, PotentialPerm)

          Cy => VolCurrent(2:Dim*LocalNodes-Dim+2:Dim)
          CALL VariableAdd( Solver % Mesh % Variables, Solver % Mesh, &
               PSolver, 'Volume Current 2', 1, Cy, PotentialPerm)

          IF ( DIM == 3 ) THEN
             Cz => VolCurrent(3:Dim*LocalNodes:Dim)
             CALL VariableAdd( Solver % Mesh % Variables, Solver % Mesh, &
                  PSolver, 'Volume Current 3', 1, Cz, PotentialPerm)
          END IF
       END IF

       IF ( CalculateConductivity ) THEN
          ElectricCond = 0.0d0
          EleC => ElectricCond(:)
          CALL VariableAdd( Solver % Mesh % Variables, Solver % Mesh, &
               PSolver, 'Electric Conductivity', 1, EleC, PotentialPerm )
       END IF

       IF ( CalculateHeating ) THEN
          Heating = 0.0d0
          JouleH => Heating(:)
          CALL VariableAdd( Solver % Mesh % Variables, Solver % Mesh, &
               PSolver, 'Joule Heating', 1, JouleH, PotentialPerm )
       END IF
          
       AllocationsDone = .TRUE.
     END IF

!------------------------------------------------------------------------------
!    Do some additional initialization, and go for it
!------------------------------------------------------------------------------

     EquationName = ListGetString( Solver % Values, 'Equation' )
     
     at = CPUTime()
     at0 = RealTime()

     CALL InitializeToZero( StiffMatrix, ForceVector )
!------------------------------------------------------------------------------
     CALL Info( 'StatCurrentSolve', '-------------------------------------',Level=4 )
     CALL Info( 'StatCurrentSolve', 'STAT CURRENT SOLVER:  ', Level=4 )
     CALL Info( 'StatCurrentSolve', '-------------------------------------',Level=4 )
     CALL Info( 'StatCurrentSolve', 'Starting Assembly...', Level=4 )

!------------------------------------------------------------------------------
!    Do the assembly
!------------------------------------------------------------------------------

     DO t = 1, Solver % NumberOfActiveElements

        IF ( RealTime() - at0 > 1.0 ) THEN
           WRITE(Message,'(a,i3,a)' ) '   Assembly: ', INT(100.0 - 100.0 * &
            (Solver % NumberOfActiveElements-t) / &
               (1.0*Solver % NumberOfActiveElements)), ' % done'
                       
           CALL Info( 'StatCurrentSolve', Message, Level=5 )

           at0 = RealTime()
        END IF

!------------------------------------------------------------------------------
!        Check if this element belongs to a body where potential
!        should be calculated
!------------------------------------------------------------------------------
       CurrentElement => Solver % Mesh % Elements( Solver % ActiveElements(t) )
       NodeIndexes => CurrentElement % NodeIndexes

       n = CurrentElement % TYPE % NumberOfNodes
 
       ElementNodes % x(1:n) = Solver % Mesh % Nodes % x(NodeIndexes)
       ElementNodes % y(1:n) = Solver % Mesh % Nodes % y(NodeIndexes)
       ElementNodes % z(1:n) = Solver % Mesh % Nodes % z(NodeIndexes)
!------------------------------------------------------------------------------

       bf_id = ListGetInteger( Model % Bodies(CurrentElement % BodyId) % &
                Values, 'Body Force', gotIt, minv=1, maxv=Model % NumberOfBodyForces )

       Load  = 0.0d0
       IF ( gotIt ) THEN
          Load(1:n) = ListGetReal( Model % BodyForces(bf_id) % Values, &
               'Current Source',n,NodeIndexes, Gotit )
       END IF

       k = ListGetInteger( Model % Bodies(CurrentElement % BodyId) % &
            Values, 'Material', minv=1, maxv=Model % NumberOfMaterials )

!------------------------------------------------------------------------------
!      Read conductivity values (might be a tensor)
!------------------------------------------------------------------------------

       CALL ListGetRealArray( Model % Materials(k) % Values, &
            'Electric Conductivity', Cwrk, n, NodeIndexes, gotIt )

       IF ( .NOT. gotIt ) CALL Fatal( 'StatCurrentSolve', &
            'No conductivity found' )
       
       Conductivity = 0.0d0
       IF ( SIZE(Cwrk,1) == 1 ) THEN
          DO i=1,3
             Conductivity( i,i,1:n ) = Cwrk( 1,1,1:n )
          END DO
       ELSE IF ( SIZE(Cwrk,2) == 1 ) THEN
          DO i=1,MIN(3,SIZE(Cwrk,1))
             Conductivity(i,i,1:n) = Cwrk(i,1,1:n)
          END DO
       ELSE
          DO i=1,MIN(3,SIZE(Cwrk,1))
             DO j=1,MIN(3,SIZE(Cwrk,2))
                Conductivity( i,j,1:n ) = Cwrk(i,j,1:n)
             END DO
          END DO
       END IF

!------------------------------------------------------------------------------
!      Get element local matrix, and rhs vector
!------------------------------------------------------------------------------
       CALL StatCurrentCompose( LocalStiffMatrix,LocalForce, &
            Conductivity,Load,CurrentElement,n,ElementNodes )
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
                 'Current Density BC',gotIt) ) CYCLE
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
!             BC: cond@Phi/@n = g
!------------------------------------------------------------------------------
              Load(1:n) = Load(1:n) + &
                ListGetReal( Model % BCs(i) % Values,'Current Density', &
                          n,NodeIndexes,gotIt )
!------------------------------------------------------------------------------
!             Get element matrix and rhs due to boundary conditions ...
!------------------------------------------------------------------------------
              CALL StatCurrentBoundary( LocalStiffMatrix, LocalForce,  &
                  Load, CurrentElement, n, ElementNodes )
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

     at = CPUTime() - at
     WRITE( Message, * ) 'Assembly (s)          :',at
     CALL Info( 'StatCurrentSolve', Message, Level=4 )
!------------------------------------------------------------------------------
!    Solve the system and we are done.
!------------------------------------------------------------------------------
     st = CPUTime()
     CALL SolveSystem( StiffMatrix, ParMatrix, ForceVector, &
                  Potential, Norm, 1, Solver )
     st = CPUTime() - st
     WRITE( Message, * ) 'Solve (s)             :',st
     CALL Info( 'StatCurrentSolve', Message, Level=4 )

!------------------------------------------------------------------------------
!    Compute the electric field from the potential: E = -grad Phi
!------------------------------------------------------------------------------
!------------------------------------------------------------------------------
!    Compute the volume current: J = cond (-grad Phi)
!------------------------------------------------------------------------------
!------------------------------------------------------------------------------
!    Compute the Joule heating: H,tot = Integral (E . D)dV
!------------------------------------------------------------------------------

     IF ( CalculateCurrent .OR. CalculateHeating ) THEN 
        CALL GeneralCurrent( Model, Potential, PotentialPerm )
     END IF

!------------------------------------------------------------------------------

     IF ( Heatingtot > 0.0D0 ) THEN
       WRITE( Message, * ) 'Total Heating Power   :', Heatingtot
       CALL Info( 'StatCurrentSolve', Message, Level=4 )
       CALL ListAddConstReal( Model % Simulation, &
           'RES: Total Joule Heating', Heatingtot )
    END IF

!------------------------------------------------------------------------------

!     CALL InvalidateVariable( Model, Solver % Mesh, 'EField')

!------------------------------------------------------------------------------
 
   CONTAINS

!------------------------------------------------------------------------------
! Compute the Current and Joule Heating at model nodes
!------------------------------------------------------------------------------
  SUBROUTINE GeneralCurrent( Model, Potential, Reorder )
!DLLEXPORT GeneralCurrent
!------------------------------------------------------------------------------
    TYPE(Model_t) :: Model
    REAL(KIND=dp) :: Potential(:)
    INTEGER :: Reorder(:)
!------------------------------------------------------------------------------
    TYPE(Element_t), POINTER :: Element
    TYPE(Nodes_t) :: Nodes 
    TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff

    REAL(KIND=dp), POINTER :: U_Integ(:), V_Integ(:), W_Integ(:), S_Integ(:)
    REAL(KIND=dp), ALLOCATABLE :: SumOfWeights(:)
    REAL(KIND=dp) :: Conductivity(3,3,Model % MaxElementNodes)
    REAL(KIND=dp) :: ddBasisddx(Model % MaxElementNodes,3,3)
    REAL(KIND=dp) :: Basis(Model % MaxElementNodes)
    REAL(KIND=dp) :: dBasisdx(Model % MaxElementNodes,3)
    REAL(KIND=DP) :: SqrtElementMetric, ECond, ElemVol
    REAL(KIND=dp) :: ElementPot(Model % MaxElementNodes)
    REAL(KIND=dp) :: Current(3)
    REAL(KIND=dp) :: s, ug, vg, wg, Grad(3), EpsGrad(3)
    REAL(KIND=dp) :: SqrtMetric, Metric(3,3), Symb(3,3,3), dSymb(3,3,3,3)
    REAL(KIND=dp) :: HeatingDensity, x, y, z
    INTEGER, POINTER :: NodeIndexes(:)
    INTEGER :: N_Integ, t, tg, i, j, k
    LOGICAL :: Stat

!------------------------------------------------------------------------------

    ALLOCATE( Nodes % x( Model % MaxElementNodes ) )
    ALLOCATE( Nodes % y( Model % MaxElementNodes ) )
    ALLOCATE( Nodes % z( Model % MaxElementNodes ) )
    ALLOCATE( SumOfWeights( Model % NumberOfNodes ) )

    SumOfWeights = 0.0d0
    HeatingTot = 0.0d0
    IF ( CalculateHeating )  Heating = 0.0d0
    IF ( CalculateCurrent )  VolCurrent = 0.0d0
    IF ( CalculateConductivity )  ElectricCond = 0.0d0

!------------------------------------------------------------------------------
!   Go through model elements, we will compute on average of elementwise
!   fluxes to nodes of the model
!------------------------------------------------------------------------------
    DO t = 1,Solver % NumberOfActiveElements
!------------------------------------------------------------------------------
!        Check if this element belongs to a body where electrostatics
!        should be calculated
!------------------------------------------------------------------------------
       Element => Solver % Mesh % Elements( Solver % ActiveElements( t ) )
       NodeIndexes => Element % NodeIndexes

       n = Element % TYPE % NumberOfNodes

       IF ( ANY(Reorder(NodeIndexes) == 0) ) CYCLE

       ElementPot = Potential( Reorder( NodeIndexes ) )
       
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
            'Electric Conductivity', Cwrk, n, NodeIndexes, gotIt )

       Conductivity = 0.0d0
       IF ( SIZE(Cwrk,1) == 1 ) THEN
          DO i=1,3
             Conductivity( i,i,1:n ) = Cwrk( 1,1,1:n )
          END DO
       ELSE IF ( SIZE(Cwrk,2) == 1 ) THEN
          DO i=1,MIN(3,SIZE(Cwrk,1))
             Conductivity(i,i,1:n) = Cwrk(i,1,1:n)
          END DO
          CalculateConductivity = .FALSE.
       ELSE
          DO i=1,MIN(3,SIZE(Cwrk,1))
             DO j=1,MIN(3,SIZE(Cwrk,2))
                Conductivity( i,j,1:n ) = Cwrk(i,j,1:n)
             END DO
          END DO
          CalculateConductivity = .FALSE.
       END IF

!------------------------------------------------------------------------------
! Need density for changing joule heating unit from W/m3 to W/kg
!------------------------------------------------------------------------------

       Density(1:n) =  ListGetReal( Model % Materials(k) % Values, &
            'Density', n, NodeIndexes, gotIt, minv=0.0d0 )
!------------------------------------------------------------------------------
! If density is not given, use W/m3
!------------------------------------------------------------------------------
       IF ( .NOT. GotIt )  Density = 1.0d0

       HeatingDensity = 0.0d0
       Current = 0.0d0
       ECond = 0.0d0
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
                EpsGrad(j) = EpsGrad(j) + SUM( Conductivity(j,i,1:n) * &
                     Basis(1:n) ) * SUM( dBasisdx(1:n,i) * ElementPot(1:n) )
             END DO
          END DO

          HeatingTot = HeatingTot + &
               s * SUM( Grad(1:DIM) * EpsGrad(1:DIM) )

          HeatingDensity = HeatingDensity + &
               s * SUM( Grad(1:DIM) * EpsGrad(1:DIM) ) / &
               SUM( Density(1:n) * Basis(1:n) )
          DO j = 1,DIM
             Current(j) = Current(j) - EpsGrad(j) * s
          END DO
          ECond = ECond + SUM( Conductivity(1,1,1:n) * Basis(1:n) ) * s

          ElemVol = ElemVol + s

       END DO! of the Gauss integration points

!------------------------------------------------------------------------------
!   Weight with element area if required
!------------------------------------------------------------------------------

       IF ( ConstantWeights ) THEN
         HeatingDensity = HeatingDensity / ElemVol
         Current(1:Dim) = Current(1:Dim) / ElemVol
         ECond = Econd / ElemVol
         SumOfWeights( Reorder( NodeIndexes(1:n) ) ) = &
             SumOfWeights( Reorder( NodeIndexes(1:n) ) ) + 1
       ELSE
         SumOfWeights( Reorder( NodeIndexes(1:n) ) ) = &
             SumOfWeights( Reorder( NodeIndexes(1:n) ) ) + ElemVol
       END IF

!------------------------------------------------------------------------------

       IF ( CalculateHeating ) THEN
          Heating( Reorder(NodeIndexes(1:n)) ) = &
               Heating( Reorder(NodeIndexes(1:n)) ) + HeatingDensity
       END IF

       IF ( CalculateConductivity ) THEN
          ElectricCond( Reorder(NodeIndexes(1:n)) ) = &
               ElectricCond( Reorder(NodeIndexes(1:n)) ) + ECond
       END IF
        
       IF ( CalculateCurrent ) THEN
          DO j=1,DIM 
             VolCurrent(DIM*(Reorder(NodeIndexes(1:n))-1)+j) = &
                  VolCurrent(DIM*(Reorder(NodeIndexes(1:n))-1)+j) + &
                  Current(j)
          END DO
       END IF

    END DO! of the bulk elements

!------------------------------------------------------------------------------
!   Finally, compute average of the fluxes at nodes
!------------------------------------------------------------------------------

    DO i = 1, Model % NumberOfNodes
       IF ( ABS( SumOfWeights(i) ) > 0.0D0 ) THEN
          IF ( CalculateHeating )  Heating(i) = Heating(i) / SumOfWeights(i)
          IF ( CalculateConductivity )  ElectricCond(i) = &
               ElectricCond(i) / SumOfWeights(i)
          DO j = 1, DIM
             IF ( CalculateCurrent )  VolCurrent(DIM*(i-1)+j) = &
                  VolCurrent(DIM*(i-1)+j) /  SumOfWeights(i)
          END DO
       END IF
    END DO

   DEALLOCATE( Nodes % x, &
       Nodes % y, &
       Nodes % z, &
       SumOfWeights)

!------------------------------------------------------------------------------
   END SUBROUTINE GeneralCurrent
!------------------------------------------------------------------------------

 
!------------------------------------------------------------------------------
     SUBROUTINE StatCurrentCompose( StiffMatrix,Force,Conductivity, &
                            Load,Element,n,Nodes )
!DLLEXPORT StatCurrentCompose
!------------------------------------------------------------------------------
       REAL(KIND=dp) :: StiffMatrix(:,:),Force(:),Load(:), Conductivity(:,:,:)
       INTEGER :: n
       TYPE(Nodes_t) :: Nodes
       TYPE(Element_t), POINTER :: Element
!------------------------------------------------------------------------------
 
       REAL(KIND=dp) :: SqrtMetric,Metric(3,3),Symb(3,3,3),dSymb(3,3,3,3)
       REAL(KIND=dp) :: Basis(n),dBasisdx(n,3),ddBasisddx(n,3,3)
       REAL(KIND=dp) :: SqrtElementMetric,U,V,W,S,A,L,C(3,3),x,y,z
       LOGICAL :: Stat

       INTEGER :: i,p,q,t,DIM
 
       TYPE(GaussIntegrationPoints_t) :: IntegStuff
 
!------------------------------------------------------------------------------
       DIM = CoordinateSystemDimension()

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

         L = SUM( Load(1:n) * Basis )
         DO i=1,DIM
            DO j=1,DIM
               C(i,j) = SUM( Conductivity(i,j,1:n) * Basis(1:n) )
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
         END DO
!------------------------------------------------------------------------------
       END DO
!------------------------------------------------------------------------------
     END SUBROUTINE StatCurrentCompose
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   SUBROUTINE StatCurrentBoundary( BoundaryMatrix, BoundaryVector, &
        LoadVector, Element, n, Nodes )
!DLLEXPORT StatCurrentBoundary
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
     REAL(KIND=dp) :: Force
     REAL(KIND=dp), POINTER :: U_Integ(:),V_Integ(:),W_Integ(:),S_Integ(:)

     INTEGER :: t,q,N_Integ

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

       DO q=1,N
         BoundaryVector(q) = BoundaryVector(q) + s * Basis(q) * Force
       END DO
     END DO
   END SUBROUTINE StatCurrentBoundary
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
 END SUBROUTINE StatCurrentSolver
!------------------------------------------------------------------------------
