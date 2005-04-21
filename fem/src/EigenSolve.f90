MODULE EigenSolve

   IMPLICIT NONE

CONTAINS

!------------------------------------------------------------------------------
     SUBROUTINE ArpackEigenSolve( Solver,Matrix,N,NEIG,EigValues,EigVectors )
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
      USE CRSMatrix
      USE IterSolve
      USE Multigrid


      IMPLICIT NONE

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
      CHARACTER ::     BMAT*1, Which*2, DirectMethod*100
      INTEGER   ::     IDO, NCV, lWORKL, kinfo, i, j, k, l, p, IERR, iter, &
                       NCONV, maxitr, ishfts, mode, istat
      LOGICAL   ::     First, Stat, Direct = .FALSE., &
                       Iterative = .FALSE., NewSystem, Damped, Stability
      REAL(KIND=dp) :: SigmaR, SigmaI, TOL

      COMPLEX(KIND=dp) :: s
!
      REAL(KIND=dp), POINTER :: SaveValues(:)

!     %--------------------------------------%
!     | Check if system is damped and if so, |
!     | move to other subroutine             |
!     %--------------------------------------%

      Damped = ListGetLogical( Solver % Values, 'Eigen System Damped', stat )

      IF ( .NOT. stat ) THEN
         Damped = .FALSE.
      END IF

      IF ( Damped ) THEN
         CALL ArpackDampedEigenSolve( Solver, Matrix, 2*N, 2*NEIG, &
              EigValues,EigVectors )
         RETURN
      END IF

!     %----------------------------------------%
!     | Check if stability analysis is defined |
!     | and if so move to other subroutine     |
!     %----------------------------------------%

      Stability = ListGetLogical( Solver % Values, 'stability analysis', stat )
      IF ( .NOT. stat ) Stability = .FALSE.

      IF ( Stability ) THEN
         CALL ArpackStabEigenSolve( Solver, Matrix, N, NEIG, EigValues,EigVectors )
         RETURN
      END IF

!     %-----------------------%
!     | Executable Statements |
!     %-----------------------%
!
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
             WORKEV(3*NCV), V(n,NCV), CHOOSE(NCV), STAT=istat )

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
         CASE( 'smallest real part')
              Which = 'SR'
         CASE( 'largest real part')
              Which = 'LR'
         CASE( 'smallest imag part' )
              Which = 'SI'
         CASE( 'largest imag part' )
              Which = 'LI'
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
         CASE( 'smallest real part')
              Which = 'LR'
         CASE( 'largest real part')
              Which = 'SR'
         CASE( 'smallest imag part' )
              Which = 'LI'
         CASE( 'largest imag part' )
              Which = 'SI'
         CASE DEFAULT
              Which = 'LM'
         END SELECT
      END IF
!
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
         IF ( Direct ) THEN
            DirectMethod = ListGetString( Solver % Values, &
              'Linear System Direct Method', stat )
            SELECT CASE( DirectMethod )
            CASE('umfpack')
               CALL ListAddLogical( Solver % Values, 'UMF Factorize', .TRUE. )
            CASE DEFAULT
               Stat = CRS_ILUT(Matrix, 0.0d0)
            END SELECT
         END IF
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
            CALL DSAUPD ( ido, BMAT, n, Which, NEIG, TOL, &
              RESID, NCV, V, n, IPARAM, IPNTR, WORKD, WORKL, lWORKL, kinfo )
         ELSE
            CALL DNAUPD ( ido, BMAT, n, Which, NEIG, TOL, &
              RESID, NCV, v, n, IPARAM, IPNTR, WORKD, WORKL, lWORKL, kinfo )
         END IF
 
         IF (ido == -1 .OR. ido == 1) THEN
            WRITE( Message, * ) ' Arnoldi iteration: ', Iter
            CALL Info( 'EigenSolve', Message, Level=5 )
            iter = iter + 1
!
!---------------------------------------------------------------------
!             Perform  y <--- OP*x = inv[M]*A*x   (lumped mass)
!                      ido =-1 inv(A-sigmaR*M)*M*x 
!                      ido = 1 inv(A-sigmaR*M)*z
!---------------------------------------------------------------------
            IF ( .NOT. Matrix % Lumped .AND. ido == 1 ) THEN

               IF ( Direct ) THEN
                  SELECT CASE( DirectMethod )
                  CASE('umfpack')
                     CALL UMFPack_SolveSystem( Solver,Matrix,WORKD(IPNTR(2)),WORKD(IPNTR(3)) )
                  CASE DEFAULT
                     DO i=0,n-1
                        WORKD( IPNTR(2)+i ) = WORKD( IPNTR(3)+i )
                     END DO
                     CALL CRS_LUSolve( N, Matrix, WORKD(IPNTR(2)) )
                  END SELECT
               ELSE
                  x => workd(ipntr(2):ipntr(2)+n-1)
                  b => workd(ipntr(3):ipntr(3)+n-1)

                  IF ( Solver % MultiGridSolver ) THEN
                     PSolver => Solver
                     CALL MultiGridSolve( Matrix, x, b,  Solver % Variable % DOFs, &
                           PSolver, Solver % MultiGridLevel, NewSystem )
                  ELSE
                     CALL IterSolver( Matrix, x, b, Solver )
                  END IF

               END IF
            ELSE
               IF ( Matrix % Lumped ) THEN
                  CALL CRS_MatrixVectorMultiply( Matrix, WORKD(IPNTR(1)), WORKD(IPNTR(2)) )
               ELSE
                  SaveValues => Matrix % Values
                  Matrix % Values => Matrix % MassValues
                  CALL CRS_MatrixVectorMultiply( Matrix, WORKD(IPNTR(1)), WORKD(IPNTR(2)) )
                  Matrix % Values => SaveValues
               END IF

               DO i=0,n-1
                  WORKD( IPNTR(1)+i ) = WORKD( IPNTR(2)+i )
               END DO

               IF ( Matrix % Lumped ) THEN
                  DO i=0,n-1
                     WORKD( IPNTR(2)+i ) = WORKD( IPNTR(1)+i ) / &
                        Matrix % MassValues( Matrix % Diag(i+1) )
                  END DO
               ELSE
                  IF ( Direct ) THEN
                     SELECT CASE( DirectMethod )
                     CASE('umfpack')
                        CALL UMFPack_SolveSystem( Solver,Matrix,WORKD(IPNTR(2)),WORKD(IPNTR(1)) )
                     CASE DEFAULT
                        CALL CRS_LUSolve( N, Matrix, WORKD(IPNTR(2)) )
                     END SELECT
                  ELSE
                    x => workd(ipntr(2):ipntr(2)+n-1)
                    b => workd(ipntr(1):ipntr(1)+n-1)

                    IF ( Solver % MultiGridSolver ) THEN
                       PSolver => Solver
                       CALL MultiGridSolve( Matrix, x, b, Solver % Variable % DOFs,  &
                              PSolver, Solver % MultiGridLevel, NewSystem )
                     ELSE
                       CALL IterSolver( Matrix, x, b, Solver )
                     END IF

                  END IF
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
               SaveValues => Matrix % Values
               Matrix % Values => Matrix % MassValues
               CALL CRS_MatrixVectorMultiply( Matrix, WORKD(IPNTR(1)), WORKD(IPNTR(2)) )
               Matrix % Values => SaveValues
            END IF
         END IF 

         IF ( NewSystem .AND. ido /= 2 ) THEN
            IF ( Iterative ) THEN
               CALL ListAddLogical( Solver % Values,  'No Precondition Recompute', .TRUE. )
            ELSE
               CALL ListAddLogical( Solver % Values, 'UMF Factorize', .FALSE. )
            END IF
            NewSystem = .FALSE.
         END IF
       END DO

       CALL ListAddLogical( Solver % Values, 'UMF Factorize', .TRUE. )
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
      ELSE 
