use serde_json::json;

#[derive(Debug, Clone, Copy, PartialEq, serde::Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Code {
    NotFound,
    Validation,
    Unauthorized,
    Forbidden,
    Conflict,
    ServerError,
    ConnectionFailed,
    ConfigInvalid,
    Usage,
    ExtrasNotFound,
    ExtrasExecFailed,
    LockTimeout,
}

/// Maps an HTTP status code to a `Code` variant. Used by http.rs.
pub fn code_for_status(status: u16) -> Code {
    match status {
        400 => Code::Validation,
        401 => Code::Unauthorized,
        403 => Code::Forbidden,
        404 => Code::NotFound,
        409 => Code::Conflict,
        _ => Code::ServerError,
    }
}

#[derive(Debug)]
pub struct EitsError {
    pub message: String,
    pub code: Code,
    pub status: Option<u16>,
    pub hint: Option<String>,
}

impl EitsError {
    pub fn api(msg: impl Into<String>, code: Code, status: Option<u16>) -> Self {
        Self {
            message: msg.into(),
            code,
            status,
            hint: None,
        }
    }

    pub fn usage(msg: impl Into<String>) -> Self {
        Self::api(msg, Code::Usage, None)
    }

    pub fn config(msg: impl Into<String>) -> Self {
        Self::api(msg, Code::ConfigInvalid, None)
    }

    pub fn with_hint(mut self, h: impl Into<String>) -> Self {
        self.hint = Some(h.into());
        self
    }

    pub fn exit_code(&self) -> i32 {
        match self.code {
            Code::Usage | Code::ConfigInvalid => 2,
            Code::ConnectionFailed => 3,
            _ => 1,
        }
    }

    pub fn to_envelope(&self) -> serde_json::Value {
        let mut v = json!({ "error": self.message, "code": self.code });
        if let Some(s) = self.status {
            v["status"] = json!(s);
        }
        if let Some(h) = &self.hint {
            v["hint"] = json!(h);
        }
        v
    }
}

pub fn exit_with(err: EitsError, pretty: bool) -> ! {
    crate::output::print_json(&err.to_envelope(), pretty);
    std::process::exit(err.exit_code());
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn envelope_shape_and_exit_codes() {
        let e = EitsError::api("Task not found", Code::NotFound, Some(404))
            .with_hint("Run `eits tasks list`");
        let v = e.to_envelope();
        assert_eq!(v["code"], "not_found");
        assert_eq!(v["status"], 404);
        assert_eq!(e.exit_code(), 1);
        assert_eq!(EitsError::usage("bad flag").exit_code(), 2);
        assert_eq!(
            EitsError::api("down", Code::ConnectionFailed, None).exit_code(),
            3
        );
    }

    #[test]
    fn non_http_error_omits_status() {
        let v = EitsError::usage("x").to_envelope();
        assert!(v.get("status").is_none() || v["status"].is_null());
    }

    #[test]
    fn code_for_status_maps_known_statuses() {
        assert_eq!(code_for_status(400), Code::Validation);
        assert_eq!(code_for_status(401), Code::Unauthorized);
        assert_eq!(code_for_status(403), Code::Forbidden);
        assert_eq!(code_for_status(404), Code::NotFound);
        assert_eq!(code_for_status(409), Code::Conflict);
        assert_eq!(code_for_status(500), Code::ServerError);
        assert_eq!(code_for_status(418), Code::ServerError);
    }
}
