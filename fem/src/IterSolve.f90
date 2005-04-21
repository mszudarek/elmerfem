! ******************************************************************************
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
! * Module containing a iterative solver for linear systems.
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

#include <huti_fdefs.h>

!------------------------------------------------------------------------------
MODULE IterSolve

   USE Lists
   USE CRSMatrix
   USE BandMatrix

   IMPLICIT NONE

   !/*
   ! * Iterative method selection
   ! */
   INTEGER, PARAMETER, PRIVATE :: ITER_BiCGStab     =           320
   INTEGER, PARAMETER, PRIVATE :: ITER_TFQMR        =           330
   INTEGER, PARAMETER, PRIVATE :: ITER_CG           =           340
   INTEGER, PARAMETER, PRIVATE :: ITER_CGS          =           350
   INTEGER, PARAMETER, PRIVATE :: ITER_GMRES        =           360

   !/*
   ! * Preconditioning type code
   ! */
   INTEGER, PARAMETER, PRIVATE :: PRECOND_NONE      =           400
   INTEGER, PARAMETER, PRIVATE :: PRECOND_DIAGONAL  =           410
   INTEGER, PARAMETER, PRIVATE :: PRECOND_ILUn      =           420
   INTEGER, PARAMETER, PRIVATE :: PRECOND_ILUT      =           430
   INTEGER, PARAMETER, PRIVATE :: PRECOND_MG        =           440

   LOGICAL :: FirstCall = .TRUE.

CONTAINS


!------------------------------------------------------------------------------
! We use backward error estimate e = ||Ax-b||/(||A|| ||x|| + ||b||)
! as stopping criteriation.
!------------------------------------------------------------------------------
  FUNCTION STOPC( x,b,r,ipar,dpar ) RESULT(err)
!------------------------------------------------------------------------------

     integer :: ipar(*),n
     double precision :: x(*),b(*),r(*),dpar(*),err,res(HUTI_NDIM)

     n = HUTI_NDIM

     CALL CRS_MatrixVectorMultiply( GlobalMatrix,x,res )
     res = res - b(1:n)

     err = SQRT(SUM( res(1:n)**2) ) /  &
        ( SQRT(SUM(GlobalMatrix % Values**2)) * SQRT(SUM(x(1:n)**2)) + SQRT(SUM(b(1:n)**2)) )

  END FUNCTION STOPC
!------------------------------------------------------------------------------

!
!------------------------------------------------------------------------------
  SUBROUTINE IterSolver( A,x,b,SolverParam )
DLLEXPORT IterSolver
!------------------------------------------------------------------------------

    IMPLICIT NONE

!------------------------------------------------------------------------------
    TYPE(Solver_t) :: SolverParam

    REAL(KIND=dp), DIMENSION(:) :: x,b
    TYPE(Matrix_t), POINTER :: A
!------------------------------------------------------------------------------

    REAL(KIND=dp) :: dpar(50),stopfun,dnrm2
    external stopfun
    REAL(KIND=dp), ALLOCATABLE :: work(:,:)
    INTEGER :: k,N,ipar(50),wsize,istat,IterType,PCondType,ILUn

    REAL(KIND=dp) :: ILUT_TOL
    LOGICAL :: Condition,GotIt,AbortNotConverged

    CHARACTER(LEN=MAX_NAME_LEN) :: str

    EXTERNAL MultigridPrec
!------------------------------------------------------------------------------
    N = A % NumberOfRows

    ipar = 0
    dpar = 0.0D0

!------------------------------------------------------------------------------
    str = ListGetString( SolverParam % Values,'Linear System Iterative Method' )

    IF ( str(1:8) == 'bicgstab' ) THEN
      IterType = ITER_BiCGStab
    ELSE IF ( str(1:5) == 'tfqmr' )THEN
      IterType = ITER_TFQMR
    ELSE IF ( str(1:3) == 'cgs' ) THEN
      IterType = ITER_CGS
    ELSE IF ( str(1:2) == 'cg' ) THEN
      IterType = ITER_CG
    ELSE IF ( str(1:5) == 'gmres' ) THEN
      IterType = ITER_GMRES
    END IF
