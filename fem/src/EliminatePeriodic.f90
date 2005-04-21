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
! * Module for eliminating DOFs corresponding to periodic BCs.
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
! *                       Date:  13 Sep 2002
! *
! *                  Module by: 
! *
! *                Modified by:
! *
! ****************************************************************************/
!------------------------------------------------------------------------------
INTEGER FUNCTION EliminatePeriodic( Model, Solver, A, b, x, n, DOFs, Norm )
  !DEC$ATTRIBUTES DLLEXPORT :: EliminatePeriodic
!------------------------------------------------------------------------------
!******************************************************************************
!
!  ARGUMENTS:
!
!  TYPE(Model_t) :: Model,  
!     INPUT: All model information (mesh,materials,BCs,etc...)
!
!  TYPE(Solver_t) :: Solver
!     INPUT: Linear equation solver options
!
!  TYPE(Matrix_t), POINTER :: A
!     INPUT: Linear equation matrix information
!
!  INTEGER :: DOFs
!     INPUT: Number of degrees of freedon of the equation
!
!  INTEGER :: n
!     INPUT: Length of unknown vector
!
!  REAL(KIND=dp) :: x(n)
!     INPUT: The unknown in the linear equation
!
!  REAL(KIND=dp) :: b(n)
!     INPUT: The right hand side of the linear equation
!
!  REAL(KIND=dp) :: Norm
!     INPUT: The norm to determine the convergence of the nonlinear system
!
!******************************************************************************


  USE Types
  USE Lists
  USE SolverUtils
  USE CRSmatrix
  USE GeneralUtils

  IMPLICIT NONE
  
  TYPE(model_t)  :: Model
  TYPE(solver_t) :: Solver
  TYPE(matrix_t), POINTER :: A
  INTEGER :: DOFs, n
  REAL(KIND=dp) :: b(n), x(n), Norm
!------------------------------------------------------------------------------

  TYPE(matrix_t), POINTER :: RedA, C, BB, C_Trans, A_Trans, BB_Trans, Projector
  TYPE(Element_t),POINTER :: CurrentElement, Parent
  REAL(KIND=dp), POINTER :: LocalEigenVectorsReal(:,:), LocalEigenVectorsImag(:,:)
  REAL(KIND=dp), POINTER :: f(:), TempVectorReal(:), TempVectorImag(:),u(:)
  REAL(KIND=dp) :: CenterOfRigidBody(3), CPUtime, TotTime, at, Scale
  LOGICAL, ALLOCATABLE :: PeriodicProj(:)
  LOGICAL :: stat, GotIt, Rigid, EigAnal
  INTEGER, ALLOCATABLE, TARGET :: ColN(:)
  INTEGER, POINTER :: NodeIndexes(:), Perm(:), PermSave(:)
  INTEGER :: RigidNodes, BoundaryNodes, NumberOfValues
  INTEGER :: NumberOfRows, RowsInUnityBlock, NEigen
  INTEGER :: istat, i, j, k, l, m, t, PeriodicNodes, DOF, Dirichlet,R(10000,2)
  LOGICAL :: AllocationsDone = .FALSE.
  INTEGER, POINTER :: PeriodicDOFs(:), DCount(:)
  CHARACTER(LEN=MAX_NAME_LEN) :: Name

interface
  INTEGER FUNCTION EliminateDirichlet( Model, Solver, A, b, x, n, DOFs, Norm )
  USE Types
  USE Lists
  USE SolverUtils
  USE CRSmatrix
  USE GeneralUtils
  TYPE(model_t)  :: Model
  TYPE(solver_t) :: Solver
  TYPE(matrix_t), POINTER :: A
  INTEGER :: DOFs, n
  REAL(KIND=dp) :: b(n), x(n), Norm
  end function eliminatedirichlet

end interface
!------------------------------------------------------------------------------

  TotTime = CPUtime()

