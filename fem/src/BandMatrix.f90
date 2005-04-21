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

#include <huti_fdefs.h>

MODULE BandMatrix


  USE Types
  USE GeneralUtils

  IMPLICIT NONE

CONTAINS

#define BAND_INDEX(i,j)  (((j)-1)*(3*A % Subband+1) + (i)-(j)+2*A % Subband+1)
#define SBAND_INDEX(i,j) (((j)-1)*(A % Subband+1) + (i)-(j)+1)

!------------------------------------------------------------------------------
  SUBROUTINE Band_ZeroMatrix(A)
DLLEXPORT Band_ZeroMatrix
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Zero a Band format matrix
!
!  ARGUMENTS:
!
!  TYPE(Matrix_t) :: A
!     INPUT: Structure holding matrix
!
!******************************************************************************
!------------------------------------------------------------------------------
    TYPE(Matrix_t), POINTER :: A

    A % Values = 0.0D0
    IF ( ASSOCIATED( A % MassValues ) ) A % MassValues = 0.0d0
    IF ( ASSOCIATED( A % DampValues ) ) A % DampValues = 0.0d0
  END SUBROUTINE Band_ZeroMatrix
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE Band_ZeroRow( A,n )
DLLEXPORT Band_ZeroRow 
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Zero given row from a Band format matrix
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
 
    INTEGER :: j,k

    IF ( A % Format == MATRIX_BAND ) THEN
      DO j=MAX(1,n-A % Subband), MIN(A % NumberOfRows, n+A % Subband)
        A % Values(BAND_INDEX(n,j)) = 0.0d0
      END DO
    ELSE
      DO j=MAX(1,n-A % Subband),n
        A % Values(SBAND_INDEX(n,j)) = 0.0d0
      END DO
    END IF
  END SUBROUTINE Band_ZeroRow
!------------------------------------------------------------------------------
  

!------------------------------------------------------------------------------
  SUBROUTINE Band_AddToMatrixElement( A,i,j,value )
DLLEXPORT Band_AddToMatrixElement
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Add a given value to an element of a  Band format matrix
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
    INTEGER :: k
!------------------------------------------------------------------------------
    IF ( A % Format == MATRIX_BAND ) THEN
      k = BAND_INDEX(i,j)
      A % Values(k) = A % Values(k) + Value
    ELSE
      IF ( j <= i ) THEN
        k = SBAND_INDEX(i,j)
        A % Values(k) = A % Values(k) + Value
       END IF
    END IF
  END SUBROUTINE Band_AddToMatrixElement
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE Band_SetMatrixElement( A,i,j,value )
DLLEXPORT Band_SetMatrixElement
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Set a given value to an element of a  Band format matrix
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

    IF ( A % Format == MATRIX_BAND ) THEN
      A % Values(BAND_INDEX(i,j))  = Value
    ELSE
      IF ( j <= i ) A % Values(SBAND_INDEX(i,j)) = Value
    END IF
  END SUBROUTINE Band_SetMatrixElement
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE Band_GlueLocalMatrix( A,N,Dofs,Indeces,LocalMatrix )
DLLEXPORT Band_GlueLocalMatrix
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Add a set of values (.i.e. element stiffness matrix) to a Band format
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
!            added to the Band format matrix
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
 
     INTEGER :: i,j,k,l,c,ind,Row,Col
     REAL(KIND=dp), POINTER :: Values(:)
 
!------------------------------------------------------------------------------

      Values => A % Values

     IF ( A % Format == MATRIX_BAND ) THEN
       DO i=1,N
         DO k=0,Dofs-1
           Row = Dofs * Indeces(i) - k
           DO j=1,N
             DO l=0,Dofs-1
               Col = Dofs * Indeces(j) - l
               ind = BAND_INDEX(Row,Col)
               Values(ind) = &
                  Values(ind) + LocalMatrix(Dofs*i-k,Dofs*j-l)
             END DO
           END DO
         END DO
       END DO
     ELSE
       DO i=1,N
         DO k=0,Dofs-1
           Row = Dofs * Indeces(i) - k
           DO j=1,N
             DO l=0,Dofs-1
               Col = Dofs * Indeces(j) - l
               IF ( Col <= Row ) THEN
                 ind = SBAND_INDEX(Row,Col)
                 Values(ind) = &
                    Values(ind) + LocalMatrix(Dofs*i-k,Dofs*j-l)
               END IF
             END DO
           END DO
         END DO
       END DO
     END IF

  END SUBROUTINE Band_GlueLocalMatrix
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
  SUBROUTINE SBand_SetDirichlet( A, b, n, Value )
