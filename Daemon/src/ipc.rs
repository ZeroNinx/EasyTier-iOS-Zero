use std::{fs, path::Path, time::SystemTime};

use serde::{Deserialize, Serialize};
use serde_json::Value;

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
}

#[derive(Debug, Serialize)]
pub struct ResponseError {
    pub code: String,
    pub message: String,
}

impl Response {
    pub fn ok(id: impl Into<String>, status: Option<&'static str>, data: Option<ResponseData>) -> Self {
        Self {
            id: id.into(),
            ok: true,
            status,
            data,
            error: None,
        }
    }

    pub fn error(id: impl Into<String>, code: impl Into<String>, message: impl Into<String>) -> Self {
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
}

impl Default for RuntimeState {
    fn default() -> Self {
        Self {
            status: RuntimeStatus::Stopped,
            profile_name: None,
            started_at: None,
            last_error: None,
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
            }),
        ),
        "start" => start(request, log_path, state),
        "stop" => stop(request, log_path, state),
        "tailLog" => {
            let limit = request.limit.unwrap_or(200).min(2000);
            let lines = tail_log(log_path, limit);
            Response::ok(
                request.id,
                Some(state.status.as_str()),
                Some(ResponseData {
                    lines: Some(lines),
                    version: None,
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

    // Core/utun are not wired yet. This marks the GUI-control lifecycle as running
    // so the next phase can replace this point with the real EasyTier Core startup.
    state.status = RuntimeStatus::Running;
    state.profile_name = Some(profile_name);
    state.started_at = Some(SystemTime::now());
    state.last_error = None;
    append_log(log_path, "runtime state changed to running (core not attached yet)");

    Response::ok(request.id, Some(state.status.as_str()), None)
}

fn stop(request: Request, log_path: &Path, state: &mut RuntimeState) -> Response {
    if state.status == RuntimeStatus::Stopped {
        return Response::ok(request.id, Some(state.status.as_str()), None);
    }

    state.status = RuntimeStatus::Stopping;
    append_log(log_path, "stop requested");

    state.status = RuntimeStatus::Stopped;
    state.profile_name = None;
    state.started_at = None;
    state.last_error = None;
    append_log(log_path, "runtime state changed to stopped");

    Response::ok(request.id, Some(state.status.as_str()), None)
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
