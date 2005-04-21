!********************************************************************
!
! File: elmer_parmat.f90
! Software: ELMER
! File info: These routines are for parallel version of the ELMER
!            solver.
!
! Author: Jouni Malinen, Juha Ruokolainen
!
! $Id: SParIterSolver.f90,v 1.7 2005/04/04 06:18:31 jpr Exp $
!
!********************************************************************

#include "huti_fdefs.h"

MODULE SParIterSolve

  USE Types
  USE Lists
  USE SParIterGlobals
  USE SParIterComm
  USE SParIterPrecond

  USE CRSMatrix

  IMPLICIT NONE

CONTAINS

  SUBROUTINE Dummy
  END SUBROUTINE Dummy


  SUBROUTINE DPCond( u,v,ipar )
    REAL(KIND=dp) :: u(*),v(*)
    integer :: ipar(*)

    u(1:HUTI_NDIM) = v(1:HUTI_NDIM)
  END SUBROUTINE DPCond


  SUBROUTINE CPCond( u,v,ipar )
    COMPLEX(KIND=dp) :: u(*),v(*)
    integer :: ipar(*)

    u(1:HUTI_NDIM) = v(1:HUTI_NDIM)
  END SUBROUTINE CPCond

  !********************************************************************
  !
  ! Initialize the Matrix structures for parallel environment
  !
  FUNCTION ParInitMatrix( SourceMatrix, Nodes, DOFs ) RESULT ( SParMatrixDesc )

    TYPE (Matrix_t),TARGET :: SourceMatrix
    TYPE (Nodes_t), TARGET :: Nodes
    INTEGER :: DOFs
    TYPE (SParIterSolverGlobalD_t), POINTER :: SParMatrixDesc

    TYPE (ParEnv_t), POINTER :: ParallelEnv
    !******************************************************************

    IF ( .NOT. ParEnv % Initialized ) THEN
       ParallelEnv => ParCommInit()
    END IF

    ALLOCATE( SParMatrixDesc )
    CALL ParEnvInit( SParMatrixDesc, Nodes, SourceMatrix, DOFs )

    SParMatrixDesc % Matrix => SourceMatrix
    SParMatrixDesc % DOFs = DOFs
    SParMatrixDesc % Nodes => Nodes
    
    ParEnv = SParMatrixDesc % ParEnv
    SParMatrixDesc % SplittedMatrix => &
                   SplitMatrix( SourceMatrix, Nodes, DOFs )

  END FUNCTION ParInitMatrix


!********************************************************************
!********************************************************************
!
! Split the given matrix (SourceMatrix) to InsideMatrix part (elements
! inside a partition) and InterfaceMatrix table (interface blocks).
!
  FUNCTION SplitMatrix( SourceMatrix, Nodes, DOFs ) &
       RESULT ( SplittedMatrix )

    USE Types
    IMPLICIT NONE

    TYPE (Matrix_t) :: SourceMatrix     ! Original matrix in this partition
    TYPE (Nodes_t) :: Nodes             ! All the nodes in this partition
    INTEGER :: DOFs                     ! Degrees of freedom per node

    TYPE (SplittedMatrixT), POINTER :: SplittedMatrix

  ! External routines

! EXTERNAL SearchNode
! INTEGER :: SearchNode

  ! Local variables

    INTEGER :: i, j, k, l, n, dd, RowInd, ColInd, RowStart, RowEnd, Gcol
    INTEGER :: InsideMRows, InsideMCols, Row, Col, currifi, RowOwner
    INTEGER, DIMENSION(:), ALLOCATABLE :: OwnIfMRows, OwnIfMCols, OwnOCOR
    INTEGER, DIMENSION(:), ALLOCATABLE :: NbsIfMRows, NbsIfMCols, NbsOCOR
    INTEGER, DIMENSION(:), ALLOCATABLE :: OwnOldCols, NbsOldCols
    INTEGER :: FoundIndex, AtLeastOneCol, OldCols, NewCol
    INTEGER, POINTER :: ColBuffer(:), RowBuffer(:), Ncol(:)

    TYPE (NeighbourList_t), POINTER :: CurrNbsL

    TYPE (Matrix_t), DIMENSION(:), ALLOCATABLE :: OwnIfMatrix
    TYPE (Matrix_t), DIMENSION(:), POINTER :: NbsIfMatrix
    TYPE (Matrix_t), DIMENSION(:), ALLOCATABLE :: RecvdIfMatrix

    LOGICAL :: NeedMass, GotNewCol

real(kind=dp) :: cputime,st
  !******************************************************************

    ALLOCATE( SplittedMatrix )
    SplittedMatrix % InsideMatrix => AllocateMatrix()

    ALLOCATE( SplittedMatrix % GlueTable )

    NULLIFY( SplittedMatrix % IfMatrix )
    NULLIFY( SplittedMatrix % NbsIfMatrix )
    NULLIFY( SplittedMatrix % Vecindices )
    NULLIFY( SplittedMatrix % IfVecs )
    NULLIFY( SplittedMatrix % RHS )
    NULLIFY( SplittedMatrix % Work )
    NULLIFY( SplittedMatrix % ResBuf )
    NULLIFY( SplittedMatrix % TmpXVec )
    NULLIFY( SplittedMatrix % TmpRVec )

  !----------------------------------------------------------------------
  !
  ! Copy the glueing table row and column indices
  !
  !----------------------------------------------------------------------

    ALLOCATE( SplittedMatrix % GlueTable % Rows( SIZE(SourceMatrix % Rows) ) )
    ALLOCATE( SplittedMatrix % GlueTable % Cols( SIZE(SourceMatrix % Cols) ) )
    ALLOCATE( SplittedMatrix % GlueTable % Inds( SIZE(SourceMatrix % Cols) ) )
    ALLOCATE( SplittedMatrix % GlueTable % RowOwner(SIZE(SourceMatrix % Rows)))

    SplittedMatrix % GlueTable % Rows(:) = SourceMatrix % Rows(:)
    SplittedMatrix % GlueTable % Cols(:) = SourceMatrix % Cols(:)

    ALLOCATE( SplittedMatrix % VecIndices( ParEnv % PEs ) )
    CALL CountNeighbourConns( SourceMatrix, SplittedMatrix, Nodes, DOFs )

  !----------------------------------------------------------------------
  !
  ! Allocate some temporary work space
  !
  !----------------------------------------------------------------------

    ALLOCATE( OwnIfMRows( ParEnv % PEs ) )
    ALLOCATE( OwnIfMCols( ParEnv % PEs ) )
    ALLOCATE( NbsIfMRows( ParEnv % PEs ) )
    ALLOCATE( NbsIfMCols( ParEnv % PEs ) )
    ALLOCATE( OwnOCOR( ParEnv % PEs ) )
    ALLOCATE( NbsOCOR( ParEnv % PEs ) )
    ALLOCATE( OwnOldCols( ParEnv % PEs ) )
    ALLOCATE( NbsOldCols( ParEnv % PEs ) )
    OwnIfMRows(:) = 0; OwnIfMCols(:) = 0; NbsIfMRows(:) = 0; NbsIfMCols(:) = 0

  !----------------------------------------------------------------------
  !
  ! Compute the memory allocations for splitted matrix blocks
  !
  !----------------------------------------------------------------------
    InsideMRows = 0; InsideMCols = 0
    DO i = 1, SourceMatrix % NumberOfRows

       AtLeastOneCol = 0; OwnOCOR(:) = 0; NbsOCOR(:) = 0
       RowInd = (SourceMatrix % INVPerm(i) + DOFs-1) / DOFs

       IF ( Nodes % NeighbourList(RowInd) % Neighbours(1)==ParEnv % MyPE ) THEN
