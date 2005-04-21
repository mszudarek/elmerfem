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
! * A solver for the Fourier transformed time-dependent diffusion equation
! * with a constant frequency forcing term,
! * (nabla^2 - iw) B(x) = -f(x,w)
! *
! * Here we are solving specifically the magnetic problem
! * (nabla^2/(mu*sigma) - iw) B(x) = iw B_ac(x)
! * 
! * This version solves for a scalar field, i.e., the AC field is
! * B_ac(x,y,z,t) = B_ac(x,y,z) exp(iwt) e_z
! *
! * If requested, the time-averaged Lorentz force due to induced field B,
! * < 1/mu (curl B) x B >, is calculated and written in the result files.
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
! *                       Date: 04 Oct 2000
! *
! *                Modified by: Ville Savolainen
! *
! *       Date of modification: 15 June 2001
! *
! ****************************************************************************/

!------------------------------------------------------------------------------
SUBROUTINE FourierDiffusionSolver( Model,Solver,dt,TransientSimulation )
  !DEC$ATTRIBUTES DLLEXPORT :: FourierDiffusionSolver
!------------------------------------------------------------------------------
!******************************************************************************
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

  USE Integration
  USE ElementDescription

  USE SolverUtils

  IMPLICIT NONE
!------------------------------------------------------------------------------
  TYPE(Solver_t), TARGET :: Solver
  TYPE(Model_t) :: Model

  REAL(KIND=dp) :: dt
  LOGICAL :: TransientSimulation
!------------------------------------------------------------------------------
! Local variables
!------------------------------------------------------------------------------
  TYPE(Matrix_t),POINTER  :: StiffMatrix
  TYPE(Nodes_t) :: ElementNodes
  TYPE(Element_t),POINTER :: CurrentElement

  INTEGER, POINTER :: NodeIndexes(:)

  LOGICAL :: AllocationsDone = .FALSE., Bubbles, GotIt

  INTEGER, POINTER :: SomeQuantityPerm(:)
  REAL(KIND=dp), POINTER :: SomeQuantity(:), ForceVector(:), &
       LrF(:), LrFr(:), LrFz(:), LrFp(:), BRe(:), BIm(:)

  INTEGER :: iter, i, j, k, n, t, istat, eq, LocalNodes
  REAL(KIND=dp) :: Norm, PrevNorm, RelativeChange, AngularFrequency

  TYPE(ValueList_t), POINTER :: Material

  INTEGER :: NonlinearIter
  REAL(KIND=dp) :: NonlinearTol,s

  REAL(KIND=dp), ALLOCATABLE :: LocalStiffMatrix(:,:), Load(:,:), Work(:), &
       LocalForce(:), Impedance(:,:), Conductivity(:), Permeability(:)

  CHARACTER(LEN=MAX_NAME_LEN) :: EquationName

  SAVE LocalStiffMatrix, Work, Load, LocalForce, ElementNodes, &
       Impedance, AllocationsDone, Conductivity, Permeability, &
       LrF, LocalNodes

  REAL(KIND=dp) :: at,at0,totat,st,totst,t1,CPUTime,RealTime

  TYPE(Solver_t), POINTER :: SolverPointer

!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
! Get variables needed for solution
!------------------------------------------------------------------------------
  IF ( .NOT.ASSOCIATED( Solver % Matrix ) ) RETURN

  Solver % Matrix % Complex = .TRUE.

  SomeQuantity     => Solver % Variable % Values
  SomeQuantityPerm => Solver % Variable % Perm

  LocalNodes = COUNT( SomeQuantityPerm > 0 )
  IF ( LocalNodes <= 0 ) RETURN

  StiffMatrix => Solver % Matrix
  ForceVector => StiffMatrix % RHS

  Norm = Solver % Variable % Norm