!------------------------------------------------------------------------------

    SELECT CASE ( IterType )

      CASE (ITER_BiCGStab)
        HUTI_WRKDIM = HUTI_BICGSTAB_WORKSIZE
        wsize = HUTI_WRKDIM

      CASE (ITER_TFQMR)
        HUTI_WRKDIM = HUTI_TFQMR_WORKSIZE
        wsize = HUTI_WRKDIM

      CASE (ITER_CG)
        HUTI_WRKDIM = HUTI_CG_WORKSIZE
        wsize = HUTI_WRKDIM

      CASE (ITER_CGS)
        HUTI_WRKDIM = HUTI_CGS_WORKSIZE
        wsize = HUTI_WRKDIM
          
      CASE (ITER_GMRES)

        HUTI_GMRES_RESTART = ListGetInteger( SolverParam % Values, &
             'Linear System GMRES Restart',  GotIt ) 
        IF ( .NOT. GotIT ) HUTI_GMRES_RESTART = 10
        HUTI_WRKDIM = HUTI_GMRES_WORKSIZE + HUTI_GMRES_RESTART
        wsize = HUTI_WRKDIM

     END SELECT
!------------------------------------------------------------------------------
          
     HUTI_STOPC = HUTI_TRESID_SCALED_BYB
     HUTI_NDIM  = N

     HUTI_DBUGLVL  = ListGetInteger( SolverParam % Values, &
           'Linear System Residual Output', GotIt )

     IF ( .NOT.Gotit ) HUTI_DBUGLVL = 1

     IF ( .NOT. OutputLevelMask(6) )  HUTI_DBUGLVL = 0

     HUTI_MAXIT = ListGetInteger( SolverParam % Values, &
         'Linear System Max Iterations', minv=1 )
 
     ALLOCATE( work(N,wsize),stat=istat )
     IF ( istat /= 0 ) THEN
       CALL Fatal( 'IterSolve', 'Memory allocation failure.' )
     END IF

     IF ( ALL(x == 0.0) ) x = 1.0d-8
     HUTI_INITIALX = HUTI_USERSUPPLIEDX

     HUTI_TOLERANCE = ListGetConstReal( SolverParam % Values, &
             'Linear System Convergence Tolerance' )
!------------------------------------------------------------------------------

     str = ListGetString( SolverParam % Values, &
      'Linear System Preconditioning',gotit )

     IF ( .NOT.gotit ) str = 'none'

     IF ( str(1:4) == 'none' ) THEN
       PCondType = PRECOND_NONE
     ELSE IF ( str(1:8) == 'diagonal' ) THEN
       PCondType = PRECOND_DIAGONAL
     ELSE IF ( str(1:4) == 'ilut' ) THEN
       ILUT_TOL = ListGetConstReal( SolverParam % Values, &
           'Linear System ILUT Tolerance',GotIt )
       PCondType = PRECOND_ILUT
     ELSE IF ( str(1:3) == 'ilu' ) THEN
       ILUn = ICHAR(str(4:4)) - ICHAR('0')
       IF ( ILUn  < 0 .OR. ILUn > 9 ) ILUn = 0
       PCondType = PRECOND_ILUn
     ELSE IF ( str(1:9) == 'multigrid' ) THEN
       PCondType = PRECOND_MG
     ELSE
       CALL Warn( 'IterSolve', 'Unknown preconditioner type, feature disabled.' )
     END IF


     IF ( .NOT. ListGetLogical( SolverParam % Values, 'No Precondition Recompute',GotIt ) ) THEN
        n = ListGetInteger( SolverParam % Values, 'Linear System Precondition Recompute', GotIt )
        IF ( n <= 0 ) n = 1

        IF ( .NOT. ASSOCIATED( A % ILUValues ) .OR. MOD( A % SolveCount, n ) == 0 ) THEN

           IF ( A % Format == MATRIX_CRS ) THEN

             IF ( A % Complex ) THEN
                IF ( PCondType == PRECOND_ILUn ) THEN
                   Condition = CRS_ComplexIncompleteLU(A,ILUn)
                ELSE IF ( PCondType == PRECOND_ILUT ) THEN
                   Condition = CRS_ComplexILUT( A,ILUT_TOL )
                END IF
             ELSE
                IF ( PCondType == PRECOND_ILUn ) THEN
                   Condition = CRS_IncompleteLU(A,ILUn)
                ELSE IF ( PCondType == PRECOND_ILUT ) THEN
                   Condition = CRS_ILUT( A,ILUT_TOL )
                END IF
             END IF

           ELSE

             IF ( PCondType == PRECOND_ILUn ) THEN
               CALL Warn( 'IterSolve', 'No ILU Preconditioner for Band Matrix format,' )
               CALL Warn( 'IterSolve', 'using Diagonal preconditioner instead...' )
   
               PCondType = PRECOND_DIAGONAL
             END IF
           END IF
        END IF
     END IF

     A % SolveCount = A % SolveCount + 1
