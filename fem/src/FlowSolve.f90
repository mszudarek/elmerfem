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
! *****************************************************************************/
!
!/******************************************************************************
! *
! *   Module containing a solver for navier-stokes equations
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
! * $Log: FlowSolve.f90,v $
! * Revision 1.108  2005/04/04 06:18:28  jpr
! * *** empty log message ***
! *
! * Revision 1.107  2004/09/27 09:32:23  jpr
! * Removed some old, inactive code.
! *
! * Revision 1.106  2004/09/24 12:15:32  jpr
! * Some corrections to the previous edits.
! *
! * Revision 1.105  2004/09/24 09:55:52  jpr
! * More formatting.
! *
! * Revision 1.104  2004/09/24 06:25:03  jpr
! * Just formatting.
! *
! * Revision 1.103  2004/09/24 05:55:47  jpr
! * Modified the 'user defined' compressibility model introduced yesterday.
! * Added compressibility model 'thermal'.
! *
! * Revision 1.102  2004/09/23 12:31:07  jpr
! * Added 'user defined' compressibility model.
! *
! * Revision 1.99  2004/08/10 13:54:15  raback
! * Added external force of type f \grad g where f and g are given fields
! *
! * Revision 1.95  2004/06/03 15:59:00  raback
! * Added ortotropic porous media (i.e. Darcys law).
! *
! * Revision 1.89  2004/03/24 11:14:51  jpr
! * Added a flag to allow divergence form discretization of the diffusion term.
! *
! * Revision 1.88  2004/03/04 11:00:59  jpr
! * Modified pressure relaxation correction to apply only in the
! * incompressible case.
! *
! * Revision 1.87  2004/03/03 09:12:00  jpr
! * Added 3rd argument to GetLocical(...) to stop the complaint about
! * missing "Output Version Numbers" keyword.
! *
! * Revision 1.85  2004/03/01 14:59:55  jpr
! * Modified residual function interfaces for goal oriented adaptivity,
! * no functionality yet.
! * Started log.
! *
! *****************************************************************************/



!------------------------------------------------------------------------------
   SUBROUTINE FlowSolver( Model,Solver,dt,TransientSimulation)
DLLEXPORT FlowSolver
!------------------------------------------------------------------------------
!******************************************************************************
!
!  Solve Navier-Stokes equations for one timestep
!
!  ARGUMENTS:
!
!  TYPE(Model_t) :: Model,  
!     INPUT: All model information (mesh,materials,BCs,etc...)
!
!  TYPE(Solver_t) :: Solver
!     INPUT: Linear equation solver options
!
!  REAL(KIND=dp) :: dt,
!     INPUT: Timestep size for time dependent simulations
!
!******************************************************************************

    USE NavierStokes
    USE NavierStokesGeneral
    USE NavierStokesCylindrical

    USE Adaptive
    USE FreeSurface
    USE DefUtils

!------------------------------------------------------------------------------
    IMPLICIT NONE

     TYPE(Model_t) :: Model
     TYPE(Solver_t), TARGET :: Solver

     REAL(KIND=dp) :: dt
     LOGICAL :: TransientSimulation
!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------
     TYPE(Matrix_t),POINTER :: StiffMatrix

     TYPE(Solver_t), POINTER :: PSolver

     INTEGER :: i,j,k,l,n,nb,pn,t,iter,LocalNodes,k1,k2,istat

     TYPE(ValueList_t),POINTER :: Material, Equation
     TYPE(Nodes_t) :: ElementNodes,ParentNodes
     TYPE(Element_t),POINTER :: CurrentElement,Parent,Elm

     REAL(KIND=dp) :: RelativeChange,UNorm,PrevUNorm,Gravity(3), &
       Tdiff,Normal(3),s,r,Relaxation,NewtonTol,NonlinearTol, &
       ReferencePressure=0.0, SpecificHeatRatio, &
       PseudoCompressibilityScale=1.0, NonlinearRelax

     REAL(KIND=dp) :: Jx,Jy,Jz,Lx,Ly,Lz,Clip

     INTEGER :: NSDOFs,NewtonIter,NonlinearIter

     TYPE(Variable_t), POINTER :: FlowSol, TempSol, MagneticSol,CurrentSol
     TYPE(Variable_t), POINTER :: KinEnergySol,KinDissipationSol,MeshSol
     TYPE(Variable_t), POINTER :: SurfSol, FlowStress, DensitySol

     INTEGER, POINTER :: FlowPerm(:),TempPerm(:), MagneticPerm(:), KinPerm(:),MeshPerm(:),SurfPerm(:)
     REAL(KIND=dp), POINTER :: FlowSolution(:), Temperature(:), &
       MagneticField(:), ElectricCurrent(:), gWork(:,:), &
         ForceVector(:), KinEnergy(:), KinDissipation(:), LayerThickness(:), &
           SurfaceRoughness(:),MeshVelocity(:), StressValues(:), FlowStressComp(:)

     REAL(KIND=dp), POINTER :: TempPrev(:)
     REAL(KIND=DP), POINTER :: Pwrk(:,:,:)

     LOGICAL :: Stabilize,NewtonLinearization = .FALSE., GotForceBC, GotIt, &
                  OutFlowBoundary, MBFlag, Convect  = .TRUE., NormalTangential, &
                  divDiscretization, GradPDiscretization, ComputeStress
! Which compressibility model is used
     CHARACTER(LEN=MAX_NAME_LEN) :: CompressibilityFlag
     INTEGER :: CompressibilityModel
     INTEGER, POINTER :: NodeIndexes(:)
     INTEGER :: body_id,bf_id,eq_id,DIM
!
     LOGICAL :: AllocationsDone = .FALSE., FreeSurfaceFlag, &
         PseudoPressureExists, PseudoCompressible, Bubbles, &
         Porous =.FALSE., PotentialForce=.FALSE.

     REAL(KIND=dp),ALLOCATABLE:: LocalMassMatrix(:,:),LocalStiffMatrix(:,:),&
         LoadVector(:,:),Viscosity(:),LocalForce(:), TimeForce(:), &
         PrevDensity(:),Density(:),U(:),V(:),W(:),MU(:),MV(:),MW(:), &
         Pressure(:),Alpha(:),Beta(:),ExtPressure(:),PrevPressure(:), &
         HeatExpansionCoeff(:), ReferenceTemperature(:), &
         Permeability(:),Mx(:),My(:),Mz(:), &
         KECmu(:), LocalTemperature(:), GasConstant(:), HeatCapacity(:), &
         LocalTempPrev(:),SlipCoeff(:,:), PseudoCompressibility(:), &
         PseudoPressure(:), PSolution(:), Drag(:,:), PotentialField(:), &
         PotentialCoefficient(:)

     SAVE U,V,W,LocalMassMatrix,LocalStiffMatrix,LoadVector,Viscosity, &
         TimeForce,LocalForce,ElementNodes,Alpha,Beta,ExtPressure,Pressure,PrevPressure, &
         PrevDensity,Density, AllocationsDone,LocalNodes, &
         HeatExpansionCoeff,ReferenceTemperature, &
         Permeability,Mx,My,Mz,LayerThickness, SlipCoeff, &
         KECmu, SurfaceRoughness, LocalTemperature, GasConstant, &
         HeatCapacity, LocalTempPrev,MU,MV,MW, ParentNodes, &
         PseudoCompressibilityScale, PseudoCompressibility, &
         PseudoPressure, PseudoPressureExists, PSolution, Drag, &
         PotentialField, PotentialCoefficient

      REAL(KIND=dp) :: at,at0,totat,st,totst,t1,CPUTime,RealTime
!------------------------------------------------------------------------------
     INTEGER :: NumberOfBoundaryNodes = 0
     INTEGER, POINTER :: BoundaryReorder(:)

     REAL(KIND=dp) :: Bu,Bv,Bw,RM(3,3)
     
     REAL(KIND=dp), POINTER :: BoundaryNormals(:,:), &
         BoundaryTangent1(:,:), BoundaryTangent2(:,:)

     SAVE NumberOfBoundaryNodes,BoundaryReorder,BoundaryNormals, &
                BoundaryTangent1, BoundaryTangent2

     INTERFACE
        FUNCTION FlowBoundaryResidual( Model,Edge,Mesh,Quant,Perm,Gnorm ) RESULT(Indicator)
          USE Types
          TYPE(Element_t), POINTER :: Edge
          TYPE(Model_t) :: Model
          TYPE(Mesh_t), POINTER :: Mesh
          REAL(KIND=dp) :: Quant(:), Indicator(2), Gnorm
          INTEGER :: Perm(:)
        END FUNCTION FlowBoundaryResidual

        FUNCTION FlowEdgeResidual( Model,Edge,Mesh,Quant,Perm ) RESULT(Indicator)
          USE Types
          TYPE(Element_t), POINTER :: Edge
          TYPE(Model_t) :: Model
          TYPE(Mesh_t), POINTER :: Mesh
          REAL(KIND=dp) :: Quant(:), Indicator(2)
          INTEGER :: Perm(:)
        END FUNCTION FlowEdgeResidual

        FUNCTION FlowInsideResidual( Model,Element,Mesh,Quant,Perm,Fnorm ) RESULT(Indicator)
          USE Types
          TYPE(Element_t), POINTER :: Element
          TYPE(Model_t) :: Model
          TYPE(Mesh_t), POINTER :: Mesh
          REAL(KIND=dp) :: Quant(:), Indicator(2), Fnorm
          INTEGER :: Perm(:)
        END FUNCTION FlowInsideResidual
     END INTERFACE
!------------------------------------------------------------------------------
     CHARACTER(LEN=MAX_NAME_LEN) :: VersionID = "$Id: FlowSolve.f90,v 1.108 2005/04/04 06:18:28 jpr Exp $"

!------------------------------------------------------------------------------
!    Check if version number output is requested
!------------------------------------------------------------------------------
     IF ( .NOT. AllocationsDone ) THEN
        IF ( ListGetLogical( GetSimulation(), 'Output Version Numbers', GotIt ) ) THEN
           CALL Info( 'FlowSolve', 'FlowSolver version:', Level = 0 ) 
           CALL Info( 'FlowSolve', VersionID, Level = 0 ) 
           CALL Info( 'FlowSolve', ' ', Level = 0 ) 
        END IF
     END IF

!------------------------------------------------------------------------------
!    Get variables needed for solving the system
!------------------------------------------------------------------------------

     IF ( .NOT. ASSOCIATED( Solver % Matrix ) ) RETURN
     DIM = CoordinateSystemDimension()

     FlowSol => Solver % Variable
     NSDOFs         =  FlowSol % DOFs
     FlowPerm       => FlowSol % Perm
     FlowSolution   => FlowSol % Values

     LocalNodes = COUNT( FlowPerm > 0 )
     IF ( LocalNodes <= 0 ) RETURN

     TempSol => VariableGet( Solver % Mesh % Variables, 'Temperature' )
     IF ( ASSOCIATED( TempSol ) ) THEN
       TempPerm     => TempSol % Perm
       Temperature  => TempSol % Values
       IF( TransientSimulation ) THEN
         IF ( ASSOCIATED(TempSol % PrevValues) ) TempPrev => TempSol % PrevValues(:,1)
       END IF
     END IF

     KinEnergySol => VariableGet( Solver % Mesh % Variables, 'Kinetic Energy' )
     IF ( ASSOCIATED( KinEnergySol ) ) THEN
       KinPerm   => KinEnergySol % Perm
       KinEnergy => KinEnergySol % Values
     END IF

     KinDissipationSol => VariableGet( Solver % Mesh % Variables, 'Kinetic Dissipation')
     IF ( ASSOCIATED( KinDissipationSol ) ) THEN
       KinDissipation => KinDissipationSol % Values
     END IF

     MeshSol => VariableGet( Solver % Mesh % Variables, 'Mesh Velocity')
     NULLIFY( MeshVelocity )
     IF ( ASSOCIATED( MeshSol ) ) THEN
       MeshPerm     => MeshSol % Perm
       MeshVelocity => MeshSol % Values
     END IF

     DensitySol => VariableGet( Solver % Mesh % Variables, 'Density' )

!------------------------------------------------------------------------------

     StiffMatrix => Solver % Matrix
     ForceVector => StiffMatrix % RHS
     UNorm = Solver % Variable % Norm

