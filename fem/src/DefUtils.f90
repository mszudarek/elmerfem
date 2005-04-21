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
!/******************************************************************************
! *
! *   Module containing utility subroutines with default values for various
! *   system subroutine arguments.
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
! *                       Date: 12 Jun 2003
! *
! *                Modified by:
! *
! *       Date of modification:
! *
! * $Log: DefUtils.f90,v $
! * Revision 1.54  2005/04/19 08:53:45  jpr
! * Renamed module LUDecomposition as LinearAlgebra.
! *
! * Revision 1.53  2005/04/14 08:48:28  jpr
! * *** empty log message ***
! *
! * Revision 1.52  2005/04/04 06:31:41  jpr
! * *** empty log message ***
! *
! * Revision 1.51  2005/04/04 06:18:27  jpr
! * *** empty log message ***
! *
! *
! * Revision 1.46  2004/09/03 09:16:47  byckling
! * Added p elements
! *
! * Revision 1.32  2004/04/01 06:44:46  jpr
! * Just formatting.
! *
! * Revision 1.31  2004/03/31 06:08:48  jpr
! * Added missing deallocate for allocated variable in new complex routines...
! *
! * Revision 1.30  2004/03/31 06:05:00  jpr
! * Modified interface to GetRealArray, GetConstRealArray introduced yesterday.
! *
! * Revision 1.29  2004/03/31 05:11:56  jpr
! * Update of the previously added complex functions to apply to multidof systems.
! *
! * Revision 1.28  2004/03/30 12:00:24  jpr
! * Added overloaded functions for updating global complex systems...
! *
! * Revision 1.27  2004/03/01 09:38:01  jpr
! * Removed some old code. Added missing DLLEXPORTs.
! *
! * Revision 1.26  2004/02/27 10:46:31  jpr
! * Made GetReal, GetConstReal reentrant by RECURSIVE definition
! *
! * Revision 1.25  2004/02/27 10:35:38  jpr
! * Started log.
! *
! * $Id: DefUtils.f90,v 1.54 2005/04/19 08:53:45 jpr Exp $
! *
! *****************************************************************************/

MODULE DefUtils

   USE Adaptive
   USE SolverUtils
   IMPLICIT NONE

   INTEGER, PRIVATE :: Indexes(512)

   INTERFACE DefaultUpdateEquations
     MODULE PROCEDURE DefaultUpdateEquationsR, DefaultUpdateEquationsC
   END INTERFACE

   INTERFACE DefaultUpdateMass
     MODULE PROCEDURE DefaultUpdateMassR, DefaultUpdateMassC
   END INTERFACE

   INTERFACE DefaultUpdateDamp
     MODULE PROCEDURE DefaultUpdateDampR, DefaultUpdateDampC
   END INTERFACE

   INTERFACE DefaultUpdateForce
     MODULE PROCEDURE DefaultUpdateForceR, DefaultUpdateForceC
   END INTERFACE

   INTERFACE Default1stOrderTime
     MODULE PROCEDURE Default1stOrderTimeR, Default1stOrderTimeC
   END INTERFACE

   INTERFACE Default2ndOrderTime
     MODULE PROCEDURE Default2ndOrderTimeR, Default2ndOrderTimeC
   END INTERFACE

     REAL(KIND=dp), TARGET  :: Store(MAX_NODES)
CONTAINS


  SUBROUTINE GetScalarLocalSolution( x,name,UElement,USolver )
DLLEXPORT GetScalarLocalSolution
     REAL(KIND=dp) :: x(:)
     CHARACTER(LEN=*), OPTIONAL :: name
     TYPE(Solver_t)  , OPTIONAL, TARGET :: USolver
     TYPE(Element_t),  OPTIONAL, TARGET :: UElement

     TYPE(Variable_t), POINTER :: Variable
     TYPE(Solver_t)  , POINTER :: Solver
     TYPE(Element_t),  POINTER :: Element

     INTEGER :: i, n

     Solver => CurrentModel % Solver
     IF ( PRESENT(USolver) ) Solver => USolver

     x = 0.0d0

     Variable => Solver % Variable
     IF ( PRESENT(name) ) THEN
        Variable => VariableGet( Solver % Mesh % Variables, TRIM(name) )
     END IF
     IF ( .NOT. ASSOCIATED( Variable ) ) RETURN

     Element => CurrentModel % CurrentElement
     IF ( PRESENT(UElement) ) Element => UElement

     IF ( ASSOCIATED( Variable ) ) THEN
        n = GetElementDOFs( Indexes, Element, Solver )
        n = MIN( n, SIZE(x) )

        IF ( ASSOCIATED( Variable % Perm ) ) THEN
           IF ( ALL( Variable % Perm(Indexes(1:n)) > 0 ) ) THEN
             DO i=1,n
                IF ( Indexes(i) <= SIZE(Variable % Perm) ) &
                  x(i) = Variable % Values(Variable % Perm(Indexes(i)))
             END DO
           END IF
        ELSE
           DO i=1,n
             IF ( Indexes(i) <= SIZE(Variable % Values) ) &
               x(i) = Variable % Values(Indexes(i))
           END DO
        END IF
     END IF
  END SUBROUTINE GetScalarLocalSolution



  SUBROUTINE GetVectorLocalSolution( x,name,UElement,USolver )
DLLEXPORT GetVectorLocalSolution
     REAL(KIND=dp) :: x(:,:)
     CHARACTER(LEN=*), OPTIONAL :: name
     TYPE(Solver_t),  OPTIONAL, TARGET :: USolver
     TYPE(Element_t), OPTIONAL, TARGET :: UElement

     TYPE(Variable_t), POINTER :: Variable
     TYPE(Solver_t)  , POINTER :: Solver
     TYPE(Element_t),  POINTER :: Element

     INTEGER :: i, j, n

     Solver => CurrentModel % Solver
     IF ( PRESENT(USolver) ) Solver => USolver

     x = 0.0d0

     Variable => Solver % Variable
     IF ( PRESENT(name) ) THEN
        Variable => VariableGet( Solver % Mesh % Variables, TRIM(name) )
     END IF
     IF ( .NOT. ASSOCIATED( Variable ) ) RETURN

     Element => CurrentModel % CurrentElement
     IF ( PRESENT(UElement) ) Element => UElement


     IF ( ASSOCIATED( Variable ) ) THEN
        n = GetElementDOFs( Indexes, Element, Solver )
        n = MIN( n, SIZE(x) )
        DO i=1,Variable % DOFs
           IF ( ASSOCIATED( Variable % Perm ) ) THEN
              IF ( ALL( Variable % Perm(Indexes(1:n)) > 0 ) ) THEN
                DO j=1,n
                  IF ( Indexes(j) <= SIZE( Variable % Perm ) ) THEN
                    x(i,j) = Variable % Values( Variable % DOFs * &
                        (Variable % Perm(Indexes(j))-1)+i )
                  END IF
                END DO
              END IF
           ELSE
              DO j=1,n
                IF ( Variable % DOFs*(Indexes(j)-1)+i <= &
                                SIZE( Variable % Values ) ) THEN
                  x(i,j) = Variable % Values(Variable % DOFs*(Indexes(j)-1)+i)
                END IF
              END DO
           END IF
         END DO
     END IF
  END SUBROUTINE GetVectorLocalSolution



  FUNCTION GetString( List, Name, Found ) RESULT(str)
DLLEXPORT GetString
     TYPE(ValueList_t), POINTER :: List
     CHARACTER(LEN=*) :: Name
     LOGICAL, OPTIONAL :: Found
     CHARACTER(LEN=MAX_NAME_LEN) :: str

     INTEGER :: i

     IF ( PRESENT( Found ) ) THEN
        str = ListGetString( List, Name, Found )
     ELSE
        str = ListGetString( List, Name )
     END IF
  END FUNCTION



  FUNCTION GetInteger( List, Name, Found ) RESULT(i)
DLLEXPORT GetInteger
     TYPE(ValueList_t), POINTER :: List
     CHARACTER(LEN=*) :: Name
     LOGICAL, OPTIONAL :: Found

     INTEGER :: i

     IF ( PRESENT( Found ) ) THEN
        i = ListGetInteger( List, Name, Found )
     ELSE
        i = ListGetInteger( List, Name )
     END IF
  END FUNCTION



  FUNCTION GetLogical( List, Name, Found ) RESULT(l)
DLLEXPORT GetLogical
     TYPE(ValueList_t), POINTER :: List
     CHARACTER(LEN=*) :: Name
     LOGICAL, OPTIONAL :: Found

     LOGICAL :: l

     IF ( PRESENT( Found ) ) THEN
        l = ListGetLogical( List, Name, Found )
     ELSE
        l = ListGetLogical( List, Name )
     END IF
  END FUNCTION



  RECURSIVE FUNCTION GetConstReal( List, Name, Found,x,y,z ) RESULT(r)
DLLEXPORT GetConstReal
     TYPE(ValueList_t), POINTER :: List
     CHARACTER(LEN=*) :: Name
     LOGICAL, OPTIONAL :: Found
     REAL(KIND=dp), OPTIONAL :: x,y,z

     REAL(KIND=dp) :: r,xx,yy,zz

     xx = 0
     yy = 0
     zz = 0
     IF ( PRESENT( x ) ) xx = x
     IF ( PRESENT( y ) ) yy = y
     IF ( PRESENT( z ) ) zz = z

     IF ( PRESENT( Found ) ) THEN
        r = ListGetConstReal( List, Name, Found,xx,yy,zz )
     ELSE
        r = ListGetConstReal( List, Name,x=xx,y=yy,z=zz )
     END IF
  END FUNCTION



  RECURSIVE FUNCTION GetReal( List, Name, Found, UElement ) RESULT(x)
DLLEXPORT GetReal
     TYPE(ValueList_t), POINTER :: List
     CHARACTER(LEN=*) :: Name
     LOGICAL, OPTIONAL :: Found
     TYPE(Element_t), OPTIONAL, TARGET :: UElement

     REAL(KIND=dp), POINTER :: x(:)
     TYPE(Element_t), POINTER :: Element

     INTEGER :: n

     IF ( PRESENT( Found ) ) Found = .FALSE.

     Element => CurrentModel % CurrentElement
     IF ( PRESENT( UElement ) ) Element => UElement

     n = GetElementNOFNodes( Element )
     x => Store(1:n)
     x = 0.0d0
     IF ( ASSOCIATED(List) ) THEN
        IF ( PRESENT( Found ) ) THEN
           x(1:n) = ListGetReal( List, Name, n, Element % NodeIndexes, Found )
        ELSE
           x(1:n) = ListGetReal( List, Name, n, Element % NodeIndexes )
        END IF
     END IF
  END FUNCTION GetReal



  RECURSIVE SUBROUTINE GetConstRealArray( List, x, Name, Found, UElement )
DLLEXPORT GetConstRealArray
     TYPE(ValueList_t), POINTER :: List
     REAL(KIND=dp), POINTER :: x(:,:)
     CHARACTER(LEN=*) :: Name
     LOGICAL, OPTIONAL :: Found
     TYPE(Element_t), OPTIONAL, TARGET :: UElement

     TYPE(Element_t), POINTER :: Element

     INTEGER :: n

     IF ( PRESENT( Found ) ) Found = .FALSE.

     Element => CurrentModel % CurrentElement
     IF ( PRESENT( UElement ) ) Element => UElement

     n = GetElementNOFNodes( Element )
     IF ( ASSOCIATED(List) ) THEN
        IF ( PRESENT( Found ) ) THEN
           x => ListGetConstRealArray( List, Name, Found )
        ELSE
           x => ListGetConstRealArray( List, Name )
        END IF
     END IF
  END SUBROUTINE GetConstRealArray




  RECURSIVE SUBROUTINE GetRealArray( List, x, Name, Found, UElement )
