!******************************************************************************
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
! *****************************************************************************
!
!******************************************************************************
! *
! ******************************************************************************
! *
! *                    Author:       Juha Ruokolainen
! *
! *                    Address: Center for Scientific Computing
! *                            Tietotie 6, P.O. BOX 405
! *                              02101 Espoo, Finland
! *                              Tel. +358 0 457 2723
! *                            Telefax: +358 0 457 2302
! *                          EMail: Juha.Ruokolainen@csc.fi
! *
! *                       Date: 08 Jun 1997
! *
! *                Modified by: Ville Savolainen, Juha Ruokolainen
! *
! *       Date of modification: 04 Jun 1999
! *
! *                Modified by: Antti Pursula
! *
! *       Date of modification: 05 Feb 2003
! *
! *****************************************************************************
 
!------------------------------------------------------------------------------
   SUBROUTINE AdvectionDiffusionSolver( Model,Solver,Timestep,TransientSimulation )
   !DEC$ATTRIBUTES DLLEXPORT :: AdvectionDiffusionSolver
!------------------------------------------------------------------------------
!******************************************************************************
!
!  Solve the advection-diffusion equation for a given (u^i,T) Cz gas field
!
!  ARGUMENTS:
!
!  TYPE(Model_t) :: Model,  
!     INPUT: All model information (mesh, materials, BCs, etc...)
!
!  TYPE(Solver_t) :: Solver
!     INPUT: Linear equation solver options
!
!  REAL(KIND=dp) :: Timestep,
!     INPUT: Timestep size for time dependent simulations
!
!  LOGICAL :: TransientSimulation
!     INPUT: Steady state or transient simulation
!
!******************************************************************************

     USE SolverUtils
     USE Differentials
     USE DefUtils

! Will need this for Density later
     USE MaterialModels
! Need these for mass conservation check
     USE Integration

     IMPLICIT NONE
!------------------------------------------------------------------------------
 
     TYPE(Model_t), TARGET :: Model
     TYPE(Solver_t) :: Solver
 
     REAL(KIND=dp) :: Timestep
     LOGICAL :: TransientSimulation
 
!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------
     INTEGER :: i,j,k,m,n,pn,t,iter,istat,bf_id,CoordinateSystem, outbody
 
     TYPE(Matrix_t),POINTER  :: StiffMatrix
     TYPE(Nodes_t)   :: ElementNodes, ParentNodes
     TYPE(Element_t),POINTER :: CurrentElement, Parent
 
     REAL(KIND=dp) :: Norm,PrevNorm,RelativeChange
     INTEGER, POINTER :: NodeIndexes(:)
     LOGICAL :: Stabilize = .FALSE., Bubbles, GotIt, AbsoluteMass = .FALSE.
     LOGICAL :: AllocationsDone = .FALSE., ScaledToSolubility = .FALSE.
     LOGICAL :: ErrorWritten

     TYPE(ValueList_t), POINTER :: Material

     INTEGER, POINTER :: SpeciesPerm(:), MeshPerm(:)
     REAL(KIND=dp), POINTER :: Species(:),ForceVector(:), MeshVelocity(:), Hwrk(:,:,:)
 
     REAL(KIND=dp), ALLOCATABLE :: LocalMassMatrix(:,:), SoretDiffusivity(:), &
       LocalStiffMatrix(:,:),Load(:),Diffusivity(:,:,:), &
                   C0(:),C1(:),CT(:),C2(:,:,:),LocalForce(:), TimeForce(:)
     CHARACTER(LEN=MAX_NAME_LEN) :: ConvectionFlag, HeatSolName, ConvectName
! Use C1, C2 as in users guide:
! Relative mass units: C1=Density, C2=Density*Diff, C0 = 0, Ct=C1
! Absolute mass units: C1=1, C2=Diff, C0 = div v, Ct=1
! Used to be for C_I, C_V
! Add C, when previous solution needed for linearization
     TYPE(Variable_t), POINTER :: TempSol,FlowSol,MeshSol

     INTEGER, POINTER :: TempPerm(:),FlowPerm(:)
     INTEGER :: NSDOFs,NewtonIter,NonlinearIter,body_id,eq_id,MDOFs
     REAL(KIND=dp) :: NonlinearTol,NewtonTol,Relax, dt

! For the moment assume a linear system
! LocalMassMatrix also added, since t-dep. possible
     REAL(KIND=dp) :: SpecificHeatRatio, ReferencePressure, Ratio, MaxSol
! Ratio => Ratio of solubilities, used in flux jump boundary condition

     REAL(KIND=dp), POINTER :: Temperature(:),FlowSolution(:)
! We need also Density, but it must be calculated for Compressible
! We read in also gamma & c_p in *.sif
     REAL(KIND=dp), ALLOCATABLE :: U(:), V(:), W(:), LocalTemperature(:), &
         Density(:), HeatCapacity(:), Pressure(:),GasConstant(:), &
         SpeciesTransferCoeff(:), SExt(:), MU(:), MV(:), MW(:)

     REAL(KIND=dp) :: at,totat,st,totst,CPUTime,at0,RealTime
     REAL(KIND=dp) :: Nrm(3), Nrm2(3)
     REAL(KIND=dp), ALLOCATABLE :: BackupForceVector(:)

     CHARACTER(LEN=MAX_NAME_LEN) :: CompressibilityFlag
     INTEGER :: CompressibilityModel
     CHARACTER(LEN=MAX_NAME_LEN) :: EquationName
     CHARACTER(LEN=MAX_NAME_LEN) :: ConcentrationUnits
! We will read velocity and temperature in
! For the moment assume steady-state velocity and temperature
! Then ElmerSolver reads them in automatically
! If time-dependent, have to somewhere:
! CALL LoadRestartFile( RestartFile,k,CurrentModel )

! Variables needed for the mass conservation check
     REAL(KIND=dp) :: Mass, PreviousMass
     INTEGER, DIMENSION( Model %  NumberOfBulkElements) :: ElementList

     CHARACTER(LEN=MAX_NAME_LEN) :: VersionID = "$Id: AdvectionDiffusion.f90,v 1.52 2004/08/03 12:50:30 apursula Exp $"

     SAVE LocalMassMatrix,LocalStiffMatrix,Load,C0,C1,CT,C2,Diffusivity, &
         TimeForce, LocalForce, ElementNodes,AllocationsDone, &
         U, V, W, LocalTemperature,Density, HeatCapacity, Pressure, &
         GasConstant, SpeciesTransferCoeff, Hwrk, MU, MV, MW, Mass, &
         ParentNodes, SExt, SoretDiffusivity

!------------------------------------------------------------------------------
!    Check if version number output is requested
!------------------------------------------------------------------------------
      IF ( .NOT. AllocationsDone ) THEN
        IF ( ListGetLogical( GetSimulation(), 'Output Version Numbers', GotIt ) ) THEN
          CALL Info( 'AdvectionDiffusion', 'AdvectionDiffusion version:', Level = 0 ) 
          CALL Info( 'AdvectionDiffusion', VersionID, Level = 0 ) 
          CALL Info( 'AdvectionDiffusion', ' ', Level = 0 ) 
        END IF
      END IF

!------------------------------------------------------------------------------
!    Get variables needed for solution
!------------------------------------------------------------------------------
     IF ( .NOT. ASSOCIATED( Solver % Matrix ) ) RETURN

     CoordinateSystem = CurrentCoordinateSystem()

     Species     => Solver % Variable % Values
     SpeciesPerm => Solver % Variable % Perm

     IF ( ALL( SpeciesPerm == 0) ) RETURN

! These are available in Model after LoadRestartFile

     TempSol => VariableGet( Solver % Mesh % Variables, 'Temperature' )
     IF ( ASSOCIATED( TempSol ) ) THEN
       TempPerm    => TempSol % Perm
       Temperature => TempSol % Values
     END IF

     FlowSol => VariableGet( Solver % Mesh % Variables, 'Flow Solution' )
     IF ( ASSOCIATED( FlowSol ) ) THEN
       FlowPerm     => FlowSol % Perm
       NSDOFs       =  FlowSol % DOFs
       FlowSolution => FlowSol % Values
     END IF

     MeshSol => VariableGet( Solver % Mesh % Variables, 'Mesh Velocity' )
     NULLIFY( MeshVelocity )
     IF ( ASSOCIATED(MeshSol ) ) THEN
       MDOFs    =  MeshSol % DOFs
       MeshPerm => MeshSol % Perm
       MeshVelocity => MeshSol % Values
     END IF

     StiffMatrix => Solver % Matrix
     ForceVector => StiffMatrix % RHS

     Norm = Solver % Variable % Norm
!------------------------------------------------------------------------------
!    Allocate some permanent storage, this is done first time only
!------------------------------------------------------------------------------
     IF ( .NOT. AllocationsDone ) THEN
       N = Solver % Mesh % MaxElementNodes

! Solve species weakly coupled, allocate accordingly
       ALLOCATE( U( N ),  V( N ), W( N ), &
                 MU( N ),MV( N ),MW( N ), &
                 LocalTemperature( N ),   &
                 Pressure( N ),           &
                 Density( N ),            &
                 ElementNodes % x( N ),   &
                 ElementNodes % y( N ),   &
                 ElementNodes % z( N ),   &
                 ParentNodes % x( N ),   &
                 ParentNodes % y( N ),   &
                 ParentNodes % z( N ),   &
                 LocalForce( 2*N ),         &
                 TimeForce( 2*N ),         &
                 LocalMassMatrix( 2*N,2*N ),  &
                 LocalStiffMatrix( 2*N,2*N ), &
                 Load( N ), Diffusivity( 3,3,N ), &
                 SoretDiffusivity( N ),   &
                 HeatCapacity( N ),       &
                 GasConstant( N ),        &
                 SpeciesTransferCoeff( N ), &
                 SExt( N ),              &
                 C0( N ), C1( N ), CT( N ), C2( 3,3,N ),STAT=istat )
 
       NULLIFY( HWrk)

       IF ( istat /= 0 ) THEN
         CALL Fatal( 'AdvectionDiffusion', 'Memory allocation error.' )
       END IF

! Add parallel solution check here

       Mass = 0.0d0

       AllocationsDone = .TRUE.
     END IF
!------------------------------------------------------------------------------
!    Do some additional initialization, and go for it
!------------------------------------------------------------------------------

     Stabilize = ListGetLogical( Solver % Values,'Stabilize',GotIt )
!#if 0
!     IF ( .NOT.GotIt ) Stabilize = .FALSE.
!#endif

     Bubbles = ListGetLogical( Solver % Values,'Bubbles',GotIt )
     IF ( .NOT.GotIt ) Bubbles = .TRUE.

     NonlinearTol = ListGetConstReal( Solver % Values, &
           'Nonlinear System Convergence Tolerance',GotIt )

     NewtonTol = ListGetConstReal( Solver % Values, &
          'Nonlinear System Newton After Tolerance',GotIt )

     NewtonIter = ListGetInteger( Solver % Values, &
         'Nonlinear System Newton After Iterations',GotIt )

     NonlinearIter = ListGetInteger( Solver % Values, &
        'Nonlinear System Max Iterations',GotIt )
     IF ( .NOT.GotIt ) NonlinearIter = 1

     Relax = ListGetConstReal( Solver % Values, &
         'Nonlinear System Relaxation Factor',GotIt )
     IF ( .NOT.GotIt ) Relax = 1

     EquationName = ListGetString( Solver % Values, 'Equation' )


!------------------------------------------------------------------------------

     dt = Timestep

