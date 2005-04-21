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
! *     Time integration module
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
! *                       Date: 09 Jun 1997
! *
! *                Modified by:
! *
! *       Date of modification:
! *
! *****************************************************************************/
!------------------------------------------------------------------------------
MODULE TimeIntegrate

   USE Types

   IMPLICIT NONE

CONTAINS

!------------------------------------------------------------------------------
   SUBROUTINE NewmarkBeta( N, dt, MassMatrix, StiffMatrix, &
                   Force, PrevSolution, Beta )
DLLEXPORT NewmarkBeta
!------------------------------------------------------------------------------
    INTEGER :: N
    REAL(KIND=dp) :: Force(:),PrevSolution(:),dt
    REAL(KIND=dp) :: MassMatrix(:,:),StiffMatrix(:,:),Beta

!------------------------------------------------------------------------------
    INTEGER :: i,j,NB

    REAL(KIND=dp) :: s
!------------------------------------------------------------------------------
    NB = SIZE( StiffMatrix,1 )

    DO i=1,NB
      s = 0.0d0
      DO j=1,NB
         IF ( j <= N ) &
            s = s + (1.0d0/dt) * MassMatrix(i,j) * PrevSolution(j) - &
                      (1-Beta) * StiffMatrix(i,j) * PrevSolution(j)

         StiffMatrix(i,j) = Beta * StiffMatrix(i,j) + (1.0d0/dt)*MassMatrix(i,j)
      END DO
      Force(i) = s
    END DO
!------------------------------------------------------------------------------
   END SUBROUTINE NewmarkBeta
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   SUBROUTINE BDFLocal( N, dt, MassMatrix, StiffMatrix, &
                   Force, PrevSolution, Order )
DLLEXPORT BDFLocal
!------------------------------------------------------------------------------

     INTEGER :: N, Order
     REAL(KIND=dp) :: Force(:),PrevSolution(:,:),dt
     REAL(KIND=dp) :: MassMatrix(:,:),StiffMatrix(:,:)


!------------------------------------------------------------------------------
     INTEGER :: i,j,NB

     REAL(KIND=dp) :: s
!------------------------------------------------------------------------------
     NB = SIZE(StiffMatrix,1)
!NB = n

     DO i=1,NB
       s = 0.0d0
       DO j=1,NB
         SELECT CASE( Order)
           CASE(1)
           IF ( j <= N ) &
             s = s + (1.0d0/dt)*MassMatrix(i,j)*PrevSolution(j,1)
           StiffMatrix(i,j) = (1.0d0/dt)*MassMatrix(i,j) + StiffMatrix(i,j)
           CASE(2)
           IF ( j <= N ) &
             s = s + (1.0d0/dt)*MassMatrix(i,j) * ( &
               (4.d0/3.d0)*PrevSolution(j,1) - (1.d0/3.d0)*PrevSolution(j,2) )
           StiffMatrix(i,j) = (1.0d0/dt)*MassMatrix(i,j) &
             + (2.d0/3.d0)*StiffMatrix(i,j)
           CASE(3)
           IF ( j <= N ) &
             s = s + (1.0d0/dt)*MassMatrix(i,j) * ( &
               (18.d0/11.d0)*PrevSolution(j,1) &
               - (9.d0/11.d0)*PrevSolution(j,2) &
               + (2.d0/11.d0)*PrevSolution(j,3) )
           StiffMatrix(i,j) = (1.0d0/dt)*MassMatrix(i,j) &
             + (6.d0/11.d0)*StiffMatrix(i,j)
           CASE(4)
           IF ( j <= N ) &
             s = s + (1.0d0/dt)*MassMatrix(i,j) * ( &
               (48.d0/25.d0)*PrevSolution(j,1) &
               - (36.d0/25.d0)*PrevSolution(j,2) &
               + (16.d0/25.d0)*PrevSolution(j,3) &
               - (3.d0/25.d0)*PrevSolution(j,4) )
           StiffMatrix(i,j) = (1.0d0/dt)*MassMatrix(i,j) &
             + (12.d0/25.d0)*StiffMatrix(i,j)
           CASE(5)
           IF ( j <= N ) &
             s = s + (1.0d0/dt)*MassMatrix(i,j) * ( &
               (300.d0/137.d0)*PrevSolution(j,1) &
               - (300.d0/137.d0)*PrevSolution(j,2) &
               + (200.d0/137.d0)*PrevSolution(j,3) &
               - (75.d0/137.d0)*PrevSolution(j,4) &
               + (12.d0/137.d0)*PrevSolution(j,5) )
           StiffMatrix(i,j) = (1.0d0/dt)*MassMatrix(i,j) &
             + (60.d0/137.d0)*StiffMatrix(i,j)
           CASE DEFAULT
             WRITE( Message, * ) 'Invalid order BDF', Order
             CALL Fatal( 'BDFLocal', Message )
         END SELECT
       END DO
       Force(i) = s
     END DO
