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
! ****************************************************************************/
!
!/*****************************************************************************
! *
! *            Module Author: Peter R�back
! *
! *                  Address: CSC - Scientific Computing Ltd.
! *                           Tekniikantie 15 a D, Box 405
! *                           02101 Espoo, Finland
! *                           Tel. +358 0 457 2080
! *                           Telefax: +358 0 457 2302
! *                    EMail: Peter.Raback@csc.fi
! *
! *                     Date: 20 Nov 2001
! *
! *               Modified by: 
! *                     EMail: 
! *
! *      Date of modification: 
! *
! ****************************************************************************/


!------------------------------------------------------------------------------
SUBROUTINE MEMLumping( Model,Solver,dt,TransientSimulation )
  !DEC$ATTRIBUTES DLLEXPORT :: MEMLumping
!------------------------------------------------------------------------------
!******************************************************************************
!
!  This subroutine reads in some computed variables and makes a lumped
!  model describing some MEMS resonator. The subroutine may be used
!  as an external solver in Elmer computations.
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
  USE DefUtils

  IMPLICIT NONE
!------------------------------------------------------------------------------
  TYPE(Solver_t), TARGET :: Solver
  TYPE(Model_t) :: Model
  REAL(KIND=dp) :: dt
  LOGICAL :: TransientSimulation
!------------------------------------------------------------------------------
! Local variables
!------------------------------------------------------------------------------

  LOGICAL :: SubroutineVisited=.FALSE., GotIt, GotIt2, EigenFrequency, &
      GotDamp
  CHARACTER(LEN=MAX_NAME_LEN) :: AplacFile, String1, String2
  INTEGER :: i,j,k,l, DIM, NoEigenModes, ElstatMode, ReynoMode, NoModes
  INTEGER, POINTER :: EigenModes(:)
  REAL(KIND=dp) :: Const1, Const2
  REAL(KIND=dp) :: Mm, Km, Ke, Fe, Kf, Gf, W, Q, V0, C0, dCdz, Grav, &
      dKfdZ, dKedZ, Sens, Pres0, Area 
  REAL(KIND=dp), POINTER :: Gravity(:,:)
  COMPLEX(KIND=dp) :: Omega, Disc
  CHARACTER(LEN=MAX_NAME_LEN) :: VersionID = "$Id: MEMLumping.f90,v 1.5 2005/03/09 15:18:14 raback Exp $"

  SAVE SubroutineVisited

  CALL Info('MEMLumping','Computing a lumped model for the MEM resonator')

!------------------------------------------------------------------------------
!    Check if version number output is requested
!------------------------------------------------------------------------------
  IF ( ListGetLogical( GetSimulation(), 'Output Version Numbers', GotIt ) ) THEN
    CALL Info( 'MEMLumping', 'MEMLumping version:', Level = 0 ) 
    CALL Info( 'MEMLumping', VersionID, Level = 0 ) 
    CALL Info( 'MEMLumping', ' ', Level = 0 ) 
  END IF
