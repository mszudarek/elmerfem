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
! *****************************************************************************/
!
!/*****************************************************************************
! *
! * Module containing multigrid solver.
! *
! *****************************************************************************
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
! *                       Date: 2001
! *
! *                Modified by:
! *
! *       Date of modification:
! *
! ****************************************************************************/


MODULE Multigrid

   USE CRSMatrix
   USE IterSolve
   USE DirectSolve

   IMPLICIT NONE

CONTAINS

!------------------------------------------------------------------------------
    SUBROUTINE MultiGridSolve( Matrix1, Solution, &
        ForceVector, DOFs, Solver, Level, NewSystem )
!------------------------------------------------------------------------------

       USE ModelDescription
       IMPLICIT NONE

       TYPE(Matrix_t), POINTER :: Matrix1
       INTEGER :: DOFs, Level
       LOGICAL, OPTIONAL :: NewSystem
       TYPE(Solver_t), POINTER :: Solver
       REAL(KIND=dp) :: ForceVector(:), Solution(:)
!------------------------------------------------------------------------------
       LOGICAL :: Found

       IF ( ListGetLogical( Solver % Values, 'MG Algebraic', Found ) ) THEN
         CALL AMGSolve( Matrix1, Solution, ForceVector, DOFs, Solver, Level, NewSystem )
       ELSE
         CALL GMGSolve( Matrix1, Solution, ForceVector, DOFs, Solver, Level, NewSystem )
       END IF

!------------------------------------------------------------------------------
    END SUBROUTINE MultiGridSolve
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    RECURSIVE SUBROUTINE GMGSolve( Matrix1, Solution, &
        ForceVector, DOFs, Solver, Level, NewSystem )
!------------------------------------------------------------------------------
       USE ModelDescription
       IMPLICIT NONE

       TYPE(Matrix_t), POINTER :: Matrix1
       INTEGER :: DOFs, Level
       LOGICAL, OPTIONAL :: NewSystem
       TYPE(Solver_t), POINTER :: Solver
       REAL(KIND=dp) :: ForceVector(:), Solution(:)
!------------------------------------------------------------------------------
       TYPE(Variable_t), POINTER :: Variable1, TimeVar, SaveVariable
       TYPE(Mesh_t), POINTER   :: Mesh1, Mesh2, SaveMesh
       TYPE(Matrix_t), POINTER :: Matrix2, PMatrix, SaveMatrix

       INTEGER :: i,j,k,l,m,n,n2,k1,k2,iter,MaxIter = 100
       LOGICAL :: Condition, Found, Parallel, Project,Transient
       CHARACTER(LEN=MAX_NAME_LEN) :: Path,str,IterMethod,mgname

       TYPE(Matrix_t), POINTER :: ProjPN, ProjQT
       INTEGER, POINTER :: Permutation(:), Permutation2(:)

       REAL(KIND=dp), POINTER :: Residual(:), Work(:), Residual2(:), &
          Work2(:),  Solution2(:), P(:), Q(:), Z(:), R1(:), R2(:)
       REAL(KIND=dp), POINTER :: Ri(:), T(:), T1(:), T2(:), S(:), V(:)

       REAL(KIND=dp) :: ResidualNorm, RHSNorm, Tolerance, &
             ILUTOL, alpha, beta, omega, rho, oldrho

       REAL(KIND=dp) :: CPUTime, tt

       LOGICAL :: NewLinearSystem
       SAVE NewLinearSystem
!------------------------------------------------------------------------------
       tt = CPUTime()
!
!      Initialize:
!      -----------
       Parallel = ParEnv % PEs > 1

       IF ( Level == Solver % MultiGridLevel ) THEN
          NewLinearSystem = .TRUE.

          IF ( PRESENT( NewSystem ) ) THEN
             NewLinearSystem = NewLinearSystem .AND. NewSystem
          END IF
       ELSE IF ( Level <= 1 ) THEN
          NewLinearSystem = .FALSE.
       END IF

!---------------------------------------------------------------------
!
!      If at lowest level, solve directly:
!      -----------------------------------
       IF ( Level <= 1 ) THEN
         IF ( .NOT. Parallel ) THEN
           IF ( ListGetLogical( Solver % Values, 'MG Lowest Linear Solver Iterative',Found ) ) THEN
             CALL IterSolver( Matrix1, Solution, ForceVector, Solver )
           ELSE
             CALL DirectSolver( Matrix1, Solution, ForceVector, Solver )
           END IF
         ELSE
           CALL SParIterSolver( Matrix1, Solver % Mesh % Nodes, DOFs, &
               Solution, ForceVector, Solver, Matrix1 % ParMatrix )
         END IF
         RETURN
       END IF
!
       n = Matrix1 % NumberOfRows
       ALLOCATE( Residual(n) )
       Residual = 0.0d0
!
!      Parallel initializations:
!      -------------------------
       IF ( Parallel ) THEN
          CALL ParallelInitSolve( Matrix1, Solution, ForceVector, &
                     Residual, DOFs, Solver % Mesh )

          PMatrix => ParallelMatrix( Matrix1 ) 
       END IF
!
!      Compute residual:
!      -----------------
       CALL MGmv( Matrix1, Solution, Residual, .TRUE. )
       Residual(1:n) = ForceVector(1:n) - Residual(1:n)
 
       RHSNorm = MGnorm( n, ForceVector )
       ResidualNorm = MGnorm( n, Residual ) / RHSNorm
 
       Tolerance = ListGetConstReal( Solver % Values, &
          'Linear System Convergence Tolerance' )
 
!      IF ( ResidualNorm < Tolerance ) THEN
!         DEALLOCATE( Residual )
!         RETURN
!      END IF
!---------------------------------------------------------------------
!
!      Initialize the multilevel solve:
!      --------------------------------
       SaveMesh     => Solver % Mesh
       SaveMatrix   => Solver % Matrix
       SaveVariable => Solver % Variable

       Mesh1 => Solver % Mesh
       Variable1   => Solver % Variable
       Permutation => Variable1 % Perm

       Mesh2   => Mesh1 % Parent
       Matrix2 => Matrix1 % Parent
!---------------------------------------------------------------------
!
!      Allocate mesh and variable structures for the
!      next level mesh, if not already there:
!      ---------------------------------------------
       IF ( .NOT. ASSOCIATED( Mesh2 ) ) THEN
          mgname = ListGetString( Solver % Values, 'MG Mesh Name', Found )
          IF ( .NOT. Found ) mgname = 'mgrid'

          WRITE( Path,'(a,i1)' ) TRIM(OutputPath) // '/' // TRIM(mgname), Level - 1

          Mesh2 => LoadMesh( CurrentModel, OutputPath, Path, &
               .FALSE., ParEnv % PEs, ParEnv % MyPE )

          CALL UpdateSolverMesh( Solver, Mesh2 )
          CALL ParallelInitMatrix( Solver, Solver % Matrix )

          TimeVar => VariableGet( Mesh1 % Variables, 'Time' )
          CALL VariableAdd( Mesh2 % Variables, Mesh2, Solver, &
                  'Time', 1, TimeVar % Values )

          CALL VariableAdd( Mesh2 % Variables, Mesh2, Solver, &
                'Coordinate 1', 1, Mesh2 % Nodes % x )

          CALL VariableAdd( Mesh2 % Variables, Mesh2, Solver, &
                'Coordinate 2', 1, Mesh2 % Nodes % y )

          CALL VariableAdd( Mesh2 % Variables,Mesh2, Solver, &
                'Coordinate 3', 1, Mesh2 % Nodes % z )

          Matrix2 => Solver % Matrix

          Mesh2 % Child    => Mesh1
          Mesh1 % Parent   => Mesh2

          Matrix2 % Child  => Matrix1
          Matrix1 % Parent => Matrix2

          Permutation2 => Solver % Variable % Perm
       ELSE
          Solver % Mesh => Mesh2
          CALL SetCurrentMesh( CurrentModel, Mesh2 )

          Solver % Variable => VariableGet( Mesh2 % Variables, &
                 Variable1 % Name, ThisOnly = .TRUE. )
       END IF
       Permutation2 => Solver % Variable % Perm

!------------------------------------------------------------------------------
!
!      Some more initializations:
!      --------------------------
       n  = Matrix1 % NumberOfRows
       n2 = Matrix2 % NumberOfRows

       Residual2 => Matrix2 % RHS
       ALLOCATE( Work(n), Work2(n2), Solution2(n2) )
!------------------------------------------------------------------------------
!
!      Mesh projector matrices from the higher level mesh
!      to the  lower and  transpose of the projector from
!      the lower level mesh to the higher:
!      ---------------------------------------------------
       ProjPN => MeshProjector( Mesh2, Mesh1, Trans = .TRUE. )
       ProjQT => MeshProjector( Mesh2, Mesh1, Trans = .TRUE. )

       Project = ListGetLogical( Solver % Values, 'MG Project Matrix', Found )
       IF ( .NOT. Found ) Project = .TRUE.

       IF ( Project ) THEN
          IF ( NewLinearSystem ) THEN
!            Project higher  level coefficient matrix to the
!            lower level: A_low = ProjPN * A_high * ProjQT^T
!            -----------------------------------------------
             CALL ProjectMatrix( Matrix1, Permutation, ProjPN, ProjQT, &
                         Matrix2, Permutation2, DOFs )
          END IF
       ELSE
          IF ( NewLinearSystem ) THEN
             Transient = ListGetString( CurrentModel % Simulation, &
                     'Simulation Type') == 'transient'

             Solver % Matrix => Matrix2
             i = Solver % MultigridLevel

             k  = ListGetInteger( Solver % Values, &
                          'Nonlinear System Max Iterations', Found )
             CALL ListAddInteger( Solver % Values, &
                          'Nonlinear System Max Iterations', 1 )

             Solver % MultigridLevel = -1
             CALL ExecSolver( Solver % PROCEDURE, CurrentModel, &
                      Solver, Solver % dt, Transient )
             Solver % MultigridLevel = i
             CALL ListAddInteger( Solver % Values, &
                      'Nonlinear System Max Iterations',MAX(1, k) )
          END IF
       END IF

!------------------------------------------------------------------------------
!
!      Global iteration parameters:
!      ----------------------------
       MaxIter = 1
       IF ( Level == Solver % MultiGridTotal ) THEN
          MaxIter = ListGetInteger( Solver % Values, &
               'MG Max Iterations', Found )

          IF ( .NOT. Found ) THEN
             MaxIter = ListGetInteger( Solver % Values, &
                  'Linear System Max Iterations' )
          END IF

          Tolerance = ListGetConstReal( Solver % Values, &
              'MG Convergence Tolerance', Found )
          IF ( .NOT. Found ) THEN
             Tolerance = ListGetConstReal( Solver % Values, &
                 'Linear System Convergence Tolerance' )
          END IF
       ELSE
          MaxIter = ListGetInteger( Solver % Values, &
               'MG Level Max Iterations', Found )
          IF ( .NOT. Found ) MaxIter = 1

          Tolerance = ListGetConstReal( Solver % Values, &
              'MG Level Convergence Tolerance', Found )
          IF ( .NOT. Found ) Tolerance = HUGE(Tolerance)
       END IF

!------------------------------------------------------------------------------
!
!      Params for pre/post smoothing steps:
!      ------------------------------------

!
!      Smoothing iterative method:
!      ---------------------------
       IterMethod = ListGetString( Solver % Values, 'MG Smoother', Found )

       IF ( .NOT. Found ) THEN
         IterMethod = ListGetString( Solver % Values, &
           'Linear System Iterative Method', Found )
       END IF
       IF ( .NOT. Found ) IterMethod = 'jacobi'

       SELECT CASE( IterMethod )
         CASE( 'cg' )
            ALLOCATE( Z(n), P(n), Q(n) )

         CASE( 'bicgstab' )
            ALLOCATE( P(n), Ri(n), T(n), T1(n), T2(n), S(n), V(n) )
            IF ( .FALSE. ) PRINT*,SIZE(ri),SIZE(p),SIZE(v)
       END SELECT
!
!      Smoothing preconditiong, if not given
!      diagonal preconditioning is used:
!      -------------------------------------
       str = ListGetString( Solver % Values, 'MG Preconditioning', Found )
       IF ( .NOT. Found ) THEN
         str = ListGetString( Solver % Values, &
           'Linear System Preconditioning', Found )
       END IF

       IF ( str == 'ilut' )  THEN

          IF ( NewLinearSystem ) THEN
             ILUTOL = ListGetConstReal( Solver % Values, &
                  'MG ILUT Tolerance', Found )
             IF ( .NOT. Found ) THEN
                ILUTOL = ListGetConstReal( Solver % Values, &
                     'Linear System ILUT Tolerance' )
             END IF

             IF ( Parallel ) THEN
                Condition = CRS_ILUT( PMatrix, ILUTOL )
             ELSE
                Condition = CRS_ILUT( Matrix1, ILUTOL )
             END IF
          END IF

       ELSE IF ( str(1:3) == 'ilu' ) THEN

          IF ( NewLinearSystem ) THEN
             k = ICHAR(str(4:4)) - ICHAR('0')
             IF ( k < 0 .OR. k > 9 ) k = 0
             IF ( Parallel ) THEN
                Condition = CRS_IncompleteLU( PMatrix, k )
             ELSE
                Condition = CRS_IncompleteLU( Matrix1, k )
             END IF
          END IF

       END IF

!------------------------------------------------------------------------------
!
!      Ok, lets go:
!      ------------
       DO iter = 1,MaxIter
          ResidualNorm = MGSweep() / RHSNorm

          WRITE(Message,'(A,I4,A,I5,A,E20.12E3)') 'MG Residual at level:', &
                 Level, ' iter:', iter,' is:', ResidualNorm
          CALL Info( 'MultigridSolve', Message, Level=5 )

          IF ( ResidualNorm < Tolerance ) EXIT
       END DO


!------------------------------------------------------------------------------
!
!      Finalize:
!      ---------
       IF ( Parallel ) THEN 
          CALL ParallelUpdateResult( Matrix1, Solution, Residual )
       END IF
       Solver % Variable => SaveVariable
       Solver % Mesh     => SaveMesh
       Solver % Matrix   => SaveMatrix
       CALL SetCurrentMesh( CurrentModel, Solver % Mesh )

       DEALLOCATE( Residual, Solution2, Work, Work2 )

       SELECT CASE( IterMethod )
         CASE( 'cg' )
            DEALLOCATE( Z, P, Q )

         CASE( 'bicgstab' )
            DEALLOCATE( P, Ri, T, T1, T2, S, V )
       END SELECT

       IF ( Level == Solver % MultiGridTotal ) THEN
          WRITE( Message, * ) 'MG iter time: ', CPUTime() - tt
          CALL Info( 'MultigridSolve', Message, Level=5 )
       END IF


       RETURN
!------------------------------------------------------------------------------

  CONTAINS

  
!------------------------------------------------------------------------------
    RECURSIVE FUNCTION MGSweep() RESULT(RNorm)
!------------------------------------------------------------------------------
       INTEGER :: i,j,Rounds
       LOGICAL :: Found
       REAL(KIND=dp) :: RNorm
!------------------------------------------------------------------------------
       INTEGER :: Sweeps
       REAL(KIND=dp), POINTER :: R1(:),R2(:)
!------------------------------------------------------------------------------

!      Presmoothing:
!      -------------
       Rounds = ListGetInteger( Solver % Values, &
         'MG Pre Smoothing Iterations', Found )
       IF(.NOT. Found) Rounds = 1

       Sweeps = ListGetInteger( Solver % Values, 'MG Sweeps', Found )
       IF ( .NOT. Found ) Sweeps = 1

       RNorm = Smooth( Matrix1, Solution, ForceVector, &
               Residual, IterMethod, Rounds )
!
!------------------------------------------------------------------------------
!
!     Solve (PAQ)z = Pr, x = x + Qz:
!     ==============================
!
!     Project current residual to the lower level mesh:
!     -------------------------------------------------
      DO i=1,DOFs
         R1 => Residual (i:n :DOFs)
         R2 => Residual2(i:n2:DOFs)

         CALL CRS_ApplyProjector( ProjPN, R1, Permutation, &
                R2, Permutation2, Trans = .FALSE. )
      END DO
!
!     Recursively solve (PAQ)z = Pr:
!     ------------------------------
      Solution2(1:n2) = 0.0d0
      DO i=1,Sweeps
         Work2(1:n2) = Solution2(1:n2)

         CALL GMGSolve( Matrix2, Work2, Residual2, &
                     DOFs, Solver, Level - 1 )

!        Solution2(1:n2) = Solution2(1:n2) + Work2(1:n2)
         Solution2(1:n2) = Work2(1:n2)
      END DO
!
!     Compute x = x + Qz:
!     -------------------
      DO i=1,DOFs
         R1 => Residual (i:n :DOFs)
         R2 => Solution2(i:n2:DOFs)

         CALL CRS_ApplyProjector( ProjQT, R2, Permutation2, &
                R1, Permutation, Trans = .TRUE. )
      END DO

      Solution(1:n) = Solution(1:n) + Residual(1:n)
!
!     Post smoothing:
!     ---------------
      Rounds = ListGetInteger( Solver % Values, &
        'MG Post Smoothing Iterations', Found )
      IF(.NOT. Found) Rounds = 1

      RNorm = Smooth( Matrix1, Solution, ForceVector, &
             Residual, IterMethod, Rounds )
!------------------------------------------------------------------------------
    END FUNCTION MGSweep
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    FUNCTION Smooth( A, x, b, r, IterMethod, Rounds ) RESULT(RNorm)
!------------------------------------------------------------------------------
       TYPE(Matrix_t), POINTER :: A
       INTEGER :: Rounds
       CHARACTER(LEN=*) :: IterMethod
       REAL(KIND=dp), TARGET :: x(:),b(:),r(:),RNorm
!------------------------------------------------------------------------------
       TYPE(Matrix_t), POINTER :: M
       INTEGER :: n
       REAL(KIND=dp), POINTER :: Mx(:),Mb(:),Mr(:)
!------------------------------------------------------------------------------
       IF ( .NOT. Parallel ) THEN
          M  => A
          Mx => x
          Mb => b
          Mr => r
       ELSE
          CALL ParallelUpdateSolve( A,x,r )
          M => ParallelMatrix( A, Mx, Mb, Mr )
       END IF

       n = M % NumberOfRows

       IF ( Rounds >= 1 ) THEN
          SELECT CASE( IterMethod )
             CASE( 'cg' )
                CALL CG( n, A, M, Mx, Mb, Mr, Rounds )

             CASE( 'bicgstab' )
                CALL BiCG( n, A, M, Mx, Mb, Mr, Rounds )

             CASE DEFAULT
                IF ( A % Complex ) THEN
                   CALL CJacobi( n, A, M, Mx, Mb, Mr, Rounds )
                ELSE 
                   CALL Jacobi( n, A, M, Mx, Mb, Mr, Rounds )
                END IF
          END SELECT
       END IF
 
       CALL MGmv( A, x, r, .TRUE. )
       r = b - r
       IF ( Parallel ) Mr = Mb - Mr

       RNorm = MGnorm( n, Mr ) 
!------------------------------------------------------------------------------
    END FUNCTION Smooth
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
    SUBROUTINE CJacobi( n, A, M, rx, rb, rr, Rounds )
!------------------------------------------------------------------------------
       TYPE(Matrix_t), POINTER :: A, M
       INTEGER :: n,Rounds
       REAL(KIND=dp) :: rx(:),rb(:),rr(:)
!------------------------------------------------------------------------------
       COMPLEX(KIND=dp) :: x(n/2),b(n/2),r(n/2),s
!------------------------------------------------------------------------------
       INTEGER :: i,j,k
