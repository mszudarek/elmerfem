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
! *  This module contains some vector utilities, curl, dot, cross, etc...
! *
! ******************************************************************************
! *
! *                     Author:       Juha Ruokolainen
! *
! *                    Address: Center for Scientific Computing
! *                           Tietotie 6, P.O. BOX 405
! *                             02
! *                             Tel. +358 0 457 2723
! *                           Telefax: +358 0 457 2302
! *                         EMail: Juha.Ruokolainen@csc.fi
! *
! *                       Date: 02 Jun 1997
! *
! *                Modified by:
! *
! *       Date of modification:
! *
! *****************************************************************************/


MODULE Differentials

  USE Types
  USE LinearAlgebra
  USE ElementDescription

  IMPLICIT NONE

CONTAINS

!------------------------------------------------------------------------------
! Compute the stress tensor given displacement field
!------------------------------------------------------------------------------
  SUBROUTINE StressComp()
DLLEXPORT StressComp
!------------------------------------------------------------------------------
!------------------------------------------------------------------------------
    TYPE(Element_t), POINTER :: Element
    TYPE(Nodes_t) :: Nodes 

    TYPE(ValueList_t), POINTER :: Material

    TYPE(Variable_t), POINTER :: StressSol, TempSol
    REAL(KIND=dp), POINTER :: Temperature(:),Displacement(:),Work(:,:)
    REAL(KIND=dp), POINTER :: Stressxx(:),Stressxy(:),Stressyy(:), &
                    DispX(:),DispY(:),DispZ(:)
    INTEGER, POINTER :: TempPerm(:),StressPerm(:)

    REAL(KIND=dp) :: ElasticModulus(MAX_NODES),PoissonRatio(MAX_NODES),Lame1(MAX_NODES), &
      Lame2(MAX_NODES),HeatExpansion(MAX_NODES),ReferenceTemperature(MAX_NODES)

    LOGICAL :: Stat,GotIt,PlaneStress
    INTEGER :: i,j,k,l,m,n,p,q,t,STDOFs
    INTEGER :: body_id,bf_id,eq_id
    REAL(KIND=dp), TARGET :: nx(MAX_NODES),ny(MAX_NODES),nz(MAX_NODES)
    REAL(KIND=dp) :: x,y,z,u,v,w,s,A(3),B(3),dx(3,3)

    INTEGER :: Perm(3,3,3)
    INTEGER, POINTER :: NodeIndexes(:),Visited(:)

    REAL(KIND=dp) :: ddBasisddx(MAX_NODES,3,3)
    REAL(KIND=dp) :: Basis(MAX_NODES)
    REAL(KIND=dp) :: dBasisdx(MAX_NODES,3),SqrtElementMetric

    REAL(KIND=dp) :: SqrtMetric,Metric(3,3),Symb(3,3,3),dSymb(3,3,3,3)
!------------------------------------------------------------------------------

    ALLOCATE( Visited(CurrentModel % NumberOfNodes) )
    Visited = 0

    Nodes % x => nx
    Nodes % y => ny
    Nodes % z => nz

!------------------------------------------------------------------------------
!    Get variables needed for solution
!------------------------------------------------------------------------------
    TempSol => VariableGet( CurrentModel % Variables, 'Temperature' )
    IF ( ASSOCIATED( TempSol) ) THEN
      TempPerm    => TempSol % Perm
      Temperature => TempSol % Values
    END IF

    StressSol => VariableGet( CurrentModel % Variables, 'Displacement 1' )
    DispX   => StressSol % Values

    StressSol => VariableGet( CurrentModel % Variables, 'Displacement 2' )
    DispY   => StressSol % Values

    StressSol => VariableGet( CurrentModel % Variables, 'Displacement 3' )
    IF ( ASSOCIATED(StressSol) ) THEN
      DispZ   => StressSol % Values
    END IF

    StressSol => VariableGet( CurrentModel % Variables, 'Displacement' )
    StressPerm     => StressSol % Perm
    STDOFs         =  StressSol % DOFs
    Displacement   => StressSol % Values

    ALLOCATE(Stressxx(CurrentModel % NumberOfNodes))
    ALLOCATE(Stressxy(CurrentModel % NumberOfNodes))
    ALLOCATE(Stressyy(CurrentModel % NumberOfNodes))

    Stressxx = 0.0D0
    Stressxy = 0.0D0
    Stressyy = 0.0D0

!   CALL VariableAdd(CurrentModel % Variables,'Stress xx',1,Stressxx,StressPerm)
!   CALL VariableAdd(CurrentModel % Variables,'Stress xy',1,Stressxy,StressPerm)
!   CALL VariableAdd(CurrentModel % Variables,'Stress yy',1,Stressyy,StressPerm)

!------------------------------------------------------------------------------
!   Go trough model elements, we will compute on average of elementwise
!   stresses to nodes of the model
!------------------------------------------------------------------------------
    t = 1
    DO WHILE( t <= CurrentModel % NumberOfBulkElements )
!------------------------------------------------------------------------------
      Element => CurrentModel % Elements(t)
      body_id = Element % BodyId
      n = Element % TYPE % NumberOfNodes
      NodeIndexes => Element % NodeIndexes
!------------------------------------------------------------------------------
!     Check if this element belongs to a body where displacements
!     should be calculated
!------------------------------------------------------------------------------
      DO WHILE( t <= CurrentModel % NumberOfBulkElements )
        Element => CurrentModel % Elements(t)

        IF ( CheckElementEquation( CurrentModel, &
                           Element,'Stress Analysis' ) ) EXIT
        t = t + 1
      END DO

      IF ( t > CurrentModel % NumberOfBulkElements ) EXIT

      Nodes % x(1:n) = CurrentModel % Nodes % x( NodeIndexes )
      Nodes % y(1:n) = CurrentModel % Nodes % y( NodeIndexes )
      Nodes % z(1:n) = CurrentModel % Nodes % z( NodeIndexes )

      k = ListGetInteger( CurrentModel % Bodies(body_id) % Values,'Material', &
             minv=1, maxv=CurrentModel % NumberOfMaterials )
      Material => CurrentModel % Materials(k) % Values

      ElasticModulus(1:n) = ListGetReal( Material, &
          'Youngs Modulus',n,NodeIndexes )

      PoissonRatio(1:n) = ListGetReal( Material, &
            'Poisson Ratio',n,NodeIndexes )

      HeatExpansion   = 0.0D0
      HeatExpansion(1:n) = ListGetReal( Material,&
        'Heat Expansion Coefficient',n,NodeIndexes,gotIt )

      ReferenceTemperature(1:n) = ListGetReal( Material, &
         'Reference Temperature',n,NodeIndexes,gotIt )

      eq_id = ListGetInteger( CurrentModel % Bodies(body_id) % Values, 'Equation', &
            minv=1, maxv=CurrentModel % NumberOfEquations )
      PlaneStress = ListGetLogical( CurrentModel % Equations(eq_id) % Values, &
                       'Plane Stress',gotIt )

      IF ( PlaneStress ) THEN
        Lame1(1:n) = ElasticModulus(1:n) * PoissonRatio(1:n) /  &
             ( (1.0d0 - PoissonRatio(1:n)**2) )
      ELSE
        Lame1(1:n) = ElasticModulus(1:n) * PoissonRatio(1:n) /  &
           (  (1.0d0 + PoissonRatio(1:n)) * (1.0d0 - 2.0d0*PoissonRatio(1:n)) )
      END IF

      Lame2(1:n) = ElasticModulus(1:n)  / ( 2* (1.0d0 + PoissonRatio(1:n)) )
!------------------------------------------------------------------------------
!     Trough element nodes
!------------------------------------------------------------------------------
      DO p=1,n
        q = StressPerm( NodeIndexes(p) )
        u = Element % TYPE % NodeU(p)
        v = Element % TYPE % NodeV(p)

        IF ( Element % TYPE % DIMENSION == 3 ) THEN
          w = Element % TYPE % NodeW(p)
        ELSE
          w = 0.0D0
        END IF
!------------------------------------------------------------------------------
!       Get coordinate system info
!------------------------------------------------------------------------------
        IF ( COordinates /= Cartesian ) THEN
          x = Nodes % x(p)
          y = Nodes % y(p)
          z = Nodes % z(p)
          CALL CoordinateSystemInfo( Metric,SqrtMetric,Symb,dSymb,x,y,z )
          CALL InvertMatrix( Metric,3 )
        END IF
