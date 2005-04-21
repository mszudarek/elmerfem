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
! *  Module computing Navier-stokes local matrices (cylindrical coordinates)
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
! *                       Date: 01 Oct 1996
! *
! *                Modified by:
! *
! *       Date of modification:
! *
! *****************************************************************************/

MODULE NavierStokesCylindrical

  USE CoordinateSystems
  USE Integration
  USE Differentials
  USE MaterialModels

  IMPLICIT NONE

  CONTAINS

!------------------------------------------------------------------------------
   SUBROUTINE NavierStokesCylindricalCompose  (                             &
       MassMatrix,StiffMatrix,ForceVector,LoadVector,NodalViscosity,   &
       NodalDensity,Ux,Uy,Uz,MUx,MUy,MUz,NodalPressure,NodalTemperature, &
       Convect,StabilizeFlag,Compressible,PseudoCompressible, NodalCompressibility, &
       Porous, NodalDrag, PotentialForce, PotentialField, PotentialCoefficient, &
       NewtonLinearization,Element,n,Nodes )
DLLEXPORT NavierStokesCylindricalCompose
!------------------------------------------------------------------------------
!******************************************************************************
!
!  Return element local matrices and RSH vector for Navier-Stokes-Equations
!  (in axisymmetric, cylindric symmetric or cylindrical coordinates)
!
!  ARGUMENTS:
!
!  REAL(KIND=dp) :: MassMatrix(:,:)
!     OUTPUT: time derivative coefficient matrix
!
!  REAL(KIND=dp) :: StiffMatrix(:,:)
!     OUTPUT: rest of the equation coefficients
!
!  REAL(KIND=dp) :: ForceVector(:)
!     OUTPUT: RHS vector
!
!  REAL(KIND=dp) :: LoadVector(:)
!     INPUT:
!
!  REAL(KIND=dp) :: NodalViscosity(:)
!     INPUT: Nodal values for viscosity (i.e. if turbulence model, or
!            power-law viscosity is used, the values vary in space)
!
!  REAL(KIND=dp) :: NodalDensity(:)
!     INPUT: nodal density values
!
!  REAL(KIND=dp) :: Ux(:),Uy(:),Uz(:)
!     INPUT: Nodal values of velocity components from previous iteration
!
!  REAL(KIND=dp) :: NodalPressure(:)
!     INPUT: Nodal values of total pressure from previous iteration
!
!  LOGICAL :: Stabilize
!     INPUT: Should stabilzation be used ?
!
!  LOGICAL :: Compressible
!     INPUT: Should compressible terms be added =
!
!  LOGICAL :: PseudoCompressible
!     INPUT: Should artificial compressibility be added ?
!
!  REAL(KIND=dp) :: NodalCompressibility(:)
!     INPUT: Artificial compressibility for the nodes
!
!  LOGICAL :: NewtonLinearization
!      INPUT: Picard or Newton  linearization of the convection term ?
!
!  TYPE(Element_t) :: Element
!       INPUT: Structure describing the element (dimension,nof nodes,
!               interpolation degree, etc...)
!
!  INTEGER :: n
!       INPUT: Number  of element nodes
!
!  TYPE(Nodes_t) :: Nodes
!       INPUT: Element node coordinates
!
!******************************************************************************

     REAL(KIND=dp), DIMENSION(:,:) :: MassMatrix,StiffMatrix
     REAL(KIND=dp), DIMENSION(:)   :: ForceVector,Ux,Uy,Uz,MUx,MUy,MUz, &
                     NodalPressure(:), NodalTemperature(:)
     REAL(KIND=dp) :: NodalViscosity(:),NodalDensity(:),LoadVector(:,:), &
         NodalCompressibility(:), NodalDrag(:,:), PotentialField(:), &
         PotentialCoefficient(:)
     LOGICAL :: StabilizeFlag,Convect,NewtonLinearization,Compressible,&
         PseudoCompressible, Porous, PotentialForce

     INTEGER :: n

     TYPE(Nodes_t) :: Nodes
     TYPE(Element_t), POINTER :: Element

!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------
     REAL(KIND=dp) :: Velo(3),dVelodx(3,3),Force(4)

     REAL(KIND=dp) :: ddBasisddx(n,3,3)
     REAL(KIND=dp) :: Basis(2*n)
     REAL(KIND=dp) :: dBasisdx(2*n,3),SqrtElementMetric

     REAL(KIND=dp) :: GMetric(3,3),Metric(3),SqrtMetric,&
                            Symb(3,3,3),dSymb(3,3,3,3), Drag(3)

     REAL(KIND=dp), DIMENSION(4,4) :: A,Mass
     REAL(KIND=dp) :: Load(4),SU(n,4,4),SW(N,4,4),LrF(3)

     REAL(KIND=dp) :: Lambda=1.0,Re,Tau,Delta,x0,y0
     REAL(KIND=dp) :: VNorm,hK,mK,Viscosity,dViscositydx(3),Density
     REAL(KIND=dp) :: Pressure,Temperature,dTemperaturedx(3), &
         dDensitydx(3), Compress

     INTEGER :: i,j,k,l,m,c,p,q,t,DIM,N_Integ,NBasis

     REAL(KIND=dp) :: s,u,v,w,x,y,z
  
     REAL(KIND=dp), DIMENSION(:), POINTER :: U_Integ,V_Integ,W_Integ,S_Integ
 
     TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff

     LOGICAL :: stat,CylindricSymmetry,Stabilize,Bubbles, PBubbles

     INTEGER :: IMap(3) = (/ 1,2,4 /)
