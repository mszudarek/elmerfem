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
! * Module containing a solver for heat equation
! *
! ******************************************************************************
! *
! *                     Author:       Juha Ruokolainen
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
! *                Modified by:
! *
! *       Date of modification:
! *
! *****************************************************************************/

!------------------------------------------------------------------------------
   SUBROUTINE HeatSolver( Model,Solver,Timestep,TransientSimulation )
DLLEXPORT HeatSolver
!------------------------------------------------------------------------------
!******************************************************************************
!
!  Solve the heat equation !
!
!  ARGUMENTS:
!
!  TYPE(Model_t) :: Model,  
!     INPUT: All model information (mesh,materials,BCs,etc...)
!
!  TYPE(Solver_t) :: Solver
!     INPUT: Linear equation solver options
!
!  REAL(KIND=dp) :: Timestep
!     INPUT: Timestep size for time dependent simulations
!
!******************************************************************************
! $Log: HeatSolve.f90,v $
! Revision 1.104  2005/04/19 08:53:46  jpr
! Renamed module LUDecomposition as LinearAlgebra.
!
! Revision 1.103  2005/04/15 12:03:26  jpr
! Modified the Heat Gap-scheme, added keyword: Heat Gap Implicit.
!
! Revision 1.100  2004/10/04 16:30:11  raback
! Minor Smart Heater Contol modifications
!
! Revision 1.99  2004/09/27 09:32:23  jpr
! Removed some old, inactive code.
!
! Revision 1.98  2004/09/24 12:16:02  jpr
! Added 'user defined' and 'thermal' compressibility models.
!
! Revision 1.96  2004/08/06 09:03:08  raback
! Added possibility for partially implicit/explicit radiation factors.
! Affects the structure Factors_t
!
! Revision 1.94  2004/05/30 15:55:19  raback
! Improved initial guess for smart heater solver temperatures.
!
! Revision 1.93  2004/05/28 18:47:11  raback
! Added Smart Solver Tolerance
!
! Revision 1.92  2004/05/20 14:34:32  raback
! Partially open cavities may now be modeled.
!
! Revision 1.89  2004/04/27 09:41:40  raback
! Enabling matrix topology changes due to radiation.
!
! Revision 1.88  2004/03/03 09:12:00  jpr
! Added 3rd argument to GetLocical(...) to stop the complaint about
! missing "Output Version Numbers" keyword.
!
! Revision 1.87  2004/03/02 07:22:36  jpr
! Corrected a bug which set the #nonlinear iterations=1, if newton after
! iter keyword was not given.
!
! Revision 1.85  2004/03/01 14:59:55  jpr
! Modified interfaces of residual functions for goal oriented adaptivity
! (no functionality yet).
! Started log.
!
!------------------------------------------------------------------------------
     USE DiffuseConvective
     USE DiffuseConvectiveGeneral

     USE Differentials
     USE Radiation
     USE MaterialModels

     USE Adaptive
     USE DefUtils

!------------------------------------------------------------------------------
     IMPLICIT NONE
!------------------------------------------------------------------------------

     INTEGER, PARAMETER :: PHASE_SPATIAL_1 = 1
     INTEGER, PARAMETER :: PHASE_SPATIAL_2 = 2
     INTEGER, PARAMETER :: PHASE_TEMPORAL  = 3
    
     TYPE(Model_t)  :: Model
     TYPE(Solver_t) :: Solver

     LOGICAL :: TransientSimulation
     REAL(KIND=dp) :: Timestep
!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------
     TYPE(Matrix_t), POINTER :: StiffMatrix

     INTEGER :: i,j,k,l,m,n,t,tt,iter,k1,k2,body_id,eq_id,istat,LocalNodes,bf_id

     TYPE(Nodes_t)   :: ElementNodes
     TYPE(Element_t),POINTER :: Element,RadiationElement

     REAL(KIND=dp) :: RelativeChange, &
           Norm,PrevNorm,Text,S,C,C1,Emissivity,StefanBoltzmann, &
           ReferencePressure=0.0d0, SpecificHeatRatio

     CHARACTER(LEN=MAX_NAME_LEN) :: RadiationFlag,ConvectionFlag

     INTEGER :: PhaseChangeModel
     CHARACTER(LEN=MAX_NAME_LEN) :: PhaseModel

     INTEGER, POINTER :: NodeIndexes(:)
     LOGICAL :: Stabilize = .TRUE., Bubbles = .TRUE., UseBubbles,NewtonLinearization = .FALSE., &
         Found, GotIt
! Which compressibility model is used
     CHARACTER(LEN=MAX_NAME_LEN) :: CompressibilityFlag
     INTEGER :: CompressibilityModel

     LOGICAL :: AllocationsDone = .FALSE.,PhaseSpatial=.FALSE., &
        PhaseChange=.FALSE., CheckLatentHeatRelease=.FALSE., FirstTime, &
        HeaterControl, HeaterControlLocal, SmartTolReached=.FALSE.

     TYPE(Variable_t), POINTER :: TempSol,FlowSol,CurrentSol, MeshSol, DensitySol
     TYPE(ValueList_t), POINTER :: Equation,Material,SolverParams,BodyForce,BC,Constants

     INTEGER, POINTER :: TempPerm(:),FlowPerm(:),CurrentPerm(:),MeshPerm(:), ControlHeaters(:)

     INTEGER :: NSDOFs,NewtonIter,NonlinearIter,MDOFs, NOFControlHeaters
     REAL(KIND=dp) :: NonlinearTol,NewtonTol,SmartTol,Relax, &
            SaveRelax,dt,CumulativeTime, VisibleFraction

     REAL(KIND=dp), POINTER :: Temperature(:),FlowSolution(:), &
       ElectricCurrent(:), PhaseChangeIntervals(:,:),ForceVector(:), &
       PrevSolution(:), HC(:), Hwrk(:,:,:),MeshVelocity(:), XX(:), YY(:),ForceHeater(:)

     REAL(KIND=dp), ALLOCATABLE :: TSolution(:),TSolution1(:), vals(:)

     REAL(KIND=dp) :: Jx,Jy,Jz,JAbs, Power, MeltPoint

     REAL(KIND=dp), ALLOCATABLE :: MASS(:,:), &
       STIFF(:,:), LOAD(:), HeatConductivity(:,:,:), &
       FORCE(:), U(:), V(:), W(:), MU(:,:),TimeForce(:), &
       Density(:), HeatTransferCoeff(:), &
       HeatCapacity(:), Enthalpy(:), Viscosity(:), LocalTemperature(:), &
       ElectricConductivity(:), Permeability(:), Work(:), C0(:), &
       Pressure(:), GasConstant(:),AText(:), HeaterArea(:), &
       HeaterDensity(:), HeaterSource(:), HeatExpansionCoeff(:), &
       ReferenceTemperature(:)

     SAVE U, V, W, MU, MASS, STIFF, LOAD, &
       FORCE, ElementNodes, HeatConductivity, HeatCapacity, HeatTransferCoeff, &
       Enthalpy, Density, AllocationsDone, Viscosity, TimeForce, &
       LocalNodes, LocalTemperature, Work, ElectricConductivity, &
       Permeability, TSolution, TSolution1, C0, Pressure, &
       GasConstant,AText,Hwrk, XX, YY, ForceHeater, Power, HeaterArea,  &
       HeaterDensity, HeaterSource, ControlHeaters, SmartTolReached,    &
       ReferenceTemperature, HeatExpansionCoeff


     INTERFACE
        FUNCTION HeatBoundaryResidual( Model,Edge,Mesh,Quant,Perm,Gnorm ) RESULT(Indicator)
          USE Types
          TYPE(Element_t), POINTER :: Edge
          TYPE(Model_t) :: Model
          TYPE(Mesh_t), POINTER :: Mesh
          REAL(KIND=dp) :: Quant(:), Indicator(2), Gnorm
          INTEGER :: Perm(:)
        END FUNCTION HeatBoundaryResidual

        FUNCTION HeatEdgeResidual( Model,Edge,Mesh,Quant,Perm ) RESULT(Indicator)
          USE Types
          TYPE(Element_t), POINTER :: Edge
          TYPE(Model_t) :: Model
          TYPE(Mesh_t), POINTER :: Mesh
          REAL(KIND=dp) :: Quant(:), Indicator(2)
          INTEGER :: Perm(:)
        END FUNCTION HeatEdgeResidual

        FUNCTION HeatInsideResidual( Model,Element,Mesh,Quant,Perm, Fnorm ) RESULT(Indicator)
          USE Types
          TYPE(Element_t), POINTER :: Element
          TYPE(Model_t) :: Model
          TYPE(Mesh_t), POINTER :: Mesh
          REAL(KIND=dp) :: Quant(:), Indicator(2), Fnorm
          INTEGER :: Perm(:)
        END FUNCTION HeatInsideResidual
     END INTERFACE

     REAL(KIND=dp) :: at,at0,totat,st,totst,t1,CPUTime,RealTime

     CHARACTER(LEN=MAX_NAME_LEN) :: VersionID = "$Id: HeatSolve.f90,v 1.104 2005/04/19 08:53:46 jpr Exp $"

!------------------------------------------------------------------------------
!    Check if version number output is requested
!------------------------------------------------------------------------------
     IF ( .NOT. AllocationsDone ) THEN
        IF ( ListGetLogical( GetSimulation(), 'Output Version Numbers', Found ) ) THEN
           CALL Info( 'HeatSolve', 'HeatSolver version:', Level = 0 ) 
           CALL Info( 'HeatSolve', VersionID, Level = 0 ) 
           CALL Info( 'HeatSolve', ' ', Level = 0 ) 
        END IF
     END IF

!------------------------------------------------------------------------------
!    The View and Gebhardt factors may change. If this is necessary, this is 
!    done within this subroutine. The routine is called in the
!    start as it may affect the matrix topology.
!------------------------------------------------------------------------------
    CALL RadiationFactors( Solver, .FALSE.)

