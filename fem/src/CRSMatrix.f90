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
! ******************************************************************************/
!
!/*******************************************************************************
! *
! * Module defining utility routines & matrix storage for sparse
! * matrix in Compressed Row Storage (CRS) format.
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
! *                       Date: 01 Oct 1996
! *
! *                Modified by:
! *
! *       Date of modification:
! *
! ******************************************************************************/

#include <huti_fdefs.h>

MODULE CRSMatrix

  USE GeneralUtils

  IMPLICIT NONE

CONTAINS


  !********************************************************************
  !
  FUNCTION CRS_Search( N,Array,Value ) RESULT ( Index )
DLLEXPORT CRS_Search

    INTEGER :: N,Value,Array(:)

    ! Local variables

    INTEGER :: Lower, Upper,Lou,Index

    !*******************************************************************

    Index = 0 
    Upper = N
    Lower = 1

    ! Handle the special case

    IF ( Upper == 0 ) RETURN

    DO WHILE( .TRUE. )
      IF ( Array(Lower) == Value ) THEN
        Index = Lower
        EXIT
      ELSE IF ( Array(Upper) == Value ) THEN
        Index = Upper
        EXIT
      END IF

      IF ( (Upper-Lower)>1 ) THEN
        Lou = ISHFT((Upper+Lower), -1)
        IF ( Array(Lou) < Value ) THEN
          Lower = Lou
        ELSE
          Upper = Lou
        END IF
      ELSE
        EXIT
      END IF
    END DO
    
    RETURN

  END FUNCTION CRS_Search

!********************************************************************



!------------------------------------------------------------------------------
  SUBROUTINE CRS_ZeroMatrix(A)
DLLEXPORT CRS_ZeroMatrix
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Zero a CRS format matrix
!
!  ARGUMENTS:
!
!  TYPE(Matrix_t) :: A
!     INPUT: Structure holding matrix
!
!******************************************************************************
!------------------------------------------------------------------------------
    TYPE(Matrix_t), POINTER :: A

    A % Values = 0.0d0
  END SUBROUTINE CRS_ZeroMatrix
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
  SUBROUTINE CRS_ZeroRow( A,n )
DLLEXPORT CRS_ZeroRow
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Zero given row from a CRS format matrix
!
!  ARGUMENTS:
!
!  TYPE(Matrix_t) :: A
!     INPUT: Structure holding matrix
!
!  INTEGER :: n
!     INPUT: Row number to be zerod
!
!******************************************************************************
!------------------------------------------------------------------------------
    TYPE(Matrix_t), POINTER :: A
    INTEGER :: n
 
    INTEGER :: i

    DO i=A % Rows(n),A % Rows(n+1)-1
       A % Values(i) = 0.0D0
    END DO

    IF ( ASSOCIATED(A % MassValues) ) THEN
       IF ( SIZE(A % MassValues) == SIZE(A % Values) ) THEN
          DO i=A % Rows(n),A % Rows(n+1)-1
             A % MassValues(i) = 0.0d0
          END DO
       END IF
    END IF

    IF ( ASSOCIATED(A % DampValues) ) THEN
       IF ( SIZE(A % DampValues) == SIZE(A % Values) ) THEN
          DO i=A % Rows(n),A % Rows(n+1)-1
             A % DampValues(i) = 0.0d0
          END DO
       END IF
    END IF
  END SUBROUTINE CRS_ZeroRow
!------------------------------------------------------------------------------
  


!------------------------------------------------------------------------------
  SUBROUTINE CRS_SortMatrix( A )
DLLEXPORT CRS_SortMatrix
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Sort columns to ascending order for rows of a CRS format matrix
!
!  ARGUMENTS:
!
!  TYPE(Matrix_t) :: A
!     INPUT: Structure holding matrix
!
!******************************************************************************
!------------------------------------------------------------------------------
    TYPE(Matrix_t), POINTER :: A

    INTEGER :: i,j,n

    INTEGER, POINTER :: Cols(:),Rows(:),Diag(:)

    Diag   => A % Diag
    Rows   => A % Rows
    Cols   => A % Cols
    n = A % NumberOfRows

    IF ( .NOT. A % Ordered ) THEN
      DO i=1,N
        CALL Sort( Rows(i+1)-Rows(i),Cols(Rows(i):Rows(i+1)-1) )
      END DO

      DO i=1,N
        DO j=Rows(i),Rows(i+1)-1
          IF ( Cols(j) == i ) THEN
            Diag(i) = j
            EXIT
          END IF
        END DO
      END DO

      A % Ordered = .TRUE.
    END IF

  END SUBROUTINE CRS_SortMatrix
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
  SUBROUTINE CRS_MakeMatrixIndex( A,i,j )
DLLEXPORT CRS_MakeMatrixIndex
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Fill in the column number to a CRS format matrix (values are not 
!    affected in any way...)
!
!  ARGUMENTS:
!
!  TYPE(Matrix_t) :: A
!     INPUT: Structure holding matrix
!
!  INTEGER :: i,j
!     INPUT: row and column numbers, respectively, of the matrix element
!
!******************************************************************************
!------------------------------------------------------------------------------
    TYPE(Matrix_t), POINTER :: A
    INTEGER :: i,j

    INTEGER :: k,n
    INTEGER, POINTER :: Cols(:),Rows(:)

    Rows   => A % Rows
    Cols   => A % Cols

    n = Rows(i)
    DO k=Rows(i),Rows(i+1)-1
      IF ( Cols(k) == j ) THEN
        RETURN
      ELSE IF ( Cols(k) < 1 ) THEN
        n = k
        EXIT
      END IF
    END DO

    IF ( Cols(n) >= 1 ) THEN
      WRITE( Message, * ) 'Trying to access non-existent column:',n,Cols(n)
      CALL Error( 'MakeMatrixIndex', Message )
      RETURN
    END IF

    Cols(n) = j
  END SUBROUTINE CRS_MakeMatrixIndex
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
  SUBROUTINE CRS_AddToMatrixElement( A,i,j,value )
DLLEXPORT CRS_AddToMatrixElement
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Add a given value to an element of a  CRS format matrix
!
!  ARGUMENTS:
!
!  TYPE(Matrix_t) :: A
!     INPUT: Structure holding matrix
!
!  INTEGER :: i,j
!     INPUT: row and column numbers, respectively, of the matrix element
!
!  REAL(KIND=dp) :: value
!     INPUT: Value to be added
!
!******************************************************************************
!------------------------------------------------------------------------------
    TYPE(Matrix_t), POINTER :: A
    INTEGER :: i,j
    REAL(KIND=dp) :: value
 
!------------------------------------------------------------------------------
!   Local variables
!------------------------------------------------------------------------------
    INTEGER :: k,n
    REAL(KIND=dp), POINTER :: Values(:)
    INTEGER, POINTER :: Cols(:),Rows(:),Diag(:)
!------------------------------------------------------------------------------

    Rows   => A % Rows
    Cols   => A % Cols
    Diag   => A % Diag
    Values => A % Values

    IF ( i /= j .OR. .NOT. A % Ordered ) THEN
      k = CRS_Search( Rows(i+1)-Rows(i),Cols(Rows(i):Rows(i+1)-1),j )
      IF ( k==0 ) RETURN
      k = k + Rows(i) - 1
    ELSE
      k = Diag(i)
    END IF
    Values(k) = Values(k) + value
  END SUBROUTINE CRS_AddToMatrixElement
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
  SUBROUTINE CRS_SetMatrixElement( A,i,j,value )
DLLEXPORT CRS_SetMatrixElement
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Set a given value to an element of a  CRS format matrix
!
!  ARGUMENTS:
!
!  TYPE(Matrix_t) :: A
!     INPUT: Structure holding matrix
!
!  INTEGER :: i,j
!     INPUT: row and column numbers, respectively, of the matrix element
!
!  REAL(KIND=dp) :: value
!     INPUT: Value to be set
!
!******************************************************************************
!------------------------------------------------------------------------------
    TYPE(Matrix_t), POINTER :: A
    INTEGER :: i,j
    REAL(KIND=dp) :: value

!------------------------------------------------------------------------------
!   Local variables
!------------------------------------------------------------------------------
 
    INTEGER :: k,n
    REAL(KIND=dp), POINTER :: Values(:)
    INTEGER, POINTER :: Cols(:),Rows(:),Diag(:)
!------------------------------------------------------------------------------

    Rows   => A % Rows
    Cols   => A % Cols
    Diag   => A % Diag
    Values => A % Values

    IF ( i /= j .OR. .NOT. A % Ordered ) THEN
       k = CRS_Search( Rows(i+1)-Rows(i),Cols(Rows(i):Rows(i+1)-1),j )
      IF ( k==0 ) RETURN
       k = k + Rows(i) - 1
    ELSE
       k = Diag(i)
    END IF
    Values(k) = value
  END SUBROUTINE CRS_SetMatrixElement
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
  SUBROUTINE CRS_GlueLocalMatrix( A,N,Dofs,Indeces,LocalMatrix )
DLLEXPORT CRS_GlueLocalMatrix
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Add a set of values (.i.e. element stiffness matrix) to a CRS format
!    matrix. 
!
!  ARGUMENTS:
!
!  TYPE(Matrix_t), POINTER :: A
!     INOUT: Structure holding matrix, values are affected in the process
!
!  INTEGER :: N
!     INPUT: Number of nodes in element
!
!  INTEGER :: Dofs
!     INPUT: Number of degrees of freedom for one node
!
!  INTEGER :: Indeces
!     INPUT: Maps element node numbers to global (or partition) node numbers
!            (to matrix rows and columns, if Dofs = 1)
!
!  REAL(KIND=dp) :: LocalMatrix(:,:)
!     INPUT: A (N x Dofs) x ( N x Dofs) matrix holding the values to be
!            added to the CRS format matrix
!          
!
!******************************************************************************
!------------------------------------------------------------------------------
 
     REAL(KIND=dp) :: LocalMatrix(:,:)
     TYPE(Matrix_t), POINTER :: A
     INTEGER :: N,Dofs,Indeces(:)

