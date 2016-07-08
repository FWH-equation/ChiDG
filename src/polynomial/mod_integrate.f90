module mod_integrate
#include <messenger.h>
    use mod_kinds,              only: rk,ik
    use mod_constants,          only: XI_MIN, XI_MAX, ETA_MIN, ETA_MAX, ZETA_MIN, ZETA_MAX, DIAG, CHIMERA, &
                                      NO_INTERIOR_NEIGHBOR, BOUNDARY, INTERIOR, ZERO
    use mod_chidg_mpi,          only: IRANK

    use type_mesh,              only: mesh_t
    use type_element,           only: element_t
    use type_face,              only: face_t
    use type_face_info,         only: face_info_t
    use type_function_info,     only: function_info_t
    use type_solverdata,        only: solverdata_t
    use type_blockmatrix,       only: blockmatrix_t
    use type_seed,              only: seed_t

    use DNAD_D
    implicit none



contains



    !>  Compute the volume integral of a flux vector
    !!
    !!      - Adds value contribution to the rhs vector
    !!      - Adds the derivative contribution to the linearization matrix
    !!
    !!  @author Nathan A. Wukie
    !!  @param[in]      elem    Element being integrated over
    !!  @param[inout]   rhs     Right-hand side vector storage
    !!  @param[inout]   lin     Domain linearization matrix
    !!  @param[in]      iblk    Selected block of the linearization being computed. lin(ielem,iblk), where iblk = (1-7)
    !!  @param[in]      ieqn    Index of the variable associated with the flux being integrated
    !!  @param[inout]   flux_x  x-Flux and derivatives at quadrature points
    !!  @param[inout]   flux_y  y-Flux and derivatives at quadrature points
    !!  @param[inout]   flux_z  z-Flux and derivatives at quadrature points
    !!
    !--------------------------------------------------------------------------------------------------------
    subroutine integrate_volume_flux(elem,sdata,idom,ieqn,iblk,flux_x,flux_y,flux_z)
        type(element_t),        intent(in)      :: elem
        type(solverdata_t),     intent(inout)   :: sdata
        integer(ik),            intent(in)      :: idom
        integer(ik),            intent(in)      :: ieqn
        integer(ik),            intent(in)      :: iblk
        type(AD_D),             intent(inout)   :: flux_x(:), flux_y(:), flux_z(:)


        integer(ik)                             :: ielem, i
        type(AD_D), dimension(elem%nterms_s)    :: integral, integral_x, integral_y, integral_z

        ielem = elem%ielement_l  ! get element index




        !
        ! Multiply each component by quadrature weights and element jacobians
        !
        flux_x = (flux_x) * (elem%gq%vol%weights) * (elem%jinv)
        flux_y = (flux_y) * (elem%gq%vol%weights) * (elem%jinv)
        flux_z = (flux_z) * (elem%gq%vol%weights) * (elem%jinv)