!------------------------------------------------------------------------------
!    Get variables needed for solution
!------------------------------------------------------------------------------

     IF ( .NOT. ASSOCIATED( Solver % Matrix ) ) RETURN

     StiffMatrix => Solver % Matrix
     ForceVector => Solver % Matrix % RHS

     TempSol => Solver % Variable
     TempPerm    => TempSol % Perm
     Temperature => TempSol % Values

     LocalNodes = COUNT( TempPerm > 0 )
     IF ( LocalNodes <= 0 ) RETURN

     FlowSol => VariableGet( Solver % Mesh % Variables, 'Flow Solution' )
     IF ( ASSOCIATED( FlowSol ) ) THEN
       FlowPerm     => FlowSol % Perm
       NSDOFs       =  FlowSol % DOFs
       FlowSolution => FlowSol % Values
     END IF

     DensitySol => VariableGet( Solver % Mesh % Variables, 'Density' )

     HeaterControl = .FALSE.
     NOFControlHeaters = 0
     IF ( Model % NumberOfBodyForces > 0 ) THEN
        IF ( .NOT. AllocationsDone ) ALLOCATE( ControlHeaters(Model % NumberOfBodyForces) )

        DO i = 1,Model % NumberOfBodyForces
           HeaterControlLocal = ListGetLogical( &
               Model % BodyForces(i) % Values, 'Smart Heater Control', Found )
           HeaterControl = HeaterControl .OR. HeaterControlLocal

           IF ( HeaterControlLocal ) THEN
              NOFControlHeaters = NOFControlHeaters + 1
              ControlHeaters(i) = NOFControlHeaters
           END IF
        END DO
        HeaterControlLocal = .FALSE.
     END IF
!------------------------------------------------------------------------------
!    Allocate some permanent storage, this is done first time only
!------------------------------------------------------------------------------
     IF ( .NOT. AllocationsDone .OR. Solver % Mesh % Changed ) THEN
       N = Solver % Mesh % MaxElementNodes

       IF ( AllocationsDone ) THEN
          DEALLOCATE(  &
                 U, V, W, MU,           &
                 Pressure,              &
                 ElementNodes % x,      &
                 ElementNodes % y,      &
                 ElementNodes % z,      &
                 Density,Work,          &
                 ElectricConductivity,  &
                 Permeability,          &
                 Viscosity,C0,          &
                 HeatTransferCoeff,     &
                 HeatExpansionCoeff,    &
                 ReferenceTemperature,  &
                 MASS,       &
                 LocalTemperature,      &
                 HeatCapacity,Enthalpy, &
                 GasConstant, AText,    &
                 HeatConductivity,            &
                 STIFF,LOAD, &
                 FORCE, TimeForce )
       END IF

       ALLOCATE( &
                 U( N ),   V( N ),  W( N ),            &
                 MU( 3,N ),                            &
                 Pressure( N ),                        &
                 ElementNodes % x( N ),                &
                 ElementNodes % y( N ),                &
                 ElementNodes % z( N ),                &
                 Density( N ),Work( N ),               &
                 ElectricConductivity(N),              &
                 Permeability(N),                      &
                 Viscosity(N),C0(N),                   &
                 HeatTransferCoeff( N ),               &
                 HeatExpansionCoeff( N ),              &
                 ReferenceTemperature( N ),            &
                 MASS(  2*N,2*N ),                     &
                 LocalTemperature( N ),                &
                 HeatCapacity( N ),Enthalpy( N ),      &
                 GasConstant( N ),AText( N ),          &
                 HeatConductivity( 3,3,N ),            &
                 STIFF( 2*N,2*N ),LOAD( N ), &
                 FORCE( 2*N ), TimeForce(2*N), STAT=istat )

       IF ( istat /= 0 ) THEN
         CALL Fatal( 'HeatSolve', 'Memory allocation error' )
       END IF

 
       NULLIFY( ForceHeater )
       IF ( HeaterControl ) THEN
          IF ( AllocationsDone ) DEALLOCATE( XX, YY, ForceHeater, HeaterArea, &
                          HeaterDensity, HeaterSource )

          n = SIZE( Temperature )
          ALLOCATE( XX( n ), YY(n), ForceHeater( n ), STAT=istat )
          XX = 0.0d0 
          YY = 0.0d0
          ALLOCATE( HeaterArea(NOFControlHeaters), HeaterDensity(NOFControlHeaters), &
                              HeaterSource(NOFControlHeaters) )
          IF ( istat /= 0 ) THEN
            CALL Fatal( 'HeatSolve', 'Memory allocation error' )
          END IF
          
       END IF

       NULLIFY( Hwrk )
       AllocationsDone = .TRUE.
     END IF

!------------------------------------------------------------------------------
!    Do some additional initialization, and go for it
!------------------------------------------------------------------------------
     Constants => GetConstants()
     StefanBoltzmann = ListGetConstReal( Model % Constants, &
                     'Stefan Boltzmann' )
!------------------------------------------------------------------------------
     SolverParams => GetSolverParams()
     Stabilize = GetLogical( SolverParams,'Stabilize',Found )

     UseBubbles = GetLogical( SolverParams,'Bubbles',Found )
     IF ( .NOT.Found ) UseBubbles = .TRUE.

     NonlinearIter = GetInteger(   SolverParams, &
                     'Nonlinear System Max Iterations', Found )
     IF ( .NOT.Found ) NonlinearIter = 1

     NonlinearTol  = GetConstReal( SolverParams, &
                     'Nonlinear System Convergence Tolerance',    Found )

     NewtonTol     = GetConstReal( SolverParams, &
                      'Nonlinear System Newton After Tolerance',  Found )

     NewtonIter    = GetInteger(   SolverParams, &
                      'Nonlinear System Newton After Iterations', Found )
     IF ( NewtonIter == 0) NewtonLinearization = .TRUE.

     Relax = GetConstReal( SolverParams, &
               'Nonlinear System Relaxation Factor',Found )
     IF ( .NOT.Found ) Relax = 1

     IF(HeaterControl) THEN
       SmartTol  = GetConstReal( SolverParams, &
           'Smart Heater Control After Tolerance',  Found )
       IF(.NOT. Found) SmartTol = 1.0
     END IF

!------------------------------------------------------------------------------

     SaveRelax = Relax
     dt = Timestep
     CumulativeTime = 0.0d0

!------------------------------------------------------------------------------
     FirstTime = .TRUE.
     
     DO WHILE( CumulativeTime < Timestep-1.0d-12 .OR. .NOT. TransientSimulation )

!------------------------------------------------------------------------------
!    The first time around this has been done by the caller...
!------------------------------------------------------------------------------
     IF ( TransientSimulation .AND. .NOT.FirstTime ) THEN
       CALL InitializeTimestep( Solver )
     END IF
     FirstTime = .FALSE.
!------------------------------------------------------------------------------
!    Save current solution
!------------------------------------------------------------------------------
     ALLOCATE( PrevSolution(LocalNodes) )
     PrevSolution = Temperature(1:LocalNodes)
!------------------------------------------------------------------------------

     totat = 0.0d0
     totst = 0.0d0

     Norm = Solver % Variable % Norm

     DO iter=1,NonlinearIter
       at  = CPUTime()
       at0 = RealTime()

       CALL Info( 'HeatSolve', ' ', Level=4 )
       CALL Info( 'HeatSolve', ' ', Level=4 )
       CALL Info( 'HeatSolve', '-------------------------------------',Level=4 )
       WRITE( Message,* ) 'TEMPERATURE ITERATION', iter
       CALL Info( 'HeatSolve', Message, Level=4 )
       CALL Info( 'HeatSolve', '-------------------------------------',Level=4 )
       CALL Info( 'HeatSolve', ' ', Level=4 )
       CALL Info( 'HeatSolve', 'Starting Assembly...', Level=4 )

!------------------------------------------------------------------------------
       CALL DefaultInitialize()
!------------------------------------------------------------------------------
       IF ( HeaterControl ) THEN
         ForceHeater = 0.0d0
         HeaterArea = 0.0d0
         HeaterSource = 0.0d0
         HeaterControlLocal = .FALSE.
       END IF
!------------------------------------------------------------------------------
       body_id = -1
       NULLIFY(Material)
!------------------------------------------------------------------------------
!      Bulk elements
!------------------------------------------------------------------------------
       DO t=1,Solver % NumberOfActiveElements

         IF ( RealTime() - at0 > 1.0 ) THEN
           WRITE(Message,'(a,i3,a)' ) '   Assembly: ', INT(100.0 - 100.0 * &
            (Solver % NumberOfActiveElements-t) / &
               (1.0*Solver % NumberOfActiveElements)), ' % done'
                       
           CALL Info( 'HeatSolve', Message, Level=5 )

           at0 = RealTime()
         END IF
!------------------------------------------------------------------------------
!        Check if this element belongs to a body where temperature 
!        should be calculated
!------------------------------------------------------------------------------
         Element => GetActiveElement(t)

!------------------------------------------------------------------------------
         IF ( Element % BodyId /= body_id ) THEN
!------------------------------------------------------------------------------
           Equation => GetEquation()
           ConvectionFlag = GetString( Equation, 'Convection', Found )

           Material => GetMaterial()
!------------------------------------------------------------------------------
           CompressibilityFlag = GetString( Material, &
                 'Compressibility Model', Found)
           IF ( .NOT.Found ) CompressibilityModel = Incompressible

           SELECT CASE( CompressibilityFlag )

             CASE( 'incompressible' )
               CompressibilityModel = Incompressible

             CASE( 'user defined' )
               CompressibilityModel = UserDefined1

             CASE( 'perfect gas', 'perfect gas equation 1' )
               CompressibilityModel = PerfectGas1

             CASE( 'thermal' )
               CompressibilityModel = Thermal

             CASE DEFAULT
               CompressibilityModel = Incompressible
           END SELECT
