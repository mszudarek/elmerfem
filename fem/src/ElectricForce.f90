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
! *                Modified by:      Antti Pursula
! *
! *       Date of modification:      20 Jun 2002
! *
! *  Included support for adaptive meshing:    27 Feb 2004
! * 
!******************************************************************************
! * 
! *            Calculate force due to static electric field
! *               by integrating Maxwell stress tensor 
! *                    over specified boundaries
! *
! *                      Antti.Pursula@csc.fi
! *
! *****************************************************************************/
 
!------------------------------------------------------------------------------
SUBROUTINE StatElecForce( Model,Solver,dt,TransientSimulation )
  !DEC$ATTRIBUTES DLLEXPORT :: StatElecForce
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

  TYPE(Mesh_t), POINTER :: Mesh
  TYPE(Solver_t), POINTER :: PSolver 
  TYPE(Variable_t), POINTER :: Var
  TYPE(Nodes_t) :: ElementNodes, ParentNodes
  TYPE(Element_t), POINTER   :: CurrentElement, Parent
  TYPE(ValueList_t), POINTER :: Material
  REAL(KIND=dp), ALLOCATABLE :: Potential(:), Permittivity(:,:,:) 
  REAL(KIND=dp), POINTER :: Pwrk(:,:,:), ForceDensity(:)
  REAL(KIND=dp), POINTER :: Fdx(:), Fdy(:), Fdz(:)
  REAL(KIND=dp) :: Force(3), ElementForce(3), Area, PermittivityOfVacuum, sf
  INTEGER, POINTER :: NodeIndexes(:), Visited(:)
  INTEGER :: DIM, t, pn, n, k, s, i, j
  LOGICAL :: stat, FirstTime = .TRUE.
  CHARACTER(LEN=MAX_NAME_LEN) :: EqName1, EqName2

  CHARACTER(LEN=MAX_NAME_LEN) :: VersionID = "$Id: ElectricForce.f90,v 1.10 2004/03/03 09:47:32 jpr Exp $"

  SAVE FirstTime, ForceDensity, Pwrk
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
!    Check if version number output is requested
!------------------------------------------------------------------------------
  IF ( FirstTime ) THEN
    IF ( ListGetLogical( GetSimulation(), 'Output Version Numbers', stat ) ) THEN
      CALL Info( 'StatElecForce', 'ElectricForce version:', Level = 0 ) 
      CALL Info( 'StatElecForce', VersionID, Level = 0 ) 
      CALL Info( 'StatElecForce', ' ', Level = 0 ) 
    END IF
  END IF

  DIM = CoordinateSystemDimension()

  IF ( FirstTime ) THEN

     Mesh => Solver % Mesh
     ALLOCATE( ForceDensity( Dim * Mesh % NumberOfNodes ) )
     ForceDensity = 0.0d0

    PSolver => Solver

    Fdx => ForceDensity( 1: Dim*Mesh % NumberOfNodes-Dim+1: Dim )
    CALL VariableAdd( Mesh % Variables, Mesh, PSolver, &
        'Electric Force Density 1', 1, Fdx )
    Fdy => ForceDensity( 2: Dim*Mesh % NumberOfNodes-Dim+2: Dim )
    CALL VariableAdd( Mesh % Variables, Mesh, PSolver, &
        'Electric Force Density 2', 1, Fdy )
    IF ( Dim == 3 ) THEN
       Fdz => ForceDensity( 3: Dim*Mesh % NumberOfNodes: Dim )
       CALL VariableAdd( Mesh % Variables, Mesh, PSolver, &
            'Electric Force Density 3', 1, Fdz )
    END IF

    CALL VariableAdd( Mesh % Variables, Mesh, PSolver, &
         'Electric Force Density', Dim, ForceDensity )

    NULLIFY( Pwrk )

    FirstTime = .FALSE.
  END IF