!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------
 
     INTEGER :: i,j,k,l,c,Row,Col
 
     INTEGER, POINTER :: Cols(:),Rows(:)
     REAL(KIND=dp), POINTER :: Values(:)

!------------------------------------------------------------------------------

     Rows   => A % Rows
     Cols   => A % Cols
     Values => A % Values

     DO i=1,N
        DO k=0,Dofs-1
           Row = Dofs * Indeces(i) - k
           DO j=1,N
              DO l=0,Dofs-1
                 Col = Dofs * Indeces(j) - l
                 DO c=Rows(Row),Rows(Row+1)-1
                    IF ( Cols(c) == Col ) THEN
                       Values(c) = Values(c) + LocalMatrix(Dofs*i-k,Dofs*j-l)
                       EXIT
                    END IF
                 END DO
              END DO
           END DO
       END DO
     END DO

  END SUBROUTINE CRS_GlueLocalMatrix
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
  SUBROUTINE CRS_SetSymmDirichlet( A,b,n,s )
DLLEXPORT CRS_SetSymmDirichlet
!------------------------------------------------------------------------------
    TYPE(Matrix_t), POINTER :: A
    INTEGER :: n
    REAL(KIND=dp) :: b(:),s
!------------------------------------------------------------------------------
    INTEGER :: i,j,k,k1,k2
    REAL(KIND=dp) :: t

    t = A % Values(A % Diag(n))

    DO i = MAX(n-A % Subband,1), MIN(n+A % Subband,A % NumberOfRows)
       IF ( i == n ) CYCLE

       k1 = A % Rows(i)
       k2 = A % Rows(i+1)-1

       IF ( k1 <= 0 .OR. k2 <= 0 ) CYCLE
       IF ( k1 > SIZE(A % Cols) .OR. k2 > SIZE(A % Cols) ) CYCLE

       IF ( A % Cols(k1) > n ) CYCLE
       IF ( A % Cols(k2) < n ) CYCLE

       k = k2 - k1 + 1
       IF ( k <= 30 ) THEN
          DO j = k1, k2
             IF ( A % Cols(j) == n ) THEN
                b(i) = b(i) - A % Values(j) * s
                A % Values(j) = 0.0_dp
                EXIT
             ELSE IF ( A % Cols(j) > n ) THEN
                EXIT
             END IF
          END DO
       ELSE
          j = CRS_Search( k,A % Cols(k1:k2),n )
          IF ( j > 0 ) THEN
             j = j + k1 - 1
             b(i) = b(i) - A % Values(j) * s
             A % Values(j) = 0.0_dp
          END IF
       END IF
    END DO

    b(n) = s * t
    CALL CRS_ZeroRow( A,n )
    CALL CRS_SetMatrixElement( A,n,n,t )
!------------------------------------------------------------------------------
  END SUBROUTINE CRS_SetSymmDirichlet
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
FUNCTION CRS_RowSum( A,k ) RESULT(rsum)
!------------------------------------------------------------------------------
DLLEXPORT CRS_RowSum
   TYPE(Matrix_t), POINTER :: A
   INTEGER :: i,k

   REAL(KIND=dp) :: rsum

   rsum = 0.0D0
   DO i=1,A % Rows(k), A % Rows(k+1)-1
     rsum  = rsum + A % Values( A % Cols(i) )
   END DO
!------------------------------------------------------------------------------
END FUNCTION CRS_RowSum
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
  FUNCTION CRS_CreateMatrix( N,Total,RowNonzeros,Ndeg,Reorder,AllocValues ) RESULT(A)
DLLEXPORT CRS_CreateMatrix
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Create the structures required for a CRS format matrix.
!
!  ARGUMENTS:
!
!  INTEGER :: N
!     INPUT: Number of rows for the matrix
!
!  INTEGER :: Total
!     INPUT: Total number of nonzero entries in the matrix
!
!  INTEGER :: RowNonzeros(:)
!     INPUT: Number of nonzero entries in rows of the matrix
!
!  INTEGER :: Reorder(:)
!     INPUT: Permutation index for bandwidth reduction
!
!  LOGICAL :: AllocValues
!     INPUT: Should the values arrays be allocated ?
!
!  FUNCTION RETURN VALUE:
!     TYPE(Matrix_t) :: A
!       Pointer to the created Matrix_t structure.
!
!******************************************************************************
!------------------------------------------------------------------------------
    INTEGER :: N,Total,Ndeg
    INTEGER :: RowNonzeros(:),Reorder(:)

    LOGICAL :: AllocValues

!------------------------------------------------------------------------------
    TYPE(Matrix_t), POINTER :: A

    INTEGER :: i,j,k,istat
    INTEGER, POINTER :: InvPerm(:)
!------------------------------------------------------------------------------

    A => AllocateMatrix()

    k = Ndeg*Ndeg*Total

    ALLOCATE( A % Rows(n+1),A % Diag(n),A % Cols(k),STAT=istat )

    IF ( istat == 0 .AND. AllocValues ) THEN
      ALLOCATE( A % Values(k), STAT=istat )
    END IF
    NULLIFY( A % ILUValues )
    NULLIFY( A % CILUValues )

    IF ( istat /= 0 ) THEN
      CALL Fatal( 'CreateMatrix', 'Memory allocation error.' )
    END IF

    InvPerm => A % Diag ! just available memory space...
    j = 0
    DO i=1,SIZE(Reorder)
       IF ( Reorder(i) > 0 ) THEN
          j = j + 1
          InvPerm(Reorder(i)) = j
       END IF
    END DO

    A % NumberOfRows = N
    A % Rows(1) = 1
    DO i=2,n
       j = InvPerm((i-2)/Ndeg+1)
       A % Rows(i) = A % Rows(i-1) + Ndeg*RowNonzeros(j)
    END DO
    j = InvPerm((n-1)/ndeg+1)
    A % Rows(n+1) = A % Rows(n)  +  Ndeg*RowNonzeros(j)

    A % Cols = 0
    A % Diag = 0

    A % SPMatrix = 0
    A % Ordered = .FALSE.
  END FUNCTION CRS_CreateMatrix
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
  SUBROUTINE CRS_PrintMatrix( A )
DLLEXPORT CRS_PrintMatrix
!------------------------------------------------------------------------------
    TYPE(Matrix_t) :: A

    INTEGER :: i,j,k

    DO i=1,A % NumberOfRows
      DO j=A % Rows(i),A % Rows(i+1)-1
        WRITE(1,*) i,A % Cols(j),A % Values(j)
      END DO

    END DO

  END SUBROUTINE CRS_PrintMatrix
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
  SUBROUTINE CRS_MatrixVectorMultiply( A,u,v )
DLLEXPORT CRS_MatrixVectorMultiply
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Matrix vector product (v = Au) for a matrix given in CRS format.
!
!  ARGUMENTS:
!
!    TYPE(Matrix_t), POINTER :: A
!    REAL(KIND=dp) :: u(*),v(*)
!
!******************************************************************************
!------------------------------------------------------------------------------

    REAL(KIND=dp), DIMENSION(*) :: u,v
    TYPE(Matrix_t), POINTER :: A

!------------------------------------------------------------------------------
     INTEGER, POINTER :: Cols(:),Rows(:)
     REAL(KIND=dp), POINTER :: Values(:)

     INTEGER :: i,j,n
     REAL(KIND=dp) :: rsum
!------------------------------------------------------------------------------

     n = A % NumberOfRows
     Rows   => A % Rows
     Cols   => A % Cols
     Values => A % Values

     DO i=1,n
        rsum = 0.0d0
        DO j=Rows(i),Rows(i+1)-1
           rsum = rsum + u(Cols(j)) * Values(j)
        END DO
        v(i) = rsum
     END DO
!------------------------------------------------------------------------------
  END SUBROUTINE CRS_MatrixVectorMultiply
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE CRS_ComplexMatrixVectorMultiply( A,u,v )
DLLEXPORT CRS_ComplexMatrixVectorMultiply
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Matrix vector product (v = Au) for a matrix given in CRS format.
!
!  ARGUMENTS:
!
!    TYPE(Matrix_t), POINTER :: A
!    COMPLEX(KIND=dp) :: u(*),v(*)
!
!******************************************************************************
!------------------------------------------------------------------------------

    COMPLEX(KIND=dp), DIMENSION(*) :: u,v
    TYPE(Matrix_t), POINTER :: A

!------------------------------------------------------------------------------
    INTEGER, POINTER :: Cols(:),Rows(:)
    REAL(KIND=dp), POINTER :: Values(:)

    INTEGER :: i,j,n
    COMPLEX(KIND=dp) :: s,rsum
!------------------------------------------------------------------------------
    n = A % NumberOfRows / 2
    Rows   => A % Rows
    Cols   => A % Cols
    Values => A % Values

    DO i=1,n
       rsum = DCMPLX( 0.0d0, 0.0d0 )
       DO j=Rows(2*i-1),Rows(2*i)-1,2
          s = DCMPLX( Values(j), -Values(j+1) )
          rsum = rsum + s * u((Cols(j)+1)/2)
       END DO
       v(i) = rsum
    END DO
