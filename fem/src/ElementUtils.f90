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
! ******************************************************************************/
!
!/*******************************************************************************
! *
! * Some utulities for the basic FEM
! *
! *******************************************************************************
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
! *                       Date: 01 Oct 1996
! *
! *                Modified by:
! *
! *       Date of modification:
! *
! ******************************************************************************/


MODULE ElementUtils

    USE Integration
    USE BandMatrix
    USE CRSMatrix
    USE Interpolation
    USE BandwidthOptimize

    IMPLICIT NONE

INTEGER :: lnodes

CONTAINS

!-------------------------------------------------------------------------------
   SUBROUTINE MakeListMatrixIndex( ListMatrix,k1,k2 )
!-------------------------------------------------------------------------------
     INTEGER :: k1,k2
     TYPE(ListMatrixPointer_t), POINTER :: ListMatrix(:)
     TYPE(ListMatrix_t), POINTER :: CList,Prev, ENTRY
!-------------------------------------------------------------------------------
     Clist => ListMatrix(k1) % Head

     IF ( .NOT. ASSOCIATED(Clist) ) THEN
        ALLOCATE( ENTRY )
        ENTRY % INDEX = k2
        NULLIFY( ENTRY % Next )
        ListMatrix(k1) % Degree = 1
        ListMatrix(k1) % Head => ENTRY
        RETURN
     END IF

     NULLIFY( Prev )
     DO WHILE( ASSOCIATED(CList) )
        IF ( Clist % INDEX >= k2 ) EXIT
        Prev  => Clist
        CList => CList % Next
     END DO

     IF ( ASSOCIATED( CList ) ) THEN
        IF ( CList % INDEX == k2 ) RETURN
     END IF

     ALLOCATE( ENTRY )
     ENTRY % INDEX = k2
     ENTRY % Next => Clist
     IF ( ASSOCIATED( Prev ) ) THEN
         Prev % Next => ENTRY
     ELSE
        ListMatrix(k1) % Head => ENTRY
     END IF

     ListMatrix(k1) % Degree = ListMatrix(k1) % Degree + 1
!-------------------------------------------------------------------------------
   END SUBROUTINE MakeListMatrixIndex
!-------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE MakeListMatrix( Model,Mesh,ListMatrix,Reorder, &
            LocalNodes,Equation, DGSolver, GlobalBubbles )
DLLEXPORT MakeMatrix
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!******************************************************************************
!------------------------------------------------------------------------------
    TYPE(Model_t)  :: Model
    TYPE(Mesh_t), POINTER  :: Mesh
    TYPE(Matrix_t),POINTER :: Matrix
    INTEGER :: LocalNodes, InvPerm(LocalNodes)
    TYPE(ListMatrixPointer_t), POINTER :: ListMatrix(:)
    INTEGER, OPTIONAL ::Reorder(:)
    LOGICAL, OPTIONAL :: DGSolver
    LOGICAL, OPTIONAL :: GlobalBubbles
    CHARACTER(LEN=*), OPTIONAL :: Equation
!------------------------------------------------------------------------------
    INTEGER :: t,i,j,k,l,m,k1,k2,n,p,q,e1,e2,f1,f2, EDOFs, FDOFs, BDOFs, This

    LOGICAL :: Flag, FoundDG, GB

    TYPE(Matrix_t), POINTER :: Projector

    INTEGER :: IndexSize, NumberOfFactors
    INTEGER, ALLOCATABLE :: Indexes(:)

    TYPE(ListMatrix_t), POINTER :: CList

    TYPE(Matrix_t),POINTER :: PMatrix
    TYPE(Element_t), POINTER :: CurrentElement,Elm, Edge1, Edge2, Face1, Face2
!------------------------------------------------------------------------------

   GB = .FALSE.
   IF ( PRESENT(GlobalBubbles) ) GB = GlobalBubbles

    ALLOCATE( ListMatrix(LocalNodes) )
    DO i=1,LocalNodes
       ListMatrix(i) % Degree = 0
       NULLIFY( ListMatrix(i) % Head )
    END DO 

    EDOFs = Mesh % MaxEdgeDOFs
    FDOFs = Mesh % MaxFaceDOFs
    BDOFs = Mesh % MaxBDOFs

    IndexSize = 128
    ALLOCATE( Indexes(IndexSize) )
 
    FoundDG = .FALSE.
    IF ( DGSolver ) THEN
       DO t=1,Mesh % NumberOfEdges
         n = 0
         Elm => Mesh % Edges(t) % BoundaryInfo % Left
         IF ( ASSOCIATED( Elm ) ) THEN
             IF ( CheckElementEquation(Model,Elm,Equation) ) THEN
                FoundDG = FoundDG .OR. Elm % DGDOFs > 0
                DO j=1,Elm % DGDOFs
                   n = n + 1
                   Indexes(n) = Elm % DGIndexes(j)
                END DO
             END IF
         END IF

         Elm => Mesh % Edges(t) % BoundaryInfo %  Right
         IF ( ASSOCIATED( Elm ) ) THEN
             IF ( CheckElementEquation(Model,Elm,Equation) ) THEN
                FoundDG = FoundDG .OR. Elm % DGDOFs > 0
                DO j=1,Elm % DGDOFs
                   n = n + 1
                   Indexes(n) = Elm % DGIndexes(j)
                END DO
             END IF
         END IF

         DO i=1,n
            k1 = Reorder(Indexes(i))
            DO j=1,n
              k2 = Reorder(Indexes(j))
              CALL MakeListMatrixIndex( ListMatrix,k1,k2 )
            END DO
         END DO
      END DO

      DO t=1,Mesh % NumberOfFaces
         n = 0
         Elm => Mesh % Faces(t) % BoundaryInfo % Left
         IF ( ASSOCIATED( Elm ) ) THEN
             IF ( CheckElementEquation(Model,Elm,Equation) ) THEN
                FoundDG = FoundDG .OR. Elm % DGDOFs > 0
                DO j=1,Elm % DGDOFs
                   n = n + 1
                   Indexes(n) = Elm % DGIndexes(j)
                END DO
             END IF
         END IF

         Elm => Mesh % Faces(t) % BoundaryInfo %  Right
         IF ( ASSOCIATED( Elm ) ) THEN
             IF ( CheckElementEquation(Model,Elm,Equation) ) THEN
                FoundDG = FoundDG .OR. Elm % DGDOFs > 0
                DO j=1,Elm % DGDOFs
                   n = n + 1
                   Indexes(n) = Elm % DGIndexes(j)
                END DO
             END IF
         END IF

         DO i=1,n
            k1 = Reorder(Indexes(i))
            DO j=1,n
              k2 = Reorder(Indexes(j))
              CALL MakeListMatrixIndex( ListMatrix,k1,k2 )
            END DO
         END DO
      END DO
    END IF

    IF ( .NOT. FoundDG ) THEN
      t = 1
      DO WHILE( t<=Mesh % NumberOfBulkElements+Mesh % NumberOFBoundaryElements )
         CurrentElement => Mesh % Elements(t)

         IF ( PRESENT(Equation) ) THEN
           DO WHILE( t<=Mesh % NumberOfBulkElements+Mesh % NumberOfBoundaryElements )
             CurrentElement => Mesh % Elements(t)
             IF ( CheckElementEquation(Model,CurrentElement,Equation) ) EXIT
             t = t + 1
           END DO
           IF ( t > Mesh % NumberOfBulkElements+Mesh % NumberOfBoundaryElements ) EXIT
         END IF

         n = CurrentElement % NDOFs + &
             CurrentElement % Type % NumberOfEdges * EDOFs + &
             CurrentElement % Type % NumberOfFaces * FDOFs

         IF ( GB ) n = n + CurrentElement % BDOFs

         IF ( n > IndexSize ) THEN
            IndexSize = n
            IF ( ALLOCATED( Indexes ) ) DEALLOCATE( Indexes )
            ALLOCATE( Indexes(n) )
         END IF

         n = 0
         DO i=1,CurrentElement % NDOFs
            n = n + 1
            Indexes(n) = CurrentElement % NodeIndexes(i)
         END DO

         IF ( ASSOCIATED(Mesh % Edges) ) THEN
            DO j=1,CurrentElement % Type % NumberOFEdges
               DO i=1, Mesh % Edges(CurrentElement % EdgeIndexes(j)) % BDOFs
                  n = n + 1
                  Indexes(n) = EDOFs * (CurrentElement % EdgeIndexes(j)-1) + i &
                               + Mesh % NumberOfNodes
               END DO
            END DO
         END IF

         IF ( ASSOCIATED( Mesh % Faces ) ) THEN
           DO j=1,CurrentElement % Type % NumberOFFaces
             DO i=1, Mesh % Faces(CurrentElement % FaceIndexes(j)) % BDOFs
               n = n + 1
               Indexes(n) = FDOFs*(CurrentElement % FaceIndexes(j)-1) + i + &
                   Mesh % NumberOfNodes + EDOFs*Mesh % NumberOfEdges
             END DO
           END DO
         END IF

         IF ( GB .AND. ASSOCIATED( CurrentElement % BubbleIndexes ) ) THEN
            DO i=1,CurrentElement % BDOFs
              n = n + 1
              Indexes(n) = FDOFs*Mesh % NumberOfFaces + &
                   Mesh % NumberOfNodes + EDOFs*Mesh % NumberOfEdges + &
                        CurrentElement % BubbleIndexes(i)
            END DO
         END IF

         DO i=1,n
            k1 = Reorder(Indexes(i))
            DO j=1,n
               k2 =  Reorder(Indexes(j))
               CALL MakeListMatrixIndex( ListMatrix,k1,k2 )
            END DO
         END DO
         t = t + 1
      END DO

      IF ( ALLOCATED( Indexes ) ) DEALLOCATE( Indexes )
