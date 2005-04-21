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
! * Mesh to mesh projection/interpolation utilities
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
! *                       Date: 20012001
! *
! *                Modified by:
! *
! *       Date of modification:
! *
! *****************************************************************************/

!------------------------------------------------------------------------------
     SUBROUTINE InterpolateMeshToMesh( OldMesh, NewMesh, OldVariables, &
                NewVariables, UseQuadrantTree, Projector )
!------------------------------------------------------------------------------
!******************************************************************************
!  DESCRIPTION:
!    Interpolates values of all variables from a mesh associated with
!    the old model to the mesh of the new model
!  ARGUMENTS:
!
!   TYPE(Mesh_t) :: OldMesh, NewMesh
!     INPUT: Old and new mesh structures
!   TYPE(Variable_t), POINTER :: OldVariables, NewVariables
!     INPUT, OUTPUT: Old and new model variable structures
!            NB. NewVariables defines the variables to be interpolated
!   TYPE(Quadrant_t), POINTER :: RootQuadrant
!     INPUT: RootQuadrant of the old mesh
!            NB. If RoodQuadrant is associated (and QuadrantTree thus
!            exists), QuadrantTree is used
!   INTEGER :: dim
!     INPUT: CoordinateSystemDimension of the old mesh.
!            NB. Currently it s assumed that the new system has same dim,
!            but this could be generalized.
!
!******************************************************************************
       USE Interpolation
       USE CRSMatrix
       USE CoordinateSystems
!-------------------------------------------------------------------------------
       TYPE(Mesh_t), TARGET  :: OldMesh, NewMesh
       TYPE(Variable_t), POINTER, OPTIONAL :: OldVariables, NewVariables
       LOGICAL, OPTIONAL :: UseQuadrantTree
       TYPE(Projector_t), POINTER, OPTIONAL :: Projector
!------------------------------------------------------------------------------
       INTEGER :: dim
       Type(Nodes_t) :: ElementNodes
       INTEGER :: nBulk, i, j, k, l
       REAL(KIND=dp), DIMENSION(3) :: Point
       INTEGER, POINTER :: NodeIndexes(:)
       REAL(KIND=dp), DIMENSION(3) :: LocalCoordinates
       TYPE(Variable_t), POINTER :: OldSol, NewSol, Var
       INTEGER, POINTER :: OldPerm(:)
       REAL(KIND=dp), POINTER :: OldValue(:), NewValue(:), ElementValues(:)
       TYPE(Quadrant_t), POINTER :: LeafQuadrant
       TYPE(Element_t),POINTER :: CurrentElement

       REAL(KIND=dp) :: BoundingBox(6), detJ, u,v,w,s
       REAL(KIND=dp) :: Basis(MAX_NODES),dBasisdx(MAX_NODES,3),ddBasisddx(1,1,1)

       LOGICAL :: UseQTree, Stat, UseProjector
       TYPE(Quadrant_t), POINTER :: RootQuadrant

       INTEGER, POINTER   :: Rows(:), Cols(:)

       TYPE Epntr_t
          TYPE(Element_t), POINTER :: Element
       END TYPE Epntr_t

       TYPE(Epntr_t), ALLOCATABLE :: ElemPtrs(:)

       INTEGER, POINTER :: RInd(:)
       LOGICAL :: Found
       REAL(KIND=dp) :: eps1 = 0.1, eps2
       REAL(KIND=dp), POINTER :: Values(:), LocalU(:), LocalV(:), LocalW(:)
!------------------------------------------------------------------------------

!
!      If projector argument given, search for existing
!      projector matrix, or generate new projector, if
!      not already there:
!      ------------------------------------------------
       IF ( PRESENT(Projector) ) THEN
          Projector => NewMesh % Projector

          DO WHILE( ASSOCIATED( Projector ) )
             IF ( ASSOCIATED(Projector % Mesh, OldMesh) ) THEN
                IF ( PRESENT(OldVariables) ) CALL ApplyProjector
                RETURN
             END IF
             Projector => Projector % Next
          END DO

          n = NewMesh % NumberOfNodes
          ALLOCATE( LocalU(n), LocalV(n), LocalW(n), ElemPtrs(n) )
          DO i=1,n
             NULLIFY( ElemPtrs(i) % Element )
          END DO
       END IF
