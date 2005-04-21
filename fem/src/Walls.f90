!******************************************************************************
!
!       ELMER, A Computational Fluid Dynamics Program.
!
!       Copyright 1st April 1995 - , Center for Scientific Computing,
!                                    Finland.
!
!       All rights reserved. No part of this program may be used,
!       reproduced or transmitted in any form or by any means
!       without the written permission of CSC.
!
!******************************************************************************
!
! This file contains subroutines for the wall boundary conditions of 
! the k-epsilon turbulence model on walls. 
!
!******************************************************************************
!
!                     Author: Jari H�m�l�inen
!
!                    Address: VTT Energy
!                             P.O.Box 1603
!                             FIN-40101 Jyv�skyl�
!                             
!                       Date: 19th June 1996
!
!                Modified by:
!
!       Date of modification:
!
!******************************************************************************
!
!     Name: SOLVE_UFRIC
!
!     Purpose: To solve the friction velocity of the previous iteration based
!              on the wall law. 
!
!     Parameters:
!
!         Input:
!             DENSIT - Density
!             VISCOS - Viscosity 
!             DIST   - Distance from the wall
!             UT     - Tangential velocity of the previous iteration
!
!         Output:
!             UFRIC  - Friction velocity
!             DFX    - Derivative of the wall law
!
!******************************************************************************
      SUBROUTINE SOLVE_UFRIC(DENSIT,VISCOS,DIST,ROUGH,UT,UFRIC,DFX)
DLLEXPORT SOLVER_UFRIC

      IMPLICIT NONE
      DOUBLE PRECISION DENSIT,VISCOS,DIST,ROUGH,UT,UFRIC,DFX,TAUW,  &
      YPLUS, FX, WALL_LAW, D_WALL_LAW

      INTEGER :: ITER 
      INTEGER :: MAXITER=100
      DOUBLE PRECISION ::  TOL=1.0D-14
 
! Default value:
      TAUW = UT / DIST
      UFRIC = DSQRT( TAUW / DENSIT )

      DO ITER=1,MAXITER
         FX  = WALL_LAW( UFRIC,UT,DENSIT,VISCOS,DIST,ROUGH )
         DFX = D_WALL_LAW( UFRIC,UT,DENSIT,VISCOS,DIST,ROUGH )

! Newton step:
         IF (DFX.EQ.0.0d0) STOP 'dfx=0'
         UFRIC = UFRIC - FX/DFX
         YPLUS = DENSIT * UFRIC * DIST / VISCOS
         IF ( DABS(FX) <= TOL ) EXIT
      END DO

      IF ( DABS(FX) > 1.0D-6 ) WRITE(*,*)'Problems in SOLVE_UFRIC, FX=',FX

      RETURN
      END
      


!******************************************************************************
!
!     Name: WALL_LAW
!
!     Purpose: To give difference between the tangential velocity given by 
!     Reichardt�s wall law and the tangential velocity of the previous 
!     iteration.
!
!     Parameters:
!
!         Input:
!             UFRIC  - Friction velocity
!             UT     - Tangential velocity
!             DENSIT - Density
!             VISCOS - Viscosity
!             DIST   - Distance
!
!         Output:
!
!******************************************************************************
      DOUBLE PRECISION FUNCTION WALL_LAW(UFRIC,UT,DENSIT, &
                 VISCOS,DIST,ROUGH)

      IMPLICIT NONE
      DOUBLE PRECISION DENSIT,VISCOS,DIST,ROUGH,UT,UFRIC,DFX, &
      YPLUS

      DOUBLE PRECISION :: DKAPPA = 0.41D0, RAJA


      YPLUS = DENSIT*UFRIC*DIST / VISCOS

! Log-law:
!      RAJA=11.2658567D0 
!      IF(YPLUS.GE.RAJA) THEN
!         WALL_LAW=(UFRIC/DKAPPA)*DLOG(ROUGH*YPLUS)-UT
!      ELSE
!         WALL_LAW=UFRIC*YPLUS-UT
!      ENDIF