!
!         Connection is local-local or local-if:
!         --------------------------------------
          DO j = SourceMatrix % Rows(i), SourceMatrix % Rows(i+1) - 1

             ColInd = SourceMatrix % Cols(j)
             ColInd = (SourceMatrix % INVPerm(ColInd) + DOFs-1) / DOFs

             IF ( Nodes % NeighbourList(ColInd) % Neighbours(1) == &
                                ParEnv % MyPE ) THEN

	      !----------------------------------------------------------
	      !
	      ! Connection is local-local
	      !
	      !----------------------------------------------------------

                InsideMCols = InsideMCols + 1
                AtLeastOneCol = 1
             ELSE

	      !----------------------------------------------------------
	      !
	      ! Connection is local-if
	      !
	      !----------------------------------------------------------

                CurrNbsL => Nodes % NeighbourList( ColInd )
                NbsIfMCols( CurrNbsL % Neighbours(1) + 1 ) = &
                     NbsIfMCols( CurrNbsL % Neighbours(1) + 1 ) + 1
                NbsOCOR( CurrNbsL % Neighbours(1) + 1 ) = 1
	  END IF
	END DO

     ELSE

	!----------------------------------------------------------------
	!
	! Connection is if-local or if-if
	!
	!----------------------------------------------------------------

	DO j = SourceMatrix % Rows(i), SourceMatrix % Rows(i+1) - 1

           ColInd = SourceMatrix % Cols(j)
           ColInd = (SourceMatrix % INVPerm(ColInd) + DOFs-1) / DOFs

	   IF ( Nodes % NeighbourList(ColInd) % Neighbours(1) == &
                            ParEnv % MyPE ) THEN

	      !----------------------------------------------------------
	      !
	      ! Connection is if-local
	      !
	      !----------------------------------------------------------

	      CurrNbsL => Nodes % NeighbourList(RowInd)
              OwnIfMCols( CurrNbsL % Neighbours(1) + 1) = &
                   OwnIfMCols( CurrNbsL % Neighbours(1) + 1) + 1
              OwnOCOR( CurrNbsL % Neighbours(1) + 1) = 1
              
	   ELSE

	      !----------------------------------------------------------
	      !
	      ! Connection is if-if
	      !
	      !----------------------------------------------------------
	      CurrNbsL => Nodes % NeighbourList(ColInd)
              NbsIfMCols( CurrNbsL % Neighbours(1) + 1) = &
                   NbsIfMCols( CurrNbsL % Neighbours(1) + 1) + 1
              NbsOCOR( CurrNbsL % Neighbours(1) + 1) = 1
	   END IF
	END DO

     END IF

     InsideMRows = InsideMRows + AtLeastOneCol
     NbsIfMRows(:) = NbsIfMRows(:) + NbsOCOR(:)
     OwnIfMRows(:) = OwnIfMRows(:) + OwnOCOR(:)
  END DO

  !----------------------------------------------------------------------
  !
  ! Allocate the block inside this partition
  !
  !----------------------------------------------------------------------

  ALLOCATE( SplittedMatrix % InsideMatrix % Rows( InsideMRows + 1 ) )
  ALLOCATE( SplittedMatrix % InsideMatrix % Cols( InsideMCols ) )
  ALLOCATE( SplittedMatrix % InsideMatrix % Diag( InsideMRows ) )
  ALLOCATE( SplittedMatrix % InsideMatrix % GRows( InsideMRows ) )
  ALLOCATE( SplittedMatrix % InsideMatrix % Gorder( InsideMRows ) )
  ALLOCATE( SplittedMatrix % InsideMatrix % Values( InsideMCols ) )

  NeedMass = .FALSE.
  IF (  ASSOCIATED( SourceMatrix % MassValues ) ) THEN
     IF ( SIZE( SourceMatrix % Values ) == SIZE( SourceMatrix % MassValues ) ) NeedMass = .TRUE.
  END IF
  NULLIFY( SplittedMatrix % InsideMatrix % MassValues )
  IF ( NeedMass ) ALLOCATE( SplittedMatrix % InsideMatrix % MassValues( InsideMCols ) )

  SplittedMatrix % InsideMatrix % Ordered = .FALSE.
  NULLIFY( SplittedMatrix % InsideMatrix % ILUValues )

  !----------------------------------------------------------------------
  !
  ! Allocate the interface blocks (both the own parts and the ones to be
  ! sent to the neighbours)
  !
  !----------------------------------------------------------------------

  ALLOCATE( SplittedMatrix % IfMatrix( ParEnv % PEs ) )
  ALLOCATE( SplittedMatrix % IfVecs( ParEnv % PEs ) )
  ALLOCATE( SplittedMatrix % NbsIfMatrix( ParEnv % PEs ) )
  ALLOCATE( OwnIfMatrix( ParEnv % PEs ) )
  ALLOCATE( RecvdIfMatrix( ParEnv % PEs ) )

  NbsIfMatrix => SplittedMatrix  % NbsIfMatrix
 
  SplittedMatrix % InsideMatrix % NumberOfRows = InsideMRows

  DO i = 1, ParEnv % PEs

     RecvdIfMatrix(i) % NumberOfRows = 0

     NbsIfMatrix(i) % NumberOfRows = NbsIfMRows(i)
     IF ( NbsIfMRows(i) /= 0 ) THEN
	ALLOCATE( NbsIfMatrix(i) % Rows( NbsIfMRows(i)+1 ) )
	ALLOCATE( NbsIfMatrix(i) % Cols( NbsIfMCols(i) ) )
	ALLOCATE( NbsIfMatrix(i) % Diag( NbsIfMRows(i) ) )
	ALLOCATE( NbsIfMatrix(i) % GRows( NbsIfMRows(i) ) )
	ALLOCATE( NbsIfMatrix(i) % RowOwner( NbsIfMRows(i) ) )
	ALLOCATE( NbsIfMatrix(i) % Values( NbsIfMCols(i) ) )

        NULLIFY( NbsIfMatrix(i) % MassValues )
        IF ( NeedMass ) ALLOCATE( NbsIfMatrix(i) % MassValues( NbsIfMCols(i) ) )
     END IF

     OwnIfMatrix(i) % NumberOfRows = OwnIfMRows(i)
     IF ( OwnIfMRows(i) /= 0 ) THEN
	ALLOCATE( OwnIfMatrix(i) % Rows( OwnIfMRows(i)+1 ) )
	ALLOCATE( OwnIfMatrix(i) % Cols( OwnIfMCols(i) ) )
	ALLOCATE( OwnIfMatrix(i) % Diag( OwnIfMRows(i) ) )
	ALLOCATE( OwnIfMatrix(i) % GRows( OwnIfMRows(i) ) )
	ALLOCATE( OwnIfMatrix(i) % Values( OwnIfMCols(i) ) )
	ALLOCATE( OwnIfMatrix(i) % RowOwner( OwnIfMRows(i) ) )

        NULLIFY( OwnIfMatrix(i) % MassValues )
	IF ( NeedMass ) ALLOCATE( OwnIfMatrix(i) % MassValues( OwnIfMCols(i) ) )
     END IF
  END DO

  !----------------------------------------------------------------------
  !
  ! Copy the actual indices into correct blocks
  !
  !----------------------------------------------------------------------

  InsideMRows = 1; InsideMCols = 1; OldCols = 1
  NbsIfMRows(:) = 1; NbsIfMCols(:) = 1; NbsOldCols(:) = 1
  OwnIfMRows(:) = 1; OwnIfMCols(:) = 1; OwnOldCols(:) = 1
  DO i = 1, SourceMatrix % NumberOfRows
     AtLeastOneCol = 0; NbsOCOR(:) = 0; OwnOCOR(:) = 0

     RowInd   = (SourceMatrix % INVPerm(i) + DOFs-1) / DOFs
     RowOwner = Nodes % NeighbourList(RowInd) % Neighbours(1)

     IF ( RowOwner == ParEnv % MyPE ) THEN
	!----------------------------------------------------------------
	!
	! Connection is local-local or local-if
	!
	!----------------------------------------------------------------
	
	DO j = SourceMatrix % Rows(i), SourceMatrix % Rows(i+1) - 1

           ColInd =  SourceMatrix % Cols(j)
           ColInd = (SourceMatrix % INVPerm(ColInd) + DOFs-1)/ DOFs

	   IF ( Nodes % NeighbourList(ColInd) % Neighbours(1) == &
		ParEnv % MyPE ) THEN

	      !----------------------------------------------------------
	      !
	      ! Connection is local-local
	      !
	      !----------------------------------------------------------

	      SplittedMatrix % InsideMatrix % Cols( InsideMCols ) = &
                             SourceMatrix % Cols(j)
	      SplittedMatrix % GlueTable % Inds(j) = InsideMCols
	      AtLeastOneCol = 1
	      InsideMCols = InsideMCols + 1
	   ELSE

	      !----------------------------------------------------------
	      !
	      ! Connection is local-if
	      !
	      !----------------------------------------------------------

	      currifi = Nodes % NeighbourList(Colind) % Neighbours(1) + 1

              NbsIfMatrix(currifi) % Cols(NbsIfMcols(currifi)) =  &
                  Nodes  % GlobalNodeNumber(ColInd) * DOFs - &
                      (DOFs - 1 - MOD(SourceMatrix % Cols(j)-1,DOFs))

              NbsIfMcols(currifi) = NbsIfMcols(currifi) + 1
              NbsOCOR(currifi) = 1
              SplittedMatrix % GlueTable % Inds(j) = -(ParEnv % PEs + currifi)

	   END IF
	END DO

     ELSE

	!----------------------------------------------------------------
	!
	! Connection is if-local or if-if
	!
	!----------------------------------------------------------------

	DO j = SourceMatrix % Rows(i), SourceMatrix % Rows(i+1) - 1
           ColInd = SourceMatrix % Cols(j)
           ColInd = (SourceMatrix % INVPerm(ColInd) + DOFs-1) / DOFs

	   IF ( Nodes % NeighbourList(ColInd) % Neighbours(1) == &
		ParEnv % MyPE ) THEN

	      !----------------------------------------------------------
	      !
	      ! Connection is if-local
	      !
	      !----------------------------------------------------------

	      currifi = Nodes % NeighbourList(RowInd) % Neighbours(1) + 1

              OwnIfMatrix(currifi) % Cols(OwnIfMcols(currifi)) =  &
                  Nodes  % GlobalNodeNumber(ColInd) * DOFs - &
                      (DOFs - 1 - MOD(SourceMatrix % Cols(j)-1,DOFs))

              SplittedMatrix % GlueTable % Inds(j) = -currifi
              OwnOCOR(currifi) = 1
              OwnIfMcols(currifi) = OwnIfMcols(currifi) + 1

	   ELSE

	      !----------------------------------------------------------
	      !
	      ! Connection is if-if
	      !
	      !----------------------------------------------------------
              currifi = Nodes % NeighbourList(ColInd) % Neighbours(1) + 1

              NbsIfMatrix(currifi) % Cols(NbsIfMcols(currifi)) =  &
                Nodes  % GlobalNodeNumber(ColInd) * DOFs - &
                    (DOFs - 1 - MOD(SourceMatrix % Cols(j)-1,DOFs))

              SplittedMatrix % GlueTable % Inds(j) = -(ParEnv % PEs + currifi)
              NbsOCOR(currifi) = 1
              NbsIfMcols(currifi) = NbsIfMcols(currifi) + 1
	   END IF
	END DO

     END IF

     !-------------------------------------------------------------------
     !
     ! Update the row indices to keep the CRS structures valid
     !
     !-------------------------------------------------------------------

     RowInd = Nodes % GlobalNodeNumber(RowInd) * DOFs - (DOFs-1-MOD(i-1, DOFs))

     IF ( AtLeastOneCol /= 0 ) THEN
        SplittedMatrix % InsideMatrix % Rows( InsideMRows )  = OldCols
        SplittedMatrix % InsideMatrix % GRows( InsideMRows ) = RowInd
     END IF

     DO j = 1, ParEnv % PEs
        IF ( OwnOCOR(j) /= 0 ) THEN
           OwnIfMatrix(j) % Rows(OwnIfMRows(j))  = OwnOldCols(j)
           OwnIfMatrix(j) % GRows(OwnIfMRows(j)) = RowInd
           OwnIfMatrix(j) % RowOwner(OwnIfMRows(j)) = RowOwner
        END IF

	IF ( NbsOCOR(j) /= 0 ) THEN
	   NbsIfMatrix(j) % Rows(NbsIfMRows(j))  = NbsOldCols(j)
	   NbsIfMatrix(j) % GRows(NbsIfMRows(j)) = RowInd
	   NbsIfMatrix(j) % RowOwner(NbsIfMRows(j)) = RowOwner
	END IF
     END DO

     InsideMRows = InsideMRows + AtLeastOneCol
     NbsIfMRows(:) = NbsIfMRows(:) + NbsOCOR(:)
     OwnIfMRows(:) = OwnIfMRows(:) + OwnOCOR(:)

     OldCols = InsideMCols
     OwnOldCols(:) = OwnIfMCols(:)
     NbsOldCols(:) = NbsIfMCols(:)
  END DO

  IF ( SplittedMatrix % InsideMatrix % NumberOfRows /= 0 ) THEN
     SplittedMatrix % InsideMatrix % Rows( InsideMRows ) = InsideMCols
  END IF

  DO j = 1, ParEnv % PEs
     IF ( OwnIfMatrix(j) % NumberOfRows /= 0 ) &
	  OwnIfMatrix(j) % Rows(OwnIfMRows(j)) = OwnIfMCols(j)

     IF ( NbsIfMatrix(j) % NumberOfRows /= 0 ) &
	  NbsIfMatrix(j) % Rows(NbsIfMRows(j)) = NbsIfMCols(j)
  END DO

  DO j = 1, ParEnv % PEs
     IF ( OwnIfMatrix(j) % NumberOfRows /= (OwnIfMRows(j) - 1) .OR. &
          NbsIfMatrix(j) % NumberOfRows /= (NbsIfMRows(j) - 1) ) THEN
        WRITE( Message, * ) OwnIfMRows, NbsIfMRows, OwnIfMCols, NbsIfMCols
        CALL Error( 'SplitMatrix', Message )
     END IF
  END DO

  !----------------------------------------------------------------------
  !
  ! Exchange the interface blocks and glue received interface parts into
  ! the interface blocks already at this processor.
  !
  !----------------------------------------------------------------------
st = cputime()
  CALL ExchangeInterfaces( NbsIfMatrix, RecvdIfMatrix )

  !----------------------------------------------------------------------
  ! Insert matrix elements to splittedmatrix if got from the
  ! exchange operation.
  !----------------------------------------------------------------------
print*,'exchangeif ', parenv % mype, cputime()-st
call flush(6)
st = cputime()
  n = SplittedMatrix % InsideMatrix % NumberOfRows

  DO i=1,n
     SplittedMatrix % InsideMatrix % Gorder(i) = i
  END DO

  CALL SortI( n, SplittedMatrix % InsideMatrix % GRows, &
        SplittedMatrix % InsideMatrix % Gorder )

  ALLOCATE( RowBuffer( n+1 ) )
  RowBuffer = SplittedMatrix % InsideMatrix % Rows
print*,'initinsert: ', parenv % mype, cputime()-st
call flush(6)
st = cputime()

  GotNewCol = .FALSE.
  DO i=1,ParEnv % PEs
     DO j=1,RecvdIfMatrix(i) % NumberOfRows
!
!       Search for position of global row in this partitions numbering:
!       ---------------------------------------------------------------
        RowInd = SearchIAItem( n, SplittedMatrix % InsideMatrix % GRows, &
          RecvdIfMatrix(i) % GRows(j), SplittedMatrix % InsideMatrix % Gorder)

        IF ( RowInd > 0 ) THEN
           DO k = RecvdIfMatrix(i) % Rows(j), RecvdIfMatrix(i) % Rows(j+1) - 1
              ColInd = -1

              DO l = RowBuffer(RowInd),  RowBuffer(RowInd+1) - 1
!
!                Equation DOF numbering to partition nodal numbering:
!                ----------------------------------------------------
                 GCol = SplittedMatrix % InsideMatrix % Cols(l)
                 GCol = (SourceMatrix % INVPerm(GCol) + DOFs-1) / DOFs
!
!                Partition nodal numbering to global nodal DOF numbering:
!                --------------------------------------------------------
                 GCol = Nodes % GlobalNodeNumber(GCol)
                 GCol = DOFs * GCol - (DOFs - 1 - &
                      MOD( SplittedMatrix % InsideMatrix % Cols(l) - 1,DOFs ) )

                 IF ( RecvdIfMatrix(i) % Cols(k) == GCol ) THEN
                    ColInd = GCol
                    EXIT
                 END IF
              END DO

              IF ( ColInd == -1 ) THEN
                 ColInd = SearchIAItem( n, &
                      SplittedMatrix % InsideMatrix % GRows, &
                      RecvdIfMatrix(i) % Cols(k), &
                      SplittedMatrix % InsideMatrix % Gorder )

                 IF ( ColInd /= -1 )  THEN
                    GotNewCol = .TRUE.
                    DO l = RowInd+1, n+1
                       SplittedMatrix % InsideMatrix % Rows(l) = &
                            SplittedMatrix % InsideMatrix % Rows(l) + 1
                    END DO
                 END IF
              END IF
           END DO
        END IF
     END DO
  END DO
print*,'rowinsert: ', parenv % mype, cputime()-st
call flush(6)
st = cputime()

  IF ( GotNewCol ) THEN
  ALLOCATE( ColBuffer( SplittedMatrix % InsideMatrix % Rows(n+1)-1 ) )
  ColBuffer = 0

  DO i=1,n
     j = SplittedMatrix % InsideMatrix % Rows(i)
     DO k = RowBuffer(i), RowBuffer(i+1) - 1
        l = k - RowBuffer(i)
        ColBuffer(k) = SplittedMatrix % InsideMatrix % Cols(k)
     END DO
  END DO

  SplittedMatrix % InsideMatrix % Cols => ColBuffer
  SplittedMatrix % InsideMatrix % Rows =  RowBuffer
  DEALLOCATE( RowBuffer )

  ALLOCATE( ColBuffer( SIZE(SplittedMatrix % InsideMatrix % Cols) ) )
  NewCol    = 0
  ColBuffer = 0
print*,'initcolinsert: ', parenv % mype, cputime()-st
call flush(6)
st = cputime()

  DO i=1,ParEnv % PEs
     DO j=1,RecvdIfMatrix(i) % NumberOfRows

        RowInd = SearchIAItem( n, SplittedMatrix % InsideMatrix % GRows, &
          RecvdIfMatrix(i) % GRows(j), SplittedMatrix % InsideMatrix % Gorder )
        
        IF ( RowInd > 0 ) THEN
           DO k = RecvdIfMatrix(i) % Rows(j), RecvdIfMatrix(i) % Rows(j+1) - 1
              ColInd = -1
              DO l = SplittedMatrix % InsideMatrix % Rows(RowInd),  &
                     SplittedMatrix % InsideMatrix % Rows(RowInd+1) - 1

                 IF ( SplittedMatrix % InsideMatrix % Cols(l) == 0 ) EXIT
