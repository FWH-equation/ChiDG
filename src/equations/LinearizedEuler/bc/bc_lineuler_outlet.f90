module bc_lineuler_outlet
    use mod_kinds,          only: rk,ik
    use mod_constants,      only: ONE, TWO, HALF, ZERO, LOCAL
    use type_bc,            only: bc_t
    use type_solverdata,    only: solverdata_t
    use type_mesh,          only: mesh_t
    use type_properties,    only: properties_t
    use type_face_info,     only: face_info_t
    use type_function_info, only: function_info_t

    use mod_integrate,      only: integrate_boundary_scalar_flux
    use mod_interpolate,    only: interpolate_face
    use DNAD_D
    
    use LINEULER_properties,   only: LINEULER_properties_t
    use mod_linearized_euler
    implicit none


    !>  Extrapolation boundary condition 
    !!      - Extrapolate interior variables to be used for calculating the boundary flux.
    !!  
    !!  @author Nathan A. Wukie
    !!  @date   3/17/2016
    !!
    !-------------------------------------------------------------------------------------------
    type, public, extends(bc_t) :: lineuler_outlet_t

    contains
    
        procedure   :: add_options
        procedure :: compute    !> bc implementation

    end type lineuler_outlet_t
    !*******************************************************************************************




contains



    !>
    !!
    !!  @author Nathan A. Wukie
    !!  @date   3/17/2016
    !!
    !!
    !!
    !-------------------------------------------------------------------------------------------
    subroutine add_options(self)
        class(lineuler_outlet_t),    intent(inout)   :: self

        !
        ! Set name
        ! 
        call self%set_name('lineuler_outlet')


    end subroutine add_options
    !*******************************************************************************************











    !> Specialized compute routine for Extrapolation Boundary Condition
    !!
    !!  @author Nathan A. Wukie
    !!  @date   3/17/2016
    !!
    !!  @param[in]      mesh    Mesh data containing elements and faces for the domain
    !!  @param[inout]   sdata   Solver data containing solution vector, rhs, linearization, etc.
    !!  @param[in]      ielem   Index of the element being computed
    !!  @param[in]      iface   Index of the face being computed
    !!  @param[in]      iblk    Index of the linearization block being computed
    !!  @param[inout]   prop    properties_t object containing equations and material_t objects
    !!
    !-------------------------------------------------------------------------------------------
    subroutine compute(self,mesh,sdata,prop,face,flux)
        class(lineuler_outlet_t),       intent(inout)   :: self
        type(mesh_t),                   intent(in)      :: mesh(:)
        type(solverdata_t),             intent(inout)   :: sdata
        class(properties_t),            intent(inout)   :: prop
        type(face_info_t),              intent(in)      :: face
        type(function_info_t),          intent(in)      :: flux


        ! Equation indices
        integer(ik)     :: irho_r, irhou_r, irhov_r, irhow_r, irhoE_r
        integer(ik)     :: irho_i, irhou_i, irhov_i, irhow_i, irhoE_i


        ! Storage at quadrature nodes
        type(AD_D), dimension(mesh(face%idomain_l)%faces(face%ielement_l,face%iface)%gq%face%nnodes)   ::  &
                        rho_r,      rhou_r,     rhov_r,     rhow_r,     rhoE_r,         &
                        rho_i,      rhou_i,     rhov_i,     rhow_i,     rhoE_i,         &
                        p_r,        u_r,        v_r,        w_r,                        &
                        p_i,        u_i,        v_i,        w_i,                        &
                        c1,         c2,         c3,         c4,                         &
                        drho,       du,         dv,         dp,                         &
                        drho_total, du_total,   dv_total,   dp_total,                   &
                        U_n,        V_n,        dU_n,       dV_n,                       &
                        flux_x, flux_y, flux_z, integrand





        !
        ! Get equation indices
        !
        irho_r  = prop%get_eqn_index("rho_r")
        irhou_r = prop%get_eqn_index("rhou_r")
        irhov_r = prop%get_eqn_index("rhov_r")
        irhow_r = prop%get_eqn_index("rhow_r")
        irhoE_r = prop%get_eqn_index("rhoE_r")


        irho_i  = prop%get_eqn_index("rho_i")
        irhou_i = prop%get_eqn_index("rhou_i")
        irhov_i = prop%get_eqn_index("rhov_i")
        irhow_i = prop%get_eqn_index("rhow_i")
        irhoE_i = prop%get_eqn_index("rhoE_i")




        associate ( idom => face%idomain_l, ielem => face%ielement_l, iface => face%iface )

            associate (norms => mesh(idom)%faces(ielem,iface)%norm, unorms => mesh(idom)%faces(ielem,iface)%unorm, faces => mesh(idom)%faces, q => sdata%q)

            !
            ! Interpolate interior solution to quadrature nodes
            !
            call interpolate_face(mesh,face,q,irho_r, rho_r,  LOCAL)
            call interpolate_face(mesh,face,q,irhou_r,rhou_r, LOCAL)
            call interpolate_face(mesh,face,q,irhov_r,rhov_r, LOCAL)
            call interpolate_face(mesh,face,q,irhow_r,rhow_r, LOCAL)
            call interpolate_face(mesh,face,q,irhoE_r,rhoE_r, LOCAL)


            call interpolate_face(mesh,face,q,irho_i, rho_i,  LOCAL)
            call interpolate_face(mesh,face,q,irhou_i,rhou_i, LOCAL)
            call interpolate_face(mesh,face,q,irhov_i,rhov_i, LOCAL)
            call interpolate_face(mesh,face,q,irhow_i,rhow_i, LOCAL)
            call interpolate_face(mesh,face,q,irhoE_i,rhoE_i, LOCAL)





            !------------------------------
            !
            !   REAL COMPONENT
            !
            !------------------------------




            !
            ! Compute linearized velocity
            !
            ! NOTE: can't just do "u = rhou/rho" because this is nonlinear. Below is the linearization of this formula.
            !
            u_r = rhou_r/rhobar  -  rhobar*ubar * rho_r
            v_r = rhov_r/rhobar  -  rhobar*vbar * rho_r
            w_r = rhow_r/rhobar  -  rhobar*wbar * rho_r



            !
            ! Compute real pressure
            !
            ! TODO: Double check linearization of pressure equation here
            !
            p_r = (gam-ONE)*(rhoE_r + HALF*(ubar**TWO + vbar**TWO + wbar**TWO)*rho_r - ( ubar*rhou_r  +  vbar*rhov_r  +  wbar*rhow_r ) )

            


            !
            ! Compute normal velocity component for characteristic analysis
            !