DLLEXPORT GetRealArray
     REAL(KIND=dp), POINTER :: x(:,:,:)
     TYPE(ValueList_t), POINTER :: List
     CHARACTER(LEN=*) :: Name
     LOGICAL, OPTIONAL :: Found
     TYPE(Element_t), OPTIONAL, TARGET :: UElement

     TYPE(Element_t), POINTER :: Element

     INTEGER :: n

     IF ( PRESENT( Found ) ) Found = .FALSE.

     Element => CurrentModel % CurrentElement
     IF ( PRESENT( UElement ) ) Element => UElement

     n = GetElementNOFNodes( Element )
     IF ( ASSOCIATED(List) ) THEN
        IF ( PRESENT( Found ) ) THEN
           CALL ListGetRealArray( List, Name, x, n, Element % NodeIndexes, Found )
        ELSE
           CALL ListGetRealArray( List, Name, x, n, Element % NodeINdexes  )
        END IF
     END IF
  END SUBROUTINE GetRealArray



  FUNCTION GetActiveElement(t,USolver) RESULT(Element)
DLLEXPORT GetActiveElement
     INTEGER :: t
     TYPE(Element_t), POINTER :: Element
     TYPE( Solver_t ), OPTIONAL, TARGET :: USolver

     TYPE( Solver_t ), POINTER :: Solver

     Solver => CurrentModel % Solver
     IF ( PRESENT( USolver ) ) Solver => USolver

     IF ( t > 0 .AND. t <= Solver % NumberOfActiveElements ) THEN
        Element => Solver % Mesh % Elements( Solver % ActiveElements(t) )
        CurrentModel % CurrentElement => Element ! may be used be user functions
     ELSE
        WRITE( Message, * ) 'Invalid element number requested: ', t
        CALL Fatal( 'GetActiveElement', Message )
     END IF
  END FUNCTION



  FUNCTION GetBoundaryElement(t,USolver) RESULT(Element)
DLLEXPORT GetBoundaryElement
     INTEGER :: t
     TYPE(Element_t), POINTER :: Element
     TYPE( Solver_t ), OPTIONAL, TARGET :: USolver

     TYPE( Solver_t ), POINTER :: Solver

     Solver => CurrentModel % Solver
     IF ( PRESENT( USolver ) ) Solver => USolver

     IF ( t > 0 .AND. t <= Solver % Mesh % NumberOfBoundaryElements ) THEN
        Element => Solver % Mesh % Elements( Solver % Mesh % NumberOfBulkElements+t )
        CurrentModel % CurrentElement => Element ! may be used be user functions
     ELSE
        WRITE( Message, * ) 'Invalid element number requested: ', t
        CALL Fatal( 'GetBoundaryElement', Message )
     END IF
  END FUNCTION



  FUNCTION ActiveBoundaryElement(UElement,USolver) RESULT(l)
DLLEXPORT ActiveBoundaryElement
     TYPE(Element_t), OPTIONAL,  TARGET :: UElement
     TYPE(Solver_t),  OPTIONAL,  TARGET :: USolver

     LOGICAL :: l
     INTEGER :: n

     TYPE(Element_t), POINTER :: Element
     TYPE( Solver_t ), POINTER :: Solver

     Solver => CurrentModel % Solver
     IF ( PRESENT( USolver ) ) Solver => USolver

     Element => CurrentModel % CurrentElement
     IF ( PRESENT( UElement ) ) Element => UElement

     n = GetElementDOFs( Indexes, Element, Solver )
     l = ALL( Solver % Variable % Perm(Indexes(1:n)) > 0)
  END FUNCTION ActiveBoundaryElement



  FUNCTION GetElementCode( Element )  RESULT(type)
DLLEXPORT GetElementCode
     INTEGER :: type
     TYPE(Element_t), OPTIONAL :: Element

     IF ( PRESENT( Element ) ) THEN
        type = Element % Type % ElementCode
     ELSE
        type = CurrentModel % CurrentElement % Type % ElementCode
     END IF
  END FUNCTION GetElementCode



  FUNCTION GetElementFamily( Element )  RESULT(family)
DLLEXPORT GetElementFamily
     INTEGER :: family
     TYPE(Element_t), OPTIONAL :: Element

     IF ( PRESENT( Element ) ) THEN
        family = Element % Type % ElementCode / 100
     ELSE
        family = CurrentModel % CurrentElement % Type % ElementCode / 100
     END IF
  END FUNCTION GetElementFamily



  FUNCTION GetElementNOFNodes( Element ) RESULT(n)
DLLEXPORT GetElementNOFNodes
     INTEGER :: n
     TYPE(Element_t), OPTIONAL :: Element

     IF ( PRESENT( Element ) ) THEN
        n = Element % Type % NumberOfNodes
     ELSE
        n = CurrentModel % CurrentElement % Type % NumberOfNodes
     END IF
  END FUNCTION GetELementNOFNodes



  FUNCTION GetElementNOFDOFs( UElement,USolver ) RESULT(n)
DLLEXPORT GetElementNOFDofs
     INTEGER :: n
     TYPE(Solver_t),  OPTIONAL, TARGET :: USolver
     TYPE(Element_t), OPTIONAL, TARGET :: UElement

     TYPE(Element_t), POINTER :: Element
     TYPE(Solver_t),  POINTER :: Solver

     INTEGER :: i,j
     LOGICAL :: Found

     IF ( PRESENT( UElement ) ) THEN
        Element => UElement
     ELSE
        Element => CurrentModel % CurrentElement
     END IF

     IF ( PRESENT( USolver ) ) THEN
        Solver => USolver
     ELSE
        Solver => CurrentModel % Solver
     END IF

     n = 0
     IF ( ListGetLogical( Solver % Values, 'Discontinuous Galerkin', Found )) THEN
        n = Element % DGDOFs
        IF ( n > 0 ) RETURN
     END IF

     n = Element % NDOFs
     IF ( ASSOCIATED( Element % EdgeIndexes ) ) THEN
        DO j=1,Element % Type % NumberOFEdges
           n =  n + Solver % Mesh % Edges( Element % EdgeIndexes(j) ) % BDOFs
        END DO
     END IF

     IF ( ASSOCIATED( Element % FaceIndexes ) ) THEN
        DO j=1,Element % Type % NumberOFFaces
           n = n + Solver % Mesh % Faces( Element % FaceIndexes(j) ) % BDOFs
        END DO
     END IF

     IF ( ListGetLogical( Solver % Values, 'Global Bubbles', Found )) THEN
        n = n + Element % BDOFs
     END IF

  END FUNCTION GetElementNOFDOFs



  FUNCTION GetElementDOFs( Indexes, UElement, USolver )  RESULT(NB)
DLLEXPORT GetElementDOFs
     TYPE(Element_t), OPTIONAL, TARGET :: UElement
     TYPE(Solver_t),  OPTIONAL, TARGET :: USolver
     INTEGER :: Indexes(:)

     TYPE(Solver_t),  POINTER :: Solver
     TYPE(Element_t), POINTER :: Element

     LOGICAL :: Found
     INTEGER :: nb,i,j,EDOFs, FDOFs, BDOFs,FaceDOFs, EdgeDOFs, BubbleDOFs

     IF ( PRESENT( UElement ) ) THEN
        Element => UElement
     ELSE
        Element => CurrentModel % CurrentElement
     END IF

     IF ( PRESENT( USolver ) ) THEN
        Solver => USolver
     ELSE
        Solver => CurrentModel % Solver
     END IF

     NB = 0

     IF ( ListGetLogical( Solver % Values, 'Discontinuous Galerkin', Found ) ) THEN
        DO i=1,Element % DGDOFs
           NB = NB + 1
           Indexes(NB) = Element % DGIndexes(i)
        END DO

        IF ( ASSOCIATED( Element % BoundaryInfo ) ) THEN
           IF ( ASSOCIATED( Element % BoundaryInfo % Left ) ) THEN
              DO i=1,Element % BoundaryInfo % Left % DGDOFs
                 NB = NB + 1
                 Indexes(NB) = Element % BoundaryInfo % Left % DGIndexes(i)
              END DO
           END IF
           IF ( ASSOCIATED( Element % BoundaryInfo % Right ) ) THEN
              DO i=1,Element % BoundaryInfo % Right % DGDOFs
                 NB = NB + 1
                 Indexes(NB) = Element % BoundaryInfo % Right % DGIndexes(i)
              END DO
           END IF
        END IF

        IF ( NB > 0 ) RETURN
     END IF

     DO i=1,Element % NDOFs
        NB = NB + 1
        Indexes(NB) = Element % NodeIndexes(i)
     END DO

     FaceDOFs   = Solver % Mesh % MaxFaceDOFs
     EdgeDOFs   = Solver % Mesh % MaxEdgeDOFs
     BubbleDOFs = Solver % Mesh % MaxBDOFs

     IF ( ASSOCIATED( Element % EdgeIndexes ) ) THEN
        DO j=1,Element % Type % NumberOFEdges
          EDOFs = Solver % Mesh % Edges( Element % EdgeIndexes(j) ) % BDOFs
          DO i=1,EDOFs
             NB = NB + 1
             Indexes(NB) = EdgeDOFs*(Element % EdgeIndexes(j)-1) + &
                      i + Solver % Mesh % NumberOfNodes
          END DO
        END DO
     END IF

     IF ( ASSOCIATED( Element % FaceIndexes ) ) THEN
        DO j=1,Element % Type % NumberOFFaces
           FDOFs = Solver % Mesh % Faces( Element % FaceIndexes(j) ) % BDOFs
           DO i=1,FDOFs
              NB = NB + 1
              Indexes(NB) = FaceDOFs*(Element % FaceIndexes(j)-1) + i + &
                 Solver % Mesh % NumberOfNodes + EdgeDOFs*Solver % Mesh % NumberOfEdges
           END DO
        END DO
     END IF

     IF ( ListGetLogical( Solver % Values, 'Global Bubbles', Found ) ) THEN
        IF ( ASSOCIATED( Element % BubbleIndexes ) ) THEN
           DO i=1,Element % BDOFs
              NB = NB + 1
              Indexes(NB) = FaceDOFs*Solver % Mesh % NumberOfFaces + &
                 Solver % Mesh % NumberOfNodes + EdgeDOFs*Solver % Mesh % NumberOfEdges+ &
                   Element % BubbleIndexes(i)
           END DO
        END IF
     END IF
  END FUNCTION GetElementDOFs



  FUNCTION GetElementNOFBDOFs( Element, USolver ) RESULT(n)
DLLEXPORT GetElementNOFBDOFs
    INTEGER :: n
    TYPE(Solver_t), OPTIONAL, POINTER :: USolver
    TYPE(Element_t), OPTIONAL, POINTER :: Element

    TYPE(Solver_t), POINTER :: Solver

    LOGICAL :: Found

    IF ( PRESENT( USolver ) ) THEN
       Solver => USolver
    ELSE
       Solver => CurrentModel % Solver
    END IF

    n = 0
    IF ( .NOT. ListGetLogical( Solver % Values, 'Global Bubbles', Found ) ) THEN
      IF ( PRESENT( Element ) ) THEN
         n = Element % BDOFs
      ELSE
         n = CurrentModel % CurrentElement % BDOFs
      END IF
    END IF
  END FUNCTION GetElementNOFBDOFs



  SUBROUTINE GetElementNodes( ElementNodes, UElement, USolver )
