!     Oct. 1st, 2022
!     Eralp Demir
!     This module contains the solver schemes for crystal plasticity
!
      module cpsolver
      implicit none
      contains
!
!     This subroutine deals with
!     global variables and their assignments
!     before entering the main solver:
!     1. assigns the global variables to locals
!     before calling the CP-solver
!     2. calls fge-predictor scheme before as
!     spare solution
!     3. calls implicit or explicit CP-solvers
!     4. assigns the results to the glboal state variables
      subroutine solve(noel, npt, dfgrd1, dfgrd0,
     + temp, dtemp, dt, matid, pnewdt, nstatv, statev,
     + sigma, jacobi)
!
      use globalvariables, only : statev_gmatinv, statev_gmatinv_t,
     + statev_gammasum_t, statev_gammasum, statev_ssdtot_t,
     + statev_gammadot_t, statev_gammadot, statev_ssdtot,
     + statev_Fp_t, statev_Fp, statev_sigma_t, statev_sigma,
     + statev_jacobi_t, statev_jacobi, statev_Fth_t, statev_Fth,
     + statev_tauc_t, statev_tauc, statev_maxx_t, statev_maxx,
     + statev_Eec_t, statev_Eec, statev_gnd_t, statev_gnd,
     + statev_ssd_t, statev_ssd, statev_loop_t, statev_loop,
     + statev_forest_t, statev_forest, statev_evmp_t, statev_evmp,
     + statev_substructure_t, statev_substructure, statev_sigma_t2,
     + statev_totgammasum_t, statev_totgammasum, statev_backstress_t,
     + statev_tausolute_t, statev_tausolute, forestproj_all,
     + numslip_all, numscrew_all, phaseid_all,
     + dirc_0_all, norc_0_all, caratio_all, cubicslip_all,
     + Cc_all, gf_all, G12_all, alphamat_all, burgerv_all,
     + sintmat1_all, sintmat2_all, hintmat1_all, hintmat2_all,
     + slipmodel_all, slipparam_all, creepmodel_all, creepparam_all,
     + hardeningmodel_all, hardeningparam_all, irradiationmodel_all,
     + irradiationparam_all, slip2screw_all, I3, I6, smallnum, largenum,
     + nstatv_outputs, dt_t
!
      use userinputs, only: constanttemperature, temperature,
     + predictor, maxnslip, maxnparam, maxxcr, cutback, explicit,
     + phi, maxnloop
!
!
      use usermaterials, only: materialparam
!
      use crss, only: slipresistance
!
      use useroutputs, only: assignoutputs
!
      use errors, only: error
!
      use utilities, only: inv3x3, nolapinverse, matvec6, vecmat6,
     + rotord4sig, gmatvec6
!
      implicit none
!
!     element no
      integer, intent(in) :: noel
!
!     ip no
      integer, intent(in) :: npt
!
!
!     current deformation gradient
      real(8), intent(in) :: dfgrd1(3,3)
!
!     former deformation gradient
      real(8), intent(in) :: dfgrd0(3,3)
!
!     ABAQUS temperature
      real(8), intent(in) :: temp
!
!     ABAQUS temperature increment
      real(8), intent(in) :: dtemp
!
!     time step
      real(8), intent(in) :: dt
!
!     material id
      integer, intent(in) :: matid
!
!     time factor
      real(8), intent(inout) :: pnewdt
!
!     number of state variables - for postprocessing
      integer, intent(in) :: nstatv
!
!     state variables - postprocessing
      real(8), intent(inout) :: statev(nstatv)
!
!     Cauchy stress
      real(8), intent(out) :: sigma(6)
!
!     Material tangent
      real(8), intent(out) :: jacobi(6,6)
!
!     Local variables used within this subroutine
!
!
!     phase-id
      integer :: phaid
!
!     number of slip systems
      integer :: nslip
!
!
!     Convergence flag (initially set to zero!)
!
!     Flag for crystal plasticity explicit/implicit solver
      integer :: cpconv
      data    cpconv     /0/
!     Flag for Euler solver convergence
      integer :: cpconv0
      data    cpconv0     /0/
!
!     Local state variables with known dimensions
!     crystal to sample transformation at the former time step
      real(8) :: gmatinv_t(3,3)
!     crystal to sample transformation at the former time step
      real(8) :: gmatinv(3,3), gmatinv0(3,3)
!     stress at the former time step
      real(8) :: sigma_t(6)
!     rss/crsss ratio at the former time step
      real(8) :: maxx_t
!     rss/crsss ratio at the current time step 
      real(8) :: maxx
!     elastic strains in the crystal reference at the former time step
      real(8) :: Eec_t(6)
!     elastic strains in the crystal reference at the current time step
      real(8) :: Eec(6), Eec0(6)
!     plastic deformation gradient at the former time step
      real(8) :: Fp_t(3,3)
!     plastic deformation gradient at the current time step
      real(8) :: Fp(3,3), Fp0(3,3)
!     thermal deformation gradient at the former time step
      real(8) :: Fth_t(3,3)
!     thermal deformation gradient at the current time step
      real(8) :: Fth(3,3)
!     inverse of the thermal deformation gradient at the former time step
      real(8) :: invFth_t(3,3)
!     inverse of the thermal deformation gradient at the current time step
      real(8) :: invFth(3,3)
!     determinant of the thermal deformation gradient
      real(8) :: detFth, detFth_t
!     mechanical deformation gradient at the former time step
      real(8) :: F_t(3,3)
!     mechanical deformation gradient at the current time step
      real(8) :: F(3,3)
!
!     Variables for velocity gradient calculation
!     Fdot
      real(8) :: Fdot(3,3)
!     velocity gradient at the current time step
      real(8) :: L(3,3)
!     inverse of the deformation gradient
      real(8) :: Finv(3,3)
!     determinant of the deformation gradient
      real(8) :: detF
!
!     Local state variable arrays
!     sum of slip per slip system
      real(8) :: gammasum_t(numslip_all(matid))
      real(8) :: gammasum(numslip_all(matid)),
     + gammasum0(numslip_all(matid))
!     slip rates
      real(8) :: gammadot_t(numslip_all(matid))
      real(8) :: gammadot(numslip_all(matid)),
     + gammadot0(numslip_all(matid))
!     slip resistance
      real(8) :: tauc_t(numslip_all(matid))
      real(8) :: tauc(numslip_all(matid)),
     + tauc0(numslip_all(matid))
!     effective overall slip resistance
!     (tauc0 + GND + SSD + solute + substructure + forest + etc.)
      real(8) :: tauceff_t(numslip_all(matid))
!     Note the size of GND is different
!     gnd density (nslip + nscrew)
      real(8) :: gnd_t(numslip_all(matid)+numscrew_all(matid))
      real(8) :: gnd(numslip_all(matid)+numscrew_all(matid))
!
!     ssd density (nslip)
      real(8) :: ssd_t(numslip_all(matid))
      real(8) :: ssd(numslip_all(matid)),
     + ssd0(numslip_all(matid))
!     loop density (maxnloop)
      real(8) :: loop_t(maxnloop)
      real(8) :: loop(maxnloop), loop0(maxnloop)
!     total forest dislocation density - derived from other terms
      real(8) :: rhofor_t(numslip_all(matid))
      real(8) :: rhofor(numslip_all(matid)),
     + rhofor0(numslip_all(matid))
!     total density
      real(8) :: rhotot_t(numslip_all(matid))
      real(8) :: rhotot(numslip_all(matid))
!     forest dislocation density as a state variable
      real(8) :: forest_t(numslip_all(matid))
      real(8) :: forest(numslip_all(matid)),
     + forest0(numslip_all(matid))
!
!
!     Scalar state variables
!     equivalent Von-Mises plastic strain
      real(8) :: evmp_t
      real(8) :: evmp, evmp0
!
!     cumulative slip
      real(8) :: totgammasum_t
      real(8) :: totgammasum, totgammasum0
!     solute strength
      real(8) :: tausolute_t
      real(8) :: tausolute, tausolute0
!     substructure density
      real(8) :: substructure_t
      real(8) :: substructure, substructure0
!     total density
      real(8) :: ssdtot_t
      real(8) :: ssdtot, ssdtot0
!     scalar cumulartive density
      real(8) :: sumrhotot_t
      real(8) :: sumrhotot     
!
!     material-related local variables
!     number screw systems
      integer :: nscrew
!     slip model flag
      integer :: smodel
!     creep model flag
      integer :: cmodel
!     hardening model flag   
      integer :: hmodel
!     irradiation mdoel flag
      integer :: imodel
!     cubic slip flag
      integer :: cubicslip
!     material temperature
      real(8) :: mattemp
!     c/a ratio for hcp materials
      real(8) :: caratio
!     compliance at the crystal reference
      real(8) :: Cc(6,6)
!     geometric factor
      real(8) :: gf
!     shear modulus
      real(8) :: G12
!     Poisson's ratio
      real(8) :: v12
!     thermal expansion coefficient
      real(8) :: alphamat(3,3)
!     slip parameters
      real(8) :: sparam(maxnparam)
!     creep parameters
      real(8) :: cparam(maxnparam)
!     hardening parameters
      real(8) :: hparam(maxnparam)
!     irradiation parameters
      real(8) :: iparam(maxnparam)
!     Burgers vector
      real(8) :: burgerv(numslip_all(matid))
!     Interaction matrices
!     Strength interaction between dislocations
      real(8) :: sintmat1(numslip_all(matid),numslip_all(matid))
!     Strength interaction dislocation loops related with irradiation
      real(8) :: sintmat2(numslip_all(matid),numslip_all(matid))
!     Latent hardening
      real(8) :: hintmat1(numslip_all(matid),numslip_all(matid))
!     Hardening interaction matrix between dislocations
      real(8) :: hintmat2(numslip_all(matid),numslip_all(matid))
!
!
!     slip direction and slip plane normal at the crystal reference (undeformed)
      real(8) :: dirc_0(numslip_all(matid),3)
      real(8) :: norc_0(numslip_all(matid),3)
!     slip direction and slip plane normal at the sample reference
      real(8) :: dirs_t(numslip_all(matid),3)
      real(8) :: nors_t(numslip_all(matid),3)
!
!     Forest projection operators for GND and SSD
      real(8) :: forestproj(numslip_all(matid),
     + numslip_all(matid)+numscrew_all(matid))
!
!     Slip to screw system map
      real(8) :: slip2screw(numscrew_all(matid),numslip_all(matid))
!
!     Schmid Dyadic
      real(8) :: Schmid(numslip_all(matid),3,3)
      real(8) :: Schmidvec(numslip_all(matid),6)
      real(8) :: SchmidxSchmid(numslip_all(matid),6,6)
      real(8) :: sdir(3), ndir(3), SNij(3,3), NSij(3,3)
      real(8) :: nsi(6), sni(6)
!
!
!
!     strain calculations
!     total strain increment
      real(8) ::  dstran(6), dstran33(3,3)
!     thermal strain increment
      real(8) ::  dstranth33(3,3), dstranth(6)
!     total spin increment
      real(8) ::  domega(3)
!     total spin (rate) 3x3 matrix
      real(8) ::  W(3,3), dW33(3,3)
!     plastic part of the velocity gradient
      real(8) ::  Lp(3,3)
!
!     Elasticity transformation
!     temporary array for elastic stiffness calculation
      real(8) :: rot4(6,6)
!     elasticity matrix at the deformed reference
      real(8) :: Cs(6,6)     
!
!     Trial stress calculation
!     trial stress
      real(8) ::  sigmatr(6)
!
!     Backstress
      real(8) :: sigmab_t(6)
!
!     stress with rotations
      real(8) :: sigmarot_t(6)
!
!     stress (3x3)
      real(8) ::  sigma33_t(3,3)
!
!
!     Resolved shear stress calculation
!     GUESS values
      real(8) ::  sigma0(6), jacobi0(6,6)
!     value of resolved shear stress
      real(8) :: tau0(numslip_all(matid))
!     absolute value of resolved shear stress
      real(8) :: abstau0(numslip_all(matid))
!     sign of rsss
      real(8) :: signtau0(numslip_all(matid))
!
!     value of resolved shear stress
      real(8) :: tau_t(numslip_all(matid))
!     absolute value of resolved shear stress
      real(8) :: abstau_t(numslip_all(matid))
!     sign of rsss
      real(8) :: signtau_t(numslip_all(matid))
!
!     value of trial resolved shear stress
      real(8) :: tautr(numslip_all(matid))
!     absolute value of resolved shear stress
      real(8) :: abstautr(numslip_all(matid))
!     sign of rsss
      real(8) :: signtautr(numslip_all(matid))
!
!     dummy variables
      real(8) :: dummy3(3), dummy33(3,3)
      real(8) :: dummy33_(3,3)
      real(8) :: dummy6(6), dummy66(6,6)
      integer :: dum1, dum2, dum3
!     unused variables
      real(8) :: notused1(maxnslip)
      real(8) :: notused2(maxnslip)
      real(8) :: notused3(maxnslip)
!     In case materials subroutine entered everytime
!     Strength interaction between dislocations
      real(8) :: notused4(maxnslip,maxnslip)
!     Strength interaction dislocation loops related with irradiation
      real(8) :: notused5(maxnslip,maxnslip)
!     Latent hardening
      real(8) :: notused6(maxnslip,maxnslip)
!     Hardening interaction matrix between dislocations
      real(8) :: notused7(maxnslip,maxnslip)
!
!     counter
      integer :: is, i, j
!
!
!
!     Reset sparse arrays
      notused1=0.;notused2=0.;notused3=0.
      notused4=0.;notused5=0.
      notused6=0.;notused7=0.
!
!
!
!     convergence check initially
!     if sinh( ) in the slip law has probably blown up
!     then try again with smaller dt
      if(any(dfgrd1 /= dfgrd1)) then
!         Set the outputs to zero initially
          sigma = 0.
          jacobi = I6
!         cut back time
          pnewdt = cutback
!         warning message in .dat file
          call error(11)
!         go to the end of subroutine
          return
      end if
!     
!
!
!     phase-id
      phaid = phaseid_all(matid)
!
!     Number of slip systems
      nslip = numslip_all(matid)
!
!     Number of screw systems
      nscrew = numscrew_all(matid)
!
!
!
!
!     undeformed slip direction
      dirc_0 = dirc_0_all(matid,1:nslip,1:3)
      
!     undeformed slip plane normal
      norc_0 = norc_0_all(matid,1:nslip,1:3)      