!------------------------------------------------------------------------------

           PhaseModel = GetString( Equation, 'Phase Change Model',Found )

           PhaseChange = Found .AND. (PhaseModel(1:4) /= 'none')
           IF ( PhaseChange ) THEN
              CheckLatentHeatRelease = GetLogical( Equation, &
                   'Check Latent Heat Release',Found )
           END IF
         END IF
!------------------------------------------------------------------------------

         n = GetElementNOFNodes()
         CALL GetElementNodes( ElementNodes )

         CALL GetScalarLocalSolution( LocalTemperature )
!------------------------------------------------------------------------------
!        Get element material parameters
!------------------------------------------------------------------------------
         HeatCapacity(1:n) = GetReal( Material, 'Heat Capacity', Found )

         CALL ListGetRealArray( Material,'Heat Conductivity',Hwrk,n, &
                      Element % NodeIndexes )

         HeatConductivity = 0.0d0
         IF ( SIZE(Hwrk,1) == 1 ) THEN
           DO i=1,3
             HeatConductivity( i,i,1:n ) = Hwrk( 1,1,1:n )
           END DO
         ELSE IF ( SIZE(Hwrk,2) == 1 ) THEN
           DO i=1,MIN(3,SIZE(Hwrk,1))
             HeatConductivity(i,i,1:n) = Hwrk(i,1,1:n)
           END DO
         ELSE
           DO i=1,MIN(3,SIZE(Hwrk,1))
             DO j=1,MIN(3,SIZE(Hwrk,2))
               HeatConductivity( i,j,1:n ) = Hwrk(i,j,1:n)
             END DO
           END DO
         END IF
!------------------------------------------------------------------------------

         IF ( CompressibilityModel == PerfectGas1 ) THEN

           ! Read Specific Heat Ratio:
           !--------------------------
           SpecificHeatRatio = GetConstReal( Material, &
               'Specific Heat Ratio', Found )
           IF ( .NOT.Found ) SpecificHeatRatio = 5.d0/3.d0

           ! For an ideal gas, \gamma, c_p and R are really a constant
           ! GasConstant is an array only since HeatCapacity formally is:
           !-------------------------------------------------------------
           GasConstant(1:n) = ( SpecificHeatRatio - 1.d0 ) * &
               HeatCapacity(1:n) / SpecificHeatRatio
         ELSE IF ( CompressibilityModel == Thermal ) THEN
           HeatExpansionCoeff(1:n) = ListGetReal( Material, &
             'Heat Expansion Coefficient',n,NodeIndexes )

           ReferenceTemperature(1:n) = ListGetReal( Material, &
             'Reference Temperature',n,NodeIndexes )

           Density(1:n) = ListGetReal( Material,'Density',n,NodeIndexes )
           Density(1:n) = Density(1:n) * ( 1 - HeatExpansionCoeff(1:n)  * &
                ( LocalTemperature(1:n) - ReferenceTemperature(1:n) ) )
         ELSE IF ( CompressibilityModel == UserDefined1 ) THEN
           IF ( ASSOCIATED( DensitySol ) ) THEN
             CALL GetScalarLocalSolution( Density, 'Density' ) 
           ELSE
             Density(1:n) = GetReal( Material,'Density' )
           END IF
         ELSE
           Density(1:n) = GetReal( Material, 'Density' )
         END IF

!------------------------------------------------------------------------------
! Take pressure deviation p_d as the dependent variable, p = p_0 + p_d
! for PerfectGas1 and PerfectGas2.
! Read p_0
!------------------------------------------------------------------------------
         IF ( CompressibilityModel /= Incompressible ) THEN
           ReferencePressure = ListGetConstReal( Material, &
               'Reference Pressure', Found)
           IF ( .NOT.Found ) ReferencePressure = 0.0d0
         END IF
!------------------------------------------------------------------------------

         HeaterControlLocal = .FALSE.
         LOAD = 0.0D0
         Pressure = 0.0d0
!------------------------------------------------------------------------------
!        Check for convection model
!------------------------------------------------------------------------------
         C1 = 1.0D0

         IF ( ConvectionFlag == 'constant' ) THEN
           U(1:n) = GetReal( Material, 'Convection Velocity 1', Found )
           V(1:n) = GetReal( Material, 'Convection Velocity 2', Found )
           W(1:n) = GetReal( Material, 'Convection Velocity 3', Found )
         ELSE IF ( ConvectionFlag == 'computed' ) THEN
           DO i=1,n
             k = FlowPerm(Element % NodeIndexes(i))
             IF ( k > 0 ) THEN
!------------------------------------------------------------------------------
               SELECT CASE( CompressibilityModel )
                 CASE( PerfectGas1 )
                   Pressure(i) = FlowSolution(NSDOFs*k) + ReferencePressure
                   Density(i)  = Pressure(i) / &
                       ( GasConstant(i) * LocalTemperature(i) )
                 CASE( UserDefined1, Thermal )
                   Pressure(i) = FlowSolution(NSDOFs*k) + ReferencePressure
               END SELECT
!------------------------------------------------------------------------------

               SELECT CASE( NSDOFs )
               CASE(3)
                 U(i) = FlowSolution( NSDOFs*k-2 )
                 V(i) = FlowSolution( NSDOFs*k-1 )
                 W(i) = 0.0D0

               CASE(4)
                 U(i) = FlowSolution( NSDOFs*k-3 )
                 V(i) = FlowSolution( NSDOFs*k-2 )
                 W(i) = FlowSolution( NSDOFs*k-1 )
               END SELECT
             ELSE
               U(i) = 0.0d0
               V(i) = 0.0d0
               W(i) = 0.0d0
             END IF
           END DO
         ELSE  ! Conduction only
           C1 = 0.0D0 
         END IF

         MU = 0.0d0
         CALL GetVectorLocalSolution( MU, 'Mesh Velocity' )
!------------------------------------------------------------------------------
!        Check if modelling Phase Change 
!------------------------------------------------------------------------------
         PhaseSpatial = .FALSE.
         IF (  PhaseChange ) THEN
           CALL EffectiveHeatCapacity
         ELSE
           IF ( CompressibilityModel == PerfectGas1 ) THEN
             HeatCapacity(1:n) = Density(1:n) * HeatCapacity(1:n) &
                          / SpecificHeatRatio
           ELSE
             HeatCapacity(1:n) = Density(1:n) * HeatCapacity(1:n)
           END IF
         END IF

         Viscosity = 0.0d0
!------------------------------------------------------------------------------
!        Add body forces, if any
!------------------------------------------------------------------------------
         BodyForce => GetBodyForce()
         IF ( ASSOCIATED( BodyForce ) ) THEN
           bf_id = GetBodyForceId()
!------------------------------------------------------------------------------
!          Frictional viscous heating
!------------------------------------------------------------------------------
           IF ( GetLogical( BodyForce, 'Friction Heat',Found) ) THEN
              Viscosity(1:n) = GetReal( Material,'Viscosity' )
           END IF
!------------------------------------------------------------------------------
!          Given heat source
!------------------------------------------------------------------------------
           LOAD(1:n) = LOAD(1:n) + Density(1:n) *  &
              GetReal( BodyForce, 'Heat Source', Found )

           IF ( HeaterControl .AND. NewtonLinearization .AND. SmartTolReached) THEN
             HeaterControlLocal = GetLogical( BodyForce, 'Smart Heater Control', Found )

             IF (  HeaterControlLocal ) THEN
               LOAD(1:n) = -LOAD(1:n)
               k = ControlHeaters(bf_id)
               s = ElementArea( Solver % Mesh, Element, n )
               HeaterDensity(k) = SUM( Density(1:n) ) / n
               HeaterArea(k) = HeaterArea(k) + s
               HeaterSource(k) = HeaterSource(k) - s * SUM(LOAD(1:n))/n
             END IF
           END IF

         END IF

!------------------------------------------------------------------------------
!        Get element local matrices, and RHS vectors
!------------------------------------------------------------------------------
         C0 = 0.0d0
!------------------------------------------------------------------------------
! Note at this point HeatCapacity = \rho * c_p OR \rho * (c_p - R)
! and C1 = 0 (diffusion) or 1 (convection)
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
         IF ( CurrentCoordinateSystem() == Cartesian ) THEN
!------------------------------------------------------------------------------
           CALL DiffuseConvectiveCompose( &
               MASS, STIFF, FORCE, LOAD, &
               HeatCapacity, C0, C1*HeatCapacity(1:n), HeatConductivity, &
               PhaseSpatial, LocalTemperature, Enthalpy, U, V, W, &
               MU(1,1:n),MU(2,1:n),MU(3,1:n), Viscosity, Density, Pressure, &
               CompressibilityModel /= Incompressible, &
               Stabilize, Bubbles, Element, n, ElementNodes )

!------------------------------------------------------------------------------
         ELSE
!------------------------------------------------------------------------------
           CALL DiffuseConvectiveGenCompose( &
               MASS, STIFF, FORCE, LOAD, &
               HeatCapacity, C0, C1*HeatCapacity(1:n), HeatConductivity, &
               PhaseSpatial, LocalTemperature, Enthalpy, U, V, W, &
               MU(1,1:n),MU(2,1:n),MU(3,1:n), Viscosity, Density, Pressure, &
               CompressibilityModel /= Incompressible, &
               Stabilize, Element, n, ElementNodes )
!------------------------------------------------------------------------------
         END IF
!------------------------------------------------------------------------------

         IF ( HeaterControlLocal ) THEN
           IF ( TransientSimulation ) THEN
             TimeForce  = 0.0d0
             CALL Default1stOrderTime( MASS, STIFF, TimeForce )
           END IF
           
           CALL UpdateGlobalEquations( Solver % Matrix, STIFF, &
               ForceHeater, FORCE, n, 1, TempPerm(Element % NodeIndexes) )
         ELSE
            Bubbles = UseBubbles .AND. .NOT.Stabilize .AND. &
            ( ConvectionFlag == 'computed' .OR. ConvectionFlag == 'constant' )
            
