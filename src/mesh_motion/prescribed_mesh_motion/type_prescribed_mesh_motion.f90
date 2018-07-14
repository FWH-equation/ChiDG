module type_prescribed_mesh_motion
#include <messenger.h>
    use mod_constants
    use mod_kinds,                              only: rk, ik
    use mod_prescribed_mesh_motion_function,    only: create_prescribed_mesh_motion_function
    use type_prescribed_mesh_motion_function,   only: prescribed_mesh_motion_function_t
    use type_chidg_worker,                      only: chidg_worker_t
    use type_domain,                              only: domain_t
    implicit none


    !>  Mesh motion class. Abstract interface to enable treatment of prescribed mesh motion.
    !!
    !!  Data flow:
    !!  gridfile :-- readprescribedmeshmotion_hdf --> pmm_group, pmm_domain_data ...
    !!  :-- init_pmm_group, init_pmm_domain --> pmm(:), mesh
    !!
    !!  @author Eric Wolf
    !!  @date   3/16/2017
    !!
    !---------------------------------------------------------------------------------------------------------------
    type, public :: prescribed_mesh_motion_t
        
        ! Prescribed mesh motions are stored as a vector of prescribed_mesh_motion_t's
        ! chidg%data%mesh%pmm(1:npmm)

        !pmm_ID is the unique ID for this pmm, so that it can be accessed via
        ! chidg%data%mesh%pmm(pmm_ID)

        integer(ik)                 :: pmm_ID
        real(rk)                    :: time = 0.0_rk
        character(:), allocatable   :: pmm_name

        ! pmmf_name is the name of the prescribed_mesh_motion_function_t associated with this pmm
        character(:), allocatable   :: pmmf_name

        ! pmm_function is the prescribed_mesh_motion_function_t associated with this pmm
        ! This is what really specifies the grid positions and velocities.
        class(prescribed_mesh_motion_function_t), allocatable                     :: pmmf

    contains
        ! Standard set/get procedures for pmm_name
        procedure   :: set_name
        procedure   :: get_name

        !These procedures read in the intermediate pmm  data structures
        !created when reading in the grid file, which are
        ! pmm_group, which contains a pmm instance that is used as an
        ! allocation source for the present pmm, and 
        ! pmm_domain_data, which contains a domain name and a pmm_ID, 
        ! which is used to store the pmm_ID of the mesh in the appropriate domain
        procedure   :: init_pmm_group 
        procedure   :: init_pmm_domain


        ! These procedures are used to initialize the pmmf associated with this pmm.

        !Set the name 
        procedure       :: set_pmmf_name
        ! Instantiate the pmmf and assign it to the pmm
        procedure       :: add_pmmf


        !These procedures compute the values of the grid positions and velocities
        ! from the pmmf associated with the pmm,
        ! then call element and face procedures to compute grid Jacobians.
!        procedure    :: update_element => pmm_update_element 
!        procedure    :: update_face => pmm_update_face
               

    end type prescribed_mesh_motion_t
    
