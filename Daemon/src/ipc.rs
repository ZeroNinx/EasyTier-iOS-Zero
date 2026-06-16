use std::{
    ffi::{CStr, CString},
    fs,
    path::Path,
    sync::Once,
    time::SystemTime,
};

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::network::{apply_plan, build_plan, AppliedNetwork};
use crate::utun::{create_utun, UtunDevice};

static CORE_LOGGER_INIT: Once = Once::new();

#[derive(Debug, Deserialize)]
pub struct Request {
    pub id: String,
    pub command: String,
    pub limit: Option<usize>,
    #[serde(rename = "profileName")]
    pub profile_name: Option<String>,
    pub options: Option<Value>,
}

#[derive(Debug, Serialize)]
pub struct Response {
    pub id: String,
    pub ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub status: Option<&'static str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<ResponseData>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<ResponseError>,
}

#[derive(Debug, Serialize)]
pub struct ResponseData {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub lines: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub version: Option<&'static str>,
    #[serde(rename = "runningInfo", skip_serializing_if = "Option::is_none")]
    pub running_info: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct ResponseError {
    pub code: String,
    pub message: String,
}

impl Response {
    pub fn ok(
        id: impl Into<String>,
        status: Option<&'static str>,
        data: Option<ResponseData>,
    ) -> Self {
        Self {
            id: id.into(),
            ok: true,
            status,
            data,
            error: None,
        }
    }