!            U_n = u_r*unorms(:,1) + v_r*unorms(:,2) + w_r*unorms(:,3)
!            V_n = u_r*(-unorms(:,2)) + v_r*(unorms(:,1))




            !
            ! Compute outgoing Characteristics, c1,c2,c3, from perturbed variables
            !
            c1 = -cbar**TWO * rho_r
            c2 = rhobar*cbar * v_r
            c3 = rhobar*cbar * u_r  +  p_r

!            c1 = -cbar**TWO * rho_r
!            c2 = rhobar*cbar * V_n
!            c3 = rhobar*cbar * U_n  +  p_r


            !
            ! Get contribution to variables from interior solution, coming from [c1,c2,c3]
            !
            drho  = -(ONE/(cbar**TWO))*c1  +  (ONE/(TWO*cbar**TWO))*c3
            du    =  (ONE/(TWO*rhobar*cbar))*c3
            dv    =  (ONE/(rhobar*cbar))*c2
            dp    =  HALF*c3
            
!            drho  = -(ONE/(cbar**TWO))*c1  +  (ONE/(TWO*cbar**TWO))*c3
!            dU_n  =  (ONE/(TWO*rhobar*cbar))*c3
!            dV_n  =  (ONE/(rhobar*cbar))*c2
!            dp    =  HALF*c3


            !
            ! Project perturbed velocities into cartesian components
            !