!------------------------------------------------------------------------------
!    Figure out the mesh that potential solver is using
!------------------------------------------------------------------------------

  i = ListGetInteger( Solver % Values, 'Potential Solver ID', stat )
  IF ( .NOT. stat ) THEN
     EqName1 = ListGetString( Solver % Values, 'Equation' )

     !  stat = .FALSE.
     DO i = 1, Model % NumberOfSolvers
        EqName2 = ListGetString( Model % Solvers(i) % Values, 'Equation' )

        IF ( TRIM( EqName1 ) == TRIM( EqName2 ) ) THEN
           stat = .TRUE.
           EXIT
        END IF
     END DO

     IF ( .NOT. stat )  CALL Fatal( 'StatElecForce', &
          'No potential solver found (1): Give potential solver id' )
     IF ( i == 1 )  CALL Fatal( 'StatElecForce', &
          'No potential solver found (2): Give potential solver id' )

     ! Assume potential solver id is one smaller than elec force solver id
     i = i-1
  END IF

  Mesh => Model % Solvers(i) % Mesh
  CALL SetCurrentMesh( Model, Mesh )

  Var => VariableGet( Mesh % Variables, 'Electric Force Density' )
  IF ( .NOT. ASSOCIATED ( Var ) )  &
       CALL Fatal( 'StatElecForce', 'Fatal error of the 1st kind' )
  ForceDensity => Var % Values

  Var => VariableGet( Mesh % Variables, 'Potential' )
  
  IF ( .NOT.ASSOCIATED( Var ) ) THEN
    WRITE( Message, * ) 'No electric potential found!'
    CALL Fatal( 'StatElecForce', Message )
  END IF

  ALLOCATE( ElementNodes % x( Mesh % MaxElementNodes ) )
  ALLOCATE( ElementNodes % y( Mesh % MaxElementNodes ) )
  ALLOCATE( ElementNodes % z( Mesh % MaxElementNodes ) )

  ALLOCATE( ParentNodes % x( Mesh % MaxElementNodes ) )
  ALLOCATE( ParentNodes % y( Mesh % MaxElementNodes ) )
  ALLOCATE( ParentNodes % z( Mesh % MaxElementNodes ) )
  ParentNodes % x = 0.0d0
  ParentNodes % y = 0.0d0
  ParentNodes % z = 0.0d0

  ALLOCATE( Potential( Mesh % MaxElementNodes ) )
  ALLOCATE( Permittivity( 3, 3, Mesh % MaxElementNodes ) )
  ALLOCATE( Visited( Mesh % NumberOfNodes ) )

!------------------------------------------------------------------------------

  PermittivityOfVacuum = ListGetConstReal( Model % Constants, &
      'Permittivity Of Vacuum', stat )
  IF ( .NOT. stat ) THEN
     CALL Warn( 'StatElecForce', 'Permittivity of Vacuum not given, using 1' )
     PermittivityOfVacuum = 1.0d0
  END IF

  ElementNodes % x = 0.0d0
  ElementNodes % y = 0.0d0
  ElementNodes % z = 0.0d0

  Area = 0.0d0
  Force  = 0.0d0
  ForceDensity = 0.0d0
  Visited = 0

  DO t = Mesh % NumberOfBulkElements + 1, &
      Mesh % NumberOfBulkElements + Mesh % NumberOfBoundaryElements

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
      IF ( Model % BCs(k) % Tag /= CurrentElement % BoundaryInfo & 
          % Constraint ) CYCLE
      IF ( .NOT.ListGetLogical(Model % BCs(k) % Values, &
          'Calculate Electric Force', stat ) )  CYCLE

      ElementNodes % x(1:n) = Mesh % Nodes % x(NodeIndexes)
      ElementNodes % y(1:n) = Mesh % Nodes % y(NodeIndexes)
      ElementNodes % z(1:n) = Mesh % Nodes % z(NodeIndexes)

!------------------------------------------------------------------------------
!     Need parent element to determine material number
!------------------------------------------------------------------------------
      Parent => CurrentElement % BoundaryInfo % Left

      stat = ASSOCIATED( Parent )
      IF ( stat ) THEN
        i = Parent % BodyId
        j = ListGetInteger( Model % Bodies(i) % Values, 'Material', &
               minv=1, maxv=Model % NumberOfMaterials )
        Material => Model % Materials(j) % Values

        CALL ListGetRealArray( Material, 'Relative Permittivity', Pwrk, n, &
            NodeIndexes, stat )
        IF ( .NOT. stat )  CALL ListGetRealArray( Material, &
            'Permittivity', Pwrk, n, NodeIndexes, stat )
      END IF
      IF ( .NOT. stat ) THEN
        Parent => CurrentElement % BoundaryInfo % Right
        IF ( .NOT. ASSOCIATED( Parent ) ) THEN
          WRITE( Message, * ) 'No permittivity found on specified boundary'
          CALL Fatal( 'StatElecForce', Message )
        END IF
        i = Parent % BodyId
        j = ListGetInteger( Model % Bodies(i) % Values, 'Material', &
               minv=1, maxv=Model % NumberOfMaterials )
        Material => Model % Materials(j) % Values

        CALL ListGetRealArray( Material, 'Relative Permittivity', Pwrk, n, &
            NodeIndexes, stat )
        IF ( .NOT. stat )  CALL ListGetRealArray( Material, &
            'Permittivity', Pwrk, n, NodeIndexes, stat )

        IF ( .NOT. stat ) THEN
          WRITE( Message, *) 'No permittivity found on specified boundary'
          CALL Fatal( 'StatElecForce', Message )
        END IF
      END IF

