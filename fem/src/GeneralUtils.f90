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
! *     Misc utilities
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
! * $Log: GeneralUtils.f90,v $
! * Revision 1.38  2005/04/04 06:18:28  jpr
! * *** empty log message ***
! *
! *
! * Revision 1.36  2004/08/06 09:03:09  raback
! * Added possibility for partially implicit/explicit radiation factors.
! * Affects the structure Factors_t
! *
! * Revision 1.30  2004/03/04 12:14:39  jpr
! * Just formatting.
! *
! * Revision 1.29  2004/03/01 14:06:56  jpr
! * Added AllocateVector/AllocateArray.
! *
! *
! * $Id: GeneralUtils.f90,v 1.38 2005/04/04 06:18:28 jpr Exp $
! ******************************************************************************/


MODULE GeneralUtils

USE Types

IMPLICIT NONE

INTERFACE AllocateVector
  MODULE PROCEDURE AllocateRealVector, AllocateIntegerVector, &
                   AllocateComplexVector, AllocateLogicalVector, &
                   AllocateElementVector
END INTERFACE

INTERFACE AllocateArray
  MODULE PROCEDURE AllocateRealArray, AllocateIntegerArray, &
                   AllocateComplexArray, AllocateLogicalArray
END INTERFACE


CONTAINS


!------------------------------------------------------------------------------
  SUBROUTINE SystemCommand( cmd ) 
