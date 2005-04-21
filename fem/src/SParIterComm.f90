!*********************************************************************
!
! File: elmer_mpi_comm.f90
! Software: ELMER
! Purpose: These routines are for parallel version of ELMER solver.
!          Subroutines for MPI-communication
!
! Author: Jouni Malinen, Juha Ruokolainen 
!
! $Id: SParIterComm.f90,v 1.9 2005/01/03 07:52:06 jpr Exp $
!
!*********************************************************************

#include "huti_fdefs.h"

MODULE SParIterComm

  USE Types
  USE SParIterGlobals

  IMPLICIT NONE

  INCLUDE "mpif.h"

CONTAINS

!-----------------------------------------------------------------
  SUBROUTINE CheckBuffer( n )
!-----------------------------------------------------------------
     INTEGER :: n, i, ierr
     INTEGER*1, ALLOCATABLE :: SendBuffer(:)

     LOGICAL :: isfine

     SAVE SendBuffer

     isfine = ALLOCATED(SendBuffer)
     IF ( isfine ) isfine = n <= SIZE(SendBuffer)
     IF ( isfine ) RETURN

     IF ( ALLOCATED(SendBuffer) ) THEN
        i = SIZE( SendBuffer )
        CALL MPI_BUFFER_DETACH( SendBuffer, i, ierr )
        DEALLOCATE( SendBuffer )
     END IF
     ALLOCATE( SendBuffer( n ) )
     CALL MPI_BUFFER_ATTACH( SendBuffer, n, ierr )
!-----------------------------------------------------------------
  END SUBROUTINE CheckBuffer
!-----------------------------------------------------------------


  !********************************************************************
  !********************************************************************
  !
  ! Initialize parallel execution environment
  !

  FUNCTION ParCommInit( ) RESULT ( ParallelEnv ) 

    TYPE (ParEnv_t), POINTER :: ParallelEnv

    ! Local variables

    INTEGER :: ierr

    !******************************************************************

    ParallelEnv => ParEnv

    ierr = 0
    CALL MPI_INIT( ierr )

    CALL MPI_COMM_SIZE( MPI_COMM_WORLD, ParEnv % PEs, ierr )
    CALL MPI_COMM_RANK( MPI_COMM_WORLD, ParEnv % MyPE, ierr )

    IF ( ParEnv % PEs <= 1 ) THEN
       CALL MPI_Finalize( ierr )
    ELSE
       WRITE( Message, * ) 'Initialize: ', ParEnv % PEs, ParEnv % MyPE
       CALL Info( 'ParCommInit', Message, Level=5 )
    
       IF ( ierr /= 0 ) THEN
          WRITE( Message, * ) 'MPI Initialization failed ! (ierr=', ierr, ')'
          CALL Fatal( 'ParCommInit', Message )
       END IF

       Parenv % NumOfNeighbours = 0
       ALLOCATE( ParEnv % SendingNB( ParEnv % PEs ) )
       ALLOCATE( ParEnv % IsNeighbour( ParEnv % PEs ) )
       ParEnv % Initialized = .TRUE.
    END IF
  END FUNCTION ParCommInit


  !********************************************************************
  !********************************************************************
  !
  ! Initialize parallel execution environment
  !
!-----------------------------------------------------------------------
  SUBROUTINE ParEnvInit( SPMatrix, Nodes, SourceMatrix, DOFs  )
!-----------------------------------------------------------------------

    TYPE(SparIterSolverGlobalD_t) :: SPMatrix
    TYPE (Nodes_t) :: Nodes
    INTEGER :: DOFs
    TYPE(Matrix_t) :: SourceMatrix

!-----------------------------------------------------------------------

    ! Local variables
    INTEGER, DIMENSION(MPI_STATUS_SIZE) :: status

    INTEGER, ALLOCATABLE :: Active(:)
    INTEGER :: i, j, k, ierr, proc, Group

!-----------------------------------------------------------------------

    !******************************************************************

    CALL CheckBuffer( 8*SourceMatrix % NumberOfRows )

    SPMatrix % ParEnv = ParEnv

    ALLOCATE( SPMatrix % ParEnv % SendingNB( ParEnv % PEs ) )
    ALLOCATE( SPMatrix % ParEnv % Active( ParEnv % PEs ) )
    ALLOCATE( SPMatrix % ParEnv % IsNeighbour( ParEnv % PEs ) )

    SPMatrix % ParEnv % NumOfNeighbours = 0
    SPMatrix % ParEnv % Active(:)       = .FALSE.
    SPMatrix % ParEnv % SendingNB(:)    = .FALSE.
    SPMatrix % ParEnv % IsNeighbour(:)  = .FALSE.

    !------------------------------------------------------------------
    !
    ! Count the number of real neighbours for this partition
    !
    !------------------------------------------------------------------

    DO i=DOFs, SourceMatrix % NumberOfRows, DOFs
       k = SourceMatrix % INVPerm(i) / DOFs
 
       IF ( SIZE( Nodes % NeighbourList(k) % Neighbours ) > 1 ) THEN
          DO j = 1, SIZE( Nodes % NeighbourList(k) % Neighbours )
             proc = Nodes % NeighbourList(k) % Neighbours(j)
             IF ( proc /= ParEnv % MyPE ) THEN
                IF ( .NOT. SPMatrix % ParEnv % IsNeighbour(proc+1) ) THEN
                   SPMatrix % ParEnv % IsNeighbour(proc+1) = .TRUE.
                   SPMatrix % ParEnv % NumOfNeighbours = &
                            SPMatrix % ParEnv % NumOfNeighbours + 1
                END IF
             END IF
          END DO
       END IF
    END DO

    !------------------------------------------------------------------
    !
    ! Scan active procs for this specific equation.
    ! TODO: wont work for disconnected areas....
    !
    !------------------------------------------------------------------

    ALLOCATE( Active( ParEnv % PEs ) )
    SPMatrix % ParEnv % Active = SPMatrix % ParEnv % IsNeighbour

    DO k = 1, ParEnv % PEs
       Active = 0
       DO i=1,ParEnv % PEs
          IF ( SPMatrix % ParEnv % Active(i) ) Active(i) = 1
       END DO

       DO i=1,ParEnv % PEs
          IF ( SPMatrix % ParEnv % IsNeighbour(i) ) THEN
             CALL MPI_BSEND( Active, ParEnv % PEs, MPI_INTEGER, i-1, &
                     k, MPI_COMM_WORLD, ierr )
          END IF
       END DO

       DO i=1,ParEnv % PEs
          IF ( SPMatrix % ParEnv % IsNeighbour(i) ) THEN
             CALL MPI_RECV( Active, ParEnv % PEs, MPI_INTEGER, i-1, &
                     k, MPI_COMM_WORLD, status, ierr )
             SPMatrix % ParEnv % Active = &
                  SPMatrix % ParEnv % Active .OR. Active /= 0
          END IF
       END DO
    END DO

    DEALLOCATE( Active )
!-----------------------------------------------------------------------
  END SUBROUTINE ParEnvInit
!-----------------------------------------------------------------------


!*********************************************************************
! Try to agree about global numbering of nodes among active
! processes.
!-----------------------------------------------------------------------
   SUBROUTINE SParGlobalNumbering( Nodes,NewNodeCnt, &
            OldIntCnts, OldIntArray, Reorder )
!-----------------------------------------------------------------------
    USE GeneralUtils
!-----------------------------------------------------------------------
     TYPE(Nodes_t) :: Nodes
     INTEGER, TARGET :: NewNodeCnt, OldIntArray(:), &
               OldIntCnts(:), Reorder(:)
!-----------------------------------------------------------------------
     INTEGER, DIMENSION(MPI_STATUS_SIZE) :: status
     INTEGER :: ierr

     INTEGER :: i,j,k,l,n,MinProc,MaxLcl,MaxGlb,InterfaceNodes
     INTEGER :: LIndex(100), IntN, Gindex, k1, k2
     INTEGER, POINTER :: IntArray(:),IntCnts(:),GIndices(:),Gorder(:)
!-----------------------------------------------------------------------
     CALL MPI_BARRIER( MPI_COMM_WORLD, ierr )

! XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
! YOU, YES YOU  DO SOMETHING ABOUT THIS 
     CALL CheckBuffer(1000000)
! XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
!
!    find least numbered of the active procs:
!    ----------------------------------------
     DO MinProc = 1,ParEnv % PEs
        IF ( ParEnv % Active( MinProc ) ) EXIT
     END DO
