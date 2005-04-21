!/*****************************************************************************
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
! ****************************************************************************/
!
!/*****************************************************************************
! *
! *****************************************************************************
! *
! *                    Author:       Juha Ruokolainen
! *
! *                 Address: Center for Scientific Computing
! *                        Tietotie 6, P.O. BOX 405
! *                          02101 Espoo, Finland
! *                          Tel. +358 0 457 2723
! *                        Telefax: +358 0 457 2302
! *                      EMail: Juha.Ruokolainen@csc.fi
! *
! *                       Date: 07 Oct 2002
! *
! *                Modified by:
! *
! *       Date of modification:
! *
! ****************************************************************************/

 

!------------------------------------------------------------------------------
SUBROUTINE ReloadInput( Model,Solver,dt,TransientSimulation )
!DEC$ATTRIBUTES DLLEXPORT :: ReloadInput
!------------------------------------------------------------------------------
!******************************************************************************
!
!
! Reaload input file from disk to get some dynamic control over solver
! paramters.
!
!
!  ARGUMENTS:
!
!  TYPE(Model_t) :: Model,  
!     INPUT: All model information (mesh, materials, BCs, etc...)
!
!  TYPE(Solver_t) :: Solver
!     INPUT: Linear & nonlinear equation solver options
!
!  REAL(KIND=dp) :: dt,
!     INPUT: Timestep size for time dependent simulations
!
!  LOGICAL :: TransientSimulation
!     INPUT: Steady state or transient simulation
!
!******************************************************************************
  USE Types
  USE Lists
  USE ModelDescription

  IMPLICIT NONE
!------------------------------------------------------------------------------
  TYPE(Solver_t), TARGET :: Solver
  TYPE(Model_t) :: Model
  REAL(KIND=dp) :: dt
  LOGICAL :: TransientSimulation
!------------------------------------------------------------------------------
! Local variables
!------------------------------------------------------------------------------

   CHARACTER(LEN=MAX_NAME_LEN) :: ModelName, MeshDir, MeshName

!------------------------------------------------------------------------------

   OPEN( 11,file='ELMERSOLVER_REREADINFO', STATUS='OLD', ERR=10 )
   READ(11,'(a)') ModelName
   CLOSE(11)

   OPEN( InFileUnit, File=ModelName )
   CALL LoadInputFile( Model, InFileUnit, ModelName, MeshDir, MeshName, .FALSE.,.FALSE. )
   CLOSE( InFileUnit )
 
   RETURN

10 CONTINUE

   OPEN( 11,file='ELMERSOLVER_REREADINFO', STATUS='OLD', ERR=20 )
   READ(11,'(a)') ModelName
   CLOSE(11)

20 CONTINUE

   RETURN

!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
END SUBROUTINE ReloadInput
!------------------------------------------------------------------------------
