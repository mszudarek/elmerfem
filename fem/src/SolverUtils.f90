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
! * Utilities for *Solver - routines
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
! *                       Date: 28 Sep 1998
! *
! *                Modified by:
! *
! *       Date of modification:
! *
! * $Log: SolverUtils.f90,v $
! * Revision 1.108  2005/04/19 08:53:48  jpr
! * Renamed module LUDecomposition as LinearAlgebra.
! *
! * Revision 1.107  2005/04/14 11:48:43  jpr
! * Removed (rest of the) sparse library interface.
! *
! * Revision 1.106  2005/04/14 11:27:58  jpr
! * *** empty log message ***
! *
! * Revision 1.105  2005/04/11 13:02:59  jpr
! * *** empty log message ***
! *
! * Revision 1.104  2005/04/04 06:18:31  jpr
! * *** empty log message ***
! *
! * Revision 1.103  2004/09/27 09:32:23  jpr
! * Removed some old, inactive code.
! *
! * Revision 1.102  2004/09/03 09:16:48  byckling
! * Added p elements
! *
! * Revision 1.96  2004/03/30 12:03:33  jpr
! * Added dirichlet condition setting to multidof variables.
! *
! * Revision 1.95  2004/03/26 10:17:00  jpr
! * Still on the periodic settings.
! *
! * Revision 1.94  2004/03/25 06:22:34  jpr
! * Modified periodic BC settings.
! *
! * Revision 1.92  2004/03/04 10:59:52  jpr
! * Removed pressure relaxation code from SolveSystem, this has been
! * moved to FlowSolve.
! *
! * Revision 1.90  2004/03/03 09:37:44  jpr
! * Removed zeroing of possibly previously computed solution field in
! * connection to eigen system solution.
! * Started log.
! *
! *
! * $Id: SolverUtils.f90,v 1.108 2005/04/19 08:53:48 jpr Exp $
! *****************************************************************************/

MODULE SolverUtils

   USE DirectSolve
   USE Multigrid
   USE IterSolve
   USE ElementUtils
   USE TimeIntegrate

   USE ParallelUtils
   USE ModelDescription
   USE MeshUtils
   USE SParIterSolve
   USE SParIterGlobals

   USE ParallelEigenSolve

   IMPLICIT NONE

CONTAINS

!------------------------------------------------------------------------------
   SUBROUTINE InitializeToZero( StiffMatrix, ForceVector )
DLLEXPORT InitializeToZero
!------------------------------------------------------------------------------
!******************************************************************************
! 
! Initialize matrix structure and vector to zero initial value
!
! TYPE(Matrix_t), POINTER :: StiffMatrix
!   INOUT: Matrix to be initialized
!
! REAL(KIND=dp) :: ForceVector(:)
!   INOUT: vector to be initialized
! 
!******************************************************************************
!------------------------------------------------------------------------------

     TYPE(Matrix_t), POINTER :: StiffMatrix
     REAL(KIND=dp) :: ForceVector(:)
!------------------------------------------------------------------------------

     SELECT CASE( StiffMatrix % Format )
       CASE( MATRIX_CRS )
         CALL CRS_ZeroMatrix( StiffMatrix )

       CASE( MATRIX_BAND,MATRIX_SBAND )
         CALL Band_ZeroMatrix( StiffMatrix )
     END SELECT

     ForceVector = 0.0d0
     IF ( ASSOCIATED( StiffMatrix % MassValues ) ) THEN
       StiffMatrix % MassValues(:) = 0.d0
     END IF

     IF ( ASSOCIATED( StiffMatrix % DampValues ) ) THEN
       StiffMatrix % DampValues(:) = 0.d0
     END IF

     IF ( ASSOCIATED( StiffMatrix % Force ) ) THEN
       StiffMatrix % Force(:,1) = 0.0d0
     END IF
!------------------------------------------------------------------------------
   END SUBROUTINE InitializeToZero
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   SUBROUTINE SetMatrixElement( StiffMatrix, i, j, Value )
DLLEXPORT SetMatrixElement
!------------------------------------------------------------------------------
     TYPE(Matrix_t), POINTER :: StiffMatrix
     INTEGER :: i,j
     REAL(KIND=dp) :: Value
!------------------------------------------------------------------------------

     SELECT CASE( StiffMatrix % Format )
       CASE( MATRIX_CRS )
         CALL CRS_SetMatrixElement( StiffMatrix, i, j, Value )

       CASE( MATRIX_BAND,MATRIX_SBAND )
         CALL Band_SetMatrixElement( StiffMatrix, i, j, Value )
     END SELECT
!------------------------------------------------------------------------------
   END SUBROUTINE SetMatrixElement
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   SUBROUTINE AddToMatrixElement( StiffMatrix, i, j,Value )
DLLEXPORT AddToMatrixElement
!------------------------------------------------------------------------------
     TYPE(Matrix_t), POINTER :: StiffMatrix
     INTEGER :: i,j
     REAL(KIND=dp) :: Value
!------------------------------------------------------------------------------

     SELECT CASE( StiffMatrix % Format )
       CASE( MATRIX_CRS )
         CALL CRS_AddToMatrixElement( StiffMatrix, i, j, Value )

       CASE( MATRIX_BAND,MATRIX_SBAND )
         CALL Band_AddToMatrixElement( StiffMatrix, i, j, Value )
     END SELECT
!------------------------------------------------------------------------------
   END SUBROUTINE AddToMatrixElement
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   SUBROUTINE ZeroRow( StiffMatrix, n )
DLLEXPORT ZeroRow
!------------------------------------------------------------------------------
     TYPE(Matrix_t), POINTER :: StiffMatrix
      INTEGER :: n
!------------------------------------------------------------------------------

     SELECT CASE( StiffMatrix % Format )
       CASE( MATRIX_CRS )
         CALL CRS_ZeroRow( StiffMatrix,n )

       CASE( MATRIX_BAND,MATRIX_SBAND )
         CALL Band_ZeroRow( StiffMatrix,n )
     END SELECT
!------------------------------------------------------------------------------
   END SUBROUTINE ZeroRow
!------------------------------------------------------------------------------

   

!------------------------------------------------------------------------------
   SUBROUTINE MatrixVectorMultiply( StiffMatrix,u,v )
DLLEXPORT MatrixVectorMultiply
!------------------------------------------------------------------------------
     TYPE(Matrix_t), POINTER :: StiffMatrix
     INTEGER :: n
     REAL(KIND=dp), DIMENSION(:) :: u,v
!------------------------------------------------------------------------------

     SELECT CASE( StiffMatrix % Format )
     CASE( MATRIX_CRS )
       CALL CRS_MatrixVectorMultiply( StiffMatrix,u,v )

     CASE( MATRIX_BAND,MATRIX_SBAND )
       CALL Band_MatrixVectorMultiply( StiffMatrix,u,v )
     END SELECT
!------------------------------------------------------------------------------
   END SUBROUTINE MatrixVectorMultiply
!------------------------------------------------------------------------------

   


!------------------------------------------------------------------------------
   SUBROUTINE Add1stOrderTime( MassMatrix, StiffMatrix,  &
          Force, dt, n, DOFs, NodeIndexes, Solver )
DLLEXPORT Add1stOrderTime
!------------------------------------------------------------------------------
!******************************************************************************
! 
!  For time dependent simulations add the time derivative coefficient terms
!  to the matrix containing other coefficients.
!
! REAL(KIND=dp) :: MassMatrix(:,:)
!   INPUT:
!
! REAL(KIND=dp) :: StiffMatrix(:,:)
!   INOUT:
!   
! REAL(KIND=dp) :: Force(:)
!   INOUT:
!   
! REAL(KIND=dp) :: dt
!   INPUT: Simulation timestep size
!
! INTEGER :: n
!   INPUT: number of element nodes
!
! INTEGER :: DOFs
!   INPUT: variable degrees of freedom
!
! TYPE(Solver_t), POINTER :: Solver
!   INPUT: solver parameter list (used to get some options for time integration)
! 
!******************************************************************************
!------------------------------------------------------------------------------
     TYPE(Solver_t) :: Solver

     REAL(KIND=dp) :: MassMatrix(:,:),StiffMatrix(:,:),Force(:),dt
     INTEGER :: n,DOFs
     INTEGER :: NodeIndexes(:)
!------------------------------------------------------------------------------
     LOGICAL :: GotIt
     INTEGER :: i,j,k,l,m,Order
     REAL(KIND=dp) :: s, t
     CHARACTER(LEN=MAX_NAME_LEN) :: Method
     REAL(KIND=dp), POINTER :: MassDiag(:)
     REAL(KIND=dp) :: PrevSol(DOFs*n,Solver % Order)
!------------------------------------------------------------------------------
     MassDiag => Solver % Matrix % MassValues

     IF ( Solver % Matrix % Lumped ) THEN
#ifndef OLD_LUMPING
       s = 0.d0
       t = 0.d0
       DO i=1,n*DOFs
         DO j=1,n*DOFs
           s = s + MassMatrix(i,j)
           IF (i /= j) THEN
             MassMatrix(i,j) = 0.d0
           END IF
         END DO
         t = t + MassMatrix(i,i)
       END DO

       DO i=1,n
         DO j=1,DOFs
           K = DOFs * (i-1) + j
           L = DOFs * (NodeIndexes(i)-1) + j
           IF ( t /= 0.d0 ) THEN
             MassMatrix(K,K) = MassMatrix(K,K) * s / t
           END IF
           MassDiag(L) = MassDiag(L) + MassMatrix(K,K)
         END DO
       END DO
#else
       DO i=1,n*DOFs
         s = 0.0d0
         DO j = 1,n*DOFs
           s = s + MassMatrix(i,j)
           MassMatrix(i,j) = 0.0d0
         END DO
         MassMatrix(i,i) = s
       END DO

       DO i=1,n
         DO j=1,DOFs
           K = DOFs * (i-1) + j
           L = DOFs * (NodeIndexes(i)-1) + j
           MassDiag(L) = MassDiag(L) + MassMatrix(K,K)
         END DO
       END DO
#endif
     END IF
!------------------------------------------------------------------------------
     Order = MIN(Solver % DoneTime, Solver % Order)

     DO i=1,n
       DO j=1,DOFs
         K = DOFs * (i-1) + j
         L = DOFs * (NodeIndexes(i)-1) + j
         DO m=1, Order
           PrevSol(K,m) = Solver % Variable % PrevValues(L,m)
         END DO
         Solver % Matrix % Force(L,1) = Solver % Matrix % Force(L,1) + Force(K)
       END DO
     END DO

!------------------------------------------------------------------------------
!PrevSol(:,Order) needed for BDF
     Method = ListGetString( Solver % Values, 'Timestepping Method', GotIt )

     SELECT CASE( Method )
     CASE( 'fs' ) 
        CALL FractionalStep( n*DOFs, dt, MassMatrix, StiffMatrix, Force, &
                   PrevSol(:,1), Solver % Beta, Solver )
     CASE('bdf')
       CALL BDFLocal( n*DOFs, dt, MassMatrix, StiffMatrix, Force, PrevSol, &
                         Order )
     CASE DEFAULT
           CALL NewmarkBeta( n*DOFs, dt, MassMatrix, StiffMatrix, Force, &
                         PrevSol(:,1), Solver % Beta )
     END SELECT
!------------------------------------------------------------------------------
   END SUBROUTINE Add1stOrderTime
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
   SUBROUTINE Add2ndOrderTime( MassMatrix, DampMatrix, StiffMatrix,  &
                Force, dt, n, DOFs, NodeIndexes, Solver )
