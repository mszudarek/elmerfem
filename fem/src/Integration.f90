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
! *     Module defining Gauss integration points and
! *            containing various integration routines
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
! *       Date of modification: 26 Apr 2000
! *
! *****************************************************************************/

MODULE Integration
   USE Types

   IMPLICIT NONE

   INTEGER, PARAMETER, PRIVATE :: MAXN = 12
   INTEGER, PARAMETER, PRIVATE :: MAX_INTEGRATION_POINTS = MAXN**3

   LOGICAL, PRIVATE :: GInit = .FALSE.

!------------------------------------------------------------------------------
   TYPE GaussIntegrationPoints_t
      INTEGER :: N
      REAL(KIND=dp), POINTER :: u(:),v(:),w(:),s(:)
   END TYPE GaussIntegrationPoints_t

   TYPE(GaussIntegrationPoints_t), TARGET, PRIVATE :: IntegStuff
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
! Storage for 1d Gauss points, and weights. The values are computed on the
! fly (see ComputeGaussPoints1D below). These values are used for quads and
! bricks as well.
!------------------------------------------------------------------------------
   REAL(KIND=dp), PRIVATE :: Points(MAXN,MAXN),Weights(MAXN,MAXN)
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
! Triangle - 1 point rule; exact integration of x^py^q, p+q<=1
!------------------------------------------------------------------------------
   REAL(KIND=dp),DIMENSION(1),PRIVATE :: UTriangle1P=(/ 0.3333333333333333D0 /)
   REAL(KIND=dp),DIMENSION(1),PRIVATE :: VTriangle1P=(/ 0.3333333333333333D0 /)
   REAL(KIND=dp),DIMENSION(1),PRIVATE :: STriangle1P=(/ 1.0000000000000000D0 /)

!------------------------------------------------------------------------------
! Triangle - 3 point rule; exact integration of x^py^q, p+q<=2
!------------------------------------------------------------------------------
   REAL(KIND=dp), DIMENSION(3), PRIVATE :: UTriangle3P = &
    (/ 0.16666666666666667D0, 0.66666666666666667D0, 0.16666666666666667D0 /)

   REAL(KIND=dp), DIMENSION(3), PRIVATE :: VTriangle3P = &
    (/ 0.16666666666666667D0, 0.16666666666666667D0, 0.66666666666666667D0 /)

   REAL(KIND=dp), DIMENSION(3), PRIVATE :: STriangle3P = &
    (/ 0.33333333333333333D0, 0.33333333333333333D0, 0.33333333333333333D0 /)

!------------------------------------------------------------------------------
! Triangle - 4 point rule; exact integration of x^py^q, p+q<=3
!------------------------------------------------------------------------------
   REAL(KIND=dp), DIMENSION(4), PRIVATE :: UTriangle4P = &
         (/  0.33333333333333333D0, 0.2000000000000000D0, &
             0.60000000000000000D0, 0.20000000000000000D0 /)

   REAL(KIND=dp), DIMENSION(4), PRIVATE :: VTriangle4P = &
         (/  0.33333333333333333D0, 0.2000000000000000D0, &
             0.20000000000000000D0, 0.60000000000000000D0 /)

   REAL(KIND=dp), DIMENSION(4), PRIVATE :: STriangle4P = &
         (/ -0.56250000000000000D0, 0.52083333333333333D0, &
             0.52083333333333333D0, 0.52083333333333333D0 /)

!------------------------------------------------------------------------------
! Triangle - 6 point rule; exact integration of x^py^q, p+q<=4
!------------------------------------------------------------------------------
   REAL(KIND=dp), DIMENSION(6), PRIVATE :: UTriangle6P = &
       (/ 0.091576213509771D0, 0.816847572980459D0, 0.091576213509771D0, &
          0.445948490915965D0, 0.108103018168070D0, 0.445948490915965D0 /)

   REAL(KIND=dp), DIMENSION(6), PRIVATE :: VTriangle6P = &
        (/ 0.091576213509771D0, 0.091576213509771D0, 0.816847572980459D0, &
           0.445948490915965D0, 0.445948490915965D0, 0.108103018168070D0 /)

   REAL(KIND=dp), DIMENSION(6), PRIVATE :: STriangle6P = &
        (/ 0.109951743655322D0, 0.109951743655322D0, 0.109951743655322D0, &
           0.223381589678011D0, 0.223381589678011D0, 0.223381589678011D0 /)

!------------------------------------------------------------------------------
! Triangle - 7 point rule; exact integration of x^py^q, p+q<=5
!------------------------------------------------------------------------------
   REAL(KIND=dp), DIMENSION(7), PRIVATE :: UTriangle7P = &
        (/ 0.333333333333333D0, 0.101286507323456D0, 0.797426985353087D0, &
           0.101286507323456D0, 0.470142064105115D0, 0.059715871789770D0, &
           0.470142064105115D0 /)

   REAL(KIND=dp), DIMENSION(7), PRIVATE :: VTriangle7P = &
        (/ 0.333333333333333D0, 0.101286507323456D0, 0.101286507323456D0, &
           0.797426985353087D0, 0.470142064105115D0, 0.470142064105115D0, &
           0.059715871789770D0 /)

   REAL(KIND=dp), DIMENSION(7), PRIVATE :: STriangle7P = &
        (/ 0.225000000000000D0, 0.125939180544827D0, 0.125939180544827D0, &
           0.125939180544827D0, 0.132394152788506D0, 0.132394152788506D0, &
           0.132394152788506D0 /)

