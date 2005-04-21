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
! * matrix in band matrix format.
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
! *                       Date: 01 Oct 1998
! *
! *                Modified by:
! *
! *       Date of modification:
! *
! ******************************************************************************/

MODULE SparseMatrix

  USE GeneralUtils

  IMPLICIT NONE

CONTAINS

!------------------------------------------------------------------------------
  SUBROUTINE Sparse_ZeroMatrix(A)
DLLEXPORT Sparse_ZeroMatrix
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Zero a Sparse format matrix
!
!  ARGUMENTS:
!
!  TYPE(Matrix_t) :: A
!     INPUT: Structure holding matrix
!
!******************************************************************************
!------------------------------------------------------------------------------
    TYPE(Matrix_t), POINTER :: A
!------------------------------------------------------------------------------
#ifdef USE_SPARSE
    CALL sfClear( A % SPMatrix )
#endif
!------------------------------------------------------------------------------
  END SUBROUTINE Sparse_ZeroMatrix
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE Sparse_ZeroRow( A,n )
DLLEXPORT Sparse_ZeroRow 
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Zero given row from a Sparse format matrix
!
!  ARGUMENTS:
!
!  TYPE(Matrix_t) :: A
!     INPUT: Structure holding matrix
!
!  INTEGER :: i
!     INPUT: Row number to be zerod
!
!******************************************************************************
!------------------------------------------------------------------------------
    TYPE(Matrix_t), POINTER :: A
    INTEGER :: n
!------------------------------------------------------------------------------
#ifdef USE_SPARSE
    CALL sfZeroRow( A % SPMatrix, n )
#endif
!------------------------------------------------------------------------------
  END SUBROUTINE Sparse_ZeroRow
!------------------------------------------------------------------------------
  

!------------------------------------------------------------------------------
  SUBROUTINE Sparse_AddToMatrixElement( A,i,j,value )
DLLEXPORT Sparse_AddToMatrixElement
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Add a given value to an element of a  Sparse format matrix
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
    INTEGER(KIND=AddrInt) :: sfGetElement
!------------------------------------------------------------------------------
#ifdef USE_SPARSE
    CALL sfAdd1Real( sfGetElement(A % SPMatrix,i,j), value )
#endif
!------------------------------------------------------------------------------
  END SUBROUTINE Sparse_AddToMatrixElement
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE Sparse_SetMatrixElement( A,i,j,value )
DLLEXPORT Sparse_SetMatrixElement
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Set a given value to an element of a  Sparse format matrix
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
    INTEGER(KIND=AddrInt) :: sfGetElement
!------------------------------------------------------------------------------
#ifdef USE_SPARSE
    CALL sfSet1Real( sfGetElement(A % SPMatrix,i,j), value )
#endif
!------------------------------------------------------------------------------
  END SUBROUTINE Sparse_SetMatrixElement
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE Sparse_GlueLocalMatrix( A,N,Dofs,Indeces,LocalMatrix )
DLLEXPORT Sparse_GlueLocalMatrix
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Add a set of values (.i.e. element stiffness matrix) to a Sparse format
!    matrix. 
!
!  ARGUMENTS:
!
!  TYPE(Matrix_t) :: A
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
!            added to the Sparse format matrix
!          
!
!******************************************************************************
!------------------------------------------------------------------------------
     REAL(KIND=dp) :: LocalMatrix(:,:)
     INTEGER :: N,Dofs,Indeces(:)
     TYPE(Matrix_t), POINTER :: A
!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------
     INTEGER :: i,j,k,l,Row,Col
!------------------------------------------------------------------------------
     DO i=1,N
       DO k=0,Dofs-1
         Row = Dofs * Indeces(i) - k
         DO j=1,N
           DO l=0,Dofs-1
             Col = Dofs * Indeces(j) - l
             CALL Sparse_AddToMatrixElement( A, Row, Col, &
                    LocalMatrix(Dofs*i-k,Dofs*j-l) )
           END DO
         END DO
       END DO
     END DO
