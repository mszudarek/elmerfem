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
! * List handling utilities ...
! *
! ******************************************************************************
! *
! *                     Author:       Juha Ruokolainen
! *
! *                    Address: Center for Scientific Computing
! *                                Tietotie 6, P.O. BOX 405
! *                                  02
! *                                  Tel. +358 0 457 2723
! *                                Telefax: +358 0 457 2302
! *                              EMail: Juha.Ruokolainen@csc.fi
! *
! *                       Date: 02 Jun 1997
! *
! *                Modified by:
! *
! *       Date of modification:
! *
! * Revision 1.54  2004/03/30 12:05:37  jpr
! * Added a user procedure call interface to ListGetRealArray().
! *
! * Revision 1.53  2004/03/02 08:12:36  jpr
! * Some formatting.
! *
! * Revision 1.52  2004/03/02 07:53:06  jpr
! * Traded skandinavian letter caseconversion support for efficiency.
! * Started log.
! *
! *
! * $Id: Lists.f90,v 1.64 2005/04/04 06:18:29 jpr Exp $
! *****************************************************************************/

!------------------------------------------------------------------------------

MODULE Lists

   USE Messages
   USE GeneralUtils

   IMPLICIT NONE

   INTEGER, PARAMETER :: LIST_TYPE_CONSTANT_SCALAR = 1
   INTEGER, PARAMETER :: LIST_TYPE_CONSTANT_TENSOR = 2
   INTEGER, PARAMETER :: LIST_TYPE_VARIABLE_SCALAR = 3
   INTEGER, PARAMETER :: LIST_TYPE_VARIABLE_TENSOR = 4
   INTEGER, PARAMETER :: LIST_TYPE_LOGICAL = 5
   INTEGER, PARAMETER :: LIST_TYPE_STRING  = 6
   INTEGER, PARAMETER :: LIST_TYPE_INTEGER = 7
   INTEGER, PARAMETER :: LIST_TYPE_CONSTANT_SCALAR_STR = 8
   INTEGER, PARAMETER :: LIST_TYPE_CONSTANT_TENSOR_STR = 9
   INTEGER, PARAMETER :: LIST_TYPE_VARIABLE_SCALAR_STR = 10
   INTEGER, PARAMETER :: LIST_TYPE_VARIABLE_TENSOR_STR = 11

   INTERFACE
     FUNCTION ExecIntFunction( Proc,Md ) RESULT(int)
       USE Types
#ifdef SGI
       INTEGER :: Proc
#else
       INTEGER(KIND=AddrInt) :: Proc
#endif
       TYPE(Model_t) :: Md

       INTEGER :: int
     END FUNCTION ExecIntFunction
   END INTERFACE

   INTERFACE
     FUNCTION ExecRealFunction( Proc,Md,Node,Temp ) RESULT(dbl)
       USE Types

#ifdef SGI
       INTEGER :: Proc
#else
       INTEGER(KIND=AddrInt) :: Proc
#endif
       TYPE(Model_t) :: Md
       INTEGER :: Node
       REAL(KIND=dp) :: Temp(*)

       REAL(KIND=dp) :: dbl
     END FUNCTION ExecRealFunction
   END INTERFACE

   INTERFACE
     SUBROUTINE ExecRealArrayFunction( Proc,Md,Node,Temp,F )
       USE Types

#ifdef SGI
       INTEGER :: Proc
#else
       INTEGER(KIND=AddrInt) :: Proc
#endif
       TYPE(Model_t) :: Md
       INTEGER :: Node,n1,n2
       REAL(KIND=dp) :: Temp(*)

       REAL(KIND=dp) :: F(:,:)
     END SUBROUTINE ExecRealArrayFunction
   END INTERFACE

   INTERFACE
     FUNCTION ExecConstRealFunction( Proc,Md,x,y,z ) RESULT(dbl)
       USE Types

#ifdef SGI
       INTEGER :: Proc
#else
       INTEGER(KIND=AddrInt) :: Proc
#endif
       TYPE(Model_t) :: Md

       REAL(KIND=dp) :: dbl,x,y,z
     END FUNCTION ExecConstRealFunction
   END INTERFACE


CONTAINS

!------------------------------------------------------------------------------
  FUNCTION InitialPermutation( Perm,Model,Mesh,Equation,DGSolver,GlobalBubbles ) RESULT(k)
!------------------------------------------------------------------------------
     TYPE(Model_t) :: Model
     TYPE(Mesh_t),  POINTER :: Mesh
     INTEGER :: Perm(:)
     INTEGER :: k
     CHARACTER(LEN=*) :: Equation
     LOGICAL, OPTIONAL :: DGSolver, GlobalBubbles
!------------------------------------------------------------------------------
     INTEGER i,j,l,t,n,e, EDOFs, FDOFs, BDOFs
     INTEGER :: Indexes(128)
     LOGICAL :: FoundDG, DG, GB
     TYPE(Element_t),POINTER :: Element, Edge, Face
!------------------------------------------------------------------------------
     Perm = 0
     k = 0
     EDOFs = Mesh % MaxEdgeDOFs
     FDOFs = Mesh % MaxFaceDOFs
     BDOFs = Mesh % MaxBDOFs

     GB = .FALSE.
     IF ( PRESENT(GlobalBubbles) ) GB=GlobalBubbles

     DG = .FALSE.
     IF ( PRESENT(DGSolver) ) DG=DGSolver
     FoundDG = .FALSE.
     IF ( DG ) THEN
       DO t=1,Mesh % NumberOfEdges
         n = 0
         Element => Mesh % Edges(t) % BoundaryInfo % Left
         IF ( ASSOCIATED( Element ) ) THEN
             IF ( CheckElementEquation(Model,Element,Equation) ) THEN
                FoundDG = FoundDG .OR. Element % DGDOFs > 0
                DO j=1,Element % DGDOFs
                   n = n + 1
                   Indexes(n) = Element % DGIndexes(j)
                END DO
             END IF
         END IF

         Element => Mesh % Edges(t) % BoundaryInfo % Right
         IF ( ASSOCIATED( Element ) ) THEN
             IF ( CheckElementEquation(Model,Element,Equation) ) THEN
                FoundDG = FoundDG .OR. Element % DGDOFs > 0
                DO j=1,Element % DGDOFs
                   n = n + 1
                   Indexes(n) = Element % DGIndexes(j)
                END DO
             END IF
         END IF

         DO i=1,n
            j = Indexes(i)
            IF ( Perm(j) == 0 ) THEN
                k = k + 1
               Perm(j) = k
            END IF
         END DO
       END DO

       DO t=1,Mesh % NumberOfFaces
         n = 0
         Element => Mesh % Faces(t) % BoundaryInfo % Left
         IF ( ASSOCIATED( Element ) ) THEN
             IF ( CheckElementEquation(Model,Element,Equation) ) THEN
                FoundDG = FoundDG .OR. Element % DGDOFs > 0
                DO j=1,Element % DGDOFs
                   n = n + 1
                   Indexes(n) = Element % DGIndexes(j)
                END DO
             END IF
         END IF

         Element => Mesh % Faces(t) % BoundaryInfo % Right
         IF ( ASSOCIATED( Element ) ) THEN
             IF ( CheckElementEquation(Model,Element,Equation) ) THEN
                FoundDG = FoundDG .OR. Element % DGDOFs > 0
                DO j=1,Element % DGDOFs
                   n = n + 1
                   Indexes(n) = Element % DGIndexes(j)
                END DO
             END IF
         END IF

         DO i=1,n
            j = Indexes(i)
            IF ( Perm(j) == 0 ) THEN
                k = k + 1
               Perm(j) = k
            END IF
         END DO
       END DO

       IF ( FoundDG ) THEN
          RETURN ! Discontinuous galerkin !!!
       END IF
     END IF

     n = Mesh % NumberOfBulkElements + Mesh % NumberOFBoundaryElements
     t = 1
     DO WHILE( t <= n )
       DO WHILE( t<=n )
         Element => Mesh % Elements(t)
         IF ( CheckElementEquation( Model, Element, Equation ) ) EXIT
         t = t + 1
       END DO

       IF ( t > n ) EXIT

       DO i=1,Element % NDOFs
         j = Element % NodeIndexes(i)
         IF ( Perm(j) == 0 ) THEN
           k = k + 1
           Perm(j) = k
         END IF
       END DO

       IF ( ASSOCIATED( Element % EdgeIndexes ) ) THEN
          DO i=1,Element % Type % NumberOfEdges
             Edge => Mesh % Edges( Element % EdgeIndexes(i) )
             DO e=1,Edge % BDOFs
                j = Mesh % NumberOfNodes + EDOFs*(Element % EdgeIndexes(i)-1) + e
                IF ( Perm(j) == 0 ) THEN
                   k = k + 1
                   Perm(j) =  k
                END IF
             END DO
          END DO
       END IF

       IF ( ASSOCIATED( Element % FaceIndexes ) ) THEN
          DO i=1,Element % Type % NumberOfFaces
             Face => Mesh % Faces( Element % FaceIndexes(i) )
             DO e=1,Face % BDOFs
                j = Mesh % NumberOfNodes + EDOFs*Mesh % NumberOfEdges + &
                          FDOFs*(Element % FaceIndexes(i)-1) + e
                IF ( Perm(j) == 0 ) THEN
                   k = k + 1
                   Perm(j) =  k
                END IF
             END DO
          END DO
       END IF

       IF ( GB .AND. ASSOCIATED( Element % BubbleIndexes ) ) THEN
         DO i=1,Element % BDOFs
            j = Mesh % NumberOfNodes + EDOFs*Mesh % NumberOfEdges + &
                 FDOFs*Mesh % NumberOfFaces + Element % BubbleIndexes(i)
            IF ( Perm(j) == 0 ) THEN
               k = k + 1
               Perm(j) =  k
            END IF
         END DO
       END IF

       t = t + 1
     END DO

     IF ( Equation == 'heat equation' ) THEN
        t = Mesh % NumberOfBulkElements + 1
        n = Mesh % NumberOfBulkElements + Mesh % NumberOfBoundaryElements
        DO WHILE( t<= n )
          Element => Mesh % Elements(t)
          IF ( ASSOCIATED( Element % BoundaryInfo % GebhardtFactors % Elements) ) THEN
             DO i=1,Element % Type % NumberOfNodes
               j = Element % NodeIndexes(i)
               IF ( Perm(j) == 0 ) THEN
                 k = k + 1
                 Perm(j) = k
               END IF
             END DO
          END IF
          t = t + 1
        END DO
     END IF

     t = Mesh % NumberOfBulkElements + 1
     n = Mesh % NumberOfBulkElements + Mesh % NumberOfBoundaryElements
     DO WHILE( t<= n )
       Element => Mesh % Elements(t)
       IF ( Element % Type % ElementCode == 102 ) THEN
          DO i=1,Element % Type % NumberOfNodes
            j = Element % NodeIndexes(i)
            IF ( Perm(j) == 0 ) THEN
              k = k + 1
              Perm(j) = k
            END IF
          END DO
       END IF
       t = t + 1
     END DO
