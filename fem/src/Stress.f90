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
! * Module computing local matrices for stress computation (cartesian
! * coordinates, axisymmetric)
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
! * $Log: Stress.f90,v $
! * Revision 1.49  2005/04/19 08:53:48  jpr
! * Renamed module LUDecomposition as LinearAlgebra.
! *
! * Revision 1.48  2005/02/15 08:28:14  jpr
! * Cleaning up of the residual functions. Some bodyforce & bc options still
! * missing from the r-functions. Also modified the interface to LocalStress
! * to include number of dofs/element different from number of element nodal
! *  points.
! *
! * Revision 1.47  2004/12/16 11:02:07  apursula
! * Added possibility to rotate the elasticity matrix in 3d with
! * anisotropic material
! *
! * Revision 1.46  2004/10/07 12:43:56  jpr
! * *** empty log message ***
! *
! * Revision 1.45  2004/10/06 11:08:49  jpr
! * Added keyword 'Stress(n)' to sections 'Body Force', 'Boundary Condition'
! * and 'Material'. Added keyword 'Strain(n)' to sections 'Body Force' and
! * 'Material'. These keywords may be used to give stress and strain
! * engineering vectors, with following meanings:
! *
! * Body Force-section:
! * Bulk term of the partial integration of the div(Sigma)*Phi is added
! * as a body force. For divergence free Sigma this amounts to setting
! * the boundary normal stress to (Sigma,n). Given Strain is used to
! * compute Sigma.
! *
! * Material-section:
! * Stress and Strain are used as prestress and prestrains to geometric
! * stiffness and/or buckling analysis (in addition to given load case).
! *
! * Boundary Condition-section:
! * Given Stress is multiplied by normal giving the the normal stress on
! * the boundary.
! *
! * Stress and Strain keywords give the components
! * 2D:
! * Strain(3) = Eta_xx Eta_yy 2*Eta_xy
! * Stress(3) = Sigma_xx Sigma_yy Sigma_xz
! * Axi Symmetric:
! * Strain(4) = Eta_rr Eta_pp Eta_zz 2*Eta_rz
! * Stress(4) = Sigma_rr Sigma_pp Sigma_zz Sigma_rz
! * 3D:
! * Strain(6) = Eta_xx Eta_yy Eta_zz 2*Eta_xy 2*Eta_yz 2*Eta_xz
! * Stress(6) = Sigma_xx Sigma_yy Sigma_zz Sigma_xy Sigma_yz Sigma_xz
! *
! *
! * Revision 1.38  2004/03/04 13:07:27  jpr
! * Modified StressBoundary to work in axisymmetric cases.
! *
! *
! * $Id: Stress.f90,v 1.49 2005/04/19 08:53:48 jpr Exp $
! *****************************************************************************/

MODULE StressLocal

!------------------------------------------------------------------------------
  USE Integration
  USE ElementDescription

  IMPLICIT NONE

!------------------------------------------------------------------------------
  CONTAINS

!------------------------------------------------------------------------------
   SUBROUTINE StressCompose( MASS, DAMP, STIFF, FORCE, LOAD, ElasticModulus,     &
     NodalPoisson, NodalDensity, NodalDamping, PlaneStress, Isotropic,           &
     NodalPreStress, NodalPreStrain, NodalStressLoad, NodalStrainLoad,           &
     NodalHeatExpansion, NodalTemperature, Element, n, Nodes, StabilityAnalysis, &
     GeometricStiffness, NodalDisplacement, RotateC, TransformMatrix )
DLLEXPORT StressCompose
!------------------------------------------------------------------------------
     REAL(KIND=dp) :: STIFF(:,:), MASS(:,:), DAMP(:,:), FORCE(:), LOAD(:,:)
     REAL(KIND=dp) :: NodalTemperature(:),ElasticModulus(:,:,:)
     REAL(KIND=dp) :: NodalPreStress(:,:), NodalPreStrain(:,:)
     REAL(KIND=dp) :: NodalStressLoad(:,:), NodalStrainLoad(:,:)
     REAL(KIND=dp) :: NodalDisplacement(:,:), NodalHeatExpansion(:,:,:)
     REAL(KIND=dp) :: TransformMatrix(:,:)
     REAL(KIND=dp), DIMENSION(:) :: NodalPoisson, NodalDensity, NodalDamping

     LOGICAL :: PlaneStress, Isotropic, StabilityAnalysis, GeometricStiffness
     LOGICAL :: RotateC

     TYPE(Nodes_t) :: Nodes
     TYPE(Element_t) :: Element

     INTEGER :: n
!------------------------------------------------------------------------------
     REAL(KIND=dp) :: Basis(n),ddBasisddx(1,1,1)
     REAL(KIND=dp) :: dBasisdx(n,3),detJ

     REAL(KIND=dp) :: LoadAtIp(3), Poisson, Young

     REAL(KIND=dp), DIMENSION(3,3) :: A,M,D,HeatExpansion
     REAL(KIND=dp) :: Temperature,Density, C(6,6), Damping
     REAL(KIND=dp) :: StressTensor(3,3), StrainTensor(3,3), InnerProd
     REAL(KIND=dp) :: StressLoad(6), StrainLoad(6), PreStress(6), PreStrain(6)

     INTEGER :: i,j,k,l,p,q,t,dim,NBasis,ind(3)

     REAL(KIND=dp) :: s,u,v,w, Radius, B(6,3), G(3,6)

     TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff

     INTEGER :: N_Integ

     REAL(KIND=dp), DIMENSION(:), POINTER :: U_Integ,V_Integ,W_Integ,S_Integ

     LOGICAL :: stat, CSymmetry, NeedMass, NeedHeat, ActiveGeometricStiffness