!------------------------------------------------------------------------------
!           If time dependent simulation add mass matrix to stiff matrix
!------------------------------------------------------------------------------
            TimeForce  = FORCE
            IF ( TransientSimulation ) THEN
               IF ( Bubbles ) FORCE = 0.0d0
               CALL Default1stOrderTime( MASS,STIFF,FORCE )
            END IF
!------------------------------------------------------------------------------
!           Update global matrices from local matrices
!------------------------------------------------------------------------------
            IF (  Bubbles ) THEN
               CALL Condensate( N, STIFF, FORCE, TimeForce )
               IF (TransientSimulation) CALL DefaultUpdateForce( TimeForce )
            END IF

            CALL DefaultUpdateEquations( STIFF, FORCE )
         END IF
!------------------------------------------------------------------------------
      END DO     !  Bulk elements
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
!     Neumann & Newton boundary conditions
!------------------------------------------------------------------------------
      DO t=1, Solver % Mesh % NumberOfBoundaryElements

        Element => GetBoundaryElement(t)
        IF ( .NOT. ActiveBoundaryElement() ) CYCLE

        n = GetElementNOFNodes()
        IF ( GetElementFamily() == 1 ) CYCLE

        BC => GetBC()
        IF ( GetLogical( BC, 'Heat Flux BC',Found) ) THEN

          CALL GetElementNodes( ElementNodes )

          HeatTransferCoeff = 0.0D0
          LOAD  = 0.0D0
!------------------------------------------------------------------------------
!         BC: -k@T/@n = \epsilon\sigma(T^4 - Text^4)
!------------------------------------------------------------------------------
          RadiationFlag = GetString( BC, 'Radiation', Found )

          IF ( Found .AND. RadiationFlag(1:4) /= 'none' ) THEN

            Emissivity = SUM( GetReal(BC, 'Emissivity') ) / n
!------------------------------------------------------------------------------
            IF (  RadiationFlag(1:9) == 'idealized' ) THEN
               AText(1:n) = GetReal( BC, 'External Temperature' )
            ELSE
              CALL DiffuseGrayRadiation( Model, Solver, Element, & 
                  Temperature, TempPerm, ForceVector, VisibleFraction)
              IF( GetLogical( BC, 'Radiation Boundary Open', Found) ) THEN
                AText(1:n) = GetReal( BC, 'External Temperature' )
                Atext(1:n) = ( (1.0 - VisibleFraction) * Atext(1:n)**4.0 + &
                    VisibleFraction * Text ** 4.0 ) ** 0.25
              ELSE
                AText(1:n) = Text
              END IF
            END IF
!------------------------------------------------------------------------------
!           Add our own contribution to surface temperature (and external
!           if using linear type iteration or idealized radiation)
!------------------------------------------------------------------------------
            DO j=1,n
              k = TempPerm(Element % NodeIndexes(j))
              Text = AText(j)

              IF ( NewtonLinearization ) THEN
                 HeatTransferCoeff(j) = Emissivity * 4*Temperature(k)**3 * &
                                   StefanBoltzmann
                 LOAD(j) = Emissivity*(3*Temperature(k)**4+Text**4) * &
                                   StefanBoltzmann
              ELSE
                 HeatTransferCoeff(j) = Emissivity * (Temperature(k)**3 + &
                 Temperature(k)**2*Text+Temperature(k)*Text**2 + Text**3) * &
                                   StefanBoltzmann 
                 LOAD(j) = HeatTransferCoeff(j) * Text
              END IF
            END DO
          END IF  ! of radition
!------------------------------------------------------------------------------
          Work(1:n) = GetReal( BC, 'Heat Transfer Coefficient',Found )
          IF ( GetLogical( BC, 'Heat Gap', Found ) ) THEN
            IF ( GetLogical( BC, 'Heat Gap Implicit', Found ) ) THEN
               AText(1:n) = 0.0d0
             ELSE
               AText(1:n) = GapTemperature( Solver, Element, Temperature, TempPerm)
            END IF
          ELSE
            IF ( ANY(Work(1:n) /= 0.0d0) ) THEN
               AText(1:n) = GetReal( BC, 'External Temperature',Found )
            ELSE
               AText(1:n) = 0.0d0
            END IF
          END IF

          DO j=1,n
!------------------------------------------------------------------------------
!           BC: -k@T/@n = \alpha(T - Text)
!------------------------------------------------------------------------------
            k = TempPerm(Element % NodeIndexes(j))
            LOAD(j) = LOAD(j) + Work(j) * AText(j)

            HeatTransferCoeff(j) = HeatTransferCoeff(j) + Work(j)
          END DO
!------------------------------------------------------------------------------
!         BC: -k@T/@n = g
!------------------------------------------------------------------------------
          LOAD(1:n) = LOAD(1:n) +  GetReal( BC, 'Heat Flux', Found )
!------------------------------------------------------------------------------
!         Get element matrix and rhs due to boundary conditions ...
!------------------------------------------------------------------------------
          IF ( CurrentCoordinateSystem() == Cartesian ) THEN
            CALL DiffuseConvectiveBoundary( STIFF,FORCE, &
              LOAD,HeatTransferCoeff,Element,n,ElementNodes )
          ELSE
            CALL DiffuseConvectiveGenBoundary(STIFF,FORCE,&
              LOAD,HeatTransferCoeff,Element,n,ElementNodes ) 
          END IF

!------------------------------------------------------------------------------
!         Update global matrices from local matrices
!------------------------------------------------------------------------------
          IF ( TransientSimulation ) THEN
            MASS = 0.d0
            CALL Default1stOrderTime( MASS, STIFF, FORCE )
          END IF

          IF ( GetLogical( BC, 'Heat Gap', Found ) ) THEN
             IF ( GetLogical( BC, 'Heat Gap Implicit', Found ) ) &
               CALL AddHeatGap( Solver, Element, STIFF, TempPerm)
          END IF
          CALL DefaultUpdateEquations( STIFF, FORCE )
!------------------------------------------------------------------------------
        END IF ! of heat-flux bc
      END DO   ! Neumann & Newton BCs
!------------------------------------------------------------------------------

      CALL DefaultFinishAssembly()
      CALL DefaultDirichletBCs()

!------------------------------------------------------------------------------
      CALL Info( 'HeatSolve', 'Assembly done', Level=4 )

!------------------------------------------------------------------------------
!     Solve the system and check for convergence
!------------------------------------------------------------------------------
      at = CPUTime() - at
      st = CPUTime()

      PrevNorm = Norm

      IF(HeaterControl .AND. NewtonLinearization .AND. SmartTolReached) THEN
        Relax = GetConstReal( SolverParams, &
            'Nonlinear System Relaxation Factor', Found )
        
        IF ( Found .AND. Relax /= 1.0d0 ) THEN
          CALL ListAddConstReal( Solver % Values, &
              'Nonlinear System Relaxation Factor', 1.0d0 )
        ELSE
          Relax = 1.0d0
        END IF
        
        CALL SolveSystem( Solver % Matrix, ParMatrix, &
            ForceHeater, XX, Norm, 1, Solver )
        
        CALL SolveSystem( Solver % Matrix, ParMatrix, &
            Solver % Matrix % RHS, YY, Norm, 1, Solver )
        
        DO i=1,Model % NumberOfBCs
          GotIt = ListGetLogical( Model % BCs(i) % Values,'Smart Heater Boundary', Found ) 
          IF(GotIt) THEN
            MeltPoint = ListGetConstReal( Model % BCs(i) % Values,'Smart Heater Temperature')
            EXIT
          END IF
        END DO
        
        IF(.NOT. GotIt) THEN
          DO i=1,Model % NumberOfBCs
            GotIt = ListGetLogical( Model % BCs(i) % Values,'Phase Change', Found ) 
            IF(GotIt) EXIT
          END DO
          DO k=1, Model % NumberOfMaterials
            MeltPoint = ListGetConstReal( Model % Materials(k) % Values, &
                'Melting Point', Found )
            IF(Found) EXIT
          END DO
        END IF

        jx = -1.0d20
        DO k = Model % Mesh % NumberOfBulkElements + 1, &
            Model % Mesh % NumberOfBulkElements + Model % Mesh % NumberOfBoundaryElements
          
          Element => Model % Mesh % Elements(k)
          
          IF ( Element % BoundaryInfo % Constraint == i ) THEN
            DO l=1,Element % TYPE % NumberOfNodes
              IF ( Model % Mesh % Nodes % x(Element % NodeIndexes(l)) >= jx ) THEN
                j = Element % NodeIndexes(l) 
                jx = Model % Mesh % Nodes % x(Element % NodeIndexes(l))
              END IF
            END DO
          END IF
        END DO

        Power = ( YY(TempPerm(j)) - MeltPoint ) / XX(TempPerm(j))
        Temperature = YY - Power * XX
        
        Power = Power * SUM( HeaterSource(1:NOFControlHeaters) ) &
            / SUM( HeaterArea(1:NOFControlHeaters ) )

        SELECT CASE( CurrentCoordinateSystem() )
          CASE( AxisSymmetric, CylindricSymmetric )         
          HeaterArea(1:NOFControlHeaters) = 2*PI*HeaterArea(1:NOFControlHeaters)
        END SELECT 

        DO i=1,NOFControlHeaters
          s = Power * SUM( HeaterArea ) * HeaterSource(i) / ( SUM( HeaterSource ) )
          CALL Info( 'HeaterControl', ' ', Level=4 )
          WRITE( Message, * ) 'Controlled Heater: ', i
          CALL Info( 'HeaterControl', Message, Level=4 )
          WRITE( Message, * ) 'Heater Volume (m^3):     ', HeaterArea(i)
          CALL Info( 'HeaterControl', Message, Level=4 )
          WRITE( Message, * ) 'Heater Power (W):      ', s
          CALL Info( 'HeaterControl', Message, Level=4 )
          WRITE( Message, * ) 'Heater Power Density (W/kg): ', s/(HeaterDensity(i) * HeaterArea(i))
          CALL Info( 'HeaterControl', Message, Level=4 )
          CALL Info( 'HeaterControl', ' ', Level=4 )
        END DO
        
        IF(NOFControlHeaters == 1) THEN
          CALL ListAddConstReal(Model % Simulation,'res: Heater Power Density',&
              s/(HeaterDensity(1) * HeaterArea(1)))
        END IF

        Norm = SQRT( SUM( Temperature**2 ) / LocalNodes )
        Solver % Variable % Norm = Norm
        
        IF ( Relax /= 1.0d0 ) THEN
          CALL ListAddConstReal( Solver % Values,  &
              'Nonlinear System Relaxation Factor', Relax )
        END IF
      ELSE
        Norm = DefaultSolve()
      END IF

      st = CPUTIme()-st
      totat = totat + at
      totst = totst + st
      WRITE(Message,'(a,i4,a,F8.2,F8.2)') 'iter: ',iter,' Assembly: (s)', at, totat
      CALL Info( 'HeatSolve', Message, Level=4 )
      WRITE(Message,'(a,i4,a,F8.2,F8.2)') 'iter: ',iter,' Solve:    (s)', st, totst
      CALL Info( 'HeatSolve', Message, Level=4 )