!------------------------------------------------------------------------------

  EigenModes => ListGetIntegerArray( Model % Simulation, 'MEM Eigen Modes',gotIt )

  IF(gotIt) THEN
    NoEigenModes = SIZE(EigenModes)
  ELSE
    NoEigenModes = 0
  END IF
  NoModes = MAX(1,NoEigenModes)

  String1 = ListGetString(Solver % Values,'MEM Sensor',GotIt)

  DO j=1,NoModes

    ! Mechanical parameters
    WRITE(Message,'(A,I1)') 'res: Elastic Mass ',j
    Mm = ListGetConstReal( Model % Simulation, Message, GotIt)
    IF(.NOT. GotIt) CALL ComputeLumpedMass(Mm)
   
    WRITE(Message,'(A,I1)') 'res: Elastic Spring ',j
    Km = ListGetConstReal( Model % Simulation, Message, GotIt) 
    IF(.NOT. GotIt) THEN
      Km = ListGetConstReal( Model % Simulation, 'res: Elastic Spring', GotIt) 
    END IF
    
    ! Electrical parameters
    C0 = ListGetConstReal( Model % Simulation,'res: Capacitance',gotIt )
    WRITE(Message,'(A,I1,I1)') 'res: Electric Spring ',j,j
    Ke = ListGetConstReal( Model % Simulation, Message, gotIt )
    
    WRITE(Message,'(A,I1)') 'res: Electric Force ',j
    Fe = ListGetConstReal( Model % Simulation, Message, gotIt )
    
    ! Fluidic parameters
    WRITE(Message,'(A,I1,I1)') 'res: Fluidic Spring ',j,j
    Kf = ListGetConstReal( Model % Simulation, Message, GotIt) 

    WRITE(Message,'(A,I1,I1)') 'res: Fluidic Damping ',j,j
    Gf = ListGetConstReal( Model % Simulation, Message, GotDamp) 
    
    Gf = -Gf
    Kf = ABS(Kf)
    Ke = -ABS(Ke)

    ! Compute the coupled system resonance frequency
    Disc = Gf**2.0 - 4.0 * Mm * (Km + Ke + Kf) 
    Omega = (-Gf + SQRT(Disc) ) / (2.0 * Mm)
    W = ABS(AIMAG(Omega)) / (2.0 * PI)

    IF(W < 1.0d-20) THEN
      WRITE(Message,'(A,T35,ES15.5)') 'The resonator is critically damped',REAL(Omega)
      CALL Info('MEMLumping',Message,Level=5)
    ELSE
      
      WRITE(Message,'(A,I1,A,T35,ES15.5)') 'Coupled Eigen Frequency ',j,':',W 
      CALL Info('MEMLumping',Message,Level=5)
      IF(ListGetLogical(Solver % Values,'Set Coupled Eigen Frequency',GotIt)) THEN
        WRITE(Message,'(A,I1)') 'res: Coupled Eigen Frequency ',j
        CALL ListAddConstReal( Model % Simulation, Message, W)
      END IF

    END IF

    ! Compute the figures of merit
    IF( Km + Ke + Kf > 0.0d0 .AND. GotDamp) THEN
      Q = SQRT(Mm * (Km + Ke + Kf)) / ABS(Gf)
      WRITE(Message,'(A,I1)') 'res: Q-value ',j
      
      CALL ListAddConstReal( Model % Simulation, Message, Q)
      WRITE(Message,'(A,I1,A,T35,ES15.5)') 'Q-value ',j,':',Q
      CALL Info('MEMLumping',Message,Level=5)     
    END IF

    WRITE(Message,'(A,I1)') 'res: Electric Current Sensitivity ',j    
    dCdz = ListGetConstReal( Model % Simulation, Message, GotIt)
    IF(.NOT. GotIt) CYCLE
    
    IF(TRIM(String1) == 'acceleration') THEN

      IF(ABS(Km + Ke) > 1.0d-20) THEN
        Sens = ABS( (dCdz / C0) * Mm / (Km + Ke) )
        CALL ListAddConstReal( Model % Simulation, 'res: Inertial Sensitivity', Sens)
        WRITE(Message,'(A,T35,ES15.5)') 'Inertial sensitivity:',Sens 
        CALL Info('MEMLumping',Message,Level=5)
        
        Gravity => ListGetConstRealArray( Model % Constants,'Gravity',GotIt) 
        IF(GotIt) THEN
          Grav = MAXVAL(Gravity)
        ELSE
          Grav = 9.81d0
        END IF
        V0 = ListGetConstReal( Model % Simulation,'res: Max Potential',gotIt )
        IF(.NOT. GotIt) CYCLE
        
        Sens = Grav * Sens / V0        
        CALL ListAddConstReal( Model % Simulation, 'res: Inertial Sensitivity Nondim', Sens)    
        WRITE(Message,'(A,T35,ES15.5)') 'Inertial sensitivity nondim:',Sens 
        CALL Info('MEMLumping',Message,Level=5)

        dKedZ  = ListGetConstReal( Model % Simulation,'res: Electric Spring Dz',GotIt) 
        dKfdZ  = ListGetConstReal( Model % Simulation,'res: Fluidic Spring Dz',GotIt)         
        IF(GotIt .AND. ABS(Mm * Grav) > 1.0d-20)  THEN
          Sens = (V0 * C0 / dCdZ)**2.0 * (dKedZ + dKfdZ) / (Mm * Grav)
          Sens = ABS(Sens)
          CALL ListAddConstReal( Model % Simulation, 'res: Offset Sensitivity', Sens)
          WRITE(Message,'(A,T35,ES15.5)') 'Offset sensitivity:',Sens
          CALL Info('MEMLumping',Message,Level=5)
        END IF
      END IF

    ELSE IF(TRIM(String1) == 'pressure') THEN

      Area = ABS( ListGetConstReal( Model % Simulation,'res: lumping factor u^1',GotIt) )
      IF(.NOT. GotIt) Area = ListGetConstReal( Model % Simulation,'res: fluidic area',GotIt) 
      IF(.NOT. GotIt) Area = ListGetConstReal( Model % Simulation,'res: charged area',GotIt) 

      IF( ABS(Km + Ke) > 1.0d-20) THEN 
        Sens = ABS( (dCdz / C0) * Area / (Km + Ke) )
        CALL ListAddConstReal( Model % Simulation, 'res: Pressure Sensitivity', Sens)
        WRITE(Message,'(A,T35,ES15.5)') 'Pressure sensitivity:',Sens
        CALL Info('MEMLumping',Message,Level=5)
        
        V0 = ListGetConstReal( Model % Simulation,'res: Max Potential',gotIt )
        IF(.NOT. GotIt) CYCLE
        
        Pres0 = 1.013d5
        Sens = Pres0 * Sens / V0        
        CALL ListAddConstReal( Model % Simulation, 'res: Pressure Sensitivity Nondim', Sens)
        WRITE(Message,'(A,T35,ES15.5)') 'Pressure sensitivity nondim:',Sens
        CALL Info('MEMLumping',Message,Level=5)
      END IF

    END IF

  END DO



  IF(ListGetLogical(Solver % Values,'Aplac Export',GotIt)) THEN
    DIM = CoordinateSystemDimension()
    
    AplacFile = ListGetString(Solver % Values,'Filename',GotIt )
    IF(.NOT. GotIt) WRITE(AplacFile,*) 'Elmer2Aplac.e2a'
    
    CALL Info('MEMLumping','------------------------------------------------------',Level=5)
    WRITE(Message,*) 'Making lumped Aplac model into file',TRIM(AplacFile)
    CALL Info('MEMLumping',Message)
    CALL Info('MEMLumping','------------------------------------------------------',Level=5)
    
    ElstatMode = ListGetInteger( Model % Simulation, 'mems: elstat mode', GotIt)
    ReynoMode = ListGetInteger( Model % Simulation, 'mems: reyno mode', GotIt)
    
    OPEN (10, FILE=AplacFile)
    
    IF(NoEigenModes > 0) THEN
      WRITE(10,'(A)') '$ eigenmode basis resonator'
    ELSE
      WRITE(10,'(A)') '$ statically biased resonator'    
    END IF
    
    ! Save some parameters for identification if they exist
    Const1 = ListGetConstReal( Model % Simulation, 'mems: aper area',GotIt)
    IF(GotIt) WRITE(10,'(A,E10.3)') '$ resonator area',Const1
    Const1 = ListGetConstReal( Model % Simulation, 'mems: aper vol',GotIt)
    IF(GotIt) WRITE(10,'(A,E10.3)') '$ resonator volume',Const1
    Const1 = ListGetConstReal( Model % Simulation, 'mems: aper min',GotIt)
    IF(GotIt) WRITE(10,'(A,E10.3)') '$ minimum gap',Const1
    Const1 = ListGetConstReal( Model % Simulation, 'mems: elstat voltage',GotIt)
    IF(GotIt) WRITE(10,'(A,E10.3)') '$ bias voltage',Const1
    Const1 = ListGetConstReal( Model % Simulation, 'mems: aper tension',GotIt)
    IF(GotIt) WRITE(10,'(A,E10.3)') '$ tension',Const1
        
    ! Make the model for the elastic resonator    
    WRITE(10,'(A)') ''
    WRITE(10,'(A)') 'Model "reso-parameters" USER_MODEL'
    
    IF(NoEigenModes > 0) THEN
      WRITE(10,'(A,I2,T35,A)') '+ N=',NoEigenModes,'$ number of eigenmodes'
      DO i=1,NoEigenModes
        WRITE(String1,'(A,I1)') 'res: elastic mass ',i
        Const1 = ListGetConstReal( Model % Simulation, String1, GotIt) 
        WRITE(String2,'(A,I1)') 'res: elastic spring ',i
        Const2 = ListGetConstReal( Model % Simulation, String2, GotIt2) 
        
        IF(NoEigenModes == 1) THEN
          IF(GotIt) WRITE(10,'(A,ES13.6,T35,A)') '+ M=',Const1,'$ effective mass'
          IF(GotIt2) WRITE(10,'(A,ES13.6,T35,A)') '+ K=',Const2,'$ effective mechanical spring'
        ELSE
          IF(GotIt) WRITE(10,'(A,I1,A,ES13.6,T35,A,I1)') '+ M',i,'=',&
              Const1,'$ effective mass ',i
          IF(GotIt2) WRITE(10,'(A,I1,A,ES13.6,T35,A,I1)') '+ K',i,'=',&
              Const2,'$ effective mechanical spring ',i
        END IF
      END DO
    ELSE 
      Const1 = ListGetConstReal( Model % Simulation,'res: Elastic Mass', GotIt) 
      IF(GotIt) WRITE(10,'(A,ES13.6,T35,A)') '+ M=',Const1,'$ effective mass'    

      Const1 = ListGetConstReal( Model % Simulation, 'mems: elstat displ', GotIt)
      Const2 = ListGetConstReal( Model % Simulation, 'mems: elstat force 1', GotIt2)
      IF(GotIt .AND. GotIt2) THEN
        WRITE(10,'(A,ES13.6,T35,A)') '+ K=',Const2/Const1,'$ effective mechanical spring'
      ELSE
        CALL Warn('AplacExport','Cant make lumped model for elasticity')
      END IF
    END IF
    
    
    ! Make the model for electrostatics
    WRITE(10,'(A)') ''
    WRITE(10,'(A)') 'Model "transducer-parameters" USER_MODEL'
    
    IF(ElstatMode == 1) THEN 
      WRITE(10,'(A,I2,T35,A)') '+ N=',NoEigenModes,'$ number of eigenmodes'
      Const1 = ListGetConstReal( Model % Simulation,'mems: elstat capa', GotIt)
      IF(GotIt) WRITE(10,'(A,ES13.6,T35,A)') '+ CE=',Const1,'$ capacitance'
      
      DO i=1,NoEigenModes
        WRITE(String1,'(A,I1)') 'mems: elstat charge ',i
        Const1 = ListGetConstReal( Model % Simulation, String1, GotIt)
        IF(NoEigenModes == 1) THEN
          IF(GotIt) WRITE(10,'(A,ES13.6,T35,A)') '+ IE=',&
              Const1,'$ el.mech transconductance'
        ELSE
          IF(GotIt) WRITE(10,'(A,I1,A,ES13.6,T35,A,I1)') '+ IE',i,'=',&
              Const1,'$ el.mech transconductance',i
        END IF
        
        DO j=1,NoEigenModes
          WRITE(String1,'(A,I1,I1)') 'mems: elstat spring ',i,j
          Const1 = ListGetConstReal( Model % Simulation, String1, GotIt)
          
          IF(NoEigenModes == 1) THEN
            IF(GotIt) WRITE(10,'(A,ES13.6,T35,A)') '+ KE=',&
                Const1,'$ electric spring coefficient'
          ELSE
            IF(GotIt) WRITE(10,'(A,I1,I1,A,ES13.6,T35,A,I1,I1)') '+ KE',i,j,'=',&
                Const1,'$ electric spring coefficient',i,j
          END IF
        END DO
      END DO
    ELSE IF(ElstatMode == 2) THEN
      WRITE(10,'(A)') '$ Capacitance is fitted to a physical model'
      WRITE(10,'(A)') '$ C = C0 * (B0 + B1 p + B2 (1+p)^a + B3 (1-p)^a), p=D/D0'
      
      Const1 = ListGetConstReal( Model % Simulation,'mems: elstat capa', GotIt)
      IF(GotIt) WRITE(10,'(A,ES13.6,T35,A)') '+ CE=',Const1,'$ capacitance at rest, C0'
      Const1 = ListGetConstReal( Model % Simulation,'mems: elstat zcrit', GotIt)
      IF(GotIt) WRITE(10,'(A,ES13.6,T35,A)') '+ D0=',Const1,'$ critical displacement, D0'
      Const1 = ListGetConstReal( Model % Simulation,'mems: elstat c5', GotIt)
      IF(GotIt) WRITE(10,'(A,ES13.6,T35,A)') '+ B0=',Const1,'$ factor for p^0, B0'
      Const1 = ListGetConstReal( Model % Simulation,'mems: elstat c4', GotIt)
      IF(GotIt) WRITE(10,'(A,ES13.6,T35,A)') '+ B1=',Const1,'$ factor for p^1, B1'
      Const1 = ListGetConstReal( Model % Simulation,'mems: elstat c3', GotIt)
      IF(GotIt) WRITE(10,'(A,ES13.6,T35,A)') '+ B2=',Const1,'$ factor for (1+p)^a, B2'
      Const1 = ListGetConstReal( Model % Simulation,'mems: elstat c2', GotIt)
      IF(GotIt) WRITE(10,'(A,ES13.6,T35,A)') '+ B3=',Const1,'$ factor for (1-p)^a, B3'
      Const1 = ListGetConstReal( Model % Simulation,'mems: elstat c1', GotIt)
      IF(GotIt) WRITE(10,'(A,ES13.6,T35,A)') '+ Ea=',Const1,'$ exponent a'
    ELSE
      CALL Warn('AplacExport','Electrostatics export format is unknown')
    END IF
    
    ! In some cases the fluidic resistance may be computed by a local approximation
    ! and the the solution of Reynolds equations is not necessary
    IF(ReynoMode == 0 .AND. ElstatMode > 0) THEN
      WRITE(10,'(A)') ''
      
      Const1 = ListGetConstReal( Model % Simulation, 'mems: elstat aeff1', GotIt)
      IF(GotIt) WRITE(10,'(A,ES13.6,T35,A)') 'Var Aeff1 ',Const1,'$ effective area u'
      Const1 = ListGetConstReal( Model % Simulation, 'mems: elstat aeff2', GotIt)
      IF(GotIt) WRITE(10,'(A,ES13.6,T35,A)') 'Var Aeff2 ',Const1,'$ effective area u^2'
      Const1 = ListGetConstReal( Model % Simulation, 'mems: elstat deff3', GotIt)
      IF(GotIt) WRITE(10,'(A,ES13.6,T35,A)') 'Var Deff3 ',Const1,'$ effective distance'
      Const1 = ListGetConstReal( Model % Simulation, 'mems: elstat displ', GotIt)
      IF(GotIt) WRITE(10,'(A,ES13.6,T35,A)') 'Var Displ ',Const1,'$ static displacement'
      Const1 = ListGetConstReal( Model % Simulation, 'mems: elstat thick', GotIt)
      IF(GotIt) WRITE(10,'(A,ES13.6,T35,A)') 'Var Dthick ',Const1,'$ diaphragm thickness'
      
    ELSE IF(ReynoMode == 1) THEN 
      
      WRITE(10,'(A)') ''
      WRITE(10,'(A)') 'Model "squeezed-film-parameters" USER_MODEL'
      
      
      DO i=1,NoEigenModes
        DO j=1,NoEigenModes
          WRITE(String1,'(A,I1,I1)') 'mems: reyno spring re ',i,j
          Const1 = ListGetConstReal( Model % Simulation, String1, GotIt)
          
          WRITE(String1,'(A,I1,I1)') 'mems: reyno damping ',i,j
          Const2 = ListGetConstReal( Model % Simulation, String1, GotIt)
          
          IF(NoEigenModes == 1) THEN
            IF(GotIt) WRITE(10,'(A,ES13.6,T35,A)') '+ KF=',&
                Const1,'$ fluidic spring coefficient'
            IF(GotIt) WRITE(10,'(A,ES13.6,T35,A)') '+ BF=',&
                Const2,'$ fluidic damping coefficient'
          ELSE
            IF(GotIt) WRITE(10,'(A,I1,I1,A,ES13.6,T35,A,I1,I1)') '+ KE',i,j,'=',&
                Const1,'$ fluidic spring coefficient ',i,j
            IF(GotIt) WRITE(10,'(A,I1,I1,A,ES13.6,T35,A,I1,I1)') '+ KE',i,j,'=',&
                Const2,'$ fluidic damping coefficient ',i,j
          END IF
        END DO
      END DO
      
    ELSE IF(ReynoMode == 2) THEN 
      
      WRITE(10,'(A)') ''
      WRITE(10,'(A)') 'Model "squeezed-film-parameters" USER_MODEL'
      WRITE(10,'(A)') '$ Fluidic spring constants fitted to a physical model'
      WRITE(10,'(A)') '$ Z = 1/(R+iwL), R=d^3/vA^2, L=d/AP'
      
      Const1 =  ListGetConstReal( Model % Simulation, 'mems: reyno cutoff',GotIt)
      IF(GotIt) WRITE(10,'(A,ES13.6,T35,A)') 'Var Cutoff ',Const1,'$ cutoff frequecy'
      Const1 =  ListGetConstReal( Model % Simulation, 'mems: reyno viscosity',GotIt)
      IF(GotIt) WRITE(10,'(A,ES13.6,T35,A)') 'Var Visc ',Const1,'$ viscosity'
      Const1 =  ListGetConstReal( Model % Simulation, 'mems: reyno refpres',GotIt)
      IF(GotIt) WRITE(10,'(A,ES13.6,T35,A)') 'Var Pres0 ',Const1,'$ reference pressure'
      Const1 =  ListGetConstReal( Model % Simulation, 'mems: reyno area',GotIt)
      IF(GotIt) WRITE(10,'(A,ES13.6,T35,A)') 'Var Area ',Const1,'$ fluidic area'
      
      DO i=1,NoEigenModes
        DO j=1,NoEigenModes
          WRITE(String1,'(A,I1,I1)') 'mems: reyno spring corr ',i,j
          Const1 = ListGetConstReal( Model % Simulation, String1, GotIt)
          IF(GotIt) WRITE(10,'(A,I1,I1,ES13.6,T35,A)') 'Var Lcorr ',i,j,Const1,'$ spring correction'
          
          WRITE(String1,'(A,I1,I1)') 'mems: reyno damping corr ',i,j
          Const1 = ListGetConstReal( Model % Simulation, String1, GotIt)
          IF(GotIt) WRITE(10,'(A,I1,I1,ES13.6,T35,A)') 'Var Rcorr ',i,j,Const1,'$ damping correction'
        END DO
      END DO
      
    ELSE
      CALL Warn('AplacExport','Fluidic export format is unknown')
    END IF

    CLOSE(10)
  END IF  