!------------------------------------------------------------------------------

     CylindricSymmetry = ( CurrentCoordinateSystem() == CylindricSymmetric .OR. &
                 CurrentCoordinateSystem() == AxisSymmetric )

     IF ( CylindricSymmetry ) THEN
       DIM = 3
     ELSE
       DIM = CoordinateSystemDimension()
     END IF
     c = DIM + 1
     N = element % TYPE % NumberOfNodes

     ForceVector = 0.0D0
     StiffMatrix = 0.0D0
     MassMatrix  = 0.0D0
     Load = 0.0D0

     NBasis    = n
     Bubbles   = .FALSE.
     Stabilize = StabilizeFlag
     IF ( .NOT.Stabilize .OR. Compressible ) THEN
       PBubbles = Element % BDOFs > 1
       IF ( PBubbles ) THEN
          NBasis  = n + Element % BDOFs
       ELSE
          NBasis  = 2 * n
          Bubbles = .TRUE.
       END IF
       Stabilize = .FALSE.
     END IF

     IF ( Bubbles ) THEN
       IntegStuff = GaussPoints( element, element % TYPE % GaussPoints2 )
     ELSE IF ( PBubbles ) THEN
       IntegStuff = GaussPoints( element, 2*NBasis )
     ELSE
       IntegStuff = GaussPoints( element )
     END IF

     U_Integ => IntegStuff % u
     V_Integ => IntegStuff % v
     W_Integ => IntegStuff % w
     S_Integ => IntegStuff % s
     N_Integ  = IntegStuff % n

!------------------------------------------------------------------------------
!    Stabilization parameter mK
!------------------------------------------------------------------------------
     IF ( Stabilize ) THEN
       hK = element % hK
       mK = element % StabilizationMK
     END IF
!
!------------------------------------------------------------------------------
!   Now we start integrating
!------------------------------------------------------------------------------
    DO t=1,N_Integ

!------------------------------------------------------------------------------
!     Integration stuff
!------------------------------------------------------------------------------
      u = U_Integ(t)
      v = V_Integ(t)
      w = W_Integ(t)
!------------------------------------------------------------------------------
!     Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
      stat = ElementInfo( Element,Nodes,u,v,w,SqrtElementMetric, &
             Basis,dBasisdx,ddBasisddx,Stabilize,Bubbles )

!------------------------------------------------------------------------------
!      Coordinatesystem dependent info
!------------------------------------------------------------------------------
      IF ( CurrentCoordinateSystem() /= Cartesian ) THEN
        x = SUM( Nodes % x(1:n) * Basis(1:n) )
        y = SUM( Nodes % y(1:n) * Basis(1:n) )
        z = SUM( Nodes % z(1:n) * Basis(1:n) )
      END IF

      CALL CoordinateSystemInfo( GMetric,SqrtMetric,Symb,dSymb,x,y,z )
      DO i=1,3
        Metric(i) = GMetric(i,i)
      END DO

      s = SqrtMetric * SqrtElementMetric * S_Integ(t)

!------------------------------------------------------------------------------
!     Density at the integration point
!------------------------------------------------------------------------------
      Density = SUM( NodalDensity(1:n)*Basis(1:n) )
      IF ( Compressible ) THEN
        Temperature = SUM( NodalTemperature(1:n)*Basis(1:n) )
        DO i=1,DIM
          dDensitydx(i)     = SUM( NodalDensity(1:n)*dBasisdx(1:n,i) )
          dTemperaturedx(i) = SUM( NodalTemperature(1:n)*dBasisdx(1:n,i) )
        END DO
! Need Pressure for transient case
        Pressure = SUM( NodalPressure(1:n)*Basis(1:n) )
      END IF
      IF(PseudoCompressible) THEN
        Pressure = SUM( NodalPressure(1:n) * Basis(1:n) )        
        Compress = Density * SUM(NodalCompressibility(1:n)*Basis(1:n))      
      END IF

!------------------------------------------------------------------------------
!     Velocity from previous iteration at the integration point
!------------------------------------------------------------------------------
      Velo    = 0.0D0
      Velo(1) = SUM( (Ux(1:n)-MUx(1:n))*Basis(1:n) )
      Velo(2) = SUM( (Uy(1:n)-MUy(1:n))*Basis(1:n) )
      IF ( DIM > 2 .AND. CurrentCoordinateSystem() /= AxisSymmetric ) THEN
        Velo(3) = SUM( (Uz(1:n)-MUz(1:n))*Basis(1:n) )
      END IF

      IF ( NewtonLinearization ) THEN
        dVelodx = 0.0D0
        DO i=1,3
          dVelodx(1,i) = SUM( Ux(1:n)*dBasisdx(1:n,i) )
          dVelodx(2,i) = SUM( Uy(1:n)*dBasisdx(1:n,i) )

          IF ( DIM > 2 .AND. CurrentCoordinateSystem() /= AxisSymmetric ) THEN
            dVelodx(3,i) = SUM( Uz(1:n)*dBasisdx(1:n,i) )
          END IF
        END DO
      END IF
