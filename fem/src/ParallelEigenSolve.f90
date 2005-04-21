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
! * Parallel eigensystem solver.
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

MODULE ParallelEigenSolve

   USE CRSMatrix
   USE IterSolve
   USE Multigrid
   USE SParIterGlobals
   USE SparIterSolve
   USE ParallelUtils

   IMPLICIT NONE

CONTAINS

!------------------------------------------------------------------------------
     SUBROUTINE ParallelArpackEigenSolve( Solver,Matrix,N,NEIG,EigValues,EigVectors )
!------------------------------------------------------------------------------
!
! This routine is modified from the arpack examples driver dndrv3 to
! the suit the needs of ELMER.
!
!  Oct 21 2000, Juha Ruokolainen 
!
!\Original Authors
!     Richard Lehoucq
!     Danny Sorensen
!     Chao Yang
!     Dept. of Computational &
!     Applied Mathematics
!     Rice University
!     Houston, Texas
!
! FILE: ndrv3.F   SID: 2.4   DATE OF SID: 4/22/96   RELEASE: 2
!
!
!

      IMPLICIT NONE

INCLUDE "mpif.h"

      TYPE(Matrix_t), POINTER :: Matrix
      TYPE(Solver_t), TARGET :: Solver
      INTEGER :: N, NEIG, DPERM(n)
      COMPLEX(KIND=dp) :: EigValues(:), EigVectors(:,:)

#ifdef USE_ARPACK
!
!     %--------------%
!     | Local Arrays |
!     %--------------%
!
      TYPE(Matrix_t), POINTER :: PMatrix
      TYPE(Solver_t), POINTER :: PSolver
      REAL(KIND=dp), TARGET :: WORKD(3*N), RESID(N),bb(N),xx(N)
      REAL(KIND=dp), POINTER :: x(:), b(:)
      INTEGER :: IPARAM(11), IPNTR(14)
      INTEGER, ALLOCATABLE :: Perm(:)
      LOGICAL, ALLOCATABLE :: Choose(:)
      REAL(KIND=dp), ALLOCATABLE :: WORKL(:), D(:,:), WORKEV(:), V(:,:)

!
!     %---------------%
!     | Local Scalars |
!     %---------------%
!
      CHARACTER ::     BMAT*1, Which*2
      INTEGER   ::     IDO, NCV, lWORKL, kinfo, i, j, k, l, p, pn, IERR, iter, &
                       NCONV, maxitr, ishfts, mode, istat, DOFs, LinIter
      LOGICAL   ::     First, Stat, Direct = .FALSE., &
                       Iterative = .FALSE., NewSystem
      REAL(KIND=dp) :: SigmaR, SigmaI, TOL, s, Residual(n), Solution(n), ForceVector(n), LinConv, ILUTOL
!
      REAL(KIND=dp), POINTER :: SaveValues(:)
      CHARACTER(LEN=MAX_NAME_LEN) :: str

!     %-----------------------%
!     | Executable Statements |
!     %-----------------------%
!
      Solution    = 0
      ForceVector = 1
      Residual    = 0

      DOFs = Solver % Variable % DOFs
      CALL ParallelInitSolve( Matrix, Solution, ForceVector, Residual, DOFs, Solver % Mesh )

      PMatrix => ParallelMatrix( Matrix ) 
      PN = PMatrix % NumberOFRows

!     %----------------------------------------------------%
!     | The number N is the dimension of the matrix. A     |
!     | generalized eigenvalue problem is solved (BMAT =   |
!     | 'G'.) NEV is the number of eigenvalues to be       |
!     | approximated.  The user can modify NEV, NCV, WHICH |
!     | to solve problems of different sizes, and to get   |
!     | different parts of the spectrum.  However, The     |
!     | following conditions must be satisfied:            |
!     |                     N <= MAXN,                     | 
!     |                   NEV <= MAXNEV,                   |
!     |               NEV + 1 <= NCV <= MAXNCV             | 
!     %----------------------------------------------------%
!
      NCV = 3 * NEIG + 1

      ALLOCATE( WORKL(3*NCV**2 + 6*NCV), D(NCV,3), &
         WORKEV(3*NCV), V(PN,NCV), CHOOSE(NCV), STAT=istat )

      IF ( istat /= 0 ) THEN
         CALL Fatal( 'EigenSolve', 'Memory allocation error.' )
      END IF