!------------------------------------------------------------------------------

     totat = 0.0d0
     totst = 0.0d0

     DO iter=1,NonlinearIter
       at  = CPUTime()
       at0 = RealTime()

       CALL Info( 'AdvectionDiffusion', ' ', Level=4 )
       CALL Info( 'AdvectionDiffusion', ' ', Level=4 )
       CALL Info( 'AdvectionDiffusion', &
             '-------------------------------------', Level=4 )
       WRITE( Message, * ) 'SPECIES ITERATION', iter
       CALL Info( 'AdvectionDiffusion', Message, Level=4 )
       CALL Info( 'AdvectionDiffusion', &
             '-------------------------------------', Level=4 )
       CALL Info( 'AdvectionDiffusion', ' ', Level=4 )

!------------------------------------------------------------------------------
       CALL InitializeToZero( StiffMatrix, ForceVector )
!------------------------------------------------------------------------------
!       Mass = 0.0d0
       body_id = -1
       NULLIFY(Material)
!------------------------------------------------------------------------------
!      Do the assembly for bulk elements
!------------------------------------------------------------------------------
       t = 1
       DO WHILE( t <= Solver % Mesh % NumberOfBulkElements )
!------------------------------------------------------------------------------
!        IF ( MOD(t-1,500) == 0 ) PRINT*,'Element: ',t

          IF ( RealTime() - at0 > 1.0 ) THEN
             WRITE(Message,'(a,i3,a)' ) '   Assembly: ', INT(100.0 - 100.0 * &
                  (Solver % Mesh % NumberOfBulkElements-t) / &
                  (1.0*Solver % Mesh % NumberOfBulkElements)), ' % done'
             
             CALL Info( 'AdvectionDiffusion', Message, Level=5 )
             
             at0 = RealTime()
          END IF

!!------------------------------------------------------------------------------
!        Check if this element belongs to a body where species
!        advection-diffusion should be calculated
!------------------------------------------------------------------------------
         CurrentElement => Solver % Mesh % Elements(t)
!
!------------------------------------------------------------------------------
         IF ( CurrentElement % BodyId /= body_id ) THEN
!------------------------------------------------------------------------------
           DO WHILE( t <= Solver % Mesh % NumberOfBulkElements )
             IF ( CheckElementEquation( &
                 Model,CurrentElement,EquationName ) ) EXIT
             t = t + 1
             CurrentElement => Solver % Mesh % Elements(t)
           END DO

           IF ( t > Solver % Mesh % NumberOfBulkElements ) EXIT

           body_id = CurrentElement % Bodyid    
           eq_id = ListGetInteger( Model % Bodies(body_id) % Values,'Equation', &
                      minv=1,maxv=Model % NumberOfEquations )
           ConvectionFlag = ListGetString( Model % Equations(eq_id) % Values, &
                         'Convection', GotIt )

           ScaledToSolubility = .FALSE.
           ConcentrationUnits = ListGetString( Model % Equations(eq_id) % &
                Values, 'Concentration Units', GotIt )
           IF ( .NOT.GotIt ) AbsoluteMass = .FALSE.
           IF (ConcentrationUnits == 'absolute mass') THEN
              AbsoluteMass = .TRUE.
           ELSE IF (ConcentrationUnits == 'mass to max solubility' ) THEN
              AbsoluteMass = .TRUE.
              ScaledToSolubility = .TRUE.
           ELSE
              AbsoluteMass = .FALSE.
           END IF

           k = ListGetInteger( Model % Bodies( CurrentElement % &
               Bodyid ) % Values, 'Material', minv=1, maxv=Model % NumberOfMaterials )

           Material => Model % Materials(k) % Values

           HeatSolName = ListGetString( Material, &
               'Temperature Field Variable', GotIt )
           IF ( Gotit ) THEN 
             TempSol => VariableGet( Solver % Mesh % Variables, &
                 TRIM( HeatSolName ) )
             IF ( ASSOCIATED( TempSol ) ) THEN
               TempPerm     => TempSol % Perm
               Temperature  => TempSol % Values
             ELSE
               WRITE( Message, * ) 'No temperature  variable ' &
                   // TRIM( HeatSolName ) // ' available'
               CALL Fatal( 'AdvectionDiffusion', Message )
             END IF
           END IF

           ConvectName = ListGetString( Material, &
               'Convection Field Variable', GotIt )
           IF ( GotIt ) THEN
             FlowSol => VariableGet( Solver % Mesh % Variables, &
                 TRIM( ConvectName ) )
             IF ( ASSOCIATED( FlowSol ) ) THEN
               FlowPerm     => FlowSol % Perm
               NSDOFs       =  FlowSol % DOFs
               FlowSolution => FlowSol % Values
             ELSE
               WRITE( Message, * ) 'No convection  variable ' // &
                   TRIM( ConvectName ) // ' available'
               CALL Fatal( 'AdvectionDiffusion', Message )
             END IF
           END IF

!------------------------------------------------------------------------------
           CompressibilityFlag = ListGetString( Material, &
               'Compressibility Model', GotIt)
           IF ( .NOT.GotIt ) CompressibilityModel = Incompressible

           SELECT CASE( CompressibilityFlag )

             CASE( 'incompressible' )
             CompressibilityModel = Incompressible

             CASE( 'user defined 1' )
             CompressibilityModel = UserDefined1

             CASE( 'user defined 2' )
             CompressibilityModel = UserDefined2

             CASE( 'perfect gas equation 1' )
             CompressibilityModel = PerfectGas1

             CASE( 'perfect gas equation 2' )
             CompressibilityModel = PerfectGas2

             CASE( 'perfect gas equation 3' )
             CompressibilityModel = PerfectGas3

           CASE DEFAULT
             CompressibilityModel = Incompressible
           END SELECT
!------------------------------------------------------------------------------
         END IF
!------------------------------------------------------------------------------
!        We've actually got an element for which species concentration
!        is to be calculated
!------------------------------------------------------------------------------
!        Set the current element pointer in the model structure to
!        reflect the element being processed
!------------------------------------------------------------------------------
         Model % CurrentElement => Model % Elements(t)

         n = CurrentElement % TYPE % NumberOfNodes
         NodeIndexes => CurrentElement % NodeIndexes
 
!------------------------------------------------------------------------------
!        Get element nodal coordinates
!------------------------------------------------------------------------------
         ElementNodes % x(1:n) = Solver % Mesh % Nodes % x(NodeIndexes)
         ElementNodes % y(1:n) = Solver % Mesh % Nodes % y(NodeIndexes)
         ElementNodes % z(1:n) = Solver % Mesh % Nodes % z(NodeIndexes)
         IF ( ASSOCIATED( TempSol ) ) THEN
           LocalTemperature(1:n) = Temperature( TempPerm(NodeIndexes) )
         ELSE
           LocalTemperature(1:n) = ListGetReal(  Material, &
                'Reference Temperature',n,NodeIndexes,GotIt )
         ENDIF
!------------------------------------------------------------------------------
!        Get system parameters for element nodal points
!------------------------------------------------------------------------------

! This used to be a Material property, then Solver, again Material...
!        Diffusivity(1:n) = ListGetReal( Material, &
!            Solver % Variable % Name (1:Solver % Variable % NameLen)// &
!        ' Diffusivity', n, NodeIndexes )

         CALL ListGetRealArray( Material,  TRIM(Solver % Variable % Name) // &
                     ' Diffusivity', Hwrk, n, NodeIndexes )

         Diffusivity = 0.0d0
         IF ( SIZE(Hwrk,1) == 1 ) THEN
           DO i=1,3
             Diffusivity( i,i,1:n ) = Hwrk( 1,1,1:n )
           END DO
         ELSE IF ( SIZE(Hwrk,2) == 1 ) THEN
           DO i=1,MIN(3,SIZE(Hwrk,1))
             Diffusivity(i,i,1:n) = Hwrk(i,1,1:n)
           END DO
         ELSE
           DO i=1,MIN(3,SIZE(Hwrk,1))
             DO j=1,MIN(3,SIZE(Hwrk,2))
               Diffusivity( i,j,1:n ) = Hwrk(i,j,1:n)
             END DO
           END DO
         END IF

! This is also different for each species (in the same carrier gas)

         SoretDiffusivity(1:n) = ListGetReal( Material, &
              TRIM( Solver % Variable % Name ) // &
              ' Soret Diffusivity', n, NodeIndexes, GotIt )
         IF ( .NOT. GotIt )  SoretDiffusivity = 0.0d0

         HeatCapacity(1:n) = ListGetReal( Material,'Heat Capacity', &
             n,NodeIndexes,GotIt )

!------------------------------------------------------------------------------
!      Previous solution for element nodal points
!------------------------------------------------------------------------------
!       C(1:n) = Species( SpeciesPerm(NodeIndexes) )
!------------------------------------------------------------------------------

! We need also Density, need to go through all that jazz, if incompressible
         IF ( CompressibilityModel >= PerfectGas1 .AND. &
             CompressibilityModel <= PerfectGas3 ) THEN
!------------------------------------------------------------------------------
! Read Specific Heat Ratio
!------------------------------------------------------------------------------
           SpecificHeatRatio = ListGetConstReal( Material, &
               'Specific Heat Ratio', GotIt )
           IF ( .NOT.GotIt ) SpecificHeatRatio = 1.4d0
!------------------------------------------------------------------------------
! For an ideal gas, \gamma, c_p and R are really a constant
! GasConstant is an array only since HeatCapacity formally is
!------------------------------------------------------------------------------
           GasConstant(1:n) = ( SpecificHeatRatio - 1.d0 ) * &
               HeatCapacity(1:n) / SpecificHeatRatio
         ELSE
           Density(1:n) = ListGetReal( Material,'Density',n,NodeIndexes )
         END IF
! Read p_0
!------------------------------------------------------------------------------
         IF ( CompressibilityModel /= Incompressible ) THEN
           ReferencePressure = ListGetConstReal( Material, &
               'Reference Pressure', GotIt)
           IF ( .NOT.GotIt ) ReferencePressure = 0.0d0
         END IF
! etc.
         Load = 0.d0
         Pressure = 0.d0

!------------------------------------------------------------------------------
!        Check for convection model
!------------------------------------------------------------------------------

         IF ( ConvectionFlag == 'constant' ) THEN
           U = ListGetReal( Material,'Convection Velocity 1',n,NodeIndexes )
           V = ListGetReal( Material,'Convection Velocity 2',n,NodeIndexes )
           W = ListGetReal( Material,'Convection Velocity 3',n,NodeIndexes )
           IF (.NOT. AbsoluteMass) THEN
              C1 = Density
              DO i=1,3
                 DO j=1,3
                    C2(i,j,:) = Density * Diffusivity(i,j,:)
                 END DO
              END DO
           ELSE
              C1 = 1.d0
              DO i=1,3
                 DO j=1,3
                    C2(i,j,:) = Diffusivity(i,j,:)
                 END DO
              END DO
           END IF
           CT = C1
         ELSE IF ( ConvectionFlag == 'computed' ) THEN
! Assumed convection velocity from Restart
           DO i=1,n
             k = FlowPerm(NodeIndexes(i))
             IF ( k > 0 ) THEN

!------------------------------------------------------------------------------
               SELECT CASE( CompressibilityModel )
!------------------------------------------------------------------------------
                 CASE( PerfectGas1,PerfectGas2,PerfectGas3 )
                 Pressure(i) = FlowSolution(NSDOFs*k) + ReferencePressure
                 Density(i)  = Pressure(i) / &
                       ( GasConstant(i) * LocalTemperature(i) )