!------------------------------------------------------------------------------
! Allocate some permanent storage, this is done first time only
!------------------------------------------------------------------------------
  IF ( .NOT. AllocationsDone .OR. Solver % Mesh % Changed ) THEN
     N = Solver % Mesh % MaxElementNodes

     IF ( AllocationsDone ) THEN
        DEALLOCATE( ElementNodes % x, &
             ElementNodes % y,      &
             ElementNodes % z,      &
             LocalForce,            &
             Impedance,             &
             Work,                  &
             LocalStiffMatrix,      &
             Conductivity, Permeability, &
             Load )
     END IF

     ALLOCATE( ElementNodes % x( N ),  &
          ElementNodes % y( N ),       &
          ElementNodes % z( N ),       &
          LocalForce( 2*N ),           &
          Impedance( 2,N ),            &
          Work( N ),                   &
          LocalStiffMatrix( 2*N,2*N ), &
          Conductivity( N ),  &
          Permeability( N ),  &
          LrF(3 * Model % NumberOfNodes), & 
          Load( 2,N ), STAT=istat )

     IF ( istat /= 0 ) THEN
        CALL Fatal( 'FourierDiffusionSolve', 'Memory allocation error.' )
     END IF

! Add Lorentz force (all components) to *.result and *.ep files
!#if 1
     IF (.NOT. ASSOCIATED(VariableGet(Model % Variables, 'Lorentz Force'))) THEN
        SolverPointer => Solver

        LrFr => LrF(1:3*LocalNodes-2:3)
        CALL VariableAdd(Solver % Mesh % Variables, Solver % Mesh, &
             SolverPointer, 'Lorentz Force 1', 1, LrFr, SomeQuantityPerm)

        LrFz => LrF(2:3*LocalNodes-1:3)
        CALL VariableAdd(Solver % Mesh % Variables, Solver % Mesh, &
             SolverPointer, 'Lorentz Force 2', 1, LrFz, SomeQuantityPerm)

        LrFp => LrF(3:3*LocalNodes:3)
        CALL VariableAdd(Solver % Mesh % Variables, Solver % Mesh, &
             SolverPointer, 'Lorentz Force 3', 1, LrFp, SomeQuantityPerm)

        CALL VariableAdd(Solver % Mesh % Variables, Solver % Mesh, &
              SolverPointer, 'Lorentz Force', 3, LrF, SomeQuantityPerm)
      END IF
!#endif

     AllocationsDone = .TRUE.
  END IF
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
! Do some additional initialization, and go for it
!------------------------------------------------------------------------------
  NonlinearTol = ListGetConstReal( Solver % Values, &
       'Nonlinear System Convergence Tolerance',GotIt )

  NonlinearIter = ListGetInteger( Solver % Values, &
       'Nonlinear System Max Iterations', GotIt )

  IF ( .NOT.GotIt ) NonlinearIter = 1

  EquationName = ListGetString( Solver % Values, 'Equation' )
  Bubbles = ListGetLogical( Solver % Values, 'Bubbles', GotIt )
  IF ( .NOT.(GotIt) ) Bubbles = .FALSE.

!------------------------------
! Figure out angular frequency:
!------------------------------
  AngularFrequency = 0.0d0

  NodeIndexes => Solver % Mesh % Elements(1) % NodeIndexes

  Work(1:1) = ListGetReal( Model % Simulation, &
     'Angular Frequency', 1, NodeIndexes, GotIt )

  IF ( GotIt ) THEN
     AngularFrequency = Work(1)
  ELSE
     Work(1:1) = ListGetReal( Model % Simulation, &
            'Frequency', 1, NodeIndexes )

     AngularFrequency = 2*PI*Work(1)
  END IF


!------------------------------------------------------------------------------
! Iterate over any nonlinearity of material or source
!------------------------------------------------------------------------------
  totat = 0.0d0
  totst = 0.0d0

  DO iter=1,NonlinearIter
!------------------------------------------------------------------------------
      at  = CPUTime()
      at0 = RealTime()

      CALL Info( 'FourierDiffusionSolve', ' ', Level=4 )
      CALL Info( 'FourierDiffusionSolve', ' ', Level=4 )
      CALL Info( 'FourierDiffusionSolve', &
           '-------------------------------------', Level=4 )
      WRITE( Message, * ) 'Fourier Diffusuion  iteration', iter
      CALL Info( 'FourierDiffusionSolve', Message, Level=4 )
      WRITE( Message, * ) 'Frequency (Hz): ', AngularFrequency/(2*PI)
      CALL Info( 'FourierDiffusionSolve', Message, Level=4 )
      CALL Info( 'FourierDiffusionSolve', &
           '-------------------------------------', Level=4 )
      CALL Info( 'FourierDiffusionSolve', ' ', Level=4 )
      CALL Info( 'FourierDiffusionSolve', 'Starting Assembly...', Level=4 )

     CALL InitializeToZero( StiffMatrix, ForceVector )
