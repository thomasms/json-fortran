!*****************************************************************************************
!> author: Izaak Beekman
!  date: 07/27/2015
!
! Module for the 12th unit test.

module jf_test_12_mod

    use json_kinds
    use json_module
    use, intrinsic :: iso_fortran_env , only: error_unit, output_unit, wp => real64

    implicit none

    character(len=*),parameter :: dir = '../files/'         !! Path to write JSON file to
    character(len=*),parameter :: file = 'test12.json'      !! Filename to write
    real(wp), parameter        :: TOL = 100*epsilon(1.0_wp) !! Tolerance for real comparisons

contains

    subroutine test_12(error_cnt)

    implicit none

    integer,intent(out) :: error_cnt !! report number of errors to caller

    integer,parameter :: imx = 5, jmx = 3, kmx = 4 !! dimensions for raw work array of primitive type

    type(json_core)                       :: json              !! factory for manipulating `json_value` pointers
    integer,dimension(3)                  :: shape             !! shape of work array
    integer, dimension(:), allocatable    :: fetched_shape     !! retrieved shape
    type(json_value), pointer             :: root, meta_array  !! json nodes to work with
    type(json_value), pointer             :: tmp_json_ptr
    type(json_file)                       :: my_file
    real(wp),dimension(imx,jmx,kmx)       :: raw_array         !! raw work array
    real(wp)                              :: array_element
    real(wp), dimension(:), allocatable   :: fetched_array
    character(kind=CK,len=:), allocatable :: description
    integer                               :: i,j,k             !! loop indices
    integer                               :: array_length, lun
    logical                               :: existed
    logical, dimension(:), allocatable    :: SOS

    error_cnt = 0
    call json%initialize(verbose=.true.,real_format='G')
    call check_errors()

    write(error_unit,'(A)') ''
    write(error_unit,'(A)') '================================='
    write(error_unit,'(A)') '   TEST 12'
    write(error_unit,'(A)') '================================='
    write(error_unit,'(A)') ''

    ! populate the raw array
    forall (i=1:imx,j=1:jmx,k=1:kmx) ! could use size(... , dim=...) instead of constants
       raw_array(i,j,k) = i + (j-1)*imx + (k-1)*imx*jmx
    end forall

    call json%create_object(root,dir//file)
    call check_errors()

    call json%create_object(meta_array,'array data')
    call check_errors()

    shape = [size(raw_array,dim=1), size(raw_array,dim=2), size(raw_array,dim=3)]
    call json%add(meta_array, 'shape', shape)
    call check_errors()

    call json%add(meta_array, 'total size', size(raw_array))
    call check_errors()

    call json%update(meta_array, 'total size', size(raw_array), found=existed)
    call check_errors(existed)

    call json%add(meta_array, CK_'description', 'test data')
    call check_errors()

    ! now add the array
    ! N.B. `json_add()` only accepts 1-D arrays and scalars, so transform with `reshape`
    ! N.B. reshape populates new array in "array element order".
    ! C.F. "Modern Fortran Explained", by Metcalf, Cohen and Reid, p. 24.
    ! N.B. Fortran is a column major language

    call json%add( meta_array, 'data', reshape( raw_array, [ size(raw_array) ] ) )
    call check_errors()

    ! now put it all together
    call json%add(root,meta_array)
    call check_errors()

    write(error_unit,'(A)') "Print the JSON object to stderr:"
    call json%print(root,error_unit)
    call check_errors()

    call json%get(root,'$.array data.data(1)',array_element)
    call check_errors(abs(array_element - 1.0_wp) <= TOL)

    call json%get(root,'@.array data.shape',fetched_shape)
    call check_errors(all(fetched_shape == shape))

    call json%update(meta_array,'description',CK_'Test Data',found=existed)
    call check_errors(existed)

    call json%update(meta_array,CK_'description','Test data',found=existed)
    call check_errors(existed)

    call json%get(meta_array,'description',description)
    call check_errors('Test data' == description)

    call json%get(root,'array data.total size',array_length)
    call check_errors(array_length == imx*jmx*kmx)

    sos = [.true.,  .true.,  .true.,  &
           .false., .false., .false., &
           .true., .true., .true.]
    call json%add(root,'SOS',sos)
    call check_errors()

    call json%get(root,'SOS',sos)
    call check_errors()

    call json%add(root,'vector string', [CK_'only one value'])
    call check_errors()

    call json%add(root,CK_'page', ['The quick brown fox     ', 'jumps over the lazy dog.'])
    call check_errors()

    call json%get(root,'SOS',tmp_json_ptr)
    call check_errors()

    call json%get(tmp_json_ptr,sos)
    call check_errors()

    call json%get(meta_array,'shape',tmp_json_ptr)
    call check_errors()

    call json%get(tmp_json_ptr,fetched_shape)
    call check_errors(all(fetched_shape == shape))

    call json%get(meta_array,'data',tmp_json_ptr)
    call check_errors()

    call json%get(tmp_json_ptr,fetched_array)
    call check_errors(all(abs(fetched_array - reshape(raw_array,[size(raw_array)])) <= TOL))

    call json%get(root,'array data.data',fetched_array)
    call check_errors(all(abs(fetched_array - reshape(raw_array,[size(raw_array)])) <= TOL))

    raw_array = 0
    call json%get(me=root,path='array data.data',array_callback=get_3D_from_array)
    call check_errors(all(abs(fetched_array - reshape(raw_array,[size(raw_array)])) <= TOL))

    my_file = json_file(root)

    call my_file%update('array data.description',CK_'vector data',found=existed)
    call check_file_errors(existed)

    call my_file%update(CK_'array data.description','Vector data',found=existed)
    call check_file_errors(existed)

    call my_file%get('SOS',sos)
    call check_file_errors()

    call my_file%get('$array data.data',fetched_array)
    call check_file_errors(all(abs(fetched_array - reshape(raw_array,[size(raw_array)])) <= TOL))

    call my_file%get(tmp_json_ptr)
    call check_file_errors(associated(tmp_json_ptr,root))

    open(file=dir//file,newunit=lun,form='formatted',action='write')
    call my_file%print_file(lun)
    call check_file_errors()
    close(lun)

    contains

      subroutine check_errors(assertion)
        !! check for errors in `json`

        implicit none

        logical, optional, intent(in) :: assertion
        if (json%failed()) then
           call json%print_error_message(error_unit)
           error_cnt = error_cnt + 1
        end if
        if (present (assertion)) then
           if (.not. assertion) error_cnt = error_cnt + 1
        end if

      end subroutine check_errors

      subroutine check_file_errors(assertion)
        !! check for errors in `my_file`

        implicit none

        logical, optional, intent(in) :: assertion
        if (my_file%failed()) then
           call my_file%print_error_message(error_unit)
           error_cnt = error_cnt + 1
        end if
        if (present (assertion)) then
           if (.not. assertion) error_cnt = error_cnt + 1
        end if

      end subroutine check_file_errors

      subroutine get_3D_from_array(json, element, i, count)
          !! array callback function

        implicit none

        class(json_core),intent(inout)      :: json
        type(json_value),pointer,intent(in) :: element
        integer,intent(in)                  :: i        !! index
        integer,intent(in)                  :: count    !! size of array

        integer :: useless !! assign count to this to silence warnings

        ! let's pretend we're c programmers!
        call json%get( element, raw_array( &
             mod(i-1,imx) + 1, &            ! i index
             mod((i-1)/imx,jmx) + 1, &      ! j index
             mod((i-1)/imx/jmx,kmx) + 1 ) ) ! k inded

        useless = count

      end subroutine get_3D_from_array

    end subroutine test_12

end module jf_test_12_mod
!*****************************************************************************************

!*****************************************************************************************
program jf_test_12

    !! 12th unit test.

    use jf_test_12_mod, only: test_12
    implicit none
    integer :: n_errors
    n_errors = 0
    call test_12(n_errors)
    if ( n_errors /= 0) stop 1

end program jf_test_12
!*****************************************************************************************
