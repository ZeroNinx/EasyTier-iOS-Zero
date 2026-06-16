mod ipc;

use std::{
    fs,
    io::{BufRead, BufReader, Write},
    net::{TcpListener, TcpStream},
    os::unix::fs::PermissionsExt,
    path::PathBuf,
};

use ipc::{handle_request, Response};

const MOBILE_UID: libc::uid_t = 501;
const MOBILE_GID: libc::gid_t = 501;
const DEFAULT_IPC_ADDR: &str = "127.0.0.1:37657";

fn main() {
    if let Err(error) = run() {
        let paths = RuntimePaths::default();
        let _ = paths.ensure();
        log_line(&paths, &format!("fatal: {error}"));
        eprintln!("fatal: {error}");
        std::process::exit(1);
    }
}

fn run() -> std::io::Result<()> {
    let paths = RuntimePaths::default();
    paths.ensure()?;
    log_line(&paths, "easytierd starting");

    let ipc_addr = std::env::var("EASYTIER_IPC_ADDR").unwrap_or_else(|_| DEFAULT_IPC_ADDR.to_owned());
    log_line(&paths, &format!("binding tcp ipc on {ipc_addr}"));
    let listener = TcpListener::bind(&ipc_addr).map_err(|error| {
        log_line(&paths, &format!("bind failed on {ipc_addr}: {error}"));
        error
    })?;
    log_line(&paths, &format!("listening on {ipc_addr}"));

    for stream in listener.incoming() {
        match stream {
            Ok(stream) => {
                if let Err(error) = handle_stream(stream, &paths) {
                    log_line(&paths, &format!("request failed: {error}"));
                }
            }
            Err(error) => {
                log_line(&paths, &format!("accept failed: {error}"));
            }
        }
    }

    Ok(())
}

fn handle_stream(mut stream: TcpStream, paths: &RuntimePaths) -> std::io::Result<()> {
    let mut reader = BufReader::new(stream.try_clone()?);
    let mut line = String::new();
    reader.read_line(&mut line)?;
    let response = match serde_json::from_str(line.trim_end()) {
        Ok(request) => handle_request(request, &paths.log),
        Err(error) => Response::error("", "invalidRequest", error.to_string()),
    };
    let encoded = serde_json::to_vec(&response)?;
    stream.write_all(&encoded)?;
    stream.write_all(b"\n")?;
    Ok(())
}

#[derive(Clone, Debug)]
struct RuntimePaths {
    base: PathBuf,
    runtime: PathBuf,
    logs: PathBuf,
    log: PathBuf,
}

impl Default for RuntimePaths {
    fn default() -> Self {
        let base = std::env::var_os("EASYTIER_BASE_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from("/var/mobile/Library/Application Support/EasyTier"));
        let runtime = base.join("runtime");
        let logs = base.join("logs");
        let log = logs.join("easytierd.log");
        Self {
            base,
            runtime,
            logs,
            log,
        }
    }
}

impl RuntimePaths {
    fn ensure(&self) -> std::io::Result<()> {
        fs::create_dir_all(&self.base)?;
        fs::create_dir_all(&self.runtime)?;
        fs::create_dir_all(&self.logs)?;
        let _ = chown_mobile(&self.base);
        let _ = chown_mobile(&self.runtime);
        let _ = chown_mobile(&self.logs);
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
