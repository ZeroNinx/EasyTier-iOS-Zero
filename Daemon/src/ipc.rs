use std::{fs, path::Path};

use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize)]
pub struct Request {
    pub id: String,
    pub command: String,
    pub limit: Option<usize>,
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

pub fn handle_request(request: Request, log_path: &Path) -> Response {
    match request.command.as_str() {
        "ping" => Response::ok(request.id, Some("stopped"), None),
        "status" => Response::ok(request.id, Some("stopped"), None),
        "tailLog" => {
            let limit = request.limit.unwrap_or(200).min(2000);
            let lines = tail_log(log_path, limit);
            Response::ok(
                request.id,
                Some("stopped"),
                Some(ResponseData {
                    lines: Some(lines),
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
