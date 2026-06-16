use std::{
    ffi::CStr,
    io,
    mem,
    os::fd::RawFd,
};

#[derive(Debug)]
pub struct UtunDevice {
    fd: RawFd,
    name: String,
}

impl UtunDevice {
    pub fn name(&self) -> &str {
        &self.name
    }

    pub fn duplicate_fd(&self) -> io::Result<RawFd> {
        let duplicated = unsafe { libc::dup(self.fd) };
        if duplicated >= 0 {
            Ok(duplicated)
        } else {
            Err(io::Error::last_os_error())
        }
    }
}

impl Drop for UtunDevice {
    fn drop(&mut self) {
        unsafe {
            libc::close(self.fd);
        }
    }
}

pub fn create_utun() -> io::Result<UtunDevice> {
    let fd = unsafe { libc::socket(libc::PF_SYSTEM, libc::SOCK_DGRAM, libc::SYSPROTO_CONTROL) };
    if fd < 0 {
        return Err(io::Error::last_os_error());
    }

    match connect_utun(fd) {
        Ok(name) => Ok(UtunDevice { fd, name }),
        Err(error) => {
            unsafe {
                libc::close(fd);
            }
            Err(error)
        }
    }
}

fn connect_utun(fd: RawFd) -> io::Result<String> {
    let mut info: libc::ctl_info = unsafe { mem::zeroed() };
    let name = b"com.apple.net.utun_control\0";
    for (index, byte) in name.iter().enumerate() {
        info.ctl_name[index] = *byte as libc::c_char;
    }

    let ioctl_result = unsafe { libc::ioctl(fd, libc::CTLIOCGINFO, &mut info) };
    if ioctl_result < 0 {
        return Err(io::Error::last_os_error());
    }

    let mut address: libc::sockaddr_ctl = unsafe { mem::zeroed() };
    address.sc_len = mem::size_of::<libc::sockaddr_ctl>() as u8;
    address.sc_family = libc::AF_SYSTEM as u8;
    address.ss_sysaddr = libc::AF_SYS_CONTROL as u16;
    address.sc_id = info.ctl_id;
    address.sc_unit = 0;

    let connect_result = unsafe {
        libc::connect(
            fd,
            &address as *const libc::sockaddr_ctl as *const libc::sockaddr,
            mem::size_of::<libc::sockaddr_ctl>() as libc::socklen_t,
        )
    };
    if connect_result < 0 {
        return Err(io::Error::last_os_error());
    }

    set_close_on_exec(fd)?;
    interface_name(fd)
}

fn set_close_on_exec(fd: RawFd) -> io::Result<()> {
    let flags = unsafe { libc::fcntl(fd, libc::F_GETFD) };
    if flags < 0 {
        return Err(io::Error::last_os_error());
    }
    let result = unsafe { libc::fcntl(fd, libc::F_SETFD, flags | libc::FD_CLOEXEC) };
    if result == 0 {
        Ok(())
    } else {
        Err(io::Error::last_os_error())
    }
}

fn interface_name(fd: RawFd) -> io::Result<String> {
    let mut buffer = [0 as libc::c_char; libc::IFNAMSIZ];
    let mut length = buffer.len() as libc::socklen_t;
    let result = unsafe {
        libc::getsockopt(
            fd,
            libc::SYSPROTO_CONTROL,
            libc::UTUN_OPT_IFNAME,
            buffer.as_mut_ptr() as *mut libc::c_void,
            &mut length,
        )
    };
    if result < 0 {
        return Err(io::Error::last_os_error());
    }

    let name = unsafe { CStr::from_ptr(buffer.as_ptr()) }
        .to_string_lossy()
        .into_owned();
    Ok(name)
}
