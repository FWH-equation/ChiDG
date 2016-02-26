module type_element
#include <messenger.h>
    use mod_kinds,              only: rk,ik
    use mod_constants,          only: SPACEDIM,NFACES,XI_MIN,XI_MAX,ETA_MIN, &
                                      ETA_MAX,ZETA_MIN,ZETA_MAX,ONE,ZERO
    use type_point,             only: point_t
    use type_densevector,       only: densevector_t
    use type_quadrature,        only: quadrature_t
    use DNAD_D
    use mod_quadrature,         only: GQ, get_quadrature
    use mod_grid,               only: ELEM_MAP
    use mod_polynomial,         only: polynomialVal, dpolynomialVal
    use mod_grid_tools,         only: compute_modal_coordinates
    use mod_inv,                only: inv
    implicit none


    !> Element data type
    !!
    !!  NOTE: could be dangerous to declare static arrays of elements using gfortran because
    !!        the compiler doens't have complete finalization rules implemented. Useing allocatables
    !!        seems to work fine.
    !!
    !!  @author Nathan A. Wukie
    !!  @date   2/1/2016
    !!
    !------------------------------------------------------------------------------------------------------------
    type, public :: element_t
        integer(ik)      :: neqns                           !< Number of equations being solved
        integer(ik)      :: nterms_s                        !< Number of terms in solution expansion.  
        integer(ik)      :: nterms_c                        !< Number of terms in coordinate expansion. 
        integer(ik)      :: idomain                         !< Processor-local domain index
        integer(ik)      :: ielem                           !< Block-local element index. Consider the block could have been split
                                                            !< for parallelization.

        integer(ik)      :: ielem_bg                        !< Block-global element index. The index an element would have if
                                                            !< rejoined into one block after being split for parallelization.

        ! Element quadrature points, mesh points and modes
        !---------------------------------------------------------
        type(point_t), allocatable  :: quad_pts(:)          !< Cartesian coordinates of discrete quadrature points
        type(point_t), allocatable  :: elem_pts(:)          !< Cartesian coordinates of discrete points defining element
        type(densevector_t)         :: coords               !< Modal representation of cartesian coordinates (nterms_var,(x,y,z))

        ! Element metric terms
        !---------------------------------------------------------
        real(rk), allocatable       :: metric(:,:,:)        !< metric matrix for each quadrature node    (mat_i,mat_j,quad_pt)
        real(rk), allocatable       :: jinv(:)              !< jacobian terms at quadrature nodes

        ! Matrices of cartesian gradients of basis/test functions
        !---------------------------------------------------------
        real(rk), allocatable       :: dtdx(:,:)            !< Derivative of basis functions in x-direction at quadrature nodes
        real(rk), allocatable       :: dtdy(:,:)            !< Derivative of basis functions in y-direction at quadrature nodes
        real(rk), allocatable       :: dtdz(:,:)            !< Derivative of basis functions in z-direction at quadrature nodes

        ! Quadrature matrices
        !---------------------------------------------------------
        type(quadrature_t), pointer  :: gq     => null()    !< Pointer to quadrature instance for solution expansion
        type(quadrature_t), pointer  :: gqmesh => null()    !< Pointer to quadrature instance for coordinate expansion

        ! Element-local mass matrices
        !---------------------------------------------------------
        real(rk), allocatable   :: mass(:,:)
        real(rk), allocatable   :: invmass(:,:)

        ! Element volume
        real(rk)                :: vol

        ! Logical tests
        logical :: geomInitialized = .false.
        logical :: numInitialized  = .false.


    contains

        ! Initialization procedures
        procedure, public   :: init_geom
        procedure, public   :: init_sol


        ! Public utility procedures
        procedure, public   :: x
        procedure, public   :: y
        procedure, public   :: z
        procedure, public   :: compute_metric


        ! Private utility procedure
        procedure           :: compute_element_matrices
        procedure           :: compute_mass_matrix
        procedure           :: compute_gradients_cartesian
        procedure           :: compute_quadrature_metrics
        procedure           :: compute_quadrature_coords
        procedure           :: assign_quadrature

        final               :: destructor

    end type element_t
    !****************************************************************************************************************

    private




