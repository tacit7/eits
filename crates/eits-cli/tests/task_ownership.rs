mod common;
use assert_cmd::Command;
use serde_json::{json, Value};

#[test]
fn lifecycle_commands_send_one_atomic_request_with_session_identity() {
    for (args, path, body) in [
        (
            vec!["tasks", "release", "42"],
            "/api/v1/tasks/42/release",
            json!({"session_id":"owner-session"}),
        ),
        (
            vec!["tasks", "handoff", "42", "--to", "73"],
            "/api/v1/tasks/42/handoff",
            json!({"session_id":"owner-session", "to":"73"}),
        ),
    ] {
        let server = common::serve(vec![(200, r#"{"success":true,"task":{"id":42}}"#)]);
        Command::cargo_bin("eits")
            .unwrap()
            .env("EITS_URL", &server.url)
            .env("EITS_SESSION_UUID", "owner-session")
            .args(args)
            .assert()
            .success();
        let requests = server.finish();
        assert_eq!(requests.len(), 1);
        assert_eq!(requests[0].method, "POST");
        assert_eq!(requests[0].path, path);
        assert_eq!(
            serde_json::from_str::<Value>(&requests[0].body).unwrap(),
            body
        );
    }
}

#[test]
fn handoff_requires_target() {
    Command::cargo_bin("eits")
        .unwrap()
        .args(["tasks", "handoff", "42"])
        .assert()
        .code(2);
}

#[test]
fn release_quiet_returns_id_and_conflict_is_reported() {
    let server = common::serve(vec![
        (200, r#"{"success":true,"task":{"id":42}}"#),
        (403, r#"{"error":"Only owner may release"}"#),
    ]);
    Command::cargo_bin("eits")
        .unwrap()
        .env("EITS_URL", &server.url)
        .env("EITS_SESSION_UUID", "owner-session")
        .args(["--quiet", "tasks", "release", "42"])
        .assert()
        .success()
        .stdout("42\n");
    Command::cargo_bin("eits")
        .unwrap()
        .env("EITS_URL", &server.url)
        .env("EITS_SESSION_UUID", "other-session")
        .args(["tasks", "release", "42"])
        .assert()
        .failure();
    assert_eq!(server.finish().len(), 2);
}
