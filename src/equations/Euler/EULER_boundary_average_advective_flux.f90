module EULER_boundary_average_advective_flux
    use mod_kinds,              only: rk,ik
    use mod_constants,          only: ONE, TWO, HALF, ME, NEIGHBOR

    use type_boundary_flux,     only: boundary_flux_t
    use type_mesh,              only: mesh_t
    use type_solverdata,        only: solverdata_t
    use type_properties,        only: properties_t
    use type_face_info,         only: face_info_t
    use type_function_info,     only: function_info_t

    use mod_interpolate,        only: interpolate
    use mod_integrate,          only: integrate_boundary_scalar_flux
    use DNAD_D

    use EULER_properties,       only: EULER_properties_t
    implicit none

    private



    !> Implementation of the Euler boundary average flux
    !!
    !!  - At a boundary interface, the solution states Q- and Q+ exists on opposite 
    !!    sides of the boundary. The average flux is computed as Favg = 1/2(F(Q-) + F(Q+))
    !!
    !!  @author Nathan A. Wukie
    !!  @date   1/28/2016
    !!
    !--------------------------------------------------------------------------------
    type, extends(boundary_flux_t), public :: EULER_boundary_average_advective_flux_t

    contains

        procedure  :: compute

    end type EULER_boundary_average_advective_flux_t
    !********************************************************************************










contains



    !>  Boundary Flux routine for Euler
    !!
    !!  @author Nathan A. Wukie
    !!  @date   1/28/2016
    !!
    !!-------------------------------------------------------------------------------------
    subroutine compute(self,mesh,sdata,prop,face_info,function_info)
        class(EULER_boundary_average_advective_flux_t), intent(in)      :: self
        type(mesh_t),                                   intent(in)      :: mesh(:)
        type(solverdata_t),                             intent(inout)   :: sdata
        class(properties_t),                            intent(inout)   :: prop
        type(face_info_t),                              intent(in)      :: face_info
        type(function_info_t),                          intent(in)      :: function_info

        ! Equation indices
        integer(ik)     :: irho
        integer(ik)     :: irhou
        integer(ik)     :: irhov
        integer(ik)     :: irhow
        integer(ik)     :: irhoe



        integer(ik) :: igq


        integer(ik)     :: idom,  ielem,  iface
        integer(ik)     :: idom_m,  ielem_m,  iface_m
        integer(ik)     :: ifcn,  idonor



        ! Storage at quadrature nodes
        !type(AD_D), dimension(mesh(face_info%idomain_l)%faces(face_info%ielement_l,face_info%iface)%gq%face%nnodes)    :: &
        type(AD_D), allocatable,    dimension(:) :: &
                        rho_m,      rho_p,                                  &
                        rhou_m,     rhou_p,                                 &
                        rhov_m,     rhov_p,                                 &
                        rhow_m,     rhow_p,                                 &
                        rhoe_m,     rhoe_p,                                 &
                        rhor_p,     rhot_p,                                 &
                        p_m,        p_p,                                    &
                        H_m,        H_p,                                    &
                        flux_x_m,   flux_y_m,   flux_z_m,                   &
                        flux_x_p,   flux_y_p,   flux_z_p,                   &
                        flux_x,     flux_y,     flux_z,                     &
                        invrho_m,   invrho_p,                               &
                        integrand

        real(rk), dimension(mesh(face_info%idomain_l)%faces(face_info%ielement_l,face_info%iface)%gq%face%nnodes)    :: &
                        x_m, y_m, z_m, r_m, theta_m, theta_p

        real(rk)    :: theta_offset


        irho  = prop%get_eqn_index("rho")
        irhou = prop%get_eqn_index("rhou")
        irhov = prop%get_eqn_index("rhov")
        irhow = prop%get_eqn_index("rhow")
        irhoE = prop%get_eqn_index("rhoE")


        idom  = face_info%idomain_l
        ielem = face_info%ielement_l
        iface = face_info%iface


        associate (norms => mesh(idom)%faces(ielem,iface)%norm, faces => mesh(idom)%faces, q => sdata%q)

            !
            ! Interpolate solution to quadrature nodes
            !
            rho_m  = interpolate(mesh,sdata,face_info,function_info, irho,  'value', ME)
            rho_p  = interpolate(mesh,sdata,face_info,function_info, irho,  'value', NEIGHBOR)

            rhou_m = interpolate(mesh,sdata,face_info,function_info, irhou, 'value', ME)
            rhou_p = interpolate(mesh,sdata,face_info,function_info, irhou, 'value', NEIGHBOR)

            rhov_m = interpolate(mesh,sdata,face_info,function_info, irhov, 'value', ME)
            rhov_p = interpolate(mesh,sdata,face_info,function_info, irhov, 'value', NEIGHBOR)

            rhow_m = interpolate(mesh,sdata,face_info,function_info, irhow, 'value', ME)
            rhow_p = interpolate(mesh,sdata,face_info,function_info, irhow, 'value', NEIGHBOR)

            rhoE_m = interpolate(mesh,sdata,face_info,function_info, irhoE, 'value', ME)
            rhoE_p = interpolate(mesh,sdata,face_info,function_info, irhoE, 'value', NEIGHBOR)

            invrho_m = ONE/rho_m
            invrho_p = ONE/rho_p