DLLEXPORT GetElementNodes
     TYPE(Nodes_t) :: ElementNodes
     TYPE(Solver_t), OPTIONAL, TARGET :: USolver
     TYPE(Element_t), OPTIONAL, TARGET :: UElement

     INTEGER :: n

     TYPE(Solver_t), POINTER  :: Solver
     TYPE(Element_t), POINTER :: Element

     Solver => CurrentModel % Solver
     IF ( PRESENT( USolver ) ) Solver => USolver

     Element => CurrentModel % CurrentElement
     IF ( PRESENT( UElement ) ) Element => UElement

     IF ( .NOT. ASSOCIATED( ElementNodes % x ) ) THEN
        n = Solver % Mesh % MaxElementNodes
        ALLOCATE( ElementNodes % x(n) )
        ALLOCATE( ElementNodes % y(n) )
        ALLOCATE( ElementNodes % z(n) )
     END IF

     n = Element % Type % NumberOfNodes
     ElementNodes % x(1:n) = Solver % Mesh % Nodes % x(Element % NodeIndexes)
     ElementNodes % y(1:n) = Solver % Mesh % Nodes % y(Element % NodeIndexes)
     ElementNodes % z(1:n) = Solver % Mesh % Nodes % z(Element % NodeIndexes)
  END SUBROUTINE GetElementNodes

  
!------------------------------------------------------------------------------
  SUBROUTINE GetRefPElementNodes( ElementNodes, Element, USolver )      
!******************************************************************************
!
!  DESCRIPTION:
!     Subroutine for getting reference p element nodes (because these are NOT
!     yet defined in element description files)
!
!  ARGUMENTS:
!
!    Type(Nodes_t) :: ElementNodes
!      INOUT: Nodes of element
!
!    Type(Element_t) :: Element
!      INPUT: Element to get nodes for
!
!    Type(Solver_t), OPTIONAL, TARGET :: USolver
!      INPUT: Solver from which to get nodes
!
!******************************************************************************
!------------------------------------------------------------------------------
    IMPLICIT NONE
    
    TYPE(Nodes_t) :: ElementNodes
    Type(Element_t) :: Element
      TYPE(Solver_t), OPTIONAL, TARGET  :: USolver

      TYPE(Solver_t), POINTER  :: Solver
      INTEGER :: i, n

      ! If element is not p element return
      IF (.NOT. ASSOCIATED( Element % PDefs ) ) THEN 
         CALL Warn('DefUtils::GetRefPElementNodes','Element given not a p element')
         RETURN
      END IF

      Solver => CurrentModel % Solver
      IF ( PRESENT( USolver ) ) Solver => USolver

      ! Reserve space for element nodes
      IF ( .NOT. ASSOCIATED( ElementNodes % x ) ) THEN
         n = Solver % Mesh % MaxElementNodes
         ALLOCATE( ElementNodes % x(n) )
         ALLOCATE( ElementNodes % y(n) )
         ALLOCATE( ElementNodes % z(n) )
      END IF

      ! Select by element type given
      SELECT CASE(Element % Type % ElementCode / 100)
      ! Line
      CASE(2)
         ElementNodes % x(:) = (/ -1d0,1d0 /)
         ElementNodes % y = 0
         ElementNodes % z = 0
      ! Triangle
      CASE(3)
         ElementNodes % x(:) = (/ -1d0,1d0,0d0 /)
         ElementNodes % y(:) = (/ 0d0,0d0,1.732050808d0 /)
         ElementNodes % z = 0
      ! Quad
      CASE(4)
         ElementNodes % x(:) = (/ -1d0,1d0,1d0,-1d0 /)
         ElementNodes % y(:) = (/ -1d0,-1d0,1d0,1d0 /)
         ElementNodes % z = 0
      ! Tetrahedron
      CASE(5)
         ElementNodes % x(:) = (/ -1d0,1d0,0d0,0d0 /)
         ElementNodes % y(:) = (/ 0d0,0d0,1.732050808d0,0.5773502693d0 /)
         ElementNodes % z(:) = (/ 0d0,0d0,0d0,1.632993162d0 /)
      ! Pyramid
      CASE(6)
         ElementNodes % x(:) = (/ -1d0,1d0,1d0,-1d0,0d0 /)
         ElementNodes % y(:) = (/ -1d0,-1d0,1d0,1d0,0d0 /)
         ElementNodes % z(:) = (/ 0d0,0d0,0d0,0d0,1.414213562d0 /)
      ! Wedge
      CASE(7)
         ElementNodes % x(:) = (/ -1d0,1d0,0d0,-1d0,1d0,0d0 /)
         ElementNodes % y(:) = (/ 0d0,0d0,1.732050808d0,0d0,0d0,1.732050808d0 /)
         ElementNodes % z(:) = (/ -1d0,-1d0,-1d0,1d0,1d0,1d0 /)
      ! Brick
      CASE(8)
         ElementNodes % x(:) = (/ -1d0,1d0,1d0,-1d0,-1d0,1d0,1d0,-1d0 /)
         ElementNodes % y(:) = (/ -1d0,-1d0,1d0,1d0,-1d0,-1d0,1d0,1d0 /)
         ElementNodes % z(:) = (/ -1d0,-1d0,-1d0,-1d0,1d0,1d0,1d0,1d0 /)
      CASE DEFAULT
         CALL Warn('DefUtils::GetRefPElementNodes','Unknown element type')
      END SELECT
    END SUBROUTINE GetRefPElementNodes


  FUNCTION GetBodyForceId(  Element, Found ) RESULT(bf_id)
DLLEXPORT GetBodyForceId
     LOGICAL, OPTIONAL :: Found
     TYPE(Element_t), OPTIONAL :: Element

     INTEGER :: bf_id, body_id

     IF ( PRESENT( Element ) ) THEN
        body_id = Element % BodyId 
     ELSE
        body_id = CurrentModel % CurrentElement % BodyId 
     END IF

     IF ( PRESENT( Found ) ) THEN
        bf_id = ListGetInteger( CurrentModel % Bodies(body_id) % Values, &
           'Body Force', Found, minv=1,maxv=CurrentModel % NumberOfBodyForces )
     ELSE
        bf_id = ListGetInteger( CurrentModel % Bodies(body_id) % Values, &
            'Body Force', minv=1,maxv=CurrentModel % NumberOfBodyForces )
     END IF
  END FUNCTION GetBodyForceId



  FUNCTION GetMaterialId( Element, Found ) RESULT(mat_id)
DLLEXPORT GetMaterialId
     LOGICAL, OPTIONAL :: Found
     TYPE(Element_t), OPTIONAL :: Element

     INTEGER :: mat_id, body_id

     IF ( PRESENT( Element ) ) THEN
        body_id = Element % BodyId 
     ELSE
        body_id = CurrentModel % CurrentElement % BodyId 
     END IF

     IF ( PRESENT( Found ) ) THEN
        mat_id = ListGetInteger( CurrentModel % Bodies(body_id) % Values, &
           'Material', Found, minv=1,maxv=CurrentModel % NumberOfMaterials )
     ELSE
        mat_id = ListGetInteger( CurrentModel % Bodies(body_id) % Values, &
           'Material', minv=1,maxv=CurrentModel % NumberOfMaterials )
     END IF
  END FUNCTION GetMaterialId



  FUNCTION GetEquationId( Element, Found ) RESULT(eq_id)
DLLEXPORT GetEquationId
     LOGICAL, OPTIONAL :: Found
     TYPE(Element_t), OPTIONAL :: Element

     INTEGER :: eq_id, body_id

     IF ( PRESENT( Element ) ) THEN
        body_id = Element % BodyId 
     ELSE
        body_id = CurrentModel % CurrentElement % BodyId 
     END IF

     IF ( PRESENT( Found ) ) THEN
        eq_id = ListGetInteger( CurrentModel % Bodies(body_id) % Values, &
           'Equation', Found, minv=1,maxv=CurrentModel % NumberOfEquations )
     ELSE
        eq_id = ListGetInteger( CurrentModel % Bodies(body_id) % Values, &
           'Equation',  minv=1,maxv=CurrentModel % NumberOfEquations )
     END IF
  END FUNCTION GetEquationId



  FUNCTION GetSimulation() RESULT(Simulation)
DLLEXPORT GetSimulation
     TYPE(ValueList_t), POINTER :: Simulation
     Simulation => CurrentModel % Simulation
  END FUNCTION GetSimulation



  FUNCTION GetConstants() RESULT(Constants)
DLLEXPORT GetConstants
     TYPE(ValueList_t), POINTER :: Constants
     Constants => CurrentModel % Constants
  END FUNCTION GetConstants



  FUNCTION GetSolverParams() RESULT(SolverParam)
DLLEXPORT GetSolverParams
     TYPE(ValueList_t), POINTER :: SolverParam
     SolverParam => CurrentModel % Solver % Values
  END FUNCTION GetSolverParams



  FUNCTION GetMaterial(  Element, Found ) RESULT(Material)
DLLEXPORT GetMaterial
    TYPE(Element_t), OPTIONAL :: Element
    LOGICAL, OPTIONAL :: Found

    TYPE(ValueList_t), POINTER :: Material

    LOGICAL :: L
    INTEGER :: mat_id

    IF ( PRESENT( Element ) ) THEN
        mat_id = GetMaterialId( Element, L )
    ELSE
        mat_id = GetMaterialId( Found=L )
    END IF

    NULLIFY( Material )
    IF ( L ) Material => CurrentModel % Materials(mat_id) % Values
    IF ( PRESENT( Found ) ) Found = L
  END FUNCTION GetMaterial



  FUNCTION GetBodyForce( Element, Found ) RESULT(BodyForce)
DLLEXPORT GetBodyForce
    TYPE(Element_t), OPTIONAL :: Element
    LOGICAL, OPTIONAL :: Found

    TYPE(ValueList_t), POINTER :: BodyForce

    LOGICAL :: l
    INTEGER :: bf_id

    IF ( PRESENT( Element ) ) THEN
       bf_id = GetBodyForceId( Element, L )
    ELSE
       bf_id = GetBodyForceId( Found=L )
    END IF

    NULLIFY( BodyForce )
    IF ( L ) BodyForce => CurrentModel % BodyForces(bf_id) % Values
    IF ( PRESENT( Found ) ) Found = L
  END FUNCTION GetBodyForce



  FUNCTION GetEquation( Element, Found ) RESULT(Equation)
DLLEXPORT GetEquation
    TYPE(Element_t), OPTIONAL :: Element
    LOGICAL, OPTIONAL :: Found

    TYPE(ValueList_t), POINTER :: Equation

    LOGICAL :: L
    INTEGER :: eq_id


    IF ( PRESENT( Element ) ) THEN
       eq_id = GetEquationId( Element, L )
    ELSE
       eq_id = GetEquationId( Found=L )
    END IF

    NULLIFY( Equation )
    IF ( L ) Equation => CurrentModel % Equations(eq_id) % Values
    IF ( PRESENT( Found ) ) Found = L
  END FUNCTION GetEquation



  FUNCTION GetBCId( UElement ) RESULT(bc_id)