!
!                Equation DOF numbering to partition nodal numbering:
!                ----------------------------------------------------
                 GCol = SplittedMatrix % InsideMatrix % Cols(l)
                 GCol = (SourceMatrix % INVPerm(GCol) + DOFs-1) / DOFs
!
!                Partition nodal numbering to global nodal DOF numbering:
!                --------------------------------------------------------
                 GCol = Nodes % GlobalNodeNumber( GCol )

                 GCol = DOFs * GCol - (DOFs - 1 - &
                      MOD( SplittedMatrix % InsideMatrix % Cols(l) - 1,DOFs ) )

                 IF ( RecvdIfMatrix(i) % Cols(k) == GCol ) THEN
                    ColInd = GCol
                    EXIT
                 END IF
              END DO

              IF ( ColInd == -1 ) THEN
                 ColInd = SearchIAItem( n, &
                      SplittedMatrix % InsideMatrix % GRows, RecvdIfMatrix(i) % Cols(k), &
                                SplittedMatrix % InsideMatrix % Gorder )

                 IF ( ColInd /= -1 )  THEN
                    ColInd = SearchNode( Nodes, ( RecvdIfMatrix(i) % Cols(k) - 1 ) / DOFs + 1 )
                    ColInd = DOFs * ColInd - ( DOFs-1-MOD(RecvdIfMatrix(i) % Cols(k)-1, DOFs) )
                    ColInd = SourceMatrix % Perm( ColInd )

                    DO GCol = SplittedMatrix % InsideMatrix % Rows(RowInd), &
                              SplittedMatrix % InsideMatrix % Rows(RowInd+1) - 1
                       IF ( SplittedMatrix % InsideMatrix % Cols(Gcol) == 0 )   EXIT
                       IF ( SplittedMatrix % InsideMatrix % Cols(GCol)>ColInd ) EXIT
                    END DO

                    IF ( SplittedMatrix % InsideMatrix % Cols(Gcol) > 0 ) THEN
                       DO l = SplittedMatrix % InsideMatrix % Rows(n+1) - 1, GCol, -1
                          SplittedMatrix % InsideMatrix % Cols(l+1) = &
                                              SplittedMatrix % InsideMatrix % Cols(l)
                       END DO
                    END IF

                    NewCol  =  NewCol + 1
                    ColBuffer( NewCol ) = GCol
                    SplittedMatrix % InsideMatrix % Cols(GCol) = ColInd

                    DO l = RowInd+1, n+1
                       SplittedMatrix % InsideMatrix % Rows(l) = &
                            SplittedMatrix % InsideMatrix % Rows(l) + 1
                    END DO
                 END IF
              END IF
           END DO
        END IF
     END DO
  END DO

!-----------------------------------------------------------------------------
  
  DO i=1, NewCol
     DO j=1,SIZE( SplittedMatrix % GlueTable % Inds )
        IF ( SplittedMatrix % GlueTable % Inds(j) >= ColBuffer(i) ) THEN
          SplittedMatrix % GlueTable % Inds(j) = &
             SplittedMatrix % GlueTable % Inds(j)  + 1
        END IF
     END DO
  END DO
print*,'colinsert: ', parenv % mype, cputime()-st
call flush(6)

!-----------------------------------------------------------------------------

  DEALLOCATE( ColBuffer )
  END IF

  ALLOCATE( SplittedMatrix % InsideMatrix % Values( & 
       SplittedMatrix % InsideMatrix % Rows(n+1) - 1 ) )

  NULLIFY( SplittedMatrix % InsideMatrix % MassValues )
  IF ( NeedMass ) &
     ALLOCATE( SplittedMatrix % InsideMatrix % MassValues( & 
        SplittedMatrix % InsideMatrix % Rows(n+1) - 1 ) )

!-----------------------------------------------------------------------------

st = cputime()
  CALL ClearInsideC( SourceMatrix, SplittedMatrix % InsideMatrix, &
             RecvdIfMatrix, Nodes, DOFs )
print*,'clear: ', parenv % mype, cputime()-st
call flush(6)
st = cputime()

  SplittedMatrix % IfMatrix(:) % NumberOfRows = 0
  DO i = 1, ParEnv % PEs
     IF ( ( OwnIfMatrix(i) % NumberOfRows   /= 0 ) .OR. &
           ( RecvdIfMatrix(i) % NumberOfRows /= 0 ) ) THEN
        CALL CombineCRSMatIndices( OwnIfMatrix(i), RecvdIfMatrix(i), &
                 SplittedMatrix % IfMatrix(i) )
     END IF
  END DO
print*,'combine: ', parenv % mype, cputime()-st
call flush(6)
st = cputime()


  ALLOCATE( SplittedMatrix % IfLCols(ParEnv % PEs)  )
  DO i = 1, ParEnv % PEs
     IF ( SplittedMatrix % IfMatrix(i) % NumberOfRows /= 0 ) THEN
        ALLOCATE( SplittedMatrix % IfVecs(i) % IfVec( &
             SplittedMatrix % IfMatrix(i) % NumberOfRows ), &
             SplittedMatrix % IfMatrix(i) % Values( SIZE(  &
             SplittedMatrix % IfMatrix(i) % Cols)), &
             SplittedMatrix % IfLCols(i) % IfVec( SIZE( &
             SplittedMatrix % IfMatrix(i) % Cols ) )  )
	SplittedMatrix % IfLCols(i) % IfVec   = 0
	SplittedMatrix % IfVecs(i) % IfVec    = 0
	SplittedMatrix % IfMatrix(i) % Values = 0.0d0

        NULLIFY( SplittedMatrix % IfMatrix(i) % MassValues )
        IF ( NeedMass ) THEN
           ALLOCATE( SplittedMatrix % IfMatrix(i) % MassValues(  &
              SIZE(SplittedMatrix % IfMatrix(i) % Cols) ) )
           SplittedMatrix % IfMatrix(i) % MassValues = 0.0d0
        END IF
     END IF
  END DO

  !----------------------------------------------------------------------
  !
  ! Renumber the Degrees of Freedom in SplittedMatrix % InsideMatrix
  !
  !----------------------------------------------------------------------
  CALL RenumberDOFs( SourceMatrix, SplittedMatrix, Nodes, DOFs )
print*,'renumber: ', parenv % mype, cputime()-st
call flush(6)
st = cputime()

  !----------------------------------------------------------------------
  !
  ! Build indirect indexing for vectors to speed up mat-vec multiply
  !
  !----------------------------------------------------------------------
  CALL BuildRevVecIndices( SplittedMatrix )
print*,'buildrev: ', parenv % mype, cputime()-st
call flush(6)
st = cputime()

  !----------------------------------------------------------------------
  !
  ! Clean up temporary work space
  !
  !----------------------------------------------------------------------

  DEALLOCATE( OwnIfMRows, OwnIfMCols, OwnOCOR, OwnOldCols, &
       NbsIfMRows, NbsIfMCols, NbsOCOR, NbsOldCols )

  DO i= 1,ParEnv % PEs
     IF ( OwnIfMatrix(i) % NumberOfRows > 0 ) THEN
        DEALLOCATE( OwnIfMatrix(i) % Rows )
        DEALLOCATE( OwnIfMatrix(i) % Diag )
        DEALLOCATE( OwnIfMatrix(i) % Cols )
        DEALLOCATE( OwnIfMatrix(i) % GRows )
        DEALLOCATE( OwnIfMatrix(i) % RowOwner )
     END IF

     IF ( RecvdIfMatrix(i) % NumberOfRows > 0 ) THEN
        DEALLOCATE( RecvdIfMatrix(i) % Rows )
        DEALLOCATE( RecvdIfMatrix(i) % Diag )
        DEALLOCATE( RecvdIfMatrix(i) % Cols )
        DEALLOCATE( RecvdIfMatrix(i) % GRows )
        DEALLOCATE( RecvdIfMatrix(i) % RowOwner )
     END IF
  END DO

  DEALLOCATE( OwnIfMatrix, RecvdIfMatrix )

END FUNCTION SplitMatrix


!********************************************************************
!********************************************************************
!
! Zero the splitted matrix (for new non-linear iteration)
!

!----------------------------------------------------------------------
SUBROUTINE ZeroSplittedMatrix( SplittedMatrix )
!----------------------------------------------------------------------
  USE Types
  IMPLICIT NONE
!----------------------------------------------------------------------
  TYPE (SplittedMatrixT), POINTER :: SplittedMatrix
!----------------------------------------------------------------------

  ! Local variables

  INTEGER :: i

  LOGICAL :: NeedMass

  !*******************************************************************

  NeedMass = ASSOCIATED( SplittedMatrix % InsideMatrix % MassValues )

  SplittedMatrix % InsideMatrix % Values = 0.0d0
  IF ( NeedMass ) &
     SplittedMatrix % InsideMatrix % MassValues = 0.0d0

  DO i = 1, ParEnv % PEs

     IF ( SplittedMatrix % IfMatrix(i) % NumberOfRows /= 0 ) THEN
        SplittedMatrix % IfMatrix(i) % Values = 0.0d0
        IF ( NeedMass ) &
           SplittedMatrix % IfMatrix(i) % MassValues = 0.0d0
     END IF

     IF ( SplittedMatrix % NbsIfMatrix(i) % NumberOfRows /= 0 ) THEN
        SplittedMatrix % NbsIfMatrix(i) % Values = 0.0d0
        IF ( NeedMass ) &
           SplittedMatrix % NbsIfMatrix(i) % MassValues = 0.0d0
     END IF

  END DO
!----------------------------------------------------------------------
END SUBROUTINE ZeroSplittedMatrix
!----------------------------------------------------------------------


!----------------------------------------------------------------------
  SUBROUTINE SParInitSolve( SourceMatrix,XVec,RHSVec,RVec,DOFs,Nodes )
!----------------------------------------------------------------------
! Initialize Parallel Solve
!----------------------------------------------------------------------

    TYPE (Matrix_t) :: SourceMatrix
    TYPE (Nodes_t), TARGET :: Nodes
    INTEGER :: DOFs
    REAL(KIND=dp), DIMENSION(:) :: XVec, RHSVec,RVec

!----------------------------------------------------------------------

    ! Local variables

    REAL(KIND=dp), POINTER :: TmpRHSVec(:)
    INTEGER :: i, j, k, l, grow, gcol
    INTEGER :: nodeind, ifind, dd, rowind
    TYPE (Matrix_t), POINTER :: CurrIf
    TYPE (GlueTableT), POINTER :: GT
    TYPE (SplittedMatrixT), POINTER :: SplittedMatrix

    LOGICAL :: NeedMass, found

!----------------------------------------------------------------------

    GlobalData     => SourceMatrix % ParMatrix
    ParEnv         =  GlobalData % ParEnv
    SplittedMatrix => Globaldata % SplittedMatrix

    GlobalData % DOFs  =  DOFs
    GlobalData % Nodes => Nodes

    CALL ZeroSplittedMatrix( SplittedMatrix )


    NeedMass = ASSOCIATED( SplittedMatrix % InsideMatrix % MassValues )
    !------------------------------------------------------------------
    !
    ! Copy the Matrix % Values into SplittedMatrix
    !
    !------------------------------------------------------------------

    GT => SplittedMatrix % GlueTable

    DO i = 1, SourceMatrix % NumberOfRows
       
       GRow = (SourceMatrix % INVPerm(i) + DOFs-1) / DOFs
       GRow = DOFs * Nodes % GlobalNodeNumber(GRow) - (DOFs-1-MOD(i-1,DOFs))

       DO j = SourceMatrix % Rows(i),SourceMatrix % Rows(i+1) - 1

          GCol = ( SourceMatrix % INVPerm( SourceMatrix % Cols(j)) + DOFs-1 ) / DOFs

          GCol = DOFs * Nodes % GlobalNodeNumber(GCol) - &
                   ( DOFs-1 - MOD(SourceMatrix % Cols(j)-1,DOFs)  )
          
found = .false.
          DO k = GT % Rows(i), GT % Rows(i+1) - 1
             IF ( SourceMatrix % Cols(j) == GT % Cols(k) ) THEN