!------------------------------------------------------------------------------
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
           IF (.NOT. AbsoluteMass) THEN
              C1 = Density
              DO i=1,3
                 DO j=1,3
                    C2(i,j,:) = Density * Diffusivity(i,j,:)
                 END DO
              END DO
           ELSE
              C1 = 1.d0
              DO i=1,3
                 DO j=1,3
                    C2(i,j,:) = Diffusivity(i,j,:)
                 END DO
              END DO
           END IF
           CT = C1
         ELSE  ! Should we allow conduction only (yes!, juha)
           U = 0.0d0
           V = 0.0d0
           W = 0.0d0

           C1 = 0.0d0
           IF (.NOT. AbsoluteMass) THEN
              CT = Density
              DO i=1,3
                 DO j=1,3
                    C2(i,j,:) = Density * Diffusivity(i,j,:)
                 END DO
              END DO
           ELSE
              CT = 1.0d0
              DO i=1,3
                 DO j=1,3
                    C2(i,j,:) = Diffusivity(i,j,:)
                 END DO
              END DO
           END IF
!          PRINT*,'Convection velocity not defined'
!          STOP
         END IF

         MU  = 0.0d0
         MV  = 0.0d0
         MW  = 0.0d0
         IF ( ASSOCIATED( MeshVelocity ) ) THEN
            DO i=1,n
              IF ( MeshPerm( NodeIndexes(i) ) > 0 ) THEN
                 MU(i) = MeshVelocity( MDOFs*(MeshPerm(NodeIndexes(i))-1)+1 )
                 MV(i) = MeshVelocity( MDOFs*(MeshPerm(NodeIndexes(i))-1)+2 )
                 IF ( MDOFs > 2 ) THEN
                    MW(i) = MeshVelocity( MDOFs*(MeshPerm(NodeIndexes(i))-1)+3 )
                 END IF
              END IF
            END DO
         END IF

         C0 = Density
         IF ( ScaledToSolubility ) THEN
            MaxSol = ListGetConstReal( Material, TRIM(Solver % Variable % Name) // &
                 ' Maximum Solubility', GotIt )
            IF ( .NOT. GotIT ) THEN
               WRITE( Message, * ) 'Maximum solubility not defined in body : ', &
                    CurrentElement % BodyId
               CALL Fatal( 'AdvectionDiffusion', Message )
            END IF
            C0 = C0 / MaxSol
         END IF
             


!------------------------------------------------------------------------------
!      Get element local matrix, and rhs vector
!------------------------------------------------------------------------------
! Add body forces here, if any
         bf_id = ListGetInteger( Model % Bodies(CurrentElement % BodyId) % &
           Values, 'Body Force', GotIt, 1, Model % NumberOfBodyForces )

         IF ( GotIt ) THEN
!------------------------------------------------------------------------------
!          Given species source
!------------------------------------------------------------------------------
! Not multiplied by density => Absolute mass source of c_n [kg/m3s]
!
! Take into account scaling of units if source given in physical units

           IF ( ScaledToSolubility .AND. ListGetLogical( Model % &
               BodyForces(bf_id) % Values, 'Physical Units', GotIt ) ) THEN

             Ratio = ListGetConstReal( Material, TRIM(Solver % Variable % Name) // &
                 ' Maximum Solubility', GotIt )
             IF ( .NOT. GotIT ) THEN
               WRITE( Message, * ) 'Maximum solubility not defined in body : ', &
                   CurrentElement % BodyId
               CALL Fatal( 'AdvectionDiffusion', Message )
             END IF
           ELSE
             Ratio = 1.0d0
           END IF
           Load(1:n) = Load(1:n) + &
               ListGetReal( Model % BodyForces(bf_id) % Values,  &
               Solver % Variable % Name (1:Solver % Variable % NameLen)// &
               ' Diffusion Source',n,NodeIndexes,gotIt ) / Ratio
         END IF

!------------------------------------------------------------------------------
         IF ( CoordinateSystem == Cartesian ) THEN
!------------------------------------------------------------------------------
           CALL DiffuseConvectiveCompose( &
             LocalMassMatrix, LocalStiffMatrix, LocalForce, Load, &
              CT, C0, C1, C2, LocalTemperature, U(1:n), V(1:n), W(1:n), MU, MV, MW, &
              SoretDiffusivity, (CompressibilityModel /= Incompressible), &
              AbsoluteMass,Stabilize, Bubbles, CurrentElement, n, ElementNodes )

         ELSE

           CALL DiffuseConvectiveGenCompose( &
             LocalMassMatrix, LocalStiffMatrix, LocalForce, Load, &
              CT, C0, C1, C2, LocalTemperature, U, V, W, MU, MV, MW, &
              SoretDiffusivity, (CompressibilityModel /= Incompressible), &
              AbsoluteMass,Stabilize,CurrentElement, n, ElementNodes )

         END IF

!------------------------------------------------------------------------------
!        If time dependent simulation add mass matrix to stiff matrix
!------------------------------------------------------------------------------
         TimeForce  = LocalForce
         IF ( TransientSimulation ) THEN
!------------------------------------------------------------------------------
!          NOTE: This will replace LocalStiffMatrix and LocalForce with the
!                combined information...
!------------------------------------------------------------------------------
           IF ( Bubbles .AND. ( ConvectionFlag == 'computed' .OR. &
                ConvectionFlag == 'constant' ) ) THEN
              LocalForce = 0.0d0
           END IF
           CALL Add1stOrderTime( LocalMassMatrix, LocalStiffMatrix, &
             LocalForce,dt,n,1,SpeciesPerm(NodeIndexes),Solver )
         END IF
!------------------------------------------------------------------------------
!      Update global matrix and rhs vector from local matrix & vector
!------------------------------------------------------------------------------
         IF ( Bubbles .AND. ( ConvectionFlag == 'computed' .OR. &
              ConvectionFlag == 'constant' ) ) THEN
           CALL Condensate( N, LocalStiffMatrix,  LocalForce, TimeForce )

           IF ( TransientSimulation ) THEN
              CALL UpdateTimeForce( StiffMatrix, ForceVector, TimeForce, &
                         n, 1, SpeciesPerm(NodeIndexes) )
           END IF
         END IF

         CALL UpdateGlobalEquations( StiffMatrix, LocalStiffMatrix, &
          ForceVector, LocalForce, n, 1, SpeciesPerm(NodeIndexes) )
!------------------------------------------------------------------------------
         t = t + 1
!------------------------------------------------------------------------------

       END DO     !  Bulk elements

!------------------------------------------------------------------------------
!     Mixed bulk - boundary element assembly
!
!     This is needed for the flux condition g_1 / g_2 = beta over a boundary
!------------------------------------------------------------------------------

       IF ( ScaledToSolubility ) THEN
         DO t=Solver % Mesh % NumberOfBulkElements + 1, &
             Solver % Mesh % NumberOfBulkElements + Solver % Mesh % NumberOfBoundaryElements

           CurrentElement => Solver % Mesh % Elements(t)
!------------------------------------------------------------------------------
!       the element type 101 (point element) can only be used
!       to set Dirichlet BCs, so skip 'em.
!------------------------------------------------------------------------------
           IF ( CurrentElement % TYPE % ElementCode == 101 ) CYCLE
!------------------------------------------------------------------------------
           DO i=1,Model % NumberOfBCs
             IF ( CurrentElement % BoundaryInfo % Constraint == &
                 Model % BCs(i) % Tag ) THEN

               IF ( .NOT. ListGetLogical( Model % BCs(i) % Values, &
                   TRIM(Solver % Variable % Name) // ' Solubility Change Boundary', &
                   GotIt ) )  CYCLE

!------------------------------------------------------------------------------
!             Set the current element pointer in the model structure to
!             reflect the element being processed
!------------------------------------------------------------------------------
               Model % CurrentElement => Solver % Mesh % Elements(t)
!------------------------------------------------------------------------------
               n = CurrentElement % TYPE % NumberOfNodes
               NodeIndexes => CurrentElement % NodeIndexes

               ElementNodes % x(1:n) = Solver % Mesh % Nodes % x(NodeIndexes)
               ElementNodes % y(1:n) = Solver % Mesh % Nodes % y(NodeIndexes)
               ElementNodes % z(1:n) = Solver % Mesh % Nodes % z(NodeIndexes)

!------------------------------------------------------------------------------
!             Get normal target body. The parent element from the opposite
!             direction is used for normal derivative calculation
!------------------------------------------------------------------------------
               body_id = ListGetInteger( Model % BCs(i) % Values, &
                   'Normal Target Body', GotIt, minv=1, maxv=Model % NumberOfBodies )
!------------------------------------------------------------------------------
!             If normal target body not defined check which direction is used
!             by the NormalVector function
!------------------------------------------------------------------------------

               IF ( .NOT. GotIt ) THEN
!------------------------------------------------------------------------------
!               Force normal to point to CurrentElement % BoundaryInfo % LBody
!------------------------------------------------------------------------------
                 body_id = CurrentElement % BoundaryInfo % LBody
                 outbody = CurrentElement % BoundaryInfo % OutBody
                 CurrentElement % BoundaryInfo % OutBody = body_id
                 Nrm = NormalVector( CurrentElement, ElementNodes, &
                     CurrentElement % TYPE % NodeU(1), CurrentElement % TYPE % NodeV(1), &
                     .TRUE. )
!------------------------------------------------------------------------------
!               Check which direction NormalVector chooses
!------------------------------------------------------------------------------
                 CurrentElement % BoundaryInfo % OutBody = outbody
                 Nrm2 = NormalVector( CurrentElement, ElementNodes, &
                     CurrentElement % TYPE % NodeU(1), CurrentElement % TYPE % NodeV(1), &
                     .TRUE. )
!------------------------------------------------------------------------------
!               Change body_id if Nrm and Nrm2 point to different directions
!------------------------------------------------------------------------------
                 IF ( SUM( Nrm(1:3) * Nrm2(1:3) ) < 0 ) &
                     body_id = CurrentElement % BoundaryInfo % RBody
               END IF
!------------------------------------------------------------------------------

               k = ListGetInteger( Model % Bodies( body_id ) % Values, &
                   'Material', minv=1, maxv=Model % NumberOfMaterials )
               Material => Model % Materials(k) % Values                

               Ratio = ListGetConstReal( Material, TRIM(Solver % Variable % Name) // &
                   ' Maximum Solubility', GotIt )

               IF ( .NOT. GotIT ) THEN
                 WRITE( Message, * ) 'No maximum solubility defined for material : ', k
                 CALL Fatal( 'AdvectionDiffusion', Message )
               END IF

               IF ( CurrentElement % BoundaryInfo % LBody == body_id ) THEN
                 k = ListGetInteger( Model % Bodies( CurrentElement % &
                     BoundaryInfo % RBody ) % Values, 'Material', &
                     minv=1,maxv=Model % NumberOfMaterials )
                 Parent => CurrentElement % BoundaryInfo % Right
               ELSE
                 k = ListGetInteger( Model % Bodies( CurrentElement % &
                     BoundaryInfo % LBody ) % Values, 'Material', &
                     minv=1,maxv=Model % NumberOfMaterials )
                 Parent => CurrentElement % BoundaryInfo % Left
               END IF
               Material => Model % Materials(k) % Values                
               Ratio = &
                   ListGetConstReal( Material, TRIM(Solver % Variable % Name) // &
                   ' Maximum Solubility', GotIt ) / Ratio

               IF ( .NOT. GotIT ) THEN
                 WRITE( Message, * ) 'No maximum solubility defined for material : ', k
                 CALL Fatal( 'AdvectionDiffusion', Message )
               END IF
               Ratio = Ratio - 1.0d0

