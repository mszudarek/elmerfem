!/***************************************************************************
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
! ***************************************************************************/
!
!
!********************************************************************
!
! File: ParIterPrecond.f90
! Software: ELMER
! File info: This module implements the parallel version of the ELMER
!            iterative solver.
!
! Author: Jouni Malinen <jim@csc.fi>
!
! $Id: SParIterPrecond.f90,v 1.3 2002/10/17 16:15:26 jpr Exp $
!
!********************************************************************


#include "huti_fdefs.h"

MODULE SParIterPrecond

  USE Types
  USE SParIterGlobals
  USE SParIterComm

  IMPLICIT NONE
  
CONTAINS

  !*********************************************************************
  !*********************************************************************
  !
  ! External Preconditioning operations
  !
  ! This is the place to do preconditioning steps if needed
  ! Called from HUTIter library
  !
  !*********************************************************************
  !*********************************************************************

  SUBROUTINE ParDiagPrec ( u, v, ipar )

    ! Input parameters

    DOUBLE PRECISION, DIMENSION(*) :: u, v
    INTEGER, DIMENSION(*) :: ipar

    ! Local parameters
    
    INTEGER :: i

    !*********************************************************************

    DO i = 1,HUTI_NDIM
       u(i) = v(i) * PIGpntr % SplittedMatrix % InsideMatrix % ILUValues(i)
    END DO

  END SUBROUTINE ParDiagPrec

  !*********************************************************************
  !*********************************************************************
  !
  ! This routines performs a forward and backward solve for ILU
  ! factorization, i.e. solves (LU)u = v.
  !
  ! Diagonal values of U must be already inverted
  
  SUBROUTINE ParLUPrec ( u, v, ipar )

    ! Input parameters

    DOUBLE PRECISION, DIMENSION(*) :: u, v
    INTEGER, DIMENSION(*) :: ipar

    ! Local parameters

    INTEGER :: i, k

    DOUBLE PRECISION, POINTER :: Vals(:)
    INTEGER, POINTER :: Rows(:),Cols(:),Diag(:)

    !*********************************************************************

    ! Forward solve, Lu = v

    Rows => PIGpntr % SplittedMatrix % InsideMatrix % Rows
    Cols => PIGpntr % SplittedMatrix % InsideMatrix % Cols
    Diag => PIGpntr % SplittedMatrix % InsideMatrix % Diag
    Vals => PIGpntr % SplittedMatrix % InsideMatrix % ILUValues

    CALL LUPrec( HUTI_NDIM, Size(Cols), Rows,Cols,Diag,Vals,u,v )

CONTAINS
    
    SUBROUTINE LUPrec( n,m,Rows,Cols,Diag,Vals,u,v )
    INTEGER :: n,m,Rows(n+1),Cols(m),Diag(n)
    DOUBLE PRECISION :: Vals(m),u(n),v(n)

    DO i = 1, n

       ! Compute u(i) = v(i) - sum L(i,j) u(j)

       u(i) = v(i)

       DO k = Rows(i), Diag(i) - 1
          u(i) = u(i) - Vals(k) * u(Cols(k))
       END DO

    END DO

    ! Backward solve, u = inv(U) u
    
    DO i = n, 1, -1

       ! Compute u(i) = u(i) - sum U(i,j) u(j)

       DO k = Diag(i)+1,Rows(i+1)-1
          u(i) = u(i) - Vals(k) * u(Cols(k))
       END DO

       ! Compute u(i) = u(i) / U(i,i)

       u(i) = Vals(Diag(i)) * u(i)

    END DO
    END SUBROUTINE LUPrec

  END SUBROUTINE ParLUPrec

  !*********************************************************************
  !*********************************************************************
  !
  ! This routines performs a forward solve for ILU
  ! factorization, i.e. solves Lu = v.
  !
  ! Diagonal values of U must be already inverted

  SUBROUTINE ParLPrec ( u, v, ipar )
    
    ! Input parameters

    DOUBLE PRECISION, DIMENSION(*) :: u, v
    INTEGER, DIMENSION(*) :: ipar

    ! Local parameters
    
    INTEGER :: i, k

    !*********************************************************************

    ! Forward solve, Lu = v

    DO i = 1, HUTI_NDIM

       ! Compute u(i) = v(i) - sum L(i,j) u(j)
       
       u(i) = v(i)
       DO k = PIGpntr % SplittedMatrix % InsideMatrix % Rows(i), &
                 PIGpntr % SplittedMatrix % InsideMatrix % Diag(i) - 1
          u(i) = u(i) - PIGpntr % SplittedMatrix % InsideMatrix % ILUValues(k) &
               * u(PIGpntr % SplittedMatrix % InsideMatrix % Cols(k))
       END DO
    END DO