!  
!------------------------------------------------------------------------------
!     Force at the integration point
!------------------------------------------------------------------------------
      Lrf = LorentzForce( Element,Nodes,u,v,w )

      Force = 0.0D0
! Use this, if the (time-averaged) Lorentz force is not divided by density
! and its phi-component is given in SI units
#ifdef LORENTZ_AVE
      Force(1) = SUM( LoadVector(1,1:n)*Basis(1:n) )/Density
      Force(2) = SUM( LoadVector(2,1:n)*Basis(1:n) )/Density
      Force(3) = SUM( LoadVector(3,1:n)*Basis(1:n) )/(Density*x)
#else
      Force(1) = SUM( LoadVector(1,1:n)*Basis(1:n) )
      Force(2) = SUM( LoadVector(2,1:n)*Basis(1:n) )
      Force(3) = SUM( LoadVector(3,1:n)*Basis(1:n) )
#endif

      IF ( DIM > 2 .AND. CurrentCoordinateSystem() /= AxisSymmetric ) THEN
        Force(1:3) = Force(1:3) + LrF / Density
        Force(4)   = SUM( LoadVector(4,1:n)*Basis(1:n) )
      ELSE
        Force(1:2) = Force(1:2) + LrF(1:2) / Density
      END IF

#if 0
!
!     NOTE: convert unit base vector, to contravariant base !
!
      DO i=1,3
        Force(i) = Force(i) * SQRT(Metric(i))
      END DO
#endif

!------------------------------------------------------------------------------
!     Additional forces due to gradient forces (electrokinetic flow) and
!     viscous drag in porous media.
!------------------------------------------------------------------------------

      IF(PotentialForce) THEN        
        Force(1) = Force(1) - SUM( PotentialCoefficient(1:n) * Basis(1:n) ) * &
            SUM(  PotentialField(1:n) * dBasisdx(1:n,1) )
        Force(2) = Force(2) - SUM( PotentialCoefficient(1:n) * Basis(1:n) ) * &
            SUM(  PotentialField(1:n) * dBasisdx(1:n,2) ) / x
        IF(DIM == 2 .AND. CurrentCoordinateSystem() /= AxisSymmetric ) THEN
          Force(3) = Force(3) - SUM( PotentialCoefficient(1:n) * Basis(1:n) ) * &
              SUM(  PotentialField(1:n) * dBasisdx(1:n,3) )
        END IF
      END IF
      
      IF(Porous) THEN
        DO i=1,DIM
          Drag(i) = SUM( NodalDrag(i,1:n) * Basis(1:n) )
        END DO
      END IF

!------------------------------------------------------------------------------
!     Effective viscosity & derivatives at integration point
!------------------------------------------------------------------------------
      Viscosity = SUM( NodalViscosity(1:n)*Basis(1:n) )
      Viscosity = EffectiveViscosity( Viscosity, Density, Ux, Uy, Uz, &
                    Element, Nodes, n, u, v, w )

!------------------------------------------------------------------------------
!      Stabilization parameters Tau & Delta
!------------------------------------------------------------------------------
     IF ( Stabilize ) THEN
!------------------------------------------------------------------------------
       DO i=1,3
         dViscositydx(i) = SUM( NodalViscosity(1:n)*dBasisdx(1:n,i) )
       END DO
!------------------------------------------------------------------------------
!      VNorm = SQRT( SUM(Velo(1:dim)**2) )
 
       IF ( Convect ) THEN
         Vnorm = 0.0D0
         DO i=1,DIM
            Vnorm = Vnorm + Velo(i) * Velo(i) / Metric(i)
         END DO
         Vnorm = MAX( SQRT( Vnorm ), 1.0d-12 )
 
         Re = MIN( 1.0D0, Density * mK * hK * VNorm / (4 * Viscosity) )

         Tau = 0.0D0
         IF ( VNorm /= 0.0D0 ) THEN
           Tau = hK * Re / (2 * Density * VNorm)
         END IF

         Delta = Density * Lambda * Re * hK * VNorm
       ELSE
         Tau = mK * hK**2 / ( 4 * Viscosity )
         Delta = 2*Viscosity / mK
       END IF

!------------------------------------------------------------------------------
!      SU will contain residual of ns-equations, SW will contain the
!      weight function terms
!------------------------------------------------------------------------------
       SU = 0.0D0
       SW = 0.0D0
       DO p=1,N
         DO i=1,DIM
           SU(p,i,c) = SU(p,i,c) + Metric(i) * dBasisdx(p,i)

           IF(Porous) THEN
             SU(p,i,i) = SU(p,i,i) + Viscosity * Drag(i) * Basis(p)
           END IF

           IF ( Convect ) THEN
           DO j=1,DIM
!
! convection
!
             SU(p,i,i) = SU(p,i,i) + Density * dBasisdx(p,j) * Velo(j)

             IF ( NewtonLinearization ) THEN
               SU(p,i,j) = SU(p,i,j) + Density * dVelodx(i,j) * Basis(p)
             END IF

             DO k =1,DIM,2
               SU(p,i,k) = SU(p,i,k) + Density * Symb(k,j,i) * Basis(p) * Velo(j)
               IF ( NewtonLinearization ) THEN
                 SU(p,i,j) = SU(p,i,j) + Density * Symb(k,j,i) * Velo(k) * Basis(p)
               END IF
             END DO