!------------------------------------------------------------------------------
       j = 1
       DO i=1,n,2
          x(j) = DCMPLX( rx(i),rx(i+1) )
          b(j) = DCMPLX( rb(i),rb(i+1) )
          r(j) = DCMPLX( rr(i),rr(i+1) )
          j = j + 1
       END DO

       DO i=1,Rounds
          CALL CRS_ComplexMatrixVectorMultiply( A, x, r )
          r(1:n/2) = b(1:n/2) - r(1:n/2)

          k = 1
          DO j=1,n,2
            s = DCMPLX( M % Values( M % Diag(j) ), -M % Values(M % Diag(j)+1) )
            r(k) = r(k) / s
            k = k + 1
          END DO
          x(1:n/2) = x(1:n/2) + r(1:n/2)
       END DO

       j = 0
       DO i=1,n,2
          j = j + 1
          rx(i)   =  REAL( x(j) )
          rx(i+1) = AIMAG( x(j) )
       END DO
!------------------------------------------------------------------------------
    END SUBROUTINE CJacobi
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    SUBROUTINE CG( n, A, M, x, b, r, Rounds )
!------------------------------------------------------------------------------
       TYPE(Matrix_t), POINTER :: A,M
       INTEGER :: Rounds
       REAL(KIND=dp) :: x(:),b(:),r(:)
       REAL(KIND=dp) :: alpha,rho,oldrho
!------------------------------------------------------------------------------
       INTEGER :: i,n
!------------------------------------------------------------------------------
       CALL MGmv( A, x, r )
       r(1:n) = b(1:n) - r(1:n)

       DO i=1,Rounds
          Z(1:n) = r(1:n)
          CALL CRS_LUSolve( n, M, Z )
          rho = MGdot( n, r, Z )

          IF ( i == 1 ) THEN
             P(1:n) = Z(1:n)
          ELSE
             P(1:n) = Z(1:n) + rho * P(1:n) / oldrho
          END IF

          CALL MGmv( A, P, Q )
          alpha  = rho / MGdot( n, P, Q )
          oldrho = rho

          x(1:n) = x(1:n) + alpha * P(1:n)
          r(1:n) = r(1:n) - alpha * Q(1:n)
       END DO
!------------------------------------------------------------------------------
    END SUBROUTINE CG
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    SUBROUTINE CCG( n, A, M, rx, rb, rr, Rounds )
!------------------------------------------------------------------------------
       INTEGER :: i,n, Rounds
       TYPE(Matrix_t), POINTER :: A,M
       REAL(KIND=dp) :: rx(:),rb(:),rr(:)
       COMPLEX(KIND=dp) :: alpha,rho,oldrho
       COMPLEX(KIND=dp) :: r(n/2),b(n/2),x(n/2)
       COMPLEX(KIND=dp) :: Z(n), P(n), Q(n)
!------------------------------------------------------------------------------
       DO i=1,n/2
         r(i) = DCMPLX( rr(2*i-1), rr(2*i) )
         x(i) = DCMPLX( rx(2*i-1), rx(2*i) )
         b(i) = DCMPLX( rb(2*i-1), rb(2*i) )
       END DO

       CALL MGCmv( A, x, r )
       r(1:n/2) = b(1:n/2) - r(1:n/2)

       DO i=1,Rounds
          Z(1:n/2) = r(1:n/2)
          CALL CRS_ComplexLUSolve( n, M, Z )
          rho = MGCdot( n/2, r, Z )

          IF ( i == 1 ) THEN
             P(1:n/2) = Z(1:n/2)
          ELSE
             P(1:n/2) = Z(1:n/2) + rho * P(1:n/2) / oldrho
          END IF

          CALL MGCmv( A, P, Q )
          alpha  = rho / MGCdot( n/2, P, Q )
          oldrho = rho

          x(1:n/2) = x(1:n/2) + alpha * P(1:n/2)
          r(1:n/2) = r(1:n/2) - alpha * Q(1:n/2)
       END DO

       DO i=1,n/2
         rr(2*i-1) =  REAL( r(i) )
         rr(2*i-0) =  AIMAG( r(i) )
         rx(2*i-1) =  REAL( x(i) )
         rx(2*i-0) =  AIMAG( x(i) )
         rb(2*i-1) =  REAL( b(i) )
         rb(2*i-0) =  AIMAG( b(i) )
       END DO
!------------------------------------------------------------------------------
    END SUBROUTINE CCG
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    SUBROUTINE BiCG( n, A, M, x, b, r, Rounds )
!------------------------------------------------------------------------------
       TYPE(Matrix_t), POINTER :: A,M
       INTEGER :: Rounds
       REAL(KIND=dp) :: x(:),b(:),r(:)
!------------------------------------------------------------------------------
       INTEGER :: i,n
       REAL(KIND=dp) :: alpha,beta,omega,rho,oldrho
!------------------------------------------------------------------------------
       CALL MGmv( A, x, r )
       r(1:n) = b(1:n) - r(1:n)

       Ri(1:n) = r(1:n)
       P(1:n) = 0
       V(1:n) = 0
       omega  = 1
       alpha  = 0
       oldrho = 1

       DO i=1,Rounds
          rho = MGdot( n, r, Ri )

          beta = alpha * rho / ( oldrho * omega )
          P(1:n) = r(1:n) + beta * (P(1:n) - omega*V(1:n))

          V(1:n) = P(1:n)
          CALL CRS_LUSolve( n, M, V )
          T1(1:n) = V(1:n)
          CALL MGmv( A, T1, V )

          alpha = rho / MGdot( n, Ri, V )

          S(1:n) = r(1:n) - alpha * V(1:n)

          T(1:n) = S(1:n)
          CALL CRS_LUSolve( n, M, T )
          T2(1:n) = T(1:n)
          CALL MGmv( A, T2, T )
          omega = MGdot( n,T,S ) / MGdot( n,T,T )

          oldrho = rho
          r(1:n) = S(1:n) - omega*T(1:n)
          x(1:n) = x(1:n) + alpha*T1(1:n) + omega*T2(1:n)
       END DO
!------------------------------------------------------------------------------
    END SUBROUTINE BiCG
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    SUBROUTINE ProjectMatrix( A, PermA, P, Q, B, PermB, DOFs )
!------------------------------------------------------------------------------
!
!     Project matrix A to B: B = PAQ^T
!
!     The code is a little complicated by the fact that there might be
!     three different  numbering schemes for  the DOFs: one  for both
!     matrices and the nodal numbering of the projectors.
!
!------------------------------------------------------------------------------
      TYPE(Matrix_t), POINTER :: A,P,Q,B
      INTEGER :: DOFs
      INTEGER, POINTER :: PermA(:), PermB(:)
!------------------------------------------------------------------------------
      INTEGER, POINTER :: L1(:), L2(:), InvPermB(:)
      REAL(KIND=dp) :: s
      REAL(KIND=dp), POINTER :: R1(:),R2(:)
      INTEGER :: i,j,k,l,NA,NB,N,k1,k2,k3,ni,nj,RDOF,CDOF
!------------------------------------------------------------------------------

      NA = A % NumberOfRows
      NB = B % NumberOfRows
!
!     Compute size for the work arrays:
!     ---------------------------------
      N = 0
      DO i=1, P % NumberOfRows
         N = MAX( N, P % Rows(i+1) - P % Rows(i) )
      END DO

      DO i=1, Q % NumberOfRows
         N = MAX( N, Q % Rows(i+1) - Q % Rows(i) )
      END DO
!
!     Allocate temporary workspace:
!     -----------------------------
      ALLOCATE( R1(N), R2(NA), L1(N), L2(N), InvPermB(SIZE(PermB)) )

!
!     Initialize:
!     -----------
      InvPermB = 0
      DO i = 1, SIZE(PermB)
         IF ( PermB(i) > 0 ) InvPermB( PermB(i) ) = i
      END DO

      R1 = 0.0d0  ! P_i:
      R2 = 0.0d0  ! Q_j: ( = Q^T_:j )

      L1 = 0      ! holds column indices of P_i in A numbering
      L2 = 0      ! holds column indices of Q_j in A numbering

      B % Values = 0.0d0

!------------------------------------------------------------------------------
!
!     Compute the projection:
!     =======================
!
!     The code below duplicated for DOFs==1, and otherwise:
!     -----------------------------------------------------
      IF ( DOFs == 1 ) THEN
!
!        Loop over rows of B:
!        --------------------
         DO i=1,NB
!
!           Get i:th row of projector P: R1=P_i
!           -----------------------------------
            ni = 0   ! number of nonzeros in P_i
            k1 = InvPermB(i)
            DO k = P % Rows(k1), P % Rows(k1+1) - 1
               l = PermA( P % Cols(k) )
               IF ( l > 0 ) THEN
                  ni = ni + 1
                  L1(ni) = l
                  R1(ni) = P % Values(k)
               END IF
            END DO

            IF ( ni <= 0 ) CYCLE
!
!           Loop over columns of row i of B:
!           --------------------------------
            DO j = B % Rows(i), B % Rows(i+1)-1
!
!              Get j:th row of projector Q: R2=Q_j
!              -----------------------------------
               nj = 0 ! number of nonzeros in Q_j
               k2 = InvPermB( B % Cols(j) )
               DO k = Q % Rows(k2), Q % Rows(k2+1)-1
                  l = PermA( Q % Cols(k) )
                  IF ( l > 0 ) THEN
                     nj = nj + 1
                     L2(nj) = l
                     R2(l)  = Q % Values(k)
                  END IF
               END DO

               IF ( nj <= 0 ) CYCLE
!
!              s=A(Q_j)^T, only entries correspoding to
!              nonzeros in P_i actually computed, then
!              B_ij = DOT( P_i, A(Q_j)^T ):
!              ------------------------------------------
               DO k=1,ni
                  k2 = L1(k)
                  s = 0.0d0
                  DO l = A % Rows(k2), A % Rows(k2+1)-1
                     s = s + R2(A % Cols(l)) * A % Values(l)
                  END DO
                  B % Values(j) = B % Values(j) + s * R1(k)
               END DO
               R2(L2(1:nj)) = 0.0d0
            END DO
         END DO

      ELSE ! DOFs /= 1
!
!        Loop over rows of B:
!        --------------------
         DO i=1,NB/DOFs
!
!           Get i:th row of projector P: R1=P_i
!           -----------------------------------
            ni = 0   ! number of nonzeros in P_i
            k1 = InvPermB(i)
            DO k = P % Rows(k1), P % Rows(k1+1) - 1
               l = PermA( P % Cols(k) )
               IF ( l > 0 ) THEN
                  ni = ni + 1
                  L1(ni) = l
                  R1(ni) = P % Values(k)
               END IF
            END DO

            IF ( ni <= 0 ) CYCLE

            DO RDOF = 1,DOFs
!
!              Loop over columns of row i of B:
!              --------------------------------
               k1 = DOFs*(i-1) + RDOF
               DO j = B % Rows(k1), B % Rows(k1+1)-1, DOFs
!
!                 Get j:th row of projector Q: R2=Q_j
!                 -----------------------------------
                  nj = 0 ! number of nonzeros in Q_j
                  k2 = InvPermB( (B % Cols(j)-1) / DOFs + 1 )
                  DO k = Q % Rows(k2), Q % Rows(k2+1)-1
                     l = PermA( Q % Cols(k) )
                     IF ( l > 0 ) THEN
                        nj = nj + 1
                        L2(nj)  = l
                        DO CDOF=1,DOFs
                           R2(DOFs*(l-1)+CDOF) = Q % Values(k)
                        END DO
                     END IF
                  END DO

                  IF ( nj <= 0 ) CYCLE

                  DO CDOF=0,DOFs-1
!
!                    s = A(Q_j)^T, only entries correspoding to
!                    nonzeros in P_i actually  computed, then
!                    B_ij = DOT( P_i, A(Q_j)^T ):
!                    ------------------------------------------
                     DO k=1,ni
                        k2 = DOFs * (L1(k)-1) + RDOF
                        s = 0.0d0
                        DO l = A % Rows(k2)+CDOF, A % Rows(k2+1)-1, DOFs
                           s = s + R2(A % Cols(l)) * A % Values(l)
                        END DO
                        B % Values(j+CDOF) = B % Values(j+CDOF) + s * R1(k)
                     END DO
                     R2(DOFs*(L2(1:nj)-1)+CDOF+1) = 0.0d0
                  END DO
               END DO
            END DO
         END DO
      END IF

      DEALLOCATE( R1, R2, L1, L2, InvPermB )
!------------------------------------------------------------------------------
    END SUBROUTINE ProjectMatrix
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    FUNCTION MGnorm( n, x ) RESULT(s)
!------------------------------------------------------------------------------
       INTEGER :: n
       REAL(KIND=dp) :: s,x(:)
!------------------------------------------------------------------------------
       IF ( .NOT. Parallel ) THEN
          s = SQRT( DOT_PRODUCT( x(1:n), x(1:n) ) )
       ELSE
          s = ParallelNorm( n, x )
       END IF
!------------------------------------------------------------------------------
    END FUNCTION MGnorm
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    FUNCTION MGdot( n, x, y ) RESULT(s)
!------------------------------------------------------------------------------
       INTEGER :: n
       REAL(KIND=dp) :: s,x(:),y(:)
!------------------------------------------------------------------------------
       IF ( .NOT. Parallel ) THEN
          s = DOT_PRODUCT( x(1:n), y(1:n) )
       ELSE
          s = ParallelDot( n, x, y )
       END IF
!------------------------------------------------------------------------------
    END FUNCTION MGdot
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    SUBROUTINE MGmv( A, x, b, Update )
!------------------------------------------------------------------------------
       REAL(KIND=dp) :: x(:), b(:)
       LOGICAL, OPTIONAL :: Update
       TYPE(Matrix_t), POINTER :: A
!------------------------------------------------------------------------------
       IF ( .NOT. Parallel ) THEN
         CALL CRS_MatrixVectorMultiply( A, x, b )
       ELSE
         IF ( PRESENT( Update ) ) THEN
           CALL ParallelMatrixVector( A,x,b,Update )
         ELSE
           CALL ParallelMatrixVector( A,x,b )
         END IF
       END IF
!------------------------------------------------------------------------------
    END SUBROUTINE MGmv
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    FUNCTION MGCnorm( n, x ) RESULT(s)
!------------------------------------------------------------------------------
       INTEGER :: n
       COMPLEX(KIND=dp) :: s,x(:)
!------------------------------------------------------------------------------
       s = SQRT( DOT_PRODUCT( x(1:n), x(1:n) ) )
!------------------------------------------------------------------------------
    END FUNCTION MGCnorm
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    FUNCTION MGCdot( n, x, y ) RESULT(s)
!------------------------------------------------------------------------------
       INTEGER :: n
       COMPLEX(KIND=dp) :: s,x(:),y(:)
!------------------------------------------------------------------------------
       s = DOT_PRODUCT( x(1:n), y(1:n) )
!------------------------------------------------------------------------------
    END FUNCTION MGCdot
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    SUBROUTINE MGCmv( A, x, b, Update )
!------------------------------------------------------------------------------
       COMPLEX(KIND=dp) :: x(:), b(:)
       LOGICAL, OPTIONAL :: Update
       TYPE(Matrix_t), POINTER :: A
!------------------------------------------------------------------------------
       CALL CRS_ComplexMatrixVectorMultiply( A, x, b )
!------------------------------------------------------------------------------
    END SUBROUTINE MGCmv
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
  END SUBROUTINE GMGSolve
!------------------------------------------------------------------------------



!/*****************************************************************************
! *
! * Subroutine containing algebraic multigrid solver.
! *
! *****************************************************************************
! *
! *       Author: Peter R�back
! *
! *       Modified by: 
! *
! *       Date of modification: 30.10.2003
! *
! ****************************************************************************/

!------------------------------------------------------------------------------
  RECURSIVE SUBROUTINE AMGSolve( Matrix1, Solution, &
    ForceVector, DOFs, Solver, Level, NewSystem )
!------------------------------------------------------------------------------
    USE ModelDescription
    IMPLICIT NONE
    
    TYPE(Matrix_t), POINTER :: Matrix1
    INTEGER :: DOFs, Level
    LOGICAL, OPTIONAL :: NewSystem
    TYPE(Solver_t), POINTER :: Solver
    REAL(KIND=dp) :: ForceVector(:), Solution(:)
!------------------------------------------------------------------------------
    TYPE AMG_t
      INTEGER, POINTER :: CF(:)
      INTEGER, POINTER :: InvCF(:) 
    END TYPE AMG_t

    TYPE(AMG_t), POINTER :: AMG(:)
    TYPE(Mesh_t), POINTER   :: Mesh
    TYPE(Matrix_t), POINTER :: Matrix2, Pmatrix
    
    INTEGER :: i,j,k,l,m,n,n2,k1,k2,iter,MaxIter = 100, DirectLimit, MinLevel
    LOGICAL :: Condition, Found, Parallel, Project,EliminateDir
    CHARACTER(LEN=MAX_NAME_LEN) :: str,IterMethod,mgname
    INTEGER, POINTER :: CF(:), InvCF(:)
    
    TYPE(Matrix_t), POINTER :: ProjPN, ProjQT, ProjT 
    
    REAL(KIND=dp), POINTER :: Residual(:), Work(:), Residual2(:), &
        Work2(:),  Solution2(:), P(:), Q(:), Z(:), R1(:), R2(:)
    REAL(KIND=dp), POINTER :: Ri(:), T(:), T1(:), T2(:), S(:), V(:)
    
    REAL(KIND=dp) :: ResidualNorm, RHSNorm, Tolerance, &
        ILUTOL, alpha, beta, omega, rho, oldrho
    
    REAL(KIND=dp) :: CPUTime, tt, tt2

    LOGICAL :: NewLinearSystem, gotit, IdenticalSets, IdenticalProjs

    SAVE NewLinearSystem, AMG, MinLevel
    
!------------------------------------------------------------------------------

    WRITE(Message,'(A,I2)') 'Starting level ',Level
    CALL Info('AMGSolve',Message)

    Mesh => Solver % Mesh    


    tt = CPUTime()
!
!      Initialize:
!      -----------
    Parallel = ParEnv % PEs > 1

    ! This is a counter that for the first full resursive round keeps the 
    ! flag NewLinerSystem true.
    IF ( Level == Solver % MultiGridLevel ) THEN
      NewLinearSystem = .TRUE.
      MinLevel = Solver % MultiGridLevel

      IF ( PRESENT( NewSystem ) ) THEN
        NewLinearSystem = NewLinearSystem .AND. NewSystem
      END IF
    ELSE IF ( Level <= 1 ) THEN
      NewLinearSystem = .FALSE.
    END IF

!---------------------------------------------------------------------
!
!      If at lowest level, solve directly:
!      -----------------------------------
    n = Matrix1 % NumberOfRows

    DirectLimit = ListGetInteger(Solver % Values,'MG Lowest Linear Solver Limit',GotIt) 
    IF(.NOT. GotIt) DirectLimit = 10

    IF ( Level <= 1 .OR. n < DirectLimit) THEN
      IF ( .NOT. Parallel ) THEN
        IF ( ListGetLogical( Solver % Values, 'MG Lowest Linear Solver Iterative',gotit ) ) THEN
          CALL IterSolver( Matrix1, Solution, ForceVector, Solver )
        ELSE
          print *,'a1',Matrix1 % Complex,SIZE(Solution),SIZE(ForceVector)
          print *,'si',SIZE(Matrix1 % Values), Matrix1 % NumberOfRows
          CALL SaveMatrix(Matrix1, 'proj.dat')          
          CALL DirectSolver( Matrix1, Solution, ForceVector, Solver )
          print *,'a2'
        END IF
      ELSE
        CALL SParIterSolver( Matrix1, Solver % Mesh % Nodes, DOFs, &
            Solution, ForceVector, Solver, Matrix1 % ParMatrix )
      END IF
      RETURN
    END IF
    
    n = Matrix1 % NumberOfRows
    ALLOCATE( Residual(n) )
    Residual = 0.0d0

!      Parallel initializations:
!      -------------------------
    IF ( Parallel ) THEN
      CALL ParallelInitSolve( Matrix1, Solution, ForceVector, &
          Residual, DOFs, Solver % Mesh )
      
      PMatrix => ParallelMatrix( Matrix1 ) 
    END IF