!
!     %--------------------------------------------------%
!     | The work array WORKL is used in DSAUPD as        |
!     | workspace.  Its dimension LWORKL is set as       |
!     | illustrated below.  The parameter TOL determines |
!     | the stopping criterion.  If TOL<=0, machine      |
!     | precision is used.  The variable IDO is used for |
!     | reverse communication and is initially set to 0. |
!     | Setting INFO=0 indicates that a random vector is |
!     | generated in DSAUPD to start the Arnoldi         |
!     | iteration.                                       |
!     %--------------------------------------------------%
!
      TOL = ListGetConstReal( Solver % Values, 'Eigen System Convergence Tolerance', stat )
      IF ( .NOT. stat ) THEN
         TOL = 100 * ListGetConstReal( Solver % Values, 'Linear System Convergence Tolerance' )
      END IF
      IDO   = 0
      kinfo = 0
      lWORKL = 3*NCV**2 + 6*NCV 
!
!     %---------------------------------------------------%
!     | This program uses exact shifts with respect to    |
!     | the current Hessenberg matrix (IPARAM(1) = 1).    |
!     | IPARAM(3) specifies the maximum number of Arnoldi |
!     | iterations allowed.  Mode 2 of DSAUPD is used     |
!     | (IPARAM(7) = 2).  All these options may be        |
!     | changed by the user. For details, see the         |
!     | documentation in DSAUPD.                          |
!     %---------------------------------------------------%
!
      ishfts = 1
      BMAT  = 'G'
      IF ( Matrix % Lumped ) THEN
         Mode  =  2
         SELECT CASE( ListGetString(Solver % Values,'Eigen System Select',stat) )
         CASE( 'smallest magnitude' )
              Which = 'SM'
         CASE( 'largest magnitude')
              Which = 'LM'
         CASE DEFAULT
              Which = 'SM'
         END SELECT
      ELSE
         Mode  = 3
         SELECT CASE( ListGetString(Solver % Values,'Eigen System Select',stat) )
         CASE( 'smallest magnitude' )
              Which = 'LM'
         CASE( 'largest magnitude')
              Which = 'SM'
         CASE DEFAULT
              Which = 'LM'
         END SELECT
      END IF

      Maxitr = ListGetInteger( Solver % Values, 'Eigen System Max Iterations', stat )
      IF ( .NOT. stat ) Maxitr = 300
!
      IPARAM(1) = ishfts
      IPARAM(3) = maxitr 
      IPARAM(7) = mode

      SigmaR = 0.0d0
      SigmaI = 0.0d0
      V = 0.0d0

!     Compute LU-factors for (A-\sigma M) (if consistent mass matrix)
!
      IF ( .NOT. Matrix % Lumped ) THEN
         Direct = ListGetString( Solver % Values, &
           'Linear System Solver', stat ) == 'direct'
         IF ( Direct ) Stat = CRS_ILUT(Matrix, 0.0d0)
      END IF

      LinIter = ListGetInteger( Solver % Values, 'Linear System Max Iterations', stat )
      IF ( .NOT. Stat ) LinIter = 1000
      LinConv = ListGetConstReal( Solver % Values, 'Linear System Convergence Tolerance', stat )
      IF ( .NOT. Stat ) LinConv = 1.0D-9