!            du    = dU_n*unorms(:,1) + dV_n*unorms(:,1)
!            dv    = dU_n*unorms(:,2) + dV_n*unorms(:,2)



            !
            ! Accumulate perturbations from interior and user-specified data
            !
            drho_total = drho 
            du_total   = du 
            dv_total   = dv
            dp_total   = dp 

            rho_r  = drho
            rhou_r = rhobar*du_total  +  rhobar*rhobar*ubar*rho_r
            rhov_r = rhobar*dv_total  +  rhobar*rhobar*vbar*rho_r
            rhow_r = rhow_r
            rhoE_r = p_r/(gam-ONE) - ( HALF*(ubar**TWO + vbar**TWO + wbar**TWO)*rho_r - ( ubar*rhou_r  +  vbar*rhov_r  +  wbar*rhow_r ) )








            !------------------------------
            !
            !   IMAGINARY COMPONENT
            !
            !------------------------------




            !
            ! Compute linearized velocity
            !
            ! NOTE: can't just do "u = rhou/rho" because this is nonlinear. Below is the linearization of this formula.
            !
            u_i = rhou_i/rhobar  -  rhobar*ubar * rho_i
            v_i = rhov_i/rhobar  -  rhobar*vbar * rho_i
            w_i = rhow_i/rhobar  -  rhobar*wbar * rho_i



            !
            ! Compute real pressure
            !
            ! TODO: Double check linearization of pressure equation here
            !
            p_i = (gam-ONE)*(rhoE_i + HALF*(ubar**TWO + vbar**TWO + wbar**TWO)*rho_i - ( ubar*rhou_i  +  vbar*rhov_i  +  wbar*rhow_i ) )

            


            !
            ! Compute normal velocity component for characteristic analysis
            !
            U_n = u_r*unorms(:,1) + v_i*unorms(:,2) + w_i*unorms(:,3)
            V_n = u_i*(-unorms(:,2)) + v_i*(unorms(:,1))




            !
            ! Compute outgoing Characteristics, c1,c2,c3, from perturbed variables
            !
            c1 = -cbar**TWO * rho_i
            c2 = rhobar*cbar * v_i
            c3 = rhobar*cbar * u_i  +  p_i

!            c1 = -cbar**TWO * rho_r
!            c2 = rhobar*cbar * V_n
!            c3 = rhobar*cbar * U_n  +  p_r


            !
            ! Get contribution to variables from interior solution, coming from [c1,c2,c3]
            !
            drho  = -(ONE/(cbar**TWO))*c1  +  (ONE/(TWO*cbar**TWO))*c3
            du    =  (ONE/(TWO*rhobar*cbar))*c3
            dv    =  (ONE/(rhobar*cbar))*c2
            dp    =  HALF*c3
            
!            drho  = -(ONE/(cbar**TWO))*c1  +  (ONE/(TWO*cbar**TWO))*c3
!            dU_n  =  (ONE/(TWO*rhobar*cbar))*c3
!            dV_n  =  (ONE/(rhobar*cbar))*c2
!            dp    =  HALF*c3


            !
            ! Project perturbed velocities into cartesian components
            !