!------------------------------------------------------------------------------
!     Allocate some permanent storage, this is done first time only
!------------------------------------------------------------------------------

     IF ( .NOT.AllocationsDone .OR. Solver % Mesh % Changed ) THEN

       N = Solver % Mesh % MaxElementDOFs
       
       IF( AllocationsDone ) THEN
          DEALLOCATE( ElementNodes % x,             &
               ElementNodes % y,                    &
               ElementNodes % z,                    &
               ParentNodes % x,                     &
               ParentNodes % y,                     &
               ParentNodes % z,                     &
               U,  V,  W,                           &
               MU, MV, MW,                          &
               Pressure,                            &
               PrevPressure,                        &
               PseudoCompressibility,               &
               PrevDensity,Density,KECmu,           &
               LayerThickness,                      &
               SurfaceRoughness,                    &
               Permeability,                        &
               Mx,My,Mz,                            &
               SlipCoeff, Drag,                     &
               TimeForce,LocalForce, Viscosity,     &
               LocalMassMatrix,                     &
               LocalStiffMatrix,                    &
               HeatExpansionCoeff,                  &
               GasConstant, HeatCapacity,           &
               ReferenceTemperature,                & 
               LocalTempPrev, LocalTemperature,     &
               PotentialField, PotentialCoefficient, &
               PSolution, LoadVector, Alpha, Beta, &
               ExtPressure, STAT=istat )
       END IF

       ALLOCATE( ElementNodes % x( N ),                  &
                 ElementNodes % y( N ),                  &
                 ElementNodes % z( N ),                  &
                 ParentNodes % x( N ),                   &
                 ParentNodes % y( N ),                   &
                 ParentNodes % z( N ),                   &
                 U(N),  V(N),  W(N),                     &
                 MU(N), MV(N), MW(N),                    &
                 Pressure( N ),                          &
                 PrevPressure( N ),                      &
                 PseudoCompressibility( N ),             &
                 PrevDensity(N),Density( N ),KECmu( N ), &
                 LayerThickness(N),                      &
                 SurfaceRoughness(N),                    &
                 Permeability(N),                        &
                 Mx(N),My(N),Mz(N),                      &
                 SlipCoeff(3,N), Drag(3,N),              &
                 TimeForce( 2*NSDOFs*N ),                &
                 LocalForce( 2*NSDOFs*N ), Viscosity( N ), &
                 LocalMassMatrix(  2*NSDOFs*N,2*NSDOFs*N ),&
                 LocalStiffMatrix( 2*NSDOFs*N,2*NSDOFs*N ),&
                 HeatExpansionCoeff(N),                  &
                 GasConstant( N ), HeatCapacity( N ),    &
                 ReferenceTemperature(N),                & 
                 LocalTempPrev(N), LocalTemperature(N),  &
                 PSolution( SIZE( FlowSolution ) ),      &
                 PotentialField( N ), PotentialCoefficient( N ), &
                 LoadVector( 4,N ), Alpha( N ), Beta( N ), &
                 ExtPressure( N ), STAT=istat )

       Drag = 0.0d0
       NULLIFY(Pwrk) 

       PseudoPressureExists = .FALSE.
       DO k=1,Model % NumberOfMaterials
         Material => Model % Materials(k) % Values
         CompressibilityFlag = ListGetString( Material, &
             'Compressibility Model', GotIt)
         IF (gotIt .AND. CompressibilityFlag == 'artificial compressible') THEN
            PseudoPressureExists = .TRUE.
         END IF
       END DO

       IF ( PseudoPressureExists ) THEN
          IF ( AllocationsDone ) THEN
             DEALLOCATE( PseudoPressure )
          END IF
          n = SIZE( FlowSolution ) / NSDOFs
          ALLOCATE( PseudoPressure(n),STAT=istat ) 
       END IF

       IF ( istat /= 0 ) THEN
         CALL Fatal( 'FlowSolve','Memory allocation error, Aborting.' )
       END IF

!------------------------------------------------------------------------------
!    Check for normal/tangetial coordinate system defined velocities
!------------------------------------------------------------------------------
       CALL CheckNormalTangentialBoundary( Model, &
            'Normal-Tangential Velocity', NumberOfBoundaryNodes, &
         BoundaryReorder, BoundaryNormals, BoundaryTangent1, &
           BoundaryTangent2, DIM )
