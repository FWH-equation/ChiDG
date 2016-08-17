module type_boundary_flux_wrapper
    use type_boundary_flux, only: boundary_flux_t


    !>  Wrapper for polymorphic boundary_flux_t arrays
    !!
    !!  @author Nathan A. Wukie
    !!  @date   2/25/2016
    !!
    !------------------------------------------------------------
    type, public :: boundary_flux_wrapper_t

        class(boundary_flux_t), allocatable  :: flux

    end type boundary_flux_wrapper_t
    !************************************************************


end module type_boundary_flux_wrapper
