use std::io::{BufRead, BufReader, Write};
use std::net::TcpListener;
use std::process::{Command, Output};
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};
use std::time::Duration;

// Child-only environment keeps parallel tests independent and excludes real credentials.
fn run(url: &str, retry: Option<&str>) -> Output {
    let config = tempfile::tempdir().unwrap();
    let mut cmd = Command::new(env!("CARGO_BIN_EXE_eits"));
    cmd.env_clear()
        .env("XDG_CONFIG_HOME", config.path())
        .env("EITS_URL", url)
        .env("EITS_API_KEY", "retry-test-secret")
        .env("EITS_RETRY_BASE_MS", "1")
        .args(["tasks", "list", "--all"]);
    if let Some(value) = retry {
        cmd.env("EITS_RETRY", value);
    }
    cmd.output().unwrap()
}

fn check_output(output: &Output, exit: i32, code: &str, retries: usize) {
    assert_eq!(output.status.code(), Some(exit));
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(json["code"], code);
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert_eq!(stderr.matches("retrying in").count(), retries);
    for bytes in [&output.stdout, &output.stderr] {
        assert!(!String::from_utf8_lossy(bytes).contains("retry-test-secret"));
    }
}

// Keep accepting until the CLI exits so unexpected extra attempts are counted
// instead of hanging a fixed-length mock response queue.
fn http_failure(status: u16, retry: Option<&str>) -> (Output, usize) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    listener.set_nonblocking(true).unwrap();
    let url = format!("http://{}/api/v1", listener.local_addr().unwrap());
    let done = Arc::new(AtomicBool::new(false));
    let stop = done.clone();
    let server = std::thread::spawn(move || {
        let mut attempts = 0;
        while !stop.load(Ordering::SeqCst) {
            match listener.accept() {
                Ok((mut stream, _)) => {
                    stream.set_nonblocking(false).unwrap();
                    stream
                        .set_read_timeout(Some(Duration::from_secs(5)))
                        .unwrap();
                    let mut reader = BufReader::new(stream.try_clone().unwrap());
                    loop {
                        let mut line = String::new();
                        if reader.read_line(&mut line).unwrap() == 0 || line == "\r\n" {
                            break;
                        }
                    }
                    attempts += 1;
                    let body = r#"{"error":"test failure"}"#;
                    write!(stream, "HTTP/1.1 {status} Test\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}", body.len()).unwrap();
                }
                Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                    std::thread::sleep(Duration::from_millis(1));
                }
                Err(e) => panic!("mock accept failed: {e}"),
            }
        }
        attempts
    });
    let output = run(&url, retry);
    done.store(true, Ordering::SeqCst);
    (output, server.join().unwrap())
}

#[test]
fn opt_out_makes_one_attempt_for_every_retryable_status() {
    for status in [429, 502, 503, 504] {
        let (output, attempts) = http_failure(status, Some("0"));
        assert_eq!(attempts, 1, "status {status}");
        check_output(&output, 1, "server_error", 0);
        let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
        assert_eq!(json["status"], status);
    }
}

#[test]
fn default_and_nonzero_values_preserve_four_attempts() {
    for retry in [None, Some("1"), Some(""), Some("false")] {
        for status in [429, 502, 503, 504] {
            let (output, attempts) = http_failure(status, retry);
            assert_eq!(attempts, 4, "status {status}, retry {retry:?}");
            check_output(&output, 1, "server_error", 3);
        }
    }
}

#[test]
fn refused_connection_opt_out_skips_all_backoff_and_preserves_exit_three() {
    // Reserve an unused local address, then close it to produce connection refused.
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}/api/v1", listener.local_addr().unwrap());
    drop(listener);
    check_output(&run(&url, Some("0")), 3, "connection_failed", 0);
    check_output(&run(&url, None), 3, "connection_failed", 3);
}

#[test]
fn nonretryable_http_errors_still_make_one_attempt() {
    for retry in [None, Some("0")] {
        let (output, attempts) = http_failure(401, retry);
        assert_eq!(attempts, 1);
        check_output(&output, 1, "unauthorized", 0);
    }
}