DLLEXPORT SBand_SetDirichlet
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Set value of unkown x_n to given value for symmetric band matrix. This is
!    done by replacing the equation of the unknown by  x_n = Value (i.e.
!    zeroing the row of the unkown in the matrix, and setting diagonal to
!    identity). Also the respective column is set to zero (except for the
!    diagonal) to preserve symmetry, while also substituting the rhs by
!    by rhs(i) = rhs(i) - A(i,n) * Value.
!
!  ARGUMENTS:
!
!  TYPE(Matrix_t) :: A
!     INOUT: Structure holding matrix, values are affected in the process
!
!  REAL(KIND=dp) :: b(:)
!     INOUT: RHS vector
!
!  INTEGER :: n
!     INPUT: odered number of the unkown (i.e. matrix row and column number)
!
!  REAL(KIND=dp) :: Value
!     INPUT: Value for the unknown
!          
!
!******************************************************************************
!------------------------------------------------------------------------------
    TYPE(Matrix_t), POINTER :: A
    REAL(KIND=dp) :: b(:),Value
    INTEGER :: n 
!------------------------------------------------------------------------------

    INTEGER :: j
!------------------------------------------------------------------------------

    DO j=MAX(1,n-A % Subband),n-1
      b(j) = b(j) - Value * A % Values(SBAND_INDEX(n,j))
      A % Values(SBAND_INDEX(n,j)) = 0.0d0
    END DO

    DO j=n+1,MIN(n+A % Subband, A % NumberOfRows)
      b(j) = b(j) - Value * A % Values(SBAND_INDEX(j,n))
      A % Values(SBAND_INDEX(j,n)) = 0.0d0
    END DO

    b(n) = Value
    A % Values(SBAND_INDEX(n,n)) = 1.0d0
!------------------------------------------------------------------------------
  END SUBROUTINE SBand_SetDirichlet
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
  FUNCTION Band_CreateMatrix( N,Subband,Symmetric,AllocValues ) RESULT(A)
DLLEXPORT Band_CreateMatrix
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Create the structures required for a Band format matrix.
!
!  ARGUMENTS:
!
!  INTEGER :: N
!     INPUT: Number of rows for the matrix
!
!  INTEGER :: Subband
!     INPUT: Max(ABS(Col-Diag(Row))) of the matrix
!
!  LOGICAL :: Symmetric
!     INPUT: Symmetric or not
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
    INTEGER :: N,Subband
    LOGICAL :: Symmetric,AllocValues

!------------------------------------------------------------------------------
    TYPE(Matrix_t), POINTER :: A

    INTEGER :: i,j,k,istat
!------------------------------------------------------------------------------

    A => AllocateMatrix()

    A % Subband = Subband
    A % NumberOfRows = N

    IF ( AllocValues ) THEN
      IF ( Symmetric ) THEN
        ALLOCATE( A % Values((A % Subband+1)*N), STAT=istat )
      ELSE
        ALLOCATE( A % Values((3*A % Subband+1)*N), STAT=istat )
      END IF
    END IF

    IF ( istat /= 0 ) THEN
      CALL Fatal( 'Band_CreateMatrix', 'Memory allocation error.' )
    END IF

    NULLIFY( A % ILUValues )
  END FUNCTION Band_CreateMatrix
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE Band_MatrixVectorMultiply( A,u,v )
DLLEXPORT Band_MatrixVectorMultiply
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Matrix vector product (v = Au) for a matrix given in Band format.
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
    REAL(KIND=dp), POINTER :: Values(:)

    INTEGER :: i,j,k,n
    REAL(KIND=dp) :: s
