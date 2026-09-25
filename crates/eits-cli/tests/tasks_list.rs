mod common;
use assert_cmd::Command;

fn command() -> Command {
    let mut cmd = Command::cargo_bin("eits").unwrap();
    cmd.env_remove("EITS_CODEX_ENV_FILE")
        .env_remove("EITS_CODEX_SESSION_ID")
        .env_remove("CODEX_THREAD_ID")
        .env_remove("CODEX_SESSION_ID")
        .env("EITS_SESSION_UUID", "test-session")
        .env("EITS_PROJECT_ID", "1");
    cmd
}

#[test]
fn state_filter_preserves_default_session_scope_and_json_output() {
    let srv = common::serve(vec![(200, r#"{"tasks":[{"id":8266,"state_id":2}]}"#)]);
    let out = command()
        .env("EITS_URL", &srv.url)
        .args(["tasks", "list", "--state", "in_progress"])
        .assert()
        .success();
    let value: serde_json::Value = serde_json::from_slice(&out.get_output().stdout).unwrap();
    assert_eq!(
        value,
        serde_json::json!({"items":[{"id":8266,"state_id":2}],"count":1})
    );
    let requests = srv.finish();
    assert_eq!(requests.len(), 1);
    let path = &requests[0].path;
    assert!(path.contains("state_id=2"), "{path}");
    assert!(path.contains("session_id=test-session"), "{path}");
    assert!(path.contains("project_id=1"), "{path}");
}

#[test]
fn every_documented_alias_and_api_id_filters_on_the_server() {
    let out = command().args(["tasks", "states"]).assert().success();
    let states: serde_json::Value = serde_json::from_slice(&out.get_output().stdout).unwrap();
    for state in states["items"].as_array().unwrap() {
        let id = state["id"].as_i64().unwrap().to_string();
        let mut values = vec![id.clone()];
        values.extend(
            state["aliases"]
                .as_array()
                .unwrap()
                .iter()
                .map(|alias| alias.as_str().unwrap().to_string()),
        );
        values.push(state["name"].as_str().unwrap().to_uppercase());
        for value in values {
            let srv = common::serve(vec![(200, r#"{"tasks":[]}"#)]);
            command()
                .env("EITS_URL", &srv.url)
                .args(["tasks", "list", "--all", "--state", &value])
                .assert()
                .success();
            let requests = srv.finish();
            assert_eq!(
                requests[0].path,
                format!("/api/v1/tasks?state_id={id}&project_id=1&limit=200"),
                "{value}"
            );
        }
    }
}

#[test]
fn invalid_states_fail_as_usage_before_network_access() {
    for value in ["unknown", "0", "5", "", "2&limit=1"] {
        let out = command()
            .env("EITS_URL", "http://127.0.0.1:1/api/v1")
            .args(["tasks", "list", "--state", value])
            .assert()
            .code(2);
        let error: serde_json::Value = serde_json::from_slice(&out.get_output().stdout).unwrap();
        assert_eq!(error["code"], "usage");
        assert!(error["error"]
            .as_str()
            .unwrap()
            .contains("expected API state ID"));
    }
}

#[test]
fn state_filter_composes_with_team_and_limit() {
    let srv = common::serve(vec![(200, r#"{"tasks":[]}"#)]);
    command()
        .env("EITS_URL", &srv.url)
        .args([
            "tasks",
            "list",
            "--state",
            "in_review",
            "--team",
            "743",
            "--limit",
            "10",
        ])
        .assert()
        .success();
    assert_eq!(
        srv.finish()[0].path,
        "/api/v1/tasks?state_id=4&team_id=743&limit=10"
    );
}

#[test]
fn list_help_documents_api_id_semantics() {
    command()
        .args(["tasks", "list", "--help"])
        .assert()
        .success()
        .stdout(predicates::str::contains("3=Done, 4=In Review"))
        .stdout(predicates::str::contains("in_progress"));
}
