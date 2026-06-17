use std::{
    ffi::{CStr, CString},
    fs,
    os::fd::RawFd,
    path::Path,
    sync::OnceLock,
    time::{Duration, Instant, SystemTime},
};

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::network::{build_plan, sync_plan, AppliedNetwork, NetworkPlan};
use crate::utun::{create_utun, UtunDevice};

static CORE_LOGGER_INIT: OnceLock<Result<(), String>> = OnceLock::new();

#[derive(Debug, Deserialize)]
pub struct Request {
    pub id: String,
    pub command: String,
    pub limit: Option<usize>,
    pub log: Option<String>,
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
    core_tun_fd: Option<RawFd>,
    core_tun_attached: bool,
    options: Option<Value>,
    applied_network: Option<AppliedNetwork>,
    last_peer_counters: Option<PeerCounterSnapshot>,
}

impl Default for RuntimeState {
    fn default() -> Self {
        Self {
            status: RuntimeStatus::Stopped,
            profile_name: None,
            started_at: None,
            last_error: None,
            utun: None,
            core_tun_fd: None,
            core_tun_attached: false,
            options: None,
            applied_network: None,
            last_peer_counters: None,
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
            let selected_log_path = match selected_log_path(log_path, request.log.as_deref()) {
                Ok(path) => path,
                Err(error) => return Response::error(request.id, "invalidLog", error),
            };
            let lines = tail_log(&selected_log_path, limit);
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

fn selected_log_path(log_path: &Path, source: Option<&str>) -> Result<std::path::PathBuf, String> {
    match source.unwrap_or("daemon") {
        "daemon" | "easytierd" | "easytierd.log" => Ok(log_path.to_path_buf()),
        "core" | "easytier-core" | "core.log" | "easytier-core.log" => {
            Ok(log_path.with_file_name("easytier-core.log"))
        }
        other => Err(format!("unknown log source: {other}")),
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

    match init_core_logger_once(log_path, &options) {
        Ok(path) => append_log(log_path, &format!("core logger ready: {path}")),
        Err(error) => append_log(log_path, &format!("core logger init skipped: {error}")),
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
    append_log(
        log_path,
        &format!("core tun fd prepared: fd={core_fd}; waiting for network plan"),
    );

    state.status = RuntimeStatus::Running;
    state.profile_name = Some(profile_name);
    state.started_at = Some(SystemTime::now());
    state.last_error = None;
    state.options = Some(options);
    state.core_tun_fd = Some(core_fd);
    state.core_tun_attached = false;
    state.utun = Some(utun);
    state.last_peer_counters = None;
    wait_for_network_plan(log_path, state);
    append_log(
        log_path,
        &format!("runtime state changed to running (core started, {utun_name} ready)"),
    );

    Response::ok(request.id, Some(state.status.as_str()), None)
}

fn stop(request: Request, log_path: &Path, state: &mut RuntimeState) -> Response {
    if state.status == RuntimeStatus::Stopped {
        return Response::ok(request.id, Some(state.status.as_str()), None);
    }

    state.status = RuntimeStatus::Stopping;
    append_log(log_path, "stop requested");

    clear_core_tun_fd(log_path, state);

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
    state.core_tun_attached = false;
    state.last_peer_counters = None;
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

fn init_core_logger_once(log_path: &Path, options: &Value) -> Result<String, String> {
    let level = options
        .get("logLevel")
        .and_then(Value::as_str)
        .unwrap_or("info");
    let core_log_path = log_path.with_file_name("easytier-core.log");
    let path = core_log_path
        .to_str()
        .ok_or_else(|| "daemon log path is not valid UTF-8".to_owned())?
        .to_owned();
    let result = CORE_LOGGER_INIT.get_or_init(|| init_core_logger(&path, level));
    result.clone().map(|_| path)
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

fn wait_for_network_plan(log_path: &Path, state: &mut RuntimeState) {
    let deadline = Instant::now() + Duration::from_secs(4);
    loop {
        apply_network_if_ready(log_path, state);
        if state.core_tun_attached {
            return;
        }
        if Instant::now() >= deadline {
            append_log(
                log_path,
                "network attach pending: no ready IPv4 plan before startup timeout",
            );
            return;
        }
        std::thread::sleep(Duration::from_millis(250));
    }
}

fn apply_network_with_info(log_path: &Path, state: &mut RuntimeState, info: Option<&str>) {
    let Some(utun_name) = state.utun.as_ref().map(|utun| utun.name().to_owned()) else {
        return;
    };
    let Some(options) = state.options.clone() else {
        return;
    };
    let parsed_info = info.and_then(|info| serde_json::from_str::<Value>(info).ok());
    log_peer_counters_if_changed(log_path, state, parsed_info.as_ref());
    let plan = match build_plan(&options, parsed_info.as_ref()) {
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

    let previous_matches = state
        .applied_network
        .as_ref()
        .map(|network| network.matches_plan(&plan))
        .unwrap_or(false);
    match sync_plan(&utun_name, &plan, state.applied_network.as_ref()) {
        Ok(applied_network) => {
            if !previous_matches {
                append_log(
                    log_path,
                    &format!(
                        "network applied on {}: {} routes={} mtu={}",
                        utun_name,
                        plan.address,
                        plan.routes.len(),
                        plan.mtu
                            .map(|mtu| mtu.to_string())
                            .unwrap_or_else(|| "-".to_owned())
                    ),
                );
                append_log(
                    log_path,
                    &format!("network plan routes: {}", format_plan_routes(&plan)),
                );
                log_core_network_snapshot(log_path, parsed_info.as_ref());
            }
            state.applied_network = Some(applied_network);
            if !state.core_tun_attached || !previous_matches {
                let reason = if state.core_tun_attached {
                    "network plan changed"
                } else {
                    "network plan ready"
                };
                attach_core_tun_fd(log_path, state, reason);
            }
        }
        Err(error) => {
            append_log(log_path, &format!("network apply failed: {error}"));
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct PeerCounterSnapshot {
    peers: usize,
    conns: usize,
    rx_bytes: u64,
    tx_bytes: u64,
    rx_packets: u64,
    tx_packets: u64,
}

fn log_peer_counters_if_changed(log_path: &Path, state: &mut RuntimeState, info: Option<&Value>) {
    let Some(info) = info else {
        return;
    };
    let Some(snapshot) = peer_counter_snapshot(info) else {
        return;
    };
    if state
        .last_peer_counters
        .as_ref()
        .is_some_and(|previous| previous == &snapshot)
    {
        return;
    }

    append_log(
        log_path,
        &format!(
            "core peer counters: peers={} conns={} rx={}/{} tx={}/{}",
            snapshot.peers,
            snapshot.conns,
            snapshot.rx_packets,
            snapshot.rx_bytes,
            snapshot.tx_packets,
            snapshot.tx_bytes
        ),
    );
    log_peer_conn_summary(log_path, info);
    state.last_peer_counters = Some(snapshot);
}

fn peer_counter_snapshot(info: &Value) -> Option<PeerCounterSnapshot> {
    let peers = info.get("peers")?.as_array()?;
    let mut snapshot = PeerCounterSnapshot {
        peers: peers.len(),
        conns: 0,
        rx_bytes: 0,
        tx_bytes: 0,
        rx_packets: 0,
        tx_packets: 0,
    };

    for peer in peers {
        let Some(conns) = peer.get("conns").and_then(Value::as_array) else {
            continue;
        };
        snapshot.conns += conns.len();
        for conn in conns {
            let Some(stats) = conn.get("stats") else {
                continue;
            };
            snapshot.rx_bytes += json_u64(stats, "rx_bytes");
            snapshot.tx_bytes += json_u64(stats, "tx_bytes");
            snapshot.rx_packets += json_u64(stats, "rx_packets");
            snapshot.tx_packets += json_u64(stats, "tx_packets");
        }
    }

    Some(snapshot)
}

fn log_peer_conn_summary(log_path: &Path, info: &Value) {
    let Some(peers) = info.get("peers").and_then(Value::as_array) else {
        return;
    };

    for peer in peers.iter().take(12) {
        let peer_id = peer
            .get("peer_id")
            .map(format_json_value)
            .unwrap_or_else(|| "-".to_owned());
        let default_conn = peer
            .get("default_conn_id")
            .map(format_json_value)
            .unwrap_or_else(|| "-".to_owned());
        let conns = peer
            .get("conns")
            .and_then(Value::as_array)
            .map(Vec::as_slice)
            .unwrap_or(&[]);
        let mut rx_packets = 0;
        let mut tx_packets = 0;
        let mut rx_bytes = 0;
        let mut tx_bytes = 0;
        let mut latency_us = Vec::new();
        let mut tunnels = Vec::new();

        for conn in conns {
            if let Some(stats) = conn.get("stats") {
                rx_packets += json_u64(stats, "rx_packets");
                tx_packets += json_u64(stats, "tx_packets");
                rx_bytes += json_u64(stats, "rx_bytes");
                tx_bytes += json_u64(stats, "tx_bytes");
                let latency = json_u64(stats, "latency_us");
                if latency > 0 {
                    latency_us.push(latency.to_string());
                }
            }
            let tunnel_type = conn
                .pointer("/tunnel/tunnel_type")
                .and_then(Value::as_str)
                .unwrap_or("-");
            let remote = conn
                .pointer("/tunnel/remote_addr/url")
                .and_then(Value::as_str)
                .unwrap_or("-");
            tunnels.push(format!("{tunnel_type}:{remote}"));
        }

        append_log(
            log_path,
            &format!(
                "core peer conn: peer_id={peer_id} conns={} default={} rx={}/{} tx={}/{} latency_us=[{}] tunnels=[{}]",
                conns.len(),
                default_conn,
                rx_packets,
                rx_bytes,
                tx_packets,
                tx_bytes,
                latency_us.join(","),
                tunnels.join(", ")
            ),
        );
    }

    if peers.len() > 12 {
        append_log(
            log_path,
            &format!("core peer conn: ... {} more", peers.len() - 12),
        );
    }
}

fn json_u64(value: &Value, key: &str) -> u64 {
    value.get(key).and_then(Value::as_u64).unwrap_or_default()
}

fn format_plan_routes(plan: &NetworkPlan) -> String {
    if plan.routes.is_empty() {
        return "[]".to_owned();
    }

    let routes = plan
        .routes
        .iter()
        .map(ToString::to_string)
        .collect::<Vec<_>>()
        .join(", ");
    format!("[{routes}]")
}

fn log_core_network_snapshot(log_path: &Path, info: Option<&Value>) {
    let Some(info) = info else {
        append_log(
            log_path,
            "core snapshot unavailable: runningInfo was not parsed",
        );
        return;
    };

    let my_node = info.get("my_node_info");
    let peer_id = my_node
        .and_then(|node| node.get("peer_id"))
        .map(format_json_value)
        .unwrap_or_else(|| "-".to_owned());
    let virtual_ipv4 = my_node
        .and_then(|node| node.get("virtual_ipv4"))
        .map(format_json_value)
        .unwrap_or_else(|| "-".to_owned());
    let hostname = my_node
        .and_then(|node| node.get("hostname"))
        .and_then(Value::as_str)
        .unwrap_or("-");
    let version = my_node
        .and_then(|node| node.get("version"))
        .and_then(Value::as_str)
        .unwrap_or("-");
    let routes = info
        .get("routes")
        .and_then(Value::as_array)
        .map(Vec::len)
        .unwrap_or_default();
    let peers = info
        .get("peers")
        .and_then(Value::as_array)
        .map(Vec::len)
        .unwrap_or_default();

    append_log(
        log_path,
        &format!(
            "core snapshot: my_peer_id={peer_id} virtual_ipv4={virtual_ipv4} hostname={hostname} version={version} routes={routes} peers={peers}"
        ),
    );

    if let Some(routes) = info.get("routes").and_then(Value::as_array) {
        for route in routes.iter().take(16) {
            append_log(
                log_path,
                &format!("core route: {}", format_core_route(route)),
            );
        }
        if routes.len() > 16 {
            append_log(
                log_path,
                &format!("core route: ... {} more", routes.len() - 16),
            );
        }
    }
}

fn format_core_route(route: &Value) -> String {
    let field = |name: &str| {
        route
            .get(name)
            .map(format_json_value)
            .unwrap_or_else(|| "-".to_owned())
    };
    format!(
        "peer_id={} ipv4={} next_hop={} cost={} latency={} proxy_cidrs={} hostname={} version={}",
        field("peer_id"),
        field("ipv4_addr"),
        field("next_hop_peer_id"),
        field("cost"),
        field("path_latency"),
        field("proxy_cidrs"),
        field("hostname"),
        field("version")
    )
}

fn format_json_value(value: &Value) -> String {
    match value {
        Value::String(value) => value.clone(),
        _ => serde_json::to_string(value).unwrap_or_else(|_| "-".to_owned()),
    }
}

fn clear_core_tun_fd(log_path: &Path, state: &mut RuntimeState) {
    if state.core_tun_fd.is_none() {
        return;
    }
    if state.core_tun_attached {
        if let Err(error) = set_core_tun_fd(-1) {
            append_log(log_path, &format!("clear core tun fd failed: {error}"));
        } else {
            append_log(log_path, "clear core tun fd requested");
        }
    }
    if let Some(fd) = state.core_tun_fd.take() {
        unsafe {
            libc::close(fd);
        }
        append_log(log_path, "core tun fd closed");
    }
    state.core_tun_attached = false;
}

fn attach_core_tun_fd(log_path: &Path, state: &mut RuntimeState, reason: &str) {
    let Some(fd) = state.core_tun_fd else {
        append_log(log_path, "set core tun fd skipped: fd is not available");
        return;
    };
    match set_core_tun_fd(fd) {
        Ok(()) => {
            state.core_tun_attached = true;
            append_log(
                log_path,
                &format!("set core tun fd succeeded: fd={fd} reason={reason}"),
            );
        }
        Err(error) => {
            state.core_tun_attached = false;
            state.last_error = Some(error.clone());
            append_log(log_path, &format!("set core tun fd failed: {error}"));
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