!
!    Do the bulk assembly:
!    ---------------------

!------------------------------------------------------------------------------
     DO t=1,Solver % Mesh % NumberOfBulkElements
!------------------------------------------------------------------------------
        IF ( RealTime() - at0 > 1.0 ) THEN
          WRITE(Message,'(a,i3,a)' ) '   Assembly: ', INT(100.0 - 100.0 * &
           (Solver % Mesh % NumberOfBulkElements-t) / &
              (1.0*Solver % Mesh % NumberOfBulkElements)), ' % done'
                      
          CALL Info( 'FourierDiffusionSolve', Message, Level=5 )
          at0 = RealTime()
        END IF
!------------------------------------------------------------------------------
!       Check if this element belongs to a body where this equation
!       should be computed
!------------------------------------------------------------------------------
        CurrentElement => Solver % Mesh % Elements(t)

        IF ( .NOT. CheckElementEquation( Model, &
             CurrentElement, EquationName ) ) CYCLE
!------------------------------------------------------------------------------
        Model % CurrentElement => CurrentElement

        n = CurrentElement % Type % NumberOfNodes
        NodeIndexes => CurrentElement % NodeIndexes

        ElementNodes % x(1:n) = Solver % Mesh % Nodes % x(NodeIndexes)
        ElementNodes % y(1:n) = Solver % Mesh % Nodes % y(NodeIndexes)
        ElementNodes % z(1:n) = Solver % Mesh % Nodes % z(NodeIndexes)
!------------------------------------------------------------------------------
!       Get equation & material parameters
!------------------------------------------------------------------------------
        k = ListGetInteger( Model % Bodies( CurrentElement % &
                Bodyid ) % Values, 'Equation', minv=1,maxv=Model % NumberOfEquations )

        Work(1:n) = ListGetReal(  Model % Equations(k) % Values, &
             'Angular Frequency', n, NodeIndexes, GotIt )

        IF ( GotIt ) THEN
           AngularFrequency = Work(1)
        ELSE
           Work(1:n) = ListGetReal(  Model % Equations(k) % Values, &
                 'Frequency', n, NodeIndexes, GotIt )
           IF ( GotIt ) AngularFrequency = 2*PI*Work(1)
        END IF

        k = ListGetInteger( Model % Bodies( CurrentElement % &
                Bodyid ) % Values, 'Material',minv=1,maxv=Model % NumberOfMaterials )

        Material => Model % Materials(k) % Values

        Conductivity(1:n) = ListGetReal(Material, &
             'Electrical Conductivity',n,NodeIndexes)

        Permeability(1:n) = ListGetReal(Material, &
             'Magnetic Permeability',n,NodeIndexes)

!------------------------------------------------------------------------------
!       The source term on nodes
!------------------------------------------------------------------------------
        k = ListGetInteger( Model % Bodies( CurrentElement % BodyId ) % &
             Values, 'Body Force', GotIt,1, Model % NumberOFBodyForces )

        Load = 0.0d0
        IF ( k > 0 ) THEN
           Load(1,1:n) = ListGetReal( Model % BodyForces(k) % Values, &
                'AC Magnetic Field Re', n, NodeIndexes, GotIt )

           Load(2,1:n) = ListGetReal( Model % BodyForces(k) % Values, &
                'AC Magnetic Field Im', n, NodeIndexes, GotIt )
        END IF

!------------------------------------------------------------------------------
!       Get element local matrix and rhs vector
!------------------------------------------------------------------------------
        CALL LocalMatrix(  LocalStiffMatrix, LocalForce, AngularFrequency, &
             Conductivity*Permeability, Load, Bubbles, CurrentElement, n, &
             ElementNodes )

!------------------------------------------------------------------------------
!       Update global matrix and rhs vector from local matrix & vector
!------------------------------------------------------------------------------
        CALL UpdateGlobalEquations( StiffMatrix, LocalStiffMatrix, &
             ForceVector, LocalForce, n, Solver % Variable % DOFs, &
                  SomeQuantityPerm(NodeIndexes) )
!------------------------------------------------------------------------------
     END DO
!------------------------------------------------------------------------------

!
!    Neumann & Newton BCs:
!    ---------------------

