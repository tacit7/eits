mod common;

use assert_cmd::Command;
use serde_json::Value;

#[test]
fn session_html_failures_identify_method_and_route_even_when_quiet() {
    for quiet in [false, true] {
        for (args, method, path) in [
            (
                vec!["sessions", "update", "s-1", "--status", "completed"],
                "PATCH",
                "/sessions/s-1",
            ),
            (
                vec!["sessions", "complete", "s-1"],
                "POST",
                "/sessions/s-1/complete",
            ),
        ] {
            let server = common::serve(vec![(404, "<html>private server traceback</html>")]);
            let mut command = Command::cargo_bin("eits").unwrap();
            command.env("EITS_URL", &server.url).args(args);
            if quiet {
                command.arg("--quiet");
            }
            let output = command.assert().code(1);
            let value: Value = serde_json::from_slice(&output.get_output().stdout).unwrap();
            assert_eq!(value["status"], 404);
            assert_eq!(value["code"], "not_found");
            assert!(value["error"]
                .as_str()
                .unwrap()
                .contains(&format!("{method} {path}")));
            assert!(!value.to_string().contains("private server traceback"));
            let requests = server.finish();
            assert_eq!(requests[0].method, method);
            assert_eq!(requests[0].path, format!("/api/v1{path}"));
        }
    }
}

#[test]
fn html_diagnostics_omit_query_values() {
    let server = common::serve(vec![(400, "<!DOCTYPE html><html>traceback</html>")]);
    let output = Command::cargo_bin("eits")
        .unwrap()
        .env("EITS_URL", &server.url)
        .args(["sessions", "list", "--search", "private-search-term"])
        .assert()
        .code(1);
    let value: Value = serde_json::from_slice(&output.get_output().stdout).unwrap();
    assert!(value["error"].as_str().unwrap().contains("GET /sessions"));
    assert!(!value.to_string().contains("private-search-term"));
    server.finish();
}

#[test]
fn long_poll_html_failure_identifies_route_without_query_values() {
    let server = common::serve(vec![(502, "<html>upstream failure</html>")]);
    let output = Command::cargo_bin("eits")
        .unwrap()
        .env("EITS_URL", &server.url)
        .args([
            "dm",
            "wait",
            "--session",
            "private-session",
            "--since",
            "2026-09-01T00:00:00Z",
            "--timeout",
            "1",
        ])
        .assert()
        .code(1);
    let value: Value = serde_json::from_slice(&output.get_output().stdout).unwrap();
    assert_eq!(value["status"], 502);
    assert_eq!(value["code"], "server_error");
    assert!(value["error"].as_str().unwrap().contains("GET /dm/wait"));
    assert!(!value.to_string().contains("private-session"));
    assert_eq!(server.finish().len(), 1);
}