!------------------------------------------------------------------------------
!       Get element basis functions, basis function derivatives, etc,
!       and compute partial derivatives of the vector A with respect
!       to global coordinates.
!------------------------------------------------------------------------------
        stat = ElementInfo( Element,Nodes,u,v,w,SqrtElementMetric, &
                  Basis,dBasisdx,ddBasisddx,.FALSE. )

        DO k=1,3
          dx(1,k) = SUM( dBasisdx(1:n,k) * DispX(StressPerm(NodeIndexes)) )
          dx(2,k) = SUM( dBasisdx(1:n,k) * DispY(StressPerm(NodeIndexes)) )
#if 0
          dx(3,k) = SUM( dBasisdx(1:n,k) * DispZ(StressPerm(NodeIndexes)) )
#endif
        END DO

        Stressxx(q) = Stressxx(q) +  &
            Lame1(p) * ( dx(1,1) + dx(2,2) ) + 2 * Lame2(p) * dx(1,1) - &
           2 * (Lame1(p) + Lame2(p)) * HeatExpansion(p) *               &
            (Temperature(TempPerm(NodeIndexes(p))) - ReferenceTemperature(p))

        Stressyy(q) = Stressyy(q) + &
            Lame1(p) * ( dx(1,1) + dx(2,2) ) + 2 * Lame2(p) * dx(2,2) - &
           2 * (Lame1(p) + Lame2(p)) * HeatExpansion(p) *               &
            (Temperature(TempPerm(NodeIndexes(p))) - ReferenceTemperature(p))

        Stressxy(q) = Stressxy(q) +  Lame2(p) * ( dx(1,2) + dx(2,1) )

        Visited(q) = Visited(q) + 1
      END DO
!------------------------------------------------------------------------------
      t = t + 1
    END DO
!------------------------------------------------------------------------------
!   Finally, compute average of the the stress at nodes
!------------------------------------------------------------------------------
    DO i=1,CurrentModel % NumberOfNodes
      IF ( Visited(i) > 0 ) THEN
        Stressxx(i) = Stressxx(i) / Visited(i)
        Stressyy(i) = Stressyy(i) / Visited(i)
        Stressxy(i) = Stressxy(i) / Visited(i)
      END IF
    END DO

    DEALLOCATE( Visited )
!------------------------------------------------------------------------------
  END SUBROUTINE StressComp
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
! Compute the grad vector B = grad(A) at model nodes
!------------------------------------------------------------------------------
  SUBROUTINE Grad( Ax,Bx,By,Bz,Reorder )
DLLEXPORT Grad
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: Ax(:),Bx(:),By(:),Bz(:)
    INTEGER :: Reorder(:)
!------------------------------------------------------------------------------
    TYPE(Element_t), POINTER :: Element
    TYPE(Nodes_t) :: Nodes 

    LOGICAL :: Stat
    INTEGER :: i,j,k,l,m,n,p,q,t
    REAL(KIND=dp), TARGET :: nx(MAX_NODES),ny(MAX_NODES),nz(MAX_NODES)
    REAL(KIND=dp) :: x,y,z,u,v,w,s,A(3),B(3),dx(3,3)

    INTEGER :: Perm(3,3,3)
    INTEGER, POINTER :: NodeIndexes(:),Visited(:)

    REAL(KIND=dp) :: ddBasisddx(MAX_NODES,3,3)
    REAL(KIND=dp) :: Basis(MAX_NODES)
    REAL(KIND=dp) :: dBasisdx(MAX_NODES,3),SqrtElementMetric

    REAL(KIND=dp) :: SqrtMetric,Metric(3,3),Symb(3,3,3),dSymb(3,3,3,3)
!------------------------------------------------------------------------------

    ALLOCATE( Visited(CurrentModel % NumberOfNodes) )
    Visited = 0

    Nodes % x => nx
    Nodes % y => ny
    Nodes % z => nz

    Bx = 0.0D0
    By = 0.0D0
    Bz = 0.0D0
!------------------------------------------------------------------------------
!   Go trough model elements, we will compute on average of elementwise
!   grads to nodes of the model
!------------------------------------------------------------------------------
    DO t=1,CurrentModel % NumberOfBulkElements
!------------------------------------------------------------------------------
      Element => CurrentModel % Elements(t)
      n = Element % TYPE % NumberOfNodes
      NodeIndexes => Element % NodeIndexes

      IF ( ANY(Reorder(NodeIndexes) == 0) ) CYCLE

      Nodes % x(1:n) = CurrentModel % Nodes % x( NodeIndexes )
      Nodes % y(1:n) = CurrentModel % Nodes % y( NodeIndexes )
      Nodes % z(1:n) = CurrentModel % Nodes % z( NodeIndexes )
!------------------------------------------------------------------------------
!     Trough element nodes
!------------------------------------------------------------------------------
      DO p=1,n
        q = Reorder( NodeIndexes(p) )
        IF ( q > 0 ) THEN
          u = Element % TYPE % NodeU(p)
          v = Element % TYPE % NodeV(p)

          IF ( Element % TYPE % DIMENSION == 3 ) THEN
            w = Element % TYPE % NodeW(p)
          ELSE
            w = 0.0D0
          END IF
!------------------------------------------------------------------------------
!       Get coordinate system info
!------------------------------------------------------------------------------
!         IF ( CurrentCoordinateSystem() /= Cartesian ) THEN
!           x = Nodes % x(p)
!           y = Nodes % y(p)
!           z = Nodes % z(p)
!           CALL CoordinateSystemInfo( Metric,SqrtMetric,Symb,dSymb,x,y,z )
!           CALL InvertMatrix( Metric,3 )
!         END IF
!------------------------------------------------------------------------------
!       Get element basis functions, basis function derivatives, etc,
!       and compute partial derivatives of the vector A with respect
!       to global coordinates.
!------------------------------------------------------------------------------
          stat = ElementInfo( Element,Nodes,u,v,w,SqrtElementMetric, &
                    Basis,dBasisdx,ddBasisddx,.FALSE. )

          Bx(q) = Bx(q) + SUM( dBasisdx(1:n,1)*Ax(Reorder(NodeIndexes)) )
          By(q) = By(q) + SUM( dBasisdx(1:n,2)*Ax(Reorder(NodeIndexes)) )
          Bz(q) = Bz(q) + SUM( dBasisdx(1:n,3)*Ax(Reorder(NodeIndexes)) )
  
          Visited(q) = Visited(q) + 1
        END IF
      END DO
!------------------------------------------------------------------------------
    END DO
!------------------------------------------------------------------------------
!   Finally, compute average of the the derivatives at nodes
!------------------------------------------------------------------------------
    DO i=1,CurrentModel % NumberOfNodes
      IF ( Visited(i) > 1 ) THEN
        Bx(i) = Bx(i) / Visited(i)
        By(i) = By(i) / Visited(i)
        Bz(i) = Bz(i) / Visited(i)
      END IF
    END DO

    DEALLOCATE( Visited )
!------------------------------------------------------------------------------
  END SUBROUTINE Grad
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  FUNCTION LorentzForce( Element,Nodes,u,v,w ) RESULT(L)
DLLEXPORT LorentzForce
!------------------------------------------------------------------------------
    TYPE(Element_t), POINTER :: Element
    TYPE(Nodes_t) :: Nodes
    REAL(KIND=dp) :: L(3),u,v,w,x,y,z
!------------------------------------------------------------------------------
    TYPE(Variable_t), POINTER :: Mx,My,Mz,MFx,MFy,MFz
    INTEGER :: i,j,k,n,bfId
    LOGICAL :: stat,GotIt
    INTEGER, POINTER :: NodeIndexes(:)

    TYPE(ValueList_t), POINTER :: Material

    REAL(KIND=dp) :: ddBasisddx(MAX_NODES,3,3),B(3),dHdx(3,3)
    REAL(KIND=dp) :: dBasisdx(MAX_NODES,3),SqrtElementMetric
    REAL(KIND=dp) :: Basis(MAX_NODES),Permeability(MAX_NODES),mu

    REAL(KIND=dp) :: ExtMx(MAX_NODES),ExtMy(MAX_NODES),ExtMz(MAX_NODES)

    REAL(KIND=dp) :: SqrtMetric,Metric(3,3),Symb(3,3,3),dSymb(3,3,3,3)