!
!     Diffuse gray radiation condition:
!     ---------------------------------
      IF ( PRESENT(Equation) ) THEN
        IF ( Equation == 'heat equation' ) THEN
          DO i = Mesh % NumberOfBulkElements+1, &
            Mesh % NumberOfBulkElements + Mesh % NumberOfBoundaryElements
  
            CurrentElement => Mesh % Elements(i)
            IF ( ASSOCIATED(CurrentElement % BoundaryInfo % GebhardtFactors % Elements) ) THEN
               DO j=1,CurrentElement % TYPE % NumberOfNodes
                  k1 = Reorder(CurrentElement % NodeIndexes(j))

                  NumberOfFactors = CurrentElement % BoundaryInfo % &
                    GebhardtFactors % NumberOfImplicitFactors
!                  IF(NumberOfFactors == 0) NumberOfFactors = CurrentElement % BoundaryInfo % &
!                    GebhardtFactors % NumberOfFactors

                  DO n=1,NumberOfFactors

                    Elm => Mesh % Elements( CurrentElement % BoundaryInfo % &
                                GebhardtFactors % Elements(n) )

                    DO k=1,Elm % Type % NumberOfNodes
                       k2 = Reorder( Elm % NodeIndexes(k) )
                       CALL MakeListMatrixIndex( ListMatrix,k1,k2 )
                    END DO
                  END DO
               END DO
            END IF
          END DO
        END IF
      END IF

      DO i=Mesh % NumberOfBulkElements+1, Mesh % NumberOfBulkElements+ &
                     Mesh % NumberOfBoundaryElements
         IF ( Mesh % Elements(i) % Type % ElementCode <  102 .OR. &
              Mesh % Elements(i) % Type % ElementCode >= 200 ) CYCLE

         DO j=1,Mesh % Elements(i) % Type % NumberOFNodes
         DO k=1,Mesh % Elements(i) % Type % NumberOFNodes
           k1 = Reorder( Mesh % Elements(i) % NodeIndexes(j) )
           k2 = Reorder( Mesh % Elements(i) % NodeIndexes(k) )
           IF ( k1 > 0 .AND. k2 > 0 ) THEN
              CALL MakeListMatrixIndex( ListMatrix,k1,k2 )
              CALL MakeListMatrixIndex( ListMatrix,k2,k1 )
           END IF
         END DO
         END DO
      END DO

!------------------------------------------------------------------------------

      DO This=1,Model % NumberOfBCs
        Projector => Model % BCs(This) % PMatrix
        IF ( .NOT. ASSOCIATED(Projector) ) CYCLE

        DO i=1,Projector % NumberOfRows
          k = Reorder( Projector % InvPerm(i) )
          IF ( k > 0 ) THEN
            DO l=Projector % Rows(i),Projector % Rows(i+1)-1
              IF ( Projector % Cols(l) <= 0 ) CYCLE

              IF ( Projector % Values(l) > 1.0d-12 ) THEN
                 m = Reorder( Projector % Cols(l) )
                 IF ( m > 0 ) THEN
                   CALL MakeListMatrixIndex( ListMatrix,k,m )
                   CList => ListMatrix( k ) % Head
                   DO WHILE( ASSOCIATED( CList ) )
                      CALL MakeListMatrixIndex( ListMatrix,m,CList % INDEX )
                      CList => CList % Next
                   END DO
                 END IF
              END IF
            END DO
          END IF
        END DO
      END DO
    END IF

    k = 0
    DO i=1,SIZE(Reorder)
       IF ( Reorder(i) > 0 ) THEN
          k = k + 1
         InvPerm( Reorder(i) ) = k
       END IF
    END DO

    Model % TotalMatrixElements = 0
    Model % Rownonzeros = 0
    DO i=1,LocalNodes
       Model % RowNonzeros(InvPerm(i)) = ListMatrix(i) % Degree
       Model % TotalMatrixElements =  &
           Model % TotalMatrixElements + ListMatrix(i) % Degree
    END DO
!------------------------------------------------------------------------------
  END SUBROUTINE MakeListMatrix
!------------------------------------------------------------------------------


!-------------------------------------------------------------------------------
   SUBROUTINE FreeListMatrix( N, ListMatrix )
DLLEXPORT FreeListMatrix
!-------------------------------------------------------------------------------
     TYPE(ListMatrixPointer_t), POINTER :: ListMatrix(:)
     INTEGER :: N
!-------------------------------------------------------------------------------

     TYPE(ListMatrix_t), POINTER :: p,p1
     INTEGER :: i
!-------------------------------------------------------------------------------
     IF ( .NOT. ASSOCIATED(ListMatrix) ) RETURN

     DO i=1,N
       p => ListMatrix(i) % Head
       DO WHILE( ASSOCIATED(p) )
         p1 => p % Next
         DEALLOCATE( p )
         p => p1 
       END DO
     END DO
     DEALLOCATE( ListMatrix )
!-------------------------------------------------------------------------------
   END SUBROUTINE FreeListMatrix
!-------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE InitializeMatrix( Matrix, n, List, Reorder, &
                 InvInitialReorder, DOFs )
DLLEXPORT InitializeMatrix
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Initialize a CRS format matrix to the effect that it will be ready to
!    accept values when CRS_GlueLocalMatrix is called (build up the index
!    tables of a CRS format matrix)....
!
!******************************************************************************
!------------------------------------------------------------------------------
    INTEGER :: Reorder(:), InvInitialReorder(:)
    INTEGER :: DOFs, n
    TYPE(Matrix_t),POINTER :: Matrix
    TYPE(ListMatrixPointer_t) :: List(:)
