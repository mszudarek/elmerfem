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
! * LU Decomposition & matrix inverse (don't use this for anything big,
! * use for example LAPACK routines instead...)
! *
! *******************************************************************************
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
! *                       Date: 01 Oct 1996
! *
! *                Modified by:
! *
! *       Date of modification:
! *
! ******************************************************************************/



MODULE LUDecomposition

  USE Types

 CONTAINS

  SUBROUTINE InvertMatrix( A,n )
DLLEXPORT InvertMatrix

    INTEGER :: n 
    REAL(KIND=dp) :: A(:,:)

    REAL(KIND=dp) :: s
    INTEGER :: i,j,k
    INTEGER :: pivot(n)

   ! /*
   !  *  AP = LU
   !  */
   CALL LUDecomp( a,n,pivot )

   DO i=1,n
     IF ( ABS(A(i,i)) == 0.0d0 ) THEN
       CALL Error( 'InvertMatrix', 'Matrix is singular.' )
       RETURN       
     END IF
     A(i,i) = 1.0d0 / A(i,i)
   END DO

   ! /*  
   !  *  INV(U)
   !  */
   DO i=N-1,1,-1
     DO j=N,i+1,-1
       s = -A(i,j)
       DO k=i+1,j-1
         s = s - A(i,k)*A(k,j)
       END DO
       A(i,j) = s
     END DO
   END DO

   ! /*
   !  * INV(L)
   !  */
   DO i=n-1,1,-1
     DO j=n,i+1,-1
       s = 0.D00
       DO k=i+1,j
         s = s - A(j,k)*A(k,i)
       END DO
       A(j,i) = A(i,i)*s
     END DO
   END DO
  
   ! /* 
   !  * A  = INV(AP)
   !  */
   DO i=1,n
     DO j=1,n
       s = 0.0D0
       DO k=MAX(i,j),n
         IF ( k /= i ) THEN
           s = s + A(i,k)*A(k,j)
         ELSE
           s = s + A(k,j)
         END IF
       END DO
       A(i,j) = s
     END DO
   END DO

   ! /*
   !  * A = INV(A) (at last)
   !  */
   DO i=n,1,-1
     IF ( pivot(i) /= i ) THEN
       DO j = 1,n
         s = A(i,j)
         A(i,j) = A(pivot(i),j)
         A(pivot(i),j) = s
       END DO
     END IF
   END DO

 END SUBROUTINE InvertMatrix


 SUBROUTINE LUSolve( n,A,x )
   REAL(KIND=dp) :: A(n,n)
   REAL(KIND=dp) :: x(n)
   INTEGER :: n 

   REAL(KIND=dp) :: s
   INTEGER :: i,j,k
   INTEGER :: pivot(n)

   ! /*
   !  *  AP = LU
   !  */
   CALL LUDecomp( A,n,pivot )

   DO i=1,n
     IF ( ABS(A(i,i)) == 0.0d0 ) THEN
       CALL Error( 'LUSolve', 'Matrix is singular.' )
       RETURN       
     END IF
     A(i,i) = 1.0d0 / A(i,i)
   END DO

   !
   ! Forward substitute
   DO i=1,n
      s = x(i)
      DO j=1,i-1
         s = s - A(i,j) * x(j)
      END DO
      x(i) = A(i,i) * s 
   END DO

   !
   ! Backward substitute (solve x from Ux = z)
   DO i=n,1,-1
      s = x(i)
      DO j=i+1,n
         s = s - A(i,j) * x(j)
      END DO
      x(i) = s
   END DO

   DO i=n,1,-1
      IF ( pivot(i) /= i ) THEN
         s = x(i)
         x(i) = x(pivot(i))
         x(pivot(i)) = s
      END IF
   END DO

  END SUBROUTINE LUSolve


!/*
! * LU- decomposition by gaussian elimination. Row pivoting is used.
! * 
! * result : AP = L'U ; L' = LD; pivot[i] is the swapped column number
! * for column i.
! *
! * Result is stored in place of original matrix.
! *
! */
  SUBROUTINE LUDecomp( a,n,pivot )