!
!        %-------------------------------------------%
!        | No fatal errors occurred.                 |
!        | Post-Process using DSEUPD.                |
!        |                                           |
!        | Computed eigenvalues may be extracted.    |  
!        |                                           |
!        | Eigenvectors may also be computed now if  |
!        | desired.  (indicated by rvec = .true.)    | 
!        %-------------------------------------------%
!           
         D = 0.0d0
         IF ( Matrix % Symmetric ) THEN
            CALL DSEUPD ( .TRUE., 'A', Choose, D, V, N, SigmaR,  &
               BMAT, n, Which, NEIG, TOL, RESID, NCV, V, N, &
               IPARAM, IPNTR, WORKD, WORKL, lWORKL, IERR )
         ELSE
            CALL DNEUPD ( .TRUE., 'A', Choose, D, D(1,2), &
               V, N, SigmaR, SigmaI, WORKEV, BMAT, N, &
               Which, NEIG, TOL, RESID, NCV, V, N, &
               IPARAM, IPNTR, WORKD, WORKL, lWORKL, IERR )
         END IF
 
!        %----------------------------------------------%
!        | Eigenvalues are returned in the First column |
!        | of the two dimensional array D and the       |
!        | corresponding eigenvectors are returned in   |
!        | the First NEV columns of the two dimensional |
!        | array V if requested.  Otherwise, an         |
!        | orthogonal basis for the invariant subspace  |
!        | corresponding to the eigenvalues in D is     |
!        | returned in V.                               |
!        %----------------------------------------------%
!
         IF (IERR /= 0) THEN 
!
!           %------------------------------------%
!           | Error condition:                   |
!           | Check the documentation of DNEUPD. |
!           %------------------------------------%
! 
            WRITE( Message, * ) ' Error with DNEUPD, info = ', IERR
            CALL Fatal( 'EigenSolve', Message )
         END IF
!
!        %------------------------------------------%
!        | Print additional convergence information |
!        %------------------------------------------%
!
         IF ( kinfo == 1 ) THEN
            CALL Fatal( 'EigenSolve', 'Maximum number of iterations reached.' )
         ELSE IF ( kinfo == 3 ) THEN
            CALL Fatal( 'EigenSolve', 'No shifts could be applied during implicit Arnoldi update, try increasing NCV.' )
         END IF      
!
!        Sort the eigenvalues to ascending order:
!        ----------------------------------------
         ALLOCATE( Perm(NEIG) )
         Perm = (/ (i, i=1,NEIG) /)
         DO i=1,NEIG
            EigValues(i) = DCMPLX( D(i,1), D(i,2) )
         END DO
         CALL SortC( NEIG, EigValues, Perm )

!
!        Extract the values to ELMER structures:
!        -----------------------------------------
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

           DO j=1,N
              IF ( D(p,2) /= 0.0d0 ) THEN
                 EigVectors(i,j) = DCMPLX( V(j,k),V(j,k+1) )
              ELSE
                 EigVectors(i,j) = DCMPLX( V(j,k),0.0d0 )
              END IF
           END DO
!
!          Normalize eigenvector  (x) so that x^T(M x) = 1
!          (probably already done, but no harm in redoing!)
!          -------------------------------------------------
!
           IF ( Matrix % Lumped ) THEN
              s = 0.0d0
              DO j=1,n
                 s = s + ABS(EigVectors(i,j))**2 * &
                     Matrix % MassValues(Matrix % Diag(j))
              END DO
           ELSE
              s = 0.0d0
              DO j=1,n
                 DO l=Matrix % Rows(j), Matrix % Rows(j+1)-1
                    s = s + Matrix % MassValues(l) * &
                     CONJG( EigVectors(i,j) ) * EigVectors(i,Matrix % Cols(l))
                 END DO
              END DO
           END IF
           IF ( ABS(s) > 0 ) EigVectors(i,:) = EigVectors(i,:) / SQRT(s)
         END DO
         CALL Info( 'EigenSolve', '--------------------------------',Level=3 )
!
      END IF

      DEALLOCATE( WORKL, D, WORKEV, V, CHOOSE, Perm )

#else
      CALL Fatal( 'EigenSolve', 'Arpack Eigen System Solver not available.' )
#endif
!
!------------------------------------------------------------------------------
     END SUBROUTINE ArpackEigenSolve
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
     SUBROUTINE ArpackStabEigenSolve( Solver, &
          Matrix, N, NEIG, EigValues, EigVectors )
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
      USE CRSMatrix
      USE IterSolve
      USE Multigrid

      IMPLICIT NONE

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
      TYPE(Solver_t), POINTER :: PSolver
      REAL(KIND=dp), TARGET :: WORKD(3*N), RESID(N)
      REAL(KIND=dp), POINTER :: x(:), b(:)
      INTEGER :: IPARAM(11), IPNTR(14)
      INTEGER, ALLOCATABLE :: Perm(:)
      LOGICAL, ALLOCATABLE :: Choose(:)
      REAL(KIND=dp), ALLOCATABLE :: WORKL(:), D(:,:), V(:,:)
!
!     %---------------%
!     | Local Scalars |
!     %---------------%
!
      CHARACTER ::     BMAT*1, Which*2, DirectMethod*200
      INTEGER   ::     IDO, NCV, lWORKL, kinfo, i, j, k, l, p, IERR, iter, &
                       NCONV, maxitr, ishfts, mode, istat
      LOGICAL   ::     First, Stat, Direct = .FALSE., &
                       Iterative = .FALSE., NewSystem, &
                       rvec = .TRUE.
      REAL(KIND=dp) :: SigmaR, SigmaI, TOL

      COMPLEX(KIND=dp) :: s
!
      REAL(KIND=dp), POINTER :: SaveValues(:)

!     %-----------------------%
!     | Executable Statements |
!     %-----------------------%
!
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
      IF ( Matrix % Lumped ) THEN
         CALL Error( 'BucklingEigenSolve', &
              'Lumped matrices are not allowed in stability analysis.' )
      END IF

      NCV = 3 * NEIG + 1

      lWORKL = NCV*(NCV+8)

      ALLOCATE( WORKL(lWORKL), D(NCV,2), V(N,NCV), CHOOSE(NCV), STAT=istat )

      IF ( istat /= 0 ) THEN
         CALL Fatal( 'EigenSolve', 'Memory allocation error.' )
      END IF

      TOL = ListGetConstReal( Solver % Values, 'Eigen System Convergence Tolerance', stat )
      IF ( .NOT. stat ) THEN
         TOL = 100 * ListGetConstReal( Solver % Values, 'Linear System Convergence Tolerance' )
      END IF
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
      IDO   = 0
      kinfo = 0
      ishfts = 1
      BMAT  = 'G'
      Mode = 2

      SELECT CASE( ListGetString( Solver % Values,'Eigen System Select', stat ) )
      CASE( 'smallest magnitude' )
         Which = 'LM'
      CASE( 'largest magnitude')
         Which = 'SM'
      CASE( 'smallest real part')
         Which = 'LR'
      CASE( 'largest real part')
         Which = 'SR'
      CASE( 'smallest imag part' )
         Which = 'LI'
      CASE( 'largest imag part' )
         Which = 'SI'
      CASE( 'smallest algebraic' )
         Which = 'LA'
      CASE( 'largest algebraic' )
         Which = 'SA'
      CASE DEFAULT
         Which = 'LM'
      END SELECT

      Maxitr = ListGetInteger( Solver % Values, 'Eigen System Max Iterations', stat )
      IF ( .NOT. stat ) Maxitr = 300

      IPARAM(1) = ishfts
      IPARAM(3) = maxitr 
      IPARAM(7) = mode

      SigmaR = 0.0d0
      SigmaI = 0.0d0
      V = 0.0d0
      D = 0.0d0

      Direct = ListGetString( Solver % Values, &
           'Linear System Solver', stat ) == 'direct'
      IF ( Direct ) THEN
         DirectMethod = ListGetString( Solver % Values, &
           'Linear System Direct Method', stat )
         SELECT CASE( DirectMethod )
         CASE('umfpack')
            CALL ListAddLogical( Solver % Values, 'UMF Factorize', .TRUE. )
         CASE DEFAULT
            Stat = CRS_ILUT(Matrix, 0.0d0)
         END SELECT
      END IF

      Iterative = ListGetString( Solver % Values, &
               'Linear System Solver', stat ) == 'iterative'

      stat = ListGetLogical( Solver % Values, 'No Precondition Recompute', stat  )

      IF ( Iterative .AND. Stat ) THEN
         CALL ListAddLogical( Solver % Values, 'No Precondition Recompute', .FALSE. )
      END IF