!      Compute residual:
!      -----------------
    IF(SIZE(Solution) /= Matrix1 % NumberOfRows) THEN
      CALL WARN('AMGSolve','Solution and matrix sizes differ')
    END IF

    CALL MGmv( Matrix1, Solution, Residual, .TRUE. )
    Residual(1:n) = ForceVector(1:n) - Residual(1:n)

    RHSNorm = MGnorm( n, ForceVector )
    ResidualNorm = MGnorm( n, Residual ) / RHSNorm

    Tolerance = ListGetConstReal( Solver % Values,'Linear System Convergence Tolerance' )

!---------------------------------------------------------------------
!
!      Initialize the multilevel solve:
!      --------------------------------


!---------------------------------------------------------------------
!      Create the Projectors between different levels
!      ---------------------------------------------


    IF( .NOT. ListGetLogical(Solver % Values,'MG Recompute Projector',GotIt) ) THEN
      NewLinearSystem = .NOT. ASSOCIATED(Matrix1 % Parent)
    END IF

    IF ( NewLinearSystem ) THEN
      ! If the projection matrix is made again deallocate the old projectors
      IF(ASSOCIATED(Matrix1 % Parent)) CALL FreeMatrix(Matrix1 % Parent)
      IF(ASSOCIATED(Matrix1 % Ematrix)) CALL FreeMatrix(Matrix1 % Ematrix)

      ! In the first time compute the node angles
      IF( Level == Solver % MultiGridTotal) THEN
        ALLOCATE(AMG(Solver % MultiGridTotal))
      END IF

      WRITE( Message, '(A,I3)' ) 'Creating a new matrix and projector for level',Level
      CALL Info('AMGSolve', Message)
      MinLevel = MIN(MinLevel,Level)
      
      EliminateDir = ListGetLogical(Solver % Values,'MG Eliminate Dirichlet',GotIt) 
      IF(.NOT. GotIt) EliminateDir = .TRUE.
      IF(Level /= Solver % MultiGridTotal) EliminateDir = .FALSE.

      IdenticalProjs = ListGetLogical(Solver % Values,'MG Identical Component Projectors',GotIt) 
      IdenticalSets = ListGetLogical(Solver % Values,'MG Identical Component Sets',GotIt)
      IF(IdenticalProjs) IdenticalSets = .TRUE.

      IF( IdenticalSets ) THEN
        CALL ChooseCoarseNodes(Matrix1, Solver, ProjT, DOFs, CF, InvCF)
      ELSE
        CALL ChooseCoarseNodes(Matrix1, Solver, ProjT, 1, CF, InvCF)
      END IF

!      CALL SaveMatrix(ProjT, 'proj.dat')
      
      ! The initial projection matrix is a transpose of the wanted one. 
      ! It is needed only in determining the matrix structure. 
      
      ProjPN => CRS_Transpose( ProjT )
      ProjQT => ProjPN
      
      Matrix1 % Ematrix => ProjPN
      ProjPN % Perm => CF
     

      ! Make the cnodes point to the set of original nodes
      AMG(Level) % InvCF => InvCF
      IF(Level < Solver % MultiGridTotal .AND. ASSOCIATED(InvCF)) THEN
        DO i=1,SIZE(InvCF)
          IF(InvCF(i) > 0) InvCF(i) = AMG(Level+1) % InvCF(InvCF(i))
        END DO
      END IF
 
      !     CALL ParallelInitMatrix( Solver, Solver % Matrix )
     
      !     Project higher  level coefficient matrix to the
      !     lower level: A_low = ProjPN * A_high * ProjQT^T
      !            -----------------------------------------------
      
      tt2 = CPUTime()
      
      IF(IdenticalProjs) THEN
        CALL CRS_ProjectMatrixCreate( Matrix1, ProjPN, ProjT, Matrix2, DOFs)
      ELSE 
        PRINT *,'DOFs1',Matrix1 % NumberOfRows, ProjT % NumberOfRows
        l = MAX( Matrix1 % NumberOfRows / ProjT % NumberOfRows, 1)
        CALL CRS_ProjectMatrixCreate( Matrix1, ProjPN, ProjT, Matrix2, l)
        PRINT *,'DOFs2',Matrix2 % NumberOfRows, ProjPN % NumberOfRows
      END IF
      CALL FreeMatrix(ProjT)      

      WRITE(Message,'(A,F5.1,A)') 'Coarse matrix element fraction',&
          100.0 *  SIZE(Matrix2 % Cols) / SIZE(Matrix1 % Cols),' %'
      CALL Info('AMGSolve',Message)
      
      Matrix2 % Child  => Matrix1
      Matrix1 % Parent => Matrix2

      WRITE( Message, '(A,ES15.4)' ) 'MG coarse matrix projection time: ', CPUTime() - tt2
      CALL Info( 'AMGSolve', Message, Level=5 )

      IF( ListGetLogical(Solver % Values,'MG Coarse Nodes Save', GotIt) ) THEN
        CALL AMGTest(0)
!        CALL AMGTest(1)
!        CALL AMGTest(2)         
      END IF
    ELSE
      Matrix2 => Matrix1 % Parent
      ProjPN => Matrix1 % Ematrix
      ProjQT => ProjPN
      CF => ProjPN % Perm
    END IF

    n  = Matrix1 % NumberOfRows
    n2 = Matrix2 % NumberOfRows

    Residual2 => Matrix2 % RHS
    ALLOCATE( Work(n), Work2(n2), Solution2(n2) )

    
!------------------------------------------------------------------------------
!      Global iteration parameters:
!      ----------------------------

    MaxIter = 1
    IF ( Level == Solver % MultiGridTotal ) THEN
      MaxIter = ListGetInteger( Solver % Values, &
          'MG Max Iterations', Found )
      IF ( .NOT. Found ) THEN
        MaxIter = ListGetInteger( Solver % Values, &
            'Linear System Max Iterations' )
      END IF
      Tolerance = ListGetConstReal( Solver % Values, &
          'MG Convergence Tolerance', Found )
      IF ( .NOT. Found ) THEN
        Tolerance = ListGetConstReal( Solver % Values, &
            'Linear System Convergence Tolerance' )
      END IF
    ELSE
      MaxIter = ListGetInteger( Solver % Values, &
          'MG Level Max Iterations', Found )
      IF ( .NOT. Found ) MaxIter = 1         
      Tolerance = ListGetConstReal( Solver % Values, &
          'MG Level Convergence Tolerance', Found )
      IF ( .NOT. Found ) Tolerance = HUGE(Tolerance)
    END IF
    
!------------------------------------------------------------------------------
!
!      Params for pre/post smoothing steps:
!      ------------------------------------

!
!      Smoothing iterative method:
!      ---------------------------
    IterMethod = ListGetString( Solver % Values, 'MG Smoother', Found )
   
    IF ( .NOT. Found ) THEN
      IterMethod = ListGetString( Solver % Values, &
          'Linear System Iterative Method', Found )
    END IF
    IF ( .NOT. Found ) IterMethod = 'jacobi'
    
    SELECT CASE( IterMethod )
      CASE( 'cg' )
      ALLOCATE( Z(n), P(n), Q(n) )
      
      CASE( 'bicgstab' )
      ALLOCATE( P(n), Ri(n), T(n), T1(n), T2(n), S(n), V(n) )
    END SELECT
!
!      Smoothing preconditiong, if not given
!      diagonal preconditioning is used:
!      -------------------------------------

    str = ListGetString( Solver % Values, 'MG Preconditioning', Found )
    IF ( .NOT. Found ) THEN
      str = ListGetString( Solver % Values, &
          'Linear System Preconditioning', Found )
    END IF
    
    IF ( str == 'ilut' )  THEN
      IF ( NewLinearSystem ) THEN
        ILUTOL = ListGetConstReal( Solver % Values,'MG ILUT Tolerance', GotIt )
        IF ( .NOT. GotIt ) THEN
          ILUTOL = ListGetConstReal( Solver % Values,'Linear System ILUT Tolerance' )
        END IF
        
        IF ( Parallel ) THEN
          Condition = CRS_ILUT( PMatrix, ILUTOL )
        ELSE
          Condition = CRS_ILUT( Matrix1, ILUTOL )
        END IF
      END IF
      
    ELSE IF ( str(1:3) == 'ilu' ) THEN      
      IF ( NewLinearSystem ) THEN
        k = ICHAR(str(4:4)) - ICHAR('0')
        IF ( k < 0 .OR. k > 9 ) k = 0
        IF ( Parallel ) THEN
          Condition = CRS_IncompleteLU( PMatrix, k )
        ELSE
          Condition = CRS_IncompleteLU( Matrix1, k )
        END IF
      END IF      
    END IF

!------------------------------------------------------------------------------
!
!      Ok, lets go:
!      ------------
    DO iter = 1,MaxIter

      ResidualNorm = MGSweep() / RHSNorm
     
      WRITE(Message,'(A,I4,A,I5,A,E20.12E3)') 'MG Residual at level:', &
          Level, ' iter:', iter,' is:', ResidualNorm
      CALL Info( 'AMGSolve', Message, Level=5 )
      
      IF ( ResidualNorm < Tolerance ) EXIT
    END DO
    
!------------------------------------------------------------------------------
!
!      Finalize:
!      ---------
    IF ( Parallel ) THEN 
      CALL ParallelUpdateResult( Matrix1, Solution, Residual )
    END IF
    
    DEALLOCATE( Residual, Solution2, Work, Work2 )
    
    SELECT CASE( IterMethod )
      CASE( 'cg' )
      DEALLOCATE( Z, P, Q )
      
      CASE( 'bicgstab' )
      DEALLOCATE( P, Ri, T, T1, T2, S, V )
    END SELECT

    IF ( Level == Solver % MultiGridTotal ) THEN
      WRITE( Message, '(A,ES15.4)' ) 'MG iter time: ', CPUTime() - tt
      CALL Info( 'AMGSolve', Message, Level=5 )

      IF(ASSOCIATED(AMG)) THEN
        DO i=MinLevel,Solver % MultiGridTotal
          IF(ASSOCIATED(AMG(i) % InvCF)) DEALLOCATE(AMG(i) % InvCF)
        END DO
        DEALLOCATE(AMG)
      END IF

    END IF
    
    RETURN
!------------------------------------------------------------------------------

  CONTAINS

  
!------------------------------------------------------------------------------
    RECURSIVE FUNCTION MGSweep() RESULT(RNorm)
!------------------------------------------------------------------------------
      INTEGER :: i,j,Rounds
      LOGICAL :: GotIt
      REAL(KIND=dp) :: RNorm
!------------------------------------------------------------------------------
      INTEGER :: Sweeps
      REAL(KIND=dp), POINTER :: R1(:),R2(:)
!------------------------------------------------------------------------------

!      Presmoothing:
!      -------------
      Rounds = ListGetInteger( Solver % Values,'MG Pre Smoothing Iterations', GotIt )
      IF(.NOT. GotIt) Rounds = 1

      Sweeps = ListGetInteger( Solver % Values, 'MG Sweeps', GotIt )
      IF ( .NOT. GotIt ) Sweeps = 1

      RNorm = Smooth( Matrix1, Solution, ForceVector,Residual, IterMethod, Rounds)

!
!------------------------------------------------------------------------------
!
!      Solve (PAQ)z = Pr, x = x + Qz:
!      ==============================
!
!      Project current residual to the lower level mesh:
!      -------------------------------------------------
      R1 => Residual(1:n)
      R2 => Residual2(1:n2)

      CALL CRS_ProjectVector( ProjPN, R1, R2, Trans = .FALSE. )
!
!      Recursively solve (PAQ)z = Pr:
!      ------------------------------
      Solution2 = 0.0d0

!      numbers of W-cycles
      DO i=1,Sweeps
        Work2(1:n2) = Solution2(1:n2)

        CALL AMGSolve( Matrix2, Work2, Residual2, DOFs, Solver, Level - 1 )

        Solution2(1:n2) = Solution2(1:n2) + Work2(1:n2)
      END DO

      IF(ListGetLogical(Solver % Values,'MG Compatible Relax Merit Only',GotIt)) STOP

!
!      Compute x = x + Qz:
!      -------------------
      R1 => Residual (1:n)
      R2 => Solution2(1:n2)
      
      CALL CRS_ProjectVector( ProjQT, R2, R1, Trans = .TRUE. )

      Solution(1:n) = Solution(1:n) + Residual(1:n)
!
!      Post smoothing:
!      ---------------
      Rounds = ListGetInteger( Solver % Values, &
          'MG Post Smoothing Iterations', GotIt )
      IF(.NOT. GotIt) Rounds = 1

      RNorm = Smooth( Matrix1, Solution, ForceVector, Residual, IterMethod, Rounds)
!------------------------------------------------------------------------------
    END FUNCTION MGSweep
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
    FUNCTION Smooth( A, x, b, r, IterMethod, Rounds) RESULT(RNorm)
!------------------------------------------------------------------------------
      TYPE(Matrix_t), POINTER :: A
      INTEGER :: Rounds
      CHARACTER(LEN=*) :: IterMethod
      REAL(KIND=dp), TARGET :: x(:),b(:),r(:),RNorm
!------------------------------------------------------------------------------
      TYPE(Matrix_t), POINTER :: M
      INTEGER :: n
      REAL(KIND=dp), POINTER :: Mx(:),Mb(:),Mr(:)
      LOGICAL :: CRSmoother
!------------------------------------------------------------------------------

      IF ( .NOT. Parallel ) THEN
        M  => A
        Mx => x
        Mb => b
        Mr => r
      ELSE
        CALL ParallelUpdateSolve( A,x,r )
        M => ParallelMatrix( A, Mx, Mb, Mr )
      END IF
      
      n = M % NumberOfRows
      
      SELECT CASE( IterMethod )
        CASE( 'cg' )
        CALL CG( n, A, M, Mx, Mb, Mr, Rounds )

        CASE( 'ccg' )
        CALL CCG( n, A, M, Mx, Mb, Mr, Rounds )

        CASE( 'bicgstab' )
        CALL BiCG( n, A, M, Mx, Mb, Mr, Rounds )
        
        CASE( 'gs' )                         
        CALL GS( n, A, M, Mx, Mb, Mr, Rounds )

        CASE( 'sor', 'sgs' )                                     
        CALL SGS( n, A, M, Mx, Mb, Mr, Rounds)

        CASE( 'psgs' )                                     
        CALL PostSGS( n, A, M, Mx, Mb, Mr, CF, Rounds)

        CASE( 'csgs' )                                     
        DO i=1,n/2
          IF(CF(2*i-1) > 0 .AND. CF(2*i) <= 0) Print *,'****** c1:',CF(2*i-1),CF(2*i)
          IF(CF(2*i-1) <= 0 .AND. CF(2*i) > 0) Print *,'****** c2:',CF(2*i-1),CF(2*i)
        END DO
        CALL CSGS( n, A, M, Mx, Mb, Mr, Rounds)


        CASE( 'cjacobi' )                                     
        CALL Jacobi( n, A, M, Mx, Mb, Mr, Rounds )


      CASE DEFAULT
        CALL Jacobi( n, A, M, Mx, Mb, Mr, Rounds )
      END SELECT
      
      CALL MGmv( A, x, r, .TRUE. )
      r = b - r
      IF ( Parallel ) Mr = Mb - Mr
      
      RNorm = MGnorm( n, Mr ) 
!------------------------------------------------------------------------------
    END FUNCTION Smooth
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    SUBROUTINE PostSGS( n, A, M, x, b, r, f, Rounds )
!------------------------------------------------------------------------------
       TYPE(Matrix_t), POINTER :: A, M
       INTEGER :: Rounds
       INTEGER, POINTER :: f(:)
       REAL(KIND=dp) :: x(:),b(:),r(:)
       INTEGER :: i,j,k,n
       REAL(KIND=dp) :: s
       INTEGER, POINTER :: Cols(:),Rows(:)
       REAL(KIND=dp), POINTER :: Values(:)

       n = A % NumberOfRows
       Rows   => A % Rows
       Cols   => A % Cols
       Values => A % Values
       
       DO k=1,Rounds
         
         DO i=1,n
           IF(f(i) /= 0) CYCLE
           s = 0.0d0
           DO j=Rows(i),Rows(i+1)-1
             s = s + x(Cols(j)) * Values(j)
           END DO
           r(i) = (b(i)-s) / M % Values(M % Diag(i))
           x(i) = x(i) + r(i)
         END DO
         DO i=1,n
           IF(f(i) == 0) CYCLE
           s = 0.0d0
           DO j=Rows(i),Rows(i+1)-1
             s = s + x(Cols(j)) * Values(j)
           END DO
           r(i) = (b(i)-s) / M % Values(M % Diag(i))
           x(i) = x(i) + r(i)
         END DO

         DO i=n,1,-1
           IF(f(i) /= 0) CYCLE
           s = 0.0d0
           DO j=Rows(i),Rows(i+1)-1
             s = s + x(Cols(j)) * Values(j)
           END DO
           r(i) = (b(i)-s) / M % Values(M % Diag(i))
           x(i) = x(i) + r(i)
         END DO         
         DO i=n,1,-1
           IF(f(i) == 0) CYCLE
           s = 0.0d0
           DO j=Rows(i),Rows(i+1)-1
             s = s + x(Cols(j)) * Values(j)
           END DO
           r(i) = (b(i)-s) / M % Values(M % Diag(i))
           x(i) = x(i) + r(i)
         END DO         

       END DO
     END SUBROUTINE PostSGS
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
    SUBROUTINE CJacobi( n, A, M, rx, rb, rr, Rounds )
!------------------------------------------------------------------------------
       TYPE(Matrix_t), POINTER :: A, M
       INTEGER :: n,Rounds
       REAL(KIND=dp) :: rx(:),rb(:),rr(:)
!------------------------------------------------------------------------------
       COMPLEX(KIND=dp) :: x(n/2),b(n/2),r(n/2)
       INTEGER :: i,j,diag
!------------------------------------------------------------------------------

       DO i=1,n/2
         r(i) = DCMPLX( rr(2*i-1), rr(2*i) )
         x(i) = DCMPLX( rx(2*i-1), rx(2*i) )
         b(i) = DCMPLX( rb(2*i-1), rb(2*i) )
       END DO

       DO j=1,Rounds
          CALL MGCmv( A, x, r )
          r(1:n/2) = b(1:n/2) - r(1:n/2)

          DO i=1,n/2
            diag = M % diag(2*i-1)
            r(i) = r(i) / DCMPLX( M % Values(diag), M % Values(diag+1))
            x(i) = x(i) + r(i)
          END DO
       END DO

       DO i=1,n/2
         rr(2*i-1) =  REAL( r(i) )
         rr(2*i-0) =  AIMAG( r(i) )
         rx(2*i-1) =  REAL( x(i) )
         rx(2*i-0) =  AIMAG( x(i) )
         rb(2*i-1) =  REAL( b(i) )
         rb(2*i-0) =  AIMAG( b(i) )
       END DO

!------------------------------------------------------------------------------
     END SUBROUTINE CJacobi
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
    SUBROUTINE GS( n, A, M, x, b, r, Rounds )
!------------------------------------------------------------------------------
       TYPE(Matrix_t), POINTER :: A, M
       INTEGER :: Rounds
       REAL(KIND=dp) :: x(:),b(:),r(:)
!------------------------------------------------------------------------------
       INTEGER :: i,j,k,n
       REAL(KIND=dp) :: s
       INTEGER, POINTER :: Cols(:),Rows(:)
       REAL(KIND=dp), POINTER :: Values(:)
!------------------------------------------------------------------------------
     
       n = A % NumberOfRows
       Rows   => A % Rows
       Cols   => A % Cols
       Values => A % Values
       
       DO k=1,Rounds

         DO i=1,n
           s = 0.0d0
           DO j=Rows(i),Rows(i+1)-1
             s = s + x(Cols(j)) * Values(j)
           END DO

           r(i) = (b(i)-s) / M % Values(M % Diag(i))
           x(i) = x(i) + r(i)
         END DO
       END DO
!------------------------------------------------------------------------------
     END SUBROUTINE GS
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
     SUBROUTINE SGS( n, A, M, x, b, r, Rounds )