!------------------------------------------------------------------------------
!            Get the diffusivity tensor
!------------------------------------------------------------------------------
               CALL ListGetRealArray( Material,  TRIM(Solver % Variable % Name) // &
                   ' Diffusivity', Hwrk, n, NodeIndexes )

               Diffusivity = 0.0d0
               IF ( SIZE(Hwrk,1) == 1 ) THEN
                 DO m=1,3
                   Diffusivity( m,m,1:n ) = Hwrk( 1,1,1:n )
                 END DO
               ELSE IF ( SIZE(Hwrk,2) == 1 ) THEN
                 DO m=1,MIN(3,SIZE(Hwrk,1))
                   Diffusivity(m,m,1:n) = Hwrk(m,1,1:n)
                 END DO
               ELSE
                 DO m=1,MIN(3,SIZE(Hwrk,1))
                   DO j=1,MIN(3,SIZE(Hwrk,2))
                     Diffusivity( m,j,1:n ) = Hwrk(m,j,1:n)
                   END DO
                 END DO
               END IF

               pn = Parent % TYPE % NumberOfNodes
               
               ParentNodes % x(1:pn) = Solver % Mesh % Nodes % x(Parent % NodeIndexes)
               ParentNodes % y(1:pn) = Solver % Mesh % Nodes % y(Parent % NodeIndexes)
               ParentNodes % z(1:pn) = Solver % Mesh % Nodes % z(Parent % NodeIndexes)
!------------------------------------------------------------------------------
!             Get element matrix and rhs due to boundary conditions ...
!------------------------------------------------------------------------------
               IF ( CoordinateSystem == Cartesian ) THEN
                 CALL DiffuseConvectiveBBoundary( LocalStiffMatrix, Parent, pn, &
                     ParentNodes, Ratio, CurrentElement, n, ElementNodes )
               ELSE
                 CALL DiffuseConvectiveGenBBoundary(LocalStiffMatrix, Parent, &
                     pn, ParentNodes, Ratio, CurrentElement,n , ElementNodes ) 
               END IF
!------------------------------------------------------------------------------
!             Update global matrices from local matrices
!------------------------------------------------------------------------------
             IF ( TransientSimulation ) THEN
               LocalMassMatrix = 0.0d0
               LocalForce = 0.0d0
               CALL Add1stOrderTime( LocalMassMatrix, LocalStiffMatrix, &
                   LocalForce,dt,pn,1,SpeciesPerm(Parent % NodeIndexes),Solver )
             END IF

               CALL UpdateGlobalEquations( StiffMatrix, LocalStiffMatrix, &
                   ForceVector, LocalForce, pn, 1, SpeciesPerm(Parent % NodeIndexes) )
!------------------------------------------------------------------------------
             END IF ! of currentelement bc == bcs(i)
           END DO ! of i=1,model bcs
         END DO   ! Boundary - bulk element assembly
!------------------------------------------------------------------------------
       END IF  ! If ScaledToSolubility

!------------------------------------------------------------------------------
!     Boundary element assembly
!------------------------------------------------------------------------------
       ErrorWritten = .FALSE.
       DO t=Solver % Mesh % NumberOfBulkElements + 1, &
           Solver % Mesh % NumberOfBulkElements + Solver % Mesh % NumberOfBoundaryElements

         CurrentElement => Solver % Mesh % Elements(t)
!------------------------------------------------------------------------------
!       the element type 101 (point element) can only be used
!       to set Dirichlet BCs, so skip 'em.
!------------------------------------------------------------------------------
         IF ( CurrentElement % TYPE % ElementCode == 101 ) CYCLE
!------------------------------------------------------------------------------
         DO i=1,Model % NumberOfBCs
           IF ( CurrentElement % BoundaryInfo % Constraint == &
               Model % BCs(i) % Tag ) THEN

!------------------------------------------------------------------------------
!             Set the current element pointer in the model structure to
!             reflect the element being processed
!------------------------------------------------------------------------------
              Model % CurrentElement => Solver % Mesh % Elements(t)
!------------------------------------------------------------------------------
              n = CurrentElement % TYPE % NumberOfNodes
              NodeIndexes => CurrentElement % NodeIndexes

              IF ( ANY( SpeciesPerm( NodeIndexes ) <= 0 ) ) CYCLE

              ElementNodes % x(1:n) = Solver % Mesh % Nodes % x(NodeIndexes)
              ElementNodes % y(1:n) = Solver % Mesh % Nodes % y(NodeIndexes)
              ElementNodes % z(1:n) = Solver % Mesh % Nodes % z(NodeIndexes)

              SpeciesTransferCoeff = 0.0D0
              SExt = 0.0D0
              Load = 0.0D0

              SpeciesTransferCoeff(1:n) = ListGetReal( Model % BCs(i) % Values,&
                   'Mass Transfer Coefficient', n, NodeIndexes, GotIt )
              IF ( ANY(SpeciesTransferCoeff(1:n) /= 0.0d0) ) THEN
                 SExt(1:n) = ListGetReal( Model % BCs(i) % Values, &
                      'External Concentration', n, NodeIndexes, GotIt )
                 
                 IF ( .NOT. AbsoluteMass .OR. ScaledToSolubility ) THEN
                    IF ( .NOT. ErrorWritten ) THEN
                       CALL Error( 'AdvectionDiffusion', '--------------------' )
                       CALL Error( 'AdvectionDiffusion', &
                            'Mass transfer coefficient possible to use only with absolute mass concentrations' )
                       CALL Error( 'AdvectionDiffusion', &
                            'Ignoring mass transfer BC' )
                       CALL Error( 'AdvectionDiffusion', '--------------------' )
                       ErrorWritten = .TRUE.
                    END IF
                    SExt = 0.0d0
                    SpeciesTransferCoeff = 0.0d0
                 END IF
              ELSE
                 SExt(1:n) = 0.0d0
              END IF

!------------------------------------------------------------------------------
!           BC: -D@c/@n = \alpha(C - Cext)
!------------------------------------------------------------------------------
              DO j=1,n
                 Load(j) = Load(j) + SpeciesTransferCoeff(j) * SExt(j)
              END DO

!------------------------------------------------------------------------------
!             BC: j_n=-\rho*\alpha*@c/@n = g
!------------------------------------------------------------------------------

              IF ( ScaledToSolubility .AND. ListGetLogical( Model % &
                  BCs(i) % Values, 'Physical Units', GotIt ) ) THEN

                Ratio = ListGetConstReal( Material, TRIM(Solver % Variable % Name) // &
                    ' Maximum Solubility', GotIt )
                IF ( .NOT. GotIT ) THEN
                  WRITE( Message, * ) 'No maximum solubility defined in body : ', &
                      CurrentElement % BodyId
                  CALL Fatal( 'AdvectionDiffusion', Message )
                END IF
              ELSE
                Ratio = 1.0d0
              END IF
              Load(1:n) = Load(1:n) + &
                  ListGetReal( Model % BCs(i) % Values, &
                  Solver % Variable % Name (1:Solver % Variable % NameLen)// &
                  ' Flux', n,NodeIndexes,gotIt ) / Ratio
!------------------------------------------------------------------------------
!             Get element matrix and rhs due to boundary conditions ...
!------------------------------------------------------------------------------
              IF ( CoordinateSystem == Cartesian ) THEN
                CALL DiffuseConvectiveBoundary( LocalStiffMatrix,LocalForce, &
                  Load,SpeciesTransferCoeff,CurrentElement,n,ElementNodes )
              ELSE
                CALL DiffuseConvectiveGenBoundary(LocalStiffMatrix,LocalForce,&
                  Load,SpeciesTransferCoeff,CurrentElement,n,ElementNodes ) 
              END IF
!------------------------------------------------------------------------------
!             Update global matrices from local matrices
!------------------------------------------------------------------------------
              IF ( TransientSimulation ) THEN
                LocalMassMatrix = 0.0d0
                CALL Add1stOrderTime( LocalMassMatrix, LocalStiffMatrix, &
                  LocalForce,dt,n,1,SpeciesPerm(NodeIndexes),Solver )
              END IF

              CALL UpdateGlobalEquations( StiffMatrix, LocalStiffMatrix, &
                ForceVector, LocalForce, n, 1, SpeciesPerm(NodeIndexes) )
!------------------------------------------------------------------------------
          END IF ! of currentelement bc == bcs(i)
        END DO ! of i=1,model bcs
      END DO   ! Boundary element assembly
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
!    FinishAssemebly must be called after all other assembly steps, but before
!    Dirichlet boundary settings. Actually no need to call it except for
!    transient simulations.
!------------------------------------------------------------------------------
      CALL FinishAssembly( Solver,ForceVector )
!------------------------------------------------------------------------------
!    Dirichlet boundary conditions
!------------------------------------------------------------------------------
      CALL SetDirichletBoundaries( Model, StiffMatrix, ForceVector, &
          Solver % Variable % Name (1:Solver % Variable % NameLen), &
          1,1,SpeciesPerm )

!------------------------------------------------------------------------------
      CALL Info( 'AdvectionDiffusion', 'Assembly done', Level=4 )

!------------------------------------------------------------------------------
!     Solve the system and check for convergence
!------------------------------------------------------------------------------
      at = CPUTime() - at
      st = CPUTime()

      PrevNorm = Norm
!------------------------------------------------------------------------------
!    Solve the system and we are done.
!------------------------------------------------------------------------------
!PRINT*,'Mass before: ',mass
      CALL SolveSystem( StiffMatrix, ParMatrix, ForceVector, &
                   Species, Norm, 1, Solver )

      st = CPUTIme()-st
      totat = totat + at
      totst = totst + st
      WRITE(Message,'(a,i4,a,F8.2,F8.2)') 'iter: ',iter,' Assembly: (s)', at, totat
      CALL Info( 'AdvectionDiffusion', Message, Level=4 )
      WRITE(Message,'(a,i4,a,F8.2,F8.2)') 'iter: ',iter,' Solve:    (s)', st, totst
      CALL Info( 'AdvectionDiffusion', Message, Level=4 )
!------------------------------------------------------------------------------
!     PRINT*,PrevNorm,Norm 
      RelativeChange = 2*ABS(PrevNorm-Norm) / (PrevNorm + Norm)

      WRITE( Message, * ) 'Result Norm   : ',Norm
      CALL Info( 'AdvectionDiffusion', Message, Level=4 )
      WRITE( Message, * ) 'Relative Change : ',RelativeChange
      CALL Info( 'AdvectionDiffusion', Message, Level=4 )


      IF ( RelativeChange < NonlinearTol ) EXIT

!------------------------------------------------------------------------------
    END DO! of the nonlinear iteration
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
! Check if integration of species density over volume really requested,
! if not return...
!------------------------------------------------------------------------------
      U(1:n) = ListGetReal( Model % Simulation, 'Species Density', &
                  n, NodeIndexes,GotIt )
      IF ( .NOT.GotIt ) RETURN
!------------------------------------------------------------------------------

      IF ( TransientSimulation )  PreviousMass = Mass

! Pick all elements for the volume integration
!    ElementList= (/ (i, i=1, Solver % Mesh %  NumberOfBulkElements ) /)
! Pick only the elements where species concentration is calculated
       body_id = -1
       NULLIFY(Material)
       i = 1
!------------------------------------------------------------------------------
!      Go through all bulk elements
!------------------------------------------------------------------------------
       t = 1
       DO WHILE( t <= Solver % Mesh % NumberOfBulkElements )