!
!     %-------------------------------------------%
!     | M A I N   L O O P (Reverse communication) |
!     %-------------------------------------------%
!
      iter = 1
      NewSystem = .TRUE.

      DO WHILE( ido /= 99 )

         CALL DSAUPD( ido, BMAT, n, Which, NEIG, TOL, &
              RESID, NCV, V, n, IPARAM, IPNTR, WORKD, WORKL, lWORKL, kinfo )

         IF( ido==-1 .OR. ido==1 ) THEN
            WRITE( Message, * ) ' Arnoldi iteration: ', Iter
            CALL Info( 'EigenSolve', Message, Level=5 )
            iter = iter + 1
         END IF

         SELECT CASE( ido )
         CASE( -1, 1 )
            SaveValues => Matrix % Values
            Matrix % Values => Matrix % MassValues
            CALL CRS_MatrixVectorMultiply( Matrix, WORKD(IPNTR(1)), WORKD(IPNTR(2)) )
            Matrix % Values => SaveValues
            
            DO i=0,n-1
               WORKD( IPNTR(1)+i ) = WORKD( IPNTR(2)+i )
            END DO
            
            IF ( Direct ) THEN
               SELECT CASE( DirectMethod )
               CASE('umfpack')
                  CALL UMFPack_SolveSystem( Solver,Matrix,WORKD(IPNTR(2)),WORKD(IPNTR(1)) )
               CASE DEFAULT
                  CALL CRS_LUSolve( N, Matrix, WORKD(IPNTR(2)) )
               END SELECT
            ELSE               
               x => workd(ipntr(2):ipntr(2)+n-1)
               b => workd(ipntr(1):ipntr(1)+n-1)
               
               IF ( Solver % MultiGridSolver ) THEN
                  PSolver => Solver
                  CALL MultiGridSolve( Matrix, x, b, Solver % Variable % DOFs,  &
                       PSolver, Solver % MultiGridLevel, NewSystem )
               ELSE
                  CALL IterSolver( Matrix, x, b, Solver )
               END IF
               
            END IF

         CASE( 2 )            
            CALL CRS_MatrixVectorMultiply( Matrix, WORKD(IPNTR(1)), WORKD(IPNTR(2)) )

         END SELECT

         IF ( NewSystem .AND. ido /= 2 ) THEN
            IF ( Iterative ) THEN
               CALL ListAddLogical( Solver % Values,  'No Precondition Recompute', .TRUE. )
            ELSE
               CALL ListAddLogical( Solver % Values, 'UMF Factorize', .FALSE. )
            END IF
            NewSystem = .FALSE.
         END IF

!-----------------------------------------------------------------------------------------      
      END DO  ! ido == 99

      CALL ListAddLogical( Solver % Values, 'UMF Factorize', .TRUE. )
!
!     %-----------------------------------------%
!     | Either we have convergence, or there is |
!     | an error.                               |
!     %-----------------------------------------%
!
      IF ( kinfo /= 0 ) THEN
         WRITE( Message, * ) 'Error with DSAUPD, info = ',kinfo
         CALL Fatal( 'EigenSolve', Message )
!
      ELSE 
         D = 0.0d0
         rvec = .TRUE.

         CALL DSEUPD ( rvec, 'A', Choose, D, V, N, SigmaR, &
              BMAT, n, Which, NEIG, TOL, RESID, NCV, V, N, &
              IPARAM, IPNTR, WORKD, WORKL, lWORKL, IERR )
            
!        %----------------------------------------------%
!        | Eigenvalues are returned in the First column |
!        | of the two dimensional array D and the       |
!        | corresponding eigenvectors are returned in   |
!        | the First NEV columns of the two dimensional |
!        | array V if requested.  Otherwise, an         |
!        | orthogonal basis for the invariant subspace  |
!        | corresponding to the eigenvalues in D is     |
!        | returned in V.                               |
!        %----------------------------------------------%
!
         IF (IERR /= 0) THEN
            WRITE( Message, * ) ' Error with DSEUPD, info = ', IERR
            CALL Fatal( 'EigenSolve', Message )
         END IF
!
!        %------------------------------------------%
!        | Print additional convergence information |
!        %------------------------------------------%
!
         IF ( kinfo == 1 ) THEN
            CALL Fatal( 'EigenSolve', 'Maximum number of iterations reached.' )
         ELSE IF ( kinfo == 3 ) THEN
            CALL Fatal( 'EigenSolve', 'No shifts could be applied during implicit Arnoldi update, try increasing NCV.' )
         END IF      
!
!        Sort the eigenvalues to ascending order:
!        ----------------------------------------
         ALLOCATE( Perm(NEIG) )
         Perm = (/ (i, i=1,NEIG) /)
         DO i=1,NEIG
            EigValues(i) = DCMPLX( 1.0d0 / D(i,1), D(i,2) )
         END DO

         CALL SortC( NEIG, EigValues, Perm )
!
!        Extract the values to ELMER structures:
!        -----------------------------------------
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

           DO j=1,N
              IF ( D(p,2) /= 0.0d0 ) THEN
                 EigVectors(i,j) = DCMPLX( V(j,k),V(j,k+1) )
              ELSE
                 EigVectors(i,j) = DCMPLX( V(j,k),0.0d0 )
              END IF
           END DO
!
!          Normalize eigenvector  (x) so that x^T(M x) = 1
!          (probably already done, but no harm in redoing!)
!          -------------------------------------------------
!
           IF ( Matrix % Lumped ) THEN
              s = 0.0d0
              DO j=1,n
                 s = s + ABS(EigVectors(i,j))**2 * &
                      Matrix % MassValues(Matrix % Diag(j))
              END DO
           ELSE
              s = 0.0d0
              DO j=1,n
                 DO l=Matrix % Rows(j), Matrix % Rows(j+1)-1
                    s = s + Matrix % MassValues(l) * &
                         CONJG( EigVectors(i,j) ) * EigVectors(i,Matrix % Cols(l))
                 END DO
              END DO
           END IF

           print *,'abs(s)=',abs(s)

           IF ( ABS(s) > 0 ) EigVectors(i,:) = EigVectors(i,:) / SQRT(s)

        END DO

         CALL Info( 'EigenSolve', '--------------------------------',Level=3 )
!
      END IF

      DO i = 1,Neig
         IF( REAL(EigValues(i)) < 0.0d0 ) THEN
            EigVectors(i,:) = EigVectors(i,:) * DCMPLX(0.0d0,1.0d0)
         END IF
      END DO

      DEALLOCATE( WORKL, D, V, CHOOSE, Perm )
#else
      CALL Fatal( 'EigenSolve', 'Arpack Eigen System Solver not available.' )
