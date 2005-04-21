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
! *                       Date:      2000
! *
! *                Modified by:      Antti Pursula
! *
! *       Date of modification:      21 Mar 2002
! *
! *****************************************************************************/

!------------------------------------------------------------------------------
SUBROUTINE ForceCompute( Model,Solver,dt,TransientSimulation )
  !DEC$ATTRIBUTES DLLEXPORT :: ForceCompute
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
  USE DefUtils

  USE Integration
  USE ElementDescription

  USE SolverUtils
  USE MaterialModels

  IMPLICIT NONE
!------------------------------------------------------------------------------
  TYPE(Solver_t) :: Solver
  TYPE(Model_t) :: Model

  REAL(KIND=dp) :: dt
  LOGICAL :: TransientSimulation
!------------------------------------------------------------------------------
! Local variables
!------------------------------------------------------------------------------
  REAL(KIND=dp), ALLOCATABLE :: Pressure(:), Velocity(:,:), Viscosity(:)
  REAL(KIND=dp), ALLOCATABLE :: ShearData(:,:)
  REAL(KIND=dp), ALLOCATABLE :: MomentAbout(:,:), Forces(:,:), Moments(:,:), Areas(:)
  TYPE(Solver_t), POINTER :: FlowSolver
  REAL(KIND=dp) :: Force(3), Moment(3), Area, ShearStress
  LOGICAL :: Stat, CalculateMoment, ViscousForce, Compressible, SumForces
  LOGICAL :: ShearOutput
  LOGICAL, ALLOCATABLE :: ActiveBoundaries(:)
  INTEGER :: i,j,k,n,pn,t,dim
  INTEGER :: NbrShearValues
  INTEGER, POINTER :: NodeIndexes(:), Indices(:)
  TYPE(Variable_t), POINTER :: Var
  TYPE(Mesh_t), POINTER :: Mesh
  TYPE(ValueList_t), POINTER :: Material
  TYPE(Nodes_t) :: ElementNodes, ParentNodes
  TYPE(Element_t), POINTER   :: CurrentElement, Parent
  CHARACTER(LEN=MAX_NAME_LEN) :: ShearFilename, MessageL, ViscosityFlag
  CHARACTER(LEN=MAX_NAME_LEN) :: CompressibilityFlag, BoundaryName, VariableName
  CHARACTER(LEN=MAX_NAME_LEN) :: VersionID = "$Id: FluidicForce.f90,v 1.18 2005/04/04 06:18:28 jpr Exp $"