!------------------------------------------------------------------------------
     DO t = Solver % Mesh % NumberOfBulkElements + 1,  &
               Solver % Mesh % NumberOfBulkElements +  &
                  Solver % Mesh % NumberOfBoundaryElements
!------------------------------------------------------------------------------
        CurrentElement => Solver % Mesh % Elements(t)
        Model % CurrentElement => CurrentElement

!------------------------------------------------------------------------------
!       The element type 101 (point element) can only be used
!       to set Dirichlet BCs, so skip em at this stage.
!------------------------------------------------------------------------------
        IF ( CurrentElement % Type % ElementCode == 101 ) CYCLE

!------------------------------------------------------------------------------
        DO i=1,Model % NumberOfBCs
           IF ( CurrentElement % BoundaryInfo % Constraint == &
                Model % BCs(i) % Tag ) THEN
!------------------------------------------------------------------------------
              n = CurrentElement % Type % NumberOfNodes
              NodeIndexes => CurrentElement % NodeIndexes

              IF ( ANY( SomeQuantityPerm(NodeIndexes) == 0 ) ) CYCLE

              ElementNodes % x(1:n) = Solver % Mesh % Nodes % x(NodeIndexes)
              ElementNodes % y(1:n) = Solver % Mesh % Nodes % y(NodeIndexes)
              ElementNodes % z(1:n) = Solver % Mesh % Nodes % z(NodeIndexes)

              Impedance(1,1:n) = ListGetReal( Model % BCs(i) % Values, &
                   'Wave Impedance 1', n, NodeIndexes, GotIt )

              Impedance(2,1:n) = ListGetReal( Model % BCs(i) % Values, &
                   'Wave Impedance 2', n, NodeIndexes, GotIt )

              Load(1,1:n) = ListGetReal( Model % BCs(i) % Values, &
                   'Wave Flux 1', n, NodeIndexes, GotIt )

              Load(2,1:n) = ListGetReal( Model % BCs(i) % Values, &
                   'Wave Flux 2', n, NodeIndexes, GotIt )
!------------------------------------------------------------------------------
!             Get element local matrix and rhs vector
!------------------------------------------------------------------------------
              CALL LocalMatrixBoundary(  LocalStiffMatrix, LocalForce, &
                  AngularFrequency, Impedance, Load, CurrentElement, &
                      n, ElementNodes )

!------------------------------------------------------------------------------
!             Update global matrix and rhs vector from local matrix & vector
!------------------------------------------------------------------------------
              CALL UpdateGlobalEquations( StiffMatrix, LocalStiffMatrix, &
                  ForceVector, LocalForce, n, Solver % Variable % DOFs,  &
                      SomeQuantityPerm(NodeIndexes) )
!------------------------------------------------------------------------------
           END IF
        END DO
!------------------------------------------------------------------------------
     END DO
!------------------------------------------------------------------------------

     CALL FinishAssembly( Solver, ForceVector )
!
!    Dirichlet BCs:
!    --------------
     CALL SetDirichletBoundaries( Model, StiffMatrix, ForceVector, &
          TRIM(Solver % Variable % Name) // ' 1', 1, &
             Solver % Variable % DOFs, SomeQuantityPerm )

     CALL SetDirichletBoundaries( Model, StiffMatrix, ForceVector, &
          TRIM(Solver % Variable % Name) // ' 2', 2, &
             Solver % Variable % DOFs, SomeQuantityPerm )

     CALL Info( 'FourierDiffusionSolve', 'Assembly done', Level=4 )

!
!    Solve the system and we are done:
!    ---------------------------------

     PrevNorm = Norm
     at = CPUTime() - at
     st = CPUTime()

     CALL SolveSystem( StiffMatrix, ParMatrix, ForceVector, &
          SomeQuantity, Norm, Solver % Variable % DOFs, Solver )

     st = CPUTIme()-st
     totat = totat + at
     totst = totst + st
     WRITE(Message,'(a,i4,a,F8.2,F8.2)') 'iter: ',iter,' Assembly: (s)', at, totat
     CALL Info( 'FourierDiffusionSolve', Message, Level=4 )
     WRITE(Message,'(a,i4,a,F8.2,F8.2)') 'iter: ',iter,' Solve:    (s)', st, totst
     CALL Info( 'FourierDiffusionSolve', Message, Level=4 )