DLLEXPORT SystemCommand
!------------------------------------------------------------------------------
    CHARACTER(LEN=*) :: cmd
    CALL SystemC( TRIM(cmd) // CHAR(0) )
!------------------------------------------------------------------------------
  END SUBROUTINE SystemCommand
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  FUNCTION FormatDate() RESULT( date )
DLLEXPORT FormatDate
!------------------------------------------------------------------------------
    CHARACTER( LEN=20 ) :: date
    INTEGER :: dates(8)

    CALL DATE_AND_TIME( VALUES=dates )
    WRITE( date, &
     '(I4,"/",I2.2,"/",I2.2," ",I2.2,":",I2.2,":",I2.2)' ) &
                dates(1),dates(2),dates(3),dates(5),dates(6),dates(7)
!------------------------------------------------------------------------------
  END FUNCTION FormatDate
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   SUBROUTINE Sort( n,a )
!------------------------------------------------------------------------------
DLLEXPORT Sort
     INTEGER :: n,a(:)
!------------------------------------------------------------------------------

     INTEGER :: i,j,l,ir,ra
!------------------------------------------------------------------------------

      IF ( n <= 1 ) RETURN
 
      l = n / 2 + 1
      ir = n
      DO WHILE( .TRUE. )
        IF ( l > 1 ) THEN
          l = l - 1
          ra = a(l)
        ELSE
         ra = a(ir)
         a(ir) = a(1)
         ir = ir - 1
         IF ( ir == 1 ) THEN
           a(1) = ra
           RETURN
         END IF
        END IF
        i = l
        j = l + l
        DO WHILE( j <= ir )
          IF ( j<ir ) THEN
            IF ( a(j)<a(j+1) ) j = j+1
          END IF

          IF ( ra<a(j) ) THEN
            a(i) = a(j)
            i = j
            j =  j + i
          ELSE
            j = ir + 1
          END IF
          a(i) = ra
       END DO
     END DO

!------------------------------------------------------------------------------
   END SUBROUTINE Sort
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   SUBROUTINE SortI( n,a,b )
DLLEXPORT SortI
!------------------------------------------------------------------------------
     INTEGER :: n,a(:),b(:)
!------------------------------------------------------------------------------

     INTEGER :: i,j,l,ir,ra,rb
!------------------------------------------------------------------------------

      IF ( n <= 1 ) RETURN
 
      l = n / 2 + 1
      ir = n
      DO WHILE( .TRUE. )
        IF ( l > 1 ) THEN
          l = l - 1
          ra = a(l)
          rb = b(l)
        ELSE
         ra = a(ir)
         rb = b(ir)
         a(ir) = a(1)
         b(ir) = b(1)
         ir = ir - 1
         IF ( ir == 1 ) THEN
           a(1) = ra
           b(1) = rb
           RETURN
         END IF
        END IF
        i = l
        j = l + l
        DO WHILE( j <= ir )
          IF ( j<ir  ) THEN
             IF ( a(j)<a(j+1) ) j = j+1
          END IF
          IF ( ra<a(j) ) THEN
            a(i) = a(j)
            b(i) = b(j)
            i = j
            j =  j + i
          ELSE
            j = ir + 1
          END IF
          a(i) = ra
          b(i) = rb
       END DO
     END DO

!------------------------------------------------------------------------------
   END SUBROUTINE SortI
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   SUBROUTINE SortF( n,a,b )
DLLEXPORT SortF
!------------------------------------------------------------------------------
     INTEGER :: n,a(:)
     REAL(KIND=dp) :: b(:)
!------------------------------------------------------------------------------

     INTEGER :: i,j,l,ir,ra
     REAL(KIND=dp) :: rb
!------------------------------------------------------------------------------

      IF ( n <= 1 ) RETURN
 
      l = n / 2 + 1
      ir = n
      DO WHILE( .TRUE. )

        IF ( l > 1 ) THEN
          l = l - 1
          ra = a(l)
          rb = b(l)
        ELSE
          ra = a(ir)
          rb = b(ir)
          a(ir) = a(1)
          b(ir) = b(1)
          ir = ir - 1
          IF ( ir == 1 ) THEN
            a(1) = ra
            b(1) = rb
            RETURN
          END IF
        END IF
        i = l
        j = l + l
        DO WHILE( j <= ir )
          IF ( j<ir  ) THEN
            IF ( a(j)<a(j+1) ) j = j+1
          END IF
          IF ( ra<a(j) ) THEN
            a(i) = a(j)
            b(i) = b(j)
            i = j
            j = j + i
          ELSE
            j = ir + 1
          END IF
          a(i) = ra
          b(i) = rb
       END DO
     END DO

!------------------------------------------------------------------------------
   END SUBROUTINE SortF
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   SUBROUTINE SortC( n,a,b )
DLLEXPORT SortC
!------------------------------------------------------------------------------
     INTEGER :: n,b(:)
     COMPLEX(KIND=dp):: a(:)
!------------------------------------------------------------------------------

     INTEGER :: i,j,l,ir,rb
     COMPLEX(KIND=dp) :: ra
!------------------------------------------------------------------------------

      IF ( n <= 1 ) RETURN
 
      l = n / 2 + 1
      ir = n
      DO WHILE( .TRUE. )
        IF ( l > 1 ) THEN
          l = l - 1
          ra = a(l)
          rb = b(l)
        ELSE
          ra = a(ir)
          rb = b(ir)
          a(ir) = a(1)
          b(ir) = b(1)
          ir = ir - 1
          IF ( ir == 1 ) THEN
            a(1) = ra
            b(1) = rb
            RETURN
          END IF
        END IF
        i = l
        j = l + l
        DO WHILE( j <= ir )
          IF ( j<ir ) THEN
             IF ( ABS(a(j))<ABS(a(j+1)) ) j = j+1
          END IF
          IF ( ABS(ra)<ABS(a(j)) ) THEN
            a(i) = a(j)
            b(i) = b(j)
            i = j
            j = j + i
          ELSE
            j = ir + 1
          END IF
          a(i) = ra
          b(i) = rb
       END DO
     END DO

!------------------------------------------------------------------------------
   END SUBROUTINE SortC
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
! Order real components in b in a decreasing order and return the new order
! of indexes in a.
!------------------------------------------------------------------------------
   SUBROUTINE SortR( n,a,b )
DLLEXPORT SortR
!------------------------------------------------------------------------------
     INTEGER :: n,a(:)
     REAL(KIND=dp) :: b(:)
!------------------------------------------------------------------------------

     INTEGER :: i,j,l,ir,ra
     REAL(KIND=dp) :: rb
!------------------------------------------------------------------------------

      IF ( n <= 1 ) RETURN
 
      l = n / 2 + 1
      ir = n
      DO WHILE( .TRUE. )

        IF ( l > 1 ) THEN
          l = l - 1
          ra = a(l)
          rb = b(l)
        ELSE
          ra = a(ir)
          rb = b(ir)
          a(ir) = a(1)
          b(ir) = b(1)
          ir = ir - 1
          IF ( ir == 1 ) THEN
            a(1) = ra
            b(1) = rb
            RETURN
          END IF
        END IF
        i = l
        j = l + l
        DO WHILE( j <= ir )
          IF ( j<ir  ) THEN
             IF ( b(j) > b(j+1) ) j = j+1
          END IF
          IF ( rb > b(j) ) THEN
            a(i) = a(j)
            b(i) = b(j)
            i = j
            j = j + i
          ELSE
            j = ir + 1
          END IF
          a(i) = ra
          b(i) = rb
       END DO
     END DO

!------------------------------------------------------------------------------
   END SUBROUTINE SortR
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
  FUNCTION Search( N,Array,Value ) RESULT ( INDEX )
DLLEXPORT Search
!------------------------------------------------------------------------------

    INTEGER :: N,Value,Array(:)
!------------------------------------------------------------------------------

    ! Local variables

    INTEGER :: Lower, Upper,Lou,INDEX
!------------------------------------------------------------------------------

    !*******************************************************************

    INDEX = 0 
    Upper = N
    Lower = 1

    ! Handle the special case

    IF ( Upper == 0 ) RETURN

    DO WHILE( .TRUE. )
      IF ( Array(Lower) == Value ) THEN
         INDEX = Lower
         EXIT
      ELSE IF ( Array(Upper) == Value ) THEN
         INDEX = Upper
         EXIT
      END IF

      IF ( (Upper-Lower)>1 ) THEN
        Lou = ISHFT((Upper + Lower), -1)
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

!------------------------------------------------------------------------------
  END FUNCTION Search
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   FUNCTION ReadAndTrim( Unit,str,echo ) RESULT(l)
DLLEXPORT ReadAndTrim
!------------------------------------------------------------------------------
!******************************************************************************
!
!  Read a (logical) line from FORTRAN device Unit and remove leading, trailing,
!  and multiple blanks between words. Also convert uppercase characters to
!  lowercase.The logical line can continue the several physical lines by adding
!  the backslash (\) mark at the end of a physical line. 
!
!  ARGUMENTS:
!
!     INTEGER :: Unit
!       INPUT: Fortran unit number to read from
!
!     CHARACTER :: str
!       OUTPUT: The string read from the file
!
!  FUNCTION RESULT:
!      LOGICAL :: l
!        Success of the read operation
!
!******************************************************************************
     INTEGER, PARAMETER :: MAXLEN = 8192

     INTEGER :: Unit
     CHARACTER*(*) :: str

     LOGICAL, OPTIONAL :: Echo
 
     LOGICAL :: l

     CHARACTER(LEN=MAXLEN) :: readstr = ' ', matcstr

     INTEGER :: i,j,k,ValueStarts=0,inlen,outlen
     LOGICAL :: InsideQuotes, OpenSection=.FALSE.

     CHARACTER(LEN=MAX_NAME_LEN) :: Prefix = '  '

     SAVE ReadStr, ValueStarts, Prefix, OpenSection

     l = .TRUE.

     outlen = LEN( str )

     IF ( ValueStarts==0 .AND. OpenSection ) THEN
        str = 'end'
        ValueStarts = 0
        OpenSection = .FALSE.
        l = .TRUE.
        RETURN
     END IF

     IF ( ValueStarts == 0 ) THEN
        READ( Unit,'(A)',END=10,ERR=10 ) readstr
     ELSE
        inlen = LEN_TRIM( readstr )
        IF ( Prefix == ' ' ) THEN
           readstr = readstr(ValueStarts:inlen)
        ELSE IF ( Prefix == '::' ) THEN
           readstr = readstr(ValueStarts:inlen)
           OpenSection = .TRUE.
           Prefix = ' '
        ELSE
           DO i=ValueStarts,inlen
              IF ( readstr(i:i) ==  ')' ) THEN
                 readstr(i:i) = ' '
                 EXIT
              ELSE IF ( readstr(i:i) == ',' ) THEN
                 readstr(i:i) = ' '
              END IF
           END DO
           readstr = TRIM(Prefix) // ' ' // readstr(ValueStarts:inlen)
        END IF
     END IF

     ValueStarts = 0
     InsideQuotes  = .FALSE.

     inlen = LEN_TRIM( readstr )
     i = 1
     DO WHILE( i <= inlen )
       IF ( readstr(i:i) == '"' ) InsideQuotes = .NOT.InsideQuotes

       IF ( .NOT. InsideQuotes .AND. readstr(i:i) == CHAR(92) .AND. i==inlen ) THEN
          readstr(i:i) = ' '
          READ( Unit,'(A)',END=10,ERR=10 ) readstr(i+1:MAXLEN)
          inlen = LEN_TRIM( readstr )
       END IF
       i = i + 1
     END DO

     inlen = LEN_TRIM( readstr )
     DO i=1,inlen
       IF ( readstr(i:i) == '$' ) THEN
          inlen = LEN_TRIM( Readstr(i+1:) )
          CALL matc( readstr(i+1:),matcstr,inlen )
          readstr(i:) = ' '
          DO j=0,inlen-1
             readstr(i+j:i+j) = matcstr(j+1:j+1)
          END DO
          EXIT
       END IF
     END DO

     IF ( PRESENT( Echo ) ) THEN
        IF ( Echo ) WRITE( 6, '(a)' ) TRIM(readstr)
     END IF

     inlen = LEN_TRIM( readstr )
     i = 1
     DO WHILE(i <= inlen )
        IF (readstr(i:i) /= ' ' .AND. ICHAR(readstr(i:i)) /= 9 ) EXIT
        i = i + 1
     END DO

     inlen =  LEN_TRIM( readstr )
     InsideQuotes = .FALSE.
     str = ' '

     k = 1
     DO WHILE( i<=inlen )
        IF ( readstr(i:i) == '"' ) THEN
          InsideQuotes = .NOT.InsideQuotes
          i = i + 1
          IF ( i > inlen ) EXIT
        END IF

        IF ( .NOT.InsideQuotes ) THEN
           IF ( readstr(i:i) == '!' .OR. readstr(i:i) == '#' .OR. &
                readstr(i:i) == '=' .OR. readstr(i:i) == '(' ) EXIT
           IF ( readstr(i:i+1) == '::' ) EXIT 
           IF ( ICHAR( readstr(i:i) ) < 32 ) EXIT
        END IF

        DO WHILE( i <= inlen )
          IF ( readstr(i:i) == '"'  ) THEN
            InsideQuotes = .NOT.InsideQuotes
            i = i + 1
            IF ( i > inlen ) EXIT
          END IF

          IF ( .NOT.InsideQuotes ) THEN
             IF ( readstr(i:i) == ' ' .OR. readstr(i:i) == '=' .OR. &
                  readstr(i:i) == '(' .OR. ICHAR(readstr(i:i)) == 9 ) EXIT
             IF ( readstr(i:i+1) == '::' ) EXIT 
             IF ( ICHAR( readstr(i:i) ) < 32 ) EXIT
          END IF

          IF ( k > outlen ) THEN
             CALL Fatal( 'ReadAndTrim', 'Output length exeeded.' )
          END IF

          j = ICHAR( readstr(i:i) )
          IF ( .NOT.InsideQuotes .AND. j>=ICHAR('A') .AND. j<=ICHAR('Z') ) THEN
            j = j - ICHAR('A') + ICHAR('a')
            str(k:k) = CHAR(j)
          ELSE
            str(k:k) = readstr(i:i)
          ENDIF

          i = i + 1
          k = k + 1
        END DO
 
        IF ( k <= outlen ) str(k:k) = ' '
        k = k + 1

        DO WHILE( i<=inlen )
          IF ( readstr(i:i) /= ' ' .AND. ICHAR(readstr(i:i)) /= 9 ) EXIT
          i = i + 1
        END DO
     END DO

     IF ( i <= inlen ) THEN
        Prefix = ' '
        IF ( ReadStr(i:i) == '=' ) THEN
           ValueStarts = i + 1
        ELSE IF ( ReadStr(i:i) == '(' ) THEN
           ValueStarts = i + 1
           Prefix = 'Size'
        ELSE IF ( ReadStr(i:i+1) == '::' ) THEN
           ValueStarts = i + 2
           Prefix = '::'
        ELSE IF ( ICHAR(readstr(i:i)) < 32 ) THEN
           DO WHILE( i <= inlen )
             IF ( ICHAR(readstr(i:i)) >= 32 ) EXIT
             i = i + 1
           END DO
           IF ( i <= inlen ) THEN
              ValueStarts = i
           END IF
        END IF
     END IF

     RETURN

10   CONTINUE

     l = .FALSE.
!------------------------------------------------------------------------------
   END FUNCTION ReadAndTrim
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  FUNCTION IntegerToString( input ) RESULT(str)
DLLEXPORT IntegerToString
!------------------------------------------------------------------------------
    CHARACTER(LEN=16) :: str
    INTEGER :: i,j,k,n,input

    str = ' '
    i = input
    n = LOG10(i+0.5d0)
    k = n
    DO j=1,n+1
       str(j:j) = CHAR(i/10**k+ICHAR('0'))
       i = i - 10**k * (i/10**k)
       k = k - 1
    END DO
!------------------------------------------------------------------------------
  END FUNCTION IntegerToString
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  FUNCTION ComponentName( BaseName, Component ) RESULT(str)
DLLEXPORT ComponentName
!------------------------------------------------------------------------------
    INTEGER :: Component
    CHARACTER(LEN=*) :: BaseName
!------------------------------------------------------------------------------
    CHARACTER(LEN=MAX_NAME_LEN) :: str
!------------------------------------------------------------------------------

    str = TRIM( BaseName ) // ' ' // TRIM( IntegerToString( Component ) )
!------------------------------------------------------------------------------
  END FUNCTION ComponentName
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
   FUNCTION InterpolateCurve( TValues,FValues,T ) RESULT( F )
DLLEXPORT InterpolateCurve
!------------------------------------------------------------------------------
     REAL(KIND=dp) :: TValues(:),FValues(:),T,F
!------------------------------------------------------------------------------
     INTEGER :: i,n
!------------------------------------------------------------------------------

     n = SIZE(TValues)

     DO i=1,n
        IF ( TValues(i) >= T ) EXIT
     END DO
     IF ( i > n ) i = n
     IF ( i < 2 ) i = 2

     F = (T-TValues(i-1)) / (TValues(i)-TValues(i-1))
     F = (1-F)*FValues(i-1) + F*FValues(i)
   END FUNCTION InterpolateCurve
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   FUNCTION DerivateCurve( TValues,FValues,T ) RESULT( F )
!------------------------------------------------------------------------------
DLLEXPORT DerivateCurve
     REAL(KIND=dp) :: TValues(:),FValues(:),T,F
!------------------------------------------------------------------------------
     INTEGER :: i,n
!------------------------------------------------------------------------------
     n = SIZE(TValues)

     DO i=1,n
       IF ( TValues(i) >= T ) EXIT
     END DO

     IF ( i < 2 ) i = 2
     IF ( i > n ) i = n

     F = (FValues(i)-FValues(i-1)) / (TValues(i)-TValues(i-1))
!------------------------------------------------------------------------------
   END FUNCTION DerivateCurve
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   SUBROUTINE SolveLinSys2x2( A, x, b )
!------------------------------------------------------------------------------
     REAL(KIND=dp) :: A(2,2),x(2),b(2),detA
!------------------------------------------------------------------------------
     detA = A(1,1) * A(2,2) - A(1,2) * A(2,1)

     IF ( detA == 0.0d0 ) THEN
       WRITE( Message, * ) 'Singular matrix, sorry!'
       CALL Error( 'SolveLinSys2x2', Message )
       RETURN
     END IF

     detA = 1.0d0 / detA
     x(1) = detA * (A(2,2) * b(1) - A(1,2) * b(2))
     x(2) = detA * (A(1,1) * b(2) - A(2,1) * b(1))
!------------------------------------------------------------------------------
   END SUBROUTINE SolveLinSys2x2
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   SUBROUTINE SolveLinSys3x3( A, x, b )
!------------------------------------------------------------------------------
     REAL(KIND=dp) :: A(3,3),x(3),b(3)
!------------------------------------------------------------------------------
     REAL(KIND=dp) :: C(2,2),y(2),g(2),s,t,q
!------------------------------------------------------------------------------

     IF ( ABS(A(1,1))>ABS(A(1,2)) .AND. ABS(A(1,1))>ABS(A(1,3)) ) THEN
       q = 1.0d0 / A(1,1)
       s = q * A(2,1)
       t = q * A(3,1)
       C(1,1) = A(2,2) - s * A(1,2)
       C(1,2) = A(2,3) - s * A(1,3)
       C(2,1) = A(3,2) - t * A(1,2)
       C(2,2) = A(3,3) - t * A(1,3)

       g(1) = b(2) - s * b(1)
       g(2) = b(3) - t * b(1)
       CALL SolveLinSys2x2( C,y,g )
       
       x(2) = y(1)
       x(3) = y(2)
       x(1) = q * ( b(1) - A(1,2) * x(2) - A(1,3) * x(3) )
     ELSE IF ( ABS(A(1,2)) > ABS(A(1,3)) ) THEN
       q = 1.0d0 / A(1,2)
       s = q * A(2,2)
       t = q * A(3,2)
       C(1,1) = A(2,1) - s * A(1,1)
       C(1,2) = A(2,3) - s * A(1,3)
       C(2,1) = A(3,1) - t * A(1,1)
       C(2,2) = A(3,3) - t * A(1,3)
       
       g(1) = b(2) - s * b(1)
       g(2) = b(3) - t * b(1)
       CALL SolveLinSys2x2( C,y,g )

       x(1) = y(1)
       x(3) = y(2)
       x(2) = q * ( b(1) - A(1,1) * x(1) - A(1,3) * x(3) )
     ELSE
       q = 1.0d0 / A(1,3)
       s = q * A(2,3)
       t = q * A(3,3)
       C(1,1) = A(2,1) - s * A(1,1)
       C(1,2) = A(2,2) - s * A(1,2)
       C(2,1) = A(3,1) - t * A(1,1)
       C(2,2) = A(3,2) - t * A(1,2)

       g(1) = b(2) - s * b(1)
       g(2) = b(3) - t * b(1)
       CALL SolveLinSys2x2( C,y,g )

       x(1) = y(1)
       x(2) = y(2)
       x(3) = q * ( b(1) - A(1,1) * x(1) - A(1,2) * x(2) )
     END IF
!------------------------------------------------------------------------------
   END SUBROUTINE SolveLinSys3x3
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   FUNCTION AllocateMatrix() RESULT(Matrix)
!------------------------------------------------------------------------------
DLLEXPORT AllocateMatrix
      TYPE(Matrix_t), POINTER :: Matrix
!------------------------------------------------------------------------------
      ALLOCATE( Matrix )

      Matrix % FORMAT = MATRIX_CRS
      Matrix % SPMatrix = 0

      NULLIFY( Matrix % Child )
      NULLIFY( Matrix % Parent )
      NULLIFY( Matrix % EMatrix )
      NULLIFY( Matrix % JacobiMatrix )

      NULLIFY( Matrix % Perm )
      NULLIFY( Matrix % InvPerm )

      NULLIFY( Matrix % Cols )
      NULLIFY( Matrix % Rows )
      NULLIFY( Matrix % Diag )
      NULLIFY( Matrix % GRows )
 
      NULLIFY( Matrix % RHS )
      NULLIFY( Matrix % Force )

      NULLIFY( Matrix % Values )
      NULLIFY( Matrix % ILUValues )
      NULLIFY( Matrix % MassValues )
      NULLIFY( Matrix % DampValues )

      NULLIFY( Matrix % ILUCols )
      NULLIFY( Matrix % ILURows )
      NULLIFY( Matrix % ILUDiag )

      NULLIFY( Matrix % CRHS )
      NULLIFY( Matrix % CForce )

      NULLIFY( Matrix % RowOwner )
      NULLIFY( Matrix % ParMatrix )

      NULLIFY( Matrix % CValues )
      NULLIFY( Matrix % CILUValues )
      NULLIFY( Matrix % CMassValues )
      NULLIFY( Matrix % CDampValues )

      NULLIFY( Matrix % GRows )
      NULLIFY( Matrix % GOrder )
      NULLIFY( Matrix % RowOwner )

      NULLIFY( Matrix % ParMatrix )

      Matrix % Lumped    = .FALSE.
      Matrix % Ordered   = .FALSE. 
      Matrix % COMPLEX   = .FALSE.
      Matrix % Symmetric = .FALSE.
      Matrix % SolveCount   = 0
      Matrix % NumberOfRows = 0
!------------------------------------------------------------------------------
   END FUNCTION AllocateMatrix
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   RECURSIVE SUBROUTINE FreeMatrix( Matrix )
!------------------------------------------------------------------------------
DLLEXPORT FreeMatrix
     TYPE(Matrix_t), POINTER :: Matrix
!------------------------------------------------------------------------------

     IF ( .NOT. ASSOCIATED( Matrix ) ) RETURN

     IF ( ASSOCIATED( Matrix % Perm ) )        DEALLOCATE( Matrix % Perm )
     IF ( ASSOCIATED( Matrix % InvPerm ) )     DEALLOCATE( Matrix % InvPerm )

     IF ( ASSOCIATED( Matrix % Cols ) ) THEN
        IF ( ASSOCIATED( Matrix % Cols, Matrix % ILUCols ) ) &
           NULLIFY( Matrix % ILUCols )
        DEALLOCATE( Matrix % Cols )
     END IF

     IF ( ASSOCIATED( Matrix % Rows ) ) THEN
        IF ( ASSOCIATED( Matrix % Rows, Matrix % ILURows ) ) &
           NULLIFY( Matrix % ILURows )
        DEALLOCATE( Matrix % Rows )
     END IF

     IF ( ASSOCIATED( Matrix % Diag ) ) THEN
        IF ( ASSOCIATED( Matrix % Diag, Matrix % ILUDiag ) ) &
           NULLIFY( Matrix % ILUDiag )
        DEALLOCATE( Matrix % Diag )
     END IF

     IF ( ASSOCIATED( Matrix % GRows ) )       DEALLOCATE( Matrix % GRows )
  
     IF ( ASSOCIATED( Matrix % RHS   ) )       DEALLOCATE( Matrix % RHS )
     IF ( ASSOCIATED( Matrix % Force ) )       DEALLOCATE( Matrix % Force )

     IF ( ASSOCIATED( Matrix % Values ) )      DEALLOCATE( Matrix % Values )
     IF ( ASSOCIATED( Matrix % MassValues ) )  DEALLOCATE( Matrix % MassValues )
     IF ( ASSOCIATED( Matrix % DampValues ) )  DEALLOCATE( Matrix % DampValues )

     IF ( ASSOCIATED( Matrix % ILUValues ) )   DEALLOCATE( Matrix % ILUValues )
     IF ( ASSOCIATED( Matrix % ILUCols ) )     DEALLOCATE( Matrix % ILUCols )
     IF ( ASSOCIATED( Matrix % ILURows ) )     DEALLOCATE( Matrix % ILURows )
     IF ( ASSOCIATED( Matrix % ILUDiag ) )     DEALLOCATE( Matrix % ILUDiag )

     IF ( ASSOCIATED( Matrix % CRHS   ) )      DEALLOCATE( Matrix % CRHS )
     IF ( ASSOCIATED( Matrix % CForce ) )      DEALLOCATE( Matrix % CForce )

     IF ( ASSOCIATED( Matrix % CValues ) )     DEALLOCATE( Matrix % CValues )
     IF ( ASSOCIATED( Matrix % CILUValues ) )  DEALLOCATE( Matrix % CILUValues )

     IF ( ASSOCIATED(Matrix % CMassValues) )  DEALLOCATE( Matrix % CMassValues )
     IF ( ASSOCIATED(Matrix % CDampValues) )  DEALLOCATE( Matrix % CDampValues )

     IF ( ASSOCIATED( Matrix % GRows ) )      DEALLOCATE( Matrix % GRows )
     IF ( ASSOCIATED( Matrix % GOrder) )      DEALLOCATE( Matrix % GOrder )
     IF ( ASSOCIATED( Matrix % RowOwner ) )   DEALLOCATE( Matrix % RowOwner )

     CALL FreeMatrix( Matrix % EMatrix )
     CALL FreeMatrix( Matrix % JacobiMatrix )

     DEALLOCATE( Matrix )
!------------------------------------------------------------------------------
   END SUBROUTINE FreeMatrix
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  RECURSIVE SUBROUTINE FreeQuadrantTree( Root )
!------------------------------------------------------------------------------
    TYPE(Quadrant_t), POINTER :: Root

    INTEGER :: i

    IF ( .NOT. ASSOCIATED( Root ) ) RETURN

    IF ( ASSOCIATED(Root % Elements) ) DEALLOCATE( Root % Elements )

    IF ( ASSOCIATED( Root % ChildQuadrants ) ) THEN
       DO i=1,SIZE(Root % ChildQuadrants)
          CALL FreeQuadrantTree( Root % ChildQuadrants(i) % Quadrant )
       END DO
       DEALLOCATE( Root % ChildQuadrants )
       NULLIFY( Root % ChildQuadrants )
    END IF

    DEALLOCATE( Root )
!------------------------------------------------------------------------------
  END SUBROUTINE FreeQuadrantTree
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE AllocateRealVector( F, n, From, FailureMessage )
DLLEXPORT AllocateRealVector
!------------------------------------------------------------------------------
    REAL(KIND=dp), POINTER :: F(:)
    INTEGER :: n
    CHARACTER(LEN=*), OPTIONAL :: From, FailureMessage
!------------------------------------------------------------------------------
    INTEGER :: istat
!------------------------------------------------------------------------------

    istat = -1
    IF ( n > 0 ) THEN
       ALLOCATE( F(n), STAT=istat )
    END IF
    IF ( istat /=  0 ) THEN
       IF ( PRESENT( FailureMessage  ) ) THEN
          WRITE( Message, * )'Unable to allocate ', n, ' element real array.'
          CALL Error( 'AllocateRealVector', Message )
          IF ( PRESENT( From ) ) THEN
             WRITE( Message, * )'Requested From: ', TRIM(From)
             CALL Error( 'AllocateRealVector', Message )
          END IF
          IF ( PRESENT( FailureMessage ) ) THEN
             CALL Fatal( 'AllocateRealVector', FailureMessage )
          END IF
       END IF
    END IF
!------------------------------------------------------------------------------
  END SUBROUTINE AllocateRealVector
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE AllocateComplexVector( f, n, From, FailureMessage )
DLLEXPORT AllocateComplexVector
!------------------------------------------------------------------------------
    COMPLEX(KIND=dp), POINTER :: f(:)
    INTEGER :: n
    CHARACTER(LEN=*), OPTIONAL :: From, FailureMessage
!------------------------------------------------------------------------------
    INTEGER :: istat
!------------------------------------------------------------------------------

    istat = -1
    IF ( n > 0 ) THEN
       ALLOCATE( f(n), STAT=istat )
    END IF
    IF ( istat /=  0 ) THEN
       IF ( PRESENT( FailureMessage  ) ) THEN
          WRITE( Message, * )'Unable to allocate ', n, ' element real array.'
          CALL Error( 'AllocateComplexVector', Message )
          IF ( PRESENT( From ) ) THEN
             WRITE( Message, * )'Requested From: ', TRIM(From)
             CALL Error( 'AllocateComplexVector', Message )
          END IF
          IF ( PRESENT( FailureMessage ) ) THEN
             CALL Fatal( 'AllocateComplexVector', FailureMessage )
          END IF
       END IF
    END IF
!------------------------------------------------------------------------------
  END SUBROUTINE AllocateComplexVector
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE AllocateIntegerVector( f, n, From, FailureMessage )
DLLEXPORT AllocateIntegerVector
!------------------------------------------------------------------------------
    INTEGER, POINTER :: f(:)
    INTEGER :: n
    CHARACTER(LEN=*), OPTIONAL :: From, FailureMessage
!------------------------------------------------------------------------------
    INTEGER :: istat
!------------------------------------------------------------------------------

    istat = -1
    IF ( n > 0 ) THEN
       ALLOCATE( f(n), STAT=istat )
    END IF
    IF ( istat /=  0 ) THEN
       IF ( PRESENT( FailureMessage  ) ) THEN
          WRITE( Message, * )'Unable to allocate ', n, ' element integer array.'
          CALL Error( 'AllocateIntegerVector', Message )
          IF ( PRESENT( From ) ) THEN
             WRITE( Message, * )'Requested From: ', TRIM(From)
             CALL Error( 'AllocateIntegerVector', Message )
          END IF
          IF ( PRESENT( FailureMessage ) ) THEN
             CALL Fatal( 'AllocateIntegerVector', FailureMessage )
          END IF
       END IF
    END IF
!------------------------------------------------------------------------------
  END SUBROUTINE AllocateIntegerVector
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE AllocateLogicalVector( f, n, From, FailureMessage )
DLLEXPORT AllocateLogicalVector
!------------------------------------------------------------------------------
    LOGICAL, POINTER :: f(:)
    INTEGER :: n
    CHARACTER(LEN=*), OPTIONAL :: From, FailureMessage
!------------------------------------------------------------------------------
    INTEGER :: istat
!------------------------------------------------------------------------------

    istat = -1
    IF ( n > 0 ) THEN
       ALLOCATE( f(n), STAT=istat )
    END IF
    IF ( istat /=  0 ) THEN
       IF ( PRESENT( FailureMessage  ) ) THEN
          WRITE( Message, * )'Unable to allocate ', n, ' element integer array.'
          CALL Error( 'AllocateLogicalVector', Message )
          IF ( PRESENT( From ) ) THEN
             WRITE( Message, * )'Requested From: ', TRIM(From)
             CALL Error( 'AllocateLogicalVector', Message )
          END IF
          IF ( PRESENT( FailureMessage ) ) THEN
             CALL Fatal( 'AllocateLogicalVector', FailureMessage )
          END IF
       END IF
    END IF
!------------------------------------------------------------------------------
  END SUBROUTINE AllocateLogicalVector
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE AllocateElementVector( f, n, From, FailureMessage )
DLLEXPORT AllocateElementVector
!------------------------------------------------------------------------------
    TYPE(Element_t), POINTER :: f(:)
    INTEGER :: n
    CHARACTER(LEN=*), OPTIONAL :: From, FailureMessage
!------------------------------------------------------------------------------
    INTEGER :: istat
!------------------------------------------------------------------------------

    istat = -1
    IF ( n > 0 ) THEN
       ALLOCATE( f(n), STAT=istat )
    END IF
    IF ( istat /=  0 ) THEN
       IF ( PRESENT( FailureMessage  ) ) THEN
          WRITE( Message, * )'Unable to allocate ', n, ' element integer array.'
          CALL Error( 'AllocateElementVector', Message )
          IF ( PRESENT( From ) ) THEN
             WRITE( Message, * )'Requested From: ', TRIM(From)
             CALL Error( 'AllocateElementVector', Message )
          END IF
          IF ( PRESENT( FailureMessage ) ) THEN
             CALL Fatal( 'AllocateElementVector', FailureMessage )
          END IF
       END IF
    END IF
!------------------------------------------------------------------------------
  END SUBROUTINE AllocateElementVector
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE AllocateRealArray( f, n1, n2, From, FailureMessage )
DLLEXPORT AllocateRealArray
!------------------------------------------------------------------------------
    REAL(KIND=dp), POINTER :: f(:,:)
    INTEGER :: n1,n2
    CHARACTER(LEN=*), OPTIONAL :: From, FailureMessage
!------------------------------------------------------------------------------
    INTEGER :: istat
!------------------------------------------------------------------------------

    istat = -1
    IF ( n1 > 0 .AND. n2 > 0 ) THEN
       ALLOCATE( f(n1,n2), STAT=istat )
    END IF
    IF ( istat /=  0 ) THEN
       IF ( PRESENT( FailureMessage  ) ) THEN
          WRITE( Message, * )'Unable to allocate ', n1, ' by ', n2, ' element real matrix.'
          CALL Error( 'AllocateRealArray', Message )
          IF ( PRESENT( From ) ) THEN
             WRITE( Message, * )'Requested From: ', TRIM(From)
             CALL Error( 'AllocateRealArray', Message )
          END IF
          IF ( PRESENT( FailureMessage ) ) THEN
             CALL Fatal( 'AllocateRealArray', FailureMessage )
          END IF
       END IF
    END IF
!------------------------------------------------------------------------------
  END SUBROUTINE  AllocateRealArray
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
  SUBROUTINE AllocateComplexArray( f, n1, n2, From, FailureMessage )
DLLEXPORT AllocateComplexArray
!------------------------------------------------------------------------------
    COMPLEX(KIND=dp), POINTER :: f(:,:)
    INTEGER :: n1,n2
    CHARACTER(LEN=*), OPTIONAL :: From, FailureMessage
!------------------------------------------------------------------------------
    INTEGER :: istat
!------------------------------------------------------------------------------

    istat = -1
    IF ( n1 > 0 .AND. n2 > 0 ) THEN
       ALLOCATE( f(n1,n2), STAT=istat )
    END IF
    IF ( istat /=  0 ) THEN
       IF ( PRESENT( FailureMessage  ) ) THEN
          WRITE( Message, * )'Unable to allocate ', n1, ' by ', n2, ' element real matrix.'
          CALL Error( 'AllocateComplexArray', Message )
          IF ( PRESENT( From ) ) THEN
             WRITE( Message, * )'Requested From: ', TRIM(From)
             CALL Error( 'AllocateComplexArray', Message )
          END IF
          IF ( PRESENT( FailureMessage ) ) THEN
             CALL Fatal( 'AllocateComplexArray', FailureMessage )
          END IF
       END IF
    END IF
!------------------------------------------------------------------------------
  END SUBROUTINE  AllocateComplexArray
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE AllocateIntegerArray( f, n1, n2, From, FailureMessage )
DLLEXPORT AllocateIntegerArray
!------------------------------------------------------------------------------
    INTEGER, POINTER :: f(:,:)
    INTEGER :: n1,n2
    CHARACTER(LEN=*), OPTIONAL :: From, FailureMessage
!------------------------------------------------------------------------------
    INTEGER :: istat
!------------------------------------------------------------------------------

    istat = -1
    IF ( n1 > 0 .AND. n2 > 0 ) THEN
       ALLOCATE( f(n1,n2), STAT=istat )
    END IF
    IF ( istat /=  0 ) THEN
       IF ( PRESENT( FailureMessage  ) ) THEN
          WRITE( Message, * )'Unable to allocate ', n1, ' by ', n2, ' element integer matrix.'
          CALL Error( 'AllocateIntegerArray', Message )
          IF ( PRESENT( From ) ) THEN
             WRITE( Message, * )'Requested From: ', TRIM(From)
             CALL Error( 'AllocateIntegerArray', Message )
          END IF
          IF ( PRESENT( FailureMessage ) ) THEN
             CALL Fatal( 'AllocateIntegerArray', FailureMessage )
          END IF
       END IF
    END IF
!------------------------------------------------------------------------------
  END SUBROUTINE  AllocateIntegerArray
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
  SUBROUTINE AllocateLogicalArray( f, n1, n2, From, FailureMessage )
DLLEXPORT AllocateLogicalArray
!------------------------------------------------------------------------------
    LOGICAL, POINTER :: f(:,:)
    INTEGER :: n1,n2
    CHARACTER(LEN=*), OPTIONAL :: From, FailureMessage
!------------------------------------------------------------------------------
    INTEGER :: istat
!------------------------------------------------------------------------------

    istat = -1
    IF ( n1 > 0 .AND. n2 > 0 ) THEN
       ALLOCATE( f(n1,n2), STAT=istat )
    END IF
    IF ( istat /=  0 ) THEN
       IF ( PRESENT( FailureMessage  ) ) THEN
          WRITE( Message, * )'Unable to allocate ', n1, ' by ', n2, ' element integer matrix.'
          CALL Error( 'AllocateLogicalArray', Message )
          IF ( PRESENT( From ) ) THEN
             WRITE( Message, * )'Requested From: ', TRIM(From)
             CALL Error( 'AllocateLogicalArray', Message )
          END IF
          IF ( PRESENT( FailureMessage ) ) THEN
             CALL Fatal( 'AllocateLogicalArray', FailureMessage )
          END IF
       END IF
    END IF
!------------------------------------------------------------------------------
  END SUBROUTINE  AllocateLogicalArray
!------------------------------------------------------------------------------


END MODULE GeneralUtils
