module solver_forward_euler
    use mod_kinds,      only: rk,ik
    use mod_constants,  only: ZERO
    use atype_solver,   only: solver_t
    use type_domain,    only: domain_t
    use type_expansion

    use mod_spatial,    only: update_space

    use mod_tecio,      only: write_tecio_variables
    implicit none
    private


    type, extends(solver_t), public :: forward_euler_s

        real(rk)        :: dt

    contains
        procedure   :: init
        procedure   :: solve

        final :: destructor
    end type forward_euler_s

contains


    !> Solver initialization
    subroutine  init(self,domain)
        class(forward_euler_s),     intent(inout)   :: self
        type(domain_t),             intent(inout)   :: domain

        !> Call any other specialized initialization requirements
        self%dt = 0.001_rk
    end subroutine



    !> Solve for update 'dq'
    subroutine solve(self,domain)
        class(forward_euler_s), intent(inout)   :: self
        type(domain_t),         intent(inout)   :: domain

        character(100)  :: filename
        integer(ik)     :: itime, ntime, ielem


        ntime = 100
        associate ( q => domain%sdata%q, dq => domain%sdata%dq, rhs => domain%sdata%rhs, dt => self%dt)

            print*, 'entering time'
            do itime = 1,ntime


                call sleep(1)
!                print*, 'updating space'
                call update_space(domain)


!                dq = dt * rhs
!                q  = q + dq
!
!
!                write(filename, "(I2,A4)") itime, '.plt'
!                call write_tecio_variables(domain,trim(filename),itime+1)
!
!
!
!                !> Clear spatial residual
!                do ielem = 1,domain%mesh%nelem
!                    rhs(ielem)%vec = ZERO
!                end do

            end do

        end associate

    end subroutine



    
    subroutine destructor(self)
        type(forward_euler_s),      intent(in) :: self
    end subroutine

end module solver_forward_euler