#endif
!
!------------------------------------------------------------------------------
    END SUBROUTINE ArpackStabEigenSolve
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
     SUBROUTINE ArpackEigenSolveComplex( Solver,Matrix,N,NEIG, &
                      EigValues, EigVectors )
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
      USE CRSMatrix
      USE IterSolve
      USE Multigrid


      IMPLICIT NONE

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
      TYPE(Solver_t), POINTER :: PSolver
      COMPLEX(KIND=dp) :: WORKD(3*N), RESID(N)
      INTEGER :: IPARAM(11), IPNTR(14)
      INTEGER, ALLOCATABLE :: Perm(:)
      LOGICAL, ALLOCATABLE :: Choose(:)
      COMPLEX(KIND=dp), ALLOCATABLE :: WORKL(:), D(:), WORKEV(:), V(:,:)

!
!     %---------------%
!     | Local Scalars |
!     %---------------%
!
      CHARACTER ::     BMAT*1, Which*2
      INTEGER   ::     IDO, NCV, lWORKL, kinfo, i, j, k, l, p, IERR, iter, &
                       NCONV, maxitr, ishfts, mode, istat
      LOGICAL   ::     First, Stat, Direct = .FALSE., &
                       Iterative = .FALSE., NewSystem
      COMPLEX(KIND=dp) :: Sigma = 0.0d0, s
      REAL(KIND=dp) :: SigmaR, SigmaI, TOL, RWORK(N), x(2*n), b(2*n)
!
      REAL(KIND=dp), POINTER :: SaveValues(:)
!
!     %-----------------------%
!     | Executable Statements |
!     %-----------------------%
!
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
      NCV   = 3*NEIG+1


      ALLOCATE( WORKL(3*NCV**2 + 6*NCV), D(NCV), &
         WORKEV(3*NCV), V(n,NCV), CHOOSE(NCV), STAT=istat )

      IF ( istat /= 0 ) THEN
         CALL Fatal( 'ComplexEigenSolve', 'Memory allocation error.' )
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
!
      TOL = ListGetConstReal( Solver % Values, 'Eigen System Convergence Tolerance', stat )
      IF ( .NOT. stat ) THEN
         TOL = 100 * ListGetConstReal( Solver % Values, 'Linear System Convergence Tolerance' )
      END IF

      lWORKL = 3*NCV**2 + 6*NCV 
      IDO   = 0
      kinfo = 0
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
         SELECT CASE(ListGetString( Solver % Values, 'Eigen System Select',stat) )
         CASE( 'smallest magnitude' )
              Which = 'SM'
         CASE( 'largest magnitude')
              Which = 'LM'
         CASE( 'smallest real part')
              Which = 'SR'
         CASE( 'largest real part')
              Which = 'LR'
         CASE( 'smallest imag part' )
              Which = 'SI'
         CASE( 'largest imag part' )
              Which = 'LI'
         CASE DEFAULT
              Which = 'SM'
         END SELECT
      ELSE
         Mode  = 3
         SELECT CASE(ListGetString( Solver % Values, 'Eigen System Select',stat) )
         CASE( 'smallest magnitude' )
              Which = 'LM'
         CASE( 'largest magnitude')
              Which = 'SM'
         CASE( 'smallest real part')
              Which = 'LR'
         CASE( 'largest real part')
              Which = 'SR'
         CASE( 'smallest imag part' )
              Which = 'LI'
         CASE( 'largest imag part' )
              Which = 'SI'
         CASE DEFAULT
              Which = 'LM'
         END SELECT
      END IF
!
      Maxitr = ListGetInteger( Solver % Values, 'Eigen System Max Iterations', stat )
      IF ( .NOT. stat ) Maxitr = 300

      IPARAM(1) = ishfts
      IPARAM(3) = maxitr 
      IPARAM(7) = mode

      SigmaR = 0
      SigmaI = 0
      V = 0
!
!     Compute LU-factors for (A-\sigma M) (if consistent mass matrix)
!
      IF ( .NOT. Matrix % Lumped ) THEN
         Direct = ListGetString( Solver % Values, &
           'Linear System Solver', stat ) == 'direct'

         IF ( Direct ) Stat = CRS_ComplexILUT(Matrix, 0.0d0)
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
!        %---------------------------------------------%
!        | Repeatedly call the routine DSAUPD and take | 
!        | actions indicated by parameter IDO until    |
!        | either convergence is indicated or maxitr   |
!        | has been exceeded.                          |
!        %---------------------------------------------%
!
         IF ( Matrix % Symmetric ) THEN
!           CALL ZSAUPD ( ido, BMAT, n, Which, NEIG, TOL, &
!             RESID, NCV, V, n, IPARAM, IPNTR, WORKD, WORKL, lWORKL, kinfo )
         ELSE
            CALL ZNAUPD ( ido, BMAT, n, Which, NEIG, TOL, &
              RESID, NCV, v, n, IPARAM, IPNTR, WORKD, WORKL, lWORKL, RWORK, kinfo )
         END IF
!
!
         IF (ido == -1 .OR. ido == 1) THEN
            WRITE( Message, * ) ' Arnoldi iteration: ', Iter
            CALL Info( 'ComplexEigenSolve', Message, Level=5 )
            Iter = Iter + 1
!---------------------------------------------------------------------
!           Perform  y <--- OP*x = inv[M]*A*x   (lumped mass)
!                    ido =-1 inv(A-sigmaR*M)*M*x 
!                    ido = 1 inv(A-sigmaR*M)*z
!---------------------------------------------------------------------

            IF (  ido == 1 ) THEN
               DO i=0,n-1
                  WORKD( IPNTR(2)+i ) = WORKD( IPNTR(3)+i )
               END DO

               IF ( Direct ) THEN
                  CALL CRS_ComplexLUSolve( N, Matrix, WORKD(IPNTR(2)) )
               ELSE
                  DO i=0,n-1
                     x(2*i+1) = REAL(  WORKD( IPNTR(2)+i ) )
                     x(2*i+2) = AIMAG( WORKD( IPNTR(2)+i ) )
                     b(2*i+1) = REAL(  WORKD( IPNTR(3)+i ) )
                     b(2*i+2) = AIMAG( WORKD( IPNTR(3)+i ) )
                  END DO
                  IF ( Solver % MultiGridSolver ) THEN
                     PSolver => Solver
                     CALL MultiGridSolve( Matrix, x, b, Solver % Variable % DOFs, &
                          PSolver, Solver % MultiGridLevel, NewSystem )
                  ELSE
                     CALL IterSolver( Matrix, x, b, Solver )
                  END IF

!                 do i=1,matrix % numberofrows
!                   j = matrix % rows(i)
!                   k = matrix % rows(i+1)-1
!                   if ( ALL( matrix % massvalues(j:k) == 0 ) ) &
!                      x(i) =  b(i) / matrix % values(matrix % diag(i))
!                 end do

                  DO i=0,n-1
                     WORKD( IPNTR(2)+i ) = DCMPLX( x(2*i+1), x(2*i+2) )
                  END DO
               END IF
            ELSE
               SaveValues => Matrix % Values
               Matrix % Values => Matrix % MassValues
               CALL CRS_ComplexMatrixVectorMultiply( Matrix, &
                     WORKD(IPNTR(1)), WORKD(IPNTR(2)) )
               Matrix % Values => SaveValues

               DO i=0,n-1
                  WORKD( IPNTR(1)+i ) = WORKD( IPNTR(2)+i )
               END DO

               IF ( Direct ) THEN
                  CALL CRS_ComplexLUSolve( N, Matrix, WORKD(IPNTR(2)) )
               ELSE
                  DO i=0,n-1
                     x(2*i+1) = REAL(  WORKD( IPNTR(2)+i ) )
                     x(2*i+2) = AIMAG( WORKD( IPNTR(2)+i ) )
                     b(2*i+1) = REAL(  WORKD( IPNTR(1)+i ) )
                     b(2*i+2) = AIMAG( WORKD( IPNTR(1)+i ) )
                  END DO
                  IF ( Solver % MultiGridSolver ) THEN
                     PSolver => Solver
                     CALL MultiGridSolve(Matrix, x, b, Solver % Variable % DOFs,&
                             PSolver, Solver % MultiGridLevel, NewSystem )
                  ELSE
                     CALL IterSolver( Matrix, x, b, Solver )
                  END IF

                  DO i=0,n-1
                     WORKD( IPNTR(2)+i ) = DCMPLX( x(2*i+1), x(2*i+2) )
                  END DO
               END IF
            END IF