!            du    = dU_n*unorms(:,1)
!            dv    = dV_n*unorms(:,2)



            !
            ! Accumulate perturbations from interior and user-specified data
            !
            drho_total = drho 
            du_total   = du 
            dv_total   = dv
            dp_total   = dp 

            rho_i  = drho
            rhou_i = rhobar*du_total  +  rhobar*rhobar*ubar*rho_i
            rhov_i = rhobar*dv_total  +  rhobar*rhobar*vbar*rho_i
            rhow_i = rhow_i
            rhoE_i = p_i/(gam-ONE) - ( HALF*(ubar**TWO + vbar**TWO + wbar**TWO)*rho_i - ( ubar*rhou_i  +  vbar*rhov_i  +  wbar*rhow_i ) )



























            !=================================================
            ! Mass flux
            !=================================================
            flux_x = rho_x_rho  * rho_r  + &
                     rho_x_rhou * rhou_r + &
                     rho_x_rhov * rhov_r + &
                     rho_x_rhow * rhow_r + &
                     rho_x_rhoE * rhoE_r
            flux_y = rho_y_rho  * rho_r  + &
                     rho_y_rhou * rhou_r + &
                     rho_y_rhov * rhov_r + &
                     rho_y_rhow * rhow_r + &
                     rho_y_rhoE * rhoE_r
            flux_z = rho_z_rho  * rho_r  + &
                     rho_z_rhou * rhou_r + &
                     rho_z_rhov * rhov_r + &
                     rho_z_rhow * rhow_r + &
                     rho_z_rhoE * rhoE_r

            integrand = flux_x*norms(:,1) + flux_y*norms(:,2) + flux_z*norms(:,3)

            call integrate_boundary_scalar_flux(mesh,sdata,face,flux,irho_r,integrand)





            flux_x = rho_x_rho  * rho_i  + &
                     rho_x_rhou * rhou_i + &
                     rho_x_rhov * rhov_i + &
                     rho_x_rhow * rhow_i + &
                     rho_x_rhoE * rhoE_i
            flux_y = rho_y_rho  * rho_i  + &
                     rho_y_rhou * rhou_i + &
                     rho_y_rhov * rhov_i + &
                     rho_y_rhow * rhow_i + &
                     rho_y_rhoE * rhoE_i
            flux_z = rho_z_rho  * rho_i  + &
                     rho_z_rhou * rhou_i + &
                     rho_z_rhov * rhov_i + &
                     rho_z_rhow * rhow_i + &
                     rho_z_rhoE * rhoE_i

            integrand = flux_x*norms(:,1) + flux_y*norms(:,2) + flux_z*norms(:,3)

            call integrate_boundary_scalar_flux(mesh,sdata,face,flux,irho_i,integrand)









            !=================================================
            ! x-momentum flux
            !=================================================
            flux_x = rhou_x_rho  * rho_r  + &
                     rhou_x_rhou * rhou_r + &
                     rhou_x_rhov * rhov_r + &
                     rhou_x_rhow * rhow_r + &
                     rhou_x_rhoE * rhoE_r
            flux_y = rhou_y_rho  * rho_r  + &
                     rhou_y_rhou * rhou_r + &
                     rhou_y_rhov * rhov_r + &
                     rhou_y_rhow * rhow_r + &
                     rhou_y_rhoE * rhoE_r
            flux_z = rhou_z_rho  * rho_r  + &
                     rhou_z_rhou * rhou_r + &
                     rhou_z_rhov * rhov_r + &
                     rhou_z_rhow * rhow_r + &
                     rhou_z_rhoE * rhoE_r

            integrand = flux_x*norms(:,1) + flux_y*norms(:,2) + flux_z*norms(:,3)

            call integrate_boundary_scalar_flux(mesh,sdata,face,flux,irhou_r,integrand)



            flux_x = rhou_x_rho  * rho_i  + &
                     rhou_x_rhou * rhou_i + &
                     rhou_x_rhov * rhov_i + &
                     rhou_x_rhow * rhow_i + &
                     rhou_x_rhoE * rhoE_i
            flux_y = rhou_y_rho  * rho_i  + &
                     rhou_y_rhou * rhou_i + &
                     rhou_y_rhov * rhov_i + &
                     rhou_y_rhow * rhow_i + &
                     rhou_y_rhoE * rhoE_i
            flux_z = rhou_z_rho  * rho_i  + &
                     rhou_z_rhou * rhou_i + &
                     rhou_z_rhov * rhov_i + &
                     rhou_z_rhow * rhow_i + &
                     rhou_z_rhoE * rhoE_i

            integrand = flux_x*norms(:,1) + flux_y*norms(:,2) + flux_z*norms(:,3)

            call integrate_boundary_scalar_flux(mesh,sdata,face,flux,irhou_i,integrand)






            !=================================================
            ! y-momentum flux
            !=================================================

            flux_x = rhov_x_rho  * rho_r  + &
                     rhov_x_rhou * rhou_r + &
                     rhov_x_rhov * rhov_r + &
                     rhov_x_rhow * rhow_r + &
                     rhov_x_rhoE * rhoE_r
            flux_y = rhov_y_rho  * rho_r  + &
                     rhov_y_rhou * rhou_r + &
                     rhov_y_rhov * rhov_r + &
                     rhov_y_rhow * rhow_r + &
                     rhov_y_rhoE * rhoE_r
            flux_z = rhov_z_rho  * rho_r  + &
                     rhov_z_rhou * rhou_r + &
                     rhov_z_rhov * rhov_r + &
                     rhov_z_rhow * rhow_r + &
                     rhov_z_rhoE * rhoE_r

            integrand = flux_x*norms(:,1) + flux_y*norms(:,2) + flux_z*norms(:,3)

            call integrate_boundary_scalar_flux(mesh,sdata,face,flux,irhov_r,integrand)


            flux_x = rhov_x_rho  * rho_i  + &
                     rhov_x_rhou * rhou_i + &
                     rhov_x_rhov * rhov_i + &
                     rhov_x_rhow * rhow_i + &
                     rhov_x_rhoE * rhoE_i
            flux_y = rhov_y_rho  * rho_i  + &
                     rhov_y_rhou * rhou_i + &
                     rhov_y_rhov * rhov_i + &
                     rhov_y_rhow * rhow_i + &
                     rhov_y_rhoE * rhoE_i
            flux_z = rhov_z_rho  * rho_i  + &
                     rhov_z_rhou * rhou_i + &
                     rhov_z_rhov * rhov_i + &
                     rhov_z_rhow * rhow_i + &
                     rhov_z_rhoE * rhoE_i

            integrand = flux_x*norms(:,1) + flux_y*norms(:,2) + flux_z*norms(:,3)

            call integrate_boundary_scalar_flux(mesh,sdata,face,flux,irhov_i,integrand)











            !=================================================
            ! z-momentum flux
            !=================================================

            flux_x = rhow_x_rho  * rho_r  + &
                     rhow_x_rhou * rhou_r + &
                     rhow_x_rhov * rhov_r + &
                     rhow_x_rhow * rhow_r + &
                     rhow_x_rhoE * rhoE_r
            flux_y = rhow_y_rho  * rho_r  + &
                     rhow_y_rhou * rhou_r + &
                     rhow_y_rhov * rhov_r + &
                     rhow_y_rhow * rhow_r + &
                     rhow_y_rhoE * rhoE_r
            flux_z = rhow_z_rho  * rho_r  + &
                     rhow_z_rhou * rhou_r + &
                     rhow_z_rhov * rhov_r + &
                     rhow_z_rhow * rhow_r + &
                     rhow_z_rhoE * rhoE_r

            integrand = flux_x*norms(:,1) + flux_y*norms(:,2) + flux_z*norms(:,3)

            call integrate_boundary_scalar_flux(mesh,sdata,face,flux,irhow_r,integrand)


            flux_x = rhow_x_rho  * rho_i  + &
                     rhow_x_rhou * rhou_i + &
                     rhow_x_rhov * rhov_i + &
                     rhow_x_rhow * rhow_i + &
                     rhow_x_rhoE * rhoE_i
            flux_y = rhow_y_rho  * rho_i  + &
                     rhow_y_rhou * rhou_i + &
                     rhow_y_rhov * rhov_i + &
                     rhow_y_rhow * rhow_i + &
                     rhow_y_rhoE * rhoE_i
            flux_z = rhow_z_rho  * rho_i  + &
                     rhow_z_rhou * rhou_i + &
                     rhow_z_rhov * rhov_i + &
                     rhow_z_rhow * rhow_i + &
                     rhow_z_rhoE * rhoE_i

            integrand = flux_x*norms(:,1) + flux_y*norms(:,2) + flux_z*norms(:,3)

            call integrate_boundary_scalar_flux(mesh,sdata,face,flux,irhow_i,integrand)







            !=================================================
            ! Energy flux
            !=================================================


            flux_x = rhoE_x_rho  * rho_r  + &
                     rhoE_x_rhou * rhou_r + &
                     rhoE_x_rhov * rhov_r + &
                     rhoE_x_rhow * rhow_r + &
                     rhoE_x_rhoE * rhoE_r
            flux_y = rhoE_y_rho  * rho_r  + &
                     rhoE_y_rhou * rhou_r + &
                     rhoE_y_rhov * rhov_r + &
                     rhoE_y_rhow * rhow_r + &
                     rhoE_y_rhoE * rhoE_r
            flux_z = rhoE_z_rho  * rho_r  + &
                     rhoE_z_rhou * rhou_r + &
                     rhoE_z_rhov * rhov_r + &
                     rhoE_z_rhow * rhow_r + &
                     rhoE_z_rhoE * rhoE_r

            integrand = flux_x*norms(:,1) + flux_y*norms(:,2) + flux_z*norms(:,3)

            call integrate_boundary_scalar_flux(mesh,sdata,face,flux,irhoE_r,integrand)


            flux_x = rhoE_x_rho  * rho_i  + &
                     rhoE_x_rhou * rhou_i + &
                     rhoE_x_rhov * rhov_i + &
                     rhoE_x_rhow * rhow_i + &
                     rhoE_x_rhoE * rhoE_i
            flux_y = rhoE_y_rho  * rho_i  + &
                     rhoE_y_rhou * rhou_i + &
                     rhoE_y_rhov * rhov_i + &
                     rhoE_y_rhow * rhow_i + &
                     rhoE_y_rhoE * rhoE_i
            flux_z = rhoE_z_rho  * rho_i  + &
                     rhoE_z_rhou * rhou_i + &
                     rhoE_z_rhov * rhov_i + &
                     rhoE_z_rhow * rhow_i + &
                     rhoE_z_rhoE * rhoE_i

            integrand = flux_x*norms(:,1) + flux_y*norms(:,2) + flux_z*norms(:,3)

            call integrate_boundary_scalar_flux(mesh,sdata,face,flux,irhoE_i,integrand)




            end associate

        end associate

    end subroutine compute
    !*********************************************************************************************************






end module bc_lineuler_outlet