!------------------------------------------------------------------------------
   END SUBROUTINE BDFLocal
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
   SUBROUTINE Bossak2ndOrder( N, dt, MassMatrix, DampMatrix, StiffMatrix, &
                        Force, X,V,A,Alpha )
DLLEXPORT Bossak2ndOrder
!------------------------------------------------------------------------------

     INTEGER :: N
     REAL(KIND=dp) :: Force(:),X(:),V(:),A(:),dt
     REAL(KIND=dp) :: Alpha,Beta, Gamma
     REAL(KIND=dp) :: MassMatrix(:,:),DampMatrix(:,:),StiffMatrix(:,:)

!------------------------------------------------------------------------------
     INTEGER :: i,j

     REAL(KIND=dp) :: s, aa
!------------------------------------------------------------------------------
     Gamma = 0.5d0 - Alpha
     Beta = (1.0d0 - Alpha)**2 / 4.0d0
     DO i=1,N
       s = 0.0d0
       DO j=1,N
         s = s + ( (1.0d0 - Alpha) / (Beta*dt**2) ) * MassMatrix(i,j) * X(j)
         s = s + ( (1.0d0 - Alpha) / (Beta*dt)) * MassMatrix(i,j) * V(j)
         s = s - ( (1.0d0 - Alpha) * (1.0d0 - 1.0d0 / (2.0d0*Beta)) + Alpha )*&
                              MassMatrix(i,j) * A(j)

         s = s + ( Gamma / (Beta*dt) ) * DampMatrix(i,j) * X(j)
         s = s + ( Gamma/Beta - 1.0d0) * DampMatrix(i,j) * V(j)
         s = s - ((1.0d0 - Gamma) + Gamma * (1.0d0 - 1.0d0 / (2.0d0*Beta))) * &
                          dt * DampMatrix(i,j) * A(j)

         StiffMatrix(i,j) = StiffMatrix(i,j) +  &
           ( (1.0d0 - Alpha) / (Beta*dt**2) ) * MassMatrix(i,j) + &
                  (Gamma / (Beta*dt)) * DampMatrix(i,j)
       END DO 
       Force(i) = s
     END DO 
   END SUBROUTINE Bossak2ndOrder
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   SUBROUTINE FractionalStep( N, dt, MassMatrix, StiffMatrix, &
                   Force, PrevSolution, Beta, Solver )
!DLLEXPORT FractionalStep
!------------------------------------------------------------------------------
     USE Types
     USE Lists

     TYPE(Solver_t) :: Solver

     INTEGER :: N
     REAL(KIND=dp) :: Force(:),PrevSolution(:),dt, fsstep, fsTheta, fsdTheta, &
                      fsAlpha, fsBeta, MassCoeff, ForceCoeff
     REAL(KIND=dp) :: MassMatrix(:,:),StiffMatrix(:,:),Beta