!
! diffusion
!
             SU(p,i,i) = SU(p,i,i) - Viscosity * Metric(j) * ddBasisddx(p,j,j)

             SU(p,i,i) = SU(p,i,i) - dViscositydx(j) * Metric(j) * dBasisdx(p,j)

             SU(p,i,j) = SU(p,i,j) - Viscosity * Metric(i) * ddBasisddx(p,j,i)

             SU(p,i,j) = SU(p,i,j) - dViscositydx(j) * Metric(i) * dBasisdx(p,i)
!------------------------------------------------------------------------------
           END DO
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------

           DO j=1,DIM,2
             DO l=1,DIM,2
               SU(p,i,i) = SU(p,i,i) + Viscosity * Metric(j) * Symb(j,j,l) * dBasisdx(p,l)

               SU(p,i,l) = SU(p,i,l) - Viscosity * Metric(j) * Symb(l,j,i) * dBasisdx(p,j)

               SU(p,i,l) = SU(p,i,l) - Viscosity * Metric(j) * Symb(l,j,i) * dBasisdx(p,j)

               SU(p,i,l) = SU(p,i,l) - Viscosity * Metric(j) * dSymb(l,j,i,j) * Basis(p)

               SU(p,i,j) = SU(p,i,j) + Viscosity * Metric(i) * Symb(j,i,l) * dBasisdx(p,l)

               SU(p,i,l) = SU(p,i,l) - Viscosity * Metric(i) * Symb(l,j,j) * dBasisdx(p,i)

               SU(p,i,l) = SU(p,i,l) - Viscosity * Metric(i) * Symb(l,i,j) * dBasisdx(p,j)

               SU(p,i,l) = SU(p,i,l) - Viscosity * Metric(i) * dSymb(l,j,j,i) * Basis(p)

               DO m=1,DIM,2
                 SU(p,i,l) = SU(p,i,l) - Viscosity * Metric(j) * Symb(j,m,i) * Symb(l,j,m) * Basis(p)

                 SU(p,i,l) = SU(p,i,l) + Viscosity * Metric(j) * Symb(j,j,m) * Symb(l,m,i) * Basis(p)

                 SU(p,i,l) = SU(p,i,l) - Viscosity * Metric(i) * Symb(m,i,j) * Symb(l,j,m) * Basis(p)

                 SU(p,i,l) = SU(p,i,l) + Viscosity * Metric(i) * Symb(j,i,m) * Symb(l,m,j) * Basis(p)
               END DO
             END DO
! then -mu,_j (g^{jk} U^i_,k + g^{ik} U^j_,k)
             DO l=1,DIM,2
               SU(p,i,l) = SU(p,i,l) - dViscositydx(j) * &
                 ( Metric(j) * Basis(p) * Symb(j,l,i) + Metric(i) * Basis(p) * Symb(i,l,j) )
             END DO
             
           END DO
           END IF

!------------------------------------------------------------------------------

!
!  Pressure
!
           SW(p,i,c) = SW(p,i,c) + Density * dBasisdx(p,i)

           IF ( Convect ) THEN
           DO j=1,DIM
!
!  Convection
!
             SW(p,i,i) = SW(p,i,i) + Density * dBasisdx(p,j) * Velo(j)

             DO k =1,DIM,2
               SW(p,i,k) = SW(p,i,k) - Density * Symb(i,j,k) * Basis(p) * Velo(j)
             END DO
!
!  Diffusion
!

             SW(p,i,i) = SW(p,i,i) + dViscositydx(j) * Metric(j) * dBasisdx(p,j)

             SW(p,i,i) = SW(p,i,i) + Viscosity * Metric(j) * ddBasisddx(p,j,j)

             SW(p,i,j) = SW(p,i,j) + Viscosity * Metric(j) * ddBasisddx(p,j,i)

             SW(p,i,j) = SW(p,i,j) + dViscositydx(j) * Metric(j) * dBasisdx(p,i)
!------------------------------------------------------------------------------
           END DO

           DO j=1,DIM,2
             DO l=1,DIM,2
               SW(p,i,i) = SW(p,i,i) - Viscosity * Metric(j) * Symb(j,j,l) * dBasisdx(p,l)

               SW(p,i,l) = SW(p,i,l) - Viscosity * Metric(j) * Symb(i,j,l) * dBasisdx(p,j)

               SW(p,i,l) = SW(p,i,l) - Viscosity * Metric(j) * Symb(i,j,l) * dBasisdx(p,j)

               SW(p,i,l) = SW(p,i,l) - Viscosity * Metric(j) * dSymb(i,j,l,j) * Basis(p)

               SW(p,i,j) = SW(p,i,j) - Viscosity * Metric(j) * Symb(i,j,l) * dBasisdx(p,l)

               SW(p,i,l) = SW(p,i,l) - Viscosity * Metric(j) * Symb(i,j,l) * dBasisdx(p,j)

               SW(p,i,l) = SW(p,i,l) - Viscosity * Metric(j) * Symb(j,j,l) * dBasisdx(p,i)

               SW(p,i,l) = SW(p,i,l) - Viscosity * Metric(j) * dSymb(i,j,l,j) * Basis(p)

               DO m=1,DIM,2
                 SW(p,i,l) = SW(p,i,l) + Viscosity * Metric(j) * Symb(i,j,m) * Symb(m,j,l) * Basis(p)

                 SW(p,i,l) = SW(p,i,l) + Viscosity * Metric(j) * Symb(j,j,m) * Symb(m,i,l) * Basis(p)

                 SW(p,i,l) = SW(p,i,l) + Viscosity * Metric(j) * Symb(j,j,m) * Symb(m,i,l) * Basis(p)

                 SW(p,i,l) = SW(p,i,l) + Viscosity * Metric(j) * Symb(i,j,m) * Symb(m,j,l) * Basis(p)
               END DO
             END DO