!------------------------------------------------------------------------------

  C => A % EMatrix

  IF ( .NOT. ASSOCIATED( C ) ) THEN
     Perm => Solver % Variable % Perm

     ALLOCATE( PeriodicDOFs(A % NumberOFRows), ColN( A % NumberOfRows ), &
               PeriodicProj(A % NumberOfRows) )

     R = 0
     PeriodicDOFs  = 0
     PeriodicNodes = 0
     PeriodicProj = .FALSE.

     DO i=1,Model % NumberOfBCs
        DO DOF=1,DOFs
           Name = Solver % Variable % Name

           IF ( DOFs > 1 ) THEN
              WRITE( Name, '(a,i1)' ) TRIM(Name) // ' ', DOF
           END IF

           Scale = -1.0d0
           IF ( .NOT. ListGetLogical( Model % BCs(i) % Values, &
              'Periodic BC ' // TRIM(Name), GotIt ) ) THEN
               IF ( .NOT. ListGetLogical( Model % BCs(i) % Values, &
                    'Anti Periodic BC ' // TRIM(Name), GotIt ) ) CYCLE
              Scale = 1.0d0
           END IF

           IF ( ParEnv % PEs <= 1 ) THEN
              Projector => Model % BCs(i) % PMatrix
              IF ( .NOT. ASSOCIATED(Projector) ) CYCLE
 
              DO j=1,Projector % NumberOfRows
                 l = Perm( Projector % InvPerm(j) )
                 IF ( l > 0 ) THEN 
                    l = DOFs * (l-1) + DOF
    
                    DO k=Projector % Rows(j), Projector % Rows(j+1)-1
                       m = Perm( Projector % Cols(k) )
                       IF ( m > 0 )  THEN
                          m = DOFs * (m-1) + DOF

                          IF ( Projector % Values(k) == 1.0d0  ) THEN
                             PeriodicNodes = PeriodicNodes + 1
                             R(PeriodicNodes,1) = l
                             R(PeriodicNodes,2) = m
                          ELSE if ( projector % values(k) /= 0.0d0 ) Then
                          END IF
                       END IF
                    END DO
                 END IF
              END DO
          ELSE
             DO j=Solver % Mesh % NumberOfBulkElements+1, Solver % Mesh % NumberOfBulkElements + &
                         Solver % Mesh % NumberOfBoundaryElements
                IF ( Solver % Mesh % Elements(j) % Type % ElementCode /= 102 ) CYCLE

                l = Perm( Solver % Mesh % Elements(j) % NodeIndexes(1) )
                m = Perm( Solver % Mesh % Elements(j) % NodeIndexes(2) )
                l = DOFs * (l-1) + DOF
                m = DOFs * (m-1) + DOF
                PeriodicNodes = PeriodicNodes + 1
                R(PeriodicNodes,1) = l
                R(PeriodicNodes,2) = m
             END DO
          END IF
        END DO
     END DO

     IF ( PeriodicNodes <= 0 .AND. ParEnv % PEs <= 1 ) THEN
         EliminatePeriodic = EliminateDirichlet( Model, Solver, A, b, x, n, DOFs, Norm )
         RETURN
      END IF

     CALL PeriodicCnstr( R, PeriodicNodes, A % NumberOFRows, PeriodicDOFs, ColN, k )

     PeriodicNodes = k
     NumberOFRows  = A % NumberOfRows - PeriodicNodes
!------------------------------------------------------------------------------
!  Form the projection matrix C ( NumberOfRows x A % NumberOfRows )
!------------------------------------------------------------------------------
     C => AllocateMatrix()

     NumberOfValues = A % NumberOfRows

     C % NumberOfRows = A % NumberOfRows
     ALLOCATE( C % Rows( C % NumberOfRows+1 ), C % Cols( NumberOfValues ), &
          C % Values( NumberOfValues ), C % Diag( C % NumberOfRows ), STAT=istat )
     IF ( istat /= 0 )  CALL Fatal( 'EliminatePeriodic', 'Memory allocation error' )

!ColN = 1

     C % Values = 0.0d0
     C % Rows(1) = 1
     DO i=1,C % NumberOfRows
        C % Rows(i+1) = C % Rows(i) + 1 ! ColN(i)
     END DO

!    ColN = 0
     DO i = 1, C % NumberOfRows
!       ColN(i) = ColN(i) + 1
        t = C % Rows(i) ! + ColN(i) - 1
        C % Values(t) = 1.0d0
        C % Cols(t) = ColN(PeriodicDOFs(i))
     END DO

     DEALLOCATE( PeriodicDOFs,  PeriodicProj )

     C % Ordered = .FALSE.
     C % Diag = 0
     CALL CRS_SortMatrixValues( C )

     C_Trans => CRS_Transpose( C, .FALSE. )
     RedA => C
     C => C_Trans
     C_Trans => RedA


     C % Ordered = .FALSE.
     ALLOCATE( C % Diag(C % NumberOFrows ) )
     C % Diag = 0
     CALL CRS_SortMatrixValues( C )

     A % EMatrix => C
     C % EMatrix => C_Trans
     NULLIFY( RedA )
  ELSE
     C_Trans => C % EMatrix
     RedA => C_Trans % EMatrix
  END IF


!------------------------------------------------------------------------------
!   Eigen analysis
!------------------------------------------------------------------------------

  EigAnal = ListGetLogical( Solver % Values, 'Eigen Analysis', GotIt )
  IF ( EigAnal ) THEN
     NEigen = ListGetInteger( Solver % Values, 'Eigen System Values', GotIt )
     IF ( GotIt .AND. NEigen > 0 ) THEN
        DEALLOCATE( Solver % Variable % EigenVectors )
        Solver % NOFEigenValues = NEigen
        ALLOCATE( Solver % Variable % EigenVectors( NEigen, NumberOfRows ) )

        Solver % Variable % EigenValues  = 0.0d0
        Solver % Variable % EigenVectors = 0.0d0

        ALLOCATE( LocalEigenVectorsReal(NEigen,NumberOfRows) )
        ALLOCATE( LocalEigenVectorsImag(NEigen,NumberOfRows) )
     END IF
  END IF

!------------------------------------------------------------------------------
!  Multiply the original matrix on both sides RedA = CAC^T
!------------------------------------------------------------------------------

  WRITE( Message, * ) 'Constructing the reduced matrix...'
  CALL Info( 'EliminatePeriodic', Message, Level=5 )

  A_Trans => CRS_Transpose( A, EigAnal )

  NULLIFY( BB )
  CALL CRS_MatrixMatrixMultiply( BB, A_Trans, C_Trans, EigAnal )
  CALL FreeMatrix( A_Trans )
  CALL Info( 'EliminatePeriodic', Message, Level=5 )

  BB_Trans => CRS_Transpose( BB, EigAnal )
  CALL FreeMatrix( BB )

  CALL Info( 'EliminatePeriodic', Message, Level=5 )
  CALL CRS_MatrixMatrixMultiply( RedA, BB_Trans, C_Trans, EigAnal )

  CALL FreeMatrix( BB_Trans )

  ALLOCATE( F( RedA % NumberOfRows ), u( RedA % NumberOfRows ) )
  F = 0.0d0
  U = 0.0d0

  IF ( .NOT. EigAnal ) CALL CRS_MatrixVectorMultiply( C, b, f )
!------------------------------------------------------------------------------
!   Solve the system
!------------------------------------------------------------------------------
  RedA % Lumped    = A % Lumped
  RedA % Complex   = A % Complex
  RedA % Symmetric = A % Symmetric

  at = CPUtime()

  ALLOCATE( Perm(SIZE(Solver % Variable % Perm) ) )
  Perm = 0
  DO i=1,SIZE(Solver % Variable % Perm)
    j = Solver % Variable % Perm(i)
    IF ( j > 0 ) THEN
       DOF = DOFs * (j-1) + 1
       IF ( ColN(DOF) > 0 ) THEN
           Perm(i) = ( ColN(DOF)-1 ) / DOFs + 1
       END IF
    END IF
  END DO

  PermSave => Solver % Variable % Perm
  BB => Solver % Matrix
  Solver % Matrix => RedA
  Solver % Variable % Perm => Perm
  CALL ParallelInitMatrix( Solver, RedA )

  IF ( ParEnv % PEs <= 1 ) THEN
     k = EliminateDirichlet( Model, Solver, RedA, f, u, RedA % NumberOfRows, DOFs, Norm )
  ELSE
    k = 0
  END IF

  IF ( k == 0 ) CALL SolveLinearSystem( RedA, f, u, Norm, DOFs, Solver )

  Solver % Matrix => BB
  Solver % Variable % Perm => PermSave

  at = CPUtime() - at
  WRITE( Message, * ) 'Time used in SolveLinearSystem (CPU): ', at
  CALL Info( 'EliminatePeriodic', Message, Level=5 )
!------------------------------------------------------------------------------
!   Map the result back to original nodes
!------------------------------------------------------------------------------

  IF ( EigAnal ) THEN
     LocalEigenVectorsReal =  REAL( Solver % Variable % EigenVectors )
     LocalEigenVectorsImag = AIMAG( Solver % Variable % EigenVectors )

     DEALLOCATE( Solver % Variable % EigenVectors )

     ALLOCATE( Solver % Variable % EigenVectors( NEigen, &
         SIZE( Solver % Variable % Values ) ) )
     Solver % Variable % EigenVectors = 0.0d0

     ALLOCATE( TempVectorReal( SIZE( Solver % Variable % Values ) ) )
     ALLOCATE( TempVectorImag( SIZE( Solver % Variable % Values ) ) )
     DO i = 1, NEigen
       CALL CRS_MatrixVectorMultiply( C_Trans, LocalEigenVectorsReal(i,:), TempVectorReal )
       CALL CRS_MatrixVectorMultiply( C_Trans, LocalEigenVectorsReal(i,:), TempVectorImag )
       Solver % Variable % EigenVectors(i,1:n) = DCMPLX( TempVectorReal, TempVectorImag )
     END DO
     DEALLOCATE( LocalEigenVectorsReal, LocalEigenVectorsImag, TempVectorReal, TempVectorImag )
  ELSE
     CALL CRS_MatrixVectorMultiply( C_Trans, u, x )
  END IF

  Norm = SQRT( SUM(x**2) / A % NumberOFRows )
!------------------------------------------------------------------------------

  DEALLOCATE( F, U )

  EliminatePeriodic = 1

  TotTime = CPUtime() - TotTime

  WRITE( Message, * ) 'Total time spent in PeriodicReduction (CPU): ', TotTime
  CALL Info( 'EliminatePeriodic', ' ', Level=5 )
  CALL Info( 'EliminatePeriodic', Message, Level=5 )
  CALL Info( 'EliminatePeriodic', ' ', Level=5 )

CONTAINS


!  Ideana oli tehd� matriisit Neumanin reunaehdoilla sek� taulukko
!  R, jossa on solmuarvojen riippuvuudet tyyliin R(i,1) = R(i,2).
!  Saa olla p��llekk�isyyksi� ja miss� tahansa j�rjestyksess�. 
!  Kutsuin sitten a.o. aliohjelmaa, joka palauttaa listat d ja
!  Pperm siten, ett� projektori saadaan seuraavasti:
!
!   P( i, Pperm( d(i) ) ) = 1
!
!  Itseasiassa tuo d on t�ss� ainoa mik� oikeastaan sis�lt�� 
!  infoa, eli vapausasteiden lopulliset riippuvuudet tyyliin
!
!      i = d(i)
!
!  Ei ole en�� N**2 luuppi, vaan ihan N. Testasin aika paljon ja
!  n�ytt�isi toimivan kyll� ihan hienosti. 
!
!  Tuo 3d on sin�ns� hankala, ett� ongelmia ei tule pelk�st��n
!  nurkkapisteist� kuten 2d:ss�, vaan my�s kaikista s�rmist�, 
!  eli toiststaan riippuvia rajoitteita on itseasiassa l�j�p�in.
!
!  Tuskin tosta edelleenk��n on mit��n lopullista iloa, heit�
!  roskiin jos silt� tuntuu. Ja eih�n toi edes toimi muuten kuin
!  kahden solmun v�lisille rajoitteille, mit��n yleisemp�� sill�
!  ei voi tehd�.
!
!  Mikko

!------------------------------------------------------------------------------ 
  SUBROUTINE PeriodicCnstr( R, n, NOFRows, d, Perm, IDC ) 
!------------------------------------------------------------------------------ 
! Eliminates dependent constraints 
! 
! On input:   R(n,2) = Initial constraint list, R(i,1) = R(i,2)
!                n   = Number of constraints 
! 
! On output:     d   = Correct list of dependencies, i = d(i)
!              Perm = Additional permutation vector 
!               idc  = number of independent constraints  
! 
! The projector for eliminating the dependent constraints is 
!     
!                   P(i, Perm( d(i))) = 1 
! 
!------------------------------------------------------------------------------ 
    INTEGER :: R(:,:), n, NOFRows, d(:), Perm(:), IDC 
 
    INTEGER :: i, j, k, CountChanges 
    LOGICAL :: ChangesOccured 

    DO i = 1, NOFRows
       d(i) = i 
    END DO 
 
    DO i = 1, n 
       j = R(i,1) ! MINVAL( R(i,1:2) ) 
       k = R(i,2) ! MAXVAL( R(i,1:2) ) 
       d(j) = d(k)
    END DO 

    ChangesOccured = .TRUE. 
    DO WHILE( ChangesOccured ) 
       ChangesOccured = .FALSE. 
       CountChanges = 0 
       DO i = 1,NOFRows
          IF( d(i) /= d(d(i)) ) THEN 
             d(i) = d(d(i)) 
             ChangesOccured = .TRUE. 
             CountChanges = CountChanges+1 
          END IF 
       END DO 
       PRINT *,'Eliminated',CountChanges,' dependent constraints' 
    END DO 

    j = 0 
    Perm = 0 
    DO i = 1, NOFRows
       IF( d(i) == i ) THEN 
          j = j + 1
          Perm(i) = j 
       END if 
    END DO 

    IDC = NOFRows - j 
!------------------------------------------------------------------------------ 
  END SUBROUTINE PeriodicCnstr 
!------------------------------------------------------------------------------ 



!------------------------------------------------------------------------------
  SUBROUTINE CRS_SortMatrixValues( A )
!    DLLEXPORT CRS_SortMatrixValues
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!   Sort columns and values to ascending order for rows of a CRS format matrix
!
!  ARGUMENTS:
!
!  TYPE(Matrix_t) :: A
!     INPUT: Structure holding matrix
!
!******************************************************************************
!------------------------------------------------------------------------------
    USE CRSMatrix
    USE GeneralUtils
    IMPLICIT NONE

    TYPE(Matrix_t), POINTER :: A

    INTEGER :: i, j, n

    INTEGER, POINTER :: Cols(:), Rows(:), Diag(:)
    REAL(KIND=dp), POINTER :: Values(:)


    Diag   => A % Diag
    Rows   => A % Rows
    Cols   => A % Cols
    Values => A % Values

    n = A % NumberOfRows

    IF ( .NOT. A % Ordered ) THEN
      DO i = 1, n
        CALL SortF( Rows(i+1)-Rows(i), Cols(Rows(i):Rows(i+1)-1), &
            Values(Rows(i):Rows(i+1)-1) )
      END DO

      DO i = 1, n
        DO j = Rows(i), Rows(i+1)-1
          IF ( Cols(j) == i ) THEN
            Diag(i) = j
            EXIT
          END IF
        END DO
      END DO

      A % Ordered = .TRUE.
    END IF

  END SUBROUTINE CRS_SortMatrixValues
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
  FUNCTION CRS_Transpose( A, MVal ) RESULT(B)
!------------------------------------------------------------------------------
!
!  Calculate transpose of A in CRS format: B = A^T
!
!------------------------------------------------------------------------------
    USE CRSMatrix
    IMPLICIT NONE

    TYPE(Matrix_t), POINTER :: A, B
    LOGICAL :: MVal

    INTEGER, ALLOCATABLE :: Row(:)
    INTEGER :: NVals
    INTEGER :: i,j,k,l

    B => AllocateMatrix()
    
    NVals = SIZE( A % Values )
    B % NumberOfRows = MAXVAL( A % Cols )
    ALLOCATE( B % Rows( B % NumberOfRows +1 ), B % Cols( NVals ), &
        B % Values( Nvals ) )
    IF ( Mval )  ALLOCATE( B % MassValues( NVals ) )

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
    IF ( Mval ) THEN
       DO i = 1, A % NumberOfRows
          DO j = A % Rows(i), A % Rows(i+1) - 1
             k = A % Cols(j)
             IF ( Row(k) < B % Rows(k+1) ) THEN 
                B % Cols( Row(k) ) = i
                B % Values( Row(k) ) = A % Values(j)
                B % MassValues( Row(k) ) = A % MassValues(j)
                Row(k) = Row(k) + 1
             ELSE
                WRITE( Message, * ) 'Trying to access non-existent column', i,k
                !ALL Error( 'CRS_Transpose', Message )
                RETURN
             END IF
          END DO
       END DO
    ELSE
       DO i = 1, A % NumberOfRows
          DO j = A % Rows(i), A % Rows(i+1) - 1
             k = A % Cols(j)
             IF ( Row(k) < B % Rows(k+1) ) THEN 
                B % Cols( Row(k) ) = i
                B % Values( Row(k) ) = A % Values(j)
                Row(k) = Row(k) + 1
             ELSE
                WRITE( Message, * ) 'Trying to access non-existent column', i,k
                CALL Error( 'CRS_Transpose', Message )
                RETURN
             END IF
          END DO
       END DO
    END IF

    DEALLOCATE( Row )

!------------------------------------------------------------------------------
  END FUNCTION CRS_Transpose
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE CRS_MatrixMatrixMultiply( C, A, B, MVal )
!------------------------------------------------------------------------------
    USE CRSMatrix
    IMPLICIT NONE

    TYPE(Matrix_t), POINTER :: A, B, C
    LOGICAL :: Mval
!------------------------------------------------------------------------------
!   If Mval is true the product C should have MassValues array.
!   Then, if the input matrices A and B contain MassValues arrays, use them
!   to calculate product MassValues, otherwise use the Values array.
!------------------------------------------------------------------------------
    REAL(KIND=dp) , POINTER :: AMassVals(:), BMassVals(:)
    LOGICAL, ALLOCATABLE :: Row(:)
    INTEGER, ALLOCATABLE :: Ind(:)
    INTEGER :: ki, NCols
    INTEGER :: i,j,k,l,m,n,Rownonzeros( A % NumberOfRows ), TotalNonzeros
!------------------------------------------------------------------------------

    IF ( .NOT. ASSOCIATED( C ) ) THEN
       Rownonzeros   = 0
       TotalNonzeros = 0

       NCols = MAXVAL( B % Cols )
       ALLOCATE( Row( NCols ), Ind( NCols ) )

       Row = .FALSE.
       DO i=1,A % NumberOfRows
          ki = 0
          DO l=A % Rows(i),A % Rows(i+1)-1
             k = A % Cols(l)
             DO m=B % Rows(k), B % Rows(k+1)-1
                j = B % Cols(m)

                IF ( .NOT. Row(j) ) THEN
                   ki = ki + 1
                   Ind(ki) = j
                   Row(j) = .TRUE.
                END IF
             END DO
          END DO

          DO j=1,ki
             Row(Ind(j)) = .FALSE.
          END DO
          RowNonzeros(i) = ki
          TotalNonzeros  = TotalNonzeros + ki
       END DO

       C => AllocateMatrix()

       C % NumberOfRows = A % NumberOFRows
       ALLOCATE( C % Cols( TotalNonzeros ), C % Values( TotalNonzeros ) )
       ALLOCATE( C % Rows( C % NumberOfRows + 1 ), &
            C % Diag( C % NumberOfRows ) )
       IF ( MVal )  ALLOCATE( C % MassValues( TotalNonzeros ) )

       C % Rows(1) = 1
       DO i=1, A % NumberOfRows
          C % Rows(i+1) = C % Rows(i) + Rownonzeros(i)
       END DO

       C % Cols = 0
       Row = .FALSE.
       DO i=1,A % NumberOfRows
          ki = 0
          DO l=A % Rows(i),A % Rows(i+1)-1
             k = A % Cols(l)
             DO m=B % Rows(k), B % Rows(k+1)-1
                j = B % Cols(m)

                IF ( .NOT. Row(j) ) THEN
                   ki = ki + 1
                   Ind(ki) = j
                   Row(j) = .TRUE.
                   CALL CRS_MakeMatrixIndex( C, i, j )
                END IF
             END DO
          END DO

          DO j=1,ki
             Row(Ind(j)) = .FALSE.
          END DO
       END DO

       CALL CRS_SortMatrix( C )

       DEALLOCATE( Row, Ind )

    END IF

    IF ( MVal ) THEN
       IF ( ASSOCIATED( A % MassValues ) ) THEN
          AMassVals => A % MassValues
       ELSE
          AMassVals => A % Values
       END IF

       IF ( ASSOCIATED( B % MassValues ) ) THEN
          BMassVals => B % MassValues
       ELSE
          BMassVals => B % Values
       END IF

       C % Values = 0.0d0
       C % MassValues = 0.0d0
       DO i=1,A % NumberOfRows
          DO l=A % Rows(i),A % Rows(i+1)-1
             k = A % Cols(l)
             DO m=B % Rows(k), B % Rows(k+1)-1
                j = B % Cols(m)
                DO n=C % Rows(i), C % Rows(i+1)-1
                   IF ( C % Cols(n) == j ) THEN
                      C % Values(n) = C % Values(n) + &
                           A % Values(l) * B % Values(m)
                      C % MassValues(n) = C % MassValues(n) + &
                           AMassVals(l) * BMassVals(m)
                      EXIT
                   END IF
                END DO
             END DO
          END DO
       END DO
    ELSE
       C % Values = 0.0d0
       DO i=1,A % NumberOfRows
          DO l=A % Rows(i),A % Rows(i+1)-1
             k = A % Cols(l)
             DO m=B % Rows(k), B % Rows(k+1)-1
                j = B % Cols(m)
                DO n=C % Rows(i), C % Rows(i+1)-1
                   IF ( C % Cols(n) == j ) THEN
                      C % Values(n) = C % Values(n) + &
                           A % Values(l) * B % Values(m)
                      EXIT
                   END IF
                END DO
             END DO
          END DO
       END DO
    END IF


!------------------------------------------------------------------------------
  END SUBROUTINE CRS_MatrixMatrixMultiply
!------------------------------------------------------------------------------


END FUNCTION EliminatePeriodic