!------------------------------------------------------------------------------
!     If modelling phase change (and if requested by the user), check if any
!     node has jumped over the phase change interval, and if so, reduce
!     timestep and or relaxation and recompute.
!------------------------------------------------------------------------------
      IF (PhaseChange .AND. CheckLatentHeatRelease .AND. iter/=Nonlineariter) THEN
!------------------------------------------------------------------------------
        IF ( CheckLatentHeat() ) THEN
          Temperature(1:LocalNodes) = PrevSolution

          Norm = SQRT( SUM(Temperature(1:LocalNodes)**2)/LocalNodes )

          IF ( TransientSimulation ) THEN
            dt = dt / 2
            WRITE( Message, * ) &
                  'Latent heat release check: reducing timestep to: ',dt
            CALL Info( 'HeatSolve', Message, Level=4 )
          ELSE
            Relax = Relax / 2
            CALL  ListAddConstReal( Solver % Values,  &
                 'Nonlinear System Relaxation Factor', Relax )
            WRITE( Message, * ) &
                 'Latent heat release check: reducing relaxation to: ',Relax
            CALL Info( 'HeatSolve', Message, Level=4 )
          END IF

          CYCLE
        END IF
        IF ( .NOT.TransientSimulation ) PrevSolution = Temperature(1:LocalNodes)
      END IF
!------------------------------------------------------------------------------

      IF ( PrevNorm + Norm /= 0.0d0 ) THEN
        RelativeChange = 2.0d0 * ABS( PrevNorm-Norm ) / (PrevNorm + Norm)
      ELSE
        RelativeChange = 0.0d0
      END IF

      WRITE( Message, * ) 'Result Norm   : ',Norm
      CALL Info( 'HeatSolve', Message, Level=4 )
      WRITE( Message, * ) 'Relative Change : ',RelativeChange
      CALL Info( 'HeatSolve', Message, Level=4 )

      IF ( RelativeChange < NewtonTol .OR. iter >= NewtonIter ) &
               NewtonLinearization = .TRUE.
      IF ( RelativeChange < NonlinearTol .AND. &
          (.NOT. HeaterControl .OR. SmartTolReached)) EXIT

      IF(HeaterControl) THEN
        IF ( RelativeChange < SmartTol ) THEN
          SmartTolReached = .TRUE.
          YY = Temperature
        END IF
      END IF
      
!------------------------------------------------------------------------------
    END DO ! of the nonlinear iteration
!------------------------------------------------------------------------------

    IF ( TransientSimulation .AND. PhaseChange ) THEN
      IF ( .NOT.ALLOCATED(TSolution) ) THEN
        ALLOCATE( TSolution(LocalNodes),TSolution1(LocalNodes),STAT=istat )
 
        IF ( istat /= 0 ) THEN
           CALL Fatal( 'HeatSolve', 'Memory allocation error.' )
         END IF
      END IF
      TSolution(1:LocalNodes) = PrevSolution(1:LocalNodes)
    END IF

!------------------------------------------------------------------------------
!   Compute cumulative time done by now and time remaining
!------------------------------------------------------------------------------
    IF ( .NOT. TransientSimulation ) EXIT
    CumulativeTime = CumulativeTime + dt
    dt = Timestep - CumulativeTime

   END DO ! time interval

!------------------------------------------------------------------------------
   CALL  ListAddConstReal( Solver % Values,  &
        'Nonlinear System Relaxation Factor', SaveRelax )
!------------------------------------------------------------------------------

   DEALLOCATE( PrevSolution )

   IF ( ListGetLogical( Solver % Values, 'Adaptive Mesh Refinement', Found ) ) &
      CALL RefineMesh( Model,Solver,Temperature,TempPerm, &
            HeatInsideResidual, HeatEdgeResidual, HeatBoundaryResidual )


CONTAINS

!------------------------------------------------------------------------------
    SUBROUTINE DiffuseGrayRadiation( Model, Solver, Element,  &
               Temperature, TempPerm, ForceVector,AngleFraction)
!------------------------------------------------------------------------------
      TYPE(Model_t)  :: Model
      TYPE(Solver_t) :: Solver
      TYPE(Element_t), POINTER :: Element
      INTEGER :: TempPerm(:)
      REAL(KIND=dp) :: Temperature(:), ForceVector(:)
      REAL(KIND=dp) :: AngleFraction
!------------------------------------------------------------------------------
      REAL(KIND=dp) :: Area, Asum
      INTEGER :: i,j,k,l,m,ImplicitFactors
      INTEGER, POINTER :: ElementList(:)
!------------------------------------------------------------------------------
!     If linear iteration compute radiation load
!------------------------------------------------------------------------------


      Asum = 0.0d0
      IF ( .NOT. NewtonLinearization ) THEN

        Text = ComputeRadiationLoad( Model, Solver % Mesh, Element, &
                 Temperature, TempPerm, Emissivity, AngleFraction)

      ELSE   !  Full Newton-Raphson solver
!------------------------------------------------------------------------------
!       Go trough surfaces (j) this surface (i) is getting
!       radiated from.
!------------------------------------------------------------------------------
        Area  = ElementArea( Solver % Mesh, Element, n )
        ElementList => Element % BoundaryInfo % GebhardtFactors % Elements

        DO j=1,Element % BoundaryInfo % GebhardtFactors % NumberOfFactors

          RadiationElement => Solver % Mesh % Elements( ElementList(j) )

          Text = ComputeRadiationCoeff(Model,Solver % Mesh,Element,j) / ( Area )
          Asum = Asum + Text
!------------------------------------------------------------------------------
!         Gebhardt factors are given elementwise at the center
!         of the element, so take avarage of nodal temperatures
!         (or integrate over surface j)
!------------------------------------------------------------------------------

          k = RadiationElement % TYPE % NumberOfNodes
          ImplicitFactors = Element % BoundaryInfo % GebhardtFactors % NumberOfImplicitFactors
          IF(ImplicitFactors == 0) &
              ImplicitFactors = Element % BoundaryInfo % GebhardtFactors % NumberOfFactors

          IF(j <= ImplicitFactors) THEN
            
            S = (SUM( Temperature( TempPerm( RadiationElement % &
                NodeIndexes))**4 )/k )**(1.0d0/4.0d0)
!------------------------------------------------------------------------------
!         Linearization of the G_jiT^4_j term
!------------------------------------------------------------------------------
            HeatTransferCoeff(1:n) = -4 * Text * S**3 * StefanBoltzmann
            LOAD(1:n) = -3 * Text * S**4 * StefanBoltzmann
!------------------------------------------------------------------------------
!         Integrate the contribution of surface j over surface i
!         and add to global matrix
!------------------------------------------------------------------------------
            CALL IntegOverA( STIFF, FORCE, LOAD, &
                HeatTransferCoeff, Element, n, k, ElementNodes ) 
            
            IF ( TransientSimulation ) THEN
              MASS = 0.d0
              CALL Add1stOrderTime( MASS, STIFF, &
                  FORCE,dt,n,1,TempPerm(Element % NodeIndexes),Solver )
            END IF
            
            DO m=1,n
              k1 = TempPerm( Element % NodeIndexes(m) )
              DO l=1,k
                k2 = TempPerm( RadiationElement % NodeIndexes(l) )
                CALL AddToMatrixElement( StiffMatrix,k1, &
                    k2,STIFF(m,l) )
              END DO
              ForceVector(k1) = ForceVector(k1) + FORCE(m)
            END DO

          ELSE

            S = (SUM( Temperature( TempPerm( RadiationElement % &
                NodeIndexes))**4 )/k )
            
            HeatTransferCoeff(1:n) = 0.0d0
            LOAD(1:n) = Text * S * StefanBoltzmann
            
            CALL IntegOverA( STIFF, FORCE, LOAD, &
                HeatTransferCoeff, Element, n, k, ElementNodes ) 
            
            DO m=1,n
              k1 = TempPerm( Element % NodeIndexes(m) )
              ForceVector(k1) = ForceVector(k1) + FORCE(m)
            END DO
            
          END IF 

        END DO

!------------------------------------------------------------------------------
!       We have already added all external temperature contributions
!       to the matrix for the Newton type iteration
!------------------------------------------------------------------------------
        AngleFraction = Asum / Emissivity
        Text = 0.0

      END IF  !  of newton-raphson

    END SUBROUTINE DiffuseGrayRadiation
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    SUBROUTINE EffectiveHeatCapacity
!------------------------------------------------------------------------------
!     See if temperature gradient indside the element is large enough 
!     to use  the c_p = SQRT( (dH/dx)^2 / (dT/dx)^2 ), otherwise
!     use c_p = dH/dT, or if in time dependent simulation, use
!     c_p = (dH/dt) / (dT/dt), if requested. 
!------------------------------------------------------------------------------
      PhaseChangeModel = PHASE_SPATIAL_1