!------------------------------------------------------------------------------
  END SUBROUTINE CRS_ComplexMatrixVectorMultiply
!------------------------------------------------------------------------------


!-------------------------------------------------------------------------------
  SUBROUTINE CRS_ApplyProjector( PMatrix, u, uperm, v, vperm, Trans )
DLLEXPORT CRS_ApplyProjector
!-------------------------------------------------------------------------------
    TYPE(Matrix_t), POINTER :: PMatrix
    REAL(KIND=dp) :: u(:),v(:)
    LOGICAL, OPTIONAL :: Trans
    INTEGER, POINTER :: uperm(:), vperm(:)
!-------------------------------------------------------------------------------
    INTEGER :: i,j,k,l,n
    REAL(KIND=dp), POINTER :: Values(:)
    LOGICAL :: LTrans
    INTEGER, POINTER :: Rows(:), Cols(:)
!-------------------------------------------------------------------------------
    LTrans = .FALSE.
    IF ( PRESENT( Trans ) ) LTrans = Trans

    n = PMatrix % NumberOfRows
    Rows   => PMatrix % Rows
    Cols   => PMatrix % Cols
    Values => PMatrix % Values

    v = 0.0d0
    IF ( ASSOCIATED( uperm ) .AND. ASSOCIATED( vperm ) ) THEN
       IF ( LTrans ) THEN
          DO i=1,n
             k = uperm(i)
             IF ( k > 0 ) THEN
                DO j=Rows(i),Rows(i+1)-1
                   l = vperm(Cols(j))
                   IF ( l > 0 ) v(l) = v(l) + u(k) * Values(j)
                END DO
             END IF
          END DO
       ELSE
          DO i=1,n
             l = vperm(i)
             IF ( l > 0 ) THEN
                DO j = Rows(i), Rows(i+1)-1
                   k = uperm(Cols(j))
                   IF ( k > 0 ) v(l) = v(l) + u(k) * Values(j)
                END DO
             END IF
          END DO
       END IF
    ELSE
       IF ( LTrans ) THEN
          DO i=1,n
             DO j=Rows(i),Rows(i+1)-1
                v(Cols(j)) = v(Cols(j)) + u(i) * Values(j)
             END DO
          END DO
       ELSE
          DO i=1,n
             DO j = Rows(i), Rows(i+1)-1
                v(i) = v(i) + u(Cols(j)) * Values(j)
             END DO
          END DO
       END IF
    END IF
!-------------------------------------------------------------------------------
  END SUBROUTINE CRS_ApplyProjector
!-------------------------------------------------------------------------------




!------------------------------------------------------------------------------
  SUBROUTINE CRS_DiagPrecondition( u,v,ipar )
DLLEXPORT CRS_DiagPrecondition
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Diagonal preconditioning of a CRS format matrix... Matrix is accessed
!    from a global variable GlobalMatrix.
!
!  ARGUMENTS:
!
!    REAL(KIND=dp) :: u,v
!
!    INTEGER :: ipar(:)
!      INPUT: structure holding info from (HUTIter-iterative solver package)
!
!******************************************************************************
!------------------------------------------------------------------------------
    REAL(KIND=dp), DIMENSION(*) :: u,v
    INTEGER, DIMENSION(*) :: ipar

    INTEGER :: i,j,n

    INTEGER, POINTER :: Cols(:),Rows(:),Diag(:)
    REAL(KIND=dp), POINTER :: ILUValues(:), Values(:)

    Diag   => GlobalMatrix % Diag
    Rows   => GlobalMatrix % Rows
    Cols   => GlobalMatrix % Cols
    Values => GlobalMatrix % Values

    n = GlobalMatrix % NumberOfRows

    IF ( .NOT. GlobalMatrix % Ordered ) THEN
       DO i=1,N
          CALL SortF( Rows(i+1)-Rows(i),Cols(Rows(i):Rows(i+1)-1), &
                   Values(Rows(i):Rows(i+1)-1) )
       END DO
       DO i=1,N
          DO j=Rows(i),Rows(i+1)-1
             IF ( Cols(j) == i ) THEN
                Diag(i) = j
                EXIT
             END IF
          END DO
       END DO
       GlobalMatrix % Ordered = .TRUE.
    END IF

    DO i=1,n
       IF  ( ABS( Values(Diag(i))) > AEPS ) THEN
           u(i) = v(i) / Values(Diag(i))
       ELSE
           u(i) = v(i)
       END IF
    END DO
!------------------------------------------------------------------------------
  END SUBROUTINE CRS_DiagPrecondition
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
  SUBROUTINE CRS_ComplexDiagPrecondition( u,v,ipar )
DLLEXPORT CRS_ComplexDiagPrecondition
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Diagonal preconditioning of a CRS format matrix... Matrix is accessed
!    from a global variable GlobalMatrix.
!
!  ARGUMENTS:
!
!    REAL(KIND=dp) :: u,v
!
!    INTEGER :: ipar(:)
!      INPUT: structure holding info from (HUTIter-iterative solver package)
!
!******************************************************************************
!------------------------------------------------------------------------------
    COMPLEX(KIND=dp), DIMENSION(*) :: u,v
    INTEGER, DIMENSION(*) :: ipar

    INTEGER :: i,j,n

    INTEGER, POINTER :: Cols(:),Rows(:),Diag(:)
    COMPLEX(KIND=dp) :: A
    REAL(KIND=dp), POINTER :: ILUValues(:), Values(:)

    Diag   => GlobalMatrix % Diag
    Rows   => GlobalMatrix % Rows
    Cols   => GlobalMatrix % Cols
    Values => GlobalMatrix % Values

    n = GlobalMatrix % NumberOfRows

    IF ( .NOT. GlobalMatrix % Ordered ) THEN
       DO i=1,N
          CALL SortF( Rows(i+1)-Rows(i),Cols(Rows(i):Rows(i+1)-1), &
                   Values(Rows(i):Rows(i+1)-1) )
       END DO

       DO i=1,N
          DO j=Rows(i),Rows(i+1)-1
             IF ( Cols(j) == i ) THEN
                Diag(i) = j
                EXIT
             END IF
          END DO
       END DO
       GlobalMatrix % Ordered = .TRUE.
    END IF

    DO i=1,n/2
       A = DCMPLX( Values(Diag(2*i-1)), -Values(Diag(2*i-1)+1) )
       u(i) = v(i) / A
    END DO
!------------------------------------------------------------------------------
  END SUBROUTINE CRS_ComplexDiagPrecondition
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
  FUNCTION CRS_IncompleteLU(A,ILUn) RESULT(Status)
    DLLEXPORT CRS_IncompleteLU
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Buids an incomplete (ILU(n)) factorization for a iterative solver
!    preconditioner. Real matrix version.
!
!  ARGUMENTS:
!
!    TYPE(Matrix_t) :: A
!      INOUT: Strcture holding input matrix, will also hold the factorization
!             on exit.
!
!    INTEGER :: N
!      INPUT: Order of fills allowed 0-9
!
!  FUNCTIN RETURN VALUE:
!    LOGICAL :: Status
!      Whether or not the factorization succeeded.
!
!******************************************************************************
!------------------------------------------------------------------------------
    TYPE(Matrix_t), POINTER :: A
    INTEGER :: ILUn
!------------------------------------------------------------------------------
    LOGICAL :: Status

    INTEGER :: i,j,k,l,m,n,istat

    INTEGER, POINTER :: Cols(:),Rows(:),Diag(:)
    REAL(KIND=dp), POINTER :: ILUValues(:), Values(:)

    REAL(KIND=dp) :: CPUTime, t

    LOGICAL, ALLOCATABLE :: C(:)
    REAL(KIND=dp), ALLOCATABLE ::  S(:)

    INTEGER, POINTER :: ILUCols(:),ILURows(:),ILUDiag(:)

    TYPE(Matrix_t), POINTER :: A1
!------------------------------------------------------------------------------
    WRITE(Message,'(a,i1,a)')  &
         'ILU(',ILUn,') (Real), Starting Factorization:'
    CALL Info( 'CRS_IncompleteLU', Message, Level = 5 )
    t = CPUTime()

    N = A % NumberOfRows
    Diag   => A % Diag
    Rows   => A % Rows
    Cols   => A % Cols
    Values => A % Values

    IF ( .NOT. ASSOCIATED(A % ILUValues) ) THEN
       IF ( ILUn == 0 ) THEN
          A % ILURows => A % Rows
          A % ILUCols => A % Cols
          A % ILUDiag => A % Diag
       ELSE
          CALL InitializeILU1( A,n )

          IF ( ILUn > 1 ) THEN
             ALLOCATE( A1 )

             DO i=1,ILUn-1
                A1 % Cols => A % ILUCols
                A1 % Rows => A % ILURows
                A1 % Diag => A % ILUDiag

                CALL InitializeILU1( A1,n )

                A % ILUCols => A1 % ILUCols
                A % ILURows => A1 % ILURows
                A % ILUDiag => A1 % ILUDiag

                DEALLOCATE( A1 % Cols, A1 % Rows, A1 % Diag )
             END DO

             DEALLOCATE(A1)
          END IF
       END IF

       ALLOCATE( A % ILUValues(A % ILURows(N+1)-1), STAT=istat )

       IF ( istat /= 0 ) THEN
         CALL Fatal( 'CRS_IncompleteLU', 'Memory allocation error.' )
       END IF
    END IF

    ILURows   => A % ILURows
    ILUCols   => A % ILUCols
    ILUDiag   => A % ILUDiag
    ILUValues => A % ILUValues
!
!   Allocate space for storing one full row:
!   ----------------------------------------
    ALLOCATE( C(n), S(n) )
    C = .FALSE.
    S =  0.0d0