!------------------------------------------------------------------------------
   END FUNCTION InitialPermutation
!------------------------------------------------------------------------------


!---------------------------------------------------------------------------
!   Check if given element belongs to a body for which given equation
!   should be solved
!---------------------------------------------------------------------------
    FUNCTION CheckElementEquation( Model,Element,Equation ) Result(Flag)
DLLEXPORT CheckElementEquation

      TYPE(Element_t), POINTER :: Element
      TYPE(Model_t) :: Model
      CHARACTER(LEN=*) :: Equation

      LOGICAL :: Flag,GotIt

      INTEGER :: k,body_id
       
      Flag = .FALSE.
      body_id = Element % BodyId
      IF ( body_id > 0 .AND. body_id <= Model % NumberOfBodies ) THEN
         k = ListGetInteger( Model % Bodies(body_id) % Values, 'Equation', &
                 minv=1, maxv=Model % NumberOFEquations )
         IF ( k > 0 ) THEN
            Flag = ListGetLogical( Model % Equations(k) % Values, Equation,gotIt )
         END IF
      END IF
!---------------------------------------------------------------------------
   END FUNCTION CheckElementEquation
!---------------------------------------------------------------------------


!------------------------------------------------------------------------------
    FUNCTION StringToLowerCase( to,from ) RESULT(n)
DLLEXPORT StringToLowerCase
!------------------------------------------------------------------------------
      CHARACTER(LEN=*) :: to,from
      INTEGER :: n
!------------------------------------------------------------------------------
      INTEGER :: i,j,A=ICHAR('A'),Z=ICHAR('Z'),U2L=ICHAR('a')-ICHAR('A')

      n = MIN( LEN(to), LEN_TRIM(from) )

      to = ' '
      DO i=1,n
        j = ICHAR( from(i:i) )
        IF ( j >= A .AND. j <= Z ) THEN
          to(i:i) = CHAR(j+U2L) 
        ELSE
          to(i:i) = from(i:i)
        END IF
      END DO
    END FUNCTION StringToLowerCase
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    SUBROUTINE VariableAdd( Variables,Mesh,Solver,Name,DOFs,Values,Perm,Output )
DLLEXPORT VariableAdd
!------------------------------------------------------------------------------
      TYPE(Variable_t), POINTER :: Variables
      TYPE(Mesh_t), POINTER :: Mesh
      TYPE(Solver_t), POINTER  :: Solver
      CHARACTER(LEN=*) :: Name
      INTEGER :: DOFs
      INTEGER, OPTIONAL, POINTER :: Perm(:)
      REAL(KIND=dp), POINTER :: Values(:)
      LOGICAL, OPTIONAL :: Output
!------------------------------------------------------------------------------
      LOGICAL :: stat
      TYPE(Variable_t), POINTER :: ptr,ptr1,ptr2
!------------------------------------------------------------------------------
      IF ( .NOT.ASSOCIATED(Variables) ) THEN
        ALLOCATE(Variables)
        ptr => Variables
      ELSE
        ALLOCATE( ptr )
      END IF

      ptr % Name = ' '
      ptr % NameLen = StringToLowerCase( ptr % Name,Name )

      IF ( .NOT. ASSOCIATED(ptr, Variables) ) THEN
        ptr1 => Variables
        ptr2 => Variables
        DO WHILE( ASSOCIATED( ptr1 ) )
           IF ( ptr % Name == ptr1 % Name ) THEN
              DEALLOCATE( ptr )
              RETURN
           END IF
           ptr2 => ptr1
           ptr1 => ptr1 % Next
         END DO
         ptr2 % Next => ptr
      END IF
      NULLIFY( ptr % Next )

      ptr % DOFs = DOFs
      IF ( PRESENT( Perm ) ) THEN
        ptr % Perm => Perm
      ELSE
        NULLIFY( ptr % Perm )
      END IF
      ptr % Norm = 0.0d0
      ptr % Values => Values
      NULLIFY( ptr % PrevValues )
      NULLIFY( ptr % EigenValues, ptr % EigenVectors )
   
      ptr % Solver => Solver
      ptr % PrimaryMesh => Mesh

      ptr % Valid  = .TRUE.
      ptr % Output = .TRUE.
      IF ( PRESENT( Output ) ) ptr % Output = Output
!------------------------------------------------------------------------------
    END SUBROUTINE VariableAdd
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    FUNCTION MeshProjector( Mesh1, Mesh2, &
         UseQuadrantTree, Trans ) RESULT( ProjectorMatrix )
DLLEXPORT MeshProjector
!------------------------------------------------------------------------------
       TYPE(Mesh_t) :: Mesh1, Mesh2
       LOGICAL, OPTIONAL :: UseQuadrantTree,Trans
       TYPE(Matrix_t), POINTER :: ProjectorMatrix
!------------------------------------------------------------------------------
       TYPE(Projector_t), POINTER :: Projector
!------------------------------------------------------------------------------
       INTERFACE
          SUBROUTINE InterpolateMeshToMesh( OldMesh, NewMesh, OldVariables, &
                     NewVariables, UseQuadrantTree, Projector )
             USE Types
             TYPE(Mesh_t) :: OldMesh, NewMesh
             LOGICAL, OPTIONAL :: UseQuadrantTree
             TYPE(Projector_t), POINTER, OPTIONAL :: Projector
             TYPE(Variable_t),  POINTER, OPTIONAL :: OldVariables,NewVariables
          END SUBROUTINE InterpolateMeshToMesh
       END INTERFACE
!------------------------------------------------------------------------------

       IF ( PRESENT(UseQuadrantTree) ) THEN
          CALL InterpolateMeshToMesh( Mesh1, Mesh2, &
                   UseQuadrantTree=UseQuadrantTree, Projector=Projector )
       ELSE
          CALL InterpolateMeshToMesh( Mesh1, Mesh2, Projector=Projector )
       END IF
 
       ProjectorMatrix => Projector % Matrix
       IF ( PRESENT(Trans) ) THEN
          IF ( Trans ) THEN
             ProjectorMatrix => Projector % TMatrix
          END IF
       END IF
!------------------------------------------------------------------------------
    END FUNCTION MeshProjector
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    RECURSIVE FUNCTION VariableGet( Variables, Name, ThisOnly ) RESULT(Var)
DLLEXPORT VariableGet
!------------------------------------------------------------------------------
      TYPE(Variable_t), POINTER :: Variables
      CHARACTER(LEN=*) :: Name

      LOGICAL, OPTIONAL :: ThisOnly
!------------------------------------------------------------------------------
      TYPE(Mesh_t), POINTER :: Mesh
      TYPE(Projector_t), POINTER :: Projector
      TYPE(Variable_t), POINTER :: Var,PVar,Tmp
