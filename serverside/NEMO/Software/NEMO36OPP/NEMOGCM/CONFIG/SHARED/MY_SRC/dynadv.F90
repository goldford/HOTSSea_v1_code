MODULE dynadv
   !!==============================================================================
   !!                       ***  MODULE  dynadv  ***
   !! Ocean active tracers:  advection scheme control
   !!==============================================================================
   !! History :  1.0  !  2006-11  (G. Madec)  Original code
   !!            3.3  !  2010-10  (C. Ethe, G. Madec)  reorganisation of initialisation phase
   !!            3.6  !  2015-05  (N. Ducousso, G. Madec)  add Hollingsworth scheme as an option 
   !!----------------------------------------------------------------------

   !!----------------------------------------------------------------------
   !!   dyn_adv      : compute the momentum advection trend 
   !!   dyn_adv_init : control the different options of advection scheme
   !!----------------------------------------------------------------------
   USE dom_oce         ! ocean space and time domain
   USE dynadv_cen2     ! centred flux form advection      (dyn_adv_cen2 routine)
   USE dynadv_ubs      ! UBS flux form advection          (dyn_adv_ubs  routine)
   USE dynkeg          ! kinetic energy gradient          (dyn_keg      routine)
   USE dynzad          ! vertical advection               (dyn_zad      routine)
   !
   USE in_out_manager  ! I/O manager
   USE lib_mpp         ! MPP library
   USE timing          ! Timing

   IMPLICIT NONE
   PRIVATE

   PUBLIC dyn_adv       ! routine called by step module
   PUBLIC dyn_adv_init  ! routine called by opa  module
 
   !                                    !* namdyn_adv namelist *
   LOGICAL, PUBLIC ::   ln_dynadv_vec   !: vector form flag
   INTEGER, PUBLIC ::   nn_dynkeg       !: scheme of kinetic energy gradient: =0 C2 ; =1 Hollingsworth
   LOGICAL, PUBLIC ::   ln_dynadv_cen2  !: flux form - 2nd order centered scheme flag
   LOGICAL, PUBLIC ::   ln_dynadv_ubs   !: flux form - 3rd order UBS scheme flag
   LOGICAL, PUBLIC ::   ln_dynzad_zts   !: vertical advection with sub-timestepping (requires vector form)
#if defined key_opp
   INTEGER, PUBLIC ::   nn_dynzad_zts   !: number of sub-time steps for ln_dynzad_zts=T
#endif
   
   INTEGER ::   nadv   ! choice of the formulation and scheme for the advection

   !! * Substitutions
#  include "domzgr_substitute.h90"
#  include "vectopt_loop_substitute.h90"
   !!----------------------------------------------------------------------
   !! NEMO/OPA 3.6 , NEMO Consortium (2015)
   !! $Id: dynadv.F90 5322 2015-06-01 07:54:08Z pabouttier $
   !! Software governed by the CeCILL licence     (NEMOGCM/NEMO_CeCILL.txt)
   !!----------------------------------------------------------------------
CONTAINS

   SUBROUTINE dyn_adv( kt )
      !!---------------------------------------------------------------------
      !!                  ***  ROUTINE dyn_adv  ***
      !!                
      !! ** Purpose :   compute the ocean momentum advection trend.
      !!
      !! ** Method  : - Update (ua,va) with the advection term following nadv
      !!      NB: in flux form advection (ln_dynadv_cen2 or ln_dynadv_ubs=T) 
      !!      a metric term is add to the coriolis term while in vector form 
      !!      it is the relative vorticity which is added to coriolis term
      !!      (see dynvor module).
      !!----------------------------------------------------------------------
      INTEGER, INTENT( in ) ::   kt   ! ocean time-step index
      !!----------------------------------------------------------------------
      !
      IF( nn_timing == 1 )  CALL timing_start('dyn_adv')
      !
      SELECT CASE ( nadv )                  ! compute advection trend and add it to general trend
      CASE ( 0 )     
                      CALL dyn_keg     ( kt, nn_dynkeg )    ! vector form : horizontal gradient of kinetic energy
                      CALL dyn_zad     ( kt )               ! vector form : vertical advection
      CASE ( 1 )     
                      CALL dyn_keg     ( kt, nn_dynkeg )    ! vector form : horizontal gradient of kinetic energy
#if defined key_opp
                      CALL dyn_zad_zts ( kt, nn_dynzad_zts )! vector form : vertical advection with sub-timestepping
#else
                      CALL dyn_zad_zts ( kt )               ! vector form : vertical advection with sub-timestepping
#endif
      CASE ( 2 ) 
                      CALL dyn_adv_cen2( kt )               ! 2nd order centered scheme
      CASE ( 3 )   
                      CALL dyn_adv_ubs ( kt )               ! 3rd order UBS      scheme
      !
      CASE (-1 )                                            ! esopa: test all possibility with control print
                      CALL dyn_keg     ( kt, nn_dynkeg )
                      CALL dyn_zad     ( kt )
                      CALL dyn_adv_cen2( kt )
                      CALL dyn_adv_ubs ( kt )
      END SELECT
      !
      IF( nn_timing == 1 )  CALL timing_stop('dyn_adv')
      !
   END SUBROUTINE dyn_adv

   
   SUBROUTINE dyn_adv_init
      !!---------------------------------------------------------------------
      !!                  ***  ROUTINE dyn_adv_init  ***
      !!                
      !! ** Purpose :   Control the consistency between namelist options for 
      !!              momentum advection formulation & scheme and set nadv
      !!----------------------------------------------------------------------
      INTEGER ::   ioptio, ios   ! Local integer
      !