!------------------------------------------------------------------------------
       TYPE(Matrix_t), POINTER :: A, M
       INTEGER :: Rounds
       REAL(KIND=dp) :: x(:),b(:),r(:)
       INTEGER :: i,j,k,n
       REAL(KIND=dp) :: s
       INTEGER, POINTER :: Cols(:),Rows(:)
       REAL(KIND=dp), POINTER :: Values(:)

       n = A % NumberOfRows
       Rows   => A % Rows
       Cols   => A % Cols
       Values => A % Values
       
       DO k=1,Rounds
         DO i=1,n
           s = 0.0d0
           DO j=Rows(i),Rows(i+1)-1
             s = s + x(Cols(j)) * Values(j)
           END DO
           r(i) = (b(i)-s) / M % Values(M % Diag(i))
           x(i) = x(i) + r(i)
         END DO

         DO i=n,1,-1
           s = 0.0d0
           DO j=Rows(i),Rows(i+1)-1
             s = s + x(Cols(j)) * Values(j)
           END DO
           r(i) = (b(i)-s) / M % Values(M % Diag(i))
           x(i) = x(i) + r(i)
         END DO         
       END DO
     END SUBROUTINE SGS
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
     SUBROUTINE CSGS( n, A, M, rx, rb, rr, Rounds )
!------------------------------------------------------------------------------
       TYPE(Matrix_t), POINTER :: A, M
       INTEGER :: Rounds
       REAL(KIND=dp) :: rx(:),rb(:),rr(:)
       INTEGER :: i,j,k,n,l
       INTEGER, POINTER :: Cols(:),Rows(:)
       REAL(KIND=dp), POINTER :: Values(:)
       COMPLEX(KIND=dp) :: r(n/2),b(n/2),x(n/2),s
       
       DO i=1,n/2
         r(i) = DCMPLX( rr(2*i-1), rr(2*i) )
         x(i) = DCMPLX( rx(2*i-1), rx(2*i) )
         b(i) = DCMPLX( rb(2*i-1), rb(2*i) )
       END DO
       
       Rows   => A % Rows
       Cols   => A % Cols
       Values => A % Values

       l = ListGetInteger(Solver % Values,'MG Info Node',GotIt)

       DO k=1,Rounds
         DO i=1,n/2
           s = 0.0d0
           
           DO j=Rows(2*i-1),Rows(2*i)-1,2             
             s = s + x((Cols(j)+1)/2) * DCMPLX( Values(j), -Values(j+1))
             IF(i==l) print *,'ij',i,j,DCMPLX( Values(j), -Values(j+1))
           END DO

           j = A % Diag(2*i-1)
           r(i) = (b(i)-s) / DCMPLX( Values(j), -Values(j+1) )
           x(i) = x(i) + r(i)
           IF(i==l) PRINT *,'ii',i,s,DCMPLX( Values(j), -Values(j+1))
         END DO
         
         DO i=n/2,1,-1
           s = 0.0d0
           
           DO j=Rows(2*i-1),Rows(2*i)-1,2             
             s = s + x((Cols(j)+1)/2) * DCMPLX( Values(j), -Values(j+1))
           END DO

           j = A % Diag(2*i-1)
           r(i) = (b(i)-s) / DCMPLX( Values(j), -Values(j+1) )
           x(i) = x(i) + r(i)
         END DO
         
       END DO
       
       DO i=1,n/2
         rr(2*i-1) =  REAL( r(i) )
         rr(2*i-0) =  AIMAG( r(i) )
         rx(2*i-1) =  REAL( x(i) )
         rx(2*i-0) =  AIMAG( x(i) )
         rb(2*i-1) =  REAL( b(i) )
         rb(2*i-0) =  AIMAG( b(i) )
       END DO

     END SUBROUTINE CSGS
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
    SUBROUTINE CG( n, A, M, x, b, r, Rounds )
!------------------------------------------------------------------------------
       TYPE(Matrix_t), POINTER :: A,M
       INTEGER :: Rounds
       REAL(KIND=dp) :: x(:),b(:),r(:)
       REAL(KIND=dp) :: alpha,rho,oldrho
!------------------------------------------------------------------------------
       INTEGER :: i,n
!------------------------------------------------------------------------------
       CALL MGmv( A, x, r )
       r(1:n) = b(1:n) - r(1:n)

       DO i=1,Rounds
          Z(1:n) = r(1:n)
          CALL CRS_LUSolve( n, M, Z )
          rho = MGdot( n, r, Z )

          IF ( i == 1 ) THEN
             P(1:n) = Z(1:n)
          ELSE
             P(1:n) = Z(1:n) + rho * P(1:n) / oldrho
          END IF

          CALL MGmv( A, P, Q )
          alpha  = rho / MGdot( n, P, Q )
          oldrho = rho

          x(1:n) = x(1:n) + alpha * P(1:n)
          r(1:n) = r(1:n) - alpha * Q(1:n)
       END DO
!------------------------------------------------------------------------------
    END SUBROUTINE CG
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    SUBROUTINE CCG( n, A, M, rx, rb, rr, Rounds )
!------------------------------------------------------------------------------
       INTEGER :: i,n, Rounds
       TYPE(Matrix_t), POINTER :: A,M
       REAL(KIND=dp) :: rx(:),rb(:),rr(:)
       COMPLEX(KIND=dp) :: alpha,rho,oldrho
       COMPLEX(KIND=dp) :: r(n/2),b(n/2),x(n/2)
       COMPLEX(KIND=dp) :: Z(n), P(n), Q(n)
!------------------------------------------------------------------------------
       DO i=1,n/2
         r(i) = DCMPLX( rr(2*i-1), rr(2*i) )
         x(i) = DCMPLX( rx(2*i-1), rx(2*i) )
         b(i) = DCMPLX( rb(2*i-1), rb(2*i) )
       END DO

       CALL MGCmv( A, x, r )
       r(1:n/2) = b(1:n/2) - r(1:n/2)

       DO i=1,Rounds
          Z(1:n/2) = r(1:n/2)
          CALL CRS_ComplexLUSolve( n, M, Z )
          rho = MGCdot( n/2, r, Z )

          IF ( i == 1 ) THEN
             P(1:n/2) = Z(1:n/2)
          ELSE
             P(1:n/2) = Z(1:n/2) + rho * P(1:n/2) / oldrho
          END IF

          CALL MGCmv( A, P, Q )
          alpha  = rho / MGCdot( n/2, P, Q )
          oldrho = rho

          x(1:n/2) = x(1:n/2) + alpha * P(1:n/2)
          r(1:n/2) = r(1:n/2) - alpha * Q(1:n/2)
       END DO

       DO i=1,n/2
         rr(2*i-1) =  REAL( r(i) )
         rr(2*i-0) =  AIMAG( r(i) )
         rx(2*i-1) =  REAL( x(i) )
         rx(2*i-0) =  AIMAG( x(i) )
         rb(2*i-1) =  REAL( b(i) )
         rb(2*i-0) =  AIMAG( b(i) )
       END DO
!------------------------------------------------------------------------------
    END SUBROUTINE CCG
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    SUBROUTINE BiCG( n, A, M, x, b, r, Rounds )
!------------------------------------------------------------------------------
       TYPE(Matrix_t), POINTER :: A,M
       INTEGER :: Rounds
       REAL(KIND=dp) :: x(:),b(:),r(:)
!------------------------------------------------------------------------------
       INTEGER :: i,n
       REAL(KIND=dp) :: alpha,beta,omega,rho,oldrho
!------------------------------------------------------------------------------
       CALL MGmv( A, x, r )
       r(1:n) = b(1:n) - r(1:n)

       Ri(1:n) = r(1:n)
       P(1:n) = 0
       V(1:n) = 0
       omega  = 1
       alpha  = 0
       oldrho = 1

       DO i=1,Rounds
          rho = MGdot( n, r, Ri )

          beta = alpha * rho / ( oldrho * omega )
          P(1:n) = r(1:n) + beta * (P(1:n) - omega*V(1:n))

          V(1:n) = P(1:n)
          CALL CRS_LUSolve( n, M, V )
          T1(1:n) = V(1:n)
          CALL MGmv( A, T1, V )

          alpha = rho / MGdot( n, Ri, V )

          S(1:n) = r(1:n) - alpha * V(1:n)

          T(1:n) = S(1:n)
          CALL CRS_LUSolve( n, M, T )
          T2(1:n) = T(1:n)
          CALL MGmv( A, T2, T )
          omega = MGdot( n,T,S ) / MGdot( n,T,T )

          oldrho = rho
          r(1:n) = S(1:n) - omega*T(1:n)
          x(1:n) = x(1:n) + alpha*T1(1:n) + omega*T2(1:n)
       END DO
!------------------------------------------------------------------------------
    END SUBROUTINE BiCG
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
    FUNCTION MGnorm( n, x ) RESULT(s)
!------------------------------------------------------------------------------
       INTEGER :: n
       REAL(KIND=dp) :: s,x(:)
!------------------------------------------------------------------------------
       IF ( .NOT. Parallel ) THEN
          s = SQRT( DOT_PRODUCT( x(1:n), x(1:n) ) )
       ELSE
          s = ParallelNorm( n, x )
       END IF
!------------------------------------------------------------------------------
    END FUNCTION MGnorm
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    FUNCTION MGdot( n, x, y ) RESULT(s)
!------------------------------------------------------------------------------
       INTEGER :: n
       REAL(KIND=dp) :: s,x(:),y(:)
!------------------------------------------------------------------------------
       IF ( .NOT. Parallel ) THEN
          s = DOT_PRODUCT( x(1:n), y(1:n) )
       ELSE
          s = ParallelDot( n, x, y )
       END IF
!------------------------------------------------------------------------------
    END FUNCTION MGdot
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    SUBROUTINE MGmv( A, x, b, Update )
!------------------------------------------------------------------------------
       REAL(KIND=dp) :: x(:), b(:)
       LOGICAL, OPTIONAL :: Update
       TYPE(Matrix_t), POINTER :: A
!------------------------------------------------------------------------------
       IF ( .NOT. Parallel ) THEN
         CALL CRS_MatrixVectorMultiply( A, x, b )
       ELSE
         IF ( PRESENT( Update ) ) THEN
           CALL ParallelMatrixVector( A,x,b,Update )
         ELSE
           CALL ParallelMatrixVector( A,x,b )
         END IF
       END IF
!------------------------------------------------------------------------------
    END SUBROUTINE MGmv
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    FUNCTION MGCnorm( n, x ) RESULT(s)
!------------------------------------------------------------------------------
       INTEGER :: n
       COMPLEX(KIND=dp) :: s,x(:)
!------------------------------------------------------------------------------
       s = SQRT( DOT_PRODUCT( x(1:n), x(1:n) ) )
!------------------------------------------------------------------------------
    END FUNCTION MGCnorm
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    FUNCTION MGCdot( n, x, y ) RESULT(s)
!------------------------------------------------------------------------------
       INTEGER :: n
       COMPLEX(KIND=dp) :: s,x(:),y(:)
!------------------------------------------------------------------------------
       s = DOT_PRODUCT( x(1:n), y(1:n) )
!------------------------------------------------------------------------------
    END FUNCTION MGCdot
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    SUBROUTINE MGCmv( A, x, b, Update )
!------------------------------------------------------------------------------
       COMPLEX(KIND=dp) :: x(:), b(:)
       LOGICAL, OPTIONAL :: Update
       TYPE(Matrix_t), POINTER :: A
!------------------------------------------------------------------------------
       CALL CRS_ComplexMatrixVectorMultiply( A, x, b )
!------------------------------------------------------------------------------
     END SUBROUTINE MGCmv
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
! Create a coarse mesh given the fine mesh and the stiffness matrix. 
! The coarse nodes may be selected in a number of ways and after the 
! selection a new mesh is made of them. This mesh is the used to create
! a projection between the coarse and fine degrees of freedom. 
!------------------------------------------------------------------------------

  SUBROUTINE ChooseCoarseNodes(Amat, Solver, Projector, Components, CF, InvCF) 
    
    TYPE(Matrix_t), POINTER  :: Amat
    TYPE(solver_t), TARGET :: Solver
    TYPE(Matrix_t), POINTER :: Projector
    INTEGER :: Components
    INTEGER, POINTER :: CF(:)
    INTEGER, POINTER, OPTIONAL :: InvCF(:)

    INTEGER :: nods, cnods, Rounds, RatioClasses(101), elimnods, Component1, NoComponents, cj
    INTEGER, POINTER :: CandList(:)
    LOGICAL :: CompMat
    LOGICAL, POINTER :: Bonds(:)
    REAL(KIND=dp), POINTER :: Ones(:), Zeros(:)
    REAL(KIND=dp) :: Limit, MaxRatio, Ratio
    INTEGER, POINTER :: Cols(:),Rows(:)

    NoComponents = Components
    Component1 = 1
    IF(Components > 1) THEN
      Component1 = ListGetInteger(Solver % Values,'MG Determining Component',&
          GotIt,minv=1,maxv=Components)
      IF(.NOT. GotIt) Component1 = 1
    END IF

    IF(Amat % COMPLEX) THEN
      CompMat = ListGetLogical(Solver % Values,'MG Complex Matrix',GotIt)
      IF(.NOT. GotIt) THEN
        CompMat = .TRUE.
        CALL Info('ChooseCoarseNodes','Assuming COMPLEX valued matrix')
      END IF
    END IF

    IF(CompMat) THEN
      NoComponents = 2
    END IF

    Rows   => Amat % Rows
    Cols   => Amat % Cols
    nods = Amat % NumberOfRows
    ALLOCATE( Bonds(SIZE(Amat % Cols)), CandList(nods), CF(nods) )


    ! Make the candidate and strong bond list for determining the coarse nodes    
    tt2 = CPUTime()
    IF(NoComponents <= 1) THEN
      CandList = 1
    ELSE    
      DO i=1,NoComponents
        IF(i==Component1) THEN
          CandList(i:nods:NoComponents) = 1
        ELSE
          CandList(i:nods:NoComponents) = 0          
        END IF
      END DO
    END IF

    IF(CompMat) THEN
      CALL AMGBondsComplex(Amat, Bonds, CandList)
    ELSE
      CALL AMGBonds(Amat, Bonds, CandList)      
    END IF

    WRITE( Message,'(A,ES15.4)') 'MG strong bond definition time: ', CPUTime() - tt2
    CALL Info( 'ChooseCoarseNodes', Message, Level=5 )

    tt2 = CPUTime()
    CF = 0
    CALL AMGCoarse(Amat, CandList, Bonds, CF, CompMat)
    
    IF(.NOT. CompMat) THEN
      IF( ListGetLogical(Solver % Values,'MG Positive Connection Eliminate',GotIt)) THEN
        CALL AMGPositiveBonds(Amat, Bonds, CandList, CF)
      END IF
    END IF

    ! Make the coarse nodes of each variable to be the same
    IF(.NOT. IdenticalProjs .AND. NoComponents > 1) THEN
      DO i=1,NoComponents
        IF(i/=Component1) THEN
          CF(i:nods:NoComponents) = CF(Component1:nods:NoComponents)
        END IF
      END DO
    END IF    

    WRITE( Message, '(A,ES15.4)' ) 'MG coarse nodes selection time: ', CPUTime() - tt2
    CALL Info( 'ChooseCoarseNodes', Message, Level=5 )

    cnods = 0
    DO i=1,nods
      IF(CF(i) < 0) THEN
        CF(i) = 0
      ELSE IF(CF(i) > 0) THEN
        cnods = cnods + 1
        CF(i) = cnods
      END IF
    END DO
    

    WRITE(Message,'(A,I)') 'Coarse mesh nodes ',cnods
    CALL Info('ChooseCoarseNodes',Message)

    WRITE(Message,'(A,F5.1,A)') 'Coarse node fraction',(100.0*cnods)/nods,' %'
    CALL Info('ChooseCoarseNodes',Message)


    IF( ListGetLogical(Solver % Values,'MG Compatible Relax Merit',GotIt) ) THEN
      Rounds = ListGetInteger(Solver % Values,'MG Compatible Relax Rounds',GotIt)
      IF(.NOT. GotIt) Rounds = 3

      ALLOCATE(Ones(nods),Zeros(nods))
      
100   k = 0
      DO i=1,nods
        IF(CF(i) <= 0) THEN
          Ones(i) = 1.0
          k = k+1
        ELSE
          Ones(i) = 0.0
        END IF
      END DO
      Zeros = 0.0
      
      IterMethod = ListGetString( Solver % Values, 'MG Smoother', Found )
      
      IF ( .NOT. Found ) THEN
        IterMethod = ListGetString( Solver % Values, &
            'Linear System Iterative Method', Found )
      END IF
      IF ( .NOT. Found ) IterMethod = 'jacobi'
      
      SELECT CASE( IterMethod )
        CASE( 'gs' )                         
        CALL CR_GS( Amat, Ones, Zeros, CF, Rounds )
        
        CASE( 'sor','sgs','psgs')                                     
        CALL CR_SGS( Amat, Ones, Zeros, CF, Rounds)

        CASE( 'csgs')                                     
        CALL CR_CSGS( nods, Amat, Ones, Zeros, CF, Rounds)       

      CASE DEFAULT
        CALL CR_Jacobi( Amat, Ones, Zeros, CF, Rounds )
      END SELECT
      
      MaxRatio = 0.0d0
      RatioClasses = 0
      DO i=1,nods
        IF(CF(i) <= 0) THEN
          Ratio = ABS(Zeros(i))
          j = INT(10*Ratio)+1
          IF(j > 0 .AND. j <= 10) THEN
            RatioClasses(j) = RatioClasses(j) + 1
          ELSE IF(j > 0) THEN
            RatioClasses(11) = RatioClasses(11) + 1            
          ELSE IF(j < 0) THEN
            RatioClasses(12) = RatioClasses(12) + 1                        
          END IF
          MaxRatio = MAX(Ratio, MaxRatio) 
        END IF
      END DO

         
      WRITE( Message, '(A)' ) 'Compatible relaxation classes (interval, no and %)'
      CALL Info('ChooseCoarseNodes',Message)

      DO i=1,13
        IF(RatioClasses(i) > 0) THEN
          IF(i==11) THEN
            WRITE( Message, '(F3.1,A,A,I9,F9.3)' ) 1.0,' - ','...',RatioClasses(i),100.0*RatioClasses(i)/k
          ELSE IF(i==12) THEN
            WRITE( Message, '(A,A,F3.1,I9,F9.3)' ) '...',' - ',0.0,RatioClasses(i),100.0*RatioClasses(i)/k
          ELSE
            WRITE( Message, '(F3.1,A,F3.1,I9,F9.3)' ) 0.1*(i-1),' - ',0.1*i,RatioClasses(i),100.0*RatioClasses(i)/k
          END IF
          CALL Info('ChooseCoarseNodes',Message)      
        END IF
      END DO
 
      WRITE( Message, '(A,ES15.5)' ) 'Compatible relaxation merit',MaxRatio
      CALL Info('ChooseCoarseNodes',Message)

      k = 0
      Limit = ListGetConstReal(Solver % Values,'MG Compatible Relax Limit',GotIt)
      IF(GotIt) THEN
        DO i=1,nods         
          IF(CandList(i) == 0) CYCLE
          Ratio = ABS(Zeros(i))
          IF(Ratio <= Limit) CYCLE 
          
          IF(CF(i) > 0) THEN
            CALL WARN('ChooseCoarseNodes','Coarse nodes should relax well!?')
          ELSE
            k = k + 1
            CF(i) = -1
          END IF
        END DO
        
        k = 0
        DO i=1,nods         
          IF(CandList(i) == 0) CYCLE
          IF(CF(i) >= 0) CYCLE

          CF(i) = 1
          k = k + 1

          IF(CompMat) CF(i+1) = CF(i) 

          DO j=Rows(i),Rows(i+1)-1
            cj = Cols(j)

            IF(cj == i .OR. CandList(i) == 0) CYCLE
            IF(Bonds(j) .AND. CF(cj) < 0) THEN
              CF(cj) = 0        
              IF(CompMat) CF(cj+1) = CF(cj)
            END IF
          END DO
        END DO
      END IF

      IF(k > 0) THEN
        WRITE(Message,'(A,I)') 'Number of added nodes using CR ',k
        CALL Info('ChooseCoarseNodes',Message)
        
        GOTO 100
      END IF

      DEALLOCATE(Ones, Zeros)

      cnods = 0
      DO i=1,nods
        IF(CF(i) < 0) THEN
          CF(i) = 0
        ELSE IF(CF(i) > 0) THEN
          cnods = cnods + 1
          CF(i) = cnods
        END IF
      END DO

      WRITE(Message,'(A,I)') 'Coarse mesh nodes after CR ',cnods
      CALL Info('ChooseCoarseNodes',Message)
      
      WRITE(Message,'(A,F5.1,A)') 'Coarse node fraction after CR ',(100.0*cnods)/nods,' %'
      CALL Info('ChooseCoarseNodes',Message)      

    END IF

    DEALLOCATE(Bonds, CandList)


    tt2 = CPUTime()

    IF(CompMat) THEN
      Projector => ComplexInterpolateF2C( Amat, CF )      
    ELSE IF(IdenticalProjs) THEN
      Projector => InterpolateF2C( Amat, CF, NoComponents)
    ELSE
      Projector => InterpolateF2C( Amat, CF, 1)      
    END IF

    WRITE( Message, '(A,ES15.4)' ) 'MG projection matrix creation time: ', CPUTime() - tt2
    CALL Info( 'ChooseCoarseNodes', Message, Level=5 )

    IF(PRESENT(InvCF)) THEN
      ALLOCATE(InvCF(cnods))
      DO i=1,nods
        IF(CF(i) > 0) InvCF(CF(i)) = i
      END DO
    END IF


  END SUBROUTINE ChooseCoarseNodes