DLLEXPORT Add2ndOrderTime
!------------------------------------------------------------------------------
!******************************************************************************
! 
!  For time dependent simulations add the time derivative coefficient terms
!  to the matrix containing other coefficients.
!
! REAL(KIND=dp) :: MassMatrix(:,:)
!   INPUT:
!
! REAL(KIND=dp) :: DampMatrix(:,:)
!   INPUT:
!
! REAL(KIND=dp) :: StiffMatrix(:,:)
!   INOUT:
!   
! REAL(KIND=dp) :: Force(:)
!   INOUT:
!   
! REAL(KIND=dp) :: dt
!   INPUT: Simulation timestep size
!
! INTEGER :: n
!   INPUT: number of element nodes
!
! INTEGER :: DOFs
!   INPUT: variable degrees of freedom
!
! TYPE(Solver_t) :: Solver
!   INPUT: solver parameter list (used to get some options for time integration)
! 
!******************************************************************************
!------------------------------------------------------------------------------
     TYPE(Solver_t) :: Solver

     REAL(KIND=dp) :: MassMatrix(:,:),DampMatrix(:,:), &
                  StiffMatrix(:,:),Force(:),dt
     INTEGER :: n,DOFs
     INTEGER :: NodeIndexes(:)
!------------------------------------------------------------------------------
     LOGICAL :: GotIt
     INTEGER :: i,j,k,l
     CHARACTER(LEN=MAX_NAME_LEN) :: Method
     REAL(KIND=dp) :: s,t
     REAL(KIND=dp) :: X(DOFs*n),V(DOFs*N),A(DOFs*N)
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
     IF ( Solver % Matrix % Lumped ) THEN
!------------------------------------------------------------------------------
#ifndef OLD_LUMPING
       s = 0.d0
       t = 0.d0
       DO i=1,n*DOFs
         DO j=1,n*DOFs
           s = s + MassMatrix(i,j)
           IF (i /= j) THEN
             MassMatrix(i,j) = 0.d0
           END IF
         END DO
         t = t + MassMatrix(i,i)
       END DO

       DO i=1,n
         DO j=1,DOFs
           K = DOFs * (i-1) + j
           IF ( t /= 0.d0 ) THEN
             MassMatrix(K,K) = MassMatrix(K,K) * s / t
           END IF
         END DO
       END DO

       s = 0.d0
       t = 0.d0
       DO i=1,n*DOFs
         DO j=1,n*DOFs
           s = s + DampMatrix(i,j)
           IF (i /= j) THEN
             DampMatrix(i,j) = 0.d0
           END IF
         END DO
         t = t + DampMatrix(i,i)
       END DO

       DO i=1,n
         DO j=1,DOFs
           K = DOFs * (i-1) + j
           IF ( t /= 0.d0 ) THEN
             DampMatrix(K,K) = DampMatrix(K,K) * s / t
           END IF
         END DO
       END DO
#else
!------------------------------------------------------------------------------
!      Lump the second order time derivative terms ...
!------------------------------------------------------------------------------
       DO i=1,n*DOFs
         s = 0.0D0
         DO j=1,n*DOFs
           s = s + MassMatrix(i,j)
           MassMatrix(i,j) = 0.0d0
         END DO
         MassMatrix(i,i) = s
       END DO

!------------------------------------------------------------------------------
!      ... and the first order terms.
!------------------------------------------------------------------------------
       DO i=1,n*DOFs
         s = 0.0D0
         DO j=1,n*DOFs
           s = s + DampMatrix(i,j)
           DampMatrix(i,j) = 0.0d0
         END DO
         DampMatrix(i,i) = s
       END DO
#endif
!------------------------------------------------------------------------------
     END IF
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
!    Get previous solution vectors and update current force
!-----------------------------------------------------------------------------
     DO i=1,n
       DO j=1,DOFs
         K = DOFs * (i-1) + j
         L = DOFs * (NodeIndexes(i)-1) + j
         SELECT CASE(Method)
         CASE DEFAULT
           X(K) = Solver % Variable % PrevValues(L,3)
           V(K) = Solver % Variable % PrevValues(L,4)
           A(K) = Solver % Variable % PrevValues(L,5)
         END SELECT
         Solver % Matrix % Force(L,1) = Solver % Matrix % Force(L,1) + Force(K)
       END DO
     END DO
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
     Method = ListGetString( Solver % Values, 'Timestepping Method', GotIt )
     SELECT CASE(Method)
     CASE DEFAULT
       CALL Bossak2ndOrder( n*DOFs, dt, MassMatrix, DampMatrix, StiffMatrix, &
              Force, X, V, A, Solver % Alpha )
     END SELECT
!------------------------------------------------------------------------------
   END SUBROUTINE Add2ndOrderTime
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
   SUBROUTINE UpdateTimeForce( StiffMatrix, &
           ForceVector, LocalForce, n, NDOFs, NodeIndexes )
DLLEXPORT UpdateTimeForce
!------------------------------------------------------------------------------
!******************************************************************************
! 
! TYPE(Matrix_t), POINTER :: StiffMatrix
!   INOUT: The global matrix
!
! REAL(KIND=dp) :: ForceVector(:)
!   INOUT: The global RHS vector
!
! REAL(KIND=dp) :: LocalForce(:)
!   INPUT: Element local force vector
!
! INTEGER :: n, NDOFs
!   INPUT :: number of nodes / element and number of DOFs / node
!
! INTEGER :: NodeIndexes(:)
!   INPUT: Element node to global node numbering mapping
! 
!******************************************************************************
!------------------------------------------------------------------------------
     TYPE(Matrix_t), POINTER :: StiffMatrix

     REAL(KIND=dp) :: LocalForce(:),ForceVector(:)

     INTEGER :: n, NDOFs, NodeIndexes(:)
!------------------------------------------------------------------------------
     INTEGER :: i,j,k
!------------------------------------------------------------------------------
!    Update rhs vector....
!------------------------------------------------------------------------------
     DO i=1,n
       DO j=1,NDOFs
         k = NDOFs * (NodeIndexes(i)-1) + j
         StiffMatrix % Force(k,1) = &
             StiffMatrix % Force(k,1) + LocalForce(NDOFs*(i-1)+j)
       END DO
     END DO

     LocalForce = 0.0d0
!------------------------------------------------------------------------------
   END SUBROUTINE UpdateTimeForce
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
   SUBROUTINE UpdateGlobalEquations( StiffMatrix, LocalStiffMatrix, &
           ForceVector, LocalForce, n, NDOFs, NodeIndexes )
DLLEXPORT UpdateGlobalEquations
!------------------------------------------------------------------------------
!******************************************************************************
! 
! Add element local matrices & vectors to global matrices and vectors
!
! TYPE(Matrix_t), POINTER :: StiffMatrix
!   INOUT: The global matrix
!
! REAL(KIND=dp) :: LocalStiffMatrix(:,:)
!   INPUT: Local matrix to be added to the global matrix
!
! REAL(KIND=dp) :: ForceVector(:)
!   INOUT: The global RHS vector
!
! REAL(KIND=dp) :: LocalForce(:)
!   INPUT: Element local force vector
!
! INTEGER :: n, NDOFs
!   INPUT :: number of nodes / element and number of DOFs / node
!
! INTEGER :: NodeIndexes(:)
!   INPUT: Element node to global node numbering mapping
! 
!******************************************************************************
!------------------------------------------------------------------------------
     TYPE(Matrix_t), POINTER :: StiffMatrix

     REAL(KIND=dp) :: LocalStiffMatrix(:,:),LocalForce(:),ForceVector(:)

     INTEGER :: n, NDOFs, NodeIndexes(:)
!------------------------------------------------------------------------------
     INTEGER :: i,j,k
!------------------------------------------------------------------------------
!    Update global matrix and rhs vector....
!------------------------------------------------------------------------------
     SELECT CASE( StiffMatrix % Format )
     CASE( MATRIX_CRS )
       CALL CRS_GlueLocalMatrix( StiffMatrix,n,NDOFs, NodeIndexes, &
                        LocalStiffMatrix )

     CASE( MATRIX_BAND,MATRIX_SBAND )
       CALL Band_GlueLocalMatrix( StiffMatrix,n,NDOFs, NodeIndexes, &
                        LocalStiffMatrix )
     END SELECT

     DO i=1,n
       DO j=1,NDOFs
         k = NDOFs * (NodeIndexes(i)-1) + j
         ForceVector(k) = ForceVector(k) + LocalForce(NDOFs*(i-1)+j)
       END DO
     END DO
!------------------------------------------------------------------------------
   END SUBROUTINE UpdateGlobalEquations
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
   SUBROUTINE UpdateMassMatrix( StiffMatrix, LocalMassMatrix, &
                  n, NDOFs, NodeIndexes )
DLLEXPORT UpdateMassMatrix
!------------------------------------------------------------------------------
!******************************************************************************
! 
! Add element local mass matrix to global mass matrix.
! 
! TYPE(Matrix_t), POINTER :: StiffMatrix
!   INOUT: The global matrix
!
! REAL(KIND=dp) :: LocalMassMatrix(:,:)
!   INPUT: Local matrix to be added to the global matrix
!
! INTEGER :: n, NDOFs
!   INPUT :: number of nodes / element and number of DOFs / node
!
! INTEGER :: NodeIndexes(:)
!   INPUT: Element node to global node numbering mapping
! 
!******************************************************************************
!------------------------------------------------------------------------------
     TYPE(Matrix_t), POINTER :: StiffMatrix

     REAL(KIND=dp) :: LocalMassMatrix(:,:)

     INTEGER :: n, NDOFs, NodeIndexes(:)
!------------------------------------------------------------------------------
     INTEGER :: i,j,k
     REAL(KIND=dp) :: s,t
     REAL(KIND=dp), POINTER  :: SaveValues(:)
!------------------------------------------------------------------------------
!    Update global matrix and rhs vector....
!------------------------------------------------------------------------------
     IF ( StiffMatrix % Lumped ) THEN
       s = 0.d0
       t = 0.d0
       DO i=1,n*NDOFs
          DO j=1,n*NDOFs
             s = s + LocalMassMatrix(i,j)
             IF (i /= j) LocalMassMatrix(i,j) = 0.0d0
          END DO
          t = t + LocalMassMatrix(i,i)
       END DO

        DO i=1,n*NDOFs
           LocalMassMatrix(i,i) = LocalMassMatrix(i,i) * s / t
        END DO
     END IF

     SaveValues => StiffMatrix % Values
     StiffMatrix % Values => StiffMatrix % MassValues 

     SELECT CASE( StiffMatrix % Format )
        CASE( MATRIX_CRS )
           CALL CRS_GlueLocalMatrix( StiffMatrix, &
                n, NDOFs, NodeIndexes, LocalMassMatrix )

       CASE( MATRIX_BAND,MATRIX_SBAND )
           CALL Band_GlueLocalMatrix( StiffMatrix, &
                n, NDOFs, NodeIndexes, LocalMassMatrix )
     END SELECT

     StiffMatrix % Values => SaveValues