!------------------------------------------------------------------------------

     AbortNotConverged = ListGetLogical( SolverParam % Values, &
          'Linear System Abort Not Converged', GotIt )
     IF ( .NOT. GotIt ) AbortNotConverged = .TRUE.

!------------------------------------------------------------------------------
     FirstCall = .TRUE.


     GlobalMatrix => A

     IF ( .NOT. A % Complex ) THEN
!------------------------------------------------------------------------------
     SELECT CASE ( IterType )
!------------------------------------------------------------------------------

       CASE (ITER_BiCGStab)
         SELECT CASE( PCondType )
           CASE (PRECOND_NONE)
             CALL huti_d_bicgstab( x, b, ipar, dpar, work, & 
                CRS_MatrixVectorProd, 0, 0, 0, 0, STOPC )

           CASE (PRECOND_DIAGONAL)
             CALL huti_d_bicgstab( x, b, ipar, dpar, work, &
                CRS_MatrixVectorProd, &
                    CRS_DiagPrecondition, 0, 0, 0, STOPC )

           CASE (PRECOND_ILUn, PRECOND_ILUT)
             CALL huti_d_bicgstab( x, b, ipar, dpar, work, &
                CRS_MatrixVectorProd, &
                   CRS_LUPrecondition, 0, 0, 0, STOPC )

           CASE (PRECOND_MG)
             CALL huti_d_bicgstab( x, b, ipar, dpar, work, &
                CRS_MatrixVectorProd, &
                   MultiGridPrec, 0, 0, 0, STOPC )
         END SELECT

!------------------------------------------------------------------------------
         
       CASE (ITER_TFQMR)
         SELECT CASE( PCondType )
           CASE (PRECOND_NONE)
              CALL huti_d_tfqmr( x, b, ipar, dpar, work, &
                 CRS_MatrixVectorProd, 0, 0, 0, 0, STOPC )

           CASE (PRECOND_DIAGONAL)
             CALL huti_d_tfqmr( x, b, ipar, dpar, work, &
                CRS_MatrixVectorProd, &
                   CRS_DiagPrecondition, 0, 0, 0, STOPC )

           CASE (PRECOND_ILUn, PRECOND_ILUT)
             CALL huti_d_tfqmr( x, b, ipar, dpar, work, &
                CRS_MatrixVectorProd, &
                   CRS_LUPrecondition, 0, 0, 0, STOPC )

           CASE (PRECOND_MG)
             CALL huti_d_tfqmr( x, b, ipar, dpar, work, &
                CRS_MatrixVectorProd, &
                   MultiGridPrec, 0, 0, 0, STOPC )
         END SELECT

!------------------------------------------------------------------------------

       CASE (ITER_CG)
         SELECT CASE( PCondType )
           CASE (PRECOND_NONE)
             CALL huti_d_cg( x, b, ipar, dpar, work, &
                 CRS_MatrixVectorProd, 0, 0, 0, 0, STOPC )

           CASE (PRECOND_DIAGONAL)
             CALL huti_d_cg( x, b, ipar, dpar, work, &
                 CRS_MatrixVectorProd, &
                     CRS_DiagPrecondition, 0, 0, 0, STOPC )

           CASE (PRECOND_ILUn, PRECOND_ILUT)
             CALL huti_d_cg( x, b, ipar, dpar, work, &
                 CRS_MatrixVectorProd, &
                     CRS_LUPrecondition, 0, 0, 0, STOPC )

           CASE (PRECOND_MG)
             CALL huti_d_cg( x, b, ipar, dpar, work, &
                CRS_MatrixVectorProd, &
                   MultiGridPrec, 0, 0, 0, STOPC )
         END SELECT
          