!
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
            SaveValues => Matrix % Values
            Matrix % Values => Matrix % MassValues
            CALL CRS_ComplexMatrixVectorMultiply( Matrix, &
                    WORKD(IPNTR(1)), WORKD(IPNTR(2)) )
            Matrix % Values => SaveValues
         END IF 

         IF ( NewSystem .AND. ido /= 2 ) THEN
            IF ( Iterative ) THEN
               CALL ListAddLogical( Solver % Values,  'No Precondition Recompute', .TRUE. )
            ELSE
               CALL ListAddLogical( Solver % Values, 'UMF Factorize', .FALSE. )
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
      ELSE 
!
!        %-------------------------------------------%
!        | No fatal errors occurred.                 |
!        | Post-Process using DSEUPD.                |
!        |                                           |
!        | Computed eigenvalues may be extracted.    |  
!        |                                           |
!        | Eigenvectors may also be computed now if  |
!        | desired.  (indicated by rvec = .true.)    | 
!        %-------------------------------------------%
!           
         D = 0.0d0
!        IF ( Matrix % Symmetric ) THEN
!           CALL ZSEUPD ( .TRUE., 'A', Choose, D, V, N, SigmaR,  &
!              BMAT, n, Which, NEIG, TOL, RESID, NCV, V, N, &
!              IPARAM, IPNTR, WORKD, WORKL, lWORKL, RWORK, IERR )
!        ELSE
            CALL ZNEUPD ( .TRUE., 'A', Choose, D, &
               V, N, Sigma, WORKEV, BMAT, N, &
               Which, NEIG, TOL, RESID, NCV, V, N, &
               IPARAM, IPNTR, WORKD, WORKL, lWORKL, RWORK, IERR )
!        END IF
 

!        %----------------------------------------------%
!        | Eigenvalues are returned in the First column |
!        | of the two dimensional array D and the       |
!        | corresponding eigenvectors are returned in   |
!        | the First NEV columns of the two dimensional |
!        | array V if requested.  Otherwise, an         |
!        | orthogonal basis for the invariant subspace  |
!        | corresponding to the eigenvalues in D is     |
!        | returned in V.                               |
!        %----------------------------------------------%
!
         IF (IERR /= 0) THEN 
!
!           %------------------------------------%
!           | Error condition:                   |
!           | Check the documentation of DNEUPD. |
!           %------------------------------------%
! 
            WRITE( Message, * ) ' Error with DNEUPD, info = ', IERR
            CALL Fatal( 'EigenSolve', Message )
         END IF
!
!        %------------------------------------------%
!        | Print additional convergence information |
!        %------------------------------------------%
!
         IF ( kinfo == 1 ) THEN
            CALL Fatal( 'EigenSolve', 'Maximum number of iterations reached.' )
         ELSE IF ( kinfo == 3 ) THEN
            CALL Fatal( 'EigenSolve', 'No shifts could be applied during implicit Arnoldi update, try increasing NCV.' )
         END IF      
!
!        Sort the eigenvalues to ascending order:
!        ----------------------------------------
         ALLOCATE( Perm(NEIG) )
         Perm = (/ (i, i=1,NEIG) /)
         DO i=1,NEIG
            EigValues(i) = D(i)
         END DO
         CALL SortC( NEIG, EigValues, Perm )

!
!        Extract the values to ELMER structures:
!        -----------------------------------------
         CALL Info( 'ComplexEigenSolve', ' ', Level=4 )
         CALL Info( 'ComplexEigenSolve', 'EIGEN SYSTEM SOLUTION COMPLETE: ', Level=4 )
         CALL Info( 'ComplexEigenSolve', ' ', Level=4 )
         WRITE( Message, * ) 'The convergence criterion is ', TOL
         CALL Info( 'ComplexEigenSolve', Message, Level=4 )
         WRITE( Message, * ) ' The number of converged Ritz values is ', IPARAM(5)
         CALL Info( 'ComplexEigenSolve', Message, Level=4 )
         CALL Info( 'ComplexEigenSolve', ' ', Level=4 )
         CALL Info( 'ComplexEigenSolve', 'Computed Eigen Values: ', Level=3 )
         CALL Info( 'ComplexEigenSolve', '--------------------------------', Level=3 )
         k = 1
         DO i=1,NEIG
            p = Perm(i)
            WRITE( Message, * ) i,EigValues(i)
            CALL Info( 'EigenSolve', Message, Level=3 )

            DO j=1,N
               EigVectors(i,j) = V(j,p)
            END DO

           IF ( Matrix % Lumped ) THEN
              s = 0.0d0
              DO j=1,n
                 s = s + ABS( EigVectors(i,j) )**2 * Matrix % MassValues( Matrix % Diag(j) )
              END DO
           ELSE
              s = 0.0d0
              DO j=1,n
                 DO l=Matrix % Rows(j), Matrix % Rows(j+1)-1
                    s = s + Matrix % MassValues(l) * &
                      CONJG( EigVectors(i,j) ) * EigVectors(i,Matrix % Cols(l))
                 END DO
              END DO
           END IF
           IF ( ABS(s) > 0 ) EigVectors(i,:) = EigVectors(i,:) / SQRT(s)
         END DO
         CALL Info( 'EigenSolve', '--------------------------------',Level=3 )
!
      END IF

      DEALLOCATE( WORKL, D, WORKEV, V, CHOOSE, Perm )
#else
      CALL Fatal( 'EigenSolve', 'Arpack Eigen System Solver not available.' )
#endif
!
!------------------------------------------------------------------------------
     END SUBROUTINE ArpackEigenSolveComplex
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
     SUBROUTINE ArpackDampedEigenSolve( Solver, KMatrix, N, NEIG, EigValues, &
          EigVectors )
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
      USE CRSMatrix
      USE IterSolve
      USE Multigrid

      IMPLICIT NONE

      TYPE(Matrix_t), POINTER :: KMatrix
      TYPE(Solver_t), TARGET :: Solver
      INTEGER :: N, NEIG, DPERM(n)
      COMPLEX(KIND=dp) :: EigValues(:), EigVectors(:,:)

#ifdef USE_ARPACK

!     %--------------%
!     | Local Arrays |
!     %--------------%

      TYPE(Solver_t), POINTER :: PSolver
      TYPE(Matrix_t), POINTER :: MMatrix, BMatrix
      REAL(KIND=dp), TARGET :: WORKD(3*N), RESID(N)
      REAL(KIND=dp), POINTER :: x(:), b(:)
      INTEGER :: IPARAM(11), IPNTR(14)
      INTEGER, ALLOCATABLE :: Perm(:), kMap(:)
      LOGICAL, ALLOCATABLE :: Choose(:)
      REAL(KIND=dp), ALLOCATABLE :: WORKL(:), D(:,:), WORKEV(:), V(:,:)
      CHARACTER(LEN=MAX_NAME_LEN) :: str
      COMPLEX(KIND=dp) :: s, EigTemp(NEIG)