CONTAINS

  SUBROUTINE ComputeLumpedMass(Mm) 
    
    REAL(KIND=dp) :: Mm

    REAL(KIND=dp) :: vol
    TYPE(Element_t), POINTER :: Element
    TYPE(Nodes_t) :: ElementNodes
    TYPE(Element_t),POINTER :: CurrentElement
    TYPE(ValueList_t), POINTER :: Material
    TYPE(Variable_t), POINTER :: DVar, Dvar2
    TYPE(Solver_t), POINTER :: PSolver 
    TYPE(GaussIntegrationPoints_t) :: IntegStuff
        
    INTEGER :: iter, i, j, k, n, t, hits, istat, eq, NoAmplitudes, &
        mat_id, body_id, NormalDirection, NoEigenModes, ElemCorners, &
        p,q, ElemDim, MaxDim
    INTEGER, POINTER :: NodeIndexes(:), EigenModes(:), DvarPerm(:)
    
    LOGICAL :: AllocationsDone = .FALSE., GotIt, &
        Shell = .FALSE., Shell2 = .FALSE., Solid=.FALSE., stat
    
    REAL(KIND=dp) :: SqrtMetric,SqrtElementMetric, Metric(3,3),Symb(3,3,3),dSymb(3,3,3,3)
    REAL(KIND=dp) :: Basis(Solver % Mesh % MaxElementNodes),dBasisdx(Solver % Mesh % MaxElementNodes, 3), &
        ddBasisddx(Solver % Mesh % MaxElementNodes,3,3)
    REAL(KIND=dp) :: MaxAperture, CoordDiff(3), Mass, x, y, z, U, V, W, S
    REAL(KIND=dp), POINTER :: ElemAperture(:), ElemAmplitude(:,:), &
        ElemThickness(:), ElemDensity(:), AmplitudeComp(:), MaxAmplitudes(:)
    
    
    SAVE ElementNodes, ElemAperture, ElemAmplitude, AllocationsDone, DvarPerm, &
        ElemDensity, ElemThickness
    
    
