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
! * FreeSurfaceSolver: Solver for free surface evolution in 2d and 3d flows
! *                    with/without surface flux 
! *
! ******************************************************************************
! *
! *                    Author:  Thomas Zwinger
! *
! *                    Address: Center for Scientific Computing
! *                                Tietotie 6, P.O. BOX 405
! *                                  02101 Espoo, Finland
! *                                  Tel. +358 0 457 2723
! *                                Telefax: +358 0 457 2183
! *                              EMail: Thomas.Zwinger@csc.fi
! *
! *                       Date: 17  May 2002
! *
! *                Modified by: Peter R�back, Juha Ruokolainen, Mikko Lyly
! *
! *
!/******************************************************************************
! *
! *       Modified by: Thomas Zwinger
! *
! *       Date of modification: 30. Oct 2002
! *
! *****************************************************************************/
   SUBROUTINE FreeSurfaceSolver( Model,Solver,dt,TransientSimulation )
  !DEC$ATTRIBUTES DLLEXPORT :: FreeSurfaceSolver
     USE DefUtils
     IMPLICIT NONE

!------------------------------------------------------------------------------
!    external variables
!------------------------------------------------------------------------------
     TYPE(Model_t) :: Model
     TYPE(Solver_t):: Solver
     REAL(KIND=dp) :: dt
     LOGICAL :: TransientSimulation
!------------------------------------------------------------------------------
!    Local variables
!------------------------------------------------------------------------------
     INTEGER :: & 
          i,j,t,N,NMAX,Nmatrix,bf_id,DIM,istat,LocalNodes,&
          NSDOFs,SubroutineVisited=0

     REAL(KIND=dp) :: &
          at,st,totat,totst,CPUTime,Norm,PrevNorm,LocalBottom, cv, &
          Relax, MaxDisp, maxdh

     LOGICAL ::&
          firstTime=.TRUE., GotIt, AllocationsDone = .FALSE., stat, &
          NeedOldValues, LimitDisp,  Bubbles = .TRUE.,&
          NormalFlux = .TRUE., SubstantialSurface = .TRUE.,&
          UseBodyForce = .TRUE.

     CHARACTER(LEN=MAX_NAME_LEN)  :: EquationName

     TYPE(Nodes_t)   :: ElementNodes
     TYPE(Element_t),POINTER :: CurrentElement
     TYPE(Variable_t), POINTER :: FlowSol

     INTEGER, POINTER ::&
          FreeSurfPerm(:), FlowPerm(:), NodeIndexes(:)

     REAL(KIND=dp), POINTER ::&
          FreeSurf(:), PreFreeSurf(:,:), TimeForce(:),&
          FlowSolution(:), PrevFlowSol(:,:), ElemFreeSurf(:), OldFreeSurf(:)
 
     REAL(KIND=dp), ALLOCATABLE :: &          
          STIFF(:,:),SourceFunc(:),FORCE(:), &
          MASS(:,:), Velo(:,:), Flux(:,:)
          
      TYPE(ValueList_t), POINTER :: BodyForce, SolverParams
!-----------------------------------------------------------------------------
!      remember these variables
!----------------------------------------------------------------------------- 
     SAVE STIFF, MASS, SourceFunc, FORCE, &
          ElementNodes, AllocationsDone, Velo, OldFreeSurf, TimeForce, &
          SubroutineVisited, ElemFreeSurf, Flux, SubstantialSurface, NormalFlux,&
          UseBodyForce