!------------------------------------------------------------------------------
    TYPE(ListMatrix_t), POINTER :: Clist
    INTEGER :: i,j,k,l,m,k1,k2
!------------------------------------------------------------------------------

    DO i=1,n
       CList => List(i) % Head
       j = Reorder( InvInitialReorder(i) )
       DO WHILE( ASSOCIATED( CList ) )
         k = Reorder( InvInitialReorder(Clist % INDEX) )
         DO l=1,DOFs
           DO m=1,DOFs
              k1 = DOFs * (j-1) + l
              k2 = DOFs * (k-1) + m
              CALL CRS_MakeMatrixIndex( Matrix,k1,k2 )
           END DO
         END DO
         CList => Clist % Next
       END DO
    END DO

    IF ( Matrix % FORMAT == MATRIX_CRS ) CALL CRS_SortMatrix( Matrix )
!------------------------------------------------------------------------------
  END SUBROUTINE InitializeMatrix
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   FUNCTION CreateMatrix( Model, Mesh, Perm, DOFs, MatrixFormat, &
          OptimizeBW, Equation, DGSolver, GlobalBubbles ) RESULT(Matrix)
DLLEXPORT CreateMatrix
!------------------------------------------------------------------------------
     TYPE(Model_t) :: Model
     TYPE(Mesh_t),  POINTER :: Mesh
     INTEGER :: DOFs, MatrixFormat
     INTEGER, TARGET :: Perm(:)
     LOGICAL :: OptimizeBW
     LOGICAL, OPTIONAL :: DGSolver, GlobalBubbles
     CHARACTER(LEN=*), OPTIONAL :: Equation

     TYPE(Matrix_t),POINTER :: Matrix
!------------------------------------------------------------------------------
     TYPE(ListMatrixPointer_t), POINTER :: ListMatrix(:)
     CHARACTER(LEN=MAX_NAME_LEN) :: Eq
     LOGICAL :: GotIt, DG, GB
     INTEGER i,j,k,t,n, EDOFs, FDOFs, BDOFs
     INTEGER, ALLOCATABLE :: InvInitialReorder(:)
     TYPE(Element_t),POINTER :: CurrentElement
!------------------------------------------------------------------------------

     NULLIFY( Matrix )

     DG = .FALSE.
     IF ( PRESENT(DGSolver) )  DG=DGSolver

     GB = .FALSE.
     IF ( PRESENT(GlobalBubbles) )  GB=GlobalBubbles

     EDOFs = 0
     DO i=1,Mesh % NumberOfEdges
        EDOFs = MAX( EDOFs, Mesh % Edges(i) % BDOFs )
     END DO
     Mesh % MaxEdgeDOFs = EDOFs

     FDOFs = 0
     DO i=1,Mesh % NumberOfFaces
        FDOFs = MAX( FDOFs, Mesh % Faces(i) % BDOFs )
     END DO
     Mesh % MaxFaceDOFs = FDOFs

     BDOFs = 0
     DO i=1,Mesh % NumberOfBulkElements
        BDOFs = MAX( BDOFs, Mesh % Elements(i) % BDOFs )
     END DO
     Mesh % MaxBDOFs = BDOFs

     IF ( PRESENT( Equation ) ) n = StringToLowerCase( Eq,Equation )

     Perm = 0
     IF ( PRESENT(Equation) ) THEN
        k = InitialPermutation( Perm,Model,Mesh,Eq,DG,GB )
        IF ( k <= 0 ) THEN
           DO i=1,SIZE(Perm)
              Perm(i) = i 
           END DO
           RETURN
        END IF
     ELSE
       k = SIZE( Perm )
     END IF

     IF ( k == SIZE(Perm) ) THEN
        DO i=1,k 
           Perm(i) = i
        END DO
     END IF

     ALLOCATE( InvInitialReorder(k) )
     InvInitialReorder = 0
     DO i=1,SIZE(Perm)
        IF ( Perm(i) > 0 ) InvInitialReorder(Perm(i)) = i
     END DO

!------------------------------------------------------------------------------
!    Compute matrix structure and do bandwidth optimization if requested
!------------------------------------------------------------------------------
     ALLOCATE( Model % RowNonZeros(k) )
     NULLIFY( ListMatrix )

     IF ( PRESENT(Equation) ) THEN
        CALL MakeListMatrix( Model, Mesh, ListMatrix, Perm, k, Eq, DG, GB )
        n = OptimizeBandwidth( ListMatrix, Perm, InvInitialReorder, &
                      k, OptimizeBW, Eq )
     ELSE 
        CALL MakeListMatrix( Model, Mesh, ListMatrix, Perm, k,' ', DG, GB )
        n = OptimizeBandwidth( ListMatrix, Perm, InvInitialReorder, &
                      k, OptimizeBW,' ' )
     ENDIF
!------------------------------------------------------------------------------
!    Ok, create and initialize the matrix
!------------------------------------------------------------------------------
     SELECT CASE( MatrixFormat )
       CASE( MATRIX_CRS )
         Matrix => CRS_CreateMatrix( DOFs*k, &
           Model % TotalMatrixElements,Model % RowNonzeros,DOFs,Perm,.TRUE. )
         Matrix % FORMAT = MatrixFormat
         CALL InitializeMatrix( Matrix, k, ListMatrix, &
               Perm, InvInitialReorder, DOFs )

       CASE( MATRIX_BAND )
         Matrix => Band_CreateMatrix( DOFs*k, DOFs*n,.FALSE.,.TRUE. )

       CASE( MATRIX_SBAND )
         Matrix => Band_CreateMatrix( DOFs*k, DOFs*n,.TRUE.,.TRUE. )
     END SELECT

     CALL FreeListMatrix( k, ListMatrix )

     NULLIFY( Matrix % MassValues, Matrix % DampValues, Matrix % Force )
!------------------------------------------------------------------------------
     Matrix % Subband = DOFs * n
     Matrix % COMPLEX = .FALSE.
     Matrix % FORMAT  = MatrixFormat
!------------------------------------------------------------------------------

     DEALLOCATE( Model % RowNonZeros, InvInitialReorder )
!------------------------------------------------------------------------------
   END FUNCTION CreateMatrix
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
  SUBROUTINE RotateMatrix( Matrix,Vector,n,DIM,DOFs,NodeIndexes,  &
                   Normals,Tangent1,Tangent2 )
DLLEXPORT RotateMatrix
!------------------------------------------------------------------------------

    REAL(KIND=dp) :: Matrix(:,:),Vector(:)
    REAL(KIND=dp), POINTER :: Normals(:,:), Tangent1(:,:),Tangent2(:,:)
    INTEGER :: n,DIM,DOFs,NodeIndexes(:)
!------------------------------------------------------------------------------

    INTEGER :: i,j,k,l
    REAL(KIND=dp) :: s,R(n*DOFs,n*DOFs),Q(n*DOFs,n*DOFs),N1(3),T1(3),T2(3)
