!> This module contains procedures for initializing and maintaining the Chimera
!! interfaces.
!!
!!  @author Nathan A. Wukie
!!  @date   2/1/2016
!!
!!
!---------------------------------------------------------------
module mod_chimera
#include <messenger.h>
    use mod_kinds,              only: rk, ik
    use mod_constants,          only: NFACES, ORPHAN, CHIMERA, &
                                      X_DIR,  Y_DIR,   Z_DIR, &
                                      XI_DIR, ETA_DIR, ZETA_DIR, &
                                      ONE, ZERO, TWO_DIM, THREE_DIM, RKTOL

    use type_mesh,              only: mesh_t
    use type_point,             only: point_t
    use type_element_indices,   only: element_indices_t
    use type_face_info,         only: face_info_t
    use type_ivector,           only: ivector_t
    use type_rvector,           only: rvector_t
    use type_pvector,           only: pvector_t

    use mod_polynomial,         only: polynomialVal
!    use mod_grid_operators,     only: mesh_point, metric_point
    use mod_periodic,           only: compute_periodic_offset
    use mod_inv,                only: inv
    implicit none









contains


    !> Routine for detecting Chimera faces. 
    !!
    !! Routine flags face as a Chimera face if it has an ftype==ORPHAN, indicating it is not an interior
    !! face and it has not been assigned a boundary condition.
    !!
    !!  @author Nathan A. Wukie
    !!  @date   2/1/2016
    !!
    !!  @param[inout]   mesh    Array of mesh types. One for each domain.
    !!
    !-----------------------------------------------------------------------------------------------------------------------
    subroutine detect_chimera_faces(mesh)
        type(mesh_t),   intent(inout)   :: mesh(:)

        integer(ik) :: idom, ndom, ielem, iface, ierr, nchimera_faces, ChiID
        logical     :: orphan_face = .false.
        logical     :: chimera_face = .false.

        !
        ! Get number of domains
        !
        ndom = size(mesh)

        
        !
        ! Loop through each element of each domain and look for ORPHAN face-types.
        ! If orphan is found, designate as CHIMERA and increment nchimera_faces
        !
        do idom = 1,ndom
            nchimera_faces = 0

            do ielem = 1,mesh(idom)%nelem


                !
                ! Loop through each face
                !
                do iface = 1,NFACES

                    !
                    ! Test if the current face is unattached
                    !
                    orphan_face = ( mesh(idom)%faces(ielem,iface)%ftype == ORPHAN ) 


                    !
                    ! If orphan_face, set as Chimera face so it can search for donors in other domains
                    !
                    if (orphan_face) then
                        ! Increment domain-local chimera face count
                        nchimera_faces = nchimera_faces + 1

                        ! Set face-type to CHIMERA
                        mesh(idom)%faces(ielem,iface)%ftype = CHIMERA

                        ! Set domain-local Chimera identifier. Really, just the index order which they were detected in, starting from 1.
                        ! The n-th chimera face
                        mesh(idom)%faces(ielem,iface)%ChiID = nchimera_faces
                    end if


                end do ! iface

            end do ! ielem



            !
            ! Set total number of Chimera faces detected for domain - idom
            !
            mesh(idom)%chimera%recv%nfaces = nchimera_faces


            !
            ! Allocate chimera_receiver_data for each chimera face in the current domain
            !
            allocate(mesh(idom)%chimera%recv%data(nchimera_faces), stat=ierr)
            if (ierr /= 0) call AllocationError


        end do ! idom






        !
        ! Now that all CHIMERA faces have been identified and we know the total number,
        ! we can store their data in the mesh-local chimera data container.
        !
        do idom = 1,ndom
            do ielem = 1,mesh(idom)%nelem


                !
                ! Loop through each face of current element
                !
                do iface = 1,NFACES

                    chimera_face = ( mesh(idom)%faces(ielem,iface)%ftype == CHIMERA )
                    if ( chimera_face ) then

                        !
                        ! Set receiver information for Chimera face
                        !
                        ChiID = mesh(idom)%faces(ielem,iface)%ChiID
                        mesh(idom)%chimera%recv%data(ChiID)%receiver_domain  = idom
                        mesh(idom)%chimera%recv%data(ChiID)%receiver_element = ielem
                        mesh(idom)%chimera%recv%data(ChiID)%receiver_face    = iface
                    end if

                end do ! iface


            end do ! ielem
        end do ! idom



    end subroutine detect_chimera_faces
    !*********************************************************************************************************************















    !> Routine for generating the data in a chimera_receiver_data instance. This includes donor_domain
    !! and donor_element indices.
    !!
    !!  @author Nathan A. Wukie
    !!  @date   2/1/2016
    !!
    !!  @parma[in]  mesh    Array of mesh_t instances
    !!
    !---------------------------------------------------------------------------------------------------------------------
    subroutine detect_chimera_donors(mesh)
        type(mesh_t),   intent(inout)   :: mesh(:)

        integer(ik) :: idom, igq, ichimera_face, idonor, ierr
        integer(ik) :: ndonors, neqns, nterms_s
        integer(ik) :: idonor_domain, idonor_element
        integer(ik) :: idomain_list, ielement_list

        real(rk)    :: offset_x, offset_y, offset_z

        type(face_info_t)       :: receiver
        type(element_indices_t)    :: donor
        type(point_t)              :: donor_coord
        type(point_t)              :: gq_node
        type(point_t)              :: dummy_coord
        logical                    :: new_donor     = .false.
        logical                    :: already_added = .false.
        logical                    :: donor_match   = .false.

        type(ivector_t)            :: ddomain, delement
        type(pvector_t)            :: dcoordinate

        !
        ! Loop over domains
        !
        do idom = 1,size(mesh)

            call write_line('Detecting chimera donors for domain: ', idom, delimiter='  ')


            !
            ! Loop over faces and process Chimera-type faces
            !
            do ichimera_face = 1,mesh(idom)%chimera%recv%nfaces

                !
                ! Get location of the face receiving Chimera data
                !
                receiver%idomain  = idom
                receiver%ielement = mesh(idom)%chimera%recv%data(ichimera_face)%receiver_element
                receiver%iface    = mesh(idom)%chimera%recv%data(ichimera_face)%receiver_face

                call write_line('   Face ', ichimera_face,' of ',mesh(idom)%chimera%recv%nfaces, delimiter='  ')

                !
                ! Loop through quadrature nodes on Chimera face and find donors
                !
                do igq = 1,mesh(receiver%idomain)%faces(receiver%ielement,receiver%iface)%gq%face%nnodes

                    !
                    ! Get node coordinates
                    !
                    gq_node = mesh(receiver%idomain)%faces(receiver%ielement,receiver%iface)%quad_pts(igq)


                    !
                    ! Get offset coordinates from face for potential periodic offset.
                    !
                    !offset_x = mesh(receiver%idomain)%faces(receiver%ielement,receiver%iface)%chimera_offset_x
                    !offset_y = mesh(receiver%idomain)%faces(receiver%ielement,receiver%iface)%chimera_offset_y
                    !offset_z = mesh(receiver%idomain)%faces(receiver%ielement,receiver%iface)%chimera_offset_z
                    
                    call compute_periodic_offset(mesh(receiver%idomain)%faces(receiver%ielement,receiver%iface), gq_node, offset_x, offset_y, offset_z)

                    call gq_node%add_x(offset_x)
                    call gq_node%add_y(offset_y)
                    call gq_node%add_z(offset_z)


                    !
                    ! Call routine to find gq donor for current node
                    !
                    call compute_gq_donor(mesh,gq_node, receiver, donor, donor_coord)


                    !
                    ! Add donor location and coordinate
                    !
                    call ddomain%push_back(donor%idomain)
                    call delement%push_back(donor%ielement)
                    call dcoordinate%push_back(donor_coord)


                end do ! igq




                !
                ! Count number of unique donors to the current face and 
                ! add to chimera donor data 
                !
                ndonors = 0
                do igq = 1,ddomain%size()

                    idomain_list  = ddomain%at(igq)
                    ielement_list = delement%at(igq)


                    !
                    ! Check if domain/element pair has already been added to the chimera donor data
                    !
                    already_added = .false.
                    do idonor = 1,mesh(idom)%chimera%recv%data(ichimera_face)%donor_domain%size()

                        idonor_domain  = mesh(idom)%chimera%recv%data(ichimera_face)%donor_domain%at(idonor)
                        idonor_element = mesh(idom)%chimera%recv%data(ichimera_face)%donor_element%at(idonor)

                        already_added = ( (idomain_list == idonor_domain) .and. (ielement_list == idonor_element) )
                        if (already_added) exit
                    end do
                    
                    !
                    ! If the current domain/element pair was not found in the chimera donor data, then add it
                    !
                    if (.not. already_added) then
                        neqns    = mesh(idomain_list)%elems(ielement_list)%neqns
                        nterms_s = mesh(idomain_list)%elems(ielement_list)%nterms_s

                        call mesh(idom)%chimera%recv%data(ichimera_face)%donor_neqns%push_back(neqns)
                        call mesh(idom)%chimera%recv%data(ichimera_face)%donor_nterms_s%push_back(nterms_s)
                        call mesh(idom)%chimera%recv%data(ichimera_face)%donor_domain%push_back(idomain_list)
                        call mesh(idom)%chimera%recv%data(ichimera_face)%donor_element%push_back(ielement_list)
                        ndonors = ndonors + 1
                    end if

                end do ! igq



                !
                ! Allocate chimera donor coordinate and quadrature index arrays. One list for each donor
                !
                mesh(idom)%chimera%recv%data(ichimera_face)%ndonors = ndonors
                allocate( mesh(idom)%chimera%recv%data(ichimera_face)%donor_coords(ndonors), &
                          mesh(idom)%chimera%recv%data(ichimera_face)%donor_gq_indices(ndonors), stat=ierr)
                if (ierr /= 0) call AllocationError





                !
                ! Now save donor coordinates and gq indices to their appropriate donor list
                !
                do igq = 1,ddomain%size()


                    idomain_list  = ddomain%at(igq)
                    ielement_list = delement%at(igq)


                    !
                    ! Check if domain/element pair has already been added to the chimera donor data
                    !
                    donor_match = .false.
                    do idonor = 1,mesh(idom)%chimera%recv%data(ichimera_face)%donor_domain%size()

                        idonor_domain  = mesh(idom)%chimera%recv%data(ichimera_face)%donor_domain%at(idonor)
                        idonor_element = mesh(idom)%chimera%recv%data(ichimera_face)%donor_element%at(idonor)

                        donor_match = ( (idomain_list == idonor_domain) .and. (ielement_list == idonor_element) )


                        if (donor_match) then
                            call mesh(idom)%chimera%recv%data(ichimera_face)%donor_gq_indices(idonor)%push_back(igq)
                            call mesh(idom)%chimera%recv%data(ichimera_face)%donor_coords(idonor)%push_back(dcoordinate%at(igq))
                            exit
                        end if
                    end do
                    
                end do







                !
                ! Clear temporary face arrays
                !
                call ddomain%clear()
                call delement%clear()
                call dcoordinate%clear()


            end do ! iface

        end do ! idom



    end subroutine detect_chimera_donors
    !***********************************************************************************************************************









    !> compute the donor domain and element for a given quadrature node.
    !!
    !!  @author Nathan A. Wukie
    !!  @date   2/1/2016
    !!
    !!  @param[in]      mesh            Array of mesh_t instances
    !!  @param[in]      gq_node         GQ point that needs to find a donor
    !!  @param[in]      receiver_face   Location of face containing the gq_node
    !!  @param[inout]   donor_element   Location of the donor element that was found
    !!  @param[inout]   donor_coord     Point defining the location of the GQ point in the donor coordinate system
    !!
    !-----------------------------------------------------------------------------------------------------------------------
    subroutine compute_gq_donor(mesh,gq_node,receiver_face,donor_element,donor_coordinate)
        type(mesh_t),               intent(in)      :: mesh(:)
        type(point_t),              intent(in)      :: gq_node
        type(face_info_t),          intent(in)      :: receiver_face
        type(element_indices_t),    intent(inout)   :: donor_element
        type(point_t),              intent(inout)   :: donor_coordinate


        integer(ik)             :: idom, ielem, inewton, spacedim
        integer(ik)             :: icandidate, ncandidates, idonor, ndonors
        real(rk)                :: xgq, ygq, zgq
        real(rk)                :: xi,  eta, zeta
        real(rk)                :: xn,  yn,  zn
        real(rk)                :: xmin, xmax, ymin, ymax, zmin, zmax
        real(rk)                :: tol
        type(ivector_t)         :: candidate_domains
        type(ivector_t)         :: candidate_elements
        type(ivector_t)         :: donors
        type(rvector_t)         :: donors_xi, donors_eta, donors_zeta
        logical                 :: contained = .false.
        logical                 :: receiver  = .false.
        logical                 :: donor_found = .false.

        real(rk)    :: mat(3,3), minv(3,3)
        real(rk)    :: R(3)
        real(rk)    :: dcoord(3)
        real(rk)    :: res, dx, dy, dz


        tol = 10._rk*RKTOL


        xgq = gq_node%c1_
        ygq = gq_node%c2_
        zgq = gq_node%c3_



        !
        ! Loop through domains and search for potential donor candidates
        !
        ncandidates = 0
        do idom = 1,size(mesh)


            !
            ! Loop through elements in the current domain
            !
            do ielem = 1,mesh(idom)%nelem


                !
                ! Get bounding coordinates for the current element
                !
                xmin = minval(mesh(idom)%elems(ielem)%elem_pts(:)%c1_)
                xmax = maxval(mesh(idom)%elems(ielem)%elem_pts(:)%c1_)

                ymin = minval(mesh(idom)%elems(ielem)%elem_pts(:)%c2_)
                ymax = maxval(mesh(idom)%elems(ielem)%elem_pts(:)%c2_)

                zmin = minval(mesh(idom)%elems(ielem)%elem_pts(:)%c3_)
                zmax = maxval(mesh(idom)%elems(ielem)%elem_pts(:)%c3_)


                !
                ! Grow bounding box by 10%. Use delta x,y,z instead of scaling xmin etc. in case xmin is 0
                !
                dx = abs(xmax - xmin)  
                dy = abs(ymax - ymin)
                dz = abs(zmax - zmin)


                xmin = xmin - 0.1*dx
                xmax = xmax + 0.1*dx
                ymin = ymin - 0.1*dy
                ymax = ymax + 0.1*dy
                zmin = (zmin-0.001) - 0.1*dz    ! This is to help 2D
                zmax = (zmax+0.001) + 0.1*dz    ! This is to help 2D

                !
                ! Test if gq_node is contained within the bounding coordinates
                !
                contained = ( (xmin < xgq) .and. (xgq < xmax ) .and. &
                              (ymin < ygq) .and. (ygq < ymax ) .and. &
                              (zmin < zgq) .and. (zgq < zmax ) )



                !
                ! Make sure that we arent adding the receiver itself as a potential donor
                !
                receiver = ( (idom == receiver_face%idomain) .and. (ielem == receiver_face%ielement) )


                !
                ! If the node was within the bounding coordinates, flag the element as a potential donor
                !
                if (contained .and. (.not. receiver)) then
                   call candidate_domains%push_back(idom) 
                   call candidate_elements%push_back(ielem)
                   ncandidates = ncandidates + 1
                end if


            end do ! ielem

        end do ! idom









        !
        ! Test gq_node on candidate element volume using Newton's method to map to donor local coordinates
        !
        ndonors = 0
        donor_found = .false.
        do icandidate = 1,ncandidates

            idom  = candidate_domains%at(icandidate)
            ielem = candidate_elements%at(icandidate)
            spacedim = mesh(idom)%spacedim


            !
            ! Newton iteration to find the donor local coordinates
            !
            xi   = 0._rk
            eta  = 0._rk
            zeta = 0._rk
            do inewton = 1,20

                !
                ! Compute local cartesian coordinates as a function of xi,eta,zeta
                !
                xn = mesh(idom)%elems(ielem)%x(xi,eta,zeta)
                yn = mesh(idom)%elems(ielem)%y(xi,eta,zeta)
                zn = mesh(idom)%elems(ielem)%z(xi,eta,zeta)



                !
                ! Assemble residual vector
                !
                R(1) = -(xn - xgq)
                R(2) = -(yn - ygq)
                R(3) = -(zn - zgq)



                !
                ! Assemble coordinate jacobian matrix
                !
                mat(1,1) = mesh(idom)%elems(ielem)%metric_point(X_DIR,XI_DIR,  xi,eta,zeta)
                mat(2,1) = mesh(idom)%elems(ielem)%metric_point(Y_DIR,XI_DIR,  xi,eta,zeta)
                mat(3,1) = mesh(idom)%elems(ielem)%metric_point(Z_DIR,XI_DIR,  xi,eta,zeta)
                mat(1,2) = mesh(idom)%elems(ielem)%metric_point(X_DIR,ETA_DIR, xi,eta,zeta)
                mat(2,2) = mesh(idom)%elems(ielem)%metric_point(Y_DIR,ETA_DIR, xi,eta,zeta)
                mat(3,2) = mesh(idom)%elems(ielem)%metric_point(Z_DIR,ETA_DIR, xi,eta,zeta)
                mat(1,3) = mesh(idom)%elems(ielem)%metric_point(X_DIR,ZETA_DIR,xi,eta,zeta)
                mat(2,3) = mesh(idom)%elems(ielem)%metric_point(Y_DIR,ZETA_DIR,xi,eta,zeta)
                mat(3,3) = mesh(idom)%elems(ielem)%metric_point(Z_DIR,ZETA_DIR,xi,eta,zeta)


                !
                ! Invert jacobian matrix
                !
                minv = inv(mat)


                !
                ! Compute coordinate update
                !
                dcoord = matmul(minv,R)


                !
                ! Update coordinates
                !
                xi   = xi   + dcoord(1)
                eta  = eta  + dcoord(2)
                zeta = zeta + dcoord(3)


                !
                ! Compute residual coordinate norm
                !
                res = norm2(R)


                !
                ! Exit if converged
                !
                if ( res < tol ) then
                    ndonors = ndonors + 1
                    call donors%push_back(icandidate)
                    call donors_xi%push_back(xi)
                    call donors_eta%push_back(eta)
                    call donors_zeta%push_back(zeta)
                    donor_found = .true.
                    exit
                end if


                !
                ! Limit computational coordinates, in case they go out of bounds.
                !
                if ( xi   >  ONE ) xi   =  ONE
                if ( xi   < -ONE ) xi   = -ONE
                if ( eta  >  ONE ) eta  =  ONE
                if ( eta  < -ONE ) eta  = -ONE
                if ( zeta >  ONE ) zeta =  ONE
                if ( zeta < -ONE ) zeta = -ONE

            end do ! inewton

            if (donor_found) then
                exit
            end if

        end do ! icandidate




        !
        ! Sanity check on donors and set donor_element location
        !
        if (ndonors == 0) then
            call chidg_signal_three(FATAL,"compute_gq_donor: No donor found for gq_node", gq_node%c1_, gq_node%c2_, gq_node%c3_)

        elseif (ndonors > 1) then
            !TODO: Account for case of multiple overlapping donors. When a gq node could be filled by two or more elements.
            !      Maybe, just choose one. Maybe, average contribution from all potential donors.
            !
            call chidg_signal(FATAL,"compute_gq_donor: Multiple donors found for the same gq_node")

        elseif (ndonors == 1) then
            idonor = donors%at(1)   ! donor index from candidates
            
            donor_element%idomain  = candidate_domains%at(idonor)
            donor_element%ielement = candidate_elements%at(idonor)


            xi   = donors_xi%at(1)
            eta  = donors_eta%at(1)
            zeta = donors_zeta%at(1)
            call donor_coordinate%set(xi,eta,zeta)


        else
            call chidg_signal(FATAL,"compute_gq_donor: invalid number of donors")
        end if




    end subroutine compute_gq_donor
    !****************************************************************************************************************















    !> Compute the matrices that interpolate solution data from a donor element expansion
    !! to the receiver nodes.
    !!
    !! These matrices get stored in mesh(idom)%chimera%recv%data(ChiID)%donor_interpolator
    !!
    !!  @author Nathan A. Wukie
    !!  @date   2/1/2016
    !!
    !-----------------------------------------------------------------------------------------------------------------
    subroutine compute_chimera_interpolators(mesh)
        type(mesh_t),   intent(inout)   :: mesh(:)

        integer(ik) :: idom, iChiID, idonor, idom_d, ielem_d, ierr, ipt, iterm
        integer(ik) :: npts, nterms_s, nterms, spacedim

        type(point_t)           :: node
        real(rk), allocatable   :: interpolator(:,:)



        !
        ! Loop over all domains
        !
        do idom = 1,size(mesh)

            spacedim = mesh(idom)%spacedim

            !
            ! Loop over each chimera face
            !
            do iChiID = 1,mesh(idom)%chimera%recv%nfaces

                
                !
                ! For each donor, compute an interpolation matrix
                !
                do idonor = 1,mesh(idom)%chimera%recv%data(iChiID)%ndonors

                    idom_d  = mesh(idom)%chimera%recv%data(iChiID)%donor_domain%at(idonor)
                    ielem_d = mesh(idom)%chimera%recv%data(iChiID)%donor_element%at(idonor)

                    !
                    ! Get number of GQ points this donor is responsible for
                    !
                    npts = mesh(idom)%chimera%recv%data(iChiID)%donor_coords(idonor)%size()
                    nterms = mesh(idom_d)%elems(ielem_d)%nterms_s

                    
                    !
                    ! Allocate interpolator matrix
                    !
                    if (allocated(interpolator)) deallocate(interpolator)
                    allocate(interpolator(npts,nterms), stat=ierr)
                    if (ierr /= 0) call AllocationError



                    !
                    ! Compute values of modal polynomials at the donor nodes
                    !
                    do iterm = 1,nterms
                        do ipt = 1,npts

                            node = mesh(idom)%chimera%recv%data(iChiID)%donor_coords(idonor)%at(ipt)
                            interpolator(ipt,iterm) = polynomialVal(spacedim,nterms,iterm,node)

                        end do ! ipt
                    end do ! iterm


                    !
                    ! Store interpolator
                    !
                    call mesh(idom)%chimera%recv%data(iChiID)%donor_interpolator%push_back(interpolator)


                end do  ! idonor



            end do  ! iChiID
        end do  ! idom


    end subroutine compute_chimera_interpolators
    !******************************************************************************************************************








end module mod_chimera