found = .true.
                
                IF ( GT % Inds(k) > 0 ) THEN
                   SplittedMatrix % InsideMatrix % Values( GT % Inds(k) ) = &
                        SplittedMatrix % InsideMatrix % Values( &
                           GT % Inds(k) ) + SourceMatrix % Values(j)
                   IF ( NeedMass ) &
                      SplittedMatrix % InsideMatrix % MassValues( GT % Inds(k) ) = &
                           SplittedMatrix % InsideMatrix % MassValues( &
                              GT % Inds(k) ) + SourceMatrix % MassValues(j)
                   EXIT

                ELSE IF ( (GT % Inds(k) + ParEnv % PEs) >= 0 ) THEN

                   ifind = ABS(GT % Inds(k))
                   CurrIf => SplittedMatrix % IfMatrix(ifind)

                   RowInd = -1
                   IF ( CurrIf % NumberOfRows > 0 ) THEN
                      RowInd = SearchIAItem( CurrIf % NumberOfRows, CurrIf % GRows, GRow )
                   END IF

                   IF ( RowInd /= -1 ) THEN
                      DO l = CurrIf % Rows(rowind), CurrIf % Rows(rowind+1)-1

                         IF ( GCol == CurrIf % Cols(l) ) THEN
                            CurrIf % Values(l) = CurrIf % Values(l) + SourceMatrix % Values(j)
                            IF ( NeedMass ) &
                                CurrIf % MassValues(l) = CurrIf % MassValues(l) + &
                                     SourceMatrix % MassValues(j)
                            EXIT
                         END IF

                      END DO
                   END IF
                   EXIT

                ELSE IF ((GT % Inds(k) + (2*ParEnv % PEs)) >= 0) THEN

                   ifind = -ParEnv % PEs + ABS(GT % Inds(k))
                   CurrIf => SplittedMatrix % NbsIfMatrix(ifind)
                  
                   RowInd = -1
                   IF ( CurrIf % NumberOfRows > 0 ) THEN
                      RowInd = SearchIAItem( CurrIf % NumberOfRows, CurrIf % GRows, GRow )
                   END IF

                   IF ( RowInd /= -1 ) THEN
                      DO l = CurrIf % Rows(RowInd), CurrIf % Rows(RowInd+1)-1
                         IF ( GCol == CurrIf % Cols(l) ) THEN
                            CurrIf % Values(l) = CurrIf % Values(l) + SourceMatrix % Values(j)
                            IF ( NeedMass ) &
                               CurrIf % MassValues(l) = CurrIf % MassValues(l) + &
                                    SourceMatrix % MassValues(j)
                            EXIT
                         END IF
                      END DO
                   END IF
                   EXIT
                END IF
             END IF
          END DO
       END DO
    END DO

    CALL GlueFinalize( SplittedMatrix, Nodes, DOFs )
    !
    ! Initialize Right-Hand-Side:
    ! ---------------------------

    IF ( .NOT. ASSOCIATED( SplittedMatrix % TmpXVec ) ) THEN
       ALLOCATE( SplittedMatrix % InsideMatrix % RHS(  &
         SplittedMatrix % InsideMatrix % NumberOfRows ) )

       ALLOCATE( SplittedMatrix % TmpXVec( SplittedMatrix %  &
                  InsideMatrix % NumberOfRows ) )

       ALLOCATE( SplittedMatrix % TmpRVec( SplittedMatrix %  &
                  InsideMatrix % NumberOfRows ) )
    END IF

    !
    ! Exchange RHS with neighbours
    ! -------------------------------------------------------------
    TmpRHSVec => SplittedMatrix % InsideMatrix % RHS

    CALL ExchangeRHSIf( SourceMatrix, SplittedMatrix, &
            Nodes, DOFs, RHSVec, TmpRHSVec )

!   CALL SParUpdateRHS( SourceMatrix, RHSVec, TmpRHSVec )

    !
    ! Initialize temporary XVec and RVec for iterator. The
    ! originals contain also the items on interfaces.
    ! -------------------------------------------------------------

    CALL SParUpdateSolve( SourceMatrix, XVec, RVec )
    !
    ! Set up the preconditioner:
    ! --------------------------
    IF ( .NOT.ASSOCIATED( SplittedMatrix % InsideMatrix % ILUValues) ) THEN
       CALL CRS_SortMatrix( SplittedMatrix % InsideMatrix )
    END IF
!----------------------------------------------------------------------
  END SUBROUTINE SParInitSolve
!----------------------------------------------------------------------


!----------------------------------------------------------------------
  SUBROUTINE SParUpdateRHS( SourceMatrix, RHSVec, TmpRHSVec )
!----------------------------------------------------------------------
    TYPE (Matrix_t) :: SourceMatrix
    REAL(KIND=dp) :: RHSVec(:), TmpRHSVec(:)
!----------------------------------------------------------------------
    ! Local variables

    INTEGER, ALLOCATABLE :: VecEPerNB(:)
    TYPE(Nodes_t), POINTER :: Nodes
    INTEGER :: i, j, k, nbind, DOFs
    TYPE (SplittedMatrixT), POINTER :: SplittedMatrix

!----------------------------------------------------------------------

    ! Collect the result:
    ! -------------------
    SplittedMatrix => SourceMatrix % ParMatrix % SplittedMatrix

    DOFs  =  SourceMatrix % ParMatrix % DOFs
    Nodes => SourceMatrix % ParMatrix % Nodes

    ALLOCATE( VecEPerNB( ParEnv % PEs ) )

    VecEPerNB = 0
    DO i = 1, SourceMatrix % NumberOfRows
       k = (SourceMatrix % INVPerm(i) + DOFs-1) / DOFs
       IF ( SIZE(Nodes % NeighbourList(k) % Neighbours) > 1 ) THEN
          IF ( Nodes % NeighbourList(k) % Neighbours(1) == ParEnv % MyPE ) THEN
             DO j = 1, SIZE(Nodes % NeighbourList(k) % Neighbours)
               IF (Nodes % NeighbourList(k) % Neighbours(j)/=ParEnv % MyPE) THEN
                 nbind = Nodes % NeighbourList(k) % Neighbours(j) + 1
                 VecEPerNB(nbind) = VecEPerNB(nbind) + 1

                 SplittedMatrix % ResBuf(nbind) % ResVal(VecEPerNB(nbind)) = &
                      RHSVec(i)
                 SplittedMatrix % ResBuf(nbind) % ResInd(VecEPerNB(nbind)) = &
                   Nodes % GlobalNodeNumber(k)*DOFs - (DOFs-1-MOD( i-1, DOFs))
               END IF
             END DO
          END IF
       END IF
    END DO

    CALL ExchangeResult( SourceMatrix, SplittedMatrix, Nodes, RHSVec, DOFs ) 

    ! Clean the work space:
    !----------------------
    DEALLOCATE( VecEPerNB )
!----------------------------------------------------------------------
  END SUBROUTINE SParUpdateRHS
!----------------------------------------------------------------------


!----------------------------------------------------------------------
  SUBROUTINE SParUpdateSolve( SourceMatrix, x, r )
!----------------------------------------------------------------------
    REAL(KIND=dp) :: x(:),r(:)
    TYPE(Matrix_t) :: SourceMatrix
!----------------------------------------------------------------------
    TYPE(Nodes_t), POINTER :: Nodes
    INTEGER :: i,j,k, DOFs
    REAL(KIND=dp), POINTER :: TmpXVec(:),TmpRVec(:)
!----------------------------------------------------------------------
    Nodes   => SourceMatrix % ParMatrix % Nodes
    DOFs    =  SourceMatrix % ParMatrix % DOFs
    TmpXVec => SourceMatrix % ParMatrix % SplittedMatrix % TmpXVec
    TmpRVec => SourceMatrix % ParMatrix % SplittedMatrix % TmpRVec

    j = 0
    DO i = 1, SourceMatrix % NumberOfRows
       k = (SourceMatrix % INVPerm(i) + DOFs-1) / DOFs
       IF ( Nodes % NeighbourList(k) % Neighbours(1) == ParEnv % MyPE ) THEN
          j = j + 1
          TmpXVec(j) = x(i)
          TmpRVec(j) = r(i)
       END IF
    END DO
!----------------------------------------------------------------------
  END SUBROUTINE SParUpdateSolve
!----------------------------------------------------------------------


!----------------------------------------------------------------------
  SUBROUTINE SParUpdateResult( SourceMatrix, XVec, RVec, GlobalUpdate )
!----------------------------------------------------------------------
    TYPE (Matrix_t) :: SourceMatrix
    LOGICAL :: GlobalUpdate
    REAL(KIND=dp) :: XVec(:), RVec(:)
!----------------------------------------------------------------------
    ! Local variables

    REAL(KIND=dp), POINTER :: TmpXVec(:), TmpRVec(:)
    INTEGER, ALLOCATABLE :: VecEPerNB(:)
    TYPE(Nodes_t), POINTER :: Nodes
    INTEGER :: i, j, k, nbind, DOFs
    TYPE (SplittedMatrixT), POINTER :: SplittedMatrix

!----------------------------------------------------------------------

    ! Collect the result:
    ! -------------------
    SplittedMatrix => SourceMatrix % ParMatrix % SplittedMatrix

    DOFs  =  SourceMatrix % ParMatrix % DOFs
    Nodes => SourceMatrix % ParMatrix % Nodes

    TmpXVec => SplittedMatrix % TmpXVec
    TmpRVec => SplittedMatrix % TmpRVec

    ALLOCATE( VecEPerNB( ParEnv % PEs ) )

    j = 0
    DO i = 1, SourceMatrix % NumberOfRows
       k = (SourceMatrix % INVPerm(i) + DOFs-1) / DOFs
       IF ( Nodes % NeighbourList(k) % Neighbours(1) == ParEnv % MyPE ) THEN
          j = j + 1
          XVec(i) = TmpXVec(j)
          RVec(i) = TmpRVec(j)
       ELSE
          RVec(i) = SourceMatrix % RHS(i)
       END IF
    END DO

    IF ( .NOT. GlobalUpdate ) RETURN

    VecEPerNB = 0
    DO i = 1, SourceMatrix % NumberOfRows
       k = (SourceMatrix % INVPerm(i) + DOFs-1) / DOFs
       IF ( SIZE(Nodes % NeighbourList(k) % Neighbours) > 1 ) THEN
          IF ( Nodes % NeighbourList(k) % Neighbours(1) == ParEnv % MyPE ) THEN
             DO j = 1, SIZE(Nodes % NeighbourList(k) % Neighbours)
               IF (Nodes % NeighbourList(k) % Neighbours(j)/=ParEnv % MyPE) THEN
                 nbind = Nodes % NeighbourList(k) % Neighbours(j) + 1
                 VecEPerNB(nbind) = VecEPerNB(nbind) + 1

                 SplittedMatrix % ResBuf(nbind) % ResVal(VecEPerNB(nbind)) = &
                      XVec(i)
                 SplittedMatrix % ResBuf(nbind) % ResInd(VecEPerNB(nbind)) = &
                   Nodes % GlobalNodeNumber(k)*DOFs - (DOFs-1-MOD( i-1, DOFs))
               END IF
             END DO
          END IF
       END IF
    END DO

    CALL ExchangeResult( SourceMatrix, SplittedMatrix, Nodes, XVec, DOFs ) 

#if 0
    VecEPerNB = 0
    DO i = 1, SourceMatrix % NumberOfRows
       k = (SourceMatrix % INVPerm(i) + DOFs-1) / DOFs
       IF ( SIZE(Nodes % NeighbourList(k) % Neighbours) > 1 ) THEN
          IF ( Nodes % NeighbourList(k) % Neighbours(1) == ParEnv % MyPE ) THEN
             DO j = 1, SIZE(Nodes % NeighbourList(k) % Neighbours)
               IF (Nodes % NeighbourList(k) % Neighbours(j)/=ParEnv % MyPE) THEN
                 nbind = Nodes % NeighbourList(k) % Neighbours(j) + 1
                 VecEPerNB(nbind) = VecEPerNB(nbind) + 1

                 SplittedMatrix % ResBuf(nbind) % ResVal(VecEPerNB(nbind)) = &
                      RVec(i)
                 SplittedMatrix % ResBuf(nbind) % ResInd(VecEPerNB(nbind)) = &
                   Nodes % GlobalNodeNumber(k)*DOFs - (DOFs-1-MOD( i-1, DOFs))
               END IF
             END DO
          END IF
       END IF
     END DO

     CALL ExchangeResult( SourceMatrix, SplittedMatrix, Nodes, RVec, DOFs ) 
#endif
     !
     ! Clean the work space:
     !----------------------
     DEALLOCATE( VecEPerNB )
!----------------------------------------------------------------------
  END SUBROUTINE SParUpdateResult
!----------------------------------------------------------------------





!----------------------------------------------------------------------
!----------------------------------------------------------------------






  !********************************************************************
  !********************************************************************
  !
  ! Call the iterative solver
  !
  SUBROUTINE SParIterSolver( SourceMatrix, Nodes, DOFs, XVec, &
              RHSVec, Solver, SParMatrixDesc )

    TYPE (Matrix_t) :: SourceMatrix
    TYPE (Nodes_t) :: Nodes
    INTEGER :: DOFs
    REAL(KIND=dp), DIMENSION(:) :: XVec, RHSVec
    TYPE (Solver_t) :: Solver
    TYPE (SParIterSolverGlobalD_t), POINTER :: SParMatrixDesc

    ! Local variables

    TYPE (ErrInfoT) :: ErrInfo
    INTEGER :: i, j, grow,gcol
    TYPE (SplittedMatrixT), POINTER :: SplittedMatrix
    INTEGER :: k, l, nodeind, ifind, dd, rowind
    TYPE (Matrix_t), POINTER :: CurrIf
    TYPE (GlueTableT), POINTER :: GT

    LOGICAL :: NeedMass, found

    !******************************************************************

    GlobalData     => SParMatrixDesc
    ParEnv         =  GlobalData % ParEnv
    SplittedMatrix => SParMatrixDesc % SplittedMatrix

    CALL ZeroSplittedMatrix( SplittedMatrix )

    NeedMass = ASSOCIATED( SplittedMatrix % InsideMatrix % MassValues )

    !------------------------------------------------------------------
    !
    ! Copy the Matrix % Values into SplittedMatrix
    !
    !------------------------------------------------------------------

    GT => SplittedMatrix % GlueTable

    DO i = 1, SourceMatrix % NumberOfRows
       
       GRow = (SourceMatrix % INVPerm(i) + DOFs-1) / DOFs
       GRow = DOFs * Nodes % GlobalNodeNumber(GRow) - (DOFs-1-MOD(i-1,DOFs))

       DO j = SourceMatrix % Rows(i),SourceMatrix % Rows(i+1) - 1

          GCol = ( SourceMatrix % INVPerm( &
                   SourceMatrix % Cols(j)) + DOFs-1 ) / DOFs

          GCol = DOFs * Nodes % GlobalNodeNumber(GCol) - &
                   ( DOFs-1 - MOD(SourceMatrix % Cols(j)-1,DOFs)  )
          