!------------------------------------------------------------------------------
! Create the initial list for measure of importance and
! make the inverse table for important connections
!------------------------------------------------------------------------------

  SUBROUTINE AMGBonds(Amat, Bonds, Cands)
    
    LOGICAL, POINTER :: Bonds(:)
    TYPE(Matrix_t), POINTER  :: Amat
    INTEGER, POINTER :: Cands(:)
    INTEGER :: Components, Component1    

    REAL(KIND=dp) :: NegLim, PosLim
    INTEGER :: nods, cnods, diagsign, maxconn, posnew, negnew, MaxConns, MinConns
    INTEGER :: i,j,k,cj,ci,ind, elimnods,posbonds,negbonds,measind
    INTEGER, POINTER :: Cols(:),Rows(:)
    LOGICAL :: debug, ElimDir, minmaxset, AllowPosLim
    REAL(KIND=dp), POINTER :: Values(:), measures(:)
    REAL(KIND=dp) :: maxbond, minbond, dirlim, meas, measlim

    CALL Info('AMGBonds','Making a list of strong matrix connections')
    debug = .FALSE.

    NegLim = ListGetConstReal(Solver % Values,'MG Strong Connection Limit',GotIt)
    IF(.NOT. GotIt) NegLim = 0.25

    ! Negative connections are more useful for the interpolation, but also 
    ! positive strong connection may be taken into account
    AllowPosLim = ListGetLogical(Solver % Values,'MG Positive Connection Allow',GotIt)
    PosLim = ListGetConstReal(Solver % Values,'MG Positive Connection Limit',GotIt)
    IF(.NOT. GotIt) PosLim = 1.0

    ! In the first time deselect the Dirichlet nodes from the candidate list
    ! their value is determined at the finest level and need not to be recomputed
    ElimDir = EliminateDir
    DirLim = ListGetConstReal(Solver % Values,'MG Eliminate Dirichlet Limit',GotIt)
    IF(.NOT. GotIt) DirLim = 1.0d-8      

    nods = Amat % NumberOfRows
    Rows   => Amat % Rows
    Cols   => Amat % Cols
    Values => Amat % Values

    maxconn = 0
    DO ind=1,nods
      maxconn = MAX(maxconn,Rows(ind+1)-Rows(ind))
    END DO
    MaxConns = ListGetInteger(Solver % Values,'MG Strong Connection Maximum',GotIt)
    MinConns = ListGetInteger(Solver % Values,'MG Strong Connection Minimum',GotIt)


    ALLOCATE(measures(maxconn))

    Bonds = .FALSE.
    posbonds = 0
    negbonds = 0

    DO ind=1,nods

      IF(Cands(ind) == 0) CYCLE

      ! Matrix entries will be treated differently depending if they have the same or
      ! different sign than the diagonal element
      diagsign = 1
      IF(Values (Amat % Diag(ind)) < 0.0) diagsign = -1

      minmaxset = .FALSE.
      DO j=Rows(ind),Rows(ind+1)-1
        cj = Cols(j)
        IF(Cands(cj) /= 0 .AND. cj /= ind ) THEN
          IF(minmaxset) THEN
            maxbond = MAX(maxbond, Values(j))
            minbond = MIN(minbond, Values(j))
          ELSE
            maxbond = Values(j)
            minbond = Values(j)
            minmaxset = .TRUE.
          END IF
        END IF
      END DO

      IF(.NOT. minmaxset) THEN
        maxbond = 0.0
      ELSE IF(AllowPosLim) THEN
        maxbond = MAX(ABS(maxbond),ABS(minbond))
      ELSE
        IF(minbond * diagsign < 0.0) maxbond = minbond
        maxbond = ABS(maxbond)
      END IF
   
      IF( maxbond < DirLim * ABS(Values (Amat % Diag(ind)) ) ) THEN
        IF(ElimDir) THEN
          Cands(ind) = 0
          elimnods = elimnods + 1
        END IF
        CYCLE
      END IF

      IF(.NOT. minmaxset) CYCLE

      ! Make the direct table of important bonds
      posnew = 0
      negnew = 0

      DO j=Rows(ind),Rows(ind+1)-1
        cj = Cols(j)
        IF(Cands(cj) /= 0 .AND. cj /= ind ) THEN
          IF(diagsign * Values(j) <= 0.0) THEN
            meas = ABS(Values(j)) / (NegLim * maxbond)
            measures(j-Rows(ind)+1) = -meas
            IF( meas > 1.0) THEN
              Bonds(j) = .TRUE.
              negnew = negnew + 1
            END IF
          ELSE IF(AllowPosLim) THEN
            meas = ABS(Values(j)) / (PosLim * maxbond)
            measures(j-Rows(ind)+1) = meas
            IF( meas > 1.0) THEN
              Bonds(j) = .TRUE.
              posnew = posnew + 1
            END IF
          ELSE
            measures(j-Rows(ind)+1) = 0.0d0
          END IF
        END IF
      END DO


      IF(MaxConns > 0) THEN
        DO WHILE(posnew + negnew > MaxConns)
          
          ! Find the weakest used connection
          measlim = HUGE(measlim)
          DO j=Rows(ind),Rows(ind+1)-1
            IF(.NOT. Bonds(j)) CYCLE
            
            meas = ABS(measures(j-Rows(ind)+1))
            IF(meas < measlim) THEN
              measlim = meas
              measind = j
            END IF
          END DO

          IF(measures(measind-Rows(ind)+1) < 0.0) THEN
            negnew = negnew - 1
          ELSE
            posnew = posnew - 1
          END IF
          Bonds(measind) = .FALSE.          
        END DO
      END IF


      IF(MinConns > 0) THEN
        DO WHILE(posnew + negnew < MinConns)
          
          ! Find the strongest unused connection
          measlim = 0.0
          measind = 0
          DO j=Rows(ind),Rows(ind+1)-1
            IF(Bonds(j)) CYCLE
            
            cj = Cols(j)
            IF(Cands(cj) == 0 .OR. cj == ind ) CYCLE
 
            meas = ABS(measures(j-Rows(ind)+1))
            IF(meas > measlim) THEN
              measlim = meas
              measind = j
            END IF
          END DO

          ! Check if there exist possible new connections
          IF(measind == 0 .OR. measlim > 1.0d-50) EXIT

          IF(measures(measind-Rows(ind)+1) < 0.0) THEN
            negnew = negnew + 1
          ELSE
            posnew = posnew + 1
          END IF
          Bonds(measind) = .TRUE.          
        END DO
      END IF

      posbonds = posbonds + posnew
      negbonds = negbonds + negnew

    END DO


    WRITE(Message,'(A,I)') 'Number of eliminated nodes',elimnods
    CALL Info('AMGBonds',Message)
    j = posbonds + negbonds
    WRITE(Message,'(A,I9,A,I9,A)') 'Number of strong connections',j,' (',posbonds,' positive)'
    CALL Info('AMGBonds',Message)
    WRITE(Message,'(A,F8.3)') 'Average number of strong bonds for each dof',1.0*j/nods
    CALL Info('AMGBonds',Message)
    WRITE(Message,'(A,F8.3)') 'Fraction of strong bonds in sparse matrix',1.0*j/SIZE(Bonds)
    CALL Info('AMGBonds',Message)

  END SUBROUTINE AMGBonds


!------------------------------------------------------------------------------
! Create the initial list for measure of importance for a complex matrix.
!------------------------------------------------------------------------------

  SUBROUTINE AMGBondsComplex(Amat, Bonds, Cands)
    
    LOGICAL, POINTER :: Bonds(:)
    TYPE(Matrix_t), POINTER  :: Amat
    INTEGER, POINTER :: Cands(:)

    REAL(KIND=dp) :: NegLim
    INTEGER :: nods, cnods, anods, maxconn, negnew, MaxConns, MinConns
    INTEGER :: i,j,k,cj,ci,ind, elimnods, negbonds, measind,j2
    INTEGER, POINTER :: Cols(:),Rows(:)
    LOGICAL :: ElimDir
    REAL(KIND=dp), POINTER :: Values(:), measures(:)
    REAL(KIND=dp) :: maxbond, dirlim, meas, measlim

    CALL Info('AMGBondsComplex','Making a list of strong matrix connections')

    NegLim = ListGetConstReal(Solver % Values,'MG Strong Connection Limit',GotIt)
    IF(.NOT. GotIt) NegLim = 0.25

    ! In the first time deselect the Dirichlet nodes from the candidate list
    ! their value is determined at the finest level and need not to be recomputed
    ElimDir = EliminateDir
    DirLim = ListGetConstReal(Solver % Values,'MG Eliminate Dirichlet Limit',GotIt)
    IF(.NOT. GotIt) DirLim = 1.0d-8      

    nods = Amat % NumberOfRows
    Rows   => Amat % Rows
    Cols   => Amat % Cols
    Values => Amat % Values

    maxconn = 0
    DO ind=1,nods
      maxconn = MAX(maxconn,Rows(ind+1)-Rows(ind))
    END DO
    MaxConns = ListGetInteger(Solver % Values,'MG Strong Connection Maximum',GotIt)
    MinConns = ListGetInteger(Solver % Values,'MG Strong Connection Minimum',GotIt)


    ALLOCATE(measures(maxconn))

    Bonds = .FALSE.
    negbonds = 0

    DO ind=1,nods

      IF(Cands(ind) == 0) CYCLE

      maxbond = 0.0d0
      DO j=Rows(ind),Rows(ind+1)-1
        cj = Cols(j)
        IF(Cands(cj) == 0 .OR. cj == ind ) CYCLE
        
        j2 = j + Rows(ind+1) - Rows(ind)
        meas = SQRT( Values(j)**2.0 + Values(j2)**2.0 )
        maxbond = MAX(meas,maxbond)
      END DO
     
      meas = SQRT(Values (Amat % Diag(ind)) ** 2.0 + Values (Amat % Diag(ind+1)) ** 2.0 )

      IF( maxbond < DirLim * meas ) THEN
        IF(ElimDir) THEN
          Cands(ind) = 0
          elimnods = elimnods + 1
        END IF
        CYCLE
      END IF

      ! Make the direct table of important bonds
      negnew = 0

      DO j=Rows(ind),Rows(ind+1)-1
        cj = Cols(j)
        IF(Cands(cj) == 0 .OR. cj == ind ) CYCLE

        j2 = j + Rows(ind+1) - Rows(ind)
        meas = SQRT( Values(j)**2.0 + Values(j2)**2.0 ) / (NegLim * maxbond)
        measures(j-Rows(ind)+1) = meas
        IF(meas > 1.0) THEN
          Bonds(j) = .TRUE.
          negnew = negnew + 1
        END IF
      END DO


      IF(MaxConns > 0) THEN
        DO WHILE(negnew > MaxConns)
          
          ! Find the weakest used connection
          measlim = HUGE(measlim)
          DO j=Rows(ind),Rows(ind+1)-1
            IF(.NOT. Bonds(j)) CYCLE
            
            meas = measures(j-Rows(ind)+1)
            IF(meas < measlim) THEN
              measlim = meas
              measind = j
            END IF
          END DO

          negnew = negnew - 1
          Bonds(measind) = .FALSE.          
        END DO
      END IF


      IF(MinConns > 0) THEN
        DO WHILE(negnew < MinConns)
          
          ! Find the strongest unused connection
          measlim = 0.0
          measind = 0
          DO j=Rows(ind),Rows(ind+1)-1
            IF(Bonds(j)) CYCLE
            
            cj = Cols(j)
            IF(Cands(cj) == 0 .OR. cj == ind ) CYCLE
 
            meas = measures(j-Rows(ind)+1)
            IF(meas > measlim) THEN
              measlim = meas
              measind = j
            END IF
          END DO

          ! Check if there exist possible new connections
          IF(measind == 0 .OR. measlim > 1.0d-50) EXIT

          negnew = negnew + 1
          Bonds(measind) = .TRUE.          
        END DO
      END IF
      negbonds = negbonds + negnew
    END DO

    WRITE(Message,'(A,I)') 'Number of eliminated nodes',elimnods
    CALL Info('AMGBondsComplex',Message)
    j = negbonds
    WRITE(Message,'(A,I9)') 'Number of strong connections',j
    CALL Info('AMGBondsComplex',Message)
    WRITE(Message,'(A,F8.3)') 'Average number of strong bonds for each dof',2.0*j/nods
    CALL Info('AMGBondsComplex',Message)
    WRITE(Message,'(A,F8.3)') 'Fraction of strong bonds in sparse matrix',4.0*j/SIZE(Bonds)
    CALL Info('AMGBondsComplex',Message)

  END SUBROUTINE AMGBondsComplex



!------------------------------------------------------------------------------
! Add a posteriori some nodes to be coarse nodes which have 
! strong positive-positvive connections
!------------------------------------------------------------------------------

  SUBROUTINE AMGPositiveBonds(Amat, Bonds, Cands, CF)
    
    LOGICAL, POINTER :: Bonds(:)    
    TYPE(Matrix_t), POINTER  :: Amat
    INTEGER, POINTER :: Cands(:), CF(:)

    INTEGER :: i, j, k, cj, ci, ind, nods, posnods
    INTEGER, POINTER :: Cols(:),Rows(:)
    LOGICAL :: ElimDir, AllowPosLim
    REAL(KIND=dp) :: maxbond, minbond, minbond2, PosLim, DirLim, diagvalue
    REAL(KIND=dp), POINTER :: Values(:)

    CALL Info('AMGPositiveBonds','Adding some F-nodes with positive connections to C-nodes')

    ! Negative connections are more useful for the interpolation, but also 
    ! positive strong connection may be taken into account
    AllowPosLim = ListGetLogical(Solver % Values,'MG Positive Connection Allow',GotIt)
    PosLim = ListGetConstReal(Solver % Values,'MG Positive Connection Limit',GotIt)
    IF(.NOT. GotIt) PosLim = 0.5

    ! In the first time deselect the Dirichlet nodes from the candidate list
    ! their value is determined at the finest level and need not to be recomputed
    ElimDir = EliminateDir
    DirLim = ListGetConstReal(Solver % Values,'MG Eliminate Dirichlet Limit',GotIt)
    IF(.NOT. GotIt) DirLim = 1.0d-8      

    nods = Amat % NumberOfRows
    Rows   => Amat % Rows
    Cols   => Amat % Cols
    Values => Amat % Values

    posnods = 0

    DO ind=1,nods
      
      IF(Cands(ind) == 0 .OR. CF(ind) > 0) CYCLE

      ! Matrix entries will be treated differently depending if they have the same or
      ! different sign than the diagonal element

      diagvalue = Values (Amat % Diag(ind))
      minbond = 0.0
      minbond2 = 0.0
      maxbond = 0.0      

      DO j=Rows(ind),Rows(ind+1)-1
        cj = Cols(j)
        IF(Cands(cj) == 0) CYCLE
        IF(cj == ind) CYCLE

        maxbond = MAX(maxbond,ABS(Values(j)))
        IF(diagvalue * Values(j) > 0.0) THEN
          minbond = minbond + ABS(Values(j))
          IF(CF(cj) <= 0) minbond2 = MAX(minbond2,ABS(Values(j)))
        END IF
      END DO

      IF(maxbond < DirLim * ABS(diagvalue)) CYCLE
      IF(minbond2 < minbond) CYCLE 

      IF(minbond2 > PosLim * maxbond) THEN
        CF(ind) = 1
        posnods = posnods + 1
      END IF
        
    END DO

    WRITE(Message,'(A,I)') 'Number of added positive connection nodes',posnods
    CALL Info('AMGPositiveBonds',Message)

  END SUBROUTINE AMGPositiveBonds

!------------------------------------------------------------------------------
! Creates a coarse mesh using the given list of strong connections. 
! Only nodes assigned by the Cands vector may be included in the 
! coarse set. The subroutine returns the vector CF which is 
! nonzero for coarse nodes. The nodes are chosen using a heuristics which
! takes into account the strength of the coupling and consistancy of direction.
!
! CF includes the classification of the nodes
! coarse nodes > 0, undecided = 0, fine nodes < 0
!------------------------------------------------------------------------------

  SUBROUTINE AMGCoarse(Amat, Cands, Bonds, CF, CompMat)
    
    TYPE(Matrix_t), POINTER :: Amat
    LOGICAL :: Bonds(:)
    INTEGER, POINTER :: Cands(:), CF(:)
    LOGICAL :: CompMat

    INTEGER :: nods, cnods    
    INTEGER :: i,j,k,cj,ci,ind,maxi,maxi2,newstarts, loops, minneigh, maxneigh, &
        MaxCon, MaxConInd, RefCon, RefCon2, prevstart, cind, find, ind0, &
        CoarseningMode
    INTEGER, POINTER :: Con(:)
    LOGICAL :: debug
    INTEGER, POINTER :: Cols(:),Rows(:)
    REAL(KIND=dp), POINTER :: Values(:)
    
    nods = Amat % NumberOfRows
    Rows   => Amat % Rows
    Cols   => Amat % Cols
    Values => Amat % Values

    ! There are three possible coarsening modes
    ! 0) find a new start only in dire need
    ! 1) find a new start if the suggested start is worse than previous new start
    ! 2) find a new start if the suggested start is worse that theoretical best start
    CoarseningMode = ListGetInteger(Solver % Values,'MG Coarsening Mode',&
        GotIt,minv=0,maxv=2)

    debug = .FALSE.

    ALLOCATE(Con(nods))
    Con = 0
    newstarts = 0
    cnods = 0
    loops = 0
    cind = 0

    ! Make the tightly bonded neighbours of of C-nodes to have value -1
    DO ind = 1, nods
      IF(CF(ind) < 1) CYCLE
      cind = cind + 1
      CF(ind) = cind

      DO i=Rows(ind),Rows(ind+1)-1
        IF(.NOT. Bonds(i)) CYCLE
        ci = Cols(i)
        IF(Cands(ci) == 0) CYCLE
        IF(CF(ci) == 0) THEN
          find = find + 1
          CF(ci) = -find
        END IF
      END DO
    END DO

    ! Calculate the initial measure of of importance
    ! unvisited neighbour get 1 point, and a decided coarse node 2 points
    DO ind = 1, nods      
      IF(CF(ind) > 0) CYCLE
      
      DO i=Rows(ind),Rows(ind+1)-1
        IF(.NOT. Bonds(i)) CYCLE
        ci = Cols(i)
        IF(Cands(ci) == 0) CYCLE
        IF(CF(ci) == 0) THEN
          IF(CF(ind) == 0) Con(ci) = Con(ci) + 1
          IF(CF(ind) < 0)  Con(ci) = Con(ci) + 2
        END IF
      END DO
    END DO

    ! Find the point to start the coarse node selection from
    MaxCon = 1000 
    prevstart = 1