!
!    Our maximum global node index:
!    -------------------------------
     MaxLcl = MAXVAL( Nodes % GlobalNodeNumber )
     MaxGlb = MaxLcl
     n = Nodes % NumberOfNodes - NewNodeCnt + 1
!
!    Lowest numbered PE will compute the size of
!    the (old) global node array, and eventually
!    distribute the knowledge:
!    -------------------------------------------
     IF ( ParEnv % MyPE == MinProc-1 ) THEN
        j = 1
        DO i=MinProc+1,ParEnv % PEs
           IF ( ParEnv % Active(i) ) THEN
              CALL MPI_RECV( k, 1, MPI_INTEGER, i-1, &
                10, MPI_COMM_WORLD, status, ierr )
              MaxGlb = MAX( MaxGlb, k )
           END IF
        END DO
     ELSE
        CALL MPI_BSEND( MaxLcl, 1, MPI_INTEGER, &
          MinProc-1, 10, MPI_COMM_WORLD, ierr )
     END IF
!
!    Recieve new interface nodes from lower
!    numbered PEs, and check if they are
!    relevant to us:
!    ---------------------------------------
     DO i=MinProc,ParEnv % MyPE
        IF ( .NOT. (ParEnv % Active(i) .AND. ParEnv % Isneighbour(i)) ) CYCLE
        
        CALL MPI_RECV( InterfaceNodes, 1, MPI_INTEGER, &
           i-1, 14, MPI_COMM_WORLD, status, ierr )

        IF ( InterfaceNodes > 0 ) THEN
           ALLOCATE( GIndices(InterfaceNodes), IntCnts(InterfaceNodes) )

           CALL MPI_RECV( GIndices, InterfaceNodes, MPI_INTEGER, &
                  i-1, 15, MPI_COMM_WORLD, status, ierr )

           CALL MPI_RECV( IntCnts, InterfaceNodes, MPI_INTEGER, &
                  i-1, 16, MPI_COMM_WORLD, status, ierr )

           CALL MPI_RECV( k, 1, MPI_INTEGER, &
                  i-1, 17, MPI_COMM_WORLD, status, ierr )

           ALLOCATE( IntArray(k) )

           CALL MPI_RECV( IntArray, SIZE(IntArray), MPI_INTEGER, &
                  i-1, 18, MPI_COMM_WORLD, status, ierr )
!
!          Update our view of the global numbering
!          at the interface nodes:
!          ---------------------------------------
           l = 0
           DO j=1,InterfaceNodes
              Lindex = 0
              IntN = IntCnts(j)
              DO k=1,IntN
                 Lindex(k) = SearchNode( Nodes, IntArray(l+k), 1, n-1 )
              END DO

              IF ( ALL( Lindex(1:IntN) > 0 ) ) THEN
!                This node belongs to us as well well:
!                -------------------------------------
                 k2 = 0
                 k1 = 0
                 DO k=n,Nodes % NumberOfNodes
                    IF ( .NOT.Nodes % Interface(k) ) CYCLE

                    k1 = k1 + 1
                    IF ( IntN == OldIntCnts(k1) ) THEN
                       IF ( ALL( IntArray(l+1:l+IntN) == &
                                    OldIntArray(k2+1:k2+IntN)) ) THEN
                           Nodes % GlobalNodeNumber(k) = GIndices(j)
                           EXIT
                        END IF
                     END IF
                     k2 = k2 + OldIntCnts(k1)
                 END DO
              END IF
              l = l + IntN
           END DO
           DEALLOCATE( Gindices, IntCnts, IntArray )
        END IF
     END DO
!
!    Update the current numbering from the 
!    previous PE in line, this will make the
!    execution strictly serial. Maybe there
!    would be an easier way?
!    ---------------------------------------
     IF ( ParEnv % MyPE > MinProc-1 ) THEN
        DO i=ParEnv % MyPE, MinProc, -1
           IF ( ParEnv % Active(i) ) THEN
              CALL MPI_RECV( MaxGlb, 1, MPI_INTEGER, &
               i-1, 20, MPI_COMM_WORLD, status, ierr )
              EXIT
           END IF
        END DO
     END IF
!
!    Renumber our own new set of nodes:
!    ----------------------------------
     DO i=n,Nodes % NumberOfNodes
        IF ( Nodes % GlobalNodeNumber(i) == 0 ) THEN
           MaxGlb = MaxGlb + 1
           Nodes % GlobalNodeNumber(i) = MaxGlb
        END IF
     END DO
!
!    Extract interface nodes:
!    ------------------------
     InterfaceNodes = COUNT( Nodes % Interface(n:) )
     IF ( InterfaceNodes > 0 ) ALLOCATE( Gindices(InterfaceNodes) )

     InterfaceNodes = 0
     DO i=n,Nodes % NumberOfNodes
        IF ( Nodes % Interface(i) ) THEN
           InterfaceNodes = InterfaceNodes + 1
           Gindices(InterfaceNodes) = Nodes % GlobalNodeNumber(i)
        END IF
     END DO
!
!    Send new interface nodes to higher numbered PEs:
!    ------------------------------------------------
     DO i=ParEnv % MyPE+2,ParEnv % PEs
        IF ( .NOT. (ParEnv % Active(i) .AND. ParEnv % Isneighbour(i)) ) CYCLE

        CALL MPI_BSEND( InterfaceNodes, 1, MPI_INTEGER, &
               i-1, 14, MPI_COMM_WORLD, ierr )

        IF ( InterfaceNodes > 0 ) THEN
           CALL MPI_BSEND( GIndices, InterfaceNodes, MPI_INTEGER, &
                    i-1, 15, MPI_COMM_WORLD, ierr )

           CALL MPI_BSEND( OldIntCnts, InterfaceNodes, &
              MPI_INTEGER, i-1, 16, MPI_COMM_WORLD, ierr )

           CALL MPI_BSEND( SIZE(OldIntArray), 1, &
              MPI_INTEGER, i-1, 17, MPI_COMM_WORLD, ierr )

           CALL MPI_BSEND( OldIntArray, SIZE(OldIntArray), &
              MPI_INTEGER, i-1, 18, MPI_COMM_WORLD, ierr )

        END IF
     END DO

     DEALLOCATE( GIndices )
!
!    Send go singal to next PE in line...
!    ------------------------------------
     DO i = ParEnv % MyPE+2, ParEnv % PEs
        IF ( ParEnv % Active(i) ) THEN
           CALL MPI_BSEND( MaxGlb, 1, MPI_INTEGER, &
               i-1, 20, MPI_COMM_WORLD, ierr )
           EXIT
        END IF
     END DO
!
!    Sort our own nodes according to ascending
!    global order:
!    -----------------------------------------
     ALLOCATE( IntCnts(NewNodeCnt), Gorder(NewNodeCnt) )
     DO i=1,NewNodeCnt
        Gorder(i) = i
     END DO

     CALL SortI( NewNodeCnt, Nodes % GlobalNodeNumber(n:), Gorder )

     DO i=1,NewNodeCnt
        IntCnts(Gorder(i)) = i
     END DO
!
!    Reorder will return the nodal reordering
!    to the caller:
!    ----------------------------------------
     Reorder(n:) = IntCnts + n - 1
!
!    Order the whole of the nodal structure
!    according to the changed order of the 
!    global numbers:
!    --------------------------------------
     DO i=1,NewNodeCnt
        k = Gorder(i)
        CALL SwapNodes( Nodes, i+n-1, k+n-1 )

        j = IntCnts(i)
        IntCnts(i) = IntCnts(k)
        IntCnts(k) = j

        Gorder(IntCnts(k)) = k
     END DO

     DEALLOCATE( IntCnts )
