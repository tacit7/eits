use crate::config::Config;
use crate::error::{Code, EitsError};
use crate::http::Client;
use serde_json::json;

pub fn run(client: &Client, cfg: &Config, pretty: bool) -> Result<(), EitsError> {
    let session_id = cfg
        .session_uuid
        .as_deref()
        .or(cfg.session_id.as_deref())
        .ok_or_else(|| {
            EitsError::usage("whoami: EITS_SESSION_UUID or EITS_SESSION_ID must be set")
        })?;

    let session_resp = client.get(&format!("/sessions/{session_id}"))?;
    let session_uuid = session_resp.get("uuid").cloned().unwrap_or(json!(null));
    let resolved_session_id = session_resp
        .get("session_id")
        .or_else(|| session_resp.get("id"))
        .cloned()
        .unwrap_or(json!(null));
    let agent_uuid = session_resp
        .get("agent_id")
        .and_then(|v| v.as_str())
        .ok_or_else(|| {
            EitsError::api(
                "whoami: agent_id not found in session response",
                Code::ServerError,
                None,
            )
        })?
        .to_string();
    let project_id = session_resp
        .get("project_id")
        .cloned()
        .unwrap_or(json!(null));

    let agent_resp = client.get(&format!("/agents/{agent_uuid}"))?;
    let agent_id = agent_resp.get("id").cloned().ok_or_else(|| {
        EitsError::api(
            "whoami: agent id not found in agent response",
            Code::ServerError,
            None,
        )
    })?;

    crate::output::print_json(
        &json!({
            "session_uuid": session_uuid,
            "session_id": resolved_session_id,
            "agent_uuid": agent_uuid,
            "agent_id": agent_id,
            "project_id": project_id,
        }),
        pretty,
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use assert_cmd::Command;

    mod common {
        include!(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/common/mod.rs"));
    }

    #[test]
    fn whoami_resolves_session_then_agent_and_prints_ids() {
        let srv = common::serve(vec![
            (
                200,
                r#"{"uuid":"u-123","session_id":7,"agent_id":"a-456","project_id":1}"#,
            ),
            (200, r#"{"id":9}"#),
        ]);
        let out = Command::cargo_bin("eitsr")
            .unwrap()
            .env("EITS_URL", &srv.url)
            .env("EITS_SESSION_UUID", "u-123")
            .args(["whoami"])
            .assert()
            .success();
        let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
        let v: serde_json::Value = serde_json::from_str(stdout.trim()).unwrap();
        assert_eq!(v["session_uuid"], "u-123");
        assert_eq!(v["session_id"], 7);
        assert_eq!(v["agent_uuid"], "a-456");
        assert_eq!(v["agent_id"], 9);
        assert_eq!(v["project_id"], 1);
        srv.finish();
    }

    #[test]
    fn whoami_without_session_identity_is_usage_error() {
        let out = Command::cargo_bin("eitsr")
            .unwrap()
            .env_remove("EITS_SESSION_UUID")
            .env_remove("EITS_SESSION_ID")
            .args(["whoami"])
            .assert()
            .code(2);
        let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
        let v: serde_json::Value = serde_json::from_str(stdout.trim()).unwrap();
        assert_eq!(v["code"], "usage");
        assert!(v["error"]
            .as_str()
            .unwrap()
            .contains("EITS_SESSION_UUID or EITS_SESSION_ID must be set"));
    }
}