!      Preconditiong:
!      --------------
      str = ListGetString( Solver % Values, 'Linear System Preconditioning', stat )

      IF ( str == 'ilut' )  THEN
        ILUTOL = ListGetConstReal( Solver % Values, &
             'Linear System ILUT Tolerance' )

        stat = CRS_ILUT( PMatrix, ILUTOL )
      ELSE IF ( str(1:3) == 'ilu' ) THEN
         k = ICHAR(str(4:4)) - ICHAR('0')
         IF ( k < 0 .OR. k > 9 ) k = 0
         stat = CRS_IncompleteLU( PMatrix, k )
      END IF

      IF ( .NOT. ASSOCIATED( Matrix % RHS ) ) THEN
         ALLOCATE( Matrix % RHS(N) )
         Matrix % RHS = 0.0d0
      END IF
!
!     %-------------------------------------------%
!     | M A I N   L O O P (Reverse communication) |
!     %-------------------------------------------%
!
      iter = 1
      NewSystem = .TRUE.

      Iterative = ListGetString( Solver % Values, &
        'Linear System Solver', stat ) == 'iterative'

      stat = ListGetLogical( Solver % Values,  'No Precondition Recompute', stat  )

      IF ( Iterative .AND. Stat ) THEN
         CALL ListAddLogical( Solver % Values, 'No Precondition Recompute', .FALSE. )
      END IF


      DO WHILE( ido /= 99 )
!
!        %---------------------------------------------%
!        | Repeatedly call the routine DSAUPD and take | 
!        | actions indicated by parameter IDO until    |
!        | either convergence is indicated or maxitr   |
!        | has been exceeded.                          |
!        %---------------------------------------------%
!
         IF ( Matrix % Symmetric ) THEN
            CALL PDSAUPD ( MPI_COMM_WORLD, ido, BMAT, PN, Which, NEIG, TOL, &
              RESID, NCV, V, PN, IPARAM, IPNTR, WORKD, WORKL, lWORKL, kinfo )
         ELSE
            CALL PDNAUPD ( MPI_COMM_WORLD, ido, BMAT, PN, Which, NEIG, TOL, &
              RESID, NCV, V, PN, IPARAM, IPNTR, WORKD, WORKL, lWORKL, kinfo )
         END IF
!
         IF (ido == -1 .OR. ido == 1) THEN
            WRITE( Message, * ) ' Arnoldi iteration: ', Iter
            CALL Info( 'EigenSolve', Message, Level=5 )
            iter = iter + 1