!
!    Ok, now we have generated the global numbering
!    of nodes. We still need to distribute the
!    information which PEs share which of the new
!    interface nodes:
!    -----------------------------------------------
     InterfaceNodes = COUNT( Nodes % Interface(n:) )
     ALLOCATE( GIndices( InterfaceNodes ) )
     j = 0
     DO i=n,Nodes % NumberOfNodes
        IF ( Nodes % Interface(i) ) THEN
           j = j + 1
           GIndices(j) = Nodes % GlobalNodeNumber(i)
           ALLOCATE( Nodes % NeighbourList(i) % Neighbours(ParEnv % PEs) )
           Nodes % NeighbourList(i) % Neighbours = -1
        END IF
     END DO

     DO i=MinProc,ParEnv % PEs
        IF ( ParEnv % MyPE == i-1 ) CYCLE
        IF ( ParEnv % Active(i) .AND. ParEnv % IsNeighbour(i) ) THEN
           CALL MPI_BSEND( InterfaceNodes, 1, &
              MPI_INTEGER, i-1, 30, MPI_COMM_WORLD, ierr )

           CALL MPI_BSEND( GIndices, InterfaceNodes, &
              MPI_INTEGER, i-1, 31, MPI_COMM_WORLD, ierr )
        END IF
     END DO

     DEALLOCATE( Gindices )

     ALLOCATE( IntCnts( Nodes % NumberOfNodes ) )

     IntCnts = 0
     DO i=n,Nodes % NumberOfNodes
        IF ( Nodes % Interface(i) ) THEN
           IntCnts(i) = IntCnts(i) + 1
           Nodes % NeighbourList(i) % Neighbours(1) = ParEnv % MyPE
        END IF
     END DO

     DO i=MinProc,ParEnv % PEs
        IF ( ParEnv % MyPE == i-1 ) CYCLE
        IF ( ParEnv % Active(i) .AND. ParEnv % IsNeighbour(i) ) THEN
           CALL MPI_RECV( InterfaceNodes, 1, MPI_INTEGER, &
               i-1, 30, MPI_COMM_WORLD, status, ierr )

           ALLOCATE( GIndices(InterfaceNodes) )

           CALL MPI_RECV( GIndices, InterfaceNodes, MPI_INTEGER, &
               i-1, 31, MPI_COMM_WORLD, status, ierr )

           DO j=1,InterfaceNodes
              k = SearchNode( Nodes, Gindices(j), n )
              IF ( k <= 0 ) CYCLE
              IntCnts(k) = IntCnts(k) + 1
              Nodes % NeighbourList(k) % Neighbours(IntCnts(k)) = i-1
           END DO

           DEALLOCATE( GIndices )
        END IF
     END DO
!
!    Reallocate the nodal neighbour lists to
!    correct sizes:
!    ---------------------------------------
     DO i=n,Nodes % NumberOfNodes
        IF ( Nodes % Interface(i) ) THEN
           k = IntCnts(i)
           ALLOCATE( Gindices(k) ) ! just work space
           Gindices = Nodes % NeighbourList(i) % Neighbours(1:k)
           CALL Sort( k, Gindices )
           DEALLOCATE( Nodes % NeighbourList(i) % Neighbours )
           Nodes % NeighbourList(i) % Neighbours => Gindices
        END IF
     END DO
     
     DEALLOCATE( IntCnts )

     CALL MPI_BARRIER( MPI_COMM_WORLD, ierr )

CONTAINS

!-----------------------------------------------------------------------
     SUBROUTINE SwapNodes( Nodes, i, k )
!-----------------------------------------------------------------------
        INTEGER :: i,k
        TYPE(Nodes_t) :: Nodes
!-----------------------------------------------------------------------
        REAL(KIND=dp) :: swapx,swapy,swapz
        LOGICAL :: swapi
        INTEGER, POINTER :: swapl(:)
!-----------------------------------------------------------------------
        swapx =  Nodes % x(i)
        swapy =  Nodes % y(i)
        swapz =  Nodes % z(i)
        swapi =  Nodes % Interface(i)
        swapl => Nodes % NeighbourList(i) % Neighbours
 
        Nodes % x(i) = Nodes % x(k)
        Nodes % y(i) = Nodes % y(k)
        Nodes % z(i) = Nodes % z(k)
        Nodes % Interface(i) = Nodes % Interface(k) 
        Nodes % NeighbourList(i) % Neighbours => &
                 Nodes % NeighbourList(k) % Neighbours

        Nodes % x(k) = swapx
        Nodes % y(k) = swapy
        Nodes % z(k) = swapz
        Nodes % Interface(k) = swapi
        Nodes % NeighbourList(k) % Neighbours => swapl
!-----------------------------------------------------------------------
     END SUBROUTINE SwapNodes
!-----------------------------------------------------------------------
   END SUBROUTINE SParGlobalNumbering
!-----------------------------------------------------------------------


!-----------------------------------------------------------------------
   SUBROUTINE SParIterBarrier
!-----------------------------------------------------------------------
   INTEGER :: ierr
   CALL MPI_BARRIER( MPI_COMM_WORLD, ierr )
!-----------------------------------------------------------------------
   END  SUBROUTINE SParIterBarrier
!-----------------------------------------------------------------------


!*********************************************************************
!*********************************************************************
!
! Send all of the interface matrix blocks (in NbsIfMatrices) to neighbour
! processors. This is done only once so there is no need to optimize
! communication...
!
  SUBROUTINE ExchangeInterfaces( NbsIfMatrix, RecvdIfMatrix )

    USE types
    IMPLICIT NONE

    ! Parameters

    TYPE (Matrix_t), DIMENSION(*) :: NbsIfMatrix, RecvdIfMatrix

    ! Local variables

    INTEGER :: i, j, ierr, sproc, destproc, rows, cols, TotalSize

    INTEGER, DIMENSION(MPI_STATUS_SIZE) :: status
  !*********************************************************************

  TotalSize = 0
  DO i = 1, ParEnv % PEs
     IF ( ParEnv % IsNeighbour(i) ) THEN
       IF ( NbsIfMatrix(i) % NumberOfRows == 0 ) THEN
           TotalSize = TotalSize + 4
       ELSE
           Cols = NbsIfMatrix(i) % Rows(NbsIfMatrix(i) % NumberOfRows+1)-1
           TotalSize = TotalSize + 4 + 8*NbsIfMatrix(i) % NumberOfRows + &
                12*Cols
       END IF
     END IF
  END DO
  TotalSize = 1.5 * TotalSize
  CALL CheckBuffer( TotalSize )

  !----------------------------------------------------------------------
  !
  ! Send the interface parts
  !
  !----------------------------------------------------------------------

    DO i = 1, ParEnv % PEs
       IF ( ParEnv % IsNeighbour(i) ) THEN

          destproc = i - 1
          IF ( NbsIfMatrix(i) % NumberOfRows == 0 ) THEN

             CALL MPI_BSEND( 0, 1, MPI_INTEGER, destproc, &
                    1000, MPI_COMM_WORLD, ierr )

          ELSE

             Cols = NbsIfMatrix(i) % Rows(NbsIfMatrix(i) % NumberOfRows+1) - 1

             CALL MPI_BSEND( NbsIfMatrix(i) % NumberOfRows, 1, MPI_INTEGER, &
                  destproc, 1000, MPI_COMM_WORLD, ierr )

             CALL MPI_BSEND( Cols, 1, MPI_INTEGER, &
                  destproc, 1001, MPI_COMM_WORLD, ierr )

             CALL MPI_BSEND( NbsIfMatrix(i) % GRows, &
                  NbsIfMatrix(i) % NumberOfRows, MPI_INTEGER, &
                  destproc, 1002, MPI_COMM_WORLD, ierr )

             CALL MPI_BSEND( NbsIfMatrix(i) % Rows, &
                  NbsIfMatrix(i) % NumberOfRows + 1, MPI_INTEGER, &
                  destproc, 1003, MPI_COMM_WORLD, ierr )

             CALL MPI_BSEND( NbsIfMatrix(i) % RowOwner, &
                  NbsIfMatrix(i) % NumberOfRows, MPI_INTEGER, &
                  destproc, 1004, MPI_COMM_WORLD, ierr )

             CALL MPI_BSEND( NbsIfMatrix(i) % Cols, &
                  Cols, MPI_INTEGER, destproc, 1005, MPI_COMM_WORLD, ierr )
        END IF
     END IF
  END DO

  !----------------------------------------------------------------------
  !
  ! Receive the interface parts
  !
  !----------------------------------------------------------------------

  DO i = 1, ParEnv % NumOfNeighbours
     CALL MPI_RECV( rows, 1, MPI_INTEGER, MPI_ANY_SOURCE, 1000, &
                    MPI_COMM_WORLD, status, ierr )
     sproc = status(MPI_SOURCE)

     IF ( Rows == 0 ) THEN

        RecvdIfMatrix(sproc+1) % NumberOfRows = 0

     ELSE
       CALL MPI_RECV( cols, 1, MPI_INTEGER, sproc, 1001, &
              MPI_COMM_WORLD, status, ierr )

       RecvdIfMatrix(sproc+1) % NumberOfRows = Rows
       ALLOCATE( RecvdIfMatrix(sproc+1) % Rows(Rows+1) )
       ALLOCATE( RecvdIfMatrix(sproc+1) % Diag(Rows) )
       ALLOCATE( RecvdIfMatrix(sproc+1) % Cols(Cols) )
       ALLOCATE( RecvdIfMatrix(sproc+1) % GRows(Rows) )
       ALLOCATE( RecvdIfMatrix(sproc+1) % RowOwner(Rows) )

       CALL MPI_RECV( RecvdIfMatrix(sproc+1) % GRows, Rows,  MPI_INTEGER, &
             sproc, 1002, MPI_COMM_WORLD, status, ierr )

       CALL MPI_RECV( RecvdIfmatrix(sproc+1) % Rows, Rows+1, MPI_INTEGER, &
            sproc, 1003, MPI_COMM_WORLD, status, ierr )

       CALL MPI_RECV( RecvdIfmatrix(sproc+1) % RowOwner, Rows, MPI_INTEGER, &
            sproc, 1004, MPI_COMM_WORLD, status, ierr )

       CALL MPI_RECV( RecvdIfMatrix(sproc+1) % Cols, Cols, MPI_INTEGER, &
            sproc, 1005, MPI_COMM_WORLD, status, ierr )
     END IF
  END DO