!------------------------------------------------------------------------------
    L = 0.0D0

    bfId = ListGetInteger( CurrentModel % Bodies( Element % BodyId ) % Values, &
                'Body Force', GotIt, 1, CurrentModel % NumberOFBodyForces )

    IF ( .NOT.GotIt ) RETURN

    IF ( .NOT.ListGetLogical( CurrentModel % BodyForces( &
          bfId ) % Values, 'Lorentz Force' , GotIt ) ) RETURN
!------------------------------------------------------------------------------
    n = Element % TYPE % NumberOfNodes
    NodeIndexes => Element % NodeIndexes

    Mx => VariableGet( CurrentModel % Variables, 'Magnetic Field 1' )
    My => VariableGet( CurrentModel % Variables, 'Magnetic Field 2' )
    Mz => VariableGet( CurrentModel % Variables, 'Magnetic Field 3' )
    IF ( .NOT.ASSOCIATED( Mx ) ) RETURN

    IF ( ANY(Mx % Perm(NodeIndexes)<=0) ) RETURN

    k = ListGetInteger( CurrentModel % Bodies &
                    (Element % BodyId) % Values, 'Material', &
                     minv=1, maxv=CurrentModel % NumberOFMaterials )
    Material => CurrentModel % Materials(k) % Values

    Permeability(1:n) = ListGetReal( Material, 'Magnetic Permeability', &
                              n, NodeIndexes ) 
!------------------------------------------------------------------------------
    ExtMx(1:n) = ListGetReal( Material, 'Applied Magnetic Field 1', &
                    n,NodeIndexes, Gotit )

    ExtMy(1:n) = ListGetReal( Material, 'Applied Magnetic Field 2', &
                  n,NodeIndexes, Gotit )

    ExtMz(1:n) = ListGetReal( Material, 'Applied Magnetic Field 3', &
                  n,NodeIndexes, Gotit )

! If you want to use time-domain solution for high-frequendy part,
! leave external field out. Better to use frequency-domain solver!
#if 1
    MFx => VariableGet( CurrentModel % Variables, 'Magnetic Flux Density 1' )
    MFy => VariableGet( CurrentModel % Variables, 'Magnetic Flux Density 2' )
    MFz => VariableGet( CurrentModel % Variables, 'Magnetic Flux Density 3' )
    IF ( ASSOCIATED( MFx ) ) THEN
      ExtMx(1:n) = ExtMx(1:n) + MFx % Values(MFx % Perm(NodeIndexes))
      ExtMy(1:n) = ExtMy(1:n) + MFy % Values(MFy % Perm(NodeIndexes))
      ExtMz(1:n) = ExtMz(1:n) + MFz % Values(MFz % Perm(NodeIndexes))
    END IF
#endif

!------------------------------------------------------------------------------
!   Get element info 
!------------------------------------------------------------------------------
    stat = ElementInfo( Element,Nodes,u,v,w,SqrtElementMetric, &
               Basis,dBasisdx,ddBasisddx,.FALSE. )
!------------------------------------------------------------------------------
    B(1) = SUM( Basis(1:n)*Mx % Values(Mx % Perm(NodeIndexes)) )
    B(2) = SUM( Basis(1:n)*My % Values(My % Perm(NodeIndexes)) )
    B(3) = SUM( Basis(1:n)*Mz % Values(Mz % Perm(NodeIndexes)) )

    B(1) = B(1) + SUM( Basis(1:n)*ExtMx(1:n) )
    B(2) = B(2) + SUM( Basis(1:n)*ExtMy(1:n) )
    B(3) = B(3) + SUM( Basis(1:n)*ExtMz(1:n) )

    DO i=1,3
      dHdx(1,i) = SUM( dBasisdx(1:n,i)* &
           Mx % Values(Mx % Perm(NodeIndexes)) / Permeability(1:n) )
      dHdx(2,i) = SUM( dBasisdx(1:n,i)* &
           My % Values(My % Perm(NodeIndexes)) / Permeability(1:n) )
      dHdx(3,i) = SUM( dBasisdx(1:n,i)* &
           Mz % Values(Mz % Perm(NodeIndexes)) / Permeability(1:n) )
    END DO
!------------------------------------------------------------------------------
!       Get coordinate system info
!------------------------------------------------------------------------------
    x = SUM( Nodes % x(1:n) * Basis(1:n) )
    y = SUM( Nodes % y(1:n) * Basis(1:n) )
    z = SUM( Nodes % z(1:n) * Basis(1:n) )
    CALL CoordinateSystemInfo( Metric,SqrtMetric,Symb,dSymb,x,y,z )
    IF ( CurrentCoordinateSystem() /= Cartesian ) CALL InvertMatrix( Metric,3 )

    mu = SUM( Permeability(1:n)*Basis(1:n) )
    L = ComputeLorentz( B,dHdx,mu,SqrtMetric,Metric,Symb )

CONTAINS

!------------------------------------------------------------------------------
  FUNCTION ComputeLorentz( B,dHdx,mu,SqrtMetric,Metric,Symb ) RESULT(LF)
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: B(:),dHdx(:,:),mu,LF(3),SqrtMetric,Metric(:,:),Symb(:,:,:)
!------------------------------------------------------------------------------
    INTEGER :: i,j,k,l,m
    REAL(KIND=dp) :: Bc(3),Ji(3),Jc(3),s,Perm(3,3,3),r
!------------------------------------------------------------------------------

    IF ( CurrentCoordinateSystem() == Cartesian ) THEN
      Ji(1) = dHdx(3,2) - dHdx(2,3)
      Ji(2) = dHdx(1,3) - dHdx(3,1)
      Ji(3) = dHdx(2,1) - dHdx(1,2)
      LF(1) = Ji(2)*B(3) - Ji(3)*B(2)
      LF(2) = Ji(3)*B(1) - Ji(1)*B(3)
      LF(3) = Ji(1)*B(2) - Ji(2)*B(1)
      RETURN
    END IF

    r = SqrtMetric

#ifdef CYLSYM
    IF ( CurrentCoordinateSystem()  == CylindricSymmetric ) THEN
      Ji(1) = -dHdx(3,2)
      Ji(2) =  dHdx(3,1)
      IF (r > 1.0d-10) THEN
         Ji(2) = Ji(2) + B(3)/(r*mu)
      ELSE
         Ji(2) = Ji(2) + Ji(2)
      END IF
      Ji(3) = dHdx(1,2) - dHdx(2,1)

      LF(1) = Ji(3)*B(2) - Ji(2)*B(3)
      LF(2) = Ji(1)*B(3) - Ji(3)*B(1)
! You might want to use SI units for the azimuthal component,
! if you compute Lorentz force at nodal points and symmetry axis,
! otherwise you divide by zero.
#ifdef SI_UNITS
      LF(3) = Ji(2)*B(1) - Ji(1)*B(2)
#else
      IF (r > 1.0d-10) THEN
         LF(3) = ( Ji(2)*B(1) - Ji(1)*B(2) ) / r
      ELSE
         LF(3) = 0.d0
      END IF
#endif
      RETURN
    END IF
#endif

    Perm = 0
    Perm(1,2,3) = -1.0d0 / SqrtMetric
    Perm(1,3,2) =  1.0d0 / SqrtMetric
    Perm(2,1,3) =  1.0d0 / SqrtMetric
    Perm(2,3,1) = -1.0d0 / SqrtMetric
    Perm(3,1,2) = -1.0d0 / SqrtMetric
    Perm(3,2,1) =  1.0d0 / SqrtMetric
!------------------------------------------------------------------------------

    Bc = 0.0d0
    DO i=1,3
      DO j=1,3
        Bc(i) = Bc(i) + Metric(i,j)*B(j)
      END DO
    END DO

!------------------------------------------------------------------------------

    Ji = 0.0d0
    DO i=1,3
      s = 0.0D0
      DO j=1,3
        DO k=1,3
          IF ( Perm(i,j,k) /= 0 ) THEN
            DO l=1,3
              s = s + Perm(i,j,k)*Metric(j,l)*dHdx(l,k)
              DO m=1,3
                s = s + Perm(i,j,k)*Metric(j,l)*Symb(k,m,l)*B(m)/mu
              END DO
            END DO
          END IF
        END DO
      END DO
      Ji(i) = s
    END DO
 
    Jc = 0.0d0
    DO i=1,3
      DO j=1,3
        Jc(i) = Jc(i) + Metric(i,j)*Ji(j)
      END DO
    END DO