!------------------------------------------------------------------------------
! Triangle - 11 point rule; exact integration of x^py^q, p+q<=6
!------------------------------------------------------------------------------
   REAL(KIND=dp), DIMENSION(11), PRIVATE :: UTriangle11P = &
    (/ 0.3019427231413448D-01, 0.5298143569082113D-01, &
       0.4972454892773975D-01, 0.7697772693248785D-01, &
       0.7008117469890058D+00, 0.5597774797709894D+00, &
       0.5428972301980696D+00, 0.3437947421925572D+00, &
       0.2356669356664465D+00, 0.8672623210691472D+00, &
       0.2151020995173866D+00 /)

   REAL(KIND=dp), DIMENSION(11), PRIVATE :: VTriangle11P = &
    (/ 0.2559891985673773D+00, 0.1748087863744473D-01, &
       0.6330812033358987D+00, 0.8588528075577063D+00, &
       0.2708520519075563D+00, 0.1870602768957014D-01, &
       0.2027008533579804D+00, 0.5718576583152437D+00, &
       0.1000777578531811D+00, 0.4654861310422605D-01, &
       0.3929681357810497D+00 /)

   REAL(KIND=dp), DIMENSION(11), PRIVATE :: STriangle11P = &
    (/ 0.3375321205342688D-01, 0.1148426034648707D-01, &
       0.4197958777582435D-01, 0.3098130358202468D-01, &
       0.2925899761167147D-01, 0.2778515729102349D-01, &
       0.8323049608963519D-01, 0.6825761580824108D-01, &
       0.6357334991651026D-01, 0.2649352562792455D-01, &
       0.8320249389723097D-01 /)

!------------------------------------------------------------------------------
! Triangle - 12 point rule; exact integration of x^py^q, p+q<=7
!------------------------------------------------------------------------------
   REAL(KIND=dp), DIMENSION(12), PRIVATE :: UTriangle12P = &
    (/ 0.6232720494911090D+00, 0.3215024938520235D+00, &
       0.5522545665686063D-01, 0.2777161669760336D+00, &
       0.5158423343535236D+00, 0.2064414986704435D+00, &
       0.3432430294535058D-01, 0.3047265008682535D+00, &
       0.6609491961864082D+00, 0.6238226509441210D-01, &
       0.8700998678316921D+00, 0.6751786707389329D-01 /)

   REAL(KIND=dp), DIMENSION(12), PRIVATE :: VTriangle12P = &
    (/ 0.3215024938520235D+00, 0.5522545665686063D-01, &
       0.6232720494911090D+00, 0.5158423343535236D+00, &
       0.2064414986704435D+00, 0.2777161669760336D+00, &
       0.3047265008682535D+00, 0.6609491961864082D+00, &
       0.3432430294535058D-01, 0.8700998678316921D+00, &
       0.6751786707389329D-01, 0.6238226509441210D-01 /)

   REAL(KIND=dp), DIMENSION(12), PRIVATE :: STriangle12P = &
    (/ 0.4388140871440586D-01, 0.4388140871440586D-01, &
       0.4388140871440587D-01, 0.6749318700971417D-01, &
       0.6749318700971417D-01, 0.6749318700971417D-01, &
       0.2877504278510970D-01, 0.2877504278510970D-01, &
       0.2877504278510969D-01, 0.2651702815743698D-01, &
       0.2651702815743698D-01, 0.2651702815743698D-01 /)

!------------------------------------------------------------------------------
! Triangle - 17 point rule; exact integration of x^py^q, p+q<=8
!------------------------------------------------------------------------------
   REAL(KIND=dp), DIMENSION(17), PRIVATE :: UTriangle17P = &
    (/ 0.2292423642627924D+00, 0.4951220175479885D-01, &
       0.3655948407066446D+00, 0.4364350639589269D+00, &
       0.1596405673569602D+00, 0.9336507149305228D+00, &
       0.5219569066777245D+00, 0.7110782758797098D+00, &
       0.5288509041694864D+00, 0.1396967677642513D-01, &
       0.4205421906708996D-01, 0.4651359156686354D-01, &
       0.1975981349257204D+00, 0.7836841874017514D+00, &
       0.4232808751402256D-01, 0.4557097415216423D+00, &
       0.2358934246935281D+00 /)

   REAL(KIND=dp), DIMENSION(17), PRIVATE :: VTriangle17P = &
    (/ 0.5117407211006358D+00, 0.7589103637479163D+00, &
       0.1529647481767193D+00, 0.3151398735074337D-01, &
       0.5117868393288316D-01, 0.1964516824106966D-01, &
       0.2347490459725670D+00, 0.4908682577187765D-01, &
       0.4382237537321878D+00, 0.3300210677033395D-01, &
       0.2088758614636060D+00, 0.9208929246654702D+00, &
       0.2742740954674795D+00, 0.1654585179097472D+00, &
       0.4930011699833554D+00, 0.4080804967846944D+00, &
       0.7127872162741824D+00 /)

   REAL(KIND=dp), DIMENSION(17), PRIVATE :: STriangle17P = &
    (/ 0.5956595662857148D-01, 0.2813390230006461D-01, &
       0.3500735477096827D-01, 0.2438077450393263D-01, &
       0.2843374448051010D-01, 0.7822856634218779D-02, &
       0.5179111341004783D-01, 0.3134229539096806D-01, &
       0.2454951584925144D-01, 0.5371382557647114D-02, &
       0.2571565514768072D-01, 0.1045933340802507D-01, &
       0.4937780841212319D-01, 0.2824772362317584D-01, &
       0.3218881684015661D-01, 0.2522089247693226D-01, &
       0.3239087356572598D-01 /)