!------------------------------------------------------------------------------

    DO i=1,n
      IF ( NodeIndexes(i) > 0 ) THEN

        R = 0.0D0
        DO j=1,n*DOFs
          R(j,j) = 1.0D0
        END DO

        N1 = Normals(NodeIndexes(i),:)

        SELECT CASE(DIM)
          CASE (2)
            R(DOFs*(i-1)+1,DOFs*(i-1)+1) =  N1(1)
            R(DOFs*(i-1)+1,DOFs*(i-1)+2) =  N1(2)

            R(DOFs*(i-1)+2,DOFs*(i-1)+1) = -N1(2)
            R(DOFs*(i-1)+2,DOFs*(i-1)+2) =  N1(1)
          CASE (3)
            T1 = Tangent1(NodeIndexes(i),:)
            T2 = Tangent2(NodeIndexes(i),:)

            R(DOFs*(i-1)+1,DOFs*(i-1)+1) = N1(1)
            R(DOFs*(i-1)+1,DOFs*(i-1)+2) = N1(2)
            R(DOFs*(i-1)+1,DOFs*(i-1)+3) = N1(3)

            R(DOFs*(i-1)+2,DOFs*(i-1)+1) = T1(1)
            R(DOFs*(i-1)+2,DOFs*(i-1)+2) = T1(2)
            R(DOFs*(i-1)+2,DOFs*(i-1)+3) = T1(3)

            R(DOFs*(i-1)+3,DOFs*(i-1)+1) = T2(1)
            R(DOFs*(i-1)+3,DOFs*(i-1)+2) = T2(2)
            R(DOFs*(i-1)+3,DOFs*(i-1)+3) = T2(3)
        END SELECT

        DO j=1,n*DOFs
          DO k=1,n*DOFs
            s = 0.0D0
            DO l=1,n*DOFs
              s = s + R(j,l) * Matrix(l,k)
            END DO
            Q(j,k) = s
          END DO
        END DO

        DO j=1,n*DOFs
          DO k=1,n*DOFs
            s = 0.0D0
            DO l=1,n*DOFs
              s = s + Q(j,l) * R(k,l)
            END DO
            Matrix(j,k) = s
          END DO
        END DO

        DO j=1,n*DOFs
          s = 0.0D0
          DO k=1,n*DOFs
            s = s + R(j,k) * Vector(k)
          END DO
          Q(j,1) = s
        END DO
        Vector(1:n*DOFs) = Q(:,1)
      END IF

    END DO
!------------------------------------------------------------------------------
  END SUBROUTINE RotateMatrix
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
  SUBROUTINE TangentDirections( Normal,Tangent1,Tangent2 )
DLLEXPORT TangentDirections
!------------------------------------------------------------------------------
   REAL(KIND=dp) :: Normal(3),Tangent1(3),Tangent2(3)
!------------------------------------------------------------------------------
   REAL(KIND=dp) :: s
!------------------------------------------------------------------------------
   IF ( ABS( Normal(1) ) <= AEPS ) THEN

     Tangent1(1) = 1
     Tangent1(2) = 0
     Tangent1(3) = 0

     Tangent2(1) = Normal(2)*Tangent1(3) - Normal(3)*Tangent1(2)
     Tangent2(2) = Normal(3)*Tangent1(1) - Normal(1)*Tangent1(3)
     Tangent2(3) = Normal(1)*Tangent1(2) - Normal(2)*Tangent1(1)

   ELSE IF ( ABS( Normal(2) ) <= AEPS ) THEN

     Tangent1(1) = 0
     Tangent1(2) = 1
     Tangent1(3) = 0

     Tangent2(1) = Normal(2)*Tangent1(3) - Normal(3)*Tangent1(2)
     Tangent2(2) = Normal(3)*Tangent1(1) - Normal(1)*Tangent1(3)
     Tangent2(3) = Normal(1)*Tangent1(2) - Normal(2)*Tangent1(1)

   ELSE IF ( ABS( Normal(3) ) <= AEPS ) THEN

     Tangent2(1) = 0
     Tangent2(2) = 0
     Tangent2(3) = 1

     Tangent1(1) = Normal(2)*Tangent2(3) - Normal(3)*Tangent2(2)
     Tangent1(2) = Normal(3)*Tangent2(1) - Normal(1)*Tangent2(3)
     Tangent1(3) = Normal(1)*Tangent2(2) - Normal(2)*Tangent2(1)

   ELSE

     Tangent1(1) =  Normal(2)
     Tangent1(2) = -Normal(1)
     Tangent1(3) =  0.0d0

     s = SQRT( SUM( Tangent1**2 ) )
     Tangent1 = Tangent1 / s

     Tangent2(1) = Normal(2)*Tangent1(3) - Normal(3)*Tangent1(2)
     Tangent2(2) = Normal(3)*Tangent1(1) - Normal(1)*Tangent1(3)
     Tangent2(3) = Normal(1)*Tangent1(2) - Normal(2)*Tangent1(1)

     s = SQRT( SUM( Tangent2**2 ) )
     Tangent2 = Tangent2 / s

   END IF
!------------------------------------------------------------------------------
 END SUBROUTINE TangentDirections
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
   FUNCTION VolumeIntegrate( Model, ElementList, IntegrandFunctionName ) &
       RESULT(Integral)
DLLEXPORT VolumeIntegrate
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Integrates a user-defined function over the specified bulk elements
!
!  ARGUMENTS:
!
!  TYPE(Model_t), POINTER :: Model,  
!     INPUT: All model information (mesh, materials, BCs, etc...)
!
!  INTEGER, DIMENSION(:) :: ElementList
!     INPUT: List of elements that belong to the integration volume
!
!  CHARACTER(LEN=MAX_NAME_LEN) :: IntegrandFunctionName
!     INPUT: Name the function has in the .sif file
!
!  FUNCTION RETURN VALUE:
!    REAL(KIND=dp) :: Integral
!     The value of the volume integral
!      
!******************************************************************************
   TYPE(Model_t) :: Model
   INTEGER, DIMENSION(:) :: ElementList
   CHARACTER(LEN=*) :: IntegrandFunctionName
   REAL(KIND=dp) :: Integral

!------------------------------------------------------------------------------
     INTEGER :: n
     TYPE(Element_t), POINTER :: CurrentElement
     INTEGER, POINTER :: NodeIndexes(:)
     TYPE(Nodes_t)   :: ElementNodes

     TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff
     REAL(KIND=dp), DIMENSION(:), POINTER :: &
         U_Integ,V_Integ,W_Integ,S_Integ

     REAL(KIND=dp), DIMENSION(Model % MaxElementNodes) :: IntegrandFunction
     REAL(KIND=dp) :: s,ug,vg,wg
     REAL(KIND=dp) :: ddBasisddx(Model % MaxElementNodes,3,3)
     REAL(KIND=dp) :: Basis(Model % MaxElementNodes)
     REAL(KIND=dp) :: dBasisdx(Model % MaxElementNodes,3),SqrtElementMetric
     REAL(KIND=dp) :: IntegrandAtGPt, dV
     INTEGER :: N_Integ, t, tg, i
     LOGICAL :: stat

! Need MaxElementNodes only in allocation
     n = Model % MaxElementNodes
     ALLOCATE( ElementNodes % x( n ),   &
               ElementNodes % y( n ),   &
               ElementNodes % z( n ) )

     Integral = 0.0d0

! Loop over all elements in the list
     DO i=1,SIZE(ElementList)

       t = ElementList(i)

       IF ( t < 1 .OR. t > Model % NumberOfBulkElements ) THEN
! do something
       END IF

       CurrentElement => Model % Elements(t)
       n = CurrentElement % TYPE % NumberOfNodes
       NodeIndexes => CurrentElement % NodeIndexes

!------------------------------------------------------------------------------
! Get element nodal coordinates
!------------------------------------------------------------------------------
       ElementNodes % x(1:n) = Model % Nodes % x(NodeIndexes)
       ElementNodes % y(1:n) = Model % Nodes % y(NodeIndexes)
       ElementNodes % z(1:n) = Model % Nodes % z(NodeIndexes)