DLLEXPORT GetBCId
     TYPE(Element_t), OPTIONAL, TARGET :: UElement

     INTEGER :: bc_id

     TYPE(Element_t), POINTER :: Element

     Element => CurrentModel % CurrentElement
     IF ( PRESENT(Uelement) ) Element => UElement

     DO bc_id=1,CurrentModel % NumberOfBCs
        IF ( Element % BoundaryInfo % Constraint == CurrentModel % BCs(bc_id) % Tag ) EXIT
     END DO
     IF ( bc_id > CurrentModel % NumberOfBCs ) bc_id=0
  END FUNCTION GetBCId



  FUNCTION GetBC( UElement ) RESULT(bc)
DLLEXPORT GetBC
     TYPE(Element_t), OPTIONAL, TARGET :: UElement
     TYPE(ValueList_t), POINTER :: BC

     INTEGER :: bc_id

     TYPE(Element_t), POINTER :: Element

     Element => CurrentModel % CurrentElement
     IF ( PRESENT(Uelement) ) Element => UElement

     NULLIFY(bc)
     bc_id = GetBCId( Element )
     IF ( bc_id > 0 )  BC => CurrentModel % BCs(bc_id) % Values
  END FUNCTION GetBC



  FUNCTION GetICId( Element, Found ) RESULT(ic_id)
DLLEXPORT GetICId
     LOGICAL, OPTIONAL :: Found
     TYPE(Element_t), OPTIONAL :: Element

     INTEGER :: ic_id, body_id

     IF ( PRESENT( Element ) ) THEN
        body_id = Element % BodyId 
     ELSE
        body_id = CurrentModel % CurrentElement % BodyId 
     END IF

     IF ( PRESENT( Found ) ) THEN
        ic_id = ListGetInteger( CurrentModel % Bodies(body_id) % Values, &
           'Initial Condition', Found, minv=1,maxv=CurrentModel % NumberOfICs )
     ELSE
        ic_id = ListGetInteger( CurrentModel % Bodies(body_id) % Values, &
           'Initial Condition', minv=1,maxv=CurrentModel % NumberOfICs )
     END IF
  END FUNCTION GetIcId


  FUNCTION GetIC(  Element, Found ) RESULT(IC)
DLLEXPORT GetIC
    TYPE(Element_t), OPTIONAL :: Element
    LOGICAL, OPTIONAL :: Found

    TYPE(ValueList_t), POINTER :: IC

    LOGICAL :: L
    INTEGER :: ic_id

    IF ( PRESENT( Element ) ) THEN
        ic_id = GetICId( Element, L )
    ELSE
        ic_id = GetICId( Found=L )
    END IF

    NULLIFY( IC )
    IF ( L ) IC => CurrentModel % ICs(ic_id) % Values
    IF ( PRESENT( Found ) ) Found = L
  END FUNCTION GetIC


  SUBROUTINE Default1stOrderTimeR( M, A, F, UElement, USolver )
DLLEXPORT Default1stOrderTimeR
    REAL(KIND=dp) :: M(:,:),A(:,:), F(:)
    TYPE(Solver_t),  OPTIONAL, TARGET :: USolver
    TYPE(Element_t), OPTIONAL, TARGET :: UElement

    TYPE(Solver_t), POINTER :: Solver
    TYPE(Variable_t), POINTER :: x
    TYPE(Element_t), POINTER :: Element

    INTEGER :: n
    REAL(KIND=dp) :: dt

    Solver => CurrentModel % Solver
    IF ( PRESENT(USolver) ) Solver => USolver

    Element => CurrentModel % CurrentElement
    IF ( PRESENT(UElement) ) Element => UElement

    x => Solver % Variable

    dt = Solver % dt
    n = GetElementDOFs( Indexes,Element,Solver )

    CALL Add1stOrderTime( M, A, F, dt, n, x % DOFs, &
           x % Perm(Indexes(1:n)), Solver )
  END SUBROUTINE Default1stOrderTimeR


  SUBROUTINE Default1stOrderTimeC( MC, AC, FC, UElement, USolver )
DLLEXPORT Default1stOrderTimeC
    COMPLEX(KIND=dp) :: MC(:,:),AC(:,:), FC(:)
    TYPE(Solver_t),  OPTIONAL, TARGET :: USolver
    TYPE(Element_t), OPTIONAL, TARGET :: UElement

    TYPE(Solver_t), POINTER :: Solver
    TYPE(Variable_t), POINTER :: x
    TYPE(Element_t), POINTER :: Element

    REAL(KIND=dp), ALLOCATABLE :: M(:,:),A(:,:), F(:)

    INTEGER :: i,j,n,DOFs
    REAL(KIND=dp) :: dt

    Solver => CurrentModel % Solver
    IF ( PRESENT(USolver) ) Solver => USolver

    Element => CurrentModel % CurrentElement
    IF ( PRESENT(UElement) ) Element => UElement

    x => Solver % Variable

    dt = Solver % dt
    DOFs = x % DOFs
    n = GetElementDOFs( Indexes,Element,Solver )

    ALLOCATE( M(DOFs*n,DOFs*n), A(DOFs*n,DOFs*n), F(DOFs*n) )
    DO i=1,n*DOFs/2
      F( 2*(i-1)+1 ) =  REAL( FC(i) )
      F( 2*(i-1)+2 ) = AIMAG( FC(i) )

      DO j=1,n*DOFs/2
        M( 2*(i-1)+1, 2*(j-1)+1 ) =   REAL( MC(i,j) )
        M( 2*(i-1)+1, 2*(j-1)+2 ) = -AIMAG( MC(i,j) )
        M( 2*(i-1)+2, 2*(j-1)+1 ) =  AIMAG( MC(i,j) )
        M( 2*(i-1)+2, 2*(j-1)+2 ) =   REAL( MC(i,j) )
        A( 2*(i-1)+1, 2*(j-1)+1 ) =   REAL( AC(i,j) )
        A( 2*(i-1)+1, 2*(j-1)+2 ) = -AIMAG( AC(i,j) )
        A( 2*(i-1)+2, 2*(j-1)+1 ) =  AIMAG( AC(i,j) )
        A( 2*(i-1)+2, 2*(j-1)+2 ) =   REAL( AC(i,j) )
      END DO
    END DO

    CALL Add1stOrderTime( M, A, F, dt, n, x % DOFs, &
           x % Perm(Indexes(1:n)), Solver )

    DO i=1,n*DOFs/2
      FC(i) = DCMPLX( F(2*(i-1)+1), F(2*(i-1)+2) )
      DO j=1,n*DOFs/2
        MC(i,j) = DCMPLX(M(2*(i-1)+1,2*(j-1)+1), -M(2*(i-1)+1,2*(j-1)+2))
        AC(i,j) = DCMPLX(A(2*(i-1)+1,2*(j-1)+1), -A(2*(i-1)+1,2*(j-1)+2))
      END DO
    END DO

    DEALLOCATE( M, A, F )
  END SUBROUTINE Default1stOrderTimeC


  SUBROUTINE Default2ndOrderTimeR( M, B, A, F, UElement, USolver )
DLLEXPORT Default2ndOrderTimeR
    REAL(KIND=dp) :: M(:,:), B(:,:), A(:,:), F(:)
    TYPE(Solver_t),  OPTIONAL, TARGET :: USolver
    TYPE(Element_t), OPTIONAL, TARGET :: UElement

    TYPE(Solver_t), POINTER :: Solver
    TYPE(Variable_t), POINTER :: x
    TYPE(Element_t), POINTER :: Element

    INTEGER :: n
    REAL(KIND=dp) :: dt

    Solver => CurrentModel % Solver
    IF ( PRESENT(USolver) ) Solver => USolver

    Element => CurrentModel % CurrentElement
    IF ( PRESENT(UElement) ) Element => UElement

    x => Solver % Variable

    dt = Solver % dt
    n = GetElementDOFs( Indexes, Element, Solver )

    CALL Add2ndOrderTime( M, B, A, F, dt, n, x % DOFs, &
          x % Perm(Indexes(1:n)), Solver )
  END SUBROUTINE Default2ndOrderTimeR



  SUBROUTINE Default2ndOrderTimeC( MC, BC, AC, FC, UElement, USolver )
DLLEXPORT Default2ndOrderTime
    COMPLEX(KIND=dp) :: MC(:,:), BC(:,:), AC(:,:), FC(:)
    TYPE(Solver_t),  OPTIONAL, TARGET :: USolver
    TYPE(Element_t), OPTIONAL, TARGET :: UElement

    TYPE(Solver_t), POINTER :: Solver
    TYPE(Variable_t), POINTER :: x
    TYPE(Element_t), POINTER :: Element
    REAL(KIND=dp), ALLOCATABLE :: M(:,:), B(:,:), A(:,:), F(:)

    INTEGER :: i,j,n,DOFs
    REAL(KIND=dp) :: dt

    Solver => CurrentModel % Solver
    IF ( PRESENT(USolver) ) Solver => USolver

    Element => CurrentModel % CurrentElement
    IF ( PRESENT(UElement) ) Element => UElement

    x => Solver % Variable

    dt = Solver % dt
    DOFs = x % DOFs
    n = GetElementDOFs( Indexes, Element, Solver )

    ALLOCATE( M(DOFs*n,DOFs*n), A(DOFs*n,DOFs*n), B(DOFs*n,DOFs*n), F(DOFs*n) )
    DO i=1,n*DOFs/2
      F( 2*(i-1)+1 ) =  REAL( FC(i) )
      F( 2*(i-1)+2 ) = AIMAG( FC(i) )

      DO j=1,n*DOFs/2
        M(2*(i-1)+1, 2*(j-1)+1) =   REAL( MC(i,j) )
        M(2*(i-1)+1, 2*(j-1)+2) = -AIMAG( MC(i,j) )
        M(2*(i-1)+2, 2*(j-1)+1) =  AIMAG( MC(i,j) )
        M(2*(i-1)+2, 2*(j-1)+2) =   REAL( MC(i,j) )
        B(2*(i-1)+1, 2*(j-1)+1) =   REAL( BC(i,j) )
        B(2*(i-1)+1, 2*(j-1)+2) = -AIMAG( BC(i,j) )
        B(2*(i-1)+2, 2*(j-1)+1) =  AIMAG( BC(i,j) )
        B(2*(i-1)+2, 2*(j-1)+2) =   REAL( BC(i,j) )
        A(2*(i-1)+1, 2*(j-1)+1) =   REAL( AC(i,j) )
        A(2*(i-1)+1, 2*(j-1)+2) = -AIMAG( AC(i,j) )
        A(2*(i-1)+2, 2*(j-1)+1) =  AIMAG( AC(i,j) )
        A(2*(i-1)+2, 2*(j-1)+2) =   REAL( AC(i,j) )
      END DO
    END DO

    CALL Add2ndOrderTime( M, B, A, F, dt, n, x % DOFs, &
          x % Perm(Indexes(1:n)), Solver )

    DO i=1,n*DOFs/2
      FC(i) = DCMPLX( F(2*(i-1)+1), F(2*(i-1)+2) )
      DO j=1,n*DOFs/2
        MC(i,j) = DCMPLX( M(2*(i-1)+1, 2*(j-1)+1), -M(2*(i-1)+1, 2*(j-1)+2) )
        BC(i,j) = DCMPLX( B(2*(i-1)+1, 2*(j-1)+1), -B(2*(i-1)+1, 2*(j-1)+2) )
        AC(i,j) = DCMPLX( A(2*(i-1)+1, 2*(j-1)+1), -A(2*(i-1)+1, 2*(j-1)+2) )
      END DO
    END DO

    DEALLOCATE( M, B, A, F )
  END SUBROUTINE Default2ndOrderTimeC



  SUBROUTINE DefaultInitialize( Solver )