!------------------------------------------------------------------------------
  END SUBROUTINE Sparse_GlueLocalMatrix
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
  FUNCTION Sparse_CreateMatrix( N ) RESULT(A)
DLLEXPORT Sparse_CreateMatrix
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Create the structures required for a Sparse format matrix.
!
!  ARGUMENTS:
!
!  INTEGER :: N
!     INPUT: Number of rows for the matrix
!
!  FUNCTION RETURN VALUE:
!     TYPE(Matrix_t) :: A
!       Pointer to the created Matrix_t structure.
!
!******************************************************************************
!------------------------------------------------------------------------------
    INTEGER :: N
!------------------------------------------------------------------------------
    TYPE(Matrix_t), POINTER :: A

    INTEGER :: istat
    INTEGER(KIND=AddrInt) :: sfCreate
!------------------------------------------------------------------------------

    A => AllocateMatrix()

    A % NumberOfRows = N
#ifdef USE_SPARSE
    A % SPMatrix = sfCreate( N,0,istat )
#endif
    IF ( A % SPMatrix == 0 ) THEN
      PRINT*,'ERROR: Sparse matrix create error:',istat
      STOP
    END IF
!------------------------------------------------------------------------------
  END FUNCTION Sparse_CreateMatrix
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE Sparse_MatrixVectorMultiply( A,u,v )
DLLEXPORT Sparse_MatrixVectorMultiply
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Matrix vector product (v = Au) for a matrix given in Sparse format.
!
!  ARGUMENTS:
!
!    REAL(KIND=dp) :: u,v
!
!******************************************************************************
!------------------------------------------------------------------------------
    REAL(KIND=dp), DIMENSION(*) :: u,v
    TYPE(Matrix_t), POINTER :: A
!------------------------------------------------------------------------------
#ifdef USE_SPARSE
    CALL sfMultiply( A % SPMatrix,v,u )
#endif
!------------------------------------------------------------------------------
  END SUBROUTINE Sparse_MatrixVectorMultiply
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE Sparse_SolveSystem( A, x, b )
!------------------------------------------------------------------------------
    TYPE(Matrix_t), POINTER :: a
    REAL(KIND=dp) :: x(:),b(:)
!------------------------------------------------------------------------------

#ifdef USE_SPARSE

    INTEGER  :: i,j,istat,sfFactor
    EXTERNAL  sfSolve,sfSet1real
    INTEGER(KIND=AddrInt) :: sfGetElement,sfCreate

#ifdef NOTDEF

    istat = sfFactor( A % SPMatrix )
    IF ( istat /= 0 ) THEN
      PRINT*,'ERROR: Sparse matrix factorization error: ', istat
      STOP
    END IF
    CALL sfSolve( A % SPMatrix, b, x )

#else

    IF ( A % SPMatrix == 0 ) THEN
      A % SPMatrix = sfCreate( A % NumberOfRows,0,istat )
      IF ( A % SPMatrix == 0 ) THEN
        PRINT*,'ERROR: Sparse matrix create error:',istat
        STOP
      END IF
    ELSE
      CALL sfClear( A % SPMatrix )
    END IF

    DO i=1,A % NumberOfRows
      DO j=A % Rows(i), A % Rows(i+1)-1
        CALL sfSet1Real( sfGetElement(A % SPMatrix,i,A % Cols(j)), &
                        A % Values(j))
      END DO
    END DO

    istat = sfFactor( A % SPMatrix )
    IF ( istat /= 0 ) THEN
      PRINT*,'ERROR: Sparse matrix factorization error: ', istat
      STOP
    END IF
    CALL sfSolve( A % SPMatrix, b, x )

#endif
#endif
!------------------------------------------------------------------------------
   END SUBROUTINE Sparse_SolveSystem
!------------------------------------------------------------------------------

END MODULE SparseMatrix