END SUBROUTINE ExchangeInterfaces

!*********************************************************************
!*********************************************************************
!
! Send all of the *VALUES* in the interface matrix blocks (in NbsIfMatrices)
! to neighbour processors. This is done once on every non-linear iteration
! when the coefficient matrix has been assembled.
!
SUBROUTINE ExchangeIfValues( NbsIfMatrix, RecvdIfMatrix, NeedMass )

  USE types
  IMPLICIT NONE

  ! Parameters

  TYPE (Matrix_t), DIMENSION(:) :: NbsIfMatrix, RecvdIfMatrix

  ! Local variables

  LOGICAL :: NeedMass
  INTEGER, DIMENSION(MPI_STATUS_SIZE) :: status
  INTEGER :: i, j, ierr, destproc, rows, cols, sproc, TotalSize

  !*********************************************************************

  !----------------------------------------------------------------------
  !
  ! Send the interface parts
  !
  !----------------------------------------------------------------------

  TotalSize = 0
  DO i = 1, ParEnv % PEs
     IF ( ParEnv % IsNeighbour(i) ) THEN
        IF ( NbsIfMatrix(i) % NumberOfRows == 0 ) THEN
           TotalSize = TotalSize + 4
        ELSE
           Cols = NbsIfMatrix(i) % Rows(NbsIfMatrix(i) % NumberOfRows+1)-1
           TotalSize = TotalSize + 4 + 8*NbsIfMatrix(i) % NumberOfRows + &
                       12*Cols
        END IF
     END IF
  END DO
  TotalSize = 1.5 * TotalSize
  CALL CheckBuffer( TotalSize )

  DO i = 1, ParEnv % PEs
     IF ( ParEnv % IsNeighbour(i) ) THEN

        destproc = i - 1
        IF ( NbsIfMatrix(i) % NumberOfRows == 0 ) THEN

          CALL MPI_BSEND( 0, 1, MPI_INTEGER, &
            destproc, 2000, MPI_COMM_WORLD, ierr )

        ELSE

           Cols = NbsIfMatrix(i) % Rows(NbsIfMatrix(i) % NumberOfRows+1) - 1

          CALL MPI_BSEND( NbsIfMatrix(i) % NumberOfRows, 1, MPI_INTEGER, &
                destproc, 2000, MPI_COMM_WORLD, ierr )

          CALL MPI_BSEND( Cols, 1, MPI_INTEGER, &
                 destproc, 2001, MPI_COMM_WORLD, ierr )

          CALL MPI_BSEND( NbsIfMatrix(i) % GRows, &
              NbsIfMatrix(i) % NumberOfRows, MPI_INTEGER, &
                destproc, 2002, MPI_COMM_WORLD, ierr )

          CALL MPI_BSEND( NbsIfMatrix(i) % Rows, &
               NbsIfMatrix(i) % NumberOfRows + 1, MPI_INTEGER, &
               destproc, 2003, MPI_COMM_WORLD, ierr )

          CALL MPI_BSEND( NbsIfMatrix(i) % Cols, &
            Cols, MPI_INTEGER, destproc, 2004, MPI_COMM_WORLD, ierr )

          CALL MPI_BSEND( NbsIfMatrix(i) % Values, Cols, &
             MPI_DOUBLE_PRECISION, destproc, 2005, MPI_COMM_WORLD, ierr )

           IF ( NeedMass ) &
              CALL MPI_BSEND( NbsIfMatrix(i) % MassValues, Cols, &
                MPI_DOUBLE_PRECISION, destproc, 2006, MPI_COMM_WORLD, ierr )
           END IF
     END IF
  END DO

  !----------------------------------------------------------------------
  !
  ! Receive the interface parts
  !
  !----------------------------------------------------------------------

  DO i = 1, ParEnv % NumOfNeighbours

     CALL MPI_RECV( Rows, 1, MPI_INTEGER, MPI_ANY_SOURCE, &
             2000, MPI_COMM_WORLD, status, ierr )
     sproc = status(MPI_SOURCE)

     IF ( Rows == 0 ) THEN
 
        RecvdIfMatrix(sproc+1) % NumberOfRows = 0

     ELSE

        CALL MPI_RECV( Cols, 1, MPI_INTEGER, sproc, 2001, &
               MPI_COMM_WORLD, status, ierr )

        RecvdIfMatrix(sproc+1) % NumberOfRows = Rows
        ALLOCATE( RecvdIfMatrix(sproc+1) % Rows(Rows+1) )
        ALLOCATE( RecvdIfMatrix(sproc+1) % Cols(Cols) )
        ALLOCATE( RecvdIfMatrix(sproc+1) % GRows(Rows) )
        ALLOCATE( RecvdIfMatrix(sproc+1) % Values(Cols) )
        ALLOCATE( RecvdIfMatrix(sproc+1) % MassValues(Cols) )
        RecvdIfMatrix(sproc+1) % MassValues = 0.0d0

        CALL MPI_RECV( RecvdIfMatrix(sproc+1) % GRows, Rows,  MPI_INTEGER, &
                  sproc, 2002, MPI_COMM_WORLD, status, ierr )

        CALL MPI_RECV( RecvdIfmatrix(sproc+1) % Rows, Rows+1, MPI_INTEGER, &
                  sproc, 2003, MPI_COMM_WORLD, status, ierr )

        CALL MPI_RECV( RecvdIfMatrix(sproc+1) % Cols, Cols, MPI_INTEGER, &
                  sproc, 2004, MPI_COMM_WORLD, status, ierr )

        CALL MPI_RECV( RecvdIfMatrix(sproc+1) % Values, Cols, &
            MPI_DOUBLE_PRECISION, sproc, 2005, MPI_COMM_WORLD, status, ierr )

        IF ( NeedMass ) &
           CALL MPI_RECV( RecvdIfMatrix(sproc+1) % MassValues, Cols, &
             MPI_DOUBLE_PRECISION, sproc, 2006, MPI_COMM_WORLD, status, ierr )
     END IF

  END DO
END SUBROUTINE ExchangeIfValues

!*********************************************************************
!*********************************************************************
!
! Exchange right-hand-side elements on the interface with neighbours
!