!------------------------------------------------------------------------------

     dim = CoordinateSystemDimension()

     CSymmetry = .FALSE.
     CSymmetry = CSymmetry .OR. CurrentCoordinateSystem() == AxisSymmetric
     CSymmetry = CSymmetry .OR. CurrentCoordinateSystem() == CylindricSymmetric

     FORCE = 0.0D0
     STIFF = 0.0D0
     MASS  = 0.0D0
     DAMP  = 0.0D0

     NeedMass = ANY( NodalDensity(1:n) /= 0.0d0 )
     NeedMass = NeedMass .OR. ANY( NodalDamping(1:n) /= 0.0d0 )
     NeedHeat = ANY( NodalTemperature(1:n) /= 0.0d0 )
     !    
     ! Integration stuff:
     ! ------------------  
     NBasis = n
     IntegStuff = GaussPoints( element )

     U_Integ => IntegStuff % u
     V_Integ => IntegStuff % v
     W_Integ => IntegStuff % w
     S_Integ => IntegStuff % s
     N_Integ =  IntegStuff % n

     !
     ! Now we start integrating:
     ! -------------------------
     DO t=1,N_Integ
       u = U_Integ(t)
       v = V_Integ(t)
       w = W_Integ(t)
!------------------------------------------------------------------------------
!      Basis function values & derivatives at the integration point
!------------------------------------------------------------------------------
       stat = ElementInfo( Element,Nodes,u,v,w,detJ, &
                Basis,dBasisdx,ddBasisddx,.FALSE.,.FALSE. )

       s = detJ * S_Integ(t)
!------------------------------------------------------------------------------

       Density = SUM( NodalDensity(1:n)*Basis )
       Damping = SUM( NodalDamping(1:n)*Basis )
       IF ( NeedHeat ) THEN
         ! Temperature at the integration point:
         !-------------------------------------- 
         Temperature = SUM( NodalTemperature(1:n)*Basis )
 
         ! Heat expansion tensor values at the integration point:
         !-------------------------------------------------------
         HeatExpansion = 0.0d0
         DO i=1,3
           IF ( Isotropic ) THEN
              HeatExpansion(i,i) = SUM( NodalHeatExpansion(1,1,1:n)*Basis )
           ELSE
              DO j=1,3
                HeatExpansion(i,j) = SUM( NodalHeatExpansion(i,j,1:n)*Basis )
              END DO
           END IF
         END DO
       END IF

       IF ( Isotropic ) Poisson = SUM( Basis(1:n) * NodalPoisson(1:n) )

       C = 0
       IF ( .NOT. Isotropic ) THEN 
          DO i=1,SIZE(ElasticModulus,1)
            DO j=1,SIZE(ElasticModulus,2)
               C(i,j) = SUM( Basis(1:n) * ElasticModulus(i,j,1:n) )
            END DO
          END DO
       ELSE
          Young = SUM( Basis(1:n) * ElasticModulus(1,1,1:n) )
       END IF

       SELECT CASE(dim)
       CASE(2)
         IF ( CSymmetry ) THEN
           IF ( Isotropic ) THEN
              C(1,1) = 1.0d0 - Poisson
              C(1,2) = Poisson
              C(1,3) = Poisson
              C(2,1) = Poisson
              C(2,2) = 1.0d0 - Poisson
              C(2,3) = Poisson
              C(3,1) = Poisson
              C(3,2) = Poisson
              C(3,3) = 1.0d0 - Poisson
              C(4,4) = 0.5d0 - Poisson

              C = C * Young / ( (1+Poisson) * (1-2*Poisson) )
           END IF
           Radius = SUM( Nodes % x(1:n) * Basis(1:n) )
           s = s * Radius
         ELSE
           IF ( Isotropic ) THEN
              IF ( PlaneStress ) THEN
                 C(1,1) = 1.0d0
                 C(1,2) = Poisson
                 C(2,1) = Poisson
                 C(2,2) = 1.0d0
                 C(3,3) = 0.5d0*(1-Poisson)
 
                 C = C * Young / ( 1 - Poisson**2 )
              ELSE
                 C(1,1) = 1.0d0 - Poisson
                 C(1,2) = Poisson
                 C(2,1) = Poisson
                 C(2,2) = 1.0d0 - Poisson
                 C(3,3) = 0.5d0 - Poisson
                 C = C * Young / ( (1+Poisson) * (1-2*Poisson) )
              END IF
           ELSE
              IF ( PlaneStress ) THEN
                C(1,1) = C(1,1) - C(1,3)*C(3,1) / C(3,3)
                C(1,2) = C(1,2) - C(1,3)*C(2,3) / C(3,3)
                C(2,1) = C(2,1) - C(1,3)*C(2,3) / C(3,3)
                C(2,2) = C(2,2) - C(2,3)*C(3,2) / C(3,3)
              ELSE
                IF ( NeedHeat ) THEN
                  HeatExpansion(1,1) = HeatExpansion(1,1) + HeatExpansion(3,3) * &
                     ( C(2,2)*C(1,3)-C(1,2)*C(2,3) ) / ( C(1,1)*C(2,2) - C(1,2)*C(2,1) )
  
                  HeatExpansion(2,2) = HeatExpansion(2,2) + HeatExpansion(3,3) * &
                     ( C(1,1)*C(2,3)-C(1,2)*C(1,3) ) / ( C(1,1)*C(2,2) - C(1,2)*C(2,1) )
                END IF
              END IF
              C(3,3) = C(4,4)
              C(1,3) = 0.0d0
              C(3,1) = 0.0d0
              C(2,3) = 0.0d0
              C(3,2) = 0.0d0
              C(4:6,:) = 0.0d0
              C(:,4:6) = 0.0d0
           END IF
         END IF

       CASE(3)
         IF ( Isotropic ) THEN
            C = 0
            C(1,1) = 1.0d0 - Poisson
            C(1,2) = Poisson
            C(1,3) = Poisson
            C(2,1) = Poisson
            C(2,2) = 1.0d0 - Poisson
            C(2,3) = Poisson
            C(3,1) = Poisson
            C(3,2) = Poisson
            C(3,3) = 1.0d0 - Poisson
            C(4,4) = 0.5d0 - Poisson
            C(5,5) = 0.5d0 - Poisson
            C(6,6) = 0.5d0 - Poisson

            C = C * Young / ( (1+Poisson) * (1-2*Poisson) )