!
!
!     Forest projection for GND
      forestproj = forestproj_all(matid,1:nslip,1:nslip+nscrew)
!
!
!     Slip to screw system mapping
      slip2screw = slip2screw_all(matid,1:nscrew,1:nslip)
!
!
!
!     Assign the global state variables
!     to the local variables
!     at the former time step
      gammasum_t = statev_gammasum_t(noel,npt,1:nslip)
      gammadot_t = statev_gammadot_t(noel,npt,1:nslip)
      tauc_t = statev_tauc_t(noel,npt,1:nslip)
      gnd_t = statev_gnd_t(noel,npt,1:nslip+nscrew)
      ssd_t = statev_ssd_t(noel,npt,1:nslip)
      loop_t = statev_loop_t(noel,npt,1:maxnloop)
      ssdtot_t = statev_ssdtot_t(noel,npt)
      forest_t = statev_forest_t(noel,npt,1:nslip)
      substructure_t = statev_substructure_t(noel,npt)
      evmp_t = statev_evmp_t(noel,npt)
      totgammasum_t = statev_totgammasum_t(noel,npt)
      tausolute_t = statev_tausolute_t(noel,npt)
      sigma_t = statev_sigma_t(noel,npt,:)
      Fp_t = statev_Fp_t(noel,npt,:,:)
      Fth_t = statev_Fth_t(noel,npt,:,:)
      Eec_t = statev_Eec_t(noel,npt,:)
!     Crystal orientations at former time step
      gmatinv_t = statev_gmatinv_t(noel,npt,:,:)
!     Backstress
      sigmab_t = statev_backstress_t(noel,npt,:)
!
!
!     Material parameters are constant
      caratio = caratio_all(matid)
      cubicslip = cubicslip_all(matid)
      Cc = Cc_all(matid,:,:)
      gf = gf_all(matid)
      G12 = G12_all(matid)
      alphamat = alphamat_all(matid,:,:)
      burgerv = burgerv_all(matid,1:nslip)
!
!
      sintmat1 = sintmat1_all(matid,1:nslip,1:nslip)
      sintmat2 = sintmat2_all(matid,1:nslip,1:nslip)
      hintmat1 = hintmat1_all(matid,1:nslip,1:nslip)
      hintmat2 = hintmat2_all(matid,1:nslip,1:nslip)
!
!
!
      smodel = slipmodel_all(matid)
      sparam = slipparam_all(matid,1:maxnparam)
      cmodel = creepmodel_all(matid)
      cparam = creepparam_all(matid,1:maxnparam)
      hmodel = hardeningmodel_all(matid)
      hparam = hardeningparam_all(matid,1:maxnparam)
      imodel = irradiationmodel_all(matid)
      iparam = irradiationparam_all(matid,1:maxnparam)
!
!
!
!
!     Temperature is constant and defined by the user
      if (constanttemperature == 1) then
!
!
!         Assign temperature
          mattemp = temperature
!
!
!
!     Temperature is defined by ABAQUS
!     Material properties are entered every time
!     Because properties can be temperature dependent
      else if (constanttemperature == 0) then
!
!         Use ABAQUS temperature (must be in K)
          mattemp = temp
!
!
!         get material constants
          call materialparam(matid,mattemp,
     + dum1,dum2,dum3,caratio,cubicslip,Cc,
     + gf,G12,v12,alphamat,notused1, ! state variables are NOT updated here
     + notused2,notused3, !forest and substructure also need to be added
     + smodel,sparam,cmodel,cparam,
     + hmodel,hparam,imodel,iparam,
     + notused4,notused5,notused6,
     + notused7) ! Interaction matrices are not updated here
!
!
!  
!    
!
      end if
!
!
!
!
!
!
!
!     Slip directions in the sample reference
      call rotateslipsystems(phaid,nslip,caratio,
     + gmatinv_t,dirc_0,norc_0,dirs_t,nors_t)
!
!
!     Calculate Schmid tensors and Schmid dyadic
      Schmid=0.; SchmidxSchmid=0.
      do is=1,nslip
!
!         Slip direction
          sdir = dirs_t(is,:)
!         Slip plane normal
          ndir = nors_t(is,:)
!
          do i=1,3
              do j=1,3
                  SNij(i,j) = sdir(i)*ndir(j)
                  NSij(i,j) = ndir(j)*sdir(i)
                  Schmid(is,i,j) = SNij(i,j)
              enddo
          enddo
!
!
!
!
          call gmatvec6(SNij,sni)
!
          call gmatvec6(NSij,nsi)
!
!         Vectorized Schmid tensor
          Schmidvec(is,1:6) = sni
!
          do i=1,6
              do j=1,6
                  SchmidxSchmid(is,i,j)=sni(i)*nsi(j)
              enddo
          enddo
!
      enddo
!
!
!
!     Calculate total and forest density
      call totalandforest(phaid, nscrew, nslip,
     + gnd_t, ssd_t,
     + ssdtot_t, forest_t,
     + forestproj, slip2screw, rhotot_t,
     + sumrhotot_t, rhofor_t)
!
!
!
!     Calculate crss
      call slipresistance(phaid, nslip, gf, G12,
     + burgerv, sintmat1, sintmat2, tauc_t,
     + rhotot_t, sumrhotot_t, rhofor_t, substructure_t,
     + tausolute_t, loop_t, hmodel, hparam, imodel, iparam,
     + mattemp, tauceff_t)
!
!
!
!
!     Elastic stiffness in the sample reference
!
!     Rotation matrix - special for symmetric 4th rank transformation
      call rotord4sig(gmatinv_t,rot4)
!
!
!
!     Elasticity tensor in sample reference
      dummy66=matmul(rot4,Cc)
      Cs = matmul(dummy66,transpose(rot4))
!
!!     To avoid numerical problems
!      Cs = (Cs + transpose(Cs))/2.
!
!
!
!
!
!     CALCULATION OF THERMAL STRAINS
!
!     No thermal strains
      if (constanttemperature == 1) then
!
!
          dstranth = 0.
!
          F = dfgrd1
!
          F_t = dfgrd0
!
          Fth = Fth_t
!
!     Thermal strains if temperature change is defined by ABAQUS
      else
!
!         Thermal eigenstrain in the crystal reference system
          dstranth33 = dtemp*alphamat
!
!         Transform the thermal strains to sample reference
          dstranth33 = matmul(matmul(gmatinv,dstranth33),
     + transpose(gmatinv))
!
!
!
!
!
!         Convert to a vector
          call matvec6(dstranth33,dstranth)
!
!         Shear corrections
          dstranth(4:6) = 2.0*dstranth(4:6)
!
!
!
!         Thermal deformation gradient
          Fth = Fth_t + dstranth33 
!
!         Invert the thermal distortions
          call inv3x3(Fth,invFth,detFth)
!
          call inv3x3(Fth_t,invFth_t,detFth_t)
!
!         Take out the thermal distortions from the total deformation
          F = matmul(dfgrd1,invFth)
!
          F_t = matmul(dfgrd0,invFth_t)
!
!
!
      end if
!     
!
!
!
!     MECHANICAL PART OF THE DEFORMATION GRADIENT
!     Calculate velocity gradient
!     Rate of deformation gradient
      Fdot = (F - F_t) / dt
!
!     Inverse of the deformation gradient
      call inv3x3(F,Finv,detF)
!
!     Velocity gradient
      L = matmul(Fdot,Finv)
!
!
!
!
!
!
!     CALCULATION OF TOTAL & MECHANICAL STRAINS      
!
!     Total stain increment from velocity gradient
      dstran33=(L+transpose(L))*0.5*dt
!
!
!
      call matvec6(dstran33,dstran)
!
!     Shear corrections
      dstran(4:6) = 2.0*dstran(4:6)
!
!
!     Total spin
      W=(L-transpose(L))*0.5
!     
!
!
!     Total spin increment - components
!     This is corrected as follows: Eralp - Alvaro 19.02.2023
!     The solution in Huang et al gives the negative -1/2*W
!     We obtained the spin directly from velocity gradient
!     1. It is positive
!     2. It has to be divided by 2
      domega(1) = W(1,2) - W(2,1)
      domega(2) = W(3,1) - W(1,3)
      domega(3) = W(2,3) - W(3,2)
      domega = domega * dt / 2.
!
!
!     MODIFICATION FOR BACKSTRESSS
      sigma_t = sigma_t - sigmab_t
!
!
!     Store the stress before rotation correction
      sigmarot_t = sigma_t
!
!
!     CALCULATION OF TRIAL STRESS
!
!     Trial stress
      sigmatr =  sigma_t + matmul(Cs,dstran)
!
!
!
!     3x3 stress tensor
      call vecmat6(sigma_t,sigma33_t)
!
!
!
!         Co-rotational stress
          sigma33_t = sigma33_t +
     + (matmul(W,sigma33_t) -
     + matmul(sigma33_t,W))*dt
!
!
!
!     Vectorize the initial guess
      call matvec6(sigma33_t,sigma_t)
!
!
!
!
!     CALCULATE RESOLVED SHEAR STRESS ON SLIP SYSTEMS
!     rss and its sign
      do is = 1, nslip
          tau_t(is) = dot_product(Schmidvec(is,:),sigma_t)
          signtau_t(is) = sign(1.0,tau_t(is))
          abstau_t(is) = abs(tau_t(is))
      end do
!
!
!
!     CALCULATE TRIAL-RESOLVED SHEAR STRESS ON SLIP SYSTEMS
!     rss and its sign
      do is = 1, nslip
          tautr(is) = dot_product(Schmidvec(is,:),sigmatr)
          signtautr(is) = sign(1.0,tautr(is))
          abstautr(is) = abs(tautr(is))
      end do
!
!
!     maximum ratio of rss to crss
      maxx = maxval(abstautr/tauceff_t)
!
!
!
!
!     DECISION FOR USING CRYSTAL PLASTICITY
!     BASED ON THRESHOLD VALUE
!
!     Elastic solution
      if (maxx <= maxxcr) then
!
!
!
!
!         stress
          sigma = sigmatr
!
!         material tangent
          jacobi = Cs
!
!
!         Assign the global state variables
!         For NO SLIP condition
          totgammasum=totgammasum_t
          gammasum=gammasum_t
          gammadot=0.
          tauc=tauc_t
          gnd=gnd_t
          ssd=ssd_t
          loop = loop_t
          ssdtot=ssdtot_t
          forest=forest_t
          substructure=substructure_t
          evmp=evmp_t
          tausolute=tausolute_t
          Fp=Fp_t
!
!
!         Elastic strains in the crystal lattice
!         Add the former elastic strains
!
!         Undo shear corrections
          dummy6 = dstran
          dummy6(4:6) = 0.5*dummy6(4:6)
!
!         Convert the strain into matrix
          call vecmat6(dummy6,dummy33)
!
!         Elastic strains in the crystal reference
          dummy33_ = matmul(transpose(gmatinv),dummy33)
          dummy33 = matmul(dummy33_,gmatinv)
!
!
!         Vectorize
          call matvec6(dummy33,dummy6)  
!
!         Shear corrections
          dummy6(4:6) = 2.0*dummy6(4:6)
!
          Eec=Eec_t+dummy6
!
!         Update orietnations
!         All the orientation changes are elastic - rotations
          dW33=0.
          dW33(1,2) = domega(1)
          dW33(1,3) = -domega(2)
          dW33(2,1) = -domega(1)
          dW33(2,3) = domega(3)
          dW33(3,1) = domega(2)
          dW33(3,2) = -domega(3)
!
          gmatinv = gmatinv_t + matmul(dW33,gmatinv_t)
!
!
!
!     Solve using crystal plasticity
      else
! 
!
!
!         Guess if Forward Gradient Predictor scheme is not active
          if (predictor == 0) then
!
              sigma0 = (1.-phi)*sigma_t + phi*sigmatr
!
!         Else Forward Gradient Predictor scheme computes sigma0
          elseif (predictor == 1) then
!
!
              call CP_ForwardGradientPredictor(
     + matid, phaid, nslip, nscrew,
     + mattemp, Cs, gf, G12,
     + burgerv, cubicslip, caratio,
     + Fp_t, gmatinv_t, Eec_t,
     + gammadot_t, gammasum_t,
     + totgammasum_t, evmp_t, sigmarot_t,
     + forestproj, slip2screw, dirs_t, nors_t,
     + Schmidvec, Schmid, SchmidxSchmid,
     + smodel, sparam,
     + cmodel, cparam,
     + imodel, iparam,
     + hmodel, hparam,
     + sintmat1, sintmat2,
     + hintmat1, hintmat2,
     + tauceff_t, tauc_t, rhotot_t,
     + sumrhotot_t, ssdtot_t,
     + rhofor_t, forest_t, substructure_t,
     + gnd_t, ssd_t, loop_t,
     + dt, dstran, domega,
     + Fp0, gmatinv0, Eec0,
     + gammadot0, gammasum0,
     + totgammasum0, evmp0,
     + tauc0, tausolute0,
     + ssdtot0, ssd0, loop0,
     + forest0, substructure0,
     + sigma0, jacobi0, cpconv0)
!
!
!
              if (cpconv0==0) then
                  sigma0 = (1.-phi)*sigma_t + phi*sigmatr
              endif
!
!
!
!         This part is added by Chris Hardie (11/05/2023)   
!         Former stress scheme
          elseif (predictor == 2) then
!
!
!
              if (dt_t > 0.0) then
!
              do i = 1, 6
                  sigma0(i) =
     + statev_sigma_t(noel,npt,i) +
     + (statev_sigma_t(noel,npt,i) -
     + statev_sigma_t2(noel,npt,i))*dt/dt_t
              end do
!
              else
                  sigma0 = sigma_t
              end if
!
!
!
!         
!
!
!
!
!
!
          end if
!
!
!         CALCULATE RESOLVED SHEAR STRESS ON SLIP SYSTEMS
!         rss and its sign
          do is = 1, nslip
              tau0(is) = dot_product(Schmidvec(is,:),sigma0)
              signtau0(is) = sign(1.0,tau0(is))
              abstau0(is) = abs(tau0(is))
          end do
!
!
!         Explicit time integration of states
          if (explicit==1) then