found = .false.
          DO k = GT % Rows(i), GT % Rows(i+1) - 1
             IF ( SourceMatrix % Cols(j) == GT % Cols(k) ) THEN
                
found = .true.
                IF ( GT % Inds(k) > 0 ) THEN
                   SplittedMatrix % InsideMatrix % Values( GT % Inds(k) ) = &
                        SplittedMatrix % InsideMatrix % Values( &
                           GT % Inds(k) ) + SourceMatrix % Values(j)
                   IF ( NeedMass ) &
                      SplittedMatrix % InsideMatrix % MassValues( GT % Inds(k) ) = &
                           SplittedMatrix % InsideMatrix % MassValues( &
                              GT % Inds(k) ) + SourceMatrix % MassValues(j)
                   EXIT

                ELSE IF ( (GT % Inds(k) + ParEnv % PEs) >= 0 ) THEN

                   ifind = ABS(GT % Inds(k))
                   CurrIf => SplittedMatrix % IfMatrix(ifind)

                   RowInd = -1
                   IF ( CurrIf % NumberOfRows > 0 ) THEN
                      RowInd = SearchIAItem( CurrIf % NumberOfRows, &
                                    CurrIf % GRows, GRow )
                   END IF

                   IF ( RowInd /= -1 ) THEN
                      DO l = CurrIf % Rows(rowind), CurrIf % Rows(rowind+1)-1

                         IF ( GCol == CurrIf % Cols(l) ) THEN
                            CurrIf % Values(l) = CurrIf % Values(l) + &
                                 SourceMatrix % Values(j)
                            IF ( NeedMass ) &
                               CurrIf % MassValues(l) = CurrIf % MassValues(l) + &
                                    SourceMatrix % MassValues(j)
                            EXIT
                         END IF

                      END DO
                   END IF
                   EXIT

                ELSE IF ((GT % Inds(k) + (2*ParEnv % PEs)) >= 0) THEN

                   ifind = -ParEnv % PEs + ABS(GT % Inds(k))
                   CurrIf => SplittedMatrix % NbsIfMatrix(ifind)
                  
                   RowInd = -1
                   IF ( CurrIf % NumberOfRows > 0 ) THEN
                      RowInd = SearchIAItem( CurrIf % NumberOfRows, &
                                  CurrIf % GRows, GRow )
                   END IF

                   IF ( RowInd /= -1 ) THEN
                      DO l = CurrIf % Rows(RowInd), CurrIf % Rows(RowInd+1)-1
                         IF ( GCol == CurrIf % Cols(l) ) THEN
                            CurrIf % Values(l) = CurrIf % Values(l) + &
                                 SourceMatrix % Values(j)
                            IF ( NeedMass ) &
                               CurrIf % MassValues(l) = CurrIf % MassValues(l) + &
                                    SourceMatrix % MassValues(j)
                            EXIT
                         END IF
                      END DO
                   END IF
                   EXIT
                END IF
             END IF
          END DO
       END DO
    END DO

    CALL GlueFinalize( SplittedMatrix, Nodes, DOFs )

    !------------------------------------------------------------------
    !
    ! Call the actual solver routine (based on older design)
    !
    !------------------------------------------------------------------
    CALL Solve( SourceMatrix, SParMatrixDesc % SplittedMatrix, &
           Nodes, RHSVec, XVec, DOFs, Solver, Errinfo )

  END SUBROUTINE SParIterSolver



!*********************************************************************
!*********************************************************************
!
!
!
SUBROUTINE Solve( SourceMatrix, SplittedMatrix, Nodes, &
         RHSVec, XVec, DOFs, Solver, ErrInfo )

  TYPE (SplittedMatrixT), POINTER :: SplittedMatrix
  TYPE(Matrix_t) :: SourceMatrix
  TYPE (Nodes_t) :: Nodes
  INTEGER :: DOFs
  TYPE (Solver_t) :: Solver
  TYPE (ErrInfoT) :: ErrInfo
  REAL(KIND=dp), DIMENSION(:) :: RHSVec, XVec

  ! Local variables

  LOGICAL :: stat
  INTEGER :: i, j, k, vecdim, nbind, dof
  INTEGER, DIMENSION(:), ALLOCATABLE :: ipar, VecEPerNB
  REAL(KIND=dp), DIMENSION(:), ALLOCATABLE :: dpar
  REAL(KIND=dp), DIMENSION(:,:), POINTER :: Work
  REAL(KIND=dp), DIMENSION(:), ALLOCATABLE :: TmpXVec, TmpRHSVec

  REAL(KIND=dp) :: ILUT_TOL
  INTEGER :: ILUn
  CHARACTER(LEN=MAX_NAME_LEN) :: Preconditioner

  !*******************************************************************

  PIGpntr => GlobalData

  !----------------------------------------------------------------------
  !
  ! Initialize Right-Hand-Side
  !
  !----------------------------------------------------------------------

  ALLOCATE( TmpRHSVec( SplittedMatrix % InsideMatrix % NumberOfRows ) )

  CALL ExchangeRHSIf( SourceMatrix, SplittedMatrix, &
            Nodes, DOFs, RHSVec, TmpRHSVec )

  !----------------------------------------------------------------------
  !
  ! Initialize entries in HUTIter control array IPAR
  !
  !----------------------------------------------------------------------

  ALLOCATE( ipar( HUTI_IPAR_DFLTSIZE ) )
  ALLOCATE( dpar( HUTI_DPAR_DFLTSIZE ) )

  HUTI_NDIM = SplittedMatrix % InsideMatrix % NumberOfRows

  HUTI_MAXIT = ListGetInteger( Solver % Values, &
         'Linear System Max Iterations' )

  HUTI_TOLERANCE = ListGetConstReal( Solver % Values, &
       'Linear System Convergence Tolerance' )

  GlobalData % RelaxIters = ListGetInteger( Solver % Values, &
                 'Relax Iters', Stat )

  HUTI_INITIALX = HUTI_USERSUPPLIEDX
! IF ( ALL(XVec == 0) ) THEN
!    XVec = SQRT( SUM( RHSVec**2 ) )
! END IF

  IF ( ParEnv % MyPE == 0 ) THEN
     HUTI_DBUGLVL = ListGetInteger( Solver % Values, &
          'Linear System Residual Output', Stat )
  ELSE
     HUTI_DBUGLVL = 0
  END IF

  HUTI_STOPC = HUTI_TRESID_SCALED_BYB


  !----------------------------------------------------------------------
  !
  ! Allocate work space for HUTI
  !
  !----------------------------------------------------------------------
  vecdim = HUTI_BICGSTAB_WORKSIZE

  !----------------------------------------------------------------------
  !
  ! Allocate work space for HUTI (if needed)
  !
  !----------------------------------------------------------------------
  HUTI_WRKDIM = VecDim

  ALLOCATE( TmpXVec( SplittedMatrix % InsideMatrix % NumberOfRows ) )

  IF ( .NOT. ASSOCIATED( SplittedMatrix % Work ) ) THEN

     ALLOCATE( SplittedMatrix % Work( HUTI_NDIM, HUTI_WRKDIM ) )

  ELSE IF ( ( HUTI_NDIM /= SIZE(SplittedMatrix % Work,1) ) .OR. &
       ( HUTI_WRKDIM /= SIZE(SplittedMatrix % Work,2) ) ) THEN

     DEALLOCATE( SplittedMatrix % Work )
     ALLOCATE( SplittedMatrix % Work( HUTI_NDIM, HUTI_WRKDIM ) )

  END IF
  Work => SplittedMatrix % Work

  !----------------------------------------------------------------------
  !
  ! Initialize temporary xvec for iterator. The original XVec contains
  ! also the items on interfaces. Initialize also global pointer.
  !
  !----------------------------------------------------------------------

  j = 1
  DO i = 1, SourceMatrix % NumberOfRows
     k = (SourceMatrix % INVPerm(i) + DOFs-1) / DOFs
     IF ( Nodes % NeighbourList(k) % Neighbours(1) == ParEnv % MyPE ) THEN
	TmpXVec(j) = XVec(i)
	j = j + 1
     END IF
  END DO

  GlobalMatrix => SplittedMatrix % InsideMatrix
  GlobalData % SplittedMatrix => SplittedMatrix
 !----------------------------------------------------------------------
 !
 ! Set up the preconditioner
 !
 !----------------------------------------------------------------------

  IF ( .NOT.ASSOCIATED( SplittedMatrix % InsideMatrix % ILUValues) ) THEN
     DO i = 1, SplittedMatrix % InsideMatrix % NumberOfRows
        DO j = SplittedMatrix % InsideMatrix % Rows(i), &
             SplittedMatrix % InsideMatrix % Rows(i+1) - 1
           IF ( SplittedMatrix % InsideMatrix % Cols(j) == i ) THEN
              SplittedMatrix % InsideMatrix % Diag(i) = j
              EXIT
           END IF
        END DO
     END DO
  END IF

  Preconditioner = ListGetString( Solver % Values, &
      'Linear System Preconditioning',stat )

  IF ( Preconditioner(1:4) == 'ilut' ) THEN

    ILUT_TOL = ListGetConstReal( Solver % Values, &
        'Linear System ILUT Tolerance',stat )

    IF ( .NOT. SourceMatrix % Complex ) THEN
       stat = CRS_ILUT( SplittedMatrix % InsideMatrix, ILUT_TOL )
    ELSE
       stat = CRS_ComplexILUT( SplittedMatrix % InsideMatrix, ILUT_TOL )
    END IF

  ELSE IF ( Preconditioner(1:3) == 'ilu' ) THEN

    ILUn = ICHAR(Preconditioner(4:4)) - ICHAR('0')
    IF ( ILUn  < 0 .OR. ILUn > 9 ) ILUn = 0
    IF ( .NOT. SourceMatrix % Complex ) THEN
       stat = CRS_IncompleteLU( SplittedMatrix % InsideMatrix, ILUn)
    ELSE
       stat = CRS_ComplexIncompleteLU( SplittedMatrix % InsideMatrix, ILUn)
    END IF

  ELSE

    IF ( .NOT. SourceMatrix % Complex ) THEN
       stat = CRS_IncompleteLU( SplittedMatrix % InsideMatrix, 0 )
    ELSE
       stat = CRS_ComplexIncompleteLU( SplittedMatrix % InsideMatrix, 0 )
    END IF

  END IF

 !----------------------------------------------------------------------
 !
 ! Call the main iterator routine
 !
 !----------------------------------------------------------------------

  IF ( .NOT. SourceMatrix % Complex ) THEN
     CALL HUTI_DBICGSTAB_2SOLV( HUTI_NDIM, HUTI_WRKDIM, TmpXVec, &
        TmpRHSVec, ipar, dpar, Work, SParMatrixVector, &
           ParPrecondition, DPcond, SParDotProd, SParNorm, Dummy )
!          CRS_DiagPrecondition, DPcond, SParDotProd, SParNorm, Dummy )
!          CRS_LUPrecondition, DPcond, SParDotProd, SParNorm, Dummy )
  ELSE
     HUTI_NDIM = HUTI_NDIM / 2
     CALL HUTI_ZBICGSTAB_2SOLV( HUTI_NDIM, HUTI_WRKDIM, TmpXVec, &
        TmpRHSVec, ipar, dpar, Work, ParComplexMatrixVector, &
           ParComplexPrecondition, CPcond, &
              ParComplexDotProd, ParComplexNorm, Dummy )