!--------------------------------------------------------------------------------
!   Rotate elasticity tensor if required

          ELSE
            IF ( RotateC ) THEN
                CALL RotateElasticityMatrix( C, TransformMatrix, 3 )
            END IF
          END IF

       END SELECT

       StressTensor = 0.0d0
       StrainTensor = 0.0d0
       IF ( StabilityAnalysis .OR. GeometricStiffness ) &
          CALL LocalStress( StressTensor,StrainTensor,NodalPoisson,ElasticModulus, &
          Isotropic,CSymmetry,PlaneStress,NodalDisplacement,Basis,dBasisdx,Nodes,dim,n )

       DO i=1,6
          PreStrain(i) = SUM( NodalPreStrain(i,1:n)*Basis(1:n) )
          PreStress(i) = SUM( NodalPreStress(i,1:n)*Basis(1:n) )
       END DO
       PreStress = PreStress + MATMUL( C, PreStrain  )

       DO i=1,6
          StrainLoad(i) = SUM( NodalStrainLoad(i,1:n)*Basis(1:n) )
          StressLoad(i) = SUM( NodalStressLoad(i,1:n)*Basis(1:n) )
       END DO
       StressLoad = StressLoad + MATMUL( C, StrainLoad )

       SELECT CASE(dim)
       CASE(2)
         IF ( Csymmetry ) THEN
            StressTensor(1,1) = StressTensor(1,1) + PreStress(1)
            StressTensor(2,2) = StressTensor(2,2) + PreStress(2)
            StressTensor(3,3) = StressTensor(3,3) + PreStress(3)
            StressTensor(1,2) = StressTensor(1,2) + PreStress(4)
            StressTensor(2,1) = StressTensor(2,1) + PreStress(4)
         ELSE
            StressTensor(1,1) = StressTensor(1,1) + PreStress(1)
            StressTensor(2,2) = StressTensor(2,2) + PreStress(2)
            StressTensor(1,2) = StressTensor(1,2) + PreStress(3)
            StressTensor(2,1) = StressTensor(2,1) + PreStress(3)
         END IF
       CASE(3)
          StressTensor(1,1) = StressTensor(1,1) + PreStress(1)
          StressTensor(2,2) = StressTensor(2,2) + PreStress(2)
          StressTensor(3,3) = StressTensor(3,3) + PreStress(3)
          StressTensor(1,2) = StressTensor(1,2) + PreStress(4)
          StressTensor(2,1) = StressTensor(2,1) + PreStress(4)
          StressTensor(2,3) = StressTensor(2,3) + PreStress(5)
          StressTensor(3,2) = StressTensor(3,2) + PreStress(5)
          StressTensor(1,3) = StressTensor(1,3) + PreStress(6)
          StressTensor(3,1) = StressTensor(3,1) + PreStress(6)
       END SELECT
       ActiveGeometricStiffness = ANY( StressTensor /= 0.0d0 ) 

       !
       ! Loop over basis functions (of both unknowns and weights):
       ! ---------------------------------------------------------
       A = 0.0d0
       M = 0.0d0
       D = 0.0d0
       B = 0.0d0

       DO p=1,NBasis

         G = 0.0d0
         SELECT CASE(dim)
         CASE(2)
           IF ( CSymmetry ) THEN
             G(1,1) = dBasisdx(p,1)
             G(1,3) = Basis(p) / Radius
             G(1,4) = dBasisdx(p,2)
             G(2,2) = dBasisdx(p,2)
             G(2,4) = dBasisdx(p,1)
           ELSE
             G(1,1) = dBasisdx(p,1)
             G(1,3) = dBasisdx(p,2)
             G(2,2) = dBasisdx(p,2)
             G(2,3) = dBasisdx(p,1)
           END IF

         CASE(3)
           G(1,1) = dBasisdx(p,1)
           G(2,2) = dBasisdx(p,2)
           G(3,3) = dBasisdx(p,3)
           G(1,4) = dBasisdx(p,2)
           G(2,4) = dBasisdx(p,1)
           G(2,5) = dBasisdx(p,3)
           G(3,5) = dBasisdx(p,2)
           G(1,6) = dBasisdx(p,3)
           G(3,6) = dBasisdx(p,1)
         END SELECT

         LoadatIp = 0.0d0
         DO i=1,dim
           DO j=1,6
             LoadAtIp(i) = LoadAtIp(i) + StressLoad(j) * G(i,j)
           END DO
         END DO

         G = MATMUL( G, C )

         DO q=1,NBasis
           DO i=1,dim
             M(i,i) = Density * Basis(p) * Basis(q)
             D(i,i) = Damping * Basis(p) * Basis(q)
           END DO
 
           SELECT CASE(dim)
           CASE(2)
              IF ( CSymmetry ) THEN
                 B(1,1) = dBasisdx(q,1)
                 B(2,2) = dBasisdx(q,2)
                 B(3,1) = Basis(q) / Radius
                 B(4,1) = dBasisdx(q,2)
                 B(4,2) = dBasisdx(q,1)
              ELSE
                 B(1,1) = dBasisdx(q,1)
                 B(2,2) = dBasisdx(q,2)
                 B(3,1) = dBasisdx(q,2)
                 B(3,2) = dBasisdx(q,1)
              END IF
 
           CASE(3)
              B(1,1) = dBasisdx(q,1)
              B(2,2) = dBasisdx(q,2)
              B(3,3) = dBasisdx(q,3)
              B(4,1) = dBasisdx(q,2)
              B(4,2) = dBasisdx(q,1)
              B(5,2) = dBasisdx(q,3)
              B(5,3) = dBasisdx(q,2)
              B(6,1) = dBasisdx(q,3)
              B(6,3) = dBasisdx(q,1)
           END SELECT
 
           A = MATMUL( G, B )
 
           !
           ! Add nodal matrix to element matrix:
           ! -----------------------------------
           DO i=1,dim
             DO j=1,dim
               STIFF( dim*(p-1)+i,dim*(q-1)+j ) =  &
                    STIFF( dim*(p-1)+i,dim*(q-1)+j ) + s*A(i,j)
             END DO
           END DO

           IF ( NeedMass .AND. (.NOT.StabilityAnalysis) ) THEN
              DO i=1,dim
                DO j=1,dim
                  MASS( dim*(p-1)+i,dim*(q-1)+j ) =  &
                       MASS( dim*(p-1)+i,dim*(q-1)+j ) + s*M(i,j)

                  DAMP( dim*(p-1)+i,dim*(q-1)+j ) =  &
                       DAMP( dim*(p-1)+i,dim*(q-1)+j ) + s*D(i,j)
                END DO
              END DO
           END IF
      
           IF ( ActiveGeometricStiffness ) THEN
             DO k = 1,dim
               InnerProd = 0.0d0
               DO i = 1,dim
                 DO j = 1,dim
                    InnerProd = InnerProd + &
                      dBasisdx(p,i) * dBasisdx(q,j) * StressTensor(i,j)
                 END DO
               END DO

               IF ( StabilityAnalysis ) THEN
                 MASS( dim*(p-1)+k,dim*(q-1)+k ) &
                     = MASS( dim*(p-1)+k,dim*(q-1)+k ) - s * InnerProd
               ELSE
                 STIFF( dim*(p-1)+k,dim*(q-1)+k ) &
                    = STIFF( dim*(p-1)+k,dim*(q-1)+k ) + s * InnerProd
               END IF
             END DO
           END IF
         END DO

         !
         ! The (rest of the) righthand side:
         ! ---------------------------------
         DO i=1,dim
           LoadAtIp(i) = LoadAtIp(i) + &
               SUM( LOAD(i,1:n)*Basis(1:n) ) * Basis(p) + &
               SUM( LOAD(4,1:n)*Basis(1:n) ) * dBasisdx(p,i)
         END DO

         IF ( NeedHeat ) THEN
           DO i=1,dim
             IF ( CSymmetry ) THEN
               DO j=1,3
                 LoadAtIp(i) = LoadAtIp(i) +  &
                   G(i,j) * HeatExpansion(j,j) * Temperature
               END DO
             ELSE
               DO j=1,dim
                 LoadAtIp(i) = LoadAtIp(i) + &
                   G(i,j) * HeatExpansion(j,j) * Temperature
               END DO
             END IF
           END DO
         END IF

         DO i=1,dim
           FORCE(dim*(p-1)+i) = FORCE(dim*(p-1)+i) + s*LoadAtIp(i)
         END DO
      END DO
    END DO

    DAMP  = ( DAMP  + TRANSPOSE(DAMP) )  / 2.0d0
    MASS  = ( MASS  + TRANSPOSE(MASS) )  / 2.0d0
    STIFF = ( STIFF + TRANSPOSE(STIFF) ) / 2.0d0