10  MaxConInd =  0
    RefCon = 0
    newstarts = newstarts + 1
    DO ind=prevstart, nods
      loops = loops + 1
      IF(Cands(ind) == 0) CYCLE
      IF(Con(ind) > RefCon) THEN
        RefCon = Con(ind)
        MaxConInd = ind
      END IF
      IF(RefCon >= MaxCon) EXIT
    END DO

    IF(RefCon < MaxCon .AND. prevstart > 1) THEN
      DO ind=1, prevstart-1        
        loops = loops + 1
        IF(Cands(ind) == 0) CYCLE
        IF(Con(ind) > RefCon) THEN
          RefCon = Con(ind)
          MaxConInd = ind
        END IF
        IF(RefCon >= MaxCon) EXIT
      END DO
    END IF

    MaxCon = RefCon
    ind = MaxConInd
    prevstart = MAX(1,ind)
    ind0 = prevstart


    DO WHILE( MaxCon > 0) 

      cind = cind + 1
      CF(ind) = cind
      Con(ind) = 0
      cnods = cnods + 1

      ! Go through all strongly bonded neighbours to 'ind'
      DO j=Rows(ind),Rows(ind+1)-1
        IF(.NOT. Bonds(j)) CYCLE
        cj = Cols(j)

        IF(CF(cj) == 0) THEN
          find = find + 1
          CF(cj) = -find
          Con(cj) = 0
          IF(Cands(cj) == 0) CYCLE
          
          ! Recompute the measure of importance for the neighbours
          DO i=Rows(cj),Rows(cj+1)-1
            IF(Bonds(i)) THEN
              ci = Cols(i)          
              IF(Cands(ci) > 0 .AND. CF(ci) == 0) THEN
                Con(ci) = Con(ci) + 1
              END IF
            END IF
          END DO
        END IF
      END DO

      ! The next candidate is probably among the secondary neighbours
      RefCon = 0
      RefCon2 = 0
      maxi = 0
      maxi2 = 0


      IF(CoarseningMode == 2) THEN       
        DO j=Rows(ind),Rows(ind+1)-1
          IF(.NOT. Bonds(j)) CYCLE
          cj = Cols(j)
          IF(Cands(cj) == 0) CYCLE
          
          DO i=Rows(cj),Rows(cj+1)-1
            IF(.NOT. Bonds(i)) CYCLE
            ci = Cols(i)
            
            IF(Cands(ci) == 0 .OR. CF(ci) /= 0) CYCLE
            
            IF(Con(ci) > RefCon .AND. ci /= maxi) THEN
              RefCon2 = RefCon
              maxi2 = maxi
              RefCon = Con(ci)
              maxi = ci
            ELSE IF (Con(ci) > RefCon2 .AND. ci /= maxi) THEN
              RefCon2 = Con(ci)
              maxi2 = ci
            END IF
          END DO
        END DO
        
        ! If none of the neighbouring nodes is a potential node go and find a new candidate
        IF(RefCon < MaxCon) THEN
          GOTO 10
        END IF

        MaxCon = MAX(RefCon2,MaxCon)

      ELSE
        maxneigh = 0
        DO j=Rows(ind),Rows(ind+1)-1
          IF(.NOT. Bonds(j)) CYCLE
          cj = Cols(j)
          IF(Cands(cj) == 0) CYCLE
          
          DO i=Rows(cj),Rows(cj+1)-1
            IF(.NOT. Bonds(i)) CYCLE
            ci = Cols(i)
            
            IF(Cands(ci) == 0 .OR. CF(ci) /= 0) CYCLE
            
            IF((Con(ci) > RefCon) .OR. (Con(ci) == RefCon .AND. -CF(cj) > maxneigh)) THEN
              RefCon = Con(ci)
              maxi = ci
              maxneigh = MAX(maxneigh,-CF(cj))
            END IF
          END DO
        END DO
        
        IF(RefCon < MaxCon) THEN

          DO j=Rows(ind0),Rows(ind0+1)-1
            IF(.NOT. Bonds(j)) CYCLE
            cj = Cols(j)
            IF(Cands(cj) == 0) CYCLE
            
            DO i=Rows(cj),Rows(cj+1)-1
              IF(.NOT. Bonds(i)) CYCLE
              ci = Cols(i)
              
              IF(Cands(ci) == 0 .OR. CF(ci) /= 0) CYCLE
              
              IF(Con(ci) > RefCon2) THEN
                RefCon2 = Con(ci)
                maxi2 = ci
                IF(CF(cj) < 0) minneigh = MIN(minneigh,-CF(cj))
              ELSE IF (Con(ci) == RefCon2) THEN
                IF(CF(cj) < 0 .AND. -CF(cj) < minneigh) THEN
                  RefCon2 = Con(ci)
                  maxi2 = ci
                  minneigh = -CF(cj)
                END IF
              END IF
            END DO
          END DO
          
          ! Favor the vicinity of the previous starting point
          IF(RefCon2 >= RefCon) THEN
            maxi = maxi2
            RefCon = RefCon2
          END IF
          ind0 = maxi
        END IF
        
        IF(CoarseningMode == 1 .AND. RefCon < MaxCon) THEN
          GOTO 10
        END IF

        IF(CoarseningMode == 0 .AND. RefCon < 1) THEN
          GOTO 10
        END IF

      END IF

      ind = maxi
    END DO

    WRITE(Message,'(A,i)') 'Coarsening algorhitm starts',newstarts
    CALL Info('AMGCoarse',Message)
    WRITE(Message,'(A,i)') 'Coarsening algorhitm tests',loops
    CALL Info('AMGCoarse',Message)
    WRITE(Message,'(A,i)') 'Coarsening algorhitm tests per start',loops/newstarts
    CALL Info('AMGCoarse',Message)

    WRITE(Message,'(A,i)') 'Coarsening algorhitm c-nodes',cind
    CALL Info('AMGCoarse',Message)
    WRITE(Message,'(A,i)') 'Coarsening algorhitm f-nodes',find
    CALL Info('AMGCoarse',Message)

  END SUBROUTINE AMGCoarse


!-----------------------------------------------------------------------------
!     make a matrix projection such that fine nodes are expressed with coarse nodes
!     Xf = P Xc, using with given set of coarse nodes, CF, and the stiffness matrix
!     used in the projection.
!------------------------------------------------------------------------------
     FUNCTION InterpolateF2C( Fmat, CF, DOFs) RESULT (Projector)
!------------------------------------------------------------------------------
       USE Interpolation
       USE CRSMatrix
       USE CoordinateSystems
!-------------------------------------------------------------------------------
       TYPE(Matrix_t), TARGET  :: Fmat
       INTEGER, POINTER :: CF(:)
       INTEGER :: DOFs
       TYPE(Matrix_t), POINTER :: Projector
!------------------------------------------------------------------------------
       INTEGER, PARAMETER :: FSIZE=1000, CSIZE=100
       INTEGER :: i, j, k, l, Fdofs, Cdofs, ind, ci, cj, Component1, Components, node
       REAL(KIND=dp), POINTER :: PValues(:), FValues(:)
       INTEGER, POINTER :: FRows(:), FCols(:), PRows(:), PCols(:), CoeffsInds(:)
       REAL(KIND=dp) :: bond, value, possum, negsum, poscsum, negcsum, diagsum, &
           ProjLim, negbond, posbond, maxbond
       LOGICAL :: Debug, AllocationsDone, DirectInterpolate, Lumping
       INTEGER :: inds(FSIZE), posinds(CSIZE), neginds(CSIZE), no, diag, InfoNode, &
           posno, negno, negi, posi, projnodes, DirectLimit
       REAL(KIND=dp) :: coeffs(FSIZE), poscoeffs(CSIZE), negcoeffs(CSIZE), wsum, &
           refbond, posmax, negmax

       Debug = .FALSE.

       CALL Info('InterpolateF2C','Starting interpolation')
       
       ProjLim = ListGetConstReal(Solver % Values,'MG Projection Limit',GotIt)
       IF(.NOT. GotIt) ProjLim = 0.1

       Lumping = ListGetLogical(Solver % Values,'MG Projection Lumping',GotIt)

       DirectInterpolate = ListGetLogical(Solver % Values,'MG Direct Interpolate',GotIt)

       DirectLimit = ListGetInteger(Solver % Values,'MG Direct Interpolate Limit',GotIt)      
       IF(.NOT. GotIt) THEN
         IF(DirectInterpolate) THEN
           DirectLimit = 0
         ELSE
           DirectLimit = HUGE(DirectLimit)
         END IF
       END IF

       Component1 = ListGetInteger(Solver % Values,'MG Determining Component',GotIt,minv=1,maxv=DOFs)
       IF(.NOT. GotIt) Component1 = 1

       Components = DOFs
       IF(.NOT. IdenticalProjs) THEN
         Components = 1
         Component1 = 1
       END IF

       InfoNode = ListGetInteger(Solver % Values,'MG Info Node',GotIt)

       Fdofs = Fmat % NumberOfRows
       FRows   => Fmat % Rows
       FCols   => Fmat % Cols
       FValues => Fmat % Values
       
       ALLOCATE(CoeffsInds(Fdofs))
       CoeffsInds = 0

       ! Calculate the order of the new dofs
       Cdofs = 0
       DO ind = 1,Fdofs
         IF(CF(ind) > 0) THEN
           Cdofs = Cdofs + 1
           CF(ind) = Cdofs
         END IF
       END DO
       
       ! Initialize stuff before allocations
       AllocationsDone = .FALSE.
       ALLOCATE( PRows(Fdofs+1) )
       PRows(1) = 1

       ! Go through the fine dofs and make a projection based on the strongly coupled nodes
       ! The first time only compute the structure of matrix to be allocated
10     inds = 0
       coeffs = 0.0d0      
       posinds = 0
       neginds = 0
       poscoeffs = 0.0
       negcoeffs = 0.0

       DO ind=Component1,Fdofs,Components

         node = (ind-Component1) / Components + 1

         Debug = (node == InfoNode) 

         ! For C-nodes use 1-to-1 mapping
         IF(CF(ind) > 0) THEN
           projnodes = 1
           IF(AllocationsDone) THEN
             PCols(PRows(node)) = CF(ind)
             Pvalues(PRows(node)) = 1.0d0            
           END IF
         ELSE
           
           no = 0
           projnodes = 0
           j = 0
           
           IF(DirectInterpolate) THEN
             DO i=FRows(ind),FRows(ind+1)-1
               ci = Fcols(i)

               IF(MOD(ci-Component1,Components) /= 0) CYCLE

               value = FValues(i)
               IF(ABS(value) < 1.0d-50) CYCLE
               no = no + 1
               inds(no) = FCols(i)
               coeffs(no) = value
               IF(ci == ind) THEN
                 diag = no
               ELSE IF(CF(ci) > 0) THEN
                 j = j + 1
               END IF
             END DO
           END IF

           IF(j < DirectLimit) THEN

             IF(no > 0) THEN
               inds(1:no) = 0
               coeffs(1:no) = 0
               no = 0
             END IF

             ! First make the list of the C-neighbouts
             diag = 0
             DO i=FRows(ind),FRows(ind+1)-1
               ci = Fcols(i)

               IF(MOD(ci-Component1,Components) /= 0) CYCLE

               IF(CF(ci) > 0 .OR. ci == ind) THEN
                 value = FValues(i)
                 IF(ABS(value) < 1.0d-50) CYCLE 
                 no = no + 1
                 inds(no) = ci
                 coeffs(no) = value
                 CoeffsInds(ci) = no
                 IF(ci == ind) diag = no
              END IF
             END DO

             
             ! Then go though the F-neigbours and express them with linear combinations
             DO i=FRows(ind),FRows(ind+1)-1
               ci = Fcols(i)

               IF(MOD(ci-Component1,Components) /= 0) CYCLE

               IF(CF(ci) > 0 .OR. ci == ind) CYCLE
               
               DO j=FRows(ci),FRows(ci+1)-1
                 cj = Fcols(j)
                 IF(ci == cj) CYCLE

                 value = Fvalues(i) * Fvalues(j) / Fvalues(Fmat % diag(ci))
                 IF(ABS(value) < 1.0d-50) CYCLE
                 
                 k = CoeffsInds(cj) 
                 IF(k == 0) THEN
                   no = no + 1
                   inds(no) = cj
                   k = no
                   CoeffsInds(cj) = no
                 END IF

                 IF(k > FSIZE) THEN
                   PRINT *,'k',k,l,cj,CoeffsInds(cj)
                   CALL Fatal('InterpolateFineToCoarse','There are more neighbours than expected')
                 END IF
                 coeffs(k) = coeffs(k) - value
               END DO
             END DO

             CoeffsInds(inds(1:no)) = 0
           END IF
             
           IF(Debug) THEN
             PRINT *,'ind no diag',ind,no,diag
             PRINT *,'coeffs',coeffs(1:no)
             PRINT *,'inds',inds(1:no)
           END IF

           ! Check for Dirichlet points which should not be projected
           IF(no <= 1) THEN
             IF(diag == 0) THEN
               CALL Fatal('InterpolateFineToCoarse','Diagonal seems to be zero!')
             ELSE
               projnodes =  0
               inds(1:no) = 0
               coeffs(1:no) = 0.0
               GOTO 20 
             END IF
           END IF

          
           ! Calculate the bond limit and the total sums 
           possum = 0.0
           negsum = 0.0
           negmax = 0.0
           posmax = 0.0
           posi = 0
           negi = 0

           IF(Lumping) THEN
             coeffs(diag) = coeffs(diag) - SUM(coeffs(1:no))
           END IF
          
           ! If the diagonal is negative the invert the selection 
           IF(coeffs(diag) < 0.0) THEN
             coeffs(1:no) = -coeffs(1:no)
           END IF

           DO i=1,no
             value = coeffs(i)
             IF(i == diag) THEN
               diagsum = value
             ELSE IF(value > 0.0) THEN
               possum = possum + value
               ci = inds(i)
               IF(CF(ci) > 0) THEN
                 posmax = MAX(posmax, value)
                 posi = posi + 1
               END IF
             ELSE 
               negsum = negsum + value
               ci = inds(i)
               IF(CF(ci) > 0) THEN
                 negmax = MIN(negmax, value)
                 negi = negi + 1
               END IF
             END IF
           END DO

           IF(posi == 0 .AND. negi == 0) THEN
             PRINT *,'The node is not connected to c-neighbours' 
             projnodes =  0
             inds(1:no) = 0
             coeffs(1:no) = 0.0
             GOTO 20               
           END IF

           posno = 0
           negno = 0

           ! Decide the algorhitm knowing which weights dominate +/-
           ! Negative weights dominate
           IF(posi == 0 .OR. ABS(possum) <= ABS(negsum)) THEN

             IF(negi == 0) THEN
               PRINT *,'Negatively bonded node has no c-neighbours',ind,negsum,possum,posi
               PRINT *,'inds',inds(1:no)
               PRINT *,'cf',CF(inds(1:no))
               PRINT *,'coeffs',coeffs(1:no)
               
               projnodes =  0
               inds(1:no) = 0
               coeffs(1:no) = 0.0
               GOTO 20                
             END IF

             negcsum = 0.0
             DO i=1,no
               value = coeffs(i)
               ci = inds(i)
               IF(CF(ci) == 0) CYCLE
               IF(value < ProjLim * negmax) THEN
                 negno = negno + 1
                 neginds(negno) = ci
                 negcoeffs(negno) = value
                 negcsum = negcsum + value
               ELSE IF(value > ProjLim * posmax) THEN
                 posno = posno + 1
                 posinds(posno) = ci
                 poscoeffs(posno) = value                 
               END IF
             END DO

             negi = negno             
             posi = 0
             refbond = -ProjLim * negsum * negmax / negcsum 

             ! Add possible positive weights
             IF(possum > refbond) THEN
               ! Order the positive coefficients in an decreasing order
               DO j = 1, posno-1
                 DO i = 1, posno-1
                   IF(poscoeffs(i) < poscoeffs(i+1)) THEN
                     poscoeffs(posno+1) = poscoeffs(i)
                     poscoeffs(i) = poscoeffs(i+1)
                     poscoeffs(i+1) = poscoeffs(posno+1)
                     posinds(posno+1) = posinds(i)
                     posinds(i) = posinds(i+1)
                     posinds(i+1) = posinds(posno+1)
                   END IF
                 END DO
               END DO
               IF(Debug) THEN
                 IF(posno > 0) THEN
                   PRINT *,'pos connections',posno
                   PRINT *,'inds',posinds(1:posno)
                   PRINT *,'coeffs',poscoeffs(1:posno)
                 END IF
               END IF
               
               poscsum = 0.0

               ! Now go through the possible positive connections 
               DO i=1,posno
                 IF(i == 1) THEN
                   posbond = possum 
                   IF(posbond < refbond) EXIT
                 ELSE
                   posbond = possum * poscoeffs(i) / (poscsum + poscoeffs(i))                
                   IF(posbond < refbond .AND. poscoeffs(i) < 0.99 * poscoeffs(i-1)) EXIT 
                 END IF
                 posi = i
                 poscsum = poscsum + poscoeffs(posi)
               END DO
             END IF

             
           ELSE ! Positive weight dominate

             IF(posi == 0) THEN
               PRINT *,'Positively bonded node has no positive c-neighbours',ind,negsum,possum
               projnodes =  0
               inds(1:no) = 0
               coeffs(1:no) = 0.0
               GOTO 20                
             END IF

             poscsum = 0.0
             DO i=1,no
               value = coeffs(i)
               ci = inds(i)
               IF(CF(ci) == 0) CYCLE
               IF( value > ProjLim * posmax ) THEN
                 posno = posno + 1
                 posinds(posno) = ci
                 poscoeffs(posno) = value
                 poscsum = poscsum + value
               ELSE IF(value < ProjLim * negmax) THEN
                 negno = negno + 1
                 neginds(negno) = ci
                 negcoeffs(negno) = value
               END IF
             END DO

             posi = posno
             negi = 0             
             refbond = ProjLim * possum * posmax / poscsum 

             IF(-negsum > refbond) THEN
               ! Order the negative coefficients in an increasing order
               DO j = 1, negno-1
                 DO i = 1,negno-1
                   IF(negcoeffs(i) > negcoeffs(i+1)) THEN
                     negcoeffs(negno+1) = negcoeffs(i)
                     negcoeffs(i) = negcoeffs(i+1)
                     negcoeffs(i+1) = negcoeffs(negno+1)
                     neginds(negno+1) = neginds(i)
                     neginds(i) = neginds(i+1)
                     neginds(i+1) = neginds(negno+1)
                   END IF
                 END DO
               END DO
               IF(Debug) THEN
                 IF(negno > 0) THEN
                   PRINT *,'neg connections after',negno
                   PRINT *,'inds',neginds(1:negno)
                   PRINT *,'coeffs',negcoeffs(1:negno)
                 END IF
               END IF

               negcsum = 0.0

               ! Now go through the possible positive connections 
               DO i=1,negno
                 IF(i == 1) THEN
                   negbond = negsum 
                   IF(-negbond < refbond) EXIT
                 ELSE
                   negbond = negsum * negcoeffs(i) / (negcsum + negcoeffs(i) )
                   IF(-negbond < refbond .AND. negcoeffs(i) > 0.99 * negcoeffs(i-1)) EXIT 
                 END IF
                 negi = i
                 negcsum = negcsum + negcoeffs(i)
               END DO

             END IF
           END IF

           projnodes = posi + negi
           IF(debug) PRINT *,'bonds',posi,negi,negcsum,neginds(1)
           
           ! Compute the weights and store them to the projection matrix
           IF(AllocationsDone) THEN
             wsum = 0.0

             IF(posi == 0) THEN
               diagsum = diagsum + possum
             END IF    
             IF(negi == 0) THEN
               diagsum = diagsum + negsum
             END IF            

             DO i=1,negi
               value = -negsum * negcoeffs(i) / (negcsum * diagsum)
               ci = neginds(i)
               IF(Debug) PRINT *,'F-: Pij',ind,CF(ci),value
               PCols(Prows(node)+i-1) = CF(ci)
               PValues(Prows(node)+i-1) = value
               wsum = wsum + value
             END DO
             DO i=1,posi
               value = -possum * poscoeffs(i) / (poscsum * diagsum)
               ci = posinds(i)
               IF(Debug) PRINT *,'F+: Pij',ind,CF(ci),value
               PCols(Prows(node)+i+negi-1) = CF(ci)
               PValues(Prows(node)+i+negi-1) = value
               wsum = wsum + value
             END DO

             IF(Debug) PRINT *,'ind wsum projnodes',ind,wsum,projnodes
           END IF

           inds(1:no) = 0
           coeffs(1:no) = 0.0
         END IF