!
!   The factorization row by row:
!   -----------------------------
    DO i=1,N
!
!      Convert current row to full form for speed,
!      only flagging the nonzero entries:
!      -------------------------------------------
       DO k=Rows(i), Rows(i+1)-1
          S(Cols(k)) = Values(k)
       END DO

       DO k = ILURows(i), ILURows(i+1)-1
          C(ILUCols(k)) = .TRUE.
       END DO
!
!      This is the factorization part for the current row:
!      ---------------------------------------------------
       DO k=ILUCols(ILURows(i)),i-1
          IF ( C(k) ) THEN
             IF ( ABS(ILUValues(ILUDiag(k))) > AEPS ) &
               S(k) = S(k) / ILUValues(ILUDiag(k)) 

             DO l = ILUDiag(k)+1, ILURows(k+1)-1
                j = ILUCols(l)
                IF ( C(j) ) THEN
                   S(j) = S(j) - S(k) * ILUValues(l)
                END IF
             END DO
          END IF
       END DO

!
!      Convert the row back to  CRS format:
!      ------------------------------------
       DO k=ILURows(i), ILURows(i+1)-1
          IF ( C(ILUCols(k)) ) THEN
             ILUValues(k)  = S(ILUCols(k))
             S(ILUCols(k)) =  0.0d0
             C(ILUCols(k)) = .FALSE.
          END IF
       END DO
    END DO

    DEALLOCATE( S, C )

!
!   Prescale the diagonal for the LU solve:
!   ---------------------------------------
    DO i=1,N
       IF ( ABS(ILUValues(ILUDiag(i))) < AEPS ) THEN
          ILUValues(ILUDiag(i)) = 1.0d0
       ELSE
          ILUValues(ILUDiag(i)) = 1.0d0 / ILUValues(ILUDiag(i))
       END IF
    END DO

!------------------------------------------------------------------------------
    WRITE(Message,'(a,i1,a,i9)') 'ILU(', ILUn, &
        ') (Real), NOF nonzeros: ',ILURows(n+1)
    CALL Info( 'CRS_IncompleteLU', Message, Level=5 )

    WRITE(Message,'(a,i1,a,i9)') 'ILU(', ILUn, &
        ') (Real), filling (%) : ',   &
         FLOOR(ILURows(n+1)*(100.0d0/Rows(n+1)))
    CALL Info( 'CRS_IncompleteLU', Message, Level=5 )

    WRITE(Message,'(A,I1,A,F8.2)') 'ILU(',ILUn, &
        ') (Real), Factorization ready at (s): ', CPUTime()-t
    CALL Info( 'CRS_IncompleteLU', Message, Level=5 )

    Status = .TRUE.
!------------------------------------------------------------------------------

  CONTAINS

!------------------------------------------------------------------------------
    SUBROUTINE InitializeILU1( A, n )
!------------------------------------------------------------------------------
      TYPE(Matrix_t), POINTER :: A
      INTEGER :: n

      INTEGER :: i,j,k,l,m,istat,RowMin,RowMax,Nonzeros

      INTEGER :: C(n)
      INTEGER, POINTER :: Cols(:),Rows(:),Diag(:), &
           ILUCols(:),ILURows(:),ILUDiag(:)
!------------------------------------------------------------------------------

      Diag => A % Diag
      Rows => A % Rows
      Cols => A % Cols

      ALLOCATE( A % ILURows(N+1),A % ILUDiag(N),STAT=istat )
      IF ( istat /= 0 ) THEN
         CALL Fatal( 'CRS_IncompleteLU', 'Memory allocation error.' )
      END IF

      ILURows => A % ILURows
      ILUDiag => A % ILUDiag
!
!     Count fills, row by row:
!     ------------------------
      NonZeros = Rows(N+1) - 1
      C = 0
      DO i=1,n
         DO k=Rows(i), Rows(i+1)-1
            C(Cols(k)) = 1
         END DO

         DO k = Cols(Rows(i)), i-1
            IF ( C(k) /= 0 ) THEN
               DO l=Diag(k)+1, Rows(k+1)-1
                  j = Cols(l)
                  IF ( C(j) == 0 ) Nonzeros = Nonzeros + 1
               END DO
            END IF
         END DO

         DO k = Rows(i), Rows(i+1)-1
            C(Cols(k)) = 0
         END DO
      END DO

!------------------------------------------------------------------------------

      ALLOCATE( A % ILUCols(Nonzeros),STAT=istat )
      IF ( istat /= 0 ) THEN
         CALL Fatal( 'CRS_IncompleteLU', 'Memory allocation error.' )
      END IF
      ILUCols => A % ILUCols

!------------------------------------------------------------------------------

!
!     Update row nonzero structures: 
!     ------------------------------
      C = 0
      ILURows(1) = 1
      DO i=1,n
         DO k=Rows(i), Rows(i+1)-1
            C(Cols(k)) = 1
         END DO

         RowMin = Cols(Rows(i))
         RowMax = Cols(Rows(i+1)-1)

         DO k=RowMin, i-1
            IF ( C(k) == 1 ) THEN
               DO l=Diag(k)+1,Rows(k+1)-1
                  j = Cols(l)
                  IF ( C(j) == 0 ) THEN
                     C(j) = 2
                     RowMax = MAX( RowMax, j )
                  END IF
               END DO
            END IF
         END DO

         j = ILURows(i) - 1
         DO k = RowMin, RowMax 
            IF ( C(k) > 0 ) THEN
               j = j + 1
               C(k) = 0
               ILUCols(j) = k
               IF ( k == i ) ILUDiag(i) = j
            END IF
         END DO
         ILURows(i+1) = j + 1
      END DO
!------------------------------------------------------------------------------
    END SUBROUTINE InitializeILU1
!------------------------------------------------------------------------------
!------------------------------------------------------------------------------
  END FUNCTION CRS_IncompleteLU
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  FUNCTION CRS_ComplexIncompleteLU(A,ILUn) RESULT(Status)
    DLLEXPORT CRS_ComplexIncompleteLU
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Buids an incomplete (ILU(n)) factorization for an iterative solver
!    preconditioner. Complex matrix version.
!
!  ARGUMENTS:
!
!    TYPE(Matrix_t) :: A
!      INOUT: Strcture holding input matrix, will also hold the factorization
!             on exit.
!
!    INTEGER :: N
!      INPUT: Order of fills allowed 0-9
!
!  FUNCTIN RETURN VALUE:
!    LOGICAL :: Status
!      Whether or not the factorization succeeded.
!
!******************************************************************************
!------------------------------------------------------------------------------
    TYPE(Matrix_t), POINTER :: A
    INTEGER :: ILUn
!------------------------------------------------------------------------------

    LOGICAL :: Status

    INTEGER :: i,j,k,l,m,n,istat

    INTEGER, POINTER :: Cols(:),Rows(:),Diag(:)
    REAL(KIND=dp), POINTER ::  Values(:)
    COMPLEX(KIND=dp), POINTER :: ILUValues(:)

    INTEGER, POINTER :: ILUCols(:),ILURows(:),ILUDiag(:)

    TYPE(Matrix_t), POINTER :: A1

    REAL(KIND=dp) :: t, CPUTime

    LOGICAL, ALLOCATABLE :: C(:)
    COMPLEX(KIND=dp), ALLOCATABLE :: S(:)
!------------------------------------------------------------------------------

    WRITE(Message,'(a,i1,a)') 'ILU(',ILUn,') (Complex), Starting Factorization:'
    CALL Info( 'CRS_ComplexIncompleteLU', Message, Level=5 )
    t = CPUTime()

    N = A % NumberOfRows
    Diag   => A % Diag
    Rows   => A % Rows
    Cols   => A % Cols
    Values => A % Values

    IF ( .NOT.ASSOCIATED(A % CILUValues) ) THEN

       ALLOCATE( A1 )
       A1 % NumberOfRows = N / 2

       ALLOCATE( A1 % Rows(n/2+1) )
       ALLOCATE( A1 % Diag(n/2) )
       ALLOCATE( A1 % Cols(SIZE(A % Cols) / 4) )

       A1 % Rows(1) = 1
       k = 0
       DO i=1,n,2
          DO j=A % Rows(i),A % Rows(i+1)-1,2
             k = k + 1
             A1 % Cols(k) = (A % Cols(j)+1) / 2
             IF ( A % Cols(j) == i ) A1 % Diag((i+1)/2) = k
          END DO
          A1 % Rows((i+1)/2+1) = k+1
       END DO

       IF ( ILUn == 0 ) THEN
          A % ILUCols => A1 % Cols
          A % ILURows => A1 % Rows
          A % ILUDiag => A1 % Diag
       ELSE
          CALL InitializeComplexILU1( A1, n/2 )

          A % ILUCols => A1 % ILUCols
          A % ILURows => A1 % ILURows
          A % ILUDiag => A1 % ILUDiag

          DEALLOCATE( A1 % Cols,A1 % Rows,A1 % Diag )
       END IF

       DEALLOCATE( A1 )

       IF ( ILUn > 1 ) THEN
          ALLOCATE( A1 )
          A1 % NumberOfRows = N / 2

          DO i=1,ILUn-1
             A1 % Cols => A % ILUCols
             A1 % Rows => A % ILURows
             A1 % Diag => A % ILUDiag

             CALL InitializeComplexILU1( A1, n/2 )

             A % ILUCols => A1 % ILUCols
             A % ILURows => A1 % ILURows
             A % ILUDiag => A1 % ILUDiag

             DEALLOCATE( A1 % Cols,A1 % Rows,A1 % Diag )
          END DO

          DEALLOCATE(A1)
       END IF

       ALLOCATE( A % CILUValues(A % ILURows(N/2+1)),STAT=istat )

       IF ( istat /= 0 ) THEN
          CALL Fatal( 'CRS_ComplexIncompleteLU', 'Memory allocation error.' )
       END IF
    END IF

    ILURows   => A % ILURows
    ILUCols   => A % ILUCols
    ILUDiag   => A % ILUDiag
    ILUValues => A % CILUValues