!------------------------------------------------------------------------------
 END SUBROUTINE StressCompose
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
 SUBROUTINE StressBoundary( STIFF,DAMP,FORCE,LOAD, NodalSpring,NodalDamp, &
             NodalBeta,NodalStress,NormalTangential,Element,n,Nodes )
DLLEXPORT StressBoundary
   USE ElementUtils
!------------------------------------------------------------------------------
   REAL(KIND=dp) :: NodalSpring(:),NodalDamp(:),NodalBeta(:),LOAD(:,:)
   TYPE(Element_t),POINTER  :: Element
   TYPE(Nodes_t)    :: Nodes
   REAL(KIND=dp) :: STIFF(:,:),DAMP(:,:),FORCE(:), NodalStress(:,:)

   INTEGER :: n
   LOGICAL :: NormalTangential
!------------------------------------------------------------------------------
   REAL(KIND=dp) :: Basis(n),ddBasisddx(1,1,1)
   REAL(KIND=dp) :: dBasisdx(n,3),detJ

   REAL(KIND=dp) :: u,v,w,s
   REAL(KIND=dp) :: LoadAtIp(3),SpringCoeff(3),DampCoeff(3),Beta,Normal(3),&
                    Tangent(3), Tangent2(3), Vect(3), Stress(3,3)
   REAL(KIND=dp), POINTER :: U_Integ(:),V_Integ(:),W_Integ(:),S_Integ(:)

   INTEGER :: i,j,t,k,l,q,p,ii,jj,dim,N_Integ

   LOGICAL :: stat, Csymm

   TYPE(GaussIntegrationPoints_t), TARGET :: IntegStuff
