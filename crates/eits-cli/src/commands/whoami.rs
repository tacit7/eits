use crate::config::Config;
use crate::error::{Code, EitsError};
use crate::http::Client;
use serde_json::json;

pub struct IdentitySnapshot {
    pub session: serde_json::Value,
    pub session_uuid: serde_json::Value,
    pub session_id: serde_json::Value,
    pub agent_uuid: String,
    pub agent_id: serde_json::Value,
    pub project_id: serde_json::Value,
}

pub fn resolve(client: &Client, cfg: &Config) -> Result<IdentitySnapshot, EitsError> {
    let session_id = cfg
        .session_uuid
        .as_deref()
        .or(cfg.session_id.as_deref())
        .ok_or_else(|| {
            EitsError::usage("whoami: EITS_SESSION_UUID or EITS_SESSION_ID must be set")
        })?;

    let session_resp = client.get(&format!("/sessions/{session_id}"))?;
    let session = session_resp.get("session").cloned().unwrap_or(session_resp);
    let session_uuid = session.get("uuid").cloned().unwrap_or(json!(null));
    let resolved_session_id = session
        .get("id")
        .filter(|v| v.is_i64() || v.is_u64())
        .cloned()
        .ok_or_else(|| {
            EitsError::api(
                "whoami: session_id not found in session response",
                Code::ServerError,
                None,
            )
        })?;
    let agent_uuid = session
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
    let project_id = session.get("project_id").cloned().unwrap_or(json!(null));

    // The session response may already carry the agent's integer id, saving
    // the second round-trip; otherwise resolve it via GET /agents/{uuid}.
    let agent_id = match session
        .get("agent_int_id")
        .filter(|v| v.is_i64() || v.is_u64())
    {
        Some(v) => v.clone(),
        None => {
            let agent_resp = client.get(&format!("/agents/{agent_uuid}"))?;
            agent_resp
                .get("agent")
                .and_then(|a| a.get("id"))
                .or_else(|| agent_resp.get("id"))
                .cloned()
                .ok_or_else(|| {
                    EitsError::api(
                        "whoami: agent id not found in agent response",
                        Code::ServerError,
                        None,
                    )
                })?
        }
    };

    Ok(IdentitySnapshot {
        session,
        session_uuid,
        session_id: resolved_session_id,
        agent_uuid,
        agent_id,
        project_id,
    })
}

pub fn run(client: &Client, cfg: &Config, pretty: bool) -> Result<(), EitsError> {
    let identity = resolve(client, cfg)?;

    crate::output::print_json(
        &json!({
            "session_uuid": identity.session_uuid,
            "session_id": identity.session_id,
            "agent_uuid": identity.agent_uuid,
            "agent_id": identity.agent_id,
            "project_id": identity.project_id,
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
    fn whoami_uses_agent_int_id_from_session_response_no_second_call() {
        let srv = common::serve(vec![(
            200,
            r#"{"uuid":"u-123","id":7,"agent_id":"a-456","agent_int_id":9,"project_id":1}"#,
        )]);
        let out = Command::cargo_bin("eits")
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
        let reqs = srv.finish();
        assert_eq!(
            reqs.len(),
            1,
            "agent_int_id present should skip /agents call"
        );
    }

    #[test]
    fn whoami_falls_back_to_agents_lookup_with_nested_shape() {
        let srv = common::serve(vec![
            (
                200,
                r#"{"uuid":"u-123","id":7,"agent_id":"a-456","project_id":1}"#,
            ),
            (200, r#"{"success":true,"agent":{"id":9}}"#),
        ]);
        let out = Command::cargo_bin("eits")
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
        let reqs = srv.finish();
        assert_eq!(
            reqs.len(),
            2,
            "missing agent_int_id requires the /agents call"
        );
    }

    #[test]
    fn whoami_without_session_identity_is_usage_error() {
        let home = tempfile::tempdir().unwrap();
        let out = Command::cargo_bin("eits")
            .unwrap()
            .env("HOME", home.path())
            .env_remove("EITS_SESSION_UUID")
            .env_remove("EITS_SESSION_ID")
            .env_remove("EITS_CODEX_ENV_FILE")
            .env_remove("EITS_CODEX_SESSION_ID")
            .env_remove("CODEX_THREAD_ID")
            .env_remove("CODEX_SESSION_ID")
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