!
!   Allocate space for storing one full row:
!   ----------------------------------------
    ALLOCATE( C(n/2), S(n/2) )
    C = .FALSE.
    S =  0.0d0
!
!   The factorization row by row:
!   -----------------------------
    DO i=1,N/2
!
!      Convert the current row to full form for speed,
!      only flagging the nonzero entries:
!      -----------------------------------------------
       DO k = ILURows(i), ILURows(i+1)-1
          C(ILUCols(k)) = .TRUE.
       END DO

       DO k = Rows(2*i-1), Rows(2*i)-1,2
          S((Cols(k)+1)/2) = DCMPLX( Values(k), -Values(k+1) )
       END DO

!
!      This is the factorization part for the current row:
!      ---------------------------------------------------
       DO k=ILUCols(ILURows(i)),i-1
          IF ( C(k) ) THEN
             IF ( ABS(ILUValues(ILUDiag(k))) > AEPS ) &
               S(k) = S(k) / ILUValues(ILUDiag(k)) 

             DO l = ILUDiag(k)+1, ILURows(k+1)-1
                j = ILUCols(l)
                IF ( C(j) ) THEN
                   S(j) = S(j) - S(k) * ILUValues(l)
                END IF
             END DO
          END IF
       END DO

!
!      Convert the row back to  CRS format:
!      ------------------------------------
       DO k=ILURows(i), ILURows(i+1)-1
          IF ( C(ILUCols(k)) ) THEN
             ILUValues(k)  = S(ILUCols(k))
             S(ILUCols(k)) =  0.0d0
             C(ILUCols(k)) = .FALSE.
          END IF
       END DO
    END DO

    DEALLOCATE( S, C )

!
!   Prescale the diagonal for the LU solve:
!   ---------------------------------------
    DO i=1,n/2
       IF ( ABS(ILUValues(ILUDiag(i))) < AEPS ) THEN
          ILUValues(ILUDiag(i)) = 1.0d0
       ELSE
          ILUValues(ILUDiag(i)) = 1.0d0 / ILUValues(ILUDiag(i))
       END IF
    END DO

!------------------------------------------------------------------------------

    WRITE(Message,'(a,i1,a,i9)') 'ILU(', ILUn, &
        ') (Complex), NOF nonzeros: ',ILURows(n/2+1)
    CALL Info( 'CRS_ComplexIncompleteLU', Message, Level=5 )

    WRITE(Message,'(a,i1,a,i9)') 'ILU(', ILUn, &
        ') (Complex), filling (%) : ',   &
         FLOOR(ILURows(n/2+1)*(400.0d0/Rows(n+1)))
    CALL Info( 'CRS_ComplexIncompleteLU', Message, Level=5 )

    WRITE(Message,'(A,I1,A,F8.2)') 'ILU(',ILUn, &
        ') (Complex), Factorization ready at (s): ', CPUTime()-t
    CALL Info( 'CRS_ComplexIncompleteLU', Message, Level=5 )

    Status = .TRUE.
!------------------------------------------------------------------------------

  CONTAINS

!------------------------------------------------------------------------------
    SUBROUTINE InitializeComplexILU1( A, n )
!------------------------------------------------------------------------------
      TYPE(Matrix_t), POINTER :: A
      INTEGER :: n

      INTEGER :: i,j,k,l,m,istat,RowMin,RowMax,Nonzeros

      INTEGER :: C(n)
      INTEGER, POINTER :: Cols(:),Rows(:),Diag(:), &
           ILUCols(:),ILURows(:),ILUDiag(:)
!------------------------------------------------------------------------------

      Diag => A % Diag
      Rows => A % Rows
      Cols => A % Cols

      ALLOCATE( A % ILURows(N+1),A % ILUDiag(N),STAT=istat )
      IF ( istat /= 0 ) THEN
         CALL Fatal( 'CRS_ComplexIncompleteLU', 'Memory allocation error.' )
      END IF

      ILURows => A % ILURows
      ILUDiag => A % ILUDiag

!
!     Count fills, row by row:
!     ------------------------
      NonZeros = Rows(N+1) - 1
      C = 0
      DO i=1,n
         DO k=Rows(i), Rows(i+1)-1
            C(Cols(k)) = 1
         END DO

         DO k = Cols(Rows(i)), i-1
            IF ( C(k) /= 0 ) THEN
               DO l=Diag(k)+1, Rows(k+1)-1
                  j = Cols(l)
                  IF ( C(j) == 0 ) Nonzeros = Nonzeros + 1
               END DO
            END IF
         END DO

         DO k = Rows(i), Rows(i+1)-1
            C(Cols(k)) = 0
         END DO
      END DO

!------------------------------------------------------------------------------

      ALLOCATE( A % ILUCols(Nonzeros),STAT=istat )
      IF ( istat /= 0 ) THEN
         CALL Fatal( 'CRS_ComplexIncompleteLU', 'Memory allocation error.' )
      END IF
      ILUCols => A % ILUCols

!------------------------------------------------------------------------------

!
!     Update row nonzero structures: 
!     ------------------------------
      C = 0
      ILURows(1) = 1
      DO i=1,n
         DO k=Rows(i), Rows(i+1)-1
            C(Cols(k)) = 1
         END DO

         RowMin = Cols(Rows(i))
         RowMax = Cols(Rows(i+1)-1)

         DO k=RowMin, i-1
            IF ( C(k) == 1 ) THEN
               DO l=Diag(k)+1,Rows(k+1)-1
                  j = Cols(l)
                  IF ( C(j) == 0 ) THEN
                     C(j) = 2
                     RowMax = MAX( RowMax, j )
                  END IF
               END DO
            END IF
         END DO

         j = ILURows(i) - 1
         DO k = RowMin, RowMax 
            IF ( C(k) > 0 ) THEN
               j = j + 1
               C(k) = 0
               ILUCols(j) = k
               IF ( k == i ) ILUDiag(i) = j
            END IF
         END DO
         ILURows(i+1) = j + 1
      END DO
!------------------------------------------------------------------------------
    END SUBROUTINE InitializeComplexILU1
!------------------------------------------------------------------------------
!------------------------------------------------------------------------------
  END FUNCTION CRS_ComplexIncompleteLU
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  FUNCTION CRS_ILUT(A,TOL) RESULT(Status)
    DLLEXPORT CRS_ILUT
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Buids an incomplete (ILUT) factorization for an iterative solver
!    preconditioner. Real matrix version.
!
!  ARGUMENTS:
!
!    TYPE(Matrix_t) :: A
!      INOUT: Strcture holding input matrix, will also hold the factorization
!             on exit.
!
!    REAL :: TOL
!      INPUT: Drop toleranece: if ILUT(i,j) <= NORM(A(i,:))*TOL the value
!             is dropped.
!
!  FUNCTIN RETURN VALUE:
!    LOGICAL :: Status
!      Whether or not the factorization succeeded.
!
!******************************************************************************
!------------------------------------------------------------------------------
    TYPE(Matrix_t), POINTER :: A
    REAL(KIND=dp) :: TOL
!------------------------------------------------------------------------------
    LOGICAL :: Status
    INTEGER :: istat,n
    REAL(KIND=dp) :: CPUTime, t
!------------------------------------------------------------------------------

    CALL Info( 'CRS_ILUT', 'Starting factorization:', Level=5 )
    t = CPUTime()

    n = A % NumberOfRows

    IF ( ASSOCIATED( A % ILUValues ) ) THEN
       DEALLOCATE( A % ILURows, A % ILUDiag, A % ILUCols, A % ILUValues )
    END IF
!
!   ... and then to the point:
!   --------------------------
    CALL ComputeILUT( A, n, TOL )
! 
    WRITE( Message, * ) 'ILU(T) (Real), NOF nonzeros: ',A % ILURows(N+1)
    CALL Info( 'CRS_ILUT', Message, Level=5 )
    WRITE( Message, * ) 'ILU(T) (Real), filling (%): ', &
         FLOOR(A % ILURows(N+1)*(100.0d0/A % Rows(N+1)))
    CALL Info( 'CRS_ILUT', Message, Level=5 )
    WRITE(Message,'(A,F8.2)') 'ILU(T) (Real), Factorization ready at (s): ', CPUTime()-t
    CALL Info( 'CRS_ILUT', Message, Level=5 )

    Status = .TRUE.
!------------------------------------------------------------------------------

  CONTAINS

!------------------------------------------------------------------------------
    SUBROUTINE ComputeILUT( A,n,TOL )
!------------------------------------------------------------------------------
      REAL(KIND=dp) :: TOL
      INTEGER :: n
      TYPE(Matrix_t), POINTER :: A
!------------------------------------------------------------------------------
      INTEGER, PARAMETER :: WORKN = 128

      INTEGER :: i,j,k,l,m,istat, RowMin, RowMax
      REAL(KIND=dp) :: NORMA

      INTEGER(KIND=AddrInt) :: Memsize

      REAL(KIND=dp), POINTER :: Values(:), ILUValues(:), CWork(:)

      INTEGER, POINTER :: Cols(:), Rows(:), Diag(:), &
           ILUCols(:), ILURows(:), ILUDiag(:), IWork(:)

      LOGICAL :: C(n)
      REAL(KIND=dp) :: S(n), CPUTime, cptime, ttime, t