!------------------------------------------------------------------------------

   dim = CoordinateSystemDimension()
   Csymm = CurrentCoordinateSystem() == AxisSymmetric .OR. &
           CurrentCoordinateSystem() == CylindricSymmetric

   STIFF = 0.0d0
   DAMP  = 0.0d0
   FORCE = 0.0D0
!
!  Integration stuff
!
   IntegStuff = GaussPoints( element )
   U_Integ => IntegStuff % u
   V_Integ => IntegStuff % v
   W_Integ => IntegStuff % w
   S_Integ => IntegStuff % s
   N_Integ =  IntegStuff % n
!
!  Now we start integrating
!
   DO t=1,N_Integ
     u = U_Integ(t)
     v = V_Integ(t)
     w = W_Integ(t)

     ! Basis function values & derivatives at the integration point:
     !--------------------------------------------------------------
     stat = ElementInfo( Element, Nodes, u, v, w, detJ, &
        Basis, dBasisdx, ddBasisddx, .FALSE., .FALSE. )

     s = detJ * S_Integ(t)
     IF ( Csymm ) s = s * SUM( Nodes % x(1:n) * Basis(1:n) )

!------------------------------------------------------------------------------

     LoadAtIp = 0.0d0
     DO i=1,dim
       LoadAtIp(i) = SUM( LOAD(i,1:n)*Basis )
     END DO

     Normal = NormalVector( Element,Nodes,u,v,.TRUE. )
     LoadAtIp = LoadAtIp + SUM( NodalBeta(1:n)*Basis ) * Normal

     Stress = 0.0d0
     SELECT CASE(dim)
     CASE(2)
       Stress(1,1) = SUM( NodalStress(1,1:n)*Basis(1:n) )
       Stress(2,2) = SUM( NodalStress(2,1:n)*Basis(1:n) )
       Stress(1,2) = SUM( NodalStress(3,1:n)*Basis(1:n) )
       Stress(2,1) = SUM( NodalStress(3,1:n)*Basis(1:n) )
     CASE(3)
       Stress(1,1) = SUM( NodalStress(1,1:n)*Basis(1:n) )
       Stress(2,2) = SUM( NodalStress(2,1:n)*Basis(1:n) )
       Stress(3,3) = SUM( NodalStress(3,1:n)*Basis(1:n) )
       Stress(1,2) = SUM( NodalStress(4,1:n)*Basis(1:n) )
       Stress(2,1) = SUM( NodalStress(4,1:n)*Basis(1:n) )
       Stress(3,2) = SUM( NodalStress(5,1:n)*Basis(1:n) )
       Stress(2,3) = SUM( NodalStress(5,1:n)*Basis(1:n) )
       Stress(1,3) = SUM( NodalStress(6,1:n)*Basis(1:n) )
       Stress(3,1) = SUM( NodalStress(6,1:n)*Basis(1:n) )
     END SELECT
     LoadAtIp = LoadatIp + MATMUL( Stress, Normal )

     IF ( NormalTangential ) THEN
        SELECT CASE( Element % Type % Dimension )
        CASE(1)
           Tangent(1) =  Normal(2)
           Tangent(2) = -Normal(1)
           Tangent(3) =  0.0d0
        CASE(2)
           CALL TangentDirections( Normal, Tangent, Tangent2 ) 
        END SELECT
     END IF

     DampCoeff(1:3)   = SUM( NodalDamp(1:n)*Basis )   * Normal
     SpringCoeff(1:3) = SUM( NodalSpring(1:n)*Basis ) * Normal

     DO p=1,N
       DO q=1,N
         DO i=1,dim
           IF ( NormalTangential ) THEN
             SELECT CASE(i)
                CASE(1)
                  Vect = Normal
                CASE(2)
                  Vect = Tangent
                CASE(3)
                  Vect = Tangent2
             END SELECT

             DO ii = 1,dim
                DO jj = 1,dim
                   k = (p-1)*dim + ii
                   l = (q-1)*dim + jj
                   DAMP(k,l)  = DAMP(k,l) + s * DampCoeff(i) * &
                      Vect(ii) * Vect(jj) * Basis(q) * Basis(p)

                   STIFF(k,l) = STIFF(k,l) + s * SpringCoeff(i) * &
                      Vect(ii) * Vect(jj) * Basis(q) * Basis(p)
                END DO
              END DO
           ELSE
              k = (p-1)*dim + i
              l = (q-1)*dim + i

              DAMP(k,l)  = DAMP(k,l)  + s * DampCoeff(i) * Basis(q) * Basis(p)
              STIFF(k,l) = STIFF(k,l) + s * SpringCoeff(i) * Basis(q) * Basis(p)
           END IF
         END DO
       END DO
     END DO

     DO q=1,N
       DO i=1,dim
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
               k = (q-1)*dim + j
               FORCE(k) = FORCE(k) + &
                   s * Basis(q) * LoadAtIp(i) * Vect(j)
            END DO
         ELSE
            k = (q-1)*dim + i
            FORCE(k) = FORCE(k) + s * Basis(q) * LoadAtIp(i)
         END IF
       END DO
     END DO
   END DO
!------------------------------------------------------------------------------
 END SUBROUTINE StressBoundary
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
 SUBROUTINE LocalStress( Stress, Strain, PoissonRatio, ElasticModulus, &
      Isotropic, CSymmetry, PlaneStress, NodalDisp, Basis, dBasisdx,   &
      Nodes, dim, n, nBasis )