contains
    





    !>  Initialize element geometry
    !!      - Set element points
    !!      - Compute modal representation of element cartesian coordinates
    !!      - Compute element metric terms
    !!
    !!  @author Nathan A. Wukie
    !!  @date   2/1/2016
    !!
    !!  @param[in] nterms_c     Number of terms in the modal representation of the cartesian coordinates
    !!  @param[in] points       Array of cartesian points defining the element
    !!
    !---------------------------------------------------------------------------------------
    subroutine init_geom(self,mapping,points,idomain,ielem)
        class(element_t),   intent(inout) :: self
        integer(ik),        intent(in)    :: mapping
        type(point_t),      intent(in)    :: points(:)
        integer(ik),        intent(in)    :: idomain
        integer(ik),        intent(in)    :: ielem

        integer(ik)                         :: ierr, nterms_c
        real(rk), dimension(:,:), pointer   :: imap => null()

        if (self%geomInitialized) call chidg_signal(FATAL,'element%init_geom -- element already initialized')



        !
        ! Check if the element mappings are initialized. If so, then get a pointer to the correct mapping 
        ! and set number of coordinate expansion terms
        !
        if (allocated(elem_map(mapping)%mat)) then
            imap            => elem_map(mapping)%mat
            nterms_c        = size(elem_map(mapping)%mat,1) ! Get nterms of coordinate expansion from size of mapping matrix
            self%nterms_c   = nterms_c                      ! Set number of terms in coordinate expansion


            if (nterms_c /= size(points)) call chidg_signal(FATAL,'element%init_geom -- mapping and points do not match')
        else
            call chidg_signal(FATAL,"element%init_geom -- element mapping not initialized. Probably need to call 'init' on chidg environment")
        end if



        !
        ! Allocate storage
        !
        allocate(self%elem_pts(nterms_c),stat=ierr)
        call self%coords%init(nterms_c,SPACEDIM,ielem)
        self%idomain  = idomain
        self%ielem    = ielem
        self%elem_pts = points

        
        !
        ! Compute mesh x,y,z modes
        !
        call compute_modal_coordinates(self%elem_pts,mapping,self%coords)


        !
        ! Confirm element geometry was initialized
        !
        self%geomInitialized = .true.   

    end subroutine init_geom
    !***********************************************************************************************************









    !>  Initialize element numerics
    !!      - Allocate storage for solution and supporting matrices
    !!      - Compute element-local matrices (cartesian gradients, mass matrices)
    !!
    !!  @author Nathan A. Wukie
    !!  @date   2/1/2016
    !!
    !!  @param[in]  nterms_s    Number of terms in the modal representation of the solution
    !!  @param[in]  neqns       Number of equations contained in the element solution
    !!
    !-----------------------------------------------------------------------------------------------------------
    subroutine init_sol(self,neqns,nterms_s)
        class(element_t),   intent(inout) :: self
        integer(ik),        intent(in)    :: neqns
        integer(ik),        intent(in)    :: nterms_s

        integer(ik) :: ierr
        integer(ik) :: nnodes,nnodes_face,nnodes_vol

        if (self%numInitialized) call chidg_signal(FATAL,'element%init_sol -- element already initialized')


        self%nterms_s    = nterms_s                 ! Set number of terms in modal expansion of solution
        self%neqns       = neqns                    ! Set number of equations being solved

        call self%assign_quadrature()               ! With nterms_s and nterms_c defined, we can assign a quadrature instance
        nnodes           = self%gq%vol%nnodes       ! With a quadrature instance assigned, we have the number of quadrature nodes


        !
        ! Allocate storage for element data structures
        !
        allocate(self%jinv(nnodes),                         &
                 self%metric(SPACEDIM,SPACEDIM,nnodes),     &
                 self%quad_pts(nnodes),                     &
                 self%dtdx(nnodes,nterms_s),                &
                 self%dtdy(nnodes,nterms_s),                &
                 self%dtdz(nnodes,nterms_s),                &
                 self%mass(nterms_s,nterms_s),              &
                 self%invmass(nterms_s,nterms_s), stat = ierr)
        if (ierr /= 0) call AllocationError


        !
        ! Call element metric and matrix calculation routines
        !
        call self%compute_quadrature_metrics()                  ! Compute element metrics
        call self%compute_element_matrices()                    ! Compute mass matrices and derivative matrices



        !
        ! Confirm element numerics were initialized
        !
        self%numInitialized = .true.    

    end subroutine init_sol
    !*************************************************************************************************************







    !>  Assign quadrature instances for solution modes (GQ) and mesh modes (GQMESH)
    !!
    !!  @author Nathan A. Wukie
    !!  @date   2/1/2016
    !!
    !!
    !-------------------------------------------------------------------------------------------------------------
    subroutine assign_quadrature(self)
        use mod_quadrature,     only: compute_nnodes_gq
        class(element_t),   intent(inout)   :: self

        integer(ik) :: nterms_s,nterms_c
        integer(ik) :: nnodes_face, nnodes_vol, igq, igq_s, igq_f
        logical     :: has_correct_nodes_terms

        nterms_s = self%nterms_s
        nterms_c = self%nterms_c

        if (nterms_c == 0) call chidg_signal(FATAL,'element%assign_quadrature -- coordinate expansion not defined')

        !
        ! Get number of quadrature nodes
        !
        call compute_nnodes_gq(nterms_s,nterms_c,nnodes_face,nnodes_vol)


        !
        ! Get solution quadrature instance
        !
        call get_quadrature(nterms_s,nnodes_vol,nnodes_face,igq_s)
        self%gq => GQ(igq_s)


        !
        ! Get coordinate quadrature instance
        !
        call get_quadrature(nterms_c,nnodes_vol,nnodes_face,igq_f)
        self%gqmesh => GQ(igq_f)


    end subroutine assign_quadrature
    !**************************************************************************************************************











    !> Compute element metric and jacobian terms
    !!
    !!  @author Nathan A. Wukie
    !!  @date   2/1/2016
    !!
    !!
    !--------------------------------------------------------------------------------------------------------------
    subroutine compute_quadrature_metrics(self)
        class(element_t),    intent(inout)   :: self

        integer(ik)             :: inode
        integer(ik)             :: nnodes

        real(rk)    :: dxdxi(self%gq%vol%nnodes), dxdeta(self%gq%vol%nnodes), dxdzeta(self%gq%vol%nnodes)
        real(rk)    :: dydxi(self%gq%vol%nnodes), dydeta(self%gq%vol%nnodes), dydzeta(self%gq%vol%nnodes)
        real(rk)    :: dzdxi(self%gq%vol%nnodes), dzdeta(self%gq%vol%nnodes), dzdzeta(self%gq%vol%nnodes)


        nnodes = self%gq%vol%nnodes

        !
        ! Compute element metric terms
        !
        dxdxi   = matmul(self%gqmesh%vol%ddxi,  self%coords%getvar(1))
        dxdeta  = matmul(self%gqmesh%vol%ddeta, self%coords%getvar(1))
        dxdzeta = matmul(self%gqmesh%vol%ddzeta,self%coords%getvar(1))

        dydxi   = matmul(self%gqmesh%vol%ddxi,  self%coords%getvar(2))
        dydeta  = matmul(self%gqmesh%vol%ddeta, self%coords%getvar(2))
        dydzeta = matmul(self%gqmesh%vol%ddzeta,self%coords%getvar(2))

        dzdxi   = matmul(self%gqmesh%vol%ddxi,  self%coords%getvar(3))
        dzdeta  = matmul(self%gqmesh%vol%ddeta, self%coords%getvar(3))
        dzdzeta = matmul(self%gqmesh%vol%ddzeta,self%coords%getvar(3))


        !
        ! Loop through quadrature nodes and compute metric terms
        !
        do inode = 1,nnodes
            self%metric(1,1,inode) = dydeta(inode)*dzdzeta(inode) - dydzeta(inode)*dzdeta(inode)
            self%metric(2,1,inode) = dydzeta(inode)*dzdxi(inode)  - dydxi(inode)*dzdzeta(inode)
            self%metric(3,1,inode) = dydxi(inode)*dzdeta(inode)   - dydeta(inode)*dzdxi(inode)

            self%metric(1,2,inode) = dxdzeta(inode)*dzdeta(inode) - dxdeta(inode)*dzdzeta(inode)
            self%metric(2,2,inode) = dxdxi(inode)*dzdzeta(inode)  - dxdzeta(inode)*dzdxi(inode)
            self%metric(3,2,inode) = dxdeta(inode)*dzdxi(inode)   - dxdxi(inode)*dzdeta(inode)

            self%metric(1,3,inode) = dxdeta(inode)*dydzeta(inode) - dxdzeta(inode)*dydeta(inode)
            self%metric(2,3,inode) = dxdzeta(inode)*dydxi(inode)  - dxdxi(inode)*dydzeta(inode)
            self%metric(3,3,inode) = dxdxi(inode)*dydeta(inode)   - dxdeta(inode)*dydxi(inode)
        end do


        !
        ! Compute inverse cell mapping jacobian
        !
        self%jinv = dxdxi*dydeta*dzdzeta - dxdeta*dydxi*dzdzeta - &
                    dxdxi*dydzeta*dzdeta + dxdzeta*dydxi*dzdeta + &
                    dxdeta*dydzeta*dzdxi - dxdzeta*dydeta*dzdxi


        !
        ! Compute element volume
        !
        self%vol = abs(sum(self%jinv * self%gq%vol%weights))

    end subroutine compute_quadrature_metrics
    !********************************************************************************************************











    !>  Subroutine computes element-specific matrices
    !!      - Mass matrix   (mass, invmass)
    !!      - Matrices of cartesian gradients of basis/test functions (dtdx, dtdy, dtdz)
    !!      - Cartesian coordinates of quadrature points (quad_pts)
    !!
    !!  @author Nathan A. Wukie
    !!  @date   2/1/2016
    !!
    !--------------------------------------------------------------------------------------------------------
    subroutine compute_element_matrices(self)
        class(element_t),   intent(inout)   :: self

        !
        ! Call to compute matrices of cartesian gradients at each quadrature node
        !
        call self%compute_gradients_cartesian()

        !
        ! Call to compute mass matrix
        !
        call self%compute_mass_matrix()

        !
        ! Call to compute cartesian coordinates at each quadrature node
        !
        call self%compute_quadrature_coords()

    end subroutine compute_element_matrices
    !********************************************************************************************************











    !>  Compute matrices containing cartesian gradients of basis/test function
    !!  at each quadrature node.
    !!
    !!  @author Nathan A. Wukie
    !!  @date   2/1/2016
    !!
    !!
    !--------------------------------------------------------------------------------------------------------
    subroutine compute_gradients_cartesian(self)
        class(element_t),   intent(inout)   :: self
        integer(ik)                         :: iterm,inode

        do iterm = 1,self%nterms_s
            do inode = 1,self%gq%vol%nnodes
                self%dtdx(inode,iterm) = self%metric(1,1,inode) * self%gq%vol%ddxi(inode,iterm)   * (ONE/self%jinv(inode)) + &
                                         self%metric(2,1,inode) * self%gq%vol%ddeta(inode,iterm)  * (ONE/self%jinv(inode)) + &
                                         self%metric(3,1,inode) * self%gq%vol%ddzeta(inode,iterm) * (ONE/self%jinv(inode))

                self%dtdy(inode,iterm) = self%metric(1,2,inode) * self%gq%vol%ddxi(inode,iterm)   * (ONE/self%jinv(inode)) + &
                                         self%metric(2,2,inode) * self%gq%vol%ddeta(inode,iterm)  * (ONE/self%jinv(inode)) + &
                                         self%metric(3,2,inode) * self%gq%vol%ddzeta(inode,iterm) * (ONE/self%jinv(inode))

                self%dtdz(inode,iterm) = self%metric(1,3,inode) * self%gq%vol%ddxi(inode,iterm)   * (ONE/self%jinv(inode)) + &
                                         self%metric(2,3,inode) * self%gq%vol%ddeta(inode,iterm)  * (ONE/self%jinv(inode)) + &
                                         self%metric(3,3,inode) * self%gq%vol%ddzeta(inode,iterm) * (ONE/self%jinv(inode))
            end do
        end do

    end subroutine compute_gradients_cartesian
    !*********************************************************************************************************











    !>  Compute cartesian coordinates at each quadrature point
    !!
    !!  @author Nathan A. Wukie
    !!  @date   2/1/2016
    !!
    !!
    !!
    !!
    !---------------------------------------------------------------------------------------------------------------
    subroutine compute_quadrature_coords(self)
        class(element_t),   intent(inout)   :: self
        integer(ik)                         :: nnodes
        real(rk)                            :: x(self%gq%vol%nnodes),y(self%gq%vol%nnodes),z(self%gq%vol%nnodes)
        integer(ik)                         :: inode

        nnodes = self%gq%vol%nnodes

        !
        ! compute cartesian coordinates associated with quadrature points
        !
        x = matmul(self%gqmesh%vol%val,self%coords%getvar(1))
        y = matmul(self%gqmesh%vol%val,self%coords%getvar(2))
        z = matmul(self%gqmesh%vol%val,self%coords%getvar(3))


        !
        ! Initialize each point with cartesian coordinates
        !
        do inode = 1,nnodes
            call self%quad_pts(inode)%set(x(inode),y(inode),z(inode))
        end do

    end subroutine compute_quadrature_coords
    !**************************************************************************************************************













    !>  Compute element-local mass matrix
    !!
    !!  @author Nathan A. Wukie
    !!  @date   2/1/2016
    !!
    !!
    !-------------------------------------------------------------------------------------------------------------
    subroutine compute_mass_matrix(self)
        class(element_t), intent(inout) :: self
        integer(ik)  :: iterm,i,j
        real(rk)     :: temp(self%nterms_s,self%gq%vol%nnodes)

        self%invmass = 0._rk
        self%mass = 0._rk
        temp = transpose(self%gq%vol%val)

        !
        ! Multiply rows by quadrature weights and cell jacobians
        !
        do iterm = 1,self%nterms_s
            temp(iterm,:) = temp(iterm,:)*(self%gq%vol%weights)*(self%jinv)
        end do


        !
        ! Perform the matrix multiplication of the transpose val matrix by
        ! the standard matrix. This produces the mass matrix. I think...
        !
        self%mass = matmul(temp,self%gq%vol%val)


        !
        ! Compute and store the inverted mass matrix
        !
        self%invmass = inv(self%mass)

    end subroutine compute_mass_matrix
    !**************************************************************************************************************
















    !> Convert local(xi,eta,zeta) coordinates to global coordinates(x,y,z)
    !!
    !!  @author Nathan A. Wukie
    !!  @date   2/1/2016
    !!
    !!
    !!
    !--------------------------------------------------------------------------------------------------------------
    function x(self,xi,eta,zeta) result(xval)
        class(element_t),   intent(in)  :: self
        real(rk),      intent(in)  :: xi,eta,zeta
        real(rk)                   :: xval

        type(point_t)              :: node
        real(rk)                   :: polyvals(self%nterms_c)
        integer(ik)                :: iterm

        call node%set(xi,eta,zeta)

        !
        ! Evaluate polynomial modes at node location
        !
        do iterm = 1,self%nterms_c
            polyvals(iterm)  = polynomialVal(3,self%nterms_c,iterm,node)
        end do

        
        !
        ! Evaluate x from dot product of modes and polynomial values
        !
        xval = dot_product(self%coords%getvar(1),polyvals)

    end function x
    !***************************************************************************************************************







    !> Convert local(xi,eta,zeta) coordinates to global coordinates(x,y,z)
    !!
    !!  @author Nathan A. Wukie
    !!  @date   2/1/2016
    !!
    !!
    !!
    !--------------------------------------------------------------------------------------------------------------
    function y(self,xi,eta,zeta) result(yval)
        class(element_t),   intent(in)  :: self
        real(rk),           intent(in)  :: xi,eta,zeta
        real(rk)                        :: yval

        type(point_t)              :: node
        real(rk)                   :: polyvals(self%nterms_c)
        integer(ik)                :: iterm

        call node%set(xi,eta,zeta)

        !
        ! Evaluate polynomial modes at node location
        !
        do iterm = 1,self%nterms_c
            polyvals(iterm)  = polynomialVal(3,self%nterms_c,iterm,node)
        end do


        !
        ! Evaluate x from dot product of modes and polynomial values
        !
        yval = dot_product(self%coords%getvar(2),polyvals)

    end function y
    !***************************************************************************************************************






    !> Convert local(xi,eta,zeta) coordinates to global coordinates(x,y,z)
    !!
    !!  @author Nathan A. Wukie
    !!  @date   2/1/2016
    !!
    !!
    !!
    !--------------------------------------------------------------------------------------------------------------
    function z(self,xi,eta,zeta) result(zval)
        class(element_t),   intent(in)  :: self
        real(rk),           intent(in)  :: xi,eta,zeta
        real(rk)                        :: zval

        type(point_t)              :: node
        real(rk)                   :: polyvals(self%nterms_c)
        integer(ik)                :: iterm

        call node%set(xi,eta,zeta)

        !
        ! Evaluate polynomial modes at node location
        !
        do iterm = 1,self%nterms_c
            polyvals(iterm)  = polynomialVal(3,self%nterms_c,iterm,node)
        end do


        !
        ! Evaluate x from dot product of modes and polynomial values
        !
        zval = dot_product(self%coords%getvar(3),polyvals)

    end function z
    !***************************************************************************************************************








    !> Compute coordinate metric term at a given point in computational space
    !!
    !!  @author Nathan A. Wukie
    !!  @date   2/1/2016
    !!
    !!  @param[in]  elem        element_t containing the geometry definition and data
    !!  @param[in]  cart_dir    Cartesian coordinate being differentiated
    !!  @param[in]  comp_dir    Computational coordinate being differentiated with respect to
    !!  @param[in]  xi          Computational coordinate - xi
    !!  @param[in]  eta         Computational coordinate - eta
    !!  @param[in]  zeta        Computational coordinate - zeta
    !!
    !----------------------------------------------------------------------------------------------------------------
    function compute_metric(self,cart_dir,comp_dir,xi,eta,zeta) result(val)
        class(element_t),   intent(in)  :: self
        integer(ik),        intent(in)  :: cart_dir
        integer(ik),        intent(in)  :: comp_dir
        real(rk),           intent(in)  :: xi, eta, zeta
        
        real(rk)        :: val
        type(point_t)   :: node
        real(rk)        :: polyvals(self%nterms_c)
        integer(ik)     :: iterm, ielem


        if (cart_dir > 3) call chidg_signal(FATAL,"Error: mesh_point -- card_dir exceeded 3 physical coordinates")
        if (comp_dir > 3) call chidg_signal(FATAL,"Error: mesh_point -- comp_dir exceeded 3 physical coordinates")

        call node%set(xi,eta,zeta)


        !
        ! Evaluate polynomial modes at node location
        !
        do iterm = 1,self%nterms_c

            polyvals(iterm) = dpolynomialVal(3,self%nterms_c,iterm,node,comp_dir)

        end do


        !
        ! Evaluate mesh point from dot product of modes and polynomial values
        !
        val = dot_product(self%coords%getvar(cart_dir), polyvals)



    end function compute_metric
    !****************************************************************************************************************
























    subroutine destructor(self)
        type(element_t), intent(inout) :: self


    end subroutine

end module type_element