!------------------------------------------------------------------------------
   END SUBROUTINE UpdateMassMatrix
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   SUBROUTINE SetDirichletBoundaries( Model, A, b, Name, DOF, NDOFs, Perm )
DLLEXPORT SetDirichletBoundaries
!------------------------------------------------------------------------------
!******************************************************************************
!
! Set dirichlet boundary condition for given dof
!
! TYPE(Model_t) :: Model
!   INPUT: the current model structure
!
! TYPE(Matrix_t), POINTER :: A
!   INOUT: The global matrix
!
! REAL(KIND=dp) :: b
!   INOUT: The global RHS vector
! 
! CHARACTER(LEN=*) :: Name
!   INPUT: name of the dof to be set
!
! INTEGER :: DOF, NDOFs
!   INPUT: The order number of the dof and the total number of DOFs for
!          this equation
!
! INTEGER :: Perm(:)
!   INPUT: The node reordering info, this has been generated at the
!          beginning of the simulation for bandwidth optimization
!******************************************************************************
!------------------------------------------------------------------------------
    TYPE(Model_t) :: Model
    TYPE(Matrix_t), POINTER :: A

    REAL(KIND=dp) :: b(:)

    CHARACTER(LEN=*) :: Name 
    INTEGER :: DOF, NDOFs, Perm(:)
!------------------------------------------------------------------------------

    TYPE(Element_t), POINTER :: Element
    INTEGER, POINTER :: NodeIndexes(:)
    INTEGER :: i,j,k,l,n,t,k1,k2
    LOGICAL :: GotIt, periodic
    REAL(KIND=dp), POINTER :: WorkA(:,:,:) => NULL()
    REAL(KIND=dp) :: Work(Model % MaxElementNodes),s

!------------------------------------------------------------------------------
     DO i=1,Model % NumberOfBCs
        CALL SetPeriodicBoundariesPass1( Model, A, b, Name, DOF, NDOFs, Perm, i )
     END DO

     DO i=1,Model % NumberOfBCs
        CALL SetPeriodicBoundariesPass2( Model, A, b, Name, DOF, NDOFs, Perm, i )
     END DO

     DO t = Model % NumberOfBulkElements + 1, &
         Model % NumberOfBulkElements + Model % NumberOfBoundaryElements

       Element => Model % Elements(t)
       Model % CurrentElement => Element
!------------------------------------------------------------------------------
       n = Element % Type % NumberOfNodes
       NodeIndexes => Element % NodeIndexes(1:n)

       DO i=1,Model % NumberOfBCs
         IF ( Element % BoundaryInfo % Constraint == Model % BCs(i) % Tag ) THEN
           IF ( DOF > 0 ) THEN
              Work(1:n) = ListGetReal( &
                   Model % BCs(i) % Values, Name, n, NodeIndexes, gotIt )
           ELSE
              CALL ListGetRealArray( &
                   Model % BCs(i) % Values, Name, WorkA, n, NodeIndexes, gotIt )
           END IF
           IF ( gotIt ) THEN
             DO j=1,n
               k = Perm(NodeIndexes(j))
               IF ( k > 0 ) THEN
                 IF ( DOF>0 ) THEN
                   k = NDOFs * (k-1) + DOF
                   IF ( A % FORMAT == MATRIX_SBAND ) THEN
                     CALL SBand_SetDirichlet( A,b,k,Work(j) )
                   ELSE IF ( A % Format == MATRIX_CRS .AND. A % Symmetric ) THEN
                     CALL CRS_SetSymmDirichlet( A,b,k,Work(j) )
                   ELSE
                     b(k) = Work(j)
                     CALL ZeroRow( A,k )
                     CALL SetMatrixElement( A,k,k,1.0d0 )
                   END IF
                 ELSE
                   DO l=1,MIN( NDOFs, SIZE(Worka,1) )
                      k1 = NDOFs * (k-1) + l
                      IF ( A % FORMAT == MATRIX_SBAND ) THEN
                        CALL SBand_SetDirichlet( A,b,k1,WorkA(l,1,j) )
                      ELSE IF ( A % Format == MATRIX_CRS .AND. A % Symmetric ) THEN
                        CALL CRS_SetSymmDirichlet( A,b,k1,WorkA(l,1,j) )
                      ELSE
                        b(k1) = WorkA(l,1,j)
                        CALL ZeroRow( A,k1 )
                        CALL SetMatrixElement( A,k1,k1,1.0d0 )
                      END IF
                    END DO
                 END IF
               END IF
             END DO
           END IF
         END IF
       END DO
     END DO
!------------------------------------------------------------------------------
   END SUBROUTINE SetDirichletBoundaries
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   SUBROUTINE SetPeriodicBoundariesPass1( Model, StiffMatrix, ForceVector, &
                      Name, DOF, NDOFs, Perm, This )
DLLEXPORT SetPeriodicBoundariesPass1
!------------------------------------------------------------------------------
!******************************************************************************
!
! Set dirichlet boundary condition for given dof
!
! TYPE(Model_t) :: Model
!   INPUT: the current model structure
!
! TYPE(Matrix_t), POINTER :: StiffMatrix
!   INOUT: The global matrix
!
! REAL(KIND=dp) :: ForceVector(:)
!   INOUT: The global RHS vector
! 
! CHARACTER(LEN=*) :: Name
!   INPUT: name of the dof to be set
!
! INTEGER :: DOF, NDOFs
!   INPUT: The order number of the dof and the total number of DOFs for
!          this equation
!
! INTEGER :: Perm(:)
!   INPUT: The node reordering info, this has been generated at the
!          beginning of the simulation for bandwidth optimization
!******************************************************************************
!------------------------------------------------------------------------------
    TYPE(Model_t) :: Model
    TYPE(Matrix_t), POINTER :: StiffMatrix

    REAL(KIND=dp) :: ForceVector(:)

    CHARACTER(LEN=*) :: Name
    INTEGER :: This, DOF, NDOFs, Perm(:)
!------------------------------------------------------------------------------

    INTEGER :: i,j,k,l,m,n,nn
    LOGICAL :: GotIt
    REAL(KIND=dp) :: Scale
    TYPE(Matrix_t), POINTER :: Projector