SUBROUTINE ExchangeRHSIf( SourceMatrix, SplittedMatrix, &
          Nodes, DOFs, SourceRHS, TargetRHS )

  TYPE (SplittedMatrixT) :: SplittedMatrix
  TYPE (Matrix_t) :: SourceMatrix
  TYPE (Nodes_t) :: Nodes
  INTEGER :: DOFs
  REAL(KIND=dp), DIMENSION(:) :: SourceRHS, TargetRHS

  ! Local variables

  INTEGER :: i, j, k, datalen, ierr, sproc, destproc, ind, psum, dl, DOF
  INTEGER :: owner, request
  INTEGER, DIMENSION(MPI_STATUS_SIZE) :: status
  INTEGER, DIMENSION(:), ALLOCATABLE :: indbuf
  REAL(KIND=dp), DIMENSION(:), ALLOCATABLE :: valbuf
  INTEGER, DIMENSION(:), ALLOCATABLE :: RHSbufInds

  !*********************************************************************

  !----------------------------------------------------------------------
  !
  ! Extract the interface elements from SourceRHS to be sent to the
  ! real owner of that element.
  !
  !----------------------------------------------------------------------

  ALLOCATE( RHSbufInds( ParEnv % PEs ) )
  RHSbufInds = 1
  DO i = 1, SourceMatrix % NumberOfRows

     k = (SourceMatrix % INVPerm(i) + DOFs-1) / DOFs
     owner = Nodes % NeighbourList(k) % Neighbours(1)

     IF ( owner /= ParEnv % MyPE ) THEN
        DOF = DOFs - 1 - MOD( i-1, DOFs )

        SplittedMatrix % RHS(owner+1) % RHSind(RHSbufInds(owner+1)) = &
              Nodes % GlobalNodeNumber(k) * DOFs - DOF

        SplittedMatrix % RHS(owner+1) % RHSvec(RHSbufInds(owner+1)) = &
             SourceRHS(i)
        RHSbufInds(owner+1) = RHSbufInds(owner+1) + 1
     END IF
  END DO

  !----------------------------------------------------------------------
  !
  ! Do the exchange operation
  !
  !----------------------------------------------------------------------

  DO i = 1, ParEnv % PEs
     IF ( ParEnv % IsNeighbour(i) ) THEN
         destproc = i - 1

        IF ( .NOT.ASSOCIATED( SplittedMatrix % RHS(i) % RHSind) ) THEN

           CALL MPI_BSEND( 0, 1, MPI_INTEGER, &
                destproc, 3000, MPI_COMM_WORLD, ierr )

        ELSE

           DataLen = SIZE( SplittedMatrix % RHS(i) % RHSind )
           CALL MPI_BSEND( DataLen, 1, MPI_INTEGER, &
                destproc, 3000, MPI_COMM_WORLD, ierr )

           CALL MPI_BSEND( SplittedMatrix % RHS(i) % RHSind, DataLen, &
              MPI_INTEGER, destproc, 3001, MPI_COMM_WORLD, ierr )

           CALL MPI_BSEND( SplittedMatrix % RHS(i) % RHSVec, DataLen, &
              MPI_DOUBLE_PRECISION, destproc, 3002, MPI_COMM_WORLD, ierr )
        END IF

     END IF
  END DO

  DO i = 1, ParEnv % NumOfNeighbours

     CALL MPI_RECV( DataLen, 1, MPI_INTEGER, MPI_ANY_SOURCE, &
               3000, MPI_COMM_WORLD, status, ierr )
     sproc = status(MPI_SOURCE)

     IF ( DataLen /= 0 ) THEN
        ALLOCATE( IndBuf(DataLen), ValBuf(DataLen) )

        CALL MPI_RECV( IndBuf, DataLen, MPI_INTEGER, sproc, &
                3001, MPI_COMM_WORLD, status, ierr )

        CALL MPI_RECV( ValBuf, DataLen, MPI_DOUBLE_PRECISION, &
             sproc, 3002, MPI_COMM_WORLD, status, ierr )

        DO j = 1, DataLen
           Ind = SearchNode( Nodes, (IndBuf(j) + DOFs-1) / DOFs )

           IF ( Ind /= -1 ) THEN
              DOF = DOFs - 1 - MOD( IndBuf(j)-1, DOFs )
              Ind = SourceMatrix % Perm( DOFs * Ind - DOF )
              IF ( Ind > 0 ) THEN
                 SourceRHS(Ind) = SourceRHS(Ind) + ValBuf(j)
              END IF
           ELSE
              WRITE( Message, * ) ParEnv % MyPE,'RHS receive error'
              CALL Fatal( 'ExchangeRHSIf', Message )
           END IF
        END DO

        DEALLOCATE( IndBuf, ValBuf )
     END IF
     
  END DO

  ! Clean up temporary work space

  DEALLOCATE( RHSbufInds )

  j = 0
  DO i = 1, SourceMatrix % NumberOfRows
     k = (SourceMatrix % INVPerm(i) + DOFs-1) / DOFs
     IF ( Nodes % NeighbourList(k) % Neighbours(1) == ParEnv % MyPE ) THEN
        j = j + 1
        TargetRHS(j) = SourceRHS(i)
     END IF
  END DO

END SUBROUTINE ExchangeRHSIf


!*********************************************************************
!*********************************************************************
!
! Build index tables for faster vector element combination (in parallel
! matrix-vector operation).
!
SUBROUTINE BuildRevVecIndices( SplittedMatrix )
  USE Types
  IMPLICIT NONE

  TYPE (SplittedMatrixT) :: SplittedMatrix
  TYPE (Nodes_t) :: Nodes

  ! Local variables

  TYPE (Matrix_t), POINTER :: CurrIf, InsideMatrix
  INTEGER :: i, j, k, l, n, VecLen, ind, ierr, destproc, sproc, TotLen
  INTEGER :: TotalSize
  INTEGER, POINTER :: RevBuff(:),RevInd(:)
  INTEGER, DIMENSION(MPI_STATUS_SIZE) :: status
  INTEGER, DIMENSION(:), ALLOCATABLE :: GIndices,RowOwner
  LOGICAL :: Found
  LOGICAL, ALLOCATABLE :: Done(:,:)
REAL(KIND=dp) :: tt,CPUTime

  !*********************************************************************
tt = CPUTime()

  ALLOCATE( Done(ParEnv % PEs, SplittedMatrix % InsideMatrix % NumberOfRows) )
  Done = .FALSE.

  TotalSize = 0
  DO i = 1, ParEnv % PEs
     IF ( ParEnv % IsNeighbour(i) ) THEN
        CurrIf => SplittedMatrix % NbsIfMatrix(i)
        IF ( CurrIf % NumberOfRows == 0 ) THEN
           TotalSize = TotalSize + 4
        ELSE
           k = CurrIf % Rows(CurrIf % NumberOfRows+1)-1
           TotalSize = TotalSize + 4 + 8*CurrIf % NumberOfRows + 12*k
        END IF
     END IF

     IF ( ParEnv % IsNeighbour(i) ) THEN
        CurrIf => SplittedMatrix % IfMatrix(i)
        IF ( CurrIf % NumberOfRows == 0 ) THEN
           TotalSize = TotalSize + 4
        ELSE
           k = CurrIf % Rows(CurrIf % NumberOfRows+1)-1
           TotalSize = TotalSize + 4 + 8*CurrIf % NumberOfRows + 12*k
        END IF
     END IF
  END DO

  TotalSize = 1.5 * TotalSize
  CALL CheckBuffer( TotalSize )

  InsideMatrix => SplittedMatrix % InsideMatrix

  DO i = 1, ParEnv % PEs
     CurrIf => SplittedMatrix % IfMatrix(i)
     ALLOCATE( GIndices( CurrIf % NumberOfRows ) )

     DO j=0,ParEnv % PEs-1
        IF (  ParEnv % IsNeighbour(j+1) ) THEN
           L = 0
           DO k=1,CurrIf % NumberOfRows
              IF ( CurrIf % RowOwner(k) == j ) THEN
                 L = L + 1
                 GIndices(L) = CurrIf % GRows(k)
              END IF
           END DO
           CALL MPI_BSEND( L, 1, MPI_INTEGER, j, 4000 + 2*i, &
                    MPI_COMM_WORLD, ierr )

           IF ( L > 0 ) THEN
              CALL MPI_BSEND( GIndices, L, MPI_INTEGER, j, &
                 4000 + 2*i+1, MPI_COMM_WORLD, ierr )
           END IF
        END IF
     END DO
     DEALLOCATE( GIndices )
  END DO