!---------------------------------------------------------------------
!             Perform  y <--- OP*x = inv[M]*A*x   (lumped mass)
!                      ido =-1 inv(A-sigmaR*M)*M*x 
!                      ido = 1 inv(A-sigmaR*M)*z
!---------------------------------------------------------------------
            IF ( .NOT. Matrix % Lumped .AND. ido == 1 ) THEN
               x => workd(ipntr(2):ipntr(2)+PN-1)
               b => workd(ipntr(3):ipntr(3)+PN-1)
               IF ( Solver % MultiGridSolver ) THEN
                  ForceVector = 0
                  Solution    = 0
                  j = 0
                  DO i=1,n
                     k = (Matrix % INVPerm(i) + DOFs-1) / DOFs
                     IF ( Solver % Mesh % Nodes % NeighbourList(k) % Neighbours(1) == ParEnv % MyPE ) THEN
                        j = j + 1
                        ForceVector(i) = b(j)
                        Solution(i)    = x(j)
                     END IF
                  END DO

                  PSolver => Solver
                  CALL MultiGridSolve( Matrix, Solution, ForceVector,  DOFs, &
                        PSolver, Solver % MultiGridLevel, NewSystem )

                  j = 0
                  DO i=1,n
                     k = (Matrix % INVPerm(i) + DOFs-1) / DOFs
                     IF ( Solver % Mesh % Nodes % NeighbourList(k) % Neighbours(1) == ParEnv % MyPE ) THEN
                        j = j + 1
                        x(j) = Solution(i)
                     END IF
                  END DO
               ELSE
                  CALL BiCGParEigen( Matrix,x,b,Residual,LinIter,LinConv )
               END IF
            ELSE
               x => workd(ipntr(1):ipntr(1)+PN-1)
               b => workd(ipntr(2):ipntr(2)+PN-1)

               SaveValues => Matrix % Values
               Matrix % Values => Matrix % MassValues
               CALL MGmv( Matrix, x, b, .FALSE., .TRUE. )
               Matrix % Values => SaveValues

               x = b
               x => workd(ipntr(2):ipntr(2)+PN-1)
               b => workd(ipntr(1):ipntr(1)+PN-1)

               IF ( Solver % MultiGridSolver ) THEN
                  ForceVector = 0
                  Solution    = 0
                  j = 0
                  DO i=1,n
                     k = (Matrix % INVPerm(i) + DOFs-1) / DOFs
                     IF ( Solver % Mesh % Nodes % NeighbourList(k) % Neighbours(1) == ParEnv % MyPE ) THEN
                        j = j + 1
                        ForceVector(i) = b(j)
                        Solution(i)    = x(j)
                     END IF
                  END DO

                  PSolver => Solver
                  CALL MultiGridSolve( Matrix, Solution, ForceVector, DOFs,  &
                       PSolver, Solver % MultiGridLevel, NewSystem )

                  j = 0
                  DO i=1,n
                     k = (Matrix % INVPerm(i) + DOFs-1) / DOFs
                     IF ( Solver % Mesh % Nodes % NeighbourList(k) % Neighbours(1) == ParEnv % MyPE ) THEN
                        j = j + 1
                        x(j) = Solution(i)
                     END IF
                  END DO
               ELSE
                  CALL BICGParEigen( Matrix,Solution,ForceVector,Residual,LinIter,LinConv )
               END IF
            END IF
         ELSE IF (ido == 2) THEN
!
!           %-----------------------------------------%
!           |         Perform  y <--- M*x.            |
!           | Need the matrix vector multiplication   |
!           | routine here that takes WORKD(IPNTR(1)) |
!           | as the input and returns the result to  |
!           | WORKD(IPNTR(2)).                        |
!           %-----------------------------------------%
!
            IF ( Matrix % Lumped ) THEN
               DO i=0,n-1
                  WORKD( IPNTR(2)+i ) = WORKD( IPNTR(1)+i ) * &
                    Matrix % MassValues( Matrix % Diag(i+1) )
               END DO
            ELSE
               x => workd(ipntr(1):ipntr(1)+PN-1)
               b => workd(ipntr(2):ipntr(2)+PN-1)

               SaveValues => Matrix % Values
               Matrix % Values => Matrix % MassValues
               CALL MGmv( Matrix, x, b, .FALSE., .TRUE. )
               Matrix % Values => SaveValues
            END IF
         END IF 

         IF ( NewSystem .AND. ido /= 2 ) THEN
            IF ( Iterative ) THEN
               CALL ListAddLogical( Solver % Values,  'No Precondition Recompute', .TRUE. )
            END IF
            NewSystem = .FALSE.
         END IF
      END DO
!
!     %-----------------------------------------%
!     | Either we have convergence, or there is |
!     | an error.                               |
!     %-----------------------------------------%
!
      IF ( kinfo /= 0 ) THEN
!
!        %--------------------------%
!        | Error message, check the |
!        | documentation in DNAUPD  |
!        %--------------------------%
!
         WRITE( Message, * ) 'Error with DNAUPD, info = ',kinfo
         CALL Fatal( 'EigenSolve', Message )
!
      END IF