!------------------------------------------------------------------------------

       ComputeStress = GetLogical( Solver % Values, 'Compute Stress', GotIt )
       IF ( ComputeStress ) THEN
         PSolver => Solver
         ALLOCATE( StressValues( SIZE( FlowSolution ) )  )
         CALL VariableAdd(Solver % Mesh % Variables, Solver % Mesh, PSolver, &
                  'Flow Stress', DIM+1, StressValues, FlowPerm )

          DO i=1,DIM+1
             FlowStressComp => StressValues(i::DIM+1)
             CALL VariableAdd(Solver % Mesh % Variables,Solver % Mesh,PSolver, &
                'Flow Stress '//CHAR(i+ICHAR('0')), 1, FlowStressComp, FlowPerm )
          END DO
       END IF
       AllocationsDone = .TRUE.
     END IF
!------------------------------------------------------------------------------

     FlowStress => VariableGet( Solver % Mesh % Variables, 'Flow Stress' )

!------------------------------------------------------------------------------
!    Do some additional initialization, and go for it
!------------------------------------------------------------------------------

     gWork => ListGetConstRealArray( Model % Constants,'Gravity',GotIt)
     IF ( GotIt ) THEN
       Gravity = gWork(1:3,1)*gWork(4,1)
     ELSE
       Gravity    =  0.00D0
       Gravity(2) = -9.81D0
     END IF
!------------------------------------------------------------------------------


     Stabilize = ListGetLogical( Solver % Values,'Stabilize',GotIt )
     DivDiscretization = ListGetLogical( Solver % Values, &
              'Div Discretization', GotIt )

     GradPDiscretization = ListGetLogical( Solver % Values, &
              'Gradp Discretization', GotIt )

     NonlinearTol = ListGetConstReal( Solver % Values, &
        'Nonlinear System Convergence Tolerance',minv=0.0d0 )

     NewtonTol = ListGetConstReal( Solver % Values, &
        'Nonlinear System Newton After Tolerance', minv=0.0d0 )

     NewtonIter = ListGetInteger( Solver % Values, &
        'Nonlinear System Newton After Iterations', minv=0 )
     IF ( NewtonIter == 0 ) NewtonLinearization = .TRUE.

     NonlinearIter = ListGetInteger( Solver % Values, &
        'Nonlinear System Max Iterations', minv=0 )

!------------------------------------------------------------------------------
!    We do our own relaxation...
!------------------------------------------------------------------------------
     NonlinearRelax = ListGetConstReal( Solver % Values, &
        'Nonlinear System Relaxation Factor', GotIt )

     IF ( .NOT. GotIt ) NonlinearRelax = 1.0d0

     CALL ListAddConstReal( Solver % Values, 'Nonlinear System Relaxation Factor', 1.0d0 )
!------------------------------------------------------------------------------
!    Check if free surfaces present
!------------------------------------------------------------------------------
     FreeSurfaceFlag = .FALSE.
     DO i=1,Model % NumberOfBCs
       FreeSurfaceFlag = FreeSurfaceFlag .OR. ListGetLogical( &
          Model % BCs(i) % Values,'Free Surface', GotIt )
       IF ( FreeSurfaceFlag ) EXIT
     END DO

     CALL CheckCircleBoundary()
!------------------------------------------------------------------------------

     totat = 0.0d0
     totst = 0.0d0

     ! Initialize the pressure to be used in artificial compressibility 
     IF(PseudoPressureExists) THEN
       PseudoPressure = FlowSolution(NSDOFs:SIZE(FlowSolution):NSDOFs)

       WRITE(Message,'(A,T25,E15.4)') 'PseudoPressure mean: ',&
           SUM(PseudoPressure)/SIZE(PseudoPressure)
       CALL Info('FlowSolve',Message,Level=5)

       PseudoCompressibilityScale = ListGetConstReal( Model % Simulation, &
           'Artificial Compressibility Scaling',GotIt)
       IF(.NOT.GotIt) PseudoCompressibilityScale = 1.0
       IF(TransientSimulation) THEN
         PseudoCompressibilityScale = PseudoCompressibilityScale / dt
       END IF
     END IF

     DO iter=1,NonlinearIter

       at  = CPUTime()
       at0 = RealTime()

       CALL Info( 'FlowSolve', ' ', Level=4 )
       CALL Info( 'FlowSolve', ' ', Level=4 )
       CALL Info( 'FlowSolve', '-------------------------------------', Level=4 )
       WRITE( Message, * ) 'NAVIER-STOKES ITERATION', iter 
       CALL Info( 'FlowSolve',Message, Level=4 )
       CALL Info( 'FlowSolve','-------------------------------------', Level=4 )
       CALL Info( 'FlowSolve', ' ', Level=4 )
       CALL Info( 'FlowSolve','Starting Assembly...', Level=4 )

!------------------------------------------------------------------------------
!     If free surfaces in model, this will compute the curvatures
!------------------------------------------------------------------------------
!     IF ( FreeSurfaceFlag ) CALL MeanCurvature( Model )
!------------------------------------------------------------------------------
!     Compute average normals for boundaries having the normal & tangetial
!     velocities specified on the boundaries
!------------------------------------------------------------------------------
      IF ( (iter == 1 .OR. FreeSurfaceFlag) .AND. NumberOfBoundaryNodes > 0 ) THEN
         CALL AverageBoundaryNormals( Model, &
           'Normal-Tangential Velocity', NumberOfBoundaryNodes, &
           BoundaryReorder, BoundaryNormals, BoundaryTangent1, &
              BoundaryTangent2, DIM )
      END IF
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
       CALL InitializeToZero( StiffMatrix, ForceVector )
!------------------------------------------------------------------------------

       body_id = -1
       DO t = 1,Solver % NumberOFActiveElements

         IF ( RealTime() - at0 > 1.0 ) THEN
           WRITE( Message,'(a,i3,a)' ) '   Assembly: ', INT(100.0 - 100.0 * &
            (Solver % NumberOfActiveElements-t) / &
               (1.0*Solver %  NumberOfActiveElements)), ' % done'

           CALL Info( 'FlowSolve', Message, Level=5 )
                       
           at0 = RealTime()
         END IF
!------------------------------------------------------------------------------
!        Check if this element belongs to a body where flow
!        should be calculated
!------------------------------------------------------------------------------
!
         CurrentElement => Solver % Mesh % Elements( Solver % ActiveElements(t) )
         NodeIndexes => CurrentElement % NodeIndexes

!------------------------------------------------------------------------------

         IF ( CurrentElement % BodyId /= body_id ) THEN
           body_id = CurrentElement % BodyId
           eq_id = ListGetInteger( Model % Bodies(body_id) % Values,'Equation', &
                   minv=1, maxv=Model % NumberOfEquations )

           Convect = ListGetLogical( Model % Equations(eq_id) % Values, &
                     'NS Convect', GotIt )
           IF ( .NOT. GotIt ) Convect = .TRUE.

           k = ListGetInteger( Model % Bodies(body_id) % Values, 'Material', &
                  minv=1, maxv=Model % NumberOfMaterials )
           Material => Model % Materials(k) % Values

!------------------------------------------------------------------------------
           CompressibilityFlag = ListGetString( Material, &
               'Compressibility Model', GotIt)
           IF ( .NOT.GotIt ) CompressibilityModel = Incompressible
           PseudoCompressible = .FALSE.
!------------------------------------------------------------------------------
           SELECT CASE( CompressibilityFlag )
!------------------------------------------------------------------------------
             CASE( 'incompressible' )
               CompressibilityModel = Incompressible

             CASE( 'perfect gas', 'perfect gas equation 1' )
               CompressibilityModel = PerfectGas1

             CASE( 'thermal' )
               CompressibilityModel = Thermal

             CASE( 'user defined' )
               CompressibilityModel = UserDefined1

             CASE( 'artificial compressible' )
               CompressibilityModel = Incompressible 
               PseudoCompressible = .TRUE.

             CASE DEFAULT
               CompressibilityModel = Incompressible
!------------------------------------------------------------------------------
           END SELECT
!------------------------------------------------------------------------------


           Clip = ListGetConstReal( Model % Equations(eq_id) % Values,'KE Clip', GotIt )
           IF ( .NOT. GotIt ) Clip = 1.0d-6
         END IF

!------------------------------------------------------------------------------
!        ok, we�ve got one for Navier-Stokes        
!------------------------------------------------------------------------------
!
!------------------------------------------------------------------------------
!        Set the current element pointer in the model structure to
!        reflect the element being processed
!------------------------------------------------------------------------------
         Model % CurrentElement => CurrentElement
!------------------------------------------------------------------------------
         n = CurrentElement % TYPE % NumberOfNodes

         ElementNodes % x(1:n) = Solver % Mesh % Nodes % x(NodeIndexes)
         ElementNodes % y(1:n) = Solver % Mesh % Nodes % y(NodeIndexes)
         ElementNodes % z(1:n) = Solver % Mesh % Nodes % z(NodeIndexes)

         SELECT CASE( NSDOFs )
           CASE(3)
             U(1:n) = FlowSolution(NSDOFs*FlowPerm(NodeIndexes)-2)
             V(1:n) = FlowSolution(NSDOFs*FlowPerm(NodeIndexes)-1)
             W(1:n) = 0.0d0

           CASE(4)
             U(1:n) = FlowSolution(NSDOFs*FlowPerm(NodeIndexes)-3)
             V(1:n) = FlowSolution(NSDOFs*FlowPerm(NodeIndexes)-2)
             W(1:n) = FlowSolution(NSDOFs*FlowPerm(NodeIndexes)-1)
         END SELECT

         MU(1:n) = 0.0d0
         MV(1:n) = 0.0d0
         MW(1:n) = 0.0d0
         IF ( ASSOCIATED( MeshVelocity ) ) THEN
            SELECT CASE( MeshSol % DOFs )
            CASE(2)
               IF ( ALL( MeshPerm( NodeIndexes ) > 0 ) ) THEN
                  MU(1:n) = MeshVelocity(2*MeshPerm(NodeIndexes)-1)
                  MV(1:n) = MeshVelocity(2*MeshPerm(NodeIndexes)-0)
               END IF

            CASE(3)
               IF ( ALL( MeshPerm( NodeIndexes ) > 0 ) ) THEN
                  MU(1:n) = MeshVelocity(3*MeshPerm(NodeIndexes)-2)
                  MV(1:n) = MeshVelocity(3*MeshPerm(NodeIndexes)-1)
                  MW(1:n) = MeshVelocity(3*MeshPerm(NodeIndexes)-0)
               END IF
            END SELECT
         END IF

         LocalTemperature = 0.0d0
         LocalTempPrev    = 0.0d0
         IF ( ASSOCIATED( TempSol ) ) THEN
            IF ( ALL( TempPerm( NodeIndexes ) > 0 ) ) THEN
               LocalTemperature(1:n) = Temperature( TempPerm(NodeIndexes) )
               IF ( TransientSimulation .AND. CompressibilityModel /= Incompressible) THEN
                 LocalTempPrev(1:n) = TempPrev( TempPerm(NodeIndexes) )
               END IF
            END IF
         END IF
         ReferencePressure = 0.0d0

!------------------------------------------------------------------------------
         SELECT CASE( CompressibilityModel )
!------------------------------------------------------------------------------
           CASE( Incompressible )
!------------------------------------------------------------------------------
             Pressure(1:n)    = FlowSolution( NSDOFs*FlowPerm(NodeIndexes) )
             Density(1:n) = ListGetReal( Material,'Density',n,NodeIndexes )

             IF(PseudoCompressible) THEN
               Pressure(1:n) = PseudoPressure(FlowPerm(NodeIndexes)) 
               PseudoCompressibility(1:n) = PseudoCompressibilityScale * &
                   ListGetReal(Material,'Artificial Compressibility', &
                   n,NodeIndexes,gotIt)
               IF(.NOT. gotIt) PseudoCompressibility(1:n) = 0.0d0
             END IF

!------------------------------------------------------------------------------
           CASE( PerfectGas1 )

              ! Use  ReferenceTemperature in .sif file for fixed temperature
              ! field. At the moment can not have both fixed T ideal gas and
              ! Boussinesq force:
              !-------------------------------------------------------------
              IF ( .NOT. ASSOCIATED( TempSol ) ) THEN
                 LocalTemperature(1:n) = ListGetReal( Material, &
                   'Reference Temperature',n,NodeIndexes )
                 LocalTempPrev = LocalTemperature
              END IF

              HeatCapacity(1:n) = ListGetReal( Material, &
                'Heat Capacity',  n,NodeIndexes,GotIt )


              ! Read Specific Heat Ratio:
              !--------------------------
              SpecificHeatRatio = ListGetConstReal( Material, &
                     'Specific Heat Ratio', GotIt )
              IF ( .NOT.GotIt ) SpecificHeatRatio = 5.d0/3.d0


              ! For an ideal gas, \gamma, c_p and R are really a constant
              ! GasConstant is an array only since HeatCapacity formally is
              !------------------------------------------------------------
              GasConstant(1:n) = ( SpecificHeatRatio - 1.d0 ) *  &
                   HeatCapacity(1:n) / SpecificHeatRatio


              ! For ideal gases take pressure deviation p_d as the
              ! dependent variable: p = p_0 + p_d
              ! Read p_0
              !---------------------------------------------------
              ReferencePressure = ListGetConstReal( Material, &
                      'Reference Pressure', GotIt )
              IF ( .NOT.GotIt ) ReferencePressure = 0.0d0

              Pressure(1:n) = FlowSolution(NSDOFs*FlowPerm(NodeIndexes))
              IF ( TransientSimulation ) THEN
                PrevPressure(1:n) = Solver % Variable % PrevValues( &
                          NSDOFs*FlowPerm(NodeIndexes),1 )
              END IF
              Density(1:n) = ( Pressure(1:n) + ReferencePressure ) / &
                 ( GasConstant(1:n) * LocalTemperature(1:n) )

           CASE( UserDefined1 )
             Pressure(1:n)    = FlowSolution(NSDOFs*FlowPerm(NodeIndexes) )
             IF ( ASSOCIATED( DensitySol ) ) THEN
               Density(1:n) = DensitySol % Values( DensitySol % Perm(NodeIndexes) )
               IF ( TransientSimulation ) THEN
                  PrevDensity(1:n) = DensitySol % PrevValues( &
                       DensitySol % Perm(NodeIndexes),1)
                END IF
             ELSE
               Density(1:n) = ListGetReal( Material,'Density',n,NodeIndexes )
               PrevDensity(1:n) = Density(1:n)
             END IF

           CASE( Thermal )
             Pressure(1:n) = FlowSolution(NSDOFs*FlowPerm(NodeIndexes))

             HeatExpansionCoeff(1:n) = ListGetReal( Material, &
               'Heat Expansion Coefficient',n,NodeIndexes )

             ReferenceTemperature(1:n) = ListGetReal( Material, &
               'Reference Temperature',n,NodeIndexes )

             Density(1:n) = ListGetReal( Material,'Density',n,NodeIndexes )
             Density(1:n) = Density(1:n) * ( 1 - HeatExpansionCoeff(1:n)  * &
                  ( LocalTemperature(1:n) - ReferenceTemperature(1:n) ) )
             IF ( TransientSimulation ) THEN
                PrevDensity(1:n) = Density(1:n) * ( 1 - HeatExpansionCoeff(1:n) * &
                   ( LocalTempPrev(1:n) - ReferenceTemperature(1:n) )  )
             END IF
!------------------------------------------------------------------------------
         END SELECT
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
!        Read in porous media defs
!------------------------------------------------------------------------------
         Porous = ListGetLogical( Material,'Porous Media', GotIt)
         IF(Porous) THEN
           CALL GetRealArray( Material,  Pwrk,'Porous Resistivity')
           
           IF( .NOT. ASSOCIATED(Pwrk) ) THEN
             Drag = 0.0d0
           ELSE IF ( SIZE(Pwrk,1) == 1 ) THEN
             DO i=1,NSDOFs-1
               Drag( i,1:n ) = Pwrk( 1,1,1:n )
             END DO
           ELSE 
             DO i=1,MIN(NSDOFs,SIZE(Pwrk,1))
               Drag(i,1:n) = Pwrk(i,1,1:n)
             END DO
           END IF
         END IF
!
!------------------------------------------------------------------------------
!        Viscosity = Laminar (+ Turbulent viscosity)
!------------------------------------------------------------------------------
         Viscosity(1:n) = ListGetReal( Material,'Viscosity',n,NodeIndexes )

#if 0
! this is now done by EffectiveViscosity() in MaterialModels.
         IF ( ASSOCIATED(KinEnergySol) ) THEN
!------------------------------------------------------------------------------
           KECmu(1:n) = ListGetReal( Material, 'KE Cmu',n,NodeIndexes )
!------------------------------------------------------------------------------
           DO i=1,n
             k = KinPerm(NodeIndexes(i))
             IF ( k > 0 ) THEN
               Bu = MAX( KinEnergy(k),Clip )
               Bv = KinDissipation(k)

               IF ( Bv < Clip ) THEN
                 Bu = Clip
                 Bv = MAX(KECmu(i) * Density(i) * Bu**2 / Viscosity(i),Clip)
               ENDIF
!------------------------------------------------------------------------------
#ifdef KWMODEL
               Viscosity(i) = Viscosity(i) + Density(i)*Bu / Bv
#else
               Viscosity(i) = Viscosity(i) + KECmu(i)*Density(i)*Bu**2 / Bv
#endif
             END IF
           END DO
         END IF
#endif
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
!        Set body forces, if any
!------------------------------------------------------------------------------
         bf_id = ListGetInteger( Model % Bodies(body_id) % Values, &
            'Body Force', gotIt, 1, Model % NumberOfBodyForces )

         LoadVector = 0.0D0

         IF ( gotIt ) THEN

           HeatExpansionCoeff   = 0.0D0
           ReferenceTemperature = 0.0D0

!------------------------------------------------------------------------------
!          Boussinesq body force & gravity
!------------------------------------------------------------------------------
           IF ( ListGetLogical( Model % BodyForces(bf_id) % Values, &
                        'Boussinesq',gotIt) ) THEN

             HeatExpansionCoeff(1:n) = ListGetReal( Material, &
               'Heat Expansion Coefficient',n,NodeIndexes )

             ReferenceTemperature(1:n) = ListGetReal( Material, &
                  'Reference Temperature',n,NodeIndexes )

             DO i=1,n
               k = TempPerm(NodeIndexes(i))
               IF ( k > 0 ) THEN
                 IF ( ListGetLogical( Model % Equations(eq_id) % Values, &
                         'Hydrostatic Pressure',gotIt ) ) THEN
                   Tdiff = 1 - HeatExpansionCoeff(i) * &
                      (Temperature(k) - ReferenceTemperature(i))

                   IF ( Tdiff <= 0.0D0 ) THEN
                      CALL Warn( 'FlowSolve','Zero or negative density.' )
                   END IF
                 ELSE
                   Tdiff = -HeatExpansionCoeff(i) * &
                               (Temperature(k) - ReferenceTemperature(i))
                 END IF
  
                 LoadVector(1,i)   = Gravity(1) * Tdiff
                 LoadVector(2,i)   = Gravity(2) * Tdiff
                 IF ( NSDOFs > 3 ) THEN
                   LoadVector(3,i) = Gravity(3) * Tdiff
                 END IF
               END IF
             END DO
           END IF
!------------------------------------------------------------------------------
           LoadVector(1,1:n) = LoadVector(1,1:n) + ListGetReal( &
               Model % BodyForces(bf_id) % Values, &
               'Flow Bodyforce 1',n,NodeIndexes,gotIt )
           
           LoadVector(2,1:n) = LoadVector(2,1:n) + ListGetReal( &
               Model % BodyForces(bf_id) % Values, &
               'Flow Bodyforce 2',n,NodeIndexes,gotIt )

           IF ( NSDOFs > 3 ) THEN
             LoadVector(3,1:n) = LoadVector(3,1:n) + ListGetReal( &
                 Model % BodyForces(bf_id) % Values, &
                 'Flow Bodyforce 3',n,NodeIndexes,gotIt )
           END IF

!------------------------------------------------------------------------------
           
           PotentialForce = ListGetLogical( Model % BodyForces(bf_id) % Values, &
               'Potential Force',gotIt) 
           IF(PotentialForce) THEN
             PotentialField(1:n) = ListGetReal( Model % BodyForces(bf_id) % Values, &
                 'Potential Field',n,NodeIndexes)             
             PotentialCoefficient(1:n) = ListGetReal( Model % BodyForces(bf_id) % Values, &
                 'Potential Coefficient',n,NodeIndexes)
           END IF
        
!------------------------------------------------------------------------------
         END IF ! of body forces

!------------------------------------------------------------------------------
!
! NOTE: LoadVector is multiplied by density inside *Navier* routines
!
         IF ( TransientSimulation ) THEN
           SELECT CASE( CompressibilityModel )
           CASE( PerfectGas1 )
             IF ( ASSOCIATED( TempSol ) ) THEN
               DO i=1,n
                 k = TempPerm(NodeIndexes(i))
                 IF ( k > 0 ) THEN
                    LoadVector(NSDOFs,i) = LoadVector(NSDOFs,i) + &
                       ( 1.0d0 / LocalTemperature(i) ) * &
                      ( Temperature(k) - TempPrev(k) ) / dt
                 END IF
               END DO
             END IF
           CASE( UserDefined1, Thermal )
              DO i=1,n
                LoadVector(NSDOFs,i) = LoadVector(NSDOFs,i) - &
                  ( Density(i) - PrevDensity(i) ) / (Density(i)*dt)
              END DO
           END SELECT
         END IF

!------------------------------------------------------------------------------
!        Get element local stiffness & mass matrices
!------------------------------------------------------------------------------
         SELECT CASE(Coordinates)
         CASE( Cartesian )
!------------------------------------------------------------------------------
           SELECT CASE( CompressibilityModel )
!------------------------------------------------------------------------------
             CASE( Incompressible,PerfectGas1,UserDefined1,Thermal)
!------------------------------------------------------------------------------
! Density needed for steady-state, also pressure for transient
!------------------------------------------------------------------------------
               CALL NavierStokesCompose( &
                   LocalMassMatrix,LocalStiffMatrix,LocalForce, LoadVector, &
                   Viscosity,Density,U,V,W,MU,MV,MW, &
                   ReferencePressure+Pressure(1:n), &
                   LocalTemperature, Convect, Stabilize, &
                   CompressibilityModel == PerfectGas1,  &
                   CompressibilityModel == Thermal  .OR. &
                   CompressibilityModel == UserDefined1, &
                   PseudoCompressible, PseudoCompressibility, Porous, Drag, & 
                   PotentialForce, PotentialField, PotentialCoefficient, &
                   DivDiscretization, GradPDiscretization, NewtonLinearization, &
                   CurrentElement,n,ElementNodes)
!------------------------------------------------------------------------------
           END SELECT
!------------------------------------------------------------------------------

         CASE( Cylindric,CylindricSymmetric,AxisSymmetric )
! Same comments as Cartesian
!------------------------------------------------------------------------------
           SELECT CASE( CompressibilityModel )
!------------------------------------------------------------------------------
             CASE( Incompressible,PerfectGas1)
!------------------------------------------------------------------------------
               CALL NavierStokesCylindricalCompose( &
                   LocalMassMatrix,LocalStiffMatrix,LocalForce, &
                   LoadVector, Viscosity,Density,U,V,W,MU,MV,MW, &
                   ReferencePressure+Pressure(1:n),LocalTemperature,&
                   Convect, Stabilize, CompressibilityModel /= Incompressible, &
                   PseudoCompressible, PseudoCompressibility, Porous, Drag, &
                   PotentialForce, PotentialField, PotentialCoefficient, &
                   NewtonLinearization,CurrentElement,n,ElementNodes )
!------------------------------------------------------------------------------
           END SELECT
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
         CASE DEFAULT
!------------------------------------------------------------------------------

           CALL NavierStokesGeneralCompose( &
               LocalMassMatrix,LocalStiffMatrix,LocalForce, &
               LoadVector, Viscosity,Density,U,V,W,MU,MV,MW,Stabilize, &
               NewtonLinearization,CurrentElement,n,ElementNodes )
           
!------------------------------------------------------------------------------
         END SELECT
!------------------------------------------------------------------------------
!        If time dependent simulation, add mass matrix to global 
!        matrix and global RHS vector
!------------------------------------------------------------------------------
         Bubbles  = .NOT.Stabilize .OR. CompressibilityModel /= Incompressible
         IF ( Bubbles ) TimeForce  = LocalForce

!if ( currentelement % bodyid == 2 ) then
!   localstiffmatrix = 0
!   localforce = 0 
!   do i=1,n
!   do j=1,n
!     localmassmatrix(nsdofs*i,nsdofs*j) = & 
!            1d-12 * localmassmatrix(nsdofs*(i-1)+1,nsdofs*(j-1)+1)
!   end do
!   end do
!end if

         IF ( TransientSimulation ) THEN
!------------------------------------------------------------------------------
!          NOTE: the following will replace LocalStiffMatrix and LocalForce
!          with the combined information
!------------------------------------------------------------------------------
           IF ( Bubbles ) LocalForce = 0.0d0

           CALL Add1stOrderTime( LocalMassMatrix, LocalStiffMatrix, &
                LocalForce, dt, n, NSDOFs, FlowPerm(NodeIndexes), Solver )
         END IF

         IF ( Bubbles  ) THEN
            nb = CurrentElement % BDOFs
            IF ( nb <= 0 ) Nb = n
            CALL NSCondensate( N, nb, NSDOFs-1, LocalStiffMatrix, &
                            LocalForce, TimeForce )
            IF ( TransientSimulation ) THEN
               CALL UpdateTimeForce( StiffMatrix, ForceVector, TimeForce, &
                             n, NSDOFs, FlowPerm(NodeIndexes) )
            END IF
         END IF
!------------------------------------------------------------------------------
!        If boundary velocities have been defined in normal/tangetial
!        coordinate systems, we will have to rotate the matrix & force vector
!        to that coordinate system
!------------------------------------------------------------------------------
         IF ( NumberOfBoundaryNodes > 0 ) THEN
           CALL RotateMatrix( LocalStiffMatrix,LocalForce,n,DIM, NSDOFs, &
             BoundaryReorder(NodeIndexes), BoundaryNormals, BoundaryTangent1, &
                              BoundaryTangent2 )
         END IF
!------------------------------------------------------------------------------
!        Add local stiffness matrix and force vector to global matrix & vector
!------------------------------------------------------------------------------
         CALL UpdateGlobalEquations( StiffMatrix, LocalStiffMatrix, &
              ForceVector, LocalForce, n, NSDOFs, FlowPerm(NodeIndexes) )
!------------------------------------------------------------------------------
      END DO
!------------------------------------------------------------------------------

      IF ( ASSOCIATED( FlowStress ) ) THEN
         CALL CRS_MatrixVectorMultiply( Solver % Matrix, &
              Solver % Variable % Values, FlowStress % Values )
         FlowStress % Values = FlowStress % Values - Solver % Matrix % RHS
         WHERE( FlowPerm > 0 )
           FlowStress % Values(FlowStress % Perm) = FlowStress % Values(FlowPerm)
         END WHERE
      END IF

      CALL Info( 'FlowSolve', 'Assembly done', Level=4 )

!------------------------------------------------------------------------------
!     Neumann & Newton boundary conditions
!------------------------------------------------------------------------------
      DO t = Solver % Mesh % NumberOfBulkElements + 1, &
                Solver % Mesh % NumberOfBulkElements + &
                   Solver % Mesh % NumberOfBoundaryElements

        CurrentElement => Solver % Mesh % Elements(t)
!------------------------------------------------------------------------------
!       Set the current element pointer in the model structure to 
!       reflect the element being processed
!------------------------------------------------------------------------------
        Model % CurrentElement => Solver % Mesh % Elements(t)
!------------------------------------------------------------------------------
        n = CurrentElement % TYPE % NumberOfNodes
        NodeIndexes => CurrentElement % NodeIndexes

        IF ( ANY( FlowPerm( NodeIndexes ) <= 0 ) ) CYCLE
!
!       The element type 101 (point element) can only be used
!       to set Dirichlet BCs, so skip �em at this stage.
!
        IF ( CurrentElement % TYPE % ElementCode == 101 ) CYCLE

        ElementNodes % x(1:n) = Solver % Mesh % Nodes % x(NodeIndexes)
        ElementNodes % y(1:n) = Solver % Mesh % Nodes % y(NodeIndexes)
        ElementNodes % z(1:n) = Solver % Mesh % Nodes % z(NodeIndexes)

!------------------------------------------------------------------------------
        DO i=1,Model % NumberOfBCs
!------------------------------------------------------------------------------
          IF ( CurrentElement % BoundaryInfo % Constraint == &
                 Model % BCs(i) % Tag ) THEN
!------------------------------------------------------------------------------
            GotForceBC = ListGetLogical(Model % BCs(i) % Values, &
                       'Flow Force BC',gotIt )

            IF ( GotForceBC ) THEN

              LocalForce  = 0.0d0
              LoadVector  = 0.0d0
              Alpha       = 0.0d0
              ExtPressure = 0.0d0
              Beta        = 0.0d0
              LocalStiffMatrix = 0.0d0
!------------------------------------------------------------------------------
!             (at the moment the following is done...)
!             BC: \tau \cdot n = \alpha n +  @\beta/@t + R_k u_k + F
!------------------------------------------------------------------------------
!------------------------------------------------------------------------------
!             normal force BC: \tau\cdot n = \alpha n
!------------------------------------------------------------------------------
              IF ( ListGetLogical(Model % BCs(i) % Values, &
                                       'Free Surface',gotIt) ) THEN
                Alpha(1:n) = ListGetReal( &
                    Model % BCs(i) % Values,'Surface Tension Coefficient', &
                                  n,NodeIndexes ) 
              END IF

              ExtPressure(1:n) = ListGetReal( Model % BCs(i) % Values, &
                  'External Pressure',n, NodeIndexes,GotForceBC )
!------------------------------------------------------------------------------
!             tangential force BC:
!             \tau\cdot n = @\beta/@t (tangential derivative of something)
!------------------------------------------------------------------------------
              
              IF ( ASSOCIATED( TempSol ) ) THEN
                Beta(1:n) = ListGetReal( Model % BCs(i) % Values, &
                 'Surface Tension Expansion Coefficient',n,NodeIndexes,gotIt )

                IF ( gotIt ) THEN
                  DO j=1,n
                    k = TempPerm( NodeIndexes(j) )
                    IF ( k>0 ) Beta(j) = 1.0D0 - Beta(j) * Temperature(k)
                  END DO

                  Beta(1:n) = Beta(1:n) * ListGetReal( &
                    Model % BCs(i) % Values,'Surface Tension Coefficient', &
                                  n,NodeIndexes ) 
                ELSE
                  Beta(1:n) = ListGetReal( &
                    Model % BCs(i) % Values,'Surface Tension Coefficient', &
                                  n,NodeIndexes,gotIt ) 
                END IF
              END IF

!------------------------------------------------------------------------------
!             force in given direction BC: \tau\cdot n = F
!------------------------------------------------------------------------------

              LoadVector(1,1:n) =  ListGetReal( Model % BCs(i) % Values, &
                        'Pressure 1',n,NodeIndexes,GotIt )

              LoadVector(2,1:n) =  ListGetReal( Model % BCs(i) % Values, &
                        'Pressure 2',n,NodeIndexes,GotIt )

              LoadVector(3,1:n) =  ListGetReal( Model % BCs(i) % Values, &
                        'Pressure 3',n,NodeIndexes,GotIt )

              LoadVector(4,1:n) =  ListGetReal( Model % BCs(i) % Values, &
                        'Mass Flux',n,NodeIndexes,GotIt )

!------------------------------------------------------------------------------
!             slip boundary condition BC: \tau\cdot n = R_k u_k
!------------------------------------------------------------------------------

              SlipCoeff = 0.0d0
              SlipCoeff(1,1:n) =  ListGetReal( Model % BCs(i) % Values, &
                    'Slip Coefficient 1',n,NodeIndexes,GotIt )

              SlipCoeff(2,1:n) =  ListGetReal( Model % BCs(i) % Values, &
                    'Slip Coefficient 2',n,NodeIndexes,GotIt )

              SlipCoeff(3,1:n) =  ListGetReal( Model % BCs(i) % Values, &
                    'Slip Coefficient 3',n,NodeIndexes,GotIt )

              NormalTangential = ListGetLogical( Model % BCs(i) % Values, &
                     'Normal-Tangential Velocity', GotIt )
               
!------------------------------------------------------------------------------
              SELECT CASE( CurrentCoordinateSystem() )
              CASE( Cartesian )

                CALL NavierStokesBoundary( LocalStiffMatrix, LocalForce, &
                 LoadVector, Alpha, Beta, ExtPressure, SlipCoeff, NormalTangential,   &
                    CurrentElement, n, ElementNodes )

             CASE( Cylindric, CylindricSymmetric,  AxisSymmetric )

                CALL NavierStokesCylindricalBoundary( LocalStiffMatrix, &
                 LocalForce, LoadVector, Alpha, Beta, ExtPressure, SlipCoeff, &
                     NormalTangential, CurrentElement, n, ElementNodes)

             CASE DEFAULT

                CALL NavierStokesGeneralBoundary( LocalStiffMatrix, &
                 LocalForce, LoadVector, Alpha, Beta, ExtPressure, SlipCoeff, &
                    CurrentElement, n, ElementNodes)

             END SELECT

!------------------------------------------------------------------------------

              IF ( ListGetLogical( Model % BCs(i) % Values, &
                        'Wall Law',GotIt ) ) THEN
                !/*
                ! * TODO: note that the following is not really valid, the
                ! * pointer to the Material structure is from the remains
                ! * of the last of the bulk elements.
                ! */
                Density(1:n)   = ListGetReal(Material,'Density',n,NodeIndexes)
                Viscosity(1:n) = ListGetReal(Material,'Viscosity',n,NodeIndexes)

                LayerThickness(1:n) = ListGetReal( Model % BCs(i) % Values, &
                        'Boundary Layer Thickness',n,NodeIndexes )

                SurfaceRoughness(1:n) = ListGetReal( Model % BCs(i) % Values, &
                        'Surface Roughness',n,NodeIndexes )

                SELECT CASE( NSDOFs )
                  CASE(3)
                    U(1:n) = FlowSolution( NSDOFs*FlowPerm(NodeIndexes)-2 )
                    V(1:n) = FlowSolution( NSDOFs*FlowPerm(NodeIndexes)-1 )
                    W(1:n) = 0.0d0
                
                  CASE(4)
                    U(1:n) = FlowSolution( NSDOFs*FlowPerm(NodeIndexes)-3 )
                    V(1:n) = FlowSolution( NSDOFs*FlowPerm(NodeIndexes)-2 )
                    W(1:n) = FlowSolution( NSDOFs*FlowPerm(NodeIndexes)-1 )
                END SELECT

                CALL NavierStokesWallLaw( LocalStiffMatrix,LocalForce,     &
                  LayerThickness,SurfaceRoughness,Viscosity,Density,U,V,W, &
                         CurrentElement,n, ElementNodes )
              END IF
!------------------------------------------------------------------------------

              IF ( TransientSimulation ) THEN
                LocalMassMatrix = 0.0d0
                CALL Add1stOrderTime( LocalMassMatrix, LocalStiffMatrix, &
                  LocalForce, dt, n, NSDOFs,FlowPerm(NodeIndexes), Solver )
              END IF

!------------------------------------------------------------------------------
!             If boundary velocities have been defined in normal/tangetial
!             coordinate systems, we will have to rotate the matrix & force
!             vector to that coordinate system.
!------------------------------------------------------------------------------
              IF ( NumberOfBoundaryNodes > 0 ) THEN
                CALL RotateMatrix( LocalStiffMatrix, LocalForce, n, DIM,   &
                    NSDOFs, BoundaryReorder(NodeIndexes), BoundaryNormals, &
                         BoundaryTangent1, BoundaryTangent2 )
              END IF
!------------------------------------------------------------------------------
!             Add local stiffness matrix and force vector to
!             global matrix & vector
!------------------------------------------------------------------------------
              CALL UpdateGlobalEquations( StiffMatrix, LocalStiffMatrix, &
                    ForceVector, LocalForce, n, NSDOFs, FlowPerm(NodeIndexes) )
!------------------------------------------------------------------------------
            END IF
!------------------------------------------------------------------------------
          END IF
        END DO
      END DO
!------------------------------------------------------------------------------

      CALL FinishAssembly( Solver, ForceVector )

!------------------------------------------------------------------------------
!     Dirichlet boundary conditions
!------------------------------------------------------------------------------
      CALL SetDirichletBoundaries( Model, StiffMatrix, ForceVector, & 
                'Velocity 1', 1, NSDOFs, FlowPerm )

      CALL SetDirichletBoundaries( Model, StiffMatrix, ForceVector, & 
                'Velocity 2', 2, NSDOFs, FlowPerm )

      IF ( NSDOFs > 3 ) THEN
        CALL SetDirichletBoundaries( Model, StiffMatrix, ForceVector, & 
                'Velocity 3', 3, NSDOFs, FlowPerm )
      END IF

      CALL SetDirichletBoundaries( Model, StiffMatrix, ForceVector, & 
                'Pressure', NSDOFs, NSDOFs, FlowPerm )
!------------------------------------------------------------------------------

      CALL Info( 'FlowSolve', 'Set boundaries done', Level=4 )
!------------------------------------------------------------------------------
!     Solve the system and check for convergence
!------------------------------------------------------------------------------
      at = CPUTime() - at
      st = CPUTime()

      PrevUNorm = UNorm

      IF ( NonlinearRelax /= 1.0d0 ) PSolution = FlowSolution
      CALL SolveSystem( StiffMatrix, ParMatrix, ForceVector, &
              FlowSolution, UNorm, NSDOFs, Solver )

      st = CPUTIme()-st
      totat = totat + at
      totst = totst + st
      WRITE(Message,'(a,i4,a,F8.2,F8.2)') 'iter: ',iter,' Assembly: (s)', at, totat
      CALL Info( 'FlowSolve', Message, Level=4 )
      WRITE(Message,'(a,i4,a,F8.2,F8.2)') 'iter: ',iter,' Solve:    (s)', st, totst
      CALL Info( 'FlowSolve', Message, Level=4 )
!------------------------------------------------------------------------------
!     If boundary velocities have been defined in normal/tangetial coordinate
!     systems, we�ll have to rotate the solution back to coordinate axis
!     directions
!------------------------------------------------------------------------------
      IF ( NumberOfBoundaryNodes > 0 ) THEN
        DO i=1,SIZE( FlowPerm )
          k = BoundaryReorder(i)

          IF ( k > 0 ) THEN
            j = FlowPerm(i)

            IF ( j > 0 ) THEN
              IF ( DIM < 3 ) THEN
                Bu = FlowSolution( NSDOFs*(j-1) + 1 )
                Bv = FlowSolution( NSDOFs*(j-1) + 2 )

                FlowSolution( NSDOFs*(j-1) + 1 ) = BoundaryNormals(k,1) * Bu - &
                                BoundaryNormals(k,2) * Bv

                FlowSolution( NSDOFs*(j-1) + 2 ) = BoundaryNormals(k,2) * Bu + &
                                BoundaryNormals(k,1) * Bv
              ELSE
                Bu = FlowSolution( NSDOFs*(j-1) + 1 )
                Bv = FlowSolution( NSDOFs*(j-1) + 2 )
                Bw = FlowSolution( NSDOFs*(j-1) + 3 )

                RM(1,:) = BoundaryNormals(k,:)
                RM(2,:) = BoundaryTangent1(k,:)
                RM(3,:) = BoundaryTangent2(k,:)

                FlowSolution(NSDOFs*(j-1)+1) = RM(1,1)*Bu + RM(2,1)*Bv + RM(3,1)*Bw
                FlowSolution(NSDOFs*(j-1)+2) = RM(1,2)*Bu + RM(2,2)*Bv + RM(3,2)*Bw
                FlowSolution(NSDOFs*(j-1)+3) = RM(1,3)*Bu + RM(2,3)*Bv + RM(3,3)*Bw
              END IF
            END IF
          END IF
        END DO 
      END IF

!------------------------------------------------------------------------------

      n = NSDOFs * LocalNodes

!------------------------------------------------------------------------------
!     This hack is needed  cause of the fluctuating pressure levels
!------------------------------------------------------------------------------
      IF ( NonlinearRelax /= 1.0d0 ) THEN
         IF ( CompressibilityModel == Incompressible ) THEN
            s = FlowSolution(NSDOFs)
            FlowSolution(NSDOFs:n:NSDOFs) = FlowSolution(NSDOFs:n:NSDOFs) -  s
            PSolution(NSDOFs:n:NSDOFs) = PSolution(NSDOFs:n:NSDOFs) - PSolution(NSDOFs)
         END IF

         FlowSolution(1:n) = (1 - NonlinearRelax) * PSolution(1:n) + &
                    NonlinearRelax * FlowSolution(1:n)
       
         IF ( CompressibilityModel == Incompressible ) THEN
            FlowSolution(NSDOFs:n:NSDOFs) = FlowSolution(NSDOFs:n:NSDOFs) + s
         END IF
      END IF
!------------------------------------------------------------------------------

      IF ( ParEnv % PEs <= 1 ) THEN
         UNorm = 0.0d0
         DO i=1,LocalNodes
            DO j=1,NSDOFs-1
               k = NSDOFs*(i-1) + j
               UNorm = UNorm + FlowSolution(k)**2
            END DO
         END DO
         UNorm = SQRT( UNorm / (NSDOFs*LocalNodes) )
         Solver % Variable % Norm = UNorm
      END IF

      IF ( PrevUNorm + UNorm /= 0.0d0 ) THEN
         RelativeChange = 2.0d0 * ABS(PrevUNorm-UNorm) / (PrevUNorm + UNorm)
      ELSE
         RelativeChange = 0.0d0
      END IF

      WRITE( Message, * ) 'Result Norm     : ',UNorm
      CALL Info( 'FlowSolve', Message, Level=4 )
      WRITE( Message, * ) 'Relative Change : ',RelativeChange
      CALL Info( 'FlowSolve', Message, Level=4 )

      IF ( RelativeChange < NewtonTol .OR. &
             iter > NewtonIter ) NewtonLinearization = .TRUE.

      IF ( RelativeChange < NonLinearTol ) EXIT

!------------------------------------------------------------------------------
!     If free surfaces in model, this will move the nodal points
!------------------------------------------------------------------------------
      IF ( FreeSurfaceFlag ) THEN
        Relaxation = ListGetConstReal( Solver % Values, &
           'Free Surface Relaxation Factor', GotIt )

        IF ( .NOT.GotIt ) Relaxation = 1.0d0

        MBFlag = ListGetLogical( Solver % Values, 'Internal Move Boundary', GotIt )
        IF ( MBFlag .OR. .NOT. GotIt ) THEN
            CALL MoveBoundary( Model,Relaxation )
        END IF
      END IF
!------------------------------------------------------------------------------
    END DO  ! of nonlinear iteration

    CALL ListAddConstReal( Solver % Values, &
        'Nonlinear System Relaxation Factor', NonlinearRelax )

    IF (ListGetLogical(Solver % Values,'Adaptive Mesh Refinement',GotIt)) &
      CALL RefineMesh( Model,Solver,FlowSolution,FlowPerm, &
         FlowInsideResidual, FlowEdgeResidual, FlowBoundaryResidual ) 

!------------------------------------------------------------------------------
    CALL CheckCircleBoundary()
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
CONTAINS
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
   SUBROUTINE CheckCircleBoundary()
!------------------------------------------------------------------------------
      REAL(KIND=dp) :: x,y,phi,x0,y0,r
      LOGICAL :: GotIt
      INTEGER :: i,j,k,l
!------------------------------------------------------------------------------

      l = 0
      DO i=1,Model % NumberOfBCs
         IF ( .NOT.ListgetLogical( Model % BCs(i) % Values, &
                  'Circle Boundary', GotIt ) ) CYCLE

         x0 = ListGetConstReal( Model % BCs(i) % Values, 'Circle X', GotIt )
         IF ( .NOT. GotIt ) x0 = 0.0d0

         y0 = ListGetConstReal( Model % BCs(i) % Values, 'Circle Y', GotIt )
         IF ( .NOT. GotIt ) y0 = 0.0d0

         R  = ListGetConstReal( Model % BCs(i) % Values, 'Circle R', GotIt )
         IF ( .NOT. GotIt ) R = 1.0d0

         DO j=Solver % Mesh % NumberOfBulkElements+1, &
            Solver % Mesh % NumberOfBulkElements+ &
               Solver % Mesh % NumberOfBoundaryElements
            CurrentElement => Solver % Mesh % Elements(j)
            IF ( CurrentElement % BoundaryInfo % Constraint &
                 /= Model % BCs(i) % Tag ) CYCLE

            n = CurrentELement % TYPE % NumberOfNodes
            NodeIndexes => CurrentElement % NodeIndexes
            DO k=1,n
               x = Solver % Mesh % Nodes % x(NodeIndexes(k)) - x0
               y = Solver % Mesh % Nodes % y(NodeIndexes(k)) - y0

               phi = ATAN2( y,x )
               x = R * COS( phi ) 
               y = R * SIN( phi ) 

               Solver % Mesh % Nodes % x(NodeIndexes(k)) = x + x0
               Solver % Mesh % Nodes % y(NodeIndexes(k)) = y + y0
            END DO
            l = l + 1
        END DO
     END DO

     IF ( l > 0 ) THEN
        WRITE( Message, * ) 'Elements on Circle', l
        CALL Info( 'FlowSolve', Message, Level=6 )
     END IF
!------------------------------------------------------------------------------
   END SUBROUTINE CheckCircleBoundary
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  END SUBROUTINE FlowSolver
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
  FUNCTION FlowBoundaryResidual( Model, Edge, Mesh, &
             Quant, Perm, Gnorm ) RESULT( Indicator )
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

     INTEGER :: i,j,k,n,l,t,bc,DIM,DOFs,Pn,En
     LOGICAL :: stat, GotIt, Compressible

     REAL(KIND=dp) :: SqrtMetric, Metric(3,3), Symb(3,3,3), dSymb(3,3,3,3)

     REAL(KIND=dp) :: Grad(3,3), Grad1(3,3), Stress(3,3), Normal(3), ForceSolved(3), &
                      EdgeLength, x(MAX_NODES), y(MAX_NODES), z(MAX_NODES), &
                      ExtPressure(MAX_NODES)

     REAL(KIND=dp) :: u, v, w, s, detJ, EdgeBasis(MAX_NODES), &
         dEdgeBasisdx(MAX_NODES,3), Basis(MAX_NODES),dBasisdx(MAX_NODES,3), &
         ddBasisddx(MAX_NODES,3,3)

     REAL(KIND=dp) :: Source, Residual(3), ResidualNorm, Area

     REAL(KIND=dp) :: Velocity(3,MAX_NODES), Pressure(MAX_NODES), &
       Force(3,MAX_NODES), NodalViscosity(MAX_NODES), Viscosity

     REAL(KIND=dp) :: Slip, SlipCoeff(3,MAX_NODES), Dir(3)
     REAL(KIND=dp) :: Temperature(MAX_NODES), Tension(MAX_NODES)

     TYPE(Variable_t), POINTER :: TempSol

     TYPE(ValueList_t), POINTER :: Material

     TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff
!------------------------------------------------------------------------------

!    Initialize:
!    -----------
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

     DOFs = DIM + 1
     IF ( CurrentCoordinateSystem() == AxisSymmetric ) DOFs = DOFs-1
!    
!    --------------------------------------------------
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

     DO bc=1,Model % NumberOfBCs
        IF ( Edge % BoundaryInfo % Constraint /= Model % BCs(bc) % Tag ) CYCLE

!       IF ( .NOT. ListGetLogical( Model % BCs(bc) % Values, &
!                 'Flow Force BC', gotIt ) ) CYCLE
!
!       Get material parameters:
!       ------------------------

        k = ListGetInteger(Model % Bodies(Element % BodyId) % Values,'Material', &
                     minv=1, maxv=Model % NumberOfMaterials )
        Material => Model % Materials(k) % Values

        NodalViscosity(1:En) = ListGetReal( Material, &
                 'Viscosity', En, Edge % NodeIndexes, GotIt )

        Compressible = .FALSE.
        IF ( ListGetString( Material, 'Compressibility Model', GotIt ) == &
               'perfect gas equation 1' ) Compressible = .TRUE.


!       Given traction:
!       ---------------
        Force = 0.0d0

        Force(1,1:En) = ListGetReal( Model % BCs(bc) % Values, &
            'Pressure 1', En, Edge % NodeIndexes, GotIt )

        Force(2,1:En) = ListGetReal( Model % BCs(bc) % Values, &
            'Pressure 2', En, Edge % NodeIndexes, GotIt )

        Force(3,1:En) = ListGetReal( Model % BCs(bc) % Values, &
            'Pressure 3', En, Edge % NodeIndexes, GotIt )

!
!       Force in normal direction:
!       ---------------------------
        ExtPressure(1:En) = ListGetReal( Model % BCs(bc) % Values, &
          'External Pressure', En, Edge % NodeIndexes, GotIt )

!
!       Slip BC condition:
!       ------------------
        SlipCoeff = 0.0d0
        SlipCoeff(1,1:En) =  ListGetReal( Model % BCs(bc) % Values, &
             'Slip Coefficient 1',En,Edge % NodeIndexes,GotIt )

        SlipCoeff(2,1:En) =  ListGetReal( Model % BCs(bc) % Values, &
             'Slip Coefficient 2',En,Edge % NodeIndexes,GotIt )

        SlipCoeff(3,1:En) =  ListGetReal( Model % BCs(bc) % Values, &
             'Slip Coefficient 3',En,Edge % NodeIndexes,GotIt )

!
!       Surface tension induced by temperature gradient (or otherwise):
!       ---------------------------------------------------------------
        TempSol => VariableGet( Mesh % Variables, 'Temperature', .TRUE. )

        IF ( ASSOCIATED( TempSol ) ) THEN
          Tension(1:En) = ListGetReal( Model % BCs(bc) % Values, &
           'Surface Tension Expansion Coefficient',En,Edge % NodeIndexes,gotIt )

           IF ( gotIt ) THEN
              DO n=1,En
                 k = TempSol % Perm( Edge % NodeIndexes(n) )
                 IF (k>0) Tension(n) = 1.0d0 - Tension(n) * TempSol % Values(k)
              END DO

              Tension(1:En) = Tension(1:En) * ListGetReal( &
                 Model % BCs(bc) % Values,'Surface Tension Coefficient', &
                               En, Edge % NodeIndexes ) 
           ELSE
              Tension(1:En) = ListGetReal( &
                  Model % BCs(bc) % Values,'Surface Tension Coefficient', &
                         En, Edge % NodeIndexes,gotIt ) 
           END IF
        ELSE
           Tension(1:En) = ListGetReal( &
               Model % BCs(bc) % Values,'Surface Tension Coefficient', &
                      En, Edge % NodeIndexes,gotIt ) 
        END IF

!
!       If dirichlet BC for velocity in any direction given,
!       nullify force in that directon:
!       ------------------------------------------------------------------
        Dir = 1
        s = ListGetConstReal( Model % BCs(bc) % Values, 'Velocity 1', GotIt )
        IF ( GotIt ) Dir(1) = 0

        s = ListGetConstReal( Model % BCs(bc) % Values, 'Velocity 2', GotIt )
        IF ( GotIt ) Dir(2) = 0

        s = ListGetConstReal( Model % BCs(bc) % Values, 'Velocity 3', GotIt )
        IF ( GotIt ) Dir(3) = 0

!
!       Elementwise nodal solution:
!       ---------------------------
        Velocity = 0.0d0
        DO k=1,DOFs-1
           Velocity(k,1:Pn) = Quant(DOFs*Perm(Element % NodeIndexes)-DOFs + k)
        END DO
        Pressure(1:Pn) = Quant( DOFs*Perm(Element % NodeIndexes) )

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
               EdgeBasis, dEdgeBasisdx, ddBasisddx, .FALSE., .FALSE. )

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

           Normal = NormalVector( Edge, EdgeNodes, u, v, .TRUE. )

           u = SUM( EdgeBasis(1:En) * x(1:En) )
           v = SUM( EdgeBasis(1:En) * y(1:En) )
           w = SUM( EdgeBasis(1:En) * z(1:En) )

           stat = ElementInfo( Element, Nodes, u, v, w, detJ, &
              Basis, dBasisdx, ddBasisddx, .FALSE., .FALSE. )

           Viscosity = SUM( NodalViscosity(1:En) * EdgeBasis(1:En) )

           Residual = 0.0d0