!------------------------------------------------------------------------------
     INTEGER :: i,j,NB

     REAL(KIND=dp) :: s
!------------------------------------------------------------------------------
     NB = SIZE( StiffMatrix,1 )

! Selvitet��n mik� FS-steppi on menossa ja otetaan vakiot

     fsstep   = ListGetConstReal( Solver % Values, 'fsstep')
     fsTheta  = ListGetConstReal( Solver % Values, 'fsTheta')
     fsdTheta = ListGetConstReal( Solver % Values, 'fsdTheta')
     fsAlpha  = ListGetConstReal( Solver % Values, 'fsAlpha')
     fsBeta   = ListGetConstReal( Solver % Values, 'fsBeta')

     SELECT CASE( INT(fsstep) )     
       CASE(1)
        MassCoeff = fsAlpha * fsTheta
        ForceCoeff = fsBeta * fsTheta 
       CASE(2)
        MassCoeff = fsBeta * fsdTheta
        ForceCoeff = fsAlpha * fsdTheta
       CASE(3)
        MassCoeff = fsAlpha * fsTheta
        ForceCoeff = fsBeta * fsTheta
     END SELECT

     DO i=1,NB
       s = 0.0d0
       DO j=1,NB
          IF ( j <= N ) &
           s = s + (1.0d0/dt) * MassMatrix(i,j) * PrevSolution(j) - &
               ForceCoeff * StiffMatrix(i,j) * PrevSolution(j)

           StiffMatrix(i,j) = MassCoeff * StiffMatrix(i,j) + (1.0d0/dt)*MassMatrix(i,j)
       END DO
       Force(i) = s
     END DO
!------------------------------------------------------------------------------
   END SUBROUTINE FractionalStep
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   SUBROUTINE Newmark2ndOrder( N, dt, MassMatrix, DampMatrix, StiffMatrix, &
                        Force, PrevSol0,PrevSol1, Avarage )
DLLEXPORT Newmark2ndOrder
!------------------------------------------------------------------------------

     INTEGER :: N
     REAL(KIND=dp) :: Force(:),PrevSol0(:),PrevSol1(:),dt
     LOGICAL :: Avarage
     REAL(KIND=dp) :: MassMatrix(:,:),DampMatrix(:,:),StiffMatrix(:,:)

!------------------------------------------------------------------------------
     INTEGER :: i,j

     REAL(KIND=dp) :: s
!------------------------------------------------------------------------------
     IF ( Avarage ) THEN 
       DO i=1,N
         s = 0.0d0
         DO j=1,N
           s = s - ((1/dt**2)*MassMatrix(i,j) - (1/(2*dt))*DampMatrix(i,j) + &
                       StiffMatrix(i,j) / 3 ) * PrevSol0(j)

           s = s + ((2/dt**2)*MassMatrix(i,j) - StiffMatrix(i,j) / 3) *  &
                               PrevSol1(j)

           StiffMatrix(i,j) = StiffMatrix(i,j) / 3 +  &
                        (1/dt**2)*MassMatrix(i,j) + (1/(2*dt))*DampMatrix(i,j)
         END DO
         Force(i) = s
       END DO
     ELSE 
       DO i=1,N
         s = 0.0d0
         DO j=1,N
           s = s - ((1/dt**2)*MassMatrix(i,j) - (1/(2*dt))*DampMatrix(i,j)) * &
                                     PrevSol0(j)

           s = s + (2/dt**2)*MassMatrix(i,j) * PrevSol1(j)

           StiffMatrix(i,j) = StiffMatrix(i,j) +  &
                        (1/dt**2)*MassMatrix(i,j) + (1/(2*dt))*DampMatrix(i,j)
         END DO
         Force(i) = s
       END DO
     END IF
   END SUBROUTINE Newmark2ndOrder
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
END MODULE TimeIntegrate
!------------------------------------------------------------------------------