#if defined key_opp
      NAMELIST/namdyn_adv/ ln_dynadv_vec, nn_dynkeg, ln_dynadv_cen2 , ln_dynadv_ubs, ln_dynzad_zts, nn_dynzad_zts
#else
      NAMELIST/namdyn_adv/ ln_dynadv_vec, nn_dynkeg, ln_dynadv_cen2 , ln_dynadv_ubs, ln_dynzad_zts
#endif
      !!----------------------------------------------------------------------
      !
      REWIND( numnam_ref )              ! Namelist namdyn_adv in reference namelist : Momentum advection scheme
      READ  ( numnam_ref, namdyn_adv, IOSTAT = ios, ERR = 901)
901   IF( ios /= 0 ) CALL ctl_nam ( ios , 'namdyn_adv in reference namelist', lwp )

      REWIND( numnam_cfg )              ! Namelist namdyn_adv in configuration namelist : Momentum advection scheme
      READ  ( numnam_cfg, namdyn_adv, IOSTAT = ios, ERR = 902 )
902   IF( ios /= 0 ) CALL ctl_nam ( ios , 'namdyn_adv in configuration namelist', lwp )
      IF(lwm) WRITE ( numond, namdyn_adv )

      IF(lwp) THEN                    ! Namelist print
         WRITE(numout,*)
         WRITE(numout,*) 'dyn_adv_init : choice/control of the momentum advection scheme'
         WRITE(numout,*) '~~~~~~~~~~~'
         WRITE(numout,*) '       Namelist namdyn_adv : chose a advection formulation & scheme for momentum'
         WRITE(numout,*) '          Vector/flux form (T/F)                           ln_dynadv_vec  = ', ln_dynadv_vec
         WRITE(numout,*) '          = 0 standard scheme  ; =1 Hollingsworth scheme   nn_dynkeg      = ', nn_dynkeg
         WRITE(numout,*) '          2nd order centred advection scheme               ln_dynadv_cen2 = ', ln_dynadv_cen2
         WRITE(numout,*) '          3rd order UBS advection scheme                   ln_dynadv_ubs  = ', ln_dynadv_ubs
         WRITE(numout,*) '          Sub timestepping of vertical advection           ln_dynzad_zts  = ', ln_dynzad_zts
#if defined key_opp
         WRITE(numout,*) '          Number of sub time steps for vertical advection  nn_dynzad_zts  = ', nn_dynzad_zts
#endif
      ENDIF

      ioptio = 0                      ! Parameter control
      IF( ln_dynadv_vec  )   ioptio = ioptio + 1
      IF( ln_dynadv_cen2 )   ioptio = ioptio + 1
      IF( ln_dynadv_ubs  )   ioptio = ioptio + 1
      IF( lk_esopa       )   ioptio =          1

      IF( ioptio /= 1 )   CALL ctl_stop( 'Choose ONE advection scheme in namelist namdyn_adv' )
      IF( ln_dynzad_zts .AND. .NOT. ln_dynadv_vec )   &
         CALL ctl_stop( 'Sub timestepping of vertical advection requires vector form; set ln_dynadv_vec = .TRUE.' )
      IF( nn_dynkeg /= nkeg_C2 .AND. nn_dynkeg /= nkeg_HW )   &  
         CALL ctl_stop( 'KEG scheme wrong value of nn_dynkeg' )

      !                               ! Set nadv
      IF( ln_dynadv_vec  )   nadv =  0 
      IF( ln_dynzad_zts  )   nadv =  1
      IF( ln_dynadv_cen2 )   nadv =  2
      IF( ln_dynadv_ubs  )   nadv =  3
      IF( lk_esopa       )   nadv = -1

      IF(lwp) THEN                    ! Print the choice
         WRITE(numout,*)
         IF( nadv ==  0 )   WRITE(numout,*) '         vector form : keg + zad + vor is used' 
         IF( nadv ==  1 )   WRITE(numout,*) '         vector form : keg + zad_zts + vor is used'
         IF( nadv ==  0 .OR. nadv ==  1 ) THEN
            IF( nn_dynkeg == nkeg_C2  )   WRITE(numout,*) 'with Centered standard keg scheme'
            IF( nn_dynkeg == nkeg_HW  )   WRITE(numout,*) 'with Hollingsworth keg scheme'
         ENDIF
         IF( nadv ==  2 )   WRITE(numout,*) '         flux form   : 2nd order scheme is used'
         IF( nadv ==  3 )   WRITE(numout,*) '         flux form   : UBS       scheme is used'
         IF( nadv == -1 )   WRITE(numout,*) '         esopa test: use all advection formulation'
      ENDIF
      !
   END SUBROUTINE dyn_adv_init

  !!======================================================================
END MODULE dynadv