!------------------------------------------------------------------------------
      REAL(KIND=dp), POINTER :: Vals(:)
      INTEGER :: i,k,n, DOFs
      LOGICAL :: Found, GlobalBubbles
      CHARACTER(LEN=MAX_NAME_LEN) :: str, tmpname
double precision :: t1,CPUTime
!------------------------------------------------------------------------------
      INTERFACE
         SUBROUTINE InterpolateMeshToMesh( OldMesh, NewMesh, OldVariables, &
                     NewVariables, UseQuadrantTree, Projector )
            USE Types
            TYPE(Mesh_t) :: OldMesh, NewMesh
            LOGICAL, OPTIONAL :: UseQuadrantTree
            TYPE(Projector_t), POINTER, OPTIONAL :: Projector
            TYPE(Variable_t),  POINTER, OPTIONAL :: OldVariables,NewVariables
         END SUBROUTINE InterpolateMeshToMesh
      END INTERFACE
!------------------------------------------------------------------------------
      k = StringToLowerCase( str,Name )

      Tmp => Variables
      DO WHILE( ASSOCIATED(tmp) )
        IF ( tmp % NameLen == k ) THEN
          IF ( tmp % Name(1:k) == str(1:k) ) THEN

            IF ( Tmp % Valid ) THEN
               Var => Tmp
               RETURN
            END IF
            EXIT

          END IF
        END IF
        tmp => tmp % Next
      END DO
      Var => Tmp

!------------------------------------------------------------------------------
      IF ( PRESENT(ThisOnly) ) THEN
         IF ( ThisOnly ) RETURN
      END IF
!------------------------------------------------------------------------------
      NULLIFY( PVar )
      Mesh => CurrentModel % Meshes
      DO WHILE( ASSOCIATED( Mesh ) )

        IF ( .NOT.ASSOCIATED( Variables, Mesh % Variables ) ) THEN
          PVar => VariableGet( Mesh % Variables, Name, ThisOnly=.TRUE. )
          IF ( ASSOCIATED( PVar ) ) THEN
            IF ( ASSOCIATED( Mesh, PVar % PrimaryMesh ) ) THEN
              EXIT
            END IF
          END IF
        END IF
        Mesh => Mesh % Next
      END DO

      IF ( .NOT.ASSOCIATED( PVar ) ) RETURN
!------------------------------------------------------------------------------

      IF ( .NOT.ASSOCIATED( Tmp ) ) THEN
         GlobalBubbles=ListGetLogical(Pvar % Solver % Values, 'Global Bubbles', Found)
         DOFs = CurrentModel % Mesh % NumberOfNodes * PVar % DOFs
         IF ( GlobalBubbles ) &
            DOFs = DOFs+CurrentModel % Mesh % NumberOfBulkElements * PVar % DOFs

         ALLOCATE( Var )
         ALLOCATE( Var % Values(DOFs) )
         Var % Values = 0

         NULLIFY( Var % Perm )
         IF ( ASSOCIATED( PVar % Perm ) ) THEN
            ALLOCATE( Var % Perm( DOFs/Pvar % DOFs ) )

            n = InitialPermutation( Var % Perm, CurrentModel, &
                CurrentModel % Mesh, ListGetString(PVar % Solver % Values,'Equation'), &
                 GlobalBubbles=GlobalBubbles )

            IF ( n == CurrentModel % Mesh % NumberOfNodes ) THEN
               DO i=1,n 
                  Var % Perm(i) = i
               END DO
            END IF
         END IF

         CALL VariableAdd( Variables, PVar % PrimaryMesh, PVar % Solver, &
           Name, PVar % DOFs, Var % Values, Var % Perm, PVar % Output ) 

         Var => VariableGet( Variables, Name, ThisOnly=.TRUE. )

         NULLIFY( Var % PrevValues )
         IF ( ASSOCIATED( PVar % PrevValues ) ) THEN
            ALLOCATE( Var % PrevValues( DOFs, SIZE(PVar % PrevValues,2) ) )
         END IF

         IF ( PVar % Name == 'flow solution' ) THEN
           Vals => Var % Values( 1: SIZE(Var % Values) : PVar % DOFs )
           CALL VariableAdd( Variables, PVar % PrimaryMesh, PVar % Solver, &
                  'Velocity 1', 1,  Vals, Var % Perm, PVar % Output ) 

           Tmp => VariableGet( Variables, 'Velocity 1', .TRUE. )
           NULLIFY( Tmp % PrevValues )
           IF ( ASSOCIATED( Var % PrevValues ) )  &
              Tmp % PrevValues => Var % PrevValues(1::PVar % DOFs,:)

           Vals => Var % Values( 2: SIZE(Var % Values) : PVar % DOFs )
           CALL VariableAdd( Variables, PVar % PrimaryMesh, PVar % Solver, &
                  'Velocity 2', 1,  Vals, Var % Perm, PVar % Output ) 

           Tmp => VariableGet( Variables, 'Velocity 2', .TRUE. )
           NULLIFY( Tmp % PrevValues )
           IF ( ASSOCIATED( Var % PrevValues ) ) &
              Tmp % PrevValues => Var % PrevValues(2::PVar % DOFs,:)

           IF ( PVar % DOFs == 3 ) THEN
             Vals => Var % Values( 3 : SIZE(Var % Values) : PVar % DOFs )
             CALL VariableAdd( Variables, PVar % PrimaryMesh, PVar % Solver, &
                    'Pressure', 1,  Vals, Var % Perm, PVar % Output ) 
           ELSE
             Vals => Var % Values( 3: SIZE(Var % Values) : PVar % DOFs )
             CALL VariableAdd( Variables, PVar % PrimaryMesh, PVar % Solver, &
                  'Velocity 3', 1,  Vals, Var % Perm, PVar % Output ) 

             Tmp => VariableGet( Variables, 'Velocity 3', .TRUE. )
             NULLIFY( Tmp % PrevValues )
             IF ( ASSOCIATED( Var % PrevValues ) ) &
                 Tmp % PrevValues => Var % PrevValues(3::PVar % DOFs,:)

             Vals => Var % Values( 4: SIZE(Var % Values) : PVar % DOFs )
             CALL VariableAdd( Variables, PVar % PrimaryMesh, PVar % Solver, &
                    'Pressure', 1,  Vals, Var % Perm, PVar % Output ) 
           END IF

           Tmp => VariableGet( Variables, 'Pressure', .TRUE. )
           NULLIFY( Tmp % PrevValues )
           IF ( ASSOCIATED( Var % PrevValues ) ) &
              Tmp % PrevValues => Var % PrevValues(PVar % DOFs::PVar % DOFs,:)
         ELSE
           IF ( PVar % DOFs > 1 ) THEN
             DO i=1,PVar % DOFs
               Vals => Var % Values( i: SIZE(Var % Values) : PVar % DOFs )
               tmpname = ComponentName( Name, i )
               CALL VariableAdd( Variables, PVar % PrimaryMesh, PVar % Solver, &
                       tmpname, 1, Vals, Var % Perm, PVar % Output ) 

               Tmp => VariableGet( Variables, TRIM( tmpname ), .TRUE. )
               NULLIFY( Tmp % PrevValues )
               IF ( ASSOCIATED( Var % PrevValues ) ) &
                  Tmp % PrevValues => &
                          Var % PrevValues(PVar % DOFs::PVar % DOFs,:)
             END DO
           END IF
        END IF
 
        Var => VariableGet( Variables, Name, ThisOnly=.TRUE. )
      END IF

!------------------------------------------------------------------------------
! Build a temporary variable list of variables to be interpolated
!------------------------------------------------------------------------------
      ALLOCATE( Tmp )
      Tmp = PVar
      Var => Tmp
      NULLIFY( Var % Next )

      IF ( PVar % Name == 'flow solution' ) THEN
        ALLOCATE( Var % Next )
        Var => Var % Next
        Var = VariableGet( PVar % PrimaryMesh % Variables, 'Velocity 1' )

        ALLOCATE( Var % Next )
        Var => Var % Next
        Var  = VariableGet(  PVar % PrimaryMesh % Variables, 'Velocity 2' )

        IF ( PVar % DOFs == 4 ) THEN
          ALLOCATE( Var % Next )
          Var => Var % Next
          Var  = VariableGet( PVar % PrimaryMesh % Variables, 'Velocity 3' )
        END IF

        ALLOCATE( Var % Next )
        Var => Var % Next
        Var = VariableGet( PVar % PrimaryMesh % Variables, 'Pressure' )
        NULLIFY( Var % Next )
        Var => Tmp
      ELSE IF ( PVar % DOFs > 1 ) THEN
        DO i=1,PVar % DOFs
          ALLOCATE( Var % Next )
          tmpname = ComponentName( Name, i )
          Var % Next = VariableGet( PVar % PrimaryMesh % Variables, tmpname )
          Var => Var % Next
        END DO
        NULLIFY( Var % Next )
        Var => Tmp
      END IF