!
!          Given force at the integration point:
!          -------------------------------------
           Residual = Residual + MATMUL( Force(:,1:En), EdgeBasis(1:En) ) - &
                 SUM( ExtPressure(1:En) * EdgeBasis(1:En) ) * Normal

!
!          Slip velocity BC:
!          -----------------
           DO i=1,DIM
              Slip = SUM( SlipCoeff(i,1:En) * EdgeBasis(1:En) )
              Residual(i) = Residual(i) - &
                   Slip * SUM( Velocity(i,1:Pn) * Basis(1:Pn) )
           END DO

!
!          Tangential tension force:
!          -------------------------
           DO i=1,DIM
              Residual(i) = Residual(i) + &
                   SUM( dEdgeBasisdx(1:En,i) * Tension(1:En) )
           END DO

!
!          Force given by the computed solution:
!          -------------------------------------
!
!          Stress tensor on the boundary:
!          ------------------------------
           Grad = MATMUL( Velocity(:,1:Pn), dBasisdx(1:Pn,:) )

           IF ( CurrentCoordinateSystem() /= Cartesian ) THEN
              Grad1 = Grad
              DO i=1,DIM
                 DO k=1,DIM
                    DO l=1,DIM
                       Grad1(i,k) = Grad1(i,k) - &
                          Symb(k,l,i) * SUM ( Velocity(l,1:Pn) * Basis(1:Pn) )
                    END DO
                 END DO
              END DO

              Grad = 0.0d0
              DO i=1,DIM
                 DO k=1,DIM
                    DO l=1,DIM
                       Grad(i,k) = Grad(i,k) + Metric(k,l) * Grad1(i,l)
                    END DO
                 END DO
              END DO
           END IF

           Stress = Viscosity * ( Grad + TRANSPOSE(Grad) )
           Stress = Stress - Metric * SUM( Pressure(1:Pn) * Basis(1:Pn) )

           IF ( Compressible ) THEN
              IF ( CurrentCoordinateSystem() == Cartesian ) THEN
                 DO i=1,DIM
                    DO k=1,DIM
                       Stress(i,i) = Stress(i,i) - &
                           (2.0d0/3.0d0) * Viscosity * Grad(k,k)
                    END DO
                 END DO
              ELSE
                 DO i=1,DIM
                    DO k=1,DIM
                       DO l=1,DIM
                          Stress(i,k) = Stress(i,k) - &
                             Metric(i,k) * (2.0d0/3.0d0) * Viscosity * Grad(l,l)
                       END DO
                    END DO
                 END DO
              END IF
           END IF

           ForceSolved = MATMUL(Stress,Normal)
           Residual = Residual - ForceSolved * Dir

           EdgeLength = EdgeLength + s

           IF ( CurrentCoordinateSystem() == Cartesian ) THEN
              Gnorm = Gnorm + s * SUM( ForceSolved**2 )
              ResidualNorm = ResidualNorm + s * SUM( Residual(1:DIM) ** 2 )
           ELSE
              CALL InvertMatrix( Metric,3 )
              DO i=1,DIM
                 DO k=1,DIM
                    ResidualNorm = ResidualNorm + &
                            s * Metric(i,k) * Residual(i) * Residual(k)
                    Gnorm = GNorm + s * Metric(i,k) * &
                                        ForceSolved(i) * ForceSolved(k)
                 END DO
              END DO
           END IF
        END DO
        EXIT
     END DO

     IF ( CoordinateSystemDimension() == 3 ) EdgeLength = SQRT(EdgeLength)
     Indicator = EdgeLength * ResidualNorm

     DEALLOCATE( Nodes % x, Nodes % y, Nodes % z)
     DEALLOCATE( EdgeNodes % x, EdgeNodes % y, EdgeNodes % z)