!------------------------------------------------------------------------------
! Triangle - 20 point rule; exact integration of x^py^q, p+q<=9
!------------------------------------------------------------------------------
   REAL(KIND=dp), DIMENSION(20), PRIVATE :: UTriangle20P = &
   (/ 0.2469118866487856D-01, 0.3348782965514246D-00, &
      0.4162560937597861D-00, 0.1832492889417431D-00, &
      0.2183952668281443D-00, 0.4523362527443628D-01, &
      0.4872975112073226D-00, 0.7470127381316580D-00, &
      0.7390287107520658D-00, 0.3452260444515281D-01, &
      0.4946745467572288D-00, 0.3747439678780460D-01, &
      0.2257524791528391D-00, 0.9107964437563798D-00, &
      0.4254445629399445D-00, 0.1332215072275240D-00, &
      0.5002480151788234D-00, 0.4411517722238269D-01, &
      0.1858526744057914D-00, 0.6300024376672695D-00 /)

   REAL(KIND=dp), DIMENSION(20), PRIVATE :: VTriangle20P = &
   (/ 0.4783451248176442D-00, 0.3373844236168988D-00, &
      0.1244378463254732D-00, 0.6365569723648120D-00, &
      0.3899759363237886D-01, 0.9093437140096456D-00, &
      0.1968266037596590D-01, 0.2191311129347709D-00, &
      0.3833588560240875D-01, 0.7389795063475102D-00, &
      0.4800989285800525D-00, 0.2175137165318176D-00, &
      0.7404716820879975D-00, 0.4413531509926682D-01, &
      0.4431292142978816D-00, 0.4440953593652837D-00, &
      0.1430831401051367D-00, 0.4392970158411878D-01, &
      0.1973209364545017D-00, 0.1979381059170009D-00 /)

   REAL(KIND=dp), DIMENSION(20), PRIVATE :: STriangle20P = &
   (/ 0.1776913091122958D-01, 0.4667544936904065D-01, &
      0.2965283331432967D-01, 0.3880447634997608D-01, &
      0.2251511457011248D-01, 0.1314162394636178D-01, &
      0.1560341736610505D-01, 0.1967065434689744D-01, &
      0.2247962849501080D-01, 0.2087108394969067D-01, &
      0.1787661200700672D-01, 0.2147695865607915D-01, &
      0.2040998247303970D-01, 0.1270342300533680D-01, &
      0.3688713099356314D-01, 0.3813199811535777D-01, &
      0.1508642325812160D-01, 0.1238422287692121D-01, &
      0.3995072336992735D-01, 0.3790911262589247D-01 /)

!------------------------------------------------------------------------------
! Tetrahedron - 1 point rule; exact integration of x^py^qz^r, p+q+r<=1
!------------------------------------------------------------------------------
   REAL(KIND=dp), DIMENSION(1), PRIVATE :: UTetra1P = (/ 0.25D0 /)
   REAL(KIND=dp), DIMENSION(1), PRIVATE :: VTetra1P = (/ 0.25D0 /)
   REAL(KIND=dp), DIMENSION(1), PRIVATE :: WTetra1P = (/ 0.25D0 /)
   REAL(KIND=dp), DIMENSION(1), PRIVATE :: STetra1P = (/ 1.00D0 /)

!------------------------------------------------------------------------------
! Tetrahedron - 4 point rule; exact integration of x^py^qz^r, p+q+r<=2
!------------------------------------------------------------------------------
   REAL(KIND=dp), DIMENSION(4), PRIVATE :: UTetra4P = &
    (/ 0.1757281246520584D0, 0.2445310270213291D0, &
       0.5556470949048655D0, 0.0240937534217468D0 /)

   REAL(KIND=dp), DIMENSION(4), PRIVATE :: VTetra4P = &
    (/ 0.5656137776620919D0, 0.0501800797762026D0, &
       0.1487681308666864D0, 0.2354380116950194D0 /)

   REAL(KIND=dp), DIMENSION(4), PRIVATE :: WTetra4P = &
    (/ 0.2180665126782654D0, 0.5635595064952189D0, &
       0.0350112499848832D0, 0.1833627308416330D0 /)

   REAL(KIND=dp), DIMENSION(4), PRIVATE :: STetra4P = &
    (/ 0.2500000000000000D0, 0.2500000000000000D0, &
       0.2500000000000000D0, 0.2500000000000000D0 /)
!------------------------------------------------------------------------------
! Tetrahedron - 5 point rule; exact integration of x^py^qz^r, p+q+r<=3
!------------------------------------------------------------------------------
   REAL(KIND=dp), DIMENSION(5), PRIVATE :: UTetra5P =  &
    (/ 0.25000000000000000D0, 0.50000000000000000D0, &
       0.16666666666666667D0, 0.16666666666666667D0, &
       0.16666666666666667D0 /)

   REAL(KIND=dp), DIMENSION(5), PRIVATE :: VTetra5P =  &
    (/ 0.25000000000000000D0, 0.16666666666666667D0, &
       0.50000000000000000D0, 0.16666666666666667D0, &
       0.16666666666666667D0 /)

   REAL(KIND=dp), DIMENSION(5), PRIVATE :: WTetra5P =  &
    (/ 0.25000000000000000D0, 0.16666666666666667D0, &
       0.16666666666666667D0, 0.50000000000000000D0, &
       0.16666666666666667D0 /)

   REAL(KIND=dp), DIMENSION(5), PRIVATE :: STetra5P =  &
    (/-0.80000000000000000D0, 0.45000000000000000D0, &
       0.45000000000000000D0, 0.45000000000000000D0, &
       0.45000000000000000D0 /)
!------------------------------------------------------------------------------
! Tetrahedron - 11 point rule; exact integration of x^py^qz^r, p+q+r<=4
!------------------------------------------------------------------------------
   REAL(KIND=dp), DIMENSION(11), PRIVATE :: UTetra11P =  &
    (/ 0.3247902050850455D+00, 0.4381969657060433D+00, &
       0.8992592373310454D-01, 0.1092714936292849D+00, &
       0.3389119319942253D-01, 0.5332363613904868D-01, &
       0.1935618747806815D+00, 0.4016250624424964D-01, &
       0.3878132182319405D+00, 0.7321489692875428D+00, &
       0.8066342495294049D-01 /)

   REAL(KIND=dp), DIMENSION(11), PRIVATE :: VTetra11P =  &
    (/ 0.4573830181783998D+00, 0.9635325047480842D-01, &
       0.3499588148445295D+00, 0.1228957438582778D+00, &
       0.4736224692062527D-01, 0.4450376952468180D+00, &
       0.2165626476982170D+00, 0.8033385922433729D+00, &
       0.7030897281814283D-01, 0.1097836536360084D+00, &
       0.1018859284267242D-01 /)

   REAL(KIND=dp), DIMENSION(11), PRIVATE :: WTetra11P =  &
    (/ 0.1116787541193331D+00, 0.6966288385119494D-01, &
       0.5810783971325720D-01, 0.3424607753785182D+00, &
       0.7831772466208499D+00, 0.3688112094344830D+00, &
       0.5872345323698884D+00, 0.6178518963560731D-01, &
       0.4077342860913465D+00, 0.9607290317342082D-01, &
       0.8343823045787845D-01 /)

   REAL(KIND=dp), DIMENSION(11), PRIVATE :: STetra11P =  &
    (/ 0.1677896627448221D+00, 0.1128697325878004D+00, &
       0.1026246621329828D+00, 0.1583002576888426D+00, &
       0.3847841737508437D-01, 0.1061709382037234D+00, &
       0.5458124994014422D-01, 0.3684475128738168D-01, &
       0.1239234851349682D+00, 0.6832098141300300D-01, &
       0.3009586149124714D-01 /)
