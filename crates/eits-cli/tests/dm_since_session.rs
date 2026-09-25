mod common;
use assert_cmd::Command;
use serde_json::Value;

fn command(url: &str) -> Command {
    let mut cmd = Command::cargo_bin("eits").unwrap();
    cmd.env("EITS_URL", url)
        .env("EITS_SESSION_UUID", "session-1")
        .env_remove("EITS_API_KEY")
        .env_remove("EITS_CODEX_ENV_FILE")
        .env_remove("EITS_CODEX_SESSION_ID")
        .env_remove("CODEX_THREAD_ID")
        .env_remove("CODEX_SESSION_ID")
        .env("EITS_RETRY_BASE_MS", "1");
    cmd
}

#[test]
fn inbox_and_wait_use_actual_started_at() {
    for sub in ["inbox", "wait"] {
        for body in [
            r#"{"started_at":"2026-09-01T12:30:00.123456Z","created_at":"2000-01-01T00:00:00Z"}"#,
            r#"{"session":{"started_at":"2026-09-01T12:30:00.123456Z"}}"#,
        ] {
            let srv = common::serve(vec![
                (200, body),
                (200, r#"{"messages":[],"items":[],"count":0}"#),
            ]);
            let out = command(&srv.url)
                .args(["dm", sub, "--since-session"])
                .assert()
                .success();
            let v: Value = serde_json::from_slice(&out.get_output().stdout).unwrap();
            assert!(v.get("warnings").is_none());
            let reqs = srv.finish();
            assert_eq!(reqs[0].path, "/api/v1/sessions/session-1");
            assert!(reqs[1]
                .path
                .contains("since=2026-09-01T12%3A30%3A00.123456Z"));
        }
    }
}

#[test]
fn missing_timestamp_warns_in_json_and_strict_mode_does_not_fetch_dms() {
    for sub in ["inbox", "wait"] {
        for (status, body) in [
            (200, r#"{"started_at":null}"#),
            (200, r#"{"started_at":" "}"#),
            (
                200,
                r#"{"created_at":"2000-01-01T00:00:00Z","turn_start_at":"2026-09-01T00:00:00Z"}"#,
            ),
            (404, r#"{"error":"missing"}"#),
        ] {
            let srv = common::serve(vec![
                (status, body),
                (200, r#"{"messages":[],"items":[],"count":0}"#),
            ]);
            let out = command(&srv.url)
                .args(["dm", sub, "--since-session"])
                .assert()
                .success();
            let v: Value = serde_json::from_slice(&out.get_output().stdout).unwrap();
            assert_eq!(v["warnings"][0]["code"], "session_start_unresolved");
            assert!(!srv.finish()[1].path.contains("since="));

            let srv = common::serve(vec![(status, body)]);
            let out = command(&srv.url)
                .args(["dm", sub, "--since-session", "--strict"])
                .assert()
                .failure();
            let v: Value = serde_json::from_slice(&out.get_output().stdout).unwrap();
            assert!(v["error"].as_str().unwrap().contains("session start"));
            assert_eq!(srv.finish().len(), 1);
        }
    }
}

#[test]
fn session_selection_and_explicit_since_remain_consistent() {
    for sub in ["inbox", "wait"] {
        for explicit in [false, true] {
            let srv = common::serve(vec![
                (200, r#"{"started_at":"2026-09-01T00:00:00Z"}"#),
                (200, r#"{"messages":[],"items":[],"count":0}"#),
            ]);
            let mut cmd = command(&srv.url);
            cmd.env_remove("EITS_SESSION_UUID")
                .env("EITS_SESSION_ID", "42")
                .args(["dm", sub, "--since-session", "--strict"]);
            if explicit {
                cmd.args(["--session", "other-session"]);
            }
            cmd.assert().success();
            let reqs = srv.finish();
            let selected = if explicit { "other-session" } else { "42" };
            assert_eq!(reqs[0].path, format!("/api/v1/sessions/{selected}"));
            assert!(reqs[1].path.contains(&format!("session={selected}")));
        }
        let srv = common::serve(vec![
            (200, "{}"),
            (200, r#"{"messages":[],"items":[],"count":0}"#),
        ]);
        let out = command(&srv.url)
            .args([
                "dm",
                sub,
                "--since-session",
                "--since",
                "2026-01-01T00:00:00Z",
            ])
            .assert()
            .success();
        let v: Value = serde_json::from_slice(&out.get_output().stdout).unwrap();
        assert_eq!(v["warnings"][0]["effective_since"], "2026-01-01T00:00:00Z");
        assert!(srv.finish()[1].path.contains("since=2026-01-01"));
        command("http://127.0.0.1:1")
            .args(["dm", sub, "--strict"])
            .assert()
            .code(2);
    }
}

#[test]
fn codex_env_file_identity_and_wait_zero_timeout_keep_resolution_contract() {
    let dir = tempfile::tempdir().unwrap();
    let env_file = dir.path().join("session.env");
    std::fs::write(&env_file, "EITS_SESSION_UUID=codex-session\n").unwrap();
    let srv = common::serve(vec![(200, "{}")]);
    let out = command(&srv.url)
        .env_remove("EITS_SESSION_UUID")
        .env_remove("EITS_SESSION_ID")
        .env("EITS_CODEX_ENV_FILE", &env_file)
        .args(["dm", "wait", "--since-session", "--timeout", "0"])
        .assert()
        .success();
    let v: Value = serde_json::from_slice(&out.get_output().stdout).unwrap();
    assert_eq!(v["count"], 0);
    assert_eq!(v["warnings"][0]["code"], "session_start_unresolved");
    assert_eq!(srv.finish()[0].path, "/api/v1/sessions/codex-session");
}