!------------------------------------------------------------------------------
! interpolation call
!------------------------------------------------------------------------------
t1 = CPUTime()
      CALL InterpolateMeshToMesh( PVar % PrimaryMesh, &
            CurrentModel % Mesh, Var, Variables, Projector=Projector )
WRITE( Message, * ) 'Interpolation time: ', CPUTime()-t1
CALL Info( 'VariableGet', Message, Level=7 )

!------------------------------------------------------------------------------
! free the temporary list
!------------------------------------------------------------------------------
      DO WHILE( ASSOCIATED( Tmp ) )
         Var => Tmp % Next
         DEALLOCATE( Tmp )
         Tmp => Var
      END DO
!------------------------------------------------------------------------------
      Var => VariableGet( Variables, Name, ThisOnly=.TRUE. )
      Var % Valid = .TRUE.
!------------------------------------------------------------------------------
    END FUNCTION VariableGet 
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
  FUNCTION ListAllocate() RESULT(ptr)
DLLEXPORT ListAllocate
!------------------------------------------------------------------------------
     TYPE(ValueList_t), POINTER :: ptr

     ALLOCATE( ptr )
     ptr % Procedure = 0
     ptr % Type = 0
     ptr % Name = ' '
     ptr % NameLen = 0
     ptr % CValue = ' '
     ptr % LValue = .FALSE.
     NULLIFY( ptr % Next )
     NULLIFY( ptr % FValues )
     NULLIFY( ptr % TValues )
     NULLIFY( ptr % IValues )
!------------------------------------------------------------------------------
  END FUNCTION ListAllocate
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE ListDelete( ptr )
DLLEXPORT ListDelete
!------------------------------------------------------------------------------
     TYPE(ValueList_t), POINTER :: ptr

     IF ( ASSOCIATED(ptr % FValues) ) DEALLOCATE(ptr % FValues)
     IF ( ASSOCIATED(ptr % TValues) ) DEALLOCATE(ptr % TValues)
     IF ( ASSOCIATED(ptr % IValues) ) DEALLOCATE(ptr % IValues)
     DEALLOCATE( ptr )
!------------------------------------------------------------------------------
  END SUBROUTINE ListDelete
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
  SUBROUTINE ListRemove( List, Name )
DLLEXPORT ListRemove
!------------------------------------------------------------------------------
     TYPE(ValueList_t), POINTER :: List
     CHARACTER(LEN=*) :: Name
!------------------------------------------------------------------------------
     CHARACTER(LEN=MAX_NAME_LEN) :: str
     INTEGER :: k
     TYPE(ValueList_t), POINTER :: ptr, ptr1
!------------------------------------------------------------------------------
     IF ( ASSOCIATED(List) ) THEN
       k = StringToLowerCase( str,Name )
       ptr  => List
       ptr1 => ptr
       DO WHILE( ASSOCIATED(ptr) )
         IF ( ptr % NameLen == k .AND. ptr % Name(1:k) == str(1:k) ) THEN
            IF ( ASSOCIATED(ptr,List) ) THEN
               List => ptr % Next
            ELSE
               ptr1 % Next => ptr % Next
            END IF
            CALL ListDelete( ptr )
            EXIT
         ELSE
           ptr1 => ptr
           ptr  => ptr % Next 
         END IF
       END DO
     END IF
!------------------------------------------------------------------------------
   END SUBROUTINE ListRemove
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   FUNCTION ListCheckPresent( List,Name ) RESULT(Found)
DLLEXPORT ListCheckPresent
!------------------------------------------------------------------------------
     TYPE(ValueList_t), POINTER :: List
     CHARACTER(LEN=*) :: Name
     LOGICAL :: Found
!------------------------------------------------------------------------------
     TYPE(ValueList_t), POINTER :: ptr

     INTEGER :: k,n
     CHARACTER(LEN=MAX_NAME_LEN) :: str
!------------------------------------------------------------------------------
     k = StringToLowerCase( str,Name )
     ptr => List
     DO WHILE( ASSOCIATED(ptr) )
       n = ptr % NameLen
       IF ( n==k ) THEN
         IF ( ptr % Name(1:k) == str(1:k) ) EXIT
       END IF
       ptr => ptr % Next
     END DO

     Found = ASSOCIATED( ptr )
!------------------------------------------------------------------------------
   END FUNCTION ListCheckPresent
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    SUBROUTINE ListAddString( List,Name,CValue,CaseConversion )
DLLEXPORT ListAddString
!------------------------------------------------------------------------------
      TYPE(ValueList_t), POINTER :: List
      CHARACTER(LEN=*) :: Name
      CHARACTER(LEN=*) :: CValue
      LOGICAL, OPTIONAL :: CaseConversion
!------------------------------------------------------------------------------
      CHARACTER(LEN=MAX_NAME_LEN) :: str
      INTEGER :: k
      LOGICAL :: DoCase
      TYPE(ValueList_t), POINTER :: ptr, ptr1
!------------------------------------------------------------------------------
      CALL ListRemove( List, Name )

      ptr => ListAllocate()
      IF ( ASSOCIATED( List ) ) THEN
        ptr % Next  => List % Next
        List % Next => ptr
      ELSE
        List => ptr
      END IF

      DoCase = .TRUE.
      IF ( PRESENT(CaseConversion) ) DoCase = CaseConversion

      IF ( DoCase ) THEN
        k = StringToLowerCase( ptr % CValue,CValue )
      ELSE
        k = MIN( MAX_NAME_LEN,LEN(CValue) )
        ptr % CValue(1:k) = CValue(1:k)
      END IF

      ptr % Type   = LIST_TYPE_STRING
      ptr % NameLen = StringToLowerCase( Ptr % Name,Name )
!------------------------------------------------------------------------------
    END SUBROUTINE ListAddString
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    SUBROUTINE ListAddLogical( List,Name,LValue )
DLLEXPORT ListAddLogical
!------------------------------------------------------------------------------
      TYPE(ValueList_t), POINTER :: List
      CHARACTER(LEN=*) :: Name
      LOGICAL :: LValue
!------------------------------------------------------------------------------
      INTEGER :: k
      CHARACTER(LEN=MAX_NAME_LEN) :: str
      TYPE(ValueList_t), POINTER :: ptr, ptr1
!------------------------------------------------------------------------------

      CALL ListRemove( List, Name )
      ptr => ListAllocate()
      IF ( ASSOCIATED( List ) ) THEN
        ptr % Next => List % Next
        List % Next => ptr
      ELSE
        List => ptr
      END IF

      Ptr % LValue = LValue
      Ptr % Type   = LIST_TYPE_LOGICAL

      Ptr % NameLen = StringToLowerCase( ptr % Name,Name )
    END SUBROUTINE ListAddLogical
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    SUBROUTINE ListAddInteger( List,Name,IValue,Proc )
DLLEXPORT ListAddInteger
!------------------------------------------------------------------------------
      TYPE(ValueList_t), POINTER :: List
      CHARACTER(LEN=*) :: Name
      INTEGER :: IValue
      INTEGER(Kind=AddrInt), OPTIONAL :: Proc
!------------------------------------------------------------------------------
      INTEGER :: k
      CHARACTER(LEN=MAX_NAME_LEN) :: str
      TYPE(ValueList_t), POINTER :: ptr, ptr1
!------------------------------------------------------------------------------
      CALL ListRemove( List, Name )

      ptr => ListAllocate()
      IF ( ASSOCIATED( List ) ) THEN
        ptr % Next => List % Next
        List % Next => ptr
      ELSE
        List => ptr
      END IF

      IF ( PRESENT(Proc) ) ptr % Procedure = Proc

      ALLOCATE( ptr % IValues(1) )
      ptr % IValues(1) = IValue
      ptr % Type       = LIST_TYPE_INTEGER

      ptr % NameLen = StringToLowerCase( ptr % Name,Name )
    END SUBROUTINE ListAddInteger
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    SUBROUTINE ListAddIntegerArray( List,Name,N,IValues,Proc )
DLLEXPORT ListAddIntegerArray
!------------------------------------------------------------------------------
      TYPE(ValueList_t), POINTER :: List
      CHARACTER(LEN=*) :: Name
      INTEGER :: N
      INTEGER :: IValues(N)
      INTEGER(KIND=AddrInt), OPTIONAL :: Proc
!------------------------------------------------------------------------------
      INTEGER :: k
      CHARACTER(LEN=MAX_NAME_LEN) :: str
      TYPE(ValueList_t), POINTER :: ptr, ptr1