!------------------------------------------------------------------------------
      SELECT CASE(PhaseModel)
!------------------------------------------------------------------------------
        CASE( 'spatial 1' )
          PhaseChangeModel = PHASE_SPATIAL_1
!------------------------------------------------------------------------------

        CASE( 'spatial 2' )
          PhaseChangeModel = PHASE_SPATIAL_2
!------------------------------------------------------------------------------

        CASE('temporal')

          IF ( TransientSimulation .AND. ALLOCATED(TSolution) )  THEN
            HeatCapacity(1:n) = Temperature( TempPerm(Element % NodeIndexes) ) - &
                     TSolution( TempPerm(Element % NodeIndexes) )

            IF ( ANY(ABS(HeatCapacity) < AEPS) ) THEN
              PhaseChangeModel = PHASE_SPATIAL_1
            ELSE
              PhaseChangeModel = PHASE_TEMPORAL
            END IF
          ELSE
             PhaseChangeModel = PHASE_SPATIAL_1
          END IF
!------------------------------------------------------------------------------
      END SELECT
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
! Check if local variation of temperature is large enough to actually use the
! Spatial 2 model. Should perhaps be scaled to element size (or actually
! compute the gradient, but this will do for now...).
!------------------------------------------------------------------------------
      PhaseSpatial = ( PhaseChangeModel == PHASE_SPATIAL_2 )
      IF ( PhaseSpatial ) THEN
        s = 0.0D0
        DO i=1,n
          DO j=i+1,n
            s = MAX( s,ABS(LocalTemperature(i)-LocalTemperature(j)) )
          END DO
        END DO
        IF ( s < AEPS ) THEN
          PhaseChangeModel = PHASE_SPATIAL_1
        END IF
      END IF
      PhaseSpatial = ( PhaseChangeModel == PHASE_SPATIAL_2 )

!------------------------------------------------------------------------------
      SELECT CASE( PhaseChangeModel )
!------------------------------------------------------------------------------
      CASE( PHASE_SPATIAL_1 )
        HeatCapacity(1:n) = ListGetDerivValue( Material, &
                 'Enthalpy', n,Element % NodeIndexes )

!------------------------------------------------------------------------------
      CASE( PHASE_SPATIAL_2 )
        Enthalpy(1:n) = ListGetReal(Material,'Enthalpy',n,Element % NodeIndexes)

!------------------------------------------------------------------------------

      CASE( PHASE_TEMPORAL )
        TSolution1 = Temperature(1:LocalNodes)

        Work(1:n) = ListGetReal( Material,'Enthalpy',n,Element % NodeIndexes )

        Temperature(1:LocalNodes) = TSolution
        Work(1:n) = Work(1:n) - ListGetReal( Material,'Enthalpy', &
                          n,Element % NodeIndexes )

        Temperature(1:LocalNodes) = TSolution1
        HeatCapacity(1:n) = Work(1:n) / HeatCapacity(1:n)
!------------------------------------------------------------------------------
      END SELECT
!------------------------------------------------------------------------------
    END SUBROUTINE EffectiveHeatCapacity
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
    FUNCTION CheckLatentHeat() RESULT(Failure)
!------------------------------------------------------------------------------
      LOGICAL :: Failure, PhaseChange, CheckLatentHeatRelease
      INTEGER :: t, eq_id, body_id
      CHARACTER(LEN=MAX_NAME_LEN) :: PhaseModel
!------------------------------------------------------------------------------

      Failure = .FALSE.
!------------------------------------------------------------------------------
      DO t=1,Solver % Mesh % NumberOfBulkElements
!------------------------------------------------------------------------------
!       Check if this element belongs to a body where temperature 
!       has been calculated
!------------------------------------------------------------------------------
        Element => Solver % Mesh % Elements(t)

        NodeIndexes => Element % NodeIndexes
        IF ( ANY( TempPerm( NodeIndexes ) <= 0 ) ) CYCLE

        body_id = Element % Bodyid
        eq_id = ListGetInteger( Model % Bodies(body_id) % Values, &
            'Equation', minv=1, maxv=Model % NumberOfEquations )

        PhaseModel = ListGetString( Model % Equations(eq_id) % Values, &
                          'Phase Change Model',Found )

        PhaseChange = Found .AND. (PhaseModel(1:4) /= 'none')

        IF ( PhaseChange ) THEN
          CheckLatentHeatRelease = ListGetLogical(Model % Equations(eq_id) % &
                    Values, 'Check Latent Heat Release',Found )
        END IF
        IF ( .NOT. ( PhaseChange .AND. CheckLatentHeatRelease ) ) CYCLE

        n = Element % TYPE % NumberOfNodes
!------------------------------------------------------------------------------
!       Set the current element pointer in the model structure to
!       reflect the element being processed
!------------------------------------------------------------------------------
        Model % CurrentElement => Element
!------------------------------------------------------------------------------
!------------------------------------------------------------------------------
!       Get element material parameters
!------------------------------------------------------------------------------
        k = ListGetInteger( Model % Bodies(body_id) % Values,'Material', &
                minv=1, maxv=Model % NumberOfMaterials )
        Material => Model % Materials(k) % Values

        PhaseChangeIntervals => ListGetConstRealArray( Material, &
                        'Phase Change Intervals' )

        DO k=1,n
          i = TempPerm( NodeIndexes(k) )
          DO j=1,SIZE(PhaseChangeIntervals,2)
            IF ( ( Temperature(i)  < PhaseChangeIntervals(1,j) .AND. &
                   PrevSolution(i) > PhaseChangeIntervals(2,j) ).OR. &
                 ( Temperature(i)  > PhaseChangeIntervals(2,j) .AND. &
                   PrevSolution(i) < PhaseChangeIntervals(1,j) )  ) THEN

              Failure = .TRUE.
              EXIT
            END IF
          END DO
          IF ( Failure ) EXIT
        END DO
        IF ( Failure ) EXIT
      END DO
!------------------------------------------------------------------------------
    END FUNCTION CheckLatentHeat
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
   SUBROUTINE IntegOverA( BoundaryMatrix, BoundaryVector, &
     LOAD, NodalAlpha, Element, n, m, Nodes )
!------------------------------------------------------------------------------
     REAL(KIND=dp) :: BoundaryMatrix(:,:),BoundaryVector(:), &
                    LOAD(:),NodalAlpha(:)

     TYPE(Nodes_t)   :: Nodes
     TYPE(Element_t) :: Element

     INTEGER :: n,  m

     REAL(KIND=dp) :: ddBasisddx(n,3,3)
     REAL(KIND=dp) :: Basis(n)
     REAL(KIND=dp) :: dBasisdx(n,3),SqrtElementMetric

     REAL(KIND=dp) :: u,v,w,s,x,y,z
     REAL(KIND=dp) :: Force,Alpha
     REAL(KIND=dp), POINTER :: U_Integ(:),V_Integ(:),W_Integ(:),S_Integ(:)

     INTEGER :: i,t,q,p,N_Integ

     TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff

     LOGICAL :: stat
!------------------------------------------------------------------------------

     BoundaryVector = 0.0D0
     BoundaryMatrix = 0.0D0
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
!     Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
       stat = ElementInfo( Element,Nodes,u,v,w,SqrtElementMetric, &
                  Basis,dBasisdx,ddBasisddx,.FALSE. )

       s = SqrtElementMetric * S_Integ(t)
!------------------------------------------------------------------------------
!      Coordinatesystem dependent info
!------------------------------------------------------------------------------
       IF ( CurrentCoordinateSystem() /= Cartesian ) THEN
         x = SUM( Nodes % x(1:n)*Basis )
         y = SUM( Nodes % y(1:n)*Basis )
         z = SUM( Nodes % z(1:n)*Basis )
         s = s * CoordinateSqrtMetric( x,y,z )
       END IF
!------------------------------------------------------------------------------
       Force = SUM( LOAD(1:n) * Basis )
       Alpha = SUM( NodalAlpha(1:n) * Basis )

       DO p=1,N
         DO q=1,M
           BoundaryMatrix(p,q) = BoundaryMatrix(p,q) + &
                  s * Alpha * Basis(p) / m
         END DO
       END DO

       DO p=1,N
         BoundaryVector(p) = BoundaryVector(p) + s * Force * Basis(p)
       END DO
     END DO
   END SUBROUTINE IntegOverA
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    FUNCTION GapTemperature( Solver, Element, Temperature, TempPerm ) RESULT(T)
!------------------------------------------------------------------------------
      TYPE(Solver_t) :: Solver
      TYPE(Element_t), POINTER :: Element
      INTEGER :: TempPerm(:)
      REAL(KIND=dp) :: Temperature(:)
!------------------------------------------------------------------------------
      TYPE(Element_t), POINTER :: Parent
      INTEGER :: i,j,k,Left,Right
      REAL(KIND=dp) :: x0,y0,z0,x,y,z,T(n)
!------------------------------------------------------------------------------
      Left  = Element % BoundaryInfo % LElement
      Right = Element % BoundaryInfo % RElement

      T = 0.d0
      IF ( Left <= 0 .OR. Right <= 0 ) RETURN

      DO i=1,n
        Parent => Solver % Mesh % Elements(Left)
        k = Element % NodeIndexes(i)

        IF ( ANY( Parent % NodeIndexes == k ) ) &
          Parent => Solver % Mesh % Elements(Right)

        x0 = ElementNodes % x(i)
        y0 = ElementNodes % y(i)
        z0 = ElementNodes % z(i)
        DO j=1,Parent % TYPE % NumberOfNodes
          k = Parent % NodeIndexes(j)
          x = Solver % Mesh % Nodes % x(k) - x0
          y = Solver % Mesh % Nodes % y(k) - y0
          z = Solver % Mesh % Nodes % z(k) - z0
          IF ( x**2 + y**2 + z**2 < AEPS ) EXIT
        END DO
        T(i) = Temperature( TempPerm( k ) )
      END DO
