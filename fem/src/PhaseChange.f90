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
! *                Modified by:      Jussi Heikonen, Ville Savolainen, Peter R�back
! *
! *       Date of modification:      3.5.2004
! *
! *****************************************************************************/


!------------------------------------------------------------------------------
SUBROUTINE PhaseChange( Model,Solver,dt,TransientSimulation )
!DEC$ATTRIBUTES DLLEXPORT :: PhaseChange
!------------------------------------------------------------------------------
  USE CoordinateSystems
  USE SolverUtils
  USE Differentials
  USE Types
  USE Lists
  USE Integration
  USE ElementDescription
  USE GeneralUtils
  USE DefUtils

  IMPLICIT NONE
!------------------------------------------------------------------------------
!******************************************************************************
!
!  Solve the free surface profile in a phase change problem related to CZ crystal growth.
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
!            (NOTE: Not used currently)
!
!******************************************************************************
  TYPE(Model_t)  :: Model
  TYPE(Solver_t), TARGET :: Solver
  LOGICAL ::  TransientSimulation
  REAL(KIND=dp) :: dt
!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------
  TYPE(Element_t), POINTER :: CurrentElement, Parent, Element
  TYPE(Variable_t), POINTER :: SurfSol, TempSol
  TYPE(Nodes_t) :: Nodes, PNodes
  TYPE(GaussIntegrationPoints_t) :: IntegStuff  

  REAL(KIND=dp) :: Normal(3), TGrad(2,3), Jump(3), Gradi(2,3), Tempo(3), &
      u, v, w, ddBasisddx(1,1,1), &
      Density, AppPull, Update, MaxUpdate, MaxTempDiff, Relax, &
      surf, xx, yy, r, detJ, Temp, MeltPoint, &
      Temp1,Temp2,Temppi,dmin,d, HeatCond, s, tave, prevtave, cvol, clim, ccum=1, &
      tabs, prevtabs, volabs, prevvolabs, CoordMin(3), CoordMax(3), &
      dTdz, ttemp, NewtonAfterTol, area, volume, prevvolume, StepSize, &
      UPull(3) = (/ 0,0,0 /)
  REAL(KIND=dp), POINTER :: Surface(:), Temperature(:), acc, &
      x(:), y(:), z(:), Basis(:), dBasisdx(:,:), NodalTemp(:), &
      Conductivity(:), LatentHeat(:)
  REAL (KIND=dp), ALLOCATABLE :: PrevTemp(:), PrevDz(:), Dz(:)
  REAL (KIND=dp), ALLOCATABLE :: IsoSurf(:,:)
  
  INTEGER :: i,j,k,t,n,nn,pn,DIM,kl,kr,l, bc, Trip_node, NoBNodes, &
       NElems,ElementCode,Next,Vertex,ii,imin,NewtonAfterIter,Node, &
       SubroutineVisited = 0, NormalDirection, TangentDirection, CoordMini(3), CoordMaxi(3)
  INTEGER, POINTER :: NodeIndexes(:),TempPerm(:),SurfPerm(:),Visited(:)
  INTEGER, DIMENSION(:), ALLOCATABLE :: InvPerm

  LOGICAL :: Stat, FirstTime = .TRUE., Newton = .FALSE., PullDetermined
  CHARACTER(LEN=MAX_NAME_LEN) :: VariableName
  CHARACTER(LEN=MAX_NAME_LEN) :: VersionID = "$Id: PhaseChange.f90,v 1.10 2005/04/04 06:18:31 jpr Exp $"
  
  SAVE UPull, FirstTime, Trip_node, NoBNodes, SubroutineVisited, Dz, PrevDz, &
      PrevTemp, Newton, ccum, NormalDirection, TangentDirection, MeltPoint

!------------------------------------------------------------------------------
  CALL Info('PhaseChange','------------------------')
  CALL Info('PhaseChange','PHASECHANGE')
  CALL Info('PhaseChange','------------------------')