!------------------------------------------------------------------------------
      CALL ListRemove( List, Name )

      ptr => ListAllocate()
      IF ( ASSOCIATED( List ) ) THEN
        ptr % Next => List % Next
        List % Next => ptr
      ELSE
        List => ptr
      END IF

      ALLOCATE( ptr % IValues(N) )

      IF ( PRESENT(Proc) ) ptr % Procedure = Proc

      ptr % Type  = LIST_TYPE_CONSTANT_TENSOR
      ptr % IValues(1:n) = IValues(1:n)

      ptr % NameLen = StringToLowerCase( ptr % Name,Name )
    END SUBROUTINE ListAddIntegerArray
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    SUBROUTINE ListAddConstReal( List,Name,FValue,Proc,CValue )
DLLEXPORT ListAddConstReal
!------------------------------------------------------------------------------
      TYPE(ValueList_t), POINTER :: List
      CHARACTER(LEN=*) :: Name
      CHARACTER(LEN=*), OPTIONAL :: Cvalue
      REAL(KIND=dp) :: FValue
      INTEGER(KIND=AddrInt), OPTIONAL :: Proc
!------------------------------------------------------------------------------
      TYPE(ValueList_t), POINTER :: ptr,ptr1
      INTEGER :: k
      CHARACTER(LEN=MAX_NAME_LEN) :: str
!------------------------------------------------------------------------------
      CALL ListRemove( List, Name )

      ptr => ListAllocate()
      IF ( ASSOCIATED( List ) ) THEN
        ptr % Next => List % Next
        List % Next => ptr
      ELSE
        List => ptr
      END IF

      NULLIFY( ptr % TValues )
      ALLOCATE( ptr % FValues(1,1,1) )

      IF ( PRESENT(Proc) ) ptr % Procedure = Proc

      ptr % FValues = FValue
      ptr % Type  = LIST_TYPE_CONSTANT_SCALAR

      IF ( PRESENT( CValue ) ) THEN
         ptr % Cvalue = CValue
         ptr % Type  = LIST_TYPE_CONSTANT_SCALAR_STR
      END IF

      ptr % NameLen = StringToLowerCase( ptr % Name,Name )
    END SUBROUTINE ListAddConstReal
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    SUBROUTINE ListAddDepReal(List,Name,DependName,N,TValues,FValues,Proc,CValue)
DLLEXPORT ListAddDepReal
!------------------------------------------------------------------------------
     TYPE(ValueList_t), POINTER :: List
     CHARACTER(LEN=*) :: Name,DependName
     CHARACTER(LEN=*), OPTIONAL :: Cvalue
     INTEGER :: N
     REAL(KIND=dp) :: FValues(N)
     REAL(KIND=dp) :: TValues(N)
     INTEGER(KIND=AddrInt), OPTIONAL :: Proc
!------------------------------------------------------------------------------
     INTEGER :: k

     CHARACTER(LEN=MAX_NAME_LEN) :: str
     TYPE(ValueList_t), POINTER :: ptr,ptr1
!------------------------------------------------------------------------------

     CALL ListRemove( List, Name )

     ptr => ListAllocate()
     IF ( ASSOCIATED( List ) ) THEN
       ptr % Next => List % Next
       List % Next => ptr
     ELSE
       List => ptr
     END IF

     IF ( PRESENT(Proc) ) ptr % Procedure = Proc

     ALLOCATE( ptr % FValues(1,1,N),ptr % TValues(N) )

     ptr % TValues = TValues(1:N)
     ptr % FValues(1,1,:) = FValues(1:N)
     ptr % Type = LIST_TYPE_VARIABLE_SCALAR

     ptr % Name = ' '
     ptr % NameLen = StringToLowerCase( ptr % Name,Name )

     ptr % DependName = ' '
     ptr % DepNameLen = StringToLowerCase( ptr % DependName,DependName )

     IF ( PRESENT( Cvalue ) ) THEN
        ptr % CValue = CValue
        ptr % Type = LIST_TYPE_VARIABLE_SCALAR_STR
     END IF

   END SUBROUTINE ListAddDepReal
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    SUBROUTINE ListAddConstRealArray( List,Name,N,M,FValues,Proc,CValue )
DLLEXPORT ListAddConstRealArray
!------------------------------------------------------------------------------
      TYPE(ValueList_t), POINTER :: List
      CHARACTER(LEN=*) :: Name
      CHARACTER(LEN=*), OPTIONAL :: Cvalue
      INTEGER :: N,M
      REAL(KIND=dp) :: FValues(:,:)
      INTEGER(KIND=AddrInt), OPTIONAL :: Proc
!------------------------------------------------------------------------------
      INTEGER :: k
      CHARACTER(LEN=MAX_NAME_LEN) :: str
      TYPE(ValueList_t), POINTER :: ptr, ptr1
!------------------------------------------------------------------------------
      CALL ListRemove( List, Name )

      ptr => ListAllocate()
      IF ( ASSOCIATED( List ) ) THEN
        ptr % Next => List % Next
        List % Next => ptr
      ELSE
        List => ptr
      END IF

      NULLIFY( ptr % TValues )
      ALLOCATE( ptr % FValues(N,M,1) )

      IF ( PRESENT(Proc) ) ptr % Procedure = Proc

      ptr % Type  = LIST_TYPE_CONSTANT_TENSOR
      ptr % FValues(1:n,1:m,1) = FValues(1:n,1:m)

      IF ( PRESENT( Cvalue ) ) THEN
         ptr % CValue = CValue
         ptr % Type  = LIST_TYPE_CONSTANT_TENSOR_STR
      END IF

      ptr % NameLen = StringToLowerCase( ptr % Name,Name )
    END SUBROUTINE ListAddConstRealArray
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
    SUBROUTINE ListAddDepRealArray(List,Name,DependName, &
               N,TValues,N1,N2,FValues,Proc,Cvalue)
DLLEXPORT ListAddDepRealArray
!------------------------------------------------------------------------------
     TYPE(ValueList_t), POINTER :: List
     CHARACTER(LEN=*) :: Name,DependName
     CHARACTER(LEN=*), OPTIONAL :: Cvalue
     INTEGER :: N,N1,N2
     REAL(KIND=dp) :: FValues(:,:,:)
     REAL(KIND=dp) :: TValues(N)
     INTEGER(KIND=AddrInt), OPTIONAL :: Proc
!------------------------------------------------------------------------------
     INTEGER :: k
     CHARACTER(LEN=MAX_NAME_LEN) :: str
     TYPE(ValueList_t), POINTER :: ptr,ptr1
!------------------------------------------------------------------------------

     CALL ListRemove( List, Name )

     ptr => ListAllocate()
     IF ( ASSOCIATED( List ) ) THEN
       ptr % Next => List % Next
       List % Next => ptr
     ELSE
       List => ptr
     END IF

     IF ( PRESENT(Proc) ) ptr % Procedure = Proc

     ALLOCATE( ptr % FValues(n1,n2,N),ptr % TValues(N) )

     ptr % TValues = TValues(1:N)
     ptr % FValues = FValues(1:n1,1:n2,1:N)
     ptr % Type = LIST_TYPE_VARIABLE_TENSOR

     IF ( PRESENT( Cvalue ) ) THEN
        ptr % CValue = CValue
        ptr % Type = LIST_TYPE_VARIABLE_TENSOR_STR
     END IF

     ptr % Name = ' '
     ptr % NameLen = StringToLowerCase( ptr % Name,Name )

     ptr % DependName = ' '
     ptr % DepNameLen = StringToLowerCase( ptr % DependName,DependName )
   END SUBROUTINE ListAddDepRealArray
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   RECURSIVE FUNCTION ListGetInteger( List,Name,gotIt,minv,maxv ) RESULT(L)
DLLEXPORT ListGetInteger
!------------------------------------------------------------------------------
     TYPE(ValueList_t), POINTER :: List
     CHARACTER(LEN=*) :: Name
     INTEGER :: L
     LOGICAL, OPTIONAL :: gotIt
     INTEGER, OPTIONAL :: minv,maxv
!------------------------------------------------------------------------------
     TYPE(ValueList_t), POINTER :: ptr

     INTEGER :: k,n
     CHARACTER(LEN=MAX_NAME_LEN) :: str
!------------------------------------------------------------------------------
     IF ( PRESENT(gotIt) ) gotIt = .TRUE.

     k = StringToLowerCase( str,Name )
     ptr => List
     DO WHILE( ASSOCIATED(ptr) )
       n = ptr % NameLen
       IF ( n==k ) THEN
         IF ( ptr % Name(1:k) == str(1:k) ) EXIT
       END IF
       ptr => ptr % Next
     END DO

     IF ( .NOT.ASSOCIATED(ptr) ) THEN
       L = 0
       IF ( PRESENT(gotIt) ) THEN
         gotIt = .FALSE.
       ELSE
         CALL Warn( 'ListGetInteger', ' ' )
         WRITE( Message, * ) 'Requested property: ', &
             '[',Name(1:k),'], not found'
         CALL Warn( 'ListGetInteger', Message )
         CALL Warn( 'ListGetInteger', ' ' )
       END IF
       RETURN
     END IF

     IF ( ptr % Procedure /= 0 ) THEN
       L = ExecIntFunction( ptr % Procedure, CurrentModel )
     ELSE
       L = ptr % IValues(1)
     END IF

     IF ( PRESENT( minv ) ) THEN
        IF ( L < minv ) THEN
           WRITE( Message, *) 'Given value ', L, ' for property: ', '[', Name(1:k),']', &
               ' smaller than given minimum: ', minv
           CALL Fatal( 'ListGetInteger', Message )
        END IF
     END IF

     IF ( PRESENT( maxv ) ) THEN
        IF ( L > maxv ) THEN
           WRITE( Message,*)  'Given value ', L, ' for property: ', '[', Name(1:k),']', &
               ' larger than given maximum: ', maxv
           CALL Fatal( 'ListGetInteger', Message )
        END IF
     END IF
   END FUNCTION ListGetInteger
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   RECURSIVE FUNCTION ListGetIntegerArray( List,Name,GotIt ) RESULT( IValues )
DLLEXPORT ListGetIntegerArray
!------------------------------------------------------------------------------
     TYPE(ValueList_t), POINTER :: List
     CHARACTER(LEN=*)  :: Name
     LOGICAL, OPTIONAL :: gotIt