!------------------------------------------------------------------------------
  END FUNCTION FlowBoundaryResidual
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  FUNCTION FlowEdgeResidual( Model,Edge,Mesh,Quant,Perm ) RESULT( Indicator )
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

     INTEGER :: i,j,k,l,n,t,DIM,DOFs,En,Pn
     LOGICAL :: stat, GotIt

     REAL(KIND=dp) :: SqrtMetric, Metric(3,3), Symb(3,3,3), dSymb(3,3,3,3)

     REAL(KIND=dp) :: NodalViscosity(MAX_NODES), Viscosity

     REAL(KIND=dp) :: Stress(3,3,2), Jump(3)

     REAL(KIND=dp) :: Grad(3,3), Grad1(3,3), Normal(3), &
                x(MAX_NODES), y(MAX_NODES), z(MAX_NODES)

     REAL(KIND=dp) :: Velocity(3,MAX_NODES), Pressure(MAX_NODES)

     REAL(KIND=dp) :: u, v, w, s, detJ, EdgeBasis(MAX_NODES), Basis(MAX_NODES), &
              dBasisdx(MAX_NODES,3), ddBasisddx(MAX_NODES,3,3)

     REAL(KIND=dp) :: Residual, ResidualNorm, EdgeLength

     TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff
!------------------------------------------------------------------------------