DLLEXPORT DefaultInitialize
     TYPE(Solver_t), OPTIONAL :: Solver

     IF ( PRESENT( Solver ) ) THEN
        CALL InitializeToZero( Solver % Matrix, Solver % Matrix % RHS )
     ELSE
        CALL InitializeToZero( CurrentModel % Solver % Matrix, &
                CurrentModel % Solver % Matrix % RHS )
     END IF
  END SUBROUTINE DefaultInitialize



  FUNCTION DefaultSolve( USolver ) RESULT(Norm)
DLLEXPORT DefaultSolve
    TYPE(Solver_t), OPTIONAL, TARGET :: USolver
    REAL(KIND=dp) :: Norm

    TYPE(Matrix_t), POINTER   :: A
    TYPE(Variable_t), POINTER :: x
    REAL(KIND=dp), POINTER    :: b(:)

    TYPE(Solver_t), POINTER :: Solver

    Solver => CurrentModel % Solver
    IF ( PRESENT( USolver ) ) Solver => USolver

    A => Solver % Matrix
    b => A % RHS
    x => Solver % Variable

    CALL SolveSystem( A, ParMatrix, b, x % Values, x % Norm, x % DOFs, Solver )
    Norm = x % Norm
  END FUNCTION DefaultSolve


  SUBROUTINE DefaultUpdateEquationsR( G, F, UElement, USolver ) 
DLLEXPORT DefaultUpdateEquationsR
     TYPE(Solver_t),  OPTIONAL, TARGET :: USolver
     TYPE(Element_t), OPTIONAL, TARGET :: UElement
     REAL(KIND=dp)   :: G(:,:), f(:)

     TYPE(Solver_t), POINTER   :: Solver
     TYPE(Matrix_t), POINTER   :: A
     TYPE(Variable_t), POINTER :: x
     REAL(KIND=dp), POINTER    :: b(:)
     TYPE(Element_t), POINTER  :: Element

     INTEGER :: n

     IF ( PRESENT( USolver ) ) THEN
        Solver => USolver
     ELSE
        Solver => CurrentModel % Solver
     END IF
     A => Solver % Matrix
     x => Solver % Variable
     b => A % RHS

     IF ( PRESENT( UElement ) ) THEN
        Element => UElement 
     ELSE
        Element => CurrentModel % CurrentElement
     END IF

     n = GetElementDOFs( Indexes, Element, Solver )
     CALL UpdateGlobalEquations( A,G,b,f,n,x % DOFs,x % Perm(Indexes(1:n)) )
  END SUBROUTINE DefaultUpdateEquationsR



  SUBROUTINE DefaultUpdateEquationsC( GC, FC, UElement, USolver ) 
DLLEXPORT DefaultUpdateEquationsC
     TYPE(Solver_t),  OPTIONAL, TARGET :: USolver
     TYPE(Element_t), OPTIONAL, TARGET :: UElement
     COMPLEX(KIND=dp)   :: GC(:,:), FC(:)

     TYPE(Solver_t), POINTER   :: Solver
     TYPE(Matrix_t), POINTER   :: A
     TYPE(Variable_t), POINTER :: x
     REAL(KIND=dp), POINTER    :: b(:)
     TYPE(Element_t), POINTER  :: Element

     REAL(KIND=dp), POINTER :: G(:,:), F(:)

     INTEGER :: i,j,n,DOFs

     IF ( PRESENT( USolver ) ) THEN
        Solver => USolver
     ELSE
        Solver => CurrentModel % Solver
     END IF
     A => Solver % Matrix
     x => Solver % Variable
     b => A % RHS

     IF ( PRESENT( UElement ) ) THEN
        Element => UElement 
     ELSE
        Element => CurrentModel % CurrentElement
     END IF

     DOFs = x % DOFs
     n = GetElementDOFs( Indexes, Element, Solver )

     ALLOCATE( G(DOFs*n,DOFs*n), F(DOFs*n) )
     DO i=1,n*DOFs/2
       F( 2*(i-1)+1 ) =  REAL( FC(i) )
       F( 2*(i-1)+2 ) = AIMAG( FC(i) )

       DO j=1,n*DOFs/2
         G( 2*(i-1)+1, 2*(j-1)+1 ) =   REAL( GC(i,j) )
         G( 2*(i-1)+1, 2*(j-1)+2 ) = -AIMAG( GC(i,j) )
         G( 2*(i-1)+2, 2*(j-1)+1 ) =  AIMAG( GC(i,j) )
         G( 2*(i-1)+2, 2*(j-1)+2 ) =   REAL( GC(i,j) )
       END DO
     END DO

     CALL UpdateGlobalEquations( A,G,b,f,n,x % DOFs,x % Perm(Indexes(1:n)) )
 
     DEALLOCATE( G, F)
  END SUBROUTINE DefaultUpdateEquationsC



  SUBROUTINE DefaultUpdateForceR( F, UElement, USolver )
DLLEXPORT DefaultUpdateForceR
    REAL(KIND=dp) :: F(:)
    TYPE(Solver_t),  OPTIONAL, TARGET :: USolver
    TYPE(Element_t), OPTIONAL, TARGET :: UElement

    TYPE(Solver_t), POINTER :: Solver
    TYPE(Variable_t), POINTER :: x
    TYPE(Element_t), POINTER :: Element

    INTEGER :: n

    Solver => CurrentModel % Solver
    IF ( PRESENT(USolver) ) Solver => USolver

    Element => CurrentModel % CurrentElement
    IF ( PRESENT(UElement) ) Element => UElement

    x => Solver % Variable
    n = GetElementDOFs( Indexes, Element, Solver )

    CALL UpdateTimeForce( Solver % Matrix,Solver % Matrix % RHS, &
         F, n, x % DOFs, x % Perm(Indexes(1:n)) )
  END SUBROUTINE DefaultUpdateForceR



  SUBROUTINE DefaultUpdateForceC( FC, UElement, USolver )
DLLEXPORT DefaultUpdateForceC
    COMPLEX(KIND=dp) :: FC(:)
    TYPE(Solver_t),  OPTIONAL, TARGET :: USolver
    TYPE(Element_t), OPTIONAL, TARGET :: UElement

    TYPE(Solver_t), POINTER :: Solver
    TYPE(Variable_t), POINTER :: x
    TYPE(Element_t), POINTER :: Element

    REAL(KIND=dp), ALLOCATABLE :: F(:)

    INTEGER :: i,n,DOFs

    Solver => CurrentModel % Solver
    IF ( PRESENT(USolver) ) Solver => USolver

    Element => CurrentModel % CurrentElement
    IF ( PRESENT(UElement) ) Element => UElement

    x => Solver % Variable
    DOFs = x % DOFs
    n = GetElementDOFs( Indexes, Element, Solver )

    ALLOCATE( F(DOFs*n) )
    DO i=1,n*DOFs/2
       F( 2*(i-1) + 1 ) =   REAL(FC(i))
       F( 2*(i-1) + 2 ) = -AIMAG(FC(i))
    END DO

    CALL UpdateTimeForce( Solver % Matrix,Solver % Matrix % RHS, &
             F, n, x % DOFs, x % Perm(Indexes(1:n)) )

    DEALLOCATE( F ) 
  END SUBROUTINE DefaultUpdateForceC



  SUBROUTINE DefaultUpdateMassR( M, UElement, USolver ) 
DLLEXPORT DefaultUpdateMassR
     TYPE(Solver_t), OPTIONAL,TARGET   :: USolver
     TYPE(Element_t), OPTIONAL, TARGET :: UElement
     REAL(KIND=dp)   :: M(:,:)

     TYPE(Solver_t), POINTER   :: Solver
     TYPE(Matrix_t), POINTER   :: A
     TYPE(Variable_t), POINTER :: x
     TYPE(Element_t), POINTER  :: Element

     INTEGER :: i,j,n

     IF ( PRESENT( USolver ) ) THEN
        Solver => USolver
        A => Solver % Matrix
        x => Solver % Variable
     ELSE
        Solver => CurrentModel % Solver
        A => Solver % Matrix
        x => Solver % Variable
     END IF

     IF ( PRESENT( UElement ) ) THEN
        Element => UElement 
     ELSE
        Element => CurrentModel % CurrentElement
     END IF

     n = GetElementDOFs( Indexes, Element, Solver )

     IF ( .NOT. ASSOCIATED( A % MassValues ) ) THEN
        ALLOCATE( A % MassValues(SIZE(A % Values)) )
        A % MassValues = 0.0d0
     END IF

     CALL UpdateMassMatrix( A, M, n, x % DOFs, x % Perm(Indexes(1:n)) )
  END SUBROUTINE DefaultUpdateMassR



  SUBROUTINE DefaultUpdateMassC( MC, UElement, USolver ) 
DLLEXPORT DefaultUpdateMassC
     TYPE(Solver_t), OPTIONAL,TARGET   :: USolver
     TYPE(Element_t), OPTIONAL, TARGET :: UElement
     COMPLEX(KIND=dp)   :: MC(:,:)

     TYPE(Solver_t), POINTER   :: Solver
     TYPE(Matrix_t), POINTER   :: A
     TYPE(Variable_t), POINTER :: x
     TYPE(Element_t), POINTER  :: Element

     REAL(KIND=dp), ALLOCATABLE :: M(:,:)

     INTEGER :: i,j,n,DOFs

     IF ( PRESENT( USolver ) ) THEN
        Solver => USolver
        A => Solver % Matrix
        x => Solver % Variable
     ELSE
        Solver => CurrentModel % Solver
        A => Solver % Matrix
        x => Solver % Variable
     END IF

     IF ( PRESENT( UElement ) ) THEN
        Element => UElement 
     ELSE
        Element => CurrentModel % CurrentElement
     END IF

     DOFs = x % DOFs
     n = GetElementDOFs( Indexes, Element, Solver )

     IF ( .NOT. ASSOCIATED( A % MassValues ) ) THEN
        ALLOCATE( A % MassValues(SIZE(A % Values)) )
        A % MassValues = 0.0d0
     END IF

     ALLOCATE( M(DOFs*n,DOFs*n) )
     DO i=1,n*DOFs/2
       DO j=1,n*DOFs/2
         M(2*(i-1)+1, 2*(j-1)+1) =   REAL( MC(i,j) )
         M(2*(i-1)+1, 2*(j-1)+2) = -AIMAG( MC(i,j) )
         M(2*(i-1)+2, 2*(j-1)+1) =  AIMAG( MC(i,j) )
         M(2*(i-1)+2, 2*(j-1)+2) =   REAL( MC(i,j) )
       END DO
     END DO

     CALL UpdateMassMatrix( A, M, n, x % DOFs, x % Perm(Indexes(1:n)) )
     DEALLOCATE( M )
  END SUBROUTINE DefaultUpdateMassC



  SUBROUTINE DefaultUpdateDampR( B, UElement, USolver ) 