!          CRS_ComplexLUPrecondition, CPcond, &
     HUTI_NDIM = HUTI_NDIM * 2
  END IF

  IF ( HUTI_INFO /= HUTI_CONVERGENCE ) THEN
     WRITE( Message, * ) 'Processor ',ParEnv % MyPE,' returned HUTI_INFO=', HUTI_INFO
     CALL Error( 'SParIter Solve', Message )
  END IF

  ErrInfo % HUTIStatus = HUTI_INFO
  !----------------------------------------------------------------------
  !
  ! Collect the result
  !
  !----------------------------------------------------------------------

  ALLOCATE( VecEPerNB( ParEnv % PEs ) )
  VecEPerNB = 0

  j = 1
  DO i = 1, SourceMatrix % NumberOfRows
     k = (SourceMatrix % INVPerm(i) + DOFs-1) / DOFs
     IF ( Nodes % NeighbourList(k) % Neighbours(1) == ParEnv % MyPE ) THEN
	XVec(i) = TmpXVec(j)
	j = j + 1
     END IF
  END DO

  DO i = 1, SourceMatrix % NumberOfRows
     k = (SourceMatrix % INVPerm(i) + DOFs-1) / DOFs
     IF ( SIZE(Nodes % NeighbourList(k) % Neighbours) > 1 ) THEN
        IF ( Nodes % NeighbourList(k) % Neighbours(1) == ParEnv % MyPE ) THEN
           DO j = 1, SIZE(Nodes % NeighbourList(k) % Neighbours)
              IF (Nodes % NeighbourList(k) % Neighbours(j)/=ParEnv % MyPE) THEN
                 nbind = Nodes % NeighbourList(k) % Neighbours(j) + 1
                 VecEPerNB(nbind) = VecEPerNB(nbind) + 1

                 SplittedMatrix % ResBuf(nbind) % ResVal(VecEPerNB(nbind)) = XVec(i)
                 SplittedMatrix % ResBuf(nbind) % ResInd(VecEPerNB(nbind)) = &
                   Nodes % GlobalNodeNumber(k)*DOFs - (DOFs-1 - MOD( i-1, DOFs))
              END IF
           END DO
        END IF
     END IF
  END DO

  CALL ExchangeResult( SourceMatrix, SplittedMatrix, Nodes, XVec, DOFs ) 
  !----------------------------------------------------------------------
  !
  ! Clean the work space
  !
  !----------------------------------------------------------------------

  DEALLOCATE( ipar, dpar, TmpXVec, TmpRHSVec, VecEPerNB )
!----------------------------------------------------------------------
END SUBROUTINE Solve
!----------------------------------------------------------------------


!----------------------------------------------------------------------
SUBROUTINE ParPrecondition( u,v,ipar )
!----------------------------------------------------------------------
    REAL(KIND=dp) :: u(*),v(*)
    INTEGER :: ipar(*)

    INTEGER :: i,j,k,n,iter,niters

    REAL(KIND=dp), POINTER :: Values(:)
    INTEGER, POINTER :: Rows(:),Cols(:)

    REAL(KIND=dp), ALLOCATABLE :: z(:), y(:)
    SAVE y,z,niters


    n = HUTI_NDIM
    niters = GlobalData % RelaxIters

    IF ( niters <= 0 ) THEN
       CALL CRS_LUPrecondition( u,v,ipar )
       RETURN
    END IF

    IF ( .NOT. ALLOCATED(z) .OR. SIZE(z) /= n ) THEN
       IF ( ALLOCATED(z) ) DEALLOCATE( z, y )

       ALLOCATE( z(n), y(n) )
    END IF

    Rows   => GlobalMatrix % Rows
    Cols   => GlobalMatrix % Cols
    Values => GlobalMatrix % Values

    u(1:n) = v(1:n)
    DO iter=1,niters

       z = 0
       CALL ParIfMatrixVector( u,z,ipar )
       z = v(1:n) - z
#if 0
       y = 0
       DO i=1,2
          CALL CRS_MatrixVectorMultiply( GlobalMatrix,y,u )
 
          y = y - (u(1:n) - z) / GlobalMatrix % Values( & 
                       GlobalMatrix % Diag(1:n) )
       END DO
       u(1:n) = y
#endif
       CALL CRS_LUPrecondition( u,z,ipar )
    END DO

!----------------------------------------------------------------------
END SUBROUTINE ParPrecondition
!----------------------------------------------------------------------


!----------------------------------------------------------------------
SUBROUTINE ParComplexPrecondition( u,v,ipar )
!----------------------------------------------------------------------
    COMPLEX(KIND=dp) :: u(*),v(*)
    INTEGER :: ipar(*)

    INTEGER :: i,j,iter,n
    INTEGER, POINTER :: Rows(:),Cols(:)

    COMPLEX(KIND=dp) :: A
    REAL(KIND=dp), POINTER :: Values(:)

    COMPLEX(KIND=dp), ALLOCATABLE :: z(:)
    SAVE z

    n = HUTI_NDIM

    IF ( .NOT. ALLOCATED(z) .OR. SIZE(z) /= n ) THEN
       IF ( ALLOCATED(z) ) DEALLOCATE( z )

       ALLOCATE( z(n) )
    END IF

    Rows   => GlobalMatrix % Rows
    Cols   => GlobalMatrix % Cols
    Values => GlobalMatrix % Values

    u(1:n) = v(1:n)
    DO iter=1,6
       z = 0
       CALL ParIfComplexMatrixVector( u,z,ipar )
       z = v(1:n) - z
       CALL CRS_ComplexLUPrecondition( u,z,ipar )
    END DO
!----------------------------------------------------------------------
END SUBROUTINE ParComplexPrecondition
!----------------------------------------------------------------------


!*********************************************************************
!*********************************************************************
!
! External Matrix - Vector operations (Parallel real, version)
!
! Multiply vector u with the global matrix,  return the result in v
! Called from HUTIter library
!

SUBROUTINE ParIfMatrixVector( u, v, ipar )

  IMPLICIT NONE

  ! Input parameters

  INTEGER, DIMENSION(*) :: ipar
  REAL(KIND=dp), DIMENSION(*) :: u, v

  ! Local parameters

  INTEGER :: i, j, k, l, colind
  TYPE( IfVecT), POINTER :: IfV
  TYPE( IfLColsT), POINTER :: IfL
  TYPE (Matrix_t), POINTER :: InsideMatrix, CurrIf

  INTEGER, POINTER :: Cols(:),Rows(:)
  REAL(KIND=dp), POINTER :: Vals(:)

  !*******************************************************************

  InsideMatrix => GlobalData % SplittedMatrix % InsideMatrix

  !----------------------------------------------------------------------
  !
  ! Compute the interface contribution for each neighbour
  !
  !----------------------------------------------------------------------

  DO i = 1, ParEnv % PEs
     CurrIf => GlobalData % SplittedMatrix % IfMatrix(i)
     IfV => GlobalData % SplittedMatrix % IfVecs(i)
     IfL => GlobalData % SplittedMatrix % IfLCols(i)

     IF ( CurrIf % NumberOfRows /= 0 ) THEN
	IfV % IfVec(1:CurrIf % NumberOfRows) = 0.0
	DO j = 1, CurrIf % NumberOfRows
	   DO k = CurrIf % Rows(j), CurrIf % Rows(j+1) - 1
              Colind = IfL % IfVec(k)
	      IfV % IfVec(j) = IfV % IfVec(j) + CurrIf % Values(k) * u(colind)
	   END DO
	END DO
     END IF
  END DO

  CALL Send_LocIf( GlobalData % SplittedMatrix )
  CALL Recv_LocIf( GlobalData % SplittedMatrix, HUTI_NDIM, v )
!----------------------------------------------------------------------
END SUBROUTINE ParIfMatrixVector
!----------------------------------------------------------------------

!*********************************************************************
!*********************************************************************
!
! External Matrix - Vector operations (Parallel real, version)
!
! Multiply vector u with the global matrix,  return the result in v
! Called from HUTIter library
!
!----------------------------------------------------------------------
  SUBROUTINE SParMatrixVector( u, v, ipar )
!----------------------------------------------------------------------

  IMPLICIT NONE

  ! Input parameters

  INTEGER, DIMENSION(*) :: ipar
  REAL(KIND=dp), DIMENSION(*) :: u, v

  ! Local parameters

  INTEGER :: i, j, k, l, n, colind
  TYPE( IfVecT), POINTER :: IfV
  TYPE( IfLColsT), POINTER :: IfL
  TYPE (Matrix_t), POINTER :: InsideMatrix, CurrIf

  INTEGER, POINTER :: Cols(:),Rows(:)
  REAL(KIND=dp), POINTER :: Vals(:)

  !*******************************************************************

  InsideMatrix => GlobalData % SplittedMatrix % InsideMatrix
  n = InsideMatrix % NumberOfRows

  !----------------------------------------------------------------------
  !
  ! Compute the interface contribution for each neighbour
  !
  !----------------------------------------------------------------------

  DO i = 1, ParEnv % PEs
     CurrIf => GlobalData % SplittedMatrix % IfMatrix(i)
     IfV => GlobalData % SplittedMatrix % IfVecs(i)
     IfL => GlobalData % SplittedMatrix % IfLCols(i)

     IF ( CurrIf % NumberOfRows /= 0 ) THEN
	IfV % IfVec(1:CurrIf % NumberOfRows) = 0.0
	DO j = 1, CurrIf % NumberOfRows
	   DO k = CurrIf % Rows(j), CurrIf % Rows(j+1) - 1
              Colind = IfL % IfVec(k)
	      IfV % IfVec(j) = IfV % IfVec(j) + CurrIf % Values(k) * u(colind)
	   END DO
	END DO
     END IF
  END DO

  CALL Send_LocIf( GlobalData % SplittedMatrix )

  !----------------------------------------------------------------------
  !
  ! Compute the local part
  !
  !----------------------------------------------------------------------

  v(1:n) = 0.0
  Rows => InsideMatrix % Rows
  Cols => InsideMatrix % Cols
  Vals => InsideMatrix % Values

#if !defined(SGI) && !defined(SGI64)
  DO i = 1, n
     DO j = Rows(i), Rows(i+1) - 1
        v(i) = v(i) + Vals(j) * u(Cols(j))
     END DO
  END DO

  CALL Recv_LocIf( GlobalData % SplittedMatrix, n, v )
#else
  CALL MV( n, SIZE(Cols), Rows,Cols, Vals, u,v )

  !----------------------------------------------------------------------
  !
  ! Receive interface parts of the vector and sum them to vector v
  !
  !----------------------------------------------------------------------
  CALL Recv_LocIf( GlobalData % SplittedMatrix, n, v )

CONTAINS 

!----------------------------------------------------------------------
  SUBROUTINE MV( n,m,Rows,Cols,Vals,u,v )
    INTEGER :: n,m,Rows(n+1),Cols(m)
    REAL(KIND=dp) :: Vals(m),u(n),v(n)

    DO i = 1, n
       DO j = Rows(i), Rows(i+1) - 1
          v(i) = v(i) + Vals(j) * u(Cols(j))
       END DO
    END DO
  END SUBROUTINE MV
!----------------------------------------------------------------------
#endif
!----------------------------------------------------------------------
END SUBROUTINE SParMatrixVector
!----------------------------------------------------------------------


!*********************************************************************
!*********************************************************************
!
! External Matrix - Vector operations (Parallel, complex version)
!
! Multiply vector u with the matrix in A_val return the result in v
! Called from HUTIter library
!

SUBROUTINE ParIfComplexMatrixVector( u, v, ipar )

  IMPLICIT NONE

  ! Input parameters

  INTEGER, DIMENSION(*) :: ipar
  COMPLEX(KIND=dp), DIMENSION(*) :: u, v


  ! Local parameters

  INTEGER :: i, j, k, l, colind
  TYPE (Matrix_t), POINTER :: InsideMatrix, CurrIf
  TYPE( IfVecT), POINTER :: IfV
  TYPE( IfLColsT), POINTER :: IfL

  COMPLEX(KIND=dp) :: A

  REAL(KIND=dp), POINTER :: Vals(:)
  INTEGER, POINTER :: Cols(:),Rows(:)
  REAL(KIND=dp), ALLOCATABLE :: buf(:)

  !*******************************************************************

  InsideMatrix => GlobalData % SplittedMatrix % InsideMatrix

  !----------------------------------------------------------------------
  !
  ! Compute the interface contribution for each neighbour
  !
  !----------------------------------------------------------------------

  DO i = 1, ParEnv % PEs
     CurrIf => GlobalData % SplittedMatrix % IfMatrix(i)

     IF ( CurrIf % NumberOfRows /= 0 ) THEN
        IfV => GlobalData % SplittedMatrix % IfVecs(i)
        IfL => GlobalData % SplittedMatrix % IfLCols(i)

	IfV % IfVec(1:CurrIf % NumberOfRows) = 0.0d0
	DO j = 1, CurrIf % NumberOfRows / 2
	   DO k = CurrIf % Rows(2*j-1), CurrIf % Rows(2*j)-1, 2
              ColInd = (IfL % IfVec(k) + 1) / 2
              A = DCMPLX( CurrIf % Values(k), -CurrIf % Values(k+1) )
              A = A * u(ColInd)
	      IfV % IfVec(2*j-1) = IfV % IfVec(2*j-1) + DREAL(A)
	      IfV % IfVec(2*j-0) = IfV % IfVec(2*j-0) + AIMAG(A)
	   END DO
	END DO
     END IF
  END DO

  CALL Send_LocIf( GlobalData % SplittedMatrix )

  ALLOCATE( buf( 2*HUTI_NDIM ) )
  buf = 0.0d0
  CALL Recv_LocIf( GlobalData % SplittedMatrix, 2*HUTI_NDIM, buf )

  DO i=1,HUTI_NDIM
     v(i) = v(i) + DCMPLX( buf(2*i-1), buf(2*i) )
  END DO
  DEALLOCATE( buf )

END SUBROUTINE ParIfComplexMatrixVector



!*********************************************************************
!*********************************************************************
!
! External Matrix - Vector operations (Parallel, complex version)
!
! Multiply vector u with the matrix in A_val return the result in v
! Called from HUTIter library
!