!    Initialize:
!    -----------
     SELECT CASE( CurrentCoordinateSystem() )
        CASE( AxisSymmetric, CylindricSymmetric )
           DIM = 3
        CASE DEFAULT
           DIM = CoordinateSystemDimension()
     END SELECT

     DOFs = DIM + 1
     IF ( CurrentCoordinateSystem() == AxisSymmetric ) DOFs = DOFs - 1

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
!    ------------------------------------
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

        Stress = 0.0d0
        DO i = 1,2
           IF ( i==1 ) THEN
              Element => Edge % BoundaryInfo % Left
           ELSE
              Element => Edge % BoundaryInfo % Right
           END IF

           IF ( ANY( Perm( Element % NodeIndexes ) <= 0 ) ) CYCLE

           Pn = Element % TYPE % NumberOfNodes
           Nodes % x(1:Pn) = Mesh % Nodes % x(Element % NodeIndexes)
           Nodes % y(1:Pn) = Mesh % Nodes % y(Element % NodeIndexes)
           Nodes % z(1:Pn) = Mesh % Nodes % z(Element % NodeIndexes)

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

           stat = ElementInfo( Element, Nodes, u, v, w, detJ, &
               Basis, dBasisdx, ddBasisddx, .FALSE., .FALSE. )

           k = ListGetInteger( Model % Bodies( Element % BodyId) % Values, 'Material', &
                            minv=1, maxv=Model % NumberOfMaterials )

           NodalViscosity(1:En) = ListGetReal( &
               Model % Materials(k) % Values, 'Viscosity', &
                    En, Edge % NodeIndexes, GotIt )

           Viscosity = SUM( NodalViscosity(1:En) * EdgeBasis(1:En) )
