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
fn inbox_defaults_to_actual_session_start() {
    for sub in ["inbox", "list"] {
        for body in [
            r#"{"started_at":"2026-09-01T12:30:00.123456Z","created_at":"2000-01-01T00:00:00Z","turn_start_at":"2026-09-02T00:00:00Z"}"#,
            r#"{"session":{"started_at":"2026-09-01T12:30:00.123456Z"}}"#,
        ] {
            let srv = common::serve(vec![
                (200, body),
                (200, r#"{"messages":[{"id":5}],"count":1}"#),
            ]);
            let out = command(&srv.url)
                .args(["dm", sub, "--from", "2", "--limit", "5"])
                .assert()
                .success();
            let v: Value = serde_json::from_slice(&out.get_output().stdout).unwrap();
            // Assert output before joining: the old implementation makes only one request.
            assert_eq!(v["items"][0]["id"], 5);
            assert!(v.get("warnings").is_none());
            let reqs = srv.finish();
            assert_eq!(reqs[0].path, "/api/v1/sessions/session-1");
            assert_eq!(
                reqs[1].path,
                "/api/v1/dm?session=session-1&limit=5&from=2&since=2026-09-01T12%3A30%3A00.123456Z"
            );
        }
    }
}

#[test]
fn all_time_and_explicit_since_skip_session_lookup() {
    for args in [vec!["--all-time"], vec!["--since", "2026-01-01T00:00:00Z"]] {
        let srv = common::serve(vec![(200, r#"{"messages":[{"id":5}],"count":1}"#)]);
        let out = command(&srv.url)
            .args(["dm", "inbox"])
            .args(&args)
            .assert()
            .success();
        let v: Value = serde_json::from_slice(&out.get_output().stdout).unwrap();
        assert_eq!(v["count"], 1);
        assert!(v.get("warnings").is_none());
        let reqs = srv.finish();
        assert!(reqs[0].path.starts_with("/api/v1/dm?"));
        assert_eq!(reqs[0].path.contains("since="), args[0] == "--since");
        if args[0] == "--since" {
            assert!(reqs[0].path.contains("since=2026-01-01T00%3A00%3A00Z"));
        }
    }
}

#[test]
fn default_resolution_failure_keeps_structured_warning() {
    for (status, body, reason) in [
        (
            200,
            r#"{"created_at":"2000-01-01T00:00:00Z"}"#,
            "missing_started_at",
        ),
        (200, r#"{"started_at":null}"#, "missing_started_at"),
        (200, r#"{"started_at":" "}"#, "missing_started_at"),
        (404, r#"{"error":"missing"}"#, "not_found"),
    ] {
        let srv = common::serve(vec![(status, body), (200, r#"{"messages":[],"count":0}"#)]);
        let out = command(&srv.url).args(["dm", "inbox"]).assert().success();
        let v: Value = serde_json::from_slice(&out.get_output().stdout).unwrap();
        assert_eq!(v["warnings"][0]["code"], "session_start_unresolved");
        assert_eq!(v["warnings"][0]["reason"], reason);
        assert_eq!(v["warnings"][0]["session"], "session-1");
        assert!(v["warnings"][0]["effective_since"].is_null());
        assert!(!srv.finish()[1].path.contains("since="));
    }
}

#[test]
fn default_resolution_uses_selected_session() {
    for explicit in [false, true] {
        let srv = common::serve(vec![
            (200, r#"{"started_at":"2026-09-01T00:00:00Z"}"#),
            (200, r#"{"messages":[],"count":0}"#),
        ]);
        let mut cmd = command(&srv.url);
        cmd.env_remove("EITS_SESSION_UUID")
            .env("EITS_SESSION_ID", "42")
            .args(["dm", "inbox"]);
        if explicit {
            cmd.args(["--session", "other-session"]);
        }
        cmd.assert().success();
        let reqs = srv.finish();
        let selected = if explicit { "other-session" } else { "42" };
        assert_eq!(reqs[0].path, format!("/api/v1/sessions/{selected}"));
        assert!(reqs[1].path.contains(&format!("session={selected}")));
    }
}

#[test]
fn all_time_rejects_conflicting_filters() {
    for args in [
        vec!["--since-session"],
        vec!["--since", "2026-01-01"],
        vec!["--strict"],
    ] {
        command("http://127.0.0.1:1")
            .args(["dm", "inbox", "--all-time"])
            .args(args)
            .assert()
            .code(2);
    }
}

#[test]
fn wait_default_still_skips_session_lookup() {
    let srv = common::serve(vec![(200, r#"{"items":[],"count":0}"#)]);
    command(&srv.url).args(["dm", "wait"]).assert().success();
    let reqs = srv.finish();
    assert!(reqs[0].path.starts_with("/api/v1/dm/wait?"));
    assert!(!reqs[0].path.contains("since="));
}
