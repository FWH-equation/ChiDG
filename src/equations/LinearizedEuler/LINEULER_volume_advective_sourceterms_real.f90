module LINEULER_volume_advective_sourceterms_real
    use mod_kinds,              only: rk,ik
    use mod_constants,          only: NFACES,ONE,TWO,HALF,ZERO, &
                                      XI_MIN,XI_MAX,ETA_MIN,ETA_MAX,ZETA_MIN,ZETA_MAX,DIAG

    use type_mesh,              only: mesh_t
    use type_volume_flux,       only: volume_flux_t
    use type_solverdata,        only: solverdata_t
    use type_properties,        only: properties_t
    use type_element_info,      only: element_info_t
    use type_function_info,     only: function_info_t
    
    use mod_interpolate,        only: interpolate_element
    use mod_integrate,          only: integrate_volume_source
    use DNAD_D

    use LINEULER_properties,    only: LINEULER_properties_t
    implicit none

    private


    !>
    !!
    !!  @author Nathan A. Wukie
    !!  @date   3/17/2016
    !!
    !!
    !----------------------------------------------------------------------------------------
    type, extends(volume_flux_t), public :: LINEULER_volume_advective_sourceterms_real_t


    contains

        procedure  :: compute
        
    end type LINEULER_volume_advective_sourceterms_real_t
    !*****************************************************************************************










contains



    !>
    !!
    !!  @author Nathan A. Wukie
    !!  @date   3/17/2016
    !!
    !!
    !-----------------------------------------------------------------------------------------
    subroutine compute(self,mesh,sdata,prop,elem_info,function_info)
        class(LINEULER_volume_advective_sourceterms_real_t),    intent(in)      :: self
        type(mesh_t),                                           intent(in)      :: mesh(:)
        type(solverdata_t),                                     intent(inout)   :: sdata
        class(properties_t),                                    intent(inout)   :: prop
        type(element_info_t),                                   intent(in)      :: elem_info
        type(function_info_t),                                  intent(in)      :: function_info

        ! Equation indices
        integer(ik)    :: irho_r,  irho_i
        integer(ik)    :: irhou_r, irhou_i
        integer(ik)    :: irhov_r, irhov_i
        integer(ik)    :: irhow_r, irhow_i
        integer(ik)    :: irhoE_r, irhoE_i

        integer(ik)    :: idom, ielem, iblk
        real(rk)       :: gam, omega, alpha, eps
        real(rk)       :: x, y



        type(AD_D), dimension(mesh(elem_info%idomain_l)%elems(elem_info%ielement_l)%gq%vol%nnodes)      ::  &
                    rho, rhou, rhov, rhow, rhoE, p, H,                        &
                    flux


        idom  = elem_info%idomain_l
        ielem = elem_info%ielement_l
        iblk  = function_info%iblk


        !
        ! Get equation indices
        !
        irho_r  = prop%get_eqn_index("rho_r")
        irhou_r = prop%get_eqn_index("rhou_r")
        irhov_r = prop%get_eqn_index("rhov_r")
!        irhow_r = prop%get_eqn_index("rhow_r")
        irhoE_r = prop%get_eqn_index("rhoE_r")

        irho_i  = prop%get_eqn_index("rho_i")
        irhou_i = prop%get_eqn_index("rhou_i")
        irhov_i = prop%get_eqn_index("rhov_i")
!        irhow_i = prop%get_eqn_index("rhow_i")
        irhoE_i = prop%get_eqn_index("rhoE_i")







        !
        ! Interpolate solution to quadrature nodes
        !
        call interpolate_element(mesh,sdata%q,idom,ielem,irho_r, rho, function_info%seed)
        call interpolate_element(mesh,sdata%q,idom,ielem,irhou_r,rhou,function_info%seed)
        call interpolate_element(mesh,sdata%q,idom,ielem,irhov_r,rhov,function_info%seed)
!        call interpolate_element(mesh,sdata%q,idom,ielem,irhow_r,rhow,function_info%seed)
        call interpolate_element(mesh,sdata%q,idom,ielem,irhoE_r,rhoE,function_info%seed)



!        ! Initialize flux derivative storage
!        flux = rho
!        flux = ZERO
!
!        !alpha = 0.05_rk
!        alpha = 0.1_rk
!        !alpha = 0.3_rk
!        !===========================
!        !        MASS FLUX
!        !===========================
!        eps = ZERO
!        do igq = 1,size(rho)
!            x = mesh(idom)%elems(ielem)%quad_pts(igq)%c1_
!            y = mesh(idom)%elems(ielem)%quad_pts(igq)%c2_
!
!            flux(igq) = eps * exp(-alpha * (x**TWO + y**TWO) )
!
!        end do
!        flux = ZERO
!
!        call integrate_volume_source(mesh(idom)%elems(ielem),sdata,idom,irho_r,iblk,flux)
!
!
!        !===========================
!        !     X-MOMENTUM FLUX
!        !===========================
!        eps = ZERO
!        do igq = 1,size(rho)
!            x = mesh(idom)%elems(ielem)%quad_pts(igq)%c1_
!            y = mesh(idom)%elems(ielem)%quad_pts(igq)%c2_
!
!            flux(igq) = eps * exp(-alpha * (x**TWO + y**TWO) )
!
!        end do
!        flux = ZERO
!
!        call integrate_volume_source(mesh(idom)%elems(ielem),sdata,idom,irhou_r,iblk,flux)
!
!
!        !============================
!        !     Y-MOMENTUM FLUX
!        !============================
!        eps = ZERO
!        do igq = 1,size(rho)
!            x = mesh(idom)%elems(ielem)%quad_pts(igq)%c1_
!            y = mesh(idom)%elems(ielem)%quad_pts(igq)%c2_
!
!            flux(igq) = eps * exp(-alpha * (x**TWO + y**TWO) )
!
!        end do
!        flux = ZERO
!
!        call integrate_volume_source(mesh(idom)%elems(ielem),sdata,idom,irhov_r,iblk,flux)
!
!!        !============================
!!        !     Z-MOMENTUM FLUX
!!        !============================
!!        flux_x = (rhow*rhou)/rho
!!        flux_y = (rhow*rhov)/rho
!!        flux_z = (rhow*rhow)/rho  +  p
!!
!!        call integrate_volume_flux(mesh(idom)%elems(ielem),sdata,idom,irhow,iblk,flux_x,flux_y,flux_z)
!!
!        !============================
!        !       ENERGY FLUX
!        !============================
!        eps = 1._rk
!        do igq = 1,size(rho)
!            x = mesh(idom)%elems(ielem)%quad_pts(igq)%c1_
!            y = mesh(idom)%elems(ielem)%quad_pts(igq)%c2_
!
!            flux(igq) = eps * exp(-alpha * (x**TWO + y**TWO) )
!
!        end do
!        flux = ZERO
!
!        call integrate_volume_source(mesh(idom)%elems(ielem),sdata,idom,irhoE_r,iblk,flux)

    end subroutine compute
    !**********************************************************************************************************






end module LINEULER_volume_advective_sourceterms_real