!
!          Elementwise nodal solution:
!          ---------------------------
           Velocity = 0.0d0
           DO k=1,DOFs-1
              Velocity(k,1:Pn) = Quant(DOFs*Perm(Element % NodeIndexes)-DOFs+k)
           END DO
           Pressure(1:Pn) = Quant( DOFs*Perm(Element % NodeIndexes) )
!
!          Stress tensor on the edge:
!          --------------------------
           Grad = MATMUL( Velocity(:,1:Pn), dBasisdx(1:Pn,:) )

           IF ( CurrentCoordinateSystem() /= Cartesian ) THEN
              Grad1 = Grad
              DO j=1,DIM
                 DO k=1,DIM
                    DO l=1,DIM
                       Grad1(j,k) = Grad1(j,k) - &
                          Symb(k,l,j) * SUM ( Velocity(l,1:Pn) * Basis(1:Pn) )
                    END DO
                 END DO
              END DO

              Grad = 0.0d0
              DO j=1,DIM
                 DO k=1,DIM
                    DO l=1,DIM
                       Grad(j,k) = Grad(j,k) + Metric(k,l) * Grad1(j,l)
                    END DO
                 END DO
              END DO
           END IF

           Stress(:,:,i) = Viscosity * ( Grad + TRANSPOSE(Grad) )

           IF ( CurrentCoordinateSystem() == Cartesian ) THEN
              DO j=1,DIM
                 Stress(j,j,i) = Stress(j,j,i) - SUM( Pressure(1:Pn) * Basis(1:Pn))
                 DO k=1,DIM
                    Stress(j,j,i) = Stress(j,j,i) - (2.0d0/3.0d0)*Viscosity*Grad(k,k)
                 END DO
              END DO
           ELSE
              DO j=1,DIM
                 DO k=1,DIM
                    Stress(j,k,i) = Stress(j,k,i) - &
                           Metric(j,k) * SUM( Pressure(1:Pn) * Basis(1:Pn) )

                    DO l=1,DIM
                       Stress(j,k,i) = Stress(j,k,i) - &
                           Metric(j,k) * (2.0d0/3.0d0) * Viscosity * Grad(l,l)
                    END DO
                 END DO
              END DO
           END IF

        END DO

        EdgeLength = EdgeLength + s

        Jump = MATMUL( ( Stress(:,:,1) - Stress(:,:,2)), Normal )

        IF ( CurrentCoordinateSystem() == Cartesian ) THEN
           ResidualNorm = ResidualNorm + s * SUM( Jump(1:DIM) ** 2 )
        ELSE
           CALL InvertMatrix( Metric,3 )
           DO i=1,DIM
              DO j=1,DIM
                 ResidualNorm = ResidualNorm + s*Metric(i,j)*Jump(i)*Jump(j)
              END DO
           END DO
        END IF
     END DO

     Indicator = EdgeLength * ResidualNorm

     DEALLOCATE( Nodes % x, Nodes % y, Nodes % z)
     DEALLOCATE( EdgeNodes % x, EdgeNodes % y, EdgeNodes % z)
!------------------------------------------------------------------------------
  END FUNCTION FlowEdgeResidual
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   FUNCTION FlowInsideResidual( Model, Element,  &
          Mesh, Quant, Perm, Fnorm ) RESULT( Indicator )
!------------------------------------------------------------------------------
     USE CoordinateSystems
     USE ElementDescription
!------------------------------------------------------------------------------
     IMPLICIT NONE
!------------------------------------------------------------------------------
     TYPE(Model_t) :: Model
     INTEGER :: Perm(:)
     REAL(KIND=dp) :: Quant(:), Indicator(2), FNorm
     TYPE( Mesh_t ), POINTER    :: Mesh
     TYPE( Element_t ), POINTER :: Element
!------------------------------------------------------------------------------

     TYPE(Nodes_t) :: Nodes

     INTEGER :: i,j,k,l,m,n,t,DIM,DOFs

     LOGICAL :: stat, GotIt, Compressible, Convect

     TYPE( Variable_t ), POINTER :: Var

     REAL(KIND=dp), TARGET :: x(MAX_NODES), y(MAX_NODES), z(MAX_NODES)

     REAL(KIND=dp) :: SqrtMetric, Metric(3,3), Symb(3,3,3), dSymb(3,3,3,3)

     REAL(KIND=dp) :: Density, NodalDensity(MAX_NODES)
 
     REAL(KIND=dp) :: Viscosity, NodalViscosity(MAX_NODES)

     REAL(KIND=dp) :: u, v, w, s, detJ, Basis(MAX_NODES), &
        dBasisdx(MAX_NODES,3), ddBasisddx(MAX_NODES,3,3)

     REAL(KIND=dp) :: Source, Residual(4), ResidualNorm, Area

     REAL(KIND=dp) :: Velocity(3,MAX_NODES), Pressure(MAX_NODES)

     REAL(KIND=dp) :: Temperature(MAX_NODES), NodalForce(4,MAX_NODES)

     REAL(KIND=dp) :: HeatCapacity(MAX_NODES), ReferenceTemperature(MAX_NODES), &
                      ReferencePressure, HeatExpansionCoeff(MAX_NODES)

     REAL(KIND=dp) :: PrevVelo(3,MAX_NODES), PrevPres(MAX_NODES), dt

     REAL(KIND=dp) :: SpecificHeatRatio, Grad(3,3), Stress(3,3), E

     REAL(KIND=dp), POINTER :: Gravity(:,:)

     TYPE(ValueList_t), POINTER :: Material

     TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff
!------------------------------------------------------------------------------

!    Initialize:
!    -----------
     Indicator = 0.0d0
     FNorm = 0.0d0

     IF ( ANY( Perm( Element % NodeIndexes ) <= 0 ) ) RETURN

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

     DOFs = DIM + 1
     IF ( CurrentCoordinateSystem() == AxisSymmetric ) DOFs = DOFs-1
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
!    Material parameters: density, viscosity, etc.
!    ----------------------------------------------
     k = ListGetInteger( Model % Bodies(Element % BodyId) % Values, 'Material', &
                  minv=1, maxv=Model % NumberOfMaterials )

     Material => Model % Materials(k) % Values

     NodalDensity(1:n) = ListGetReal( &
         Material, 'Density', n, Element % NodeIndexes, GotIt )

     NodalViscosity(1:n) = ListGetReal( &
         Material, 'Viscosity', n, Element % NodeIndexes, GotIt )

     k = ListGetInteger( Model % Bodies(Element % BodyId) % Values,'Equation', &
                      minv=1, maxv=Model % NumberOfEquations   )

     Convect = ListGetLogical( Model % Equations(k) % Values, &
                   'NS Convect', GotIt )
     IF ( .NOT. GotIt ) Convect = .TRUE.
!
!    Elementwise nodal solution:
!    ---------------------------
     Velocity = 0.0d0
     DO k=1,DOFs-1
        Velocity(k,1:n) = Quant( DOFs*Perm(Element % NodeIndexes)-DOFs+k )
     END DO
     Pressure(1:n) = Quant( DOFs*Perm(Element % NodeIndexes) )

!
!    Check for time dep.
!    -------------------
     PrevPres(1:n)     = Pressure(1:n)
     PrevVelo(1:3,1:n) = Velocity(1:3,1:n)

     dt = Model % Solver % dt

     IF ( ListGetString( Model % Simulation, 'Simulation Type') == 'transient' ) THEN
        Var => VariableGet( Model % Variables, 'Flow Solution', .TRUE. )

        PrevVelo = 0.0d0
        DO k=1,DOFs-1
           PrevVelo(k,1:n) = &
              Var % PrevValues(DOFs*Var % Perm(Element % NodeIndexes)-DOFs+k,1)
        END DO
        PrevPres(1:n)=Var % PrevValues(DOFs*Var % Perm(Element % NodeIndexes),1)
     END IF


!
!    Check for compressible flow equations:
!    --------------------------------------
     Compressible = .FALSE.

     IF (  ListGetString( Material, 'Compressibility Model', GotIt ) == &
                      'perfect gas equation 1' ) THEN

        Compressible = .TRUE.

        Var => VariableGet( Mesh % Variables, 'Temperature', .TRUE. )
        IF ( ASSOCIATED( Var ) ) THEN
           Temperature(1:n) = &
               Var % Values( Var % Perm(Element % NodeIndexes) )
        ELSE
           Temperature(1:n) = ListGetReal( Material, &
               'Reference Temperature',n,Element % NodeIndexes )
        END IF

        SpecificHeatRatio = ListGetConstReal( Material, &
                  'Specific Heat Ratio' )

        ReferencePressure = ListGetConstReal( Material, &
                   'Reference Pressure' )

        HeatCapacity(1:n) = ListGetReal( Material, &
                      'Heat Capacity',n,Element % NodeIndexes )

        NodalDensity(1:n) =  (Pressure(1:n) + ReferencePressure) * SpecificHeatRatio / &
              ( (SpecificHeatRatio - 1) * HeatCapacity(1:n) * Temperature(1:n) )
     END IF
!
!    Body Forces:
!    ------------
!
     k = ListGetInteger( Model % Bodies(Element % BodyId) % Values, &
       'Body Force', GotIt, 1, Model % NumberOfBodyForces )

     NodalForce = 0.0d0

     IF ( GotIt .AND. k > 0  ) THEN
