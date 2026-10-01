use std::net::TcpListener;
use std::process::{Command, Output};

fn run(config: &std::path::Path, url: &str, alternate: &str, quiet: bool) -> Output {
    let mut command = Command::new(env!("CARGO_BIN_EXE_eits"));
    command
        .env_clear()
        .env("XDG_CONFIG_HOME", config)
        .env("EITS_URL", url)
        .env("EITS_API_URL", alternate)
        .env("EITS_API_KEY", "diagnostics-test-secret")
        .env("EITS_RETRY", "0")
        .args(["tasks", "link-session", "1", "test-session"]);
    if quiet {
        command.arg("--quiet");
    }
    command.output().unwrap()
}

#[test]
fn link_session_connection_failure_is_actionable_even_when_quiet() {
    let config = tempfile::tempdir().unwrap();
    let closed = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}/api/v1", closed.local_addr().unwrap());
    drop(closed);
    // A listening alternate detects an accidental fallback without contacting EITS.
    let alternate = TcpListener::bind("127.0.0.1:0").unwrap();
    alternate.set_nonblocking(true).unwrap();
    let alternate_url = format!("http://{}/api/v1", alternate.local_addr().unwrap());

    for quiet in [false, true] {
        let output = run(config.path(), &url, &alternate_url, quiet);
        assert_eq!(output.status.code(), Some(3));
        let error: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
        assert_eq!(error["code"], "connection_failed");
        assert!(error["error"]
            .as_str()
            .unwrap()
            .contains(&format!("{url}/tasks/1/sessions")));
        let hint = error["hint"].as_str().unwrap();
        assert!(hint.contains("EITS_URL"));
        assert!(hint.contains("server"));
        assert!(error.get("status").is_none());
        for bytes in [&output.stdout, &output.stderr] {
            assert!(!String::from_utf8_lossy(bytes).contains("diagnostics-test-secret"));
        }
    }
    assert_eq!(
        alternate.accept().unwrap_err().kind(),
        std::io::ErrorKind::WouldBlock
    );
}

#[test]
fn link_session_invalid_url_is_a_configuration_error() {
    let config = tempfile::tempdir().unwrap();
    let output = run(
        config.path(),
        "not-a-url",
        "http://127.0.0.1:1/api/v1",
        false,
    );
    assert_eq!(output.status.code(), Some(2));
    let error: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(error["code"], "config_invalid");
    assert!(error["hint"].as_str().unwrap().contains("/api/v1"));
}