!------------------------------------------------------------------------------
     TYPE(ValueList_t), POINTER :: ptr

     INTEGER, POINTER :: IValues(:)

     INTEGER :: i,k,N
     CHARACTER(LEN=MAX_NAME_LEN) :: str
!------------------------------------------------------------------------------
     IF ( PRESENT(gotIt) ) gotIt = .TRUE.
     NULLIFY( IValues )

     k = StringToLowerCase( str,Name )
     ptr => List
     DO WHILE( ASSOCIATED(ptr) )
       n = ptr % NameLen
       IF ( n==k ) THEN
         IF ( ptr % Name(1:k) == str(1:k) ) EXIT
       END IF
       ptr => ptr % Next
     END DO

     IF ( .NOT.ASSOCIATED(ptr) ) THEN
       IF ( PRESENT(gotIt) ) THEN 
         gotIt = .FALSE.
       ELSE
         CALL Warn( 'ListGetIntegerArray', ' ' )
         WRITE( Message, * ) 'Requested property: ', &
             '[',Name(1:k),'], not found'
         CALL Warn( 'ListGetIntegerArray', Message )
         CALL Warn( 'ListGetIntegerArray', ' ' )
       END IF
       RETURN
     END IF

     N = SIZE(ptr % IValues)
     IValues => Ptr % IValues(1:N)

     IF ( ptr % Procedure /= 0 ) THEN
       IValues = 0
       DO i=1,N
         Ivalues(i) = ExecIntFunction( ptr % Procedure,CurrentModel )
       END DO
     END IF
   END FUNCTION ListGetIntegerArray
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
   RECURSIVE FUNCTION ListGetLogical( List,Name,gotIt ) RESULT(L)
DLLEXPORT ListGetLogical
!------------------------------------------------------------------------------
     TYPE(ValueList_t), POINTER :: List
     CHARACTER(LEN=*) :: Name
     LOGICAL :: L
     LOGICAL, OPTIONAL :: gotIt
!------------------------------------------------------------------------------
     TYPE(ValueList_t), POINTER :: ptr

     INTEGER :: k,n
     CHARACTER(LEN=MAX_NAME_LEN) :: str
!------------------------------------------------------------------------------
     IF ( PRESENT(gotIt) ) gotIt = .TRUE.

     k = StringToLowerCase( str,Name )
     ptr => List
     DO WHILE( ASSOCIATED(ptr) )
       n = ptr % NameLen
       IF ( n==k ) THEN
         IF ( ptr % Name(1:k) == str(1:k) ) EXIT
       END IF
       ptr => ptr % Next
     END DO

     IF ( .NOT.ASSOCIATED(ptr) ) THEN
       L = .FALSE.
       IF ( PRESENT(gotIt) ) THEN
         gotIt = .FALSE.
       ELSE
         CALL Warn( 'ListGetLogical', ' ' )
         WRITE( Message, * ) 'Requested property: ', &
             '[',Name(1:k),'], not found'
         CALL Warn( 'ListGetLogical', Message )
         CALL Warn( 'ListGetLogical', ' ' )
       END IF
       RETURN
     END IF

     L = ptr % Lvalue
!------------------------------------------------------------------------------
   END FUNCTION ListGetLogical
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   RECURSIVE FUNCTION ListGetString( List,Name,gotIt ) RESULT(S)
DLLEXPORT ListGetString
!------------------------------------------------------------------------------
     TYPE(ValueList_t), POINTER :: List
     CHARACTER(LEN=*) :: Name
     LOGICAL, OPTIONAL :: gotIt
     CHARACTER(LEN=MAX_NAME_LEN) :: S
!------------------------------------------------------------------------------
     TYPE(ValueList_t), POINTER :: ptr

     INTEGER :: k,n
     CHARACTER(LEN=MAX_NAME_LEN) :: str
!------------------------------------------------------------------------------
     IF ( PRESENT(gotIt) ) gotIt = .TRUE.

     k = StringToLowerCase( str,Name )
     ptr => List
     DO WHILE( ASSOCIATED(ptr) )
       n = ptr % NameLen
       IF ( n==k ) THEN
         IF ( ptr % Name(1:n) == str(1:k) ) EXIT
       END IF
       ptr => ptr % Next
     END DO

     IF ( .NOT.ASSOCIATED(ptr) ) THEN
       S = ' '
       IF ( PRESENT(gotIt) ) THEN
         gotIt = .FALSE.
       ELSE
         CALL Warn( 'ListGetString', ' ' )
         WRITE( Message, * ) 'Requested property: ', &
             '[',Name(1:k),'], not found'
         CALL Warn( 'ListGetString', Message )
         CALL Warn( 'ListGetString', ' ' )
       END IF
       RETURN
     END IF

     S = ptr % Cvalue
!------------------------------------------------------------------------------
   END FUNCTION ListGetString
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
   RECURSIVE FUNCTION ListGetConstReal( List,Name,gotIt,x,y,z,minv,maxv ) RESULT(F)
DLLEXPORT ListGetConstReal
!------------------------------------------------------------------------------
     TYPE(ValueList_t), POINTER :: List
     CHARACTER(LEN=*) :: Name
     REAL(KIND=dp) :: F
     LOGICAL, OPTIONAL :: gotIt
     REAL(KIND=dp), OPTIONAL :: x,y,z
     REAL(KIND=dp), OPTIONAL :: minv,maxv
!------------------------------------------------------------------------------
     TYPE(ValueList_t), POINTER :: ptr

     TYPE(Variable_t), POINTER :: Variable

     REAL(KIND=dp) :: xx,yy,zz

     INTEGER :: i,j,k,n
     CHARACTER(LEN=MAX_NAME_LEN) :: cmd, str
!------------------------------------------------------------------------------
     F = 0.0D0
     IF ( PRESENT(gotIt) ) gotIt = .TRUE.

     k = StringToLowerCase( str,Name )
     ptr => List
     DO WHILE( ASSOCIATED(ptr) )
       n = ptr % NameLen
       IF ( n==k ) THEN
         IF ( ptr % Name(1:k) == str(1:k) ) EXIT
       END IF
       ptr => ptr % Next
     END DO

     IF ( .NOT.ASSOCIATED(ptr) ) THEN
       IF ( PRESENT(gotIt) ) THEN
         gotIt = .FALSE.
       ELSE
         CALL Warn( 'ListGetConstReal', ' ' )
         WRITE( Message, * ) 'Requested property: ', &
             '[',Name(1:k),'], not found'
         CALL Warn( 'ListGetConstReal', Message )
         CALL Warn( 'ListGetConstReal', ' ' )
       END IF
       RETURN
     END IF

     xx = 0.0d0
     yy = 0.0d0
     zz = 0.0d0
     IF ( PRESENT(x) ) xx = x
     IF ( PRESENT(y) ) yy = y
     IF ( PRESENT(z) ) zz = z

     IF ( Ptr % Type >= 8 ) THEN
        cmd = ptr % CValue
        k = LEN_TRIM( cmd )
        CALL matc( cmd, str, k )
        READ( str(1:k), * ) F
     ELSE IF ( ptr % Procedure /= 0 ) THEN
       F = ExecConstRealFunction( ptr % Procedure,CurrentModel,x,y,z )
     ELSE
       F = ptr % Fvalues(1,1,1)
     END IF

     IF ( PRESENT( minv ) ) THEN
        IF ( F < minv ) THEN
           WRITE( Message, *) 'Given value ', F, ' for property: ', '[', Name(1:k),']', &
               ' smaller than given minimum: ', minv
           CALL Fatal( 'ListGetInteger', Message )
        END IF
     END IF

     IF ( PRESENT( maxv ) ) THEN
        IF ( F > maxv ) THEN
           WRITE( Message, *) 'Given value ', F, ' for property: ', '[', Name(1:k),']', &
               ' larger than given maximum: ', maxv
           CALL Fatal( 'ListGetInteger', Message )
        END IF
     END IF
   END FUNCTION ListGetConstReal
!------------------------------------------------------------------------------