!------------------------------------------------------------------------------
!        Check if this element belongs to a body where species
!        advection-diffusion was calculated
!------------------------------------------------------------------------------
         CurrentElement => Solver % Mesh % Elements(t)
!------------------------------------------------------------------------------
         IF ( CurrentElement % BodyId /= body_id ) THEN
!------------------------------------------------------------------------------
           DO WHILE( t <= Solver % Mesh % NumberOfBulkElements )
             IF ( CheckElementEquation( &
                 Model,CurrentElement,EquationName ) ) EXIT
             t = t + 1
             CurrentElement => Solver % Mesh % Elements(t)
           END DO

           IF ( t > Solver % Mesh % NumberOfBulkElements ) EXIT

           body_id = CurrentElement % Bodyid    

         END IF
!------------------------------------------------------------------------------
!        We've actually got an element for which species concentration
!        was calculated
!------------------------------------------------------------------------------
         ElementList(i) = t
         i = i + 1
         t = t + 1
           
       END DO!  Bulk elements

! Integrate only over gas
!   PRINT*,ElementList(1:i-1)
    Mass = VolumeIntegrate( Model, ElementList(1:i-1), 'Species Density' )
    IF ( TransientSimulation )  PRINT*,'Mass Gain: ',Mass - PreviousMass
    PRINT*,'Species Mass',Mass
!------------------------------------------------------------------------------

CONTAINS

!*******************************************************************************
! *
! * Diffuse-convective local matrix computing (cartesian coordinates)
! *
! *******************************************************************************

!------------------------------------------------------------------------------
   SUBROUTINE DiffuseConvectiveCompose( MassMatrix,StiffMatrix,ForceVector,  &
      LoadVector,NodalCT,NodalC0,NodalC1,NodalC2,Temperature, &
         Ux,Uy,Uz,MUx,MUy,MUz,SoretD,Compressible,AbsoluteMass, &
           Stabilize,UseBubbles,Element,n,Nodes )
!------------------------------------------------------------------------------
!******************************************************************************
!
!  Return element local matrices and RSH vector for diffusion-convection
!  equation: 
!
!  ARGUMENTS:
!
!  REAL(KIND=dp) :: MassMatrix(:,:)
!     OUTPUT: time derivative coefficient matrix
!
!  REAL(KIND=dp) :: StiffMatrix(:,:)
!     OUTPUT: rest of the equation coefficients
!
!  REAL(KIND=dp) :: ForceVector(:)
!     OUTPUT: RHS vector
!
!  REAL(KIND=dp) :: LoadVector(:)
!     INPUT:
!
!  REAL(KIND=dp) :: NodalCT,NodalC0,NodalC1
!     INPUT: Coefficient of the time derivative term, 0 degree term, and
!            the convection term respectively
!
!  REAL(KIND=dp) :: NodalC2(:,:,:)
!     INPUT: Nodal values of the diffusion term coefficient tensor
!
!
!  REAL(KIND=dp) :: Temperature
!     INPUT: Temperature from previous iteration, needed if we model
!            phase change
!
!  REAL(KIND=dp) :: SoretD
!     INPUT: Soret Diffusivity D_t : j_t = D_t grad(T)
!
!  REAL(KIND=dp) :: Ux(:),Uy(:),Uz(:)
!     INPUT: Nodal values of velocity components from previous iteration
!           used only if coefficient of the convection term (C1) is nonzero
!
!  LOGICAL :: Stabilize
!     INPUT: Should stabilzation be used ? Used only if coefficient of the
!            convection term (C1) is nonzero
!
!  TYPE(Element_t) :: Element
!       INPUT: Structure describing the element (dimension,nof nodes,
!               interpolation degree, etc...)
!
!  INTEGER :: n
!       INPUT: Number of element nodes
!
!  TYPE(Nodes_t) :: Nodes
!       INPUT: Element node coordinates
!
!******************************************************************************

     REAL(KIND=dp), DIMENSION(:)   :: ForceVector,Ux,Uy,Uz,MUx,MUy,MUz,LoadVector
     REAL(KIND=dp), DIMENSION(:,:) :: MassMatrix,StiffMatrix
     REAL(KIND=dp) :: Temperature(:), SoretD(:)
     REAL(KIND=dp) :: NodalC0(:),NodalC1(:),NodalCT(:),NodalC2(:,:,:),dT

     LOGICAL :: Stabilize,UseBubbles,Compressible,AbsoluteMass

     INTEGER :: n

     TYPE(Nodes_t) :: Nodes
     TYPE(Element_t), POINTER :: Element

!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------
!
     REAL(KIND=dp) :: ddBasisddx(n,3,3)
     REAL(KIND=dp) :: Basis(2*n)
     REAL(KIND=dp) :: dBasisdx(2*n,3),SqrtElementMetric

     REAL(KIND=dp) :: Velo(3),dVelodx(3,3),Force

     REAL(KIND=dp) :: A,M
     REAL(KIND=dp) :: Load

     REAL(KIND=dp) :: VNorm,hK,mK
     REAL(KIND=dp) :: Lambda=1.0,Pe,Pe1,Pe2,Tau,x,y,z

     REAL(KIND=dp) :: SorD, GradTemp(3), SoretForce

     INTEGER :: i,j,k,c,p,q,t,dim,N_Integ,NBasis

     TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff
     REAL(KIND=dp) :: s,u,v,w,DivVelo

     REAL(KIND=dp) :: C0,C00,C1,CT,C2(3,3),dC2dx(3,3,3),SU(n),SW(n)
     REAL(KIND=dp) :: NodalCThermal(n), CThermal

     REAL(KIND=dp), DIMENSION(:), POINTER :: U_Integ,V_Integ,W_Integ,S_Integ

     LOGICAL :: stat,Convection,ConvectAndStabilize,Bubbles,ThermalDiffusion

!------------------------------------------------------------------------------

     dim = CoordinateSystemDimension()
     c = dim + 1

     ForceVector = 0.0D0
     StiffMatrix = 0.0D0
     MassMatrix  = 0.0D0
     Load = 0.0D0
     Convection =  ANY( NodalC1 /= 0.0d0 )
     NBasis = n
     Bubbles = .FALSE.
     IF ( Convection .AND. .NOT. Stabilize .AND. UseBubbles ) THEN
        NBasis = 2*n
        Bubbles = .TRUE.
     END IF

     ThermalDiffusion = .FALSE.
     IF ( ANY( ABS( SoretD(1:n) ) > AEPS ) ) THEN
        ThermalDiffusion = .TRUE. 
        NodalCThermal = NodalC0(1:n)
     END IF
     NodalC0 = 0.0d0   ! this is the way it works, maybe could do better some time

!------------------------------------------------------------------------------
!    Integration stuff
!------------------------------------------------------------------------------
     IF ( Bubbles ) THEN
        IntegStuff = GaussPoints( element, Element % TYPE % GaussPoints2 )
     ELSE
        IntegStuff = GaussPoints( element )
     END IF
     U_Integ => IntegStuff % u
     V_Integ => IntegStuff % v
     W_Integ => IntegStuff % w
     S_Integ => IntegStuff % s
     N_Integ =  IntegStuff % n

!------------------------------------------------------------------------------
!    Stabilization parameters: hK, mK (take a look at Franca et.al.)
!    If there is no convection term we don t need stabilization.
!------------------------------------------------------------------------------
     ConvectAndStabilize = .FALSE.
     IF ( Stabilize .AND. Convection ) THEN
       ConvectAndStabilize = .TRUE.
       hK = element % hK
       mK = element % StabilizationMK
     END IF

!------------------------------------------------------------------------------
!    Now we start integrating
!------------------------------------------------------------------------------
     DO t=1,N_Integ

       u = U_Integ(t)
       v = V_Integ(t)
       w = W_Integ(t)

!------------------------------------------------------------------------------
!      Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
       stat = ElementInfo( Element,Nodes,u,v,w,SqrtElementMetric, &
             Basis,dBasisdx,ddBasisddx,ConvectAndStabilize,Bubbles )

       s = SqrtElementMetric * S_Integ(t)
!------------------------------------------------------------------------------
!      Coefficient of the convection and time derivative terms
!      at the integration point
!------------------------------------------------------------------------------
       C0 = SUM( NodalC0(1:n) * Basis(1:n) )
       C1 = SUM( NodalC1(1:n) * Basis(1:n) )
       CT = SUM( NodalCT(1:n) * Basis(1:n) )


!------------------------------------------------------------------------------
!      Coefficient of the diffusion term & it s derivatives at the
!      integration point
!------------------------------------------------------------------------------
       DO i=1,dim
         DO j=1,dim
           C2(i,j) = SUM( NodalC2(i,j,1:n) * Basis(1:n) )
         END DO
       END DO
!------------------------------------------------------------------------------
!      If there's no convection term we don't need the velocities, and
!      also no need for stabilization
!------------------------------------------------------------------------------
       Convection = .FALSE.
       IF ( C1 /= 0.0D0 ) THEN
          Convection = .TRUE.
!------------------------------------------------------------------------------
!         Velocity from previous iteration at the integration point
!------------------------------------------------------------------------------
          Velo = 0.0D0
          Velo(1) = SUM( (Ux(1:n)-MUx(1:n))*Basis(1:n) )
          Velo(2) = SUM( (Uy(1:n)-MUy(1:n))*Basis(1:n) )
          IF ( dim > 2 ) Velo(3) = SUM( (Uz(1:n)-MUz(1:n))*Basis(1:n) )

          IF ( Compressible .AND. AbsoluteMass ) THEN
            dVelodx = 0.0D0
            DO i=1,3
              dVelodx(1,i) = SUM( Ux(1:n)*dBasisdx(1:n,i) )
              dVelodx(2,i) = SUM( Uy(1:n)*dBasisdx(1:n,i) )
              IF ( dim > 2 ) dVelodx(3,i) = SUM( Uz(1:n)*dBasisdx(1:n,i) )
            END DO

            DivVelo = 0.0D0
            DO i=1,dim
              DivVelo = DivVelo + dVelodx(i,i)
            END DO
            C0 = DivVelo
          END IF

          IF ( Stabilize ) THEN
!------------------------------------------------------------------------------
!           Stabilization parameter Tau
!------------------------------------------------------------------------------
            VNorm = SQRT( SUM(Velo(1:dim)**2) )

!#if 1
            Pe  = MIN( 1.0D0, mK*hK*C1*VNorm/(2*ABS(C2(1,1))) )

            Tau = 0.0D0
            IF ( VNorm /= 0.0 ) THEN
               Tau = hK * Pe / (2 * C1 * VNorm)
            END IF
!#else
!            C00 = C0
!            IF ( DT /= 0.0d0 ) C00 = C0 + CT / DT
!
!            Pe1 = 0.0d0
!            IF ( C00 /= 0.0d0 ) THEN
!              Pe1 = 2 * ABS(C2(1,1)) / ( mK * C00 * hK**2 )
!              Pe1 = C00 * hK**2 * MAX( 1.0d0, Pe1 )
!            ELSE
!              Pe1 = 2 * ABS(C2(1,1)) / mK
!            END IF
!
!            Pe2 = 0.0d0
!            IF ( C2(1,1) /= 0.0d0 ) THEN
!              Pe2 = ( mK * C1 * VNorm * hK ) / ABS(C2(1,1))
!              Pe2 = 2 * ABS(C2(1,1)) * MAX( 1.0d0, Pe2 ) / mK
!            ELSE
!              Pe2 = 2 * hK * C1 * VNorm
!            END IF
!
!            Tau = hk**2 / ( Pe1 + Pe2 )
!#endif
!------------------------------------------------------------------------------

            DO i=1,dim
              DO j=1,dim
                DO k=1,dim
                  dC2dx(i,j,k) = SUM( NodalC2(i,j,1:n)*dBasisdx(1:n,k) )
                END DO
              END DO
            END DO