DLLEXPORT LUDecomp

    REAL(KIND=dp), DIMENSION (:,:) :: a
    INTEGER :: n
    INTEGER, DIMENSION (:) :: pivot

    INTEGER :: i,j,k,l
    REAL(KIND=dp) :: swap

    DO i=1,n
      j = i
      DO k=i+1,n
        IF ( ABS(A(i,k)) > ABS(A(i,j)) ) j = k
      END DO

      IF ( ABS(A(i,j)) == 0.0d0) THEN
        CALL Error( 'LUDecomp', 'Matrix is singluar.' )
        RETURN
      END IF

      pivot(i) = j

      IF ( j /= i ) THEN
        DO k=1,i
          swap = A(k,j)
          A(k,j) = A(k,i)
          A(k,i) = swap
        END DO
      END IF

      DO k=i+1,n
        A(i,k) = A(i,k) / A(i,i)
      END DO

      DO k=i+1,n
        IF ( j /= i ) THEN
          swap = A(k,i)
          A(k,i) = A(k,j)
          A(k,j) = swap
        END IF

        DO  l=i+1,n
          A(k,l) = A(k,l) - A(k,i) * A(i,l)
        END DO
      END DO
    END DO

    pivot(n) = n
    IF ( ABS(A(n,n)) == 0.0d0 ) THEN
      CALL Error( 'LUDecomp',  'Matrix is (at least almost) singular.' )
    END IF

  END SUBROUTINE LUDecomp



  SUBROUTINE ComplexInvertMatrix( A,n )
DLLEXPORT ComplexInvertMatrix

    COMPLEx(KIND=dp), DIMENSION(:,:) :: A
    INTEGER :: n 

    COMPLEX(KIND=dp) :: s
    INTEGER :: i,j,k
    INTEGER :: pivot(n)

   ! /*
   !  *  AP = LU
   !  */
   CALL ComplexLUDecomp( a,n,pivot )

   DO i=1,n
     IF ( ABS(A(i,i))==0.0d0 ) THEN
       CALL Error( 'ComplexInvertMatrix', 'Matrix is singular.' )
       RETURN       
     END IF
     A(i,i) = 1.0D0/A(i,i)
   END DO

   ! /*  
   !  *  INV(U)
   !  */
   DO i=N-1,1,-1
     DO j=N,i+1,-1
       s = -A(i,j)
       DO k=i+1,j-1
         s = s - A(i,k)*A(k,j)
       END DO
       A(i,j) = s
     END DO
   END DO

   ! /*
   !  * INV(L)
   !  */
   DO i=n-1,1,-1
     DO j=n,i+1,-1
       s = 0.D00
       DO k=i+1,j
         s = s - A(j,k)*A(k,i)
       END DO
       A(j,i) = A(i,i)*s
     END DO
   END DO
  
   ! /* 
   !  * A  = INV(AP)
   !  */
   DO i=1,n
     DO j=1,n
       s = 0.0D0
       DO k=MAX(i,j),n
         IF ( k /= i ) THEN
           s = s + A(i,k)*A(k,j)
         ELSE
           s = s + A(k,j)
         END IF
       END DO
       A(i,j) = s
     END DO
   END DO

   ! /*
   !  * A = INV(A) (at last)
   !  */
   DO i=n,1,-1
     IF ( pivot(i) /= i ) THEN
       DO j = 1,n
         s = A(i,j)
         A(i,j) = A(pivot(i),j)
         A(pivot(i),j) = s
       END DO
     END IF
   END DO

 END SUBROUTINE ComplexInvertMatrix

!/*
! * LU- decomposition by gaussian elimination. Row pivoting is used.
! * 
! * result : AP = L'U ; L' = LD; pivot[i] is the swapped column number
! * for column i.
! *
! * Result is stored in place of original matrix.
! *
! */

  SUBROUTINE ComplexLUDecomp( a,n,pivot )
DLLEXPORT LUDecomp

    COMPLEX(KIND=dp), DIMENSION (:,:) :: a
    INTEGER :: n
    INTEGER, DIMENSION (:) :: pivot

    INTEGER :: i,j,k,l
    COMPLEX(KIND=dp) :: swap

    DO i=1,n
      j = i
      DO k=i+1,n
        IF ( ABS(A(i,k)) > ABS(A(i,j)) ) j = k
      END DO

      IF ( ABS(A(i,j))==0.0d0 ) THEN
        CALL Error( 'ComplexLUDecomp', 'Matrix is singluar.' )
        RETURN
      END IF

      pivot(i) = j

      IF ( j /= i ) THEN
        DO k=1,i
          swap = A(k,j)
          A(k,j) = A(k,i)
          A(k,i) = swap
        END DO
      END IF

      DO k=i+1,n
        A(i,k) = A(i,k) / A(i,i)
      END DO

      DO k=i+1,n
        IF ( j /= i ) THEN
          swap = A(k,i)
          A(k,i) = A(k,j)
          A(k,j) = swap
        END IF

        DO  l=i+1,n
          A(k,l) = A(k,l) - A(k,i) * A(i,l)
        END DO
      END DO
    END DO

    pivot(n) = n
    IF ( ABS(A(n,n))==0.0d0 ) THEN
      CALL Error( 'ComplexLUDecomp', 'Matrix is (at least almost) singular.' )
    END IF

  END SUBROUTINE ComplexLUDecomp


END MODULE LUDecomposition