!     %---------------%
!     | Local Scalars |
!     %---------------%

      CHARACTER ::     BMAT*1, Which*2
      INTEGER   ::     IDO, NCV, lWORKL, kinfo, i, j, k, l, p, IERR, iter, &
                       NCONV, maxitr, ishfts, mode, istat, DampedMaxIter, ILU
      LOGICAL   ::     First, Stat, NewSystem, UseI = .FALSE.
      REAL(KIND=dp) :: SigmaR, SigmaI, TOL, DampedTOL, IScale

!     %-------------------------------------%
!     | So far only iterative solver        |
!     | and non-lumped matrixes are allowed |
!     %-------------------------------------%

      IF ( KMatrix % Lumped ) THEN
         CALL Error( 'DampedEigenSolve', 'Lumped matrixes are not allowed' )
      END IF

      IF (  ListGetString( Solver % Values, 'Linear System Solver', Stat ) &
           == 'direct' ) THEN
         CALL Error( 'DampedEigenSolve', 'Direct solver is not allowed' )
      END IF

      IF ( Solver % MultiGridSolver ) THEN
         CALL Error( 'DampedEigenSolve', 'MultiGrid solver is not allowed' )
      END IF

      Stat = ListGetLogical( Solver % Values, &
           'No Precondition Recompute', Stat  )

      IF ( Stat ) THEN
         CALL ListAddLogical( Solver % Values, &
              'No Precondition Recompute', .FALSE. )
      END IF


!     %-----------------------%
!     | Executable Statements |
!     %-----------------------%

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

      NCV = 3 * NEIG + 1

      ALLOCATE( WORKL(3*NCV**2 + 6*NCV), D(NCV,3), &
         WORKEV(3*NCV), V(n,NCV), CHOOSE(NCV), STAT=istat )

      CHOOSE = .FALSE.
      Workl = 0.0d0
      workev = 0.0d0
      v = 0.0d0
      d = 0.0d0

      IF ( istat /= 0 ) THEN
         CALL Fatal( 'DampedEigenSolve', 'Memory allocation error.' )
      END IF

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

      TOL = ListGetConstReal( Solver % Values, &
           'Eigen System Convergence Tolerance', Stat )

      IF ( .NOT. Stat ) THEN
         TOL = 100 * ListGetConstReal( Solver % Values, &
              'Linear System Convergence Tolerance' )
      END IF

      DampedMaxIter = ListGetInteger( Solver % Values, &
           'Linear System Max Iterations', Stat, 1 )

      IF ( .NOT. Stat ) DampedMaxIter = 100

      DampedTOL = ListGetConstReal( Solver % Values, &
           'Linear System Convergence Tolerance', Stat )

      IF ( .NOT. Stat ) DampedTOL = TOL / 100

      UseI = ListGetLogical( Solver % Values, &
                     'Eigen System Use Identity', Stat )

      IF ( .NOT. Stat ) UseI = .TRUE.
!      IF ( .NOT. Stat ) UseI = .FALSE.   Changed by Antti 2004-02-18

      IDO   = 0
      kinfo = 0
      lWORKL = 3*NCV**2 + 6*NCV 
!     %---------------------------------------------------%
!     | This program uses exact shifts with respect to    |
!     | the current Hessenberg matrix (IPARAM(1) = 1).    |
!     | IPARAM(3) specifies the maximum number of Arnoldi |
!     | iterations allowed.  Mode 2 of DSAUPD is used     |
!     | (IPARAM(7) = 2).  All these options may be        |
!     | changed by the user. For details, see the         |
!     | documentation in DSAUPD.                          |
!     %---------------------------------------------------%
      
      ishfts = 1
      BMAT  = 'G'
      Mode  = 3
      
      SELECT CASE( ListGetString(Solver % Values, 'Eigen System Select',Stat) )
         CASE( 'smallest magnitude' )
         Which = 'LM'
         
         CASE( 'largest magnitude')
         Which = 'SM'
         
         CASE( 'smallest real part')
         Which = 'LR'
         
         CASE( 'largest real part')
         Which = 'SR'
         
         CASE( 'smallest imag part' )
         Which = 'LI'

         CASE( 'largest imag part' )
         Which = 'SI'
         
         CASE DEFAULT
         Which = 'LM'
      END SELECT

      Maxitr = ListGetInteger(Solver % Values,'Eigen System Max Iterations',Stat)
      IF ( .NOT. Stat ) Maxitr = 300

      IPARAM(1) = ishfts
      IPARAM(3) = maxitr 
      IPARAM(7) = mode

      SigmaR = 0.0d0
      SigmaI = 0.0d0
      V = 0.0d0
!------------------------------------------------------------------------------
! Create M and B matrixes
!------------------------------------------------------------------------------
      MMatrix => AllocateMatrix()
      MMatrix % Values => KMatrix % MassValues
      MMatrix % NumberOfRows = KMatrix % NumberOfRows
      MMatrix % Rows => KMatrix % Rows
      MMatrix % Cols => KMatrix % Cols
      MMatrix % Diag => KMatrix % Diag

      IScale = MAXVAL( ABS( MMatrix % Values ) )

      BMatrix => AllocateMatrix()
      BMatrix % NumberOfRows = KMatrix % NumberOfRows
      BMatrix % Rows => KMatrix % Rows
      BMatrix % Cols => KMatrix % Cols
      BMatrix % Diag => KMatrix % Diag
      BMatrix % Values => KMatrix % DampValues
!------------------------------------------------------------------------------
!     ILU Preconditioning
!------------------------------------------------------------------------------
      str = ListGetString( Solver % Values, 'Linear System Preconditioning', Stat )

      IF ( .NOT. Stat ) THEN
         CALL Warn( 'DampedEigenSolve', 'Using ILU0 preconditioning' )
         ILU = 0
      ELSE
         IF ( str(1:4) == 'none' .OR. str(1:8) == 'diagonal' .OR. &
              str(1:4) == 'ilut' .OR. str(1:9) == 'multigrid' ) THEN

           ILU = 0
           CALL Warn( 'DampedEigenSolve', 'Useing ILU0 preconditioning' )
         ELSE IF ( str(1:3) == 'ilu' ) THEN
           ILU = ICHAR(str(4:4)) - ICHAR('0')
           IF ( ILU  < 0 .OR. ILU > 9 ) ILU = 0
         ELSE
           ILU = 0
           CALL Warn( 'DampedEigenSolve','Unknown preconditioner type, useing ILU0' )
         END IF
      END IF

      Stat = CRS_IncompleteLU( KMatrix, ILU )
      IF ( .NOT. UseI ) Stat = CRS_IncompleteLU( MMatrix, ILU )

!     %-------------------------------------------%
!     | M A I N   L O O P (Reverse communication) |
!     %-------------------------------------------%

      iter = 1
      DO WHILE( ido /= 99 )

!        %---------------------------------------------%
!        | Repeatedly call the routine DSAUPD and take | 
!        | actions indicated by parameter IDO until    |
!        | either convergence is indicated or maxitr   |
!        | has been exceeded.                          |
!        %---------------------------------------------%
         CALL DNAUPD ( ido, BMAT, n, Which, NEIG, TOL, RESID, NCV, v, n, &
                 IPARAM, IPNTR, WORKD, WORKL, lWORKL, kinfo )

         SELECT CASE(ido)
         CASE(-1 )
            !
            ! ido =-1 inv(A)*M*x:
            !----------------------------
            x => workd( ipntr(1) : ipntr(1)+n-1 )
            b => workd( ipntr(2) : ipntr(2)+n-1 )

            CALL EigenMGmv2( n/2, MMatrix, x, b, UseI, IScale )
            x = b
            CALL EigenBiCG( n, KMatrix, MMatrix, BMatrix, &
                 b, x, DampedMaxIter, DampedTOL, UseI, IScale )

         CASE( 1 )
            ! 
            ! ido =-1 inv(A)*z:
            !--------------------------
            WRITE( Message, * ) ' Arnoldi iteration: ', Iter
            CALL Info( 'EigenSolve', Message, Level=5 )
            iter = iter + 1

            x => workd( ipntr(2) : ipntr(2)+n-1 )
            b => workd( ipntr(3) : ipntr(3)+n-1 )

            CALL EigenBiCG( n, KMatrix, MMatrix, BMatrix, &
                  x, b, DampedMaxIter, DampedTOL, UseI,IScale )

         CASE( 2 )