!------------------------------------------------------------------------------
! Check variables needed for computing aperture and amplitude
!------------------------------------------------------------------------------

    NULLIFY(DVar)
    DVar => VariableGet( Model % Variables, 'Displacement' )
  
    IF (ASSOCIATED (DVar)) THEN
      Solid = .TRUE. 
      NormalDirection = ListGetInteger(Solver % Values,'Normal Direction',GotIt) 
      IF(.NOT. GotIt) THEN      
        NormalDirection = 1
        DO i=1,DVar % DOFs
          CoordDiff(i) = MAXVAL(Dvar % Values(Dvar % DOFs *(Dvar % Perm-1)+i)) - &
              MINVAL(Dvar % Values(Dvar % DOFs *(Dvar % Perm-1)+i))
          IF( CoordDiff(i) > CoordDiff(NormalDirection) )  NormalDirection = i
        END DO
      END IF
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
    
    IF(.NOT. (Shell .OR. Solid)) THEN 
      RETURN
    END IF

    EigenModes => ListGetIntegerArray( Model % Simulation, 'MEM Eigen Modes',gotIt )
    IF(gotIt) THEN
      NoEigenModes = SIZE(EigenModes)
    ELSE
      NoEigenModes = 0
    END IF
    
    IF(NoEigenModes > 0) THEN
      IF(.NOT. ASSOCIATED(Dvar % EigenVectors)) &
          CALL Fatal('LumpedMEMS','No EigenVectors exists!')
    END IF
    NoAmplitudes = MAX(1,NoEigenModes)