!------------------------------------------------------------------------------

      stat = ALL( Var % Perm( NodeIndexes ) > 0 )
        
      IF ( .NOT. stat ) THEN
        WRITE( Message, *) 'No potential available for specified boundary'
        CALL Fatal( 'StatElecForce', Message )
      END IF

!------------------------------------------------------------------------------
      pn = Parent % TYPE % NumberOfNodes

      ParentNodes % x(1:pn) = Mesh % Nodes % x(Parent % NodeIndexes)
      ParentNodes % y(1:pn) = Mesh % Nodes % y(Parent % NodeIndexes)
      ParentNodes % z(1:pn) = Mesh % Nodes % z(Parent % NodeIndexes)

!------------------------------------------------------------------------------

      Permittivity = 0.0d0
      IF ( SIZE(Pwrk,1) == 1 ) THEN
        DO i=1,3
          Permittivity( i,i,1:n ) = Pwrk( 1,1,1:n )
        END DO
      ELSEIF ( SIZE(Pwrk,2) == 1 ) THEN
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

      Potential = 0.0d0
      Potential(1:pn) = Var % Values( Var % Perm( Parent % NodeIndexes ) )
      ElementForce = 0.0d0

      CALL MaxwellStressTensorIntegrate( Force, Area )

    END DO
  END DO

  DO i= 1, Mesh % NumberOfNodes
    IF ( Visited(i) > 0 ) THEN
       DO j = 1, Dim
          ForceDensity(Dim*i-Dim+j) = &
               ForceDensity(Dim*i-Dim+j) / Visited(i)
       END DO
    ELSE
       DO j = 1, Dim
          ForceDensity(Dim*i-Dim+j) = 0.0d0
       END DO
    END IF
  END DO
!  ForceDensity = ForceDensity * Area

!------------------------------------------------------------------------------

  CALL Info( 'StatElecForce', ' ', Level=4 )
  WRITE( Message, '("Net electric force  : ", 3ES15.6E2 )' ) Force
  CALL Info( 'StatElecForce', Message, Level=4 )

!  WRITE( Message, *) 'Resultant force : ', Force, SQRT( SUM( Force * Force ) )

  sf = SQRT(SUM( Force**2 ) )
  WRITE( Message, '("Resultant force  : ", ES15.6 )' ) sf
  CALL Info( 'StatElecForce', Message, Level=4 )

  CALL ListAddConstReal( Model % Simulation, &
      'RES: Electric Force', SQRT( SUM( Force * Force ) ) )

  DEALLOCATE( ElementNodes % x )
  DEALLOCATE( ElementNodes % y )
  DEALLOCATE( ElementNodes % z )

  DEALLOCATE( ParentNodes % x )
  DEALLOCATE( ParentNodes % y )
  DEALLOCATE( ParentNodes % z )

  DEALLOCATE( Potential )
  DEALLOCATE( Permittivity )
  DEALLOCATE( Visited )

  Var => VariableGet( Mesh % Variables, 'Electric Force Density' ,ThisOnly=.TRUE. )
  Var % PrimaryMesh => Mesh
  CALL InvalidateVariable( Model % Meshes,  Mesh, 'Electric Force Density' )
  Var % Valid = .TRUE.

  CALL SetCurrentMesh( Model, Solver % Mesh )

CONTAINS