!           %-----------------------------------------%
!           |         Perform  y <--- M*x.            |
!           | Need the matrix vector multiplication   |
!           | routine here that takes WORKD(IPNTR(1)) |
!           | as the input and returns the result to  |
!           | WORKD(IPNTR(2)).                        |
!           %-----------------------------------------%
            x => workd( ipntr(1): ipntr(1)+n-1 )
            b => workd( ipntr(2): ipntr(2)+n-1 )
            CALL EigenMGmv2( N/2, MMatrix, x, b, UseI, IScale )

         CASE DEFAULT
         END SELECT

      END DO

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
      ELSE 
!        %-------------------------------------------%
!        | No fatal errors occurred.                 |
!        | Post-Process using DSEUPD.                |
!        |                                           |
!        | Computed eigenvalues may be extracted.    |  
!        |                                           |
!        | Eigenvectors may also be computed now if  |
!        | desired.  (indicated by rvec = .true.)    | 
!        %-------------------------------------------%

         D = 0.0d0
         CALL DNEUPD ( .TRUE., 'A', Choose, D, D(1,2), V, N, SigmaR, SigmaI, &
         WORKEV, BMAT, N, Which, NEIG, TOL, RESID, NCV, V, N, IPARAM, IPNTR, &
                        WORKD, WORKL, lWORKL, IERR )
!        %----------------------------------------------%
!        | Eigenvalues are returned in the First column |
!        | of the two dimensional array D and the       |
!        | corresponding eigenvectors are returned in   |
!        | the First NEV columns of the two dimensional |
!        | array V if requested.  Otherwise, an         |
!        | orthogonal basis for the invariant subspace  |
!        | corresponding to the eigenvalues in D is     |
!        | returned in V.                               |
!        %----------------------------------------------%

         IF ( IERR /= 0 ) THEN 
!           %------------------------------------%
!           | Error condition:                   |
!           | Check the documentation of DNEUPD. |
!           %------------------------------------%
            WRITE( Message, * ) ' Error with DNEUPD, info = ', IERR
            CALL Fatal( 'EigenSolve', Message )
         END IF

!        %------------------------------------------%
!        | Print additional convergence information |
!        %------------------------------------------%

         IF ( kinfo == 1 ) THEN
            CALL Fatal( 'EigenSolve', 'Maximum number of iterations reached.' )
         ELSE IF ( kinfo == 3 ) THEN
            CALL Fatal( 'EigenSolve', &
                 'No shifts could be applied during implicit Arnoldi update, try increasing NCV.' )
         END IF      

!        Sort the eigenvalues to ascending order:
!        ( and keep in mind the corresponding vector )
!        ---------------------------------------------
         DO i = 1, NEIG
            EigTemp(i) = DCMPLX( D(i,1), D(i,2) )
         END DO

         ALLOCATE( kMap( NEIG ) )
         kMap(1) = 1
         DO i = 2, NEIG
            IF ( AIMAG( EigTemp(i-1) ) == 0 ) THEN
               kMap(i) = kMap(i-1) + 1
            ELSE IF ( EigTemp(i) == CONJG( EigTemp(i-1) ) ) THEN
               kMap(i) = kMap(i-1)
            ELSE
               kMap(i) = kMap(i-1) + 2
            END IF
         END DO

         ALLOCATE( Perm( NEIG ) )
         Perm = (/ (i, i=1,NEIG) /)
         CALL SortC( NEIG, EigTemp, Perm )
         
!        Extract the values to ELMER structures:
!        -----------------------------------------
         CALL Info( 'EigenSolve', ' ', Level=4 )
         CALL Info( 'EigenSolve', 'EIGEN SYSTEM SOLUTION COMPLETE: ', Level=4 )
         CALL Info( 'EigenSolve', ' ', Level=4 )

         WRITE( Message, * ) 'The convergence criterion is ', TOL
         CALL Info( 'EigenSolve', Message, Level=4 )

         WRITE( Message, * ) ' The number of converged Ritz values is ', &
              IPARAM(5)
         CALL Info( 'EigenSolve', Message, Level=4 )

         CALL Info( 'EigenSolve', ' ', Level=4 )
         CALL Info( 'EigenSolve', 'Computed Eigen Values: ', Level=3 )
         CALL Info( 'EigenSolve', '--------------------------------', Level=3 )

!------------------------------------------------------------------------------
! Extracting the right eigen values and vectors.
!------------------------------------------------------------------------------

! Take the first ones separately
!------------------------------------------------------------------------------
         EigValues(1) = EigTemp(1)         
         
         WRITE( Message, * ) 1,EigValues(1)
         CALL Info( 'EigenSolve', Message, Level=3 )
         
         p = Perm(1)
         k = kMap(p)
         IF( AIMAG( EigValues(1) ) == 0 ) THEN
            DO j = 1, N/2
               EigVectors(1,j) = DCMPLX( V(j,k), 0.0d0 )
            END DO
         ELSE
            DO j = 1, N/2
               EigVectors(1,j) = DCMPLX( V(j,k), V(j,k+1) )
            END DO
         END IF

! Then take the rest of requested values
!------------------------------------------------------------------------------
         l = 2
         DO i = 2, NEIG/2
            IF ( AIMAG( EigValues(i-1) ) /= 0 .AND. &
                 ABS( AIMAG( EigTemp(l) ) ) == ABS( AIMAG( EigValues(i-1) ) ) ) l = l + 1
            
            EigValues(i) = EigTemp(l)
            IF ( AIMAG( EigValues(i) ) < 0 ) THEN
               EigValues(i) = CONJG( EigValues(i) )
            END IF
            
            WRITE( Message, * ) i,EigValues(i)
            CALL Info( 'EigenSolve', Message, Level=3 )
            
            p = Perm(l)
            k = kMap(p)
            IF( AIMAG( EigValues(i) ) == 0 ) THEN
               DO j = 1, N/2
                  EigVectors(i,j) = DCMPLX( V(j,k), 0.0d0 )
               END DO
            ELSE
               DO j = 1, N/2
                  EigVectors(i,j) = DCMPLX( V(j,k), V(j,k+1) )
               END DO
            END IF

            l = l + 1
         END DO
               
! Finally normalize eigenvectors (x) so that x^H(M x) = 1
! (probably already done, but no harm in redoing!)
! -----------------------------------------------------------------------------
         DO i = 1, NEIG/2
            s = 0.0d0
            DO j=1,N/2
               DO k = MMatrix % Rows(j), MMatrix % Rows(j+1)-1
                  s = s + MMatrix % Values(k) * &
                       CONJG( EigVectors(i,j) ) * EigVectors(i,MMatrix % Cols(k))
               END DO
            END DO
            IF ( ABS(s) > 0 ) EigVectors(i,:) = EigVectors(i,:) / SQRT(s)
         END DO
         
         CALL Info( 'EigenSolve', '--------------------------------',Level=3 )
      END IF

      DEALLOCATE( WORKL, D, WORKEV, V, CHOOSE, Perm )

      NULLIFY( MMatrix % Rows, MMatrix % Cols, MMatrix % Diag, MMatrix % Values )
      CALL FreeMatrix( MMatrix )

      NULLIFY( BMatrix % Rows, BMatrix % Cols, BMatrix % Diag, BMatrix % Values )
      CALL FreeMatrix( BMatrix )
