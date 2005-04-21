!/*****************************************************************************
! *
! *       ELMER, A Computational Fluid Dynamics Program.
! *
! *       Copyright 1st April 1995 - , CSC - Scietific Computing, Finland
! *
! *       All rights reserved. No part of this program may be used,
! *       reproduced or transmitted in any form or by any means
! *       without the written permission of CSC.
! *
! ****************************************************************************/
!
!/*****************************************************************************
! * This module may be used to compute aperture and amplitude from the displacement 
! * fields of different type. These may the later be used by reduced dimensional
! * solvers for fluidics and electrostatics, for example.
! *****************************************************************************
! *
! *             Module Author: Peter R�back
! *
! *                   Address: CSC - Scenter for Scientific Computing
! *                            Tekniikantie 15a D
! *                            02101 Espoo, Finland
! *                            Tel. +358 0 457 2080
! *                    E-Mail: Peter.Raback@csc.fi
! *
! *                      Date: 04.06.2000
! *
! *               Modified by: Peter R�back
! *
! *      Date of modification: 31.5.2003
! *
! ****************************************************************************/
 

!------------------------------------------------------------------------------
SUBROUTINE ApertureAmplitude( Model,Solver,dt,TransientSimulation )
!DEC$ATTRIBUTES DLLEXPORT :: ApertureAmplitude
!------------------------------------------------------------------------------
!******************************************************************************
!
!  Solve the aperture and amplitude resulting from different motions.
!  The different possibilities are 3D elasticity and 2D shells and 
!  their harmonic analysis. 
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
  TYPE(Nodes_t) :: ElementNodes
  TYPE(Element_t),POINTER :: CurrentElement
  TYPE(ValueList_t), POINTER :: Material
  TYPE(Variable_t), POINTER :: DVar, Dvar2
  TYPE(Solver_t), POINTER :: PSolver 

  INTEGER :: iter, i, j, k, n, t, istat, eq, LocalNodes, &
      eq_id, eq_idold, mat_id, mat_idold, body_id, body_idold, &
      ElemCorners, ElemDim, MinDim, MaxDim, NormalDirection, &
      PrevDoneTime=0, TimeStepVisited=0, NoEigenModes, NoAmplitudes
  INTEGER, POINTER :: NodeIndexes(:), AperturePerm(:), EigenModes(:)
  INTEGER, ALLOCATABLE :: DvarPerm(:)

  LOGICAL :: AllocationsDone = .FALSE., GotIt, Stat, &
      TrueOrFalse, Shell = .FALSE., Shell2 = .FALSE., Solid=.FALSE., &
      ApertureInitilized=.FALSE., ReferencePlaneExists=.FALSE., &
      Visited=.FALSE., ApertureExists, AplacExport = .FALSE., &
      EigenSystemDamped

  REAL(KIND=dp), POINTER :: Array(:,:), Amplitude(:), &
      Aperture(:), ApertureVelocity(:), PrevAperture(:,:), AmplitudeComp(:)
  REAL(KIND=dp) :: MaxAperture, MinAperture, MaxApertureVelocity, MinApertureVelocity, &
      ReferencePlane(4), WorkReal, Volume, CoordDiff(3)
  REAL(KIND=dp), ALLOCATABLE :: Work(:), dX(:), dY(:), dZ(:), &
       ElemAperture(:), ElemAmplitude(:,:), ElemApertureVelocity(:), &
       MaxAmplitudes(:), MinAmplitudes(:), ElasticMass(:), ElasticSpring(:), &
       ElemThickness(:), ElemDensity(:), AngularVelocity(:)

  CHARACTER(LEN=MAX_NAME_LEN) :: EquationName, String1

  SAVE Work, ElementNodes, Amplitude, Aperture, PrevAperture, &
      ElemAperture, ElemAmplitude, ElemApertureVelocity, AllocationsDone, DvarPerm, &
      dX, dY, dZ, PrevDoneTime, TimeStepVisited, ElasticMass, ElasticSpring, &
      ApertureVelocity, Visited, MaxAmplitudes, MinAmplitudes, &
      AngularVelocity, ElemThickness, ElemDensity