! then -mu,_j g^{jk} (w_i,_k +  w_k,_i)
             DO l=1,DIM,2
               SW(p,i,l) = SW(p,i,l) + dViscositydx(j) * &
                 ( Metric(j) * Basis(p) * Symb(i,j,l) + Metric(i) * Basis(p) * Symb(j,i,l) )
             END DO

           END DO
           END IF

           IF ( CurrentCoordinateSystem() == AxisSymmetric ) THEN
             SU(p,i,3) = 0.0D0
             SW(p,i,3) = 0.0D0
           END IF

         END DO
!------------------------------------------------------------------------------
       END DO
     END IF

!------------------------------------------------------------------------------
!    Loop over basis functions (of both unknowns and weights)
!------------------------------------------------------------------------------
     DO p=1,NBasis
     DO q=1,NBasis
!
!------------------------------------------------------------------------------
! First plain Navier-Stokes
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
!      Mass Matrix:
! -----------------------------------
!------------------------------------------------------------------------------
       Mass = 0.0D0
       DO i=1,DIM
         Mass(i,i) = Density * Basis(q) * Basis(p)
       END DO

! Continuity equation
       IF ( Compressible ) THEN
         Mass(c,c) = ( Density / Pressure ) * Basis(q) * Basis(p)
       END IF
!------------------------------------------------------------------------------

       A = 0.0
!
!------------------------------------------------------------------------------
!      Stiffness Matrix:
!------------------------------
! Possible Porous media effects
!------------------------------------------------------------------------------
       IF(Porous) THEN
         DO i=1,DIM
           A(i,i) = A(i,i) + Viscosity * Drag(i) * Basis(q) * Basis(p)
         END DO
       END IF

! -----------------------------------
!      Diffusive terms
!------------------------------------------------------------------------------
       DO i=1,DIM
         DO j = 1,DIM
           A(i,i) = A(i,i) + Viscosity * Metric(j) * dBasisdx(q,j) * dBasisdx(p,j)

           A(i,j) = A(i,j) + Viscosity * Metric(i) * dBasisdx(q,i) * dBasisdx(p,j)

           IF ( Compressible ) THEN
!------------------------------------------------------------------------------
!  For compressible flows add (2/3) \mu \nabla \cdot u
!  Partial derivative terms only here
!------------------------------------------------------------------------------
             A(i,j) = A(i,j) - (2.0d0/3.0d0) * Viscosity * Metric(i) * &
                           dBasisdx(q,j) * dBasisdx(p,i)
           END IF
         END DO
       END DO

!------------------------------------------------------------------------------
       IF ( Compressible ) THEN
!------------------------------------------------------------------------------
!  For compressible flows add (2/3) \mu \nabla \cdot u
!  Terms involving Christoffel symbols
!------------------------------------------------------------------------------
         DO i=1,DIM
           A(i,1) = A(i,1) - ( 2.0d0 /3.0d0 ) * Viscosity * Metric(i) * &
                    Basis(q) * Symb(3,1,3) * dBasisdx(p,i)
         END DO

         DO j=1,DIM
           A(1,j) = A(1,j) + ( 2.0d0 / 3.0d0 ) * Viscosity * dBasisdx(q,j) * &
                    Metric(3) * Symb(3,3,1) * Basis(p)
         END DO

         A(1,1) = A(1,1) + ( 2.0d0 / 3.0d0 ) * Viscosity * Symb(3,1,3) * &
                  Basis(q) * Metric(3) * Symb(3,3,1) * Basis(p)
       END IF
!------------------------------------------------------------------------------

       IF ( .NOT.CylindricSymmetry ) THEN
         A(1,3) = A(1,3) - 2 * Viscosity * Metric(3) * Symb(3,3,1) * Basis(p) * dBasisdx(q,3)
         A(3,1) = A(3,1) + 2 * Viscosity * Metric(3) * Symb(1,3,3) * Basis(q) * dBasisdx(p,3)
         A(3,1) = A(3,1) - 2 * Viscosity * Metric(3) * Symb(1,3,3) * Basis(p) * dBasisdx(q,3)
       END IF
       A(1,1) = A(1,1) + 2 * Viscosity * Metric(3) * Basis(q) * Basis(p)
       A(3,3) = A(3,3) - 2 * Viscosity * Symb(3,1,3) * Basis(p) * dBasisdx(q,1)


