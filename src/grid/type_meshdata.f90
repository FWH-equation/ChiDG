module type_meshdata
    use mod_kinds,  only: ik
    use type_point, only: point_t



    !> Data type for returning mesh-data from a file-read routine
    !!
    !!  @author Nathan A. Wukie
    !!  @date   4/11/2016
    !!
    !!
    !-----------------------------------------------------------------------------------------
    type, public :: meshdata_t

        character(len=:),   allocatable :: name                 !< Name of the current block
        !type(point_t),      allocatable :: points(:,:,:)        !< Rank-3 array containing mesh points
        type(point_t),      allocatable :: points(:)            !< Rank-3 array containing mesh points
        integer(ik),        allocatable :: connectivity(:,:)    !< Connectivity data for each element with the indices of associated nodes in the points array 
        character(len=:),   allocatable :: eqnset               !< String indicating the equation set to allocate for the domain
        integer(ik)                     :: spacedim             !< Number of spatial dimensions
        integer(ik)                     :: nterms_c             !< Integer specifying the number of terms in the coordinate expansion
        integer(ik)                     :: proc                 !< Integer specifying the processor assignment

    end type meshdata_t
    !*****************************************************************************************







end module type_meshdata