!------------------------------------------------------------------------------
!    Check if version number output is requested
!------------------------------------------------------------------------------
     IF ( FirstTime ) THEN
       IF ( ListGetLogical( GetSimulation(), 'Output Version Numbers', Stat ) ) THEN
         CALL Info( 'PhaseChange', 'PhaseChange version:', Level = 0 ) 
         CALL Info( 'PhaseChange', VersionID, Level = 0 ) 
         CALL Info( 'PhaseChange', ' ', Level = 0 ) 
       END IF
     END IF

!------------------------------------------------------------------------------  

  SubroutineVisited = SubroutineVisited + 1

!------------------------------------------------------------------------------
! Get variables needed for solution
!------------------------------------------------------------------------------
  SurfSol  => Solver % Variable
  Surface  => SurfSol % Values
  SurfPerm => SurfSol % Perm
  
  VariableName = ListGetString( Solver % Values, 'Phase Change Variable', Stat )
  IF(Stat) THEN
    TempSol => VariableGet( Solver % Mesh % Variables, TRIM(VariableName) )
  ELSE
    TempSol => VariableGet( Solver % Mesh % Variables, 'Temperature' )
  END IF
  TempPerm    => TempSol % Perm
  Temperature => TempSol % Values
  
  DIM = CoordinateSystemDimension()

  IF(DIM /= 2) THEN
    CALL Fatal('PhaseChange','Implemented only in 2D')
  END IF

  n = Solver % Mesh % MaxElementNodes

  ALLOCATE( Visited( Solver % Mesh % NumberOfNodes ), &
      IsoSurf(2*Solver % Mesh % NumberOfBulkElements,2), &
      InvPerm( Solver % Mesh % NumberOfNodes ), &
      Nodes % x(n), Nodes % y(n), Nodes % z(n), &
      PNodes % x(n), PNodes % y(n), PNodes % z(n), &
      x(n), y(n), z(n), Basis(n), dBasisdx(n,3), NodalTemp(n), &
      Conductivity(n), LatentHeat(n) )

  IsoSurf = 0
  InvPerm = 0
  Visited = 0
  
  IF (FirstTime) THEN

    NoBNodes = 0    
    CoordMax = -HUGE(CoordMax)
    CoordMin = HUGE(CoordMin)
    
    DO k=Model % Mesh % NumberOfBulkElements + 1, &
        Model % Mesh % NumberOfBulkElements + Model % Mesh % NumberOfBoundaryElements
      
      Element => Model % Mesh % Elements(k)
      
      DO bc = 1, Model % NumberOfBCs
        IF ( Element % BoundaryInfo % Constraint == &
            Model % BCs(bc) % Tag ) THEN
          
          IF ( .NOT. ListGetLogical(Model % BCs(bc) % Values, &
              'Phase Change',Stat) ) CYCLE

          DO l=1,Element % TYPE % NumberOfNodes           
            i = Element % NodeIndexes(l)
            
            DO j=1,DIM
              IF(j==1) xx = Model % Mesh % Nodes % x(i)
              IF(j==2) xx = Model % Mesh % Nodes % y(i)
              IF(j==3) xx = Model % Mesh % Nodes % z(i)
              IF(xx > CoordMax(j)) THEN
                CoordMax(j) = xx
                CoordMaxi(j) = i
              END IF
              IF(xx < CoordMin(j)) THEN
                CoordMin(j) = xx
                CoordMini(j) = i
              END IF
            END DO
            
            IF ( Visited(i) /= 1 ) THEN
              NoBnodes = NoBNodes + 1
              Visited(i) = 1
            END IF
          
          END DO
        END IF
      END DO
    END DO

    IF(NoBNodes == 0) THEN
      CALL Warn('PhaseChange','No boundary elemenents with phase change boundary')
      RETURN
    END IF
    
    ! Direction of minimum change
    j = 1
    DO i=1,DIM
      IF(CoordMax(i)-CoordMin(i) < CoordMax(j)-CoordMin(j)) THEN
        j = i
      END IF
    END DO
    NormalDirection = j

    ! Direction of maximum change
    j = 1
    DO i=1,DIM
      IF(CoordMax(i)-CoordMin(i) > CoordMax(j)-CoordMin(j)) THEN
        j = i
      END IF
    END DO
    TangentDirection = j