!print*,parenv % mype, 'first send: ', CPUTime()-tt
!tt = CPUtime()
!
!
!
  DO i = 1, ParEnv % PEs
     IF ( .NOT. ParEnv % IsNeighbour(i) ) CYCLE

     CurrIf => SplittedMatrix % IfMatrix(i)

     ALLOCATE( RevBuff(1000) )
     RevInd => RevBuff
     RevInd = 0
     TotLen = 0
     sproc = i-1

     DO j=0,ParEnv % PEs-1
        CALL MPI_RECV( VecLen, 1, MPI_INTEGER, sproc, &
          4000+2*(j+1), MPI_COMM_WORLD, status, ierr )

        IF ( VecLen /= 0 ) THEN
           ALLOCATE( GIndices(VecLen) )

           CALL MPI_RECV( GIndices, VecLen, MPI_INTEGER, sproc, &
              4000+2*(j+1)+1, MPI_COMM_WORLD, status, ierr )

           IF ( TotLen + VecLen > SIZE(RevBuff) ) THEN
              ALLOCATE( RevInd( 2*(TotLen + VecLen) ) )
              RevInd = 0
              RevInd(1:SIZE(RevBuff)) = RevBuff
              DEALLOCATE( RevBuff )
              RevBuff => RevInd 
              Revind => RevBuff(TotLen+1:)
           END IF


           DO n = 1, VecLen
              Ind = SearchIAItem( InsideMatrix %  NumberOfRows, &
                InsideMatrix % GRows, GIndices(n), InsideMatrix % Gorder )

              IF ( Ind > 0 ) THEN
                 RevInd(n) = Ind

                 IF ( Done(i,Ind) ) CYCLE
                 Done(i,Ind) = .TRUE.

                 Found = .FALSE.
                 DO k = 1,CurrIf % NumberOfRows
                    DO l = CurrIf % Rows(k), CurrIf % Rows(k+1) - 1
                       IF ( Currif % Cols(l) == GIndices(n) ) THEN
                          SplittedMatrix % IfLCols(i) % IfVec(l) = ind
                          Found = .True.
                       END IF
                    END DO
                 END DO
              ELSE
                 WRITE( Message, * ) ParEnv % MyPE,' Could not find local node ', &
                          GIndices(n), '(reveiced from', sproc, ')'
                 CALL Error( 'BuildRevVecIndices', Message )
              END IF
           END DO

           DEALLOCATE( GIndices )
           Totlen = TotLen + VecLen
           RevInd => RevBuff(TotLen+1:)
        END IF 

        ParEnv % SendingNB(sproc+1) = .TRUE.
     END DO

     IF ( TotLen > 0 ) THEN
        SplittedMatrix % VecIndices(i) % RevInd => RevBuff
     ELSE
        DEALLOCATE( RevBuff )
        NULLIFY( SplittedMatrix % VecIndices(i) % RevInd )
     END IF
  END DO

!print*,parenv % mype, 'first recv: ', CPUTime()-tt
!tt = CPUtime()
!
!
!
  DO i = 1, ParEnv % PEs
     IF ( .NOT. ParEnv % IsNeighbour(i) ) CYCLE

     CurrIf => SplittedMatrix % NbsIfMatrix(i)
     IF ( CurrIf % NumberOfRows <= 0 ) THEN

        CALL MPI_BSEND( 0, 1, MPI_INTEGER, i-1, 5000, MPI_COMM_WORLD, ierr )

     ELSE

        VecLen = CurrIf % Rows(CurrIf % NumberOfRows+1) - 1
        CALL MPI_BSEND(VecLen, 1, MPI_INTEGER, i-1, &
                5000, MPI_COMM_WORLD, ierr)

        CALL MPI_BSEND( CurrIf % Cols, VecLen, MPI_INTEGER, &
               i-1, 5001, MPI_COMM_WORLD, ierr )
     END IF
  END DO

!print*,parenv % mype, 'secnd send: ', CPUTime()-tt
!tt = CPUtime()

  DO i = 1, ParEnv % PEs
     IF ( .NOT. ParEnv % IsNeighbour(i)) CYCLE

     CurrIf => SplittedMatrix % IfMatrix(i)
     sproc = i-1

     CALL MPI_RECV( VecLen, 1, MPI_INTEGER, sproc, 5000, &
               MPI_COMM_WORLD, status, ierr )

     IF ( VecLen /= 0 ) THEN
        ALLOCATE( GIndices(VecLen) )

        CALL MPI_RECV( GIndices, VecLen, MPI_INTEGER, sproc, &
               5001, MPI_COMM_WORLD, status, ierr )

        DO n = 1, VecLen

           Ind = SearchIAItem( InsideMatrix % NumberOfRows, &
               InsideMatrix % GRows, GIndices(n), InsideMatrix % Gorder )

           IF ( Ind > 0 ) THEN
              IF ( Done(i,Ind ) ) CYCLE
              Done(i,Ind) = .TRUE.

              DO k = 1,CurrIf % NumberOfRows
                 DO l = CurrIf % Rows(k), CurrIf % Rows(k+1) - 1
                    IF ( Currif % Cols(l) == GIndices(n) ) THEN
                       SplittedMatrix % IfLCols(i) % IfVec(l) = Ind
                    END IF
                 END DO
              END DO
                 
           ELSE
              WRITE( Message, * ) ParEnv % MyPE,'Could not find local node ', &
                       GIndices(n), '(reveiced from', sproc, ')'
              CALL Error( 'BuildRevVecIndices', Message )
           END IF
        END DO

        DEALLOCATE( GIndices )
        ParEnv % SendingNB(sproc+1) = .TRUE.
     END IF
  END DO
  DEALLOCATE( Done )
!print*,parenv % mype, 'secnd recv: ', CPUTime()-tt

END SUBROUTINE BuildRevVecIndices

!*********************************************************************
!*********************************************************************
!
! Send our part of the interface matrix blocks to neighbours.
!

SUBROUTINE Send_LocIf( SplittedMatrix )

  USE types
  IMPLICIT NONE

  TYPE (SplittedMatrixT) :: SplittedMatrix

  ! Local variables

  INTEGER :: i, j, k, ierr, TotalL
  TYPE (Matrix_t), POINTER :: IfM
  TYPE (IfVecT), POINTER :: IfV
  INTEGER, ALLOCATABLE :: L(:)
  REAL(KIND=dp), ALLOCATABLE :: VecL(:,:)

  !*********************************************************************

  ALLOCATE( L(ParEnv % PEs) )
  L = 0
  TotalL = 0

  DO i = 1, ParEnv % PEs
     IfM => SplittedMatrix % IfMatrix(i)

     DO j=1,ParEnv % PEs
        IF ( .NOT. ParEnv % IsNeighbour(j) ) CYCLE

        DO k=1,IfM % NumberOfRows
           IF ( IfM % RowOwner(k) == j-1 ) THEN
              L(j) = L(j) + 1
              TotalL = TotalL + 1
           END IF
        END DO
     END DO
  END DO

  ALLOCATE( VecL( MAXVAL(L), ParEnv % PEs ) )
  L = 0
  VecL = 0

  CALL CheckBuffer( 12*TotalL )

  DO i = 1, ParEnv % PEs
     IfM => SplittedMatrix % IfMatrix(i)
     IfV => SplittedMatrix % IfVecs(i)

     DO j=1, ParEnv % PEs
        IF ( .NOT. ParEnv % IsNeighbour(j) ) CYCLE

        DO k=1,IfM % NumberOfRows
           IF ( IfM % RowOwner(k) == j-1 ) THEN
              L(j) = L(j) + 1
              VecL(L(j),j) = IfV % IfVec(k)
           END IF
        END DO
     END DO
  END DO

  DO j=1,ParEnv % PEs
     IF ( .NOT. ParEnv % IsNeighbour(j) ) CYCLE

     CALL MPI_BSEND( L(j), 1, MPI_INTEGER, J-1, 6000, &
                MPI_COMM_WORLD, IERR )

     IF ( L(j) > 0 ) THEN
        CALL MPI_BSEND( VecL(1:L(j),j), L(j), MPI_DOUBLE_PRECISION, &
                 J-1, 6001, MPI_COMM_WORLD, ierr )
     END IF
  END DO

  IF ( ALLOCATED(VecL) ) DEALLOCATE( VecL, L )

END SUBROUTINE Send_LocIf

!*********************************************************************
!*********************************************************************
!
! Receive interface block contributions to vector from neighbours
!