!
!
!
!             Solve using explicit crystal plasticity solver
              call CP_DunneExplicit(matid, phaid,
     + nslip, mattemp, Cs, gf, G12,
     + burgerv, cubicslip, caratio,
     + Fp_t, gmatinv_t, Eec_t,
     + gammadot_t, gammasum_t,
     + totgammasum_t, evmp_t,
     + sigma0, abstau0, signtau0, sigmatr,
     + Schmid, Schmidvec, SchmidxSchmid,  
     + smodel, sparam, cmodel, cparam,
     + imodel, iparam, hmodel, hparam,
     + sintmat1, sintmat2,
     + hintmat1, hintmat2,
     + tauceff_t, tauc_t,
     + rhotot_t, sumrhotot_t,
     + ssdtot_t, rhofor_t,
     + forest_t, substructure_t,
     + ssd_t, loop_t, dt, L, dstran,
     + Lp, Fp, gmatinv, Eec,
     + gammadot, gammasum,
     + totgammasum, evmp,
     + tauc, tausolute,
     + ssdtot, ssd, loop, forest, substructure,
     + sigma, jacobi, cpconv)
!
!
!
!         Implicit time integration of states
          elseif (explicit==0) then
!
!
              call CP_DunneImplicit(matid, phaid,
     + nslip, nscrew, mattemp, Cs, gf, G12,
     + burgerv, cubicslip, caratio,
     + Fp_t, gmatinv_t, Eec_t,
     + gammadot_t, gammasum_t,
     + totgammasum_t, evmp_t,
     + sigma0, abstau0, signtau0,
     + sigmatr, forestproj, slip2screw,
     + Schmid, Schmidvec, SchmidxSchmid,
     + smodel, sparam, cmodel, cparam,
     + imodel, iparam, hmodel, hparam,
     + sintmat1, sintmat2,
     + hintmat1, hintmat2,
     + tauceff_t, tauc_t, rhotot_t,
     + sumrhotot_t, ssdtot_t,
     + rhofor_t, forest_t, substructure_t,
     + gnd_t, ssd_t, loop_t, dt, L, dstran,
     + Lp, Fp, gmatinv, Eec,
     + gammadot, gammasum,
     + totgammasum, evmp,
     + tauc, tausolute,
     + ssdtot, ssd, loop, forest, substructure,
     + sigma, jacobi, cpconv)
!
!
!
!
          endif
!
!
!
!
!
!         If stress-based Dunne crystal plasticity DOES NOT CONVERGE
          if (cpconv == 0) then
!             If Forward Gradient Predictor solution available
!             Use the Eulersolver result (if turned ON)
              if (predictor == 1) then
!
!
!                 If Forward Gradient Predictor solution converged
                  if (cpconv0 == 1) then
!
!                     USE Forward Gradient Predictor SOLUTION AS THE SOLUTION
                      Fp = Fp0
                      gmatinv = gmatinv0
                      Eec = Eec0
                      gammadot = gammadot0
                      gammasum = gammasum0
                      totgammasum = totgammasum0
                      evmp = evmp0
                      tauc= tauc0
                      tausolute = tausolute
                      ssdtot = ssdtot0
                      ssd = ssd0
                      loop = loop0
                      forest = forest0
                      substructure = substructure0
                      sigma = sigma0
                      jacobi =jacobi0
                      cpconv = cpconv0
!
!
!
                  endif
!
              endif
!
!
!
          endif
!
!
!         STILL NOT CONVERGED THE CUTBACK TIME
!         Convergence check
!         Use cpsolver did not converge
!         Diverged! - use time cut backs
          if (cpconv == 0) then         
!
!             Set the outputs to zero initially
              sigma = statev_sigma_t(noel,npt,:)
              jacobi = statev_jacobi_t(noel,npt,:,:)
!             Set time cut back and send a message
              pnewdt = cutback
              call error(14)
!
          endif
!
!
!
!
      endif
!
!
!
!
!
!
!     Assign the global state variables          
      statev_gammasum(noel,npt,1:nslip)=gammasum
      statev_gammadot(noel,npt,1:nslip)=gammadot
      statev_tauc(noel,npt,1:nslip)=tauc
      statev_ssd(noel,npt,1:nslip)=ssd
      statev_loop(noel,npt,1:maxnloop)=loop
      statev_ssdtot(noel,npt)=ssdtot
      statev_forest(noel,npt,1:nslip)=forest
      statev_substructure(noel,npt)=substructure
      statev_evmp(noel,npt)=evmp
      statev_maxx(noel,npt)=maxx
      statev_totgammasum(noel,npt)=totgammasum
      statev_tausolute(noel,npt)=tausolute
      statev_sigma(noel,npt,1:6)=sigma
      statev_jacobi(noel,npt,1:6,1:6)=jacobi
      statev_Fp(noel,npt,1:3,1:3)=Fp
      statev_Fth(noel,npt,1:3,1:3)=Fth
      statev_Eec(noel,npt,1:6)=Eec
!     Crystal orientations at former time step
      statev_gmatinv(noel,npt,1:3,1:3)=gmatinv
!
!
!     Write the outputs for post-processing
!     If outputs are defined by the user
      if (nstatv_outputs>0) then
!
          call assignoutputs(noel,npt,nstatv,statev)
!
      end if
!
!
!
!
!
!
      return
      end subroutine solve
!
!
!
!
!
!
!
!
!
!
!     Explicit state update rule
!     Solution using state variables at the former time step
      subroutine CP_DunneExplicit(matid, phaid,
     + nslip, mattemp, Cs, gf, G12,
     + burgerv, cubicslip, caratio,
     + Fp_t, gmatinv_t, Eec_t,
     + gammadot_t, gammasum_t,
     + totgammasum_t, evmp_t,
     + sigma0, abstau0, signtau0, sigmatr,
     + Schmid, Schmidvec, SchmidxSchmid,  
     + slipmodel, slipparam,
     + creepmodel, creepparam,
     + irradiationmodel, irradiationparam,
     + hardeningmodel, hardeningparam,
     + sintmat1, sintmat2,
     + hintmat1, hintmat2,
     + tauceff_t, tauc_t, rhotot_t,
     + sumrhotot_t, ssdtot_t,
     + rhofor_t, forest_t, substructure_t,
     + ssd_t, loop_t, dt, L, dstran,
     + Lp, Fp, gmatinv, Eec,
     + gammadot, gammasum,
     + totgammasum, evmp,
     + tauc, tausolute,
     + ssdtot, ssd, loop, forest, substructure,
     + sigma, jacobi, cpconv)
!
      use globalvariables, only : I3, I6, smallnum
!
      use userinputs, only : maxniter, tolerance,
     + maxnparam, maxnloop, quadprec, SVDinversion
!
      use utilities, only : vecmat6, matvec6,
     + nolapinverse, deter3x3, inv3x3, trace3x3,
     + vecmat9, matvec9, nolapinverse16, nolapinverse,
     + SVDinverse
!
      use slip, only : sinhslip, doubleexpslip,
     + powerslip
!
      use creep, only : expcreep
!
      use hardening, only: hardeningrules
!
      use errors, only : error
!
      implicit none
!
!
!     INPUTS
!
!     material-id
      integer, intent(in) :: matid
!     phase-id
      integer, intent(in) :: phaid
!     number of slip sytems
      integer, intent(in) :: nslip
!     temperature
      real(8), intent(in) :: mattemp
!     elastic compliance
      real(8), intent(in) :: Cs(6,6)
!     geometric factor
      real(8), intent(in) :: gf
!     elastic shear modulus
      real(8), intent(in) :: G12
!     Burgers vectors
      real(8), intent(in) :: burgerv(nslip)
!     flag for cubic slip systems
      integer, intent(in) :: cubicslip
!     c/a ratio for hcp crystals
      real(8), intent(in) :: caratio
!     plastic part of the deformation gradient at former time step
      real(8), intent(in) :: Fp_t(3,3)
!     Crystal to sample transformation martrix at former time step
      real(8), intent(in) :: gmatinv_t(3,3)
!     Lattice strains
      real(8), intent(in) :: Eec_t(6)
!     slip rates at the former time step
      real(8), intent(in) :: gammadot_t(nslip)
!     total slip per slip system accumulated over the time
!     at the former time step
      real(8), intent(in) :: gammasum_t(nslip)
!     overall total slip at the former time step
      real(8), intent(in) :: totgammasum_t
!     Von-Mises equivalent total plastic strain at the former time step
      real(8), intent(in) :: evmp_t
!     Cauchy stress guess
      real(8), intent(in) :: sigma0(6)
!     rss guess
      real(8), intent(in) :: abstau0(nslip)
!     sign of rss guess
      real(8), intent(in) :: signtau0(nslip)
!     trial stress
      real(8), intent(in) :: sigmatr(6)
!     Schmid tensor
      real(8), intent(in) :: Schmid(nslip,3,3)  
!     Vectorized Schmid tensor
      real(8), intent(in) :: Schmidvec(nslip,6)  
!     Schmid dyadic
      real(8), intent(in) :: SchmidxSchmid(nslip,6,6)
!     slip model no.
      integer, intent(in) :: slipmodel
!     slip model parameters
      real(8), intent(in) :: slipparam(maxnparam)
!     creep model no.
      integer, intent(in) :: creepmodel
!     creep model parameters
      real(8), intent(in) :: creepparam(maxnparam)    
!     irrradiation model no.
      integer, intent(in) :: irradiationmodel
!     irradiation model parameters
      real(8), intent(in) :: irradiationparam(maxnparam)        
!     hardening model no.
      integer, intent(in) :: hardeningmodel
!     hardening model parameters
      real(8), intent(in) :: hardeningparam(maxnparam)
!
!     Interaction matrices
!     Strength interaction between dislocations
      real(8), intent(in) :: sintmat1(nslip,nslip)
!     Strength interaction dislocation loops related with irradiation
      real(8), intent(in) :: sintmat2(nslip,nslip)
!     Latent hardening
      real(8), intent(in) :: hintmat1(nslip,nslip)
!     Hardening interaction matrix between dislocations
      real(8), intent(in) :: hintmat2(nslip,nslip)
!
!
!     overall crss
      real(8), intent(in) :: tauceff_t(nslip)
!     crss at former time step
      real(8), intent(in) :: tauc_t(nslip)
!     total dislocation density over all slip systems at the former time step
      real(8), intent(in) :: rhotot_t(nslip)
!     total scalar dislocation density over all slip systems at the former time step
      real(8), intent(in) :: sumrhotot_t
!     total dislocation density over all slip systems at the former time step
      real(8), intent(in) :: ssdtot_t
!     total forest dislocation density per slip system at the former time step
      real(8), intent(in) :: rhofor_t(nslip)
!     forest dislocation density per slip system at the former time step (hardening model = 4)
      real(8), intent(in) :: forest_t(nslip)
!     substructure dislocation density at the former time step
      real(8), intent(in) :: substructure_t
!     statistically-stored dislocation density per slip system at the former time step
      real(8), intent(in) :: ssd_t(nslip)
!     defect loop density per slip system at the former time step
      real(8), intent(in) :: loop_t(maxnloop)
!     time increment
      real(8), intent(in) :: dt
!     total velocity gradient at the current time step
      real(8), intent(in) :: L(3,3)
!     mechanical strain increment
      real(8), intent(in) :: dstran(6)
!
!
!
!     OUTPUTS
!
!     plastic velocity gradient
      real(8), intent(out) :: Lp(3,3)
!     plastic part of the deformation gradient
      real(8), intent(out) :: Fp(3,3)
!     Crystal to sample transformation martrix at current time step
      real(8), intent(out) :: gmatinv(3,3)
!     Green-Lagrange strains in the crystal reference
      real(8), intent(out) :: Eec(6)
!     slip rates at the current time step
      real(8), intent(out) :: gammadot(nslip)
!     total slip per slip system accumulated over the time
!     at the current time step
      real(8), intent(out) :: gammasum(nslip)
!     overall total slip at the current time step
      real(8), intent(out) :: totgammasum
!     Von-Mises equivalent total plastic strain at the current time step
      real(8), intent(out) :: evmp
!     crss at the current time step
      real(8), intent(out) :: tauc(nslip)
!     solute strength due to irradiation hardening
      real(8), intent(out) :: tausolute
!     total dislocation density over all slip systems at the current time step
      real(8), intent(out) :: ssdtot
!     forest dislocation density per slip system at the current time step
      real(8), intent(out) :: forest(nslip)
!     substructure dislocation density at the current time step
      real(8), intent(out) :: substructure
!     statistically-stored dislocation density per slip system at the current time step
      real(8), intent(out) :: ssd(nslip)
!     defect loop density per slip system at the current time step
      real(8), intent(out) :: loop(maxnloop)
!     Cauchy stress
      real(8), intent(out) :: sigma(6)
!     material tangent
      real(8), intent(out) :: jacobi(6,6)
!     convergence flag
      integer, intent(out) :: cpconv
!
!
!     Local variables used within this subroutine
!
!     plastic velocity gradient for slip
      real(8) Lp_s(3,3)
!     plastic velocity gradient for creep
      real(8) Lp_c(3,3)
!     plastic tangent stiffness for slip
      real(16) Pmat_s(6,6)
!     plastic tangent stiffness for creep
      real(16) Pmat_c(6,6)
!     tangent matrix for NR iteration
      real(16) Pmat(6,6)
!     slip rates for slip
      real(16) gammadot_s(nslip)
!     slip rates for creep
      real(16) gammadot_c(nslip)
!     derivative of slip rates wrto rss for slip
      real(8) dgammadot_dtau_s(nslip)
!     derivative of slip rates wrto rss for creep
      real(8) dgammadot_dtau_c(nslip)
!     derivative of slip rates wrto rss for slip
      real(8) dgammadot_dtauc_s(nslip)
!     derivative of slip rates wrto rss for creep
      real(8) dgammadot_dtauc_c(nslip)
!
!     rss at the former time step
      real(8) :: tau(nslip)
!     absolute value of rss at the former time step
      real(8) :: abstau(nslip)
!     sign of rss at the former time step
      real(8) :: signtau(nslip)
!
!     Jacobian of the Newton-Raphson loop
!     and its inverse
      real(16) :: dpsi_dsigma16(6,6), invdpsi_dsigma16(6,6)
      real(8)  :: dpsi_dsigma(6,6), invdpsi_dsigma(6,6)
!     residual of the Newton-Raphson loop
!     vector and scalar
      real(8) :: psinorm, psi(6)
!
!     plastic strain increment
      real(8) :: plasstraininc33(3,3), plasstraininc(6)
!
!     plastic strain rate
      real(8) :: plasstrainrate(3,3)