!------------------------------------------------------------------------------

 CONTAINS

!------------------------------------------------------------------------------
   SUBROUTINE ComputeGaussPoints1D( Points,Weights,n )
!------------------------------------------------------------------------------
! Subroutine to compute gaussian integration points and weights in [-1,1]
! as roots of Legendre polynomials.
!------------------------------------------------------------------------------
     INTEGER :: n
     REAL(KIND=dp) :: Points(n),Weights(n)
!------------------------------------------------------------------------------
     REAL(KIND=dp)   :: A(n/2,n/2),s,x,Work(8*n)
     COMPLEX(KIND=dp) :: Eigs(n/2)
     REAL(KIND=dp)   :: P(n+1),Q(n),P0(n),P1(n+1)
     INTEGER :: i,j,k,np,info
!------------------------------------------------------------------------------
! One point is trivial
!------------------------------------------------------------------------------
     IF ( n <= 1 ) THEN
       Points(1)  = 0.0d0
       Weights(1) = 2.0d0
       RETURN
     END IF
!------------------------------------------------------------------------------
! Compute coefficients of n:th Legendre polynomial from the recurrence:
!
! (i+1)P_{i+1}(x) = (2i+1)*x*P_i(x) - i*P_{i-1}(x), P_{0} = 1; P_{1} = x;
!
! CAVEAT: Computed coefficients inaccurate for n > ~15
!------------------------------------------------------------------------------
     P = 0
     P0(1) = 1
     P1(1) = 1
     P1(2) = 0

     DO i=1,n-1
       P(1:i+1) = (2*i+1) * P1(1:i+1)  / (i+1)
       P(3:i+2) = P(3:i+2) - i*P0(1:i) / (i+1)
       P0(1:i+1) = P1(1:i+1); P1(1:i+2) = P(1:i+2)
     END DO
!------------------------------------------------------------------------------
! Odd n implicates zero as one of the roots...
!------------------------------------------------------------------------------
     np = n - MOD(n,2)
!------------------------------------------------------------------------------
!  Variable substitution: y=x^2
!------------------------------------------------------------------------------
     np = np / 2
     DO i=1,np+1
       P(i) = P(2*i-1)
     END DO
!------------------------------------------------------------------------------
! Solve the roots of the polynomial by forming a matrix whose characteristic
! polynomial is the n:th Legendre polynomial and solving for the eigenvalues.
! Dunno if this is a very good method....
!------------------------------------------------------------------------------
     A=0
     DO i=1,np-1
       A(i,i+1) = 1
     END DO

     DO i=1,np
       A(np,i) = -P(np+2-i) / P(1)
     END DO

     CALL DGEEV( 'N','N',np,A,n/2,Points,P0,Work,1,Work,1,Work,8*n,info )
!------------------------------------------------------------------------------
     DO i=1,np
       s = EvalPoly( np,P,Points(i) )
       IF ( ABS(s) > 3.0d-12 ) THEN
         CALL Warn( 'ComputeGaussPoints1D', &
                 '-------------------------------------------------------' )
         CALL Warn( 'ComputeGaussPoints1D', 'Computed integration point' )
         CALL Warn( 'ComputeGaussPoints1D', 'seems to be inaccurate: ' )
         WRITE( Message, * ) 'Points req.: ',n
         CALL Warn( 'ComputeGaussPoints1D', Message )
         WRITE( Message, * ) 'Residual: ',s
         CALL Warn( 'ComputeGaussPoints1D', Message )
         WRITE( Message, * ) 'Point: +-', SQRT(Points(i))
         CALL Warn( 'ComputeGaussPoints1D', Message )
         CALL Warn( 'ComputeGaussPoints1D', &
                 '-------------------------------------------------------' )
       END IF
     END DO
!------------------------------------------------------------------------------
! Backsubstitute from y=x^2
!------------------------------------------------------------------------------
     Q(1:np+1) = P(1:np+1)
     P = 0
     DO i=1,np+1
       P(2*i-1) = Q(i)
     END DO

     Q(1:np) = Points(1:np)
     DO i=1,np
       Points(2*i-1) = +SQRT( Q(i) )
       Points(2*i)   = -SQRT( Q(i) )
     END DO
     IF ( MOD(n,2) == 1 ) Points(n) = 0.0d0

     CALL DerivPoly( n,Q,P )
     CALL RefineRoots( n,P,Q,Points )
!------------------------------------------------------------------------------
! Finally, the integration weights equal to
!
! W_i = 2/( (1-x_i^2)*Q(x_i)^2 ), x_i is the i:th root, and Q(x) = dP(x) / dx
!------------------------------------------------------------------------------
     CALL DerivPoly( n,Q,P )

     DO i=1,n
       s = EvalPoly( n-1,Q,Points(i) )
       Weights(i) = 2 / ((1-Points(i)**2)*s**2);
     END DO
!------------------------------------------------------------------------------
! ... make really sure the weights add up:
!------------------------------------------------------------------------------
     Weights(1:n) = 2 * Weights(1:n) / SUM(Weights(1:n))

CONTAINS

!--------------------------------------------------------------------------

   FUNCTION EvalPoly( n,P,x ) RESULT(s)
     INTEGER :: i,n
     REAL(KIND=dp) :: P(n+1),x,s
 
     s = 0.0d0
     DO i=1,n+1
       s = s * x + P(i)
     END DO
   END FUNCTION EvalPoly

!--------------------------------------------------------------------------

   SUBROUTINE DerivPoly( n,Q,P )
     INTEGER :: i,n
     REAL(KIND=dp) :: Q(n),P(n+1)
 
     DO i=1,n
       Q(i) = P(i)*(n-i+1)
     END DO
   END SUBROUTINE DerivPoly
 