! Read this from Simulation block in the .sif file
       IntegrandFunction(1:n) = ListGetReal( Model % Simulation, &
           IntegrandFunctionName, n, NodeIndexes )

!------------------------------------------------------------------------------
!    Gauss integration stuff
!------------------------------------------------------------------------------
       IntegStuff = GaussPoints( CurrentElement )
       U_Integ => IntegStuff % u
       V_Integ => IntegStuff % v
       W_Integ => IntegStuff % w
       S_Integ => IntegStuff % s
       N_Integ =  IntegStuff % n

!------------------------------------------------------------------------------
! Loop over Gauss integration points
!------------------------------------------------------------------------------
       DO tg=1,N_Integ

         ug = U_Integ(tg)
         vg = V_Integ(tg)
         wg = W_Integ(tg)

!------------------------------------------------------------------------------
! Need SqrtElementMetric and Basis at the integration point
!------------------------------------------------------------------------------
         stat = ElementInfo( CurrentElement,ElementNodes,ug,vg,wg, &
             SqrtElementMetric,Basis,dBasisdx,ddBasisddx,.FALSE. )

         s = SqrtElementMetric * S_Integ(tg)

! Calculate the function to be integrated at the Gauss point
         IntegrandAtGPt = SUM( IntegrandFunction(1:n) * Basis )

! Use general coordinate system for dV
         dV = CoordinateSqrtMetric( SUM( ElementNodes % x(1:n) * Basis), &
             SUM( ElementNodes % y(1:n) * Basis), &
             SUM( ElementNodes % z(1:n) * Basis) )

         Integral = Integral + s*IntegrandAtGPt*dV

       END DO! of the Gauss integration points

     END DO! of the bulk elements

     DEALLOCATE( ElementNodes % x, &
         ElementNodes % y, &
         ElementNodes % z )
!------------------------------------------------------------------------------
   END FUNCTION VolumeIntegrate
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
   FUNCTION FluxIntegrate( Model, ElementList, IntegrandFunctionName ) &
!------------------------------------------------------------------------------
       RESULT(Integral)
 DLLEXPORT FluxIntegrate
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Integrates the normal component of a user-defined vector function
!    over the specified boundary elements
!
!  ARGUMENTS:
!
!  TYPE(Model_t) :: Model,  
!     INPUT: All model information (mesh, materials, BCs, etc...)
!
!  INTEGER, DIMENSION(:) :: ElementList
!     INPUT: List of elements that belong to the integration boundary
!
!  CHARACTER(LEN=MAX_NAME_LEN) :: IntegrandFunctionName
!     INPUT: Name the function has in the .sif file
!
!  FUNCTION RETURN VALUE:
!    REAL(KIND=dp) :: Integral
!     The value of the flux integral
!      
!******************************************************************************
   TYPE(Model_t) :: Model
   INTEGER, DIMENSION(:) :: ElementList
   CHARACTER(LEN=*) :: IntegrandFunctionName
   REAL(KIND=dp) :: Integral

!------------------------------------------------------------------------------
     INTEGER :: n
     TYPE(Element_t), POINTER :: CurrentElement
     INTEGER, POINTER :: NodeIndexes(:)
     TYPE(Nodes_t)    :: ElementNodes

     TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff
     REAL(KIND=dp), DIMENSION(:), POINTER :: &
         U_Integ,V_Integ,W_Integ,S_Integ

     REAL(KIND=dp), DIMENSION(Model % MaxElementNodes,3) :: IntegrandFunction
!     REAL(KIND=dp), POINTER :: IntegrandFunction(:,:)
     CHARACTER(LEN=2) :: Component
     CHARACTER(LEN=MAX_NAME_LEN) :: IntegrandFunctionComponent
     REAL(KIND=dp) :: s,ug,vg,wg
     REAL(KIND=dp) :: ddBasisddx(Model % MaxElementNodes,3,3)
     REAL(KIND=dp) :: Basis(Model % MaxElementNodes)
     REAL(KIND=dp) :: dBasisdx(Model % MaxElementNodes,3),SqrtElementMetric
     REAL(KIND=dp) :: Normal(3)
     REAL(KIND=dp) :: IntegrandAtGPt(3), FluxAtGPt, dS
     INTEGER :: N_Integ, t, tg, i, j, DIM
     LOGICAL :: stat

     DIM = CoordinateSystemDimension()

! Need MaxElementNodes only in allocation
     n = Model % MaxElementNodes
     ALLOCATE( ElementNodes % x( n ),   &
               ElementNodes % y( n ),   &
               ElementNodes % z( n ) )

     Integral = 0.0d0

! Loop over all elements in the list
     DO i=1,SIZE(ElementList)

       t = ElementList(i)

       IF ( t < 1 .OR. t > Model % NumberOfBulkElements ) THEN
! do something
       END IF

       CurrentElement => Model % Elements(t)
       n = CurrentElement % TYPE % NumberOfNodes
       NodeIndexes => CurrentElement % NodeIndexes

       Model % CurrentElement => Model % Elements(t)
!------------------------------------------------------------------------------
! Get element nodal coordinates
!------------------------------------------------------------------------------
       ElementNodes % x(1:n) = Model % Nodes % x(NodeIndexes)
       ElementNodes % y(1:n) = Model % Nodes % y(NodeIndexes)
       ElementNodes % z(1:n) = Model % Nodes % z(NodeIndexes)

! Read the integrand from Simulation block in the .sif file
! It is assumed to be a contravariant vector, but
! ListGetRealArray doesn t exist, so we READ it component by component
! naming them with suffixes " 1" etc.
       DO j=1,DIM
         WRITE (Component, '(" ",I1.1)') j
         IntegrandFunctionComponent = IntegrandFunctionName(1: &
             LEN_TRIM(IntegrandFunctionName))
         IntegrandFunctionComponent(LEN_TRIM(IntegrandFunctionName)+1: &
             LEN_TRIM(IntegrandFunctionName)+2) = Component
         IntegrandFunction(1:n,j) = ListGetReal( Model % Simulation, &
          IntegrandFunctionComponent(1:LEN_TRIM(IntegrandFunctionComponent)), &
          n, NodeIndexes )
       END DO

!------------------------------------------------------------------------------
!    Gauss integration stuff
!------------------------------------------------------------------------------
       IntegStuff = GaussPoints( CurrentElement )
       U_Integ => IntegStuff % u
       V_Integ => IntegStuff % v
       W_Integ => IntegStuff % w
       S_Integ => IntegStuff % s
       N_Integ =  IntegStuff % n

!------------------------------------------------------------------------------
! Loop over Gauss integration points
!------------------------------------------------------------------------------
       DO tg=1,N_Integ

         ug = U_Integ(tg)
         vg = V_Integ(tg)
         wg = W_Integ(tg)

!------------------------------------------------------------------------------
! Need SqrtElementMetric and Basis at the integration point
!------------------------------------------------------------------------------
         stat = ElementInfo( CurrentElement,ElementNodes,ug,vg,wg, &
             SqrtElementMetric,Basis,dBasisdx,ddBasisddx,.FALSE. )

! If we want to allow covariant integrand vectors given
! we would also need Metric, and read it as follows...
!     IF ( CurrentCoordinateSystem() /= Cartesian ) THEN
!       x = SUM( nodes % x(1:n) * Basis )
!       y = SUM( nodes % y(1:n) * Basis )
!       z = SUM( nodes % z(1:n) * Basis )
!     END IF
!
!     CALL CoordinateSystemInfo( Metric,SqrtMetric,Symb,dSymb,x,y,z )
!     s = SqrtMetric * SqrtElementMetric * S_Integ(t)
! And also FluxAtGpt...
! Now we won t need Metric, so get SqrtMetric later...

         s = SqrtElementMetric * S_Integ(tg)

