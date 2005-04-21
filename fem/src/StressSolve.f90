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
! * Module containing a solver for linear stress equations
! *
! ******************************************************************************
! *
! *                     Author:       Juha Ruokolainen
! *
! *                    Address: Center for Scientific Computing
! *                            Tietotie 6, P.O. Box 405
! *                              02101 Espoo, Finland
! *                              Tel. +358 0 457 2723
! *                            Telefax: +358 0 457 2302
! *                          EMail: Juha.Ruokolainen@csc.fi
! *
! *                       Date: 08 Jun 1997
! *
! *                Modified by:
! *
! *       Date of modification:
! *
! * $Log: StressSolve.f90,v $
! * Revision 1.120  2005/04/19 08:53:48  jpr
! * Renamed module LUDecomposition as LinearAlgebra.
! *
! * Revision 1.119  2005/04/15 13:01:42  jpr
! * Corrected a bug in the Stress computation related to bandwidth optimization.
! *
! * Revision 1.114  2005/02/15 13:41:21  jpr
! * Some more cleaning up of the code.
! *
! * Revision 1.113  2005/02/15 09:36:12  jpr
! * Use computed stress solution in StressInsideResidual if present ('Calculate
! * Stresses' activated), instead of trying to compute this to nodes directly.
! *
! * Revision 1.111  2005/02/15 08:28:14  jpr
! * Cleaning up of the residual functions. Some bodyforce & bc options still
! * missing from the r-functions. Also modified the interface to LocalStress
! * to include number of dofs/element different from number of element nodal
! * points.
! *
! * Revision 1.110  2005/02/14 15:04:00  raback
! * Added second strategy for model lumping.
! *
! * Revision 1.109  2005/02/14 10:34:39  jpr
! * Corrected a bug in the boundary residual routine (adaptive meshing).
! *
! * Revision 1.101  2005/02/14 07:04:34  jpr
! * Rewrite of the stress calculation.
! *
! * Revision 1.100  2004/12/16 11:02:07  apursula
! * Added possibility to rotate the elasticity matrix in 3d with
! * anisotropic material
! *
! * Revision 1.99  2004/11/09 08:43:39  jpr
! * Corrected a bug in computing Von Mises stress. The bug resulted in
! * indexing arrays over allocated size when the domain of the displacement
! * solver was not the whole mesh.
! *
! * Revision 1.96  2004/10/15 14:26:43  raback
! * Enabled model lumping for 3D structures loaded at one boundary.
! *
! * Revision 1.93  2004/10/06 11:08:49  jpr
! * Added keyword 'Stress(n)' to sections 'Body Force', 'Boundary Condition'
! * and 'Material'. Added keyword 'Strain(n)' to sections 'Body Force' and
! * 'Material'. These keywords may be used to give stress and strain
! * engineering vectors, with following meanings:
! *
! * Body Force-section:
! * Bulk term of the partial integration of the div(Sigma)*Phi is added
! * as a body force. For divergence free Sigma this amounts to setting
! * the boundary normal stress to (Sigma,n). Given Strain is used to
! * compute Sigma.
! *
! * Material-section:
! * Stress and Strain are used as prestress and prestrains to geometric
! * stiffness and/or buckling analysis (in addition to given load case).
! *
! * Boundary Condition-section:
! * Given Stress is multiplied by normal giving the the normal stress on
! * the boundary.
! *
! * Stress and Strain keywords give the components
! * 2D:
! * Strain(3) = Eta_xx Eta_yy 2*Eta_xy
! * Stress(3) = Sigma_xx Sigma_yy Sigma_xz
! * Axi Symmetric:
! * Strain(4) = Eta_rr Eta_pp Eta_zz 2*Eta_rz
! * Stress(4) = Sigma_rr Sigma_pp Sigma_zz Sigma_rz
! * 3D:
! * Strain(6) = Eta_xx Eta_yy Eta_zz 2*Eta_xy 2*Eta_yz 2*Eta_xz
! * Stress(6) = Sigma_xx Sigma_yy Sigma_zz Sigma_xy Sigma_yz Sigma_xz
! *
! *
! * Revision 1.83  2004/08/09 06:42:16  apursula
! * Changed: asking for Poisson Ratio only in isotropic cases
! *
! * Revision 1.81  2004/07/29 08:11:14  apursula
! * Added complaints if density is not given
! *
! * Revision 1.78  2004/03/04 13:09:11  jpr
! * Modified axisymmetric case to call StressBoundary instead of
! * StressGeneralBoundary to implement boundary damping in axisymmetric cases.
! * Still to be implemented in general coordinate case.
! *
! * Revision 1.77  2004/03/03 09:12:01  jpr
! * Added 3rd argument to GetLocical(...) to stop the complaint about
! * missing "Output Version Numbers" keyword.
! *
! * Revision 1.75  2004/03/01 14:59:55  jpr
! * Modified residual function interfaces for goal oriented adaptivity,
! * no functionality yet.
! * Started log.
! *
! *****************************************************************************/

!------------------------------------------------------------------------------
   SUBROUTINE StressSolver( Model,Solver,dt,TransientSimulation )
!DEC$ATTRIBUTES DLLEXPORT :: StressSolver
!------------------------------------------------------------------------------

    USE CoordinateSystems
    USE StressLocal
    USE StressGeneral
    USE Adaptive
    USE DefUtils
    USE ElementDescription

    IMPLICIT NONE
!------------------------------------------------------------------------------
!******************************************************************************
!
!  Solve stress equations for one timestep
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
!     INPUT: Timestep size for time dependent simulations (NOTE: Not used
!            currently)
!
!******************************************************************************

     TYPE(Model_t)  :: Model
     TYPE(Solver_t), TARGET :: Solver

     LOGICAL ::  TransientSimulation
     REAL(KIND=dp) :: dt
!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------
     TYPE(Solver_t), POINTER :: PSolver

     INTEGER :: i,j,k,l,n,t,iter,STDOFs,istat, body_id

     TYPE(ValueList_t),POINTER :: SolverParams, Equation, Material, BodyForce, BC
     TYPE(Nodes_t) :: ElementNodes
     TYPE(Element_t),POINTER :: Element

     REAL(KIND=dp) :: RelativeChange,UNorm,PrevUNorm, &
         Tdiff,Normal(3),NewtonTol,NonlinearTol,s, UzawaParameter

     INTEGER :: NewtonIter,MaxIter, MinIter
     TYPE(Variable_t), POINTER :: StressSol, TempSol, Var

     REAL(KIND=dp), POINTER :: Temperature(:),Displacement(:),Work(:,:,:), &
            VonMises(:), NodalStress(:), StressComp(:), ContactPressure(:), &
            NormalDisplacement(:), TransformMatrix(:,:), UWrk(:,:)

     REAL(KIND=dp) :: UnitNorm, Unit1(3), Unit2(3), Unit3(3)

     INTEGER, POINTER :: TempPerm(:),DisplPerm(:),StressPerm(:),NodeIndexes(:)

     INTEGER :: StressType
     LOGICAL :: GotForceBC,Found,NewtonLinearization = .FALSE.
     LOGICAL :: PlaneStress, CalcStress, CalcStressAll, Isotropic = .TRUE.
     LOGICAL :: Contact = .FALSE.
     LOGICAL :: stat, stat2, stat3, RotateC, MeshDisplacementActive

     LOGICAL :: AllocationsDone = .FALSE., NormalTangential
     LOGICAL :: StabilityAnalysis = .FALSE., ModelLumping, FixDisplacement
     LOGICAL :: GeometricStiffness = .FALSE., EigenAnalysis=.FALSE., OrigEigenAnalysis

     REAL(KIND=dp),ALLOCATABLE:: MASS(:,:),STIFF(:,:),&
       DAMP(:,:), LOAD(:,:),FORCE(:), &
       LocalTemperature(:),ElasticModulus(:,:,:),PoissonRatio(:), &
       HeatExpansionCoeff(:,:,:),DampCoeff(:),SpringCoeff(:),Beta(:), &
       ReferenceTemperature(:),BoundaryDispl(:), Density(:), Damping(:), &
       NodalDisplacement(:,:), ContactLimit(:), LocalNormalDisplacement(:), &
       LocalContactPressure(:), PreStress(:,:), PreStrain(:,:), &
       StressLoad(:,:), StrainLoad(:,:)

     SAVE MASS,DAMP, STIFF,LOAD, &
       FORCE,ElementNodes,DampCoeff,SpringCoeff,Beta,Density, Damping, &
       LocalTemperature,AllocationsDone,ReferenceTemperature,BoundaryDispl, &
       ElasticModulus, PoissonRatio,HeatExpansionCoeff, VonMises, NodalStress, &
       CalcStress, CalcStressAll, NodalDisplacement, Contact, ContactPressure, &
       NormalDisplacement, ContactLimit, LocalNormalDisplacement, &
       LocalContactPressure, PreStress, PreStrain, StressLoad, StrainLoad, Work, &
       RotateC, TransformMatrix, body_id
!------------------------------------------------------------------------------
     INTEGER :: NumberOfBoundaryNodes, DIM
     INTEGER, POINTER :: BoundaryReorder(:)

     REAL(KIND=dp) :: Bu,Bv,Bw,RM(3,3)
     REAL(KIND=dp), POINTER :: BoundaryNormals(:,:), &
         BoundaryTangent1(:,:), BoundaryTangent2(:,:)

     REAL(KIND=dp) :: LumpedArea, LumpedCenter(3), LumpedMoments(3,3)

     SAVE NumberOfBoundaryNodes,BoundaryReorder,BoundaryNormals, &
              BoundaryTangent1, BoundaryTangent2

     REAL(KIND=dp) :: at,at0,CPUTime,RealTime

     INTERFACE
        FUNCTION StressBoundaryResidual( Model,Edge,Mesh,Quant,Perm, Gnorm ) RESULT(Indicator)
          USE Types
          TYPE(Element_t), POINTER :: Edge
          TYPE(Model_t) :: Model
          TYPE(Mesh_t), POINTER :: Mesh
          REAL(KIND=dp) :: Quant(:), Indicator(2), Gnorm
          INTEGER :: Perm(:)
        END FUNCTION StressBoundaryResidual

        FUNCTION StressEdgeResidual( Model,Edge,Mesh,Quant,Perm ) RESULT(Indicator)
          USE Types
          TYPE(Element_t), POINTER :: Edge
          TYPE(Model_t) :: Model
          TYPE(Mesh_t), POINTER :: Mesh
          REAL(KIND=dp) :: Quant(:), Indicator(2)
          INTEGER :: Perm(:)
        END FUNCTION StressEdgeResidual

        FUNCTION StressInsideResidual( Model,Element,Mesh,Quant,Perm, Fnorm ) RESULT(Indicator)
          USE Types
          TYPE(Element_t), POINTER :: Element
          TYPE(Model_t) :: Model
          TYPE(Mesh_t), POINTER :: Mesh
          REAL(KIND=dp) :: Quant(:), Indicator(2), Fnorm
          INTEGER :: Perm(:)
        END FUNCTION StressInsideResidual
     END INTERFACE
!------------------------------------------------------------------------------
     CHARACTER(LEN=MAX_NAME_LEN) :: VersionID = "$Id: StressSolve.f90,v 1.120 2005/04/19 08:53:48 jpr Exp $"

!------------------------------------------------------------------------------
!    Check if version number output is requested
!------------------------------------------------------------------------------
     IF ( .NOT. AllocationsDone ) THEN
        IF ( ListGetLogical( GetSimulation(), 'Output Version Numbers', Found ) ) THEN
           CALL Info( 'StressSolve', 'StressSolver version:', Level = 0 ) 
           CALL Info( 'StressSolve', VersionID, Level = 0 ) 
           CALL Info( 'StressSolve', ' ', Level = 0 ) 
        END IF
     END IF

     DIM = CoordinateSystemDimension()
!------------------------------------------------------------------------------
!    Get variables needed for solution
!------------------------------------------------------------------------------
     IF ( .NOT. ASSOCIATED( Solver % Matrix ) ) RETURN

     SolverParams => GetSolverParams()

     StressSol => Solver % Variable
     DisplPerm      => StressSol % Perm
     STDOFs         =  StressSol % DOFs
     Displacement   => StressSol % Values

     IF ( COUNT( DisplPerm > 0 ) <= 0 ) RETURN

     TempSol => VariableGet( Solver % Mesh % Variables, 'Temperature' )
     IF ( ASSOCIATED( TempSol) ) THEN
       TempPerm    => TempSol % Perm
       Temperature => TempSol % Values
     END IF

     MeshDisplacementActive = ListGetLogical( Solver % Values,  &
               'Displace Mesh', Found )
     IF ( .NOT. Found ) MeshDisplacementActive = .TRUE.

     IF ( AllocationsDone .AND. MeshDisplacementActive ) THEN
        CALL DisplaceMesh( Solver % Mesh, Displacement, -1, DisplPerm, STDOFs )
     END IF

     UNorm = Solver % Variable % Norm
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
!     Allocate some permanent storage, this is done first time only
!------------------------------------------------------------------------------
     IF ( .NOT. AllocationsDone .OR. Solver % Mesh % Changed) THEN
       N = Model % MaxElementNodes

       IF ( AllocationsDone ) THEN
         DEALLOCATE( ElementNodes % x,     &
                     ElementNodes % y,     &
                     ElementNodes % z,     &
                     BoundaryDispl,        &
                     Density,              &
                     Damping,              &
                     DampCoeff,            &
                     SpringCoeff,          &
                     ReferenceTemperature, &
                     HeatExpansionCoeff,   &
                     LocalTemperature,     &
                     ElasticModulus,       &
                     PoissonRatio,         &
                     PreStress, PreStrain, &
                     StressLoad, StrainLoad, &
                     NodalDisplacement,      &
                     FORCE, MASS, DAMP, STIFF, LOAD, Beta, &
                     ContactLimit, LocalNormalDisplacement, LocalContactPressure, &
                     TransformMatrix )
       END IF

       ALLOCATE( ElementNodes % x( N ),     &
                 ElementNodes % y( N ),     &
                 ElementNodes % z( N ),     &
                 BoundaryDispl( N ),        &
                 Density( N ),              &
                 Damping( N ),              &
                 DampCoeff( N ),            &
                 PreStress( 6,N ),          &
                 PreStrain( 6,N ),          &
                 StressLoad( 6,N ),         &
                 StrainLoad( 6,N ),         &
                 SpringCoeff( N ),          &
                 ReferenceTemperature( N ), &
                 HeatExpansionCoeff( 3,3,N ), &
                 LocalTemperature( N ),       &
                 ElasticModulus(6,6,N),       &
                 PoissonRatio( N ),           &
                 FORCE( STDOFs*N ),           &
                 MASS(  STDOFs*N,STDOFs*N ),  &
                 DAMP(  STDOFs*N,STDOFs*N ),  &
                 STIFF( STDOFs*N,STDOFs*N ),  &
                 NodalDisplacement( 3, N ),   &
                 LOAD( 4,N ), Beta( N ),      &
                 ContactLimit(N), LocalNormalDisplacement(N), &
                 LocalContactPressure(N),     &
                 TransformMatrix(3,3),  STAT=istat )


       NULLIFY( Work )

       TransformMatrix = 0.0d0

       IF ( .NOT. AllocationsDone ) THEN
          CalcStressAll = GetLogical( SolverParams, 'Calculate Stresses',Found )

          CalcStress = .FALSE.
          DO i=1,Model % NumberOfEquations
             CalcStress = CalcStress .OR. GetLogical( &
                 Model % Equations(i) % Values, 'Calculate Stresses', Found )

             IF ( .NOT. Found .AND. CalcStressAll ) THEN
                CALL ListAddLogical( &
                    Model % Equations(i) % Values, 'Calculate Stresses', .TRUE. )
             END IF
          END DO

          IF ( CalcStress .OR. CalcStressAll ) THEN
             PSolver => Solver
             n = SIZE( Displacement ) / STDOFs
             ALLOCATE( NodalStress( 6*n ) )
             CALL VariableAdd(Solver % Mesh % Variables, Solver % Mesh, PSolver, &
                         'Stress', 6, NodalStress, DisplPerm )

             DO i=1,6
                StressComp => NodalStress(i::6)
                CALL VariableAdd(Solver % Mesh % Variables,Solver % Mesh,PSolver, &
                   'Stress '//CHAR(i+ICHAR('0')), 1, StressComp, DisplPerm )
             END DO

             ALLOCATE( VonMises( n ) )
             CALL VariableAdd(Solver % Mesh % Variables, Solver % Mesh, PSolver, &
                         'VonMises', 1, VonMises, DisplPerm )
          END IF

          Contact = GetLogical( SolverParams, 'Contact', Found )
          IF( Contact ) THEN
             PSolver => Solver
             n = SIZE( Displacement ) / STDOFs
             ALLOCATE( ContactPressure( n ), NormalDisplacement( n ) )
             ContactPressure = 0.0d0
             NormalDisplacement = 0.0d0
             CALL VariableAdd(Solver % Mesh % Variables, Solver % Mesh, PSolver, &
                  'Contact Pressure', 1, ContactPressure, DisplPerm )
          END IF

       END IF

       IF ( istat /= 0 ) THEN
          CALL Fatal( 'StressSolve', 'Memory allocation error.' )
       END IF

!------------------------------------------------------------------------------
!    Check for normal/tangetial coordinate system defined velocities
!------------------------------------------------------------------------------
       CALL CheckNormalTangentialBoundary( Model, &
        'Normal-Tangential Displacement',NumberOfBoundaryNodes, &
          BoundaryReorder, BoundaryNormals, BoundaryTangent1, &
             BoundaryTangent2, DIM )
!------------------------------------------------------------------------------

       AllocationsDone = .TRUE.
     END IF

!------------------------------------------------------------------------------
!    Do some additional initialization, and go for it
!------------------------------------------------------------------------------
     IF ( CalcStress .OR. CalcStressAll ) THEN
        Var => VariableGet( Solver % Mesh % Variables, 'VonMises', .TRUE. )
        VonMises => Var % Values
        Var => VariableGet( Solver % Mesh % Variables, 'Stress', .TRUE. )
        StressPerm  => Var % Perm
        NodalStress => Var % Values
     END IF

!------------------------------------------------------------------------------
     NonlinearTol = GetConstReal( SolverParams, &
        'Nonlinear System Convergence Tolerance', Found )

     NewtonTol = GetConstReal( SolverParams, &
        'Nonlinear System Newton After Tolerance', Found )

     NewtonIter = GetInteger( SolverParams, &
        'Nonlinear System Newton After Iterations', Found )

     MaxIter = GetInteger( SolverParams, &
         'Nonlinear System Max Iterations',Found )
     IF ( .NOT.Found ) MaxIter = 1

     MinIter = GetInteger( SolverParams, &
         'Nonlinear System Min Iterations',Found )


     EigenAnalysis = GetLogical( SolverParams, 'Eigen Analysis', Found )
     OrigEigenAnalysis = EigenAnalysis

     StabilityAnalysis = GetLogical( SolverParams, 'Stability Analysis', Found )
     IF( .NOT. Found ) StabilityAnalysis = .FALSE.

     IF( StabilityAnalysis .AND. (CurrentCoordinateSystem() /= Cartesian) ) &
         CALL Fatal( 'StressSolve', &
          'Only cartesian coordinate system is allowed in stability analysis.' )

     GeometricStiffness = GetLogical( SolverParams, 'Geometric Stiffness', Found )
     IF (.NOT. Found ) GeometricStiffness = .FALSE.

     IF( GeometricStiffness .AND. (CurrentCoordinateSystem() /= Cartesian) ) &
          CALL Fatal( 'StressSolve', &
          'Only cartesian coordinates are allowed with geometric stiffness.' )

     IF ( StabilityAnalysis .AND. GeometricStiffness )  &
          CALL Fatal( 'StressSolve', &
          'Stability analysis and geometric stiffening can not be activated simultaneously.' )

     IF ( StabilityAnalysis .OR. GeometricStiffness ) THEN
       MinIter = 2
       MaxIter = 2
     END IF

     ModelLumping = GetLogical( SolverParams, 'Model Lumping', Found )
     IF ( ModelLumping ) THEN       
       FixDisplacement = GetLogical( SolverParams, 'Fix Displacement')
       IF(DIM /= 3) CALL Fatal('StressSolve','Model Lumping implemented only for 3D')
!       MaxIter = 6
!       MinIter = MaxIter
       CALL CoordinateIntegrals(LumpedArea, LumpedCenter, LumpedMoments, &
            Model % MaxElementNodes)
     END IF

!------------------------------------------------------------------------------

     NormalTangential = NumberOfBoundaryNodes > 0
     DO iter=1,MaxIter
       IF( StabilityAnalysis .OR. GeometricStiffness ) THEN
          SELECT CASE( iter )
          CASE( 1 )
            EigenAnalysis = .FALSE.
          CASE DEFAULT
            EigenAnalysis = OrigEigenAnalysis
          END SELECT
          CALL ListAddLogical( SolverParams, 'Eigen Analysis', EigenAnalysis )
       END IF

       at  = CPUTime()
       at0 = RealTime()

       CALL Info( 'StressSolve', ' ', Level=4 )
       CALL Info( 'StressSolve', ' ', Level=4 )
       CALL Info( 'StressSolve', '-------------------------------------',Level=4 )
       WRITE( Message, * ) 'DISPLACEMENT SOLVER ITERATION', iter
       CALL Info( 'StressSolve', Message,Level=4 )
       CALL Info( 'StressSolve', '-------------------------------------',Level=4 )
       CALL Info( 'StressSolve', ' ', Level=4 )
       CALL Info( 'StressSolve', 'Starting assembly...',Level=4 )
!------------------------------------------------------------------------------
!      Compute average normals for boundaries having the normal & tangential
!      field components specified on the boundaries
!------------------------------------------------------------------------------
       IF ( iter == 1 .AND. NormalTangential ) THEN
          CALL AverageBoundaryNormals( Model, &
               'Normal-Tangential Displacement', NumberOfBoundaryNodes, &
            BoundaryReorder, BoundaryNormals, BoundaryTangent1, &
               BoundaryTangent2, DIM )
       END IF
!------------------------------------------------------------------------------

       CALL DefaultInitialize()

       body_id = -1
!------------------------------------------------------------------------------
       DO t=1,Solver % NumberOFActiveElements

         IF ( RealTime() - at0 > 1.0 ) THEN
           WRITE(Message,'(a,i3,a)' ) '   Assembly: ', INT(100.0 - 100.0 * &
            (Solver % NumberOfActiveElements-t) / &
               (1.0*Solver % NumberOfActiveElements)), ' % done'
                       
           CALL Info( 'StressSolve', Message, Level=5 )
           at0 = RealTime()
         END IF

!------------------------------------------------------------------------------

         Element => GetActiveElement(t)
         n = GetElementNOFNOdes()

         NodeIndexes => Element % NodeIndexes
         CALL GetElementNodes( ElementNodes )

         Equation => GetEquation()
         PlaneStress = GetLogical( Equation, 'Plane Stress',Found )

         Material => GetMaterial()
         Density(1:n) = GetReal( Material, 'Density', Found )
         IF ( .NOT. Found )  CALL Fatal( 'StressSolve', &
             'No value for density found' )
         Damping(1:n) = GetReal( Material, 'Damping', Found )

         CALL InputTensor( HeatExpansionCoeff, Isotropic,  &
             'Heat Expansion Coefficient', Material, n, NodeIndexes )

         CALL InputTensor( ElasticModulus, Isotropic, &
             'Youngs Modulus', Material, n, NodeIndexes )

         PoissonRatio = 0.0d0
         IF ( Isotropic )  PoissonRatio(1:n) = GetReal( Material, 'Poisson Ratio' )

         ReferenceTemperature(1:n) = GetReal(Material, &
               'Reference Temperature', Found )

         PreStress = 0.0d0
         PreStrain = 0.0d0
         CALL ListGetRealArray( Material, 'Stress', Work, n, NodeIndexes, Found )
         IF ( Found ) THEN
            k = SIZE(Work,1)
            PreStress(1:k,1:n) = Work(1:k,1,1:n)
         END IF
         CALL ListGetRealArray( Material, 'Strain', Work, n, NodeIndexes, Found )
         IF ( Found ) THEN
            k = SIZE(Work,1)
            PreStrain(1:k,1:n) = Work(1:k,1,1:n)
         END IF

         ! Check need for elasticity matrix rotation:
         !-------------------------------------------
         IF ( Element % BodyId /= body_id ) THEN
           body_id = Element % BodyId
           RotateC = GetLogical( Material, 'Rotate Elasticity Tensor', stat )

           IF ( RotateC ) THEN
              CALL GetConstRealArray( Material, UWrk, &
                  'Material Coordinates Unit Vector 1', stat, Element )
              IF ( stat ) THEN
                Unit1(1:3) = UWrk(1:3,1)
              ELSE
                Unit1(1:3) = (/ 1.0d0, 0.0d0, 0.0d0 /)
              END IF

              UnitNorm = SQRT( SUM( Unit1(1:3) * Unit1(1:3) ) )
              IF ( UnitNorm > 0.0001 )  Unit1 = Unit1 / UnitNorm

              CALL GetConstRealArray( Material, UWrk, &
                  'Material Coordinates Unit Vector 2', stat2, Element )
              IF ( stat2 ) THEN
                Unit2(1:3) = UWrk(1:3,1)
              ELSE
                Unit2(1:3) = (/ 0.0d0, 1.0d0, 0.0d0 /)
              END IF

              UnitNorm = SQRT( SUM( Unit2(1:3) * Unit2(1:3) ) )
              IF ( UnitNorm > 0.0001 )  Unit2 = Unit2 / UnitNorm

              CALL GetConstRealArray( Material, UWrk, &
                  'Material Coordinates Unit Vector 3', stat3, Element )
              IF ( stat3 ) THEN
                Unit3(1:3) = UWrk(1:3,1)
              ELSE
                Unit3(1:3) = (/ 0.0d0, 0.0d0, 1.0d0 /)
              END IF

              UnitNorm = SQRT( SUM( Unit3(1:3) * Unit3(1:3) ) )
              IF ( UnitNorm > 0.0001 )  Unit3 = Unit3/UnitNorm

              IF ( stat .OR. stat2 .OR. stat3 ) THEN
                DO i = 1, 3
                  TransformMatrix(1,i) = Unit1(i)
                  TransformMatrix(2,i) = Unit2(i)
                  TransformMatrix(3,i) = Unit3(i)
                END DO
              ELSE
                CALL Info( 'StressSolver', &
                    'No unit vectors found. Skipping rotation of C', LEVEL=8 )
              END IF
            END IF
          END IF

         ! Set body forces:
         !-----------------
         BodyForce => GetBodyForce()
         LOAD = 0.0D0
         StressLoad = 0.0d0
         StrainLoad = 0.0d0
         IF ( ASSOCIATED( BodyForce ) ) THEN
           LOAD(1,1:n)  = GetReal( BodyForce, 'Stress Bodyforce 1', Found )
           LOAD(2,1:n)  = GetReal( BodyForce, 'Stress Bodyforce 2', Found )
           LOAD(3,1:n)  = GetReal( BodyForce, 'Stress Bodyforce 3', Found )
           LOAD(4,1:n)  = GetReal( BodyForce, 'Stress Pressure', Found )

           CALL ListGetRealArray( BodyForce, 'Stress', Work, n, NodeIndexes, Found )
           IF ( Found ) THEN
              k = SIZE(Work,1)
              StressLoad(1:k,1:n) = Work(1:k,1,1:n)
           END IF

           CALL ListGetRealArray( BodyForce, 'Strain', Work, n, NodeIndexes, Found )
           IF ( Found ) THEN
              k = SIZE(Work,1)
              StrainLoad(1:k,1:n) = Work(1:k,1,1:n)
           END IF
         END IF

         ! Get element local stiffness & mass matrices:
         !---------------------------------------------
         CALL GetVectorLocalSolution( NodalDisplacement )
         CALL GetScalarLocalSolution( LocalTemperature, 'Temperature' )

         SELECT CASE( CurrentCoordinateSystem() )
         CASE( Cartesian, AxisSymmetric, CylindricSymmetric )
            CALL StressCompose( MASS, DAMP, STIFF, FORCE, LOAD, ElasticModulus, &
               PoissonRatio, Density, Damping, PlaneStress, Isotropic,          &
               PreStress, PreStrain, StressLoad, StrainLoad, HeatExpansionCoeff,&
               LocalTemperature, Element, n, ElementNodes, StabilityAnalysis    &
               .AND. iter>1, GeometricStiffness .AND. iter>1, NodalDisplacement, &
               RotateC, TransformMatrix )

         CASE DEFAULT
            CALL StressGeneralCompose( MASS, STIFF,FORCE, LOAD, ElasticModulus, &
               PoissonRatio,Density,PlaneStress,Isotropic,HeatExpansionCoeff,   &
               LocalTemperature, Element,n,ElementNodes )
         END SELECT
!------------------------------------------------------------------------------
!        If time dependent simulation, add mass matrix to global 
!        matrix and global RHS vector
!------------------------------------------------------------------------------
         IF ( TransientSimulation .AND. Solver % NOFEigenValues <= 0 )  THEN
            CALL Default2ndOrderTime( MASS, DAMP, STIFF, FORCE )
         END IF
!------------------------------------------------------------------------------
!        If boundary fields have been defined in normal/tangential
!        coordinate systems, we�ll have to rotate the matrix & force vector
!        to that coordinate system
!------------------------------------------------------------------------------
         IF ( NormalTangential ) THEN
            CALL RotateMatrix( STIFF,FORCE,n,STDOFs,STDOFs, &
             BoundaryReorder(NodeIndexes),BoundaryNormals,BoundaryTangent1, &
                               BoundaryTangent2 )
         END IF
!------------------------------------------------------------------------------
!        Update global matrices from local matrices 
!------------------------------------------------------------------------------
         CALL DefaultUpdateEquations( STIFF, FORCE )

         IF ( Solver % NOFEigenValues > 0 ) THEN
            CALL DefaultUpdateMass( MASS )
            CALL DefaultUpdateDamp( DAMP )
         END IF
!------------------------------------------------------------------------------
      END DO

      CALL Info( 'StressSolve', 'Assembly done', Level=4 )

!------------------------------------------------------------------------------
!     Neumann & Newton boundary conditions
!------------------------------------------------------------------------------
      DO t = 1, Solver % Mesh % NumberOfBoundaryElements

        Element => GetBoundaryElement(t)
        IF ( .NOT. ActiveBoundaryElement() .OR. GetElementFamily() == 1 ) CYCLE
        n = GetElementNOFNodes()

        BC => GetBC()
        IF ( ASSOCIATED( BC ) ) THEN
!------------------------------------------------------------------------------
           CALL GetElementNodes( ElementNodes )

           LOAD  = 0.0d0
           Beta  = 0.0d0
           DampCoeff   = 0.0d0
           SpringCoeff = 0.0d0
!------------------------------------------------------------------------------
!          Force in given direction BC: \tau\cdot n = F
!------------------------------------------------------------------------------
           GotForceBC = .FALSE.
           LOAD(1,1:n) = GetReal( BC, 'Force 1',Found )
           GotForceBC = GotForceBC .OR. Found
           LOAD(2,1:n) = GetReal( BC, 'Force 2',Found )
           GotForceBC = GotForceBC .OR. Found
           LOAD(3,1:n) = GetReal( BC, 'Force 3',Found )
           GotForceBC = GotForceBC .OR. Found
           Beta(1:n) =  GetReal( BC, 'Normal Force',Found )
           GotForceBC = GotForceBC .OR. Found
           CALL ListGetRealArray( BC, 'Stress', Work, &
                   n, NodeIndexes, Found )
           GotForceBC = GotForceBC .OR. Found
           StressLoad = 0.0d0
           IF ( Found ) THEN
              k = SIZE(Work,1)
              StressLoad(1:k,1:n) = Work(1:k,1,1:n)
           END IF
           DampCoeff(1:n) =  GetReal( BC, 'Damping', Found )
           GotForceBC = GotForceBC .OR. Found
           SpringCoeff(1:n) =  GetReal( BC, 'Spring', Found )
           GotForceBC = GotForceBC .OR. Found
           ContactLimit(1:n) =  GetReal( BC, 'Contact Limit', Found )
           GotForceBC = GotForceBC .OR. Found

           IF(ModelLumping .AND. .NOT. FixDisplacement) THEN
             IF(GetLogical( BC, 'Model Lumping Boundary',Found )) THEN
               CALL LumpedLoads( iter, LumpedArea, LumpedCenter, LumpedMoments, Load )
               GotForceBC = .TRUE.
             END IF
           END IF

           IF ( .NOT. GotForceBC ) CYCLE
!---------------------------------------------------------------------------
           IF( Contact ) THEN
              CALL GetScalarLocalSolution( LocalContactPressure, 'Contact Pressure' )
              Beta = Beta - LocalContactPressure
           END IF 

           SELECT CASE( CurrentCoordinateSystem() )
           CASE( Cartesian, AxisSymmetric, CylindricSymmetric )
              CALL StressBoundary( STIFF,DAMP,FORCE,LOAD,SpringCoeff,DampCoeff, &
                Beta, StressLoad, NormalTangential, Element,n,ElementNodes )
           CASE DEFAULT
              DAMP = 0.0d0
              CALL StressGeneralBoundary( STIFF,FORCE, LOAD, SpringCoeff,Beta, &
                              Element,n,ElementNodes )
           END SELECT

           IF ( TransientSimulation .AND. Solver % NOFEigenValues <= 0 )  THEN
              MASS = 0.0d0
              CALL Default2ndOrderTime( MASS, DAMP, STIFF, FORCE )
           END IF
!------------------------------------------------------------------------------
!          If boundary fields have been defined in normal/tangetial coordinate
!          systems, we�ll have to rotate the matrix & force vector to that
!          coordinate system
!---------------------------------------------------------------------------
           IF ( NormalTangential ) THEN
             CALL RotateMatrix( STIFF,FORCE,n,STDOFs,STDOFs, &
              BoundaryReorder(NodeIndexes),BoundaryNormals,BoundaryTangent1, &
                                BoundaryTangent2 )
           END IF
!---------------------------------------------------------------------------
!          Update global matrices from local matrices
!---------------------------------------------------------------------------
           CALL DefaultUpdateEquations( STIFF, FORCE )
           IF ( Solver % NOFEigenValues > 0 ) CALL DefaultUpdateDamp( DAMP )
!------------------------------------------------------------------------------
         END IF
      END DO
!------------------------------------------------------------------------------

      CALL DefaultFinishAssembly()
      CALL DefaultDirichletBCS()
!------------------------------------------------------------------------------
      IF(ModelLumping .AND. FixDisplacement) THEN
        CALL LumpedDisplacements( Model, iter, LumpedArea, LumpedCenter)
      END IF

      CALL Info( 'StressSolve', 'Set boundaries done', Level=4 )

!------------------------------------------------------------------------------
!     Solve the system and check for convergence
!------------------------------------------------------------------------------
      PrevUNorm = UNorm
      UNorm = DefaultSolve()

      IF ( PrevUNorm + UNorm /= 0.0d0 ) THEN
         RelativeChange = 2.0d0 * ABS( PrevUNorm - UNorm) / ( PrevUnorm + UNorm)
      ELSE
         RelativeChange = 0.0d0
      END IF

      WRITE( Message, * ) 'Result Norm   : ',UNorm
      CALL Info( 'StressSolve', Message, Level=4 )
      WRITE( Message, * ) 'Relative Change : ',RelativeChange
      CALL Info( 'StressSolve', Message, Level=4 )
!------------------------------------------------------------------------------
!     If boundary fields have been defined in normal/tangential coordinate
!     systems, we�ll have to rotate the solution back to coordinate axis
!     directions
!------------------------------------------------------------------------------
      IF ( NumberOfBoundaryNodes > 0 ) THEN
        DO i=1,SIZE( Displperm )
          k = BoundaryReorder(i)

          IF ( k > 0 ) THEN
            j = DisplPerm(i)

            IF ( j > 0 ) THEN
              IF ( STDOFs < 3 ) THEN
                Bu = Displacement( STDOFs*(j-1)+1 )
                Bv = Displacement( STDOFs*(j-1)+2 )

                Displacement( STDOFs*(j-1)+1) = BoundaryNormals(k,1) * Bu - &
                                BoundaryNormals(k,2) * Bv

                Displacement( STDOFs*(j-1)+2) = BoundaryNormals(k,2) * Bu + &
                                BoundaryNormals(k,1) * Bv
              ELSE
                Bu = Displacement( STDOFs*(j-1)+1 )
                Bv = Displacement( STDOFs*(j-1)+2 )
                Bw = Displacement( STDOFs*(j-1)+3 )

                RM(1,:) = BoundaryNormals(k,:)
                RM(2,:) = BoundaryTangent1(k,:)
                RM(3,:) = BoundaryTangent2(k,:)

                Displacement(STDOFs*(j-1)+1) = RM(1,1)*Bu+RM(2,1)*Bv+RM(3,1)*Bw
                Displacement(STDOFs*(j-1)+2) = RM(1,2)*Bu+RM(2,2)*Bv+RM(3,2)*Bw
                Displacement(STDOFs*(j-1)+3) = RM(1,3)*Bu+RM(2,3)*Bv+RM(3,3)*Bw
              END IF
            END IF
          END IF
        END DO 
      END IF

!------------------------------------------------------------------------------
!     Update contact pressure:
!------------------------------------------------------------------------------
      IF( Contact ) THEN
         CALL ComputeNormalDisplacement( Displacement, &
              NormalDisplacement, DisplPerm, STDOFs )
         
         UzawaParameter = GetConstReal( SolverParams, 'Uzawa Parameter', Found )
         IF( .NOT.Found ) THEN
            WRITE( Message, * ) 'Using default value 1.0 for Uzawa parameter'
            CALL Info( 'StressSolve', Message, Level=4 )
            UzawaParameter = 1.0d0
         END IF
         
         ContactPressure = MAX( 0.0d0, ContactPressure &
              + UzawaParameter * NormalDisplacement )
      END IF

!------------------------------------------------------------------------------
      IF ( RelativeChange < NewtonTol .OR. &
             iter > NewtonIter ) NewtonLinearization = .TRUE.

      IF ( Iter > MinIter .AND. RelativeChange < NonLinearTol ) EXIT
!------------------------------------------------------------------------------

      IF ( CalcStress .OR. CalcStressAll ) THEN
         IF( StabilityAnalysis .AND. Iter == 1 ) THEN
            CALL ComputeStress( Displacement, NodalStress,  &
                   VonMises, DisplPerm, StressPerm )
            CALL InvalidateVariable( Model % Meshes, Solver % Mesh, 'Stress' )
            CALL InvalidateVariable( Model % Meshes, Solver % Mesh, 'VonMises' )
         END IF
      END IF

      IF( ModelLumping ) THEN
        CALL LumpedSprings(iter,LumpedArea, LumpedCenter, LumpedMoments, &
            Model % MaxElementNodes)
      END IF

    END DO ! of nonlinear iter
!------------------------------------------------------------------------------

    IF ( CalcStress .OR. CalcStressAll ) THEN
       IF( .NOT. StabilityAnalysis ) THEN
          CALL ComputeStress( Displacement, NodalStress, &
                VonMises, DisplPerm, StressPerm )
          CALL InvalidateVariable( Model % Meshes, Solver % Mesh, 'Stress' )
          CALL InvalidateVariable( Model % Meshes, Solver % Mesh, 'VonMises' )
       END IF
    END IF

    IF ( GetLogical( SolverParams, 'Adaptive Mesh Refinement', Found) ) THEN
       CALL RefineMesh( Model, Solver, Displacement, DisplPerm, &
            StressInsideResidual, StressEdgeResidual, StressBoundaryResidual )

       IF ( MeshDisplacementActive ) THEN
         StressSol => Solver % Variable
          IF ( .NOT.ASSOCIATED( Solver % Mesh, Model % Mesh ) ) &
            CALL DisplaceMesh( Solver % Mesh, StressSol % Values, 1, &
                StressSol % Perm, StressSol % DOFs,.FALSE.)
       END IF
    END IF
 
    IF ( MeshDisplacementActive ) THEN
       CALL DisplaceMesh(Model % Mesh, Displacement, 1, &
               DisplPerm, STDOFs, .FALSE. )
    END IF

CONTAINS

!------------------------------------------------------------------------------
  SUBROUTINE ComputeNormalDisplacement( Displacement, NormalDisplacement, &
       DisplPerm, STDOfs )
!------------------------------------------------------------------------------
    INTEGER :: DisplPerm(:), STDOfs
    REAL(KIND=dp) :: Displacement(:), NormalDisplacement(:)
!------------------------------------------------------------------------------
    INTEGER, PARAMETER :: MaxNodes = 100
    TYPE( Element_t ), POINTER :: Element
    TYPE( Nodes_t ) :: ElementNodes
    TYPE( ValueList_t ), POINTER :: BC
    REAL( KIND=dp ) :: Normal(3), LocalDisplacement(3), U, V
    REAL( KIND=dp ) :: ContactLimit( MaxNodes )
    INTEGER :: i, j, k, t, n
    LOGICAL :: ContactBoundary, Found
    INTEGER, POINTER :: Visited(:)

    ALLOCATE( Visited(SIZE(DisplPerm)) )
    Visited = 0

    NormalDisplacement = 0.0d0

    DO t = 1, Solver % Mesh % NumberOfBoundaryElements
       Element => GetBoundaryElement(t)
       IF ( .NOT. ActiveBoundaryElement() .OR. GetElementFamily() == 1 ) CYCLE
       n = GetElementNOFNodes()
       BC => GetBC()
       
       IF ( ASSOCIATED( BC ) ) THEN
          ContactBoundary = GetLogical( BC, 'Contact Boundary', Found ) 
          IF( .NOT.Found .OR. .NOT.ContactBoundary ) CYCLE
!------------------------------------------------------------------------------
          ContactLimit(1:n) =  GetReal( BC, 'Contact Limit', Found )
          IF( .NOT.Found ) ContactLimit = 9.9d9
             
          CALL GetElementNodes( ElementNodes )
          
          DO i = 1,n
             U = Element % TYPE % NodeU(i)
             V = Element % TYPE % NodeV(i)
             
             Normal = NormalVector( Element, ElementNodes, U, V, .TRUE. )    
             k = DisplPerm( Element % NodeIndexes(i) )
             
             LocalDisplacement = 0.0d0
             DO j = 1,STDOFs
                LocalDisplacement( j ) = Displacement( STDOFs*(k-1)+j )
             END DO
             
             NormalDisplacement( k ) = NormalDisplacement( k ) & 
                  + SUM( Normal(1:3) * LocalDisplacement(1:3) ) - ContactLimit(i)

             Visited( k ) = Visited( k ) + 1
             
          END DO
!------------------------------------------------------------------------------
       END IF
    END DO
!------------------------------------------------------------------------------
    WHERE( Visited >= 1 ) NormalDisplacement = NormalDisplacement / Visited

    DEALLOCATE( Visited )
!------------------------------------------------------------------------------
  END SUBROUTINE ComputeNormalDisplacement
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   SUBROUTINE ComputeStress( Displacement, NodalStress, &
                 VonMises, DisplPerm, StressPerm )
!------------------------------------------------------------------------------
     INTEGER :: DisplPerm(:)
     INTEGEr, POINTER :: StressPerm(:)
     REAL(KIND=dp) :: VonMises(:), NodalStress(:), Displacement(:)
!------------------------------------------------------------------------------
     TYPE(Nodes_t) :: Nodes
     INTEGER :: n,nd
     TYPE(Element_t), POINTER :: Element

     INTEGER :: i,j,k,l,p,q, t, dim,elem, IND(9), BodyId,EqId
     LOGICAL :: stat, CSymmetry, Isotropic, ComputeFlag
     INTEGER, POINTER :: Visited(:), Indexes(:), Permutation(:)
     REAL(KIND=dp) :: u,v,w,x,y,z,Strain(3,3),Stress(3,3),LGrad(3,3),detJ, &
            Young, Poisson, Ident(3,3), C(6,6), S(6), weight, st, Work(9), Principal(3)
     REAL(KIND=dp), ALLOCATABLE :: Basis(:),dBasisdx(:,:),  FORCE(:), ForceG(:), &
        ddBasisddx(:,:,:), SBasis(:,:), LocalDisplacement(:,:), MASS(:,:)

     REAL(KIND=dp), POINTER :: StressTemp(:)

     TYPE(Solver_t), POINTER :: StSolver
     LOGICAL :: FirstTime = .TRUE., OptimizeBW

     TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff

     SAVE Nodes, StSolver, ForceG, Permutation
!------------------------------------------------------------------------------

     dim = CoordinateSystemDimension()

     n = MAX( Solver % Mesh % MaxElementDOFs, Solver % Mesh % MaxElementNodes )
     ALLOCATE( Indexes(n), LocalDisplacement(3,n) )
     ALLOCATE( MASS(n,n), FORCE(6*n) )
     ALLOCATE( Basis(n), dBasisdx(n,3), ddBasisddx(n,3,3) )

     IF ( FirstTime .OR. Solver % Mesh % Changed ) THEN
       IF ( FirstTime ) THEN
         ALLOCATE( StSolver )
       ELSE
         DEALLOCATE( ForceG )
         CALL FreeMatrix( StSolver % Matrix )
       END IF

       StSolver = Solver
       StSolver % Variable => VariableGet( StSolver % Mesh % Variables, &
                  'StressTemp', ThisOnly=.TRUE. )
       IF ( ASSOCIATED( StSolver % Variable ) ) THEN
          Permutation => StSolver % Variable % Perm
       ELSE
          ALLOCATE( Permutation( SIZE(Solver % Variable % Perm) ) )
       END IF

       OptimizeBW = GetLogical( StSolver % Values, 'Optimize Bandwidth', Found )
       IF ( .NOT. Found ) OptimizeBW = .TRUE.

       StSolver % Matrix => CreateMatrix( Model, Solver % Mesh, Permutation, &
        1, MATRIX_CRS, OptimizeBW,'Calculate Stresses', GlobalBubbles=.FALSE. )
       ALLOCATE( StSolver % Matrix % RHS(StSolver % Matrix % NumberOfRows) )

       ALLOCATE( ForceG(StSolver % Matrix % NumberOfRows*6) )

       IF ( .NOT. ASSOCIATED( StSolver % Variable ) ) THEN
          ALLOCATE( StressTemp(StSolver % Matrix % NumberOfRows) )
          StressTemp   = 0.0d0
          CALL VariableAdd( StSolver % Mesh % Variables, StSolver % Mesh, StSolver, &
                 'StressTemp', 1, StressTemp, StressPerm, Output=.FALSE. )
          StSolver % Variable => VariableGet( StSolver % Mesh % Variables, 'StressTemp' )
       END IF
       FirstTime = .FALSE.
     END IF

     Model % Solver => StSolver

     Ident = 0.0d0
     DO i=1,3
        Ident(i,i) = 1.0d0
     END DO

     CSymmetry = CurrentCoordinateSystem() == AxisSymmetric .OR. &
                 CurrentCoordinateSystem() == CylindricSymmetric

     IND = (/ 1, 4, 6, 4, 2, 5, 6, 5, 3 /)

     NodalStress  = 0.0d0
     ForceG       = 0.0d0
     CALL DefaultInitialize()

     DO elem = 1,Solver % NumberOfActiveElements
        Element => GetActiveElement(elem, Solver)
        n  = GetElementNOFNodes()
        nd = GetElementDOFs( Indexes )

        Equation => GetEquation()

        ! Check if stresses wanted for this body:
        ! ---------------------------------------
        ComputeFlag = GetLogical( Equation, 'Calculate Stresses', Found )

        IF ( Found .AND. .NOT. ComputeFlag .OR. &
                 .NOT. Found .AND. .NOT. CalcStressAll ) CYCLE

        ! Get material parameters:
        ! ------------------------
        Material => GetMaterial()

        PoissonRatio(1:n) = GetReal( Material, 'Poisson Ratio', Stat )
        CALL InputTensor( ElasticModulus, Isotropic, &
                'Youngs Modulus', Material, n, Element % NodeIndexes )
        PlaneStress = ListGetLogical( Equation, 'Plane Stress', stat )

        ! Element nodal points:
        ! ---------------------
        CALL GetElementNodes( Nodes )

        ! Displacement field at element nodal points:
        ! -------------------------------------------
        CALL GetVectorLocalSolution( LocalDisplacement, USolver=Solver )

        ! Integrate local stresses:
        ! -------------------------
        IntegStuff = GaussPoints( Element )
        Stress = 0.0d0
        MASS   = 0.0d0
        FORCE  = 0.0d0

        DO t=1,IntegStuff % n
          u = IntegStuff % u(t)
          v = IntegStuff % v(t)
          w = IntegStuff % w(t)
          Weight = IntegStuff % s(t)

          stat = ElementInfo( Element, Nodes, u, v, w, detJ, &
             Basis, dBasisdx, ddBasisddx, .FALSE. ,.FALSE. )

          Weight = Weight * detJ
          IF ( CSymmetry ) Weight = Weight * SUM( Basis(1:n) * Nodes % x(1:n) )

          CALL LocalStress( Stress, Strain, PoissonRatio, &
            ElasticModulus, Isotropic, CSymmetry, PlaneStress, &
            LocalDisplacement, Basis, dBasisdx, Nodes, dim, n, nd )

          DO p=1,nd
            DO q=1,nd
              MASS(p,q) = MASS(p,q) + Weight*Basis(q)*Basis(p)
            END DO

            DO i=1,3
            DO j=i,3
              k = Ind( 3*(i-1)+j )
              FORCE(6*(p-1)+k) = FORCE(6*(p-1)+k) + Weight*Stress(i,j)*Basis(p)
            END DO
            END DO
          END DO
        END DO

        CALL DefaultUpdateEquations( MASS, FORCE )

        DO p=1,nd
          l = Permutation(Indexes(p))
          DO i=1,3
          DO j=i,3
             k = Ind(3*(i-1)+j)
             ForceG(6*(l-1)+k) = ForceG(6*(l-1)+k) + FORCE(6*(p-1)+k)
          END DO
          END DO
        END DO
      END DO

      DO i=1,3
      DO j=i,3
        k = IND(3*(i-1)+j)

        StSolver % Matrix % RHS = ForceG(k::6)
        st = DefaultSolve()
        DO l=1,SIZE( Permutation )
          IF ( Permutation(l) > 0 ) THEN
            NodalStress(6*(StressPerm(l)-1)+k) = StSolver % Variable % Values(Permutation(l))
          END IF
        END DO

        IF ( k == 1 ) THEN
          CALL ListAddLogical( StSolver % Values, 'UMF Factorize', .FALSE. )
          CALL ListAddInteger( StSolver % Values, 'Linear System Precondition Recompute', 100 )
        END IF
      END DO
      END DO

      CALL ListAddLogical( StSolver % Values, 'UMF Factorize', .TRUE. )
      CALL ListAddInteger( StSolver % Values, 'Linear System Precondition Recompute', 1 )

      ! Von Mises stress from the component nodal values:
      ! -------------------------------------------------
      VonMises = 0
      DO i=1,SIZE( StressPerm )
         IF ( StressPerm(i) <= 0 ) CYCLE

         p = 0
         DO j=1,3
            DO k=1,3
              p = p + 1
              q = 6 * (StressPerm(i)-1) + IND(p)
              Stress(j,k) = NodalStress(q)
            END DO
         END DO

         Stress(:,:) = Stress(:,:) - TRACE(Stress(:,:),3) * Ident/3

         DO j=1,3
            DO k=1,3
              VonMises(StressPerm(i)) = VonMises(StressPerm(i)) + Stress(j,k)**2
            END DO
         END DO
      END DO

      VonMises = SQRT( 3.0d0 * VonMises / 2.0d0 )

      DEALLOCATE( Basis, dBasisdx, ddBasisddx )
      DEALLOCATE( Indexes, LocalDisplacement, MASS, FORCE )

      Model % Solver => Solver
!------------------------------------------------------------------------------
   END SUBROUTINE ComputeStress
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
   FUNCTION TRACE( F, dim ) RESULT(t)
!------------------------------------------------------------------------------
     INTEGER :: i, dim
     REAL(KIND=dp) :: F(:,:), t

     t = 0.0d0
     DO i=1,dim
        t = t + F(i,i)
     END DO
!------------------------------------------------------------------------------
   END FUNCTION TRACE
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
! Computes area, center of area and different moments
!------------------------------------------------------------------------------
   SUBROUTINE CoordinateIntegrals(Area, Center, Moments, maxnodes)

     REAL(KIND=dp) :: Area, Center(:), Moments(:,:)
     INTEGER :: maxnodes

     REAL(KIND=dp) :: Coords(3)
     INTEGER :: power
     TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff
     REAL(KIND=dp) :: Basis(maxnodes),ddBasisddx(1,1,1)
     REAL(KIND=dp) :: dBasisdx(maxnodes,3),detJ,u,v,w
     REAL(KIND=dp), DIMENSION(:), POINTER :: U_Integ,V_Integ,W_Integ,S_Integ
     INTEGER :: N_Integ
     LOGICAL :: stat

     Area = 0.0
     Center = 0.0
     Moments = 0.0


     ! On the first round compute area and center of area.
     ! On the second round compute the square deviations from the mean.
     
     DO power = 1,2

       DO t=1,Solver % Mesh % NumberOfBoundaryElements
         Element => GetBoundaryElement(t)
         IF ( .NOT. ActiveBoundaryElement() .OR. GetElementFamily() == 1 ) CYCLE
         BC => GetBC()
         IF ( .NOT. ASSOCIATED( BC ) ) CYCLE
!------------------------------------------------------------------------------
         IF(.NOT. GetLogical( BC, 'Model Lumping Boundary',Found )) CYCLE
         
         n = GetElementNOFNodes()
         CALL GetElementNodes( ElementNodes )

         IntegStuff = GaussPoints( Element )
         U_Integ => IntegStuff % u
         V_Integ => IntegStuff % v
         W_Integ => IntegStuff % w
         S_Integ => IntegStuff % s
         N_Integ =  IntegStuff % n
         
         DO k=1,N_Integ
           u = U_Integ(k)
           v = V_Integ(k)
           w = W_Integ(k)
           
           ! Basis function values & derivatives at the integration point:
           !--------------------------------------------------------------
           stat = ElementInfo( Element, ElementNodes, u, v, w, detJ, &
               Basis, dBasisdx, ddBasisddx, .FALSE., .FALSE. )
           
           s = detJ * S_Integ(k)
           IF ( CurrentCoordinateSystem() == AxisSymmetric .OR. &
               CurrentCoordinateSystem() == CylindricSymmetric ) THEN
             s = s * SUM( ElementNodes % x(1:n) * Basis(1:n) )
           END IF
           
           Coords(1) = SUM(Basis(1:n) * ElementNodes % x(1:n))
           IF (DIM > 1) THEN
             Coords(2) =  SUM(Basis(1:n) * ElementNodes % y(1:n))
           END IF
           IF (DIM > 2) THEN
             Coords(3) =  SUM(Basis(1:n) * ElementNodes % z(1:n))
           END IF
           
           IF(power == 1) THEN
             Area = Area + s
             Center(1:DIM) = Center(1:DIM) + s * Coords(1:DIM)
           ELSE
             Coords(1:DIM) = Coords(1:DIM) - Center(1:DIM) 
             DO i = 1,DIM
               DO j = 1,DIM
                 Moments(i,j) = Moments(i,j) + s * Coords(i) * Coords(j)
               END DO
             END DO
           END IF

         END DO
       END DO 
     
       IF(power == 1) Center(1:DIM) = Center(1:DIM) / Area
     END DO

     ! print *,'Area',Area
     ! print *,'Center',Center(1:DIM)
     ! print *,'Moments',Moments(1:DIM,1:DIM)
   END SUBROUTINE CoordinateIntegrals


!------------------------------------------------------------------------------
! Compute the loads resulting to pure forces or pure moments.
! Pure moments may only be computed under certain conditions that 
! should be valid for boundaries with normal in the direction of some axis.
!------------------------------------------------------------------------------

   SUBROUTINE LumpedLoads( Permutation, Area, Center, Moments, Forces )
     INTEGER :: Permutation
     REAL (KIND=dp) :: Area, Center(:), Moments(:,:), Forces(:,:)
     
     REAL (KIND=dp), POINTER :: y(:), z(:)
     REAL (KIND=dp) :: c, Eps
     LOGICAL :: isy, isz
     INTEGER :: ix,iy,iz,nx,ny,nz

     Forces = 0.0d0
     Eps = 1.0d-6

     IF(Permutation <= 3) THEN
       Forces(Permutation,1:n) = 1.0 / LumpedArea
     ELSE IF(Permutation <= 6) THEN
       ix = MOD(Permutation - 4, 3) + 1
       iy = MOD(Permutation - 3, 3) + 1
       iz = MOD(Permutation - 2, 3) + 1

       IF(Permutation == 4) THEN
         z => ElementNodes % Z
         y => ElementNodes % Y
       ELSE IF(Permutation == 5) THEN
         z => ElementNodes % X
         y => ElementNodes % Z
       ELSE IF(Permutation == 6) THEN
         z => ElementNodes % Y
         y => ElementNodes % X
       END IF

       isy = (ABS(Moments(iy,ix)) < Eps * Moments(iy,iy))
       isz = (ABS(Moments(iz,ix)) < Eps * Moments(iz,iz))

!       IF(isy .AND. isz) THEN
!         c = 1.0 / (Moments(iy,iy) + Moments(iz,iz) )
!         Forces(iy,1:n) = -c * (z(1:n) - Center(iz))
!         Forces(iz,1:n) = c * (y(1:n) - Center(iy))
!       ELSE 

       IF(isy) THEN
         c = 1.0 / Moments(iy,iy)
         Forces(iz,1:n) = c * (y(1:n) - Center(iy))
       ELSE IF(isz) THEN
         c = -1.0 / Moments(iz,iz)
         Forces(iy,1:n) = c * (z(1:n) - Center(iz))
       ELSE 
         c = 1.0 / (Moments(iy,iy) + Moments(iz,iz) )
         Forces(iy,1:n) = -c * (z(1:n) - Center(iz))
         Forces(iz,1:n) =  c * (y(1:n) - Center(iy))
         CALL Warn('StressSolve','Moment matrix not diagonalazible!')
         PRINT *,Moments(iy,ix),Moments(iz,ix),Moments(iy,iy),Moments(iz,iz)
       END IF
     END IF
   END SUBROUTINE LumpedLoads


!------------------------------------------------------------------------------
   SUBROUTINE LumpedDisplacements( Model, Permutation, Area, Center )
!------------------------------------------------------------------------------
!  This subroutine is used to set pure translations and rotations to the 
!  chosen boundary in order to perform model lumping.
!------------------------------------------------------------------------------

     TYPE(Model_t) :: Model
     REAL(KIND=dp) :: Area, Center(:)
     INTEGER :: Permutation
!------------------------------------------------------------------------------
     TYPE(Matrix_t), POINTER :: StiffMatrix
     REAL(KIND=dp), POINTER :: ForceVector(:)
     INTEGER, POINTER :: Perm(:)
     TYPE(Element_t), POINTER :: CurrentElement
     INTEGER, POINTER :: NodeIndexes(:)
     INTEGER :: i,j,k,l,n,t,ind
     LOGICAL :: GotIt
     REAL(KIND=dp) :: Coords(3), dCoords(3), dFii, dx, s
    
    !------------------------------------------------------------------------------
    
     StiffMatrix => Solver % Matrix
     ForceVector => StiffMatrix % RHS
     Perm => Solver % Variable % Perm
     
     dX   = 1.0d-2*SQRT(Area)
     dFii = 1.0d-2
     
     DO t = 1, Solver % Mesh % NumberOfBoundaryElements
       Element => GetBoundaryElement(t)
       CurrentElement => Element
       IF ( .NOT. ActiveBoundaryElement()) CYCLE
       n = GetElementNOFNodes()
       
       BC => GetBC()
       IF ( .NOT. ASSOCIATED( BC ) ) CYCLE
       
       IF(.NOT. GetLogical( BC, 'Model Lumping Boundary',Found )) CYCLE

       NodeIndexes => CurrentElement % NodeIndexes
       
       DO j=1,n
         k = Perm(NodeIndexes(j))
         IF(k == 0) CYCLE
         
         dCoords = 0.0d0
         IF(Permutation <= 3) THEN
           dCoords(Permutation) = dX
         ELSE
           Coords(1) = Solver % Mesh % Nodes % x(NodeIndexes(j))
           Coords(2) = Solver % Mesh % Nodes % y(NodeIndexes(j))
           Coords(3) = Solver % Mesh % Nodes % z(NodeIndexes(j))
           Coords = Coords - Center
           IF (Permutation == 4) THEN
             dCoords(2) =  dFii * Coords(3) 
             dCoords(3) = -dFii * Coords(2)
           ELSE IF(Permutation == 5) THEN
             dCoords(1) = -dFii * Coords(3) 
             dCoords(3) =  dFii * Coords(1)
           ELSE IF(Permutation == 6) THEN
             dCoords(1) =  dFii * Coords(2)
             dCoords(2) = -dFii * Coords(1)
           END IF
         END IF

         DO l=1,dim
           ind = dim * (k-1) + l
           IF ( StiffMatrix % Format == MATRIX_SBAND ) THEN
             CALL SBand_SetDirichlet( StiffMatrix,ForceVector,ind,dCoords(l) )             
           ELSE IF ( StiffMatrix % Format == MATRIX_CRS .AND. &
              StiffMatrix % Symmetric ) THEN 
             CALL CRS_SetSymmDirichlet(StiffMatrix,ForceVector,ind,dCoords(l) )
           ELSE
             s = StiffMatrix % Values(StiffMatrix % Diag(ind))
             ForceVector(ind) = dCoords(l) * s
             CALL ZeroRow( StiffMatrix,ind )
             CALL SetMatrixElement( StiffMatrix,ind,ind,1.0d0*s )
           END IF
         END DO
       END DO
     END DO
!------------------------------------------------------------------------------
  END SUBROUTINE LumpedDisplacements
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
! At the end of each iteration assemblys one line of the Kmatrix and finally 
! invert the matrix. The displacements and the springs are taken to be the 
! average values on the surface.
!------------------------------------------------------------------------------
   SUBROUTINE LumpedSprings(Permutation,Area, Center, Moments, maxnodes)
!------------------------------------------------------------------------------
     INTEGER :: Permutation, maxnodes     
     REAL(KIND=dp) :: Area, Center(:), Moments(:,:)
!------------------------------------------------------------------------------
     TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff
     REAL(KIND=dp) :: Basis(maxnodes),ddBasisddx(1,1,1)
     REAL(KIND=dp) :: dBasisdx(maxnodes,3),detJ,u,v,w
     REAL(KIND=dp), DIMENSION(:), POINTER :: U_Integ,V_Integ,W_Integ,S_Integ
     REAL(KIND=dp) :: LocalDisp(DIM,maxnodes),Kmat(6,6),up, vp, wp, &
         xp(maxnodes), yp(maxnodes), zp(maxnodes), KmatMin(6,6), KvecAtIP(6), &
         Strain(3,3),Stress(3,3), dFii, Dx, &
         ForceAtIp(3), MomentAtIp(3), Coord(3)
     INTEGER :: N_Integ, pn
     LOGICAL :: stat, CSymmetry, Isotropic
     CHARACTER(LEN=MAX_NAME_LEN) :: KmatFile
     TYPE(Nodes_t) :: ParentNodes
     TYPE(Element_t),POINTER :: Parent

     SAVE ParentNodes
!------------------------------------------------------------------------------

     n = maxnodes
     ALLOCATE( ParentNodes % x(n), ParentNodes % y(n), ParentNodes % z(n))

     CSymmetry = CurrentCoordinateSystem() == CylindricSymmetric .OR. &
                 CurrentCoordinateSystem() == AxisSymmetric
    
     dFii = 1.0d-2
     dX = 1.0d-2*SQRT(Area)

     IF (Permutation == 1) THEN
       Kmat = 0.0d0       
       KmatMin = HUGE(KmatMin)
     END IF

     DO t = 1, Solver % Mesh % NumberOfBoundaryElements
       Element => GetBoundaryElement(t)
       IF ( .NOT. ActiveBoundaryElement() .OR. GetElementFamily() == 1 ) CYCLE
       
       BC => GetBC()
       IF ( .NOT. ASSOCIATED( BC ) ) CYCLE
       IF(.NOT. GetLogical( BC, 'Model Lumping Boundary',Found )) CYCLE
       
       n = GetElementNOFNodes()
       CALL GetElementNodes( ElementNodes )

       ! Get parent element & nodes:
       ! ---------------------------
       Parent => Element % BoundaryInfo % Left
       stat = ASSOCIATED( Parent )
       IF ( .NOT. stat ) stat = ALL(DisplPerm(Parent % NodeIndexes) > 0)
       IF ( .NOT. stat ) THEN
         Parent => Element % BoundaryInfo % Right
         stat = ASSOCIATED( Parent )
         IF ( stat ) stat = ALL(DisplPerm(Parent % NodeIndexes) > 0)
         IF ( .NOT. stat ) CALL Fatal( 'StressSolve', & 
                      'Cannot find proper parent for side element' )
       END IF
       pn = GetElementNOFNodes( Parent )
       CALL GetElementNodes( ParentNodes, Parent )
       CALL GetVectorLocalSolution( LocalDisp, UElement=Parent )

       IF(FixDisplacement) THEN
         Material => GetMaterial(Parent)
         PoissonRatio(1:pn) = GetReal( Material, 'Poisson Ratio', Stat )
         CALL InputTensor( HeatExpansionCoeff, Isotropic,  &
             'Heat Expansion Coefficient', Material, pn, Parent % NodeIndexes )
         
         CALL InputTensor( ElasticModulus, Isotropic, &
             'Youngs Modulus', Material, pn, Parent % NodeIndexes )
         
         PlaneStress = ListGetLogical( Equation, 'Plane Stress', stat )
       END IF

       ! Get boundary nodal points in parent local coordinates:
       ! ------------------------------------------------------
       DO i = 1,n
         DO j = 1,pn
           IF ( Element % NodeIndexes(i) == Parent % NodeIndexes(j) ) THEN
             xp(i) = Parent % Type % NodeU(j)
             yp(i) = Parent % Type % NodeV(j)
             zp(i) = Parent % Type % NodeW(j)
             EXIT
           END IF
         END DO
       END DO
       

       IntegStuff = GaussPoints( Element )

       U_Integ => IntegStuff % u
       V_Integ => IntegStuff % v
       W_Integ => IntegStuff % w
       S_Integ => IntegStuff % s
       N_Integ =  IntegStuff % n
       
       DO k=1,N_Integ
         u = U_Integ(k)
         v = V_Integ(k)
         w = W_Integ(k)
         
         ! Basis function values & derivatives at the integration point:
         !--------------------------------------------------------------
         stat = ElementInfo( Element, ElementNodes, u, v, w, detJ, &
             Basis, dBasisdx, ddBasisddx, .FALSE., .FALSE. )
         Normal = NormalVector( Element, ElementNodes, U, V, .TRUE. )    

         IF(FixDisplacement) THEN
           Coord(1) = SUM(Basis(1:n) * ElementNodes % x(1:n))
           Coord(2) = SUM(Basis(1:n) * ElementNodes % y(1:n))
           Coord(3) = SUM(Basis(1:n) * ElementNodes % z(1:n))
           Coord = Coord - Center
         END IF

         s = detJ * S_Integ(k)
         IF ( CurrentCoordinateSystem() == AxisSymmetric .OR. &
              CurrentCoordinateSystem() == CylindricSymmetric ) THEN
           s = s * SUM( ElementNodes % x(1:n) * Basis(1:n) )
         END IF
         
         ! The plane  elements only include the  derivatives in the direction
         ! of the plane. Therefore compute the derivatives of the displacemnt
         ! field from the parent element:
         ! -------------------------------------------------------------------
         Up = SUM( xp(1:n) * Basis(1:n) )
         Vp = SUM( yp(1:n) * Basis(1:n) )
         Wp = SUM( zp(1:n) * Basis(1:n) )
 
         stat = ElementInfo( Parent,ParentNodes, Up, Vp, Wp, detJ, &
             Basis, dBasisdx, ddBasisddx, .FALSE., .FALSE. )

         IF(FixDisplacement) THEN
           CALL LocalStress( Stress, Strain, PoissonRatio, &
               ElasticModulus, Isotropic, CSymmetry, PlaneStress,   &
               LocalDisp, Basis, dBasisdx, ParentNodes, DIM, pn )
          
           ForceAtIp = MATMUL( Stress, Normal )
           MomentAtIp(1) = ForceAtIp(2) * Coord(3) - ForceAtIp(3) * Coord(2)
           MomentAtIp(2) = ForceAtIp(3) * Coord(1) - ForceAtIp(1) * Coord(3)
           MomentAtIp(3) = ForceAtIp(1) * Coord(2) - ForceAtIp(2) * Coord(1)

           Kmat(1:3,Permutation) = Kmat(1:3,Permutation) + s * ForceAtIp 
           Kmat(4:6,Permutation) = Kmat(4:6,Permutation) + s * MomentAtIp 

         ELSE           
           DO i=1,DIM
             ForceAtIP(i) = SUM( Basis(1:pn) * LocalDisp(i,1:pn) )
           END DO
           
           MomentAtIP(1) = 0.5 * &
               ( SUM( dBasisdx(1:pn,2) * LocalDisp(3,1:pn)) &
               - SUM( dBasisdx(1:pn,3) * LocalDisp(2,1:pn)) )
           MomentAtIp(2) = 0.5 * &
               ( SUM( dBasisdx(1:pn,3) * LocalDisp(1,1:pn)) &
               - SUM( dBasisdx(1:pn,1) * LocalDisp(3,1:pn)) )
           MomentAtIp(3) = 0.5 * &
               ( SUM( dBasisdx(1:pn,1) * LocalDisp(2,1:pn)) &
               - SUM( dBasisdx(1:pn,2) * LocalDisp(1,1:pn)) )

           Kmat(Permutation,1:3) = Kmat(Permutation,1:3) + s * ForceAtIp
           Kmat(Permutation,4:6) = Kmat(Permutation,4:6) + s * MomentAtIp
           
           DO i = 1,dim
             IF(ABS(KmatMin(Permutation,i)) > ABS(ForceAtIp(i))) THEN
               KmatMin(Permutation,i) = ForceAtIp(i)
             END IF
             IF(ABS(KmatMin(Permutation,i+3)) > ABS(MomentAtIp(i))) THEN
               KmatMin(Permutation,i+3) = MomentAtIp(i)
             END IF
           END DO
         END IF
       END DO
     END DO

     IF(Permutation == 6) THEN
       KmatFile = ListGetString(Solver % Values,'Model Lumping Filename',stat )
       IF(.NOT. stat) KmatFile = "Kmat.dat"

       CALL Info( 'StressSolve', '-----------------------------------------', Level=4 )
       WRITE( Message, * ) 'Saving lumped spring matrix to file ', TRIM(KmatFile)
       CALL Info( 'StressSolve', Message, Level=4 )
       CALL Info( 'StressSolve', '-----------------------------------------', Level=4 )
              
       IF (FixDisplacement) THEN
         Kmat(1:3,:) = Kmat(1:3,:) / dX
         Kmat(4:6,:) = Kmat(4:6,:) / dFii         
       ELSE
         Kmat = Kmat / Area

         ! The minimum of displacement mus always be smaller than
         ! the average displacement of the end.
         DO i=1,6
           DO j=1,6
             IF(ABS(Kmat(i,j)) < ABS(KMatMin(i,j))) KmatMin(i,j) = Kmat(i,j)
           END DO
         END DO

         ! Save the Kmatrix prior to inversion to external file
         OPEN (10, FILE= TRIM(KmatFile) // '.' // TRIM("inv"))
         DO i=1,Permutation
           WRITE(10,'(6ES17.8E3)') Kmat(i,:)
         END DO
         CLOSE(10)              

         OPEN (10, FILE= TRIM(KmatFile) // '.' // TRIM("min-inv"))
         DO i=1,Permutation
           WRITE(10,'(6ES17.8E3)') KmatMin(i,:)
         END DO
         CLOSE(10)              

         IF(ListGetLogical(Solver % Values,'Symmetrisize',stat)) THEN
           Kmat = (Kmat + TRANSPOSE(Kmat)) / 2.0d0
           KmatMin = (KmatMin + TRANSPOSE(KmatMin)) / 2.0d0
         END IF

         CALL InvertMatrix(Kmat,Permutation)
         CALL InvertMatrix(KmatMin,Permutation)
       END IF

       IF(FixDisplacement .AND. ListGetLogical(Solver % Values,'Symmetrisize',stat)) THEN
         Kmat = (Kmat + TRANSPOSE(Kmat)) / 2.0d0
       END IF

       ! Save the Kmatrix to an external file
       OPEN (10, FILE=KmatFile)
       DO i=1,Permutation
         WRITE(10,'(6ES17.8E3)') Kmat(i,:)
       END DO
       CLOSE(10)

       IF(.NOT. FixDisplacement) THEN
         OPEN (10, FILE= TRIM(KmatFile) // '.' // TRIM("min"))
         DO i=1,Permutation
           WRITE(10,'(6ES17.8E3)') Kmat(i,:)
         END DO
         CLOSE(10)
       END IF

       ! Save the area center to an external file
       OPEN (10, FILE= TRIM(KmatFile) // '.' // TRIM("center"))
       DO i=1,3
         WRITE(10,'(ES17.8E3)') Center(i)
       END DO
       CLOSE(10)
     END IF


   END SUBROUTINE LumpedSprings


  END SUBROUTINE StressSolver
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   FUNCTION StressBoundaryResidual( Model, Edge, Mesh, Quant, Perm, Gnorm ) RESULT( Indicator )
!------------------------------------------------------------------------------
     USE StressLocal
     USE DefUtils
     IMPLICIT NONE
!------------------------------------------------------------------------------
     TYPE(Model_t) :: Model
     INTEGER :: Perm(:)
     TYPE( Mesh_t ), POINTER    :: Mesh
     TYPE( Element_t ), POINTER :: Edge
     REAL(KIND=dp) :: Quant(:), Indicator(2), Gnorm
!------------------------------------------------------------------------------

     TYPE(Nodes_t) :: Nodes, EdgeNodes
     TYPE(Element_t), POINTER :: Element, Bndry

     INTEGER :: i,j,k,n,l,t,dim,DOFs,nd,Pn,En
     LOGICAL :: stat, Found

     REAL(KIND=dp) :: SqrtMetric, Metric(3,3), Symb(3,3,3), dSymb(3,3,3,3)

     REAL(KIND=dp) :: Normal(3), EdgeLength, x(4), y(4), z(4), ExtPressure(MAX_NODES)

     REAL(KIND=dp) :: u, v, w, s, detJ, EdgeBasis(4), dEdgeBasisdx(4,3), &
         Basis(MAX_NODES),dBasisdx(MAX_NODES,3), ddBasisddx(MAX_NODES,3,3)

     REAL(KIND=dp) :: Residual(3), ResidualNorm, Area
     REAL(KIND=dp) :: Force(3,MAX_NODES), ForceSolved(3)
     REAL(KIND=dp) :: Dir(3)

     REAL(KIND=dp) :: Displacement(3), NodalDisplacement(3,MAX_NODES)
     REAL(KIND=dp) :: YoungsModulus, ElasticModulus(6,6,MAX_NODES)
     REAL(KIND=dp) :: PoissonRatio, NodalPoissonRatio(MAX_NODES)
     REAL(KIND=dp) :: Grad(3,3), Strain(3,3), Stress1(3,3), Stress2(3,3)
     REAL(KIND=dp) :: Identity(3,3), YoungsAverage, LocalTemp(MAX_NODES), &
                      LocalHexp(3,3,MAX_NODES)

     LOGICAL :: PlaneStress, Isotropic, CSymmetry = .FALSE.

     TYPE(ValueList_t), POINTER :: Material, Equation, BodyForce, BC

     TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff

     SAVE Nodes, EdgeNodes
!------------------------------------------------------------------------------
     LocalTemp = 0
     LocalHexp = 0

     ! Initialize:
     ! -----------
     Gnorm = 0.0d0
     Indicator = 0.0d0

     Identity = 0.0d0
     DO i=1,3
        Identity(i,i) = 1.0d0
     END DO

     CSymmetry = CurrentCoordinateSystem() == CylindricSymmetric .OR. &
                 CurrentCoordinateSystem() == AxisSymmetric

     dim = CoordinateSystemDimension()
     DOFs = dim

!    --------------------------------------------------
     Element => Edge % BoundaryInfo % Left

     IF ( .NOT. ASSOCIATED( Element ) ) THEN
        Element => Edge % BoundaryInfo % Right
     ELSE IF ( ANY( Perm( Element % NodeIndexes ) <= 0 ) ) THEN
        Element => Edge % BoundaryInfo % Right
     END IF

     IF ( .NOT. ASSOCIATED( Element ) ) RETURN
     IF ( ANY( Perm( Element % NodeIndexes ) <= 0 ) ) RETURN

     En = GetElementNOFNodes( Edge )
     CALL GetElementNodes( EdgeNodes )

     nd = GetElementNOFDOFs( Element )
     Pn = GetElementNOFNodes( Element )
     CALL GetElementNodes( Nodes, UElement=Element )

     DO l = 1,En
       DO k = 1,Pn
          IF ( Edge % NodeIndexes(l) == Element % NodeIndexes(k) ) THEN
             x(l) = Element % Type % NodeU(k)
             y(l) = Element % Type % NodeV(k)
             z(l) = Element % Type % NodeW(k)
             EXIT
          END IF
       END DO
     END DO

     ! Integrate square of residual over boundary element:
     ! ---------------------------------------------------
     Indicator     = 0.0d0
     EdgeLength    = 0.0d0
     YoungsAverage = 0.0d0
     ResidualNorm  = 0.0d0

     BC => GetBC()
     IF ( .NOT. ASSOCIATED( BC ) ) RETURN

     ! Logical parameters:
     ! -------------------
     Equation => GetEquation( Element )
     PlaneStress = GetLogical( Equation, 'Plane Stress' ,Found )

     Material => GetMaterial( Element )
     NodalPoissonRatio(1:pn) = GetReal( &
                  Material, 'Poisson Ratio',Found, Element )
     CALL InputTensor( ElasticModulus, Isotropic, &
                 'Youngs Modulus', Material, Pn, Element % NodeIndexes )

     ! Given traction:
     ! ---------------
     Force = 0.0d0
     Force(1,1:En) = GetReal( BC, 'Force 1', Found )
     Force(2,1:En) = GetReal( BC, 'Force 2', Found )
     Force(3,1:En) = GetReal( BC, 'Force 3', Found )

     ! Force in normal direction:
     ! ---------------------------
     ExtPressure(1:En) = GetReal( BC, 'Normal Force', Found )

     ! If dirichlet BC for displacement in any direction given,
     ! nullify force in that directon:
     ! --------------------------------------------------------
     Dir = 1.0d0
     IF ( ListCheckPresent( BC, 'Displacement' ) )   Dir = 0
     IF ( ListCheckPresent( BC, 'Displacement 1' ) ) Dir(1) = 0
     IF ( ListCheckPresent( BC, 'Displacement 2' ) ) Dir(2) = 0
     IF ( ListCheckPresent( BC, 'Displacement 3' ) ) Dir(3) = 0

     ! Elementwise nodal solution:
     ! ---------------------------
     CALL GetVectorLocalSolution( NodalDisplacement, UElement=Element )

     ! Integration:
     ! ------------
     EdgeLength    = 0.0d0
     YoungsAverage = 0.0d0
     ResidualNorm  = 0.0d0

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

        ! Stress tensor on the edge:
        ! --------------------------
        CALL LocalStress( Stress1, Strain, NodalPoissonRatio, &
           ElasticModulus, Isotropic, CSymmetry, PlaneStress, &
           NodalDisplacement, Basis, dBasisdx, Nodes, dim, pn, nd )

        ! Given force at the integration point:
        ! -------------------------------------
        Residual = MATMUL( Force(:,1:En), EdgeBasis(1:En) ) - &
          SUM( ExtPressure(1:En) * EdgeBasis(1:En) ) * Normal

        ForceSolved = MATMUL( Stress1, Normal )
        Residual = Residual - ForceSolved * Dir

        EdgeLength    = EdgeLength + s
        ResidualNorm  = ResidualNorm  + s * SUM(Residual(1:DIM) ** 2)
        YoungsAverage = YoungsAverage + &
                    s * SUM( ElasticModulus(1,1,1:Pn) * Basis(1:Pn) )
     END DO

     IF ( YoungsAverage > AEPS ) THEN
        YoungsAverage = YoungsAverage / EdgeLength
        Indicator = EdgeLength * ResidualNorm / YoungsAverage
     END IF

!------------------------------------------------------------------------------
   END FUNCTION StressBoundaryResidual
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  FUNCTION StressEdgeResidual( Model,Edge,Mesh,Quant,Perm ) RESULT( Indicator )
!------------------------------------------------------------------------------
     USE StressLocal
     USE DefUtils
     IMPLICIT NONE

     TYPE(Model_t) :: Model
     INTEGER :: Perm(:)
     REAL(KIND=dp) :: Quant(:), Indicator(2)
     TYPE( Mesh_t ), POINTER    :: Mesh
     TYPE( Element_t ), POINTER :: Edge
!------------------------------------------------------------------------------

     TYPE(Nodes_t) :: Nodes, EdgeNodes
     TYPE(Element_t), POINTER :: Element, Bndry

     INTEGER :: i,j,k,l,n,t,dim,DOFs,En,Pn, nd
     LOGICAL :: stat, Found

     REAL(KIND=dp) :: SqrtMetric, Metric(3,3), Symb(3,3,3), dSymb(3,3,3,3)
     REAL(KIND=dp) :: Stressi(3,3,2), Jump(3), Identity(3,3)
     REAL(KIND=dp) :: Normal(3), x(4), y(4), z(4)
     REAL(KIND=dp) :: Displacement(3), NodalDisplacement(3,MAX_NODES)
     REAL(KIND=dp) :: YoungsModulus, ElasticModulus(6,6,MAX_NODES)
     REAL(KIND=dp) :: PoissonRatio, NodalPoissonRatio(MAX_NODES)
     REAL(KIND=dp) :: Grad(3,3), Strain(3,3), Stress1(3,3), Stress2(3,3)
     REAL(KIND=dp) :: YoungsAverage, LocalTemp(MAX_NODES), LocalHexp(3,3,MAX_NODES)

     LOGICAL :: PlaneStress, Isotropic, CSymmetry

     TYPE(ValueList_t), POINTER :: Material, Equation

     REAL(KIND=dp) :: u, v, w, s, detJ, EdgeBasis(MAX_NODES), Basis(MAX_NODES), &
              dBasisdx(MAX_NODES,3), ddBasisddx(MAX_NODES,3,3)

     REAL(KIND=dp) :: Residual, ResidualNorm, EdgeLength

     TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff

     SAVE Nodes, EdgeNodes
!------------------------------------------------------------------------------

     LocalTemp = 0
     LocalHexp = 0

!    Initialize:
!    -----------
     dim = CoordinateSystemDimension()
     DOFs = dim

     CSymmetry = CurrentCoordinateSystem() == CylindricSymmetric .OR. &
                 CurrentCoordinateSystem() == AxisSymmetric


     Identity = 0.0d0
     Metric   = 0.0d0
     DO i = 1,3
        Metric(i,i)   = 1.0d0
        Identity(i,i) = 1.0d0
     END DO
!
!    ---------------------------------------------
     En = GetElementNOFNodes( Edge )
     CALL GetElementNodes( EdgeNodes, Edge )

!    Integrate square of jump over edge:
!    ------------------------------------
     ResidualNorm  = 0.0d0
     EdgeLength    = 0.0d0
     Indicator     = 0.0d0
     Grad          = 0.0d0
     YoungsAverage = 0.0d0

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

        Stressi = 0.0d0
        DO i = 1,2
           IF ( i==1 ) THEN
              Element => Edge % BoundaryInfo % Left
           ELSE
              Element => Edge % BoundaryInfo % Right
           END IF

           IF ( ANY( Perm( Element % NodeIndexes ) <= 0 ) ) CYCLE

           pn = GetElementNOFNodes( Element )
           nd = GetElementNOFDOFs( Element )
           CALL GetElementNodes( Nodes, Element )
           DO j = 1,en
              DO k = 1,pn
                 IF ( Edge % NodeIndexes(j) == Element % NodeIndexes(k) ) THEN
                    x(j) = Element % Type % NodeU(k)
                    y(j) = Element % Type % NodeV(k)
                    z(j) = Element % Type % NodeW(k)
                    EXIT
                 END IF
              END DO
           END DO

           u = SUM( EdgeBasis(1:En) * x(1:En) )
           v = SUM( EdgeBasis(1:En) * y(1:En) )
           w = SUM( EdgeBasis(1:En) * z(1:En) )

           stat = ElementInfo( Element, Nodes, u, v, w, detJ, &
               Basis, dBasisdx, ddBasisddx, .FALSE., .FALSE. )

           ! Logical parameters:
           ! -------------------
           Equation => GetEquation( Element )
           PlaneStress = GetLogical( Equation,'Plane Stress',Found )

           ! Material parameters:
           ! --------------------
           Material => GetMaterial( Element )
           NodalPoissonRatio(1:pn) = GetReal( Material, 'Poisson Ratio', Found, Element )
           CALL InputTensor( ElasticModulus, Isotropic, &
                         'Youngs Modulus', Material, pn, Element % NodeIndexes )

           ! Elementwise nodal solution:
           ! ---------------------------
           CALL GetVectorLocalSolution( NodalDisplacement, UElement=Element )

           ! Stress tensor on the edge:
           ! --------------------------
           CALL LocalStress( Stress1, Strain, NodalPoissonRatio, &
              ElasticModulus, Isotropic, CSymmetry, PlaneStress, &
              NodalDisplacement, Basis, dBasisdx, Nodes, dim, pn, nd )

           Stressi(:,:,i) = Stress1
        END DO

        EdgeLength  = EdgeLength + s
        Jump = MATMUL( ( Stressi(:,:,1) - Stressi(:,:,2)), Normal )
        ResidualNorm = ResidualNorm + s * SUM( Jump(1:DIM) ** 2 )

        YoungsAverage = YoungsAverage + s *  &
                    SUM( ElasticModulus(1,1,1:pn) * Basis(1:pn) )
     END DO

     YoungsAverage = YoungsAverage / EdgeLength
     Indicator = EdgeLength * ResidualNorm / YoungsAverage

!------------------------------------------------------------------------------
   END FUNCTION StressEdgeResidual
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   FUNCTION StressInsideResidual( Model, Element,  &
                      Mesh, Quant, Perm, Fnorm ) RESULT( Indicator )
!------------------------------------------------------------------------------
     USE StressLocal
     USE DefUtils
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

     INTEGER :: i,j,k,l,m,n,nd,t,dim,DOFs,I1(6),I2(6), Indexes(MAX_NODES)

     LOGICAL :: stat, Found

     TYPE( Variable_t ), POINTER :: Var

     REAL(KIND=dp), TARGET :: x(MAX_NODES), y(MAX_NODES), z(MAX_NODES)

     REAL(KIND=dp) :: SqrtMetric, Metric(3,3), Symb(3,3,3), dSymb(3,3,3,3)

     REAL(KIND=dp) :: Density, NodalDensity(MAX_NODES)
     REAL(KIND=dp) :: ElasticModulus(6,6,MAX_NODES)
     REAL(KIND=dp) :: PoissonRatio, NodalPoissonRatio(MAX_NODES)
     REAL(KIND=dp) :: Damping, NodalDamping(MAX_NODES)
     REAL(KIND=dp) :: NodalDisplacement(3,MAX_NODES), Displacement(3),Identity(3,3)
     REAL(KIND=dp) :: Grad(3,3), Strain(3,3), Stress1(3,3), Stress2(3,3)
     REAL(KIND=dp) :: Stressi(3,3,MAX_NODES), YoungsAverage, LocalTemp(MAX_NODES), &
                Energy, NodalForce(4,MAX_NODES), Veloc(3,MAX_NODES), Accel(3,MAX_NODES), &
                  LocalHexp(3,3,MAX_NODES), vec(1:MAX_NODES)

     LOGICAL :: PlaneStress, CSymmetry, Isotropic, Transient

     REAL(KIND=dp) :: u, v, w, s, detJ, Basis(MAX_NODES), &
        dBasisdx(MAX_NODES,3), ddBasisddx(MAX_NODES,3,3)
     REAL(KIND=dp) :: Residual(3), ResidualNorm, Area

     TYPE(ValueList_t), POINTER :: Material, BodyForce, Equation

     TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff

     SAVE Nodes
!------------------------------------------------------------------------------
     LocalTemp = 0
     LocalHexp = 0

     ! Initialize:
     ! -----------
     Fnorm     = 0.0d0
     Indicator = 0.0d0

     IF ( ANY( Perm( Element % NodeIndexes ) <= 0 ) ) RETURN

     Metric = 0.0d0
     DO i=1,3
        Metric(i,i) = 1.0d0
     END DO

     dim = CoordinateSystemDimension()
     DOFs = dim 

     CSymmetry = CurrentCoordinateSystem() == CylindricSymmetric .OR. &
                 CurrentCoordinateSystem() == AxisSymmetric

     ! Element nodal points:
     ! ---------------------
     nd = GetElementNOFDOFs()
     n  = GetElementNOFNodes()

     CALL GetElementNodes( Nodes )

     ! Logical parameters:
     ! -------------------
     equation => GetEquation()
     PlaneStress = GetLogical( Equation, 'Plane Stress',Found )

     ! Material parameters:
     ! --------------------
     Material => GetMaterial()

     CALL InputTensor( ElasticModulus, Isotropic, &
           'Youngs Modulus', Material, n, Element % NodeIndexes )

     NodalPoissonRatio(1:n) = GetReal( Material, 'Poisson Ratio', Found )

     ! Check for time dep.
     ! -------------------
     IF ( ListGetString( Model % Simulation, 'Simulation Type') == 'transient' ) THEN
        Transient = .TRUE.
        Var => VariableGet( Model % Variables, 'Displacement', .TRUE. )

        nd = GetElementDOFs( Indexes )

        Veloc = 0.0d0
        Accel = 0.0d0
        DO i=1,DOFs
           Veloc(i,1:nd) = Var % PrevValues(DOFs*(Var % Perm(Indexes(1:nd))-1)+i,1)
           Accel(i,1:nd) = Var % PrevValues(DOFs*(Var % Perm(Indexes(1:nd))-1)+i,2)
        END DO
        NodalDensity(1:n) = GetReal( Material, 'Density', Found )
        NodalDamping(1:n) = GetReal( Material, 'Damping', Found )
     ELSE
        Transient = .FALSE.
     END IF

     ! Elementwise nodal solution:
     ! ---------------------------
     CALL GetVectorLocalSolution( NodalDisplacement )

     ! Body Forces:
     ! ------------
     BodyForce => GetBodyForce()

     NodalForce = 0.0d0

     IF ( ASSOCIATED( BodyForce ) ) THEN
        NodalForce(1,1:n) = NodalForce(1,1:n) + GetReal( &
            BodyForce, 'Stress BodyForce 1', Found )
        NodalForce(2,1:n) = NodalForce(1,1:n) + GetReal( &
            BodyForce, 'Stress BodyForce 2', Found )
        NodalForce(3,1:n) = NodalForce(1,1:n) + GetReal( &
            BodyForce, 'Stress BodyForce 3', Found )
     END IF

     Identity = 0.0D0
     DO i = 1,dim
        Identity(i,i) = 1.0D0
     END DO
     CSymmetry = .FALSE.

     Var => VariableGet( Model % Variables, 'Stress 1' )
     IF ( ASSOCIATED( Var ) ) THEN

       ! If stress already computed:
       ! ---------------------------
       I1(1:6) = (/ 1,2,3,1,2,1 /)
       I2(1:6) = (/ 1,2,3,2,3,3 /)
       DO i=1,6
         CALL GetScalarLocalSolution(Vec(1:nd),'Stress ' // CHAR(i+ICHAR('0')))
         Stressi(I1(i),I2(i),1:nd) = Vec(1:nd)
         Stressi(I2(i),I1(i),1:nd) = Vec(1:nd)
       END DO
     ELSE
       ! Values of the stress tensor at node points:
       ! -------------------------------------------
       DO i = 1,n
         u = Element % Type % NodeU(i)
         v = Element % Type % NodeV(i)
         w = Element % Type % NodeW(i)

         stat = ElementInfo( Element, Nodes, u, v, w, detJ, &
             Basis, dBasisdx, ddBasisddx, .FALSE., .FALSE. )

         CALL LocalStress( Stressi(:,:,i), Strain, NodalPoissonRatio, &
                   ElasticModulus, Isotropic, CSymmetry, PlaneStress, &
                   NodalDisplacement, Basis, dBasisdx, Nodes, dim, n, nd )
       END DO
     END IF

     ! Integrate square of residual over element:
     ! ------------------------------------------
     ResidualNorm = 0.0d0
     Fnorm = 0.0d0
     Area = 0.0d0
     Energy = 0.0d0
     YoungsAverage = 0.0d0

     IntegStuff = GaussPoints( Element )

     DO t=1,IntegStuff % n
        u = IntegStuff % u(t)
        v = IntegStuff % v(t)
        w = IntegStuff % w(t)

        stat = ElementInfo( Element, Nodes, u, v, w, detJ, &
            Basis, dBasisdx, ddBasisddx, .FALSE., .FALSE. )

        IF ( CurrentCoordinateSystem() == Cartesian ) THEN
           s = IntegStuff % s(t) * detJ
        ELSE
           u = SUM( Basis(1:n) * Nodes % x(1:n) )
           v = SUM( Basis(1:n) * Nodes % y(1:n) )
           w = SUM( Basis(1:n) * Nodes % z(1:n) )

           CALL CoordinateSystemInfo( Metric,SqrtMetric,Symb,dSymb,u,v,w )
           s = IntegStuff % s(t) * detJ * SqrtMetric
        END IF

        ! Residual of the diff.equation:
        ! ------------------------------
        Residual = 0.0d0
        DO i = 1,3
           Residual(i) = -SUM( NodalForce(i,1:n) * Basis(1:n) )

           IF ( Transient ) THEN
              Residual(i) = Residual(i) + SUM(NodalDensity(1:n)*Basis(1:n)) * &
                            SUM( Accel(i,1:nd) * Basis(1:nd) )
              Residual(i) = Residual(i) + SUM(NodalDamping(1:n)*Basis(1:n)) * &
                            SUM( Veloc(i,1:nd) * Basis(1:nd) )
           END IF

           DO j = 1,3
             Residual(i) = Residual(i) - SUM(Stressi(i,j,1:nd)*dBasisdx(1:nd,j))
           END DO
        END DO

!       IF ( CSymmetry ) THEN
!          DO k=1,3
!             Residual(1) = Residual(1) + ...
!          END DO
!       END IF

       ! Dual norm of the load:
       ! ----------------------
        DO i = 1,dim
           Fnorm = Fnorm + s * SUM( NodalForce(i,1:n) * Basis(1:n) ) ** 2
        END DO

        YoungsAverage = YoungsAverage + s*SUM( ElasticModulus(1,1,1:n) * Basis(1:n) )

        ! Energy:
        ! -------
        CALL LocalStress( Stress1, Strain, NodalPoissonRatio, &
           ElasticModulus, Isotropic, CSymmetry, PlaneStress, &
           NodalDisplacement, Basis, dBasisdx, Nodes, dim, n, nd )

        Energy = Energy + s*DDOTPROD(Strain,Stress1,dim) / 2.0d0

        Area = Area + s
        ResidualNorm = ResidualNorm + s * SUM( Residual(1:dim) ** 2 )
     END DO

     YoungsAverage = YoungsAverage / Area
     Fnorm = Energy
     Indicator = Area * ResidualNorm / YoungsAverage

CONTAINS

!------------------------------------------------------------------------------
  FUNCTION DDOTPROD(A,B,N) RESULT(C)
!------------------------------------------------------------------------------
    IMPLICIT NONE
    DOUBLE PRECISION :: A(:,:),B(:,:),C
    INTEGER :: N
!------------------------------------------------------------------------------
    INTEGER :: I,J
!------------------------------------------------------------------------------
    C = 0.0D0
    DO i = 1,N
       DO j = 1,N
          C = C + A(i,j)*B(i,j)
       END DO
    END DO
!------------------------------------------------------------------------------
  END FUNCTION DDOTPROD
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
   END FUNCTION StressInsideResidual
!------------------------------------------------------------------------------
