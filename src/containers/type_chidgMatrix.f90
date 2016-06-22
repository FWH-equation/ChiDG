module type_chidgMatrix
#include <messenger.h>
    use mod_kinds,              only: rk, ik
    use type_blockmatrix,       only: blockmatrix_t
    use type_mesh,              only: mesh_t
    use type_face_info,         only: face_info_t
    use type_seed,              only: seed_t
    use type_bcset_coupling,    only: bcset_coupling_t
    use DNAD_D
    implicit none




    !> ChiDG matrix type. Contains an array of blockmatrix_t types, each corresponding to a domain.
    !!
    !!
    !!  @author Nathan A. Wukie
    !!  @date   2/1/2016
    !!
    !!
    !-----------------------------------------------------------------------------------------------------------
    type, public :: chidgMatrix_t

        type(blockmatrix_t), allocatable    :: dom(:)       !< Array of block-matrices. One for each domain

    contains
        ! Initializers
        generic,    public  :: init => initialize
        procedure,  private :: initialize                   !< ChiDGMatrix initialization

        ! Setters
        procedure   :: store                                !< Store linearization data for local blocks
        procedure   :: store_chimera                        !< Store linearization data for chimera blocks
        procedure   :: store_bc                             !< Store linearization data for boundary condition blocks
        procedure   :: clear                                !< Zero matrix-values


        final       :: destructor

    end type chidgMatrix_t
    !***********************************************************************************************************



    private
contains




    !>  Subroutine for initializing chidgMatrix_t
    !!
    !!  @author Nathan A. Wukie
    !!  @date   2/1/2016
    !!
    !!  @param[in]  domains     Array of domain_t instances
    !!  
    !!
    !-----------------------------------------------------------------------------------------------------------
    subroutine initialize(self,mesh,bcset_coupling,mtype)
        class(chidgMatrix_t),   intent(inout)           :: self
        type(mesh_t),           intent(in)              :: mesh(:)
        type(bcset_coupling_t), intent(in), optional    :: bcset_coupling(:)
        character(*),           intent(in)              :: mtype

        integer(ik) :: ierr, ndomains, idom


        !
        ! Allocate blockmatrix_t for each domain
        !
        ndomains = size(mesh)
        allocate(self%dom(ndomains), stat=ierr)
        if (ierr /= 0) call AllocationError



        !
        ! Call initialization procedure for each blockmatrix_t
        !
        do idom = 1,ndomains

            if ( present(bcset_coupling) ) then
                call self%dom(idom)%init(mesh(idom),bcset_coupling(idom),mtype)
            else
                call self%dom(idom)%init(mesh(idom),mtype=mtype)
            end if

        end do



    end subroutine initialize
    !***********************************************************************************************************








    !> Procedure for storing linearization information
    !!
    !!  @author Nathan A. Wukie
    !!  @date   2/1/2016
    !!
    !!
    !!  @param[in]  integral    Array of modes from the spatial scheme, with embedded partial derivatives for the linearization matrix
    !!  @param[in]  idom        Domain index for storing the linearization
    !!  @param[in]  ielem       Element index for which the linearization was computed
    !!  @param[in]  iblk        Index of the block for the linearization of the given elemen
    !!  @param[in]  ivar        Index of the variable, for which the linearization was computed
    !!
    !-----------------------------------------------------------------------------------------------------------
    subroutine store(self, integral, idom, ielem, iblk, ivar)
        class(chidgMatrix_t),   intent(inout)   :: self
        type(AD_D),             intent(in)      :: integral(:)
        integer(ik),            intent(in)      :: idom, ielem, iblk, ivar

        !
        ! Store linearization in associated domain blockmatrix_t
        !
        call self%dom(idom)%store(integral,ielem,iblk,ivar)

    end subroutine store
    !***********************************************************************************************************









    !> Procedure for stiring linearization information for Chimera faces
    !!
    !!  @author Nathan A. Wukie
    !!  @date   2/1/2016
    !!
    !!
    !!  @param[in]  integral    Array of modes from the spatial scheme, with embedded partial derivatives for the linearization matrix
    !!  @param[in]  face        face_info_t containing the indices defining the Chimera face
    !!  @param[in]  seed        seed_t containing the indices defining the element against which the Chimera face was linearized
    !!  @param[in]  ivar        Index of the variable, for which the linearization was computed
    !!
    !-----------------------------------------------------------------------------------------------------------
    subroutine store_chimera(self,integral,face,seed,ivar)
        class(chidgMatrix_t),       intent(inout)   :: self
        type(AD_D),                 intent(in)      :: integral(:)
        type(face_info_t),          intent(in)      :: face
        type(seed_t),               intent(in)      :: seed
        integer(ik),                intent(in)      :: ivar 

        integer(ik) :: idomain_l

        idomain_l = face%idomain_l

        !
        ! Store linearization in associated domain blockmatrix_t
        !
        call self%dom(idomain_l)%store_chimera(integral,face,seed,ivar)

    end subroutine store_chimera
    !***********************************************************************************************************









    !> Procedure for stiring linearization information for boundary condition faces
    !!
    !!  @author Nathan A. Wukie
    !!  @date   2/1/2016
    !!
    !!
    !!  @param[in]  integral    Array of modes from the spatial scheme, with embedded partial derivatives for the linearization matrix
    !!  @param[in]  face        face_info_t containing the indices defining the Chimera face
    !!  @param[in]  seed        seed_t containing the indices defining the element against which the Chimera face was linearized
    !!  @param[in]  ivar        Index of the variable, for which the linearization was computed
    !!
    !-----------------------------------------------------------------------------------------------------------
    subroutine store_bc(self,integral,face,seed,ivar)
        class(chidgMatrix_t),       intent(inout)   :: self
        type(AD_D),                 intent(in)      :: integral(:)
        type(face_info_t),          intent(in)      :: face
        type(seed_t),               intent(in)      :: seed
        integer(ik),                intent(in)      :: ivar 

        integer(ik) :: idomain_l

        idomain_l = face%idomain_l

        !
        ! Store linearization in associated domain blockmatrix_t
        !
        call self%dom(idomain_l)%store_bc(integral,face,seed,ivar)

    end subroutine store_bc
    !***********************************************************************************************************


















    !> Set all ChiDGMatrix matrix-values to zero
    !!
    !!  @author Nathan A. Wukie
    !!  @date   2/1/2016
    !! 
    !! 
    !----------------------------------------------------------------------------------------------------------
    subroutine clear(self)
        class(chidgMatrix_t),   intent(inout)   :: self

        integer(ik) :: idom
    

        !
        ! Call blockmatrix_t%clear() on all matrices
        !
        do idom = 1,size(self%dom)
           call self%dom(idom)%clear() 
        end do
    
    
    end subroutine clear
    !***********************************************************************************************************











    !> ChiDGMatrix destructor.
    !!
    !!  @author Nathan A. Wukie
    !!  @date   2/1/2016
    !!
    !!
    !-----------------------------------------------------------------------------------------------------------
    subroutine destructor(self)
        type(chidgMatrix_t),    intent(inout)   :: self

    end subroutine
    !***********************************************************************************************************



end module type_chidgMatrix