!------------------------------------------------------------------------------
!    Check if version number output is requested
!------------------------------------------------------------------------------
  IF ( ListGetLogical( GetSimulation(), 'Output Version Numbers', stat ) ) THEN
    CALL Info( 'FluidicForce', 'FluidicForce version:', Level = 0 ) 
    CALL Info( 'FluidicForce', VersionID, Level = 0 ) 
    CALL Info( 'FluidicForce', ' ', Level = 0 ) 
  END IF

  DO i=1,Model % NumberOfSolvers
     FlowSolver => Model % Solvers(i)
     IF ( ListGetString( FlowSolver % Values, 'Equation' ) == 'navier-stokes' ) EXIT
  END DO

  Mesh => Model % Meshes
  DO WHILE( ASSOCIATED(Mesh) )
     IF ( Mesh % OutputActive ) EXIT 
     Mesh => Mesh % Next
  END DO

  CALL Info( 'ForceCompute', '-------------------------------------',Level=4 )
  CALL Info( 'ForceCompute', 'Computing Fluidic Force:  ', Level=4 )
  CALL Info( 'ForceCompute', '-------------------------------------',Level=4 )

  CALL SetCurrentMesh( Model, Mesh )

  VariableName = GetString( Solver % Values, 'Velocity Field Name', stat )
  IF ( .NOT. stat )  THEN
     Var => VariableGet( Mesh % Variables, 'Flow Solution', .TRUE. )
  ELSE
     Var => VariableGet( Mesh % Variables, VariableName, .TRUE. )
  END IF

  ALLOCATE( ElementNodes % x(Mesh % MaxElementNodes) )
  ALLOCATE( ElementNodes % y(Mesh % MaxElementNodes) )
  ALLOCATE( ElementNodes % z(Mesh % MaxElementNodes) )

  ALLOCATE( Pressure(   Mesh % MaxElementNodes ) )
  ALLOCATE( Viscosity(  Mesh % MaxElementNodes ) )
  ALLOCATE( Velocity( 3,Mesh % MaxElementNodes ) )

  ALLOCATE( MomentAbout(3,Mesh % MaxElementNodes) )
  ALLOCATE( Forces(Model % NumberOfBCs,3)  )
  ALLOCATE( Moments(Model % NumberOfBCs,3)  )
  ALLOCATE( ActiveBoundaries(Model % NumberOfBCs) )
  ALLOCATE( Areas(Model % NumberOfBCs)  )

  ALLOCATE( ParentNodes % x(Mesh % MaxElementNodes) )
  ALLOCATE( ParentNodes % y(Mesh % MaxElementNodes) )
  ALLOCATE( ParentNodes % z(Mesh % MaxElementNodes) )

  MomentAbout = 0.0d0
  Forces = 0.0d0
  Moments = 0.0d0
  ActiveBoundaries = .FALSE.
  Areas = 0.0d0

  DIM = CoordinateSystemDimension()

  ViscousForce = ListGetLogical( Solver % Values, 'Calculate Viscous Force',stat )
  IF ( .NOT. stat )  ViscousForce = .TRUE.

  ShearOutput = GetLogical( Solver % Values, 'Shear Stress Output', stat )
  IF ( ShearOutput .AND. DIM == 3 ) THEN
     CALL Warn( 'FluidicForce', &
          'Shear stress output not implemented for 3D cases' )
     ShearOutput = .FALSE.
  END IF
  IF ( ShearOutput ) THEN
     ShearFilename = GetString( Solver % Values, 'Shear Stress Output File', stat )
     IF ( .NOT. stat )  ShearFilename = 'shearstress.dat'

     NbrShearValues = 0
     ALLOCATE( ShearData( Mesh % NumberOfBoundaryElements, 3 ) )
     ShearData = 0.0d0
  END IF

  SumForces = ListGetLogical( Solver % Values, 'Sum Forces',stat )

  IF (CurrentCoordinateSystem() == 2 .OR. CurrentCoordinateSystem() >= 5) THEN
     DO i = 1, Model % NumberOfMaterials
        Material => Model % Materials(i) % Values
        CompressibilityFlag = ListGetString( Material, &
             'Compressibility Model', stat)
        IF ( stat .AND. CompressibilityFlag /= 'incompressible' ) THEN
           CALL Warn( 'ForceCompute', &
                'Force component due to compressibility not implemented in polar coordinates' )
           EXIT
        END IF
     END DO
  END IF

  DO t = Mesh % NumberOfBulkElements + 1, &
      Mesh % NumberOfBulkElements + &
      Mesh % NumberOfBoundaryElements

!------------------------------------------------------------------------------
     CurrentElement => Mesh % Elements(t)
!------------------------------------------------------------------------------
!    Set the current element pointer in the model structure to 
!    reflect the element being processed
!------------------------------------------------------------------------------
     Model % CurrentElement => Mesh % Elements(t)