!------------------------------------------------------------------------------

     IF ( PrevNorm + Norm /= 0.0d0 ) THEN
        RelativeChange = 2*ABS(PrevNorm - Norm) / (PrevNorm + Norm)
     ELSE
        RelativeChange = 0.0d0
     END IF

     WRITE( Message, * ) 'Result Norm    : ',Norm
     CALL Info( 'FourierDiffusionSolve', Message, Level=4 )
     WRITE( Message, * ) 'Relative Change: ',RelativeChange
     CALL Info( 'FourierDiffusionSolve', Message, Level=4 )

     IF ( RelativeChange < NonlinearTol ) EXIT
!------------------------------------------------------------------------------
  END DO ! of nonlinear iteration
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
!   Compute the time-averaged Lorentz force
!------------------------------------------------------------------------------

!#if 1
    LrFr => LrF(1:3*LocalNodes-2:3)
    LrFz => LrF(2:3*LocalNodes-1:3)
    LrFp => LrF(3:3*LocalNodes:3)

    BRe => SomeQuantity(1:2*LocalNodes-1:2)
    BIm => SomeQuantity(2:2*LocalNodes:2)

    CALL LorentzForceAve(LrFr,LrFz,LrFp,BRe,BIm,SomeQuantityPerm)
!#endif


CONTAINS


!------------------------------------------------------------------------------
  SUBROUTINE LocalMatrix(  StiffMatrix, Force, AngularFrequency, &
       NodalConductivity, Load, Bubbles, Element, n, Nodes )
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: StiffMatrix(:,:), Force(:), AngularFrequency, &
         NodalConductivity(:), Load(:,:)
    LOGICAL :: Bubbles
    INTEGER :: n
    TYPE(Nodes_t) :: Nodes
    TYPE(Element_t), POINTER :: Element
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: Basis(2*n),dBasisdx(2*n,3),ddBasisddx(n,3,3)
    REAL(KIND=dp) :: SqrtElementMetric,U,V,W,S,Conductivity,M,D,L1,L2
    COMPLEX(KIND=dp) :: LSTIFF(2*n,2*n), LFORCE(2*n), A
    LOGICAL :: Stat
    INTEGER :: i,p,q,t,dim, NBasis, CoordSys
    TYPE(GaussIntegrationPoints_t) :: IntegStuff

    REAL(KIND=dp) :: X,Y,Z,Metric(3,3),SqrtMetric,Symb(3,3,3),dSymb(3,3,3,3)
!------------------------------------------------------------------------------
    dim = CoordinateSystemDimension()
    CoordSys = CurrentCoordinateSystem()

    Metric = 0.0d0
    Metric(1,1) = 1.0d0
    Metric(2,2) = 1.0d0
    Metric(3,3) = 1.0d0

    LSTIFF = 0.0d0
    LFORCE = 0.0d0
!------------------------------------------------------------------------------
!   Numerical integration
!------------------------------------------------------------------------------
    IF ( Bubbles ) THEN
       IntegStuff = GaussPoints( Element, Element % Type % GaussPoints2 )
       NBasis = 2*n
    ELSE
       NBasis = n
       IntegStuff = GaussPoints( Element )
    END IF
!------------------------------------------------------------------------------
    DO t=1,IntegStuff % n
       U = IntegStuff % u(t)
       V = IntegStuff % v(t)
       W = IntegStuff % w(t)
       S = IntegStuff % s(t)
!------------------------------------------------------------------------------
!      Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
       stat = ElementInfo( Element, Nodes, U, V, W, SqrtElementMetric, &
            Basis, dBasisdx, ddBasisddx, .FALSE., Bubbles )

       s = s * SqrtElementMetric
       IF ( CoordSys /= Cartesian ) THEN
          X = SUM( Nodes % X(1:n) * Basis(1:n) )
          Y = SUM( Nodes % Y(1:n) * Basis(1:n) )
          Z = SUM( Nodes % Z(1:n) * Basis(1:n) )
          CALL CoordinateSystemInfo( Metric,SqrtMetric,Symb,dSymb,X,Y,Z )
          s = s * SqrtMetric
       END IF
!------------------------------------------------------------------------------
!      The source term and the coefficient of the time derivative and 
!      diffusion terms at the integration point