! Get normal to the element boundary at the integration point
! N.B. NormalVector returns covariant normal vector
         Normal = NormalVector( CurrentElement,ElementNodes,ug,vg,.TRUE. )

! Calculate the contravariant vector function to be integrated
! at the Gauss point
         DO j=1,DIM
           IntegrandAtGPt(j) = SUM( IntegrandFunction(1:n,j) * Basis )
         END DO
! Calculate the normal component of the vector function
         FluxAtGPt = SUM( IntegrandAtGPt * Normal )

! Use general coordinate system for dS
! Would be included in s by SqrtMetric
         dS = CoordinateSqrtMetric( SUM( ElementNodes % x(1:n) * Basis), &
             SUM( ElementNodes % y(1:n) * Basis), &
             SUM( ElementNodes % z(1:n) * Basis) )

         Integral = Integral + s*FluxAtGPt*dS

       END DO! of the Gauss integration points

     END DO! of the boundary elements

     DEALLOCATE( ElementNodes % x, &
         ElementNodes % y, &
         ElementNodes % z )
!------------------------------------------------------------------------------
   END FUNCTION FluxIntegrate
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
   FUNCTION SurfaceIntegrate( Model, ElementList, IntegrandFunctionName ) &
       RESULT(Integral)
 DLLEXPORT SurfaceIntegrate
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Integrates A user-defined vector function 
!    over the specified boundary elements
!
!  ARGUMENTS:
!
!  TYPE(Model_t), POINTER :: Model,  
!     INPUT: All model information (mesh, materials, BCs, etc...)
!
!  INTEGER, DIMENSION(:) :: ElementList
!     INPUT: List of elements that belong to the integration boundary
!
!  CHARACTER(LEN=MAX_NAME_LEN) :: IntegrandFunctionName
!     INPUT: Name the function has in the .sif file
!
!  FUNCTION RETURN VALUE:
!    REAL(KIND=dp), DIMENSION(3) :: Integral
!     The vector value of the integral
!      
!******************************************************************************
   TYPE(Model_t) :: Model
   INTEGER, DIMENSION(:) :: ElementList
   CHARACTER(LEN=*) :: IntegrandFunctionName
   REAL(KIND=dp), DIMENSION(3) :: Integral

!------------------------------------------------------------------------------
     INTEGER :: n
     TYPE(Element_t), POINTER :: CurrentElement
     INTEGER, POINTER :: NodeIndexes(:)
     TYPE(Nodes_t)    :: ElementNodes

     TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff
     REAL(KIND=dp), DIMENSION(:), POINTER :: &
         U_Integ,V_Integ,W_Integ,S_Integ

     REAL(KIND=dp), DIMENSION(Model % MaxElementNodes,3) :: IntegrandFunction
!     REAL(KIND=dp), POINTER :: IntegrandFunction(:,:)
     CHARACTER(LEN=2) :: Component
     CHARACTER(LEN=MAX_NAME_LEN) :: IntegrandFunctionComponent
     REAL(KIND=dp) :: s,ug,vg,wg
     REAL(KIND=dp) :: ddBasisddx(Model % MaxElementNodes,3,3)
     REAL(KIND=dp) :: Basis(Model % MaxElementNodes)
     REAL(KIND=dp) :: dBasisdx(Model % MaxElementNodes,3),SqrtElementMetric
!     REAL(KIND=dp) :: Normal(3)
     REAL(KIND=dp) :: IntegrandAtGPt(3), dS
     INTEGER :: N_Integ, t, tg, i, j, DIM
     LOGICAL :: stat

     DIM = CoordinateSystemDimension()

! Need MaxElementNodes only in allocation
     n = Model % MaxElementNodes
     ALLOCATE( ElementNodes % x( n ),   &
               ElementNodes % y( n ),   &
               ElementNodes % z( n ) )

     Integral = 0.0d0

! Loop over all elements in the list
     DO i=1,SIZE(ElementList)

       t = ElementList(i)

       IF ( t < 1 .OR. t > Model % NumberOfBulkElements ) THEN
! do something
       END IF

       CurrentElement => Model % Elements(t)
       Model % CurrentElement => CurrentElement
       n = CurrentElement % TYPE % NumberOfNodes
       NodeIndexes => CurrentElement % NodeIndexes

!------------------------------------------------------------------------------
! Get element nodal coordinates
!------------------------------------------------------------------------------
       ElementNodes % x(1:n) = Model % Nodes % x(NodeIndexes)
       ElementNodes % y(1:n) = Model % Nodes % y(NodeIndexes)
       ElementNodes % z(1:n) = Model % Nodes % z(NodeIndexes)

! Read the integrand from Simulation block in the .sif file
! It is assumed to be a contravariant vector, but
! ListGetRealArray doesn t exist, so we READ it component by component
! naming them with suffixes " 1" etc.
       DO j=1,DIM
         WRITE (Component, '(" ",I1.1)') j
         IntegrandFunctionComponent = IntegrandFunctionName(1: &
             LEN_TRIM(IntegrandFunctionName))
         IntegrandFunctionComponent(LEN_TRIM(IntegrandFunctionName)+1: &
             LEN_TRIM(IntegrandFunctionName)+2) = Component
         IntegrandFunction(1:n,j) = ListGetReal( Model % Simulation, &
          IntegrandFunctionComponent(1:LEN_TRIM(IntegrandFunctionComponent)), &
          n, NodeIndexes )
       END DO

!------------------------------------------------------------------------------
!    Gauss integration stuff
!------------------------------------------------------------------------------
       IntegStuff = GaussPoints( CurrentElement )
       U_Integ => IntegStuff % u
       V_Integ => IntegStuff % v
       W_Integ => IntegStuff % w
       S_Integ => IntegStuff % s
       N_Integ =  IntegStuff % n

!------------------------------------------------------------------------------
! Loop over Gauss integration points
!------------------------------------------------------------------------------
       DO tg=1,N_Integ

         ug = U_Integ(tg)
         vg = V_Integ(tg)
         wg = W_Integ(tg)

!------------------------------------------------------------------------------
! Need SqrtElementMetric and Basis at the integration point
!------------------------------------------------------------------------------
         stat = ElementInfo( CurrentElement,ElementNodes,ug,vg,wg, &
             SqrtElementMetric,Basis,dBasisdx,ddBasisddx,.FALSE. )

! If we want to allow covariant integrand vectors given
! we would also need Metric, and read it as follows...
!     IF ( CurrentCoordinateSystem() /= Cartesian ) THEN
!       x = SUM( nodes % x(1:n) * Basis )
!       y = SUM( nodes % y(1:n) * Basis )
!       z = SUM( nodes % z(1:n) * Basis )
!     END IF
!
!     CALL CoordinateSystemInfo( Metric,SqrtMetric,Symb,dSymb,x,y,z )
!     s = SqrtMetric * SqrtElementMetric * S_Integ(t)
! Now we won t need Metric, so get SqrtMetric later...

         s = SqrtElementMetric * S_Integ(tg)

! If you need normal directly at the integration point
!         Normal = NormalVector( CurrentElement,ElementNodes,ug,vg,.TRUE. )

! Calculate the contravariant vector function to be integrated
! at the Gauss point
         DO j=1,DIM
           IntegrandAtGPt(j) = SUM( IntegrandFunction(1:n,j) * Basis )
         END DO