!------------------------------------------------------------------------------
!      Convection terms, Picard linearization
!------------------------------------------------------------------------------

       IF ( Convect ) THEN
          DO i = 1,dim
            DO j = 1,dim
              A(i,i) = A(i,i) + Density * dBasisdx(q,j) * Velo(j) * Basis(p)
            END DO
          END DO
          A(1,3) = A(1,3) + Density * Symb(3,3,1) * Basis(q) * Velo(3) * Basis(p)
          A(3,1) = A(3,1) + Density * Symb(1,3,3) * Basis(q) * Velo(3) * Basis(p)
          A(3,3) = A(3,3) + Density * Symb(3,1,3) * Basis(q) * Velo(1) * Basis(p)
 
!------------------------------------------------------------------------------
!      Convection terms, Newton linearization
!------------------------------------------------------------------------------
!
          IF ( NewtonLinearization ) THEN
            DO i=1,dim
              DO j=1,dim
                A(i,j) = A(i,j) + Density * dVelodx(i,j) * Basis(q) * Basis(p)
              END DO
            END DO
            A(1,3) = A(1,3) + Density * Symb(3,3,1) * Basis(q) * Velo(3) * Basis(p)
            A(3,1) = A(3,1) + Density * Symb(3,1,3) * Basis(q) * Velo(3) * Basis(p)
            A(3,3) = A(3,3) + Density * Symb(1,3,3) * Basis(q) * Velo(1) * Basis(p)
          END IF
       END IF
!
!------------------------------------------------------------------------------
!      Pressure terms
!------------------------------------------------------------------------------
!
       DO i=1,dim
         A(i,c) = A(i,c) - Metric(i) * Basis(q) * dBasisdx(p,i)
       END DO
       A(1,c) = A(1,c) + Metric(3) * Basis(q) * Symb(3,3,1) * Basis(p)  
!
!------------------------------------------------------------------------------
!      Continuity equation
!------------------------------------------------------------------------------
       DO i=1,dim
!------------------------------------------------------------------------------
         IF ( Compressible ) THEN
           A(c,c) = A(c,c) + ( Density / Pressure ) * Velo(i) * &
                        dBasisdx(q,i) * Basis(p)

           A(c,i) = A(c,i) - ( Density / Temperature ) * &
               dTemperaturedx(i) * Basis(q) * Basis(p)

           A(c,i) = A(c,i) + Density * dBasisdx(q,i) * Basis(p)
         ELSE
           A(c,i) = A(c,i) + Density * dBasisdx(q,i) * Basis(p)
         END IF
!------------------------------------------------------------------------------
       END DO

       A(c,1) = A(c,1) + Density * Symb(1,3,3) * Basis(q) * Basis(p)

!------------------------------------------------------------------------------
!      Artificial Compressibility, affects only the continuity equation
!------------------------------------------------------------------------------  

       IF(PseudoCompressible) THEN
         A(c,c) = A(c,c) + Compress * Basis(q) * Basis(p)
       END IF


!------------------------------------------------------------------------------
!      Stabilization...
!------------------------------------------------------------------------------
!
       IF ( Stabilize ) THEN
          DO i=1,dim
             DO j=1,c
                Mass(j,i) = Mass(j,i) + Tau * Density * Basis(q) * SW(p,i,j)
                DO k=1,c
                  A(j,k) = A(j,k) + Tau * SU(q,i,k) * SW(p,i,j)
                END DO
             END DO

             DO j=1,dim
                A(j,i) = A(j,i) + Delta * dBasisdx(q,i) * Metric(j) * dBasisdx(p,j)
                DO l=1,dim,2
                   A(l,i) = A(l,i) - Delta * dBasisdx(q,i) * Metric(j) * Symb(j,j,l) * Basis(p)

                   A(j,l) = A(j,l) + Delta * Symb(l,i,i) * Basis(q) * Metric(j) * dBasisdx(p,j)
                   DO m=1,dim,2
                      A(m,l) = A(m,l) - Delta * Symb(l,i,i) * Basis(q) * Metric(j) * Symb(j,j,m) * Basis(p)
                   END DO
                END DO
             END DO
          END DO
       END IF

!
!------------------------------------------------------------------------------
! Add nodal matrix to element matrix
!------------------------------------------------------------------------------
!
       IF ( CurrentCoordinateSystem() == AxisSymmetric ) THEN
         DO i=1,3
           DO j=1,3
             StiffMatrix( 3*(p-1)+i,3*(q-1)+j ) = &
                StiffMatrix( 3*(p-1)+i,3*(q-1)+j ) + s*A(IMap(i),IMap(j))

             MassMatrix(  3*(p-1)+i,3*(q-1)+j ) =  &
                MassMatrix(  3*(p-1)+i,3*(q-1)+j ) + s*Mass(IMap(i),IMap(j))
            END DO
         END DO
       ELSE
         DO i=1,c
           DO j=1,c
             StiffMatrix( c*(p-1)+i,c*(q-1)+j ) = &
                 StiffMatrix( c*(p-1)+i,c*(q-1)+j ) + s*A(i,j)

             MassMatrix(  c*(p-1)+i,c*(q-1)+j ) = &
                 MassMatrix(  c*(p-1)+i,c*(q-1)+j ) + s*Mass(i,j)
           END DO
         END DO
       END IF
 
     END DO
     END DO

