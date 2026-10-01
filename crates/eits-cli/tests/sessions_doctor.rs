mod common;
use assert_cmd::Command;
use serde_json::Value;

fn run(body: &'static str, setup: impl FnOnce(&std::path::Path), id: &str) -> Value {
    let home = tempfile::tempdir().unwrap();
    setup(home.path());
    let server = common::serve(vec![(200, body)]);
    let out = Command::cargo_bin("eits")
        .unwrap()
        .env_clear()
        .env("HOME", home.path())
        .env("EITS_URL", &server.url)
        .env("EITS_SESSION_UUID", "thread-123")
        .env("CODEX_THREAD_ID", "thread-123")
        .args(["sessions", "doctor", id])
        .assert()
        .success();
    let text = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    assert!(!text.contains("DO_NOT_DISCLOSE"));
    let requests = server.finish();
    assert_eq!(requests.len(), 1);
    assert_eq!(requests[0].method, "GET");
    assert_eq!(
        requests[0].path,
        format!(
            "/api/v1/sessions/{}",
            if id == "self" { "thread-123" } else { id }
        )
    );
    serde_json::from_str(&text).unwrap()
}

#[test]
fn codex_report_is_read_only_and_never_prints_file_contents() {
    let v = run(
        r#"{"session":{"uuid":"thread-123","provider":"codex","entrypoint":"cli","project_id":1,"archived":false,"description":"DO_NOT_DISCLOSE"}}"#,
        |home| {
            let env = home.join(".eits/codex/sessions");
            let messages = home.join(".codex/sessions/2026/09/28");
            std::fs::create_dir_all(&env).unwrap();
            std::fs::create_dir_all(&messages).unwrap();
            std::fs::write(env.join("thread-123.env"), "PRIVATE=DO_NOT_DISCLOSE").unwrap();
            std::fs::write(
                messages.join("rollout-time-thread-123.jsonl"),
                "DO_NOT_DISCLOSE",
            )
            .unwrap();
        },
        "self",
    );
    assert_eq!(v["metadata"]["provider"]["value"], "codex");
    assert_eq!(v["metadata"]["archived"]["value"], false);
    assert_eq!(v["reader_routing"]["reader"], "codex");
    assert_eq!(v["local"]["env_file"]["status"], "present");
    assert_eq!(v["local"]["message_file"]["status"], "found");
}

#[test]
fn omitted_metadata_is_unavailable_not_inferred_from_model() {
    let v = run(
        r#"{"uuid":"thread-123","project_id":1,"model_provider":"openai"}"#,
        |_| {},
        "7138",
    );
    for key in ["provider", "entrypoint", "archived"] {
        assert_eq!(v["metadata"][key]["status"], "unavailable");
    }
    assert_eq!(v["reader_routing"]["status"], "unavailable");
    assert_eq!(v["local"]["message_file"]["status"], "unavailable");
    assert_eq!(v["local"]["env_file"]["status"], "missing");
}

#[test]
fn claude_uses_api_worktree_and_uuid_not_integer_lookup_id() {
    let v = run(
        r#"{"uuid":"thread-123","provider":"claude","worktree_path":"/a.b/c","archived":true}"#,
        |home| {
            let dir = home.join(".claude/projects/-a-b-c");
            std::fs::create_dir_all(&dir).unwrap();
            std::fs::write(dir.join("thread-123.jsonl"), "DO_NOT_DISCLOSE").unwrap();
        },
        "7138",
    );
    assert_eq!(v["reader_routing"]["reader"], "claude");
    assert_eq!(v["local"]["message_file"]["status"], "found");
    assert_eq!(v["metadata"]["archived"]["value"], true);
}

#[test]
fn missing_self_identity_is_a_usage_error() {
    let home = tempfile::tempdir().unwrap();
    Command::cargo_bin("eits")
        .unwrap()
        .env_clear()
        .env("HOME", home.path())
        .args(["sessions", "doctor", "self"])
        .assert()
        .code(2);
}

#[test]
fn missing_files_and_missing_project_path_are_distinct() {
    let codex = run(
        r#"{"uuid":"thread-123","provider":"codex"}"#,
        |_| {},
        "self",
    );
    assert_eq!(codex["local"]["message_file"]["status"], "missing");
    let claude = run(
        r#"{"uuid":"thread-123","provider":"claude"}"#,
        |_| {},
        "self",
    );
    assert_eq!(claude["local"]["message_file"]["status"], "unavailable");
    assert_eq!(
        claude["local"]["message_file"]["reason"],
        "resolved_project_path_not_exposed_by_api"
    );
}

#[test]
fn explicit_null_provider_preserves_the_apps_claude_fallback() {
    let v = run(
        r#"{"uuid":"thread-123","provider":null,"entrypoint":null,"project_id":null}"#,
        |_| {},
        "self",
    );
    assert_eq!(v["metadata"]["provider"]["status"], "available");
    assert!(v["metadata"]["provider"]["value"].is_null());
    assert_eq!(v["reader_routing"]["reader"], "claude");
}

#[test]
fn unsupported_uuid_and_invalid_provider_cannot_drive_discovery() {
    let v = run(r#"{"uuid":"../escape","provider":"codex"}"#, |_| {}, "self");
    assert_eq!(v["local"]["message_file"]["status"], "unavailable");
    let v = run(r#"{"uuid":"thread-123","provider":42}"#, |_| {}, "self");
    assert_eq!(v["reader_routing"]["status"], "unavailable");
}

#[test]
fn explicit_env_file_override_wins_without_exposing_path_or_contents() {
    let home = tempfile::tempdir().unwrap();
    let path = home.path().join("DO_NOT_DISCLOSE.env");
    std::fs::write(&path, "PRIVATE=DO_NOT_DISCLOSE").unwrap();
    let server = common::serve(vec![(200, r#"{"uuid":"thread-123"}"#)]);
    let out = Command::cargo_bin("eits")
        .unwrap()
        .env_clear()
        .env("HOME", home.path())
        .env("EITS_URL", &server.url)
        .env("EITS_CODEX_ENV_FILE", &path)
        .env("CODEX_THREAD_ID", "missing")
        .args(["sessions", "doctor", "7138", "--pretty"])
        .assert()
        .success();
    let text = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    assert!(!text.contains("DO_NOT_DISCLOSE"));
    let v: Value = serde_json::from_str(&text).unwrap();
    assert_eq!(v["local"]["env_file"]["status"], "present");
    assert_eq!(
        v["local"]["env_file_scope"],
        "current_process_not_queried_session"
    );
    assert_eq!(server.finish().len(), 1);
}

#[test]
fn filesystem_scan_errors_are_not_reported_as_missing() {
    let v = run(
        r#"{"uuid":"thread-123","provider":"codex"}"#,
        |home| {
            std::fs::create_dir(home.join(".codex")).unwrap();
            std::fs::write(home.join(".codex/sessions"), "not a directory").unwrap();
        },
        "self",
    );
    assert_eq!(v["local"]["message_file"]["status"], "unavailable");
}

#[cfg(unix)]
#[test]
fn skipped_symlink_cannot_establish_file_absence() {
    let v = run(
        r#"{"uuid":"thread-123","provider":"codex"}"#,
        |home| {
            let root = home.join(".codex/sessions");
            std::fs::create_dir_all(&root).unwrap();
            std::os::unix::fs::symlink(home.join("elsewhere"), root.join("linked")).unwrap();
        },
        "self",
    );
    assert_eq!(v["local"]["message_file"]["status"], "unavailable");
}