! Find triple point:
!-------------------
    Trip_node = CoordMaxi(TangentDirection)

    ALLOCATE( Dz(NobNodes), PrevDz(NobNodes), PrevTemp(NobNodes) )
    Dz = 0.0d0
    PrevDz = 0.0d0
    PrevTemp = 0.0d0
  END IF

!------------------------------------------------------------------------------

 
  NewtonAfterIter = ListGetInteger( Solver % Values, &
       'Nonlinear System Newton After Iterations', stat )
  
  IF ( stat .AND. SubroutineVisited > NewtonAfterIter ) Newton = .TRUE.
!--------------------------------------------------------------------

  IF ( .NOT. TransientSimulation .AND. .NOT. Newton ) THEN

! Find the melting point isotherm:
!---------------------------------
    NElems = 0

    DO k=1, Model % NumberOfMaterials
      IF ( ListGetLogical(Model % Materials(k) % Values, 'Solid', stat) ) EXIT
    END DO
    MeltPoint = ListGetConstReal(Model % Materials(k) % Values, 'Melting Point', Stat)
 
    IF(ListGetLogical(Solver % Values,'Use Triple Point for Melting Point', Stat)) THEN
      MeltPoint = Temperature( TempPerm(Trip_node) )
    END IF
        
    DO t=1,Solver % NumberOfActiveElements
      CurrentElement => Solver % Mesh % Elements( Solver % ActiveElements(t) )
      k = ListGetInteger( Model % Bodies(CurrentElement % BodyId) % Values, 'Material' )
      
      IF (ListGetLogical(Model % Materials(k) % Values, 'Solid', stat) .OR. &
          ListGetLogical(Model % Materials(k) % Values, 'Liquid', stat)) THEN
        
        ElementCode = CurrentElement % TYPE % ElementCode
        NodeIndexes => CurrentElement % NodeIndexes
        n = CurrentElement % TYPE % NumberOfNodes
        
        Nodes % x(1:n) = Solver % Mesh % Nodes % x(NodeIndexes)
        Nodes % y(1:n) = Solver % Mesh % Nodes % y(NodeIndexes)
        Nodes % z(1:n) = Solver % Mesh % Nodes % z(NodeIndexes)
        
        Vertex = ElementCode/100
        n=0
        DO nn=1,Vertex
          temp1 = Temperature( TempPerm(NodeIndexes(nn)) )
          next  = MODULO(nn,Vertex) + 1
          temp2 = Temperature( TempPerm(NodeIndexes(next)) )
          
          IF ( ( (temp1 < MeltPoint) .AND. (MeltPoint <= temp2) ) .OR. &
              ( (temp2 <= MeltPoint) .AND. (MeltPoint < temp1) ) ) THEN
            n = n + 1
            
            IF ( n < 3 ) THEN
              NElems = NElems + 1
              IsoSurf(NElems,1) = Nodes % x(nn) + &
                  (MeltPoint-temp1) * ((Nodes % x(next) - Nodes % x(nn)) / (temp2-temp1))              
              IsoSurf(NElems,2) = Nodes % y(nn) + &
                  (MeltPoint-temp1) * ((Nodes % y(next) - Nodes % y(nn)) / (temp2-temp1))
            ELSE
              CALL Warn('PhaseChange','Wiggly Isotherm')
              WRITE(Message,*) 'nodeindexes',nodeindexes(1:Vertex)
              CALL Warn('PhaseChange',Message)
              WRITE(Message,*) 'temperature',temperature(TempPerm(NodeIndexes(1:Vertex)))
              CALL Warn('PhaseChange',Message)
              STOP
            END IF
          END IF
        END DO
        
        IF ( n == 1 ) THEN
          NElems = NElems - 1
          CYCLE
        END IF
        
        IF (nelems >= 2) THEN
          IF ( IsoSurf(Nelems-1,TangentDirection) > IsoSurf(Nelems,TangentDirection) ) THEN
            Temppi = IsoSurf(Nelems-1,1)
            IsoSurf(Nelems-1,1) = IsoSurf(Nelems,1)
            IsoSurf(Nelems,1) = Temppi
            Temppi = IsoSurf(Nelems-1,2)
            IsoSurf(Nelems-1,2) = IsoSurf(Nelems,2)
            IsoSurf(Nelems,2) = Temppi
          END IF
        END IF
      END IF
    END DO
  END IF