!------------------------------------------------------------------------------
!           Compute residual & stablization vectors
!------------------------------------------------------------------------------
            DO p=1,N
              SU(p) = C0 * Basis(p)
              DO i = 1,dim
                SU(p) = SU(p) + C1 * dBasisdx(p,i) * Velo(i)
                DO j=1,dim
                  SU(p) = SU(p) - C2(i,j) * ddBasisddx(p,i,j)
                  SU(p) = SU(p) - dC2dx(i,j,j) * dBasisdx(p,i)
                END DO
              END DO

              SW(p) = C0 * Basis(p)
              DO i = 1,dim
                SW(p) = SW(p) + C1 * dBasisdx(p,i) * Velo(i)
                DO j=1,dim
                  SW(p) = SW(p) - C2(i,j) * ddBasisddx(p,i,j)
                  SW(p) = SW(p) - dC2dx(i,j,j) * dBasisdx(p,i)
                END DO
              END DO
            END DO
          END IF
        END IF

!------------------------------------------------------------------------------
!       Loop over basis functions of both unknowns and weights
!------------------------------------------------------------------------------
        DO p=1,NBasis
        DO q=1,NBasis
!------------------------------------------------------------------------------
!         The diffusive-convective equation without stabilization
!------------------------------------------------------------------------------
          M = CT * Basis(q) * Basis(p)
          A = C0 * Basis(q) * Basis(p)
!------------------------------------------------------------------------------
!         The diffusion term
!------------------------------------------------------------------------------
          DO i=1,dim
            DO j=1,dim
              A = A + C2(i,j) * dBasisdx(q,i) * dBasisdx(p,j)
            END DO
          END DO

          IF ( Convection ) THEN
!------------------------------------------------------------------------------
!           The convection term
!------------------------------------------------------------------------------
            DO i=1,dim
              A = A + C1 * Velo(i) * dBasisdx(q,i) * Basis(p)
            END DO
!------------------------------------------------------------------------------
!           Next we add the stabilization...
!------------------------------------------------------------------------------
            IF ( Stabilize ) THEN
              A = A + Tau * SU(q) * SW(p)
              M = M + Tau * CT * Basis(q) * SW(p)
            END IF
          END IF

          StiffMatrix(p,q) = StiffMatrix(p,q) + s * A
          MassMatrix(p,q)  = MassMatrix(p,q)  + s * M
        END DO
        END DO

!------------------------------------------------------------------------------
!       The righthand side...
!------------------------------------------------------------------------------
!       Force at the integration point
!------------------------------------------------------------------------------
        Force = SUM( LoadVector(1:n)*Basis(1:n) )

!------------------------------------------------------------------------------
        DO p=1,NBasis
          Load = Basis(p)
          IF ( ConvectAndStabilize ) Load = Load + Tau * SW(p)
          ForceVector(p) = ForceVector(p) + s * Force * Load
        END DO

!------------------------------------------------------------------------------
!     Add Soret diffusivity if necessary
!     -div( rho D_t grad(T)) 
!------------------------------------------------------------------------------

        IF ( ThermalDiffusion ) THEN

           CThermal = SUM( NodalCThermal(1:n) * Basis(1:n) )

           GradTemp = 0.0d0
           DO i = 1, dim
              GradTemp(i) = SUM( dBasisdx(1:n,i) * Temperature(1:n) )
           END DO
           SorD = SUM( Basis(1:n) * SoretD(1:n) )

           DO p=1,NBasis
              IF ( ConvectAndStabilize ) THEN 
                 Load = Tau * SW(p)
              ELSE
                 Load = 1.0d0
              END IF

              SoretForce = CThermal * SorD * SUM( GradTemp(1:dim) * dBasisdx(p,1:dim) )
              ForceVector(p) = ForceVector(p) - s * SoretForce * Load
           END DO
            
        END IF

     END DO


!------------------------------------------------------------------------------
   END SUBROUTINE DiffuseConvectiveCompose
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   SUBROUTINE DiffuseConvectiveBBoundary( BoundaryMatrix, Parent, &
               pn, ParentNodes, Ratio, Element, n, Nodes )
!------------------------------------------------------------------------------
!******************************************************************************
!
!  Return element local matrices for a discontinuous flux boundary conditions
!  of diffusion equation: 
!
!  ARGUMENTS:
!
!  REAL(KIND=dp) :: BoundaryMatrix(:,:)
!      OUTPUT: coefficient matrix if equations
!
!  TYPE(Element_t) :: Parent
!       INPUT: Structure describing the boundary elements parent
!
!  INTEGER :: pn
!       INPUT: Number of parent element nodes
!
!  TYPE(Nodes_t) :: ParentNodes
!       INPUT: Parent element node coordinates
!
!  REAL(KIND=dp) :: Ratio
!       INPUT: The ratio of maximal solubilities - 1 (defining the 
!             measure of discontinuity)
!
!  TYPE(Element_t) :: Element
!       INPUT: Structure describing the element (dimension,nof nodes,
!               interpolation degree, etc...)
!
!  INTEGER :: n
!       INPUT: Number  of element nodes
!
!  TYPE(Nodes_t) :: Nodes
!       INPUT: Element node coordinates
!
!******************************************************************************

     TYPE(Nodes_t) :: Nodes, ParentNodes
     TYPE(Element_t), POINTER :: Element, Parent
     REAL(KIND=dp) :: BoundaryMatrix(:,:), Ratio
     INTEGER :: n, pn

     REAL(KIND=dp) :: ddBasisddx(n,3,3), ParentdBasisdx(pn,3)
     REAL(KIND=dp) :: Basis(n), ParentBasis(pn)
     REAL(KIND=dp) :: dBasisdx(n,3), SqrtElementMetric

     REAL(KIND=dp) :: Diff(3,3)
     REAL(KIND=dp) :: u, v, w, s, x(n), y(n), z(n), Normal(3), FluxVector(3)
     REAL(KIND=dp), POINTER :: U_Integ(:), V_Integ(:), W_Integ(:), S_Integ(:)

     INTEGER :: ParentNodeIndexes(n)
     INTEGER :: i, t, q, p, N_Integ, j

     TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff

     LOGICAL :: stat
!------------------------------------------------------------------------------

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

       Normal = Normalvector( Element, Nodes, u, v, .TRUE. )
!------------------------------------------------------------------------------
!      Need parent element basis functions for calculating normal derivatives
!------------------------------------------------------------------------------
       DO i = 1,n
         DO j = 1,pn
           IF ( Element % NodeIndexes(i) == Parent % NodeIndexes(j) ) THEN
             x(i) = Parent % TYPE % NodeU(j)
             y(i) = Parent % TYPE % NodeV(j)
             z(i) = Parent % TYPE % NodeW(j)
             ParentNodeIndexes(i) = j
             EXIT
           END IF
         END DO
       END DO

       u = SUM( Basis(1:n) * x(1:n) )
       v = SUM( Basis(1:n) * y(1:n) )
       w = SUM( Basis(1:n) * z(1:n) )

       stat = ElementInfo( Parent, ParentNodes,u, v, w, SqrtElementMetric, &
           ParentBasis, ParentdBasisdx, ddBasisddx, .FALSE. )

       FluxVector = 0.0d0

       DO i = 1, 3
         DO j = 1, 3
           Diff(i,j) = SUM( Diffusivity(i,j,1:n) * Basis(1:n) )
         END DO
       END DO

       DO q = 1, pn
         DO j = 1, 3
           FluxVector(j) = SUM( Diff(j,1:3) * ParentdBasisdx(q,1:3) )
         END DO
         DO i = 1, n
           p = ParentNodeIndexes(i)
           BoundaryMatrix(p,q) = BoundaryMatrix(p,q) + Ratio * &
               s * Basis(i) * SUM( FluxVector(1:3) * Normal(1:3) )
         END DO
       END DO

     END DO

   END SUBROUTINE DiffuseConvectiveBBoundary
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
   SUBROUTINE DiffuseConvectiveBoundary( BoundaryMatrix,BoundaryVector, &
               LoadVector,NodalAlpha,Element,n,Nodes )
!------------------------------------------------------------------------------
!******************************************************************************
!
!  Return element local matrices and RSH vector for boundary conditions
!  of diffusion convection equation: 
!
!  ARGUMENTS:
!
!  REAL(KIND=dp) :: BoundaryMatrix(:,:)
!     OUTPUT: coefficient matrix if equations
!
!  REAL(KIND=dp) :: BoundaryVector(:)
!     OUTPUT: RHS vector
!
!  REAL(KIND=dp) :: LoadVector(:)
!     INPUT: coefficient of the force term
!
!  REAL(KIND=dp) :: NodalAlpha
!     INPUT: coefficient for temperature dependent term
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

     REAL(KIND=dp) :: BoundaryMatrix(:,:),BoundaryVector(:), &
                    LoadVector(:),NodalAlpha(:)

     TYPE(Nodes_t)   :: Nodes
     TYPE(Element_t) :: Element

     INTEGER :: n

     REAL(KIND=dp) :: ddBasisddx(n,3,3)
     REAL(KIND=dp) :: Basis(n)
     REAL(KIND=dp) :: dBasisdx(n,3),SqrtElementMetric

     REAL(KIND=dp) :: u,v,w,s
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
       Force = SUM( LoadVector(1:n)*Basis )
       Alpha = SUM( NodalAlpha(1:n)*Basis )

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
   END SUBROUTINE DiffuseConvectiveBoundary
!------------------------------------------------------------------------------

!*******************************************************************************
! *
! *  Diffuse-convective local matrix computing (general euclidian coordinates)
! *
! *******************************************************************************
!------------------------------------------------------------------------------
   SUBROUTINE DiffuseConvectiveGenCompose( MassMatrix,StiffMatrix,ForceVector, &
       LoadVector,NodalCT,NodalC0,NodalC1,NodalC2,Temperature, &
         Ux,Uy,Uz,MUx,MUy, MUz,SoretD, Compressible,AbsoluteMass, &
             Stabilize,Element,n,Nodes )
!------------------------------------------------------------------------------
!******************************************************************************
!
!  Return element local matrices and RSH vector for diffusion-convection
!  equation (genaral euclidian coordinate system): 
!
!  ARGUMENTS:
!
!  REAL(KIND=dp) :: MassMatrix(:,:)
!     OUTPUT: time derivative coefficient matrix
!
!  REAL(KIND=dp) :: StiffMatrix(:,:)
!     OUTPUT: rest of the equation coefficients
!
!  REAL(KIND=dp) :: ForceVector(:)
!     OUTPUT: RHS vector
!
!  REAL(KIND=dp) :: LoadVector(:)
!     INPUT:
!
!  REAL(KIND=dp) :: NodalCT,NodalC0,NodalC1
!     INPUT: Coefficient of the time derivative term, 0 degree term, and the
!             convection term respectively
!
!  REAL(KIND=dp) :: NodalC2(:,:,:)
!     INPUT: Nodal values of the diffusion term coefficient tensor
!

!  REAL(KIND=dp) :: Temperature
!     INPUT: Temperature from previous iteration, needed if we model
!            phase change
!
!  REAL(KIND=dp) :: SoretD
!     INPUT: Soret Diffusivity D_t : j_t = D_t grad(T)
!