! Use general coordinate system for dS
! Would be included in s by SqrtMetric
         dS = CoordinateSqrtMetric( SUM( ElementNodes % x(1:n) * Basis), &
             SUM( ElementNodes % y(1:n) * Basis), &
             SUM( ElementNodes % z(1:n) * Basis) )

         DO j=1,DIM
           Integral(j) = Integral(j) + s*IntegrandAtGPt(j)*dS
         END DO

       END DO! of the Gauss integration points

     END DO! of the boundary elements

     DEALLOCATE( ElementNodes % x, &
         ElementNodes % y, &
         ElementNodes % z )
!------------------------------------------------------------------------------
   END FUNCTION SurfaceIntegrate
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
   FUNCTION LineIntegrate( Model, LineElement, LineElementNodes, &
       IntegrandFunctionName, QuadrantTreeExists, RootQuadrant ) &
       RESULT(Integral)
 DLLEXPORT LineIntegrate
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Integrates the normal component of a user-defined vector function
!    over a specified line element
!
!  ARGUMENTS:
!
!  TYPE(Model_t), POINTER :: Model,  
!     INPUT: All model information (mesh, materials, BCs, etc...)
!
!  TYPE(Element_t) :: LineElement
!     INPUT: Line element that belongs to the line of integration
!
!  REAL(KIND=dp), DIMENSION(LineElement % Type % NumberOfNodes,3) ::
!     LineElementNodes
!     INPUT: List of nodal point coordinates
!
!  CHARACTER(LEN=MAX_NAME_LEN) :: IntegrandFunctionName
!     INPUT: Name the function has in the .sif file or somewhere else
!
!  LOGICAL :: QuadrantTreeExists
!     INPUT: QuadrantTree has been built, use it in element search
!
!  TYPE(Quadrant_t), POINTER :: RootQuadrant
!     OUTPUT: Quadrant tree structure root
!
!
!  FUNCTION RETURN VALUE:
!    REAL(KIND=dp) :: Integral
!     The value of the flux integral
!      
!******************************************************************************
   TYPE(Model_t) :: Model
! TARGET only for CurrentElement
   TYPE(Element_t), TARGET :: LineElement
   REAL(KIND=dp), DIMENSION(:,:), TARGET :: LineElementNodes
   CHARACTER(LEN=*) :: IntegrandFunctionName
   REAL(KIND=dp) :: Integral
   LOGICAL :: QuadrantTreeExists
   TYPE(Quadrant_t), POINTER :: RootQuadrant
!------------------------------------------------------------------------------
     INTEGER :: n
! Only one element at a time, need CurrentElement only for NormalVector!
     TYPE(Element_t), POINTER :: CurrentElement
! LineElement nodes don t belong to global node structure
! Need the structure for the function calls
     TYPE(Nodes_t) :: ElementNodes

     TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff
     REAL(KIND=dp), DIMENSION(:), POINTER :: &
         U_Integ,V_Integ,W_Integ,S_Integ

! IntegrandFunction at the bulk element nodal points
     REAL(KIND=dp), DIMENSION(Model % MaxElementNodes,3) :: IntegrandAtNodes
! IntegrandFunction at the Gauss points
     REAL(KIND=dp), DIMENSION(LineElement % TYPE % GaussPoints,3) :: IntegrandFunction
     CHARACTER(LEN=2) :: Component
     CHARACTER(LEN=MAX_NAME_LEN) :: IntegrandFunctionComponent
     REAL(KIND=dp) :: s,ug,vg,wg
     REAL(KIND=dp) :: ddBasisddx(LineElement % TYPE % NumberOfNodes,3,3)
     REAL(KIND=dp) :: Basis(LineElement % TYPE % NumberOfNodes)
     REAL(KIND=dp) :: dBasisdx(LineElement % TYPE % NumberOfNodes,3),SqrtElementMetric
     REAL(KIND=dp) :: Normal(3)
! IntegrandFunction already at GPts
     REAL(KIND=dp) :: FluxAtGPt, dS
     INTEGER :: N_Integ, t, tg, i, j, DIM
     LOGICAL :: stat
! Search for the bulk element each Gauss point belongs to
     TYPE(Element_t), POINTER :: BulkElement
     TYPE(Nodes_t) :: BulkElementNodes
     INTEGER, POINTER :: NodeIndexes(:)
     REAL(KIND=dp), DIMENSION(3) :: LocalCoordsInBulkElem
     REAL(KIND=dp), DIMENSION(3) :: Point
     INTEGER :: nBulk, maxlevel=10, k, Quadrant
     TYPE(Quadrant_t), POINTER :: LeafQuadrant

     DIM = CoordinateSystemDimension()

     n = LineElement % TYPE % NumberOfNodes

     Integral = 0.0d0

!------------------------------------------------------------------------------
! Get element nodal coordinates
!------------------------------------------------------------------------------
! Move from LineElementNodes to Nodes_t structure
     ElementNodes % x => LineElementNodes(1:n,1)
     ElementNodes % y => LineElementNodes(1:n,2)
     ElementNodes % z => LineElementNodes(1:n,3)

!------------------------------------------------------------------------------
!    Gauss integration stuff
!------------------------------------------------------------------------------
     IntegStuff = GaussPoints( LineElement )
     U_Integ => IntegStuff % u
     V_Integ => IntegStuff % v
     W_Integ => IntegStuff % w
     S_Integ => IntegStuff % s
     N_Integ =  IntegStuff % n

!------------------------------------------------------------------------------
! Loop over Gauss integration points
!------------------------------------------------------------------------------
     DO tg=1,N_Integ

       ug = U_Integ(tg)
       vg = V_Integ(tg)
       wg = W_Integ(tg)

!------------------------------------------------------------------------------
! Need SqrtElementMetric and Basis at the integration point
!------------------------------------------------------------------------------
       stat = ElementInfo( LineElement,ElementNodes,ug,vg,wg, &
           SqrtElementMetric,Basis,dBasisdx,ddBasisddx,.FALSE. )

! If we want to allow covariant integrand vectors given... (see FluxIntegrate)

       s = SqrtElementMetric * S_Integ(tg)

! Find in which bulk element the Gauss point belongs to
       IF ( QuadrantTreeExists ) THEN
! Find the last existing quadrant that the point belongs to
         Point = (/ SUM( ElementNodes % x(1:n) * Basis), &
             SUM( ElementNodes % y(1:n) * Basis), &
             SUM( ElementNodes % z(1:n) * Basis) /)
!         PRINT*,'Point:', Point
         CALL FindLeafElements(Point, DIM, RootQuadrant, LeafQuadrant)         
!         PRINT*,'Elems in LeafQuadrant',LeafQuadrant % NElemsInQuadrant
! Go through the bulk elements in the last ChildQuadrant only
         nBulk = Model % MaxElementNodes
         ALLOCATE( BulkElementNodes % x( nBulk ),   &
             BulkElementNodes % y( nBulk ),   &
             BulkElementNodes % z( nBulk ) )
!         PRINT*,'Elements:', LeafQuadrant % Elements
         DO k=1, LeafQuadrant % NElemsInQuadrant
           BulkElement => Model % Elements( &
               LeafQuadrant % Elements(k) )
           nBulk = BulkElement % TYPE % NumberOfNodes
           NodeIndexes => BulkElement % NodeIndexes
           BulkElementNodes % x(1:nBulk) = Model % Nodes % x(NodeIndexes)
           BulkElementNodes % y(1:nBulk) = Model % Nodes % y(NodeIndexes)
           BulkElementNodes % z(1:nBulk) = Model % Nodes % z(NodeIndexes)
           IF ( PointInElement( BulkElement,BulkElementNodes, &
               (/ SUM( ElementNodes % x(1:n) * Basis), &
               SUM( ElementNodes % y(1:n) * Basis), &
               SUM( ElementNodes % z(1:n) * Basis) /), &
               LocalCoordsInBulkElem) ) EXIT
         END DO
