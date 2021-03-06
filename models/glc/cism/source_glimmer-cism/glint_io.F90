!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! WARNING: this file was automatically generated on
! Tue, 15 Jun 2010 22:11:50 +0000
! from ncdf_template.F90.in
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

! +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
! +                                                           +
! +  ncdf_template.f90 - part of the Glimmer_CISM ice model   + 
! +                                                           +
! +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
! 
! Copyright (C) 2004, 2005, 2006, 2007, 2008, 2009, 2010
! Glimmer-CISM contributors - see AUTHORS file for list of contributors
!
! This file is part of Glimmer-CISM.
!
! Glimmer-CISM is free software: you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation, either version 2 of the License, or (at
! your option) any later version.
!
! Glimmer-CISM is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU General Public License for more details.
!
! You should have received a copy of the GNU General Public License
! along with Glimmer-CISM.  If not, see <http://www.gnu.org/licenses/>.
!
! Glimmer-CISM is hosted on BerliOS.de:
! https://developer.berlios.de/projects/glimmer-cism/
!
! +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

#define NCO outfile%nc
#define NCI infile%nc


module glint_io
  !*FD template for creating subsystem specific I/O routines
  !*FD written by Magnus Hagdorn, 2004

  private :: get_xtype

  character(len=*),private,parameter :: hotvars = ' outmask '

contains

  !*****************************************************************************
  ! netCDF output
  !*****************************************************************************
  subroutine glint_io_createall(model,data,outfiles)
    !*FD open all netCDF files for output
    use glint_type
    use glide_types
    use glimmer_ncdf
    use glimmer_ncio
    implicit none
    type(glide_global_type) :: model
    type(glint_instance), optional :: data
    type(glimmer_nc_output),optional,pointer :: outfiles
    
    ! local variables
    type(glimmer_nc_output), pointer :: oc

    if (present(outfiles)) then
       oc => outfiles
    else
       oc=>model%funits%out_first
    end if

    do while(associated(oc))
       if (present(data)) then
          call glint_io_create(oc,model,data)
       else
          call glint_io_create(oc,model)
       end if
       oc=>oc%next
    end do
  end subroutine glint_io_createall

  subroutine glint_io_writeall(data,model,atend,outfiles,time)
    !*FD if necessary write to netCDF files
    use glint_type
    use glide_types
    use glimmer_ncdf
    use glimmer_ncio
    implicit none
    type(glint_instance) :: data
    type(glide_global_type) :: model
    logical, optional :: atend
    type(glimmer_nc_output),optional,pointer :: outfiles
    real(dp),optional :: time

    ! local variables
    type(glimmer_nc_output), pointer :: oc
    logical :: forcewrite=.false.

    if (present(outfiles)) then
       oc => outfiles
    else
       oc=>model%funits%out_first
    end if

    if (present(atend)) then
       forcewrite = atend
    end if

    do while(associated(oc))
#ifdef HAVE_AVG
       if (oc%do_averages) then
          call glint_avg_accumulate(oc,data,model)
       end if
#endif
       call glimmer_nc_checkwrite(oc,model,forcewrite,time)
       if (oc%nc%just_processed) then
          ! write standard variables
          call glint_io_write(oc,data)
#ifdef HAVE_AVG
          if (oc%do_averages) then
             call glint_avg_reset(oc,data)
          end if
