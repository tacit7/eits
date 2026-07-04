use serde_json::json;

pub fn run(cfg: &crate::config::Config) -> serde_json::Value {
    json!({
        "session_uuid": cfg.session_uuid,
        "session_id": cfg.session_id,
        "agent_uuid": std::env::var("EITS_AGENT_UUID").ok(),
        "agent_id": std::env::var("EITS_AGENT_ID").ok(),
        "project_id": cfg.project_id,
    })
}

#[cfg(test)]
mod tests {
    use assert_cmd::Command;

    #[test]
    fn whoami_reports_null_for_unset_env() {
        let out = Command::cargo_bin("eitsr")
            .unwrap()
            .env_remove("EITS_SESSION_UUID")
            .env_remove("EITS_SESSION_ID")
            .env_remove("EITS_AGENT_UUID")
            .env_remove("EITS_AGENT_ID")
            .env_remove("EITS_PROJECT_ID")
            .args(["whoami"])
            .assert()
            .success();
        let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
        let v: serde_json::Value = serde_json::from_str(stdout.trim()).unwrap();
        assert!(v["session_uuid"].is_null());
        assert!(v["session_id"].is_null());
        assert!(v["agent_uuid"].is_null());
        assert!(v["agent_id"].is_null());
        assert!(v["project_id"].is_null());
    }

    #[test]
    fn whoami_reports_set_env_values() {
        let out = Command::cargo_bin("eitsr")
            .unwrap()
            .env("EITS_SESSION_UUID", "u-123")
            .env("EITS_SESSION_ID", "7")
            .env("EITS_AGENT_UUID", "a-456")
            .env("EITS_AGENT_ID", "9")
            .env("EITS_PROJECT_ID", "1")
            .args(["whoami"])
            .assert()
            .success();
        let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
        let v: serde_json::Value = serde_json::from_str(stdout.trim()).unwrap();
        assert_eq!(v["session_uuid"], "u-123");
        assert_eq!(v["session_id"], "7");
        assert_eq!(v["agent_uuid"], "a-456");
        assert_eq!(v["agent_id"], "9");
        assert_eq!(v["project_id"], "1");
    }
}