20       IF(Debug) PRINT *,'ind nodes',ind,projnodes
         PRows(node+1) = PRows(node) + projnodes

       END DO

       ! Allocate space for the projection matrix and thereafter do the loop again
       IF(.NOT. AllocationsDone) THEN
         IF(Debug) PRINT *,'allocated space',PRows(Fdofs+1)-1
         Projector => AllocateMatrix()
         Projector % NumberOfRows = Fdofs/Components

         ALLOCATE( PCols(PRows(Fdofs/Components+1)-1), PValues(PRows(Fdofs/Components+1)-1) )           
         AllocationsDone = .TRUE.
         PCols   = 0
         PValues = 0
         
         Projector % Rows   => PRows
         Projector % Cols   => PCols 
         Projector % Values => PValues
         
         GOTO 10
       END IF

       DEALLOCATE(CoeffsInds)
       
     END FUNCTION InterpolateF2C
!-------------------------------------------------------------------------


!-----------------------------------------------------------------------------
!     As the previous one but expects complex valued equation.
!     The projector is built using only the absolute values. 
!------------------------------------------------------------------------------
     FUNCTION ComplexInterpolateF2C( Fmat, CF ) RESULT (Projector)
!------------------------------------------------------------------------------
       USE Interpolation
       USE CRSMatrix
       USE CoordinateSystems
!-------------------------------------------------------------------------------
       TYPE(Matrix_t), TARGET  :: Fmat
       INTEGER, POINTER :: CF(:)
       TYPE(Matrix_t), POINTER :: Projector
!------------------------------------------------------------------------------
       INTEGER, PARAMETER :: FSIZE=1000, CSIZE=100
       INTEGER :: i, j, k, l, Fdofs, Cdofs, ind, ci, cj, node
       REAL(KIND=dp), POINTER :: PValues(:), FValues(:)
       INTEGER, POINTER :: FRows(:), FCols(:), PRows(:), PCols(:), CoeffsInds(:)
       REAL(KIND=dp) :: bond, ProjLim, posbond, maxbond
       LOGICAL :: Debug, AllocationsDone, DirectInterpolate, Lumping
       INTEGER :: inds(FSIZE), posinds(CSIZE), no, diag, InfoNode, posi, &
           DirectLimit, projnodes
       REAL(KIND=dp) :: wsum, refbond, posmax

       REAL(KIND=dp) :: poscoeffs(CSIZE), value, poscsum, possum, diagsum
       COMPLEX(KIND=dp) :: coeffs(FSIZE), cvalue 

       Debug = .FALSE.

       CALL Info('ComplexInterpolateF2C','Starting interpolation')

       
       ProjLim = ListGetConstReal(Solver % Values,'MG Projection Limit',GotIt)
       IF(.NOT. GotIt) ProjLim = 0.1

       Lumping = ListGetLogical(Solver % Values,'MG Projection Lumping',GotIt)

       DirectInterpolate = ListGetLogical(Solver % Values,'MG Direct Interpolate',GotIt)

       DirectLimit = ListGetInteger(Solver % Values,'MG Direct Interpolate Limit',GotIt)      
       IF(.NOT. GotIt) THEN
         IF(DirectInterpolate) THEN
           DirectLimit = 0
         ELSE
           DirectLimit = HUGE(DirectLimit)
         END IF
       END IF

       InfoNode = ListGetInteger(Solver % Values,'MG Info Node',GotIt)

       Fdofs = Fmat % NumberOfRows 
       FRows   => Fmat % Rows
       FCols   => Fmat % Cols
       FValues => Fmat % Values
       
       ALLOCATE(CoeffsInds(Fdofs))
       CoeffsInds = 0

       ! Calculate the order of the new dofs 
       Cdofs = 0
       DO ind = 1,Fdofs,2
         IF(CF(ind) > 0) THEN
           Cdofs = Cdofs + 1
           CF(ind) = Cdofs
         END IF
       END DO
       
       if(Debug) print *,'cdofs',cdofs,'fdofs',fdofs

       ! Initialize stuff before allocations
       AllocationsDone = .FALSE.
       ALLOCATE( PRows(Fdofs/2+1) )
       PRows(1) = 1

       ! Go through the fine dofs and make a projection based on the strongly coupled nodes
       ! The first time only compute the structure of matrix to be allocated
10     inds = 0
       coeffs = 0.0
       posinds = 0
       poscoeffs = 0.0

       DO node=1,Fdofs/2

         ind = 2*node-1

!         Debug = (node == InfoNode) 

         if(debug) print *,'ind',ind

         ! For C-nodes use 1-to-1 mapping (for real and complex dofs)
         IF(CF(ind) > 0) THEN
           projnodes = 1
           IF(AllocationsDone) THEN
             PCols(PRows(node)) = CF(ind)
             Pvalues(PRows(node)) = 1.0d0            
           END IF
         ELSE
           
           no = 0
           projnodes = 0
           j = 0
           
           IF(DirectInterpolate) THEN
             DO i=FRows(ind),FRows(ind+1)-1,2
               ci = Fcols(i)

               cvalue = DCMPLX(FValues(i),-FValues(i+1))
               IF(ABS(cvalue) < 1.0d-50) CYCLE
               no = no + 1
               inds(no) = FCols(i)
               coeffs(no) = cvalue
               IF(ci == ind) THEN
                 diag = no
               ELSE IF(CF(ci) > 0) THEN
                 j = j + 1
               END IF
             END DO
           END IF

           IF(j < DirectLimit) THEN

             IF(no > 0) THEN
               inds(1:no) = 0
               coeffs(1:no) = 0.0
               no = 0
             END IF

             ! First make the list of the C-neighbouts
             diag = 0
             DO i=FRows(ind),FRows(ind+1)-1,2
               ci = Fcols(i)

               IF(CF(ci) > 0 .OR. ci == ind) THEN
                 cvalue = DCMPLX(FValues(i),-Fvalues(i+1))
                 IF(ABS(cvalue) < 1.0d-50) CYCLE 
                 no = no + 1
                 inds(no) = ci
                 coeffs(no) = cvalue
                 CoeffsInds(ci) = no
                 IF(ci == ind) diag = no
               END IF
             END DO

             
             ! Then go though the F-neigbours and express them with linear combinations
             DO i=FRows(ind),FRows(ind+1)-1,2
               ci = Fcols(i)

               IF(CF(ci) > 0 .OR. ci == ind) CYCLE
               
               DO j=FRows(ci),FRows(ci+1)-1,2
                 cj = Fcols(j)
                 IF(ci == cj) CYCLE
                                  
                 cvalue = DCMPLX(Fvalues(i), -Fvalues(i+1)) * DCMPLX(Fvalues(j),-Fvalues(j+1)) / &
                     DCMPLX(Fvalues(Fmat % diag(ci)),-Fvalues(Fmat % diag(ci)+1))
                 IF(ABS(cvalue) < 1.0d-50) CYCLE
                 
                 k = CoeffsInds(cj) 
                 IF(k == 0) THEN
                   no = no + 1
                   inds(no) = cj
                   k = no
                   CoeffsInds(cj) = no
                 END IF

                 IF(k > FSIZE) THEN
                   PRINT *,'k',k,l,cj,CoeffsInds(cj)
                   CALL Fatal('InterpolateFineToCoarse','There are more neighbours than expected')
                 END IF
                 coeffs(k) = coeffs(k) - cvalue
               END DO
             END DO
             
!             IF(debug) PRINT *,'no',no,'inds',inds(1:no)
           
             CoeffsInds(inds(1:no)) = 0
           END IF
             
!          IF(Debug) THEN
!             PRINT *,'ind no diag',ind,no,diag
!             PRINT *,'coeffs',coeffs(1:no)
!             PRINT *,'inds',inds(1:no)
!           END IF

           ! Check for Dirichlet points which should not be projected
           IF(no <= 1) THEN
             IF(diag == 0) THEN
               CALL Fatal('InterpolateFineToCoarse','Diagonal seems to be zero!')
             ELSE
               projnodes =  0
               inds(1:no) = 0
               coeffs(1:no) = 0.0
               GOTO 20 
             END IF
           END IF

          
           ! Calculate the bond limit and the total sums 
           possum = 0.0
           posmax = 0.0
           posi = 0

           IF(Lumping) THEN
             coeffs(diag) = coeffs(diag) - SUM(coeffs(1:no))
           END IF

           DO i=1,no
             value = ABS(coeffs(i))
             IF(i == diag) THEN
               diagsum = value
             ELSE 
               possum = possum + value
               ci = inds(i)
               IF(CF(ci) > 0) THEN
                 posmax = MAX(posmax, value )
                 posi = posi + 1
               END IF
             END IF
           END DO

           IF(posi == 0) THEN
             PRINT *,'The node is not connected to c-neighbours' 
             PRINT *,'inds',inds(1:no)
             PRINT *,'cf',CF(inds(1:no))
             PRINT *,'coeffs',coeffs(1:no)

             projnodes =  0
             inds(1:no) = 0
             coeffs(1:no) = 0.0
             GOTO 20               
           END IF

           projnodes = 0
           poscsum = 0.0

           DO i=1,no
             value = ABS(coeffs(i))
             ci = inds(i)
             IF(CF(ci) == 0) CYCLE
             IF(ABS(value) > ProjLim * posmax) THEN
               projnodes = projnodes + 1
               posinds(projnodes) = ci
               poscoeffs(projnodes) = value                 
               poscsum = poscsum + value
             END IF
           END DO

!          IF(debug) PRINT *,'bonds',projnodes,poscsum
           
           wsum = 0.0
          ! Compute the weights and store them to a projection matrix
           IF(AllocationsDone) THEN

            wsum = 0.0
            DO i=1,projnodes
               value = possum * poscoeffs(i) / (poscsum * diagsum)
               ci = posinds(i)
               IF(Debug) PRINT *,'F+: Pij',node,CF(ci),value,poscoeffs(i)

               PCols(Prows(node)+i-1) = CF(ci) 
               PValues(Prows(node)+i-1) = value
               
               wsum = wsum + value
             END DO
             IF(Debug) PRINT *,'ind projnodes wsum',ind,projnodes,wsum,diagsum,poscsum,possum

           END IF

           inds(1:no) = 0
           coeffs(1:no) = 0.0
         END IF

20       PRows(node+1) = PRows(node) + projnodes
!         IF(Debug) PRINT *,'ind nodes',ind,projnodes,wsum

       END DO

       ! Allocate space for the projection matrix and thereafter do the loop again
       IF(.NOT. AllocationsDone) THEN
         IF(Debug) PRINT *,'allocated space',PRows(Fdofs/2+1)-1
         Projector => AllocateMatrix()
         Projector % NumberOfRows = Fdofs/2

         ALLOCATE( PCols(PRows(Fdofs/2+1)-1), PValues(PRows(Fdofs/2+1)-1) )           
         AllocationsDone = .TRUE.
         PCols   = 0
         PValues = 0
         
         Projector % Rows   => PRows
         Projector % Cols   => PCols 
         Projector % Values => PValues
         
         GOTO 10
       END IF

       DEALLOCATE(CoeffsInds)

       Cdofs = 0
       DO ind = 1,Fdofs
         IF(CF(ind) > 0) THEN
           Cdofs = Cdofs + 1
           CF(ind) = Cdofs
         END IF
       END DO
       
       
     END FUNCTION ComplexInterpolateF2C
!-------------------------------------------------------------------------


 
!------------------------------------------------------------------------------
!   This subroutine may be used to check that mapping Xf = P Xc is accurate.
!   The list of original nodes for each level is stored in the Cnodes vector.
!   For the momont this only works for cases with one DOF and no permutation!
!------------------------------------------------------------------------------
    SUBROUTINE AMGTest(direction) 
!------------------------------------------------------------------------------
      INTEGER :: direction

      INTEGER :: i,j,Rounds, nods1, nods2, SaveLimit
      LOGICAL :: GotIt
      CHARACTER(LEN=MAX_NAME_LEN) :: Filename
      REAL(KIND=dp) :: RNorm
      REAL(KIND=dp), POINTER :: Ina(:), Inb(:), Outa(:), Outb(:)

      nods1 = Matrix1 % NumberOfRows
      nods2 = Matrix2 % NumberOfRows

      SaveLimit = ListGetInteger(Solver % Values,'MG Coarse Nodes Save Limit',GotIt) 
      IF(nods2 > SaveLimit) RETURN

!      Project the fine dofs to the coarse dofs
!      ----------------------------------------

      IF(Direction == 0) THEN
        WRITE( Filename,'(a,i1,a,i1,a)' ) 'mapping', Level,'to',Level-1, '.dat'

        ALLOCATE( Ina(nods1), Inb(nods1), Outa(nods2), Outb(nods2) )

        IF(nods1 < SaveLimit) THEN
          IF ( Level == Solver % MultiGridTotal ) THEN
            WRITE( Filename,'(a,i1,a)' ) 'nodes', Solver % MultiGridTotal - Level,'.dat'
            OPEN (10,FILE=Filename)        
            DO i=1,nods1
              WRITE (10,'(3ES17.8E3)') Mesh % Nodes % X(i), Mesh % Nodes % Y(i), Mesh % Nodes % Z(i)
            END DO
          END IF
        END IF

        WRITE( Filename,'(a,i1,a)' ) 'nodes', Solver % MultiGridTotal - Level+1,'.dat'
        OPEN (10,FILE=Filename)        
        DO i=1,nods2
          WRITE (10,'(3ES17.8E3)') Mesh % Nodes % X(AMG(Level) % InvCF(i)), &
              Mesh % Nodes % Y(AMG(Level) % InvCF(i)), Mesh % Nodes % Z(AMG(Level) % InvCF(i))
        END DO
        CLOSE(10)
      END IF
  

      IF(Direction == 1) THEN
        WRITE( Filename,'(a,i1,a,i1,a)' ) 'mapping', Level,'to',Level-1, '.dat'

        ALLOCATE( Ina(nods1), Inb(nods1), Outa(nods2), Outb(nods2) )

        IF ( Level == Solver % MultiGridLevel ) THEN
          Ina = Mesh % Nodes % X
          Inb = Mesh % Nodes % Y
        ELSE
          Ina = Mesh % Nodes % X(AMG(Level+1) % InvCF )
          Inb = Mesh % Nodes % Y(AMG(Level+1) % InvCF )
        END IF

        Outa = 0.0d0
        Outb = 0.0d0
        
        CALL CRS_ProjectVector( ProjPN, Ina, Outa, Trans = .FALSE. )
        CALL CRS_ProjectVector( ProjPN, Inb, Outb, Trans = .FALSE. )        

        OPEN (10,FILE=Filename)        
        DO i=1,nods2
          WRITE (10,'(4ES17.8E3)') Mesh % Nodes % X(AMG(Level) % InvCF(i) ), &
              Mesh % Nodes % Y(AMG(Level) % InvCF(i) ) , Outa(i), Outb(i)
        END DO
        CLOSE(10)
      END IF
      
!      Project the coarse dofs to the fine dofs
!      ----------------------------------------

      IF(Direction == 2) THEN

        WRITE( Filename,'(a,i1,a,i1,a)' ) 'mapping', Level-1,'to',Level, '.dat'

        ALLOCATE( Ina(nods2), Inb(nods2), Outa(nods1), Outb(nods1) )
      
        Ina = 0.0d0
        Inb = 0.0d0

        Ina = Mesh % Nodes % X(AMG(Level) % InvCF )
        Inb = Mesh % Nodes % Y(AMG(Level) % InvCF )

        Outa = 0.0d0
        Outb = 0.0d0

        
        PRINT *,'Initial Interval x',MINVAL(Ina),MAXVAL(Ina)
        PRINT *,'Initial Interval y',MINVAL(Inb),MAXVAL(Inb)
        PRINT *,'Initial Mean Values',SUM(Ina)/SIZE(Ina),SUM(Inb)/SIZE(Inb)

        CALL CRS_ProjectVector( ProjQT, Ina, Outa, Trans = .TRUE. )
        CALL CRS_ProjectVector( ProjQT, Inb, Outb, Trans = .TRUE. )        

        PRINT *,'Final Interval x',MINVAL(Outa),MAXVAL(Outa),SUM(Outa)/SIZE(Outa)
        PRINT *,'Final Interval y',MINVAL(Outb),MAXVAL(Outb),SUM(Outb)/SIZE(Outb)
        PRINT *,'Final Mean Values',SUM(Outa)/SIZE(Outa),SUM(Outb)/SIZE(Outb)
        
        OPEN (10,FILE=Filename)        
 
        IF ( Level == Solver % MultiGridLevel ) THEN
          DO i=1,nods1
            WRITE (10,'(4ES17.8E3)') Mesh % Nodes % X(i), Mesh % Nodes % Y(i) , Outa(i), Outb(i)
          END DO
        ELSE
          DO i=1,nods1
            WRITE (10,'(4ES17.8E3)') Mesh % Nodes % X(AMG(Level+1) % InvCF(i) ), &
                Mesh % Nodes % Y(AMG(Level+1) % InvCF(i) ) , Outa(i), Outb(i)
          END DO
        END IF
        CLOSE(10)        

      END IF

      WRITE(Message,'(A,A)') 'Save mapped results into file: ',TRIM(Filename)
      CALL Info('MGTest',Message)

      DEALLOCATE(Ina, Inb, Outa, Outb)

    END SUBROUTINE AMGTest

!------------------------------------------------------------------------------


!----------------------------------------------------------------------------
!   The following subroutines are CR (Compatible Relaxation) versions of the
!   simple relaxation schemes. The relaxation speed of equation Ax = 0 to x=0
!   may be used as a measure of the goodness of the chosen coarse node set.
!-----------------------------------------------------------------------------
    SUBROUTINE CR_Jacobi( A, x0, x1, f, Rounds )
!-----------------------------------------------------------------------------
       TYPE(Matrix_t), POINTER :: A
       INTEGER :: Rounds, f(:)
       REAL(KIND=dp) :: x0(:), x1(:), s
       INTEGER :: i,j,k,n
       INTEGER, POINTER :: Rows(:), Cols(:)
       REAL(KIND=dp), POINTER :: Values(:)
       
       n = A % NumberOfRows
       Rows   => A % Rows
       Cols   => A % Cols
       Values => A % Values

       DO k=1,Rounds
         IF(k > 1) x0 = x1
         DO i=1,n
           IF(f(i) > 0) CYCLE
           s = 0.0d0
           DO j=Rows(i),Rows(i+1)-1
             s = s + x0(Cols(j)) * Values(j)
           END DO

           x1(i) = x0(i) - s / A % Values(A % Diag(i))
         END DO
       END DO
     END SUBROUTINE CR_Jacobi


!------------------------------------------------------------------------------
    SUBROUTINE CR_GS( A, x0, x1, f, Rounds )
!------------------------------------------------------------------------------
       TYPE(Matrix_t), POINTER :: A
       INTEGER :: Rounds, f(:)
       REAL(KIND=dp) :: x0(:), x1(:)
       INTEGER :: i,j,k,n
       REAL(KIND=dp) :: s
       INTEGER, POINTER :: Cols(:),Rows(:)
       REAL(KIND=dp), POINTER :: Values(:)
     
       n = A % NumberOfRows
       Rows   => A % Rows
       Cols   => A % Cols
       Values => A % Values
       
       x1 = x0

       DO k=1,Rounds
         DO i=1,n
           IF(f(i) > 0) CYCLE
           s = 0.0d0
           DO j=Rows(i),Rows(i+1)-1
             s = s + x1(Cols(j)) * Values(j)
           END DO

           x1(i) = x1(i) - s / A % Values(A % Diag(i))
         END DO
         IF(k == Rounds-1) x0 = x1
       END DO

     END SUBROUTINE CR_GS