!            idom_m  = face_info%idomain
!            ielem_m = face_info%ielement
!            iface_m = face_info%iface
!
!
!            if ( mesh(idom_m)%faces(ielem_m, iface_m)%periodic_type == 'cylindrical' ) then
!                theta_offset = (PI/180._rk)*mesh(idom_m)%faces(ielem_m,iface_m)%chimera_offset_theta
!
!                x_m     = mesh(idom_m)%faces(ielem_m,iface_m)%quad_pts(:)%c1_
!                y_m     = mesh(idom_m)%faces(ielem_m,iface_m)%quad_pts(:)%c2_
!                r_m     = sqrt(x_m**TWO + y_m**TWO)
!                theta_m = atan2(y_m,x_m)
!
!
!                theta_p = theta_m + theta_offset
!
!                !
!                ! Transform 'p' cartesian vector to 'p' cylindrical at theta_p
!                !
!                ! rhor and rhotheta are constant from face to face
!                !
!                rhor_p =  cos(theta_p)*rhou_p + sin(theta_p)*rhov_p ! rhor
!                rhot_p = -sin(theta_p)*rhou_p + cos(theta_p)*rhov_p ! rhotheta
!
!
!                !
!                ! Transform 'p' cylindrical to 'p' cartesian at theta_m
!                !
!                rhou_p = cos(theta_m)*rhor_p - sin(theta_m)*rhot_p
!                rhov_p = sin(theta_m)*rhor_p + cos(theta_m)*rhot_p
!
!            end if
!
!
!





            !
            ! Compute pressure and total enthalpy
            !
            call prop%fluid%compute_pressure(rho_m,rhou_m,rhov_m,rhow_m,rhoE_m,p_m)
            call prop%fluid%compute_pressure(rho_p,rhou_p,rhov_p,rhow_p,rhoE_p,p_p)

            H_m = (rhoE_m + p_m)*invrho_m
            H_p = (rhoE_p + p_p)*invrho_p



            !================================
            !       MASS FLUX
            !================================
            flux_x_m = rhou_m
            flux_y_m = rhov_m
            flux_z_m = rhow_m

            flux_x_p = rhou_p
            flux_y_p = rhov_p
            flux_z_p = rhow_p

            flux_x = (flux_x_m + flux_x_p)
            flux_y = (flux_y_m + flux_y_p)
            flux_z = (flux_z_m + flux_z_p)


            ! dot with normal vector
            integrand = HALF*(flux_x*norms(:,1) + flux_y*norms(:,2) + flux_z*norms(:,3))

            call integrate_boundary_scalar_flux(mesh,sdata,face_info,function_info,irho,integrand)


            !================================
            !       X-MOMENTUM FLUX
            !================================
            flux_x_m = (rhou_m*rhou_m)*invrho_m + p_m
            flux_y_m = (rhou_m*rhov_m)*invrho_m
            flux_z_m = (rhou_m*rhow_m)*invrho_m

            flux_x_p = (rhou_p*rhou_p)*invrho_p + p_p
            flux_y_p = (rhou_p*rhov_p)*invrho_p
            flux_z_p = (rhou_p*rhow_p)*invrho_p

            flux_x = (flux_x_m + flux_x_p)
            flux_y = (flux_y_m + flux_y_p)
            flux_z = (flux_z_m + flux_z_p)


            ! dot with normal vector
            integrand = HALF*(flux_x*norms(:,1) + flux_y*norms(:,2) + flux_z*norms(:,3))

            call integrate_boundary_scalar_flux(mesh,sdata,face_info,function_info,irhou,integrand)


            !================================
            !       Y-MOMENTUM FLUX
            !================================
            flux_x_m = (rhov_m*rhou_m)*invrho_m
            flux_y_m = (rhov_m*rhov_m)*invrho_m + p_m
            flux_z_m = (rhov_m*rhow_m)*invrho_m

            flux_x_p = (rhov_p*rhou_p)*invrho_p
            flux_y_p = (rhov_p*rhov_p)*invrho_p + p_p
            flux_z_p = (rhov_p*rhow_p)*invrho_p

            flux_x = (flux_x_m + flux_x_p)
            flux_y = (flux_y_m + flux_y_p)
            flux_z = (flux_z_m + flux_z_p)


            ! dot with normal vector
            integrand = HALF*(flux_x*norms(:,1) + flux_y*norms(:,2) + flux_z*norms(:,3))

            call integrate_boundary_scalar_flux(mesh,sdata,face_info,function_info,irhov,integrand)


            !================================
            !       Z-MOMENTUM FLUX
            !================================
            flux_x_m = (rhow_m*rhou_m)*invrho_m
            flux_y_m = (rhow_m*rhov_m)*invrho_m
            flux_z_m = (rhow_m*rhow_m)*invrho_m + p_m

            flux_x_p = (rhow_p*rhou_p)*invrho_p
            flux_y_p = (rhow_p*rhov_p)*invrho_p
            flux_z_p = (rhow_p*rhow_p)*invrho_p + p_p

            flux_x = (flux_x_m + flux_x_p)
            flux_y = (flux_y_m + flux_y_p)
            flux_z = (flux_z_m + flux_z_p)


            ! dot with normal vector
            integrand = HALF*(flux_x*norms(:,1) + flux_y*norms(:,2) + flux_z*norms(:,3))

            call integrate_boundary_scalar_flux(mesh,sdata,face_info,function_info,irhow,integrand)


            !================================
            !          ENERGY FLUX
            !================================
            flux_x_m = rhou_m*H_m
            flux_y_m = rhov_m*H_m
            flux_z_m = rhow_m*H_m

            flux_x_p = rhou_p*H_p
            flux_y_p = rhov_p*H_p
            flux_z_p = rhow_p*H_p

            flux_x = (flux_x_m + flux_x_p)
            flux_y = (flux_y_m + flux_y_p)
            flux_z = (flux_z_m + flux_z_p)


            ! dot with normal vector
            integrand = HALF*(flux_x*norms(:,1) + flux_y*norms(:,2) + flux_z*norms(:,3))

            call integrate_boundary_scalar_flux(mesh,sdata,face_info,function_info,irhoE,integrand)

        end associate


    end subroutine compute
    !*********************************************************************************************************












end module EULER_boundary_average_advective_flux