DLLEXPORT DefaultUpdateDampR
     TYPE(Solver_t), OPTIONAL,  TARGET :: USolver
     TYPE(Element_t), OPTIONAL, TARGET :: UElement
     REAL(KIND=dp)   :: B(:,:)

     TYPE(Solver_t), POINTER   :: Solver
     TYPE(Matrix_t), POINTER   :: A
     TYPE(Variable_t), POINTER :: x
     TYPE(Element_t), POINTER  :: Element

     REAL(KIND=dp), POINTER :: SaveValues(:)

     INTEGER :: i,j,n

     IF ( PRESENT( USolver ) ) THEN
        Solver => USolver
     ELSE
        Solver => CurrentModel % Solver
     END IF

     A => Solver % Matrix
     x => Solver % Variable

     IF ( PRESENT( UElement ) ) THEN
        Element => UElement 
     ELSE
        Element => CurrentModel % CurrentElement
     END IF

     n =  GetElementDOFs( Indexes, Element, Solver )

     IF ( .NOT. ASSOCIATED( A % DampValues ) ) THEN
        ALLOCATE( A % DampValues(SIZE(A % Values)) ) 
        A % DampValues = 0.0d0
     END IF

     SaveValues => A % MassValues
     A % MassValues => A % DampValues
     CALL UpdateMassMatrix( A, B, n, x % DOFs, x % Perm(Indexes(1:n)) )
     A % MassValues => SaveValues
  END SUBROUTINE DefaultUpdateDampR



  SUBROUTINE DefaultUpdateDampC( BC, UElement, USolver ) 
DLLEXPORT DefaultUpdateDampC
     TYPE(Solver_t), OPTIONAL,  TARGET :: USolver
     TYPE(Element_t), OPTIONAL, TARGET :: UElement
     COMPLEX(KIND=dp)   :: BC(:,:)

     TYPE(Solver_t), POINTER   :: Solver
     TYPE(Matrix_t), POINTER   :: A
     TYPE(Variable_t), POINTER :: x
     TYPE(Element_t), POINTER  :: Element

     REAL(KIND=dp), POINTER :: SaveValues(:)

     REAL(KIND=dp), ALLOCATABLE :: B(:,:)

     INTEGER :: i,j,n,DOFs

     IF ( PRESENT( USolver ) ) THEN
        Solver => USolver
     ELSE
        Solver => CurrentModel % Solver
     END IF

     A => Solver % Matrix
     x => Solver % Variable

     IF ( PRESENT( UElement ) ) THEN
        Element => UElement 
     ELSE
        Element => CurrentModel % CurrentElement
     END IF

     DOFs = x % DOFs
     n =  GetElementDOFs( Indexes, Element, Solver )

     IF ( .NOT. ASSOCIATED( A % DampValues ) ) THEN
        ALLOCATE( A % DampValues(SIZE(A % Values)) ) 
        A % DampValues = 0.0d0
     END IF

     ALLOCATE( B(DOFs*n, DOFs*n) )
     DO i=1,n*DOFs/2
       DO j=1,n*DOFs/2
         B(2*(i-1)+1, 2*(j-1)+1) =   REAL( BC(i,j) )
         B(2*(i-1)+1, 2*(j-1)+2) = -AIMAG( BC(i,j) )
         B(2*(i-1)+2, 2*(j-1)+1) =  AIMAG( BC(i,j) )
         B(2*(i-1)+2, 2*(j-1)+2) =   REAL( BC(i,j) )
       END DO
     END DO

     SaveValues => A % MassValues
     A % MassValues => A % DampValues
     CALL UpdateMassMatrix( A, B, n, x % DOFs, x % Perm(Indexes(1:n)) )
     A % MassValues => SaveValues

     DEALLOCATE( B )
  END SUBROUTINE DefaultUpdateDampC



  SUBROUTINE DefaultDirichletBCs( USolver )
DLLEXPORT DefaultDirichletBCs
     TYPE(Solver_t), OPTIONAL, TARGET :: USolver

     TYPE(Matrix_t), POINTER   :: A
     TYPE(Variable_t), POINTER :: x
     TYPE(Solver_t), POINTER :: Solver
     REAL(KIND=dp), POINTER    :: b(:)
     REAL(KIND=dp) :: xx, Work(MAX_NODES), STIFF(MAX_NODES,MAX_NODES)
     INTEGER :: i,j, k, kk, l, m, n,nd, nb, mb, nn, DOF, local, numEdgeDofs, & 
          lInd(MAX_NODES), gInd(MAX_NODES) 
     LOGICAL :: Flag,Found
     TYPE(ValueList_t), POINTER :: BC
     TYPE(Element_t), POINTER :: Element, Parent, Edge, Face, SaveElement

     CHARACTER(LEN=MAX_NAME_LEN) :: name

     IF ( PRESENT( USolver ) ) THEN
        Solver => USolver
     ELSE
        Solver => CurrentModel % Solver
     END IF
     A => Solver % Matrix
     x => Solver % Variable
     b => A % RHS

     IF ( x % DOFs > 1 ) THEN
        ! TEMP!!!
        CALL SetDirichletBoundaries( CurrentModel,A, b, x % Name,-1,x % DOFs,x % Perm )
     END IF

     CALL Info('DefUtils::DefaultDirichletBCs','Setting Diriclet boundary conditions')

     DO DOF=1,x % DOFs
        name = x % name
        IF ( x % DOFs > 1 ) name = ComponentName( name, DOF )

        ! Dirichlet BCs for face & edge DOFs:
        ! -----------------------------------
        DO i=1,Solver % Mesh % NumberOfBoundaryElements
           Element => GetBoundaryElement(i)
           IF ( .NOT. ActiveBoundaryElement() ) CYCLE

           BC => GetBC()
           IF ( .NOT. ASSOCIATED( BC ) ) CYCLE
           IF ( .NOT. ListCheckPresent( BC, TRIM(Name) ) ) CYCLE

           Parent => Element % BoundaryInfo % Left
           IF ( .NOT. ASSOCIATED( Parent ) ) THEN
               Parent => Element % BoundaryInfo % Right
           END IF
           IF ( .NOT. ASSOCIATED( Parent ) ) CYCLE

           ! Clear dofs associated with element edges:
           ! -----------------------------------------
           IF ( ASSOCIATED( Solver % Mesh % Edges ) ) THEN
              DO j=1,Parent % Type % NumberOfEdges
                 Edge => Solver % Mesh % Edges( Parent % EdgeIndexes(j) )
                 IF ( Edge % BDOFs == 0 ) CYCLE

                 n = 0
                 DO k=1,Element % Type % NumberOfNodes
                   DO l=1,Edge % Type % NumberOfNodes
                     IF ( Edge % NodeIndexes(l) == Element % NodeIndexes(k) ) n=n+1
                   END DO
                 END DO

                 IF ( n == Edge % Type % NumberOfNodes ) THEN
                   DO k=1,Edge % BDOFs
                      n = Solver % Mesh % NumberofNodes + &
                          (Parent % EdgeIndexes(j)-1)*Solver % Mesh % MaxEdgeDOFs+k

                      n = x % Perm( n )
                      IF ( n <= 0 ) CYCLE
                      n = x % DOFs*(n-1) + DOF
                      CALL CRS_ZeroRow( A, n )
                      A % RHS(n) = 0.0d0
                   END DO
                 END IF
              END DO
           END IF

           ! Clear dofs associated with element faces:
           ! -----------------------------------------
           IF ( ASSOCIATED( Solver % Mesh % Faces ) ) THEN
              DO j=1,Parent % Type % NumberOfFaces
                 Face => Solver % Mesh % Faces( Parent % FaceIndexes(j) )
                 IF ( Face % BDOFs == 0 ) CYCLE

                 n = 0
                 DO k=1,Element % Type % NumberOfNodes
                   DO l=1,Face % Type % NumberOfNodes
                     IF ( Face % NodeIndexes(l) == Element % NodeIndexes(k) ) n=n+1
                   END DO
                 END DO
                 IF ( n /= Face % Type % NumberOfNodes ) CYCLE

                 DO k=1,Face % BDOFs
                    n = Solver % Mesh % NumberofNodes + &
                      Solver % Mesh % MaxEdgeDOFs * Solver % Mesh % NumberOfEdges + &
                        (Parent % FaceIndexes(j)-1) * Solver % Mesh % MaxFaceDOFs + k

                    n = x % Perm( n )
                    IF ( n <= 0 ) CYCLE
                    n = x % DOFs*(n-1) + DOF
                    CALL CRS_ZeroRow( A, n )
                    A % RHS(n) = 0.0d0
                 END DO
              END DO
           END IF
        END DO
     END DO

     ! Set Dirichlet dofs for edges and faces
     DO DOF=1,x % DOFs
        name = x % name
        IF ( x % DOFs > 1 ) name = ComponentName(name,DOF)
        
        CALL SetDirichletBoundaries( CurrentModel, A, b, &
                Name, DOF, x % DOFs, x % Perm )

        SaveElement => CurrentModel % CurrentElement
!       Dirichlet BCs for face & edge DOFs:
!       -----------------------------------
        DO i=1,Solver % Mesh % NumberOfBoundaryElements
           Element => GetBoundaryElement(i)
           IF ( .NOT. ActiveBoundaryElement() ) CYCLE

           BC => GetBC()
           IF ( .NOT. ASSOCIATED( BC ) ) CYCLE
           IF ( .NOT. ListCheckPresent( BC, TRIM(Name) ) ) CYCLE

           ! Get parent element:
           ! -------------------
           Parent => Element % BoundaryInfo % Left
           IF ( .NOT. ASSOCIATED( Parent ) ) THEN
               Parent => Element % BoundaryInfo % Right
           END IF
           IF ( .NOT. ASSOCIATED( Parent ) )   CYCLE
           IF ( .NOT. ASSOCIATED( Parent % pDefs ) ) CYCLE

           n = Element % Type % NumberOfNodes
           DO j=1,n
             l = Element % NodeIndexes(j)
             Work(j)  = ListGetConstReal( BC, Name, Found, &
               CurrentModel % Mesh % Nodes % x(l), &
               CurrentModel % Mesh % Nodes % y(l), &
               CurrentModel % Mesh % Nodes % z(l) )
           END DO

           SELECT CASE(Parent % Type % Dimension)
           CASE(2)
              ! If no edges do not try to set boundary conditions
              ! @todo This should changed to EXIT
              IF ( .NOT. ASSOCIATED( Solver % Mesh % Edges ) ) CYCLE

              ! If boundary edge has no dofs move on to next edge
              IF (Element % BDOFs <= 0) CYCLE

              ! Number of nodes for this element
              n = Element % Type % NumberOfNodes
              
              ! Get indexes for boundary and values for dofs associated to them
              CALL getBoundaryIndexes( Solver % Mesh, Element, Parent, gInd, numEdgeDofs )
              CALL LocalBcBDOFs( BC, Element, numEdgeDofs, Name, STIFF, Work )

              ! Contribute this boundary to global system
              ! (i.e solve global boundary problem)
              DO k=n+1,numEdgeDofs
                 nb = x % Perm( gInd(k) )
                 IF ( nb <= 0 ) CYCLE
                 nb = x % DOFs * (nb-1) + DOF
                 A % RHS(nb) = A % RHS(nb) + Work(k)
                 DO l=1,numEdgeDofs
                    mb = x % Perm( gInd(l) )
                    IF ( mb <= 0 ) CYCLE
                    mb = x % DOFs * (mb-1) + DOF
                    DO kk=A % Rows(nb)+DOF-1,A % Rows(nb+1)-1,x % DOFs
                       IF ( A % Cols(kk) == mb ) THEN
                          A % Values(kk) = A % Values(kk) + STIFF(k,l)
                          EXIT
                       END IF
                    END DO
                 END DO
              END DO
           CASE(3)
              ! If no faces present do not try to set boundary conditions
              ! @todo This should be changed to EXIT
              IF ( .NOT. ASSOCIATED( Solver % Mesh % Faces ) ) CYCLE

              ! Parameters of element
              n = Element % Type % NumberOfNodes
              
              ! Get global boundary indexes and solve dofs associated to them
              CALL getBoundaryIndexes( Solver % Mesh, Element,  &
                          Parent, gInd, numEdgeDofs )
              ! If boundary face has no dofs skip to next boundary element
              IF (numEdgeDOFs == n) CYCLE

              ! Get local solution
              CALL LocalBcBDofs( BC, Element, numEdgeDofs, Name, STIFF, Work )

              ! Contribute this entry to global boundary problem
              DO k=n+1, numEdgeDOFs
                 nb = x % Perm( gInd(k) )
                 IF ( nb <= 0 ) CYCLE
                 nb = x % DOFs * (nb-1) + DOF
                 A % RHS(nb) = A % RHS(nb) + Work(k)
                 DO l=1, numEdgeDOFs
                    mb = x % Perm( gInd(l) )
                    IF ( mb <= 0 ) CYCLE
                    mb = x % DOFs * (mb-1) + DOF
                    DO kk=A % Rows(nb)+DOF-1,A % Rows(nb+1)-1,x % DOFs
                       IF ( A % Cols(kk) == mb ) THEN
                          A % Values(kk) = A % Values(kk) + STIFF(k,l)
                          EXIT
                       END IF
                    END DO
                 END DO
              END DO
           END SELECT
        END DO
        CurrentModel % CurrentElement => SaveElement
     END DO

     CALL Info('DefUtils::DefaultDirichletBCs','Dirichlet boundary conditions set')