SUBROUTINE Recv_LocIf( SplittedMatrix, ndim, v )

  USE types
  IMPLICIT NONE

  TYPE (SplittedMatrixT) :: SplittedMatrix
  INTEGER :: ndim
  REAL(KIND=dp), DIMENSION(*) :: v
  REAL(KIND=dp), ALLOCATABLE :: DPBuffer(:)

  SAVE DPBuffer

  ! Local variables

  integer :: i, j, k, ierr, sproc
  integer, dimension(MPI_STATUS_SIZE) :: status

  INTEGER, POINTER :: RevInd(:)
  INTEGER :: VecLen, TotLen

  !*********************************************************************

  IF ( .NOT. ALLOCATED(DPBuffer) ) ALLOCATE( DPBuffer( ndim ) ) 

  DO i = 1, ParEnv % NumOfNeighbours
     CALL MPI_RECV( VecLen, 1, MPI_INTEGER, MPI_ANY_SOURCE, &
              6000, MPI_COMM_WORLD, status, ierr )

     IF ( VecLen > 0 ) THEN
        sproc = status(MPI_SOURCE)

        RevInd => SplittedMatrix % VecIndices(sproc+1) % RevInd

        IF ( VecLen > SIZE( DPBuffer ) ) THEN
           DEALLOCATE( DPBuffer )
           ALLOCATE( DPBuffer( VecLen ) )
        END IF

        CALL MPI_RECV( DPBuffer, VecLen, MPI_DOUBLE_PRECISION, &
               sproc, 6001, MPI_COMM_WORLD, status, ierr )

        DO k = 1, VecLen
           IF ( RevInd(k) > 0 ) THEN
              v(RevInd(k)) = v(RevInd(k)) + DPBuffer(k)
           ELSE
              WRITE( Message, * ) ParEnv % MyPE, 'If Receive error: ', k,RevInd(k)
              CALL Fatal( 'Recv_LocIf', Message )
           END IF
        END DO
     END IF
  END DO
 
! CALL MPI_BARRIER( MPI_COMM_WORLD, ierr )
END SUBROUTINE Recv_LocIf


!*********************************************************************
!*********************************************************************
!
! Compute global dot product of vectors x and y
!

FUNCTION SParDotProd( ndim, x, xind, y, yind ) RESULT(dres)

  IMPLICIT NONE

  ! Parameters

  INTEGER :: ndim, xind, yind
  REAL(KIND=dp) :: x(*)
  REAL(KIND=dp) :: y(*)
  REAL(KIND=dp) :: dres

  ! Local variables

  REAL(KIND=dp) :: dsum, del
  INTEGER :: ierr, i
  integer, dimension(MPI_STATUS_SIZE) :: status

  !*********************************************************************


  IF ( xind == 1 .AND. yind  == 1 ) THEN
     dres = 0
     DO i = 1, ndim
        dres = dres + y(i) * x(i)
     END DO
  ELSE
     CALL Error( 'SParDotProd', 'xind or yind not 1' )
  END IF

  DO i = 1,ParEnv % PEs
     IF ( ParEnv % Active(i) .AND. i-1 /= ParEnv % MyPe ) THEN
        CALL MPI_BSEND( dres, 1, MPI_DOUBLE_PRECISION, &
              i-1, 7000, MPI_COMM_WORLD, ierr )
     END IF
  END DO

  DO i = 1,ParEnv % PEs
     IF ( ParEnv % Active(i) .AND. i-1 /= ParEnv % MyPe ) THEN
        CALL MPI_RECV( dsum, 1, MPI_DOUBLE_PRECISION, &
           i-1, 7000, MPI_COMM_WORLD, status, ierr )

        dres = dres + dsum
     END IF
  END DO

! CALL MPI_ALLREDUCE( dsum, dres, 1, MPI_DOUBLE_PRECISION, &
!             MPI_SUM, MPI_COMM_WORLD, ierr )
END FUNCTION SParDotProd

!*********************************************************************
!*********************************************************************
!
! Compute global 2-norm of vector x
!

FUNCTION SParNorm( ndim, x, xind ) RESULT(dres)

  IMPLICIT NONE

  ! Parameters

  INTEGER :: ndim, xind
  REAL(KIND=dp) :: x(*)
  REAL(KIND=dp) :: dres

  ! Local variables

  REAL(KIND=dp) :: dsum
  INTEGER :: i, ierr
  INTEGER, DIMENSION(MPI_STATUS_SIZE) :: status

  !*********************************************************************

  dres = 0
  DO i = 1, ndim
     dres = dres + x(i) * x(i)
  END DO

  DO i = 1,ParEnv % PEs
     IF ( ParEnv % Active(i) .AND. i-1 /= ParEnv % MyPe ) THEN
        CALL MPI_BSEND( dres, 1, MPI_DOUBLE_PRECISION, &
              i - 1, 8000, MPI_COMM_WORLD, ierr )
     END IF
  END DO

  DO i = 1,ParEnv % PEs
     IF ( ParEnv % Active(i) .AND. i-1 /= ParEnv % MyPe ) THEN
        CALL MPI_RECV( dsum, 1, MPI_DOUBLE_PRECISION, &
           i - 1, 8000, MPI_COMM_WORLD, status, ierr )

        dres = dres + dsum
     END IF
  END DO

! CALL MPI_ALLREDUCE( dsum, dres, 1, MPI_DOUBLE_PRECISION, &
!            MPI_SUM, MPI_COMM_WORLD, ierr )

  dres = SQRT( dres )

END FUNCTION SParNorm

!*********************************************************************
!*********************************************************************
!
! Compute global dot product of vectors x and y
!

FUNCTION ParComplexDotProd( ndim, x, xind, y, yind ) result (dres)

  IMPLICIT NONE

  ! Parameters

  INTEGER :: ndim, xind, yind
  COMPLEX(KIND=dp) :: x(*)
  COMPLEX(KIND=dp) :: y(*)
  COMPLEX(KIND=dp) :: dres


  ! Local variables

  COMPLEX(KIND=dp) :: dsum
  INTEGER :: ierr, i
  INTEGER, DIMENSION(MPI_STATUS_SIZE) :: status

  !*********************************************************************


  dres = 0.0d0

  IF ( xind == 1 .AND. yind  == 1 ) THEN
     DO i = 1, ndim
        dres = dres + x(i) * y(i)
     END DO
  ELSE
     CALL Fatal( 'ParComplexDotProd', 'xind or yind not 1' )
  END IF

  DO i = 1, ParEnv % PEs
     IF ( ParEnv % Active(i) .AND. i-1 /= ParEnv % MyPe ) THEN
        CALL MPI_BSEND( dres, 1, MPI_DOUBLE_COMPLEX, &
              i-1, 7000, MPI_COMM_WORLD, ierr )
     END IF
  END DO

  DO i = 1, ParEnv % PEs
     IF ( ParEnv % Active(i) .AND. i-1 /= ParEnv % MyPe ) THEN
        CALL MPI_RECV( dsum, 1, MPI_DOUBLE_COMPLEX, &
          i-1, 7000, MPI_COMM_WORLD, status, ierr )

        dres = dres + dsum
     END IF
  END DO

! CALL MPI_ALLREDUCE( dsum, dres, 1, MPI_DOUBLE_PRECISION, &
!             MPI_SUM, MPI_COMM_WORLD, ierr )
END FUNCTION ParComplexDotProd

!*********************************************************************
!*********************************************************************
!
! Compute global 2-norm of vector x
!

FUNCTION ParComplexNorm( ndim, x, xind ) result (norm)

  IMPLICIT NONE

  ! Parameters

  INTEGER :: ndim, xind
  REAL(KIND=dp) :: norm
  COMPLEX(KIND=dp) :: x(*)


  ! Local variables

  REAL(KIND=dp) :: nsum
  INTEGER :: i, ierr
  INTEGER, DIMENSION(MPI_STATUS_SIZE) :: status

  !*********************************************************************

  norm = 0.0d0
  DO i = 1, ndim
     norm = norm + DREAL(x(i))**2 + AIMAG(x(i))**2
  END DO

  DO i = 1,ParEnv % PEs
     IF ( ParEnv % Active(i) .AND. i-1 /= ParEnv % MyPe ) THEN
        CALL MPI_BSEND( norm, 1, MPI_DOUBLE_PRECISION, &
              i - 1, 8000, MPI_COMM_WORLD, ierr )
     END IF
  END DO

  DO i = 1,ParEnv % PEs
     IF ( ParEnv % Active(i) .AND. i-1 /= ParEnv % MyPe ) THEN
        CALL MPI_RECV( nsum, 1, MPI_DOUBLE_PRECISION, &
           i - 1, 8000, MPI_COMM_WORLD, status, ierr )

        norm = norm + nsum
     END IF
  END DO