!       Add r for cylindrical coordinate system integral
!        flux_x = (flux_x) * (elem%gq%vol%weights) * (elem%jinv) * (elem%quad_pts(:)%c2_)
!        flux_y = (flux_y) * (elem%gq%vol%weights) * (elem%jinv) * (elem%quad_pts(:)%c2_)
!        flux_z = (flux_z) * (elem%gq%vol%weights) * (elem%jinv) * (elem%quad_pts(:)%c2_)


        !
        ! FLUX-X
        ! Multiply by column of test function gradients, integrate, add to RHS, add derivatives to linearization
        !
        integral_x = matmul(transpose(elem%dtdx),flux_x)                            ! Integrate





        !
        ! FLUX-Y
        ! Multiply by column of test function gradients, integrate, add to RHS, add derivatives to linearization
        !
        integral_y = matmul(transpose(elem%dtdy),flux_y)                            ! Integrate



        !
        ! FLUX-Z
        ! Multiply by column of test function gradients, integrate, add to RHS, add derivatives to linearization
        !
        integral_z = matmul(transpose(elem%dtdz),flux_z)                            ! Integrate



        integral = integral_x + integral_y + integral_z

        

        call store_volume_integrals(integral,sdata,idom,ielem,ieqn,iblk)            ! Store values and derivatives


    end subroutine integrate_volume_flux
    !*********************************************************************************************************












    !>  Compute the volume integral of a flux vector
    !!
    !!      - Adds value contribution to the rhs vector
    !!      - Adds the derivative contribution to the linearization matrix
    !!
    !!  @author Nathan A. Wukie
    !!  @param[in]      elem    Element being integrated over
    !!  @param[inout]   rhs     Right-hand side vector storage
    !!  @param[inout]   lin     Domain linearization matrix
    !!  @param[in]      iblk    Selected block of the linearization being computed. lin(ielem,iblk), where iblk = (1-7)
    !!  @param[in]      ieqn    Index of the variable associated with the flux being integrated
    !!  @param[inout]   flux_x  x-Flux and derivatives at quadrature points
    !!  @param[inout]   flux_y  y-Flux and derivatives at quadrature points
    !!  @param[inout]   flux_z  z-Flux and derivatives at quadrature points
    !!
    !--------------------------------------------------------------------------------------------------------
    subroutine integrate_volume_source(elem,sdata,idom,ieqn,iblk,source)
        type(element_t),        intent(in)      :: elem
        type(solverdata_t),     intent(inout)   :: sdata
        integer(ik),            intent(in)      :: idom
        integer(ik),            intent(in)      :: ieqn
        integer(ik),            intent(in)      :: iblk
        type(AD_D),             intent(inout)   :: source(:)


        integer(ik)                             :: ielem, i
        type(AD_D), dimension(elem%nterms_s)    :: integral, integral_x, integral_y, integral_z

        ielem = elem%ielement_l  ! get element index

        !
        ! Multiply each component by quadrature weights and element jacobians
        !
        source = (source) * (elem%gq%vol%weights) * (elem%jinv)
!       Add r for cylindrical coordinate system integral
!        source = (source) * (elem%gq%vol%weights) * (elem%jinv) * (elem%quad_pts(:)%c2_)



        !
        ! Multiply by column of test function gradients, integrate, add to RHS, add derivatives to linearization
        !
        integral = matmul(transpose(elem%gq%vol%val),source)                        ! Integrate




        call store_volume_integrals(integral,sdata,idom,ielem,ieqn,iblk)            ! Store values and derivatives


    end subroutine integrate_volume_source
    !********************************************************************************************************













    !>  Compute the boundary integral of a flux scalar
    !!
    !!      - Adds value contribution to the rhs vector
    !!      - Adds the derivative contribution to the linearization matrix
    !!
    !!  @author Nathan A. Wukie
    !!  @param[in]      face    Face being integrated over
    !!  @param[inout]   rhs     Right-hand side vector storage
    !!  @param[inout]   lin     Domain linearization matrix
    !!  @param[in]      iblk    Selected block of the linearization being computed. lin(ielem,iblk), where iblk = (1-7)
    !!  @param[in]      ieqn    Index of the variable associated with the flux being integrated
    !!  @param[inout]   flux_x  x-Flux and derivatives at quadrature points
    !!  @param[inout]   flux_y  y-Flux and derivatives at quadrature points
    !!  @param[inout]   flux_z  z-Flux and derivatives at quadrature points
    !!
    !--------------------------------------------------------------------------------------------------------
    subroutine integrate_boundary_scalar_flux(mesh,sdata,face_info,function_info,ieqn,integrand)
        type(mesh_t),           intent(in)      :: mesh(:)
        type(solverdata_t),     intent(inout)   :: sdata
        type(face_info_t),      intent(in)      :: face_info
        type(function_info_t),  intent(in)      :: function_info
        integer(ik),            intent(in)      :: ieqn
        type(AD_D),             intent(inout)   :: integrand(:)
        
        ! Data for applying to neighbor
        type(AD_D),             allocatable     :: integrand_n(:)
        type(face_info_t)                       :: face_n
        type(function_info_t)                   :: function_n
        integer(ik)                             :: ineighbor_element_l, ineighbor_face, ineighbor_proc, iblk_n
        logical                                 :: parallel_neighbor

        integer(ik)                             :: nterms_s, ierr, ftype
        type(AD_D), allocatable                 :: integral(:)


        associate ( idomain_l   => face_info%idomain_l,     &
                    ielement_l  => face_info%ielement_l,    &
                    iface       => face_info%iface,         &
                    ifcn        => function_info%ifcn,      &
                    idonor      => function_info%idonor,    &
                    iblk        => function_info%iblk )


        ftype    = mesh(idomain_l)%faces(ielement_l,iface)%ftype
        nterms_s = mesh(idomain_l)%faces(ielement_l,iface)%nterms_s



        ! Neighbor indices
        ineighbor_proc      = mesh(idomain_l)%faces(ielement_l,iface)%ineighbor_proc
        ineighbor_element_l = mesh(idomain_l)%faces(ielement_l,iface)%get_neighbor_element_l()
        ineighbor_face      = mesh(idomain_l)%faces(ielement_l,iface)%get_neighbor_face()

        parallel_neighbor = ( IRANK /= ineighbor_proc )

        !
        ! Store quadrature flux for neighbor integral
        !