!
!     Von-Mises equivalent plastic strain rate and increment
      real(8) :: pdot, dp
!
!     stress increment
      real(8) :: dsigma(6)
!
!     stress 3x3 matrix
      real(8) :: sigma33(3,3)
!
!     plastic part of the deformation gradient
      real(8) :: detFp, invFp(3,3)
!
!     elastic part of the deformation gradient
      real(8) :: Fe(3,3)
!
!     elastic part of the velocity gradient
      real(8) :: Le(3,3)
!
!     elastic spin
      real(8) :: We(3,3)
!
!     increment in rotation matrix
      real(8) :: dR(3,3)
!
!     Von-Mises stress
      real(8) :: sigmaii, vms, sigmadev(3,3)
!
!     Co-rotational stress update
      real(8) :: dotsigma33(3,3)
!
!     Total mechanical strain increment
      real(8) :: dstran33(3,3)
!
!     Plastic strain increment
      real(8) :: dstranp33(3,3)
!
!     elastic strain increment
      real(8) :: dstrane33(3,3)
!
!     crss increment
      real(8) :: dtauc(nslip)
!
!     ssd density increment
      real(8) :: dssd(nslip)
!
!     ssd density increment
      real(8) :: dloop(maxnloop)
!
!     total ssd density increment
      real(8) :: dssdtot
!
!     forest dislocation density increment
      real(8) :: dforest(nslip)
!
!     substructure dislocation density increment
      real(8) :: dsubstructure
!
!
!
!     error flag for svd inversion
      integer :: err
!
!     other variables
      real(8) :: dummy3(3), dummy33(3,3),
     + dummy33_(3,3), dummy6(6), dummy0
      integer :: is, il, iter
!   
!     
!
!
!
!     Set convergence flag
      cpconv = 1
!
!
!     Reset variables for iteration   
      iter = 0
      psinorm = 1.
!
!
!     Initial guess for NR scheme
!     Stress at the former time step
      sigma = sigma0
      abstau = abstau0
      signtau =signtau0
!
!
!
!     Newton-Raphson (NR) iteration to find stress increment
      do while ((psinorm >= tolerance).and.(iter <= maxniter))
!
!         increment iteration no.
          iter = iter + 1
!
!
!         Slip models to find slip rates
!
!         none
          if (slipmodel == 0) then
!
              Lp_s = 0.
              Pmat_s = 0.
              gammadot_s = 0.
              dgammadot_dtau_s = 0.
              dgammadot_dtauc_s = 0.
!
!         sinh law
          elseif (slipmodel == 1) then
!
              call sinhslip(Schmid,SchmidxSchmid,
     + abstau,signtau,tauceff_t,rhofor_t,burgerv,dt,
     + nslip,phaid,mattemp,slipparam,
     + irradiationmodel,irradiationparam,
     + cubicslip,caratio,Lp_s,Pmat_s,
     + gammadot_s,dgammadot_dtau_s,
     + dgammadot_dtauc_s)
!
!
!         double exponent law (exponential law)
          elseif (slipmodel == 2) then
!
!
             call doubleexpslip(Schmid,SchmidxSchmid,
     + abstau,signtau,tauceff_t,burgerv,dt,nslip,phaid,
     + mattemp,slipparam,irradiationmodel,
     + irradiationparam,cubicslip,caratio,
     + Lp_s,Pmat_s,gammadot_s,
     + dgammadot_dtau_s,dgammadot_dtauc_s) 
!
!
!         power law
          elseif (slipmodel == 3) then
!
!
              call powerslip(Schmid,SchmidxSchmid,
     + abstau,signtau,tauceff_t,burgerv,dt,
     + nslip,phaid,mattemp,slipparam,
     + irradiationmodel,irradiationparam,
     + cubicslip,caratio,Lp_s,Pmat_s,
     + gammadot_s,dgammadot_dtau_s,
     + dgammadot_dtauc_s)
!
!
          end if
!
!
!
!         Slip due to creep
          if (creepmodel == 0) then
!
              Lp_c = 0.
              Pmat_c = 0.
              gammadot_c = 0.
              dgammadot_dtau_c = 0.
              dgammadot_dtauc_c = 0.
!
          elseif (creepmodel == 1) then
!
!
              call expcreep(Schmid,SchmidxSchmid,
     + abstau,signtau,tauceff_t,dt,nslip,phaid,
     + mattemp,creepparam,gammasum,
     + Lp_c,Pmat_c,gammadot_c,
     + dgammadot_dtau_c,dgammadot_dtauc_c)
!
!
!
!
          endif
!
!
!         Sum the effects of creep and slip rates
          Lp = Lp_s + Lp_c
          Pmat = Pmat_s + Pmat_c
          gammadot = gammadot_s + gammadot_c
!
!
!
!
!
!         Check for the Pmat
          if(any(Pmat /= Pmat)) then
!             did not converge
              cpconv = 0
!             enter dummy stress and jacobian
              sigma = 0.
              jacobi = I6
!             return to end of the subroutine
!             warning message
              call error(15)
              return
          endif
!
!
!         plastic strain rate
          plasstrainrate = (Lp + transpose(Lp))/2.
!
!
!         Plastic strain increment
          plasstraininc33 = plasstrainrate*dt
          call matvec6(plasstraininc33,plasstraininc)
          plasstraininc(4:6)=2.*plasstraininc(4:6)
!
!
!
!
!         Tangent-stiffness calculation
!         Jacobian of the Newton loop (see Dunne, Rugg, Walker, 2007)
          dpsi_dsigma16 = I6 + matmul(Cs, Pmat)
!
!         Assign to the double precision
          dpsi_dsigma = dpsi_dsigma16
!
!         If quad-precision during inverse is ON
          if (quadprec == 1) then
!
!             invert the stiffness
              call nolapinverse16(dpsi_dsigma16,invdpsi_dsigma16,6)
!
!             convert back to 8-bits
              invdpsi_dsigma = invdpsi_dsigma16
!
          else
!
!
!             Check for the dpsi_dsigma
!             Infinity check
              if(any(dpsi_dsigma>huge(dpsi_dsigma))) then
!                 did not converge
                  cpconv = 0
!                 enter dummy stress and jacobian
                  sigma = 0.
                  jacobi = I6
!                 return to end of the subroutine
!                 warning message
                  call error(15)
                  return
              endif
!
!
!
!             Then invert (double precision version)
              call nolapinverse(dpsi_dsigma,invdpsi_dsigma,6)
!
          end if
!
!
!
!
!
!         If inversion is not successfull!
!         Check for the inverse
          if(any(invdpsi_dsigma /= invdpsi_dsigma)) then
!
!             Try using singular value decomposition
!             If singular value decomposition is ON
              if (SVDinversion==1) then
!
!
!                 Invert
                  call SVDinverse(dpsi_dsigma,6,invdpsi_dsigma,err)
!
              else
!
                  err = 1
!
              endif
!
!
!
!
              if (err==1) then
!                 did not converge
                  cpconv = 0
!                 enter dummy stress and jacobian
                  sigma = 0.
                  jacobi = I6
!                 return to end of the subroutine
!                 warning message
                  call error(15)
                  return
              end if
!
!
!
!
!
!
!
!
!
          endif
!
!
!
!
!
!
!
!
!
!         residual (predictor - corrector)
          psi = sigmatr - sigma - matmul(Cs,plasstraininc)
!
!         norm of the residual
          psinorm = sqrt(sum(psi*psi))
!
!
!         stress increment
          dsigma = matmul(invdpsi_dsigma,psi)
!
!
!         stress update
          sigma = sigma + dsigma
!
!         convert it to 3x3 marix
          call vecmat6(sigma,sigma33)
!
!
!         calculate resolved shear stress on slip systems
!         rss and its sign
          do is = 1, nslip
              tau(is) = dot_product(Schmidvec(is,:),sigma)
              signtau(is) = sign(1.0,tau(is))
              abstau(is) = abs(tau(is))
          end do
!
!
!
!     End of NR iteration
      end do
!
!
!
!
!
!
!
!
!
!     convergence check
      if (iter == maxniter) then
!         did not converge
          cpconv = 0
!         enter dummy stress and jacobian
          sigma = 0.
          jacobi = I6
!         return to end of the subroutine
!         warning message
          call error(16)
          return
      end if
!
!
!     calculate jacobian
      jacobi = matmul(invdpsi_dsigma,Cs)
!
!
!
!     Check for NaN in the stress vector
      if(any(sigma/=sigma)) then
!         did not converge
          cpconv = 0
!         enter dummy stress and jacobian
          sigma = 0.
          jacobi = I6
!         return to end of the subroutine
!         warning message
          call error(17)
          return
      endif
!
!
!     Check for NaN in the jacobi matrix
      if(any(jacobi/=jacobi))  then
!         did not converge
          cpconv = 0
!         enter dummy stress and jacobian
          sigma = 0.
          jacobi = I6
!         return to end of the subroutine
!         warning message
          call error(18)
          return
      endif
!
!
!
!     calculate von mises invariant plastic strain rate
      pdot=sqrt(2./3.*sum(plasstrainrate*plasstrainrate))
!
!     Total plastic strain increment
      dp = pdot*dt
!
!     Von-Mises equivalent total plastic strain
      evmp = evmp_t + dp
!
!     Total slip over time per slip system
      gammasum = 0.
      do is =1, nslip
!
          gammasum(is) = gammasum_t(is) +
     + abs(gammadot(is))*dt
!
      enddo
!
!
!     Total slip
      totgammasum = totgammasum_t +
     + sum(abs(gammadot))*dt
!
!
!
!
!
!
!     Trace of stress
      call trace3x3(sigma33,sigmaii)
!
!     deviatoric stress
      sigmadev = sigma33 - sigmaii*I3/3.
!
!     Von-Mises stress
      vms = sqrt(3./2.*(sum(sigmadev*sigmadev)))
!
!
!     variables for plastic part of the deformation gradient
      dummy33 = I3 - Lp*dt
      call inv3x3(dummy33,dummy33_,dummy0)
!
!     plastic part of the deformation gradient
      Fp = matmul(dummy33_,Fp_t)
!
!     determinant
      call deter3x3(Fp,detFp)
!
!
!
!
!     check wheter the determinant is negative
!     or close zero
      if (detFp <= smallnum) then
!         did not converge
          cpconv = 0
!         enter dummy stress and jacobian
          sigma = 0.
          jacobi = I6
!         return to end of the subroutine
!         warning message
          call error(19)
          return
      else
!         Scale Fp with its determinant to make it isochoric
          Fp = Fp / detFp**(1./3.)
!
      end if
!
!
!
!
!
!
!     Elastic part of the velocity gradient
      Le = L - Lp
!
!     Elastic spin
      We = (Le - transpose(Le)) / 2.
!
!
!
!     stress rate due to spin
      dotsigma33 = matmul(We,sigma33) - matmul(sigma33,We)
!
!
!     Update co-rotational sress state
      sigma33 = sigma33 + dotsigma33*dt
!
!
!     Vectorize stress
      call matvec6(sigma33,sigma)
!
!
!
!
!
!
!     Orientation update  
!
!     Intermediate variable
      dR = I3 - We*dt
!
!     Invert or transpose since rotations are orthogonal
      dR = transpose(dR)
!
!
!
!     Update the crystal orientations
      gmatinv = matmul(dR, gmatinv_t)
!
!
!     Calculate plastic strain increment
      dstranp33 = 0.5*(Lp+transpose(Lp))*dt
!
!
!
!     Undo shear corrections
      dummy6 = dstran
      dummy6(4:6) = 0.5*dummy6(4:6)
!
!     Convert the strain into matrix
      call vecmat6(dummy6,dstran33)
!
!     Elastic strain increment
      dstrane33 = dstran33-dstranp33
!
!     Elastic strains in the crystal reference
      dummy33_ = matmul(transpose(gmatinv),dstrane33)
      dummy33 = matmul(dummy33_,gmatinv)
!
!     Vectorize
      call matvec6(dummy33,dummy6)   
!
!     Shear corrections
      dummy6(4:6) = 2.0*dummy6(4:6)
!
!     Add the strain increment to the former value
      Eec=Eec_t+dummy6
!     
!
!
!
!
!
!
!
!
!     Update the states using hardening laws
       call hardeningrules(phaid,nslip,
     + mattemp,dt,G12,burgerv,
     + totgammasum,gammadot,pdot,
     + irradiationmodel,irradiationparam,
     + hardeningmodel,hardeningparam,
     + hintmat1,hintmat2,
     + tauc_t,ssd_t,loop_t,
     + forest_t,substructure_t,
     + tausolute,dtauc,dssdtot,dforest,
     + dsubstructure,dssd,dloop)
!
!
!
!
!     Update the hardening states
!
      tauc = tauc_t + dtauc
!
      ssd = ssd_t + dssd
!
      loop = loop_t + dloop
!
      ssdtot = ssdtot_t + dssdtot
!
      forest = forest_t + dforest
!
      substructure = substructure_t + dsubstructure
!
!
!
!
!
!
!     Check if the statevariables going negative due to softening
!     This may happen at high temperature and strain rates constants going bad
      if(any(tauc < 0.)) then
!         did not converge
          cpconv = 0
!         enter dummy stress and jacobian
          sigma = 0.
          jacobi = I6
!         return to end of the subroutine
!         warning message
          call error(21)
          return
      endif
!
      if(any(ssd < 0.)) then
!         did not converge
          cpconv = 0
!         enter dummy stress and jacobian
          sigma = 0.
          jacobi = I6
!         return to end of the subroutine
!         warning message
          call error(21)
          return
      endif
!
!
!     Loop density set to zero if negative
      do il = 1, maxnloop
          if(loop(il) < 0.) then
!
              loop(il) = 0.
!
          endif
      enddo
!
!
!
!
      if(any(forest < 0.)) then
!         did not converge
          cpconv = 0
!         enter dummy stress and jacobian
          sigma = 0.
          jacobi = I6
!         return to end of the subroutine
!         warning message
          call error(21)
          return
      endif
!
      if(substructure < 0.) then
!         did not converge
          cpconv = 0
!         enter dummy stress and jacobian
          sigma = 0.
          jacobi = I6
!         return to end of the subroutine
!         warning message
          call error(21)
          return
      endif
!
!
!
      return
      end subroutine CP_DunneExplicit