! CALL MPI_ALLREDUCE( nsum, norm, 1, MPI_DOUBLE_PRECISION, &
!            MPI_SUM, MPI_COMM_WORLD, ierr )

  norm = SQRT( norm )

END FUNCTION ParComplexNorm



!*********************************************************************
!*********************************************************************
!
! Finalize MPI environment
!

SUBROUTINE ParEnvFinalize()

  USE types
  IMPLICIT NONE

  ! local variables

  INTEGER :: ierr

  !*********************************************************************

  CALL MPI_BARRIER( MPI_COMM_WORLD, ierr )
  CALL MPI_FINALIZE( ierr )

  IF ( ierr /= 0 ) THEN
     WRITE( Message, * ) 'MPI Finalization failed ! (ierr=', ierr, ')'
     CALL Fatal( 'ParEnvFinalize', Message )
  END IF

END SUBROUTINE ParEnvFinalize

!*********************************************************************
!*********************************************************************
!
! Send parts of the result vector to neighbours
!
!
!*********************************************************************
SUBROUTINE ExchangeResult( SourceMatrix, SplittedMatrix, Nodes, XVec, DOFs )

  USE types
  IMPLICIT NONE

  TYPE(SplittedMatrixT) :: SplittedMatrix
  TYPE(Matrix_t) :: SourceMatrix
  TYPE (Nodes_t) :: Nodes
  INTEGER :: DOFs
  REAL(KIND=dp), DIMENSION(:) :: XVec

  ! Local variables

  INTEGER :: i, j, ierr, sproc, destproc, BufLen, ResInd, DOF
  INTEGER, DIMENSION(:), ALLOCATABLE :: IndBuf
  TYPE (ResBufferT), POINTER :: CurrRBuf
  INTEGER, DIMENSION(MPI_STATUS_SIZE) :: status
  REAL(KIND=dp), DIMENSION(:), ALLOCATABLE :: ValBuf

  !*********************************************************************

  DO i = 1, ParEnv % PEs
     IF ( ParEnv % IsNeighbour(i) ) THEN

        destproc = i - 1

        CurrRBuf => SplittedMatrix % ResBuf(i)

        IF ( .NOT. ASSOCIATED(CurrRBuf % ResInd) ) THEN
           CALL MPI_BSEND( 0, 1, MPI_INTEGER, destproc, 9000, MPI_COMM_WORLD, ierr )
        ELSE

           BufLen = SIZE( CurrRBuf % ResInd )
           CALL MPI_BSEND( BufLen, 1, MPI_INTEGER, destproc, 9000, MPI_COMM_WORLD, ierr )

           CALL MPI_BSEND( CurrRBuf % ResInd, BufLen, MPI_INTEGER, &
                 destproc, 9001, MPI_COMM_WORLD, ierr )

           CALL MPI_BSEND( CurrRBuf % ResVal, BufLen, MPI_DOUBLE_PRECISION, &
                   destproc, 9002, MPI_COMM_WORLD, ierr )
        END IF

     END IF
  END DO


  DO i = 1, ParEnv % NumOfNeighbours
     CALL MPI_RECV( BufLen, 1, MPI_INTEGER, &
         MPI_ANY_SOURCE, 9000, MPI_COMM_WORLD, status, ierr )

     IF ( BufLen > 0 ) THEN
        sproc = status(MPI_SOURCE)
        ALLOCATE( IndBuf( BufLen ), ValBuf( BufLen ) )

        CALL MPI_RECV( IndBuf, BufLen, MPI_INTEGER, &
             sproc, 9001, MPI_COMM_WORLD, status, ierr )

        CALL MPI_RECV( ValBuf, BufLen, MPI_DOUBLE_PRECISION, &
             sproc, 9002, MPI_COMM_WORLD, status, ierr )

        DO j = 1, BufLen
           ResInd = SearchNode( Nodes, (IndBuf(j) + DOFs-1) / DOFs )
           IF ( ResInd > 0 ) THEN
              DOF = DOFs-1 - MOD( IndBuf(j)-1, DOFs )
              ResInd = SourceMatrix % Perm( DOFs * ResInd - DOF )
              IF ( ResInd > 0 ) XVec(ResInd) = ValBuf(j)
           ELSE
              WRITE( Message, * ) ParEnv % MyPE, 'Result Receive error: '
              CALL Fatal( 'ExchangeResult', Message )
           END IF
        END DO

        DEALLOCATE( IndBuf, ValBuf )
     END IF
  END DO
! CALL MPI_BARRIER( MPI_COMM_WORLD, ierr )

END SUBROUTINE ExchangeResult
!*********************************************************************



!*********************************************************************
!*********************************************************************
!
! Search an element QueriedNode from an ordered set Nodes and return
! Index to Nodes structure. Rerturn value -1 means QueriedNode was
! not found.
!
FUNCTION SearchNode( Nodes, QueriedNode,First,Last ) RESULT ( Index )

  USE Types
  IMPLICIT NONE

  TYPE (Nodes_t) :: Nodes
  INTEGER :: QueriedNode, Index
  INTEGER, OPTIONAL :: First,Last

  ! Local variables

  INTEGER :: Lower, Upper, Lou, i

  !*********************************************************************

  Index = -1
  Upper = Nodes % NumberOfNodes
  Lower = 1
  IF ( PRESENT( Last  ) ) Upper = Last
  IF ( PRESENT( First ) ) Lower = First

  ! Handle the special case

  IF ( Upper == 0 ) RETURN

10 CONTINUE
  IF ( Nodes % GlobalNodeNumber(Lower) == QueriedNode ) THEN
     Index = Lower
     RETURN
  ELSE IF ( Nodes % GlobalNodeNumber(Upper) == QueriedNode ) THEN
     Index = Upper
     RETURN
  END IF

  IF ( (Upper - Lower) > 1 ) THEN
     Lou = ISHFT((Upper + Lower), -1)
     IF ( Nodes % GlobalNodeNumber(Lou) < QueriedNode ) THEN
        Lower = Lou
        GOTO 10
     ELSE
        Upper = Lou
        GOTO 10
     END IF
  END IF

  RETURN

END FUNCTION SearchNode


!*********************************************************************
!*********************************************************************
!
! Search an element Item from an ordered integer array(N) and return
! Index to that array element. Return value -1 means Item was not found.
!
FUNCTION SearchIAItem( N, IArray, Item, SortOrder ) RESULT ( Index )

  USE types
  IMPLICIT NONE

  INTEGER :: Item, Index, i
  INTEGER :: N
  INTEGER, DIMENSION(:) :: IArray
  INTEGER, OPTIONAL :: SortOrder(:)

  ! Local variables

  INTEGER :: Lower, Upper, lou

  !*********************************************************************

  Index = -1
  Upper =  N
  Lower =  1

  ! Handle the special case

  IF ( Upper == 0 ) RETURN

  IF ( .NOT. PRESENT(SortOrder) ) THEN
     Index = SearchIAItemLinear( n,IArray,Item )
     RETURN
  END IF

  DO WHILE( .TRUE. )
     IF ( IArray(Lower) == Item ) THEN
        Index = Lower
        EXIT
     ELSE IF ( IArray(Upper) == Item ) THEN
        Index = Upper
        EXIT
     END IF

     IF ( (Upper - Lower) > 1 ) THEN
        Lou = ISHFT((Upper + Lower), -1)
        IF ( IArray(lou) < Item ) THEN
           Lower = Lou
        ELSE
           Upper = Lou
        END IF
     ELSE 
        EXIT
     END IF
  END DO

  IF ( Index > 0 ) Index  = SortOrder(Index)
  RETURN

END FUNCTION SearchIAItem


!*********************************************************************
!*********************************************************************
!
! Search an element Item from an ordered integer array(N) and return
! Index to that array element. Return value -1 means Item was not found.
!
FUNCTION SearchIAItemLinear( N, IArray, Item ) RESULT ( Index )

  USE types
  IMPLICIT NONE

  INTEGER :: N
  INTEGER, DIMENSION(*) :: IArray
  INTEGER :: Item, Index, i

  ! Local variables

  INTEGER :: Lower, Upper, lou
  !*********************************************************************

  Index = -1
  DO i=1,N
     IF ( IArray(i) == Item ) THEN
       Index = i
       RETURN
     END IF
  END DO

END FUNCTION SearchIAItemLinear


!********************************************************************
! End
!********************************************************************

END MODULE SParIterComm