!
!      Check if using the spatial division hierarchy for the search:
!      -------------------------------------------------------------
       RootQuadrant => OldMesh % RootQuadrant
       dim = CoordinateSystemDimension()

       IF ( .NOT. PRESENT( UseQuadrantTree ) ) THEN
         UseQTree = .TRUE.
       ELSE
         UseQTree = UseQuadrantTree
       ENDIF

       IF ( UseQTree ) THEN
          IF ( .NOT.ASSOCIATED( RootQuadrant ) ) THEN
             BoundingBox(1) = MINVAL( OldMesh % Nodes % x )
             BoundingBox(2) = MINVAL( OldMesh % Nodes % y )
             BoundingBox(3) = MINVAL( OldMesh % Nodes % z )
             BoundingBox(4) = MAXVAL( OldMesh % Nodes % x )
             BoundingBox(5) = MAXVAL( OldMesh % Nodes % y )
             BoundingBox(6) = MAXVAL( OldMesh % Nodes % z )

             eps2 = eps1 * MAXVAL( BoundingBox(4:6) - BoundingBox(1:3) )
             BoundingBox(1:3) = BoundingBox(1:3) - eps2
             BoundingBox(4:6) = BoundingBox(4:6) + eps2

             CALL BuildQuadrantTree( OldMesh,BoundingBox,OldMesh % RootQuadrant)
             RootQuadrant => OldMesh % RootQuadrant
          END IF
       END IF
!------------------------------------------------------------------------------

       n = OldMesh % MaxElementNodes
       ALLOCATE( ElementNodes % x(n), ElementNodes % y(n), &
                 ElementNodes % z(n), ElementValues(n) )

!------------------------------------------------------------------------------
! Loop over all nodes in the new mesh
!------------------------------------------------------------------------------
       DO i=1,NewMesh % NumberOfNodes
!------------------------------------------------------------------------------
          Point(1) = NewMesh % Nodes % x(i)
          Point(2) = NewMesh % Nodes % y(i)
          Point(3) = NewMesh % Nodes % z(i)
!------------------------------------------------------------------------------
! Find in which old mesh bulk element the point belongs to
!------------------------------------------------------------------------------
          IF ( ASSOCIATED(RootQuadrant) .AND. UseQTree ) THEN
!------------------------------------------------------------------------------
! Find the last existing quadrant that the point belongs to
!------------------------------------------------------------------------------
             CALL FindLeafElements(Point, dim, RootQuadrant, LeafQuadrant)
             IF ( .NOT. ASSOCIATED( LeafQuadrant ) ) THEN
                NULLIFY ( CurrentElement )
                CYCLE
             END IF
!------------------------------------------------------------------------------
 
             ! Go through the bulk elements in the last ChildQuadrant
             ! only.  Try to find matching element with progressively
             ! sloppier tests. Allow at most 100 % of slack:
             ! -------------------------------------------------------
             Found = .FALSE.
             Eps2 = 1.0d-12
             DO j=1,20
                DO k=1, LeafQuadrant % NElemsInQuadrant
                   CurrentElement => OldMesh % Elements( &
                       LeafQuadrant % Elements(k) )

                   NodeIndexes => CurrentElement % NodeIndexes
                   n = CurrentElement % Type % NumberOfNodes

                   ElementNodes % x(1:n) = OldMesh % Nodes % x(NodeIndexes)
                   ElementNodes % y(1:n) = OldMesh % Nodes % y(NodeIndexes)
                   ElementNodes % z(1:n) = OldMesh % Nodes % z(NodeIndexes)

                   Found = PointInElement( CurrentElement, ElementNodes, &
                              Point, LocalCoordinates, Eps2 )
                   IF ( Found ) EXIT
                END DO
                IF ( Found ) EXIT
                Eps2  = 10 * Eps2
             END DO
 
             IF ( k > LeafQuadrant % NElemsInQuadrant ) THEN
                WRITE( Message, * ) 'Point was not found in any of the elements!',i
                CALL Warn( 'InterpolateMeshToMesh', Message )
                CYCLE
             END IF
!------------------------------------------------------------------------------
          ELSE