!------------------------------------------------------------------------------
!    Get constants
!------------------------------------------------------------------------------

     DIM = CoordinateSystemDimension()
     SolverParams => GetSolverParams()

     cv = GetConstReal( SolverParams, 'Velocity Implicity', GotIt)
     IF(.NOT. GotIt) cv = 1.0d0 
     WRITE(Message,'(a,F8.2)') 'Velocity implicity (1=fully implicit)=', cv
     CALL Info('FreeSurfaceSolver', Message, Level=4)

     Relax = GetConstReal( SolverParams, 'Relaxation Factor', GotIt)
     IF(.NOT. GotIt) Relax = 1.0d0

     MaxDisp = GetConstReal( SolverParams, 'Maximum Displacement', LimitDisp)

     NeedOldValues = GotIt .OR. LimitDisp 

     Bubbles = GetLogical( SolverParams,'Bubbles',GotIt )
     IF (.NOT.Gotit) THEN
        Bubbles = .TRUE.
     END IF
     IF (Bubbles) THEN
        CALL Info('FreeSurfaceSolver', 'Using Bubble stabilization', Level=4)
     ELSE
        CALL Info('FreeSurfaceSolver', &
             'Using residual squared-stabilized formulation.', Level=4)
     END IF

     UseBodyForce =  GetLogical( SolverParams,'Use Accumulation',GotIt )
     IF (.NOT.Gotit) UseBodyForce = .TRUE.

     IF (UseBodyForce) THEN
        NormalFlux =  GetLogical( SolverParams,'Normal Flux',GotIt )
        IF (.NOT.Gotit) NormalFlux = .TRUE.

        IF (NormalFlux) THEN
           CALL Info('FreeSurfaceSolver', &
                'Using scalar value for accumulaton/ablation rate', Level=4)
        ELSE
           CALL Info('FreeSurfaceSolver', &
                'Computing accumulaton/ablation rate from input vector', Level=4)
        END IF
     ELSE
        NormalFlux = .TRUE.
        CALL Info('FreeSurfaceSolver', 'Zero accumulation/ablation', Level=4)
     END IF


!    Velocity from NS-Solver
!    -----------------------
     FlowSol => VariableGet( Solver % Mesh % Variables, 'Flow Solution' )
     IF ( ASSOCIATED( FlowSol ) ) THEN
       FlowPerm     => FlowSol % Perm
       NSDOFs       =  FlowSol % DOFs
       FlowSolution => FlowSol % Values
       PrevFlowSol => FlowSol % PrevValues
     ELSE
       CALL Info('FreeSurfaceSolver', 'No variable for velocity associated.', Level=4)
     END IF

     WRITE(Message,'(a,i1,a,i1)') 'DIM=', DIM, ', NSDOFs=', NSDOFs
     CALL Info( 'FreeSurfaceSolver', Message, level=4) 

!------------------------------------------------------------------------------
!    Allocate some permanent storage, this is done first time only
!------------------------------------------------------------------------------

     IF ( .NOT. AllocationsDone ) THEN
       NMAX = Model % MaxElementNodes
       IF (Bubbles) THEN
          Nmatrix = 2*NMAX
       ELSE
          Nmatrix = NMAX
       END IF

       ALLOCATE( ElementNodes % x( NMAX ),    &
                 ElementNodes % y( NMAX ),    &
                 ElementNodes % z( NMAX ),    &
                 TimeForce( NMAX ),           &
                 FORCE( Nmatrix ),    &
                 STIFF( Nmatrix, Nmatrix ), &
                 MASS( Nmatrix, Nmatrix ),  &
                 Velo( 3, NMAX ), &
                 Flux( 3, NMAX), &
                 ElemFreeSurf( NMAX ),&
                 SourceFunc( NMAX ),  STAT=istat )
       IF ( istat /= 0 ) THEN
         CALL Fatal('FreeSurfaceSolver','Memory allocation error, Aborting.')
       END IF

       IF(NeedOldValues) THEN
         ALLOCATE(OldFreeSurf(Model % NumberOfNodes), STAT=istat)
         
         IF ( istat /= 0 ) THEN
           CALL Fatal('FreeSurfaceSolver','Memory allocation error, Aborting.')
         END IF
       END IF

       CALL Info('FreeSurfaceSolver','Memory allocations done', Level=4)
       AllocationsDone = .TRUE.

     END IF

!------------------------------------------------------------------------------
!    Get variables for the solution
!------------------------------------------------------------------------------

     FreeSurf     => Solver % Variable % Values     ! Nodal values for free surface displacement
     FreeSurfPerm => Solver % Variable % Perm       ! Permutations for free surface displacement
     PreFreeSurf  => Solver % Variable % PrevValues ! Nodal values for free surface displacement
                                                    !                     from previous timestep
     IF( NeedOldValues) THEN
       OldFreeSurf = FreeSurf
     END IF
     
!------------------------------------------------------------------------------
!    assign matrices
!------------------------------------------------------------------------------
     LocalNodes = Model % NumberOfNodes
     Norm = Solver % Variable % Norm     