!------------------------------------------------------------------------------

    LF = 0.0d0
    DO i=1,3
      s = 0.0D0
      DO j=1,3
        DO k=1,3
          IF ( Perm(i,j,k) /= 0 ) THEN
            s = s + Perm(i,j,k)*Jc(k)*Bc(j)
          END IF
        END DO
      END DO
      LF(i) = s
    END DO
!------------------------------------------------------------------------------
  END FUNCTION ComputeLorentz
!------------------------------------------------------------------------------
  END FUNCTION LorentzForce
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  FUNCTION JouleHeat( Element,Nodes,u,v,w ) RESULT(JouleH)
!------------------------------------------------------------------------------
    TYPE(Element_t) :: Element
    TYPE(Nodes_t) :: Nodes
    REAL(KIND=dp) :: JouleH,u,v,w,x,y,z
!------------------------------------------------------------------------------
    TYPE(Variable_t), POINTER :: Mx,My,Mz,MFx,MFy,MFz
    INTEGER :: i,j,k,n,bfId
    LOGICAL :: stat,GotIt
    INTEGER, POINTER :: NodeIndexes(:)

    TYPE(ValueList_t), POINTER :: Material

    REAL(KIND=dp) :: ddBasisddx(MAX_NODES,3,3),B(3),dHdx(3,3)
    REAL(KIND=dp) :: dBasisdx(MAX_NODES,3),SqrtElementMetric
    REAL(KIND=dp) :: Basis(MAX_NODES),Permeability(MAX_NODES), &
             ElectricConductivity(MAX_NODES)

    REAL(KIND=dp) :: ExtMx(MAX_NODES),ExtMy(MAX_NODES),ExtMz(MAX_NODES)

    REAL(KIND=dp) :: mu,SqrtMetric,Metric(3,3),Symb(3,3,3),dSymb(3,3,3,3)
!------------------------------------------------------------------------------
    JouleH = 0.0D0

    bfId = ListGetInteger( CurrentModel % Bodies( Element % BodyId ) % &
     Values, 'Body Force', GotIt, 1, CurrentModel % NumberOfBodyForces )

    IF ( .NOT.GotIt ) RETURN

    IF ( .NOT.ListGetLogical( CurrentModel % BodyForces( &
          bfId ) % Values, 'Joule Heat' , GotIt ) ) RETURN
!------------------------------------------------------------------------------
    n = Element % TYPE % NumberOfNodes
    NodeIndexes => Element % NodeIndexes

    Mx => VariableGet( CurrentModel % Variables, 'Magnetic Field 1' )
    My => VariableGet( CurrentModel % Variables, 'Magnetic Field 2' )
    Mz => VariableGet( CurrentModel % Variables, 'Magnetic Field 3' )
    IF ( .NOT.ASSOCIATED( Mx ) ) RETURN

    IF ( ANY(Mx % Perm(NodeIndexes)<=0) ) RETURN

    k = ListGetInteger( CurrentModel % Bodies &
                    (Element % BodyId) % Values, 'Material', &
                      minv=1, maxv=CurrentModel % NumberOfMaterials )
    Material => CurrentModel % Materials(k) % Values

    Permeability(1:n) = ListGetReal( Material, 'Magnetic Permeability', &
                              n, NodeIndexes ) 

    ElectricConductivity(1:n) = ListGetReal( Material, &
                    'Electrical Conductivity',n,NodeIndexes )
!------------------------------------------------------------------------------
    ExtMx(1:n) = ListGetReal( Material, 'Applied Magnetic Field 1', &
                    n,NodeIndexes, Gotit )

    ExtMy(1:n) = ListGetReal( Material, 'Applied Magnetic Field 2', &
                  n,NodeIndexes, Gotit )

    ExtMz(1:n) = ListGetReal( Material, 'Applied Magnetic Field 3', &
                  n,NodeIndexes, Gotit )
!
    MFx => VariableGet( CurrentModel % Variables, 'Magnetic Flux Density 1' )
    MFy => VariableGet( CurrentModel % Variables, 'Magnetic Flux Density 2' )
    MFz => VariableGet( CurrentModel % Variables, 'Magnetic Flux Density 3' )
    IF ( ASSOCIATED( MFx ) ) THEN
      ExtMx(1:n) = ExtMx(1:n) + MFx % Values(MFx % Perm(NodeIndexes))
      ExtMy(1:n) = ExtMy(1:n) + MFy % Values(MFy % Perm(NodeIndexes))
      ExtMz(1:n) = ExtMz(1:n) + MFz % Values(MFz % Perm(NodeIndexes))
    END IF

!------------------------------------------------------------------------------
!   Get element info 
!------------------------------------------------------------------------------
    stat = ElementInfo( Element,Nodes,u,v,w,SqrtElementMetric, &
               Basis,dBasisdx,ddBasisddx,.FALSE. )
!------------------------------------------------------------------------------
    B(1) = SUM( Basis(1:n)*Mx % Values(Mx % Perm(NodeIndexes)) )
    B(2) = SUM( Basis(1:n)*My % Values(My % Perm(NodeIndexes)) )
    B(3) = SUM( Basis(1:n)*Mz % Values(Mz % Perm(NodeIndexes)) )

    B(1) = B(1) + SUM( Basis(1:n)*ExtMx(1:n) )
    B(2) = B(2) + SUM( Basis(1:n)*ExtMy(1:n) )
    B(3) = B(3) + SUM( Basis(1:n)*ExtMz(1:n) )

    mu = SUM( Basis(1:n) * Permeability(1:n) )
    DO i=1,3
      dHdx(1,i) = SUM( dBasisdx(1:n,i)* &
           Mx % Values(Mx % Perm(NodeIndexes))/Permeability(1:n) )
      dHdx(2,i) = SUM( dBasisdx(1:n,i)* &
           My % Values(My % Perm(NodeIndexes))/Permeability(1:n) )
      dHdx(3,i) = SUM( dBasisdx(1:n,i)* &
           Mz % Values(Mz % Perm(NodeIndexes))/Permeability(1:n) )
    END DO
!------------------------------------------------------------------------------
!       Get coordinate system info
!------------------------------------------------------------------------------
    x = SUM( Nodes % x(1:n) * Basis(1:n))
    y = SUM( Nodes % y(1:n) * Basis(1:n))
    z = SUM( Nodes % z(1:n) * Basis(1:n))
    CALL CoordinateSystemInfo( Metric,SqrtMetric,Symb,dSymb,x,y,z )
    IF ( CurrentCoordinateSystem() /= Cartesian ) CALL InvertMatrix( Metric,3 )

    JouleH = ComputeHeat( B,dHdx,mu,SqrtMetric,Metric,Symb ) / &
      SUM( ElectricConductivity(1:n) * Basis(1:n) )

CONTAINS

!------------------------------------------------------------------------------
  FUNCTION ComputeHeat( B,dHdx,mu,SqrtMetric,Metric,Symb ) RESULT(JH)
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: B(:),dHdx(:,:),mu,JH,SqrtMetric,Metric(:,:),Symb(:,:,:)
!------------------------------------------------------------------------------
    INTEGER :: i,j,k,l,m
    REAL(KIND=dp) :: Bc(3),Ji(3),Jc(3),s,Perm(3,3,3),r
!------------------------------------------------------------------------------

    IF ( CurrentCoordinateSystem() == Cartesian ) THEN
      Ji(1) = dHdx(3,2) - dHdx(2,3)
      Ji(2) = dHdx(1,3) - dHdx(3,1)
      Ji(3) = dHdx(2,1) - dHdx(1,2)
      JH = Ji(1)*Ji(1) + Ji(2)*Ji(2) + Ji(3)*Ji(3)
      RETURN
    END IF

#ifdef CYLCYM
    IF ( CurrentCoordinateSystem() == CylindricSymmetric ) THEN
      r = SqrtMetric
      Ji(1) = -dHdx(3,2)
      Ji(2) = B(3)/(r*mu) + dHdx(3,1)
      Ji(3) = dHdx(1,2) - dHdx(2,1)
      JH = Ji(1)*Ji(1) + Ji(2)*Ji(2) + Ji(3)*Ji(3)
      RETURN
    END IF