!------------------------------------------------------------------------------
  END SUBROUTINE DefaultDirichletBCs
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
  SUBROUTINE LocalBcBDOFs(BC, Element, nd, Name, STIFF, Force )
!******************************************************************************
!
!  DESCRIPTION:
!     Given boundary condition, element and stiffness matrix and force 
!     vector, assemble boundary problem local stiffness matrix and 
!     force vector
!
!  ARGUMENTS:
!
!    Type(ValueList_t), POINTER :: BC
!      INOUT: Boundary condition value list
!
!    Type(Element_t) :: Element
!      INPUT: Boundary element to get stiffness matrix to
!
!    INTEGER :: nd
!      INPUT: number of degrees of freedom in boundary element
!
!    CHARACTER(LEN=MAX_NAME_LEN) :: Name
!      INPUT: name of boundary condition
!
!    REAL(Kind=dp) :: STIFF(:,:), Force
!      OUTPUT: Boundary problem stiffness matrix and force vector
!    
!******************************************************************************
!------------------------------------------------------------------------------
    IMPLICIT NONE
    TYPE(Element_t), POINTER :: Element
    INTEGER :: nd
    REAL(KIND=dp) :: Force(:), STIFF(:,:)
    TYPE(ValueList_t), POINTER :: BC
    CHARACTER(LEN=MAX_NAME_LEN) :: Name
!------------------------------------------------------------------------------
    TYPE(GaussIntegrationPoints_t) :: IP
    INTEGER :: i,j,p,q,t,n
    REAL(KIND=dp) :: xip,yip,zip,s,DetJ,Load
    REAL(KIND=dp) :: Basis(nd),dBasisdx(nd,3),ddBasisddx(nd,3,3)
    LOGICAL :: stat
    TYPE(Nodes_t) :: Nodes
    SAVE Nodes
!------------------------------------------------------------------------------

     n = Element % Type % NumberOfNodes    

     ! Get nodes of boundary elements parent and gauss points for boundary
     CALL GetElementNodes( Nodes, Element )
     IP = GaussPoints( Element )

     STIFF(1:nd,1:nd) = 0.0d0
     Force(1:nd) = 0.0d0

     DO t=1,IP % n
       stat = ElementInfo( Element, Nodes, IP % u(t), IP % v(t), IP % w(t), &
               DetJ, Basis, dBasisdx, ddBasisddx, .FALSE., .FALSE. )

       s = IP % s(t) * DetJ

       ! Get value of boundary condition
       xip = SUM( Basis(1:n) * Nodes % x(1:n) )
       yip = SUM( Basis(1:n) * Nodes % y(1:n) )
       zip = SUM( Basis(1:n) * Nodes % z(1:n) )
       Load = ListGetConstReal( BC, Name, x=xip,y=yip,z=zip )

       ! Build local stiffness matrix and force vector
       DO p=1,nd
          DO q=1,nd
             STIFF(p,q) = STIFF(p,q) + s * Basis(p)*Basis(q)
          END DO
          FORCE(p) = Force(p) + s * Load * Basis(p)
       END DO
    END DO
!------------------------------------------------------------------------------
  END SUBROUTINE LocalBcBDOFs
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
  SUBROUTINE LocalBcBDOFsOld( BC, Parent, Edge, nd, Name, localInd, numEdgeDofs, STIFF, Force )
!------------------------------------------------------------------------------
    IMPLICIT NONE
    TYPE(Element_t), POINTER :: Parent, Edge
    INTEGER :: nd, numEdgeDofs, localInd(:)
    REAL(KIND=dp) :: FORCE(:), STIFF(:,:)
    TYPE(ValueList_t), POINTER :: BC
    CHARACTER(LEN=MAX_NAME_LEN) :: Name
!------------------------------------------------------------------------------
    TYPE(GaussIntegrationPoints_t) :: IP
    INTEGER :: i,j,p,q,t, n, boundary
    REAL(KIND=dp) :: xip,yip,zip,s,DetJ,Load
    REAL(KIND=dp) :: Basis(nd),dBasisdx(nd,3),ddBasisddx(nd,3,3), &
         lBasis(numEdgeDofs)
    LOGICAL :: stat
    TYPE(Nodes_t) :: Nodes
    SAVE Nodes
!------------------------------------------------------------------------------

     n = Parent % Type % NumberOfNodes
     boundary = Edge % PDefs % localNumber
     
     ! Get nodes of boundary elements parent and gauss points for boundary
     CALL GetElementNodes( Nodes, Parent )
     IP = GaussPointsBoundary(Parent, boundary, Edge % PDefs % GaussPoints)

     STIFF(1:nd,1:nd) = 0.0d0
     FORCE(1:nd) = 0.0d0

     DO t=1,IP % n
       stat = ElementInfo( Parent, Nodes, IP % u(t), IP % v(t), IP % w(t), &
               DetJ, Basis, dBasisdx, ddBasisddx, .FALSE., .FALSE. )

       s = IP % s(t) * DetJ

       ! Get value of boundary condition
       xip = SUM( Basis(1:n) * Nodes % x(1:n) )
       yip = SUM( Basis(1:n) * Nodes % y(1:n) )
       zip = SUM( Basis(1:n) * Nodes % z(1:n) )
       Load = ListGetConstReal( BC, Name, x=xip,y=yip,z=zip )

       ! Build vector containing ONLY basis functions on boundary
       lBasis(1:numEdgeDofs) = Basis(localInd)

       DO p=1,numEdgeDofs
          DO q=1,numEdgeDofs
             STIFF(p,q) = STIFF(p,q) + s * lBasis(p)*lBasis(q)
          END DO
          FORCE(p) = Force(p) + s * Load * lBasis(p)
       END DO
    END DO

!------------------------------------------------------------------------------
  END SUBROUTINE LocalBcBDOFsOld
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE SolveBcBDOFs( BC, Element, n,nd, Name, Work )
!------------------------------------------------------------------------------
     TYPE(Element_t), POINTER :: Element, Parent
     INTEGER :: n, nd
     REAL(KIND=dp) :: Work(nd)
     TYPE(ValueList_t), POINTER :: BC
     CHARACTER(LEN=MAX_NAME_LEN) :: Name
!------------------------------------------------------------------------------
     INTEGER :: i
     REAL(KIND=dp) :: STIFF(nd,nd), F(nd)
!------------------------------------------------------------------------------
     ! CALL LocalBcBDOFs( BC, Element, Parent, n,nd, Name, STIFF, F )
     DO i=1,n
        STIFF(i,i) = 1.0d0
        F(i) = Work(i)
     END DO
     CALL BCCondensate( n, nd-n, STIFF, F, Work(n+1:nd) )
!------------------------------------------------------------------------------
  END SUBROUTINE SolveBcBDOFs
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE BCCondensate( n, nb, K, F, Work )
!------------------------------------------------------------------------------
    USE LinearAlgebra
!------------------------------------------------------------------------------
    INTEGER :: n,nb
    REAL(KIND=dp) :: K(:,:), F(:), Kbb(nb,nb), &
         Kbl(nb,n), Klb(n,nb), Fb(nb), Work(:)

    INTEGER :: i, Ldofs(n), Bdofs(nb)

    Ldofs = (/ (i, i=1,n) /)
    Bdofs = (/ (i, i=n+1,n+nb) /)

    Kbb = K(Bdofs,Bdofs)
    Kbl = K(Bdofs,Ldofs)
    Klb = K(Ldofs,Bdofs)

    Work(1:nb) = F(Bdofs) - MATMUL( Kbl, F(1:n) )
    CALL LUSolve( nb, Kbb, Work )
!------------------------------------------------------------------------------
  END SUBROUTINE BCCondensate
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE DefaultFinishAssembly( Solver )
!------------------------------------------------------------------------------
DLLEXPORT DefaultFinishAssembly
    TYPE(Solver_t), OPTIONAL :: Solver

    IF ( PRESENT( Solver ) ) THEN
       CALL FinishAssembly( Solver, Solver % Matrix % RHS )
    ELSE
       CALL FinishAssembly( CurrentModel % Solver, CurrentModel % Solver % Matrix % RHS )
    END IF
!------------------------------------------------------------------------------
  END SUBROUTINE DefaultFinishAssembly