!------------------------------------------------------------------------------
!    Do some additional initialization, and go for it
!------------------------------------------------------------------------------
     totat = 0.0d0
     totst = 0.0d0
     at = CPUTime()
     CALL Info( 'FreeSurfaceSolver', 'start assembly', Level=4 )
     CALL DefaultInitialize()
!------------------------------------------------------------------------------
!    Do the assembly
!------------------------------------------------------------------------------
    DO t=1,Solver % NumberOfActiveElements
       CurrentElement => GetActiveElement(t)
       n = GetElementNOFNodes()
       NodeIndexes => CurrentElement % NodeIndexes

       ! set coords of highest occuring dimension to zero (to get correct path element)
       !-------------------------------------------------------------------------------
       ElementNodes % x(1:n) = Solver % Mesh % Nodes % x(NodeIndexes)
       IF (DIM == 2) THEN
          ElementNodes % y(1:n) = 0.0
          ElementNodes % z(1:n) = 0.0
       ELSE IF (DIM == 3) THEN
          ElementNodes % y(1:n) = Solver % Mesh % Nodes % y(NodeIndexes)
          ElementNodes % z(1:n) = 0.0d0
       ELSE
          WRITE(Message,'(a,i1,a)')&
               'It is not possible to compute free-surface problems in DIM=',&
               DIM, ' dimensions. Aborting'
          CALL Fatal( 'FreeSurfaceSolver', Message) 
          STOP   
       END IF

       ! get velocity profile
       IF ( ASSOCIATED( FlowSol ) ) THEN
         DO i=1,n
           j = NSDOFs*FlowPerm(NodeIndexes(i))

           IF(TransientSimulation .AND. ABS(cv-1.0) > 0.001) THEN
             IF((DIM == 2) .AND. (NSDOFs == 3)) THEN
               Velo(1,i) = cv * FlowSolution( j-2 ) + (1-cv) * PrevFlowSol(j-2,1)
               Velo(2,i) = cv * FlowSolution( j-1 ) + (1-cv) * PrevFlowSol(j-1,1)
               Velo(3,i) = 0.0d0
             ELSE IF ((DIM == 3) .AND. (NSDOFs == 4)) THEN
               Velo(1,i) = cv * FlowSolution( j-3 ) + (1-cv) * PrevFlowSol(j-3,1)
               Velo(2,i) = cv * FlowSolution( j-2 ) + (1-cv) * PrevFlowSol(j-2,1)
               Velo(3,i) = cv * FlowSolution( j-1 ) + (1-cv) * PrevFlowSol(j-1,1)
             ELSE IF ((CurrentCoordinateSystem() == CylindricSymmetric) &
                 .AND. (DIM == 2) .AND. (NSDOFs == 4)) THEN  
               Velo(1,i) = cv * FlowSolution( j-3 ) + (1-cv) * PrevFlowSol(j-3,1)
               Velo(2,i) = cv * FlowSolution( j-2 ) + (1-cv) * PrevFlowSol(j-2,1)
               Velo(3,i) = cv * FlowSolution( j-1 ) + (1-cv) * PrevFlowSol(j-1,1)
             ELSE
               WRITE(Message,'(a,i1,a,i1,a)')&
                   'DIM=', DIM, ' NSDOFs=', NSDOFs, ' does not combine. Aborting'
               CALL Fatal( 'FreeSurfaceSolver', Message)               
             END IF
           ELSE
             IF((DIM == 2) .AND. (NSDOFs == 3)) THEN
               Velo(1,i) = FlowSolution( j-2 ) 
               Velo(2,i) = FlowSolution( j-1 ) 
               Velo(3,i) = 0.0d0
             ELSE IF ((DIM == 3) .AND. (NSDOFs == 4)) THEN
               Velo(1,i) = FlowSolution( j-3 ) 
               Velo(2,i) = FlowSolution( j-2 ) 
               Velo(3,i) = FlowSolution( j-1 ) 
             ELSE IF ((CurrentCoordinateSystem() == CylindricSymmetric) &
                 .AND. (DIM == 2) .AND. (NSDOFs == 4)) THEN
               Velo(1,i) = FlowSolution( j-3 ) 
               Velo(2,i) = FlowSolution( j-2 ) 
               Velo(3,i) = FlowSolution( j-1 ) 
             ELSE
               WRITE(Message,'(a,i1,a,i1,a)')&
                   'DIM=', DIM, ' NSDOFs=', NSDOFs, ' does not combine. Aborting'
               CALL Fatal( 'FreeSurfaceSolver', Message)
             END IF
           END IF             
         END DO
       ELSE
          Velo=0.0d0          
       END IF
