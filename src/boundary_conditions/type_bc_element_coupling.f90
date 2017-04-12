module type_bc_element_coupling
#include <messenger.h>
    use mod_kinds,                  only: rk, ik
    use type_element_coupling_data, only: element_coupling_data_t
    implicit none




    !>
    !!
    !!  @author Nathan A. Wukie
    !!  @date   4/12/2017
    !!
    !!
    !--------------------------------------------------------------------
    type, public :: bc_element_coupling_t

        type(element_coupling_data_t),  allocatable :: data(:)

    contains

        procedure   :: add_coupled_element
        procedure   :: new_coupled_element
        procedure   :: set_coupled_element_recv
        procedure   :: ncoupled_elements

        procedure   :: idomain_g
        procedure   :: idomain_l
        procedure   :: ielement_g
        procedure   :: ielement_l
        procedure   :: proc

    end type bc_element_coupling_t
    !********************************************************************



contains




    !>  Add a coupled element.
    !!
    !!  @author Nathan A. Wukie
    !!  @date   4/12/2017
    !!
    !!
    !---------------------------------------------------------------------
    subroutine add_coupled_element(self,idomain_g, idomain_l, ielement_g, ielement_l, proc)
        class(bc_element_coupling_t),   intent(inout)   :: self
        integer(ik),                    intent(in)      :: idomain_g
        integer(ik),                    intent(in)      :: idomain_l
        integer(ik),                    intent(in)      :: ielement_g
        integer(ik),                    intent(in)      :: ielement_l
        integer(ik),                    intent(in)      :: proc

        logical     :: already_added
        integer(ik) :: ielem_coupled, idomain_g_coupled, ielement_g_coupled, elem_ID


        !
        ! Check if element has already been added to coupling list
        ! for the specified face
        !
        already_added = .false.
        do ielem_coupled = 1,self%ncoupled_elements()

            idomain_g_coupled  = self%data(ielem_coupled)%idomain_g
            ielement_g_coupled = self%data(ielem_coupled)%ielement_g

            already_added = (idomain_g_coupled  == idomain_g ) .and. &
                            (ielement_g_coupled == ielement_g)
            if (already_added) exit

        end do




        !
        ! If not already added, create new coupling 
        ! instance, set coupling indices.
        !
        if (.not. already_added) then

            elem_ID = self%new_coupled_element()
            call self%data(elem_ID)%set_coupling(idomain_g,idomain_l,ielement_g,ielement_l,proc)

        end if


    end subroutine add_coupled_element
    !*********************************************************************





    !>  Extend the data array containint element coupling. Returns
    !!  an identifier for the new instance.
    !!
    !!  @author Nathan A. Wukie
    !!  @date   4/12/2017
    !!
    !!
    !----------------------------------------------------------------------
    function new_coupled_element(self) result(elem_ID)
        class(bc_element_coupling_t),   intent(inout)   :: self

        type(element_coupling_data_t),  allocatable :: temp_data(:)
        integer(ik)                                 :: elem_ID, ierr

        
        !
        ! Resize array storage
        !
        allocate(temp_data(self%ncoupled_elements() + 1), stat=ierr)
        if (ierr /= 0) call AllocationError


        !
        ! Copy preciously initialized instances to new array. 
        !
        if (self%ncoupled_elements() > 0) then
            temp_data(1:size(self%data)) = self%data(1:size(self%data))
        end if



        !
        ! Move resized temp allocation back to bc_element_coupling%data.
        !
        call move_alloc(temp_data,self%data)


        !
        ! Set coupling identifier of newly allocated instance to be returned.
        !
        elem_ID = self%ncoupled_elements()


    end function new_coupled_element
    !**********************************************************************




    !>  Set parallel access indices.
    !!
    !!  These indices allow access to solution data in chidg_vector that
    !!  was received from other processors.
    !!
    !!  @author Nathan A. Wukie
    !!  @date   4/12/2017
    !!
    !!
    !----------------------------------------------------------------------
    subroutine set_coupled_element_recv(self,idomain_g,ielement_g,recv_comm,recv_domain,recv_element)
        class(bc_element_coupling_t),   intent(inout)   :: self
        integer(ik),                    intent(in)      :: idomain_g
        integer(ik),                    intent(in)      :: ielement_g
        integer(ik),                    intent(in)      :: recv_comm
        integer(ik),                    intent(in)      :: recv_domain
        integer(ik),                    intent(in)      :: recv_element

        character(:),   allocatable :: user_msg
        integer(ik)                 :: icoupled, elem_ID
        logical                     :: element_found



        !
        ! Find the index associated with the element (idomain_g,ielement_g)
        !
        do icoupled = 1,self%ncoupled_elements()

            element_found = (idomain_g  == self%idomain_g(icoupled)  ) .and. &
                            (ielement_g == self%ielement_g(icoupled) )
            if (element_found) elem_ID = icoupled
            if (element_found) exit

        end do !icoupled

        user_msg = "bc_patch%set_coupled_element_recv: did not find element coupling."
        if (.not. element_found) call chidg_signal(FATAL,user_msg)


        call self%data(elem_ID)%set_recv(recv_comm,recv_domain,recv_element)

    end subroutine set_coupled_element_recv
    !**********************************************************************








    !>  Return the number of coupled element are stored.
    !!
    !!  @author Nathan A. Wukie
    !!  @date   4/12/2017
    !!
    !!
    !----------------------------------------------------------------------
    function ncoupled_elements(self) result(n)
        class(bc_element_coupling_t),    intent(in) :: self

        integer(ik) :: n

        if (allocated(self%data)) then
            n = size(self%data)
        else
            n = 0
        end if

    end function ncoupled_elements
    !**********************************************************************







    !>  Return the identifier idomain_g
    !!
    !!  @author Nathan A. Wukie
    !!  @date   4/12/2017
    !!
    !-----------------------------------------------------------------------
    function idomain_g(self,elem_ID) result(idomain_g_)
        class(bc_element_coupling_t),   intent(in)  :: self
        integer(ik),                    intent(in)  :: elem_ID

        integer(ik) :: idomain_g_

        idomain_g_ = self%data(elem_ID)%idomain_g

    end function idomain_g
    !************************************************************************






    !>  Return the identifier idomain_l
    !!
    !!  @author Nathan A. Wukie
    !!  @date   4/12/2017
    !!
    !-----------------------------------------------------------------------
    function idomain_l(self,elem_ID) result(idomain_l_)
        class(bc_element_coupling_t),   intent(in)  :: self
        integer(ik),                    intent(in)  :: elem_ID

        integer(ik) :: idomain_l_

        idomain_l_ = self%data(elem_ID)%idomain_l

    end function idomain_l
    !************************************************************************







    !>  Return the identifier ielement_g
    !!
    !!  @author Nathan A. Wukie
    !!  @date   4/12/2017
    !!
    !-----------------------------------------------------------------------
    function ielement_g(self,elem_ID) result(ielement_g_)
        class(bc_element_coupling_t),   intent(in)  :: self
        integer(ik),                    intent(in)  :: elem_ID

        integer(ik) :: ielement_g_

        ielement_g_ = self%data(elem_ID)%ielement_g

    end function ielement_g
    !************************************************************************






    !>  Return the identifier ielement_l
    !!
    !!  @author Nathan A. Wukie
    !!  @date   4/12/2017
    !!
    !-----------------------------------------------------------------------
    function ielement_l(self,elem_ID) result(ielement_l_)
        class(bc_element_coupling_t),   intent(in)  :: self
        integer(ik),                    intent(in)  :: elem_ID

        integer(ik) :: ielement_l_

        ielement_l_ = self%data(elem_ID)%ielement_l

    end function ielement_l
    !************************************************************************




    !>  Return the identifier proc
    !!
    !!  @author Nathan A. Wukie
    !!  @date   4/12/2017
    !!
    !-----------------------------------------------------------------------
    function proc(self,elem_ID) result(proc_)
        class(bc_element_coupling_t),   intent(in)  :: self
        integer(ik),                    intent(in)  :: elem_ID

        integer(ik) :: proc_

        proc_ = self%data(elem_ID)%proc

    end function proc
    !************************************************************************

    






end module type_bc_element_coupling