!------------------------------------------------------------------------------

    Values => A % Values
    n = A % NumberOfRows

    IF ( A % Format == MATRIX_BAND ) THEN
      DO i=1,n
        s = 0.0d0
        DO j=MAX(1,i-A % Subband), MIN(n,i+A % Subband)
          s = s + u(j) * Values(BAND_INDEX(i,j))
        END DO
        v(i) = s
      END DO
    ELSE
      DO i=1,n
        s = 0.0d0
        DO j=MAX(1,i-A % Subband),i
          s = s + u(j) * Values(SBAND_INDEX(i,j))
        END DO

        DO j=i+1,MIN(i+A % Subband, A % NumberOfRows)
          s = s + u(j) * Values(SBAND_INDEX(j,i))
        END DO
        v(i) = s
      END DO
    END IF

  END SUBROUTINE Band_MatrixVectorMultiply
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE Band_MatrixVectorProd( u,v,ipar )
DLLEXPORT Band_MatrixVectorProd
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Matrix vector product (v = Au) for a matrix given in Band format. The
!    matrix is accessed from a global variable GlobalMatrix.
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

!------------------------------------------------------------------------------
    REAL(KIND=dp), POINTER :: Values(:)

    TYPE(Matrix_t), POINTER :: A
    INTEGER :: i,j,k,n
    REAL(KIND=dp) :: s
!------------------------------------------------------------------------------
    A => GlobalMatrix

    Values => A % Values
    n = A % NumberOfRows

    IF ( A % Format == MATRIX_BAND ) THEN
      IF ( HUTI_EXTOP_MATTYPE == HUTI_MAT_NOTTRPSED ) THEN
        DO i=1,n
          s = 0.0d0
          DO j=MAX(1,i-A % Subband), MIN(n,i+A % Subband)
            s = s + u(j) * Values(BAND_INDEX(i,j))
          END DO
          v(i) = s
        END DO
      ELSE
        v(1:n) = 0.0d0
        DO i=1,n
          s = u(i)
          DO j=MAX(1,i-A % Subband), MIN(n,i+A % Subband)
            v(j) = v(j) + s * Values(BAND_INDEX(i,j))
          END DO
        END DO
      END IF
    ELSE
      DO i=1,n
        s = 0.0d0
        DO j=MAX(1,i-A % Subband),i
          s = s + u(j) * Values(SBAND_INDEX(i,j))
        END DO

        DO j=i+1,MIN(i+A % Subband, A % NumberOfRows)
          s = s + u(j) * Values(SBAND_INDEX(j,i))
        END DO
        v(i) = s
      END DO
    END IF

  END SUBROUTINE Band_MatrixVectorProd
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
  SUBROUTINE Band_DiagPrecondition( u,v,ipar )
DLLEXPORT Band_DiagPrecondition
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Diagonal preconditioning of a Band format matrix.
!
!  ARGUMENTS:
!
!    REAL(KIND=dp) :: u(*),v(*)
!
!    INTEGER :: ipar(:)
!      INPUT: structure holding info from (HUTIter-iterative solver package)
!
!******************************************************************************
!------------------------------------------------------------------------------
    REAL(KIND=dp), DIMENSION(*) :: u,v
    INTEGER, DIMENSION(*) :: ipar

    INTEGER :: i,j,k,n
    TYPE(Matrix_t), POINTER :: A

    REAL(KIND=dp), POINTER :: Values(:)

    A => GlobalMatrix
    Values => GlobalMatrix % Values

    n = A % NumberOfRows

    IF ( A % Format == MATRIX_BAND ) THEN
      DO i=1,n
        k = BAND_INDEX(i,i)
        IF  ( ABS(Values(k)) > AEPS ) THEN
           u(i) = v(i) / Values(k)
        ELSE
           u(i) = v(i)
        END IF
      END DO
    ELSE 
      DO i=1,n
        k = SBAND_INDEX(i,i)
        IF  ( ABS(Values(k)) > AEPS ) THEN
          u(i) = v(i) / Values(k)
        ELSE
          u(i) = v(i)
        END IF
      END DO
    END IF
  END SUBROUTINE Band_DiagPrecondition
!------------------------------------------------------------------------------

END MODULE BandMatrix