!------------------------------------------------------------------------------
!      get the accumulation/ablation rate (i.e. normal surface flux)
!      from the body force section
!------------------------------------------------------------------------------
       SourceFunc = 0.0d0
       Flux  = 0.0d0
       SubstantialSurface = .TRUE.
       BodyForce => GetBodyForce()
       IF ( UseBodyForce.AND.ASSOCIATED( BodyForce ) ) THEN
          SubstantialSurface = .FALSE.
          ! Accumulation/ablation is given in normal direction of surface:
          !---------------------------------------------------------------
          IF (NormalFlux) THEN 
             SourceFunc(1:n) = GetReal( BodyForce, &
                  'Accumulation Ablation' )
          ! Accumulation/ablation has to be computed from given flux:
          !----------------------------------------------------------
          ELSE 
             Flux(1,1:n) = GetReal( BodyForce, 'Accumulation Flux 1')
             IF (DIM == 2) THEN
                Flux(2,1:n) = GetReal( BodyForce, 'Accumulation Flux 2' )
             ELSE
                Flux(2,1:n) = 0.0d0
             END IF
             IF (DIM == 3) THEN
                Flux(3,1:n) = GetReal( BodyForce, 'Accumulation Flux 3' )
             ELSE
                Flux(3,1:n) = 0.0d0
             END IF
             SourceFunc = 0.0d0
          END IF
       END IF

       IF( TransientSimulation) THEN
         ElemFreeSurf(1:n) = PreFreeSurf(FreeSurfPerm(NodeIndexes),1)
       END IF

!------------------------------------------------------------------------------
!      Get element local matrix, and rhs vector
!------------------------------------------------------------------------------
       CALL LocalMatrix( STIFF, MASS, FORCE,&
           SourceFunc, ElemFreeSurf, Velo, CurrentElement,&
           n, ElementNodes, NodeIndexes, TransientSimulation,&
           Flux, NormalFlux, SubstantialSurface)

!------------------------------------------------------------------------------
!        If time dependent simulation add mass matrix to stiff matrix
!------------------------------------------------------------------------------
         IF ( Bubbles ) TimeForce  = FORCE
         IF ( TransientSimulation ) THEN
!------------------------------------------------------------------------------
!          NOTE: This will replace STIFF and LocalForce with the
!                combined information...
!------------------------------------------------------------------------------
           IF ( Bubbles ) FORCE = 0.0d0
            CALL Default1stOrderTime( MASS, STIFF, FORCE )
         END IF
!------------------------------------------------------------------------------
!        Update global matrices from local matrices
!------------------------------------------------------------------------------
         IF (Bubbles) THEN
            CALL Condensate( N, STIFF, FORCE, TimeForce )
            IF ( TransientSimulation ) CALL DefaultUpdateForce( TimeForce )
         END IF
!------------------------------------------------------------------------------
!      Update global matrix and rhs vector from local matrix & vector
!------------------------------------------------------------------------------
       CALL DefaultUpdateEquations( STIFF, FORCE )
!------------------------------------------------------------------------------
    END DO

!------------------------------------------------------------------------------
!     Neumann & Newton boundary conditions
!------------------------------------------------------------------------------
!
! MIND: In weak formulation it is not possible to prescribe a contact angle on
!       a boundary in this solver. This has to be taken care of in the boundary
!       condition for the stress tensor in the Navier-Stokes Solver. Thus, in
!       generally it does not make sense to prescribe a van Neumann type of
!       condition here.

!------------------------------------------------------------------------------
!    FinishAssemebly must be called after all other assembly steps, but before
!    Dirichlet boundary settings. Actually no need to call it except for
!    transient simulations.
!------------------------------------------------------------------------------
     CALL DefaultFinishAssembly()
     CALL DefaultDirichletBCs()