!
!     %-------------------------------------------%
!     | No fatal errors occurred.                 |
!     | Post-Process using DSEUPD.                |
!     |                                           |
!     | Computed eigenvalues may be extracted.    |  
!     |                                           |
!     | Eigenvectors may also be computed now if  |
!     | desired.  (indicated by rvec = .true.)    | 
!     %-------------------------------------------%
!        
      D = 0.0d0
      IF ( Matrix % Symmetric ) THEN
         CALL pDSEUPD ( MPI_COMM_WORLD, .TRUE., 'A', Choose, D, V, PN, SigmaR,  &
            BMAT, PN, Which, NEIG, TOL, RESID, NCV, V, PN, &
            IPARAM, IPNTR, WORKD, WORKL, lWORKL, IERR )
      ELSE
         CALL pDNEUPD ( MPI_COMM_WORLD, .TRUE., 'A', Choose, D, D(1,2), &
            V, PN, SigmaR, SigmaI, WORKEV, BMAT, PN, &
            Which, NEIG, TOL, RESID, NCV, V, PN, &
            IPARAM, IPNTR, WORKD, WORKL, lWORKL, IERR )
      END IF

!     %----------------------------------------------%
!     | Eigenvalues are returned in the First column |
!     | of the two dimensional array D and the       |
!     | corresponding eigenvectors are returned in   |
!     | the First NEV columns of the two dimensional |
!     | array V if requested.  Otherwise, an         |
!     | orthogonal basis for the invariant subspace  |
!     | corresponding to the eigenvalues in D is     |
!     | returned in V.                               |
!     %----------------------------------------------%

      IF (IERR /= 0) THEN 
!
!        %------------------------------------%
!        | Error condition:                   |
!        | Check the documentation of DNEUPD. |
!        %------------------------------------%
!
         WRITE( Message, * ) ' Error with DNEUPD, info = ', IERR
         CALL Fatal( 'EigenSolve', Message )
      END IF
!
!     %------------------------------------------%
!     | Print additional convergence information |
!     %------------------------------------------%
!
      IF ( kinfo == 1 ) THEN
         CALL Fatal( 'EigenSolve', 'Maximum number of iterations reached.' )
      ELSE IF ( kinfo == 3 ) THEN
         CALL Fatal( 'EigenSolve', &
            'No shifts could be applied during implicit Arnoldi update, try increasing NCV.' )
      END IF      
!
!     Sort the eigenvalues to ascending order:
!        ----------------------------------------
      ALLOCATE( Perm(NEIG) )
      Perm = (/ (i, i=1,NEIG) /)
      DO i=1,NEIG
         EigValues(i) = DCMPLX( D(i,1), D(i,2) )
      END DO
      CALL SortC( NEIG, EigValues, Perm )
!
!     Extract the values to ELMER structures:
!     -----------------------------------------
      CALL Info( 'EigenSolve', ' ', Level=4 )
      CALL Info( 'EigenSolve', 'EIGEN SYSTEM SOLUTION COMPLETE: ', Level=4 )
      CALL Info( 'EigenSolve', ' ', Level=4 )
      WRITE( Message, * ) 'The convergence criterion is ', TOL
      CALL Info( 'EigenSolve', Message, Level=4 )
      WRITE( Message, * ) ' The number of converged Ritz values is ', IPARAM(5)
      CALL Info( 'EigenSolve', Message, Level=4 )
      CALL Info( 'EigenSolve', ' ', Level=4 )
      CALL Info( 'EigenSolve', 'Computed Eigen Values: ', Level=3 )
      CALL Info( 'EigenSolve', '--------------------------------', Level=3 )
      k = 1
      DO i=1,NEIG
        p = Perm(i)
        WRITE( Message, * ) i,EigValues(i)
        CALL Info( 'EigenSolve', Message, Level=3 )

        k = 1
        DO j=1,p-1
           IF ( D(j,2) == 0 ) THEN
              k = k + 1
           ELSE
              k = k + 2
           END IF
        END DO

        Solution = 0.0d0
        Residual = 0.0d0
        DO j=1,PN
           IF ( D(p,2) /= 0.0d0 ) THEN
              Matrix % ParMatrix % SplittedMatrix % TmpXVec(j) = V(j,k)
              Matrix % ParMatrix % SplittedMatrix % TmpRVec(j) = V(j,k+1)
           ELSE
              Matrix % ParMatrix % SplittedMatrix % TmpXVec(j) = V(j,k)
              Matrix % ParMatrix % SplittedMatrix % TmpRVec(j) = 0.0d0
           END IF
        END DO

        CALL ParallelUpdateResult( Matrix, Solution, Residual )

        DO j=1,N
           EigVectors(i,j) = DCMPLX( Solution(j), Residual(j) )
        END DO

      END DO
      CALL Info( 'EigenSolve', '--------------------------------',Level=3 )

      DEALLOCATE( WORKL, D, WORKEV, V, CHOOSE, Perm )