!------------------------------------------------------------------------------

  CALL Info('ApertureAmplitude','---------------------------------------------------',Level=5)
  CALL Info('ApertureAmplitude','Computing amplitude and aperture from displacements',Level=5)
  CALL Info('ApertureAmplitude','---------------------------------------------------',Level=5)

  CALL Warn('ApertureAmplitude','This Solver and the old StatElecReduced and Reynolds are soon obsolite!')
  CALL Info('ApertureAmplitude','Consult the new Models Manual for the current versions.')

!------------------------------------------------------------------------------
! Get variables needed for solution
!------------------------------------------------------------------------------

  Aperture     => Solver % Variable % Values
  AperturePerm => Solver % Variable % Perm

  IF(TransientSimulation) THEN
    PrevAperture => Solver % Variable % PrevValues
    IF(PrevDoneTime /= Solver % DoneTime) THEN
      TimeStepVisited = 0
      PrevDoneTime = INT(Solver % DoneTime + 0.5d0)
    END IF
    TimeStepVisited = TimeStepVisited + 1
  END IF

  LocalNodes = COUNT( AperturePerm > 0 )
  IF ( LocalNodes <= 0 ) RETURN

  EigenModes => ListGetIntegerArray( Solver % Values, 'Eigen Mode',gotIt )
  IF (gotIt) THEN
    NoEigenModes = SIZE(EigenModes)
  ELSE
    NoEigenModes = 0
  END IF
  
  IF(NoEigenModes > 0) THEN
    EigenSystemDamped = ListGetLogical( Solver % Values, 'Eigen System Damped',gotIt)
  END IF

  NoAmplitudes = MAX(1,NoEigenModes)

  AplacExport = .FALSE.
  DO k = 1, Model % NumberOfSolvers
    String1 = ListGetString( Model % Solvers(k) % Values, 'Equation',gotIt )
    IF(TRIM(String1) == 'aplac export') AplacExport = .TRUE.
  END DO
  IF(.NOT. AplacExport) THEN
    AplacExport = ListGetLogical( Model % Simulation, 'Aplac Export',gotIt)
  END IF