!
!       Boussinesq approximation of heat expansion for
!       incompressible flow equations:
!
!       Density for the force term equals to
!
!       \rho = rho_0 (1-\beta(T-T_0)),
!
!       where \beta is the  heat expansion  coefficient,
!       T temperature and \rho_0 and T_0 correspond to
!       stress free state. Otherwise density is assumed
!       constant.
!       ----------------------------------------------
        IF (ListGetLogical(Model % BodyForces(k) % Values,'Boussinesq',GotIt)) THEN

           Var => VariableGet( Mesh % Variables, 'Temperature', .TRUE. )
           IF ( ASSOCIATED( Var ) ) THEN
              Temperature(1:n) = &
                  Var % Values( Var % Perm(Element % NodeIndexes) )

              HeatExpansionCoeff(1:n) = ListGetReal( Material, &
                 'Heat Expansion Coefficient',n,Element % NodeIndexes )

              ReferenceTemperature(1:n) = ListGetReal( Material, &
                 'Reference Temperature',n,Element % NodeIndexes )

              Gravity => ListGetConstRealArray( Model % Constants, &
                             'Gravity' )

              k = ListGetInteger( Model % Bodies(Element % BodyId) % Values,'Equation', &
                        minv=1, maxv=Model % NumberOfEquations )

              IF ( ListGetLogical( Model % Equations(k) % Values, &
                            'Hydrostatic Pressure', GotIt) ) THEN
                 DO i=1,DIM
                    NodalForce(i,1:n) = ( 1 - HeatExpansionCoeff(1:n) * &
                       ( Temperature(1:n) - ReferenceTemperature(1:n) ) ) * &
                            Gravity(i,1) * Gravity(4,1)
                 END DO
              ELSE
                 DO i=1,DIM
                    NodalForce(i,1:n) = ( -HeatExpansionCoeff(1:n) * &
                       ( Temperature(1:n) - ReferenceTemperature(1:n) ) ) * &
                            Gravity(i,1) * Gravity(4,1)
                 END DO
              END IF
           END IF
        END IF

!
!       Given external force:
!       ---------------------
        NodalForce(1,1:n) = NodalForce(1,1:n) + ListGetReal( &
             Model % BodyForces(k) % Values, 'Flow BodyForce 1', &
                  n, Element % NodeIndexes, GotIt )

        NodalForce(2,1:n) = NodalForce(2,1:n) + ListGetReal( &
             Model % BodyForces(k) % Values, 'Flow BodyForce 2', &
                  n, Element % NodeIndexes, GotIt )

        NodalForce(3,1:n) = NodalForce(3,1:n) + ListGetReal( &
             Model % BodyForces(k) % Values, 'Flow BodyForce 3', &
                  n, Element % NodeIndexes, GotIt )
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

        Density   = SUM( NodalDensity(1:n)   * Basis(1:n) )
        Viscosity = SUM( NodalViscosity(1:n) * Basis(1:n) )
!
!       Residual of the navier-stokes equations:
!
!       or more generally:
!
!       ----------------------------------------------------------
!
        Residual = 0.0d0
        DO i=1,DIM
!
!          given force:
!          -------------
           Residual(i) = -Density * SUM( NodalForce(i,1:n) * Basis(1:n) )
 
           IF ( CurrentCoordinateSystem() == Cartesian ) THEN
!             + grad(p):
!             ----------
              Residual(i) = Residual(i) + SUM( Pressure(1:n) * dBasisdx(1:n,i) )

              DO j=1,DIM
!
!                - 2 ( \mu \epsilon^{ij} )_{,j}:
!                -------------------------------
                 Residual(i) = Residual(i) - Viscosity * &
                     SUM( Velocity(i,1:n) * ddBasisddx(1:n,j,j) )

                 Residual(i) = Residual(i) - &
                      SUM( NodalViscosity(1:n) * dBasisdx(1:n,j) ) * &
                          SUM( Velocity(i,1:n) * dBasisdx(1:n,j) )

                  Residual(i) = Residual(i) - Viscosity * &
                      SUM( Velocity(j,1:n) * ddBasisddx(1:n,i,j) )

                  Residual(i) = Residual(i) - &
                      SUM( NodalViscosity(1:n) * dBasisdx(1:n,j) ) * &
                          SUM( Velocity(j,1:n) * dBasisdx(1:n,i) )

                  IF ( Compressible ) THEN
!
!                    + (2/3) grad(\mu div(u)):
!                    -------------------------
                     Residual(i) = Residual(i) + &
                        Viscosity * ( 2.0d0 / 3.0d0 ) * &
                           SUM( Velocity(j,1:n) * ddBasisddx(1:n,j,i) )

                     Residual(i) = Residual(i) + &
                         SUM( NodalViscosity(1:n) * dBasisdx(1:n,i) ) * &
                             SUM( Velocity(j,1:n) * dBasisdx(1:n,j) )

                  END IF
              END DO

              IF ( Convect ) THEN
!
!                + \rho * (@u/@t + u.grad(u)):
!                -----------------------------
                 Residual(i) = Residual(i) + Density *  &
                     SUM((Velocity(i,1:n)-PrevVelo(i,1:n))*Basis(1:n)) / dt

                 DO j=1,DIM
                    Residual(i) = Residual(i) + &
                        Density * SUM( Velocity(j,1:n) * Basis(1:n) ) * &
                            SUM( Velocity(i,1:n) * dBasisdx(1:n,j) )
                 END DO
              END IF
           ELSE
!             + g^{ij}p_{,j}:
!             ---------------
              DO j=1,DIM
                 Residual(i) = Residual(i) + Metric(i,j) * &
                      SUM( Pressure(1:n) * dBasisdx(1:n,i) )
              END DO

!             - g^{jk} (\mu u^i_{,k})_{,j}):
!             ------------------------------
              DO j=1,DIM
                 DO k=1,DIM
                    Residual(i) = Residual(i) -   &
                         Metric(j,k) * Viscosity * &
                         SUM( Velocity(i,1:n) * ddBasisddx(1:n,j,k) )

                    DO l=1,DIM
                       Residual(i) = Residual(i) +  &
                            Metric(j,k) * Viscosity * Symb(j,k,l) * &
                            SUM( Velocity(i,1:n) * dBasisdx(1:n,l) )

                       Residual(i) = Residual(i) -  &
                            Metric(j,k) * Viscosity * Symb(l,j,i) * &
                            SUM( Velocity(l,1:n) * dBasisdx(1:n,k) )

                       Residual(i) = Residual(i) -  &
                            Metric(j,k) * Viscosity * Symb(l,k,i) * &
                            SUM( Velocity(l,1:n) * dBasisdx(1:n,j) )

                       Residual(i) = Residual(i) -  &
                            Metric(j,k) * Viscosity * dSymb(l,j,i,k) * &
                            SUM( Velocity(l,1:n) * Basis(1:n) )

                       DO m=1,DIM
                          Residual(i) = Residual(i) - Metric(j,k) * Viscosity *&
                                  Symb(m,k,i) * Symb(l,j,m) * &
                                        SUM( Velocity(l,1:n) * Basis(1:n) )

                          Residual(i) = Residual(i) + Metric(j,k) * Viscosity *&
                                  Symb(j,k,m) * Symb(l,m,i) * &
                                        SUM( Velocity(l,1:n) * Basis(1:n) )
                       END DO
                    END DO
                 END DO
              END DO

!             - g^{ik} (\mu u^j_{,k})_{,j}):
!             ------------------------------
              DO j=1,DIM
                 DO k=1,DIM
                    Residual(i) = Residual(i) -   &
                         Metric(i,k) * Viscosity * &
                         SUM( Velocity(j,1:n) * ddBasisddx(1:n,j,k) )

                    DO l=1,DIM
                       Residual(i) = Residual(i) +  &
                            Metric(i,k) * Viscosity * Symb(j,k,l) * &
                            SUM( Velocity(j,1:n) * dBasisdx(1:n,l) )

                       Residual(i) = Residual(i) -  &
                            Metric(i,k) * Viscosity * Symb(l,j,j) * &
                            SUM( Velocity(l,1:n) * dBasisdx(1:n,k) )

                       Residual(i) = Residual(i) -  &
                            Metric(i,k) * Viscosity * Symb(l,k,j) * &
                            SUM( Velocity(l,1:n) * dBasisdx(1:n,j) )

                       Residual(i) = Residual(i) -  &
                            Metric(i,k) * Viscosity * dSymb(l,j,j,k) * &
                            SUM( Velocity(l,1:n) * Basis(1:n) )

                       DO m=1,DIM
                          Residual(i) = Residual(i) - Metric(i,k) * Viscosity *&
                                  Symb(m,k,j) * Symb(l,j,m) * &
                                        SUM( Velocity(l,1:n) * Basis(1:n) )

                          Residual(i) = Residual(i) + Metric(i,k) * Viscosity *&
                                  Symb(j,k,m) * Symb(l,m,j) * &
                                        SUM( Velocity(l,1:n) * Basis(1:n) )
                       END DO
                    END DO
                 END DO
              END DO

              IF ( Convect ) THEN
!
!                + \rho * (@u/@t + u^j u^i_{,j}):
!                --------------------------------
                 Residual(i) = Residual(i) + Density *  &
                     SUM((Velocity(i,1:n)-PrevVelo(i,1:n))*Basis(1:n)) / dt

                 DO j=1,DIM
                    Residual(i) = Residual(i) + &
                         Density * SUM( Velocity(j,1:n) * Basis(1:n) ) * &
                         SUM( Velocity(i,1:n) * dBasisdx(1:n,j) )

                    DO k=1,DIM
                       Residual(i) = Residual(i) + &
                            Density * SUM( Velocity(j,1:n) * Basis(1:n) ) * &
                            Symb(j,k,i) * SUM( Velocity(k,1:n) * Basis(1:n) )
                    END DO
                 END DO
              END IF
           END IF
        END DO

!
!       Continuity equation:
!       --------------------
        IF ( CurrentCoordinateSystem() == Cartesian ) THEN
!
!          + \rho * div(u):
!          ----------------
           DO j=1,DIM
              Residual(DIM+1) = Residual(DIM+1) + &
                   Density * SUM( Velocity(j,1:n) * dBasisdx(1:n,j) )
           END DO

           IF ( Compressible ) THEN
!
!             + u.grad(\rho):
!             ----------------
              DO j=1,DIM
                 Residual(DIM+1) = Residual(DIM+1) + &
                      SUM( Velocity(j,1:n) * Basis(1:n) ) *  &
                           SUM( NodalDensity(1:n) * dBasisdx(1:n,j) ) 
              END DO
           END IF
        ELSE
!
!          + \rho * u^j_{,j}:
!          ------------------
           DO j=1,DIM
              Residual(DIM+1) = Residual(DIM+1) + &
                   Density * SUM( Velocity(j,1:n) * dBasisdx(1:n,j) )

              DO k=1,DIM
                 Residual(DIM+1) = Residual(DIM+1) + Density * &
                      Symb(k,j,j) * SUM( Velocity(k,1:n) * Basis(1:n) )
              END DO
           END DO

           IF ( Compressible ) THEN
!
!             + u^j \rho_{,j}:
!             ----------------
              DO j=1,DIM
                 Residual(DIM+1) = Residual(DIM+1) + &
                      SUM( Velocity(j,1:n) * Basis(1:n) ) *  &
                      SUM( NodalDensity(1:n) * dBasisdx(1:n,j) ) 
              END DO
           END IF
        END IF

        DO i=1,DIM
           FNorm = FNorm + s * (Density * SUM(NodalForce(i,1:n)*Basis(1:n))**2)
        END DO 
        Area = Area + s

        IF ( CurrentCoordinateSystem() == Cartesian ) THEN
           ResidualNorm = ResidualNorm + &
             s * (Element % hK**2 * SUM(Residual(1:dim)**2) + Residual(dim+1)**2 )
        ELSE
           CALL InvertMatrix( Metric,3 )
           DO i=1,dim
              DO j=1,dim
                 ResidualNorm = ResidualNorm + &
                    s * Element % hK **2 * Metric(i,j) * Residual(i) * Residual(j)
              END DO
           END DO
           ResidualNorm = ResidualNorm + s * Residual(dim+1)**2
        END IF
     END DO

!    FNorm = Area * FNorm
     Indicator = ResidualNorm
!------------------------------------------------------------------------------
  END FUNCTION FlowInsideResidual
!------------------------------------------------------------------------------