!
!
!
!
!
!
!
!
!
!
!     Implicit state update rule
!     Solution using state variables at the former time step
      subroutine CP_DunneImplicit(matid, phaid,
     + nslip, nscrew, mattemp, Cs, gf, G12,
     + burgerv, cubicslip, caratio,
     + Fp_t, gmatinv_t, Eec_t,
     + gammadot_t, gammasum_t,
     + totgammasum_t, evmp_t,
     + sigma0, abstau0, signtau0,
     + sigmatr, forestproj, slip2screw,
     + Schmid, Schmidvec, SchmidxSchmid,
     + slipmodel, slipparam,
     + creepmodel, creepparam,
     + irradiationmodel, irradiationparam,
     + hardeningmodel, hardeningparam,
     + sintmat1, sintmat2,
     + hintmat1, hintmat2,
     + tauceff_t, tauc_t, rhotot_t,
     + sumrhotot_t, ssdtot_t, rhofor_t,
     + forest_t, substructure_t,
     + gnd_t, ssd_t, loop_t, dt, L, dstran,
     + Lp, Fp, gmatinv, Eec,
     + gammadot, gammasum,
     + totgammasum, evmp,
     + tauc, tausolute,
     + ssdtot, ssd, loop, forest, substructure,
     + sigma, jacobi, cpconv)
!
      use globalvariables, only : I3, I6, smallnum
!
      use userinputs, only : maxniter, maxnparam, maxnloop,
     + tolerance, tauctolerance , quadprec, SVDinversion
!
      use utilities, only : vecmat6, matvec6,
     + nolapinverse, deter3x3, inv3x3, trace3x3,
     + vecmat9, matvec9, nolapinverse16,
     + nolapinverse, SVDinverse
!
      use slip, only : sinhslip, doubleexpslip,
     + powerslip
!
      use creep, only : expcreep
!
      use hardening, only: hardeningrules
!
      use crss, only: slipresistance
!
      use errors, only : error
!
      implicit none
!
!
!     INPUTS
!
!     material-id
      integer, intent(in) :: matid
!     phase-id
      integer, intent(in) :: phaid
!     number of slip sytems
      integer, intent(in) :: nslip
!     number of screw sytems
      integer, intent(in) :: nscrew
!     temperature
      real(8), intent(in) :: mattemp
!     elastic compliance
      real(8), intent(in) :: Cs(6,6)
!     geometric factor
      real(8), intent(in) :: gf
!     elastic shear modulus
      real(8), intent(in) :: G12
!     Burgers vectors
      real(8), intent(in) :: burgerv(nslip)
!     flag for cubic slip systems
      integer, intent(in) :: cubicslip
!     c/a ratio for hcp crystals
      real(8), intent(in) :: caratio
!     plastic part of the deformation gradient at former time step
      real(8), intent(in) :: Fp_t(3,3)
!     Crystal to sample transformation martrix at former time step
      real(8), intent(in) :: gmatinv_t(3,3)
!     Lattice strains
      real(8), intent(in) :: Eec_t(6)
!     slip rates at the former time step
      real(8), intent(in) :: gammadot_t(nslip)
!     total slip per slip system accumulated over the time
!     at the former time step
      real(8), intent(in) :: gammasum_t(nslip)
!     overall total slip at the former time step
      real(8), intent(in) :: totgammasum_t
!     Von-Mises equivalent total plastic strain at the former time step
      real(8), intent(in) :: evmp_t
!     Cauchy stress guess
      real(8), intent(in) :: sigma0(6)
!     rss guess
      real(8), intent(in) :: abstau0(nslip)
!     sign guess
      real(8), intent(in) :: signtau0(nslip)
!     trial stress
      real(8), intent(in) :: sigmatr(6)
!     Forest projections
      real(8), intent(in) :: forestproj(nslip,nslip+nscrew)
!     Forest projections
      real(8), intent(in) :: slip2screw(nscrew,nslip)
!     Schmid tensor
      real(8), intent(in) :: Schmid(nslip,3,3)  
!     Vectorized Schmid tensor
      real(8), intent(in) :: Schmidvec(nslip,6) 
!     Schmid dyadic
      real(8), intent(in) :: SchmidxSchmid(nslip,6,6)
!     slip model no.
      integer, intent(in) :: slipmodel
!     slip model parameters
      real(8), intent(in) :: slipparam(maxnparam)
!     creep model no.
      integer, intent(in) :: creepmodel
!     creep model parameters
      real(8), intent(in) :: creepparam(maxnparam)    
!     irrradiation model no.
      integer, intent(in) :: irradiationmodel
!     irradiation model parameters
      real(8), intent(in) :: irradiationparam(maxnparam)        
!     hardening model no.
      integer, intent(in) :: hardeningmodel
!     hardening model parameters
      real(8), intent(in) :: hardeningparam(maxnparam)
!
!     Interaction matrices
!     Strength interaction between dislocations
      real(8), intent(in) :: sintmat1(nslip,nslip)
!     Strength interaction dislocation loops related with irradiation
      real(8), intent(in) :: sintmat2(nslip,nslip)
!     Latent hardening
      real(8), intent(in) :: hintmat1(nslip,nslip)
!     Hardening interaction matrix between dislocations
      real(8), intent(in) :: hintmat2(nslip,nslip)
!
!
!     overall crss
      real(8), intent(in) :: tauceff_t(nslip)
!     crss at former time step
      real(8), intent(in) :: tauc_t(nslip)
!     total dislocation density over all slip systems at the former time step
      real(8), intent(in) :: rhotot_t(nslip)
!     total dislocation density over all slip systems at the former time step
      real(8), intent(in) :: sumrhotot_t
!     total dislocation density over all slip systems at the former time step
      real(8), intent(in) :: ssdtot_t
!     total forest dislocation density per slip system at the former time step
      real(8), intent(in) :: rhofor_t(nslip)
!     forest dislocation density per slip system at the former time step (hardening model = 4)
      real(8), intent(in) :: forest_t(nslip)
!     substructure dislocation density at the former time step
      real(8), intent(in) :: substructure_t
!     statistically-stored dislocation density per slip system at the former time step
      real(8), intent(in) :: gnd_t(nslip+nscrew) 
!     statistically-stored dislocation density per slip system at the former time step
      real(8), intent(in) :: ssd_t(nslip)
!     loop defect density per slip system at the former time step
      real(8), intent(in) :: loop_t(maxnloop)
!     time increment
      real(8), intent(in) :: dt
!     total velocity gradient at the current time step
      real(8), intent(in) :: L(3,3)
!     mechanical strain increment
      real(8), intent(in) :: dstran(6)
!
!
!
!     OUTPUTS
!
!     plastic velocity gradient
      real(8), intent(out) :: Lp(3,3)
!     plastic part of the deformation gradient
      real(8), intent(out) :: Fp(3,3)
!     Crystal to sample transformation martrix at current time step
      real(8), intent(out) :: gmatinv(3,3)
!     Green-Lagrange strains in the crystal reference
      real(8), intent(out) :: Eec(6)
!     slip rates at the current time step
      real(8), intent(out) :: gammadot(nslip)
!     total slip per slip system accumulated over the time
!     at the current time step
      real(8), intent(out) :: gammasum(nslip)
!     overall total slip at the current time step
      real(8), intent(out) :: totgammasum
!     Von-Mises equivalent total plastic strain at the current time step
      real(8), intent(out) :: evmp
!     crss at the current time step
      real(8), intent(out) :: tauc(nslip)
!     solute strength due to irradiation hardening
      real(8), intent(out) :: tausolute
!     total dislocation density over all slip systems at the current time step
      real(8), intent(out) :: ssdtot
!     forest dislocation density per slip system at the current time step
      real(8), intent(out) :: forest(nslip)
!     substructure dislocation density at the current time step
      real(8), intent(out) :: substructure
!     statistically-stored dislocation density per slip system at the current time step
      real(8), intent(out) :: ssd(nslip)
!     loop defect density per slip system at the current time step
      real(8), intent(out) :: loop(maxnloop)
!     Cauchy stress
      real(8), intent(out) :: sigma(6)
!     material tangent
      real(8), intent(out) :: jacobi(6,6)  
!     convergence flag
      integer, intent(out) :: cpconv
!
!
!
!     Local variables used within this subroutine    
!
!     plastic velocity gradient for slip
      real(8) Lp_s(3,3)
!     plastic velocity gradient for creep
      real(8) Lp_c(3,3)
!     plastic tangent stiffness for slip
      real(16) Pmat_s(6,6)
!     plastic tangent stiffness for creep
      real(16) Pmat_c(6,6)
!     tangent matrix for NR iteration
      real(16) Pmat(6,6)
!     slip rates for slip
      real(16) gammadot_s(nslip)
!     slip rates for creep
      real(16) gammadot_c(nslip)
!     derivative of slip rates wrto rss for slip
      real(8) dgammadot_dtau_s(nslip)
!     derivative of slip rates wrto rss for creep
      real(8) dgammadot_dtau_c(nslip)
!     derivative of slip rates wrto crss for slip
      real(8) dgammadot_dtauc_s(nslip)
!     derivative of slip rates wrto crss for creep
      real(8) dgammadot_dtauc_c(nslip)
!
!
!     rss at the former time step
      real(8) :: tau(nslip)
!     absolute of value of rss at the former time step
      real(8) :: abstau(nslip)
!     sign of rss at the former time step
      real(8) :: signtau(nslip)
!
!     Jacobian of the Newton-Raphson loop
!     and its inverse
      real(16) :: dpsi_dsigma16(6,6), invdpsi_dsigma16(6,6)
      real(8)  :: dpsi_dsigma(6,6), invdpsi_dsigma(6,6)
!     residual of the Newton-Raphson loop
!     vector and scalar
      real(8) :: psinorm, psi(6)
!
!     plastic strain increment
      real(8) :: plasstraininc33(3,3), plasstraininc(6)
!
!     plastic strain rate
      real(8) :: plasstrainrate(3,3)
!
!     Von-Mises equivalent plastic strain rate and increment
      real(8) :: pdot, dp
!
!     stress increment
      real(8) :: dsigma(6)
!
!     stress 3x3 matrix
      real(8) :: sigma33(3,3)
!
!     plastic part of the deformation gradient
      real(8) :: detFp, invFp(3,3)
!
!     elastic part of the deformation gradient
      real(8) :: Fe(3,3)
!
!     elastic part of the velocity gradient
      real(8) :: Le(3,3)
!
!     elastic spin
      real(8) :: We(3,3)
!
!     increment in rotation matrix
      real(8) :: dR(3,3)
!
!     Von-Mises stress
      real(8) :: sigmaii, vms, sigmadev(3,3)
!
!     Co-rotational stress update
      real(8) :: dotsigma33(3,3)
!
!     Cauchy stress at former time step in 3x3
      real(8) :: sigma33_t(3,3)
!
!     Total mechanical strain increment
      real(8) :: dstran33(3,3)
!
!     Plastic strain increment
      real(8) :: dstranp33(3,3)
!
!     elastic strain increment
      real(8) :: dstrane33(3,3)
!
!     crss increment
      real(8) :: dtauc(nslip)
!
!
!     ssd density increment
      real(8) :: dssd(nslip)
!
!     ssd density increment
      real(8) :: dloop(maxnloop)
!
!     total ssd density increment
      real(8) :: dssdtot
!
!     forest dislocation density increment
      real(8) :: dforest(nslip)
!
!     substructure dislocation density increment
      real(8) :: dsubstructure
!
!     Residues
      real(8) :: dtauceff(nslip), tauceff_old(nslip)
!
!     Current values of state variables
!     overall crss
      real(8) :: tauceff(nslip)
!
!     overall forest density
      real(8) :: rhofor(nslip)
!
!     overall total density
      real(8) :: rhotot(nslip)
!
!     overall total scalar density
      real(8) :: sumrhotot
!
!     Overall residue
      real(8) :: dtauceffnorm
!
!     error flag for svd inversion
      integer :: err
!
!     other variables
      real(8) :: dummy3(3), dummy33(3,3),
     + dummy33_(3,3), dummy6(6), dummy0
      integer :: is, il, iter, oiter
!
!
!     Set convergence flag to "converged"
      cpconv = 1
!
!
!     Initial guess for NR scheme
!     Stress at the former time step
      sigma = sigma0
      abstau = abstau0
      signtau =signtau0
!
!
!     State assignments
      tauc = tauc_t
      tauceff = tauceff_t
      ssdtot = ssdtot_t
      ssd = ssd_t
      loop = loop_t
      forest = forest_t
      substructure = substructure_t
!
!     Reset variables for the inner iteration    
      oiter = 0
      dtauceffnorm = 1.
!
!
!     Outer loop for state update
      do while ((dtauceffnorm >= tauctolerance).and.(oiter <= maxniter))
!
!         increment iteration no.
          oiter = oiter + 1
!
!         Reset variables for the inner iteration
          psinorm = 1.
          iter = 0
!
!         Newton-Raphson (NR) iteration to find stress increment
          do while ((psinorm >= tolerance).and.(iter <= maxniter))
!
!             increment iteration no.
              iter = iter + 1
!
!             Slip models to find slip rates
!
!             none
              if (slipmodel == 0) then
!
                  Lp_s = 0.
                  Pmat_s = 0.
                  gammadot_s = 0.
!
!
!             sinh law
              elseif (slipmodel == 1) then
!
                  call sinhslip(Schmid,SchmidxSchmid,
     + abstau,signtau,tauceff,rhofor,burgerv,dt,
     + nslip,phaid,mattemp,slipparam,
     + irradiationmodel,irradiationparam,
     + cubicslip,caratio,Lp_s,Pmat_s,
     + gammadot_s,dgammadot_dtau_s,
     + dgammadot_dtauc_s)
!
!
!             exponential law
              elseif (slipmodel == 2) then
!
!
                  call doubleexpslip(Schmid,SchmidxSchmid,
     + abstau,signtau,tauceff,burgerv,dt,nslip,phaid,
     + mattemp,slipparam,irradiationmodel,
     + irradiationparam,cubicslip,caratio,
     + Lp_s,Pmat_s,gammadot_s,dgammadot_dtau_s,
     + dgammadot_dtauc_s)
!
!
!             power law
              elseif (slipmodel == 3) then
!
!
                  call powerslip(Schmid,SchmidxSchmid,
     + abstau,signtau,tauceff,burgerv,dt,
     + nslip,phaid,mattemp,slipparam,
     + irradiationmodel,irradiationparam,
     + cubicslip,caratio,Lp_s,Pmat_s,
     + gammadot_s,dgammadot_dtau_s,
     + dgammadot_dtauc_s)