!------------------------------------------------------------------------------

       CASE (ITER_CGS)
         SELECT CASE( PCondType )
           CASE (PRECOND_NONE)
             CALL huti_d_cgs( x, b, ipar, dpar, work, &
                CRS_MatrixVectorProd, 0, 0, 0, 0, STOPC )

           CASE (PRECOND_DIAGONAL)
             CALL huti_d_cgs( x, b, ipar, dpar, work, &
                CRS_MatrixVectorProd, &
                   CRS_DiagPrecondition, 0, 0, 0, STOPC )

           CASE (PRECOND_ILUn, PRECOND_ILUT)
             CALL huti_d_cgs( x, b, ipar, dpar, work, &
                CRS_MatrixVectorProd, &
                    CRS_LUPrecondition, 0, 0, 0, STOPC )

           CASE (PRECOND_MG)
             CALL huti_d_cgs( x, b, ipar, dpar, work, &
                CRS_MatrixVectorProd, &
                   MultiGridPrec, 0, 0, 0, STOPC )
         END SELECT
          
!------------------------------------------------------------------------------

       CASE (ITER_GMRES)
         SELECT CASE( PCondType )
           CASE (PRECOND_NONE)
              CALL huti_d_gmres( x, b, ipar, dpar, work, CRS_MatrixVectorProd, &
                                  0, 0, 0, 0, STOPC )

           CASE (PRECOND_DIAGONAL)
              CALL huti_d_gmres( x, b, ipar, dpar, work, &
                 CRS_MatrixVectorProd, CRS_DiagPrecondition, 0, 0, 0, STOPC )

           CASE (PRECOND_ILUn, PRECOND_ILUT)
              CALL huti_d_gmres( x, b, ipar, dpar, work, &
                   CRS_MatrixVectorProd, CRS_LUPrecondition, 0, 0, 0, STOPC )

           CASE (PRECOND_MG)
              CALL huti_d_gmres( x, b, ipar, dpar, work, &
                   CRS_MatrixVectorProd, MultiGridPrec, 0, 0, 0, STOPC )
       END SELECT
!------------------------------------------------------------------------------
     END SELECT
!------------------------------------------------------------------------------
     ELSE
     HUTI_NDIM = HUTI_NDIM / 2
!------------------------------------------------------------------------------
     SELECT CASE ( IterType )
!------------------------------------------------------------------------------
       CASE (ITER_BiCGStab)
         SELECT CASE( PCondType )
           CASE (PRECOND_NONE)
             CALL huti_z_bicgstab( x,b,ipar,dpar,work, & 
               CRS_ComplexMatrixVectorProd,0,0,0,0,STOPC )

           CASE (PRECOND_DIAGONAL)
             CALL huti_z_bicgstab( x,b,ipar,dpar,work, &
                CRS_ComplexMatrixVectorProd, &
                   CRS_ComplexDiagPrecondition,0,0,0,STOPC )

           CASE (PRECOND_ILUn, PRECOND_ILUT)
             CALL huti_z_bicgstab( x,b,ipar,dpar,work, &
                CRS_ComplexMatrixVectorProd, &
                   CRS_ComplexLUPrecondition,0,0,0,STOPC )

           CASE (PRECOND_MG)
             CALL huti_z_bicgstab( x,b,ipar,dpar,work, &
                CRS_ComplexMatrixVectorProd, MultigridPrec,0,0,0,STOPC )
         END SELECT

!------------------------------------------------------------------------------
         
       CASE (ITER_TFQMR)
         SELECT CASE( PCondType )
           CASE (PRECOND_NONE)
             CALL huti_z_tfqmr( x,b,ipar,dpar,work, &
                 CRS_ComplexMatrixVectorProd,0,0,0,0,STOPC )

           CASE (PRECOND_DIAGONAL)
             CALL huti_z_tfqmr( x,b,ipar,dpar,work, &
                CRS_ComplexMatrixVectorProd, &
                   CRS_ComplexDiagPrecondition,0,0,0,STOPC )

           CASE (PRECOND_ILUn, PRECOND_ILUT)
             CALL huti_z_tfqmr( x,b,ipar,dpar,work, &
                CRS_ComplexMatrixVectorProd, &
                   CRS_ComplexLUPrecondition,0,0,0,STOPC )

           CASE (PRECOND_MG)
             CALL huti_z_tfqmr( x,b,ipar,dpar,work, &
                CRS_ComplexMatrixVectorProd, MultigridPrec,0,0,0,STOPC )
         END SELECT