!         PRINT*,'Point in Element: ', LeafQuadrant % Elements(k)
        ELSE
! Go through all BulkElements
! Need MaxElementNodes only in allocation
         nBulk = Model % MaxElementNodes
         ALLOCATE( BulkElementNodes % x( nBulk ),   &
             BulkElementNodes % y( nBulk ),   &
             BulkElementNodes % z( nBulk ) )
         DO k=1,Model % NumberOfBulkElements
           BulkElement => Model % Elements(k)
           nBulk = BulkElement % TYPE % NumberOfNodes
           NodeIndexes => BulkElement % NodeIndexes
           BulkElementNodes % x(1:nBulk) = Model % Nodes % x(NodeIndexes)
           BulkElementNodes % y(1:nBulk) = Model % Nodes % y(NodeIndexes)
           BulkElementNodes % z(1:nBulk) = Model % Nodes % z(NodeIndexes)
           IF ( PointInElement(BulkElement,BulkElementNodes, &
               (/ SUM( ElementNodes % x(1:n) * Basis), &
               SUM( ElementNodes % y(1:n) * Basis), &
               SUM( ElementNodes % z(1:n) * Basis) /), &
               LocalCoordsInBulkElem) ) EXIT
         END DO
!         PRINT*,'Point in Element: ', k
       END IF
! Calculate value of the function in the bulk element
! Read the integrand from Simulation block in the .sif file
! It is assumed to be a contravariant vector, but
! ListGetRealArray doesn t exist, so we read it component by component
! naming them with suffixes " 1" etc.

      DO j=1,DIM
        WRITE (Component, '(" ",I1.1)') j
        IntegrandFunctionComponent = IntegrandFunctionName(1: &
            LEN_TRIM(IntegrandFunctionName))
        IntegrandFunctionComponent(LEN_TRIM(IntegrandFunctionName)+1: &
            LEN_TRIM(IntegrandFunctionName)+2) = Component
        IntegrandAtNodes(1:nBulk,j) = ListGetReal( Model % Simulation, &
            IntegrandFunctionComponent(1:LEN_TRIM(IntegrandFunctionComponent)), &
            nBulk, NodeIndexes )
      END DO

      DO j=1,DIM
        IntegrandFunction(tg,j) = InterpolateInElement( BulkElement, &
            IntegrandAtNodes(1:nBulk,j),LocalCoordsInBulkElem(1), &
            LocalCoordsInBulkElem(2),LocalCoordsInBulkElem(3) )
      END DO

      DEALLOCATE( BulkElementNodes % x, &
          BulkElementNodes % y, &
          BulkElementNodes % z )

! Get normal to the element boundary at the integration point
! N.B. NormalVector returns covariant normal vector
! NormalVector defined weirdly, doesn t accept LineElement as an argument,
! but wants a pointer
         CurrentElement => LineElement
         Normal = NormalVector( CurrentElement,ElementNodes,ug,vg,.FALSE. )
! Might be consistently in wrong direction, since no check
!         Normal = NormalVector( CurrentElement,ElementNodes,ug,vg,.TRUE. )

! Contravariant vector function to be integrated is already
! at the Gauss point

! Calculate the normal component of the vector function
         FluxAtGPt = SUM( IntegrandFunction(tg,1:DIM) * Normal(1:DIM) )

! Use general coordinate system for dS
! Would be included in s by SqrtMetric
         dS = CoordinateSqrtMetric( SUM( ElementNodes % x(1:n) * Basis), &
             SUM( ElementNodes % y(1:n) * Basis), &
             SUM( ElementNodes % z(1:n) * Basis) )

         Integral = Integral + s*FluxAtGPt*dS

       END DO! of the Gauss integration points

!------------------------------------------------------------------------------
   END FUNCTION LineIntegrate
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   FUNCTION ElementArea( Mesh,Element,N ) RESULT(A)
DLLEXPORT ElementArea
!------------------------------------------------------------------------------
     TYPE(Mesh_t), POINTER :: Mesh
     INTEGER :: N
     TYPE(Element_t) :: Element
!------------------------------------------------------------------------------

     REAL(KIND=dp), TARGET :: NX(N),NY(N),NZ(N)

     REAL(KIND=dp) :: A,R1,R2,Z1,Z2,S,U,V,W,X,Y,Z

     TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff
     INTEGER :: N_Integ,t

     REAL(KIND=dp) :: Metric(3,3),Symb(3,3,3),dSymb(3,3,3,3), &
              SqrtMetric,SqrtElementMetric

     TYPE(Nodes_t) :: Nodes

     LOGICAL :: stat

     REAL(KIND=dp) :: ddBasisddx(n,3,3)
     REAL(KIND=dp) :: Basis(n)
     REAL(KIND=dp) :: dBasisdx(n,3)

     REAL(KIND=dp), DIMENSION(:), POINTER :: U_Integ,V_Integ,W_Integ,S_Integ
!------------------------------------------------------------------------------
 
#if 0
     IF ( ( CurrentCoordinateSystem() == AxisSymmetric .OR. &
            CurrentCoordinateSystem() == CylindricSymmetric ) .AND. Element % TYPE % ELementCode / 100 == 2 ) THEN
       R1 = Mesh % Nodes % x(Element % NodeIndexes(1))
       R2 = Mesh % Nodes % x(Element % NodeIndexes(2))

       Z1 = Mesh % Nodes % y(Element % NodeIndexes(1))
       Z2 = Mesh % Nodes % y(Element % NodeIndexes(2))

       A = PI*ABS(R1+R2)*SQRT((Z1-Z2)*(Z1-Z2)+(R1-R2)*(R1-R2))
     ELSE 
#endif
       Nodes % x => NX
       Nodes % y => NY
       Nodes % z => NZ

       Nodes % x = Mesh % Nodes % x(Element % NodeIndexes)
       Nodes % y = Mesh % Nodes % y(Element % NodeIndexes)
       Nodes % z = Mesh % Nodes % z(Element % NodeIndexes)

       IntegStuff = GaussPoints( element )
       U_Integ => IntegStuff % u
       V_Integ => IntegStuff % v
       W_Integ => IntegStuff % w
       S_Integ => IntegStuff % s
       N_Integ  = IntegStuff % n
!
!------------------------------------------------------------------------------
!   Now we start integrating
!------------------------------------------------------------------------------
!
       A = 0.0
       DO t=1,N_Integ
!
!        Integration stuff
!
         u = U_Integ(t)
         v = V_Integ(t)
         w = W_Integ(t)
!
!------------------------------------------------------------------------------
!        Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
         stat = ElementInfo( Element,Nodes,u,v,w,SqrtElementMetric, &
                    Basis,dBasisdx,ddBasisddx,.FALSE. )
!------------------------------------------------------------------------------
!        Coordinatesystem dependent info
!------------------------------------------------------------------------------
         IF ( CurrentCoordinateSystem() /= Cartesian ) THEN
           X = SUM( Nodes % x(1:n)*Basis )
           Y = SUM( Nodes % y(1:n)*Basis )
           Z = SUM( Nodes % z(1:n)*Basis )

           SqrtMetric = CoordinateSqrtMetric( x,y,z )
           A =  A + SqrtMetric * SqrtElementMetric * S_Integ(t)
         ELSE
           A =  A + SqrtElementMetric * S_Integ(t)
         END IF
       END DO
#if 0
     END IF
#endif

   END FUNCTION ElementArea
!------------------------------------------------------------------------------



END MODULE ElementUtils