!------------------------------------------------------------------------------
    END FUNCTION GapTemperature
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    SUBROUTINE AddHeatGap( Solver, Element, STIFF, TempPerm )
!------------------------------------------------------------------------------
      TYPE(Solver_t) :: Solver
      TYPE(Element_t), POINTER :: Element
      REAL(KIND=dp) :: STIFF(:,:)
      INTEGER :: TempPerm(:)
!------------------------------------------------------------------------------
      TYPE(Element_t), POINTER :: Parent
      INTEGER :: i,j,k,l,Left,Right, Ind(n)
      REAL(KIND=dp) :: x0,y0,z0,x,y,z
!------------------------------------------------------------------------------
      Left  = Element % BoundaryInfo % LElement
      Right = Element % BoundaryInfo % RElement

      IF ( Left <= 0 .OR. Right <= 0 ) RETURN

      l = 0
      DO i=1,n
        Parent => Solver % Mesh % Elements(Left)
        k = Element % NodeIndexes(i)

        IF ( ANY( Parent % NodeIndexes == k ) ) &
          Parent => Solver % Mesh % Elements(Right)

        x0 = ElementNodes % x(i)
        y0 = ElementNodes % y(i)
        z0 = ElementNodes % z(i)
        DO j=1,Parent % Type % NumberOfNodes
          k = Parent % NodeIndexes(j)
          x = Solver % Mesh % Nodes % x(k) - x0
          y = Solver % Mesh % Nodes % y(k) - y0
          z = Solver % Mesh % Nodes % z(k) - z0
          IF ( x**2 + y**2 + z**2 < AEPS ) EXIT
        END DO
        Ind(i) = k
      END DO

      DO i=1,n
        DO j=1,n
          k = TempPerm( Element % NodeIndexes(i) )
          l = TempPerm( Ind(j) )
          IF ( k > 0 .AND. l > 0 ) &
            CALL AddToMatrixElement( Solver % Matrix,k,l,-STIFF(i,j) )
        END DO
      END DO
!------------------------------------------------------------------------------
    END SUBROUTINE AddHeatGap
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
  END SUBROUTINE HeatSolver
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  FUNCTION HeatBoundaryResidual( Model, Edge, Mesh, Quant, Perm,Gnorm ) RESULT( Indicator )
!------------------------------------------------------------------------------
     USE Radiation
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
     TYPE(Element_t), POINTER :: Element, Bndry


     INTEGER :: i,j,k,n,l,t,DIM,Pn,En
     LOGICAL :: stat, Found

     REAL(KIND=dp), POINTER :: Hwrk(:,:,:)

     REAL(KIND=dp) :: SqrtMetric, Metric(3,3), Symb(3,3,3), dSymb(3,3,3,3)

     REAL(KIND=dp) :: NodalConductivity(MAX_NODES), Conductivity

     REAL(KIND=dp) :: Emissivity, StefanBoltzmann
     REAL(KIND=dp) :: ExtTemperature(MAX_NODES), TransferCoeff(MAX_NODES)

     REAL(KIND=dp) :: Grad(3,3), Normal(3), EdgeLength, &
          x(MAX_NODES), y(MAX_NODES), z(MAX_NODES), gx, gy, gz

     REAL(KIND=dp) :: u, v, w, s, detJ, EdgeBasis(MAX_NODES), Basis(MAX_NODES), &
         dBasisdx(MAX_NODES,3), ddBasisddx(MAX_NODES,3,3), Temperature(MAX_NODES)

     REAL(KIND=dp) :: Source, Residual, ResidualNorm, Area, Flux(MAX_NODES)

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

     Indicator = 0.0d0
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
        s = ListGetConstReal( Model % BCs(j) % Values,'Temperature',Dirichlet )

!       Get various flux bc options:
!       ----------------------------

!       ...given flux:
!       --------------
        Flux(1:En) = ListGetReal( Model % BCs(j) % Values, &
          'Heat Flux', En, Edge % NodeIndexes, Found )

!       ...convective heat transfer:
!       ----------------------------
        TransferCoeff(1:En) =  ListGetReal( Model % BCs(j) % Values, &
          'Heat Transfer Coefficient', En, Edge % NodeIndexes, Found )

        ExtTemperature(1:En) = ListGetReal( Model % BCs(j) % Values, &
          'External Temperature', En, Edge % NodeIndexes, Found )

!       ...black body radiation:
!       ------------------------
        Emissivity      = 0.0d0
        StefanBoltzmann = 0.0d0

        SELECT CASE(ListGetString(Model % BCs(j) % Values,'Radiation',Found))
           !------------------
           CASE( 'idealized' )
           !------------------

              Emissivity = SUM(ListGetReal( Model % BCs(j) % Values, &
                   'Emissivity', En, Edge % NodeIndexes)) / En 

              StefanBoltzMann = &
                    ListGetConstReal( Model % Constants,'Stefan Boltzmann' )

           !---------------------
           CASE( 'diffuse gray' )
           !---------------------

              Emissivity = SUM(ListGetReal( Model % BCs(j) % Values, &
                  'Emissivity', En, Edge % NodeIndexes)) / En

              StefanBoltzMann = &
                    ListGetConstReal( Model % Constants,'Stefan Boltzmann' )

              ExtTemperature(1:En) =  ComputeRadiationLoad( Model, &
                      Mesh, Edge, Quant, Perm, Emissivity )
        END SELECT

!       get material parameters:
!       ------------------------
        k = ListGetInteger(Model % Bodies(Element % BodyId) % Values,'Material', &
                    minv=1, maxv=Model % NumberOFMaterials)

        CALL ListGetRealArray( Model % Materials(k) % Values, &
               'Heat Conductivity', Hwrk, En, Edge % NodeIndexes )

        NodalConductivity( 1:En ) = Hwrk( 1,1,1:En )

!       elementwise nodal solution:
!       ---------------------------
        Temperature(1:Pn) = Quant( Perm(Element % NodeIndexes) )

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
              gx = SUM( EdgeBasis(1:En) * EdgeNodes % x(1:En) )
              gy = SUM( EdgeBasis(1:En) * EdgeNodes % y(1:En) )
              gz = SUM( EdgeBasis(1:En) * EdgeNodes % z(1:En) )
      
              CALL CoordinateSystemInfo( Metric, SqrtMetric, &
                         Symb, dSymb, gx, gy, gz )

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
           Conductivity = SUM( NodalConductivity(1:En) * EdgeBasis(1:En) )
!
!          given flux at integration point:
!          --------------------------------
           Residual = -SUM( Flux(1:En) * EdgeBasis(1:En) )

!          convective ...:
!          ----------------
           Residual = Residual + SUM(TransferCoeff(1:En) * EdgeBasis(1:En)) * &
                     ( SUM( Temperature(1:Pn) * Basis(1:Pn) ) - &
                       SUM( ExtTemperature(1:En) * EdgeBasis(1:En) ) )

!          black body radiation...:
!          -------------------------
           Residual = Residual + &
                Emissivity * StefanBoltzmann * &
                     ( SUM( Temperature(1:Pn) * Basis(1:Pn) ) ** 4 - &
                       SUM( ExtTemperature(1:En) * EdgeBasis(1:En) ) ** 4 )

!          flux given by the computed solution, and 
!          force norm for scaling the residual:
!          -----------------------------------------
           IF ( CurrentCoordinateSystem() == Cartesian ) THEN
              DO k=1,DIM
                 Residual = Residual + Conductivity  * &
                    SUM( dBasisdx(1:Pn,k) * Temperature(1:Pn) ) * Normal(k)

                 Gnorm = Gnorm + s * (Conductivity * &
                       SUM(dBasisdx(1:Pn,k) * Temperature(1:Pn)) * Normal(k))**2
              END DO
           ELSE
              DO k=1,DIM
                 DO l=1,DIM
                    Residual = Residual + Metric(k,l) * Conductivity  * &
                       SUM( dBasisdx(1:Pn,k) * Temperature(1:Pn) ) * Normal(l)

                    Gnorm = Gnorm + s * (Metric(k,l) * Conductivity * &
                      SUM(dBasisdx(1:Pn,k) * Temperature(1:Pn) ) * Normal(l))**2
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
  END FUNCTION HeatBoundaryResidual
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
  FUNCTION HeatEdgeResidual( Model, Edge, Mesh, Quant, Perm ) RESULT( Indicator )
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
     TYPE(Element_t), POINTER :: Element, Bndry

     INTEGER :: i,j,k,l,n,t,DIM,En,Pn
     LOGICAL :: stat, Found
     REAL(KIND=dp), POINTER :: Hwrk(:,:,:)

     REAL(KIND=dp) :: SqrtMetric, Metric(3,3), Symb(3,3,3), dSymb(3,3,3,3)

     REAL(KIND=dp) :: NodalConductivity(MAX_NODES), Conductivity

     REAL(KIND=dp) :: Grad(3,3), Normal(3), EdgeLength, Jump, &
                x(MAX_NODES),y(MAX_NODES),z(MAX_NODES)

     REAL(KIND=dp) :: u, v, w, s, detJ, EdgeBasis(MAX_NODES), &
          Basis(MAX_NODES), dBasisdx(MAX_NODES,3), &
             ddBasisddx(MAX_NODES,3,3), Temperature(MAX_NODES)

     REAL(KIND=dp) :: Residual, ResidualNorm, Area, Flux(MAX_NODES)

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
                   'Heat Conductivity', Hwrk,En, Edge % NodeIndexes )

           NodalConductivity( 1:En ) = Hwrk( 1,1,1:En )
           Conductivity = SUM( NodalConductivity(1:En) * EdgeBasis(1:En) )
!
!          Temperature at element nodal points:
!          ------------------------------------
           Temperature(1:Pn) = Quant( Perm(Element % NodeIndexes) )
!
!          Finally, the flux:
!          ------------------
           DO j=1,DIM
              Grad(j,i) = Conductivity * SUM( dBasisdx(1:Pn,j) * Temperature(1:Pn) )
           END DO
        END DO