SUBROUTINE ParComplexMatrixVector( u, v, ipar )

  IMPLICIT NONE

  ! Input parameters

  INTEGER, DIMENSION(*) :: ipar
  COMPLEX(KIND=dp), DIMENSION(*) :: u, v


  ! Local parameters

  INTEGER :: i, j, k, l, colind
  TYPE (Matrix_t), POINTER :: InsideMatrix, CurrIf
  TYPE( IfVecT), POINTER :: IfV
  TYPE( IfLColsT), POINTER :: IfL

  COMPLEX(KIND=dp) :: A

  REAL(KIND=dp), POINTER :: Vals(:)
  INTEGER, POINTER :: Cols(:),Rows(:)
  REAL(KIND=dp), ALLOCATABLE :: buf(:)

  !*******************************************************************

  InsideMatrix => GlobalData % SplittedMatrix % InsideMatrix

  !----------------------------------------------------------------------
  !
  ! Compute the interface contribution for each neighbour
  !
  !----------------------------------------------------------------------

  DO i = 1, ParEnv % PEs
     CurrIf => GlobalData % SplittedMatrix % IfMatrix(i)

     IF ( CurrIf % NumberOfRows /= 0 ) THEN
        IfV => GlobalData % SplittedMatrix % IfVecs(i)
        IfL => GlobalData % SplittedMatrix % IfLCols(i)

	IfV % IfVec(1:CurrIf % NumberOfRows) = 0.0d0
	DO j = 1, CurrIf % NumberOfRows / 2
	   DO k = CurrIf % Rows(2*j-1), CurrIf % Rows(2*j)-1, 2
              ColInd = (IfL % IfVec(k) + 1) / 2
              A = DCMPLX( CurrIf % Values(k), -CurrIf % Values(k+1) )
              A = A * u(ColInd)
	      IfV % IfVec(2*j-1) = IfV % IfVec(2*j-1) + DREAL(A)
	      IfV % IfVec(2*j-0) = IfV % IfVec(2*j-0) + AIMAG(A)
	   END DO
	END DO
     END IF
  END DO

  CALL Send_LocIf( GlobalData % SplittedMatrix )

  !----------------------------------------------------------------------
  !
  ! Compute the local part
  !
  !----------------------------------------------------------------------

  v(1:HUTI_NDIM) = 0.0
  Rows => InsideMatrix % Rows
  Cols => InsideMatrix % Cols
  Vals => InsideMatrix % Values

#ifndef SGI
  DO i = 1, HUTI_NDIM
     DO j = Rows(2*i-1), Rows(2*i)-1, 2
        A = DCMPLX( Vals(j), -Vals(j+1) )
        v(i) = v(i) + A * u(Cols(j+1)/2)
     END DO
  END DO
#else
  CALL MV( HUTI_NDIM, SIZE(Cols), Rows,Cols, Vals, u,v )
#endif

  !----------------------------------------------------------------------
  !
  ! Receive interface parts of the vector and sum them to vector v
  !
  !----------------------------------------------------------------------
  ALLOCATE( buf( 2*HUTI_NDIM ) )
  buf = 0.0d0
  CALL Recv_LocIf( GlobalData % SplittedMatrix, 2*HUTI_NDIM, buf )

  DO i=1,HUTI_NDIM
     v(i) = v(i) + DCMPLX( buf(2*i-1), buf(2*i) )
  END DO
  DEALLOCATE( buf )

CONTAINS 

  SUBROUTINE MV( n,m,Rows,Cols,Vals,u,v )
    INTEGER :: n,m
    INTEGER :: Rows(2*n+1),Cols(m)
    REAL(KIND=dp) :: Vals(m)
    COMPLEX(KIND=dp) :: A,u(n),v(n)

    DO i = 1, HUTI_NDIM
       DO j = Rows(2*i-1), Rows(2*i)-1, 2
          A = DCMPLX( Vals(j), -Vals(j+1) )
          v(i) = v(i) + A * u(Cols(j+1)/2)
       END DO
    END DO
  END SUBROUTINE MV

END SUBROUTINE ParComplexMatrixVector




!*********************************************************************
!*********************************************************************
!
! This routine is used to count the nodes which have connections to
! neighbours the count of connections for neighbour. Then this information
! is used to allocate some communication buffers.
!
SUBROUTINE CountNeighbourConns( SourceMatrix, SplittedMatrix, Nodes, DOFs )

  USE Types
  IMPLICIT NONE

  TYPE (SplittedMatrixT) :: SplittedMatrix
  TYPE (Nodes_t) :: Nodes
  INTEGER :: DOFs
  TYPE (Matrix_t) :: SourceMatrix

  ! Local variables

  INTEGER :: i, j, k
  INTEGER, DIMENSION(:), ALLOCATABLE :: ResEPerNB, RHSEPerNB

  !*******************************************************************

  IF ( .NOT. ASSOCIATED( SplittedMatrix % ResBuf ) ) THEN
     ALLOCATE( SplittedMatrix % ResBuf( ParEnv % PEs ) )
  END IF
  IF ( .NOT. ASSOCIATED( SplittedMatrix % RHS ) ) THEN
     ALLOCATE( SplittedMatrix % RHS( ParEnv % PEs ) )
  END IF

  !----------------------------------------------------------------------
  !
  ! Count the nodes per neighbour which are shared between neighbours
  !
  !----------------------------------------------------------------------

  ALLOCATE( ResEPerNB( ParEnv % PEs ) )
  ALLOCATE( RHSEPerNB( ParEnv % PEs ) )
  ResEPerNB = 0; RHSEPerNB = 0

  DO i = DOFs, SourceMatrix % NumberOfRows, DOFs
     k =  (SourceMatrix % INVPerm(i) + DOFs-1) / DOFs

     IF ( Nodes % Interface(k) ) THEN
        IF ( Nodes % NeighbourList(k) % Neighbours(1) == ParEnv % MyPE ) THEN
           DO j = 1, SIZE( Nodes % NeighbourList(k) % Neighbours )
  	     IF ( Nodes % NeighbourList(k) % Neighbours(j)/=ParEnv % MyPE ) THEN
	        ResEPerNB(Nodes % NeighbourList(k) % Neighbours(j)+1) = &
	        ResEPerNB(Nodes % NeighbourList(k) % Neighbours(j)+1) + 1
	     END IF
  	  END DO
        ELSE
          RHSEPerNB(Nodes % NeighbourList(k) % Neighbours(1)+1) = &
             RHSEPerNB(Nodes % NeighbourList(k) % Neighbours(1)+1) + 1
        END IF
     END IF
  END DO

  !----------------------------------------------------------------------
  !
  ! Allocate some buffers for communication
  !
  !----------------------------------------------------------------------

  RHSEperNB = RHSEperNB * DOFs
  ResEPerNB = ResEPerNB * DOFs

  DO i = 1, ParEnv % PEs
     NULLIFY( SplittedMatrix % RHS(i) % RHSVec )
     NULLIFY( SplittedMatrix % RHS(i) % RHSInd )
     IF ( RHSEPerNB(i) /= 0 ) THEN
	ALLOCATE( SplittedMatrix % RHS(i) % RHSVec( RHSEperNB(i) ) )
	ALLOCATE( SplittedMatrix % RHS(i) % RHSind( RHSEperNB(i) ) )
     END IF

     NULLIFY( SplittedMatrix % ResBuf(i) % ResVal )
     NULLIFY( SplittedMatrix % ResBuf(i) % ResInd )
     IF ( ResEPerNB(i) /= 0 ) THEN
	ALLOCATE( SplittedMatrix % ResBuf(i) % ResVal( ResEPerNB(i) ) )
	ALLOCATE( SplittedMatrix % ResBuf(i) % ResInd( ResEPerNB(i) ) )
     END IF

  END DO

  DEALLOCATE( ResEPerNB, RHSEPerNB )
END SUBROUTINE CountNeighbourConns


!*********************************************************************
!*********************************************************************
!
! This subroutine combines indices of two matrices in CRS format.
! Row and column indices are assumed to be in sorted order.
!

SUBROUTINE CombineCRSMatIndices ( SMat1, SMat2, DMat )

  USE Types
  IMPLICIT NONE

  TYPE (Matrix_t), TARGET :: SMat1, SMat2, DMat
  TYPE (Matrix_t), POINTER :: SSMat1, SSMat2
! External routines

! EXTERNAL SearchIAItem
! INTEGER :: SearchIAItem

  ! Local variables

  INTEGER :: i, j, k, i1, i2, j1, j2, ind, ind1, ind2, DRows, DCols, row, col

  LOGICAL, ALLOCATABLE :: done(:)

  !*******************************************************************

  IF ( SMat1 % NumberOfRows == 0 .AND. SMat2 % NumberOfRows == 0 ) THEN

     RETURN

  ELSE IF ( SMat1 % NumberOfRows == 0 ) THEN

     ALLOCATE( DMat % Rows(  SMat2 % NumberOfRows + 1) )
     ALLOCATE( DMat % GRows( SMat2 % NumberOfRows ) )
     ALLOCATE( DMat % RowOwner( SMat2 % NumberOfRows ) )
     ALLOCATE( DMat % Cols( SMat2 % Rows(SMat2 % NumberOfRows + 1)-1 ) )

     DMat % NumberOfRows = SMat2 % NumberOfRows
     DMat % Rows = SMat2 % Rows(1:SMat2 % NumberOfRows+1)
     DMat % GRows = SMat2 % GRows(1:SMat2 % NumberOfRows)
     DMat % Cols = SMat2 % Cols(1:SIZE(DMat % Cols))
     DMat % RowOwner = SMat2 % RowOwner(1:SMat2 % NumberOfRows)

     RETURN

  ELSE IF ( SMat2 % NumberOfRows == 0 ) THEN

     ALLOCATE( DMat % Rows( SMat1 % NumberOfRows + 1) )
     ALLOCATE( DMat % GRows( SMat1 % NumberOfRows ) )
     ALLOCATE( DMat % RowOwner( SMat1 % NumberOfRows ) )
     ALLOCATE( DMat % Cols( SMat1 % Rows(SMat1 % NumberOfRows + 1)-1 ) )

     DMat % NumberOfRows = SMat1 % NumberOfRows
     DMat % Rows = SMat1 % Rows(1:SMat1 % NumberOfRows+1)
     DMat % GRows = SMat1 % GRows(1:SMat1 % NumberOfRows)
     DMat % Cols = SMat1 % Cols(1:SIZE(DMat % Cols))
     DMat % RowOwner = SMat1 % RowOwner(1:SMat1 % NumberOfRows)
     RETURN

  END IF
	
  !----------------------------------------------------------------------
  !
  ! First we have to compute the strorage allocations
  !
  !----------------------------------------------------------------------

  SMat1 % Ordered = .FALSE.
  SMat2 % Ordered = .FALSE.
  SSMat1 => SMat1
  SSMat2 => SMat2
  CALL CRS_SortMatrix( SSMat1 )
  CALL CRS_SortMatrix( SSMat2 )

  DRows = SMat2 % NumberOfRows; DCols = SMat2 % Rows(DRows + 1)

  DO i = 1, SMat1 % NumberOfRows
     ind1 = SearchIAItem( SMat2 % NumberOfRows, &
          SMat2 % GRows, SMat1 % GRows(i) )

     IF ( Ind1 /= -1 ) THEN
	DO j = SMat1 % Rows(i), SMat1 % Rows(i+1) - 1
	   ind2 = SearchIAItem( SMat2 % Rows(ind1+1) - SMat2 % Rows(ind1), &
		SMat2 % Cols(Smat2 % Rows(ind1):), SMat1 % Cols(j) )
	   IF ( ind2 == -1 ) THEN
	      DCols = DCols + 1
	   END IF
	END DO

     ELSE
	DRows = DRows + 1
	DCols = DCols + ( SMat1 % Rows(i+1) - SMat1 % Rows(i) )
     END IF
  END DO

  DMat % NumberOfRows = DRows
  DMat % Ordered = .TRUE.
  ALLOCATE( DMat % Rows( DRows + 1) )
  ALLOCATE( DMat % GRows( DRows ) )
  ALLOCATE( DMat % Cols( DCols ) )
  ALLOCATE( DMat % RowOwner( DRows ) )

  !----------------------------------------------------------------------
  !
  ! Then we combine the index structures of the two CRS matrices
  !
  !----------------------------------------------------------------------

  row = 1; col = 1; i1 = 1; i2 = 1
  ALLOCATE( Done( Smat2 % NumberOfRows ) )
  done = .FALSE.

  DO WHILE ( i1 <= SMat1 % NumberOfRows .OR. &
             i2 <= SMat2 % NumberOfRows )

     ind = -1
     IF ( i1 <= SMat1 % NumberOfRows ) THEN
        ind = SearchIAItem( SMat2 % NumberOfRows, &
          SMat2 % GRows, SMat1 % GRows(i1) )
     END IF

     IF ( i1 > SMat1 % NumberOfRows ) THEN

        DO i=1,Smat2 % NumberOfRows
           IF ( .NOT.done(i) ) THEN
              DMat % Rows(row) = Col
              DMat % GRows(row)    = SMat2 % GRows(i)
              DMat % RowOwner(row) = SMat2 % RowOwner(i)
              Row = Row + 1
              DO k = SMat2 % Rows(i), SMat2 % Rows(i+1) - 1
                 DMat % Cols(col) = SMat2 % Cols(k)
                 Col = Col + 1
              END DO
              i2 = i2 + 1
           END IF
        END DO

     ELSE IF ( i2 > SMat2 % NumberOfRows .OR. Ind == -1 ) THEN

	DMat % Rows(Row)     = Col
	DMat % GRows(Row)    = SMat1 % GRows(i1)
	DMat % RowOwner(Row) = SMat1 % RowOwner(i1)
	Row = Row + 1
	DO k = SMat1 % Rows(i1), SMat1 % Rows(i1+1) - 1
	   DMat % Cols(Col) = SMat1 % Cols(k)
	   Col = Col + 1
	END DO
	i1 = i1 + 1

     ELSE IF ( Ind /= -1 ) then
	      
	DMat % Rows(Row)  = Col
	DMat % GRows(Row) = SMat1 % GRows(i1)
	DMat % RowOwner(Row) = SMat1 % RowOwner(i1)
	Row = Row + 1
	j1 = SMat1 % Rows(i1)
        j2 = SMat2 % Rows(Ind)

	DO WHILE ( j1 < SMat1 % Rows(i1+1) .OR. &
	           j2 < SMat2 % Rows(Ind+1) )

	   IF ( (j1 <  SMat1 % Rows(i1+1) .AND. &
	 	 j2 >= SMat2 % Rows(Ind+1)) &
		.OR. (SMat1 % Cols(j1) < SMat2 % Cols(j2) &
                .AND. j1 < SMat1 % Rows(i1+1) ) ) THEN

              DMat % Cols(col) = SMat1 % Cols(j1)
	      col = col + 1
	      j1 = j1 + 1
	
	   ELSE IF ( (j1 >= SMat1 % Rows(i1+1) .AND. &
	       	      j2 <  SMat2 % Rows(Ind+1)) &
		.OR. (SMat2 % Cols(j2) < SMat1 % Cols(j1)  &
                .AND. j2 < SMat2 % Rows(Ind+1) ) ) THEN
              
              DMat % Cols(col) = SMat2 % Cols(j2)
	      col = col + 1
	      j2 = j2 + 1
	
	   ELSE IF ( SMat1 % Cols(j1) == SMat2 % Cols(j2) ) THEN

	      DMat % Cols(col) = SMat1 % Cols(j1)
	      col = col + 1
	      j1 = j1 + 1; j2 = j2 + 1
              
	   END IF
	END DO

        Done(Ind) = .TRUE.
	i1 = i1 + 1; i2 = i2 + 1
     END IF

  END DO
  DMat % Rows(Row) = Col

  DEALLOCATE( Done )