!--------------------------------------------------------------------------

   SUBROUTINE RefineRoots( n,P,Q,Points )
     INTEGER :: i,j,n
     REAL(KIND=dp) :: P(n+1),Q(n),Points(n)
 
     REAL(KIND=dp) :: x,s
     INTEGER, PARAMETER :: MaxIter = 400

     DO i=1,n
       x = Points(i)
       DO j=1,MaxIter
         s = EvalPoly(n,P,x) / EvalPoly(n-1,Q,x)
         x = x - s
         IF ( ABS(s) <= ABS(x)*EPSILON(s) ) EXIT
       END DO
       IF ( ABS(EvalPoly(n,P,x))<ABS(EvalPoly(n,P,Points(i))) ) THEN
         IF ( ABS(x-Points(i))<1.0d-8 ) Points(i) = x
       END IF
     END DO
   END SUBROUTINE RefineRoots

!--------------------------------------------------------------------------
 END SUBROUTINE ComputeGaussPoints1D
!--------------------------------------------------------------------------

!------------------------------------------------------------------------------
   SUBROUTINE GaussPointsInit
!------------------------------------------------------------------------------
     INTEGER :: n,istat

     ALLOCATE( IntegStuff % u(MAX_INTEGRATION_POINTS),STAT=istat ) 
     ALLOCATE( IntegStuff % v(MAX_INTEGRATION_POINTS),STAT=istat ) 
     ALLOCATE( IntegStuff % w(MAX_INTEGRATION_POINTS),STAT=istat ) 
     ALLOCATE( IntegStuff % s(MAX_INTEGRATION_POINTS),STAT=istat ) 

     IF ( istat /= 0 ) THEN
       CALL Fatal( 'GaussPointsInit', 'Memory allocation error.' )
       STOP
     END IF

     DO n=1,MAXN
       CALL ComputeGaussPoints1D( Points(1:n,n),Weights(1:n,n),n )
     END DO

!    IntegStuff % u = 0.0d0
!    IntegStuff % v = 0.0d0
!    IntegStuff % w = 0.0d0
!    IntegStuff % s = 0.0d0
!    IntegStuff % n = 0
     GInit = .TRUE.
!------------------------------------------------------------------------------
  END SUBROUTINE GaussPointsInit
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   FUNCTION GaussPoints0D( n ) RESULT(p)
DLLEXPORT GaussPoints0D
!------------------------------------------------------------------------------
      INTEGER :: n
      TYPE(GaussIntegrationPoints_t), POINTER :: p

      IF ( .NOT. GInit ) CALL GaussPointsInit
      p => IntegStuff
      p % n = 1
      p % u(1) = 0
      p % v(1) = 0
      p % w(1) = 0
      p % s(1) = 1
!------------------------------------------------------------------------------
   END FUNCTION GaussPoints0D
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   FUNCTION GaussPoints1D( n ) RESULT(p)
DLLEXPORT GaussPoints1D
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Return gaussian integration points for 1D line element
!
!  ARGUMENTS:
!
!    INTEGER :: n
!      INPUT: number of points in the requested rule
!
!******************************************************************************
!------------------------------------------------------------------------------

      INTEGER :: n
      TYPE(GaussIntegrationPoints_t), POINTER :: p

      IF ( .NOT. GInit ) CALL GaussPointsInit
      p => IntegStuff

      IF ( n < 1 .OR. n > MAXN ) THEN
        p % n = 0
        WRITE( Message, * ) 'Invalid number of points: ',n
        CALL Error( 'GaussPoints1D', Message )
        RETURN
      END IF

      p % n = n
      p % u(1:n) = Points(1:n,n)
      p % v(1:n) = 0.0d0
      p % w(1:n) = 0.0d0
      p % s(1:n) = Weights(1:n,n)
!------------------------------------------------------------------------------
   END FUNCTION GaussPoints1D
!------------------------------------------------------------------------------

   FUNCTION GaussPointsPTriangle(n) RESULT(p)
DLLEXPORT GaussPointPTriangle

      INTEGER :: i,n
      TYPE(GaussIntegrationPoints_t), POINTER :: p
      REAL (KIND=dp) :: uq, vq, sq

      IF ( .NOT. GInit ) CALL GaussPointsInit
      p => IntegStuff

      ! Construct gauss points for p (barycentric) triangle from 
      ! gauss points for quadrilateral
      p = GaussPointsQuad( n )
      
      ! For each point apply mapping from quad to triangle and 
      ! multiply weight by detJ of mapping
      DO i=1,p % n  
         uq = p % u(i) 
         vq = p % v(i) 
         sq = p % s(i)
         p % u(i) = 1d0/2*(uq-uq*vq)
         p % v(i) = SQRT(3d0)/2*(1d0+vq)
         p % s(i) = -SQRT(3d0)/4*(-1+vq)*sq
      END DO
      
      p % w(1:n) = 0.0d0
    END FUNCTION GaussPointsPTriangle

!------------------------------------------------------------------------------
   FUNCTION GaussPointsTriangle( n ) RESULT(p)
DLLEXPORT GaussPointsTriangle
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Return gaussian integration points for 2D triangle element
!
!  ARGUMENTS:
!
!    INTEGER :: n
!      INPUT: number of points in the requested rule
!
!******************************************************************************
!------------------------------------------------------------------------------

      INTEGER :: i,n
      TYPE(GaussIntegrationPoints_t), POINTER :: p

      IF ( .NOT. GInit ) CALL GaussPointsInit
      p => IntegStuff

      SELECT CASE (n)
      CASE (1)
         p % u(1:n) = UTriangle1P
         p % v(1:n) = VTriangle1P
         p % s(1:n) = STriangle1P / 2.0D0
         p % n = 1
      CASE (3)
         p % u(1:n) = UTriangle3P
         p % v(1:n) = VTriangle3P
         p % s(1:n) = STriangle3P / 2.0D0
         p % n = 3
      CASE (4)
         p % u(1:n) = UTriangle4P
         p % v(1:n) = VTriangle4P
         p % s(1:n) = STriangle4P / 2.0D0
         p % n = 4
      CASE (6)
         p % u(1:n) = UTriangle6P
         p % v(1:n) = VTriangle6P
         p % s(1:n) = STriangle6P / 2.0D0
         p % n = 6
      CASE (7)
         p % u(1:n) = UTriangle7P
         p % v(1:n) = VTriangle7P
         p % s(1:n) = STriangle7P / 2.0D0
         p % n = 7
      CASE (11)
         p % u(1:n) = UTriangle11P
         p % v(1:n) = VTriangle11P
         p % s(1:n) = STriangle11P
         p % n = 11
      CASE (12)
         p % u(1:n) = UTriangle12P
         p % v(1:n) = VTriangle12P
         p % s(1:n) = STriangle12P
         p % n = 12
      CASE (17)
         p % u(1:n) = UTriangle17P
         p % v(1:n) = VTriangle17P
         p % s(1:n) = STriangle17P
         p % n = 17
      CASE (20)
         p % u(1:n) = UTriangle20P
         p % v(1:n) = VTriangle20P
         p % s(1:n) = STriangle20P
         p % n = 20
      CASE DEFAULT
