module spalart_allmaras_bc_diffusion
    use mod_kinds,              only: rk,ik
    use mod_constants,          only: ZERO, ONE, TWO, HALF

    use type_operator,          only: operator_t
    use type_chidg_worker,      only: chidg_worker_t
    use type_properties,        only: properties_t
    use DNAD_D

    use mod_spalart_allmaras,   only: SA_c_n1, SA_sigma
    implicit none

    private



    !>  Volume diffusion integral for Spalart-Allmaras flux terms.
    !!
    !!
    !!  @author Nathan A. Wukie
    !!  @date   12/9/2016
    !!
    !-----------------------------------------------------------------------------------------
    type, extends(operator_t), public :: spalart_allmaras_bc_diffusion_operator_t

    contains

        procedure   :: init
        procedure   :: compute

    end type spalart_allmaras_bc_diffusion_operator_t
    !*****************************************************************************************










contains



    !>
    !!
    !!  @author Nathan A. Wukie (AFRL)
    !!  @date   8/29/2016
    !!
    !-----------------------------------------------------------------------------------------
    subroutine init(self)
        class(spalart_allmaras_bc_diffusion_operator_t),   intent(inout) :: self
        
        !
        ! Set operator name
        !
        call self%set_name("Spalart-Allmaras BC Diffusion Operator")

        !
        ! Set operator type
        !
        call self%set_operator_type("BC Diffusive Flux")

        !
        ! Set operator equations
        !
        call self%add_primary_field("Density * NuTilde")

    end subroutine init
    !*****************************************************************************************



    !>  Boundary Flux routine for Euler
    !!
    !!  @author Nathan A. Wukie
    !!  @date   1/28/2016
    !!
    !!----------------------------------------------------------------------------------------
    subroutine compute(self,worker,prop)
        class(spalart_allmaras_bc_diffusion_operator_t),    intent(inout)   :: self
        type(chidg_worker_t),                               intent(inout)   :: worker
        class(properties_t),                                intent(inout)   :: prop

        ! Storage at quadrature nodes
        type(AD_D), allocatable, dimension(:) ::    &
            rho, rho_nutilde, invrho,               &
            nutilde, chi, f_n1, nu_l, mu_l,         &
            drho_dx, dnutilde_dx, drho_nutilde_dx,  &
            drho_dy, dnutilde_dy, drho_nutilde_dy,  &
            drho_dz, dnutilde_dz, drho_nutilde_dz,  &
            dnutilde_drho, dnutilde_drhonutilde,    &
            eps,                                    &
            flux_x, flux_y, flux_z, diffusion, integrand


        real(rk), allocatable, dimension(:) ::      &
            normx, normy, normz



        !
        ! Interpolate solution to quadrature nodes
        !
        rho         = worker%get_primary_field_face('Density',          'value','boundary')
        rho_nutilde = worker%get_primary_field_face('Density * NuTilde','value','boundary')
        eps         = worker%get_primary_field_face('Artificial Viscosity', 'value', 'boundary')


        !
        ! Interpolate gradient to quadrature nodes
        !
        drho_dx         = worker%get_primary_field_face('Density',          'ddx+lift','boundary')
        drho_dy         = worker%get_primary_field_face('Density',          'ddy+lift','boundary')
        drho_dz         = worker%get_primary_field_face('Density',          'ddz+lift','boundary')

        drho_nutilde_dx = worker%get_primary_field_face('Density * NuTilde','ddx+lift','boundary')
        drho_nutilde_dy = worker%get_primary_field_face('Density * NuTilde','ddy+lift','boundary')
        drho_nutilde_dz = worker%get_primary_field_face('Density * NuTilde','ddz+lift','boundary')





        invrho = ONE/rho


        !
        ! Get normal vector
        !
        normx = worker%normal(1)
        normy = worker%normal(2)
        normz = worker%normal(3)




        !
        ! Get model fields:
        !   Viscosity
        !
        mu_l = worker%get_model_field_face('Laminar Viscosity','value','boundary')
        nu_l = mu_l*invrho


        !
        ! Compute nutilde, chi
        !
        nutilde = rho_nutilde*invrho
        chi     = nutilde/nu_l



        ! Initialize derivatives first
        f_n1 = rho
        where (nutilde >= ZERO)
            f_n1 = ONE
        else where
            f_n1 = (SA_c_n1 + chi*chi*chi)/(SA_c_n1 - chi*chi*chi)
        end where



        !
        ! Compute nutilde jacobians for gradient calculation using chain-rule.
        !
        dnutilde_drho        = -rho_nutilde*invrho*invrho
        dnutilde_drhonutilde =  invrho


        dnutilde_dx = dnutilde_drho * drho_dx  +  dnutilde_drhonutilde * drho_nutilde_dx
        dnutilde_dy = dnutilde_drho * drho_dy  +  dnutilde_drhonutilde * drho_nutilde_dy
        dnutilde_dz = dnutilde_drho * drho_dz  +  dnutilde_drhonutilde * drho_nutilde_dz


        !================================
        !       TURBULENCE FLUX
        !================================
        diffusion = -(ONE/SA_sigma)*(mu_l + f_n1*rho_nutilde)


        flux_x = (diffusion - 00._rk*eps)*dnutilde_dx
        flux_y = (diffusion - 00._rk*eps)*dnutilde_dy
        flux_z = (diffusion - 00._rk*eps)*dnutilde_dz

        integrand = flux_x*normx + flux_y*normy + flux_z*normz

        call worker%integrate_boundary('Density * NuTilde',integrand)


    end subroutine compute
    !******************************************************************************************












end module spalart_allmaras_bc_diffusion
