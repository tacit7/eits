use assert_cmd::Command;
use serde_json::Value;
use std::os::unix::fs::PermissionsExt;

fn report(binary: &str, dir: &tempfile::TempDir, extras: &std::path::Path) -> Value {
    let out = Command::cargo_bin(binary)
        .unwrap()
        .env_clear()
        .env("HOME", dir.path())
        .env("PATH", dir.path())
        .env("EITS_EXTRAS", extras)
        .env("EITS_URL", "http://credential:secret@127.0.0.1:1")
        .env("EITS_API_TOKEN", "secret-token")
        .env("EITS_CODEX_ENV_FILE", dir.path().join("invalid.env"))
        .args(["doctor", "cli", "--pretty"])
        .assert()
        .success()
        .stderr("");
    let stdout = String::from_utf8(out.get_output().stdout.clone()).unwrap();
    assert!(!stdout.contains("secret"));
    serde_json::from_str(&stdout).unwrap()
}

#[test]
fn reports_binary_build_and_routing_without_running_fallback_or_loading_config() {
    let dir = tempfile::tempdir().unwrap();
    let extras = dir.path().join("eits-extras");
    std::fs::write(&extras, "#!/bin/sh\ntouch \"$HOME/executed\"\nexit 99\n").unwrap();
    std::fs::set_permissions(&extras, std::fs::Permissions::from_mode(0o755)).unwrap();
    for binary in ["eits", "eitsr"] {
        let v = report(binary, &dir, &extras);
        assert_eq!(v["implementation"], "rust");
        assert_eq!(v["version"], env!("CARGO_PKG_VERSION"));
        assert_eq!(
            v["executable"],
            assert_cmd::cargo::cargo_bin(binary)
                .canonicalize()
                .unwrap()
                .to_str()
                .unwrap()
        );
        assert_eq!(v["fallback"]["available"], true);
        assert_eq!(v["fallback"]["source"], "EITS_EXTRAS");
        assert_eq!(v["fallback"]["path"], extras.to_str().unwrap());
        assert_eq!(v["fallback"]["executed"], false);
        assert!(v["command_families"]["rust"]
            .as_array()
            .unwrap()
            .contains(&serde_json::json!("doctor")));
        assert!(v["command_families"]["legacy"]
            .as_array()
            .unwrap()
            .contains(&serde_json::json!("agents")));
        assert!(!dir.path().join("executed").exists());
    }
}

#[test]
fn invalid_override_is_reported_without_disclosing_its_value() {
    let dir = tempfile::tempdir().unwrap();
    let v = report("eits", &dir, &dir.path().join("secret-token"));
    assert_eq!(v["fallback"]["available"], false);
    assert_eq!(v["fallback"]["path"], Value::Null);
    assert_eq!(v["fallback"]["error"], "extras_not_found");
}

#[test]
fn discovery_matches_delegation_precedence_and_handles_missing_fallback() {
    let dir = tempfile::tempdir().unwrap();
    let bin = dir.path().join("bin");
    let libexec = dir.path().join("libexec");
    let path_dir = dir.path().join("path");
    for p in [&bin, &libexec, &path_dir] {
        std::fs::create_dir(p).unwrap();
    }
    let executable = bin.join("eits");
    std::fs::copy(assert_cmd::cargo::cargo_bin("eits"), &executable).unwrap();
    let run = || {
        let out = Command::new(&executable)
            .env_clear()
            .env("PATH", &path_dir)
            .args(["doctor", "cli"])
            .assert()
            .success()
            .stderr("");
        serde_json::from_slice::<Value>(&out.get_output().stdout).unwrap()
    };
    assert_eq!(run()["fallback"]["available"], false);
    for (path, source) in [
        (path_dir.join("eits-extras"), "PATH"),
        (bin.join("eits-extras"), "sibling"),
        (libexec.join("eits-extras"), "libexec"),
    ] {
        std::fs::write(&path, "#!/bin/sh\nexit 99\n").unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).unwrap();
        let v = run();
        assert_eq!(v["fallback"]["source"], source);
        assert_eq!(
            std::path::Path::new(v["fallback"]["path"].as_str().unwrap())
                .canonicalize()
                .unwrap(),
            path.canonicalize().unwrap()
        );
    }
    // An invalid explicit override must not silently select a lower-priority candidate.
    let out = Command::new(&executable)
        .env_clear()
        .env("PATH", path_dir)
        .env("EITS_EXTRAS", dir.path().join("missing"))
        .args(["doctor", "cli"])
        .assert()
        .success();
    let v: Value = serde_json::from_slice(&out.get_output().stdout).unwrap();
    assert_eq!(v["fallback"]["available"], false);
}