!  REAL(KIND=dp) :: Ux(:),Uy(:),Uz(:)
!     INPUT: Nodal values of velocity components from previous iteration
!          used only if coefficient of the convection term (C1) is nonzero
!
!  LOGICAL :: Stabilize
!     INPUT: Should stabilzation be used ? Used only if coefficient of the
!            convection term (C1) is nonzero
!
!  TYPE(Element_t) :: Element
!       INPUT: Structure describing the element (dimension,nof nodes,
!               interpolation degree, etc...)
!
!  TYPE(Nodes_t) :: Nodes
!       INPUT: Element node coordinates
!
!******************************************************************************

     REAL(KIND=dp), DIMENSION(:) :: ForceVector,Ux,Uy,Uz,MUx,MUy,MUz,LoadVector
     REAL(KIND=dp), DIMENSION(:,:) :: MassMatrix,StiffMatrix
     REAL(KIND=dp) :: NodalC0(:),NodalC1(:),NodalCT(:),NodalC2(:,:,:)
     REAL(KIND=dp) :: Temperature(:), SoretD(:), dT

     LOGICAL :: Stabilize,Compressible,AbsoluteMass

     INTEGER :: n

     TYPE(Nodes_t) :: Nodes
     TYPE(Element_t), POINTER :: Element

!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------
!
     REAL(KIND=dp) :: ddBasisddx(n,3,3)
     REAL(KIND=dp) :: Basis(2*n)
     REAL(KIND=dp) :: dBasisdx(2*n,3),SqrtElementMetric

     REAL(KIND=dp) :: Velo(3),Force

     REAL(KIND=dp) :: A,M
     REAL(KIND=dp) :: Load

     REAL(KIND=dp) :: VNorm,hK,mK
     REAL(KIND=dp) :: Lambda=1.0,Pe,Pe1,Pe2,C00,Tau,Delta,x,y,z

     REAL(KIND=dp) :: SorD, GradTemp(3), SoretForce

     INTEGER :: i,j,k,c,p,q,t,dim,N_Integ,NBasis

     REAL(KIND=dp) :: s,u,v,w,DivVelo,dVelodx(3,3)

     REAL(KIND=dp) :: SqrtMetric,Metric(3,3),Symb(3,3,3),dSymb(3,3,3,3)

     REAL(KIND=dp), DIMENSION(:), POINTER :: U_Integ,V_Integ,W_Integ,S_Integ

     REAL(KIND=dp) :: C0,CT,C1,C2(3,3),dC2dx(3,3,3),SU(n),SW(n)
     REAL(KIND=dp) :: NodalCThermal(n), CThermal

     LOGICAL :: stat,CylindricSymmetry,Convection,ConvectAndStabilize,Bubbles
     LOGICAL :: ThermalDiffusion

     TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff

!------------------------------------------------------------------------------

     CylindricSymmetry = (CurrentCoordinateSystem() == CylindricSymmetric .OR. &
                  CurrentCoordinateSystem() == AxisSymmetric)

     IF ( CylindricSymmetry ) THEN
       dim = 3
     ELSE
       dim = CoordinateSystemDimension()
     END IF
     n = element % TYPE % NumberOfNodes

     ForceVector = 0.0D0
     StiffMatrix = 0.0D0
     MassMatrix  = 0.0D0
     Load = 0.0D0

     Convection =  ANY( NodalC1 /= 0.0d0 )
     NBasis = n
     Bubbles = .FALSE.
     IF ( Convection .AND. .NOT. Stabilize ) THEN
        NBasis = 2*n
        Bubbles = .TRUE.
     END IF
     
     ThermalDiffusion = .FALSE.
     IF ( ANY( ABS( SoretD(1:n) ) > AEPS ) ) THEN
        ThermalDiffusion = .TRUE. 
        NodalCThermal = NodalC0(1:n)
     END IF
     NodalC0 = 0.0d0   ! this is the way it works, maybe could do better some time

!------------------------------------------------------------------------------
!    Integration stuff
!------------------------------------------------------------------------------
     IF ( Bubbles ) THEN
        IntegStuff = GaussPoints( element, Element % TYPE % GaussPoints2 )
     ELSE
        IntegStuff = GaussPoints( element )
     END IF
     U_Integ => IntegStuff % u
     V_Integ => IntegStuff % v
     W_Integ => IntegStuff % w
     S_Integ => IntegStuff % s
     N_Integ =  IntegStuff % n
 
!------------------------------------------------------------------------------
!    Stabilization parameters: hK, mK (take a look at Franca et.al.)
!    If there is no convection term we dont need stabilization.
!------------------------------------------------------------------------------
     ConvectAndStabilize = .FALSE.
     IF ( Stabilize .AND. ANY(NodalC1 /= 0.0D0) ) THEN
       ConvectAndStabilize = .TRUE.
       hK = element % hK
       mK = element % StabilizationMK
     END IF

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
             Basis,dBasisdx,ddBasisddx,ConvectAndStabilize,Bubbles )

!------------------------------------------------------------------------------
!      Coordinatesystem dependent info
!------------------------------------------------------------------------------
       IF ( CurrentCoordinateSystem() /= Cartesian ) THEN
         x = SUM( nodes % x(1:n)*Basis(1:n) )
         y = SUM( nodes % y(1:n)*Basis(1:n) )
         z = SUM( nodes % z(1:n)*Basis(1:n) )
       END IF

       CALL CoordinateSystemInfo( Metric,SqrtMetric,Symb,dSymb,x,y,z )

       s = SqrtMetric * SqrtElementMetric * S_Integ(t)
!------------------------------------------------------------------------------
!      Coefficient of the convection and time derivative terms at the
!      integration point
!------------------------------------------------------------------------------
       C0 = SUM( NodalC0(1:n)*Basis(1:n) )
       CT = SUM( NodalCT(1:n)*Basis(1:n) )
       C1 = SUM( NodalC1(1:n)*Basis(1:n) )
!------------------------------------------------------------------------------
!     Compute effective heatcapacity, if modelling phase change,
!     at the integration point.
!     NOTE: This is for heat equation only, not generally for diff.conv. equ.
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
!      Coefficient of the diffusion term & its derivatives at the
!      integration point
!------------------------------------------------------------------------------
       DO i=1,dim
         DO j=1,dim
           C2(i,j) = SQRT(Metric(i,i)) * SQRT(Metric(j,j)) * &
                SUM( NodalC2(i,j,1:n) * Basis(1:n) )
         END DO
       END DO
 
!------------------------------------------------------------------------------
!      If there's no convection term we don't need the velocities, and
!      also no need for stabilization
!------------------------------------------------------------------------------
       Convection = .FALSE.
       IF ( C1 /= 0.0D0 ) THEN
         Convection = .TRUE.
!------------------------------------------------------------------------------
!        Velocity and pressure (deviation) from previous iteration
!        at the integration point
!------------------------------------------------------------------------------
         Velo = 0.0D0
         Velo(1) = SUM( (Ux(1:n)-MUx(1:n))*Basis(1:n) )
         Velo(2) = SUM( (Uy(1:n)-MUy(1:n))*Basis(1:n) )
         IF ( dim > 2 .AND. CurrentCoordinateSystem() /= AxisSymmetric ) THEN
           Velo(3) = SUM( (Uz(1:n)-MUz(1:n))*Basis(1:n) )
         END IF

         IF ( Compressible .AND. AbsoluteMass ) THEN

           dVelodx = 0.0D0
           DO i=1,3
             dVelodx(1,i) = SUM( Ux(1:n)*dBasisdx(1:n,i) )
             dVelodx(2,i) = SUM( Uy(1:n)*dBasisdx(1:n,i) )
             IF ( dim > 2 .AND. CurrentCoordinateSystem() /= AxisSymmetric ) &
               dVelodx(3,i) = SUM( Uz(1:n)*dBasisdx(1:n,i) )
           END DO
  
           DivVelo = 0.0D0
           DO i=1,dim
             DivVelo = DivVelo + dVelodx(i,i)
           END DO
           IF ( CurrentCoordinateSystem() >= Cylindric .AND. &
                CurrentCoordinateSystem() <= AxisSymmetric ) THEN
! Cylindrical coordinates
             DivVelo = DivVelo + Velo(1)/x
           ELSE
! General coordinate system
             DO i=1,dim
               DO j=i,dim
                 DivVelo = DivVelo + Velo(j)*Symb(i,j,i)
               END DO
             END DO
           END IF
           C0 = DivVelo
         END IF

!------------------------------------------------------------------------------
!          Stabilization parameters...
!------------------------------------------------------------------------------
         IF ( Stabilize ) THEN
!          VNorm = SQRT( SUM(Velo(1:dim)**2) )
 
           Vnorm = 0.0D0
           DO i=1,dim
              Vnorm = Vnorm + Velo(i)*Velo(i) / Metric(i,i)
           END DO
           Vnorm = SQRT( Vnorm )
 
!#if 1
           Pe = MIN(1.0D0,mK*hK*C1*VNorm/(2*ABS(C2(1,1))))

           Tau = 0.0D0
           IF ( VNorm /= 0.0D0 ) THEN
             Tau = hK * Pe / (2 * C1 * VNorm)
           END IF
!#else
!            C00 = C0
!            IF ( dT > 0 ) C00 = C0 + CT
!
!            Pe1 = 0.0d0
!            IF ( C00 > 0 ) THEN
!              Pe1 = 2 * ABS(C2(1,1)) / ( mK * C00 * hK**2 )
!              Pe1 = C00 * hK**2 * MAX( 1.0d0, Pe1 )
!            ELSE
!              Pe1 = 2 * ABS(C2(1,1)) / mK
!            END IF
!
!            Pe2 = 0.0d0
!            IF ( C2(1,1) /= 0.0d0 ) THEN
!              Pe2 = ( mK * C1 * VNorm * hK ) / ABS(C2(1,1))
!              Pe2 = 2*ABS(C2(1,1)) * MAX( 1.0d0, Pe2 ) / mK
!            ELSE
!              Pe2 = 2 * hK * C1 * VNorm
!            END IF
!
!            Tau = hk**2 / ( Pe1 + Pe2 )
!#endif

!------------------------------------------------------------------------------
           DO i=1,dim
             DO j=1,dim
               DO k=1,3
                 dC2dx(i,j,k) = SQRT(Metric(i,i))*SQRT(Metric(j,j))* &
                      SUM(NodalC2(i,j,1:n)*dBasisdx(1:n,k))
               END DO
             END DO
           END DO
!------------------------------------------------------------------------------
!          Compute residual & stabilization weight vectors
!------------------------------------------------------------------------------
           DO p=1,n
             SU(p) = C0 * Basis(p)
             DO i = 1,dim
               SU(p) = SU(p) + C1 * dBasisdx(p,i) * Velo(i)
               IF ( Element % TYPE % BasisFunctionDegree <= 1 ) CYCLE

               DO j=1,dim
                 SU(p) = SU(p) - C2(i,j) * ddBasisddx(p,i,j)
                 SU(p) = SU(p) - dC2dx(i,j,j) * dBasisdx(p,i)
                 DO k=1,dim
                   SU(p) = SU(p) + C2(i,j) * Symb(i,j,k) * dBasisdx(p,k)
                   SU(p) = SU(p) - C2(i,k) * Symb(k,j,j) * dBasisdx(p,i)
                   SU(p) = SU(p) - C2(k,j) * Symb(k,j,i) * dBasisdx(p,i)
                 END DO
               END DO
             END DO

             SW(p) = C0 * Basis(p)

             DO i = 1,dim
               SW(p) = SW(p) + C1 * dBasisdx(p,i) * Velo(i)
               IF ( Element % TYPE % BasisFunctionDegree <= 1 ) CYCLE

               DO j=1,dim
                 SW(p) = SW(p) - C2(i,j) * ddBasisddx(p,i,j)
                 SW(p) = SW(p) - dC2dx(i,j,j) * dBasisdx(p,i)
                 DO k=1,dim
                   SW(p) = SW(p) + C2(i,j) * Symb(i,j,k) * dBasisdx(p,k)
                   SW(p) = SW(p) - C2(i,k) * Symb(k,j,j) * dBasisdx(p,i)
                   SW(p) = SW(p) - C2(k,j) * Symb(k,j,i) * dBasisdx(p,i)
                 END DO
               END DO
             END DO
           END DO
         END IF
       END IF