!------------------------------------------------------------------------------

       CASE (ITER_CG)
         SELECT CASE( PCondType )
           CASE (PRECOND_NONE)
             CALL huti_z_cg( x,b,ipar,dpar,work, &
                 CRS_ComplexMatrixVectorProd,0,0,0,0,STOPC )

           CASE (PRECOND_DIAGONAL)
             CALL huti_z_cg( x,b,ipar,dpar,work, &
                CRS_ComplexMatrixVectorProd, &
                    CRS_ComplexDiagPrecondition,0,0,0,STOPC )

           CASE (PRECOND_ILUn, PRECOND_ILUT)
             CALL huti_z_cg( x,b,ipar,dpar,work, &
                CRS_ComplexMatrixVectorProd, &
                    CRS_ComplexLUPrecondition,0,0,0,STOPC )

           CASE (PRECOND_MG)
             CALL huti_z_cg( x,b,ipar,dpar,work, &
                CRS_ComplexMatrixVectorProd, MultigridPrec,0,0,0,STOPC )
         END SELECT

!------------------------------------------------------------------------------

       CASE (ITER_CGS)
         SELECT CASE( PCondType )
           CASE (PRECOND_NONE)
             CALL huti_z_cgs( x,b,ipar,dpar,work, CRS_ComplexMatrixVectorProd, &
                                  0,0,0,0,STOPC )

           CASE (PRECOND_DIAGONAL)
             CALL huti_z_cgs( x,b,ipar,dpar,work, &
                CRS_ComplexMatrixVectorProd, CRS_ComplexDiagPrecondition,0,0,0,STOPC )

           CASE (PRECOND_ILUn, PRECOND_ILUT)
             CALL huti_z_cgs( x,b,ipar,dpar,work, &
                  CRS_ComplexMatrixVectorProd, CRS_ComplexLUPrecondition,0,0,0,STOPC )

           CASE (PRECOND_MG)
             CALL huti_z_cgs( x,b,ipar,dpar,work, &
                CRS_ComplexMatrixVectorProd, MultigridPrec,0,0,0,STOPC )
         END SELECT

!------------------------------------------------------------------------------

       CASE (ITER_GMRES)
         SELECT CASE( PCondType )
           CASE (PRECOND_NONE)
             CALL huti_z_gmres( x,b,ipar,dpar,work, CRS_ComplexMatrixVectorProd, &
                                  0,0,0,0,STOPC )

           CASE (PRECOND_DIAGONAL)
             CALL huti_z_gmres( x,b,ipar,dpar,work, &
                CRS_ComplexMatrixVectorProd, CRS_ComplexDiagPrecondition,0,0,0,STOPC )

           CASE (PRECOND_ILUn, PRECOND_ILUT)
             CALL huti_z_gmres( x,b,ipar,dpar,work, &
                  CRS_ComplexMatrixVectorProd, CRS_ComplexLUPrecondition,0,0,0,STOPC )

           CASE (PRECOND_MG)
             CALL huti_z_gmres( x,b,ipar,dpar,work, &
                CRS_ComplexMatrixVectorProd, MultigridPrec,0,0,0,STOPC )
       END SELECT
!------------------------------------------------------------------------------
     END SELECT
!------------------------------------------------------------------------------
     END IF
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
     IF ( HUTI_INFO /= HUTI_CONVERGENCE ) THEN
        IF ( AbortNotConverged ) THEN
           CALL Fatal( 'IterSolve', 'Failed convergence tolerances.' )
        ELSE
           CALL Error( 'IterSolve', 'Failed convergence tolerances.' )
        END IF
     END IF
!------------------------------------------------------------------------------
          
     DEALLOCATE( work )

!------------------------------------------------------------------------------
  END SUBROUTINE IterSolver 
!------------------------------------------------------------------------------

END MODULE IterSolve
