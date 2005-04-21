
MODULE ReynoldsUtilities

  USE Types
  IMPLICIT NONE

  CONTAINS


!------------------------------------------------------------------------------
  FUNCTION ComputeHoleImpedance(holemodel, r, b, p, visc, &
      dens, d, w) RESULT(impedance)
!!!DEC$ATTRIBUTES DLLEXPORT :: ComputeHoleImpedance
    
    CHARACTER(LEN=*) :: holemodel    
    COMPLEX(KIND=dp) :: corr, c, q, iu, qr, impedance,holeimp
    REAL(KIND=dp) :: r,b,d,p,visc,dens,w,eps,skvorimp
    INTEGER :: visited=0
    
    SAVE visited

    d = ABS(d)
    
    visited = visited + 1 
    eps = 1.0d-10
    c = 0.0
    iu = DCMPLX( 0, 1.0)
    q = SQRT(iu * w * dens / visc)

    holeimp = 0.0
    skvorimp = 0.0


    SELECT CASE( holemodel )

      CASE('slot')
      qr = q * r / 2.0d0
      corr = 1.0d0 - (1.0d0/qr)*((EXP(qr)-1.0)/(EXP(qr)+1.0))
      holeimp = (iu * w * dens * b) / corr

      CASE('round')
      qr = iu * q * r
      corr = 1.0d0 - (2.0d0/(qr**2)) * &
          BesselFunctionZ(qr,0,eps,.TRUE.) / &
          BesselFunctionZ(qr,0,eps,.FALSE.)
      holeimp = (iu * w * dens * b) / corr

      ! Flow gathering to the hole
      skvorimp = (6.0*visc*r*r / (d**3.0)) *  &
          (-2.0*LOG(p)-3.0+4.0*p-p*p)/(8.0*p)
      
      CASE ('square')
      CALL Warn('ComputeHoleImpedance','Square hole not implemented using slot instead!')

      qr = q * r / 2.0d0
      corr = 1.0d0 - (1.0d0/qr)*((EXP(qr)-1.0)/(EXP(qr)+1.0))
      holeimp = (iu * w * dens * b) / corr

    CASE DEFAULT 
      CALL WARN('ComputeHoleImpedance','Unknown hole type: '//TRIM(holemodel))       
    END SELECT

    IF(MOD(visited,400) == -1 ) THEN 
      PRINT *,'geom.cor :',corr
      PRINT *,'qr       :',qr
      PRINT *,'holeimp  :',holeimp
      PRINT *,'skvorimp :',skvorimp
    END IF

    impedance = holeimp/p + 1.0*skvorimp

  CONTAINS 

!------------------------------------------------------------------------------
! Calculates the Bessel function for integer n
! with relative accuracy eps. If integrate is true
! calculates its first integral int \int J(x)*x*dx
    FUNCTION BesselFunctionZ( z, m, eps, integrate) RESULT(f)
      
      COMPLEX(KIND=dp) :: z, f, df
      REAL(KIND=dp) :: eps, prodk, prodl
      INTEGER :: m, n, k, l
      LOGICAL :: integrate
      
      f = 0.0
      k = 0
      prodk = 1.0d0
      prodl = 1.0d0
      
      n = ABS(m)
      IF(n > 0) THEN
        DO l=1,n
          prodl = l*prodl
        END DO
      END IF
      l = n
      
      DO
        df = z ** (2*k) * ((-1)**k) / (2**(2*k) * prodk * prodl)
        IF(integrate) THEN
          df = df * z ** 2 / (2*k+2+n)
        ENDIF
        f = f + df
        IF(ABS(df) < eps * ABS(f)) EXIT
        
        k = k+1
        prodk = k * prodk
        l = k+n
        prodl = l * prodl
      END DO
      
      f = f * (z ** n) / (2 ** n) 
      IF (m < 0) THEN
        f = f * ((-1)**m)
      END IF
    END FUNCTION BesselFunctionZ

!------------------------------------------------------------------------------

  END FUNCTION ComputeHoleImpedance
!------------------------------------------------------------------------------
    

!------------------------------------------------------------------------------
  FUNCTION ComputeSideImpedance(d, visc, dens, omega, rarefaction, pref) RESULT(impedance)
!!DEC$ATTRIBUTES DLLEXPORT :: ComputeSideImpedance
    
    COMPLEX(KIND=dp) :: impedance
    REAL(KIND=dp) :: d, visc, dens, omega, mfp, kn, dl, pref
    LOGICAL :: rarefaction

    d = ABS(d)

    IF(rarefaction) THEN
      mfp = SQRT(PI/ (2.0 * dens * pref) ) * visc
      kn = mfp / d

      dl = 0.8488 * (1.0 + 2.676 * Kn**0.659)
    ELSE
      dl = 0.8488 
    END IF

    impedance = 12.0 * dl * visc / d

  END FUNCTION ComputeSideImpedance
!------------------------------------------------------------------------------

END MODULE ReynoldsUtilities
!------------------------------------------------------------------------------