!-------------------------------------------------------------------
  Relax = ListGetConstReal( Solver % Values,  & 
      'Nonlinear System Relaxation Factor', stat )
  IF ( .NOT. stat ) Relax = 1
  
  Node = 0
  MaxTempDiff = 0.0
  
  IF ( TransientSimulation ) THEN

    PullDetermined = .FALSE.
100 InvPerm = 0
    Node = 0

    DO t = Solver % Mesh % NumberOfBulkElements + 1,  &
        Solver % Mesh % NumberOfBulkElements + Solver % Mesh % NumberOfBoundaryElements
      
      CurrentElement => Solver % Mesh % Elements(t)
      k = CurrentElement % BoundaryInfo % Constraint
      
      IF ( k == 0 ) CYCLE
      IF ( .NOT. ListGetLogical( Model % BCs(k) % Values, 'Phase Change', stat ) ) CYCLE
      
      n = CurrentElement % TYPE % NumberOfNodes
      NodeIndexes => CurrentElement % NodeIndexes
      
      Nodes % x(1:n) = Solver % Mesh % Nodes % x(NodeIndexes)
      Nodes % y(1:n) = Solver % Mesh % Nodes % y(NodeIndexes)
      Nodes % z(1:n) = Solver % Mesh % Nodes % z(NodeIndexes)
      
      LatentHeat(1:n) = ListGetReal( Model % BCs(k) % Values, 'Latent Heat', n, NodeIndexes )
      
      DO nn = 1,n

        IF ( .NOT. PullDetermined .AND. NodeIndexes(nn) /= Trip_node ) CYCLE

        IF ( InvPerm(NodeIndexes(nn)) > 0) CYCLE

        Node = Node + 1
        InvPerm( NodeIndexes(nn) ) = Node               

! If inner boundary, Normal Target Body should be defined for the boundary 
! (if not, material density will be used to determine the  normal direction 
! and should be defined for bodies on both sides):
! -------------------------------------------------------------------------
         
        u = CurrentElement % TYPE % NodeU(nn)
        v = CurrentElement % TYPE % NodeV(nn)
        w = CurrentElement % TYPE % NodeW(nn)
        
        Normal = NormalVector( CurrentElement, Nodes, 0.0d0,0.0d0, .TRUE. )
        Normal = Normal / SQRT( SUM(Normal**2) )
        
        TGrad = 0.0d0
        Gradi = 0.0d0

        DO i=1,2
          IF ( i==1 ) THEN
            Parent => CurrentElement % BoundaryInfo % Left
          ELSE
            Parent => CurrentElement % BoundaryInfo % Right
          END IF
          
          pn = Parent % TYPE % NumberOfNodes
          NodalTemp(1:pn) = Temperature(TempPerm(Parent % NodeIndexes))
          
          stat = ElementInfo( CurrentElement, Nodes, u, v, w, detJ, &
              Basis, dBasisdx, ddBasisddx, .FALSE., .FALSE. )
          