#define MAX_FNC 32

!------------------------------------------------------------------------------
   RECURSIVE FUNCTION ListGetReal( List,Name,N,NodeIndexes,gotIt,minv,maxv ) RESULT(F)
DLLEXPORT ListGetReal
!------------------------------------------------------------------------------
     TYPE(ValueList_t), POINTER :: List
     CHARACTER(LEN=*)  :: Name
     INTEGER :: N,NodeIndexes(:)
     REAL(KIND=dp)  :: F(N)
     LOGICAL, OPTIONAL :: GotIt
     REAL(KIND=dp), OPTIONAL :: minv,maxv
!------------------------------------------------------------------------------
     TYPE(ValueList_t), POINTER :: ptr

     TYPE(Variable_t), POINTER :: Variable, CVar, TVar

     REAL(KIND=dp) :: T(MAX_FNC)
     INTEGER :: i,j,k,l
     CHARACTER(LEN=MAX_NAME_LEN) :: str, cmd
!------------------------------------------------------------------------------
     F = 0.0D0
     IF ( PRESENT(GotIt) ) GotIt = .TRUE.

     k = StringToLowerCase( str,Name )
     ptr => List
     DO WHILE( ASSOCIATED(ptr) )
       l = ptr % NameLen
       IF ( l==k ) THEN
         IF ( ptr % Name(1:k) == str(1:k) ) EXIT
       END IF
       ptr => ptr % Next
     END DO

     IF ( .NOT.ASSOCIATED(ptr) ) THEN
       IF ( PRESENT(GotIt) ) THEN
         GotIt = .FALSE.
       ELSE
         CALL Warn( 'ListGetReal', ' ' )
         WRITE( Message, * ) 'Requested property: ', &
             '[',Name(1:k),'], not found'
         CALL Warn( 'ListGetReal', Message )
         CALL Warn( 'ListGetReal', ' ' )
       END IF
       RETURN
     END IF

     SELECT CASE(ptr % Type)
     CASE( LIST_TYPE_CONSTANT_SCALAR )
       IF ( ptr % Procedure /= 0 ) THEN
         DO i=1,n
           F(i) = ExecConstRealFunction( ptr % Procedure,CurrentModel, &
                CurrentModel % Mesh % Nodes % x( NodeIndexes(i) ), &
                CurrentModel % Mesh % Nodes % y( NodeIndexes(i) ), &
                CurrentModel % Mesh % Nodes % z( NodeIndexes(i) ) )
         END DO
       ELSE
         F = ptr % Fvalues(1,1,1)
       END IF
     
     CASE( LIST_TYPE_VARIABLE_SCALAR )
       IF ( ptr % DependName /= 'coordinate' ) THEN
          Variable => VariableGet( CurrentModel % Variables,ptr % DependName ) 
          IF ( .NOT. ASSOCIATED( Variable ) ) THEN
             WRITE( Message, * ) 'Can''t find independent variable:[', &
                TRIM(ptr % DependName),']' // &
                  'for dependent variable:[', TRIM(Name),']'
             CALL Fatal( 'ListGetReal', Message )
          END IF
       ELSE
          Variable => VariableGet( CurrentModel % Variables,'Coordinate 1' )
       END IF


       DO i=1,n
         k = NodeIndexes(i)
         IF ( ASSOCIATED(Variable % Perm) ) k = Variable % Perm( k )
         IF ( k > 0 ) THEN
           IF ( SIZE( Variable % Values ) >= k ) THEN

             IF ( ptr % DependName == 'coordinate' ) THEN
               CVar => VariableGet( CurrentModel % Variables, 'Coordinate 1' )
               T(1) = CVar % Values(k)
               CVar => VariableGet( CurrentModel % Variables, 'Coordinate 2' )
               T(2) = CVar % Values(k)
               CVar => VariableGet( CurrentModel % Variables, 'Coordinate 3' )
               T(3) = CVar % Values(k)
             ELSE
               IF ( Variable % DOFs == 1 ) THEN
                  T = Variable % Values(k)
               ELSE
                  DO j=1,Variable % DOFs
                     T(j) = Variable % Values(Variable % DOFs*(k-1)+j)
                  END DO
               END IF
             END IF
           ELSE
             T(1) = Variable % Values(1)
           END IF
           IF ( ptr % Procedure /= 0 ) THEN
              F(i) = ExecRealFunction( ptr % Procedure,CurrentModel, &
                           NodeIndexes(i), T )
           ELSE
              F(i) = InterpolateCurve(ptr % TValues,ptr % FValues(1,1,:),T(1))
           END IF
         END IF
       END DO

     CASE( LIST_TYPE_CONSTANT_SCALAR_STR )
         TVar => VariableGet( CurrentModel % Variables, 'Time' ) 
         WRITE( cmd, '(a,e15.8)' ) 'st = ', TVar % Values(1)
         k = LEN_TRIM( cmd )
         CALL matc( cmd, str, k )

         cmd = ptr % CValue
         k = LEN_TRIM( cmd )
         CALL matc( cmd, str, k )
         READ( str(1:k), * ) F(1)
         F(2:n) = F(1)

     CASE( LIST_TYPE_VARIABLE_SCALAR_STR )
       IF ( ptr % DependName /= 'coordinate' ) THEN
          Variable => VariableGet( CurrentModel % Variables,ptr % DependName ) 
          IF ( .NOT. ASSOCIATED( Variable ) ) THEN
             WRITE( Message, * ) 'Can''t find independent variable:[', &
                TRIM(ptr % DependName),']' // &
                  'for dependent variable:[', TRIM(Name),']'
             CALL Fatal( 'ListGetReal', Message )
          END IF
       ELSE
          Variable => VariableGet( CurrentModel % Variables,'Coordinate 1' )
       END IF


       DO i=1,n
         k = NodeIndexes(i)
         IF ( ASSOCIATED(Variable % Perm) ) k = Variable % Perm( k )
         IF ( k > 0 ) THEN
            IF ( SIZE( Variable % Values ) >= k ) THEN
               IF ( ptr % DependName == 'coordinate' ) THEN
                  CVar => VariableGet( CurrentModel % Variables, 'Coordinate 1' )
                  T(1) = CVar % Values(k)
                  CVar => VariableGet( CurrentModel % Variables, 'Coordinate 2' )
                  T(2) = CVar % Values(k)
                  CVar => VariableGet( CurrentModel % Variables, 'Coordinate 3' )
                  T(3) = CVar % Values(k)
                  j = 3
               ELSE
                  IF ( Variable % DOFs == 1 ) THEN
                     T(1) = Variable % Values(k)
                  ELSE
                     DO j=1,Variable % DOFs
                        T(j) = Variable % Values(Variable % DOFs*(k-1)+j)
                     END DO
                  END IF
                  j = Variable % DOFs
               END IF
            ELSE
              T(1) = Variable % Values(1)
              j =  1
            END IF

            TVar => VariableGet( CurrentModel % Variables, 'Time' ) 
            WRITE( cmd, * ) 'st = ', TVar % Values(1)
            k = LEN_TRIM( cmd )
            CALL matc( cmd, str, k )

            DO l=1,j
              WRITE( cmd, * ) 'tx(',l-1,') = ', T(l)
              k = LEN_TRIM( cmd )
              CALL matc( cmd, str, k )
            END DO

            cmd = ptr % CValue
            k = LEN_TRIM( cmd )
            CALL matc( cmd, str, k )
            READ( str(1:k), * ) F(i)
         END IF
       END DO
     END SELECT

     IF ( PRESENT( minv ) ) THEN
        IF ( MINVAL(F(1:n)) < minv ) THEN
           WRITE( Message,*) 'Given value ', MINVAL(F(1:n)), ' for property: ', '[', Name(1:k),']', &
               ' smaller than given minimum: ', minv
           CALL Fatal( 'ListGetReal', Message )
        END IF
     END IF

     IF ( PRESENT( maxv ) ) THEN
        IF ( MAXVAL(F(1:n)) > maxv ) THEN
           WRITE( Message,*) 'Given value ', MAXVAL(F(1:n)), ' for property: ', '[', Name(1:k),']', &
               ' larger than given maximum ', maxv
           CALL Fatal( 'ListGetReal', Message )
        END IF
     END IF
   END FUNCTION ListGetReal
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
   RECURSIVE FUNCTION ListGetConstRealArray( List,Name,GotIt ) RESULT( F )
DLLEXPORT ListGetConstRealArray
!------------------------------------------------------------------------------
     TYPE(ValueList_t), POINTER :: List
     CHARACTER(LEN=*) :: Name
     LOGICAL, OPTIONAL :: gotIt
!------------------------------------------------------------------------------
     REAL(KIND=dp), POINTER  :: F(:,:)

     TYPE(ValueList_t), POINTER :: ptr

     TYPE(Variable_t), POINTER :: Variable

     INTEGER :: i,j,k,n,N1,N2
     CHARACTER(LEN=MAX_NAME_LEN) :: str