!------------------------------------------------------------------------------
     LOGICAL :: Isotropic, CSymmetry, PlaneStress
     INTEGER :: n,nd,dim
     INTEGER, OPTIONAL :: nBasis
     TYPE(Nodes_t) :: Nodes
     REAL(KIND=dp) :: Stress(:,:), Strain(:,:), ElasticModulus(:,:,:)
     REAL(KIND=dp) :: Basis(:), dBasisdx(:,:), PoissonRatio(:), NodalDisp(:,:)
!------------------------------------------------------------------------------
     INTEGER :: i,j,k,p,q,IND(9)
     REAL(KIND=dp) :: C(6,6), Young, LGrad(3,3), Poisson, S(6), Radius
!------------------------------------------------------------------------------

     Stress = 0.0d0
     Strain = 0.0d0

     nd = n
     IF ( PRESENT( nBasis ) ) nd = nBasis
!
!    Material parameters:
!    --------------------
     IF ( Isotropic ) Poisson = SUM( Basis(1:n) * PoissonRatio(1:n) )

     C = 0
     IF ( .NOT. Isotropic ) THEN 
        DO i=1,SIZE(ElasticModulus,1)
          DO j=1,SIZE(ElasticModulus,2)
             C(i,j) = SUM( Basis(1:n) * ElasticModulus(i,j,1:n) )
          END DO
        END DO
     ELSE
        Young = SUM( Basis(1:n) * ElasticModulus(1,1,1:n) )
     END IF

     SELECT CASE(dim)
     CASE(2)
       IF ( CSymmetry ) THEN
         IF ( Isotropic ) THEN
            C(1,1) = 1.0d0 - Poisson
            C(1,2) = Poisson
            C(1,3) = Poisson
            C(2,1) = Poisson
            C(2,2) = 1.0d0 - Poisson
            C(2,3) = Poisson
            C(3,1) = Poisson
            C(3,2) = Poisson
            C(3,3) = 1.0d0 - Poisson
            C(4,4) = 0.5d0 - Poisson

            C = C * Young / ( (1+Poisson) * (1-2*Poisson) )
         END IF
       ELSE
         IF ( Isotropic ) THEN
            IF ( PlaneStress ) THEN
               C(1,1) = 1.0d0
               C(1,2) = Poisson
               C(2,1) = Poisson
               C(2,2) = 1.0d0
               C(3,3) = 0.5d0*(1-Poisson)

               C = C * Young / ( 1 - Poisson**2 )
             ELSE
               C(1,1) = 1.0d0 - Poisson
               C(1,2) = Poisson
               C(2,1) = Poisson
               C(2,2) = 1.0d0 - Poisson
               C(3,3) = 0.5d0 - Poisson

!              To compute Stress_zz afterwards....!
               C(4,1) = Poisson
               C(4,2) = Poisson

               C = C * Young / ( (1+Poisson) * (1-2*Poisson) )
            END IF
         ELSE
            IF ( PlaneStress ) THEN
               C(1,1) = C(1,1) - C(1,3) * C(3,1) / C(3,3)
               C(1,2) = C(1,2) - C(1,3) * C(2,3) / C(3,3)
               C(2,1) = C(2,1) - C(2,3) * C(1,3) / C(3,3)
               C(2,2) = C(2,2) - C(2,3) * C(3,2) / C(3,3)
            ELSE
!              To compute Stress_zz afterwards....!
               C(4,1) = C(3,1)
               C(4,2) = C(3,2)
               C(4,3) = C(3,4)
            END IF
            C(3,3) = C(4,4)
            C(1,3) = 0; C(3,1) = 0
            C(2,3) = 0; C(3,2) = 0
         END IF
       END IF

     CASE(3)
       IF ( Isotropic ) THEN
          C = 0
          C(1,1) = 1.0d0 - Poisson
          C(1,2) = Poisson
          C(1,3) = Poisson
          C(2,1) = Poisson
          C(2,2) = 1.0d0 - Poisson
          C(2,3) = Poisson
          C(3,1) = Poisson
          C(3,2) = Poisson
          C(3,3) = 1.0d0 - Poisson
          C(4,4) = 0.5d0 - Poisson
          C(5,5) = 0.5d0 - Poisson
          C(6,6) = 0.5d0 - Poisson

          C = C * Young / ( (1+Poisson) * (1-2*Poisson) )
       END IF
     END SELECT
!
!    Compute strain: 
!    ---------------
     LGrad = MATMUL( NodalDisp(:,1:nd), dBasisdx(1:nd,:) )
     Strain = ( LGrad + TRANSPOSE(LGrad) ) / 2

     IF ( CSymmetry ) THEN
       Strain(1,3) = 0.0d0
       Strain(2,3) = 0.0d0
       Strain(3,1) = 0.0d0
       Strain(3,2) = 0.0d0
       Strain(3,3) = 0.0d0

       Radius = SUM( Nodes % x(1:n) * Basis(1:n) )

       IF ( Radius > 10*AEPS ) THEN
         Strain(3,3) = SUM( NodalDisp(1,1:nd) * Basis(1:nd) ) / Radius
       END IF
     END IF

     !
     ! Compute stresses: 
     ! -----------------
     CALL Strain2Stress( Stress, Strain, C, dim, CSymmetry )

     IF ( dim==2 .AND. .NOT. CSymmetry .AND. .NOT. PlaneStress ) THEN
        S(1) = Strain(1,1)
        S(2) = Strain(2,2)
        S(3) = Strain(1,2)
        Stress(3,3) = Stress(3,3) + SUM( C(4,1:3) * S(1:3) )
     END IF
   END SUBROUTINE LocalStress
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   SUBROUTINE Strain2Stress( Stress, Strain, C, dim, CSymmetry )
!------------------------------------------------------------------------------
     REAL(KIND=dp) :: Stress(:,:), Strain(:,:), C(:,:)
     INTEGER :: dim
     LOGICAL :: CSymmetry