!------------------------------------------------------------------------------
!    Solve System
!------------------------------------------------------------------------------
     at = CPUTime() - at
     st = CPUTime()
     Norm = DefaultSolve()
    
     IF(NeedOldValues) THEN
        IF(LimitDisp) THEN 
           maxdh = -HUGE(maxdh)         
           DO i=1, Model % NumberOfNodes
              j = FreeSurfPerm(i)
              IF(j > 0) THEN
                 maxdh = MAX(maxdh, ABS(FreeSurf(j)-OldFreeSurf(j)))
              END IF
           END DO
           IF(maxdh > MaxDisp) THEN
              Relax = Relax * MaxDisp/maxdh
           END IF
           WRITE(Message,'(a,E8.2)') 'Maximum displacement',maxdh
           CALL Info( 'FreeSurfaceSolver', Message, Level=4 )
        END IF
        WRITE(Message,'(a,F8.2)') 'pp Relaxation factor',Relax
        CALL Info( 'FreeSurfaceSolver', Message, Level=4 )
        DO i=1, Model % NumberOfNodes
           j = FreeSurfPerm(i)
           IF(j > 0) THEN
              FreeSurf(j) = Relax * FreeSurf(j) + (1-Relax) * OldFreeSurf(j)
           END IF
        END DO
     END IF

     st = CPUTIme()-st
     totat = totat + at
     totst = totst + st

     WRITE(Message,'(a,F8.2,F8.2)') 'Assembly: (s)', at, totat
     CALL Info( 'FreeSurfaceSolver', Message, Level=4 )
     WRITE(Message,'(a,F8.2,F8.2)') ' Solve:    (s)', st, totst
     CALL Info( 'FreeSurfaceSolver', Message, Level=4 )
     SubroutineVisited = SubroutineVisited + 1

!------------------------------------------------------------------------------
   CONTAINS

!------------------------------------------------------------------------------
!==============================================================================
     SUBROUTINE LocalMatrix( STIFF, MASS, FORCE,&
          SourceFunc, OldFreeSurf, Velo, &
          Element, nCoord, Nodes, NodeIndexes, TransientSimulation,&
          Flux, NormalFlux, SubstantialSurface)
!------------------------------------------------------------------------------
!    INPUT:  SourceFunc(:)   nodal values of the accumulation/ablation function
!            
!            Element         current element
!            n               number of nodes
!            Nodes           current node points
!
!    OUTPUT: STIFF(:,:)
!            MASS(:,:)
!            FORCE(:)
!------------------------------------------------------------------------------
!      external variables:
!      ------------------------------------------------------------------------
       REAL(KIND=dp) ::&
             STIFF(:,:), MASS(:,:), FORCE(:), SourceFunc(:), &
             Velo(:,:), OldFreeSurf(:), Flux(:,:)

       INTEGER :: nCoord, NodeIndexes(:)
       TYPE(Nodes_t) :: Nodes
       TYPE(Element_t), POINTER :: Element
       LOGICAL :: TransientSimulation,NormalFlux,SubstantialSurface
!------------------------------------------------------------------------------
!      internal variables:
!      ------------------------------------------------------------------------
       REAL(KIND=dp) ::&
          Basis(2*nCoord),dBasisdx(2*nCoord,3),ddBasisddx(2*nCoord,3,3),&
          Vgauss(3), VMeshGauss(3), Source, gradFreeSurf(3), normGradFreeSurf,&
          FluxGauss(3),X,Y,Z,U,V,W,S,SqrtElementMetric, SU(2*nCoord),SW(2*nCoord),Tau,hK,UNorm
       LOGICAL :: Stat
       INTEGER :: i,j,t,p,q, n
       TYPE(GaussIntegrationPoints_t) :: IntegStuff
!------------------------------------------------------------------------------

       FORCE = 0.0d0
       STIFF = 0.0d0
       MASS  = 0.0d0

       IF (Bubbles) THEN
          n = nCoord * 2
       ELSE
          n = nCoord
       END IF

       hK = ElementDiameter( Element, Nodes )

!
!      Numerical integration:
!      ----------------------
       IF (Bubbles) THEN
          IntegStuff = GaussPoints( Element, Element % type % gausspoints2)
       ELSE
          IntegStuff = GaussPoints( Element )
       END IF

       SU = 0.0d0
       SW = 0.0d0

       DO t = 1,IntegStuff % n
         U = IntegStuff % u(t)
         V = IntegStuff % v(t)
         W = IntegStuff % w(t)
         S = IntegStuff % s(t)