#endif

    Perm = 0
    Perm(1,2,3) = -1.0d0 / SqrtMetric
    Perm(1,3,2) =  1.0d0 / SqrtMetric
    Perm(2,1,3) =  1.0d0 / SqrtMetric
    Perm(2,3,1) = -1.0d0 / SqrtMetric
    Perm(3,1,2) = -1.0d0 / SqrtMetric
    Perm(3,2,1) =  1.0d0 / SqrtMetric
!------------------------------------------------------------------------------

    Bc = 0.0d0
    DO i=1,3
      DO j=1,3
        Bc(i) = Bc(i) + Metric(i,j)*B(j)
      END DO
    END DO

!------------------------------------------------------------------------------

    Ji = 0.0d0
    DO i=1,3
      s = 0.0D0
      DO j=1,3
        DO k=1,3
          IF ( Perm(i,j,k) /= 0 ) THEN
            DO l=1,3
              s = s + Perm(i,j,k)*Metric(j,l)*dHdx(l,k)
              DO m=1,3
                s = s + Perm(i,j,k)*Metric(j,l)*Symb(k,m,l)*B(m)/mu
              END DO
            END DO
          END IF
        END DO
      END DO
      Ji(i) = s
    END DO
 
    Jc = 0.0d0
    DO i=1,3
      DO j=1,3
        Jc(i) = Jc(i) + Metric(i,j)*Ji(j)
      END DO
    END DO

!------------------------------------------------------------------------------

    JH = 0.0d0
    DO i=1,3
      JH = JH + Ji(i) * Jc(i)
    END DO
!------------------------------------------------------------------------------
  END FUNCTION ComputeHeat
!------------------------------------------------------------------------------
  END FUNCTION JouleHeat
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
! Compute the curl vector B = curl(A) at model nodes
!------------------------------------------------------------------------------
  SUBROUTINE Curl( Ax,Ay,Az,Bx,By,Bz,Reorder )
DLLEXPORT Curl
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: Ax(:),Ay(:),Az(:),Bx(:),By(:),Bz(:)
    INTEGER :: Reorder(:)
!------------------------------------------------------------------------------
    TYPE(Element_t), POINTER :: Element
    TYPE(Nodes_t) :: Nodes 

    LOGICAL :: Stat
    INTEGER :: i,j,k,l,m,n,p,q,t
    REAL(KIND=dp), TARGET :: nx(MAX_NODES),ny(MAX_NODES),nz(MAX_NODES)
    REAL(KIND=dp) :: x,y,z,u,v,w,s,A(3),B(3),dx(3,3)

    INTEGER :: Perm(3,3,3)
    INTEGER, POINTER :: NodeIndexes(:),Visited(:)

    REAL(KIND=dp) :: ddBasisddx(MAX_NODES,3,3)
    REAL(KIND=dp) :: Basis(MAX_NODES),aaz(MAX_NODES)
    REAL(KIND=dp) :: dBasisdx(MAX_NODES,3),SqrtElementMetric

    REAL(KIND=dp) :: SqrtMetric,Metric(3,3),Symb(3,3,3),dSymb(3,3,3,3)
!------------------------------------------------------------------------------

    ALLOCATE( Visited(CurrentModel % NumberOfNodes) )
    Visited = 0

    Perm = 0
    Perm(1,2,3) = -1
    Perm(1,3,2) =  1
    Perm(2,1,3) =  1
    Perm(2,3,1) = -1
    Perm(3,1,2) = -1
    Perm(3,2,1) =  1

    Nodes % x => nx
    Nodes % y => ny
    Nodes % z => nz

    Bx = 0.0D0
    By = 0.0D0
    Bz = 0.0D0
!------------------------------------------------------------------------------
!   Go trough model elements, we will compute on average of elementwise
!   curls on nodes of the model
!------------------------------------------------------------------------------
    DO t=1,CurrentModel % NumberOfBulkElements
!------------------------------------------------------------------------------
      Element => CurrentModel % Elements(t)
      n = Element % TYPE % NumberOfNodes
      NodeIndexes => Element % NodeIndexes

      Nodes % x(1:n) = CurrentModel % Nodes % x( NodeIndexes )
      Nodes % y(1:n) = CurrentModel % Nodes % y( NodeIndexes )
      Nodes % z(1:n) = CurrentModel % Nodes % z( NodeIndexes )
!------------------------------------------------------------------------------
!     Trough element nodes
!------------------------------------------------------------------------------

      IF (MINVAL(Reorder(NodeIndexes)) > 0) THEN

      DO p=1,n
        q = Reorder(NodeIndexes(p))
        u = Element % TYPE % NodeU(p)
        v = Element % TYPE % NodeV(p)

        IF ( Element % TYPE % DIMENSION == 3 ) THEN
          w = Element % TYPE % NodeW(p)
        ELSE
          w = 0.0D0
        END IF
!------------------------------------------------------------------------------
!       Get element basis functions, basis function derivatives, etc,
!       and compute partials derivatives of the vector A with respect
!       to global coordinates.
!------------------------------------------------------------------------------
        stat = ElementInfo( Element,Nodes,u,v,w,SqrtElementMetric, &
                  Basis,dBasisdx,ddBasisddx,.FALSE. )
!------------------------------------------------------------------------------
!       Get coordinate system info
!------------------------------------------------------------------------------
        IF ( CurrentCoordinateSystem() /= Cartesian ) THEN
          x = SUM( Nodes % x(1:n) * Basis(1:n))
          y = SUM( Nodes % y(1:n) * Basis(1:n))
          z = SUM( Nodes % z(1:n) * Basis(1:n))
          CALL CoordinateSystemInfo( Metric,SqrtMetric,Symb,dSymb,x,y,z )
          CALL InvertMatrix( Metric,3 )
        END IF

!        print *, '***',p
!        print *, '***',x,y,z
!        print *, '***',NodeIndexes
!        print *, '***',Reorder(NodeIndexes)

        DO k=1,3
          dx(1,k) = SUM( dBasisdx(1:n,k) * Ax(Reorder(NodeIndexes)) )
          dx(2,k) = SUM( dBasisdx(1:n,k) * Ay(Reorder(NodeIndexes)) )
          dx(3,k) = SUM( dBasisdx(1:n,k) * Az(Reorder(NodeIndexes)) )
        END DO
!------------------------------------------------------------------------------
!       And compute the curl for the node of the current element
!------------------------------------------------------------------------------
        IF ( CurrentCoordinateSystem() /= Cartesian ) THEN
          A(1) = Ax(q)
          A(2) = Ay(q)
          A(3) = Az(q)
          B = 0.0D0
          IF ( ABS(SqrtMetric) > 1.0d-15 ) THEN
            DO i=1,3
              s = 0.0D0
              DO j=1,3
                DO k=1,3
                  IF ( Perm(i,j,k) /= 0 ) THEN
                    DO l=1,3
                      s = s + Perm(i,j,k)*Metric(j,l)*dx(l,k)
                      DO m=1,3
                        s = s + Perm(i,j,k)*Metric(j,l)*Symb(k,m,l)*A(m)
                      END DO
                    END DO
                  END IF
                END DO
              END DO
              B(i) = s
            END DO
       
            Bx(q) = Bx(q) + B(1) / SqrtMetric
            By(q) = By(q) + B(2) / SqrtMetric
            Bz(q) = Bz(q) + B(3) / SqrtMetric
          END IF
        ELSE

          Bx(q) = Bx(q) + dx(3,2) - dx(2,3)
          By(q) = By(q) + dx(1,3) - dx(3,1)
          Bz(q) = Bz(q) + dx(2,1) - dx(1,2)

        END IF
        Visited(q) = Visited(q) + 1
      END DO

    END IF

!------------------------------------------------------------------------------
    END DO
!------------------------------------------------------------------------------
!   Finally, compute average of the the curls at nodes
!------------------------------------------------------------------------------
    DO i=1,CurrentModel % NumberOfNodes
      IF ( Visited(i) > 0 ) THEN
        Bx(i) = Bx(i) / Visited(i)
        By(i) = By(i) / Visited(i)
        Bz(i) = Bz(i) / Visited(i)
      END IF
    END DO

    DEALLOCATE( Visited )
!------------------------------------------------------------------------------
  END SUBROUTINE Curl
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
SUBROUTINE AxiSCurl( Ar,Az,Ap,Br,Bz,Bp,Reorder )
  DLLEXPORT AxiSCurl
