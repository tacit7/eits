mod common;
use assert_cmd::Command;
use serde_json::{json, Value};

const CREATED: &str = r#"{"success":true,"task_id":42}"#;

fn command(url: &str, cwd: &std::path::Path) -> Command {
    let mut cmd = Command::cargo_bin("eits").unwrap();
    cmd.env_clear()
        .env("EITS_URL", url)
        .env("EITS_SESSION_UUID", "test-session")
        .current_dir(cwd)
        .args(["tasks", "create", "--title", "project inference"]);
    cmd
}

#[test]
fn explicit_project_wins_over_environment_without_lookup() {
    let cwd = tempfile::tempdir().unwrap();
    let srv = common::serve(vec![(200, CREATED)]);
    command(&srv.url, cwd.path())
        .env("EITS_PROJECT_ID", "7")
        .args([
            "--project",
            "6",
            "--team",
            "755",
            "--description",
            "details",
            "--priority",
            "high",
        ])
        .assert()
        .success()
        .stderr("")
        .stdout(format!("{CREATED}\n"));
    let requests = srv.finish();
    assert_eq!(requests.len(), 1);
    assert_eq!(requests[0].method, "POST");
    assert_eq!(requests[0].path, "/api/v1/tasks");
    assert_eq!(
        serde_json::from_str::<Value>(&requests[0].body).unwrap(),
        json!({
            "title": "project inference", "description": "details", "priority": "high",
            "project_id": "6", "team_id": "755", "session_id": "test-session"
        })
    );
}

#[test]
fn environment_project_skips_lookup_and_preserves_quiet_output() {
    let cwd = tempfile::tempdir().unwrap();
    let srv = common::serve(vec![(200, CREATED)]);
    command(&srv.url, cwd.path())
        .env("EITS_PROJECT_ID", "7")
        .arg("--quiet")
        .assert()
        .success()
        .stderr("")
        .stdout("42\n");
    let requests = srv.finish();
    assert_eq!(requests.len(), 1);
    assert_eq!(
        serde_json::from_str::<Value>(&requests[0].body).unwrap()["project_id"],
        "7"
    );
}

fn check_lookup(cwd: &std::path::Path, status: u16, response: &'static str, expected: Value) {
    let srv = common::serve(vec![(status, response), (200, CREATED)]);
    let out = command(&srv.url, cwd).assert().success();
    assert_eq!(
        serde_json::from_slice::<Value>(&out.get_output().stdout).unwrap(),
        json!({"success":true,"task_id":42})
    );
    let stderr = String::from_utf8_lossy(&out.get_output().stderr);
    if expected.is_null() {
        assert!(
            stderr.contains("warning:")
                && stderr.contains("global/unscoped")
                && stderr.contains("--project"),
            "{stderr}"
        );
    } else {
        assert!(stderr.is_empty(), "{stderr}");
    }
    let requests = srv.finish();
    assert_eq!(requests.len(), 2);
    assert_eq!(requests[0].method, "GET");
    let url = reqwest::Url::parse(&format!("http://localhost{}", requests[0].path)).unwrap();
    assert_eq!(url.path(), "/api/v1/projects");
    assert_eq!(
        url.query_pairs().collect::<Vec<_>>(),
        vec![(
            "path".into(),
            cwd.canonicalize()
                .unwrap()
                .to_string_lossy()
                .into_owned()
                .into()
        )]
    );
    assert_eq!(requests[1].method, "POST");
    assert_eq!(requests[1].path, "/api/v1/tasks");
    assert_eq!(
        serde_json::from_str::<Value>(&requests[1].body).unwrap()["project_id"],
        expected
    );
}

#[test]
fn cwd_lookup_infers_numeric_and_string_project_ids() {
    let cwd = tempfile::Builder::new()
        .prefix("eits space & project")
        .tempdir()
        .unwrap();
    for response in [r#"{"projects":[{"id":6}]}"#, r#"{"projects":[{"id":"6"}]}"#] {
        check_lookup(cwd.path(), 200, response, json!("6"));
    }
}

#[cfg(unix)]
#[test]
fn symlinked_cwd_uses_canonical_project_path() {
    let root = tempfile::tempdir().unwrap();
    let project = root.path().join("project");
    std::fs::create_dir(&project).unwrap();
    let link = root.path().join("alias");
    std::os::unix::fs::symlink(&project, &link).unwrap();
    check_lookup(&link, 200, r#"{"projects":[{"id":6}]}"#, json!("6"));
}

#[test]
fn missing_ambiguous_or_malformed_lookup_warns_without_polluting_json() {
    let cwd = tempfile::tempdir().unwrap();
    for response in [
        r#"{"projects":[]}"#,
        r#"{"projects":[{"id":6},{"id":7}]}"#,
        r#"{"projects":[{}]}"#,
        r#"{"projects":[{"id":null}]}"#,
        r#"{"projects":[{"id":""}]}"#,
        r#"{}"#,
    ] {
        check_lookup(cwd.path(), 200, response, Value::Null);
    }
}

#[test]
fn failed_lookup_warns_without_polluting_json() {
    let cwd = tempfile::tempdir().unwrap();
    check_lookup(cwd.path(), 403, r#"{"error":"forbidden"}"#, Value::Null);
}