!------------------------------------------------------------------------------
! Allocate some permanent storage, this is done first time only
!------------------------------------------------------------------------------
 
    IF ( .NOT. AllocationsDone ) THEN
      N = Solver % Mesh % MaxElementNodes        
      ALLOCATE( ElementNodes % x( N ),  &
          ElementNodes % y( N ),       &
          ElementNodes % z( N ),       &
          DvarPerm(N),                &
          ElemAmplitude(NoAmplitudes,N),         &
          ElemThickness(N), &
          ElemDensity(N), &
          MaxAmplitudes(NoAmplitudes), &
          STAT=istat )
      IF ( istat /= 0 ) CALL FATAL('LumpedMEMS','Memory allocation error')
      AllocationsDone = .TRUE.
    END IF

!------------------------------------------------------------------------------
! Calculate the aperture and amplitude for later use and
! then normalize the amplitude.
!------------------------------------------------------------------------------

    hits = 0
    Mass = 0.0d0
    MaxDim = 0
    MaxAmplitudes = 0.0d0
    vol = 0.0d0
    
    
    DO t = 1, Solver % Mesh % NumberOfBulkElements 
      
      hits = hits + 1
      
      CurrentElement => Solver % Mesh % Elements( t )
      Model % CurrentElement => CurrentElement
      
      n = CurrentElement % TYPE % NumberOfNodes
      NodeIndexes => CurrentElement % NodeIndexes
      
      ElemCorners = CurrentElement % TYPE % ElementCode / 100
      IF(ElemCorners > 4) THEN
        ElemDim = 3
      ELSE IF(ElemCorners > 2) THEN
        ElemDim = 2
      ELSE
        ElemDim = ElemCorners
      END IF
      MaxDim = MAX(MaxDim,ElemDim)
      IF(ElemDim < MaxDim) CYCLE
      
      ElementNodes % x(1:n) = Solver % Mesh % Nodes % x(NodeIndexes(1:n))
      ElementNodes % y(1:n) = Solver % Mesh % Nodes % y(NodeIndexes(1:n))
      ElementNodes % z(1:n) = Solver % Mesh % Nodes % z(NodeIndexes(1:n))
      
      body_id = CurrentElement % BodyId
      mat_id = ListGetInteger( Model % Bodies( body_id ) % Values, &
          'Material', minv=1,maxv=Model % NumberOfMaterials )
      Material => Model % Materials(mat_id) % Values      
      DvarPerm(1:n) = Dvar % Perm(NodeIndexes(1:n))

      IF(Solid) THEN
        IF (NoEigenModes == 0) THEN
          ElemDensity(1:n) = ListGetReal( Material, 'Density', n, NodeIndexes(1:n), GotIt)          
          ElemAmplitude(1,1:n) = Dvar % Values(&
              Dvar % DOFs * (DvarPerm(1:n)-1) + NormalDirection )
        ELSE 
          DO j=1,NoAmplitudes
            ElemAmplitude(j,1:n) = Dvar % EigenVectors(EigenModes(j), &
                Dvar % DOFs * (DvarPerm(1:n)-1) + NormalDirection )
          END DO
        END IF
        
      ELSE IF(Shell) THEN     
        IF (NoEigenModes == 0) THEN
          ElemDensity(1:n) = ListGetReal( Material, 'Density',n, NodeIndexes(1:n), GotIt)          
          ElemThickness(1:n) = ListGetReal( Material, 'Thickness',n, NodeIndexes(1:n), GotIt)
          ElemAmplitude(1,1:n) = Dvar % Values(Dvar%DOFs*(DvarPerm(1:n)-1)+1)
          IF(Shell2) THEN
            DvarPerm(1:n) = Dvar2 % Perm(NodeIndexes(1:n))          
            ElemAmplitude(1,1:n) = ElemAmplitude(1,1:n) - &
                Dvar2 % Values(Dvar%DOFs*(DvarPerm(1:n)-1)+1)
          END IF
        ELSE          
          DO j=1,NoEigenModes
            ElemAmplitude(j,1:n) = Dvar % EigenVectors &
                (EigenModes(j), Dvar%DOFs*(DvarPerm(1:n)-1)+1) 
          END DO
        END IF
      END IF
      
      DO j=1,NoAmplitudes
        MaxAmplitudes(j) = MAX(MaxAmplitudes(j), MAXVAL(ABS(ElemAmplitude(j,1:n))))
      END DO
    
      IF(NoEigenModes > 0) CYCLE

      IntegStuff = GaussPoints( CurrentElement )

      DO i=1,IntegStuff % n

        U = IntegStuff % u(i)
        V = IntegStuff % v(i)
        W = IntegStuff % w(i)