!------------------------------------------------------------------------------
  IMPLICIT NONE
  REAL(KIND=dp) :: Ar(:),Az(:),Ap(:),Br(:),Bz(:),Bp(:)
  INTEGER :: Reorder(:)

  TYPE(Element_t), POINTER :: Element
  TYPE(Nodes_t) :: Nodes 

  LOGICAL :: Stat

  INTEGER, POINTER :: NodeIndexes(:),Visited(:)
  INTEGER :: p,q,i,t,n

  REAL(KIND=dp) :: u,v,w,r

  REAL(KIND=dp) :: ddBasisddx(MAX_NODES,3,3)
  REAL(KIND=dp) :: Basis(MAX_NODES)
  REAL(KIND=dp) :: dBasisdx(MAX_NODES,3),SqrtElementMetric
  
!------------------------------------------

  ALLOCATE( Visited(CurrentModel % NumberOfNodes) )

  ALLOCATE(Nodes % x(MAX_NODES),Nodes % y(MAX_NODES),Nodes % z(MAX_NODES))

  Visited = 0

  Br = 0.0d0
  Bz = 0.0d0
  Bp = 0.0d0

  DO t=1,CurrentModel % NumberOfBulkElements

     Element => CurrentModel % Elements(t)
     n = Element % TYPE % NumberOfNodes
     NodeIndexes => Element % NodeIndexes

     Nodes % x(1:n) = CurrentModel % Nodes % x( NodeIndexes )
     Nodes % y(1:n) = CurrentModel % Nodes % y( NodeIndexes )
     Nodes % z(1:n) = CurrentModel % Nodes % z( NodeIndexes )

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

           r = SUM( Basis(1:n) * Nodes % x(1:n) )

           Br(q) = Br(q) - SUM( dBasisdx(1:n,2)*Ap(Reorder(NodeIndexes)) )

           Bp(q) = Bp(q) + SUM( dBasisdx(1:n,2) * Ar(Reorder(NodeIndexes)) ) &
                - SUM( dBasisdx(1:n,1) * Az(Reorder(NodeIndexes)) )

           Bz(q) = Bz(q) + SUM( dBasisdx(1:n,1) * Ap(Reorder(NodeIndexes)) )

           IF (r > 1.0d-10) THEN
              Bz(q) = Bz(q) + SUM( Basis(1:n)*Ap(Reorder(NodeIndexes)) ) / r
           ELSE
              Bz(q) = Bz(q) + SUM( dBasisdx(1:n,1)*Ap(Reorder(NodeIndexes)) )
           END IF

           Visited(q) = Visited(q) + 1
           
        END DO
     END IF
  END DO

  DO i=1,CurrentModel % NumberOfNodes
     IF ( Visited(i) > 0 ) THEN
        Br(i) = Br(i) / Visited(i)
        Bp(i) = Bp(i) / Visited(i)
        Bz(i) = Bz(i) / Visited(i)
     END IF
  END DO

  DEALLOCATE( Visited )
  DEALLOCATE( Nodes % x, Nodes % y, Nodes % z )

!------------------------------------------------------------------------------
END SUBROUTINE AxiSCurl
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
! Compute the curl vector B = curl(A) at model nodes, A given at edge dofs
!------------------------------------------------------------------------------
!------------------------------------------------------------------------------
SUBROUTINE WhitneyCurl( Ae,Bx,By,Bz,Reorder,nedges )
DLLEXPORT WhitneyCurl
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: Ae(:),Bx(:),By(:),Bz(:)
    INTEGER :: Reorder(:),nedges
!------------------------------------------------------------------------------
    TYPE(Element_t) :: Element
    TYPE(Nodes_t) :: Nodes 

    LOGICAL :: Stat
    INTEGER :: i,j,k,l,m,n,p,q,t
    REAL(KIND=dp), TARGET :: nx(MAX_NODES),ny(MAX_NODES),nz(MAX_NODES)
    REAL(KIND=dp) :: x,y,z,u,v,w,s,A(3),B(3),dx(3,3)

    INTEGER, POINTER :: NodeIndexes(:),Visited(:)

    REAL(KIND=dp) :: ddBasisddx(MAX_NODES,3,3)
    REAL(KIND=dp) :: Basis(MAX_NODES),aaz(MAX_NODES)
    REAL(KIND=dp) :: dBasisdx(MAX_NODES,3),SqrtElementMetric
    REAL(KIND=dp) :: WhitneyBasis(nedges,3)
    REAL(KIND=dp) :: dWhitneyBasisdx(nedges,3,3)

    REAL(KIND=dp) :: SqrtMetric,Metric(3,3),Symb(3,3,3),dSymb(3,3,3,3)
!------------------------------------------------------------------------------

    ALLOCATE( Visited(CurrentModel % NumberOfNodes) )
    Visited = 0

    Nodes % x => nx
    Nodes % y => ny
    Nodes % z => nz

    Bx = 0.0D0
    By = 0.0D0
    Bz = 0.0D0
!------------------------------------------------------------------------------
!   Go through model elements, we will compute on average of elementwise
!   curls on nodes of the model
!------------------------------------------------------------------------------
    DO t=1,CurrentModel % NumberOfBulkElements
!------------------------------------------------------------------------------
      Element = CurrentModel % Elements(t)

      IF ( Element % Type % ElementCode/100 == 3 ) THEN
         Element % Type => GetElementType( 303 )
      ELSE
         Element % Type => GetElementType( 504 )
      END IF

      n = Element % Type % NumberOfNodes
      NodeIndexes => Element % NodeIndexes

      Nodes % x(1:n) = CurrentModel % Nodes % x( NodeIndexes )
      Nodes % y(1:n) = CurrentModel % Nodes % y( NodeIndexes )
      Nodes % z(1:n) = CurrentModel % Nodes % z( NodeIndexes )
!------------------------------------------------------------------------------
!     Through element nodes
!------------------------------------------------------------------------------

      IF (MINVAL(Reorder(NodeIndexes)) > 0) THEN

      DO p=1,n+nedges
        q = Reorder(NodeIndexes(p))
        u = Element % Type % NodeU(p)
        v = Element % Type % NodeV(p)
        w = Element % Type % NodeW(p)

!------------------------------------------------------------------------------
!       Get element basis functions, basis function derivatives, etc,
!       and compute partials derivatives of the vector A with respect
!       to global coordinates.
!------------------------------------------------------------------------------
        stat = ElementInfo( Element, Nodes, u, v, w, SqrtElementMetric, &
                    Basis, dBasisdx, ddBasisddx, .FALSE. )

        stat = WhitneyElementInfo( Element, Basis, dBasisdx,&
               nedges, WhitneyBasis, dWhitneyBasisdx )

        DO k=1,3
          dx(1,k) = SUM( dWhitneyBasisdx(1:nedges,1,k)*Ae(Reorder(NodeIndexes(n+1:n+nedges))))
          dx(2,k) = SUM( dWhitneyBasisdx(1:nedges,2,k)*Ae(Reorder(NodeIndexes(n+1:n+nedges))))
          dx(3,k) = SUM( dWhitneyBasisdx(1:nedges,3,k)*Ae(Reorder(NodeIndexes(n+1:n+nedges))))      
        END DO

!------------------------------------------------------------------------------
!       And compute the curl for the node of the current element
!------------------------------------------------------------------------------

        Bx(q) = Bx(q) + dx(3,2) - dx(2,3)
        By(q) = By(q) + dx(1,3) - dx(3,1)
        Bz(q) = Bz(q) + dx(2,1) - dx(1,2)

        Visited(q) = Visited(q) + 1
      END DO

    END IF

!------------------------------------------------------------------------------
    END DO
!------------------------------------------------------------------------------
!   Finally, compute average of the the curls at nodes
!------------------------------------------------------------------------------
    DO i=1,CurrentModel % NumberOfNodes
      IF ( Visited(i) > 0 ) THEN
        Bx(i) = Bx(i) / Visited(i)
        By(i) = By(i) / Visited(i)
        Bz(i) = Bz(i) / Visited(i)
      END IF
    END DO

    DEALLOCATE( Visited )
!------------------------------------------------------------------------------
  END SUBROUTINE WhitneyCurl
!------------------------------------------------------------------------------


!-------------------------------------------------
!  Compute divergence in cylindrical coordinates
!-------------------------------------------------