!       Add r for cylindrical coordinate system integral
!        integrand = integrand * mesh(idom)%faces(ielem,iface)%quad_pts(:)%c2_

        integrand_n = integrand



        !
        ! Allocate integral array. MIGHT NOT NEED THIS. TEST.
        !
        allocate(integral(nterms_s), stat=ierr)
        if (ierr /= 0) call AllocationError




        !
        ! Integrate and apply once
        !
        associate ( weights => mesh(idomain_l)%faces(ielement_l,iface)%gq%face%weights(:,iface), &
                    jinv => mesh(idomain_l)%faces(ielement_l,iface)%jinv, &
                    val => mesh(idomain_l)%faces(ielement_l,iface)%gq%face%val(:,:,iface) )


            !
            ! Multiply each component by quadrature weights. The fluxes have already been multiplied by norm
            !
            integrand = (integrand) * (weights)
            integral = matmul(transpose(val),integrand)


            call store_boundary_integral_residual(     mesh,sdata,face_info,function_info,ieqn,integral)
            call store_boundary_integral_linearization(mesh,sdata,face_info,function_info,ieqn,integral)


        end associate





        !
        ! Integrate and apply second time if there is a neighbor
        !
        if ( ineighbor_element_l /= NO_INTERIOR_NEIGHBOR ) then
            if ( .not. parallel_neighbor ) then

                face_n%idomain_g  = mesh(idomain_l)%faces(ielement_l,iface)%ineighbor_domain_g
                face_n%idomain_l  = mesh(idomain_l)%faces(ielement_l,iface)%ineighbor_domain_l
                face_n%ielement_g = mesh(idomain_l)%faces(ielement_l,iface)%ineighbor_element_g
                face_n%ielement_l = mesh(idomain_l)%faces(ielement_l,iface)%ineighbor_element_l
                face_n%iface      = mesh(idomain_l)%faces(ielement_l,iface)%get_neighbor_face()
                face_n%seed       = face_info%seed


                !
                ! Get linearization block for the neighbor element
                !
                if ( iblk /= DIAG ) then
                        iblk_n = DIAG
                else if ( iblk == DIAG ) then
                        iblk_n = ineighbor_face
                else
                    call chidg_signal(FATAL,"store_boundary_integrals: unexpected value")
                end if


                function_n%type   = function_info%type
                function_n%ifcn   = function_info%ifcn
                function_n%idonor = function_info%idonor
                function_n%iblk   = iblk_n
                


                associate ( weights_n => mesh(idomain_l)%faces(ineighbor_element_l,ineighbor_face)%gq%face%weights(:,ineighbor_face),   &
                            jinv_n    => mesh(idomain_l)%faces(ineighbor_element_l,ineighbor_face)%jinv,                                & 
                            val_n     => mesh(idomain_l)%faces(ineighbor_element_l,ineighbor_face)%gq%face%val(:,:,ineighbor_face) )

                    integrand_n = (integrand_n) * (weights_n)

                    !
                    ! Integrate and negate for contribution to neighbor element
                    !
                    integral = -matmul(transpose(val_n),integrand_n)

                    call store_boundary_integral_residual(     mesh,sdata,face_n,function_n,ieqn,integral)
                    call store_boundary_integral_linearization(mesh,sdata,face_n,function_n,ieqn,integral)

                end associate

            end if ! .not. parallel_neighbor
        end if ! ielem_n


        end associate

    end subroutine integrate_boundary_scalar_flux
    !********************************************************************************************************



















    !> Store volume integral values to RHS vector, and partial derivatives to LIN block matrix
    !!
    !!  @author Nathan A. Wukie
    !!
    !!
    !!  @param[in]      integral    Array of autodiff values containing integrals and partial derivatives for the RHS vector and LIN linearization matrix
    !!  @param[inout]   rhs         Right-hand side vector
    !!  @param[inout]   lin         Block matrix storing the linearization of the spatial scheme
    !!  @param[in]      ielem       Element index for applying to the correct location in RHS and LIN
    !!  @param[in]      ieqn        Variable index
    !!  @param[in]      iblk        Block index for the correct linearization block for the current element
    !!
    !---------------------------------------------------------------------------------------------------------
    subroutine store_volume_integrals(integral,sdata,idom,ielem,ieqn,iblk)
        type(AD_D),             intent(inout)   :: integral(:)
        type(solverdata_t),     intent(inout)   :: sdata
        integer(ik),            intent(in)      :: idom
        integer(ik),            intent(in)      :: ielem
        integer(ik),            intent(in)      :: ieqn
        integer(ik),            intent(in)      :: iblk

        integer(ik) :: i
        real(rk)    :: vals(size(integral))


        !
        ! Only store rhs once. if iblk == DIAG
        !
        if (iblk == DIAG) then
            vals = sdata%rhs%dom(idom)%vecs(ielem)%getvar(ieqn) - integral(:)%x_ad_
            call sdata%rhs%dom(idom)%vecs(ielem)%setvar(ieqn,vals)
        end if

        !
        ! Negate derivatives before adding to linearization
        !
        do i = 1,size(integral)
            integral(i)%xp_ad_ = -integral(i)%xp_ad_
        end do

        !
        ! Store linearization
        !
        call sdata%lhs%store(integral,idom,ielem,iblk,ieqn)


    end subroutine store_volume_integrals
    !*********************************************************************************************************










    !> Store boundary integral values to RHS vector, and partial derivatives to LIN block matrix
    !!
    !!  @author Nathan A. Wukie
    !!
    !!
    !!  @param[in]      integral    Array of autodiff values containing integrals and partial derivatives for the RHS vector and LIN linearization matrix
    !!  @param[inout]   rhs         Right-hand side vector
    !!  @param[inout]   lin         Block matrix storing the linearization of the spatial scheme
    !!  @param[in]      ielem       Element index for applying to the correct location in RHS and LIN
    !!  @param[in]      ieqn        Variable index
    !!  @param[in]      iblk        Block index for the correct linearization block for the current element
    !!
    !--------------------------------------------------------------------------------------------------------
    subroutine store_boundary_integral_residual(mesh,sdata,face_info,function_info,ieqn,integral)
        type(mesh_t),           intent(in)      :: mesh(:)
        type(solverdata_t),     intent(inout)   :: sdata
        type(face_info_t),      intent(in)      :: face_info
        type(function_info_t),  intent(in)      :: function_info
        integer(ik),            intent(in)      :: ieqn
        type(AD_D),             intent(inout)   :: integral(:)

        integer(ik)     :: ftype
        real(rk)        :: vals(size(integral))

        logical         :: add_flux = .false.



        associate ( idomain_l  => face_info%idomain_l, ielement_l  => face_info%ielement_l, iface => face_info%iface, &
                    ifcn  => function_info%ifcn,       idonor => function_info%idonor,      iblk  => function_info%iblk )


            ftype = mesh(idomain_l)%faces(ielement_l,iface)%ftype


            associate ( rhs => sdata%rhs%dom(idomain_l)%vecs, lhs => sdata%lhs)


                !
                ! Only store rhs once. if iblk == DIAG. Also, since the integral could be computed more than once for chimera faces, only store for the first donor.
                ! The integral should be the same for any value of idonor. Only the derivatives will change
                !
                if ( ftype == BOUNDARY .and. ( ielement_l == face_info%seed%ielement_l ) ) then


                    vals = rhs(ielement_l)%getvar(ieqn) + integral(:)%x_ad_
                    call rhs(ielement_l)%setvar(ieqn,vals)




                else if ( ftype == CHIMERA .and. iblk == DIAG ) then

                    if (idonor == 1) then
                        vals = rhs(ielement_l)%getvar(ieqn) + integral(:)%x_ad_
                        call rhs(ielement_l)%setvar(ieqn,vals)
                    end if




                else if ( ftype == INTERIOR ) then
                    !
                    ! Check if particular flux function has been added already
                    !
                    add_flux = sdata%function_status%compute_function_equation( face_info, function_info, ieqn )



                    !
                    ! Store if needed
                    !
                    if ( add_flux ) then
                        !
                        ! Add to residual and store
                        !
                        vals = rhs(ielement_l)%getvar(ieqn) + integral(:)%x_ad_
                        call rhs(ielement_l)%setvar(ieqn,vals)

                        !
                        ! Register flux was stored
                        !
                        call sdata%function_status%register_function_computed( face_info, function_info, ieqn )
                    end if





                end if


            end associate

        end associate
    end subroutine store_boundary_integral_residual
    !***********************************************************************************************************









    !> Store boundary integral values to RHS vector, and partial derivatives to LIN block matrix
    !!
    !!  @author Nathan A. Wukie
    !!
    !!
    !!  @param[in]      integral    Array of autodiff values containing integrals and partial derivatives for the RHS vector and LIN linearization matrix
    !!  @param[inout]   rhs         Right-hand side vector
    !!  @param[inout]   lin         Block matrix storing the linearization of the spatial scheme
    !!  @param[in]      ielem       Element index for applying to the correct location in RHS and LIN
    !!  @param[in]      ieqn        Variable index
    !!  @param[in]      iblk        Block index for the correct linearization block for the current element
    !!
    !--------------------------------------------------------------------------------------------------------
    subroutine store_boundary_integral_linearization(mesh,sdata,face_info,function_info,ieqn,integral)
        type(mesh_t),           intent(in)      :: mesh(:)
        type(solverdata_t),     intent(inout)   :: sdata
        type(face_info_t),      intent(in)      :: face_info
        type(function_info_t),  intent(in)      :: function_info
        integer(ik),            intent(in)      :: ieqn
        type(AD_D),             intent(inout)   :: integral(:)

        integer(ik)                 :: i, idomain_l, ielement_l, iface, ftype, ChiID
        integer(ik)                 :: iblk, idonor, ifcn
        type(seed_t)                :: seed
        real(rk)                    :: vals(size(integral))

        logical :: add_linearization


        idomain_l  = face_info%idomain_l
        ielement_l = face_info%ielement_l
        iface      = face_info%iface
        seed       = face_info%seed
        ftype      = mesh(idomain_l)%faces(ielement_l,iface)%ftype

        ifcn   = function_info%ifcn
        idonor = function_info%idonor
        iblk   = function_info%iblk



        associate ( rhs => sdata%rhs%dom(idomain_l)%vecs, lhs => sdata%lhs)


            !
            ! Store linearization. Rules for different face types.
            !
            if ( ftype == CHIMERA ) then

                if (iblk /= DIAG) then
                    !
                    ! Store linearization of Chimera boundary donor elements.
                    !
                    call lhs%store_chimera(integral,face_info,seed,ieqn)
                else
                    !
                    ! Store linearization of Chimera boundary receiver element. Since this could be computed multiple times,
                    ! we just store it once.
                    !
                    if (idonor == 1) then
                        call lhs%store(integral,idomain_l,ielement_l,iblk,ieqn)
                    end if
                end if



            else if ( (ftype == BOUNDARY) ) then
                !
                ! Store linearization of boundary condition
                !
                call lhs%store_bc(integral,face_info,seed,ieqn)



            else if ( ftype == INTERIOR ) then


                add_linearization = sdata%function_status%linearize_function_equation( face_info, function_info, ieqn )

                !
                ! Store linearization if not already stored
                !
                if ( add_linearization ) then
                    ! Store linearization
                    call lhs%store(integral,idomain_l,ielement_l,iblk,ieqn)

                    ! Register flux as linearized
                    call sdata%function_status%register_function_linearized( face_info, function_info, ieqn )
                end if


            end if ! ftype

        end associate

    end subroutine store_boundary_integral_linearization
    !***********************************************************************************************************




























end module mod_integrate