!------------------------------------------------------------------------------
!      Loop over basis functions of both unknowns and weights
!------------------------------------------------------------------------------
       DO p=1,NBasis
       DO q=1,NBasis
!------------------------------------------------------------------------------
!        The diffusive-convective equation without stabilization
!------------------------------------------------------------------------------
         M = CT * Basis(q) * Basis(p)
         A = C0 * Basis(q) * Basis(p)
         DO i=1,dim
           DO j=1,dim
             A = A + C2(i,j) * dBasisdx(q,i) * dBasisdx(p,j)
           END DO
         END DO

         IF ( Convection ) THEN
           DO i=1,dim
             A = A + C1 * Velo(i) * dBasisdx(q,i) * Basis(p)
           END DO

!------------------------------------------------------------------------------
!        Next we add the stabilization...
!------------------------------------------------------------------------------
           IF ( Stabilize ) THEN
             A = A + Tau * SU(q) * SW(p)
             M = M + Tau * CT * Basis(q) * SW(p)
           END IF
         END IF

         StiffMatrix(p,q) = StiffMatrix(p,q) + s * A
         MassMatrix(p,q)  = MassMatrix(p,q)  + s * M
       END DO
       END DO

!------------------------------------------------------------------------------
!      Force at the integration point
!------------------------------------------------------------------------------
       Force = SUM( LoadVector(1:n)*Basis(1:n) )

!------------------------------------------------------------------------------
!      The righthand side...
!------------------------------------------------------------------------------
       DO p=1,NBasis
         Load = Basis(p)

         IF ( ConvectAndStabilize ) THEN
           Load = Load + Tau * SW(p)
         END IF

         ForceVector(p) = ForceVector(p) + s * Load * Force
       END DO

!------------------------------------------------------------------------------
!     Add Soret diffusivity if necessary
!     -div( rho D_t grad(T)) 
!------------------------------------------------------------------------------

        IF ( ThermalDiffusion ) THEN

           CThermal = SUM( NodalCThermal(1:n) * Basis(1:n) )

           GradTemp = 0.0d0
           IF ( CurrentCoordinateSystem() >= Cylindric .AND. &
               CurrentCoordinateSystem() <= AxisSymmetric ) THEN

             DO i = 1, dim
               GradTemp(i) = SUM( dBasisdx(1:n,i) * Temperature(1:n) )
             END DO
           ELSE
             CALL Error( 'AdvectionDiffusion', &
                 'Thermal diffusion not implemented for this coordinate system. Ignoring it.' )
           END IF

           SorD = SUM( Basis(1:n) * SoretD(1:n) )

           DO p=1,NBasis
              IF ( ConvectAndStabilize ) THEN 
                 Load = Tau * SW(p)
              ELSE
                 Load = 1.0d0
              END IF

              SoretForce = CThermal * SorD * SUM( GradTemp(1:dim) * dBasisdx(p,1:dim) )
              ForceVector(p) = ForceVector(p) - s * SoretForce * Load
           END DO
            
        END IF

     END DO
!------------------------------------------------------------------------------
   END SUBROUTINE DiffuseConvectiveGenCompose
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
   SUBROUTINE DiffuseConvectiveGenBBoundary( BoundaryMatrix, Parent, &
               pn, ParentNodes, Ratio, Element, n, Nodes )
!------------------------------------------------------------------------------
!******************************************************************************
!
!  Return element local matrices for a discontinuous flux boundary conditions
!  of diffusion equation in general coordinate system: 
!
!  ARGUMENTS:
!
!  REAL(KIND=dp) :: BoundaryMatrix(:,:)
!      OUTPUT: coefficient matrix if equations
!
!  TYPE(Element_t) :: Parent
!       INPUT: Structure describing the boundary elements parent
!
!  INTEGER :: pn
!       INPUT: Number of parent element nodes
!
!  TYPE(Nodes_t) :: ParentNodes
!       INPUT: Parent element node coordinates
!
!  REAL(KIND=dp) :: Ratio
!       INPUT: The ratio of maximal solubilities - 1 (defining the 
!             measure of discontinuity)
!
!  TYPE(Element_t) :: Element
!       INPUT: Structure describing the element (dimension,nof nodes,
!               interpolation degree, etc...)
!
!  INTEGER :: n
!       INPUT: Number  of element nodes
!
!  TYPE(Nodes_t) :: Nodes
!       INPUT: Element node coordinates
!
!******************************************************************************

     TYPE(Nodes_t)   :: Nodes, ParentNodes
     TYPE(Element_t), POINTER :: Element, Parent
     REAL(KIND=dp) :: BoundaryMatrix(:,:), Ratio
     INTEGER :: n, pn

     REAL(KIND=dp) :: ddBasisddx(n,3,3), ParentdBasisdx(pn,3)
     REAL(KIND=dp) :: Basis(n), ParentBasis(pn)
     REAL(KIND=dp) :: dBasisdx(n,3), SqrtElementMetric

     REAL(KIND=dp) :: Diff(3,3)
     REAL(KIND=dp) :: xpos, ypos, zpos
     REAL(KIND=dp) :: u, v, w, s, x(n), y(n), z(n), Normal(3), FluxVector(3)
     REAL(KIND=dp), POINTER :: U_Integ(:), V_Integ(:), W_Integ(:), S_Integ(:)

     INTEGER :: ParentNodeIndexes(n)
     INTEGER :: i, t, q, p, N_Integ, j

     TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff

     LOGICAL :: stat
!------------------------------------------------------------------------------

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
         xpos = SUM( Nodes % x(1:n)*Basis )
         ypos = SUM( Nodes % y(1:n)*Basis )
         zpos = SUM( Nodes % z(1:n)*Basis )
         s = s * CoordinateSqrtMetric( xpos,ypos,zpos )
       END IF

       Normal = Normalvector( Element, Nodes, u, v, .TRUE. )
!------------------------------------------------------------------------------
!      Need parent element basis functions for calculating normal derivatives
!------------------------------------------------------------------------------
       DO i = 1,n
         DO j = 1,pn
           IF ( Element % NodeIndexes(i) == Parent % NodeIndexes(j) ) THEN
             x(i) = Parent % TYPE % NodeU(j)
             y(i) = Parent % TYPE % NodeV(j)
             z(i) = Parent % TYPE % NodeW(j)
             ParentNodeIndexes(i) = j
             EXIT
           END IF
         END DO
       END DO

       u = SUM( Basis(1:n) * x(1:n) )
       v = SUM( Basis(1:n) * y(1:n) )
       w = SUM( Basis(1:n) * z(1:n) )

       stat = ElementInfo( Parent, ParentNodes,u, v, w, SqrtElementMetric, &
           ParentBasis, ParentdBasisdx, ddBasisddx, .FALSE. )

       FluxVector = 0.0d0
       DO i = 1, 3
         DO j = 1, 3
           Diff(i,j) = SUM( Diffusivity(i,j,1:n) * Basis(1:n) )
         END DO
       END DO

       DO q = 1, pn
         DO j = 1, 3
           FluxVector(j) = SUM( Diff(j,1:3) * ParentdBasisdx(q,1:3) )
         END DO
         DO i = 1, n
           p = ParentNodeIndexes(i)
           BoundaryMatrix(p,q) = BoundaryMatrix(p,q) + Ratio * &
               s * Basis(i) * SUM( FluxVector(1:3) * Normal(1:3) )
         END DO
       END DO

     END DO
     
   END SUBROUTINE DiffuseConvectiveGenBBoundary
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
   SUBROUTINE DiffuseConvectiveGenBoundary( BoundaryMatrix,BoundaryVector, &
              LoadVector,NodalAlpha,Element,n,Nodes)
!------------------------------------------------------------------------------
!******************************************************************************
!
!  Return element local matrices and RSH vector for boundary conditions
!  of diffusion convection equation: 
!
!  ARGUMENTS:
!
!  REAL(KIND=dp) :: BoundaryMatrix(:,:)
!     OUTPUT: coefficient matrix if equations
!
!  REAL(KIND=dp) :: BoundaryVector(:)
!     OUTPUT: RHS vector
!
!  REAL(KIND=dp) :: LoadVector(:)
!     INPUT: coefficient of the force term
!
!  REAL(KIND=dp) :: NodalAlpha
!     INPUT: coefficient for temperature dependent term
!
!  TYPE(Element_t) :: Element
!       INPUT: Structure describing the element (dimension,nof nodes,
!               interpolation degree, etc...)
!
!  INTEGER :: n
!       INPUT: Number of element nodes
!
!  TYPE(Nodes_t) :: Nodes
!       INPUT: Element node coordinates
!
!******************************************************************************

!------------------------------------------------------------------------------

     REAL(KIND=dp) :: BoundaryMatrix(:,:),BoundaryVector(:)
     REAL(KIND=dp) :: LoadVector(:),NodalAlpha(:)
     TYPE(Nodes_t)    :: Nodes
     TYPE(Element_t),POINTER  :: Element

     INTEGER :: n
!------------------------------------------------------------------------------

     REAL(KIND=dp) :: ddBasisddx(n,3,3)
     REAL(KIND=dp) :: Basis(n)
     REAL(KIND=dp) :: dBasisdx(n,3),SqrtElementMetric

     REAL(KIND=dp) :: u,v,w,s,x,y,z
     REAL(KIND=dp) :: Force,Alpha
     REAL(KIND=dp), POINTER :: U_Integ(:),V_Integ(:),W_Integ(:),S_Integ(:)

     REAL(KIND=dp) :: SqrtMetric,Metric(3,3),Symb(3,3,3),dSymb(3,3,3,3)

     INTEGER :: i,t,q,p,N_Integ

     LOGICAL :: stat,CylindricSymmetry

     TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff
!------------------------------------------------------------------------------

     BoundaryVector = 0.0D0
     BoundaryMatrix = 0.0D0
 
!------------------------------------------------------------------------------
!    Integration stuff
!------------------------------------------------------------------------------
     IntegStuff = GaussPoints( element )
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
!      Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
       stat = ElementInfo( Element,Nodes,u,v,w,SqrtElementMetric, &
                  Basis,dBasisdx,ddBasisddx,.FALSE. )

       s =  S_Integ(t) * SqrtElementMetric
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
!      Basis function values at the integration point
!------------------------------------------------------------------------------
       Alpha = SUM( NodalAlpha(1:n)*Basis )
       Force = SUM( LoadVector(1:n)*Basis )

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
  END SUBROUTINE DiffuseConvectiveGenBoundary
!------------------------------------------------------------------------------

END SUBROUTINE AdvectionDiffusionSolver
!------------------------------------------------------------------------------