!        CALL Error( 'GaussPointsTriangle', 'Invalid number of points requested' )
!        p % n = 0

         p = GaussPointsQuad( n )
         DO i=1,p % n
            p % v(i) = (p % v(i) + 1) / 2
            p % u(i) = (p % u(i) + 1) / 2 * (1 - p % v(i))
            p % s(i) = p % s(i) * ( 1 - p % v(i) )
         END DO
         p % s(1:p % n) = 0.5d0 * p % s(1:p % n) / SUM( p % s(1:p % n) )
      END SELECT
      p % w(1:n) = 0.0d0
!------------------------------------------------------------------------------
   END FUNCTION GaussPointsTriangle
!------------------------------------------------------------------------------

   FUNCTION GaussPointsPTetra(np) RESULT(p)
DLLEXPORT GaussPointsPTetra

   INTEGER :: i,np,n
   TYPE(GaussIntegrationPoints_t), POINTER :: p
   REAL(KIND=dp) :: uh, vh, wh, sh
   
   IF ( .NOT. GInit ) CALL GaussPointsInit
   p => IntegStuff

   n = DBLE(np)**(1.0D0/3.0D0) + 0.5D0

   ! Get gauss points of p brick 
   ! (take into account term z^2) from jacobian determinant
   p = GaussPointsPBrick(n,n,n+1)
   ! p = GaussPointsBrick( np )
   ! WRITE (*,*) 'Getting gauss points for: ', n, p % n

   ! For each point apply mapping from brick to 
   ! tetrahedron and multiply each weight by detJ 
   ! of mapping
   DO i=1,p % n
      uh = p % u(i)
      vh = p % v(i)
      wh = p % w(i)
      sh = p % s(i)

      p % u(i)= 1d0/4*(uh - uh*vh - uh*wh + uh*vh*wh)
      p % v(i)= SQRT(3d0)/4*(5d0/3 + vh - wh/3 - vh*wh)
      p % w(i)= SQRT(6d0)/3*(1d0 + wh)
      p % s(i)= -sh * SQRT(2d0)/16 * (1d0 - vh - wh + vh*wh) * (-1d0 + wh)
   END DO
END FUNCTION GaussPointsPTetra

!------------------------------------------------------------------------------
   FUNCTION GaussPointsTetra( n ) RESULT(p)
DLLEXPORT GaussPointsTetra
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Return gaussian integration points for 3D tetra element
!
!  ARGUMENTS:
!
!    INTEGER :: n
!      INPUT: number of points in the requested rule
!
!******************************************************************************

      INTEGER :: i,n
      TYPE(GaussIntegrationPoints_t), POINTER :: p

      REAL( KIND=dp ) :: ScaleFactor

      IF ( .NOT. GInit ) CALL GaussPointsInit
      p => IntegStuff

      SELECT CASE (n)
      CASE (1)
         p % u(1:n) = UTetra1P
         p % v(1:n) = VTetra1P
         p % w(1:n) = WTetra1P
         p % s(1:n) = STetra1P / 6.0D0
         p % n = 1
      CASE (4)
         p % u(1:n) = UTetra4P
         p % v(1:n) = VTetra4P
         p % w(1:n) = WTetra4P
         p % s(1:n) = STetra4P / 6.0D0
         p % n = 4
      CASE (5)
         p % u(1:n) = UTetra5P
         p % v(1:n) = VTetra5P
         p % w(1:n) = WTetra5P
         p % s(1:n) = STetra5P / 6.0D0
         p % n = 5
      CASE (11)
         p % u(1:n) = UTetra11P
         p % v(1:n) = VTetra11P
         p % w(1:n) = WTetra11P
         p % s(1:n) = STetra11P / 6.0D0
         p % n = 11
      CASE DEFAULT
!        CALL Error( 'GaussPointsTetra', 'Invalid number of points requested.' )
!        p % n = 0
         p = GaussPointsBrick( n )

         DO i=1,p % n
            ScaleFactor = 0.5d0
            p % u(i) = ( p % u(i) + 1 ) * Scalefactor
            p % v(i) = ( p % v(i) + 1 ) * ScaleFactor
            p % w(i) = ( p % w(i) + 1 ) * ScaleFactor
            p % s(i) = p % s(i) * ScaleFactor**3

            ScaleFactor = 1.0d0 - p % w(i)
            p % u(i) = p % u(i) * ScaleFactor
            p % v(i) = p % v(i) * ScaleFactor
            p % s(i) = p % s(i) * ScaleFactor**2

            ScaleFactor = 1.0d0 - p % v(i) / ScaleFactor
            p % u(i) = p % u(i) * ScaleFactor
            p % s(i) = p % s(i) * ScaleFactor
         END DO
!         p % s(1:p % n) = p % s(1:p % n) / SUM( p % s(1:p % n) ) / 6.0d0
      END SELECT
!------------------------------------------------------------------------------
   END FUNCTION GaussPointsTetra
!------------------------------------------------------------------------------

   FUNCTION GaussPointsPPyramid( np ) RESULT(p)