!
!------------------------------------------------------------------------------
! The righthand side...
!------------------------------------------------------------------------------
!
     IF (  Convect .AND. NewtonLinearization ) THEN
       DO i=1,dim
         DO j=1,dim
           Force(i) = Force(i) + dVelodx(i,j) * Velo(j)
         END DO
       END DO

       IF ( CurrentCoordinateSystem() /= AxisSymmetric ) THEN
         Force(1) = Force(1) + Symb(3,3,1) * Velo(3) * Velo(3)
         Force(3) = Force(3) + Symb(3,1,3) * Velo(1) * Velo(3)
         Force(3) = Force(3) + Symb(1,3,3) * Velo(3) * Velo(1)
       END IF
     END IF 

     DO p=1,NBasis
       Load = 0.0d0
       DO i=1,c
         Load(i) = Load(i) + Density * Force(i) * Basis(p)
       END DO

       IF(PseudoCompressible) THEN
         Load(c) = Load(c) + Pressure * Basis(p) * Compress
       END IF

       IF ( Stabilize ) THEN
          DO i=1,DIM
            DO j=1,c
              Load(j) = Load(j) + Tau * Density * Force(i) * SW(p,i,j)
            END DO
          END DO
       END IF

       IF ( CurrentCoordinateSystem() == AxisSymmetric ) THEN
         DO i=1,3
           ForceVector(3*(p-1)+i) = ForceVector(3*(p-1)+i) + s*Load(IMap(i))
         END DO
       ELSE
         DO i=1,c
           ForceVector( c*(p-1)+i ) = ForceVector( c*(p-1)+i ) + s*Load(i)
         END DO
       END IF
     END DO

   END DO 

!------------------------------------------------------------------------------
 END SUBROUTINE NavierStokesCylindricalCompose
!------------------------------------------------------------------------------



!------------------------------------------------------------------------------
 SUBROUTINE NavierStokesCylindricalBoundary( BoundaryMatrix,BoundaryVector, &
     LoadVector,NodalAlpha,NodalBeta,NodalExtPressure,NodalSlipCoeff,NormalTangential, &
         Element,n,Nodes )
DLLEXPORT NavierStokesCylindricalBoundary
!------------------------------------------------------------------------------
!******************************************************************************
!
!  Return element local matrices and RSH vector for Navier-Stokes-equations
!  boundary conditions. (No velocity dependent velocity BC:s ("Newton BCs")
!  at the moment, so BoundaryMatrix will contain only zeros at exit...)
!
!  ARGUMENTS:
!
!  REAL(KIND=dp) :: BoundaryMatrix(:,:)
!     OUTPUT: time derivative coefficient matrix
!
!  REAL(KIND=dp) :: BoundaryVector(:)
!     OUTPUT: RHS vector
!
!  REAL(KIND=dp) :: LoadVector(:,:)
!     INPUT: Nodal values force in coordinate directions
!
!  REAL(KIND=dp) :: NodalAlpha(:,:)
!     INPUT: Nodal values of force in normal direction
!
!  REAL(KIND=dp) :: NodalBeta(:,:)
!     INPUT: Nodal values of something which will be taken derivative in
!            tangential direction and added to force...
!
!  TYPE(Element_t) :: Element
!       INPUT: Structure describing the element (dimension,nof nodes,
!               interpolation degree, etc...)
!
!  INTEGER :: n
!       INPUT: Number of boundary element nodes
!
!  TYPE(Nodes_t) :: Nodes
!       INPUT: Element node coordinates
!
!******************************************************************************
!------------------------------------------------------------------------------

   USE ElementUtils

   IMPLICIT NONE

   REAL(KIND=dp) :: BoundaryMatrix(:,:),BoundaryVector(:),LoadVector(:,:), &
                 NodalAlpha(:),NodalBeta(:),NodalSlipCoeff(:,:), NodalExtPressure(:)

   TYPE(Element_t),POINTER :: Element
   TYPE(Nodes_t)    :: Nodes

   INTEGER :: n

   LOGICAL :: NormalTangential

!------------------------------------------------------------------------------
!  Local variables
!------------------------------------------------------------------------------
   REAL(KIND=dp) :: ddBasisddx(n,3,3)
   REAL(KIND=dp) :: Basis(n)
   REAL(KIND=dp) :: dBasisdx(n,3),SqrtElementMetric

   REAL(KIND=dp) :: Metric(3,3),SqrtMetric,Symb(3,3,3),dSymb(3,3,3,3)
   REAL(KIND=dp) :: u,v,w,s,x,y,z
   REAL(KIND=dp) :: Force(4),Alpha,Normal(3),Tangent(3),Tangent2(3), Vect(3), SlipCoeff
   REAL(KIND=dp), POINTER :: U_Integ(:),V_Integ(:),W_Integ(:),S_Integ(:)

   INTEGER :: i,j,k,t,q,p,c,DIM,N_Integ

   LOGICAL :: stat

   TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff
REAL(KIND=dp) :: xx,yy,ydot,ydotdot
!------------------------------------------------------------------------------

   IF ( CurrentCoordinateSystem() == CylindricSymmetric ) THEN
     DIM = 3
   ELSE
     DIM = CoordinateSystemDimension()
   END IF
   c = DIM + 1
   n = Element % TYPE % NumberOfNodes

   BoundaryVector = 0.0D0
   BoundaryMatrix = 0.0D0