!
!
              end if
!
!
!
!             Slip due to creep
              if (creepmodel == 0) then
!
!
                  Lp_c = 0.
                  Pmat_c = 0.
                  gammadot_c = 0.
!
!
              elseif (creepmodel == 1) then
!
!
!
                  call expcreep(Schmid,SchmidxSchmid,
     + abstau,signtau,tauceff,dt,nslip,phaid,
     + mattemp,creepparam,gammasum,Lp_c,Pmat_c,
     + gammadot_c,dgammadot_dtau_c,
     + dgammadot_dtauc_c)
!
!
!
!
              endif
!
!
!             Sum the effects of creep and slip rates
              Lp = Lp_s + Lp_c
              Pmat = Pmat_s + Pmat_c
              gammadot = gammadot_s + gammadot_c
!
!
!
!
!
!
!             Check for the Pmat
              if(any(Pmat /= Pmat)) then
!                 did not converge
                  cpconv = 0
!                 enter dummy stress and jacobian
                  sigma = 0.
                  jacobi = I6
!                 return to end of the subroutine
!                 warning message
                  call error(15)
                  return
              endif
!
!
!
!             plastic strain rate
              plasstrainrate = (Lp + transpose(Lp))/2.
!
!             Plastic strain increment
              plasstraininc33 = plasstrainrate*dt
              call matvec6(plasstraininc33,plasstraininc)
              plasstraininc(4:6)=2.*plasstraininc(4:6)
!
!
!
!
!             Tangent-stiffness calculation
!             Jacobian of the Newton loop (see Dunne, Rugg, Walker, 2007)
              dpsi_dsigma16 = I6 + matmul(Cs, Pmat)
!
!             Assign to the double precision
              dpsi_dsigma = dpsi_dsigma16    
!
!             If quad-precision during inverse is ON
              if (quadprec == 1) then
!
!                 invert the stiffness
                  call nolapinverse16(dpsi_dsigma16,invdpsi_dsigma16,6)
!
!                 convert back to double precision
                  invdpsi_dsigma = invdpsi_dsigma16
!
              else
!
!                 Then invert (double precision version)
                  call nolapinverse(dpsi_dsigma,invdpsi_dsigma,6)
!
              end if
!
!
!             If inversion is not successfull!
!             Check for the inverse
              if(any(invdpsi_dsigma /= invdpsi_dsigma)) then
!
!                 Try using singular value decomposition
!                 If singular value decomposition is ON
                  if (SVDinversion==1) then
!
!                     Invert
                      call SVDinverse(dpsi_dsigma,6,invdpsi_dsigma,err)
!
!
!
                  else
!
!
!                     did not converge
                      err = 1
!
!
!
                  end if
!
!                 Check again and if still not successfull
                  if(err==1) then
!                     did not converge
                      cpconv = 0
!                     enter dummy stress and jacobian
                      sigma = 0.
                      jacobi = I6
!                     return to end of the subroutine
!                     warning message
                      call error(15)
                      return
                  end if
!
!
              endif
!
!
!
!             residual (predictor - corrector scheme)
              psi = sigmatr - sigma - matmul(Cs,plasstraininc)
!
!             norm of the residual
              psinorm = sqrt(sum(psi*psi))
!
!
!             stress increment
              dsigma = matmul(invdpsi_dsigma,psi)
!
!
!             stress update
              sigma = sigma + dsigma
!
!             convert it to 3x3 marix
              call vecmat6(sigma,sigma33)
!
!
!             calculate resolved shear stress on slip systems
!             rss and its sign
              do is = 1, nslip
                  tau(is) = dot_product(Schmidvec(is,:),sigma)
                  signtau(is) = sign(1.0,tau(is))
                  abstau(is) = abs(tau(is))
              end do     
!
!
!
!         End of NR iteration (inner loop)
          end do
!
!
!
!
!
!
!
!
!
!         calculate Von Mises invariant plastic strain rate
          pdot=sqrt(2./3.*sum(plasstrainrate*plasstrainrate))
!
!         Von-Mises plastic strain increment
          dp = pdot*dt
!
!         Total plastic strain increment
          evmp = evmp_t + dp
!
!         Total slip over time per slip system
          gammasum = 0.
          do is = 1, nslip
!
              gammasum(is) = gammasum_t(is) +
     +        abs(gammadot(is))*dt
!
          enddo
!
!
!         Total slip
          totgammasum = totgammasum_t +
     +    sum(abs(gammadot))*dt
!
!
!
!
!
!
!
!
!
!
!         convergence check
          if (iter == maxniter) then
!             did not converge
              cpconv = 0
!             enter dummy stress and jacobian
              sigma = 0.
              jacobi = I6
!             return to end of the subroutine
!             warning message
              call error(16)
              return
          end if
!
!
!
!
!         Check for NaN in the stress vector
          if(any(sigma/=sigma)) then
!             did not converge
              cpconv = 0
!             enter dummy stress and jacobian
              sigma = 0.
              jacobi = I6
!             return to end of the subroutine
!             warning message
              call error(17)
              return
      endif
!
!
!
!
!
!
!
!
!         Update the states using hardening laws
          call hardeningrules(phaid,nslip,
     + mattemp,dt,G12,burgerv,
     + totgammasum,gammadot,pdot,
     + irradiationmodel,irradiationparam,
     + hardeningmodel,hardeningparam,
     + hintmat1,hintmat2,
     + tauc_t,ssd_t,loop_t,
     + forest_t,substructure_t,
     + tausolute,dtauc,dssdtot,dforest,
     + dsubstructure,dssd,dloop)
!
!
!
!
!         Update the hardening states
!
          tauc = tauc_t + dtauc
!
          ssd = ssd_t + dssd
!
          loop = loop_t + dloop
!
          ssdtot = ssdtot_t + dssdtot
!
          forest = forest_t + dforest
!
          substructure = substructure_t + dsubstructure
!
!
!
!         Recalculate total and forest density
          call totalandforest(phaid,
     + nscrew, nslip, gnd_t,
     + ssd, ssdtot, forest,
     + forestproj, slip2screw, rhotot,
     + sumrhotot, rhofor)
!
!
!
!         Store the former value of effective tauc
          tauceff_old = tauceff
!
!         Recalculate slip resistance for the next iteration
!         Calculate crss
          call slipresistance(phaid, nslip,
     + gf, G12, burgerv, sintmat1, sintmat2,
     + tauc, rhotot, sumrhotot, rhofor,
     + substructure, tausolute, loop,
     + hardeningmodel, hardeningparam,
     + irradiationmodel, irradiationparam,
     + mattemp, tauceff)
!
!
!         Calculate the change of state
!         with respect to the former increment
          dtauceff = abs(tauceff-tauceff_old)
!
          dtauceffnorm = maxval(dtauceff)
!
!
!
!         Check if the statevariables going negative due to softening
!         This may happen at high temperature and strain rates constants going bad
          if(any(tauc < 0.)) then
!             did not converge
              cpconv = 0
!             enter dummy stress and jacobian
              sigma = 0.
              jacobi = I6
!             return to end of the subroutine
!             warning message
              call error(21)
              return
          endif
!
          if(any(ssd < 0.)) then
!             did not converge
              cpconv = 0
!             enter dummy stress and jacobian
              sigma = 0.
              jacobi = I6
!             return to end of the subroutine
!             warning message
              call error(21)
              return
          endif
!
!         Loop density set to zero if negative
          do il = 1, maxnloop
              if(loop(il) < 0.) then
!
                  loop(il) = 0.
!
              endif
          enddo
!
!
          if(any(forest < 0.)) then
!             did not converge
              cpconv = 0
!             enter dummy stress and jacobian
              sigma = 0.
              jacobi = I6
!             return to end of the subroutine
!             warning message
              call error(21)
              return
          endif
!
          if(substructure < 0.) then
!             did not converge
              cpconv = 0
!             enter dummy stress and jacobian
              sigma = 0.
              jacobi = I6
!             return to end of the subroutine
!             warning message
              call error(21)
              return
          endif
!
!
!
!
!
!     End of state update (outer loop)
      end do
!
!
!
!
!
!
!     calculate jacobian
      jacobi = matmul(invdpsi_dsigma,Cs)    
!
!
!
!     Check for NaN in the jacobi matrix
      if(any(jacobi/=jacobi))  then
!         did not converge
          cpconv = 0
!         enter dummy stress and jacobian
          sigma = 0.
          jacobi = I6
!         return to end of the subroutine
!         warning message
          call error(18)
          return
      endif 
!
!
!
!
!
!
!     Trace of stress
      call trace3x3(sigma33,sigmaii)
!
!     deviatoric stress
      sigmadev = sigma33 - sigmaii*I3/3.
!
!     Von-Mises stress
      vms = sqrt(3./2.*(sum(sigmadev*sigmadev)))
!
!
!     variables for plastic part of the deformation gradient
      dummy33 = I3 - Lp*dt
      call inv3x3(dummy33,dummy33_,dummy0)
!
!     plastic part of the deformation gradient
      Fp = matmul(dummy33_,Fp_t)
!
!     determinant
      call deter3x3(Fp,detFp)
!
!
!
!
!     check wheter the determinant is negative
!     or close zero
      if (detFp <= smallnum) then
!         did not converge
          cpconv = 0
!         enter dummy stress and jacobian
          sigma = 0.
          jacobi = I6
!         return to end of the subroutine
!         warning message
          call error(19)
          return
      else
!         Scale Fp with its determinant to make it isochoric
          Fp = Fp / detFp**(1./3.)
!
      end if
!
!
!
!
!
!
!     Elastic part of the velocity gradient
      Le = L - Lp
!
!     Elastic spin
      We = (Le - transpose(Le)) / 2.
!
!
!
!     stress rate due to spin
      dotsigma33 = matmul(We,sigma33) - matmul(sigma33,We)
!
!
!     Update co-rotational sress state
      sigma33 = sigma33 + dotsigma33*dt
!
!
!     Vectorize stress
      call matvec6(sigma33,sigma)
!
!
!
!
!
!     Orientation update  
!
!     Intermediate variable
      dR = I3 - We*dt
!
!     Invert or transpose since rotations are orthogonal
      dR = transpose(dR)
!
!
!
!     Update the crystal orientations
      gmatinv = matmul(dR, gmatinv_t)
!
!
!     Calculate plastic strain increment
      dstranp33 = 0.5*(Lp+transpose(Lp))*dt
!
!
!
!     Undo shear corrections
      dummy6 = dstran
      dummy6(4:6) = 0.5*dummy6(4:6)
!
!     Convert the strain into matrix
      call vecmat6(dummy6,dstran33)
!
!     Elastic strain increment
      dstrane33 = dstran33-dstranp33
!
!     Elastic strains in the crystal reference
      dummy33_ = matmul(transpose(gmatinv),dstrane33)
      dummy33 = matmul(dummy33_,gmatinv)
!
!     Vectorize
      call matvec6(dummy33,dummy6)
!
!     Shear corrections
      dummy6(4:6) = 2.0*dummy6(4:6)
!
!     Add the strain increment to the former value
      Eec=Eec_t+dummy6
!
!
!     
!
!
!
!
!
!
!
!
!
!
!
      return
      end subroutine CP_DunneImplicit
!
!
!
!
!
!
!
!     Forward Gradient Predictor scheme
      subroutine CP_ForwardGradientPredictor(matid, phaid,
     + nslip, nscrew, mattemp, Cs, gf, G12,
     + burgerv, cubicslip, caratio,
     + Fp_t, gmatinv_t, Eec_t,
     + gammadot_t, gammasum_t,
     + totgammasum_t, evmp_t, sigma_t,
     + forestproj, slip2screw, dirs_t, nors_t,
     + Schmidvec, Schmid, SchmidxSchmid,
     + slipmodel, slipparam,
     + creepmodel, creepparam,
     + irradiationmodel, irradiationparam,
     + hardeningmodel, hardeningparam,
     + sintmat1, sintmat2,
     + hintmat1, hintmat2,
     + tauceff_t, tauc_t, rhotot_t,
     + sumrhotot_t, ssdtot_t,
     + rhofor_t, forest_t, substructure_t,
     + gnd_t, ssd_t, loop_t, dt, dstran, domega,
     + Fp, gmatinv, Eec,
     + gammadot, gammasum,
     + totgammasum, evmp,
     + tauc, tausolute,
     + ssdtot, ssd, loop, forest, substructure,
     + sigma, jacobi, cpconv)
!
      use globalvariables, only : I3, I6, smallnum
!
      use userinputs, only : theta, maxnparam, maxnloop
!
      use utilities, only : vecmat6, matvec6,
     + nolapinverse, deter3x3, inv3x3, trace3x3,
     + vecmat9, matvec9
!
      use slip, only : sinhslip, doubleexpslip,
     + powerslip
!
      use creep, only : expcreep
!
      use hardening, only: hardeningrules
!
      use crss, only: slipresistance
!
      use errors, only : error
!
      implicit none
!
!     INPUTS
!
!     material-id
      integer, intent(in) :: matid
!     phase-id
      integer, intent(in) :: phaid
!     number of slip sytems
      integer, intent(in) :: nslip
!     number of screw sytems
      integer, intent(in) :: nscrew
!     temperature
      real(8), intent(in) :: mattemp
!     elastic compliance
      real(8), intent(in) :: Cs(6,6)
!     geometric factor
      real(8), intent(in) :: gf
!     elastic shear modulus
      real(8), intent(in) :: G12
!     Burgers vectors
      real(8), intent(in) :: burgerv(nslip)
!     flag for cubic slip systems
      integer, intent(in) :: cubicslip
!     c/a ratio for hcp crystals
      real(8), intent(in) :: caratio
!     plastic part of the deformation gradient at former time step
      real(8), intent(in) :: Fp_t(3,3)
!     Crystal to sample transformation martrix at former time step
      real(8), intent(in) :: gmatinv_t(3,3)
!     Lattice strains
      real(8), intent(in) :: Eec_t(6)
!     slip rates at the former time step
      real(8), intent(in) :: gammadot_t(nslip)
!     total slip per slip system accumulated over the time
!     at the former time step
      real(8), intent(in) :: gammasum_t(nslip)
!     overall total slip at the former time step
      real(8), intent(in) :: totgammasum_t
!     Von-Mises equivalent total plastic strain at the former time step
      real(8), intent(in) :: evmp_t
!     Cauchy stress at the former time step
      real(8), intent(in) :: sigma_t(6)