    pub fn error(
        id: impl Into<String>,
        code: impl Into<String>,
        message: impl Into<String>,
    ) -> Self {
        Self {
            id: id.into(),
            ok: false,
            status: None,
            data: None,
            error: Some(ResponseError {
                code: code.into(),
                message: message.into(),
            }),
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RuntimeStatus {
    Stopped,
    Starting,
    Running,
    Stopping,
    Failed,
}

impl RuntimeStatus {
    fn as_str(self) -> &'static str {
        match self {
            Self::Stopped => "stopped",
            Self::Starting => "starting",
            Self::Running => "running",
            Self::Stopping => "stopping",
            Self::Failed => "failed",
        }
    }
}

#[derive(Debug)]
pub struct RuntimeState {
    status: RuntimeStatus,
    profile_name: Option<String>,
    started_at: Option<SystemTime>,
    last_error: Option<String>,
    utun: Option<UtunDevice>,
    options: Option<Value>,
    applied_network: Option<AppliedNetwork>,
}

impl Default for RuntimeState {
    fn default() -> Self {
        Self {
            status: RuntimeStatus::Stopped,
            profile_name: None,
            started_at: None,
            last_error: None,
            utun: None,
            options: None,
            applied_network: None,
        }
    }
}

pub fn handle_request(request: Request, log_path: &Path, state: &mut RuntimeState) -> Response {
    match request.command.as_str() {
        "ping" => Response::ok(request.id, Some(state.status.as_str()), None),
        "status" => Response::ok(request.id, Some(state.status.as_str()), None),
        "version" => Response::ok(
            request.id,
            Some(state.status.as_str()),
            Some(ResponseData {
                lines: None,
                version: Some(env!("CARGO_PKG_VERSION")),
                running_info: None,
            }),
        ),
        "start" => start(request, log_path, state),
        "stop" => stop(request, log_path, state),
        "runningInfo" => running_info(request, state, log_path),
        "tailLog" => {
            let limit = request.limit.unwrap_or(200).min(2000);
            let lines = tail_log(log_path, limit);
            Response::ok(
                request.id,
                Some(state.status.as_str()),
                Some(ResponseData {
                    lines: Some(lines),
                    version: None,
                    running_info: None,
                }),
            )
        }
        other => Response::error(
            request.id,
            "unknownCommand",
            format!("unknown command: {other}"),
        ),
    }
}

fn start(request: Request, log_path: &Path, state: &mut RuntimeState) -> Response {
    if state.status == RuntimeStatus::Running {
        return Response::ok(request.id, Some(state.status.as_str()), None);
    }

    let Some(options) = request.options else {
        state.status = RuntimeStatus::Failed;
        state.last_error = Some("missing EasyTier options".to_owned());
        append_log(log_path, "start rejected: missing EasyTier options");
        return Response::error(request.id, "invalidProfile", "missing EasyTier options");
    };

    let Some(config) = options.get("config").and_then(Value::as_str) else {
        state.status = RuntimeStatus::Failed;
        state.last_error = Some("missing EasyTier config".to_owned());
        append_log(log_path, "start rejected: missing EasyTier config");
        return Response::error(request.id, "invalidProfile", "missing EasyTier config");
    };
    if config.trim().is_empty() {
        state.status = RuntimeStatus::Failed;
        state.last_error = Some("empty EasyTier config".to_owned());
        append_log(log_path, "start rejected: empty EasyTier config");
        return Response::error(request.id, "invalidProfile", "empty EasyTier config");
    }

    state.status = RuntimeStatus::Starting;
    let profile_name = request.profile_name.unwrap_or_else(|| "default".to_owned());
    let option_keys = options
        .as_object()
        .map(|object| object.len())
        .unwrap_or_default();
    append_log(
        log_path,
        &format!("start requested for profile '{profile_name}' with {option_keys} option fields"),
    );

    if let Err(error) = init_core_logger_once(log_path, &options) {
        append_log(log_path, &format!("core logger init skipped: {error}"));
    }

    if let Err(error) = run_core(config) {
        state.status = RuntimeStatus::Failed;
        state.last_error = Some(error.clone());
        append_log(log_path, &format!("core start failed: {error}"));
        return Response::error(request.id, "coreStartFailed", error);
    }

    let utun = match create_utun() {
        Ok(utun) => utun,
        Err(error) => {
            let error = error.to_string();
            let _ = easytier_ios::stop_network_instance();
            state.status = RuntimeStatus::Failed;
            state.last_error = Some(error.clone());
            append_log(log_path, &format!("utun create failed: {error}"));
            return Response::error(request.id, "utunCreateFailed", error);
        }
    };
    let utun_name = utun.name().to_owned();
    let core_fd = match utun.duplicate_fd() {
        Ok(fd) => fd,
        Err(error) => {
            let error = error.to_string();
            let _ = easytier_ios::stop_network_instance();
            state.status = RuntimeStatus::Failed;
            state.last_error = Some(error.clone());
            append_log(log_path, &format!("utun fd duplicate failed: {error}"));
            return Response::error(request.id, "utunAttachFailed", error);
        }
    };
    if let Err(error) = set_core_tun_fd(core_fd) {
        unsafe {
            libc::close(core_fd);
        }
        let _ = easytier_ios::stop_network_instance();
        state.status = RuntimeStatus::Failed;
        state.last_error = Some(error.clone());
        append_log(log_path, &format!("set core tun fd failed: {error}"));
        return Response::error(request.id, "utunAttachFailed", error);
    }

    state.status = RuntimeStatus::Running;
    state.profile_name = Some(profile_name);
    state.started_at = Some(SystemTime::now());
    state.last_error = None;
    state.options = Some(options);
    state.utun = Some(utun);
    apply_network_if_ready(log_path, state);
    append_log(
        log_path,
        &format!("runtime state changed to running (core started, {utun_name} attached)"),
    );

    Response::ok(request.id, Some(state.status.as_str()), None)
}

fn stop(request: Request, log_path: &Path, state: &mut RuntimeState) -> Response {
    if state.status == RuntimeStatus::Stopped {
        return Response::ok(request.id, Some(state.status.as_str()), None);
    }

    state.status = RuntimeStatus::Stopping;
    append_log(log_path, "stop requested");

    let stop_result = easytier_ios::stop_network_instance();
    if stop_result != 0 {
        append_log(log_path, "core stop returned failure");
    }

    if let Some(applied_network) = state.applied_network.take() {
        applied_network.cleanup();
        append_log(log_path, "network routes cleaned up");
    }
    state.utun = None;
    state.status = RuntimeStatus::Stopped;
    state.profile_name = None;
    state.started_at = None;
    state.last_error = None;
    state.options = None;
    append_log(log_path, "runtime state changed to stopped");

    Response::ok(request.id, Some(state.status.as_str()), None)
}

fn running_info(request: Request, state: &mut RuntimeState, log_path: &Path) -> Response {
    match get_core_running_info() {
        Ok(info) => {
            apply_network_with_info(log_path, state, Some(&info));
            Response::ok(
                request.id,
                Some(state.status.as_str()),
                Some(ResponseData {
                    lines: None,
                    version: None,
                    running_info: Some(info),
                }),
            )
        }
        Err(error) => Response::error(request.id, "runningInfoUnavailable", error),
    }
}

fn tail_log(path: &Path, limit: usize) -> Vec<String> {
    let Ok(contents) = fs::read_to_string(path) else {
        return Vec::new();
    };
    let mut lines: Vec<String> = contents
        .lines()
        .rev()
        .take(limit)
        .map(ToOwned::to_owned)
        .collect();
    lines.reverse();
    lines
}

fn append_log(path: &Path, message: &str) {
    use std::io::Write;

    if let Ok(mut file) = fs::OpenOptions::new().create(true).append(true).open(path) {
        let _ = writeln!(file, "{message}");
    }
}

fn init_core_logger_once(log_path: &Path, options: &Value) -> Result<(), String> {
    let level = options
        .get("logLevel")
        .and_then(Value::as_str)
        .unwrap_or("info");
    let core_log_path = log_path.with_file_name("easytier-core.log");
    let path = core_log_path
        .to_str()
        .ok_or_else(|| "daemon log path is not valid UTF-8".to_owned())?
        .to_owned();
    let mut result = Ok(());

    CORE_LOGGER_INIT.call_once(|| {
        result = init_core_logger(&path, level);
    });

    result
}

fn init_core_logger(path: &str, level: &str) -> Result<(), String> {
    let path = CString::new(path).map_err(|error| error.to_string())?;
    let level = CString::new(level).map_err(|error| error.to_string())?;
    let subsystem =
        CString::new("com.zeroninex.easytier.daemon").map_err(|error| error.to_string())?;
    let mut err: *const std::ffi::c_char = std::ptr::null();
    let ret =
        easytier_ios::init_logger(path.as_ptr(), level.as_ptr(), subsystem.as_ptr(), &mut err);
    if ret == 0 {
        Ok(())
    } else {
        Err(take_core_string(err).unwrap_or_else(|| "unknown logger error".to_owned()))
    }
}

fn run_core(config: &str) -> Result<(), String> {
    let config = CString::new(config).map_err(|error| error.to_string())?;
    let mut err: *const std::ffi::c_char = std::ptr::null();
    let ret = easytier_ios::run_network_instance(config.as_ptr(), &mut err);
    if ret == 0 {
        Ok(())
    } else {
        Err(take_core_string(err).unwrap_or_else(|| "unknown core start error".to_owned()))
    }
}

fn get_core_running_info() -> Result<String, String> {
    let mut info: *const std::ffi::c_char = std::ptr::null();
    let mut err: *const std::ffi::c_char = std::ptr::null();
    let ret = easytier_ios::get_running_info(&mut info, &mut err);
    if ret != 0 {
        return Err(take_core_string(err).unwrap_or_else(|| "running info unavailable".to_owned()));
    }

    take_core_string(info).ok_or_else(|| "running info is empty".to_owned())
}

fn apply_network_if_ready(log_path: &Path, state: &mut RuntimeState) {
    let info = get_core_running_info().ok();
    apply_network_with_info(log_path, state, info.as_deref());
}

fn apply_network_with_info(log_path: &Path, state: &mut RuntimeState, info: Option<&str>) {
    if state.applied_network.is_some() {
        return;
    }
    let Some(utun) = state.utun.as_ref() else {
        return;
    };
    let Some(options) = state.options.as_ref() else {
        return;
    };
    let parsed_info = info.and_then(|info| serde_json::from_str::<Value>(info).ok());
    let plan = match build_plan(options, parsed_info.as_ref()) {
        Ok(Some(plan)) => plan,
        Ok(None) => {
            append_log(log_path, "network apply skipped: no IPv4 address yet");
            return;
        }
        Err(error) => {
            append_log(log_path, &format!("network plan failed: {error}"));
            return;
        }
    };

    match apply_plan(utun.name(), &plan) {
        Ok(applied_network) => {
            append_log(
                log_path,
                &format!(
                    "network applied on {}: {}/{} routes={}",
                    utun.name(),
                    plan.address.address,
                    plan.address.prefix,
                    plan.routes.len()
                ),
            );
            state.applied_network = Some(applied_network);
        }
        Err(error) => {
            append_log(log_path, &format!("network apply failed: {error}"));
        }
    }
}

fn set_core_tun_fd(fd: std::ffi::c_int) -> Result<(), String> {
    let mut err: *const std::ffi::c_char = std::ptr::null();
    let ret = easytier_ios::set_tun_fd(fd, &mut err);
    if ret == 0 {
        Ok(())
    } else {
        Err(take_core_string(err).unwrap_or_else(|| "unknown set tun fd error".to_owned()))
    }
}

fn take_core_string(ptr: *const std::ffi::c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    let value = unsafe { CStr::from_ptr(ptr) }
        .to_string_lossy()
        .into_owned();
    easytier_ios::free_string(ptr);
    Some(value)
}