#endif
       end if
       oc=>oc%next
    end do
  end subroutine glint_io_writeall
  
  subroutine glint_io_create(outfile,model,data)
    use glide_types
    use glint_type
    use glimmer_ncdf
    use glimmer_map_types
    use glimmer_log
    use glimmer_paramets
    use glimmer_scales
    implicit none
    type(glimmer_nc_output), pointer :: outfile
    type(glide_global_type) :: model
    type(glint_instance), optional :: data

    integer status,varid,pos

    integer :: time_dimid
    integer :: x1_dimid
    integer :: y1_dimid

    ! defining dimensions
    status = nf90_inq_dimid(NCO%id,'time',time_dimid)
    call nc_errorhandle(__FILE__,__LINE__,status)
    status = nf90_inq_dimid(NCO%id,'x1',x1_dimid)
    call nc_errorhandle(__FILE__,__LINE__,status)
    status = nf90_inq_dimid(NCO%id,'y1',y1_dimid)
    call nc_errorhandle(__FILE__,__LINE__,status)

    NCO%vars = ' '//trim(NCO%vars)//' '
    ! expanding hotstart variables
    pos = index(NCO%vars,' hot ') 
    if (pos.ne.0) then
       NCO%vars = NCO%vars(:pos)//NCO%vars(pos+4:)
       NCO%hotstart = .true.
    end if
    if (NCO%hotstart) then
       NCO%vars = trim(NCO%vars)//hotvars
    end if
    ! checking if we need to handle time averages
    pos = index(NCO%vars,"_tavg")
    if (pos.ne.0) then
       outfile%do_averages = .True.
    end if    

    !     ablt -- ablation
    pos = index(NCO%vars,' ablt ')
    status = nf90_inq_varid(NCO%id,'ablt',varid)
    if (pos.ne.0) then
      NCO%vars(pos+1:pos+4) = '    '
    end if
    if (pos.ne.0 .and. status.eq.nf90_enotvar) then
       call write_log('Creating variable ablt')
       status = nf90_def_var(NCO%id,'ablt',get_xtype(outfile,NF90_FLOAT),(/x1_dimid, y1_dimid, time_dimid/),varid)
       call nc_errorhandle(__FILE__,__LINE__,status)
       status = nf90_put_att(NCO%id, varid, 'long_name', 'ablation')
       status = nf90_put_att(NCO%id, varid, 'units', 'meter (water)/year')
       if (glimmap_allocated(model%projection)) then
          status = nf90_put_att(NCO%id, varid, 'grid_mapping',glimmer_nc_mapvarname)
          status = nf90_put_att(NCO%id, varid, 'coordinates', 'lon lat')
       end if
     end if

    !     arng -- air temperature half-range
    pos = index(NCO%vars,' arng ')
    status = nf90_inq_varid(NCO%id,'arng',varid)
    if (pos.ne.0) then
      NCO%vars(pos+1:pos+4) = '    '
    end if
    if (pos.ne.0 .and. status.eq.nf90_enotvar) then
       call write_log('Creating variable arng')
       status = nf90_def_var(NCO%id,'arng',get_xtype(outfile,NF90_FLOAT),(/x1_dimid, y1_dimid, time_dimid/),varid)
       call nc_errorhandle(__FILE__,__LINE__,status)
       status = nf90_put_att(NCO%id, varid, 'long_name', 'air temperature half-range')
       status = nf90_put_att(NCO%id, varid, 'units', 'degreeC')
       if (glimmap_allocated(model%projection)) then
          status = nf90_put_att(NCO%id, varid, 'grid_mapping',glimmer_nc_mapvarname)
          status = nf90_put_att(NCO%id, varid, 'coordinates', 'lon lat')
       end if
     end if

    !     global_orog -- orographic elevation provided by global model
    pos = index(NCO%vars,' global_orog ')
    status = nf90_inq_varid(NCO%id,'global_orog',varid)
    if (pos.ne.0) then
      NCO%vars(pos+1:pos+11) = '           '
    end if
    if (pos.ne.0 .and. status.eq.nf90_enotvar) then
       call write_log('Creating variable global_orog')
       status = nf90_def_var(NCO%id,'global_orog',get_xtype(outfile,NF90_FLOAT),(/x1_dimid, y1_dimid, time_dimid/),varid)
       call nc_errorhandle(__FILE__,__LINE__,status)
       status = nf90_put_att(NCO%id, varid, 'long_name', 'orographic elevation provided by global model')
       status = nf90_put_att(NCO%id, varid, 'standard_name', 'surface_altitude')
       status = nf90_put_att(NCO%id, varid, 'units', 'meter')
       if (glimmap_allocated(model%projection)) then
          status = nf90_put_att(NCO%id, varid, 'grid_mapping',glimmer_nc_mapvarname)
          status = nf90_put_att(NCO%id, varid, 'coordinates', 'lon lat')
       end if
     end if

    !     inmask -- downscaling mask
    pos = index(NCO%vars,' inmask ')
    status = nf90_inq_varid(NCO%id,'inmask',varid)
    if (pos.ne.0) then
      NCO%vars(pos+1:pos+6) = '      '
    end if
    if (pos.ne.0 .and. status.eq.nf90_enotvar) then
       call write_log('Creating variable inmask')
       status = nf90_def_var(NCO%id,'inmask',get_xtype(outfile,NF90_FLOAT),(/x1_dimid, y1_dimid, time_dimid/),varid)
       call nc_errorhandle(__FILE__,__LINE__,status)
       status = nf90_put_att(NCO%id, varid, 'long_name', 'downscaling mask')
       status = nf90_put_att(NCO%id, varid, 'units', '1')
       if (glimmap_allocated(model%projection)) then
          status = nf90_put_att(NCO%id, varid, 'grid_mapping',glimmer_nc_mapvarname)
          status = nf90_put_att(NCO%id, varid, 'coordinates', 'lon lat')
       end if
     end if

    !     local_orog -- orographic elevation provided by local model
    pos = index(NCO%vars,' local_orog ')
    status = nf90_inq_varid(NCO%id,'local_orog',varid)
    if (pos.ne.0) then
      NCO%vars(pos+1:pos+10) = '          '
    end if
    if (pos.ne.0 .and. status.eq.nf90_enotvar) then
       call write_log('Creating variable local_orog')
       status = nf90_def_var(NCO%id,'local_orog',get_xtype(outfile,NF90_FLOAT),(/x1_dimid, y1_dimid, time_dimid/),varid)
       call nc_errorhandle(__FILE__,__LINE__,status)
       status = nf90_put_att(NCO%id, varid, 'long_name', 'orographic elevation provided by local model')
       status = nf90_put_att(NCO%id, varid, 'standard_name', 'surface_altitude')
       status = nf90_put_att(NCO%id, varid, 'units', 'meter')
       if (glimmap_allocated(model%projection)) then
          status = nf90_put_att(NCO%id, varid, 'grid_mapping',glimmer_nc_mapvarname)
          status = nf90_put_att(NCO%id, varid, 'coordinates', 'lon lat')
       end if
     end if

    !     outmask -- upscaling mask
    pos = index(NCO%vars,' outmask ')
    status = nf90_inq_varid(NCO%id,'outmask',varid)
    if (pos.ne.0) then
      NCO%vars(pos+1:pos+7) = '       '
    end if
    if (pos.ne.0 .and. status.eq.nf90_enotvar) then
       call write_log('Creating variable outmask')
       status = nf90_def_var(NCO%id,'outmask',get_xtype(outfile,NF90_FLOAT),(/x1_dimid, y1_dimid, time_dimid/),varid)
       call nc_errorhandle(__FILE__,__LINE__,status)
       status = nf90_put_att(NCO%id, varid, 'long_name', 'upscaling mask')
       status = nf90_put_att(NCO%id, varid, 'units', '1')
       if (glimmap_allocated(model%projection)) then
          status = nf90_put_att(NCO%id, varid, 'grid_mapping',glimmer_nc_mapvarname)
          status = nf90_put_att(NCO%id, varid, 'coordinates', 'lon lat')
       end if
     end if

    !     prcp -- precipitation
    pos = index(NCO%vars,' prcp ')
    status = nf90_inq_varid(NCO%id,'prcp',varid)
    if (pos.ne.0) then
      NCO%vars(pos+1:pos+4) = '    '
    end if
    if (pos.ne.0 .and. status.eq.nf90_enotvar) then
       call write_log('Creating variable prcp')
       status = nf90_def_var(NCO%id,'prcp',get_xtype(outfile,NF90_FLOAT),(/x1_dimid, y1_dimid, time_dimid/),varid)
       call nc_errorhandle(__FILE__,__LINE__,status)
       status = nf90_put_att(NCO%id, varid, 'long_name', 'precipitation')
       status = nf90_put_att(NCO%id, varid, 'standard_name', 'lwe_precipitation_rate')
       status = nf90_put_att(NCO%id, varid, 'units', 'meter (water)/year')
       if (glimmap_allocated(model%projection)) then
          status = nf90_put_att(NCO%id, varid, 'grid_mapping',glimmer_nc_mapvarname)
          status = nf90_put_att(NCO%id, varid, 'coordinates', 'lon lat')
       end if
     end if

    !     siced -- superimposed ice depth
    pos = index(NCO%vars,' siced ')
    status = nf90_inq_varid(NCO%id,'siced',varid)
    if (pos.ne.0) then
      NCO%vars(pos+1:pos+5) = '     '
    end if
    if (pos.ne.0 .and. status.eq.nf90_enotvar) then
       call write_log('Creating variable siced')
       status = nf90_def_var(NCO%id,'siced',get_xtype(outfile,NF90_FLOAT),(/x1_dimid, y1_dimid, time_dimid/),varid)
       call nc_errorhandle(__FILE__,__LINE__,status)
       status = nf90_put_att(NCO%id, varid, 'long_name', 'superimposed ice depth')
       status = nf90_put_att(NCO%id, varid, 'units', 'meter')
       if (glimmap_allocated(model%projection)) then
          status = nf90_put_att(NCO%id, varid, 'grid_mapping',glimmer_nc_mapvarname)
          status = nf90_put_att(NCO%id, varid, 'coordinates', 'lon lat')
       end if
     end if

    !     snowd -- snow depth
    pos = index(NCO%vars,' snowd ')
    status = nf90_inq_varid(NCO%id,'snowd',varid)
    if (pos.ne.0) then
      NCO%vars(pos+1:pos+5) = '     '
    end if
    if (pos.ne.0 .and. status.eq.nf90_enotvar) then
       call write_log('Creating variable snowd')
       status = nf90_def_var(NCO%id,'snowd',get_xtype(outfile,NF90_FLOAT),(/x1_dimid, y1_dimid, time_dimid/),varid)
       call nc_errorhandle(__FILE__,__LINE__,status)
       status = nf90_put_att(NCO%id, varid, 'long_name', 'snow depth')
       status = nf90_put_att(NCO%id, varid, 'standard_name', 'surface_snow_thickness')
       status = nf90_put_att(NCO%id, varid, 'units', 'meter')
       if (glimmap_allocated(model%projection)) then
          status = nf90_put_att(NCO%id, varid, 'grid_mapping',glimmer_nc_mapvarname)
          status = nf90_put_att(NCO%id, varid, 'coordinates', 'lon lat')
       end if
     end if

  end subroutine glint_io_create

  subroutine glint_io_write(outfile,data)
    use glint_type
    use glimmer_ncdf
    use glimmer_paramets
    use glimmer_scales
    implicit none
    type(glimmer_nc_output), pointer :: outfile
    !*FD structure containg output netCDF descriptor
    type(glint_instance) :: data
    !*FD the model instance

    ! local variables
    real(dp) :: tavgf
    integer status, varid
    integer up
     
    tavgf = outfile%total_time
    if (tavgf.ne.0.d0) then
       tavgf = 1.d0/tavgf
    end if

    ! write variables
    status = nf90_inq_varid(NCO%id,'ablt',varid)
    if (status .eq. nf90_noerr) then
       status = nf90_put_var(NCO%id, varid, &
            data%ablt, (/1,1,outfile%timecounter/))
       call nc_errorhandle(__FILE__,__LINE__,status)
    end if

    status = nf90_inq_varid(NCO%id,'arng',varid)
    if (status .eq. nf90_noerr) then
       status = nf90_put_var(NCO%id, varid, &
            data%arng, (/1,1,outfile%timecounter/))
       call nc_errorhandle(__FILE__,__LINE__,status)
    end if

    status = nf90_inq_varid(NCO%id,'global_orog',varid)
    if (status .eq. nf90_noerr) then
       status = nf90_put_var(NCO%id, varid, &
            data%global_orog, (/1,1,outfile%timecounter/))
       call nc_errorhandle(__FILE__,__LINE__,status)
    end if

    status = nf90_inq_varid(NCO%id,'inmask',varid)
    if (status .eq. nf90_noerr) then
       status = nf90_put_var(NCO%id, varid, &
            data%downs%lmask, (/1,1,outfile%timecounter/))
       call nc_errorhandle(__FILE__,__LINE__,status)
    end if

    status = nf90_inq_varid(NCO%id,'local_orog',varid)
    if (status .eq. nf90_noerr) then
       status = nf90_put_var(NCO%id, varid, &
            data%local_orog, (/1,1,outfile%timecounter/))
       call nc_errorhandle(__FILE__,__LINE__,status)
    end if

    status = nf90_inq_varid(NCO%id,'outmask',varid)
    if (status .eq. nf90_noerr) then
       status = nf90_put_var(NCO%id, varid, &
            data%out_mask, (/1,1,outfile%timecounter/))
       call nc_errorhandle(__FILE__,__LINE__,status)
    end if

    status = nf90_inq_varid(NCO%id,'prcp',varid)
    if (status .eq. nf90_noerr) then
       status = nf90_put_var(NCO%id, varid, &
            data%prcp, (/1,1,outfile%timecounter/))
       call nc_errorhandle(__FILE__,__LINE__,status)
    end if

    status = nf90_inq_varid(NCO%id,'siced',varid)
    if (status .eq. nf90_noerr) then
       status = nf90_put_var(NCO%id, varid, &
            data%siced, (/1,1,outfile%timecounter/))
       call nc_errorhandle(__FILE__,__LINE__,status)
    end if

    status = nf90_inq_varid(NCO%id,'snowd',varid)
    if (status .eq. nf90_noerr) then
       status = nf90_put_var(NCO%id, varid, &
            data%snowd, (/1,1,outfile%timecounter/))
       call nc_errorhandle(__FILE__,__LINE__,status)
    end if

  end subroutine glint_io_write

  !*****************************************************************************
  ! netCDF input
  !*****************************************************************************  
  subroutine glint_io_readall(data,model)
    !*FD read from netCDF file
    use glint_type
    use glide_types
    use glimmer_ncio
    use glimmer_ncdf
    implicit none
    type(glint_instance) :: data
    type(glide_global_type) :: model

    ! local variables
    type(glimmer_nc_input), pointer :: ic    

    ic=>model%funits%in_first
    do while(associated(ic))
       call glimmer_nc_checkread(ic,model)
       if (ic%nc%just_processed) then
          call glint_io_read(ic,data)
       end if
       ic=>ic%next
    end do
  end subroutine glint_io_readall

  subroutine glint_io_read(infile,data)
    !*FD read variables from a netCDF file
    use glimmer_log
    use glimmer_ncdf
    use glint_type
    use glimmer_paramets
    use glimmer_scales
    implicit none
    type(glimmer_nc_input), pointer :: infile
    !*FD structure containg output netCDF descriptor
    type(glint_instance) :: data
    !*FD the model instance

    ! local variables
    integer status,varid
    integer up
    real(dp) :: scaling_factor

    ! read variables
    status = nf90_inq_varid(NCI%id,'outmask',varid)
    if (status .eq. nf90_noerr) then
       call write_log('  Loading outmask')
       status = nf90_get_var(NCI%id, varid, &
            data%out_mask, (/1,1,infile%current_time/))
       call nc_errorhandle(__FILE__,__LINE__,status)
       status = nf90_get_att(NCI%id, varid,'scale_factor',scaling_factor)
       if (status.ne.NF90_NOERR) then
          scaling_factor = 1.0d0
       end if
       if (abs(scaling_factor-1.0d0).gt.1.d-17) then
          call write_log("scaling outmask",GM_DIAGNOSTIC)
          data%out_mask = data%out_mask*scaling_factor
       end if
    end if

    status = nf90_inq_varid(NCI%id,'siced',varid)
    if (status .eq. nf90_noerr) then
       call write_log('  Loading siced')
       status = nf90_get_var(NCI%id, varid, &
            data%siced, (/1,1,infile%current_time/))
       call nc_errorhandle(__FILE__,__LINE__,status)
       status = nf90_get_att(NCI%id, varid,'scale_factor',scaling_factor)
       if (status.ne.NF90_NOERR) then
          scaling_factor = 1.0d0
       end if
       if (abs(scaling_factor-1.0d0).gt.1.d-17) then
          call write_log("scaling siced",GM_DIAGNOSTIC)
          data%siced = data%siced*scaling_factor
       end if
    end if

    status = nf90_inq_varid(NCI%id,'snowd',varid)
    if (status .eq. nf90_noerr) then
       call write_log('  Loading snowd')
       status = nf90_get_var(NCI%id, varid, &
            data%snowd, (/1,1,infile%current_time/))
       call nc_errorhandle(__FILE__,__LINE__,status)
       status = nf90_get_att(NCI%id, varid,'scale_factor',scaling_factor)
       if (status.ne.NF90_NOERR) then
          scaling_factor = 1.0d0
       end if
       if (abs(scaling_factor-1.0d0).gt.1.d-17) then
          call write_log("scaling snowd",GM_DIAGNOSTIC)
          data%snowd = data%snowd*scaling_factor
       end if
    end if

  end subroutine glint_io_read

  subroutine glint_io_checkdim(infile,model,data)
    !*FD check if dimension sizes in file match dims of model
    use glimmer_log
    use glimmer_ncdf
    use glide_types
    use glint_type
    implicit none
    type(glimmer_nc_input), pointer :: infile
    !*FD structure containg output netCDF descriptor
    type(glide_global_type) :: model
    type(glint_instance), optional :: data

    integer status,dimid,dimsize
    character(len=150) message

    ! check dimensions
  end subroutine glint_io_checkdim

  !*****************************************************************************
  ! calculating time averages
  !*****************************************************************************  