!------------------------------------------------------------------------------
  SUBROUTINE MaxwellStressTensorIntegrate( Force, Area )
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: Force(3), Area
!------------------------------------------------------------------------------

    TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff
    REAL(KIND=dp), POINTER :: U_Integ(:), V_Integ(:), W_Integ(:), S_Integ(:)
    REAL(KIND=dp) :: Basis(n),dBasisdx(n,3),ddBasisddx(n,3,3)
    REAL(KIND=dp) :: ParentBasis(pn),ParentdBasisdx(pn,3)
    REAL(KIND=dp) :: SqrtMetric,Metric(3,3),Symb(3,3,3),dSymb(3,3,3,3)
    REAL(KIND=dp) :: u,v,w,s, detJ, x(n), y(n), z(n)
    REAL(KIND=dp) :: Tensor(3,3), Normal(3), EField(3), DFlux(3), Integral(3)
    REAL(KIND=dp) :: ElementArea, xpos, ypos, zpos
    INTEGER :: N_Integ
    INTEGER :: i,j,l
    LOGICAL :: stat

    ElementArea = 0.0d0

!------------------------------------------------------------------------------
!    Integration stuff
!------------------------------------------------------------------------------
    IntegStuff = GaussPoints( CurrentElement )

    U_Integ => IntegStuff % u
    V_Integ => IntegStuff % v
    W_Integ => IntegStuff % w
    S_Integ => IntegStuff % s
    N_Integ =  IntegStuff % n

!------------------------------------------------------------------------------
!     Over integration points
!------------------------------------------------------------------------------
    DO l=1,N_Integ
!------------------------------------------------------------------------------
      u = U_Integ(l)
      v = V_Integ(l)
      w = W_Integ(l)
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
        xpos = SUM( ElementNodes % x(1:n)*Basis(1:n) )
        ypos = SUM( ElementNodes % y(1:n)*Basis(1:n) )
        zpos = SUM( ElementNodes % z(1:n)*Basis(1:n) )
        s = 2*PI
      END IF
         
      CALL CoordinateSystemInfo( Metric,SqrtMetric,Symb,dSymb,xpos,ypos,zpos )
 
      s = s * SqrtMetric * detJ * S_Integ(l)

      Normal = Normalvector( CurrentElement,ElementNodes, u,v, .TRUE. )
!------------------------------------------------------------------------------
!
! Need parent element basis etc., for computing normal derivatives
! on boundary.
!
!------------------------------------------------------------------------------
      DO i = 1,n
        DO j = 1,pn
          IF ( CurrentElement % NodeIndexes(i) == &
              Parent % NodeIndexes(j) ) THEN
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
      EField = 0.0d0
      DFlux = 0.0d0
      DO i=1,DIM
        EField(i) = SUM( ParentdBasisdx(1:pn,i) * Potential(1:pn) )
        DO j=1,DIM
          DFlux(i) = DFlux(i)+ SUM( ParentdBasisdx(1:pn,j) *Potential(1:pn) ) &
              * SUM( Permittivity(i,j,1:n) * Basis(1:n) )
        END DO
      END DO
      DFlux = PermittivityOfVacuum * DFlux

      Tensor = 0.0d0
      DO i=1, DIM
        DO j=1, DIM
          Tensor(i,j) = - DFlux(i) * EField(j)
        END DO
      END DO
      DO i=1, DIM
        Tensor(i,i) = Tensor(i,i) + SUM( DFlux * EField ) / 2.0d0
      END DO

      Integral = MATMUL( Tensor, Normal )

      Force  = Force  + s * Integral

      ElementForce = ElementForce + s * Integral

      ElementArea = ElementArea + s * SUM( Basis(1:n) )

      Area = Area + s * SUM( Basis(1:n ) )

!------------------------------------------------------------------------------
    END DO

    ElementForce = ElementForce / ElementArea
    DO i=1, n
       DO j = 1, Dim
          ForceDensity( Dim*(CurrentElement % NodeIndexes(i))-Dim+j ) = &
               ForceDensity(Dim*(CurrentElement % NodeIndexes(i))-Dim+j) &
               + ElementForce(j)
       END DO
    END DO

    Visited( CurrentElement % NodeIndexes ) = &
        Visited( CurrentElement % NodeIndexes ) + 1

!------------------------------------------------------------------------------
  END SUBROUTINE MaxwellStressTensorIntegrate
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
END SUBROUTINE StatElecForce
!------------------------------------------------------------------------------