SUBROUTINE Divergence(dive,Ar,Az,Aphi,Reorder)
  IMPLICIT NONE
  REAL(KIND=dp) :: dive(:),Ar(:),Az(:),Aphi(:)
  INTEGER :: Reorder(:)

  TYPE(Element_t), POINTER :: Element
  TYPE(Nodes_t) :: Nodes 

  LOGICAL :: Stat

  INTEGER, POINTER :: NodeIndexes(:),Visited(:)
  
  REAL(KIND=dp) :: ddBasisddx(MAX_NODES,3,3)
  REAL(KIND=dp) :: Basis(MAX_NODES)
  REAL(KIND=dp) :: dBasisdx(MAX_NODES,3),SqrtElementMetric

  INTEGER :: t,n,p,i,q
  REAL(KIND=dp) :: u,v,w,r

!--------------------------------------------------------------
 
  ALLOCATE( Visited(CurrentModel % NumberOfNodes) )

  ALLOCATE(Nodes % x(MAX_NODES),Nodes % y(MAX_NODES),Nodes % z(MAX_NODES))

  Visited = 0

  dive=0

  DO t=1,CurrentModel % NumberOfBulkElements

   Element => CurrentModel % Elements(t) 
   n = Element % TYPE % NumberOfNodes
   NodeIndexes => Element % NodeIndexes

   Nodes % x(1:n) = CurrentModel % Nodes % x( NodeIndexes )
   Nodes % y(1:n) = CurrentModel % Nodes % y( NodeIndexes )
   Nodes % z(1:n) = CurrentModel % Nodes % z( NodeIndexes )

   IF (MINVAL(Reorder(NodeIndexes)) > 0) THEN

   DO p=1,n

     q = Reorder(NodeIndexes(p))
     u = Element % TYPE % NodeU(p)
     v = Element % TYPE % NodeV(p)

     IF ( Element % TYPE % DIMENSION == 3 ) THEN
       w = Element % TYPE % NodeW(p)
     ELSE
       w = 0.0D0
     END IF

     stat = ElementInfo( Element,Nodes,u,v,w,SqrtElementMetric, &
         Basis,dBasisdx,ddBasisddx,.FALSE. )

     r = SUM(Basis(1:n)*nodes % x(1:n))

     dive(q) = dive(q) + SUM(dBasisdx(1:n,1)*Ar(Reorder(NodeIndexes))) &
         + SUM(dBasisdx(1:n,3)*Aphi(Reorder(NodeIndexes))) &
         + SUM(dBasisdx(1:n,2)*Az(Reorder(NodeIndexes)))

     IF (r > 1d-10) THEN
       dive(q) = dive(q) + SUM(Basis(1:n)*Ar(Reorder(NodeIndexes)))/r
     ELSE
       dive(q) = dive(q) + SUM(dBasisdx(1:n,1)*Ar(Reorder(NodeIndexes)))
     END IF

     Visited(q) = Visited(q) + 1

   END DO

 END IF

END DO

DO i=1,CurrentModel % NumberOfNodes
  IF ( Visited(i) > 1 ) THEN
    dive(i) = dive(i)/Visited(i)
  END IF
END DO

DEALLOCATE( Visited )
DEALLOCATE(Nodes%x,nodes%y,nodes%z)

END SUBROUTINE Divergence

!------------------------------------------------------------------------------
!  Compute cross product of given vectors
!------------------------------------------------------------------------------
  SUBROUTINE Cross( Ax,Ay,Az,Bx,By,Bz,Cx,Cy,Cz,n )
DLLEXPORT Cross
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: Ax,Ay,Az,Bx,By,Bz,Cx,Cy,Cz
!------------------------------------------------------------------------------
    INTEGER :: i,j,k,n
    REAL(KIND=dp) :: SqrtMetric,Metric(3,3),Symb(3,3,3),dSymb(3,3,3,3),x,y,z
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
!   Compute the cross product
!------------------------------------------------------------------------------
    Cx = Ay * Bz - Az * By
    Cy = Az * Bx - Ax * Bz
    Cz = Ax * By - Ay * Bx
!------------------------------------------------------------------------------
!   Make contravariant
!------------------------------------------------------------------------------
    IF ( CurrentCoordinateSystem() /= Cartesian ) THEN
      x = CurrentModel % Nodes % x(n)
      y = CurrentModel % Nodes % y(n)
      z = CurrentModel % Nodes % z(n)
      CALL CoordinateSystemInfo( Metric,SqrtMetric,Symb,dSymb,x,y,z )

      x = SqrtMetric * Cx
      y = SqrtMetric * Cy
      z = SqrtMetric * Cz

      Cx = Metric(1,1)*x + Metric(1,2)*y + Metric(1,3)*z
      Cy = Metric(2,1)*x + Metric(2,2)*y + Metric(2,3)*z
      Cz = Metric(3,1)*x + Metric(3,2)*y + Metric(3,3)*z
    END IF
!------------------------------------------------------------------------------
  END SUBROUTINE Cross
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE DivCheck(Ur,Uz,Up,FlowPerm,Brv,Bzv,Bpv,MagPerm,EB,EMagPerm)
!------------------------------------------------------------------------------
    IMPLICIT NONE

    DOUBLE PRECISION :: Ur(:),Uz(:),Up(:),Brv(:),Bpv(:),Bzv(:),EB(:)
    INTEGER :: FlowPerm(:),MagPerm(:),EMagPerm(:)

!

    TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff
    TYPE(Element_t), POINTER :: Element
    TYPE(Nodes_t) :: Nodes
    INTEGER :: N_Integ
    DOUBLE PRECISION, DIMENSION(:), POINTER :: U_Integ,V_Integ,W_Integ,S_Integ
    INTEGER, POINTER :: NodeIndexes(:)
    DOUBLE PRECISION :: Basis(27),dBasisdx(27,3),ddBasisddx(27,3,3)
    DOUBLE PRECISION :: u,v,w,SqrtElementMetric,r,s
    DOUBLE PRECISION :: Vr,Vp,Vz,dVdx(3,3),Br,Bp,Bz,dBdx(3,3),divb,vdivb
    DOUBLE PRECISION :: iBr,iBp,iBz,eBr,eBp,eBz,idBdx(3,3),edBdx(3,3)
    DOUBLE PRECISION :: idivb,edivb,eref,iref
!    double precision, allocatable :: dive(:)
    INTEGER :: t,i,n,j,p,q
    LOGICAL :: stat

!

    ALLOCATE(Nodes%x(27),Nodes%y(27),Nodes%z(27) &
!        ,dive(CurrentModel%NumberofNodes))
        )


    iref=0
    eref=0
    vdivb=0

!    open(10)

!    dive=0

    DO t=1,CurrentModel % NumberOfBulkElements
      Element => CurrentModel % Elements(t)
      n = Element % TYPE % NumberOfNodes
      NodeIndexes => Element % NodeIndexes

      IF ( ANY(FlowPerm(NodeIndexes)==0) .OR. ANY(MagPerm(NodeIndexes)==0) &
          .OR. ANY(EMagPerm(NodeIndexes)==0) ) THEN
        CYCLE
      END IF

      Nodes % x(1:n) = CurrentModel % Nodes % x(NodeIndexes)
      Nodes % y(1:n) = CurrentModel % Nodes % y(NodeIndexes)
      Nodes % z(1:n) = CurrentModel % Nodes % z(NodeIndexes)
      
      IntegStuff = GaussPoints( Element )
      U_Integ => IntegStuff % u
      V_Integ => IntegStuff % v
      W_Integ => IntegStuff % w
      S_Integ => IntegStuff % s
      N_Integ =  IntegStuff % n

!----------------------

#if 0
      WRITE (10,*) t
      WRITE (10,*) MagPerm(NodeIndexes)
   DO p=1,n

     q = MagPerm(NodeIndexes(p))
     u = Element % TYPE % NodeU(p)
     v = Element % TYPE % NodeV(p)

     IF ( Element % TYPE % DIMENSION == 3 ) THEN
       w = Element % TYPE % NodeW(p)
     ELSE
       w = 0.0D0
     END IF

     stat = ElementInfo( Element,Nodes,u,v,w,SqrtElementMetric, &
         Basis,dBasisdx,ddBasisddx,.FALSE. )

     r = SUM(Basis(1:n)*nodes % x(1:n))

     dive(q) = dive(q) + SUM(dBasisdx(1:n,1)*Brv(MagPerm(NodeIndexes))) &