!------------------------------------------------------------------------------

      ttime  = CPUTime()
      cptime = 0.0d0

      Diag => A % Diag
      Rows => A % Rows
      Cols => A % Cols
      Values => A % Values

      ALLOCATE( A % ILURows(N+1),A % ILUDiag(N),STAT=istat )
      IF ( istat /= 0 ) THEN
         CALL Fatal( 'CRS_ILUT', 'Memory allocation error.' )
      END IF

      ILURows => A % ILURows
      ILUDiag => A % ILUDiag

      ALLOCATE( ILUCols( WORKN*N ),  ILUValues( WORKN*N ), STAT=istat )
      IF ( istat /= 0 ) THEN
         CALL Fatal( 'CRS_ILUT', 'Memory allocation error.' )
      END IF
!
!     The factorization row by row:
!     -----------------------------
      ILURows(1) = 1
      S =  0.0d0
      C = .FALSE.

      DO i=1,n
!
!        Convert the current row to full form for speed,
!        only flagging the nonzero entries:
!        -----------------------------------------------
         DO k=Rows(i), Rows(i+1) - 1
            C(Cols(k)) = .TRUE.
            S(Cols(k)) = Values(k)
         END DO
!
!        Check bandwidth for speed, bandwidth optimization
!        helps here ALOT, use it!
!        -------------------------------------------------
         RowMin = Cols(Rows(i))
         RowMax = Cols(Rows(i+1)-1)
!
!        Here is the factorization part for the current row:
!        ---------------------------------------------------
         DO k=RowMin,i-1
            IF ( C(k) ) THEN
               IF ( ABS(ILUValues(ILUDiag(k))) > AEPS ) &
                 S(k) = S(k) / ILUValues(ILUDiag(k)) 
              
               DO l=ILUDiag(k)+1, ILURows(k+1)-1
                  j = ILUCols(l)
                  IF ( .NOT. C(j) ) THEN
                     C(j) = .TRUE.
                     RowMax = MAX( RowMax,j )
                  END IF
                  S(j) = S(j) - S(k) * ILUValues(l)
               END DO
            END IF
         END DO
!
!        This is the ILUT part, drop element ILU(i,j), if
!        ABS(ILU(i,j)) <= NORM(A(i,:))*TOL:
!        -------------------------------------------------
         NORMA = SQRT( SUM( ABS(Values(Rows(i):Rows(i+1)-1))**2 ) )

         j = ILURows(i)-1
         DO k=RowMin, RowMax
            IF ( C(k) ) THEN
               IF ( ABS(S(k)) >= TOL*NORMA .OR. k==i ) THEN
                  j = j + 1
                  ILUCols(j)   = k
                  ILUValues(j) = S(k)
                  IF ( k == i ) ILUDiag(i) = j
               END IF
               S(k) =  0.0d0
               C(k) = .FALSE.
            END IF
         END DO
         ILURows(i+1) = j + 1
!
!        Preparations for the next row:
!        ------------------------------
         IF ( i < N ) THEN
!
!           Check if still enough workspace:
!           --------------------------------
            IF ( SIZE(ILUCols) < ILURows(i+1) + N ) THEN

               t = CPUTime()
!              k = ILURows(i+1) + MIN( WORKN, n-i ) * n
               k = ILURows(i+1) + MIN( 0.75d0*ILURows(i+1), (n-i)*(1.0d0*n) )
               ALLOCATE( IWork(k), STAT=istat )
               IF ( istat /= 0 ) THEN
                  CALL Fatal( 'CRS_ILUT', 'Memory allocation error.' )
               END IF
               IWork( 1:ILURows(i+1)-1 ) = ILUCols( 1:ILURows(i+1)-1 )
               DEALLOCATE( ILUCols )

               ALLOCATE( CWork(k), STAT=istat )
               IF ( istat /= 0 ) THEN
                  CALL Fatal( 'CRS_ILUT', 'Memory allocation error.' )
               END IF
               CWork( 1:ILURows(i+1)-1 ) = ILUValues( 1:ILURows(i+1)-1 )
               DEALLOCATE( ILUValues )

               ILUCols   => IWork
               ILUValues => CWork
               NULLIFY( IWork, CWork )
               cptime = cptime + ( CPUTime() - t )
!              PRINT*,'tot: ', CPUTime()-ttime, 'copy: ', cptime
            END IF
         END IF
      END DO
!
!     Prescale the diagonal for the LU solve:
!     ---------------------------------------
      DO i=1,n
         IF ( ABS(ILUValues(ILUDiag(i))) < AEPS ) THEN
            ILUValues(ILUDiag(i)) = 1.0d0
         ELSE
            ILUValues(ILUDiag(i)) = 1.0d0 / ILUValues(ILUDiag(i))
         END IF
      END DO

      A % ILUCols   => ILUCols
      A % ILUValues => ILUValues
!------------------------------------------------------------------------------
    END SUBROUTINE ComputeILUT
!------------------------------------------------------------------------------
  END FUNCTION CRS_ILUT
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
  FUNCTION CRS_ComplexILUT(A,TOL) RESULT(Status)
    DLLEXPORT CRS_ComplexILUT
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Buids an incomplete (ILUT) factorization for an iterative solver
!    preconditioner. Complex matrix version.
!
!  ARGUMENTS:
!
!    TYPE(Matrix_t) :: A
!      INOUT: Strcture holding input matrix, will also hold the factorization
!             on exit.
!
!    REAL :: TOL
!      INPUT: Drop toleranece: if ABS(ILUT(i,j)) <= NORM(A(i,:))*TOL the value
!             is dropped.
!
!  FUNCTIN RETURN VALUE:
!    LOGICAL :: Status
!      Whether or not the factorization succeeded.
!
!******************************************************************************
!------------------------------------------------------------------------------
    TYPE(Matrix_t), POINTER :: A
    REAL(KIND=dp) :: TOL
!------------------------------------------------------------------------------
    INTEGER :: n, istat
    LOGICAL :: Status
    REAL(KIND=dp) :: CPUTime, t
!------------------------------------------------------------------------------

    CALL Info( 'CRS_ComplexILUT', 'ILU(T) (Complex), Starting factorization: ', Level=5 )
    t = CPUTime()

    n = A % NumberOfRows / 2

    IF ( ASSOCIATED( A % CILUValues ) ) THEN
       DEALLOCATE( A % ILURows, A % ILUCols, A % ILUDiag, A % CILUValues )
    END IF
!
!   ... and then to the point:
!   --------------------------
    CALL ComplexComputeILUT( A, n, TOL )
 
!------------------------------------------------------------------------------
    
    WRITE( Message, * ) 'ILU(T) (Complex), NOF nonzeros: ',A % ILURows(n+1)
    CALL Info( 'CRS_ComplexILUT', Message, Level=5 )
    WRITE( Message, * ) 'ILU(T) (Complex), filling (%): ', &
         FLOOR(A % ILURows(n+1)*(400.0d0/A % Rows(2*n+1)))
    CALL Info( 'CRS_ComplexILUT', Message, Level=5 )
    WRITE(Message,'(A,F8.2)') 'ILU(T) (Complex), Factorization ready at (s): ', CPUTime()-t
    CALL Info( 'CRS_ComplexILUT', Message, Level=5 )

    Status = .TRUE.
!------------------------------------------------------------------------------

  CONTAINS

!------------------------------------------------------------------------------
    SUBROUTINE ComplexComputeILUT( A,n,TOL )
!------------------------------------------------------------------------------
      REAL(KIND=dp) :: TOL
      INTEGER :: n
      TYPE(Matrix_t), POINTER :: A
!------------------------------------------------------------------------------
      INTEGER, PARAMETER :: WORKN = 128

      INTEGER :: i,j,k,l,m,istat,RowMin,RowMax
      REAL(KIND=dp) :: NORMA

      REAL(KIND=dp), POINTER :: Values(:)
      COMPLEX(KIND=dp), POINTER :: ILUValues(:), CWork(:)

      INTEGER, POINTER :: Cols(:), Rows(:), Diag(:), &
           ILUCols(:), ILURows(:), ILUDiag(:), IWork(:)

      LOGICAL :: C(n)
      COMPLEX(KIND=dp) :: S(n)
!------------------------------------------------------------------------------

      Diag => A % Diag
      Rows => A % Rows
      Cols => A % Cols
      Values => A % Values

      ALLOCATE( A % ILURows(n+1),A % ILUDiag(n),STAT=istat )
      IF ( istat /= 0 ) THEN
         CALL Fatal( 'CRS_ComplexILUT', 'Memory allocation error.' )
      END IF

      ILURows => A % ILURows
      ILUDiag => A % ILUDiag

      ALLOCATE( ILUCols( WORKN*N ),  ILUValues( WORKN*N ), STAT=istat )
      IF ( istat /= 0 ) THEN
         CALL Fatal( 'CRS_ComplexILUT', 'Memory allocation error.' )
      END IF
!
!     The factorization row by row:
!     -----------------------------
      ILURows(1) = 1
      C = .FALSE.
      S = DCMPLX( 0.0d0, 0.0d0 )

      DO i=1,n
!
!        Convert the current row to full form for speed,
!        only flagging the nonzero entries:
!        -----------------------------------------------
         DO k=Rows(2*i-1), Rows(2*i)-1,2
            C((Cols(k)+1) / 2) = .TRUE.
            S((Cols(k)+1) / 2) = DCMPLX( Values(k), -Values(k+1) )
         END DO