#else
      CALL Fatal( 'EigenSolve', 'Arpack Eigen System Solver not available.' )
#endif
!
!------------------------------------------------------------------------------
     END SUBROUTINE ParallelArpackEigenSolve
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    SUBROUTINE Jacobi( n, A, M, x, b, r, Rounds )
!------------------------------------------------------------------------------
       TYPE(Matrix_t), POINTER :: A, M
       INTEGER :: Rounds
       REAL(KIND=dp) :: x(:),b(:),r(:)
!------------------------------------------------------------------------------
       INTEGER :: i,n
!------------------------------------------------------------------------------
       DO i=1,Rounds
          CALL MGmv( A, x, r )
          r(1:n) = b(1:n) - r(1:n)

          r(1:n) = r(1:n) / M % Values(M % Diag)
          x(1:n) = x(1:n) + r(1:n)
       END DO
!------------------------------------------------------------------------------
    END SUBROUTINE Jacobi
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    SUBROUTINE CGParEigen( A, x, b, r, Rounds, Conv )
!------------------------------------------------------------------------------
       TYPE(Matrix_t), POINTER :: A
       INTEGER :: Rounds
       REAL(KIND=dp) :: x(:),b(:),r(:)
       REAL(KIND=dp) :: alpha,rho,oldrho, Conv
!------------------------------------------------------------------------------
!------------------------------------------------------------------------------
       TYPE(Matrix_t), POINTER :: M
       INTEGER :: i,n
       REAL(KIND=dp), POINTER :: Mx(:),Mb(:),Mr(:), Z(:), P(:), Q(:)
       REAL(KIND=dp) :: RNorm
!------------------------------------------------------------------------------
       M => ParallelMatrix( A, Mx, Mb, Mr )
       n = M % NumberOfRows
       M % RHS(1:n) = b(1:n)

       ALLOCATE( Z(n), P(n), Q(n) )

       CALL MGmv( A, Mx, Mr )
       Mr(1:n) = Mb(1:n) - Mr(1:n)

       DO i=1,Rounds
          Z(1:n) = Mr(1:n)
          CALL CRS_LUSolve( n, M, Z )
          rho = MGdot( n, Mr, Z )

          IF ( i == 1 ) THEN
             P(1:n) = Z(1:n)
          ELSE
             P(1:n) = Z(1:n) + rho * P(1:n) / oldrho
          END IF

          CALL MGmv( A, P, Q )
          alpha  = rho / MGdot( n, P, Q )
          oldrho = rho

          Mx(1:n) = Mx(1:n) + alpha * P(1:n)
          Mr(1:n) = Mr(1:n) - alpha * Q(1:n)

          RNorm = MGnorm( n, Mr ) / MGNorm( n, Mb )
          IF ( RNorm < Conv ) EXIT
       END DO

       PRINT*,'iters: ', i, RNorm

       DEALLOCATE( Z, P, Q )

       x(1:n)= Mx(1:n)
       b(1:n)= Mb(1:n)
!------------------------------------------------------------------------------
    END SUBROUTINE CGParEigen
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    SUBROUTINE BiCGParEigen( A, x, b, r, Rounds, Conv )
!------------------------------------------------------------------------------
       TYPE(Matrix_t), POINTER :: A,M
       INTEGER :: Rounds
       REAL(KIND=dp) :: x(:),b(:),r(:), Conv
