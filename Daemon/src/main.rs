mod ipc;

use std::{
    fs,
    io::{BufRead, BufReader, Write},
    os::unix::{fs::PermissionsExt, net::UnixListener},
    path::PathBuf,
};

use ipc::{handle_request, Response};

const MOBILE_UID: libc::uid_t = 501;
const MOBILE_GID: libc::gid_t = 501;

fn main() -> std::io::Result<()> {
    let paths = RuntimePaths::default();
    paths.ensure()?;
    log_line(&paths, "easytierd starting");

    if paths.socket.exists() {
        fs::remove_file(&paths.socket)?;
    }

    let listener = UnixListener::bind(&paths.socket)?;
    chown_mobile(&paths.socket)?;
    fs::set_permissions(&paths.socket, fs::Permissions::from_mode(0o660))?;
    log_line(&paths, &format!("listening on {}", paths.socket.display()));

    for stream in listener.incoming() {
        match stream {
            Ok(mut stream) => {
                let mut reader = BufReader::new(stream.try_clone()?);
                let mut line = String::new();
                if let Err(error) = reader.read_line(&mut line) {
                    log_line(&paths, &format!("read failed: {error}"));
                    continue;
                }
                let response = match serde_json::from_str(line.trim_end()) {
                    Ok(request) => handle_request(request, &paths.log),
                    Err(error) => Response::error("", "invalidRequest", error.to_string()),
                };
                let encoded = serde_json::to_vec(&response)?;
                stream.write_all(&encoded)?;
                stream.write_all(b"\n")?;
            }
            Err(error) => {
                log_line(&paths, &format!("accept failed: {error}"));
            }
        }
    }

    Ok(())
}

#[derive(Clone, Debug)]
struct RuntimePaths {
    base: PathBuf,
    runtime: PathBuf,
    logs: PathBuf,
    socket: PathBuf,
    log: PathBuf,
}

impl Default for RuntimePaths {
    fn default() -> Self {
        let base = std::env::var_os("EASYTIER_BASE_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from("/var/mobile/Library/Application Support/EasyTier"));
        let runtime = base.join("runtime");
        let logs = base.join("logs");
        let socket = runtime.join("easytierd.sock");
        let log = logs.join("easytierd.log");
        Self {
            base,
            runtime,
            logs,
            socket,
            log,
        }
    }
}

impl RuntimePaths {
    fn ensure(&self) -> std::io::Result<()> {
        fs::create_dir_all(&self.base)?;
        fs::create_dir_all(&self.runtime)?;
        fs::create_dir_all(&self.logs)?;
        chown_mobile(&self.base)?;
        chown_mobile(&self.runtime)?;
        chown_mobile(&self.logs)?;
        fs::set_permissions(&self.base, fs::Permissions::from_mode(0o700))?;
        fs::set_permissions(&self.runtime, fs::Permissions::from_mode(0o700))?;
        fs::set_permissions(&self.logs, fs::Permissions::from_mode(0o700))?;
        Ok(())
    }
}

fn chown_mobile(path: &PathBuf) -> std::io::Result<()> {
    use std::{ffi::CString, io};

    let c_path = CString::new(path.as_os_str().as_encoded_bytes())
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "path contains null byte"))?;
    let result = unsafe { libc::chown(c_path.as_ptr(), MOBILE_UID, MOBILE_GID) };
    if result == 0 {
        Ok(())
    } else {
        Err(io::Error::last_os_error())
    }
}

fn log_line(paths: &RuntimePaths, message: &str) {
    if let Ok(mut file) = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&paths.log)
    {
        let _ = writeln!(file, "{message}");
    }
}
