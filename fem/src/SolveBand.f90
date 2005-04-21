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
! * call LAPACK band matrix solvers.
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
! *                       Date: 08 Jun 1997
! *
! *                Modified by:
! *
! *       Date of modification:
! *
! *****************************************************************************/


      SUBROUTINE SolveBandLapack( N,M,A,X,Subband,Band )
DLLEXPORT SolveBandLapack

      IMPLICIT NONE

      INTEGER :: N,M,Subband,Band,i,j
      DOUBLE PRECISION :: A(Band,N),X(M,N)

      INTEGER :: IPIV(N),INFO

      IF ( N .LE. 0 ) RETURN

      INFO = 0
      CALL DGBTRF( N,N,Subband,Subband,A,Band,IPIV,INFO )
      IF ( info /= 0 ) THEN
         PRINT*,'ERROR: SolveBand: singular matrix. LAPACK DGBTRF info: ',info
         STOP
      END IF

      INFO = 0
      CALL DGBTRS( 'N',N,Subband,Subband,M,A,Band,IPIV,X,N,INFO )
        IF ( info /= 0 ) THEN
        PRINT*,'ERROR: SolveBand: singular matrix. LAPACK DGBTRS info: ',info
          STOP
        END IF

      END


      SUBROUTINE SolveComplexBandLapack( N,M,A,X,Subband,Band )
DLLEXPORT SolveBandLapack

      IMPLICIT NONE

      INTEGER :: N,M,Subband,Band,i,j
      DOUBLE COMPLEX :: A(Band,N),X(M,N)

      INTEGER :: IPIV(N),INFO

      IF ( N .LE. 0 ) RETURN

      INFO = 0
      CALL ZGBTRF( N,N,Subband,Subband,A,Band,IPIV,INFO )
        IF ( info /= 0 ) THEN
        PRINT*,'ERROR: SolveBand: singular matrix. LAPACK ZGBTRF info: ',info
          STOP
        END IF

      INFO = 0
      CALL ZGBTRS( 'N',N,Subband,Subband,M,A,Band,IPIV,X,N,INFO )
        IF ( info /= 0 ) THEN
        PRINT*,'ERROR: SolveBand: singular matrix. LAPACK ZGBTRS info: ',info
          STOP
        END IF

      END
