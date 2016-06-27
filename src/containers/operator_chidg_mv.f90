module operator_chidg_mv
#include <messenger.h>
    use mod_kinds,          only: rk, ik
    use type_chidgMatrix,   only: chidgMatrix_t
    use type_chidgVector
    implicit none



    public operator(*)
    interface operator(*)
        module procedure MULT_chidgMatrix_chidgVector
    end interface

contains


    !> This function implements the important matrix-vector multiplication 
    !! operation : A*x : for multi-domain configurations, which use the chidg'Container' 
    !! type containers.
    !!
    !!  @author Nathan A. Wukie
    !!  @date   2/1/2016
    !!
    !!
    !!
    !------------------------------------------------------------------------------------
    function MULT_chidgMatrix_chidgVector(A,x) result(res)
        type(chidgMatrix_t),    intent(in)  :: A
        type(chidgVector_t),    intent(in)  :: x

        type(chidgVector_t) :: res
        integer(ik)         :: idom, ielem, iblk
        integer(ik)         :: dparent_g, dparent_l, eparent_g, eparent_l
        logical             :: nonconforming = .false.


        !
        ! Allocate result and clear
        !
        res = x
        call res%clear




        !
        ! Compute A*x for global matrix-vector product
        !
        do idom = 1,size(A%dom)

            !
            ! Routine for local blocks (lblks)
            !
            do ielem = 1,size(A%dom(idom)%lblks,1)
                do iblk = 1,size(A%dom(idom)%lblks,2)
                    
                    if (allocated(A%dom(idom)%lblks(ielem,iblk)%mat)) then
                        matrix_proc = IRANK
                        vector_proc = A%dom(idom)%lblks(ielem,iblk)%parent_proc()

                        local_multiply    = ( matrix_proc == vector_proc )
                        parallel_multiply = ( matrix_proc /= vector_proc )

                        dparent_l = A%dom(idom)%lblks(ielem,iblk)%dparent_l()
                        eparent_l = A%dom(idom)%lblks(ielem,iblk)%eparent_l()

        
                        if ( local_multiply ) then
                            associate ( resvec => res%dom(idom)%vecs(ielem)%vec,    &
                                        xvec   => x%dom(idom)%vecs(eparent_l)%vec,    &
                                        Amat   => A%dom(idom)%lblks(ielem,iblk)%mat )

                                resvec = resvec + matmul(Amat,xvec)

                            end associate
                        end if

                    end if

                end do
            end do



            !
            ! Routine for off-diagonal, chimera blocks
            !
            if (allocated(A%dom(idom)%chi_blks)) then
                do ielem = 1,size(A%dom(idom)%chi_blks,1)
                    do iblk = 1,size(A%dom(idom)%chi_blks,2)


                        if (allocated(A%dom(idom)%chi_blks(ielem,iblk)%mat)) then
                            matrix_proc = IRANK
                            vector_proc = A%dom(idom)%chi_blks(ielem,iblk)%parent_proc()

                            local_multiply    = ( matrix_proc == vector_proc )
                            parallel_multiply = ( matrix_proc /= vector_proc )


                            dparent_l = A%dom(idom)%chi_blks(ielem,iblk)%dparent_l()
                            eparent_l = A%dom(idom)%chi_blks(ielem,iblk)%eparent_l()

                            if ( local_multiply ) then
                                associate ( resvec => res%dom(idom)%vecs(ielem)%vec,        &
                                            xvec   => x%dom(dparent_l)%vecs(eparent_l)%vec,     &
                                            Amat   => A%dom(idom)%chi_blks(ielem,iblk)%mat  ) 

                                    !
                                    ! Test matrix vector sizes
                                    !
                                    nonconforming = ( size(Amat,2) /= size(xvec) )
                                    if (nonconforming) call chidg_signal(FATAL,"operator_chidg_mv: nonconforming Chimera m-v operation")

                                    resvec = resvec + matmul(Amat,xvec)

                                end associate
                            end if
                        end if

                    end do ! iblk
                end do ! ielem
            end if  ! allocated



!            !
!            ! Routine for boundary condition blocks
!            !
!            if ( allocated(A%dom(idom)%bc_blks) ) then
!                do ielem = 1,size(A%dom(idom)%bc_blks,1)
!                    do iblk = 1,size(A%dom(idom)%bc_blks,2)
!
!
!                        if ( allocated(A%dom(idom)%bc_blks(ielem,iblk)%mat) ) then
!                             dparent = A%dom(idom)%bc_blks(ielem,iblk)%dparent()
!                             eparent = A%dom(idom)%bc_blks(ielem,iblk)%eparent()
!
!                            associate ( resvec => res%dom(idom)%vecs(ielem)%vec,        &
!                                        xvec   => x%dom(dparent)%vecs(eparent)%vec,     &
!                                        Amat   => A%dom(idom)%bc_blks(ielem,iblk)%mat   ) 
!
!                                !
!                                ! Test matrix vector sizes
!                                !
!                                nonconforming = ( size(Amat,2) /= size(xvec) )
!                                if (nonconforming) call chidg_signal(FATAL,"operator_chidg_mv: nonconforming Chimera m-v operation")
!
!
!                                !
!                                ! Do MV multiply and add to vector
!                                !
!                                resvec = resvec + matmul(Amat,xvec)
!
!                                ! Test without global coupling
!                                !if (ielem == eparent) then
!                                !    resvec = resvec + matmul(Amat,xvec)
!                                !end if
!
!
!                            end associate
!                        end if
!
!                    end do ! iblk
!                end do ! ielem
!            end if  ! allocated

        end do ! idom






    end function MULT_chidgMatrix_chidgVector
    !****************************************************************************************


end module operator_chidg_mv