!------------------------------------------------------------------------------
! Allocate some permanent storage, this is done first time only
!------------------------------------------------------------------------------
  IF ( .NOT. AllocationsDone .OR. Solver % Mesh % Changed ) THEN
    N = Solver % Mesh % MaxElementNodes
    
    IF ( AllocationsDone ) THEN
      DEALLOCATE( ElementNodes % x, &
          ElementNodes % y,      &
          ElementNodes % z,      &
          Work,                  &
          DvarPerm,             &
          dX, dY, dZ,&
          ElemAperture,          &
          ElemAmplitude,         &
          ElemApertureVelocity, &
          ElasticMass, &
          ElasticSpring, &
          AngularVelocity, &
          ElemThickness, & 
          ElemDensity, &
          MaxAmplitudes,      &
          MinAmplitudes, &
          Amplitude)
    END IF
        
    ALLOCATE( ElementNodes % x( N ),  &
        ElementNodes % y( N ),       &
        ElementNodes % z( N ),       &
        Work(N),                     &
        DvarPerm(N),                &
        dX(N), dY(N), dZ(N), &
        ElemThickness(N),          &
        ElemDensity(N),          &
        ElemAperture(N),          &
        ElemApertureVelocity(N), &
        ElemAmplitude(NoAmplitudes,N),         &
        ElasticMass(NoAmplitudes), &
        ElasticSpring(NoAmplitudes), &
        AngularVelocity(NoAmplitudes), &
        MaxAmplitudes(NoAmplitudes), &
        MinAmplitudes(NoAmplitudes), &
        Amplitude(NoAmplitudes*Model%NumberOfNodes), &
        STAT=istat )

    IF ( istat /= 0 ) CALL FATAL('ApertureAmplitude','Memory allocation error')
    
    PSolver => Solver
    Aperture = 0.0d0
    Amplitude = 0.0d0
    
    CALL VariableAdd( Solver % Mesh % Variables, Solver % Mesh, & 
        PSolver, 'Amplitude', NoAmplitudes, Amplitude, AperturePerm)
    
    IF(NoAmplitudes > 1) THEN
      DO i=1,NoAmplitudes
        AmplitudeComp => Amplitude(i::NoAmplitudes)
        CALL VariableAdd(Solver % Mesh % Variables,Solver % Mesh, PSolver, &
            'Amplitude '//CHAR(i+ICHAR('0')), 1, AmplitudeComp, AperturePerm )
      END DO
    END IF
    
    IF(TransientSimulation) THEN
      ALLOCATE( ApertureVelocity(Model%NumberOfNodes), STAT=istat)
      IF ( istat /= 0 ) CALL FATAL('ApertureAmplitude','Memory allocation error')       
      ApertureVelocity = 0.0d0
      CALL VariableAdd( Solver % Mesh % Variables, Solver % Mesh, & 
          PSolver, 'Aperture Velocity', 1, ApertureVelocity, AperturePerm)
    END IF

    AllocationsDone = .TRUE.
  END IF


!------------------------------------------------------------------------------
! Do some additional initialization, and go for it
!------------------------------------------------------------------------------

  EquationName = ListGetString( Solver % Values, 'Equation' )

  NULLIFY(DVar)
  DVar => VariableGet( Model % Variables, 'Displacement' )
  
  IF (ASSOCIATED (DVar)) THEN
    Solid = .TRUE. 
  ELSE 
    DVar => VariableGet( Model % Variables, 'Deflection' )
    IF(ASSOCIATED (DVar)) THEN
      Shell = .TRUE.
    END IF
    DVar2 => VariableGet( Model % Variables, 'Deflection B' )
    IF(ASSOCIATED (DVar2)) THEN
      Shell2 = .TRUE.
    END IF
  END IF

  IF(NoEigenModes > 0) THEN
    IF(.NOT. ASSOCIATED(Dvar % EigenVectors)) &
        CALL Fatal('ApertureAmplitude','No EigenVectors exists!')
  END IF

!------------------------------------------------------------------------------
! Calculate the aperture and amplitude for later use and
! then normalize the amplitude.
!------------------------------------------------------------------------------

  IF(TransientSimulation) THEN
    IF(TimeStepVisited == 1) THEN
      Amplitude = MaxAmplitudes(1) * Amplitude 
    ELSE
      Amplitude = MaxAmplitudes(1) * Amplitude - ABS(Aperture - PrevAperture(:,1))
    END IF
  END IF

  mat_idold = 0
  eq_idold = 0
  body_idold = 0

  MinAperture = HUGE(MinAperture)
  MaxAperture = -HUGE(MaxAperture)
  MinApertureVelocity = HUGE(MinApertureVelocity)
  MaxApertureVelocity = -HUGE(MaxApertureVelocity)
  ElasticMass = 0.0d0
  Volume = 0.0d0

  MaxDim = 0
  MinDim = 3


  DO t=1,Solver % NumberOfActiveElements

    CurrentElement => Solver % Mesh % Elements(Solver % ActiveElements(t) )
    Model % CurrentElement => CurrentElement
    
    ElemCorners = CurrentElement % TYPE % ElementCode / 100
    
    IF(ElemCorners > 4) THEN
      ElemDim = 3
    ELSE IF(ElemCorners > 2) THEN
      ElemDim = 2
    ELSE
      ElemDim = ElemCorners
    END IF
    MaxDim = MAX(MaxDim,ElemDim)
    MinDim = MIN(MinDim,ElemDim)
    
    n = CurrentElement % TYPE % NumberOfNodes
    NodeIndexes => CurrentElement % NodeIndexes

    ElementNodes % x(1:n) = Solver % Mesh % Nodes % x(NodeIndexes(1:n))
    ElementNodes % y(1:n) = Solver % Mesh % Nodes % y(NodeIndexes(1:n))
    ElementNodes % z(1:n) = Solver % Mesh % Nodes % z(NodeIndexes(1:n))

!------------------------------------------------------------------------------
!       Get equation & material parameters
!------------------------------------------------------------------------------    
    body_id = CurrentElement % BodyId
    mat_id = ListGetInteger( Model % Bodies( body_id ) % Values, &
        'Material', minv=1,maxv=Model % NumberOfMaterials )

    Material => Model % Materials(mat_id) % Values
    ApertureExists = .TRUE.

    IF(body_id /= body_idold) THEN
      body_idold = body_id
      mat_idold = mat_id
      
      Array => ListGetConstRealArray( Model % Bodies( body_id) % Values, &
          'Reference Plane',ReferencePlaneExists)
      IF ( .NOT. ReferencePlaneExists) THEN
        Array => ListGetConstRealArray( Material, &
            'Reference Plane',ReferencePlaneExists)
      END IF
      IF ( ReferencePlaneExists) THEN
        ReferencePlane = Array(1:4,1)
      END IF
    END IF


    IF(Solid) THEN
      DvarPerm(1:n) = Dvar % Perm(NodeIndexes(1:n))

      IF(.NOT. ReferencePlaneExists) THEN
        CoordDiff(1) = MAXVAL(ElementNodes % x(1:n)) - MINVAL(ElementNodes % x(1:n))
        CoordDiff(2) = MAXVAL(ElementNodes % y(1:n)) - MINVAL(ElementNodes % y(1:n))
        CoordDiff(3) = MAXVAL(ElementNodes % y(1:n)) - MINVAL(ElementNodes % z(1:n))
      
        NormalDirection = 1
        DO i=1,DVar % DOFs
          IF( CoordDiff(i) < CoordDiff(NormalDirection) )  NormalDirection = i
        END DO
      END IF


      IF(NoEigenModes /= 0) THEN
        IF(ReferencePlaneExists) THEN
          DO i=1,n
            ElemAperture(i) = DistanceFromPlane( ElementNodes % x(i), &
                ElementNodes % y(i), ElementNodes % z(i), ReferencePlane)
          END DO
          
          DO j=1,NoAmplitudes
            IF ( DVar % DOFs == 2 ) THEN
              dX(1:n) = Dvar % EigenVectors(EigenModes(j),2*DvarPerm(1:n)-1)
              dY(1:n) = Dvar % EigenVectors(EigenModes(j),2*DvarPerm(1:n))
              dZ(1:n) = 0.0d0
            ELSE
              dX(1:n) = Dvar % EigenVectors(EigenModes(j),3*DvarPerm(1:n)-2)
              dY(1:n) = Dvar % EigenVectors(EigenModes(j),3*DvarPerm(1:n)-1)
              dZ(1:n) = Dvar % EigenVectors(EigenModes(j),3*DvarPerm(1:n))
            END IF
            
            DO i=1,n
              ElemAmplitude(j,i) = AmplitudeOverPlane(ElementNodes % x(i), &
                  ElementNodes % y(i), ElementNodes % z(i), &
                  dX(i), dY(i), dZ(i), ReferencePlane) 
            END DO
          END DO
        ELSE
          
          ElemAperture(1:n) = ListGetReal( Material,'Reference Aperture',n,NodeIndexes)
          DO i=1,n
            DO j=1,NoAmplitudes
              ElemAmplitude(j,i) = Dvar % EigenVectors(EigenModes(j), &
                  Dvar % DOFs * (DvarPerm(i)-1) + NormalDirection )
              IF(ElemAperture(i) < 0.0) ElemAmplitude(j,i) = -ElemAmplitude(j,i) 
            END DO
            ElemAperture(i) = ABS(ElemAperture(i))
          END DO
        END IF
        
      ELSE IF (NoEigenModes == 0) THEN
        
        IF(ReferencePlaneExists) THEN          
          DvarPerm(1:n) = Dvar % Perm(NodeIndexes(1:n))
          IF ( DVar % DOFs == 2 ) THEN
            dX(1:n) = Dvar % Values(2*DvarPerm(1:n)-1)
            dY(1:n) = Dvar % Values(2*DvarPerm(1:n))
            dZ(1:n) = 0.0d0
          ELSE
            dX(1:n) = Dvar % Values(3*DvarPerm(1:n)-2)
            dY(1:n) = Dvar % Values(3*DvarPerm(1:n)-1)
            dZ(1:n) = Dvar % Values(3*DvarPerm(1:n))
          END IF
          
          DO i=1,n
            ElemAperture(i) = DistanceFromPlane( ElementNodes % x(i)-dx(i), &
                ElementNodes % y(i)-dy(i), ElementNodes % z(i)-dz(i), ReferencePlane)
            ElemAmplitude(1,i) = AmplitudeOverPlane(ElementNodes % x(i)-dx(i), &
                ElementNodes % y(i)-dy(i), ElementNodes % z(i)-dz(i), &
                dX(i), dY(i), dZ(i), ReferencePlane) 
          END DO

        ELSE
          ElemAperture(1:n) = ListGetReal( Material,'Reference Aperture',n,NodeIndexes)
          DO i=1,n
            ElemAmplitude(1,i) = Dvar % Values(&
                Dvar % DOFs * (DvarPerm(i)-1) + NormalDirection )
            ElemAperture(i) = ElemAperture(i) + ElemAmplitude(1,i)
            IF(ElemAperture(i) < 0.0) THEN
              ElemAmplitude(1,i) = -ElemAmplitude(1,i) 
              ElemAperture(i) = -ElemAperture(i)
            END IF
          END DO          
        END IF
      END IF


    ELSE IF(Shell) THEN
      DvarPerm(1:n) = Dvar % Perm(NodeIndexes(1:n))

      IF (NoEigenModes > 0) THEN
        IF(ReferencePlaneExists) THEN
          DO i=1,n
            ElemAperture(i) = DistanceFromPlane( ElementNodes % x(i), &
                ElementNodes % y(i), ElementNodes % z(i), ReferencePlane)
          END DO
          
          DO j=1,NoEigenModes
            ElemAmplitude(j,1:n) = Dvar % EigenVectors &
                (EigenModes(j),Dvar%DOFs*(DvarPerm(1:n)-1)+1)          
          END DO
          
          IF(Shell2) THEN
            DvarPerm(1:n) = Dvar2 % Perm(NodeIndexes(1:n))          
            ElemAperture(1:n) = ElemAperture(1:n) &
                + (Dvar2 % Values(Dvar2%DOFs * (DvarPerm(1:n)-1)+1))
          END IF
        ELSE
          
          ElemAperture(1:n) = ListGetReal( Material,'Reference Aperture',n,NodeIndexes)
          DO i=1,n
            DO j=1,NoEigenModes
              ElemAmplitude(j,i) = Dvar % EigenVectors &
                  (EigenModes(j), Dvar%DOFs*(DvarPerm(i)-1)+1) 
              IF(ElemAperture(i) < 0.0) ElemAmplitude(j,i) = -ElemAmplitude(j,i)              
            END DO
            IF(Shell2) THEN              
              ElemAperture(i) = ElemAperture(i) - &
                  (Dvar2 % Values(Dvar2 %DOFs * (DvarPerm(i)-1)+1))
            END IF
          END DO          
        END IF


      ELSE IF (NoEigenModes == 0) THEN

        IF(ReferencePlaneExists) THEN
          DO i=1,n
            ElemAperture(i) = DistanceFromPlane( ElementNodes % x(i), &
                ElementNodes % y(i), ElementNodes % z(i), ReferencePlane)
          END DO
                    
          ElemAmplitude(1,1:n) = Dvar % Values(Dvar%DOFs*(DvarPerm(1:n)-1)+1)
          
          IF(Shell2) THEN
            DvarPerm(1:n) = Dvar2 % Perm(NodeIndexes(1:n))          
            ElemAmplitude(1,1:n) = ElemAmplitude(1,1:n) - &
                Dvar2 % Values(Dvar%DOFs*(DvarPerm(1:n)-1)+1)
          END IF
        ELSE

          ElemAperture(1:n) = ListGetReal( Material,'Reference Aperture',n,NodeIndexes)
          ElemAmplitude(1,1:n) = Dvar % Values(Dvar%DOFs*(DvarPerm(1:n)-1)+1)

          IF(Shell2) THEN
            DvarPerm(1:n) = Dvar2 % Perm(NodeIndexes(1:n))          
            ElemAmplitude(1,1:n) = ElemAmplitude(1,1:n) - &
                Dvar2 % Values(Dvar%DOFs*(DvarPerm(1:n)-1)+1)
          END IF
          DO i=1,n
            IF(ElemAperture(i) < 0.0) THEN
              ElemAmplitude(1,i) = -ElemAmplitude(1,i)              
              ElemAperture(i) = -ElemAperture(i)
            END IF
          END DO

        END IF

      END IF
    ENDIF


    ! In transient simulation the speed is obtained from the time
    ! derivative. Amplitude is now a sign off average mobility.
    IF(TransientSimulation) THEN
      ElemAperture(1:n) = ElemAperture(1:n) + ElemAmplitude(1,1:n)
      
      IF(.NOT. Visited) THEN
        ElemApertureVelocity(1:n) = ElemAmplitude(1,1:n) / dt
      ELSE
        ElemApertureVelocity(1:n) = ( ElemAperture(1:n) -  &
            PrevAperture(AperturePerm(NodeIndexes(1:n)),1) ) / dt
      END IF
    END IF
      
    Aperture(AperturePerm(NodeIndexes(1:n))) = ElemAperture(1:n)
    MaxAperture = MAX(MaxAperture,MAXVAL(ElemAperture(1:n)))
    MinAperture = MIN(MinAperture,MINVAL(ElemAperture(1:n)))

    IF(TransientSimulation) THEN
      ApertureVelocity(AperturePerm(NodeIndexes(1:n))) = ElemApertureVelocity(1:n)      
      MaxApertureVelocity = MAX(MaxApertureVelocity,MAXVAL(ElemApertureVelocity(1:n)))
      MinApertureVelocity = MIN(MaxApertureVelocity,MINVAL(ElemApertureVelocity(1:n)))
    ELSE
      DO j=1,NoAmplitudes
        Amplitude(NoAmplitudes*(AperturePerm(NodeIndexes(1:n))-1)+j) = &
            ElemAmplitude(j,1:n)
      END DO
    END IF
      
    IF(NoEigenModes == 0) THEN
      ElemDensity(1:n) = ListGetReal( Material, 'Density',n, NodeIndexes(1:n), GotIt)
      IF(.NOT. GotIt) ElemDensity(1:n) = 1.0d0
      IF(Shell) ElemThickness(1:n) = ListGetReal( Material, 'Thickness',n, NodeIndexes(1:n), GotIt)
      IF(.NOT. GotIt) ElemThickness(1:n) = 1.0d0
    END IF

    CALL LumpedIntegral(n, Model, ElementNodes, CurrentElement, &
        ElemAmplitude, ElemDensity, ElemThickness)

  END DO

  IF(TransientSimulation) THEN
    Amplitude = Amplitude + dt * ABS(ApertureVelocity)
  END IF

  ! Normalize amplitude to unity 

  DO j=1,NoAmplitudes
    MaxAmplitudes(j) = MAXVAL(Amplitude(j::NoAmplitudes))
    MinAmplitudes(j) = MINVAL(Amplitude(j::NoAmplitudes))

    IF(MaxAmplitudes(j) < -MinAmplitudes(j)) MaxAmplitudes(j) = MinAmplitudes(j)

    IF(ABS(MaxAmplitudes(j)) <= TINY(MaxAmplitudes(j)) ) THEN
      Amplitude(j::NoAmplitudes) = 1.0d0
    ELSE
      Amplitude(j::NoAmplitudes) = Amplitude(j::NoAmplitudes)/MaxAmplitudes(j)
    END IF

    IF(NoEigenModes == 0 .AND. Shell) THEN
      IF(ABS(MaxAmplitudes(j)) <= TINY(MaxAmplitudes(j)) ) THEN
        ElasticMass(j) = 0.0d0
      ELSE        
        ElasticMass(j) = ElasticMass(j) / MaxAmplitudes(j)**2.0
      END IF
    END IF
  END DO


  DO j=1,NoEigenModes
    AngularVelocity(j) = SQRT( DVar % EigenValues(EigenModes(j)) )
    ElasticMass(j) = 1.0d0 / (MaxAmplitudes(j) ** 2.0)
    ElasticSpring(j) = DVar % EigenValues(EigenModes(j)) / MaxAmplitudes(j) ** 2.0
  END DO

  WRITE(Message,'(A,T35,ES15.4)') 'Minimum Aperture (m): ',MinAperture
  CALL Info('ApertureAmplitude',Message,Level=5)
  CALL ListAddConstReal( Model % Simulation,'res: Minimum Aperture', MinAperture)
  
  WRITE(Message,'(A,T35,ES15.4)') 'Maximum Aperture (m): ',MaxAperture
  CALL Info('ApertureAmplitude',Message,Level=5)
  CALL ListAddConstReal( Model % Simulation,'res: Maximum Aperture', MaxAperture)

  
  IF(NoEigenModes == 0) THEN
    IF(TransientSimulation) THEN
      WRITE(Message,'(A,T35,ES15.4)') 'Minimum d(Aperture)/dt (m/s): ',MinApertureVelocity
      CALL Info('ApertureAmplitude',Message,Level=5)
      
      WRITE(Message,'(A,T35,ES15.4)') 'Maximum d(Aperture)/dt (m/s): ',MaxApertureVelocity
      CALL Info('ApertureAmplitude',Message,Level=5)
      
      CALL ListAddConstReal( Model % Simulation, &
          'res: Elastic Travel', MaxAmplitudes(1))
    ELSE IF(NoEigenModes == 0) THEN
      CALL ListAddConstReal( Model % Simulation, &
          'res: Elastic Displacement', MaxAmplitudes(1))
    END IF
    IF(Shell) THEN
      CALL ListAddConstReal( Model % Simulation,'res: Elastic Mass', ElasticMass(1))
      WRITE(Message,'(A,T35,ES15.5)') 'Elastic Mass',ElasticMass(1)
      CALL Info('ApertureAmplitude',Message,Level=5)
    END IF
  ELSE

    IF(NoEigenModes > 1) THEN
      WRITE(Message,'(A,I2,A)') 'There are ',NoEigenModes,' eigen modes'    
      CALL Info('ApertureAmplitude',Message,Level=5)
    END IF
    
    DO j=1,NoEigenModes
      WRITE(Message,'(A)') 'Maximum Amplitude'
      WRITE(Message,'(A,I1)') TRIM('Maximum Amplitude')//' ',j
      CALL ListAddConstReal( Model % Simulation,'res: '//TRIM(Message),MaxAmplitudes(j))

      WRITE(Message,'(A,T35,ES15.5)') TRIM(Message)//':',MaxAmplitudes(j)
      CALL Info('ApertureAmplitude',Message,Level=5)

      WRITE(Message,'(A)') 'Eigen Frequency'
      WRITE(Message,'(A,I1)') TRIM(Message)//' ',j
      CALL ListAddConstReal( Model % Simulation, &
          'res: '//TRIM(Message), AngularVelocity(j)/(2.0d0 * PI))

      WRITE(Message,'(A,T35,ES15.5)') TRIM(Message),AngularVelocity(j)/(2.0d0*PI)
      CALL Info('ApertureAmplitude',Message,Level=5)

      WRITE(Message,'(A)') 'Elastic Mass'
      WRITE(Message,'(A,I1)') TRIM(Message)//' ',j
      CALL ListAddConstReal( Model % Simulation, &
          'res: '//TRIM(Message), ElasticMass(j))

      WRITE(Message,'(A,T35,ES15.5)') TRIM(Message),ElasticMass(j)
      CALL Info('ApertureAmplitude',Message,Level=5)

      WRITE(Message,'(A)') 'Elastic Spring'
      WRITE(Message,'(A,I1)') TRIM(Message)//' ',j
      CALL ListAddConstReal( Model % Simulation, &
          'res: '//TRIM(Message), ElasticSpring(j))

      WRITE(Message,'(A,T35,ES15.5)') TRIM(Message),ElasticSpring(j)
      CALL Info('ApertureAmplitude',Message,Level=5)
    END DO
  END IF

!-----------------------------------------------------------------------------------
!  Save parameters in a format that may be utilized by lumped mems models
!-----------------------------------------------------------------------------------

  IF(AplacExport) THEN
    IF(MaxDim == 2 .AND. MinDim == MaxDim) THEN
      CALL ListAddConstReal( Model % Simulation, 'mems: aper area',Volume)
    END IF
    CALL ListAddInteger( Model % Simulation, 'mems: aper dim',MaxDim)
    CALL ListAddConstReal( Model % Simulation, 'mems: aper min',MinAperture)
    Work(1:1) = ListGetReal( Material, 'Tension',1, NodeIndexes(1:1), GotIt)
    IF(GotIt) CALL ListAddConstReal( Model % Simulation, 'mems: aper tension',Work(1))
    CALL ListAddInteger( Model % Simulation, 'mems: aper nomodes', NoEigenModes)
  END IF

  Visited = .TRUE.

CONTAINS

!------------------------------------------------------------------------------
! calculates the distance from plane a1*x+y2*y+a3*z=a4
!------------------------------------------------------------------------------
  FUNCTION DistanceFromPlane( x, y, z, a) RESULT(h)
    USE Types
    
    REAL(KIND=dp) :: x, y, z, a(:)
    REAL(KIND=dp) :: s, h
    
    s = SQRT(a(1)*a(1)+a(2)*a(2)+a(3)*a(3))
    h = (a(1)*x+a(2)*y+a(3)*z-a(4))/s
    h = ABS(h) ! ABS?  

  END FUNCTION DistanceFromPlane
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
  FUNCTION AmplitudeOverPlane( x, y, z, dx, dy, dz, a) RESULT(dh)
!------------------------------------------------------------------------------
    USE Types
    
    REAL(KIND=dp) :: x, y, z, dx, dy, dz, a(:)
    REAL(KIND=dp) :: s, h, dh
    
    s = SQRT(a(1)*a(1)+a(2)*a(2)+a(3)*a(3))
    h = (a(1)*x+a(2)*y+a(3)*z-a(4))/s
    dh = (dx*a(1)+dy*a(2)+dz*a(3))/s
    IF(h < 0.0d0) dh = -dh

  END FUNCTION AmplitudeOverPlane
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   SUBROUTINE LumpedIntegral(n, Model, ElementNodes, CurrentElement, &
       Amplitude, Density, Thickness)
!------------------------------------------------------------------------------
     INTEGER :: n
     TYPE(Model_t) :: Model
     TYPE(Nodes_t) :: ElementNodes
     TYPE(Element_t), POINTER :: CurrentElement
     REAL(KIND=dp) :: Amplitude(:,:), Density(:), Thickness(:)

!------------------------------------------------------------------------------
     
     TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff
     REAL(KIND=dp), DIMENSION(:), POINTER :: &
         U_Integ,V_Integ,W_Integ,S_Integ
     REAL(KIND=dp) :: s,ug,vg,wg
     REAL(KIND=dp) :: ddBasisddx(Model % MaxElementNodes,3,3)
     REAL(KIND=dp) :: Basis(Model % MaxElementNodes)
     REAL(KIND=dp) :: dBasisdx(Model % MaxElementNodes,3),SqrtElementMetric
     REAL(KIND=dp) :: dV, Amplitudei, Amplitudej
     INTEGER :: N_Integ, t, tg, ii, jj, i,j,k,l
     LOGICAL :: stat

!------------------------------------------------------------------------------
!    Gauss integration stuff
!-----------------------------------------------------------------------------

     IntegStuff = GaussPoints( CurrentElement )
     U_Integ => IntegStuff % u
     V_Integ => IntegStuff % v
     W_Integ => IntegStuff % w
     S_Integ => IntegStuff % s
     N_Integ =  IntegStuff % n

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
       stat = ElementInfo( CurrentElement,ElementNodes,ug,vg,wg, &
           SqrtElementMetric,Basis,dBasisdx,ddBasisddx,.FALSE. )

       s = SqrtElementMetric * S_Integ(tg)
 
       dV = CoordinateSqrtMetric( SUM( ElementNodes % x(1:n) * Basis(1:n)), &
           SUM( ElementNodes % y(1:n) * Basis(1:n)), &
           SUM( ElementNodes % z(1:n) * Basis(1:n)) )
 
! Calculate the function to be integrated at the Gauss point

       IF(NoEigenModes == 0) THEN
         DO i=1,NoAmplitudes         
           Amplitudei = SUM(Amplitude(i,1:n) * Basis(1:n))
           IF(Shell) THEN
             ElasticMass(i) = ElasticMass(i) +  &
                 s * dV * Amplitudei**2.0 * SUM(Thickness(1:n) * Density(1:n) * Basis(1:n))        
           ELSE
             ElasticMass(i) = ElasticMass(i) +  &
                 s * dV * Amplitudei**2.0 * SUM(Density(1:n) * Basis(1:n))        
           END IF
         END DO
       END IF

       Volume = Volume + s * dV 

     END DO! of the Gauss integration points
       
!------------------------------------------------------------------------------
   END SUBROUTINE LumpedIntegral
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
END SUBROUTINE ApertureAmplitude
!------------------------------------------------------------------------------