!------------------------------------------------------------------------------
     INTEGER :: i,j,n,p,q
     INTEGER :: i1(6), i2(6)
     REAL(KIND=dp) :: S(9), csum
!------------------------------------------------------------------------------
     S = 0.0d0
     SELECT CASE(dim)
     CASE(2)
        IF ( CSymmetry ) THEN
          n = 4
          S(1) = Strain(1,1)
          S(2) = Strain(2,2)
          S(3) = Strain(3,3)
          S(4) = Strain(1,2)*2
          i1(1:n) = (/ 1,2,3,1 /)
          i2(1:n) = (/ 1,2,3,2 /)
        ELSE
          n = 3
          S(1) = Strain(1,1)
          S(2) = Strain(2,2)
          S(3) = Strain(1,2)*2
          i1(1:n) = (/ 1,2,1 /)
          i2(1:n) = (/ 1,2,2 /)
        END IF
     CASE(3)
        n = 6
        S(1) = Strain(1,1)
        S(2) = Strain(2,2)
        S(3) = Strain(3,3)
        S(4) = Strain(1,2)*2
        S(5) = Strain(2,3)*2
        S(6) = Strain(1,3)*2
        i1(1:n) = (/ 1,2,3,1,2,1 /)
        i2(1:n) = (/ 1,2,3,2,3,3 /)
     END SELECT


     DO i=1,n
       p = i1(i)
       q = i2(i)
       csum = 0.0d0
       DO j=1,n
          csum = csum + C(i,j) * S(j)
       END DO
       Stress(p,q) = csum
       Stress(q,p) = csum
     END DO
!------------------------------------------------------------------------------
   END SUBROUTINE Strain2Stress
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   SUBROUTINE InputTensor( Tensor, IsScalar, Name, Material, n, NodeIndexes )
!------------------------------------------------------------------------------
      REAL(KIND=dp) :: Tensor(:,:,:)
      INTEGER :: n, NodeIndexes(:)
      LOGICAL :: IsScalar
      CHARACTER(LEN=*) :: Name
      TYPE(ValueList_t), POINTER :: Material
!------------------------------------------------------------------------------
      LOGICAL :: FirstTime = .TRUE., stat
      REAL(KIND=dp), POINTER :: Hwrk(:,:,:)

      INTEGER :: i,j

      SAVE FirstTime, Hwrk
!------------------------------------------------------------------------------
      IF ( FirstTime ) THEN
         NULLIFY( Hwrk )
         FirstTime = .FALSE.
      END IF

      Tensor = 0.0d0
      IsScalar = .TRUE.

      CALL ListGetRealArray( Material, Name, Hwrk, n, NodeIndexes, stat )
      IF ( .NOT. stat ) RETURN

      IsScalar = SIZE(HWrk,1) == 1 .AND. SIZE(HWrk,2) == 1

      IF ( SIZE(Hwrk,1) == 1 ) THEN
         DO i=1,MIN(6,SIZE(HWrk,2) )
            Tensor( i,i,1:n ) = Hwrk( 1,1,1:n )
         END DO
      ELSE IF ( SIZE(Hwrk,2) == 1 ) THEN
         DO i=1,MIN(6,SIZE(Hwrk,1))
            Tensor( i,i,1:n ) = Hwrk( i,1,1:n )
         END DO
      ELSE
        DO i=1,MIN(6,SIZE(Hwrk,1))
           DO j=1,MIN(6,SIZE(Hwrk,2))
              Tensor( i,j,1:n ) = Hwrk( i,j,1:n )
           END DO
        END DO
      END IF
!------------------------------------------------------------------------------
   END SUBROUTINE InputTensor
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE RotateStressVector(C,T)
!------------------------------------------------------------------------------
    IMPLICIT NONE

    REAL(KIND=dp) :: T(:,:), C(:), CT(3,3)
    INTEGER :: i,j,p,q,r,s
    INTEGER :: I1(6) = (/ 1,2,3,1,2,1 /), I2(6) = (/ 1,2,3,2,3,3 /)

    !
    ! Convert stress vector to stress tensor:
    ! ----------------------------------------
    CT = 0.0d0
    DO i=1,6
      p = I1(i)
      q = I2(i)
      CT(p,q) = C(i)
      CT(q,p) = C(i)
    END DO

    !
    ! Rotate the tensor:
    ! ------------------
    CALL Rotate2IndexTensor( CT, T, 3 )

    !
    ! Convert back to vector form:
    ! ----------------------------
    DO i=1,6
      p = I1(i)
      q = I2(i)
      C(i) = CT(p,q)
    END DO
!------------------------------------------------------------------------------
  END SUBROUTINE RotateStressVector
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE RotateStrainVector(C,T)
!------------------------------------------------------------------------------
    IMPLICIT NONE

    REAL(KIND=dp) :: T(:,:), C(:), CT(3,3)
    INTEGER :: i,j,p,q,r,s
    INTEGER :: I1(6) = (/ 1,2,3,1,2,1 /), I2(6) = (/ 1,2,3,2,3,3 /)

    !
    ! Convert strain vector to strain tensor:
    ! ---------------------------------------
    CT = 0.0d0
    C(4:6) = C(4:6)/2
    DO i=1,6
      p = I1(i)
      q = I2(i)
      CT(p,q) = C(i)
      CT(q,p) = C(i)
    END DO

    !
    ! Rotate the tensor:
    ! ------------------
    CALL Rotate2IndexTensor( CT, T, 3 )

    !
    ! Convert back to vector form:
    ! ----------------------------
    DO i=1,6
      p = I1(i)
      q = I2(i)
      C(i) = CT(p,q)
    END DO
    C(4:6) = 2*C(4:6)