END SUBROUTINE CombineCRSMatIndices


!*********************************************************************
!*********************************************************************
!
! Update all necessary global structures after the local matrix has
! been built.
!

SUBROUTINE GlueFinalize( SplittedMatrix, Nodes, DOFs )
  USE Types
  IMPLICIT NONE

  TYPE (Nodes_t) :: Nodes
  INTEGER :: DOFs
  TYPE (SplittedMatrixT) :: SplittedMatrix

  ! External routines

! EXTERNAL SearchIAItem
! INTEGER :: SearchIAItem

  ! Local variables

  TYPE (Matrix_t), POINTER :: CurrIf, InsideMatrix
  INTEGER :: i, j, k, l, RowInd, Rows, ColInd
  TYPE (Matrix_t), DIMENSION(:), ALLOCATABLE :: RecvdIfMatrix

  LOGICAL :: Found, NeedMass
  TYPE(GlueTableT), POINTER :: GT

  !*******************************************************************

  !----------------------------------------------------------------------
  !
  ! Exchange interface block values stored in GlueLocalMatrix routine
  !
  !----------------------------------------------------------------------
  GT => SplittedMatrix % GlueTable

  InsideMatrix => SplittedMatrix % InsideMatrix
  NeedMass = ASSOCIATED( InsideMatrix % MassValues )

  ALLOCATE( RecvdIfMatrix( ParEnv % PEs ) )
  RecvdIfMatrix(:) % NumberOfRows = 0
  CALL ExchangeIfValues( SplittedMatrix % NbsIfMatrix, RecvdIfMatrix, NeedMass )

  !----------------------------------------------------------------------
  !
  ! Add received interface block values into our own interface blocks or
  ! into InsideMatrix.
  !
  !----------------------------------------------------------------------

  DO i = 1, ParEnv % PEs
     IF ( RecvdIfMatrix(i) % NumberOfRows /= 0 ) THEN

	CurrIf => SplittedMatrix % IfMatrix(i)
	DO j = 1, RecvdIfMatrix(i) % NumberOfRows

	   RowInd = SearchIAItem( CurrIf % NumberOfRows, &
                CurrIf % GRows, RecvdIfMatrix(i) % GRows(j) )

	   IF ( RowInd /= -1 ) THEN
	      ! Value to be added to IfMatrix

	      DO  k=RecvdIfMatrix(i) % Rows(j),RecvdIfMatrix(i) % Rows(j+1)-1

		 DO l = CurrIf % Rows(RowInd), CurrIf % Rows(RowInd+1)-1
		    IF ( RecvdIfMatrix(i) % Cols(k) == CurrIf % Cols(l) ) THEN
		       CurrIf % Values(l) = CurrIf % Values(l) + &
                             RecvdIfMatrix(i) % Values(k)
                       IF ( NeedMass ) &
                          CurrIf % MassValues(l) = CurrIf % MassValues(l) + &
                                 RecvdIfMatrix(i) % MassValues(k)
		       EXIT
		    END IF
		 END DO
	      END DO

           ELSE
  	      ! Value to be added to InsideMatrix

              RowInd = SearchIAItem( InsideMatrix % NumberOfRows, &
                  InsideMatrix % GRows, RecvdIfMatrix(i) % GRows(j), &
                      InsideMatrix % Gorder )

	      IF ( RowInd > 0 ) THEN
	         DO k = RecvdIfMatrix(i) % Rows(j),  &
                         RecvdIfMatrix(i) % Rows(j+1) - 1

                    Found = .FALSE.
                    ColInd = SearchIAItem( InsideMatrix % NumberOfRows, &
                         InsideMatrix % GRows, RecvdIfMatrix(i) % Cols(k), &
                            InsideMatrix % Gorder )

                    DO l = InsideMatrix % Rows(RowInd), InsideMatrix % Rows(RowInd + 1) - 1
 		       IF ( ColInd == InsideMatrix % Cols(l) ) THEN
 		          InsideMatrix % Values(l) = InsideMatrix % Values(l) + &
                                   RecvdIfMatrix(i) % Values(k)
                          IF ( NeedMass ) &
                             InsideMatrix % MassValues(l) = InsideMatrix % MassValues(l) + &
                                      RecvdIfMatrix(i) % MassValues(k)
                          Found = .TRUE.
 		          EXIT
 		       END IF
                    END DO

                    IF ( .NOT. Found ) THEN
                       PRINT*,ParEnv % MyPE,  'GlueFinalize: This should not happen 0'
                       PRINT*,ParEnv % MyPE, i-1, RecvdIfMatrix(i) % GRows(j), &
                                   RecvdIfMatrix(i) % Cols(k)
                    END IF
	         END DO
              ELSE
                 PRINT*,ParEnv % MyPE, 'GlueFinalize: This should not happen 1', RowInd
              END IF
	   END IF
	END DO
     END IF
  END DO

  DO i=1,ParEnv % PEs
     IF ( RecvdIfMatrix(i) % NumberOfRows > 0 ) THEN
        DEALLOCATE( RecvdIfMatrix(i) % Rows )
        DEALLOCATE( RecvdIfMatrix(i) % Cols )
        DEALLOCATE( RecvdIfMatrix(i) % GRows )
        DEALLOCATE( RecvdIfMatrix(i) % Values )
        IF ( ASSOCIATED( RecvdIfMatrix(i) % MassValues ) ) DEALLOCATE( RecvdIfMatrix(i) % MassValues )
     END IF
  END DO

  DEALLOCATE( RecvdIfMatrix )

END SUBROUTINE GlueFinalize

!*********************************************************************
!*********************************************************************
!
! Compress the given interface matrix deleting the inside connections.
!
! MODIFIES THE STRUCTURE OF INPUT MATRIX RecvdIfMatrix !!
!
SUBROUTINE ClearInsideC( SourceMatrix, InsideMatrix, &
            RecvdIfMatrix, Nodes, DOFs )

  USE Types
  IMPLICIT NONE

  ! Parameters

  TYPE (Matrix_t), DIMENSION(:) :: RecvdIfMatrix
  TYPE (Matrix_t) :: SourceMatrix, InsideMatrix
  TYPE (Nodes_t) :: Nodes
  INTEGER :: DOFs

  ! External routines

! EXTERNAL SearchIAItem
! INTEGER :: SearchIAItem

  ! Local variables

  INTEGER :: NewRow, NewCol,old_nv,nc
  INTEGER :: p,i,j,k,l,RowInd,ColInd,GCol
  
  !*********************************************************************
  !
  ! Compression of the matrix is done in place and lengths are
  ! stored in New* variables
  !
  DO p = 1, ParEnv % PEs

     IF ( RecvdIfMatrix(p) % NumberOfRows <= 0 ) CYCLE

     NewRow = 1; NewCol = 1; old_nv = 1
     DO i = 1, RecvdIfMatrix(p) % NumberOfRows

        NC = 0
        RowInd = SearchIAItem( InsideMatrix % NumberOfRows,  &
          InsideMatrix % GRows, RecvdIfMatrix(p) % GRows(i), &
            InsideMatrix % Gorder )

        IF ( RowInd /= -1 ) THEN
           DO j = RecvdIfMatrix(p) % Rows(i),RecvdIfMatrix(p) % Rows(i+1) - 1

              GCol = ( RecvdIfMatrix(p) % Cols(j) + DOFs-1 ) / DOFs
              GCol = DOFs * SearchNode( Nodes,  GCol ) - &
                 ( DOFs-1 - MOD(RecvdIfMatrix(p) % Cols(j)-1,DOFs) )

              GCol = SourceMatrix % Perm( Gcol )

              ColInd = -1
              DO k = InsideMatrix % Rows(RowInd), &
                     InsideMatrix % Rows(RowInd+1) - 1
                  IF ( GCol == InsideMatrix % Cols(k) ) THEN
                     ColInd = GCol
                     EXIT
                  END IF
              END DO

              IF ( ColInd == -1 ) THEN
                 RecvdIfMatrix(p) % Cols(NewCol) = RecvdIfMatrix(p) % Cols(j)
                 NewCol = NewCol + 1
                 NC = 1
              END IF
	   END DO

        ELSE

           DO j = RecvdIfMatrix(p) % Rows(i), RecvdIfMatrix(p) % Rows(i+1)-1
              RecvdIfMatrix(p) % Cols(NewCol) = RecvdIfMatrix(p) % Cols(j)
              NewCol = NewCol + 1
              NC = 1
           END DO

        END IF

        IF ( NC /= 0 ) THEN
           RecvdIfMatrix(p) % GRows(NewRow)    = RecvdIfMatrix(p) % GRows(i)
           RecvdIfMatrix(p) % RowOwner(NewRow) = RecvdIfMatrix(p) % RowOwner(i)
           RecvdIfMatrix(p) % Rows(NewRow)  = old_nv
           NewRow = NewRow + 1
        END IF
        old_nv = NewCol
	   
     END DO
     RecvdIfMatrix(p) % Rows(NewRow) = NewCol
     RecvdIfMatrix(p) % NumberOfRows  = NewRow - 1
  END DO

END SUBROUTINE ClearInsideC

!*********************************************************************
!*********************************************************************
!
! Convert the original local DoF numbering to a compressed one to
! enable direct use of column indices in matrix operations.
!

SUBROUTINE RenumberDOFs( SourceMatrix, SplittedMatrix, Nodes, DOFs )

  USE Types

  IMPLICIT NONE

  TYPE (SplittedMatrixT) :: SplittedMatrix
  TYPE (Nodes_t) :: Nodes
  INTEGER :: DOFs
  TYPE( Matrix_t) :: SourceMatrix

  ! Local variables

  INTEGER, DIMENSION(:), ALLOCATABLE :: RevDofList
  INTEGER :: i, j, k, Inside
  TYPE (Matrix_t), POINTER :: InsideMatrix

  !*******************************************************************

  ! Construct a list to convert original DOF (Degrees of Freedom)
  ! numbering to truncated one (for InsideMatrix).

  ALLOCATE( RevDofList( SourceMatrix % NumberOfRows ) )

  Inside = 0
  DO i = 1, SourceMatrix % NumberOfRows
     k = (SourceMatrix % INVPerm(i) + DOFs-1) / DOFs
     IF ( Nodes % NeighbourList(k) % Neighbours(1) == ParEnv % MyPE ) THEN
	Inside = Inside + 1
	RevDofList(i) = Inside
     ELSE
	RevDofList(i) = -1
     END IF
  END DO

  ! Scan the InsideMatrix and change the numbering

  InsideMatrix => SplittedMatrix % InsideMatrix
  DO i = 1, InsideMatrix % NumberOfRows
     DO j = InsideMatrix % Rows(i), InsideMatrix % Rows(i+1)-1
	InsideMatrix % Cols(j) = RevDofList( InsideMatrix % Cols(j) )
     END DO
  END DO

  DEALLOCATE( RevDofList )

END SUBROUTINE RenumberDOFs
!********************************************************************
! End
!********************************************************************

END MODULE SParIterSolve