!------------------------------------------------------------------------------
!      Effective conductivity (times the magnetic permeability)
!------------------------------------------------------------------------------
       Conductivity = SUM( NodalConductivity(1:n)*Basis )

       D = -AngularFrequency
       M = 0._dp

       L1 = AngularFrequency * SUM( Load(1,1:n) * Basis(1:n) )
       L2 = AngularFrequency * SUM( Load(2,1:n) * Basis(1:n) )
!------------------------------------------------------------------------------
!      The Helmholz equation
!------------------------------------------------------------------------------
       DO p=1,NBasis
          DO q=1,NBasis
             A = DCMPLX( M, D ) * Basis(q) * Basis(p)

             DO i=1,dim
                DO j=1,dim
                   A = A + Metric(i,j) * dBasisdx(q,i) * dBasisdx(p,j) &
                        / Conductivity
                END DO
             END DO

             LSTIFF(p,q) = LSTIFF(p,q) + s*A
          END DO
          LFORCE(p) = LFORCE(p) + s * Basis(p) * DCMPLX( L1,L2 )
       END DO
    END DO
!------------------------------------------------------------------------------

    IF ( Bubbles ) THEN
       CALL LCondensate( n,LSTIFF,LFORCE )
    END IF

    DO i=1,n
       Force( 2*(i-1)+1 ) = REAL( LFORCE(i) )
       Force( 2*(i-1)+2 ) = AIMAG( LFORCE(i) )

       DO j=1,n
         StiffMatrix( 2*(i-1)+1, 2*(j-1)+1 ) =  REAL( LSTIFF(i,j) )
         StiffMatrix( 2*(i-1)+1, 2*(j-1)+2 ) = -AIMAG( LSTIFF(i,j) )
         StiffMatrix( 2*(i-1)+2, 2*(j-1)+1 ) =  AIMAG( LSTIFF(i,j) )
         StiffMatrix( 2*(i-1)+2, 2*(j-1)+2 ) =  REAL( LSTIFF(i,j) )
       END DO
    END DO
!------------------------------------------------------------------------------
  END SUBROUTINE LocalMatrix
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE LocalMatrixBoundary(  StiffMatrix, Force, AngularFrequency, &
              Impedance, Load, Element, n, Nodes )
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: StiffMatrix(:,:),Force(:),Impedance(:,:),Load(:,:)
    REAL(KIND=dp) :: AngularFrequency
    INTEGER :: n
    TYPE(Nodes_t) :: Nodes
    TYPE(Element_t), POINTER :: Element
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: SqrtElementMetric,U,V,W,S,Impedance1,Impedance2,L1,L2
    REAL(KIND=dp) :: Basis(n),dBasisdx(n,3),ddBasisddx(n,3,3),X,Y,Z
    COMPLEX(KIND=dp) :: LSTIFF(n,n), LFORCE(n), A
    LOGICAL :: Stat
    INTEGER :: i,p,q,t,dim,CoordSys
    TYPE(GaussIntegrationPoints_t) :: IntegStuff
!------------------------------------------------------------------------------
    dim = CoordinateSystemDimension()
    CoordSys = CurrentCoordinateSystem()

    LSTIFF = 0.0d0
    LFORCE = 0.0d0
!------------------------------------------------------------------------------
!   Numerical integration
!------------------------------------------------------------------------------
    IntegStuff = GaussPoints( Element )
!------------------------------------------------------------------------------
    DO t=1,IntegStuff % n
       U = IntegStuff % u(t)
       V = IntegStuff % v(t)
       W = IntegStuff % w(t)
       S = IntegStuff % s(t)
!------------------------------------------------------------------------------
!      Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
       stat = ElementInfo( Element, Nodes, U, V, W, SqrtElementMetric, &
              Basis, dBasisdx, ddBasisddx, .FALSE., .FALSE. )

       s = s * SqrtElementMetric
       IF ( CoordSys /= Cartesian ) THEN
          X = SUM( Nodes % x(1:n) * Basis(1:n) )
          Y = SUM( Nodes % y(1:n) * Basis(1:n) )
          Z = SUM( Nodes % z(1:n) * Basis(1:n) )
          s = s * CoordinateSqrtMetric( X,Y,Z )
       END IF