DLLEXPORT GaussPointsPPyramid
      
   INTEGER :: np,n,i
   REAL(KIND=dp) :: uh,vh,wh,sh
   TYPE(GaussIntegrationPoints_t), POINTER :: p

   IF ( .NOT. GInit ) CALL GaussPointsInit
   p => IntegStuff

   n = DBLE(np)**(1.0D0/3.0D0) + 0.5D0

   ! Get gauss points of p brick 
   ! (take into account term (-1+z)^2) from jacobian determinant
   p = GaussPointsPBrick(n,n,n+1)

   ! For each point apply mapping from brick to 
   ! pyramid and multiply each weight by detJ 
   ! of mapping
   DO i=1,p % n
      uh = p % u(i)
      vh = p % v(i)
      wh = p % w(i)
      sh = p % s(i)

      p % u(i)= 1d0/2*uh*(1d0-wh)
      p % v(i)= 1d0/2*vh*(1d0-wh)
      p % w(i)= SQRT(2d0)/2*(1d0+wh)
      p % s(i)= sh * SQRT(2d0)/8 * (-1d0+wh)**2
   END DO      

   END FUNCTION GaussPointsPPyramid

!------------------------------------------------------------------------------
   FUNCTION GaussPointsPyramid( np ) RESULT(p)
DLLEXPORT GaussPointsPyramid
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Return gaussian integration points for 3D prism element
!
!  ARGUMENTS:
!
!    INTEGER :: n
!      INPUT: number of points in the requested rule
!
!******************************************************************************
      INTEGER :: np

      INTEGER :: i,j,k,n,t
      TYPE(GaussIntegrationPoints_t), POINTER :: p

      IF ( .NOT. GInit ) CALL GaussPointsInit
      p => IntegStuff

      n = REAL(np)**(1.0D0/3.0D0) + 0.5D0

      IF ( n < 1 .OR. n > MAXN ) THEN
         p % n = 0
         WRITE( Message, * ) 'Invalid number of points: ', n
         CALL Error( 'GaussPointsPyramid', Message )
         RETURN
      END IF

      t = 0
      DO i=1,n
        DO j=1,n
          DO k=1,n
             t = t + 1
             p % u(t) = Points(k,n)
             p % v(t) = Points(j,n)
             p % w(t) = Points(i,n)
             p % s(t) = Weights(i,n)*Weights(j,n)*Weights(k,n)
          END DO
        END DO
      END DO
      p % n = t

      DO t=1,p % n
        p % w(t) = (p % w(t) + 1.0d0) / 2.0d0
        p % u(t) = p % u(t) * (1.0d0-p % w(t))
        p % v(t) = p % v(t) * (1.0d0-p % w(t))
        p % s(t) = p % s(t) * (1.0d0-p % w(t))**2/2
      END DO
!------------------------------------------------------------------------------
   END FUNCTION GaussPointsPyramid
!------------------------------------------------------------------------------

   FUNCTION GaussPointsPWedge(n) RESULT(p)
DLLEXPORT GaussPointsPWedge
       
   INTEGER :: n, i
   REAL(KIND=dp) :: uh,vh,wh,sh
   TYPE(GaussIntegrationPoints_t), POINTER :: p

   IF ( .NOT. GInit ) CALL GaussPointsInit
   p => IntegStuff

   ! Get gauss points of brick
   p = GaussPointsBrick(n)

   ! For each point apply mapping from brick to 
   ! wedge and multiply each weight by detJ 
   ! of mapping
   DO i=1,p % n
      uh = p % u(i)
      vh = p % v(i)
      wh = p % w(i)
      sh = p % s(i)

      p % u(i)= 1d0/2*(uh-uh*vh)
      p % v(i)= SQRT(3d0)/2*(1d0+vh)
      p % w(i)= wh
      p % s(i)= sh * SQRT(3d0)*(1-vh)/4
   END DO

   END FUNCTION GaussPointsPWedge

!------------------------------------------------------------------------------
   FUNCTION GaussPointsWedge( np ) RESULT(p)
DLLEXPORT GaussPointsWedge
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Return gaussian integration points for 3D wedge element
!
!  ARGUMENTS:
!
!    INTEGER :: n
!      INPUT: number of points in the requested rule
!
!******************************************************************************
      INTEGER :: np

      INTEGER :: i,j,k,n,t
      TYPE(GaussIntegrationPoints_t), POINTER :: p

      IF ( .NOT. GInit ) CALL GaussPointsInit
      p => IntegStuff

      n = REAL(np)**(1.0d0/3.0d0) + 0.5d0

      IF ( n < 1 .OR. n > MAXN ) THEN
         p % n = 0
         WRITE( Message, * ) 'Invalid number of points: ', n
         CALL Error( 'GaussPointsWedge', Message )
         RETURN
      END IF

      t = 0
      DO i=1,n
        DO j=1,n
          DO k=1,n
             t = t + 1
             p % u(t) = Points(k,n)
             p % v(t) = Points(j,n)
             p % w(t) = Points(i,n)
             p % s(t) = Weights(i,n)*Weights(j,n)*Weights(k,n)
          END DO
        END DO
      END DO
      p % n = t

      DO i=1,p % n
        p % v(i) = (p % v(i) + 1)/2
        p % u(i) = (p % u(i) + 1)/2 * (1 - p % v(i))
        p % s(i) = p % s(i) * (1-p % v(i))/4
      END DO
!------------------------------------------------------------------------------
   END FUNCTION GaussPointsWedge
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   FUNCTION GaussPointsQuad( np ) RESULT(p)
DLLEXPORT GaussPointsQuad
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Return gaussian integration points for 2D quad element
!
!  ARGUMENTS:
!
!    INTEGER :: n
!      INPUT: number of points in the requested rule
!
!******************************************************************************
      INTEGER :: np

      INTEGER i,j,n,t
      TYPE(GaussIntegrationPoints_t), POINTER :: p

      IF ( .NOT. GInit ) CALL GaussPointsInit
      p => IntegStuff

      n = SQRT( REAL(np) ) + 0.5

      ! WRITE (*,*) 'Integration:', n, np 

      IF ( n < 1 .OR. n > MAXN ) THEN
        p % n = 0
        WRITE( Message, * ) 'Invalid number of points: ', n
        CALL Error( 'GaussPointsQuad', Message )
        RETURN
      END IF

      t = 0
      DO i=1,n
        DO j=1,n
          t = t + 1
          p % u(t) = Points(j,n)
          p % v(t) = Points(i,n)
          p % s(t) = Weights(i,n)*Weights(j,n)
        END DO
      END DO
      p % n = t