#ifdef HAVE_AVG
  subroutine glint_avg_accumulate(outfile,data,model)
    use glide_types
    use glint_type
    use glimmer_ncdf
    implicit none
    type(glimmer_nc_output), pointer :: outfile
    !*FD structure containg output netCDF descriptor
    type(glide_global_type) :: model
    type(glint_instance) :: data

    ! local variables
    real(dp) :: factor
    integer status, varid

    ! increase total time
    outfile%total_time = outfile%total_time + model%numerics%tinc
    factor = model%numerics%tinc

  end subroutine glint_avg_accumulate

  subroutine glint_avg_reset(outfile,data)
    use glint_type
    use glimmer_ncdf
    implicit none
    type(glimmer_nc_output), pointer :: outfile
    !*FD structure containg output netCDF descriptor
    type(glint_instance) :: data

    ! local variables
    integer status, varid

    ! reset total time
    outfile%total_time = 0.

  end subroutine glint_avg_reset
#endif

  !*********************************************************************
  ! some private procedures
  !*********************************************************************

  !> apply default type to be used in netCDF file
  integer function get_xtype(outfile,xtype)
    use glimmer_ncdf
    implicit none
    type(glimmer_nc_output), pointer :: outfile !< derived type holding information about output file
    integer, intent(in) :: xtype                !< the external netCDF type

    get_xtype = xtype
    
    if (xtype.eq.NF90_REAL .and. outfile%default_xtype.eq.NF90_DOUBLE) then
       get_xtype = NF90_DOUBLE
    end if
    if (xtype.eq.NF90_DOUBLE .and. outfile%default_xtype.eq.NF90_REAL) then
       get_xtype = NF90_REAL
    end if
  end function get_xtype

  !*********************************************************************
  ! lots of accessor subroutines follow
  !*********************************************************************
  subroutine glint_get_ablt(data,outarray)
    use glimmer_scales
    use glimmer_paramets
    use glint_type
    implicit none
    type(glint_instance) :: data
    real, dimension(:,:), intent(out) :: outarray

    outarray = data%ablt
  end subroutine glint_get_ablt

  subroutine glint_set_ablt(data,inarray)
    use glimmer_scales
    use glimmer_paramets
    use glint_type
    implicit none
    type(glint_instance) :: data
    real, dimension(:,:), intent(in) :: inarray

    data%ablt = inarray
  end subroutine glint_set_ablt

  subroutine glint_get_arng(data,outarray)
    use glimmer_scales
    use glimmer_paramets
    use glint_type
    implicit none
    type(glint_instance) :: data
    real, dimension(:,:), intent(out) :: outarray

    outarray = data%arng
  end subroutine glint_get_arng

  subroutine glint_set_arng(data,inarray)
    use glimmer_scales
    use glimmer_paramets
    use glint_type
    implicit none
    type(glint_instance) :: data
    real, dimension(:,:), intent(in) :: inarray

    data%arng = inarray
  end subroutine glint_set_arng

  subroutine glint_get_global_orog(data,outarray)
    use glimmer_scales
    use glimmer_paramets
    use glint_type
    implicit none
    type(glint_instance) :: data
    real, dimension(:,:), intent(out) :: outarray

    outarray = data%global_orog
  end subroutine glint_get_global_orog

  subroutine glint_set_global_orog(data,inarray)
    use glimmer_scales
    use glimmer_paramets
    use glint_type
    implicit none
    type(glint_instance) :: data
    real, dimension(:,:), intent(in) :: inarray

    data%global_orog = inarray
  end subroutine glint_set_global_orog

  subroutine glint_get_inmask(data,outarray)
    use glimmer_scales
    use glimmer_paramets
    use glint_type
    implicit none
    type(glint_instance) :: data
    real, dimension(:,:), intent(out) :: outarray

    outarray = data%downs%lmask
  end subroutine glint_get_inmask

  subroutine glint_set_inmask(data,inarray)
    use glimmer_scales
    use glimmer_paramets
    use glint_type
    implicit none
    type(glint_instance) :: data
    real, dimension(:,:), intent(in) :: inarray

    data%downs%lmask = inarray
  end subroutine glint_set_inmask

  subroutine glint_get_local_orog(data,outarray)
    use glimmer_scales
    use glimmer_paramets
    use glint_type
    implicit none
    type(glint_instance) :: data
    real, dimension(:,:), intent(out) :: outarray

    outarray = data%local_orog
  end subroutine glint_get_local_orog

  subroutine glint_set_local_orog(data,inarray)
    use glimmer_scales
    use glimmer_paramets
    use glint_type
    implicit none
    type(glint_instance) :: data
    real, dimension(:,:), intent(in) :: inarray

    data%local_orog = inarray
  end subroutine glint_set_local_orog

  subroutine glint_get_outmask(data,outarray)
    use glimmer_scales
    use glimmer_paramets
    use glint_type
    implicit none
    type(glint_instance) :: data
    real, dimension(:,:), intent(out) :: outarray

    outarray = data%out_mask
  end subroutine glint_get_outmask

  subroutine glint_set_outmask(data,inarray)
    use glimmer_scales
    use glimmer_paramets
    use glint_type
    implicit none
    type(glint_instance) :: data
    real, dimension(:,:), intent(in) :: inarray

    data%out_mask = inarray
  end subroutine glint_set_outmask

  subroutine glint_get_prcp(data,outarray)
    use glimmer_scales
    use glimmer_paramets
    use glint_type
    implicit none
    type(glint_instance) :: data
    real, dimension(:,:), intent(out) :: outarray

    outarray = data%prcp
  end subroutine glint_get_prcp

  subroutine glint_set_prcp(data,inarray)
    use glimmer_scales
    use glimmer_paramets
    use glint_type
    implicit none
    type(glint_instance) :: data
    real, dimension(:,:), intent(in) :: inarray

    data%prcp = inarray
  end subroutine glint_set_prcp

  subroutine glint_get_siced(data,outarray)
    use glimmer_scales
    use glimmer_paramets
    use glint_type
    implicit none
    type(glint_instance) :: data
    real, dimension(:,:), intent(out) :: outarray

    outarray = data%siced
  end subroutine glint_get_siced

  subroutine glint_set_siced(data,inarray)
    use glimmer_scales
    use glimmer_paramets
    use glint_type
    implicit none
    type(glint_instance) :: data
    real, dimension(:,:), intent(in) :: inarray

    data%siced = inarray
  end subroutine glint_set_siced

  subroutine glint_get_snowd(data,outarray)
    use glimmer_scales
    use glimmer_paramets
    use glint_type
    implicit none
    type(glint_instance) :: data
    real, dimension(:,:), intent(out) :: outarray

    outarray = data%snowd
  end subroutine glint_get_snowd

  subroutine glint_set_snowd(data,inarray)
    use glimmer_scales
    use glimmer_paramets
    use glint_type
    implicit none
    type(glint_instance) :: data
    real, dimension(:,:), intent(in) :: inarray

    data%snowd = inarray
  end subroutine glint_set_snowd


end module glint_io