!------------------------------------------------------------------------------
     SUBROUTINE CR_SGS( A, x0, x1, f, Rounds)
!------------------------------------------------------------------------------
       TYPE(Matrix_t), POINTER :: A
       INTEGER :: Rounds, f(:)
       REAL(KIND=dp) :: x0(:),x1(:)
       INTEGER :: i,j,k,n
       REAL(KIND=dp) :: s
       INTEGER, POINTER :: Cols(:),Rows(:)
       REAL(KIND=dp), POINTER :: Values(:)
     
       n = A % NumberOfRows
       Rows   => A % Rows
       Cols   => A % Cols
       Values => A % Values
       
       x1 = x0

       DO k=1,Rounds
         DO i=1,n
           IF(f(i) > 0) CYCLE
           s = 0.0d0
           DO j=Rows(i),Rows(i+1)-1
             s = s + x1(Cols(j)) * Values(j)
           END DO
           x1(i) = x1(i) - s / A % Values(A % Diag(i))
         END DO

         DO i=n,1,-1
           IF(f(i) > 0) CYCLE
           s = 0.0d0
           DO j=Rows(i),Rows(i+1)-1
             s = s + x1(Cols(j)) * Values(j)
           END DO
           x1(i) = x1(i) - s / A % Values(A % Diag(i))
         END DO

         IF(k == Rounds-1) x0 = x1
       END DO
     END SUBROUTINE CR_SGS


!------------------------------------------------------------------------------
     SUBROUTINE CR_CSGS( n, A, rx0, rx1, f, Rounds)
!------------------------------------------------------------------------------
       TYPE(Matrix_t), POINTER :: A
       INTEGER :: n, Rounds, f(:)
       REAL(KIND=dp) :: rx0(:),rx1(:)

       COMPLEX(KIND=dp) :: x0(n/2),x1(n/2), s
       INTEGER :: i,j,k,j2,diag,l
       INTEGER, POINTER :: Cols(:),Rows(:)
       REAL(KIND=dp), POINTER :: Values(:)
     
       n = A % NumberOfRows
       Rows   => A % Rows
       Cols   => A % Cols
       Values => A % Values
              
       DO i=1,n/2
         x0(i) = DCMPLX( rx0(2*i-1), rx0(2*i) )
       END DO

       x1 = x0      

       l = ListGetInteger(Solver % Values,'MG Info Node',GotIt)


       DO k=1,Rounds
         DO i=1,n/2
           IF(f(2*i-1) > 0) CYCLE
           IF(f(2*i) > 0) PRINT *,'f(2*i-1) /= f(2*i)',i 

           s = 0.0d0

           ! Go only through the real part of matrix
           DO j=Rows(2*i-1),Rows(2*i)-1             
             j2 = j + Rows(2*i) - Rows(2*i-1)
             
             IF(i==l) print *,'i0',i,j2-j,(Cols(j)-1)/2+1,(Cols(j2)-1)/2+1

             IF(MOD(Cols(j),2) == 0) CYCLE
             s = s + x1((Cols(j)-1)/2+1) * DCMPLX( Values(j), Values(j2))
             IF(i == l) THEN
!               print *,'i',i,2*i-1,Cols(j),Cols(j2),(Cols(j)-1)/2+1
               PRINT *,'a',i,(Cols(j2)-1)/2+1,Values(j),Values(j2)
             END IF
           END DO
           j = A % Diag(2*i-1)
           j2 = j + Rows(2*i) - Rows(2*i-1)          
           x1(i) = x1(i) - s / DCMPLX( Values(j), Values(j2)) 

           IF(i == l) THEN
             PRINT *,'diag',i,j,j2,s,DCMPLX( Values(j), Values(j2))
           END IF
         END DO

         DO i=n/2,1,-1
           IF(f(2*i-1) > 0) CYCLE
           s = 0.0d0
           DO j=Rows(2*i-1),Rows(2*i)-1
             IF(MOD(Cols(j),2) == 0) CYCLE
             j2 = j + Rows(2*i) - Rows(2*i-1)
             s = s + x1((Cols(j)-1)/2+1) * DCMPLX( Values(j), Values(j2))
           END DO
           j = A % Diag(2*i-1)
           j2 = j + Rows(2*i) - Rows(2*i-1)          
           x1(i) = x1(i) - s / DCMPLX( Values(j), Values(j2)) 
         END DO

         IF(k == Rounds-1) x0 = x1
       END DO

       DO i=1,n/2
         rx0(2*i-1) =  REAL( x0(i) )
         rx0(2*i-0) =  AIMAG( x0(i) )
         rx1(2*i-1) =  REAL( x1(i) )
         rx1(2*i-0) =  AIMAG( x1(i) )
       END DO

     END SUBROUTINE CR_CSGS


!-------------------------------------------------------------------------------
  SUBROUTINE CRS_ProjectVector( PMatrix, u, v, Trans )
!-------------------------------------------------------------------------------
    TYPE(Matrix_t), POINTER :: PMatrix
    REAL(KIND=dp), POINTER :: u(:),v(:)
    LOGICAL, OPTIONAL :: Trans
!-------------------------------------------------------------------------------
    INTEGER :: i,j,k,l,n
    REAL(KIND=dp), POINTER :: Values(:)
    LOGICAL :: LTrans
    INTEGER, POINTER :: Rows(:), Cols(:)
!-------------------------------------------------------------------------------
    LTrans = .FALSE.
    IF ( PRESENT( Trans ) ) LTrans = Trans

    n = PMatrix % NumberOfRows
    Rows   => PMatrix % Rows
    Cols   => PMatrix % Cols
    Values => PMatrix % Values

    v = 0.0d0

    IF ( LTrans ) THEN
      DO i=1,n
        DO j=Rows(i),Rows(i+1)-1
          v(Cols(j)) = v(Cols(j)) + u(i) * Values(j)
        END DO
      END DO
    ELSE
      DO i=1,n
        DO j = Rows(i), Rows(i+1)-1
          v(i) = v(i) + u(Cols(j)) * Values(j)
        END DO
      END DO
    END IF
!-------------------------------------------------------------------------------
  END SUBROUTINE CRS_ProjectVector
!-------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE CRS_ProjectMatrix( A, P, Q, B, DOFs)
!------------------------------------------------------------------------------
!
!     Project matrix A to B: B = PAQ^T
!
!------------------------------------------------------------------------------
    TYPE(Matrix_t), POINTER :: A,P,Q,B
    INTEGER :: DOFs
!------------------------------------------------------------------------------
    INTEGER, POINTER :: L1(:), L2(:)
    REAL(KIND=dp) :: s
    REAL(KIND=dp), POINTER :: R1(:),R2(:)
    INTEGER :: i,j,k,l,NA,NB,N,k1,k2,k3,ni,nj,RDOF,CDOF
!------------------------------------------------------------------------------

    NA = A % NumberOfRows
    NB = B % NumberOfRows

!
!     Compute size for the work arrays:
!     ---------------------------------
    N = 0
    DO i=1, P % NumberOfRows
      N = MAX( N, P % Rows(i+1) - P % Rows(i) )
    END DO
    
    DO i=1, Q % NumberOfRows
      N = MAX( N, Q % Rows(i+1) - Q % Rows(i) )
    END DO

!
!     Allocate temporary workspace:
!     -----------------------------
    ALLOCATE( R1(N), R2(NA), L1(N), L2(N) )

!
!     Initialize:
!     -----------

    R1 = 0.0d0  ! P_i:
    R2 = 0.0d0  ! Q_j: ( = Q^T_:j )
    
    L1 = 0      ! holds column indices of P_i in A numbering
    L2 = 0      ! holds column indices of Q_j in A numbering
    
    B % Values = 0.0d0

!------------------------------------------------------------------------------
!
!     Compute the projection:
!     =======================
!
!        Loop over rows of B:
!        --------------------

    IF(DOFs == 1) THEN
      DO i=1,NB
!
!           Get i:th row of projector P: R1=P_i
!           -----------------------------------
        ni = 0   ! number of nonzeros in P_i
        DO k = P % Rows(i), P % Rows(i+1) - 1
          l = P % Cols(k) 
          IF ( l > 0 ) THEN
            ni = ni + 1
            L1(ni) = l
            R1(ni) = P % Values(k)
          END IF
        END DO
          
        IF ( ni <= 0 ) CYCLE
!
!           Loop over columns of row i of B:
!           --------------------------------
        DO j = B % Rows(i), B % Rows(i+1)-1
!
!              Get j:th row of projector Q: R2=Q_j
!              -----------------------------------
          nj = 0 ! number of nonzeros in Q_j
          k2 = B % Cols(j) 
          DO k = Q % Rows(k2), Q % Rows(k2+1)-1
            
            l = Q % Cols(k) 
            IF ( l > 0 ) THEN
              nj = nj + 1
              L2(nj) = l
              R2(l)  = Q % Values(k)
            END IF
          END DO
          
          IF ( nj <= 0 ) CYCLE
            !
!              s=A(Q_j)^T, only entries correspoding to
!              nonzeros in P_i actually computed, then
!              B_ij = DOT( P_i, A(Q_j)^T ):
!              ------------------------------------------
               
          DO k=1,ni
            
            k2 = L1(k)
            s = 0.0d0
            DO l = A % Rows(k2), A % Rows(k2+1)-1
              s = s + R2(A % Cols(l)) * A % Values(l)
            END DO
            B % Values(j) = B % Values(j) + s * R1(k)
          END DO
          
          R2(L2(1:nj)) = 0.0d0
        END DO
      END DO

    ELSE ! DOFs /= 1
!
!        Loop over rows of B:
!        --------------------
      DO i=1,NB/DOFs
!
!           Get i:th row of projector P: R1=P_i
!           -----------------------------------
        ni = 0   ! number of nonzeros in P_i
        DO k = P % Rows(i), P % Rows(i+1) - 1
          l = P % Cols(k) 
          IF ( l > 0 ) THEN
            ni = ni + 1
            L1(ni) = l
            R1(ni) = P % Values(k)
          END IF
        END DO
        
        IF ( ni <= 0 ) CYCLE
        
        DO RDOF = 1,DOFs
!
!              Loop over columns of row i of B:
!              --------------------------------
          k1 = DOFs*(i-1) + RDOF
          DO j = B % Rows(k1), B % Rows(k1+1)-1, DOFs
!
!                 Get j:th row of projector Q: R2=Q_j
!                 -----------------------------------
            nj = 0 ! number of nonzeros in Q_j
            k2 = (B % Cols(j)-1) / DOFs + 1 
            DO k = Q % Rows(k2), Q % Rows(k2+1)-1
              l = Q % Cols(k) 
              IF ( l > 0 ) THEN
                nj = nj + 1
                L2(nj)  = l
                DO CDOF=1,DOFs
                  R2(DOFs*(l-1)+CDOF) = Q % Values(k)
                END DO
              END IF
            END DO
            
            IF ( nj <= 0 ) CYCLE
            
            DO CDOF=0,DOFs-1
!
!                    s = A(Q_j)^T, only entries correspoding to
!                    nonzeros in P_i actually  computed, then
!                    B_ij = DOT( P_i, A(Q_j)^T ):
!                    ------------------------------------------
              DO k=1,ni
                k2 = DOFs * (L1(k)-1) + RDOF
                s = 0.0d0
                DO l = A % Rows(k2)+CDOF, A % Rows(k2+1)-1, DOFs
                  s = s + R2(A % Cols(l)) * A % Values(l)
                END DO
                IF((j+CDOF) > SIZE(B % Values)) PRINT *,'j',j,CDOF
                B % Values(j+CDOF) = B % Values(j+CDOF) + s * R1(k)
              END DO
              R2(DOFs*(L2(1:nj)-1)+CDOF+1) = 0.0d0
            END DO
          END DO
        END DO
      END DO
    END IF
         

    DEALLOCATE( R1, R2, L1, L2 )

!------------------------------------------------------------------------------
  END SUBROUTINE CRS_ProjectMatrix
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
     FUNCTION CRS_Transpose( A ) RESULT(B)
!------------------------------------------------------------------------------
!
!  Calculate transpose of A in CRS format: B = A^T
!
!------------------------------------------------------------------------------
       USE CRSMatrix
       IMPLICIT NONE
       
       TYPE(Matrix_t), POINTER :: A, B
       
       INTEGER, ALLOCATABLE :: Row(:)
       INTEGER :: NVals
       INTEGER :: i,j,k,istat
       
       B => AllocateMatrix()
       
       NVals = SIZE( A % Values )

       B % NumberOfRows = MAXVAL( A % Cols )

       ALLOCATE( B % Rows( B % NumberOfRows +1 ), B % Cols( NVals ), &
           B % Values( Nvals ), B % Diag( B % NumberOfRows ), STAT=istat )
       IF ( istat /= 0 )  CALL Fatal( 'CRS_Transpose', &
           'Memory allocation error.' )
       
       B % Diag = 0
       
       ALLOCATE( Row( B % NumberOfRows ) )
       Row = 0
       
       DO i = 1, NVals
         Row( A % Cols(i) ) = Row( A % Cols(i) ) + 1
       END DO
       
       B % Rows(1) = 1
       DO i = 1, B % NumberOfRows
         B % Rows(i+1) = B % Rows(i) + Row(i)
       END DO
       B % Cols = 0
       
       DO i = 1, B % NumberOfRows
         Row(i) = B % Rows(i)
       END DO
       
       DO i = 1, A % NumberOfRows
         DO j = A % Rows(i), A % Rows(i+1) - 1
           k = A % Cols(j)
           IF ( Row(k) < B % Rows(k+1) ) THEN 
             B % Cols( Row(k) ) = i
             B % Values( Row(k) ) = A % Values(j)
             Row(k) = Row(k) + 1
           ELSE
             WRITE( Message, * ) 'Trying to access non-existent column', i,k,j
             CALL Error( 'CRS_Transpose', Message )
             RETURN
           END IF
         END DO
       END DO

       DEALLOCATE( Row )

!------------------------------------------------------------------------------
     END FUNCTION CRS_Transpose
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    SUBROUTINE CRS_ProjectMatrixCreate( A, P, R, B, DOFs) 
!------------------------------------------------------------------------------
!
!     Project matrix A to B: B = PAR
!
!------------------------------------------------------------------------------
      TYPE(Matrix_t), POINTER :: A,P,R,B
      INTEGER :: DOFs
!------------------------------------------------------------------------------
      INTEGER, POINTER :: L1(:), L2(:)
      REAL(KIND=dp) :: s
      REAL(KIND=dp), POINTER :: R1(:),R2(:)
      INTEGER :: i,j,k,l,NA,NB,ci,cj,ck,cl,NoRow,i2,j2
      INTEGER :: TotalNonzeros, comp1, comp2
      LOGICAL :: AllocationsDone 
      INTEGER, ALLOCATABLE :: Row(:), Ind(:)
!------------------------------------------------------------------------------

      AllocationsDone = .FALSE.
      NA = A % NumberOfRows
      NB = P % NumberOfRows
      ALLOCATE( Row( NA ), Ind( NB ) )
 
      B => AllocateMatrix()      
      B % NumberOfRows = P % NumberOfRows * DOFs
      ALLOCATE( B % Rows( B % NumberOfRows + 1 ), &
          B % Diag( B % NumberOfRows ), &
          B % RHS( B % NumberOfRows ) )        
      B % RHS = 0.0d0
      B % Diag = 0
      B % Rows(1) = 1

      Row = 0
      Ind = 0
10    TotalNonzeros = 0

      IF(DOFs == 1) THEN
        DO i=1,P % NumberOfRows
          
          NoRow = 0
          DO j=P % Rows(i),P % Rows(i+1)-1          
            cj = P % Cols(j)
            
            DO k=A % Rows(cj), A % Rows(cj+1)-1
              ck = A % Cols(k) 
              
              DO l=R % Rows(ck), R % Rows(ck+1)-1
                cl = R % Cols(l)
                
                i2 = Row(cl)
                
                IF ( i2 == 0) THEN
                  NoRow = NoRow + 1
                  Ind(NoRow) = cl
                  i2 = B % Rows(i) + NoRow - 1                   
                  Row(cl) = i2
                  
                  IF(AllocationsDone) THEN
                    IF(i == cl) B % Diag(cl) = i2
                    B % Cols(i2) = cl                     
                    B % Values(i2) = P % Values(j) * A % Values(k) * R % Values(l)
                  END IF
                ELSE IF(AllocationsDone) THEN
                  j2 = B % Rows(i) + NoRow - 1
                  B % Values(i2) = B % Values(i2) + P % Values(j) * A % Values(k) * R % Values(l)
                END IF
              END DO
            END DO
          END DO
          
          DO j=1,NoRow
            Row(Ind(j)) = 0
          END DO
          
          B % Rows(i+1) = B % Rows(i) + NoRow
          TotalNonzeros  = TotalNonzeros + NoRow
        END DO
      ELSE  ! DOFs /= 1
        DO i=1,P % NumberOfRows
          DO comp1 = 1,DOFs
            
            NoRow = 0
            DO j=P % Rows(i),P % Rows(i+1)-1          
              cj = DOFs * (P % Cols(j)-1) + comp1
              
              DO k=A % Rows(cj), A % Rows(cj+1)-1
                ck = (A % Cols(k) - 1) / DOFs + 1
                
                DO l=R % Rows(ck), R % Rows(ck+1)-1
                  DO comp2 = 1, DOFs
                    cl = DOFs * (R % Cols(l)-1) + comp2
                    i2 = Row(cl)
                    
                    IF ( i2 == 0) THEN
                      NoRow = NoRow + 1
                      Ind(NoRow) = cl
                      i2 = B % Rows(DOFs*(i-1)+comp1) + NoRow - 1                   
                      Row(cl) = i2
                      
                      IF(AllocationsDone) THEN
                        IF(DOFs*(i-1) + comp1 == cl) B % diag(cl) = i2 
                        B % Cols(i2) = cl                     
                        B % Values(i2) = P % Values(j) * A % Values(k) * R % Values(l)
                      END IF
                    ELSE IF(AllocationsDone) THEN
                      j2 = B % Rows(DOFs*(i-1)+comp1) + NoRow - 1
                      B % Values(i2) = B % Values(i2) + P % Values(j) * A % Values(k) * R % Values(l)
                    END IF
                  END DO
                END DO
              END DO
            END DO
            
            DO j=1,NoRow
              Row(Ind(j)) = 0
            END DO

            B % Rows(DOFs*(i-1)+comp1+1) = B % Rows(DOFs*(i-1)+comp1) + NoRow
            TotalNonzeros  = TotalNonzeros + NoRow
          END DO
        END DO
      END IF

      IF(.NOT. AllocationsDone) THEN
        ALLOCATE( B % Cols( TotalNonzeros ), B % Values( TotalNonzeros ) )
        B % Cols = 0
        B % Values = 0.0d0
        AllocationsDone = .TRUE.
        GOTO 10 
      END IF

      DEALLOCATE( Row, Ind )
      
    END SUBROUTINE CRS_ProjectMatrixCreate


  SUBROUTINE SaveMatrix( A, FileName)
!------------------------------------------------------------------------------
    TYPE(Matrix_t) :: A
    CHARACTER(LEN=*) :: FileName

    INTEGER :: i,j,k

    OPEN (10, FILE=FileName) 

    DO i=1,A % NumberOfRows
      DO j=A % Rows(i),A % Rows(i+1)-1
        WRITE(10,*) i,A % Cols(j),A % Values(j)
      END DO
    END DO

    CLOSE(10)

  END SUBROUTINE SaveMatrix
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
   END SUBROUTINE AMGSolve
!------------------------------------------------------------------------------

END MODULE Multigrid