!------------------------------------------------------------------------------
!        Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
        stat = ElementInfo( CurrentElement,ElementNodes,U,V,W,SqrtElementMetric, &
            Basis,dBasisdx,ddBasisddx,.FALSE. )
!------------------------------------------------------------------------------
!      Coordinatesystem dependent info
!------------------------------------------------------------------------------
        s = 1.0
        IF ( CurrentCoordinateSystem() /= Cartesian ) THEN
          x = SUM( ElementNodes % x(1:n)*Basis(1:n) )
          y = SUM( ElementNodes % y(1:n)*Basis(1:n) )
          z = SUM( ElementNodes % z(1:n)*Basis(1:n) )
          s = 2.0 * PI  
      
          IF(.FALSE.) THEN
            CALL CoordinateSystemInfo( Metric,SqrtMetric,Symb,dSymb,x,y,z )
            s = s * SqrtMetric 
          ELSE  
            s = s * x
          END IF
        END IF

        s = s * SqrtElementMetric * IntegStuff % s(i)
        vol =  vol + S

        IF(Solid) THEN
          Mass = Mass + s * SUM( Basis(1:n) * ElemAmplitude(1,1:n) **2.0 * ElemDensity(1:n) )
        ELSE
          Mass = Mass + s * SUM( Basis(1:n) * ElemAmplitude(1,1:n) **2.0 *  &
              ElemDensity(1:n) * ElemThickness(1:n))
        END IF
      END DO
    END DO

    IF(NoEigenModes == 0) THEN
      Mass = Mass / MaxAmplitudes(1) ** 2.0
      Mm = Mass
      
      WRITE(Message,'(A,I1,A,T35,ES15.5)') 'Elastic Mass ',1,':',Mass
      CALL Info('MEMLumping',Message,Level=5)    
      
      WRITE(Message,'(A,I1)') 'res: Elastic Mass ',1
      CALL ListAddConstReal(Model % Simulation,'res: Elastic Mass 1',Mass)
    END IF

  END SUBROUTINE ComputeLumpedMass
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
END SUBROUTINE MEMLumping
!------------------------------------------------------------------------------