!------------------------------------------------------------------------------
   END FUNCTION GaussPointsQuad
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
   FUNCTION GaussPointsPBrick( nx, ny, nz ) RESULT(p)
DLLEXPORT GaussPointsPBrick
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Return gaussian integration points for 3D brick element for
!    composite rule 
!    sum_i=1^nx(sum_j=1^ny(sum_k=1^nz w_ijk f(x_{i,j,k},y_{i,j,k},z_{i,j,k})))
!
!  ARGUMENTS:
!
!    INTEGER :: nx
!      INPUT: number of points in the requested rule in x direction
!
!    INTEGER :: ny
!      INPUR: number of points in the requested rule in y direction
!
!******************************************************************************
      INTEGER :: nx, ny,nz

      INTEGER i,j,k,t
      TYPE(GaussIntegrationPoints_t), POINTER :: p

      IF ( .NOT. GInit ) CALL GaussPointsInit
      p => IntegStuff

      ! Check validity of number of integration points
      IF ( nx < 1 .OR. nx > MAXN .OR. &
           ny < 1 .OR. ny > MAXN .OR. &
           nz < 1 .OR. nz > MAXN) THEN
        p % n = 0
        WRITE( Message, * ) 'Invalid number of points: ', nx, ny, nz
        CALL Error( 'GaussPointsBrick', Message )
        RETURN
      END IF

      t = 0
      DO i=1,nx
        DO j=1,ny
          DO k=1,nz
            t = t + 1
            p % u(t) = Points(i,nx)
            p % v(t) = Points(j,ny)
            p % w(t) = Points(k,nz)
            p % s(t) = Weights(i,nx)*Weights(j,ny)*Weights(k,nz)
          END DO
        END DO
      END DO
      p % n = t
!------------------------------------------------------------------------------
    END FUNCTION GaussPointsPBrick
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   FUNCTION GaussPointsBrick( np ) RESULT(p)
DLLEXPORT GaussPointsBrick
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Return gaussian integration points for 3D brick element
!
!  ARGUMENTS:
!
!    INTEGER :: n
!      INPUT: number of points in the requested rule
!
!******************************************************************************
      INTEGER :: np

      INTEGER i,j,k,n,t
      TYPE(GaussIntegrationPoints_t), POINTER :: p

      IF ( .NOT. GInit ) CALL GaussPointsInit
      p => IntegStuff

      n = REAL(np)**(1.0D0/3.0D0) + 0.5D0

      IF ( n < 1 .OR. n > MAXN ) THEN
        p % n = 0
        WRITE( Message, * ) 'Invalid number of points: ', n
        CALL Error( 'GaussPointsBrick', Message )
        RETURN
      END IF

      t = 0
      DO i=1,n
        DO j=1,n
          DO k=1,n
            t = t + 1
            p % u(t) = Points(k,n)
            p % v(t) = Points(j,n)
            p % w(t) = Points(i,n)
            p % s(t) = Weights(i,n)*Weights(j,n)*Weights(k,n)
          END DO
        END DO
      END DO
      p % n = t
!------------------------------------------------------------------------------
   END FUNCTION GaussPointsBrick
!------------------------------------------------------------------------------


!------------------------------------------------------------------------------
   FUNCTION GaussPoints( elm,np ) RESULT(IntegStuff)
DLLEXPORT GaussPoints
!------------------------------------------------------------------------------
!******************************************************************************
!
!  DESCRIPTION:
!    Given element structure return gauss integration points for the element
!
!  ARGUMENTS:
!
!  TYPE(Element_t) :: elm
!     INPUT: Structure holding element description
!
!  FUNCTION RETURN VALUE:
!    TYPE(GaussIntegrationPoints_t) :: IntegStuff
!      Structure holding the integration points...
!******************************************************************************

!------------------------------------------------------------------------------
     TYPE( Element_t ) :: elm
     INTEGER, OPTIONAL :: np
     TYPE( GaussIntegrationPoints_t ) :: IntegStuff
     LOGICAL :: pElement

!------------------------------------------------------------------------------
     INTEGER :: n

     TYPE(ElementType_t), POINTER :: elmt
!------------------------------------------------------------------------------
     elmt => elm % Type

     n = elmt % GaussPoints

     ! For p elements use different number of gauss points 
     pElement = ASSOCIATED(elm % PDefs)
     IF (pElement) n = elm % PDefs % GaussPoints

     IF ( PRESENT(np) ) n = np
     
     SELECT CASE( elmt % ElementCode / 100 )
     CASE (1)
        IntegStuff = GaussPoints0D( n )

     CASE (2)
        IntegStuff = GaussPoints1D( n )
     CASE (3)
        ! For p type elements gauss points are different
        IF (pElement) THEN
           IntegStuff = GaussPointsPTriangle(n)
        ELSE    
           IntegStuff = GaussPointsTriangle( n )
        END IF
     CASE (4)
        IntegStuff = GaussPointsQuad( n )

     CASE (5)
        ! For p type elements gauss points are different
        IF (pElement) THEN
           IntegStuff = GaussPointsPTetra(n)
        ELSE
           IntegStuff = GaussPointsTetra( n )
        END IF
     CASE (6)
        IF (pElement) THEN
           IntegStuff = GaussPointsPPyramid(n)
        ELSE
           IntegStuff = GaussPointsPyramid( n )
        END IF
     CASE (7)
        ! For p type elements gauss points are different
        IF (pElement) THEN
           IntegStuff = GaussPointsPWedge(n)
        ELSE 
           IntegStuff = GaussPointsWedge( n )
        END IF
     CASE (8)
        IntegStuff = GaussPointsBrick( n )
     END SELECT

   END FUNCTION GaussPoints
!---------------------------------------------------------------------------
END MODULE Integration
!---------------------------------------------------------------------------