!       Compute squre of the flux jump:
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
  END FUNCTION HeatEdgeResidual
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   FUNCTION HeatInsideResidual( Model, Element, Mesh, &
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

     LOGICAL :: stat, Found, Compressible
     TYPE( Variable_t ), POINTER :: Var

     REAL(KIND=dp), POINTER :: Hwrk(:,:,:)

     REAL(KIND=dp) :: SqrtMetric, Metric(3,3), Symb(3,3,3), dSymb(3,3,3,3)

     REAL(KIND=dp) :: NodalDensity(MAX_NODES),  Density
     REAL(KIND=dp) :: NodalCapacity(MAX_NODES), Capacity

     REAL(KIND=dp) :: Velo(3,MAX_NODES), Pressure(MAX_NODES)
     REAL(KIND=dp) :: Conductivity, NodalConductivity(MAX_NODES)

     REAL(KIND=dp) :: u, v, w, s, detJ, Basis(MAX_NODES), &
                dBasisdx(MAX_NODES,3), ddBasisddx(MAX_NODES,3,3)

     REAL(KIND=dp) :: Source, Residual, ResidualNorm, Area
     REAL(KIND=dp) :: SpecificHeatRatio, ReferencePressure, dt

     REAL(KIND=dp) :: NodalSource(MAX_NODES), Temperature(MAX_NODES), &
                      PrevTemp(MAX_NODES)

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
     Temperature(1:n) = Quant( Perm(Element % NodeIndexes) )
!
!    Check for time dep.
!    -------------------
     PrevTemp(1:n) = Temperature(1:n)
     dt = Model % Solver % dt
     IF ( ListGetString( Model % Simulation, 'Simulation Type') == 'transient' ) THEN
        Var => VariableGet( Model % Variables, 'Temperature', .TRUE. )
        PrevTemp(1:n) = Var % PrevValues(Var % Perm(Element % NodeIndexes),1)
     END IF
!
!    Material parameters: conductivity, heat capacity and density
!    -------------------------------------------------------------
     k = ListGetInteger( Model % Bodies(Element % BodyId) % Values, 'Material', &
                     minv=1, maxv=Model % NumberOfMaterials )

     Material => Model % Materials(k) % Values

     CALL ListGetRealArray( Material, &
                  'Heat Conductivity', Hwrk,n, Element % NodeIndexes )

     NodalConductivity( 1:n ) = Hwrk( 1,1,1:n )

     NodalDensity(1:n) = ListGetReal( Material, &
            'Density', n, Element % NodeIndexes, Found )

     NodalCapacity(1:n) = ListGetReal( Material, &
          'Heat Capacity', n, Element % NodeIndexes, Found )
!
!    Check for compressible flow equations:
!    --------------------------------------
     Compressible = .FALSE.

     IF (  ListGetString( Material, 'Compressibility Model', Found ) == &
                 'perfect gas equation 1' ) THEN

        Compressible = .TRUE.

        Pressure = 0.0d0
        Var => VariableGet( Mesh % Variables, 'Pressure', .TRUE. )
        IF ( ASSOCIATED( Var ) ) THEN
           Pressure(1:n) = &
               Var % Values( Var % Perm(Element % NodeIndexes) )
        END IF

        ReferencePressure = ListGetConstReal( Material, &
                   'Reference Pressure' )

        SpecificHeatRatio = ListGetConstReal( Material, &
                   'Specific Heat Ratio' )

        NodalDensity(1:n) =  (Pressure(1:n) + ReferencePressure) * SpecificHeatRatio / &
              ( (SpecificHeatRatio - 1) * NodalCapacity(1:n) * Temperature(1:n) )
     END IF
!
!    Get (possible) convection velocity at the nodes of the element:
!    ----------------------------------------------------------------
     k = ListGetInteger( Model % Bodies(Element % BodyId) % Values, 'Equation', &
                minv=1, maxv=Model % NumberOFEquations )

     Velo = 0.0d0
     SELECT CASE( ListGetString( Model % Equations(k) % Values, &
                         'Convection', Found ) )

        !-----------------
        CASE( 'constant' )
        !-----------------

           Velo(1,1:n) = ListGetReal( Material, &
              'Convection Velocity 1', n, Element % NodeIndexes, Found )

           Velo(2,1:n) = ListGetReal( Material, &
              'Convection Velocity 2', n, Element % NodeIndexes, Found )

           Velo(3,1:n) = ListGetReal( Material, &
              'Convection Velocity 3', n, Element % NodeIndexes, Found )

        !-----------------
        CASE( 'computed' )
        !-----------------

           Var => VariableGet( Mesh % Variables, 'Velocity 1', .TRUE. )
           IF ( ASSOCIATED( Var ) ) THEN
              IF ( ALL( Var % Perm( Element % NodeIndexes ) > 0 ) ) THEN
                 Velo(1,1:n) = Var % Values(Var % Perm(Element % NodeIndexes))
   
                 Var => VariableGet( Mesh % Variables, 'Velocity 2', .TRUE. )
                 IF ( ASSOCIATED( Var ) ) &
                    Velo(2,1:n) = Var % Values( &
                              Var % Perm(Element % NodeIndexes ) )
   
                 Var => VariableGet( Mesh % Variables, 'Velocity 3', .TRUE. )
                 IF ( ASSOCIATED( Var ) ) &
                    Velo(3,1:n) = Var % Values( &
                             Var % Perm( Element % NodeIndexes ) )
              END IF
           END IF

     END SELECT

!
!    Heat source:
!    ------------
!
     k = ListGetInteger( &
         Model % Bodies(Element % BodyId) % Values,'Body Force',Found, &
                 1, Model % NumberOFBodyForces)

     NodalSource = 0.0d0
     IF ( Found .AND. k > 0  ) THEN
        NodalSource(1:n) = ListGetReal( Model % BodyForces(k) % Values, &
               'Heat Source', n, Element % NodeIndexes, Found )
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

        Capacity     = SUM( NodalCapacity(1:n) * Basis(1:n) )
        Density      = SUM( NodalDensity(1:n) * Basis(1:n) )
        Conductivity = SUM( NodalConductivity(1:n) * Basis(1:n) )
!
!       Residual of the convection-diffusion (heat) equation:
!        R = \rho * c_p * (@T/@t + u.grad(T)) - &
!            div(C grad(T)) + p div(u) - h,
!       ---------------------------------------------------
!
!       or more generally:
!
!        R = \rho * c_p * (@T/@t + u^j T_{,j}) - &
!          g^{jk} (C T_{,j}}_{,k} + p div(u) - h
!       ---------------------------------------------------
!
        Residual = -Density * SUM( NodalSource(1:n) * Basis(1:n) )

        IF ( CurrentCoordinateSystem() == Cartesian ) THEN
           DO j=1,DIM
!
!             - grad(C).grad(T):
!             --------------------
!
              Residual = Residual - &
                 SUM( Temperature(1:n) * dBasisdx(1:n,j) ) * &
                 SUM( NodalConductivity(1:n) * dBasisdx(1:n,j) )

!
!             - C div(grad(T)):
!             -------------------
!
              Residual = Residual - Conductivity * &
                 SUM( Temperature(1:n) * ddBasisddx(1:n,j,j) )
           END DO
        ELSE
           DO j=1,DIM
              DO k=1,DIM
!
!                - g^{jk} C_{,k}T_{j}:
!                ---------------------
!
                 Residual = Residual - Metric(j,k) * &
                    SUM( Temperature(1:n) * dBasisdx(1:n,j) ) * &
                    SUM( NodalConductivity(1:n) * dBasisdx(1:n,k) )

!
!                - g^{jk} C T_{,jk}:
!                -------------------
!
                 Residual = Residual - Metric(j,k) * Conductivity * &
                    SUM( Temperature(1:n) * ddBasisddx(1:n,j,k) )
!
!                + g^{jk} C {_jk^l} T_{,l}:
!                ---------------------------
                 DO l=1,DIM
                    Residual = Residual + Metric(j,k) * Conductivity * &
                      Symb(j,k,l) * SUM( Temperature(1:n) * dBasisdx(1:n,l) )
                 END DO
              END DO
           END DO
        END IF

!       + \rho * c_p * (@T/@t + u.grad(T)):
!       -----------------------------------
        Residual = Residual + Density * Capacity *  &
           SUM((Temperature(1:n)-PrevTemp(1:n))*Basis(1:n)) / dt

        DO j=1,DIM
           Residual = Residual + &
              Density * Capacity * SUM( Velo(j,1:n) * Basis(1:n) ) * &
                    SUM( Temperature(1:n) * dBasisdx(1:n,j) )
        END DO


        IF ( Compressible ) THEN
!
!          + p div(u) or p u^j_{,j}:
!          -------------------------
!
           DO j=1,DIM
              Residual = Residual + &
                 SUM( Pressure(1:n) * Basis(1:n) ) * &
                      SUM( Velo(j,1:n) * dBasisdx(1:n,j) )

              IF ( CurrentCoordinateSystem() /= Cartesian ) THEN
                 DO k=1,DIM
                    Residual = Residual + &
                       SUM( Pressure(1:n) * Basis(1:n) ) * &
                           Symb(j,k,j) * SUM( Velo(k,1:n) * Basis(1:n) )
                 END DO
              END IF
           END DO
        END IF

!
!       Compute also force norm for scaling the residual:
!       -------------------------------------------------
        DO i=1,DIM
           Fnorm = Fnorm + s * ( Density * &
             SUM( NodalSource(1:n) * Basis(1:n) ) ) ** 2
        END DO

        Area = Area + s
        ResidualNorm = ResidualNorm + s *  Residual ** 2
     END DO

!    Fnorm = Element % hk**2 * Fnorm
     Indicator = Element % hK**2 * ResidualNorm
!------------------------------------------------------------------------------
  END FUNCTION HeatInsideResidual
!------------------------------------------------------------------------------