!
!        Check bandwidth for speed, bandwidth optimization
!        helps here ALOT, use it!
!        -------------------------------------------------
         RowMin = (Cols(Rows(2*i-1)) + 1) / 2
         RowMax = (Cols(Rows(2*i)-1) + 1) / 2
!
!        Here is the factorization part for the current row:
!        ---------------------------------------------------
         DO k=RowMin,i-1
            IF ( C(k) ) THEN
               IF ( ABS(ILUValues(ILUDiag(k))) > AEPS ) &
                 S(k) = S(k) / ILUValues(ILUDiag(k)) 
              
               DO l=ILUDiag(k)+1, ILURows(k+1)-1
                  j = ILUCols(l)
                  IF ( .NOT. C(j) ) THEN
                     C(j) = .TRUE.
                     RowMax = MAX( RowMax,j )
                  END IF
                  S(j) = S(j) - S(k) * ILUValues(l)
               END DO
            END IF
         END DO

!
!        This is the ILUT part, drop element ILUT(i,j), if
!        ABS(ILUT(i,j)) <= NORM(A(i,:))*TOL:
!        -------------------------------------------------
         NORMA = 0.0d0
         DO k = Rows(2*i-1), Rows(2*i)-1, 2
            NORMA = NORMA + Values(k)**2 + Values(k+1)**2
         END DO
         NORMA = SQRT(NORMA)

         j = ILURows(i)-1
         DO k=RowMin, RowMax
            IF ( C(k) ) THEN
               IF ( ABS(S(k)) > TOL*NORMA .OR. k==i ) THEN
                  j = j + 1
                  ILUCols(j)   = k
                  ILUValues(j) = S(k)
                  IF ( k == i ) ILUDiag(i) = j
               END IF
               C(k) = .FALSE.
               S(k) = DCMPLX( 0.0d0, 0.0d0 )
            END IF
         END DO
         ILURows(i+1) = j + 1
!
!        Preparations for the next row:
!        ------------------------------
         IF ( i < N ) THEN
!
!           Check if still enough workspace:
!           --------------------------------
            IF ( SIZE(ILUCols) < ILURows(i+1) + n ) THEN
!              k = ILURows(i+1) + MIN( WORKN, n-i ) * n
               k = ILURows(i+1) + MIN( 0.75d0*ILURows(i+1), (n-i)*(1.0d0*n) )

               ALLOCATE( IWork(k), STAT=istat )
               IF ( istat /= 0 ) THEN
                  CALL Fatal( 'CRS_ComplexILUT', 'Memory allocation error.' )
               END IF
               IWork( 1:ILURows(i+1)-1 ) = ILUCols( 1:ILURows(i+1)-1 )
               DEALLOCATE( ILUCols )

               ALLOCATE( CWork(k), STAT=istat )
               IF ( istat /= 0 ) THEN
                  CALL Fatal( 'CRS_ComplexILUT', 'Memory allocation error.' )
               END IF
               CWork( 1:ILURows(i+1)-1 ) = ILUValues( 1:ILURows(i+1)-1 )
               DEALLOCATE( ILUValues )

               ILUCols   => IWork
               ILUValues => CWork
            END IF
         END IF
      END DO
!
!     Prescale the diagonal for the LU solve:
!     ---------------------------------------
      DO i=1,n
         IF ( ABS(ILUValues(ILUDiag(i))) < AEPS ) THEN
            ILUValues(ILUDiag(i)) = 1.0d0
         ELSE
            ILUValues(ILUDiag(i)) = 1.0d0 / ILUValues(ILUDiag(i))
         END IF
      END DO

      A % ILUCols    => ILUCols
      A % CILUValues => ILUValues
      NULLIFY( ILUCols, ILUValues )
!------------------------------------------------------------------------------
    END SUBROUTINE ComplexComputeILUT
!------------------------------------------------------------------------------
  END FUNCTION CRS_ComplexILUT
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
  SUBROUTINE CRS_LUPrecondition( u,v,ipar )
    DLLEXPORT CRS_LUPrecondition
!------------------------------------------------------------------------------
!******************************************************************************
! 
!  DESCRIPTION:
!    Incomplete factorization preconditioner solver for a CRS format matrix.
!    Matrix is accessed from a global variable GlobalMatrix.
!
!  ARGUMENTS:
!
!    REAL(KIND=dp) :: u,v
!
!    INTEGER :: ipar(:)
!      INPUT: structure holding info from (HUTIter-iterative solver package)
!
!******************************************************************************
    INTEGER, DIMENSION(*) :: ipar
    REAL(KIND=dp), DIMENSION(HUTI_NDIM) :: u,v

    u = v
    CALL CRS_LUSolve( HUTI_NDIM,GlobalMatrix,u )
  END SUBROUTINE CRS_LUPrecondition
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
  SUBROUTINE CRS_ComplexLUPrecondition( u,v,ipar )
    DLLEXPORT CRS_ComplexLUPrecondition
!------------------------------------------------------------------------------
!******************************************************************************
! 
!  DESCRIPTION:
!    Incomplete factorization preconditioner solver for a CRS format matrix.
!    Matrix is accessed from a global variable GlobalMatrix.
!
!  ARGUMENTS:
!
!    REAL(KIND=dp) :: u,v
!
!    INTEGER :: ipar(:)
!      INPUT: structure holding info from (HUTIter-iterative solver package)
!
!******************************************************************************
    INTEGER, DIMENSION(*) :: ipar
    COMPLEX(KIND=dp), DIMENSION(HUTI_NDIM) :: u,v

    u = v
    CALL CRS_ComplexLUSolve( HUTI_NDIM,GlobalMatrix,u )
  END SUBROUTINE CRS_ComplexLUPrecondition
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
  SUBROUTINE CRS_LUSolve( N,A,b )
DLLEXPORT CRS_LUSolve
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Solve a system (Ax=b) after factorization A=LUD has been done. This
!    routine is meant as a part of  a preconditioner for an iterative solver.
!
!  ARGUMENTS:
!
!    INTEGER :: N
!      INPUT: Size of the system
!
!    TYPE(Matrix_t) :: A
!      INPUT: Structure holding input matrix
!
!    DOUBLE PRECISION :: b
!      INOUT: on entry the RHS vector, on exit the solution vector.
!
!******************************************************************************
!------------------------------------------------------------------------------
 
    TYPE(Matrix_t), POINTER :: A
    INTEGER :: N
    DOUBLE PRECISION :: b(N)

!------------------------------------------------------------------------------

    INTEGER :: i,j
    DOUBLE PRECISION :: s

    DOUBLE PRECISION, POINTER :: Values(:)
    INTEGER, POINTER :: Cols(:),Rows(:),Diag(:)

!------------------------------------------------------------------------------

    Diag => A % ILUDiag
    Rows => A % ILURows
    Cols => A % ILUCols
    Values => A % ILUValues

!
!   if no ilu provided do diagonal solve:
!   -------------------------------------
    IF ( .NOT. ASSOCIATED( Values ) ) THEN
       b = b / A % Values( A % Diag )
       RETURN
    END IF

!***********************************************************************
! The following #ifdefs  seem really necessery, if speed is an issue:
! SGI compiler optimizer  wants to know the sizes of the arrays very
! explicitely, while DEC compiler seems to make a copy of some of the
! arrays on the subroutine call (destroying performance).
!***********************************************************************
#ifndef SGI
    !
    ! Forward substitute (solve z from Lz = b)
    DO i=1,n
       s = b(i)
       DO j=Rows(i),Diag(i)-1
          s = s - Values(j) * b(Cols(j))
       END DO
       b(i) = s 
    END DO

    !
    ! Backward substitute (solve x from UDx = z)
    DO i=n,1,-1
       s = b(i)
       DO j=Diag(i)+1,Rows(i+1)-1
          s = s - Values(j) * b(Cols(j))
       END DO
       b(i) = Values(Diag(i)) * s
    END DO
#else
    CALL LUSolve( n,SIZE(Cols),Rows,Cols,Diag,Values,b )

  CONTAINS

    SUBROUTINE LUSolve( n,m,Rows,Cols,Diag,Values,b )
      INTEGER :: n,m,Rows(n+1),Cols(m),Diag(n)
      REAL(KIND=dp) :: Values(m),b(n)

      INTEGER :: i,j

      !
      ! Forward substitute (solve z from Lz = b)
      DO i=1,n
         DO j=Rows(i),Diag(i)-1
            b(i) = b(i) - Values(j) * b(Cols(j))
         END DO
      END DO

      !
      ! Backward substitute (solve x from UDx = z)
      DO i=n,1,-1
         DO j=Diag(i)+1,Rows(i+1)-1
            b(i) = b(i) - Values(j) * b(Cols(j))
         END DO
         b(i) = Values(Diag(i)) * b(i)
      END DO
    END SUBROUTINE LUSolve
#endif

  END SUBROUTINE CRS_LUSolve
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
  SUBROUTINE CRS_ComplexLUSolve( N,A,b )