!         + SUM(dBasisdx(1:n,3)*Aphi(MagPerm(NodeIndexes))) &
         + SUM(dBasisdx(1:n,2)*Bzv(MagPerm(NodeIndexes)))

     IF (r > 1d-10) THEN
       dive(q) = dive(q) + SUM(Basis(1:n)*Brv(MagPerm(NodeIndexes)))/r
     ELSE
       dive(q) = dive(q) + SUM(dBasisdx(1:n,1)*Brv(MagPerm(NodeIndexes)))
     END IF
     WRITE (10,*) q
     WRITE (10,*) SUM(Basis(1:n)*Brv(MagPerm(NodeIndexes)))/r &
         + SUM(dBasisdx(1:n,1)*Brv(MagPerm(NodeIndexes))) &
         + SUM(dBasisdx(1:n,2)*Bzv(MagPerm(NodeIndexes)))


   END DO
!   write (10,*) SUM(Basis(1:n)*Brv(MagPerm(NodeIndexes)))
!   write (10,*) SUM(dBasisdx(1:n,1)*Brv(MagPerm(NodeIndexes)))
!   write (10,*) SUM(dBasisdx(1:n,2)*Bzv(MagPerm(NodeIndexes)))
    WRITE (10,*) 'div',dive(MagPerm(NodeIndexes))
#endif

!--------------------

      DO i=1,N_Integ

        u = U_Integ(i)
        v = V_Integ(i)
        w = W_Integ(i)
      
        stat = ElementInfo( Element,Nodes,u,v,w,SqrtElementMetric, &
            Basis,dBasisdx,ddBasisddx,.FALSE. )

        r = SUM( Basis(1:n)*nodes%x(1:n) )
        s = r * SqrtElementMetric * S_Integ(i)

        iBr = SUM(Basis(1:n)*Brv(MagPerm(NodeIndexes))) 
        eBr = SUM(Basis(1:n)*EB(3*EMagPerm(NodeIndexes)-2))
        Br = iBr + eBr

        iBp = SUM(Basis(1:n)*Bpv(MagPerm(NodeIndexes))) 
        eBp = SUM(Basis(1:n)*EB(3*EMagPerm(NodeIndexes)-0))
        Bp = iBp + eBp

        iBz = SUM(Basis(1:n)*Bzv(MagPerm(NodeIndexes))) 
        eBz = SUM(Basis(1:n)*EB(3*EMagPerm(NodeIndexes)-1))
        Bz = iBz + eBz

        Vr = SUM(Basis(1:n)*Ur(FlowPerm(NodeIndexes)))
        Vp = SUM(Basis(1:n)*Up(FlowPerm(NodeIndexes)))
        Vz = SUM(Basis(1:n)*Uz(FlowPerm(NodeIndexes)))

!        PRINT *,'---------'
!        PRINT *, Br,Bp,Bz
!        PRINT *, Vr,Vp,Vz
!        PRINT *,'---------'

        DO j=1,3
          idBdx(1,j) = SUM(dBasisdx(1:n,j)*Brv(MagPerm(NodeIndexes)))
          edBdx(1,j) = SUM(dBasisdx(1:n,j)*EB(3*EMagPerm(NodeIndexes)-2))

          idBdx(2,j) = SUM(dBasisdx(1:n,j)*Bzv(MagPerm(NodeIndexes))) 
          edBdx(2,j) = SUM(dBasisdx(1:n,j)*EB(3*EMagPerm(NodeIndexes)-1))

          idBdx(3,j) = SUM(dBasisdx(1:n,j)*Bpv(MagPerm(NodeIndexes))) 
          edBdx(3,j) = SUM(dBasisdx(1:n,j)*EB(3*EMagPerm(NodeIndexes)-0))

          dVdx(1,j) = SUM(dBasisdx(1:n,j)*Ur(FlowPerm(NodeIndexes)))
          dVdx(2,j) = SUM(dBasisdx(1:n,j)*Uz(FlowPerm(NodeIndexes)))
          dVdx(3,j) = r * SUM( dBasisdx(1:n,j)*Up(FlowPerm(NodeIndexes)))
        END DO

        dBdx = idBdx + edBdx

!        print *, '--------------'
!        print *, eBr,eBp,eBz
!        print *, iBr,iBp,iBz
!        print *, r
!        print *, '--------------'

        dVdx(3,1) = Vp + dVdx(3,1)
        Vp = r * Vp

        iref=iref+s*( &
            (dVdx(1,2)*iBz+dVdx(1,1)*iBr-Vz*idBdx(1,2)-Vr*idBdx(1,1))**2 &
            + (dVdx(3,2)*iBz+dVdx(3,1)*iBr-Vz*idBdx(3,2)-Vr*idBdx(3,1) &
            + (Vr*iBp-Vp*iBr)/r)**2 &
            + (dVdx(2,1)*iBr+iBz*dVdx(2,2)-Vz*idBdx(2,2)-Vr*idBdx(2,1))**2 )

        eref=eref+s*( &
            (dVdx(1,2)*eBz+dVdx(1,1)*eBr-Vz*edBdx(1,2)-Vr*edBdx(1,1))**2 &
            + (dVdx(3,2)*eBz+dVdx(3,1)*eBr-Vz*edBdx(3,2)-Vr*edBdx(3,1) &
            + (Vr*eBp-Vp*eBr)/r)**2 &
            + (dVdx(2,1)*eBr+eBz*dVdx(2,2)-Vz*edBdx(2,2)-Vr*edBdx(2,1))**2 )

#if 0        

eref=eref+s*( &
    +(Vp*eBz-Vz*eBp)**2+(Vr*eBz-Vz*eBr)**2+(Vr*eBp-Vp*eBr)**2)
iref=iref+s*( &
    +(Vp*iBz-Vz*iBp)**2+(Vr*iBz-Vz*iBr)**2+(Vr*iBp-Vp*iBr)**2)

#endif     
        idivb = iBr/r + idBdx(1,1) + idBdx(2,2)
        edivb = eBr/r + edBdx(1,1) + edBdx(2,2)
        divb = idivb + edivb

!        PRINT *,'idivb, edivb',idivb,edivb
        

        vdivb=vdivb+s*( (Vr**2+Vp**2+Vz**2)*idivb**2 )
!        vdivb=vdivb+s*( (Vr**2+Vz**2)*idivb**2 )

      END DO

    END DO

!    close(10)

    eref = SQRT(eref)
    iref = SQRT(iref)
    vdivb = SQRT(vdivb)

    OPEN(10,status='UNKNOWN',position='APPEND')

    WRITE(10,*)  '   '
    WRITE(10,*)  '*********************************************************'
    WRITE(10,*)  'Divcheck'
    WRITE(10,*)  eref,iref,vdivb
    WRITE(10,*)  '*********************************************************'
    WRITE(10,*)  '   '

    CLOSE(10)

!------------------------------------------------------------------------------
  END SUBROUTINE DivCheck
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
!  Compute dot product of given vectors
!------------------------------------------------------------------------------
  FUNCTION Dot( Ax,Ay,Az,Bx,By,Bz,n ) RESULT(L)
DLLEXPORT Dot
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: Ax,Ay,Az,Bx,By,Bz
    REAL(KIND=dp) :: L
!------------------------------------------------------------------------------
    INTEGER :: i,j,k,n
    REAL(KIND=dp) :: SqrtMetric,Metric(3,3),Symb(3,3,3),dSymb(3,3,3,3),x,y,z
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
!     Compute the dot product
!------------------------------------------------------------------------------
    IF ( CurrentCoordinateSystem() == Cartesian ) THEN
      L =  Ax*Bx + Ay*By + Az*Bz
    ELSE
      x = CurrentModel % Nodes % x(n)
      y = CurrentModel % Nodes % y(n)
      z = CurrentModel % Nodes % z(n)
      CALL CoordinateSystemInfo( Metric,SqrtMetric,Symb,dSymb,x,y,z )
!
!  NOTE: this is for orthogonal coordinates only
!
      L = Ax*Bx / Metric(1,1) + Ay*By / Metric(2,2) + Az*Bz / Metric(3,3)
    END IF
!------------------------------------------------------------------------------
  END FUNCTION Dot
!------------------------------------------------------------------------------

END MODULE Differentials