!------------------------------------------------------------------------------
     IF ( PRESENT(gotIt) ) gotIt = .TRUE.
     NULLIFY( F ) 

     k = StringToLowerCase( str,Name )
     ptr => List
     DO WHILE( ASSOCIATED(ptr) )
       n = ptr % NameLen
       IF ( n==k ) THEN
         IF ( ptr % Name(1:k) == str(1:k) ) EXIT
       END IF
       ptr => ptr % Next
     END DO

     IF ( .NOT.ASSOCIATED(ptr) ) THEN
       IF ( PRESENT(GotIt) ) THEN
         gotIt = .FALSE.
       ELSE
         CALL Warn( 'ListGetConstRealArray', ' ' )
         WRITE( Message, * ) 'Requested property: ', &
             '[',Name(1:k),'], not found'
         CALL Warn( 'ListGetConstRealArray', Message )
         CALL Warn( 'ListGetConstRealArray', ' ' )
       END IF
       RETURN
     END IF

     N1 = SIZE( ptr % FValues,1 )
     N2 = SIZE( ptr % FValues,2 )

     F => ptr % FValues(:,:,1)

     IF ( ptr % Procedure /= 0 ) THEN
       DO i=1,N1
         DO j=1,N2
           F(i,j) = ExecConstRealFunction( ptr % Procedure,CurrentModel,0.0d0,0.0d0,0.0d0 )
         END DO
       END DO
     END IF
   END FUNCTION ListGetConstRealArray
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
   RECURSIVE SUBROUTINE ListGetRealArray( List,Name,F,N,NodeIndexes,gotIt )
DLLEXPORT ListGetRealArray
!------------------------------------------------------------------------------
     TYPE(ValueList_t), POINTER :: List
     CHARACTER(LEN=*) :: Name
     LOGICAL, OPTIONAL :: gotIt
     INTEGER :: N,NodeIndexes(:)
     REAL(KIND=dp), POINTER :: F(:,:,:), G(:,:)
!------------------------------------------------------------------------------

     TYPE(ValueList_t), POINTER :: ptr

     TYPE(Variable_t), POINTER :: Variable, CVar

     REAL(KIND=dp) :: T(MAX_FNC)
     INTEGER :: i,j,k,nlen,N1,N2
     CHARACTER(LEN=MAX_NAME_LEN) :: str
!------------------------------------------------------------------------------
     IF ( PRESENT(gotIt) ) gotIt = .TRUE.

     k = StringToLowerCase( str,Name )
     ptr => List
     DO WHILE( ASSOCIATED(ptr) )
       nlen = ptr % NameLen
       IF ( nlen==k ) THEN
         IF ( ptr % Name(1:k) == str(1:k) ) EXIT
       END IF
       ptr => ptr % Next
     END DO

     IF ( .NOT.ASSOCIATED(ptr) ) THEN
       IF ( PRESENT(GotIt) ) THEN
         gotIt = .FALSE.
       ELSE
         CALL Warn( 'ListGetRealArray', ' ' )
         WRITE( Message, * ) 'Requested property: ', &
             '[',Name(1:k),'], not found'
         CALL Warn( 'ListGetRealArray', Message )
         CALL Warn( 'ListGetRealArray', ' ' )
       END IF
       RETURN
     END IF

     N1 = SIZE(ptr % FValues,1)
     N2 = SIZE(ptr % FValues,2)

     IF ( .NOT.ASSOCIATED( F ) ) THEN
       ALLOCATE( F(N1,N2,N) )
     ELSE IF ( SIZE(F,1)/=N1.OR.SIZE(F,2)/=N2.OR.SIZE(F,3)/= N ) THEN
       DEALLOCATE( F )
       ALLOCATE( F(N1,N2,N) )
     END IF

     SELECT CASE(ptr % Type)
     CASE ( LIST_TYPE_CONSTANT_TENSOR )
       DO i=1,n
         F(:,:,i) = ptr % FValues(:,:,1)
       END DO

       IF ( ptr % Procedure /= 0 ) THEN
         DO i=1,N1
           DO j=1,N2
             F(i,j,1) = ExecConstRealFunction( ptr % Procedure,CurrentModel,0.0d0,0.0d0,0.0d0 )
           END DO
         END DO
       END IF
   
     
     CASE( LIST_TYPE_VARIABLE_TENSOR )
       IF ( ptr % DependName /= 'coordinate' ) THEN
          Variable => VariableGet( CurrentModel % Variables,ptr % DependName ) 
          IF ( .NOT. ASSOCIATED( Variable ) ) THEN
             WRITE( Message, * ) 'Can''t find independent variable:[', &
                TRIM(ptr % DependName),']' // &
                  'for dependent variable:[', TRIM(Name),']'
             CALL Fatal( 'ListGetReal', Message )
          END IF
       ELSE
          Variable => VariableGet( CurrentModel % Variables,'Coordinate 1' )
       END IF

       DO i=1,n
         k = NodeIndexes(i)
         IF ( ASSOCIATED(Variable % Perm) ) k = Variable % Perm( k )
         IF ( k > 0 ) THEN
           IF ( SIZE( Variable % Values ) >= k ) THEN

             IF ( ptr % DependName == 'coordinate' ) THEN
               CVar => VariableGet( CurrentModel % Variables, 'Coordinate 1' )
               T(1) = CVar % Values(k)
               CVar => VariableGet( CurrentModel % Variables, 'Coordinate 2' )
               T(2) = CVar % Values(k)
               CVar => VariableGet( CurrentModel % Variables, 'Coordinate 3' )
               T(3) = CVar % Values(k)
             ELSE
               IF ( Variable % DOFs == 1 ) THEN
                  T = Variable % Values(k)
               ELSE
                  DO j=1,Variable % DOFs
                     T(j) = Variable % Values(Variable % DOFs*(k-1)+j)
                  END DO
               END IF
             END IF
           ELSE
             T(1) = Variable % Values(1)
           END IF
           IF ( ptr % Procedure /= 0 ) THEN
             G => F(:,:,i)
             CALL ExecRealArrayFunction( ptr % Procedure,CurrentModel, &
                       NodeIndexes(i), T, G )
           ELSE
             DO j=1,N1
               DO k=1,N2
                 F(j,k,i) = InterpolateCurve(ptr % TValues, ptr % FValues(j,k,:),T(1))
               END DO
             END DO
           END IF
         END IF
       END DO

     CASE DEFAULT
       F = 0.0d0
       DO i=1,N1
         IF ( PRESENT( GotIt ) ) THEN
           F(i,1,:) = ListGetReal( List,Name,N,NodeIndexes,GotIt )
         ELSE
           F(i,1,:) = ListGetReal( List,Name,N,NodeIndexes )
         END IF
       END DO
     END SELECT
!------------------------------------------------------------------------------
   END SUBROUTINE ListGetRealArray
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   RECURSIVE FUNCTION ListGetDerivValue(List,Name,N,NodeIndexes) RESULT(F)
DLLEXPORT ListGetDerivValue
!------------------------------------------------------------------------------
     TYPE(ValueList_t), POINTER ::  List
     CHARACTER(LEN=*) :: Name
     INTEGER :: N,NodeIndexes(:)
     REAL(KIND=dp) :: F(N)
!------------------------------------------------------------------------------
     TYPE(ValueList_t), POINTER :: ptr

     TYPE(Variable_t), POINTER :: Variable

     REAL(KIND=dp) :: T
     INTEGER :: i,k,l
     CHARACTER(LEN=MAX_NAME_LEN) :: str
!------------------------------------------------------------------------------
     F = 0.0D0
     k = StringToLowerCase( str,Name )

     ptr => List
     DO WHILE( ASSOCIATED(ptr) )
       l = ptr % NameLen
       IF ( l==k ) THEN
         IF ( ptr % Name(1:k) == str(1:k) ) EXIT
       END IF
       ptr => ptr % Next
     END DO

     IF ( .NOT.ASSOCIATED(ptr) ) THEN
       CALL Warn( 'ListGetDerivValue', ' ' )
       WRITE( Message, * ) 'Requested property: ', &
           '[',Name(1:k),'], not found'
       CALL Warn( 'ListGetDerivValue', Message )
       CALL Warn( 'ListGetDerivValue', ' ' )
       RETURN
     END IF

     SELECT CASE(ptr % Type)
       CASE( LIST_TYPE_VARIABLE_SCALAR )
         Variable => VariableGet( CurrentModel % Variables,ptr % DependName ) 
         DO i=1,n
           k = NodeIndexes(i)
           IF ( ASSOCIATED(Variable % Perm) ) k = Variable % Perm(K)
           IF ( k > 0 ) THEN
             T = Variable % Values(k)
             F(i) = DerivateCurve(ptr % TValues,ptr % FValues(1,1,:),T)
           END IF
         END DO
     END SELECT

   END FUNCTION ListGetDerivValue
!------------------------------------------------------------------------------

END MODULE Lists