!------------------------------------------------------------------------------
     n = CurrentElement % TYPE % NumberOfNodes
     NodeIndexes => CurrentElement % NodeIndexes

     IF ( CurrentElement % TYPE % ElementCode == 101 ) CYCLE

     DO k=1, Model % NumberOfBCs
        IF ( Model % BCs(k) % Tag /= CurrentElement % BoundaryInfo % Constraint ) CYCLE
        IF ( .NOT.ListGetLogical(Model % BCs(k) % Values,'Calculate Fluidic Force',stat ) ) CYCLE

        ElementNodes % x(1:n) = Mesh % Nodes % x(NodeIndexes)
        ElementNodes % y(1:n) = Mesh % Nodes % y(NodeIndexes)
        ElementNodes % z(1:n) = Mesh % Nodes % z(NodeIndexes)

        Parent => CurrentELement % BoundaryInfo % Left

        stat = ASSOCIATED( Parent )
        IF ( stat ) stat = stat .AND. ALL(Var % Perm(Parent % NodeIndexes(1:n)) > 0)

        IF ( .NOT. stat ) THEN
           Parent => CurrentELement % BoundaryInfo % Right

           stat = ASSOCIATED( Parent )
           IF ( stat ) stat = ALL(Var % Perm(Parent % NodeIndexes(1:n)) > 0)

           IF ( .NOT. stat )  CALL Fatal( 'ForceCompute', &
                'No flow solution available for specified boundary' )
        END IF

        i = Parent % BodyId
        pn = Parent % Type % NumberOfNodes

        ParentNodes % x(1:pn) = Mesh % Nodes % x(Parent % NodeIndexes)
        ParentNodes % y(1:pn) = Mesh % Nodes % y(Parent % NodeIndexes)
        ParentNodes % z(1:pn) = Mesh % Nodes % z(Parent % NodeIndexes)

        j = ListGetInteger( Model % Bodies(i) % Values, 'Material', &
              minv=1, maxv=Model % NumberOFMaterials )
        Material => Model % Materials(j) % Values

        Compressible = .FALSE.
        CompressibilityFlag = ListGetString( Material, &
             'Compressibility Model', stat)
        IF ( stat .AND. CompressibilityFlag /= 'incompressible' )  &
             Compressible = .TRUE.

        Viscosity(1:pn) = ListGetReal( Material, 'Viscosity', pn, Parent % NodeIndexes )

        MomentAbout(1,1:n) = ListGetReal( Model % BCs(k) % Values, &
            'Moment About 1', n, NodeIndexes, stat )
        
        MomentAbout(2,1:n) = ListGetReal( Model % BCs(k) % Values, &
            'Moment About 2', n, NodeIndexes, CalculateMoment )
        CalculateMoment = stat .OR. CalculateMoment
        
        MomentAbout(3,1:n) = ListGetReal( Model % BCs(k) % Values, &
            'Moment About 3', n, NodeIndexes, stat )
        CalculateMoment = stat .OR. CalculateMoment

        Velocity = 0.0d0
        DO i=1,pn
           DO j=1,DIM
              Velocity(j,i) = &
                Var % Values(Var % DOFs * (Var % Perm(Parent % NodeIndexes(i))-1)+j)
           END DO
        END DO
        Pressure(1:pn) = Var % Values(Var % DOFs * Var % Perm(Parent % NodeIndexes))

        Force = 0.0d0
        Moment = 0.0d0
        Area = 0.0d0
        ShearStress = 0.0d0

        CALL ForceIntegrate( Force, Moment, MomentAbout, ViscousForce, Compressible, & 
             Area, ShearStress)

        ActiveBoundaries(k) = .TRUE.
        Forces(k,1:3) = Forces(k,1:3) + Force(1:3)
        Moments(k,1:3) = Moments(k,1:3) + Moment(1:3)
        Areas(k) = Areas(k) + Area

        IF ( ShearOutput ) THEN
           NbrShearValues = NbrShearValues + 1
           ShearData(NbrShearValues,1) = ShearStress
           ShearData(NbrShearValues,2) = SUM( ElementNodes % x(1:n) ) / n
           ShearData(NbrShearValues,3) = SUM( ElementNodes % y(1:n) ) / n
        END IF
     END DO
  END DO

  IF(SumForces) THEN
    Areas(1) = SUM(Areas)
    Forces(1,1:3) = SUM(Forces(:,1:3))
    Moments(1,1:3) = SUM(Moments(:,1:3))
    ActiveBoundaries = .FALSE.
    ActiveBoundaries(1) = .TRUE.
  END IF

  DO k=1, Model % NumberOfBCs
    IF(.NOT. ActiveBoundaries(k)) CYCLE
    
    IF(.NOT. SumForces) THEN
      IF(Model % NumberOfBCs < 10) THEN
        WRITE( BoundaryName, '("bc ",I1)') k
      ELSE
        WRITE( BoundaryName, '("bc ",I2)') k
      END IF
    ELSE
      WRITE( BoundaryName, '("")') 
    END IF

    CALL Info('ForceCompute','Forces on Boundary '//TRIM(BoundaryName),Level=4 )
    WRITE( Message, '("Fluidic Force:", 3ES17.6E2)') Forces(k,1:3)
    CALL Info( 'ForceCompute', Message, Level=4 )
    WRITE( Message, '("Resultant Force:", ES17.6E2)') SQRT(SUM(Forces(k,1:3)**2 ))
    CALL Info( 'ForceCompute', Message, Level=4 )
    WRITE( Message, '("Contact Area:   ", ES17.6E2)') Areas(k)
    CALL Info( 'ForceCompute', Message, Level=4 )
    IF ( CalculateMoment ) THEN
      WRITE( Message, &
          '("Moment about (",ES9.3E1,",",ES9.3E1,",",ES9.3E1,") is:",3Es14.6E2)') &
          MomentAbout(1:3,1), Moments(k,1:3)
      CALL Info( 'ForceCompute', Message, Level=4 )
      
      CALL ListAddConstReal( Model % Simulation, &
           'res: fluid moment 3 '//TRIM(BoundaryName), Moments(k,3) )
      CALL ListAddConstReal( Model % Simulation, &
           'res: fluid moment 2 '//TRIM(BoundaryName), Moments(k,2) )
      CALL ListAddConstReal( Model % Simulation, &
           'res: fluid moment 1 '//TRIM(BoundaryName), Moments(k,1) )
   END IF

    CALL ListAddConstReal( Model % Simulation, & 
        'res: fluid force area '//TRIM(BoundaryName), Areas(k) )
    CALL ListAddConstReal( Model % Simulation, &
        'res: fluid force '//TRIM(BoundaryName), SQRT(SUM(Forces(k,1:3)**2 )) )

    IF ( DIM > 2 )  CALL ListAddConstReal( Model % Simulation, &
        'res: fluid force 3 '//TRIM(BoundaryName), Forces(k,3) )
    CALL ListAddConstReal( Model % Simulation, &
        'res: fluid force 2 '//TRIM(BoundaryName), Forces(k,2) )
    CALL ListAddConstReal( Model % Simulation, &
        'res: fluid force 1 '//TRIM(BoundaryName), Forces(k,1) )
  END DO

!------------------------------------------------------------------------------
!   Sort shear data and write it on the disk
!------------------------------------------------------------------------------

  IF ( ShearOutput ) THEN

!     IF ( .FALSE. ) THEN

     ALLOCATE( Indices( NbrShearValues ) )
     Indices = 0
     Indices = (/ ( i, i= 1,NbrShearValues ) /)

     IF ( ( MaxVal( ShearData(1:NbrShearValues,2) ) - &
            MINVAL( ShearData(1:NbrShearValues,2) ) ) > &
          ( MaxVal( ShearData(1:NbrShearValues,3) ) - &
            MINVAL( ShearData(1:NbrShearValues,3) ) ) ) THEN
        ! Sort ascending depending on coordinate 1
        CALL SortF( NbrShearValues, Indices, ShearData(1:NbrShearValues,2) )

        ShearData(1:NbrShearValues,1) = ShearData(Indices,1)
        ShearData(1:NbrShearValues,3) = ShearData(Indices,3)
     ELSE
        ! Sort ascending depending on coordinate 1
        CALL SortF( NbrShearValues, Indices, ShearData(1:NbrShearValues,3) )

        ShearData(1:NbrShearValues,1) = ShearData(Indices,1)
        ShearData(1:NbrShearValues,2) = ShearData(Indices,2)
     END IF
!     END IF

     OPEN(10, FILE=ShearFilename)
     DO t = 1, NbrShearValues
        WRITE( 10, * ) ShearData(t,:)
     END DO
     CLOSE(10)

     WRITE( MessageL, * ) 'Variables in columns of matrix: ' // TRIM(ShearFilename)
     ShearFilename = TRIM( ShearFilename ) // '.names'

     OPEN(10, FILE=ShearFilename)
     WRITE( 10, * ) TRIM(MessageL)
     WRITE( 10, * ) '1: Shear stress [N/m2]'
     WRITE( 10, * ) '2: Coordinate 1'
     WRITE( 10, * ) '3: Coordinate 2'
     
     CLOSE(10)

     DEALLOCATE( ShearData )
     DEALLOCATE( Indices )
  END IF


  DEALLOCATE( ElementNodes % x )
  DEALLOCATE( ElementNodes % y )
  DEALLOCATE( ElementNodes % z )

  DEALLOCATE( Forces, Moments, Areas)
  DEALLOCATE( Pressure, Viscosity, Velocity )

  DEALLOCATE( ParentNodes % x )
  DEALLOCATE( ParentNodes % y )
  DEALLOCATE( ParentNodes % z )

CONTAINS

!------------------------------------------------------------------------------
  SUBROUTINE ForceIntegrate( Force, Moment, MomentAbout, ViscousForce, &
       Compressible, Area, ShearStress )
!------------------------------------------------------------------------------
     REAL(KIND=dp) :: Force(3), Moment(3), MomentAbout(:,:), Area, ShearStress
     LOGICAL :: ViscousForce, Compressible
!------------------------------------------------------------------------------
     REAL(KIND=dp) :: LForce(3), LMoment(3), TForce
     REAL(KIND=dp) :: Basis(n), dBasisdx(n,3), ddBasisddx(n,3,3)
     REAL(KIND=dp) :: ParentBasis(pn), ParentdBasisdx(pn,3)
     REAL(KIND=dp) :: SqrtMetric, Metric(3,3), Symb(3,3,3), dSymb(3,3,3,3)
     REAL(KIND=dp) :: u, v, w, s, detJ, x(n), y(n), z(n), xpos, ypos, zpos
     REAL(KIND=dp) :: Grad(3,3), Stress(3,3), Normal(3), Radius(3)
     REAL(KIND=dp) :: Div
     REAL(KIND=dp) :: Visc

     INTEGER :: N_Integ
     REAL(KIND=dp), POINTER :: U_Integ(:), V_Integ(:), W_Integ(:), S_Integ(:)

     LOGICAL :: stat
     INTEGER :: i,t
     TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff
!------------------------------------------------------------------------------
!    Integration stuff
!------------------------------------------------------------------------------
     IntegStuff = GaussPoints( CurrentElement )

     U_Integ => IntegStuff % u
     V_Integ => IntegStuff % v
     W_Integ => IntegStuff % w
     S_Integ => IntegStuff % s
     N_Integ =  IntegStuff % n

     TForce = 0.0d0

!------------------------------------------------------------------------------
     DO t=1,N_Integ
!------------------------------------------------------------------------------

        u = U_Integ(t)
        v = V_Integ(t)
        w = W_Integ(t)
!------------------------------------------------------------------------------
!      Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
        stat = ElementInfo( CurrentElement, ElementNodes, u, v, w, &
           detJ, Basis, dBasisdx, ddBasisddx, .FALSE., .FALSE. )

!------------------------------------------------------------------------------
!      Coordinatesystem dependent info
!------------------------------------------------------------------------------
        s = 1.0d0
        IF ( CurrentCoordinateSystem() /= Cartesian ) THEN
          xpos = SUM( ElementNodes % x(1:n) * Basis(1:n) )
          ypos = SUM( ElementNodes % y(1:n) * Basis(1:n) )
          zpos = SUM( ElementNodes % z(1:n) * Basis(1:n) )
          s = 2*PI
        END IF
         
        CALL CoordinateSystemInfo( Metric,SqrtMetric,Symb,dSymb,xpos,ypos,zpos)
 
        s = s * SqrtMetric * detJ * S_Integ(t)

        Normal = Normalvector( CurrentElement, ElementNodes, u, v, .TRUE. )
!------------------------------------------------------------------------------
!
! Need parent element basis etc., for computing normal derivatives
! on boundary.
!
!------------------------------------------------------------------------------
        DO i = 1,n
          DO j = 1,pn
            IF ( CurrentElement % NodeIndexes(i) == Parent % NodeIndexes(j) ) THEN
               x(i) = Parent % TYPE % NodeU(j)
               y(i) = Parent % TYPE % NodeV(j)
               z(i) = Parent % TYPE % NodeW(j)
               EXIT
            END IF
          END DO
        END DO

        u = SUM( Basis(1:n) * x(1:n) )
        v = SUM( Basis(1:n) * y(1:n) )
        w = SUM( Basis(1:n) * z(1:n) )

        stat = ElementInfo( Parent, ParentNodes, u, v, w, detJ, ParentBasis, &
                  ParentdBasisdx, ddBasisddx, .FALSE., .FALSE. )

!------------------------------------------------------------------------------


        Stress = 0.0d0
        Div = 0.0d0

        IF ( ViscousForce ) THEN
          
          Grad = MATMUL( Velocity(:,1:pn),ParentdBasisdx )
          Visc = SUM( Viscosity(1:pn) * ParentBasis(1:pn) )

          ViscosityFlag = ListGetString( Material,'Viscosity Model', stat )
          IF ( stat )  CALL Warn( 'FluidicForce', &
               'Viscosity models ignored in fluidic force computation' )

          IF ( Compressible ) THEN
            
            IF ( CurrentCoordinateSystem() == Cartesian ) THEN
              DO i = 1, DIM
                Div = Div + Grad(i,i)
              END DO
            ELSE
              Div = SUM( Velocity(1,1:pn) * ParentdBasisdx(1:pn,1) ) + &
                  SUM( Velocity(1,1:pn) * ParentBasis(1:pn) ) / xpos + &
                  SUM( Velocity(2,1:pn) * ParentdBasisdx(1:pn,2) )
            END IF

          END IF
          
          Stress = Visc * ( Grad + TRANSPOSE(Grad) )
          
        END IF

        IF ( CurrentCoordinateSystem() == 2 &
             .OR. CurrentCoordinateSystem() >= 5 ) THEN
           DO i=1,DIM
              Stress(i,i) = Stress(i,i) - SUM( Pressure(1:pn) * ParentBasis )
           END DO
        ELSE
           DO i=1,DIM
              Stress(i,i) = Stress(i,i) - SUM( Pressure(1:pn) * ParentBasis ) &
                   -(2.0d0/3.0d0)*Visc*Div
           END DO
        END IF

        LForce = -MATMUL( Stress, Normal )
        Force  = Force  + s * LForce
        TForce = TForce + s * (LForce(1)*Normal(2) - LForce(2)*Normal(1))

        IF (CalculateMoment) THEN
          Radius(1) = SUM( (ElementNodes % x(1:n) - MomentAbout(1,1:n)) * Basis )
          Radius(2) = SUM( (ElementNodes % y(1:n) - MomentAbout(2,1:n)) * Basis )
          Radius(3) = SUM( (ElementNodes % z(1:n) - MomentAbout(3,1:n)) * Basis )
          
          LMoment(1) = Radius(2) * LForce(3) - Radius(3) * LForce(2)
          LMoment(2) = Radius(3) * LForce(1) - Radius(1) * LForce(3)
          LMoment(3) = Radius(1) * LForce(2) - Radius(2) * LForce(1)
          
          Moment = Moment + s * LMoment
        END IF

        Area = Area + s 

!------------------------------------------------------------------------------
     END DO

     ShearStress = TForce / Area

!------------------------------------------------------------------------------
  END SUBROUTINE ForceIntegrate
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
END SUBROUTINE ForceCompute
!------------------------------------------------------------------------------