! Calculate the basis functions for the parent element:
! -----------------------------------------------------
          DO j = 1,n
            DO k = 1,pn
              IF( NodeIndexes(j) == Parent % NodeIndexes(k) ) THEN
                x(j) = Parent % TYPE % NodeU(k)
                y(j) = Parent % TYPE % NodeV(k)
                z(j) = Parent % TYPE % NodeW(k)
                EXIT
              END IF
            END DO
          END DO
          u = SUM( Basis(1:n) * x(1:n) )
          v = SUM( Basis(1:n) * y(1:n) )
          w = SUM( Basis(1:n) * z(1:n) )
          
          PNodes % x(1:pn) = Solver % Mesh % Nodes % x(Parent % NodeIndexes)
          PNodes % y(1:pn) = Solver % Mesh % Nodes % y(Parent % NodeIndexes)
          PNodes % z(1:pn) = Solver % Mesh % Nodes % z(Parent % NodeIndexes)
          
          stat = ElementInfo( Parent, PNodes, u, v, w, detJ, Basis, &
              dBasisdx, ddBasisddx, .FALSE., .FALSE. )
          
          k=ListGetInteger(Model % Bodies(Parent % BodyId) % Values,'Material')
          Conductivity(1:pn) = ListGetReal( Model % Materials(k) % Values, &
              'Heat Conductivity', pn, Parent % NodeIndexes )
          
          DO j=1,DIM
            TGrad(i,j) = SUM( Conductivity(1:pn) * Basis(1:pn) ) * &
                SUM( dBasisdx(1:pn,j) * NodalTemp(1:pn) )
            Gradi(i,j) = SUM( dBasisdx(1:pn,j) * NodalTemp(1:pn) )
          END DO
        END DO
        
        Jump(1:DIM) = ( TGrad(1,1:DIM) - TGrad(2,1:DIM) )
        
        Parent => CurrentElement % BoundaryInfo % Left
        k = ListGetInteger(Model % Bodies(Parent % BodyId) % Values,'Material')
        
        IF (ListGetLogical(Model % Materials(k) % Values, 'Liquid', stat)) THEN
          Parent => CurrentElement % BoundaryInfo % Right
        ELSE
          Jump = -Jump
          Tempo(1:DIM) = Gradi(1,1:DIM)
          Gradi(1,1:DIM) = Gradi(2,1:DIM)
          Gradi(2,1:DIM) = Tempo(1:DIM)
        END IF

        k = ListGetInteger(Model % Bodies(Parent % BodyId) % Values, 'Material')
        Density = ListGetConstReal( Model % Materials(k) % Values, 'Density' )
        MeltPoint = ListGetConstReal( Model % Materials(k) % Values,  'Melting Point' )

        IF(.NOT. PullDetermined .AND. NodeIndexes(nn) == Trip_node ) THEN
          Upull(2) = SUM( Normal * Jump / ( Density * LatentHeat(nn) ) ) / Normal(NormalDirection)
          WRITE(Message,*) 'Pull velocity: ', upull
          CALL Info('PhaseChange',Message) 
          PullDetermined = .TRUE.
          GOTO 100
        END IF

        IF(PullDetermined) THEN
          Dz(InvPerm(NodeIndexes(nn))) = Solver % dt * &
              SUM( ( UPull - Jump / (LatentHeat(nn) * Density) ) * Normal ) * Normal(NormalDirection)  
        END IF

      END DO
    END DO

    IF(.NOT. PullDetermined) CALL Fatal('PhaseChange','Unable to determine the pull velocity')

    StepSize = ListGetConstReal(Solver % Values,'Step Size',Stat) 
    IF(Stat) THEN
      Dz = StepSize * Dz / (ABS(MAXVAL(Dz)))
    END IF
    
    DO n=1,Solver % Mesh % NumberOfNodes
      k = SurfPerm(n)
      IF(k > 0 .AND. InvPerm(n) > 0) THEN
        StepSize = Surface(k)
        Surface(k) = SurfSol % PrevValues(k,1) + Dz(InvPerm(n))        
        WRITE(Message,*)  'x:',Solver % Mesh % Nodes % x(n),' ds:',Dz(InvPerm(n)),' h:',Surface(k),StepSize
        CALL Info('PhaseChange',Message)          
      END IF
    END DO

  END IF


  IF(.NOT. TransientSimulation) THEN

    area = 0.0
    volume = 0.0
    tave = 0.0
    tabs = 0.0
    volabs = 0.0

    DO t = Solver % Mesh % NumberOfBulkElements + 1,  &
        Solver % Mesh % NumberOfBulkElements + Solver % Mesh % NumberOfBoundaryElements
      
      CurrentElement => Solver % Mesh % Elements(t)
      k = CurrentElement % BoundaryInfo % Constraint
      
      IF ( k == 0 ) CYCLE
      IF ( .NOT. ListGetLogical( Model % BCs(k) % Values, 'Phase Change', stat ) ) CYCLE
      
      n = CurrentElement % TYPE % NumberOfNodes
      NodeIndexes => CurrentElement % NodeIndexes
      
      Nodes % x(1:n) = Solver % Mesh % Nodes % x(NodeIndexes)
      Nodes % y(1:n) = Solver % Mesh % Nodes % y(NodeIndexes)
      Nodes % z(1:n) = Solver % Mesh % Nodes % z(NodeIndexes)
      
      DO nn=1,n

        IF ( InvPerm(NodeIndexes(nn)) > 0) CYCLE

        IF(TangentDirection == 1) xx = Nodes % x(nn)
        IF(TangentDirection == 2) xx = Nodes % y(nn)

        IF(NormalDirection == 1) yy = Nodes % x(nn)
        IF(NormalDirection == 2) yy = Nodes % y(nn)
        
        k = SurfPerm( NodeIndexes(nn) )

        IF ( .NOT. Newton ) THEN          
          
          ! Find the the contour element that has the x-coordinate in closest to the thah of the
          ! free surface

          dmin = HUGE(dmin)          
          DO i=1,Nelems-1,2
            IF ( (xx >= IsoSurf(i,TangentDirection)) .AND. (xx <= IsoSurf(i+1,TangentDirection)) ) THEN
              d = 0.0
              imin = i
              EXIT
            ELSE
              d=MIN( ABS(xx - IsoSurf(i,TangentDirection)), ABS(xx - IsoSurf(i+1,TangentDirection)) )
            END IF            
            IF (d <= dmin ) THEN
              dmin = d
              imin = i
            END IF
          END DO
          
          i = imin

          IF ( i >= Nelems ) THEN
            CALL Warn('PhaseChange','Isotherm error')
            WRITE(Message,*) 'Nodeindexes',NodeIndexes(nn)
            CALL Warn('PhaseChange',Message)
            WRITE(Message,*) 'x:',Nodes % x(nn)
            CALL Warn('PhaseChange',Message)
            STOP
          END IF
          
          IF ( ABS( IsoSurf(i+1,TangentDirection) - IsoSurf(i,TangentDirection) ) > AEPS ) THEN
            Update = IsoSurf(i,NormalDirection) + ( xx - IsoSurf(i,TangentDirection) ) * &
                ( IsoSurf(i+1,NormalDirection) - IsoSurf(i,NormalDirection) ) / &
                ( IsoSurf(i+1,TangentDirection) - IsoSurf(i,TangentDirection) ) - yy
          ELSE
            Update = 0.5d0 * ( IsoSurf(i,NormalDirection) + IsoSurf(i+1,NormalDirection) ) - yy
          END IF
        END IF
         
        Node = Node + 1        
        TTemp = Temperature( TempPerm(NodeIndexes(nn)) )

        MaxTempDiff = MAX(MaxTempDiff, ABS(Ttemp-MeltPoint))
        IF ( NodeIndexes(nn) == Trip_node ) THEN
           Update = 0.0d0
        ELSE IF ( Newton ) THEN
          dTdz = ( TTemp - PrevTemp(Node) )
          IF ( ABS(dTdz) < AEPS ) THEN
             CALL Warn( 'PhaseChange', 'Very small temperature update.' )
             dTdz = 1
          END IF
          Update = dz(Node) * ( MeltPoint - TTemp ) / dTdz
        END IF

        PrevTemp(Node) = TTemp
        DZ(Node) = Update
        
        IF ( nn == 3 ) THEN
          Surface(k)=0.5*(Surface(SurfPerm(NodeIndexes(1)))+Surface(SurfPerm(NodeIndexes(2))))
          Update = 0.0
        END IF
        
        InvPerm( NodeIndexes(nn) ) = Node
      END DO


      IntegStuff = GaussPoints( CurrentElement )      
      DO i=1,IntegStuff % n        

        u = IntegStuff % u(i)
        v = IntegStuff % v(i)
        w = IntegStuff % w(i)

        stat = ElementInfo( CurrentElement, Nodes, u, v, w, detJ, &
            Basis, dBasisdx, ddBasisddx, .FALSE., .FALSE. )
       
        s = IntegStuff % s(i) * detJ

        IF ( CurrentCoordinateSystem() /= Cartesian ) THEN
          s = s * SUM(Basis(1:n) * Nodes % x(1:n)) * 2.0 * PI
        END IF

        area = area + S
        volume = volume + S * SUM(Basis(1:n) * Dz(InvPerm(NodeIndexes(1:n))))
        tave = tave + S * SUM(Basis(1:n) * Temperature( TempPerm(NodeIndexes(1:n)) ) ) - &
            S * MeltPoint
        volabs = volabs + S * SUM(Basis(1:n) * ABS(Dz(InvPerm(NodeIndexes(1:n)))))
        tabs = tabs + S * SUM(Basis(1:n) * ABS(Temperature( TempPerm(NodeIndexes(1:n))) &
            - MeltPoint) )        

      END DO
      
    END DO

    Relax = ListGetConstReal( Solver % Values,  & 
        'Nonlinear System Relaxation Factor', stat )
    IF ( .NOT. stat ) Relax = 1
    
    ! There are several different acceleration methods which are mainly inactive
    tave = tave / area
    tabs = tabs / area
    volume = volume / area
    volabs = volabs / area

    !       PRINT *,'PR:vol',volume,cvol 
    !        PRINT *,'PR:temp',tave,tave/(prevtave-tave)
    !        PRINT *,'PR:abs(vol)',volabs,prevvolabs/(prevvolabs-volabs)
    !        PRINT *,'PR:abs(temp)',tabs,tabs/(prevtabs-tabs)

    i = ListGetInteger(Solver % Values,'Lumped Newton After Iterations', Stat)
    IF(Stat .AND. SubroutineVisited > i) THEN

      j = ListGetInteger(Solver % Values,'Lumped Newton Mode', Stat)
      SELECT CASE( j ) 
        CASE( 1 )
        cvol = 0.5*(prevtave+tave)/(prevtave-tave)

        CASE( 2 )
        cvol = 0.5*(prevvolabs+volabs)/(prevvolabs-volabs)
        
        CASE( 3 )
        cvol = 0.5*(prevtabs+tabs)/(prevtabs-tabs)
        
      CASE DEFAULT
        cvol = 0.5*(prevvolume+volume)/(prevvolume-volume)
        !        print *,'PR: cvol',cvol
      END SELECT
      
      IF(cvol < 0.0) THEN
        cvol = 1.0
        ccum = 1.0
      END IF
      clim = ListGetConstReal(Solver % Values,'Lumped Newton Limiter', Stat)
      IF(.NOT. Stat) clim = 100.0
      cvol = MIN(clim,cvol)
      cvol = MAX(1.0/clim,cvol)

      ccum = ccum * cvol
      !        print *,'PR: ccum',ccum
      
      WRITE(Message,*) 'Lumped Newton relaxation: ', ccum
      CALL Info('PhaseChange',Message)

      Relax = Relax * ccum
    END IF

    MaxUpdate = MAXVAL(ABS(Dz))
    Dz = Relax * Dz
    PrevDz = Dz
    DO i=1,Solver % Mesh % NumberOfNodes
      IF(InvPerm(i) > 0) Surface(SurfPerm(i)) = Surface(SurfPerm(i)) + Dz(InvPerm(i))
    END DO

    WRITE(Message,*) 'Maximum surface update: ', MaxUpdate
    CALL Info('PhaseChange',Message)
    
    WRITE(Message,*) 'Maximum temperature difference: ', MaxTempDiff
    CALL Info('PhaseChange',Message)
    
    prevvolume = volume
    prevtave = tave
    prevtabs = tabs
    prevvolabs = volabs

    NewtonAfterTol = ListGetConstReal( Solver % Values, &
        'Nonlinear System Newton After Tolerance', stat )
    IF ( stat .AND. ABS(MaxUpdate) < NewtonAfterTol ) Newton = .TRUE.    
  END IF
   
  FirstTime = .FALSE.
  
  Solver % Variable % Norm = ABS( MaxUpdate )
!--------------------------------------------------------------------

  DEALLOCATE( Nodes % x, Nodes % y, Nodes % z, &
      PNodes % x, PNodes % y, PNodes % z, &
      IsoSurf, InvPerm, x, y, z, Basis, dBasisdx, NodalTemp, &
      Conductivity, LatentHeat )

!------------------------------------------------------------------------------
END SUBROUTINE PhaseChange
!------------------------------------------------------------------------------