!------------------------------------------------------------------------------
       Impedance1 = SUM( Impedance(1,1:n) * Basis )
       IF ( ABS(Impedance1) > AEPS ) &
          Impedance1 = AngularFrequency / Impedance1

       Impedance2 = SUM( Impedance(2,1:n) * Basis )
       IF ( ABS(Impedance2) > AEPS ) &
          Impedance2 = AngularFrequency / Impedance2

       L1 = SUM( Load(1,1:n) * Basis )
       L2 = SUM( Load(2,1:n) * Basis )
!------------------------------------------------------------------------------
       DO p=1,n
          DO q=1,n
             A = DCMPLX(Impedance1, Impedance2) * Basis(q) * Basis(p)
             LSTIFF(p,q) = LSTIFF(p,q) + s * A
          END DO

          LFORCE(p) = LFORCE(p) + s * Basis(p) * DCMPLX(L1,L2)
       END DO
!------------------------------------------------------------------------------
    END DO
!------------------------------------------------------------------------------
    DO i=1,n
       Force( 2*(i-1)+1 ) =  REAL( LFORCE(i) )
       Force( 2*(i-1)+2 ) = AIMAG( LFORCE(i) )

       DO j=1,n
         StiffMatrix( 2*(i-1)+1, 2*(j-1)+1 ) =  REAL( LSTIFF(i,j) )
         StiffMatrix( 2*(i-1)+1, 2*(j-1)+2 ) = -AIMAG( LSTIFF(i,j) )
         StiffMatrix( 2*(i-1)+2, 2*(j-1)+1 ) =  AIMAG( LSTIFF(i,j) )
         StiffMatrix( 2*(i-1)+2, 2*(j-1)+2 ) =  REAL( LSTIFF(i,j) )
       END DO
    END DO
!------------------------------------------------------------------------------
  END SUBROUTINE LocalMatrixBoundary
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE LCondensate( n, K, F )
!------------------------------------------------------------------------------
    USE LinearAlgebra
!------------------------------------------------------------------------------
    INTEGER :: n
    COMPLEX(KIND=dp) :: K(:,:), F(:), Kbb(n,n), &
         Kbl(n,n), Klb(n,n), Fb(n)

    INTEGER :: i, Ldofs(n), Bdofs(n)

    Ldofs = (/ (i, i=1,n) /)
    Bdofs = Ldofs + n

    Kbb = K(Bdofs,Bdofs)
    Kbl = K(Bdofs,Ldofs)
    Klb = K(Ldofs,Bdofs)
    Fb  = F(Bdofs)

    CALL ComplexInvertMatrix( Kbb,n )
    F(1:n) = F(1:n) - MATMUL( Klb, MATMUL( Kbb, Fb  ) )
    K(1:n,1:n) = &
         K(1:n,1:n) - MATMUL( Klb, MATMUL( Kbb, Kbl ) )
!------------------------------------------------------------------------------
  END SUBROUTINE LCondensate
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
   SUBROUTINE LorentzForceAve( LrFr,LrFz,LrFp,BRe,BIm,Reorder )
!------------------------------------------------------------------------------

! Calculate the nodal, time-averaged, values of the Lorentz Force.
!
! It's assumed that the induced field solved through the Fourier transform
! has only z-component in a cylindrically symmetric geometry, i.e.,
! B^{i,f} = B_z e_z, B_z = B_re cos(wt) - B_im sin(wt),
! and the external AC field also has only z component, i.e.,
! B^{e,ac} = B^e e_z, B^e = B^ac cos(wt)

! The Lorentz force has thus only r-component,
! but also zero z- and phi-components are stored for the input
! of the (cylindrical) Navier-Stokes solver.
!
! Contribution from B^{i,f} with itself
! < 1/mu (curl B^i) x B^i > |r = -(1/2) * ( B_re * @B_re/@r + B_im * @B_im/@r )
!
! Contribution from B^{i,f} with B^{e,ac}
! < 1/mu (curl B^i) x B^e > |r = -(1/2) * ( B^ac * @B_re/@r )


     USE Types
     IMPLICIT NONE
     REAL(KIND=dp) :: BRe(:),BIm(:)
     REAL(KIND=dp) :: LrFr(:),LrFz(:),LrFp(:), Lorentz(3)
     INTEGER :: Reorder(:)

     TYPE(Element_t), POINTER :: Element
     TYPE(Nodes_t) :: Nodes 


     LOGICAL :: Stat

     INTEGER, POINTER :: NodeIndexes(:),Visited(:)
     INTEGER :: p,q,i,t,n,k

     REAL(KIND=dp) :: u,v,w

     REAL(KIND=dp) :: ddBasisddx(MAX_NODES,3,3)
     REAL(KIND=dp) :: Basis(MAX_NODES)
     REAL(KIND=dp) :: dBasisdx(MAX_NODES,3),SqrtElementMetric

     REAL(KIND=dp), ALLOCATABLE :: Permeability(:), BacRe(:), BacIm(:)
