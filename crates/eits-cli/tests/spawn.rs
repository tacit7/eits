mod common;

use assert_cmd::Command;
use common::serve;

const UUID: &str = "01234567-89ab-cdef-0123-456789abcdef";
const SUCCESS: &str = r#"{"session_id":42,"session_uuid":"01234567-89ab-cdef-0123-456789abcdef","agent_id":7,"message":"spawned"}"#;

fn spawn(url: &str, dir: &tempfile::TempDir) -> Command {
    let mut cmd = Command::cargo_bin("eits").unwrap();
    cmd.env(
        "EITS_EXTRAS",
        concat!(env!("CARGO_MANIFEST_DIR"), "/../../scripts/eits-extras"),
    )
    .env("EITS_URL", url)
    .env("EITS_API_KEY", "")
    .env("EITS_SESSION_UUID", "")
    .env("EITS_PROJECT_ID", "1")
    .env("EITS_SPAWN_LOG", dir.path().join("spawn-errors.log"))
    .args([
        "agents",
        "spawn",
        "--provider",
        "codex",
        "--instructions",
        "contract test",
    ]);
    cmd
}

#[test]
fn quiet_outputs_only_uuid_and_preserves_payload() {
    for flag in ["--quiet", "-q"] {
        let server = serve(vec![(201, SUCCESS)]);
        let dir = tempfile::tempdir().unwrap();
        spawn(&server.url, &dir)
            .arg(flag)
            .assert()
            .success()
            .stdout(format!("{UUID}\n"))
            .stderr("[eits] delegating to legacy eits-extras; output format may differ\n");
        let requests = server.finish();
        assert_eq!(requests.len(), 1);
        assert_eq!(requests[0].method, "POST");
        assert_eq!(requests[0].path, "/api/v1/agents");
        let body: serde_json::Value = serde_json::from_str(&requests[0].body).unwrap();
        assert_eq!(body["provider"], "codex");
        assert_eq!(body["instructions"], "contract test");
        assert!(body.get("quiet").is_none());
    }
}

#[test]
fn normal_output_keeps_full_response_and_compact_summary() {
    let server = serve(vec![(201, SUCCESS)]);
    let dir = tempfile::tempdir().unwrap();
    let result = spawn(&server.url, &dir).assert().success();
    let values: Vec<serde_json::Value> =
        serde_json::Deserializer::from_slice(&result.get_output().stdout)
            .into_iter()
            .map(Result::unwrap)
            .collect();
    assert_eq!(values.len(), 2);
    assert_eq!(values[0]["message"], "spawned");
    assert_eq!(values[1]["session_uuid"], UUID);
    assert!(values[1].get("message").is_none());
    server.finish();
}

#[test]
fn quiet_keeps_warnings_on_stderr() {
    let server = serve(vec![(201, SUCCESS)]);
    let dir = tempfile::tempdir().unwrap();
    spawn(&server.url, &dir)
        .env("EITS_PROJECT_ID", "")
        .arg("--quiet")
        .assert()
        .success()
        .stdout(format!("{UUID}\n"))
        .stderr(predicates::str::contains(
            "warning: instructions do not contain EITS_PROJECT_ID",
        ));
    server.finish();
}

#[test]
fn quiet_http_error_has_empty_stdout_and_nonzero_status() {
    let server = serve(vec![(422, r#"{"error":"invalid request"}"#)]);
    let dir = tempfile::tempdir().unwrap();
    spawn(&server.url, &dir)
        .arg("--quiet")
        .assert()
        .failure()
        .stdout("")
        .stderr(predicates::str::contains("spawn failed (HTTP 422)"));
    server.finish();
}

#[test]
fn quiet_rejects_success_without_a_session_uuid() {
    for body in [
        r#"{}"#,
        r#"{"session_uuid":null}"#,
        r#"{"session_uuid":""}"#,
        r#"{"session_uuid":42}"#,
        "not json",
    ] {
        let server = serve(vec![(201, body)]);
        let dir = tempfile::tempdir().unwrap();
        spawn(&server.url, &dir)
            .arg("--quiet")
            .assert()
            .failure()
            .stdout("")
            .stderr(predicates::str::contains("session_uuid"));
        server.finish();
    }
}

#[test]
fn quiet_dry_run_reports_diagnostics_without_spawning() {
    let dir = tempfile::tempdir().unwrap();
    spawn("http://127.0.0.1:1/api/v1", &dir)
        .args(["--quiet", "--dry-run"])
        .assert()
        .success()
        .stdout("")
        .stderr(predicates::str::contains("Dry-run validation passed"));
}