! Reichardt�s law:
      WALL_LAW=(UFRIC/DKAPPA)*DLOG(1.0D0+0.4D0*YPLUS)  &
            + UFRIC*7.8D0  &
              *(           &
                 1.0D0-DEXP(-YPLUS/11.0D0) &
                 -(YPLUS/11.0D0)*DEXP(-0.33D0*YPLUS) &
               ) - UT

      RETURN
      END


!******************************************************************************
!
!     Name: D_WALL_LAW
!
!     Purpose: To calculate derivative of the wall law.
!
!     Parameters:
!
!         Input:
!             UFRIC  - Friction velocity
!             UT     - Tangential velocity
!             DENSIT - Density
!             VISCOS - Viscosity
!             DIST   - Distance
!
!         Output:
!
!******************************************************************************
      DOUBLE PRECISION FUNCTION D_WALL_LAW( UFRIC,UT, DENSIT,  &
                    VISCOS,DIST,ROUGH )

      IMPLICIT NONE

      DOUBLE PRECISION DENSIT,VISCOS,DIST,ROUGH,UT,UFRIC,DFX,  &
      YPLUS

      DOUBLE PRECISION :: DKAPPA = 0.41D0, RAJA
      
      YPLUS=DENSIT*UFRIC*DIST/VISCOS

! Log-law:
!      RAJA=11.2658567D0 
!      IF(YPLUS.GE.RAJA) THEN
!         D_WALL_LAW=(1.0D0/DKAPPA)* &
!             ( DLOG(ROUGH*DENSIT*UFRIC*DIST/VISCOS) + 1.0D0 ) 
!      ELSE
!         D_WALL_LAW=DENSIT*DIST*2.0D0*UFRIC/VISCOS
!      ENDIF
 
! Reichardt�s law:
      D_WALL_LAW=DLOG(1.0D0 + 0.4D0*YPLUS)/DKAPPA  &
          + (0.4D0/DKAPPA)*YPLUS/(1.0D0 + 0.4D0*YPLUS) &
          + 7.8D0*( 1.0D0 - DEXP(-YPLUS/11.0D0) -   &
          (YPLUS/11.0D0)*DEXP(-0.33*YPLUS) )  &
          + 7.8D0*(YPLUS/11.0D0)  &
          *(  &
          DEXP(-YPLUS/11.0D0)-DEXP(-0.033*YPLUS)  &
          +0.033D0*YPLUS*DEXP(-0.033*YPLUS) &
          )

      RETURN
      END

!******************************************************************************
!
!     Name: KEWALL
!
!     Purpose: To calculate the boundary values of turbulent kinetic energy
!              and its dissipation based on the wall law.
!
!     Parameters:
!
!         Input:
!             UT     - Tangential velocity of the previous iteration
!             DIST   - Distance from the wall
!             VISCOS - Viscosity
!             DENSIT - Density
!
!         Output:
!             TK     - Turbulent kinetic energy 
!             TEPS   - Turbulent kinetic energy dissipation
!
!******************************************************************************
      SUBROUTINE KEWALL (TK, TEPS, UT, DIST, ROUGH, VISCOS, DENSIT )
DLLEXPORT KEWALL

      IMPLICIT NONE

      DOUBLE PRECISION TK, TEPS, UT, DIST, VISCOS, DENSIT, ROUGH
      DOUBLE PRECISION UFRIC, DFX, UTLOCAL
      DOUBLE PRECISION :: CMYY   = 0.09D0
      DOUBLE PRECISION :: KARMAN = 0.41D0
      DOUBLE PRECISION :: SMALL  = 1.0D-10

      UTLOCAL = DMAX1( UT,SMALL )
      CALL SOLVE_UFRIC(DENSIT,VISCOS,DIST,ROUGH,UTLOCAL,UFRIC,DFX)
      TK   = ( UFRIC**2 ) /  DSQRT( CMYY )
      TEPS = ( UFRIC**3 ) / ( KARMAN * DIST )

      RETURN
      END
!******************************************************************************