!------------------------------------------

     ALLOCATE( Visited(CurrentModel % NumberOfNodes) )

     ALLOCATE(Nodes % x(MAX_NODES),Nodes % y(MAX_NODES),Nodes % z(MAX_NODES))

     ALLOCATE( Permeability(MAX_NODES) )

     ALLOCATE( BacRe(MAX_NODES), BacIm(MAX_NODES) )

     Visited = 0

     LrFr = 0.0d0
     LrFz = 0.0d0
     LrFp = 0.0d0

     DO t=1,CurrentModel % NumberOfBulkElements

        Element => CurrentModel % Elements(t)
        n = Element % TYPE % NumberOfNodes
        NodeIndexes => Element % NodeIndexes

        Nodes % x(1:n) = CurrentModel % Nodes % x( NodeIndexes )
        Nodes % y(1:n) = CurrentModel % Nodes % y( NodeIndexes )
        Nodes % z(1:n) = CurrentModel % Nodes % z( NodeIndexes )

        Permeability(1:n) = ListGetReal(Material, &
             'Magnetic Permeability',n,NodeIndexes)

        k = ListGetInteger( Model % Bodies( Element % BodyId ) % &
             Values, 'Body Force', GotIt, 1, Model % NumberOFBodyForces )

        BacRe = 0.0d0
        BacIm = 0.0d0

        IF ( k > 0 ) THEN
           BacRe(1:n) = ListGetReal( Model % BodyForces(k) % Values, &
                'AC Magnetic Field Re', n, NodeIndexes, GotIt )

           BacIm(1:n) = ListGetReal( Model % BodyForces(k) % Values, &
                'AC Magnetic Field Im', n, NodeIndexes, GotIt )

        END IF


        IF ( MINVAL(Reorder(NodeIndexes)) > 0 ) THEN

           DO p=1,n

              q = Reorder(NodeIndexes(p))
              u = Element % TYPE % NodeU(p)
              v = Element % TYPE % NodeV(p)

              IF ( Element % TYPE % DIMENSION == 3 ) THEN
                 w = Element % TYPE % NodeW(p)
              ELSE
                 w = 0.0D0
              END IF

              stat = ElementInfo( Element, Nodes, u, v, w, SqrtElementMetric, &
                   Basis, dBasisdx, ddBasisddx, .FALSE. )

! Calculate Lorentz Force directly here, don't call LorentzForce
              LrFr(q) = LrFr(q) - 0.5_dp * ( &
                   SUM( dBasisdx(1:n,1) * BRe(Reorder(NodeIndexes)) ) * &
                   SUM( Basis(1:n)*BRe(Reorder(NodeIndexes)) ) + &
                   SUM( dBasisdx(1:n,1) * BIm(Reorder(NodeIndexes)) ) * &
                   SUM( Basis(1:n)*BIm(Reorder(NodeIndexes)) ) ) / &
                   Permeability(p)

              LrFr(q) = LrFr(q) - 0.5_dp * ( &
                   SUM( dBasisdx(1:n,1) * BRe(Reorder(NodeIndexes)) ) * &
                   BacIm(p) ) / Permeability(p)

              Visited(q) = Visited(q) + 1
           
           END DO
        END IF
      END DO

      DO i=1,CurrentModel % NumberOfNodes
         IF ( Visited(i) > 1 ) THEN
            LrFr(i) = LrFr(i) / Visited(i)
            LrFp(i) = LrFp(i) / Visited(i)
            LrFz(i) = LrFz(i) / Visited(i)
         END IF
      END DO

      DEALLOCATE( Visited )
      DEALLOCATE( Nodes % x, Nodes % y, Nodes % z )
      DEALLOCATE ( Permeability )

    END SUBROUTINE LorentzForceAve


!------------------------------------------------------------------------------
END SUBROUTINE FourierDiffusionSolver
!------------------------------------------------------------------------------