!------------------------------------------------------------------------------
       INTEGER :: i,n
       REAL(KIND=dp) :: RNorm
       REAL(KIND=dp) :: alpha,beta,omega,rho,oldrho
       REAL(KIND=dp),POINTER :: Ri(:),P(:),V(:),T(:),T1(:),T2(:),S(:),Mx(:),Mb(:),Mr(:)
!------------------------------------------------------------------------------
       M => ParallelMatrix( A, Mx, Mb, Mr )
       n = M % NumberOfRows
       M % RHS(1:n) = b(1:n)

       CALL MGmv( A, Mx, Mr )
       Mr(1:n) = Mb(1:n) - Mr(1:n)

       ALLOCATE( Ri(n),P(n),V(n),T(n),T1(n),T2(n),S(n) )

       Ri(1:n) = Mr(1:n)
       P(1:n) = 0
       V(1:n) = 0
       omega  = 1
       alpha  = 0
       oldrho = 1

       DO i=1,Rounds
          rho = MGdot( n, Mr, Ri )

          beta = alpha * rho / ( oldrho * omega )
          P(1:n) = Mr(1:n) + beta * (P(1:n) - omega*V(1:n))

          V(1:n) = P(1:n)
          CALL CRS_LUSolve( n, M, V )
          T1(1:n) = V(1:n)
          CALL MGmv( A, T1, V )

          alpha = rho / MGdot( n, Ri, V )

          S(1:n) = Mr(1:n) - alpha * V(1:n)

          T(1:n) = S(1:n)
          CALL CRS_LUSolve( n, M, T )
          T2(1:n) = T(1:n)
          CALL MGmv( A, T2, T )
          omega = MGdot( n,T,S ) / MGdot( n,T,T )

          oldrho = rho
          Mr(1:n) = S(1:n) - omega*T(1:n)
          Mx(1:n) = Mx(1:n) + alpha*T1(1:n) + omega*T2(1:n)

          RNorm = MGnorm( n, Mr ) / MGNorm( n, Mb )
          IF ( RNorm < Conv ) EXIT
       END DO

       PRINT*,'iters: ', i, RNorm

       DEALLOCATE( Ri,P,V,T,T1,T2,S )

       x(1:n) = Mx(1:n)
       b(1:n) = Mb(1:n)
!------------------------------------------------------------------------------
    END SUBROUTINE BiCGParEigen
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    FUNCTION MGnorm( n, x ) RESULT(s)
!------------------------------------------------------------------------------
       INTEGER :: n
       REAL(KIND=dp) :: s,x(:)
!------------------------------------------------------------------------------
       s = ParallelNorm( n, x )
!------------------------------------------------------------------------------
    END FUNCTION MGnorm
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    FUNCTION MGdot( n, x, y ) RESULT(s)
!------------------------------------------------------------------------------
       INTEGER :: n
       REAL(KIND=dp) :: s,x(:),y(:)
!------------------------------------------------------------------------------
       s = ParallelDot( n, x, y )
!------------------------------------------------------------------------------
    END FUNCTION MGdot
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    SUBROUTINE MGmv( A, x, b, Update, UseMass )
!------------------------------------------------------------------------------
       REAL(KIND=dp) :: x(:), b(:)
       LOGICAL, OPTIONAL :: Update, UseMass
       TYPE(Matrix_t), POINTER :: A
!------------------------------------------------------------------------------
       LOGICAL :: mass, updt
!------------------------------------------------------------------------------
       mass = .FALSE.
       IF ( PRESENT( UseMass ) ) Mass = UseMass
       updt = .FALSE.
       IF ( PRESENT( Update ) ) updt = Update

       CALL ParallelMatrixVector( A,x,b,updt,mass )
!------------------------------------------------------------------------------
    END SUBROUTINE MGmv
!------------------------------------------------------------------------------
END MODULE ParallelEigenSolve