!------------------------------------------------------------------------------

  ! Return integration points for edge or face of p element
  
   FUNCTION GaussPointsBoundary(Element, boundary, np) RESULT(gaussP)
     Use PElementMaps, ONLY : getElementBoundaryMap 
     USE Integration
     IMPLICIT NONE

     ! Parameters
     Type(Element_t) :: Element
     INTEGER, INTENT(IN) :: boundary, np

     TYPE( GaussIntegrationPoints_t ) :: gaussP
     Type(Nodes_t) :: Nodes, bNodes 
     Type(Element_t) :: mapElement
     Type(Element_t), POINTER :: RefElement
     INTEGER :: i, n, eCode, bMap(4)
     REAL(KIND=dp) :: x(3), y(3), z(3)

     SELECT CASE(Element % Type % ElementCode / 100)
     ! Triangle and Quadrilateral
     CASE (3,4)
        n = 2
        eCode = 202
     ! Tetrahedron
     CASE (5)
        n = 3
        eCode = 303
     ! Pyramid
     CASE (6)
        ! Select edge element by boundary
        IF (boundary == 1) THEN
           n = 4
           eCode = 404
        ELSE
           n = 3
           eCode = 303
        END IF
     ! Wedge
     CASE (7)
        ! Select edge element by boundary
        SELECT CASE (boundary)
        CASE (1,2)
           n = 3
           eCode = 303
        CASE (3,4,5)
           n = 4
           eCode = 404
        END SELECT
     ! Brick
     CASE (8)
        n = 4
        eCode = 404
     CASE DEFAULT
        WRITE (*,*) 'DefUtils::GaussPointsBoundary: Unsupported element type'
     END SELECT

     ! Get element boundary map
     bMap(1:4) = getElementBoundaryMap(Element, boundary)
     ! Get ref nodes for element
     CALL GetRefPElementNodes( Nodes, Element )
     ALLOCATE(bNodes % x(n), bNodes % y(n), bNodes % z(n))
        
     ! Set coordinate points of destination
     DO i=1,n
        IF (bMap(i) == 0) CYCLE  
        bNodes % x(i) = Nodes % x(bMap(i)) 
        bNodes % y(i) = Nodes % y(bMap(i))
        bNodes % z(i) = Nodes % z(bMap(i))   
     END DO

     ! Get element to map from
     mapElement % Type => GetElementType(eCode)
     CALL AllocateVector(mapElement % NodeIndexes, mapElement % Type % NumberOfNodes)

     ! Get gauss points and map them to given element
     gaussP = GaussPoints( mapElement, np )
     
     CALL MapGaussPoints( mapElement, mapElement % Type % NumberOfNodes, gaussP, bNodes )
     
     ! Deallocate memory
     DEALLOCATE(bNodes % x, bNodes % y, bNodes % z, mapElement % NodeIndexes)
   END FUNCTION GaussPointsBoundary

   SUBROUTINE MapGaussPoints( Element, n, gaussP, Nodes )
     IMPLICIT NONE

     Type(Element_t) :: Element
     Type(GaussIntegrationPoints_t) :: gaussP
     Type(Nodes_t) :: Nodes
     INTEGER :: n

     INTEGER :: i
     REAL(KIND=dp) :: xh,yh,zh,sh, DetJ
     REAL(KIND=dp) :: Basis(n),dBasisdx(n,3),ddBasisddx(n,3,3)
     LOGICAL :: stat
     
     ! Map each gauss point from reference element to given nodes
     DO i=1,gaussP % n
        stat = ElementInfo( Element, Nodes, gaussP % u(i), gaussP % v(i), gaussP % w(i), &
             DetJ, Basis, dBasisdx, ddBasisddx, .FALSE., .FALSE. )

        IF (.NOT. stat) THEN
           WRITE (*,*) 'DefUtils::MapGaussPoints: Element to map degenerate'
           STOP
        END IF

        ! Get mapped points
        sh = gaussP % s(i) * DetJ
        xh = SUM( Basis(1:n) * Nodes % x(1:n) )
        yh = SUM( Basis(1:n) * Nodes % y(1:n) )
        zh = SUM( Basis(1:n) * Nodes % z(1:n) )
        ! Set mapped points
        gaussP % u(i) = xh
        gaussP % v(i) = yh
        gaussP % w(i) = zh
        gaussP % s(i) = sh
     END DO
   END SUBROUTINE MapGaussPoints


!------------------------------------------------------------------------------
   SUBROUTINE getBoundaryIndexes( Mesh, Element, Parent, Indexes, indSize )
!******************************************************************************
!
!  DESCRIPTION:
!     Calculate global indexes of boundary dofs for given element and 
!     its boundary. 
!
!  ARGUMENTS:
!
!    Type(Mesh_t) :: Mesh
!      INPUT: Finite element mesh containing edges and faces of elements
!
!    Type(Element_t) :: Element
!      INPUT: Boundary element to get indexes for
!
!    Type(Element_t) :: Parent
!      INPUT: Parent of boundary element to get indexes for
!
!    INTEGER :: Indexes(:)
!      OUTPUT: Calculated indexes of boundary element in global system
! 
!    INTEGER :: indSize
!      OUTPUT: Size of created index vector, i.e. how many indexes were created
!        starting from index 1
!    
!******************************************************************************
!------------------------------------------------------------------------------
     IMPLICIT NONE

     ! Parameters
     Type(Mesh_t) :: Mesh
     Type(Element_t) :: Parent
     Type(Element_t), POINTER :: Element
     INTEGER :: indSize, Indexes(:)
     
     ! Variables
     Type(Element_t), POINTER :: Edge, Face
     INTEGER :: i,j,n

     ! Clear indexes
     Indexes = 0
     n = Element % Type % NumberOfNodes

     ! Nodal indexes
     Indexes(1:n) = Element % NodeIndexes(1:n)

     ! Assign rest of indexes if neccessary
     SELECT CASE(Parent % Type % Dimension)
     CASE (2)
        ! Add index for each bubble dof in edge
        DO i=1,Element % BDOFs
           n = n+1
           
           IF (SIZE(Indexes) < n) THEN
              CALL Warn('DefUtils::getBoundaryIndexes','Not enough space reserved for indexes')
              RETURN
           END IF

           Indexes(n) = Mesh % NumberOfNodes + &
                (Parent % EdgeIndexes(Element % PDefs % localNumber)-1) * Mesh % MaxEdgeDOFs + i
        END DO
     
        indSize = n 
     CASE (3)
        ! Get boundary face
        Face => Mesh % Faces( Parent % FaceIndexes(Element % PDefs % localNumber) )
        
        ! Add indexes of faces edges 
        DO i=1, Face % Type % NumberOfEdges
           Edge => Mesh % Edges( Face % EdgeIndexes(i) )
           
           ! If edge has no dofs jump to next edge
           IF (Edge % BDOFs <= 0) CYCLE

           DO j=1,Edge % BDOFs
              n = n + 1
              
              IF (SIZE(Indexes) < n) THEN
                 CALL Warn('DefUtils::getBoundaryIndexes','Not enough space reserved for indexes')
                 RETURN
              END IF
              
              Indexes(n) = Mesh % NumberOfNodes +&
                  ( Face % EdgeIndexes(i)-1)*Mesh % MaxEdgeDOFs + j
           END DO
        END DO
               
        ! Add indexes of faces bubbles
        DO i=1,Face % BDOFs
           n = n + 1

           IF (SIZE(Indexes) < n) THEN
              CALL Warn('DefUtils::getBoundaryIndexes','Not enough space reserved for indexes')
              RETURN
           END IF

           Indexes(n) = Mesh % NumberOfNodes + &
                Mesh % NumberOfEdges * Mesh % MaxEdgeDOFs + &
                (Parent % FaceIndexes( Element % PDefs % localNumber )-1) * Mesh % MaxFaceDOFs + i
        END DO        

        indSize = n
     CASE DEFAULT
        CALL Fatal('DefUtils::getBoundaryIndexes','Unsupported dimension')
     END SELECT
   END SUBROUTINE getBoundaryIndexes


!------------------------------------------------------------------------------
   SUBROUTINE getBoundaryIndexesGL( Mesh, Element, BElement, lIndexes, gIndexes, indSize )
!******************************************************************************
!
!  DESCRIPTION:
!     Calculate global AND local indexes of boundary dofs for given element and 
!     its boundary. 
!
!  ARGUMENTS:
!
!    Type(Mesh_t) :: Mesh
!      INPUT: Finite element mesh containing edges and faces of elements
!
!    Type(Element_t) :: Element
!      INPUT: Parent of boundary element to get indexes for
!
!    Type(Element_t) :: BElement
!      INPUT: Boundary element to get indexes for
!
!    INTEGER :: lIndexes(:), gIndexes(:)
!      OUTPUT: Calculated indexes of boundary element in local and 
!        global system
! 
!    INTEGER :: indSize
!      OUTPUT: Size of created index vector, i.e. how many indexes were created
!        starting from index 1
!    
!******************************************************************************
!------------------------------------------------------------------------------
     IMPLICIT NONE

     ! Parameters
     Type(Mesh_t) :: Mesh
     Type(Element_t) :: Element
     Type(Element_t), POINTER :: BElement
     INTEGER :: indSize, lIndexes(:), gIndexes(:)
     ! Variables
     Type(Element_t), POINTER :: Edge, Face
     INTEGER :: i,j,k,n,edgeDofSum, faceOffSet, edgeOffSet(12), localBoundary, nNodes, bMap(4), &
          faceEdgeMap(4)
     LOGICAL :: stat

     ! Clear indexes
     lIndexes = 0
     gIndexes = 0
     
     ! Get boundary map and number of nodes on boundary
     localBoundary = BElement % PDefs % localNumber
     nNodes = BElement % Type % NumberOfNodes
     bMap(1:4) = getElementBoundaryMap(Element, localBoundary)
     n = nNodes + 1

     ! Assign local and global node indexes
     lIndexes(1:nNodes) = bMap(1:nNodes)
     gIndexes(1:nNodes) = Element % NodeIndexes(lIndexes(1:nNodes))

     ! Assign rest of indexes
     SELECT CASE(Element % Type % Dimension)
     CASE (2)
        edgeDofSum = Element % Type % NumberOfNodes

        IF (SIZE(Indexes) < nNodes + Mesh % MaxEdgeDOFs) THEN
           WRITE (*,*) 'DefUtils::getBoundaryIndexes: Not enough space reserved for edge indexes'
           RETURN
        END IF

        DO i=1,Element % Type % NumberOfEdges
           Edge => Mesh % Edges( Element % EdgeIndexes(i) )
           
           ! For boundary edge add local and global indexes
           IF (localBoundary == i) THEN
              DO j=1,Edge % BDOFs
                 lIndexes(n) = edgeDofSum + j
                 gIndexes(n) = Mesh % NumberOfNodes + &
                      (Element % EdgeIndexes(localBoundary)-1) * Mesh % MaxEdgeDOFs + j
                 n = n+1
              END DO
              EXIT
           END IF
           
           edgeDofSum = edgeDofSum + Edge % BDOFs 
        END DO
        
        indSize = n - 1
     CASE (3)
        IF (SIZE(Indexes) < nNodes + (Mesh % MaxEdgeDOFs * BElement % Type % NumberOfEdges) +&
             Mesh % MaxFaceDofs) THEN
           WRITE (*,*) 'DefUtils::getBoundaryIndexes: Not enough space reserved for edge indexes'
           RETURN
        END IF

        ! Get offsets for each edge
        edgeOffSet = 0
        faceOffSet = 0
        edgeDofSum = 0
        DO i=1,Element % Type % NumberOfEdges
           Edge => Mesh % Edges( Element % EdgeIndexes(i) )
           edgeOffSet(i) = edgeDofSum
           edgeDofSum = edgeDofSum + Edge % BDOFs
        END DO

        ! Get offset for faces
        faceOffSet = edgeDofSum

        ! Add element edges to local indexes
        faceEdgeMap(1:4) = getFaceEdgeMap(Element, localBoundary)
        Face => Mesh % Faces( Element % FaceIndexes(localBoundary) )
        DO i=1,Face % Type % NumberOfEdges
           Edge => Mesh % Edges( Face % EdgeIndexes(i) )
           
           IF (Edge % BDOFs <= 0) CYCLE

           DO j=1,Edge % BDOFs
              lIndexes(n) = Element % Type % NumberOfNodes + edgeOffSet(faceEdgeMap(i)) + j
              gIndexes(n) = Mesh % NumberOfNodes +&
                  ( Face % EdgeIndexes(i)-1)*Mesh % MaxEdgeDOFs + j
              n=n+1
           END DO
        END DO

        DO i=1,Element % Type % NumberOfFaces
           Face => Mesh % Faces( Element % FaceIndexes(i) )
           
           IF (Face % BDOFs <= 0) CYCLE

           ! For boundary face add local and global indexes
           IF (localBoundary == i) THEN
              DO j=1,Face % BDOFs 
                 lIndexes(n) = Element % Type % NumberOfNodes + faceOffSet + j
                 gIndexes(n) = Mesh % NumberOfNodes + &
                      Mesh % NumberOfEdges * Mesh % MaxEdgeDOFs + &
                      (Element % FaceIndexes(localBoundary)-1) * Mesh % MaxFaceDOFs + j
                 n=n+1
              END DO
              EXIT
           END IF

           faceOffSet = faceOffSet + Face % BDOFs
        END DO
        
        indSize = n - 1
     END SELECT
   END SUBROUTINE getBoundaryIndexesGL

END MODULE DefUtils