DLLEXPORT CRS_ComplexLUSolve
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Solve a (complex9 system (Ax=b) after factorization A=LUD has been
!    done. This routine is meant as a part of  a preconditioner for an
!    iterative solver.
!
!  ARGUMENTS:
!
!    INTEGER :: N
!      INPUT: Size of the system
!
!    TYPE(Matrix_t) :: A
!      INPUT: Structure holding input matrix
!
!    DOUBLE PRECISION :: b
!      INOUT: on entry the RHS vector, on exit the solution vector.
!
!******************************************************************************
!------------------------------------------------------------------------------
 
    TYPE(Matrix_t), POINTER :: A
    INTEGER :: N
    COMPLEX(KIND=dp) :: b(N)

!------------------------------------------------------------------------------

    COMPLEX(KIND=dp), POINTER :: Values(:)
    INTEGER :: i,j
    COMPLEX(KIND=dp) :: x, s
    INTEGER, POINTER :: Cols(:),Rows(:),Diag(:)
    
!------------------------------------------------------------------------------

    Diag => A % ILUDiag
    Rows => A % ILURows
    Cols => A % ILUCols
    Values => A % CILUValues

!
!   if no ilu provided do diagonal solve:
!   -------------------------------------
    IF ( .NOT. ASSOCIATED( Values ) ) THEN
       Diag => A % Diag

       DO i=1,n/2
          x = DCMPLX( A % Values(Diag(2*i-1)), -A % Values(Diag(2*i-1)+1) )
          b(i) = b(i) / x
       END DO
       RETURN
    END IF

!***********************************************************************
! The following #ifdefs  seem really necessery, if speed is an issue:
! SGI compiler optimizer  wants to know the sizes of the arrays very
! explicitely, while DEC compiler seems to make a copy of some of the
! arrays on the subroutine call (destroying performance).
!***********************************************************************
#ifndef SGI
    !
    ! Forward substitute
    DO i=1,n
       s = b(i)
       DO j=Rows(i),Diag(i)-1
          s = s - Values(j) * b(Cols(j))
       END DO
       b(i) = s
    END DO

    !
    ! Backward substitute
    DO i=n,1,-1
       s = b(i)
       DO j=Diag(i)+1,Rows(i+1)-1
          s = s - Values(j) * b(Cols(j))
       END DO
       b(i) = Values(Diag(i)) * s
    END DO
#else
    CALL ComplexLUSolve( n,SIZE(Cols),Rows,Cols,Diag,Values,b )

  CONTAINS

    SUBROUTINE ComplexLUSolve( n,m,Rows,Cols,Diag,Values,b )
      INTEGER :: n,m,Rows(n+1),Cols(m),Diag(n)
      COMPLEX(KIND=dp) :: Values(m),b(n)

      INTEGER :: i,j

      !
      ! Forward substitute
      DO i=1,n
         DO j=Rows(i),Diag(i)-1
            b(i) = b(i) - Values(j) * b(Cols(j))
         END DO
      END DO

      !
      ! Backward substitute
      DO i=n,1,-1
         DO j=Diag(i)+1,Rows(i+1)-1
            b(i) = b(i) - Values(j) * b(Cols(j))
         END DO
         b(i) = Values(Diag(i)) * b(i)
      END DO
    END SUBROUTINE ComplexLUSolve
#endif

  END SUBROUTINE CRS_ComplexLUSolve
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
  SUBROUTINE CRS_MatrixVectorProd( u,v,ipar )
DLLEXPORT CRS_MatrixVectorProd
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Matrix vector product (v = Au) for a matrix given in CRS format. The
!    matrix is accessed from a global variable GlobalMatrix.
!
!  ARGUMENTS:
!
!    DOUBLE PRECISION :: u,v
!
!    INTEGER :: ipar(:)
!      INPUT: structure holding info from (HUTIter-iterative solver package)
!
!******************************************************************************
!------------------------------------------------------------------------------

    INTEGER, DIMENSION(*) :: ipar
    REAL(KIND=dp) :: u(HUTI_NDIM),v(HUTI_NDIM)

!------------------------------------------------------------------------------
    INTEGER, POINTER :: Cols(:),Rows(:)
    REAL(KIND=dp), POINTER :: Values(:)

    INTEGER :: i,j,n
    REAL(KIND=dp) :: s
!------------------------------------------------------------------------------

    n = GlobalMatrix % NumberOfRows
    Rows   => GlobalMatrix % Rows
    Cols   => GlobalMatrix % Cols
    Values => GlobalMatrix % Values

!***********************************************************************
! The following #ifdefs  seem really necessery, if speed is an issue:
! SGI compiler optimizer  wants to know the sizes of the arrays very
! explicitely, while DEC compiler seems to make a copy of some of the
! arrays on the subroutine call (destroying performance).
!***********************************************************************
#ifndef SGI
    IF ( HUTI_EXTOP_MATTYPE == HUTI_MAT_NOTTRPSED ) THEN
       DO i=1,n
          s = 0.0d0
          DO j=Rows(i),Rows(i+1)-1
             s = s + Values(j) * u(Cols(j))
          END DO
          v(i) = s
       END DO
    ELSE
       v(1:n) = 0.0d0
       DO i=1,n
          s = u(i)
          DO j=Rows(i),Rows(i+1)-1
             v(Cols(j)) = v(Cols(j)) + s * Values(j)
          END DO
       END DO
    END IF
#else
    CALL MatVec( n,SIZE(Cols),Rows,Cols,Values,u,v )

  CONTAINS

    SUBROUTINE MatVec( n,m,Rows,Cols,Values,u,v )
      INTEGER :: n,m
      INTEGER :: Rows(n+1),Cols(m)
      REAL(KIND=dp) :: Values(m),u(n),v(n)

      INTEGER :: i,j

      IF ( HUTI_EXTOP_MATTYPE == HUTI_MAT_NOTTRPSED ) THEN
         v(1:n) = 0.0d0
         DO i=1,n
            DO j=Rows(i),Rows(i+1)-1
               v(i) = v(i) + Values(j) * u(Cols(j))
            END DO
         END DO
      ELSE
         v(1:n) = 0.0d0
         DO i=1,n
            s = u(i)
            DO j=Rows(i),Rows(i+1)-1
               v(Cols(j)) = v(Cols(j)) + s * Values(j)
            END DO
         END DO
      END IF
    END SUBROUTINE MatVec
#endif

  END SUBROUTINE CRS_MatrixVectorProd
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
  SUBROUTINE CRS_ComplexMatrixVectorProd( u,v,ipar )
DLLEXPORT CRS_ComplexMatrixVectorProd
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Complex matrix vector product (v = Au) for a matrix given in
!    CRS format. The matrix is accessed from a global variable
!    GlobalMatrix.
!
!  ARGUMENTS:
!
!    DOUBLE PRECISION :: u,v
!
!    INTEGER :: ipar(:)
!      INPUT: structure holding info from (HUTIter-iterative solver package)
!
!******************************************************************************
!------------------------------------------------------------------------------

    INTEGER, DIMENSION(*) :: ipar
    COMPLEX(KIND=dp) :: u(HUTI_NDIM),v(HUTI_NDIM)

!------------------------------------------------------------------------------
    INTEGER, POINTER :: Cols(:),Rows(:)
    INTEGER :: i,j,n
    COMPLEX(KIND=dp) :: s,rsum
    REAL(KIND=dp), POINTER :: Values(:)
!------------------------------------------------------------------------------

    n = HUTI_NDIM
    Rows   => GlobalMatrix % Rows
    Cols   => GlobalMatrix % Cols
    Values => GlobalMatrix % Values

!***********************************************************************
! The following #ifdefs  seem really necessery, if speed is an issue:
! SGI compiler optimizer  wants to know the sizes of the arrays very
! explicitely, while DEC compiler seems to make a copy of some of the
! arrays on the subroutine call (destroying performance).
!***********************************************************************
#ifndef SGI
    IF ( HUTI_EXTOP_MATTYPE == HUTI_MAT_NOTTRPSED ) THEN
       DO i=1,n
          rsum = DCMPLX( 0.0d0, 0.0d0 )
          DO j=Rows(2*i-1),Rows(2*i)-1,2
             s = DCMPLX( Values(j), -Values(j+1) )
             rsum = rsum + s * u((Cols(j)+1)/2)
          END DO
          v(i) = rsum
       END DO
    ELSE
       v = DCMPLX( 0.0d0, 0.0d0 )
       DO i=1,n
          rsum = u(i)
          DO j=Rows(2*i-1),Rows(2*i)-1,2
             s = DCMPLX( Values(j), -Values(j+1) )
             v((Cols(j)+1)/2) = v((Cols(j)+1)/2) + s * rsum
          END DO
       END DO
    END IF
#else
    CALL ComplexMatVec( n,SIZE(Cols),Rows,Cols,Values,u,v )

  CONTAINS

    SUBROUTINE ComplexMatVec( n,m,Rows,Cols,Values,u,v )
      INTEGER :: n,m
      INTEGER :: Rows(2*n+1),Cols(m)
      REAL(KIND=dp) :: Values(m)
      COMPLEX(KIND=dp) :: u(n),v(n)

      INTEGER :: i,j
      COMPLEX(KIND=dp) :: s, rsum

      IF ( HUTI_EXTOP_MATTYPE == HUTI_MAT_NOTTRPSED ) THEN
         DO i=1,n
            rsum = DCMPLX( 0.0d0, 0.0d0 )
            DO j=Rows(2*i-1),Rows(2*i)-1,2
               s = DCMPLX( Values(j), -Values(j+1) )
               rsum = rsum + s * u((Cols(j)+1)/2)
            END DO
            v(i) = rsum
         END DO
      ELSE
         v = DCMPLX( 0.0d0, 0.0d0 )
         DO i=1,n
            rsum = u(i)
            DO j=Rows(2*i-1),Rows(2*i)-1,2
               s = DCMPLX( Values(j), -Values(j+1) )
               v((Cols(j)+1)/2) = v((Cols(j)+1)/2) + s * rsum
            END DO
         END DO
      END IF
    END SUBROUTINE ComplexMatVec
#endif

  END SUBROUTINE CRS_ComplexMatrixVectorProd
!------------------------------------------------------------------------------

END MODULE CRSMatrix
!------------------------------------------------------------------------------