#else
      CALL Fatal( 'DampedEigenSolve', 'Arpack Eigen System Solver not available.' )
#endif
!------------------------------------------------------------------------------
     END SUBROUTINE ArpackDampedEigenSolve
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
    SUBROUTINE EigenBiCG( n, KMatrix, MMatrix, BMatrix, x, b, Rounds, TOL, UseI, IScale )
!------------------------------------------------------------------------------
      USE CRSMatrix

      TYPE(Matrix_t), POINTER :: KMatrix, MMatrix, BMatrix
      INTEGER :: Rounds
      REAL(KIND=dp) :: x(:), b(:), TOL, IScale
      LOGICAL :: UseI
!------------------------------------------------------------------------------
      INTEGER :: i, n
      REAL(KIND=dp) :: alpha, beta, omega, rho, oldrho, bnorm
      REAL(KIND=dp) :: r(n), Ri(n), P(n), V(n), S(n), &
           T(n), T1(n), T2(n), Tmp(n/2)
!------------------------------------------------------------------------------
      CALL EigenMGmv1( n/2, KMatrix, MMatrix, BMatrix, x, r, UseI, IScale )
      r(1:n) = b(1:n) - r(1:n)

      Ri(1:n) = r(1:n)
      P(1:n) = 0
      V(1:n) = 0
      omega  = 1
      alpha  = 0
      oldrho = 1
      Tmp = 0.0d0

      bnorm = EigenMGdot( n,b,b )

      CALL Info( 'DampedEigenSolve', '--------------------' )
      CALL Info( 'DampedEigenSolve', 'Begin BiCG iteration' )
      CALL Info( 'DampedEigenSolve', '--------------------' )

      DO i=1,Rounds
         rho = EigenMGdot( n, r, Ri )
         
         beta = alpha * rho / ( oldrho * omega )
         P(1:n) = r(1:n) + beta * (P(1:n) - omega*V(1:n))
!------------------------------------------------------------------------------
         Tmp(1:n/2) = P(1:n/2)

         IF ( .NOT. UseI ) THEN
            CALL CRS_LUSolve( n/2, MMatrix, Tmp(1:n/2) )
         ELSE
            Tmp(1:n/2) = Tmp(1:n/2) / IScale
         END IF

         V(n/2+1:n) = Tmp(1:n/2)

         Tmp(1:n/2) = P(n/2+1:n)
         CALL CRS_LUSolve( n/2, KMatrix, Tmp(1:n/2) )
         V(1:n/2) = -1*Tmp(1:n/2)

         T1(1:n) = V(1:n)         
         CALL EigenMGmv1( n/2, KMatrix, MMatrix, BMatrix, T1, V, UseI, IScale )
!------------------------------------------------------------------------------
         alpha = rho / EigenMGdot( n, Ri, V )         
         S(1:n) = r(1:n) - alpha * V(1:n)         
!------------------------------------------------------------------------------
         Tmp(1:n/2) = S(1:n/2)

         IF ( .NOT. UseI ) THEN
            CALL CRS_LUSolve( n/2, MMatrix, Tmp(1:n/2) )
         ELSE
            Tmp(1:n/2) = Tmp(1:n/2) / IScale
         END IF

         T(n/2+1:n) = Tmp(1:n/2)

         Tmp(1:n/2) = S(n/2+1:n)
         CALL CRS_LUSolve( n/2, KMatrix, Tmp(1:n/2) )
         T(1:n/2) = -1*Tmp(1:n/2)

         T2(1:n) = T(1:n)
         CALL EigenMGmv1( n/2, KMatrix, MMatrix, BMatrix, T2, T, UseI, IScale )
!------------------------------------------------------------------------------
         omega = EigenMGdot( n,T,S ) / EigenMGdot( n,T,T )         
         oldrho = rho
         r(1:n) = S(1:n) - omega*T(1:n)
         x(1:n) = x(1:n) + alpha*T1(1:n) + omega*T2(1:n)
!------------------------------------------------------------------------------
         WRITE(*,*) i,EigenMGdot( n,r,r ) / bnorm

         IF ( EigenMGdot( n,r,r ) / bnorm < TOL ) THEN
            CALL EigenMGmv1( n/2, KMatrix, MMatrix, BMatrix, x, r, UseI, IScale )
            r(1:n) = b(1:n) - r(1:n)

            WRITE( Message,* ) 'Correct residual:', EigenMGdot( n,r,r ) / bnorm
            CALL Info( 'DampedEigenSolve', Message )

            IF ( EigenMGdot( n,r,r ) / bnorm < TOL ) EXIT
         END IF
      END DO

      IF ( EigenMGdot( n,r,r ) / bnorm >= TOL ) THEN
         CALL Fatal( 'EigenBiCG', 'Failed to converge' )
      END IF
!------------------------------------------------------------------------------
    END SUBROUTINE EigenBiCG
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
    FUNCTION EigenMGdot( n, x, y ) RESULT(s)
!------------------------------------------------------------------------------
      USE Types
      INTEGER :: n
      REAL(KIND=dp) :: s, x(:), y(:)
      
      s = DOT_PRODUCT( x(1:n), y(1:n) )
!------------------------------------------------------------------------------
    END FUNCTION EigenMGdot
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
    SUBROUTINE EigenMGmv1( n, KMatrix, MMatrix, BMatrix, x, b, UseI, IScale )
!------------------------------------------------------------------------------
      USE CRSMatrix

      INTEGER :: n
      TYPE(Matrix_t), POINTER :: KMatrix, MMatrix, BMatrix
      REAL(KIND=dp) :: x(:), b(:), IScale
      LOGICAL :: UseI

      REAL(KIND=dp) :: Tmp(n)

      Tmp = 0.0d0
      b = 0.0d0

      IF ( .NOT. UseI ) THEN
         CALL CRS_MatrixVectorMultiply( MMatrix, x(n+1:2*n), Tmp(1:n) )
         b(1:n) = b(1:n) + Tmp(1:n)
      ELSE
         b(1:n) = x(n+1:2*n) * IScale
      END IF

      CALL CRS_MatrixVectorMultiply( KMatrix, x(1:n), Tmp(1:n) )
      b(n+1:2*n) = b(n+1:2*n) - Tmp(1:n)

      CALL CRS_MatrixVectorMultiply( BMatrix, x(n+1:2*n), Tmp(1:n) )
      b(n+1:2*n) = b(n+1:2*n) - Tmp(1:n)
!------------------------------------------------------------------------------
    END SUBROUTINE EigenMGmv1
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
    SUBROUTINE EigenMGmv2( n, MMatrix, x, b, UseI, IScale )
!------------------------------------------------------------------------------
      USE CRSMatrix

      INTEGER :: n
      REAL(KIND=dp) :: x(:), b(:), IScale
      TYPE(Matrix_t), POINTER :: MMatrix
      LOGICAL :: UseI

      IF ( .NOT. UseI ) THEN
         CALL CRS_MatrixVectorMultiply( MMatrix, x(1:n), b(1:n) )
      ELSE
         b(1:n) = x(1:n) * IScale
      END IF
      CALL CRS_MatrixVectorMultiply( MMatrix, x(n+1:2*n), b(n+1:2*n) )
!------------------------------------------------------------------------------
    END SUBROUTINE EigenMGmv2
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
END MODULE EigenSolve
!------------------------------------------------------------------------------