!------------------------------------------------------------------------------
! Go through all old mesh bulk elements
!------------------------------------------------------------------------------
             DO k=1,OldMesh % NumberOfBulkElements
                CurrentElement => OldMesh % Elements(k)

                n = CurrentElement % Type % NumberOfNodes
                NodeIndexes => CurrentElement % NodeIndexes

                ElementNodes % x(1:n) = OldMesh % Nodes % x(NodeIndexes)
                ElementNodes % y(1:n) = OldMesh % Nodes % y(NodeIndexes)
                ElementNodes % z(1:n) = OldMesh % Nodes % z(NodeIndexes)

                IF ( PointInElement( CurrentElement, ElementNodes, &
                        Point, LocalCoordinates ) ) EXIT
             END DO
             IF ( k == OldMesh % NumberOfBulkElements + 1 ) THEN
                WRITE( Message, * ) 'Point was not found in any of the elements!',i
                CALL Warn( 'InterpolateMeshToMesh', Message )
                CYCLE
             END IF
          END IF
!------------------------------------------------------------------------------
!
!         Found CurrentElement in OldModel:
!         ---------------------------------
          IF ( PRESENT(Projector) ) THEN
             ElemPtrs(i) % Element => CurrentElement
             LocalU(i) = LocalCoordinates(1)
             LocalV(i) = LocalCoordinates(2)
             LocalW(i) = LocalCoordinates(3)
          END IF

          IF ( .NOT.PRESENT(OldVariables) .OR. PRESENT(Projector) ) CYCLE
!------------------------------------------------------------------------------
!
!         Go through all variables to be interpolated:
!         --------------------------------------------
          Var => NewVariables
          DO WHILE( ASSOCIATED( Var ) )

             IF ( (Var % DOFs == 1) .AND. &
                 (Var % Name(1:10) /= 'coordinate') .AND. &
                    (Var % Name(1:4) /= 'time') ) THEN

!------------------------------------------------------------------------------
!
!               Interpolate variable at Point in CurrentElement:
!               ------------------------------------------------

                OldSol => VariableGet( OldVariables, Var % Name, .TRUE. )
                IF ( .NOT. ASSOCIATED( OldSol ) ) THEN 
                   WRITE( Message, * ) Var % Name, ' not found in old mesh!'
                   CALL Fatal( 'InterpolateMeshToMesh', Message )
                END IF
                OldPerm  => OldSol % Perm
                OldValue => OldSol % Values

                NewSol => VariableGet( NewVariables, Var % Name, .TRUE. )
                IF ( .NOT. ASSOCIATED( NewSol ) ) THEN
                   WRITE( Message, * ) Var % Name, ' not found in new mesh!'
                   CALL Fatal( 'InterpolateMeshToMesh', Message )
                   Var => Var % Next
                   CYCLE
                END IF
                NewValue => NewSol % Values

! Check that the node was found in the old mesh
                IF ( ASSOCIATED ( CurrentElement ) ) THEN
!------------------------------------------------------------------------------
!
!                  Check for rounding errors:
!                  --------------------------
                   WHERE( OldPerm( NodeIndexes ) /= 0 )
                      ElementValues(1:n) = OldValue(OldPerm(NodeIndexes))
                   ELSEWHERE
                      ElementValues(1:n) = 0.0d0
                   END WHERE

!------------------------------------------------------------------------------
!
!                  Check that the variable is available for this node:
!                  ---------------------------------------------------
                   IF ( NewSol % Perm(i) /= 0 ) THEN
                      NewValue(NewSol % Perm(i)) = InterpolateInElement( &
                           CurrentElement, ElementValues, LocalCoordinates(1), &
                           LocalCoordinates(2), LocalCoordinates(3) )
                   END IF
                ELSE
                   IF ( NewSol % Perm(i) /= 0 ) NewValue(NewSol % Perm(i)) = 0.0d0
                END IF

!------------------------------------------------------------------------------
             END IF
             Var => Var % Next
          END DO
!------------------------------------------------------------------------------
       END DO