!    CALL UpdateOwnedVectorEl( PIGpntr, u, HUTI_NDIM )

  END SUBROUTINE ParLPrec

  !*********************************************************************
  !*********************************************************************
  !
  ! This routines performs backward solve for ILU
  ! factorization, i.e. solves Uu = v.
  !
  ! Diagonal values of U must be already inverted

  SUBROUTINE ParUPrec ( u, v, ipar )

    ! Input parameters

    DOUBLE PRECISION, DIMENSION(*) :: u, v
    INTEGER, DIMENSION(*) :: ipar

    ! Local parameters
    
    INTEGER :: i, k

    !*********************************************************************

    ! Backward solve, u = inv(U) u

    DO i = HUTI_NDIM, 1, -1

       ! Compute u(i) = u(i) - sum U(i,j) u(j)

       u(i) = v(i)
       DO k = PIGpntr % SplittedMatrix % InsideMatrix % Diag(i) + 1, &
             PIGpntr % SplittedMatrix % InsideMatrix % Rows(i+1) - 1
          u(i) = u(i) - PIGpntr % SplittedMatrix % InsideMatrix % ILUValues(k) &
               * u(PIGpntr % SplittedMatrix % InsideMatrix % Cols(k))
       END DO
       
       ! Compute u(i) = u(i) / U(i,i)

       u(i) = PIGpntr % SplittedMatrix % InsideMatrix % ILUValues( &
              PIGpntr % SplittedMatrix % InsideMatrix % Diag(i)) * u(i)
    END DO

!    CALL UpdateOwnedVectorEl( PIGpntr, u, HUTI_NDIM )

  END SUBROUTINE ParUPrec

  !*********************************************************************
  !*********************************************************************
  !
  ! This routine is used to perform ILU(0) preconditioning setup
  ! Incomplete LU factorization is saved to Matrix % ILUValues.
  ! Diagonal entries are inverted.
  !
  
  SUBROUTINE ParILU0 ( Matrix )

    ! Input parameters

    TYPE (Matrix_t) :: Matrix

    ! Local parameters

    INTEGER :: i, j, k, l
    DOUBLE PRECISION :: tl
    PARAMETER ( tl = 1.0d-15 )
  
    !*********************************************************************

    ! Initialize the ILUValues

    DO i = 1, SIZE( Matrix % Values )
       Matrix % ILUValues(i) = Matrix % Values(i)
    END DO

    !
    ! This is from Saads book, Algorithm 10.4
    !

    DO i = 2, Matrix % NumberOfRows

       DO k = Matrix % Rows(i), Matrix % Diag(i) - 1

          ! Check for small pivot

          IF ( ABS(Matrix % ILUValues( Matrix % Diag( Matrix % Cols(k) ))) &
               .LT. tl ) THEN
             PRINT *, 'Small pivot : ', &
                  Matrix % ILUValues( Matrix % Diag( Matrix % Cols(k) ))
          END IF

          ! Compute a_ik = a_ik / a_kk
          
          Matrix % ILUValues(k) = Matrix % ILUValues (k) &
               / Matrix % ILUValues(Matrix % Diag( Matrix % Cols(k)))

          DO j = k + 1, Matrix % Rows(i+1) - 1

             ! Compute a_ij = a_ij - a_ik * a_kj

             DO l = Matrix % Rows(Matrix % Cols(k)), &
                  Matrix % Rows(Matrix % Cols(k) + 1) - 1

                IF (Matrix % Cols(l) .eq. Matrix % Cols(j) ) then
                   Matrix % ILUValues(j) = Matrix % ILUValues(j) - &
                        Matrix % ILUValues(k) * Matrix % ILUValues(l)
                   EXIT
                END IF

             END DO

          END DO
          
       END DO

    END DO

    DO i = 1, Matrix % NumberOfRows
       Matrix % ILUValues(Matrix % Diag(i)) = 1.0 / &
            Matrix % ILUValues(Matrix % Diag(i))
    END DO

  END SUBROUTINE ParILU0
  
END MODULE SParIterPrecond