!     Forest projection for GND
      real(8), intent(in) :: forestproj(nslip,nslip+nscrew)
!     Slip to screw system mapping
      real(8), intent(in) :: slip2screw(nscrew,nslip)
!     undeformed slip direction in crsytal reference frame
      real(8), intent(in) :: dirs_t(nslip,3)
!     undeformed slip plane normal in crystal reference frame
      real(8), intent(in) :: nors_t(nslip,3)
!     Schmid tensor - vectorized
      real(8), intent(in) :: Schmidvec(nslip,6)
!     Schmid tensor - unused
      real(8), intent(in) :: Schmid(nslip,3,3)
!     Schmid dyadic - unused
      real(8), intent(in) :: SchmidxSchmid(nslip,6,6)
!     slip model no.
      integer, intent(in) :: slipmodel
!     slip model parameters
      real(8), intent(in) :: slipparam(maxnparam)
!     creep model no.
      integer, intent(in) :: creepmodel
!     creep model parameters
      real(8), intent(in) :: creepparam(maxnparam)
!     irrradiation model no.
      integer, intent(in) :: irradiationmodel
!     irradiation model parameters
      real(8), intent(in) :: irradiationparam(maxnparam)
!     hardening model no.
      integer, intent(in) :: hardeningmodel
!     hardening model parameters
      real(8), intent(in) :: hardeningparam(maxnparam)
!
!     Interaction matrices
!     Strength interaction between dislocations
      real(8), intent(in) :: sintmat1(nslip,nslip)
!     Strength interaction dislocation loops related with irradiation
      real(8), intent(in) :: sintmat2(nslip,nslip)
!     Latent hardening
      real(8), intent(in) :: hintmat1(nslip,nslip)
!     Hardening interaction matrix between dislocations
      real(8), intent(in) :: hintmat2(nslip,nslip)
!
!
!     overall crss
      real(8), intent(in) :: tauceff_t(nslip)
!     crss at former time step
      real(8), intent(in) :: tauc_t(nslip)
!     total dislocation density over all slip systems at the former time step
      real(8), intent(in) :: rhotot_t(nslip)
!     total scalar dislocation density over all slip systems at the former time step
      real(8), intent(in) :: sumrhotot_t
!     total dislocation density over all slip systems at the former time step
      real(8), intent(in) :: ssdtot_t
!     total forest dislocation density per slip system at the former time step
      real(8), intent(in) :: rhofor_t(nslip)
!     forest dislocation density per slip system at the former time step (hardening model = 4)
      real(8), intent(in) :: forest_t(nslip)
!     substructure dislocation density at the former time step
      real(8), intent(in) :: substructure_t
!     statistically-stored dislocation density per slip system at the former time step
      real(8), intent(in) :: gnd_t(nslip+nscrew)
!     statistically-stored dislocation density per slip system at the former time step
      real(8), intent(in) :: ssd_t(nslip)
!     defect loop density per slip system at the former time step
      real(8), intent(in) :: loop_t(maxnloop)
!     time increment
      real(8), intent(in) :: dt
!     mechanical strain increment
      real(8), intent(in) :: dstran(6)
!     mechanical spin increment
      real(8), intent(in) :: domega(3)
!
!
!     OUTPUTS
!
!     plastic part of the deformation gradient
      real(8), intent(out) :: Fp(3,3)
!     Crystal to sample transformation martrix at current time step
      real(8), intent(out) :: gmatinv(3,3)
!     Green-Lagrange strains in the crystal reference
      real(8), intent(out) :: Eec(6)
!     slip rates at the current time step
      real(8), intent(out) :: gammadot(nslip)
!     total slip per slip system accumulated over the time
!     at the current time step
      real(8), intent(out) :: gammasum(nslip)
!     overall total slip at the current time step
      real(8), intent(out) :: totgammasum
!     Von-Mises equivalent total plastic strain at the current time step
      real(8), intent(out) :: evmp
!     crss at the current time step
      real(8), intent(out) :: tauc(nslip)
!     solute strength due to irradiation hardening
      real(8), intent(out) :: tausolute
!     total dislocation density over all slip systems at the current time step
      real(8), intent(out) :: ssdtot
!     forest dislocation density per slip system at the current time step
      real(8), intent(out) :: forest(nslip)
!     substructure dislocation density at the current time step
      real(8), intent(out) :: substructure
!     statistically-stored dislocation density per slip system at the current time step
      real(8), intent(out) :: ssd(nslip)
!     defect loop density per slip system at the current time step
      real(8), intent(out) :: loop(maxnloop)
!     Cauchy stress
      real(8), intent(out) :: sigma(6)
!     material tangent
      real(8), intent(out) :: jacobi(6,6)
!     convergence flag
      integer, intent(out) :: cpconv
!
!
!     Variables used within
!     deviatoric strains
      real(8) :: dev
!     Plastic spin dyadic (without shears)
      real(8) :: W(3,nslip), W33(3,3)
!     Resolved shear stress
      real(8) :: tau_t(nslip)
      real(8) :: abstau_t(nslip)
      real(8) :: signtau_t(nslip)
!     Two coefficients used in the solution
!     ddemsd = D * P + beta
      real(8) :: ddemsd(6,nslip)
!     Stress correction for large rotations
!     beta = sigma * W - W * sigma
      real(8) :: beta(6,nslip)
!     Results from the constitutive laws
      real(8) :: Lp_s(3,3), Lp_c(3,3)
!     Quad-precision variables
      real(16) :: Pmat_s(6,6), Pmat_c(6,6)
      real(16) :: gammadot_s(nslip), gammadot_c(nslip)    
!     derivative of slip rates wrto rss for slip
      real(8) :: dgammadot_dtau_s(nslip)
!     derivative of slip rates wrto rss for creep
      real(8) :: dgammadot_dtau_c(nslip)
!     derivative of slip rates wrto crss for slip
      real(8) :: dgammadot_dtauc_s(nslip)
!     derivative of slip rates wrto crss for creep
      real(8) :: dgammadot_dtauc_c(nslip)
!     total derivative of slip rates wrto rss
      real(8) :: dgammadot_dtau(nslip)
!     total derivative of slip rates wrto crss
      real(8) :: dgammadot_dtauc(nslip)
!     Plastic strain increment related quantities
      real(8) :: Lp(3,3), pdot, plasstrainrate(3,3), dp
!     Hardening increment mapping (numerically calculated)
      real(8) :: Hab(nslip,nslip)
!
!
!
!
!
!
!     Variables used in the solution for slip increments
      real(8) :: Nab(nslip,nslip)
      real(8) :: Mab(nslip,nslip)
!     The derivative of shear rates with respecto to rss
      real(8) :: ddgdde(nslip,6)
!     Slip increments
      real(8) :: dgamma(nslip)
!     Total spin increment
      real(8) :: domega33(3,3)
!     Plastic spin increment
      real(8) :: domega33_p(3,3)
!     Elastic spin increment
      real(8) :: domega33_e(3,3)
!     Rotation matrix increment
      real(8) :: dgmatinv(3,3)
!
!     Increment in Cauchy stress
      real(8) :: dsigma(6)
!
!
!     Determinant of plastic deformation gradient
      real(8) :: detFp
!     Strain increment and related variables
      real(8) :: dstranp(6), dstrane(6)
      real(8) :: dstrane33(3,3)
!     crss increment
      real(8) :: dtauc(nslip)
!     ssd density increment
      real(8) :: dssd(nslip)
!     loop density increment
      real(8) :: dloop(maxnloop)
!     total ssd density increment
      real(8) :: dssdtot
!     forest dislocation density increment
      real(8) :: dforest(nslip)
!     substructure dislocation density increment
      real(8) :: dsubstructure
!
!
!
!
!     overall crss
      real(8) :: tauceff(nslip)
!     forest density
      real(8) :: rhofor(nslip)
!     total density
      real(8) :: rhotot(nslip)
!     total scalar density
      real(8) :: sumrhotot
!
!     Dummy variables
      real(8) :: dummy33(3,3), dummy33_(3,3)
      real(8) :: dummy0, dummy6(6), dummy66(6,6)
!
!     Variables uses within the subroutine
      integer :: is, js, il, i, j, k, a, b
!
!
!
!     Initiate convergence flag
      cpconv = 1
!
!
!
!
!     Volumetric change in the strain
      dev = dstran(1) + dstran(2) + dstran(3)
!
!
!     Plastic spin dyadic
      W = 0.
      do is = 1, nslip
!
          W(1,is) = 0.5*(dirs_t(is,1)*nors_t(is,2)-
     + dirs_t(is,2)*nors_t(is,1))
!
          W(2,is) = 0.5*(dirs_t(is,3)*nors_t(is,1)-
     + dirs_t(is,1)*nors_t(is,3))
!
          W(3,is) = 0.5*(dirs_t(is,2)*nors_t(is,3)-
     + dirs_t(is,3)*nors_t(is,2))
!
      end do
!
!
!
!     Calculate RSSS
      do is = 1, nslip
          tau_t(is) = dot_product(Schmidvec(is,:),sigma_t)
          abstau_t(is) = abs(tau_t(is))
          signtau_t(is) = sign(1.0,tau_t(is))
      end do
!
!
!
!
!
!     Calculate beta and ddemsd
      beta=0.; ddemsd=0.
      do is = 1, nslip
!
!         Symbolic math result
          beta(1,is) = -2.*W(2,is)*sigma_t(5) + 2.*W(1,is)*sigma_t(4)
          beta(2,is) = -2.*W(1,is)*sigma_t(4) + 2.*W(3,is)*sigma_t(6)
          beta(3,is) = -2.*W(3,is)*sigma_t(6) + 2.*W(2,is)*sigma_t(5)
          beta(4,is) = -W(1,is)*sigma_t(1) + W(1,is)*sigma_t(2) - 
     + W(2,is)*sigma_t(6) + W(3,is)*sigma_t(5)
          beta(5,is) = -W(2,is)*sigma_t(3) + W(2,is)*sigma_t(1) + 
     + W(1,is)*sigma_t(6) - W(3,is)*sigma_t(4)
          beta(6,is) = -W(3,is)*sigma_t(2) - W(1,is)*sigma_t(5) + 
     + W(2,is)*sigma_t(4) + W(3,is)*sigma_t(3)
!
!
          ddemsd(:,is) = matmul(Cs,Schmidvec(is,:)) +
     + beta(:,is)
!
      end do
!
!
!
!
!
!     Slip models to find slip rates
!
!     none
      if (slipmodel == 0) then
!
          Lp_s = 0.
          Pmat_s = 0.
          gammadot_s = 0.
          dgammadot_dtau_s = 0.
          dgammadot_dtauc_s = 0.
!
!     sinh law
      elseif (slipmodel == 1) then
!
          call sinhslip(Schmid,SchmidxSchmid,
     + abstau_t,signtau_t,tauceff_t,rhofor_t,burgerv,dt,
     + nslip,phaid,mattemp,slipparam,
     + irradiationmodel,irradiationparam,
     + cubicslip,caratio,Lp_s,Pmat_s,
     + gammadot_s,dgammadot_dtau_s,
     + dgammadot_dtauc_s)
!
!
!     exponential law
      elseif (slipmodel == 2) then
!
!
          call doubleexpslip(Schmid,SchmidxSchmid,
     + abstau_t,signtau_t,tauceff_t,burgerv,dt,nslip,phaid,
     + mattemp,slipparam,irradiationmodel,
     + irradiationparam,cubicslip,caratio,
     + Lp_s,Pmat_s,gammadot_s,
     + dgammadot_dtau_s,dgammadot_dtauc_s) 
!
!
!     power law
      elseif (slipmodel == 3) then
!
!
          call powerslip(Schmid,SchmidxSchmid,
     + abstau_t,signtau_t,tauceff_t,burgerv,dt,
     + nslip,phaid,mattemp,slipparam,
     + irradiationmodel,irradiationparam,
     + cubicslip,caratio,Lp_s,Pmat_s,
     + gammadot_s,dgammadot_dtau_s,
     + dgammadot_dtauc_s)
!
!
      end if
!
!
!
!     Slip due to creep     
      if (creepmodel == 0) then
!
!
          Lp_c = 0.
          Pmat_c = 0.
          gammadot_c = 0.
          dgammadot_dtau_c = 0.
          dgammadot_dtauc_c = 0.
!
      elseif (creepmodel == 1) then
!
!
!
          call expcreep(Schmid,SchmidxSchmid,
     + abstau_t,signtau_t,tauceff_t,dt,nslip,phaid,
     + mattemp,creepparam,gammasum,
     + Lp_c,Pmat_c,gammadot_c,
     + dgammadot_dtau_c,dgammadot_dtauc_c)
!
!
!
!
      endif
!
!
!     Sum the effects of creep and slip rates
      gammadot = gammadot_s + gammadot_c
!
      dgammadot_dtau = dgammadot_dtau_s +
     + dgammadot_dtau_c
!
      dgammadot_dtauc = dgammadot_dtauc_s +
     + dgammadot_dtauc_c
!
      Lp = Lp_s + Lp_c
!
!
!     Check for the slip rates
      if(any(gammadot /= gammadot)) then
!         did not converge
          cpconv = 0
!         enter dummy stress and jacobian
          sigma = 0.
          jacobi = I6
!         return to end of the subroutine
!         warning message
          call error(14)
          return
      endif      
!
!
!     Plastic strain-related quantities for hardening calculations
!
!     plastic strain rate
      plasstrainrate = (Lp + transpose(Lp))/2.
!
!
!     calculate von mises invariant plastic strain rate
      pdot=sqrt(2./3.*sum(plasstrainrate*plasstrainrate))
!
!
!
!     Total slip over time per slip system
      gammasum = 0.
      do is =1, nslip
!
          gammasum(is) = gammasum_t(is) +
     +    abs(gammadot(is))*dt
!
      enddo
!
!
!     Total slip
      totgammasum = totgammasum_t +
     + sum(abs(gammadot))*dt
!
!
!
!
!
!     Update the states using hardening laws
       call hardeningrules(phaid,nslip,
     + mattemp,dt,G12,burgerv,
     + totgammasum,gammadot,pdot,
     + irradiationmodel,irradiationparam,
     + hardeningmodel,hardeningparam,
     + hintmat1,hintmat2,
     + tauc_t,ssd_t,loop_t,
     + forest_t,substructure_t,
     + tausolute,dtauc,dssdtot,dforest,
     + dsubstructure,dssd,dloop)