!
!        Basis function values & derivatives at the integration point:
!        -------------------------------------------------------------
         stat = ElementInfo( Element,Nodes,U,V,W,SqrtElementMetric, &
              Basis,dBasisdx,ddBasisddx,.FALSE., Bubbles )

!        Correction from metric
!        ----------------------
          S = S * SqrtElementMetric

         IF ( CurrentCoordinateSystem() /= Cartesian ) THEN
            X = SUM( Nodes % x(1:nCoord) * Basis(1:nCoord) )
            Y = SUM( Nodes % y(1:nCoord) * Basis(1:nCoord) )
            Z = SUM( Nodes % z(1:nCoord) * Basis(1:nCoord) )
            S = S * X
         END IF
!
!        Velocities and (norm of) gradient of free surface and source function 
!        at Gauss point
!        ---------------------------------------------------------------------

         gradFreeSurf=0.0d0
         Vgauss=0.0d0
         VMeshGauss=0.0d0

         DO i=1,DIM-1
           gradFreeSurf(i) = SUM(dBasisdx(1:nCoord,i)*OldFreeSurf(1:nCoord))
         END DO

         gradFreeSurf(DIM) = 1.0d0

         DO i=1,DIM
           Vgauss(i) = SUM( Basis(1:nCoord)*Velo(i,1:nCoord) )
         END DO

         IF (DIM==3) THEN
           normGradFreeSurf = SQRT(1.0d0 + gradFreeSurf(1)**2 + &
                gradFreeSurf(2)**2)
         ELSE
           normGradFreeSurf = SQRT(1.0d0 + gradFreeSurf(1)**2)
         END IF

         UNorm = SQRT( SUM( Vgauss(1:dim-1)**2 ) )
         Tau = hK / ( 2*Unorm )

         IF ( .NOT. Bubbles ) THEN
            DO p=1,n
               SU(p) = 0.0d0
               DO i=1,dim-1
                  SU(p) = SU(p) + Vgauss(i) * dBasisdx(p,i)
               END DO

               SW(p) = 0.0d0
               DO i=1,dim-1
                  SW(p) = SW(p) + Vgauss(i) * dBasisdx(p,i)
               END DO
            END DO
         END IF

!        Stiffness matrix:
!        -----------------
         DO p=1,n
           DO q=1,n
             DO i=1,DIM-1
               STIFF(p,q) = STIFF(p,q) + &
                       s * Vgauss(i) * dBasisdx(q,i) * Basis(p)
             END DO
             STIFF(p,q) =  STIFF(p,q) + s * Tau * SU(q) * SW(p)
           END DO
         END DO


!        Mass Matrix:
!        ------------
         IF ( TransientSimulation ) THEN
            DO p=1,n
              DO q=1,n
                MASS(p,q) = MASS(p,q) +  &
                         S * Basis(q) * (Basis(p) + Tau*SW(p))
              END DO
            END DO
         END IF

!        Get accumulation/ablation function if flux input is given
!        (i.e., calculate vector product between flux and normal)
!        --------------------------------------------------------- 
         IF (.NOT.(SubstantialSurface)) THEN
            IF (NormalFlux) THEN 
               Source = normGradFreeSurf * SUM( SourceFunc(1:nCoord) &
                    * Basis(1:nCoord) )
            ELSE
               DO i=1,dim
                  FluxGauss(i) = SUM(Basis(1:nCoord)*Flux(i,1:nCoord))
               END DO
               Source = SUM(FluxGauss(1:DIM)*gradFreeSurf(1:DIM))
            END IF
         ELSE
            Source = 0.0d0
         END IF

!        Assemble force vector:
!        ---------------------
         FORCE(1:n) = FORCE(1:n) &
              + (Vgauss(dim)+Source) * (Basis(1:n) + Tau*SW(1:n)) * s
      END DO
!------------------------------------------------------------------------------
    END SUBROUTINE LocalMatrix

!==============================================================================
!------------------------------------------------------------------------------
  END SUBROUTINE FreeSurfaceSolver
!------------------------------------------------------------------------------