!------------------------------------------------------------------------------
!
!      Construct mesh projector, if requested. Next time around
!      will use the existing projector to interpolate values:
!      ---------------------------------------------------------
       IF ( PRESENT(Projector) ) THEN
          n = NewMesh % NumberOfNodes

          ALLOCATE( Rows(n+1) )
          Rows(1) = 1
          DO i=2,n+1
             IF ( ASSOCIATED( ElemPtrs(i-1) % Element ) ) THEN
                Rows(i) = Rows(i-1) + &
                    ElemPtrs(i-1) % Element % Type % NumberOfNodes
             ELSE
                Rows(i) = Rows(i-1) + 1
             END IF
          END DO

          ALLOCATE( Cols(Rows(n+1)-1), Values(Rows(n+1)-1) )
          Cols   = 0
          Values = 0

          ALLOCATE( Projector )
          Projector % Matrix => AllocateMatrix()
          Projector % Matrix % NumberOfRows = n
          Projector % Matrix % Rows   => Rows
          Projector % Matrix % Cols   => Cols 
          Projector % Matrix % Values => Values

          Projector % Next => NewMesh % Projector
          NewMesh % Projector => Projector
          NewMesh % Projector % Mesh => OldMesh

          ALLOCATE( RInd(OldMesh % NumberOfNodes) )
          RInd = 0

          DO i=1,n
             CurrentElement => ElemPtrs(i) % Element

             IF ( .NOT. ASSOCIATED( CurrentElement ) ) THEN
                Cols( Rows(i) ) = i
                RInd(i) = RInd(i) + 1
                CYCLE
             END IF

             k = CurrentElement % Type % NumberOfNodes
             NodeIndexes => CurrentElement % NodeIndexes

             RInd(NodeIndexes) = RInd(NodeIndexes) + 1

             u = LocalU(i)
             v = LocalV(i)
             w = LocalW(i)

             Basis(1:k) = 0.0d0
             DO j=1,k
                l = Rows(i) + j - 1
                Cols(l)   = NodeIndexes(j)
                Basis(j)  = 1.0d0
                Values(l) = &
                   InterpolateInElement( CurrentElement, Basis, u, v, w )
                Basis(j)  = 0.0d0
             END DO
          END DO

          DEALLOCATE( ElemPtrs, LocalU, LocalV, LocalW )

!
!         Store also the transpose of the projector:
!         ------------------------------------------ 
          n = OldMesh % NumberOfNodes

          ALLOCATE( Rows(n+1) )
          Rows(1) = 1
          DO i=2,n+1
             Rows(i) = Rows(i-1) + RInd(i-1)
          END DO

          ALLOCATE( Cols(Rows(n+1)-1), Values(Rows(n+1)-1) )
          Projector % TMatrix => AllocateMatrix()
          Projector % TMatrix % NumberOfRows = n
          Projector % TMatrix % Rows   => Rows
          Projector % TMatrix % Cols   => Cols 
          Projector % TMatrix % Values => Values

          RInd = 0
          DO i=1,Projector % Matrix % NumberOfRows
             DO j=Projector % Matrix % Rows(i), Projector % Matrix % Rows(i+1)-1
                k = Projector % Matrix % Cols(j)
                l = Rows(k) + RInd(k)
                RInd(k) = RInd(k) + 1
                Cols(l) = i
                Values(l) = Projector % Matrix % Values(j)
             END DO
          END DO

          DEALLOCATE( RInd )

          IF ( PRESENT(OldVariables) ) CALL ApplyProjector
       END IF

       DEALLOCATE( ElementNodes % x, ElementNodes % y, &
                   ElementNodes % z, ElementValues )

CONTAINS

!------------------------------------------------------------------------------
     SUBROUTINE ApplyProjector
!------------------------------------------------------------------------------
        INTEGER :: i
!------------------------------------------------------------------------------
        Var => OldVariables
        DO WHILE( ASSOCIATED(Var) )
           IF ( Var % DOFs == 1 .AND. &
              (Var % Name(1:10) /= 'coordinate') .AND. &
                 (Var % Name(1:4) /= 'time') ) THEN
 
              OldSol => VariableGet( OldMesh % Variables, Var % Name, .TRUE. )
              NewSol => VariableGet( NewMesh % Variables, Var % Name, .TRUE. )
              IF ( .NOT. (ASSOCIATED ( NewSol ) ) ) THEN
                 Var => Var % Next
                 CYCLE
              END IF

              CALL CRS_ApplyProjector( Projector % Matrix, &
                   OldSol % Values, OldSol % Perm,         &
                   NewSol % Values, NewSol % Perm )

              IF ( ASSOCIATED( OldSol % PrevValues ) ) THEN
                 DO i=1,SIZE(OldSol % PrevValues,2)
                    CALL CRS_ApplyProjector( Projector % Matrix,  &
                         OldSol % PrevValues(:,i), OldSol % Perm, &
                         NewSol % PrevValues(:,i), NewSol % Perm )
                 END DO
              END IF
           END IF
           Var => Var % Next
        END DO
!------------------------------------------------------------------------------
     END SUBROUTINE ApplyProjector
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
   END SUBROUTINE InterpolateMeshToMesh
!------------------------------------------------------------------------------