!
!
!
!
!     Update the hardening states
!
      tauc = tauc_t + dtauc
!
      ssd = ssd_t + dssd
!
      loop = loop_t + dloop
!
      ssdtot = ssdtot_t + dssdtot
!
      forest = forest_t + dforest
!
      substructure = substructure_t + dsubstructure
!
!
!      
!     Check if the statevariables going negative due to softening
!     This may happen at high temperature and strain rates constants going bad
      if(any(tauc < 0.)) then
!         did not converge
          cpconv = 0
!         enter dummy stress and jacobian
          sigma = 0.
          jacobi = I6
!         return to end of the subroutine
!         warning message
          call error(21)
          return
      endif
!
      if(any(ssd < 0.)) then
!         did not converge
          cpconv = 0
!         enter dummy stress and jacobian
          sigma = 0.
          jacobi = I6
!         return to end of the subroutine
!         warning message
          call error(21)
          return
      endif
!
!
!
      if(any(forest < 0.)) then
!         did not converge
          cpconv = 0
!         enter dummy stress and jacobian
          sigma = 0.
          jacobi = I6
!         return to end of the subroutine
!         warning message
          call error(21)
          return
      endif
!
      if(substructure < 0.) then
!         did not converge
          cpconv = 0
!         enter dummy stress and jacobian
          sigma = 0.
          jacobi = I6
!         return to end of the subroutine
!         warning message
          call error(21)
          return
      endif
!
!
!     Find the effective hardening increment
!
!     Calculate total and forest density
      call totalandforest(phaid,
     + nscrew, nslip, gnd_t,
     + ssd, ssdtot, forest,
     + forestproj, slip2screw, rhotot,
     + sumrhotot, rhofor)
!
!
!
!     Calculate crss
      call slipresistance(phaid, nslip, gf, G12,
     + burgerv, sintmat1, sintmat2,
     + tauc, rhotot, sumrhotot, rhofor,
     + substructure, tausolute, loop,
     + hardeningmodel, hardeningparam,
     + irradiationmodel, irradiationparam,
     + mattemp, tauceff)
!
!
!
!     Numerical calculation of derivative dtauc/dgamma
      Hab = 0.
      do is = 1, nslip
!
          if (abs(gammadot(is))>sqrt(smallnum)) then
!
              Hab(is,is) = (tauceff(is)-tauceff_t(is))/dt/
     + abs(gammadot(is))
!
!
          end if
!
      end do
!     
!
!
!
!
!
!     Euler solution
      Nab = 0.
      dgamma = 0.
      do a = 1, nslip
!
          do b = 1, nslip
!
              dummy0 = 0.
              do i = 1, 6
                  dummy0 = dummy0 + ddemsd(i,a)*Schmidvec(b,i)
              end do
!
              Nab(a,b) = theta*dt*dgammadot_dtau(a)*dummy0 -
     + Hab(a,b)*dgammadot_dtauc(a)*sign(1.0,gammadot(b))*theta*dt
!
!
          end do
!
          Nab(a,a) = Nab(a,a) + 1.
!
!         Given quantities in vector form
          dgamma(a) = dot_product(ddemsd(:,a),dstran)*
     + dgammadot_dtau(a)*theta*dt + gammadot(a)*dt
!
!
      end do
!
!
!     Solve for the slip increments
      call nolapinverse(Nab,Mab,nslip)
!
!
!
!
!     Check for the inversion
      if(any(Mab /= Mab)) then
!         did not converge
          cpconv = 0
!         enter dummy stress and jacobian
          sigma = 0.
          jacobi = I6
!         return to end of the subroutine
!         warning message
          call error(14)
          return
      endif
!
!
!
!
!     Slip increments
      dgamma = matmul(Mab,dgamma)
!
!
!
!
!     Slip rates
      gammadot = dgamma/dt
!
!
!
!
!
!
!     Redo the slip calculations
!
!
!     Plastic velocity gradient
      Lp = 0.
      do is = 1, nslip
          Lp = Lp + gammadot(is)*Schmid(is,:,:)
      end do
!
!
!
!
!     Total slip over time per slip system
      gammasum = 0.
      do is = 1, nslip
!
          gammasum(is) = gammasum_t(is) +
     + abs(gammadot(is))*dt
!
      enddo
!
!
!     Total slip
      totgammasum = totgammasum_t +
     + sum(abs(gammadot))*dt     
!
!
!
!     variables for plastic part of the deformation gradient
      dummy33 = I3 - Lp*dt
      call inv3x3(dummy33,dummy33_,dummy0)
!
!     plastic part of the deformation gradient
      Fp = matmul(dummy33_,Fp_t)
!
!     determinant
      call deter3x3(Fp,detFp)
!
!
!
!
!     check wheter the determinant is negative
!     or close zero
      if (detFp <= smallnum) then
!         did not converge
          cpconv = 0
!         enter dummy stress and jacobian
          sigma = 0.
          jacobi = I6
!         return to end of the subroutine
!         warning message
          call error(19)
          return
      else
!         Scale Fp with its determinant to make it isochoric
          Fp = Fp / detFp**(1./3.)
!
      end if     
!
!     plastic strain rate
      plasstrainrate = (Lp + transpose(Lp))/2.
!
!     calculate von mises invariant plastic strain rate
      pdot=sqrt(2./3.*sum(plasstrainrate*plasstrainrate))
!
!     Total plastic strain increment
      dp = pdot*dt
!
!     Von-Mises equivalent total plastic strain
      evmp = evmp_t + dp
!
!
!
!
!     Update the states using hardening laws
       call hardeningrules(phaid,nslip,
     + mattemp,dt,G12,burgerv,
     + totgammasum,gammadot,pdot,
     + irradiationmodel,irradiationparam,
     + hardeningmodel,hardeningparam,
     + hintmat1,hintmat2,
     + tauc_t,ssd_t,loop_t,
     + forest_t,substructure_t,
     + tausolute,dtauc,dssdtot,dforest,
     + dsubstructure,dssd,dloop)
!
!
!
!
!     Update the hardening states
!
      tauc = tauc_t + dtauc
!
      ssd = ssd_t + dssd
!
      loop = loop_t + dloop
!
      ssdtot = ssdtot_t + dssdtot
!
      forest = forest_t + dforest
!
      substructure = substructure_t + dsubstructure
!
!
!     Check if the statevariables going negative due to softening
!     This may happen at high temperature and strain rates constants going bad
      if(any(tauc < 0.)) then
!         did not converge
          cpconv = 0
!         enter dummy stress and jacobian
          sigma = 0.
          jacobi = I6
!         return to end of the subroutine
!         warning message
          call error(21)
          return
      endif
!
      if(any(ssd < 0.)) then
!         did not converge
          cpconv = 0
!         enter dummy stress and jacobian
          sigma = 0.
          jacobi = I6
!         return to end of the subroutine
!         warning message
          call error(21)
          return
      endif
!
!
!     Loop density set to zero if negative
      do il = 1, maxnloop
          if(loop(il) < 0.) then
!
              loop(il) = 0.
!
          endif
      enddo
!
!
      if(any(forest < 0.)) then
!         did not converge
          cpconv = 0
!         enter dummy stress and jacobian
          sigma = 0.
          jacobi = I6
!         return to end of the subroutine
!         warning message
          call error(21)
          return
      endif       
!
      if(substructure < 0.) then
!         did not converge
          cpconv = 0
!         enter dummy stress and jacobian
          sigma = 0.
          jacobi = I6
!         return to end of the subroutine
!         warning message
          call error(21)
          return
      endif
!
!
!
!
!     Calculate total and forest density
      call totalandforest(phaid, 
     + nscrew, nslip, gnd_t,
     + ssd, ssdtot, forest,
     + forestproj, slip2screw, rhotot,
     + sumrhotot, rhofor)
!
!
!
!     Calculate crss
      call slipresistance(phaid, nslip, gf, G12,
     + burgerv, sintmat1, sintmat2,
     + tauc, rhotot, sumrhotot, rhofor,
     + substructure, tausolute, loop,
     + hardeningmodel, hardeningparam,
     + irradiationmodel, irradiationparam,
     + mattemp, tauceff)
!
!
!
!
!
!     Elastic strains in the crystal reference
!
!
!     Elastic strain increment
      dstranp=0.
      do is = 1, nslip
          dstranp(:) = dstranp(:) + Schmidvec(is,:)*dgamma(is)
      end do
!
!
!     Subtract the plastic strain increment from total
      dstrane = dstran - dstranp
!
!     undo shear corrections
      dstrane(4:6) = 0.5*dstrane(4:6)
!
!
!     Convert to 3x3 matrix
      call vecmat6(dstrane,dstrane33)
!
!
!     Elastic strains in the crystal reference
      dummy33_ = matmul(transpose(gmatinv),dstrane33)
      dummy33 = matmul(dummy33_,gmatinv)
!
!     Vectorize
      call matvec6(dummy33,dummy6)      
!
!     Shear corrections
      dummy6(4:6) = 2.0*dummy6(4:6)
!
!     Add the strain increment to the former value
      Eec=Eec_t + dummy6
!
!
!
!
!
!
!
!
!     Spin increment (3x3 matrix)
      domega33 = 0.
      domega33(1,2) = domega(1)
      domega33(1,3) = -domega(2)
      domega33(2,1) = -domega(1)
      domega33(2,3) = domega(3)
      domega33(3,1) = domega(2)
      domega33(3,2) = -domega(3)
!
!
!     Calculate plastic spin from slip
      domega33_p=0.
      do is = 1, nslip
!
          W33 = 0.
          W33(1,2) = W(1,is)
          W33(1,3) = -W(2,is)
          W33(2,1) = -W(1,is)
          W33(2,3) = W(3,is)
          W33(3,1) = W(2,is)
          W33(3,2) = -W(3,is)        
!
          domega33_p = domega33_p + W33*dgamma(is)
!
!
      end do
!
!
!     Elastic spin
      domega33_e = domega33 - domega33_p
!
!
!
!
!
!     Orientation update
      dgmatinv = matmul(domega33_e,gmatinv_t)
!
!
      gmatinv = gmatinv_t + dgmatinv
!
!
!
!
!
!     Stress update
      dsigma = matmul(Cs,dstran) -
     + sigma_t*dev - matmul(ddemsd,dgamma)
!
      sigma = sigma_t + dsigma
!
!
!
!     Material tangent
!
!     Step-1: Calculate ddgamma_ddeps
      do is=1,nslip
!
          ddgdde(is,:) = dt*theta*dgammadot_dtau(is)*ddemsd(:,is)
!
      end do
!
!
!
!
!     Step-2: Calculate overall expression
      jacobi = Cs - matmul(ddemsd,matmul(Mab,ddgdde))
!
!
!     Correction for large deformations
      do i=1,3
          do j=1,3
              jacobi(i,j) = jacobi(i,j) - sigma(i)
              jacobi(i+3,j) = jacobi(i+3,j) - sigma(i+3)
          end do
      end do
!
!
      jacobi = jacobi / (1.+dev)
!
!     Make it symmetric to help convergence
      jacobi = 0.5*(jacobi + transpose(jacobi))
!
!
!
      return
      end subroutine CP_ForwardGradientPredictor
!
!
!
!
!  
!
!      
!
!
!
!
!
!
!      
!
!
!
!
!
!     Implicit state update rule
!     Solution using the updated state variables
      subroutine rotateslipsystems(iphase,nslip,caratio,
     + gmatinv,dirc,norc,dirs,nors)
      implicit none
      integer, intent(in) :: iphase
      integer, intent(in) :: nslip
      real(8), intent(in) :: caratio
      real(8), intent(in) :: gmatinv(3,3)
      real(8), intent(in) :: dirc(nslip,3)
      real(8), intent(in) :: norc(nslip,3)
      real(8), intent(out) :: dirs(nslip,3)
      real(8), intent(out) :: nors(nslip,3)
!
      integer :: i, is
      real(8) :: tdir(3), tnor(3)
      real(8) :: tdir1(3), tnor1(3)
      real(8) :: dirmag, normag
!
      dirs=0.;nors=0.
!
!
      do is=1,nslip ! rotate slip directions 
!
          tdir = dirc(is,:)
          tnor = norc(is,:)
!
!
!
          tdir1 = matmul(gmatinv,tdir)
          tnor1 = matmul(gmatinv,tnor)
!
          dirmag = norm2(tdir1)
          normag = norm2(tnor1)
!
!
          dirs(is,:) = tdir1/dirmag
          nors(is,:) = tnor1/normag
!
!
      end do
!
!
!
!
      return
      end subroutine rotateslipsystems
!
!
!
!
!
!
!
!
!
!     Calculates the total and forest density
!     from SSD and GND densities using summation
!     and forest projections
      subroutine totalandforest(iphase, nscrew, nslip,
     + gnd, ssd, ssdtot, forest, forestproj, slip2screw,
     + rhotot, sumrhotot, rhofor)
      use utilities, only : vecprod
      implicit none
      integer, intent(in) :: iphase
      integer, intent(in) :: nscrew
      integer, intent(in) :: nslip
      real(8), intent(in) :: gnd(nslip+nscrew)
      real(8), intent(in) :: ssd(nslip)
      real(8), intent(in) :: ssdtot
      real(8), intent(in) :: forest(nslip)
      real(8), intent(in) :: forestproj(nslip,nslip+nscrew)
      real(8), intent(in) :: slip2screw(nscrew,nslip)
      real(8), intent(out) :: rhotot(nslip)
      real(8), intent(out) :: sumrhotot
      real(8), intent(out) :: rhofor(nslip)
!
!     local variables
!
      real(8) vec(3)
      integer i, j
!
!
!
!
!
!     Compute forest density
!     Add gnd and sdd contributions (if exist)
!     Forest projections
      rhofor = forest + matmul(forestproj, abs(gnd)) +
     + matmul(forestproj(1:nslip,1:nslip), ssd) + ! edges
     + matmul(forestproj(1:nslip,nslip+1:nslip+nscrew),
     + matmul(slip2screw,ssd)) ! screws
!
!
      rhotot = ssd +
     + abs(gnd(1:nslip)) + ! edges
     + matmul(transpose(slip2screw), abs(gnd(nslip+1:nslip+nscrew))) ! screws
!
!
!   
!     Scalar sum
      sumrhotot = sqrt(sum(gnd*gnd)) + ssdtot
!
!
      return
      end subroutine totalandforest
!
!
!
!
      end module cpsolver