!------------------------------------------------------------------------------
  END SUBROUTINE RotateStrainVector
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE RotateElasticityMatrix(C,T,dim)
!------------------------------------------------------------------------------
    INTEGER :: dim
    REAL(KIND=dp) :: T(:,:), C(:,:)
!------------------------------------------------------------------------------
    SELECT CASE(dim)
    CASE(2)
      CALL RotateElasticityMatrix2D(C,T)
    CASE(3)
      CALL RotateElasticityMatrix3D(C,T)
    END SELECT
!------------------------------------------------------------------------------
  END SUBROUTINE RotateElasticityMatrix
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE RotateElasticityMatrix2D(C,T)
!------------------------------------------------------------------------------
    IMPLICIT NONE

    REAL(KIND=dp) :: T(:,:), C(:,:), CT(2,2,2,2)
    INTEGER :: i,j,p,q,r,s
    INTEGER :: I1(3) = (/ 1,2,1 /), I2(3) = (/ 1,2,2 /)

    !
    ! Convert C-matrix to 4 index elasticity tensor:
    ! ----------------------------------------------
    CT = 0.0d0
    DO i=1,2
      p = I1(i)
      q = I2(i)
      DO j=1,2
        r = I1(j)
        s = I2(j)
        CT(p,q,r,s) = C(i,j)
        CT(p,q,s,r) = C(i,j)
        CT(q,p,r,s) = C(i,j)
        CT(q,p,s,r) = C(i,j)
      END DO
    END DO

    !
    ! Rotate the tensor:
    ! ------------------
    CALL Rotate4IndexTensor( CT, T, 2 )

    !
    ! Convert back to matrix form:
    ! ----------------------------
    DO i=1,2
      p = I1(i)
      q = I2(i)
      DO j=1,2
        r = I1(j)
        s = I2(j)
        C(i,j) = CT(p,q,r,s)
      END DO
    END DO
!------------------------------------------------------------------------------
  END SUBROUTINE RotateElasticityMatrix2D
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
  SUBROUTINE RotateElasticityMatrix3D(C,T)
!------------------------------------------------------------------------------
    IMPLICIT NONE

    REAL(KIND=dp) :: T(:,:), C(:,:), CT(3,3,3,3)
    INTEGER :: i,j,p,q,r,s
    INTEGER :: I1(6) = (/ 1,2,3,1,2,1 /), I2(6) = (/ 1,2,3,2,3,3 /)

    !
    ! Convert C-matrix to 4 index elasticity tensor:
    ! ----------------------------------------------
    CT = 0.0d0
    DO i=1,6
      p = I1(i)
      q = I2(i)
      DO j=1,6
        r = I1(j)
        s = I2(j)
        CT(p,q,r,s) = C(i,j)
        CT(p,q,s,r) = C(i,j)
        CT(q,p,r,s) = C(i,j)
        CT(q,p,s,r) = C(i,j)
      END DO
    END DO

    !
    ! Rotate the tensor:
    ! ------------------
    CALL Rotate4IndexTensor( CT, T, 3 )

    !
    ! Convert back to matrix form:
    ! ----------------------------
    DO i=1,6
      p = I1(i)
      q = I2(i)
      DO j=1,6
        r = I1(j)
        s = I2(j)
        C(i,j) = CT(p,q,r,s)
      END DO
    END DO
!------------------------------------------------------------------------------
  END SUBROUTINE RotateElasticityMatrix3D
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   SUBROUTINE Rotate2IndexTensor( C, T, dim )
!------------------------------------------------------------------------------
     INTEGER :: dim
     REAL(KIND=dp) :: C(:,:),T(:,:)
!------------------------------------------------------------------------------
     INTEGER :: i,j
     REAL(KIND=dp) :: C1(dim,dim)
!------------------------------------------------------------------------------
     C1 = 0
     DO i=1,dim
       DO j=1,dim
         C1(:,i) = C1(:,i) + T(i,j)*C(:,j)
       END DO
     END DO

     C = 0
     DO i=1,dim
       DO j=1,dim
         C(i,:) = C(i,:) + T(i,j)*C1(j,:)
       END DO
     END DO
!------------------------------------------------------------------------------
   END SUBROUTINE Rotate2IndexTensor
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   SUBROUTINE Rotate4IndexTensor( C, T, dim )
!------------------------------------------------------------------------------
     INTEGER :: dim
     REAL(KIND=dp) :: C(:,:,:,:),T(:,:)
!------------------------------------------------------------------------------
     INTEGER :: i,j
     REAL(KIND=dp) :: C1(dim,dim,dim,dim)
!------------------------------------------------------------------------------
     C1 = 0
     DO i=1,dim
       DO j=1,dim
         C1(:,:,:,i) = C1(:,:,:,i) + T(i,j)*C(:,:,:,j)
       END DO
     END DO

     C = 0
     DO i=1,dim
       DO j=1,dim
         C(:,:,i,:) = C(:,:,i,:) + T(i,j)*C1(:,:,j,:)
       END DO
     END DO

     C1 = 0
     DO i=1,dim
       DO j=1,dim
         C1(:,i,:,:) = C1(:,i,:,:) + T(i,j)*C(:,j,:,:)
       END DO
     END DO

     C = 0
     DO i=1,dim
       DO j=1,dim
         C(i,:,:,:) = C(i,:,:,:) + T(i,j)*C1(j,:,:,:)
       END DO
     END DO
!------------------------------------------------------------------------------
   END SUBROUTINE Rotate4IndexTensor
!------------------------------------------------------------------------------

END MODULE StressLocal
