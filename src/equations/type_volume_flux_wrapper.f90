module type_volume_flux_wrapper
    use type_volume_flux, only: volume_flux_t


    !>
    !!
    !!  @author Nathan A. Wukie
    !!
    !!
    !-------------------------------------------------------------------
    type, public :: volume_flux_wrapper_t

        class(volume_flux_t), allocatable  :: flux

    end type volume_flux_wrapper_t
    !*******************************************************************


end module type_volume_flux_wrapper