!------------------------------------------------------------------------------

    Scale = -1.0d0
    IF ( .NOT. ListGetLogical( Model % BCs(This) % Values, &
       'Periodic BC ' // TRIM(Name), GotIt ) ) THEN
       IF ( .NOT. ListGetLogical( Model % BCs(This) % Values, &
          'Anti Periodic BC ' // TRIM(Name), GotIt ) ) RETURN
       Scale = 1.0d0
    END IF

    Projector => Model % BCs(This) % PMatrix
    IF ( .NOT. ASSOCIATED(Projector) ) RETURN
!
!   Do the assembly of the projector:
!   ---------------------------------
!
    DO i=1,Projector % NumberOfRows
       k = Perm(Projector % InvPerm(i))
       IF ( k > 0 ) THEN
          k = NDOFs * (k-1) + DOF
          DO l=Projector % Rows(i),Projector % Rows(i+1)-1
             IF ( Projector % Cols(l) <= 0 ) CYCLE

             IF ( Projector % Values(l) > 1.0d-12 ) THEN
                m = Perm( Projector % Cols(l) )
                IF ( m > 0 ) THEN
                   m = NDOFs * (m-1) + DOF
                   DO nn=StiffMatrix % Rows(k),StiffMatrix % Rows(k+1)-1
                      CALL AddToMatrixElement( StiffMatrix, m, StiffMatrix % Cols(nn), &
                             Projector % Values(l) * StiffMatrix % Values(nn) )
                   END DO
                   ForceVector(m) = ForceVector(m) + Projector % Values(l) * ForceVector(k)
                END IF
             END IF
          END DO
       END IF
    END DO
!------------------------------------------------------------------------------
   END SUBROUTINE SetPeriodicBoundariesPass1
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   SUBROUTINE SetPeriodicBoundariesPass2( Model, StiffMatrix, ForceVector, &
                      Name, DOF, NDOFs, Perm, This )
DLLEXPORT SetPeriodicBoundariesPass2
!------------------------------------------------------------------------------
!******************************************************************************
!
! Set dirichlet boundary condition for given dof
!
! TYPE(Model_t) :: Model
!   INPUT: the current model structure
!
! TYPE(Matrix_t), POINTER :: StiffMatrix
!   INOUT: The global matrix
!
! REAL(KIND=dp) :: ForceVector(:)
!   INOUT: The global RHS vector
! 
! CHARACTER(LEN=*) :: Name
!   INPUT: name of the dof to be set
!
! INTEGER :: DOF, NDOFs
!   INPUT: The order number of the dof and the total number of DOFs for
!          this equation
!
! INTEGER :: Perm(:)
!   INPUT: The node reordering info, this has been generated at the
!          beginning of the simulation for bandwidth optimization
!******************************************************************************
!------------------------------------------------------------------------------
    TYPE(Model_t) :: Model
    TYPE(Matrix_t), POINTER :: StiffMatrix

    REAL(KIND=dp) :: ForceVector(:)

    CHARACTER(LEN=*) :: Name
    INTEGER :: This, DOF, NDOFs, Perm(:)
!------------------------------------------------------------------------------

    INTEGER :: i,j,k,l,m,n,nn
    LOGICAL :: GotIt
    REAL(KIND=dp) :: Scale
    TYPE(Matrix_t), POINTER :: Projector
!------------------------------------------------------------------------------

    Scale = -1.0d0
    IF ( .NOT. ListGetLogical( Model % BCs(This) % Values, &
       'Periodic BC ' // TRIM(Name), GotIt ) ) THEN
       IF ( .NOT. ListGetLogical( Model % BCs(This) % Values, &
          'Anti Periodic BC ' // TRIM(Name), GotIt ) ) RETURN
       Scale = 1.0d0
    END IF

    Projector => Model % BCs(This) % PMatrix
    IF ( .NOT. ASSOCIATED(Projector) ) RETURN
!
!   Do the assembly of the projector:
!   ---------------------------------
    DO i=1,Projector % NumberOfRows
       k = Perm(Projector % InvPerm(i))
       IF ( k > 0 ) THEN
          k = NDOFs * (k-1) + DOF
          CALL ZeroRow( StiffMatrix,k )
          DO l=Projector % Rows(i),Projector % Rows(i+1)-1
             IF ( Projector % Cols(l) <= 0 ) CYCLE

             m = Perm( Projector % Cols(l) )
             IF ( m > 0 ) THEN
                m = NDOFs * (m-1) + DOF
                IF ( Projector % Values(l) > 1.0d-12 ) THEN
                  CALL SetMatrixElement( StiffMatrix, k, m, Projector % Values(l) )
                END IF
             END IF
          END DO
          ForceVector(k) = 0.0d0
          CALL SetMatrixElement( StiffMatrix, k, k, Scale )
       END IF
    END DO
!------------------------------------------------------------------------------
   END SUBROUTINE SetPeriodicBoundariesPass2
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
   SUBROUTINE CheckNormalTangentialBoundary( Model, VariableName, &
     NumberOfBoundaryNodes, BoundaryReorder, BoundaryNormals,     &
        BoundaryTangent1, BoundaryTangent2, dim )
DLLEXPORT CheckNormalTangentialBoundary
!******************************************************************************
!
! Check if Normal / Tangential vector boundary conditions present and
! allocate space for normals, and if in 3D for two tangent direction
! vectors.
!
!******************************************************************************
!------------------------------------------------------------------------------
    TYPE(Model_t) :: Model

    CHARACTER(LEN=*) :: VariableName

    INTEGER, POINTER :: BoundaryReorder(:)
    INTEGER :: NumberOfBoundaryNodes,dim

    REAL(KIND=dp), POINTER :: BoundaryNormals(:,:),BoundaryTangent1(:,:), &
                       BoundaryTangent2(:,:)
!------------------------------------------------------------------------------

    TYPE(Element_t), POINTER :: CurrentElement
    INTEGER :: i,j,k,n,t
    LOGICAL :: GotIt
    INTEGER, POINTER :: NodeIndexes(:),Visited(:)
!------------------------------------------------------------------------------

    ALLOCATE( BoundaryReorder(Model % NumberOfNodes), &
             Visited(Model % NumberOfNodes) )

    NumberOfBoundaryNodes = 0
    Visited = 0
    BoundaryReorder = 0

!------------------------------------------------------------------------------
    DO t=Model % NumberOfBulkElements + 1, Model % NumberOfBulkElements + &
                  Model % NumberOfBoundaryElements

      CurrentElement => Model % Elements(t)
      IF ( CurrentElement % Type % ElementCode == 101 )  CYCLE

      n = CurrentElement % Type % NumberOfNodes
      NodeIndexes => CurrentElement % NodeIndexes

      DO i=1,Model % NumberOfBCs
        IF ( CurrentElement % BoundaryInfo % Constraint == &
                  Model % BCs(i) % Tag ) THEN
          IF ( ListGetLogical( Model % BCs(i) % Values, &
            VariableName, gotIt) ) THEN
            DO j=1,n
              k = NodeIndexes(j)
              IF ( Visited(k) == 0 ) THEN
                NumberOfBoundaryNodes = NumberOfBoundaryNodes + 1
                BoundaryReorder(NodeIndexes(j)) = NumberOfBoundaryNodes
              END IF
              Visited(k) = Visited(k) + 1
            END DO

          END IF
        END IF
      END DO
    END DO
!------------------------------------------------------------------------------

    DEALLOCATE( Visited )

    IF ( NumberOfBoundaryNodes == 0 ) THEN
      DEALLOCATE( BoundaryReorder )
      NULLIFY( BoundaryReorder, BoundaryNormals,BoundaryTangent1, &
                         BoundaryTangent2)
    ELSE
      ALLOCATE( BoundaryNormals(NumberOfBoundaryNodes,3)  )
      ALLOCATE( BoundaryTangent1(NumberOfBoundaryNodes,3) )
      ALLOCATE( BoundaryTangent2(NumberOfBoundaryNodes,3) )
      BoundaryNormals  = 0.0d0
      BoundaryTangent1 = 0.0d0
      BoundaryTangent2 = 0.0d0
    END IF

!------------------------------------------------------------------------------
  END SUBROUTINE CheckNormalTangentialBoundary
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   SUBROUTINE AverageBoundaryNormals( Model, VariableName,    &
     NumberOfBoundaryNodes, BoundaryReorder, BoundaryNormals, &
       BoundaryTangent1, BoundaryTangent2, dim )
DLLEXPORT AverageBoundaryNormals
!------------------------------------------------------------------------------
!******************************************************************************
!
! Average boundary normals for nodes
!
!******************************************************************************
!------------------------------------------------------------------------------
    TYPE(Model_t) :: Model

    INTEGER, POINTER :: BoundaryReorder(:)
    INTEGER :: NumberOfBoundaryNodes,DIM

    REAL(KIND=dp), POINTER :: BoundaryNormals(:,:),BoundaryTangent1(:,:), &
                       BoundaryTangent2(:,:)

    CHARACTER(LEN=*) :: VariableName
!------------------------------------------------------------------------------
    TYPE(Element_t), POINTER :: CurrentElement
    TYPE(Nodes_t) :: ElementNodes
    INTEGER :: i,j,k,n,t
    LOGICAL :: GotIt
    REAL(KIND=dp) :: s,Bu,Bv
    INTEGER, POINTER :: NodeIndexes(:)

    REAL(KIND=dp), TARGET :: x(Model % MaxElementNodes)
    REAL(KIND=dp), TARGET :: y(Model % MaxElementNodes)
    REAL(KIND=dp), TARGET :: z(Model % MaxElementNodes)
!------------------------------------------------------------------------------

    BoundaryNormals = 0.0d0

    ElementNodes % x => x
    ElementNodes % y => y
    ElementNodes % z => z

!------------------------------------------------------------------------------
!   Compute sum of elementwise normals for nodes on boundaries
!------------------------------------------------------------------------------
    DO t=Model % NumberOfBulkElements + 1, Model % NumberOfBulkElements + &
                  Model % NumberOfBoundaryElements

      CurrentElement => Model % Elements(t)
      IF ( CurrentElement % Type % ElementCode == 101 ) CYCLE

      n = CurrentElement % Type % NumberOfNodes
      NodeIndexes => CurrentElement % NodeIndexes

      ElementNodes % x(1:n) = Model % Nodes % x(NodeIndexes)
      ElementNodes % y(1:n) = Model % Nodes % y(NodeIndexes)
      ElementNodes % z(1:n) = Model % Nodes % z(NodeIndexes)

      DO i=1,Model % NumberOfBCs
        IF ( CurrentElement % BoundaryInfo % Constraint == &
                  Model % BCs(i) % Tag ) THEN

          IF ( ListGetLogical( Model % BCs(i) % Values, &
                 VariableName, gotIt) ) THEN

            DO j=1,CurrentElement % Type % NumberOfNodes
              k = BoundaryReorder( NodeIndexes(j) )
              Bu = CurrentElement % Type % NodeU(j)

              IF ( CurrentElement % Type % Dimension > 1 ) THEN
                Bv = CurrentElement % Type % NodeV(j)
              ELSE
                Bv = 0.0D0
              END IF
#if 1
              BoundaryNormals(k,:) = BoundaryNormals(k,:) + &
                  NormalVector( CurrentElement,ElementNodes,Bu,Bv,.TRUE. )
#else
              BoundaryNormals(k,:) = &
                  NormalVector( CurrentElement,ElementNodes,Bu,Bv,.TRUE. )
#endif
            END DO
          END IF
        END IF
      END DO
    END DO
!------------------------------------------------------------------------------
!   normalize 
!------------------------------------------------------------------------------
    DO i=1,Model % NumberOfNodes
      k = BoundaryReorder(i) 
      IF ( k > 0 ) THEN
        s = SQRT( SUM( BoundaryNormals(k,:)**2 ) )

        IF ( s /= 0.0D0 ) THEN
          BoundaryNormals(k,:) = BoundaryNormals(k,:) / s
        END IF

        IF ( CoordinateSystemDimension() > 2 ) THEN
          CALL TangentDirections( BoundaryNormals(k,:),  &
              BoundaryTangent1(k,:), BoundaryTangent2(k,:) )
        END IF
      END IF
    END DO
!------------------------------------------------------------------------------
  END SUBROUTINE AverageBoundaryNormals
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE InitializeTimestep( Solver )
DLLEXPORT InitializeTimestep
!------------------------------------------------------------------------------
!******************************************************************************
!
! Rotate previous force and solution vectors
!
! TYPE(Solver_t) :: Solver
!   INPUT:
!
!******************************************************************************
!------------------------------------------------------------------------------
     TYPE(Solver_t) :: Solver
!------------------------------------------------------------------------------
     CHARACTER(LEN=MAX_NAME_LEN) :: Method
     LOGICAL :: GotIt
     INTEGER :: i, Order,ndofs
     REAL(KIND=dp), POINTER :: Work(:)

!------------------------------------------------------------------------------
     Solver % DoneTime = Solver % DoneTime + 1
!------------------------------------------------------------------------------

     IF ( .NOT. ASSOCIATED( Solver % Matrix ) .OR. &
          .NOT. ASSOCIATED( Solver % Variable % Values ) ) RETURN

     IF ( Solver % TimeOrder <= 0 ) RETURN

!------------------------------------------------------------------------------

     Method = ListGetString( Solver % Values, 'Timestepping Method', GotIt )
    
     IF ( .NOT.GotIt ) THEN

        Solver % Beta = ListGetConstReal( Solver % Values, 'Newmark Beta', GotIt )
        IF ( .NOT. GotIt ) THEN
           Solver % Beta = ListGetConstReal( CurrentModel % Simulation, 'Newmark Beta', GotIt )
       END IF

       IF ( .NOT.GotIt ) THEN
         CALL Warn( 'InitializeTimestep', &
               'Timestepping method defaulted to IMPLICIT EULER' )

         Solver % Beta = 1.0D0
         Method = 'implicit euler'
       END IF

     ELSE

       SELECT CASE( Method )
         CASE('implicit euler')
           Solver % Beta = 1.0d0

         CASE('explicit euler')
           Solver % Beta = 0.0d0

         CASE('runge-kutta')
           Solver % Beta = 0.0d0

         CASE('crank-nicolson')
           Solver % Beta = 0.5d0

         CASE('fs')
           Solver % Beta = 0.5d0

         CASE('newmark')
           Solver % Beta = ListGetConstReal( Solver % Values, 'Newmark Beta', GotIt )
           IF ( .NOT. GotIt ) THEN
              Solver % Beta = ListGetConstReal( CurrentModel % Simulation, &
                              'Newmark Beta', GotIt )
           END IF

           IF ( Solver % Beta<0 .OR. Solver % Beta>1 ) THEN
             WRITE( Message, * ) 'Invalid value of Beta ', Solver % Beta
             CALL Warn( 'InitializeTimestep', Message )
           END IF

         CASE('bdf')
           IF ( Solver % Order < 1 .OR. Solver % Order > 5  ) THEN
             WRITE( Message, * ) 'Invalid order BDF ',  Solver % Order
             CALL Fatal( 'InitializeTimestep', Message )
           END IF

         CASE DEFAULT 
           WRITE( Message, * ) 'Unknown timestepping method: ',Method
           CALL Fatal( 'InitializeTimestep', Message )
       END SELECT

     END IF

     ndofs = Solver % Matrix % NumberOfRows

     IF ( Method /= 'bdf' .OR. Solver % TimeOrder > 1 ) THEN
       IF ( Solver % DoneTime == 1 .AND. Solver % Beta /= 0.0d0 ) THEN
         Solver % Beta = 1.0d0
       END IF
 
       SELECT CASE( Solver % TimeOrder )
         CASE(1)
           Order = MIN(Solver % DoneTime, Solver % Order)
           DO i=Order, 2, -1
             Solver % Variable % PrevValues(:,i) = &
                   Solver % Variable % PrevValues(:,i-1)
           END DO
           Solver % Variable % PrevValues(:,1) = Solver % Variable % Values
           Solver % Matrix % Force(:,2) = Solver % Matrix % Force(:,1)

         CASE(2)
           SELECT CASE(Method)
           CASE DEFAULT
             Solver % Alpha = ListGetConstReal( Solver % Values, &
                        'Bossak Alpha', GotIt )
             IF ( .NOT. GotIt ) THEN
                 Solver % Alpha = ListGetConstReal( CurrentModel % Simulation, &
                            'Bossak Alpha', GotIt )
             END IF
             IF ( .NOT. GotIt ) Solver % Alpha = -0.05d0

             Solver % Variable % PrevValues(:,3) = &
                                 Solver % Variable % Values
             Solver % Variable % PrevValues(:,4) = &
                        Solver % Variable % PrevValues(:,1)
             Solver % Variable % PrevValues(:,5) = &
                        Solver % Variable % PrevValues(:,2)
           END SELECT
       END SELECT
     ELSE
       Order = MIN(Solver % DoneTime, Solver % Order)
       DO i=Order, 2, -1
         Solver % Variable % PrevValues(:,i) = &
               Solver % Variable % PrevValues(:,i-1)
       END DO
       Solver % Variable % PrevValues(:,1) = Solver % Variable % Values
     END IF


!------------------------------------------------------------------------------
  END SUBROUTINE InitializeTimestep
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
  SUBROUTINE FinishAssembly( Solver, ForceVector )
DLLEXPORT FinishAssembly
!------------------------------------------------------------------------------
!******************************************************************************
!
! Update force vector AFTER ALL OTHER ASSEMBLY STEPS BUT BEFORE SETTING
! DIRICHLET CONDITIONS. Required only for time dependent simulations..
!
! TYPE(Solver_t) :: Solver
!   INPUT:
!
! REAL(KIND=dp) :: ForceVector(:)
!   INOUT:
!
!******************************************************************************
!------------------------------------------------------------------------------
    TYPE(Solver_t) :: Solver
    REAL(KIND=dp) :: ForceVector(:)
    REAL(KIND=dp), POINTER :: MassDiag(:)
    CHARACTER(LEN=MAX_NAME_LEN) :: Method, Simulation
    INTEGER :: Order
    LOGICAL :: Transient
!------------------------------------------------------------------------------

    MassDiag => Solver % Matrix % MassValues
    Simulation = ListGetString( CurrentModel % Simulation, 'Simulation Type' )

    IF ( Simulation == 'transient' ) THEN
      Method = ListGetString( Solver % Values, 'Timestepping Method' )

      Order = MIN(Solver % DoneTime, Solver % Order)

      IF ( Order <= 0 ) RETURN

      IF ( Method /= 'bdf' .OR. Solver % TimeOrder > 1 ) THEN
        SELECT CASE( Solver % TimeOrder )
          CASE(1)
            IF ( Solver % Beta == 0.0d0 ) THEN
               ForceVector = ForceVector + Solver % Matrix % Force(:,1) 
            ELSE
               ForceVector = ForceVector + Solver % Beta * &
                 Solver % Matrix % Force(:,1) + &
                    ( 1 - Solver % Beta ) * Solver % Matrix % Force(:,2)
            END IF

          CASE(2)
            SELECT CASE(Method)
            CASE DEFAULT
              ForceVector = ForceVector + Solver % Matrix % Force(:,1)
            END SELECT
          END SELECT
      ELSE
        SELECT CASE( Order)
          CASE(1)
            ForceVector = ForceVector + Solver % Matrix % Force(:,1)
          CASE(2)
            ForceVector = ForceVector + (2.d0/3.d0)*Solver % Matrix % Force(:,1)
          CASE(3)
            ForceVector = ForceVector + (6.d0/11.d0)*Solver % Matrix % Force(:,1)
          CASE(4)
            ForceVector = ForceVector + (12.d0/25.d0)*Solver % Matrix % Force(:,1)
          CASE(5)
            ForceVector = ForceVector + (60.d0/137.d0)*Solver % Matrix % Force(:,1)
          CASE DEFAULT
            WRITE( Message, * ) 'Invalid order BDF', Order
            CALL Fatal( 'FinishAssembly', Message )
        END SELECT
      END IF
    END IF
!------------------------------------------------------------------------------
  END SUBROUTINE FinishAssembly
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  RECURSIVE SUBROUTINE InvalidateVariable( TopMesh,PrimaryMesh,Name )
DLLEXPORT InvalidateVariable
!------------------------------------------------------------------------------
    CHARACTER(LEN=*) :: Name
    TYPE(Mesh_t),  POINTER :: TopMesh,PrimaryMesh
!------------------------------------------------------------------------------
    CHARACTER(LEN=MAX_NAME_LEN) :: tmpname
    INTEGER :: i
    TYPE(Mesh_t), POINTER :: Mesh
    TYPE(Variable_t), POINTER :: Var,Var1
!------------------------------------------------------------------------------
    Mesh => TopMesh

    DO WHILE( ASSOCIATED(Mesh) )
      IF ( .NOT.ASSOCIATED( PrimaryMesh, Mesh) ) THEN
        Var => VariableGet( Mesh % Variables, Name, .TRUE.)
        IF ( ASSOCIATED( Var ) ) THEN
          Var % Valid = .FALSE.
          Var % PrimaryMesh => PrimaryMesh
          IF ( Var % DOFs > 1 ) THEN
            IF ( Var % Name == 'flow solution' ) THEN
              Var1 => VariableGet( Mesh % Variables, 'Velocity 1', .TRUE.)
              IF ( ASSOCIATED( Var1 ) ) THEN
                 Var1 % Valid = .FALSE.
                 Var1 % PrimaryMesh => PrimaryMesh
              END IF
              Var1 => VariableGet( Mesh % Variables, 'Velocity 2', .TRUE.)
              IF ( ASSOCIATED( Var1 ) ) THEN
                 Var1 % Valid = .FALSE.
                 Var1 % PrimaryMesh => PrimaryMesh
              END IF
              Var1 => VariableGet( Mesh % Variables, 'Velocity 3', .TRUE.)
              IF ( ASSOCIATED( Var1 ) ) THEN
                 Var1 % Valid = .FALSE.
                 Var1 % PrimaryMesh => PrimaryMesh
              END IF
              Var1 => VariableGet( Mesh % Variables, 'Pressure', .TRUE.)
              IF ( ASSOCIATED( Var1 ) ) THEN
                 Var1 % Valid = .FALSE.
                 Var1 % PrimaryMesh => PrimaryMesh
              END IF
              Var1 => VariableGet( Mesh % Variables, 'Surface', .TRUE.)
              IF ( ASSOCIATED( Var1 ) ) THEN
                 Var1 % Valid = .FALSE.
                 Var1 % PrimaryMesh => PrimaryMesh
              END IF
            ELSE
              DO i=1,Var % DOFs
                tmpname = ComponentName( Name, i )
                Var1 => VariableGet( Mesh % Variables, tmpname, .TRUE. )
                IF ( ASSOCIATED( Var1 ) ) THEN
                   Var1 % Valid = .FALSE.
                   Var1 % PrimaryMesh => PrimaryMesh
                END IF
              END DO
            END IF
          END IF
        END IF
      END IF
!     CALL InvalidateVariable( Mesh % Child, PrimaryMesh, Name )
      Mesh => Mesh % Next
    END DO 
!------------------------------------------------------------------------------
  END SUBROUTINE InvalidateVariable
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  RECURSIVE SUBROUTINE SolveLinearSystem( StiffMatrix, ForceVector, &
                  Solution, Norm, DOFs, Solver )
DLLEXPORT SolveLinearSystem
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: ForceVector(:), Solution(:), Norm
    TYPE(Matrix_t), POINTER :: StiffMatrix
    INTEGER :: DOFs
    TYPE(Solver_t), TARGET :: Solver
!------------------------------------------------------------------------------
    TYPE(Variable_t), POINTER :: Var
    TYPE(Mesh_t), POINTER :: Mesh
    LOGICAL :: Relax,GotIt, ScaleSystem, EigenAnalysis
    INTEGER :: n,i,j,k,l,istat
    TYPE(Solver_t), POINTER :: PSolver
    CHARACTER(LEN=MAX_NAME_LEN) :: Method, ProcName
    INTEGER(KIND=AddrInt) :: Proc
    REAL(KIND=dp), ALLOCATABLE :: PSolution(:), Diag(:)
    REAL(KIND=dp) :: s,Relaxation,Beta,Gamma,DiagReal,DiagImag
!------------------------------------------------------------------------------
    n = StiffMatrix % NumberOfRows

    IF ( Solver % Matrix % Lumped .AND. Solver % TimeOrder == 1 ) THEN
      Method = ListGetString( Solver % Values, 'Timestepping Method', GotIt)
      IF (  Method == 'runge-kutta' .OR. Method == 'explicit euler' ) THEN
         DO i=1,n
            IF ( ABS( StiffMatrix % Values(StiffMatrix % Diag(i)) ) > 0.0d0 ) THEN
              Solution(i) = ForceVector(i) / StiffMatrix % Values(StiffMatrix % Diag(i))
            END IF
          END DO
         RETURN
      END IF
    END IF

    ScaleSystem = ListGetLogical( Solver % Values, 'Linear System Scaling', GotIt )
    IF ( .NOT. GotIt  ) ScaleSystem = .TRUE.

!   Cant use scaling in parallel:
!   --------------------------
    IF ( ParEnv % PEs > 1 ) ScaleSystem = .FALSE.
scalesystem = .false.

    IF ( ScaleSystem ) THEN
!
!     Scale system Ax = b as:
!       (DAD)y = Db, where D = 1/SQRT(Diag(A)), and y = D^-1 x
!     --------------------------------------------------------
      ALLOCATE( Diag(n) )
      IF ( ParEnv % PEs <= 1 ) THEN

         IF ( Solver % Matrix % Complex ) THEN
            DO i=1,n,2
              j = StiffMatrix % Diag(i)
              DiagReal  =  StiffMatrix % Values(j)
              DiagImag  = -StiffMatrix % Values(j+1)
              IF ( ABS(DCMPLX(DiagReal,DiagImag)) > 0.0d0 ) THEN
                Diag(i)   = 1.0d0 / SQRT( ABS( DCMPLX(DiagReal,DiagImag) ) )
                Diag(i+1) = 1.0d0 / SQRT( ABS( DCMPLX(DiagReal,DiagImag) ) )
              ELSE
                Diag(i)   = 1.0d0
                Diag(i+1) = 1.0d0
              END IF
            END DO
         ELSE
            DO i=1,n
              IF ( ABS( StiffMatrix % Values(StiffMatrix % Diag(i)) ) > 0.0d0 ) THEN
                 Diag(i) = 1.0d0 / SQRT( ABS(StiffMatrix % Values(StiffMatrix % Diag(i))) )
              ELSE
                Diag(i) = 1.0d0
              END IF
            END DO
         END IF

         DO i=1,n
            DO j=StiffMatrix % Rows(i), StiffMatrix % Rows(i+1)-1
               StiffMatrix % Values(j) = StiffMatrix % Values(j) * &
                 ( Diag(i) * Diag(StiffMatrix % Cols(j)) )
            END DO
         END DO

         ForceVector(1:n) =  ForceVector(1:n) * Diag(1:n)

         IF ( ASSOCIATED( StiffMatrix % MassValues ) ) THEN
            IF (SIZE(StiffMatrix % Values)==SIZE(StiffMatrix % MassValues)) THEN
               DO i=1,n
                  DO j=StiffMatrix % Rows(i), StiffMatrix % Rows(i+1)-1
                     StiffMatrix % MassValues(j) = StiffMatrix % MassValues(j) * &
                           ( Diag(i) * Diag(StiffMatrix % Cols(j)) )
                  END DO
               END DO
            END IF
         END IF

         IF ( ASSOCIATED( StiffMatrix % DampValues ) ) THEN
            IF (SIZE(StiffMatrix % Values)==SIZE(StiffMatrix % DampValues)) THEN
               DO i=1,n
                  DO j=StiffMatrix % Rows(i), StiffMatrix % Rows(i+1)-1
                     StiffMatrix % DampValues(j) = StiffMatrix % DampValues(j) * &
                           ( Diag(i) * Diag(StiffMatrix % Cols(j)) )
                  END DO
               END DO
            END IF
         END IF
      ELSE
         Diag = 1.0d0
      END IF
    END IF
    IF ( Solver % MultiGridLevel == -1  ) RETURN

!------------------------------------------------------------------------------
!   If solving eigensystem go there:
!   --------------------------------
    EigenAnalysis = Solver % NOFEigenValues > 0 .AND. &
          ListGetLogical( Solver % Values, 'Eigen Analysis',GotIt )

    IF ( EigenAnalysis ) THEN
       CALL SolveEigenSystem( &
           StiffMatrix, Solver %  NOFEigenValues, &
           Solver % Variable % EigenValues,       &
           Solver % Variable % EigenVectors, Solver )
   
       IF ( ScaleSystem ) THEN
         DO i=1,Solver % NOFEigenValues
!
!           Solve x:  INV(D)x = y
!           --------------------------
            IF ( Solver % Matrix % Complex ) THEN
               Solver % Variable % EigenVectors(i,1:n/2) = &
                   Solver % Variable % EigenVectors(i,1:n/2) * Diag(1:n:2)
            ELSE
               Solver % Variable % EigenVectors(i,1:n) = &
                       Solver % Variable % EigenVectors(i,1:n) * Diag(1:n)
            END IF
         END DO
! 
!         Scale the system back to original:
!         ----------------------------------
         DO i=1,n
            DO j=StiffMatrix % Rows(i), StiffMatrix % Rows(i+1)-1
               StiffMatrix % Values(j) = StiffMatrix % Values(j) / &
                 ( Diag(i) * Diag(StiffMatrix % Cols(j)) )
            END DO
         END DO

         ForceVector(1:n) =  ForceVector(1:n) / Diag(1:n)

         IF ( ASSOCIATED( StiffMatrix % MassValues ) ) THEN
            IF (SIZE(StiffMatrix % Values)==SIZE(StiffMatrix % MassValues)) THEN
               DO i=1,n
                  DO j=StiffMatrix % Rows(i), StiffMatrix % Rows(i+1)-1
                     StiffMatrix % MassValues(j) = StiffMatrix % MassValues(j) / &
                           ( Diag(i) * Diag(StiffMatrix % Cols(j)) )
                  END DO
               END DO
            END IF
         END IF

         IF ( ASSOCIATED( StiffMatrix % DampValues ) ) THEN
            IF (SIZE(StiffMatrix % Values)==SIZE(StiffMatrix % DampValues)) THEN
               DO i=1,n
                  DO j=StiffMatrix % Rows(i), StiffMatrix % Rows(i+1)-1
                     StiffMatrix % DampValues(j) = StiffMatrix % DampValues(j) / &
                           ( Diag(i) * Diag(StiffMatrix % Cols(j)) )
                  END DO
               END DO
            END IF
         END IF

         DEALLOCATE( Diag )
       END IF

       Norm = SQRT( SUM( Solution(1:n)**2 ) / n )
       Solver % Variable % Norm = Norm

       CALL InvalidateVariable( CurrentModel % Meshes, Solver % Mesh, &
                       Solver % Variable % Name )
       RETURN
    END IF

!------------------------------------------------------------------------------
    Relaxation = ListGetConstReal( Solver % Values, &
      'Nonlinear System Relaxation Factor', Relax )

    Relax = Relax .AND. (Relaxation /= 1.0d0)

    IF ( Relax  ) THEN
      ALLOCATE( PSolution(n), STAT=istat ) 
      IF ( istat /= 0 ) THEN
        CALL Fatal( 'SolveSystem', 'Memory allocation error.' )
      END IF
      PSolution = Solution(1:n)
    END IF
!------------------------------------------------------------------------------
! 
!   Convert initial value to the scaled system:
!   -------------------------------------------
    IF ( ScaleSystem ) Solution(1:n) = Solution(1:n) / Diag(1:n)

    IF ( ParEnv % PEs <= 1 ) THEN
       IF ( ALL( ForceVector(1:n) == 0.0d0 ) ) THEN
          Solution = 0.0d0
       ELSE
          IF ( Solver % MultiGridSolver ) THEN
              PSolver => Solver
              CALL MultiGridSolve( StiffMatrix, Solution, ForceVector, &
                      DOFs, PSolver, Solver % MultiGridLevel )
          ELSE IF ( ListGetString( Solver % Values, &
                  'Linear System Solver', GotIt ) == 'iterative' ) THEN
             CALL IterSolver( StiffMatrix, Solution, ForceVector, Solver )
          ELSE
             CALL DirectSolver( StiffMatrix, Solution, ForceVector, Solver )
          END IF
       END IF
       

       IF ( ScaleSystem ) THEN
! 
!         Solve x:  INV(D)x = y
!         ----------------------
          Solution(1:n) = Solution(1:n) * Diag(1:n)

! 
!         Scale the system back to original:
!         ----------------------------------
          DO i=1,n
             DO j=StiffMatrix % Rows(i), StiffMatrix % Rows(i+1)-1
                StiffMatrix % Values(j) = StiffMatrix % Values(j) / &
                  ( Diag(i) * Diag(StiffMatrix % Cols(j)) )
             END DO
          END DO

          ForceVector(1:n) =  ForceVector(1:n) / Diag(1:n)

          IF ( ASSOCIATED( StiffMatrix % MassValues ) ) THEN
             IF (SIZE(StiffMatrix % Values)==SIZE(StiffMatrix % MassValues)) THEN
                DO i=1,n
                   DO j=StiffMatrix % Rows(i), StiffMatrix % Rows(i+1)-1
                      StiffMatrix % MassValues(j) = StiffMatrix % MassValues(j) / &
                            ( Diag(i) * Diag(StiffMatrix % Cols(j)) )
                   END DO
                END DO
             END IF
          END IF

          IF ( ASSOCIATED( StiffMatrix % DampValues ) ) THEN
             IF (SIZE(StiffMatrix % Values)==SIZE(StiffMatrix % DampValues)) THEN
                DO i=1,n
                   DO j=StiffMatrix % Rows(i), StiffMatrix % Rows(i+1)-1
                      StiffMatrix % DampValues(j) = StiffMatrix % DampValues(j) / &
                            ( Diag(i) * Diag(StiffMatrix % Cols(j)) )
                   END DO
                END DO
             END IF
          END IF

          DEALLOCATE( Diag )
       END IF

       IF ( Relax ) THEN
          Solution(1:n) = (1-Relaxation)*PSolution + Relaxation*Solution(1:n)
       END IF
       Norm = SQRT( SUM( Solution(1:n)**2 ) / n )
!------------------------------------------------------------------------------
    ELSE
       IF ( Solver % MultiGridSolver ) THEN
          PSolver => Solver
          CALL MultiGridSolve( StiffMatrix, Solution, ForceVector, &
                 DOFs, PSolver, Solver % MultiGridLevel )
       ELSE
          CALL SParIterSolver( StiffMatrix, Solver % Mesh % Nodes, DOFs, &
            Solution, ForceVector, Solver, StiffMatrix % ParMatrix )
       END IF
!------------------------------------------------------------------------------
       IF ( Relax ) THEN
          Solution(1:n) = (1-Relaxation)*PSolution + Relaxation*Solution(1:n)
       END IF
!------------------------------------------------------------------------------
       Norm = ParallelNorm( n,Solution )
    END IF
!------------------------------------------------------------------------------
    IF ( ALLOCATED(PSolution) ) DEALLOCATE( PSolution )
!------------------------------------------------------------------------------
  END SUBROUTINE SolveLinearSystem
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  RECURSIVE SUBROUTINE SolveSystem( StiffMatrix,ParMatrix,ForceVector, &
                    Solution,Norm,DOFs,Solver )
DLLEXPORT SolveSystem
!------------------------------------------------------------------------------
!******************************************************************************
!
! Solve a linear system
!
! TYPE(Matrix_t), POINTER :: StiffMatrix
!   INPUT: The coefficient matrix
!
! TYPE(ParIterSolverGlobalD_t), POINTER :: ParMatrix
!   INPUT: holds info for parallel solver, if not executing in parallel
!          this is just a dummy.
!
! REAL(KIND=dp) :: ForceVector(:)
!   INPUT: The RHS vector
!
! REAL(KIND=dp) :: Solution(:)
!   INOUT: Previous solution on entry, new solution on exit (hopefully)
!
! REAL(KIND=dp) :: Norm
!   OUTPUT: 2-Norm of solution
!
! INTEGER :: DOFs
!   INPUT: Number of degrees of freedom / node for this equation
!
! TYPE(Solver_t) :: Solver
!   INPUT: Holds various solver options
! 
!******************************************************************************
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: ForceVector(:), Solution(:), Norm
    TYPE(Matrix_t), POINTER :: StiffMatrix
    INTEGER :: DOFs
    TYPE(Solver_t), TARGET :: Solver
    TYPE(SParIterSolverGlobalD_t), POINTER :: ParMatrix
!------------------------------------------------------------------------------
    TYPE(Variable_t), POINTER :: Var
    TYPE(Mesh_t), POINTER :: Mesh, SaveMEsh
    LOGICAL :: Relax, GotIt
    INTEGER :: n,i,j,k,istat
    TYPE(Matrix_t), POINTER :: SaveMatrix
    TYPE(Solver_t), POINTER :: PSolver
    CHARACTER(LEN=MAX_NAME_LEN) :: Method, ProcName, VariableName
    INTEGER(KIND=AddrInt) :: Proc
    REAL(KIND=dp) :: s,Relaxation,Beta,Gamma
    REAL(KIND=dp), ALLOCATABLE :: PSolution(:), Diag(:)


    INTERFACE ExecLinSolveProcs
      INTEGER FUNCTION ExecLinSolveProcs( Proc,Model,Solver,A,b,x,n,DOFs,Norm )
        USE Types
        INTEGER(KIND=AddrInt) :: Proc
        TYPE(Model_t) :: Model
        TYPE(Solver_t) :: Solver
        TYPE(Matrix_t), POINTER :: A
        INTEGER :: n, DOFs
        REAL(KIND=dp) :: x(n),b(n), Norm
      END FUNCTION ExecLinSolveProcs
    END INTERFACE
!------------------------------------------------------------------------------
    n = StiffMatrix % NumberOfRows

    IF ( Solver % LinBeforeProc /= 0 ) THEN
       istat = ExecLinSolveProcs( Solver % LinBeforeProc,CurrentModel,Solver, &
              StiffMatrix,  ForceVector, Solution, n, DOFs, Norm )
       IF ( istat /= 0 ) GOTO 10
    END IF

!------------------------------------------------------------------------------
!   If parallel execution, check for parallel matrix initializations
!------------------------------------------------------------------------------
    IF ( .NOT. ASSOCIATED( Solver % Matrix % ParMatrix ) ) THEN
       CALL ParallelInitMatrix( Solver, Solver % Matrix )
    END IF
!------------------------------------------------------------------------------

    CALL SolveLinearSystem( StiffMatrix, ForceVector, Solution, Norm, DOFs, Solver )

!------------------------------------------------------------------------------

10  CONTINUE

    IF ( Solver % LinAfterProc /= 0 ) THEN
       istat = ExecLinSolveProcs( Solver % LinAfterProc, CurrentModel, Solver, &
                 StiffMatrix,  ForceVector, Solution, n, DOFs, Norm )
    END IF


    IF ( Solver % TimeOrder == 2 ) THEN
      IF ( ASSOCIATED( Solver % Variable % PrevValues ) ) THEN
        Gamma =  0.5d0 - Solver % Alpha
        Beta  = (1.0d0 - Solver % Alpha)**2 / 4.0d0
        DO i=1,n
          Solver % Variable % PrevValues(i,2) = &
           (1.0d0/(Beta*Solver % dt**2))* &
            (Solution(i)-Solver % Variable % PrevValues(i,3)) -  &
             (1.0d0/(Beta*Solver % dt))*Solver % Variable % PrevValues(i,4)+ &
               (1.0d0-1.0d0/(2*Beta))*Solver % Variable % PrevValues(i,5)

          Solver % Variable % PrevValues(i,1) = &
            Solver % Variable % PrevValues(i,4) + &
              Solver % dt*((1.0d0-Gamma)*Solver % Variable % PrevValues(i,5)+&
                Gamma*Solver % Variable % PrevValues(i,2))
        END DO
      END IF
    END IF
!------------------------------------------------------------------------------
    Solver % Variable % Norm = Norm

    Solver % Variable % PrimaryMesh => Solver % Mesh
    CALL InvalidateVariable( CurrentModel % Meshes, Solver % Mesh, &
                    Solver % Variable % Name )

!------------------------------------------------------------------------------
  END SUBROUTINE SolveSystem
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE SolveEigenSystem( StiffMatrix, NOFEigen, &
          EigenValues, EigenVectors,Solver )
DLLEXPORT SolveEigenSystem
!------------------------------------------------------------------------------
!******************************************************************************
!
! Solve a linear eigen system
!
!******************************************************************************
  USE EigenSolve
!------------------------------------------------------------------------------
    COMPLEX(KIND=dp) :: EigenValues(:),EigenVectors(:,:)
    REAL(KIND=dp) :: Norm
    TYPE(Matrix_t), POINTER :: StiffMatrix
    INTEGER :: NOFEigen
    TYPE(Solver_t) :: Solver
!------------------------------------------------------------------------------

    INTEGER :: n

!------------------------------------------------------------------------------
    n = StiffMatrix % NumberOfRows

    IF ( .NOT. Solver % Matrix % Complex ) THEN
       IF ( ParEnv % PEs <= 1 ) THEN
          CALL ArpackEigenSolve( Solver, StiffMatrix, n, NOFEigen, &
                       EigenValues, EigenVectors )
       ELSE
          CALL ParallelArpackEigenSolve( Solver, StiffMatrix, n, NOFEigen, &
                       EigenValues, EigenVectors )
       END IF
    ELSE
       CALL ArpackEigenSolveComplex( Solver, StiffMatrix, n/2, &
                NOFEigen, EigenValues, EigenVectors )
    END IF

!------------------------------------------------------------------------------
  END SUBROUTINE SolveEigenSystem
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    SUBROUTINE NSCondensate( N, Nb, dim, K, F, F1 )
DLLEXPORT NSCondensate
!------------------------------------------------------------------------------
      USE LinearAlgebra
      INTEGER :: N, Nb, dim
      REAL(KIND=dp) :: K(:,:),F(:),F1(:), Kbb(nb*dim,nb*dim), &
           Kbl(nb*dim,n*(dim+1)),Klb(n*(dim+1),nb*dim),Fb(nb*dim)

      INTEGER :: m, i, j, l, p, Cdofs((dim+1)*n), Bdofs(dim*nb)

      m = 0
      DO p = 1,n
        DO i = 1,dim+1
          m = m + 1
          Cdofs(m) = (dim+1)*(p-1) + i
        END DO
      END DO
      
      m = 0
      DO p = 1,nb
        DO i = 1,dim
          m = m + 1
          Bdofs(m) = (dim+1)*(p-1) + i + n*(dim+1)
        END DO
      END DO

      Kbb = K(Bdofs,Bdofs)
      Kbl = K(Bdofs,Cdofs)
      Klb = K(Cdofs,Bdofs)
      Fb  = F(Bdofs)

      CALL InvertMatrix( Kbb,nb*dim )

      F(1:(dim+1)*n) = F(1:(dim+1)*n) - MATMUL( Klb, MATMUL( Kbb, Fb ) )
      K(1:(dim+1)*n,1:(dim+1)*n) = &
           K(1:(dim+1)*n,1:(dim+1)*n) - MATMUL( Klb, MATMUL( Kbb,Kbl ) )

      Fb  = F1(Bdofs)
      F1(1:(dim+1)*n) = F1(1:(dim+1)*n) - MATMUL( Klb, MATMUL( Kbb, Fb ) )
!------------------------------------------------------------------------------
    END SUBROUTINE NSCondensate
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    SUBROUTINE Condensate( N, K, F, F1 )
DLLEXPORT Condensate
!------------------------------------------------------------------------------
      USE LinearAlgebra
      INTEGER :: N, dim
      REAL(KIND=dp) :: K(:,:),F(:),F1(:),Kbb(N,N), &
           Kbl(N,N),Klb(N,N),Fb(N)

      INTEGER :: m, i, j, l, p, Ldofs(N), Bdofs(N)

      Ldofs = (/ (i, i=1,n) /)
      Bdofs = Ldofs + n

      Kbb = K(Bdofs,Bdofs)
      Kbl = K(Bdofs,Ldofs)
      Klb = K(Ldofs,Bdofs)
      Fb  = F(Bdofs)

      CALL InvertMatrix( Kbb,n )

      F(1:n) = F(1:n) - MATMUL( Klb, MATMUL( Kbb, Fb  ) )
      K(1:n,1:n) = &
           K(1:n,1:n) - MATMUL( Klb, MATMUL( Kbb, Kbl ) )

      Fb  = F1(Bdofs)
      F1(1:n) = F1(1:n) - MATMUL( Klb, MATMUL( Kbb, Fb  ) )
!------------------------------------------------------------------------------
    END SUBROUTINE Condensate
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
  SUBROUTINE CondensateP( N, Nb, K, F, F1 )
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!     Subroutine for condensation of p element bubbles from linear problem.
!     Modifies given stiffness matrix and force vector(s) 
!
!  ARGUMENTS:
!    INTEGER :: N
!      INPUT: Sum of nodal, edge and face degrees of freedom 
!
!    INTEGER :: Nb
!      INPUT: Sum of internal (bubble) degrees of freedom
!
!    REAL(Kind=dp) :: K(:,:)
!      INOUT: Local stiffness matrix
!
!    REAL(Kind=dp) :: F(:)
!      INOUT: Local force vector
!
!    REAL(Kind=dp), OPTIONAL :: F1(:)
!      INOUT: Local second force vector 
!    
!******************************************************************************
!------------------------------------------------------------------------------

    USE LinearAlgebra
    INTEGER :: N, Nb
    REAL(KIND=dp) :: K(:,:),F(:),Kbb(Nb,Nb), &
         Kbl(Nb,N), Klb(N,Nb), Fb(Nb)
    REAL(KIND=dp), OPTIONAL :: F1(:)

    INTEGER :: m, i, j, l, p, Ldofs(N), Bdofs(Nb)

    Ldofs = (/ (i, i=1,n) /)
    Bdofs = (/ (i, i=n+1,n+nb) /)

    Kbb = K(Bdofs,Bdofs)
    Kbl = K(Bdofs,Ldofs)
    Klb = K(Ldofs,Bdofs)
    Fb  = F(Bdofs)
 
    CALL InvertMatrix( Kbb,nb )

    F(1:n) = F(1:n) - MATMUL( Klb, MATMUL( Kbb, Fb  ) )
    IF (PRESENT(F1)) THEN
       F1(1:n) = F1(1:n) - MATMUL( Klb, MATMUL( Kbb, Fb  ) )
    END IF

    K(1:n,1:n) = &
         K(1:n,1:n) - MATMUL( Klb, MATMUL( Kbb, Kbl ) )
!------------------------------------------------------------------------------
  END SUBROUTINE CondensateP
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
SUBROUTINE SolveWithLinearRestriction( StiffMatrix, ForceVector, Solution, &
        Norm, DOFs, Solver )
DLLEXPORT SolveWithLinearRestriction
!------------------------------------------------------------------------------  
!******************************************************************************
!  This subroutine will solve the system with some linear restriction.
!  The restriction matrix is assumed to be in the EMatrix-field of 
!  the StiffMatrix. The restriction vector is the RHS-field of the
!  EMatrix.
!  NOTE: Only serial solver implemented so far ...
!
!  ARGUMENTS:
!
!  TYPE(Matrix_t), POINTER :: StiffMatrix
!     INPUT: Linear equation matrix information. 
!            The restriction matrix is assumed to be in the EMatrix-field.
!
!  REAL(KIND=dp) :: ForceVector(:)
!     INPUT: The right hand side of the linear equation
!
!  REAL(KIND=dp) :: Solution(:)
!     INOUT: Previous solution as input, new solution as output.
!
!  REAL(KIND=dp) :: Norm
!     OUTPUT: The 2-norm of the solution.
!
!  INTEGER :: DOFs
!     INPUT: Number of degrees of freedon of the equation.
!
!  TYPE(Solver_t), TARGET :: Solver
!     INPUT: Linear equation solver options.
!
!******************************************************************************

  IMPLICIT NONE
  TYPE(Matrix_t), POINTER :: StiffMatrix
  REAL(KIND=dp) :: ForceVector(:), Solution(:), Norm
  INTEGER :: DOFs
  TYPE(Solver_t), TARGET :: Solver
!------------------------------------------------------------------------------
  TYPE(Solver_t), POINTER :: SolverPointer
  TYPE(Matrix_t), POINTER :: CollectionMatrix, RestMatrix, &
       RestMatrixTranspose
  REAL(KIND=dp), POINTER :: CollectionVector(:), RestVector(:), MultiplierValues(:)
  REAL(KIND=dp), ALLOCATABLE :: CollectionSolution(:)
  INTEGER, ALLOCATABLE :: TmpRow(:)
  INTEGER :: NumberOfRows, NumberOfValues, MultiplierDOFs, istat
  INTEGER :: i, j, k, l
  LOGICAL :: Found, ExportMultiplier
  CHARACTER(LEN=MAX_NAME_LEN) :: MultiplierName
  SAVE MultiplierValues, SolverPointer
!------------------------------------------------------------------------------
  SolverPointer => Solver
  CALL Info( 'SolveWithLinearRestriction ', ' ' )

  RestMatrix => StiffMatrix % EMatrix
  IF ( .NOT. ASSOCIATED( RestMatrix ) ) CALL Fatal( 'AddMassFlow', 'RestMatrix not associated' ) 

  RestVector => RestMatrix % RHS
  IF ( .NOT. ASSOCIATED( RestVector ) ) CALL Fatal( 'AddMassFlow', 'RestVector not associated' )

  ALLOCATE( TmpRow( StiffMatrix % NumberOfRows ), STAT=istat )
  IF ( istat /= 0 ) CALL Fatal( 'SolveWithLinearRestriction', 'Memory allocation error.' )
  
  NumberOfValues = SIZE( RestMatrix % Values )
  NumberOfRows = StiffMatrix % NumberOfRows

!------------------------------------------------------------------------------
! If multiplier should be exported,  allocate memory and export the variable.
!------------------------------------------------------------------------------

  ExportMultiplier = ListGetLogical( Solver % Values, 'Export Lagrange Multiplier', Found )
  IF ( .NOT. Found ) ExportMultiplier = .FALSE.

  IF ( ExportMultiplier ) THEN
     MultiplierName = ListGetString( Solver % Values, 'Lagrange Multiplier Name', Found )
     IF ( .NOT. Found ) THEN
        CALL Info( 'SolveWithLinearRestriction', 'Lagrange Multiplier Name set to LagrangeMultiplier' )
        MultiplierName = "LagrangeMultiplier"
     END IF

     IF ( .NOT. ASSOCIATED( MultiplierValues ) ) THEN
        MultiplierDOFs = RestMatrix % NumberOfRows / Solver % Mesh % NumberOfNodes +1
        ALLOCATE( MultiplierValues( MultiplierDOFs * Solver % Mesh % NumberOfNodes ), STAT=istat )
        IF ( istat /= 0 ) CALL Fatal('SolveWithLinearRestriction','Memory allocation error.')
        MultiplierValues = 0.0d0

        CALL VariableAdd( Solver % Mesh % Variables, Solver % Mesh, SolverPointer, &
             MultiplierName, MultiplierDOFs, MultiplierValues, Solver % Variable % Perm )
     END IF
  END IF

!------------------------------------------------------------------------------
! Set the RestMatrixTranspose to EMatrix-field of the RestMatrix.
! Allocate matrix if necessary.
!------------------------------------------------------------------------------
  RestMatrixTranspose => RestMatrix % EMatrix
  
  IF ( .NOT. ASSOCIATED( RestMatrixTranspose ) ) THEN
     RestMatrix % EMatrix => AllocateMatrix()
     RestMatrixTranspose => RestMatrix % EMatrix     
     RestMatrixTranspose % NumberOfRows = NumberOfRows
     
     ALLOCATE( RestMatrixTranspose % Rows( NumberOfRows +1 ), &
          RestMatrixTranspose % Cols( NumberOfValues ), &
          RestMatrixTranspose % Values( NumberOfValues ), & 
          RestMatrixTranspose % Diag( NumberOfRows ), &
          STAT=istat )
     
     IF ( istat /= 0 ) THEN
        CALL Fatal( 'SolveWithLinearRestriction', &
             'Memory allocation error.' )
     END IF     
  END IF

  RestMatrixTranspose % Rows = 0
  RestMatrixTranspose % Cols = 0
  RestMatrixTranspose % Diag = 0
  RestMatrixTranspose % Values = 0.0d0
  TmpRow = 0

!------------------------------------------------------------------------------
! Create the RestMatrixTranspose
!------------------------------------------------------------------------------

! Calculate number of values / row in RestMatrixTranspose:
!---------------------------------------------------------
  DO i = 1, NumberOfValues
     TmpRow( RestMatrix % Cols(i) ) = TmpRow( RestMatrix % Cols(i) ) + 1
  END DO

! Assign the row numbering to RestMatrixTranspose:
!-------------------------------------------------
  RestMatrixTranspose % Rows(1) = 1
  DO i = 1, NumberOfRows
     RestMatrixTranspose % Rows(i+1) = &
          RestMatrixTranspose % Rows(i) + TmpRow(i)
  END DO

! Save rows begin indexes to TmpRow:
!-----------------------------------
  DO i = 1, NumberOfRows
     TmpRow(i) = RestMatrixTranspose % Rows(i)
  END DO

! Assign column numbering and values to RestMatrixTranspose:
!-----------------------------------------------------------
  DO i = 1, RestMatrix % NumberOfRows
     DO j = RestMatrix % Rows(i), RestMatrix % Rows(i+1) - 1        
        k = RestMatrix % Cols(j)
        
        IF ( TmpRow(k) < RestMatrixTranspose % Rows(k+1) ) THEN           
           RestMatrixTranspose % Cols( TmpRow(k) ) = i
           RestMatrixTranspose % Values( TmpRow(k) ) = &
                RestMatrix % Values(j)           
           TmpRow(k) = TmpRow(k) + 1           
        ELSE           
           WRITE( Message, * ) 'Trying to access non-existent column', i,k
           CALL Error( 'SolveWithLinearRestriction', Message )
           RETURN           
        END IF        
     END DO
  END DO
  
  CALL Info( 'SolveWithLinearRestriction', 'RestMatrixTranspose done' )

!------------------------------------------------------------------------------
! Allocate memory for CollectionMatrix i.e. the matrix that is actually solved.
! Allocate memory for CollectionVector and CollectionSolution too.
!------------------------------------------------------------------------------
  
  NumberOfRows = StiffMatrix % NumberOfRows + RestMatrix % NumberOfRows
  NumberOfValues = SIZE( StiffMatrix % Values ) &
       + 2 * SIZE( RestMatrix % Values ) + RestMatrix % NumberOfRows

  CollectionMatrix => AllocateMatrix()
  CollectionMatrix % NumberOfRows = NumberOfRows
  
  ALLOCATE( CollectionMatrix % Rows( NumberOfRows +1 ), &
       CollectionMatrix % Cols( NumberOfValues ), &
       CollectionMatrix % Values( NumberOfValues ), &
       CollectionMatrix % Diag( NumberOfRows ), &
       CollectionMatrix % RHS( NumberOfRows ), &
       CollectionSolution( NumberOfRows ), &
       STAT = istat )
  IF ( istat /= 0 ) CALL Fatal( 'SolveWithLinearRestriction', 'Memory allocation error.' )
  
  CollectionVector => CollectionMatrix % RHS
    
  CollectionMatrix % Rows = 0
  CollectionMatrix % Cols = 0
  CollectionMatrix % Diag = 0
  CollectionMatrix % Values = 0.0d0
  CollectionVector = 0.0d0
  CollectionSolution = 0.0d0

!------------------------------------------------------------------------------
! Put StiffMatrix and RestMatrixTranspose into CollectionMatrix
!------------------------------------------------------------------------------

! Calculate number of values / row for upper part of ColectionMatrix:
!--------------------------------------------------------------------
  TmpRow = 0
  DO i = 1, StiffMatrix % NumberOfRows
     TmpRow(i) = StiffMatrix % Rows(i+1) -  StiffMatrix % Rows(i)
     TmpRow(i) = TmpRow(i) + &
          RestMatrixTranspose % Rows(i+1) - RestMatrixTranspose % Rows(i)     
  END DO

! Assign row numbering for upper part of CollectionMatrix:
!---------------------------------------------------------
  CollectionMatrix % Rows(1) = 1
  DO i = 1, StiffMatrix % NumberOfRows     
     CollectionMatrix % Rows(i+1) = CollectionMatrix % Rows(i) + TmpRow(i)     
  END DO

! Save rows begin indexes to TmpRow:
!-----------------------------------
  DO i = 1, StiffMatrix % NumberOfRows
     TmpRow(i) = CollectionMatrix % Rows(i)
  END DO

! Assign column numbering and values for upper part of CollectionMatrix:
!-----------------------------------------------------------------------  
  DO i = 1, StiffMatrix % NumberOfRows     
     DO j = StiffMatrix % Rows(i), StiffMatrix % Rows(i+1) - 1        
        k = StiffMatrix % Cols(j)
        
        IF ( TmpRow(i) < CollectionMatrix % Rows(i+1) ) THEN           
           CollectionMatrix % Cols( TmpRow(i) ) = k
           CollectionMatrix % Values( TmpRow(i) ) = StiffMatrix % Values(j)           
           TmpRow(i) = TmpRow(i) + 1           
        ELSE           
           WRITE( Message, * ) 'Trying to access non-existent column', i,k
           CALL Error( 'SolveWithLinearRestriction', Message )
           RETURN           
        END IF        
     END DO
!------------------------------------------------------------------------------
     DO j = RestMatrixTranspose % Rows(i), RestMatrixTranspose % Rows(i+1) - 1        
        k = RestMatrixTranspose % Cols(j) + StiffMatrix % NumberOfRows
        
        IF ( TmpRow(i) < CollectionMatrix % Rows(i+1) ) THEN           
           CollectionMatrix % Cols( TmpRow(i) ) = k
           CollectionMatrix % Values( TmpRow(i) ) = &
                RestMatrixTranspose % Values(j)
           TmpRow(i) = TmpRow(i) + 1           
        ELSE           
           WRITE( Message, * ) 'Trying to access non-existent column', i,k
           CALL Error( 'SolveWithLinearRestriction', Message )
           RETURN           
        END IF        
     END DO     
  END DO! <- NumberOfRows in upper part of CollectioMatrix.

! Assign diagonal numbering for upper part of CollectionMatrix:
!--------------------------------------------------------------
  DO i = 1, StiffMatrix % NumberOfRows
     CollectionMatrix % Diag(i) = StiffMatrix % Diag(i) &
          + RestMatrixTranspose % Rows(i) -1     
  END DO
  
  CALL Info( 'SolveWithLinearRestriction', 'CollectionMatrix upper part done' ) 

!------------------------------------------------------------------------------
! Put the RestMatrix to lower part of CollectionMatrix
!------------------------------------------------------------------------------

! Assign row numbering for lower part of CollectionMatrix:
!---------------------------------------------------------
  NumberOfRows = StiffMatrix % NumberOfRows
  NumberOfValues = SIZE( StiffMatrix % Values ) &
       + SIZE( RestMatrixTranspose % Values )
  
  DO i = 1, RestMatrix % NumberOfRows +1     
     CollectionMatrix % Rows( i + NumberOfRows ) = &
          NumberOfValues + RestMatrix % Rows(i) + (i-1)     
  END DO

! Save rows begin indexes to TmpRow:
!-----------------------------------
  TmpRow = 0
  DO i = 1, RestMatrix % NumberOfRows
     TmpRow(i) = RestMatrix % Rows(i)
  END DO

! Assign column numbering and values to lower part of CollectionMatrix:
!----------------------------------------------------------------------
  NumberOfRows = StiffMatrix % NumberOfRows
  
  DO i = 1, RestMatrix % NumberOfRows     
     DO j = RestMatrix % Rows(i), RestMatrix % Rows(i+1) - 1        
        k = RestMatrix % Cols(j)
        
        IF ( TmpRow(i) < CollectionMatrix % Rows( i + NumberOfRows +1 ) ) THEN           
           l = TmpRow(i) + NumberOfValues + (i-1)           
           CollectionMatrix % Cols(l) = k
           CollectionMatrix % Values(l) = RestMatrix % Values(j)           
           TmpRow(i) = TmpRow(i) + 1           
        ELSE           
           WRITE( Message, * ) 'Trying to access non-existent column', i,k
           CALL Error( 'SolveWithLinearRestriction', Message )
           RETURN           
        END IF        
     END DO
       
     IF ( TmpRow(i) < CollectionMatrix % Rows( i + NumberOfRows +1 ) ) THEN        
        l = TmpRow(i) + NumberOfValues + (i-1)        
        CollectionMatrix % Cols(l) = i + NumberOfRows
        CollectionMatrix % Diag( i + NumberOfRows ) = l
        CollectionMatrix % Values(l) = 0.0d0
        TmpRow(i) = TmpRow(i) + 1        
     ELSE        
        WRITE( Message, * ) 'Trying to access non-existent column', i,k
        CALL Error( 'SolveWithLinearRestriction', Message )
        RETURN          
     END IF     
  END DO! <- NumberOfRows in lower part of CollectionMatrix
    
  CALL Info( 'SolveWithLinearRestriction', 'CollectionMatrix done' )

!------------------------------------------------------------------------------
! Assign values to CollectionVector
!------------------------------------------------------------------------------

  j = StiffMatrix % NumberOfRows  
  CollectionVector( 1:j ) = ForceVector( 1:j )
  
  i = StiffMatrix % NumberOfRows +1
  j = CollectionMatrix % NumberOfRows
  k = RestMatrix % NumberOfRows
  CollectionVector( i:j ) = RestVector( 1:k )
  
  CALL Info( 'SolveWithLinearRestriction', 'CollectionVector done' )

!------------------------------------------------------------------------------
! Solve the Collection-system 
!------------------------------------------------------------------------------
  
  CALL SolveLinearSystem( CollectionMatrix, CollectionVector, &
       CollectionSolution, Norm, DOFs, Solver )
  
!------------------------------------------------------------------------------
! Separate the solution from CollectionSolution
!------------------------------------------------------------------------------
    Solution = 0.0d0
    i = 1
    j = StiffMatrix % NumberOfRows
    Solution( i:j ) = CollectionSolution( i:j )

    IF ( ExportMultiplier ) THEN
       i = StiffMatrix % NumberOfRows
       j = RestMatrix % NumberOfRows
       MultiplierValues = 0.0d0
       MultiplierValues(1:j) = CollectionSolution(i+1:i+j)
    END IF
!------------------------------------------------------------------------------
    CALL FreeMatrix( CollectionMatrix )
    DEALLOCATE( TmpRow, CollectionSolution )

    CALL Info( 'SolveWithLinearRestriction', 'All done' )

!------------------------------------------------------------------------------
  END SUBROUTINE SolveWithLinearRestriction
!------------------------------------------------------------------------------

END MODULE SolverUtils