contains



    !>
    !!  @author Eric Wolf
    !!  @date 4/7/2017
    !--------------------------------------------------------------------------------
    subroutine set_name(self,pmm_name)
        class(prescribed_mesh_motion_t),    intent(inout)   :: self
        character(*),                       intent(in)      :: pmm_name                        

        self%pmm_name = pmm_name

    end subroutine set_name
    !********************************************************************************

    !>
    !!  @author Eric Wolf
    !!  @date 4/7/2017
    !--------------------------------------------------------------------------------
    function get_name(self) result(pmm_name)
        class(prescribed_mesh_motion_t), intent(inout)  :: self

        character(len=:), allocatable   :: pmm_name

        pmm_name =  self%pmm_name

    end function get_name
    !********************************************************************************



    !>
    !!  This subroutine takes a an input pmm (from a pmm_group, which is generated by reading in the
    !!  grid file and initializing a pmm instance according to a PMM group),
    !!  and uses this pmm instance as an allocation source for the present pmm.
    !!
    !!  @author Eric Wolf
    !!  @date 4/7/2017
    !--------------------------------------------------------------------------------
    subroutine init_pmm_group(self,pmm_in)
        class(prescribed_mesh_motion_t),    intent(inout)   :: self
        class(prescribed_mesh_motion_t),    intent(inout)   :: pmm_in

        integer(ik)     :: ierr

        call self%set_name(pmm_in%get_name())
        self%pmmf_name = pmm_in%pmmf_name
        if (allocated(self%pmmf)) deallocate(self%pmmf)
        allocate(self%pmmf, source = pmm_in%pmmf, stat=ierr)
        if (ierr /= 0) call AllocationError

    end subroutine init_pmm_group
    !********************************************************************************

    
    !>
    !!  This subroutine takes in a mesh (domain) that was selected from a
    !!  pmm_domain_data_t, whch is generated by reading in the grid file,
    !!  and sets the pmm_ID for all elements and faces in the mesh (domain)
    !!  to be equal to the present pmm_ID.
    !!
    !!  Called from chidg%data%add_pmm_domain(..)
    !!
    !!  @author Eric Wolf
    !!  @date 4/7/2017
    !--------------------------------------------------------------------------------
    subroutine init_pmm_domain(self,domain)
        class(prescribed_mesh_motion_t),               intent(inout)       :: self
        type(domain_t),                                       intent(inout)           ::domain 


        integer(ik)     :: ielem, nelem, iface
        
        ! Loop through the elements and faces in the mesh and assign the pmm_ID


        domain%pmm_ID = self%pmm_ID
        nelem = domain%nelem
        do ielem = 1, nelem
            !Check if a PMM has already been assigned
            !if (mesh%elems(ielem)%pmm_ID /= NO_PMM_ASSIGNED)  then
            !   bad bad bad
            !else
            domain%elems(ielem)%pmm_ID = self%pmm_ID
            do iface = 1, NFACES
                domain%faces(ielem, iface)%pmm_ID = self%pmm_ID
            end do
            !end if
        end do

    end subroutine init_pmm_domain
    !********************************************************************************

    
    !>
    !!
    !!
    !!  @author Eric Wolf
    !!  @date 4/7/2017
    !--------------------------------------------------------------------------------
    subroutine set_pmmf_name(self, pmmfstring)
        class(prescribed_mesh_motion_t),        intent(inout)   :: self
        character(*),                           intent(in)      :: pmmfstring

        self%pmmf_name = pmmfstring

    end subroutine
    !********************************************************************************


    !>
    !!  Called from get_pmm_hdf
    !! 
    !!  @author Eric Wolf
    !!  @date 4/7/2017
    !--------------------------------------------------------------------------------
    subroutine add_pmmf(self, pmmfstring)
        class(prescribed_mesh_motion_t),        intent(inout)   :: self
        character(*),                           intent(in)      :: pmmfstring
        class(prescribed_mesh_motion_function_t), allocatable                :: pmmf
            
        integer(ik)     :: ierr
        call self%set_pmmf_name(pmmfstring)
        call create_prescribed_mesh_motion_function(pmmf, pmmfstring)
        if (allocated(self%pmmf)) deallocate(self%pmmf)
        allocate(self%pmmf, source = pmmf, stat=ierr)
        if (ierr /= 0) call AllocationError

    end subroutine
    !********************************************************************************




!    !>
!    !!  @author Eric Wolf
!    !!  @date 4/7/2017
!    !--------------------------------------------------------------------------------
!    subroutine pmm_update_element(self, worker)
!        class(prescribed_mesh_motion_t),        intent(inout)   :: self
!        type(chidg_worker_t),                   intent(inout)      :: worker
!
!        integer(ik)             :: inode
!        !type(point_t)   :: ref_pos, grid_pos, grid_vel
!        real(rk), dimension(3)  :: ref_pos, grid_pos, grid_vel
!        
!        !Use the pmm_function to compute the values of the position and velocity at elem_pts
!        do inode = 1, worker%mesh%domain(worker%element_info%idomain_l)%elems(worker%element_info%ielement_l)%nterms_c
!
!            ref_pos = worker%mesh%domain(worker%element_info%idomain_l)%elems(worker%element_info%ielement_l)%elem_pts(inode,1:3)
!
!           ! grid_pos = self%pmmf%compute_pos(ref_pos, self%time)
!           ! grid_vel = self%pmmf%compute_vel(ref_pos, self%time)
!            
!
!!            worker%mesh(worker%element_info%idomain_l)%elems(worker%element_info%ielement_l)%ale_elem_pts(inode) = grid_pos
!!            worker%mesh(worker%element_info%idomain_l)%elems(worker%element_info%ielement_l)%ale_vel_elem_pts(inode) = grid_vel
!!
!        end do
!
!        !Use the element_t procedures to recompute coordinate expansion, quadrature node values, and grid metrics
!        call worker%mesh%domain(worker%element_info%idomain_l)%elems(worker%element_info%ielement_l)%update_element_ale()
!
!    end subroutine pmm_update_element
!    !********************************************************************************
!
!
!    !>
!    !!  @author Eric Wolf
!    !!  @date 4/7/2017
!    !--------------------------------------------------------------------------------
!    subroutine pmm_update_face(self, worker)
!        class(prescribed_mesh_motion_t),        intent(inout)   :: self
!        type(chidg_worker_t),                   intent(in)      :: worker
!
!        call worker%mesh%domain(worker%element_info%idomain_l)%faces(worker%element_info%ielement_l, worker%iface)%update_face_ale(&
!            worker%mesh%domain(worker%element_info%idomain_l)%elems(worker%element_info%ielement_l))
!
!
!    end subroutine pmm_update_face
!    !********************************************************************************
!


end module type_prescribed_mesh_motion