!
!------------------------------------------------------------------------------
!  Integration stuff
!------------------------------------------------------------------------------
!
   IntegStuff = GaussPoints( element )
   U_Integ => IntegStuff % u
   V_Integ => IntegStuff % v
   W_Integ => IntegStuff % w
   S_Integ => IntegStuff % s
   N_Integ =  IntegStuff % n
!
!------------------------------------------------------------------------------
!  Now we start integrating
!------------------------------------------------------------------------------
!
   DO t=1,N_Integ

     u = U_Integ(t)
     v = V_Integ(t)
     w = W_Integ(t)
!
!------------------------------------------------------------------------------
!     Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
     stat = ElementInfo( Element,Nodes,u,v,w,SqrtElementMetric, &
                Basis,dBasisdx,ddBasisddx,.FALSE. )
!
!------------------------------------------------------------------------------
!    Coordinatesystem dependent info
!------------------------------------------------------------------------------
!
     IF ( CurrentCoordinateSystem() /= Cartesian ) THEN
       x = SUM( Nodes % x(1:n) * Basis )
       y = SUM( Nodes % y(1:n) * Basis )
       z = SUM( Nodes % z(1:n) * Basis )
     END IF

     CALL CoordinateSystemInfo( Metric,SqrtMetric,Symb,dSymb,x,y,z )
     s = SqrtMetric * SqrtElementMetric * S_Integ(t)
!
!------------------------------------------------------------------------------
!    Add to load: tangetial derivative of something
!------------------------------------------------------------------------------
!
     Force = 0.0d0
     DO i=1,dim
       Force(i) = SUM( NodalBeta(1:n)*dBasisdx(1:n,i) )
     END DO

     Normal = NormalVector( Element, Nodes, u,v,.TRUE. )
     Alpha = SUM( NodalExtPressure(1:n)*Basis )
     DO i=1,dim
        Force(i) = Force(i) + Alpha * Normal(i)
     END DO
!
!------------------------------------------------------------------------------
!    Add to load: given force in normal direction
!------------------------------------------------------------------------------
!
     Alpha = SUM( NodalAlpha(1:n)*Basis )
!
!------------------------------------------------------------------------------
!    Add to load: given force in coordinate directions
!------------------------------------------------------------------------------
     DO i=1,c
        Force(i) = Force(i) + SUM( LoadVector(i,1:n)*Basis(1:n) )
     END DO


     SELECT CASE( Element % Type % Dimension )
        CASE(1)
           Tangent(1) =  Normal(2)
           Tangent(2) = -Normal(1)
           Tangent(3) =  0.0d0
        CASE(2)
           CALL TangentDirections( Normal, Tangent, Tangent2 ) 
     END SELECT

     IF ( ANY( NodalSlipCoeff(:,:) /= 0.0d0 ) ) THEN
        DO p=1,n
          DO q=1,n
            DO i=1,DIM

              SlipCoeff = SUM( NodalSlipCoeff(i,1:n) * Basis(1:n) )
              IF ( NormalTangential ) THEN
                 SELECT CASE(i)
                    CASE(1)
                      Vect = Normal
                    CASE(2)
                      Vect = Tangent
                    CASE(3)
                      Vect = Tangent2
                 END SELECT

                 DO j=1,dim
                    DO k=1,dim
                       BoundaryMatrix( (p-1)*c+j,(q-1)*c+k ) = &
                          BoundaryMatrix( (p-1)*c+j,(q-1)*c+k ) + &
                           s * SlipCoeff * Basis(q) * Basis(p) * Vect(j) * Vect(k)
                    END DO
                 END DO
              ELSE
                  BoundaryMatrix( (p-1)*c+i,(q-1)*c+i ) = &
                     BoundaryMatrix( (p-1)*c+i,(q-1)*c+i ) + &
                         s * SlipCoeff * Basis(q) * Basis(p)
              END IF
            END DO
          END DO
        END DO
     END IF

     DO q=1,N
       DO i=1,dim
          k = (q-1)*c + i
          IF ( NormalTangential ) THEN
             SELECT CASE(i)
                CASE(1)
                  Vect = Normal
                CASE(2)
                  Vect = Tangent
                CASE(3)
                  Vect = Tangent2
             END SELECT

             DO j=1,dim
                k = (q-1)*c + j
                BoundaryVector(k) = BoundaryVector(k) +  &
                             s * Basis(q) * Force(i) * Vect(j)
             END DO
          ELSE
             BoundaryVector(k) = BoundaryVector(k) + s * Basis(q) * Force(i)
          END IF
          BoundaryVector(k) = BoundaryVector(k) - s * Alpha * dBasisdx(q,i)
       END DO
       k = (q-1)*c + 1
       BoundaryVector(k) = BoundaryVector(k) - s * Alpha * Basis(q) * Symb(3,1,3)
     END DO
   END DO

!------------------------------------------------------------------------------
 END SUBROUTINE NavierStokesCylindricalBoundary
!------------------------------------------------------------------------------

END MODULE NavierStokesCylindrical
