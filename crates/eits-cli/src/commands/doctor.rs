use crate::config::Config;
use crate::http::Client;
use crate::output;
use serde_json::{json, Value};
use std::path::PathBuf;
use std::process::Command as StdCommand;

pub fn run(pretty: bool) {
    let mut warnings: Vec<String> = Vec::new();
    let cfg_result = Config::resolve();

    let config = match &cfg_result {
        Ok(cfg) => json!({
            "ok": true,
            "base_url": cfg.base_url,
            "base_url_source": config_source("EITS_URL"),
            "project_id": present_secretless(&cfg.project_id),
            "project_id_source": config_source("EITS_PROJECT_ID"),
        }),
        Err(err) => {
            warnings.push(format!("config: {}", err.message));
            json!({
                "ok": false,
                "error": err.message,
                "hint": err.hint,
            })
        }
    };

    let identity = match &cfg_result {
        Ok(cfg) => json!({
            "session_uuid": present_secretless(&cfg.session_uuid),
            "session_uuid_source": config_source("EITS_SESSION_UUID"),
            "session_id": present_secretless(&cfg.session_id),
            "session_id_source": config_source("EITS_SESSION_ID"),
            "agent_uuid": present_secretless(&cfg.agent_uuid),
            "agent_uuid_source": config_source("EITS_AGENT_UUID"),
            "has_session_identity": cfg.session_identity().is_some(),
            "has_agent_identity": cfg.agent_uuid.is_some(),
        }),
        Err(_) => json!({
            "has_session_identity": false,
            "has_agent_identity": false,
        }),
    };

    let server = match &cfg_result {
        Ok(cfg) => {
            let client = Client::new(cfg.clone());
            match client.get("/sessions?limit=1") {
                Ok(_) => json!({ "ok": true, "checked": "GET /sessions?limit=1" }),
                Err(err) => {
                    warnings.push(format!("server: {}", err.message));
                    json!({
                        "ok": false,
                        "checked": "GET /sessions?limit=1",
                        "error": err.message,
                        "hint": err.hint,
                    })
                }
            }
        }
        Err(_) => json!({ "ok": false, "checked": false }),
    };

    let git = git_report();
    if !git["inside_repo"].as_bool().unwrap_or(false) {
        warnings.push("git: current directory is not inside a git repository".into());
    }

    let hooks = hooks_report();
    if !hooks["has_any_registration"].as_bool().unwrap_or(false) {
        warnings.push("hooks: no EITS hook registration found".into());
    }

    let capabilities = match &cfg_result {
        Ok(cfg) => capabilities_report(cfg),
        Err(_) => json!({
            "tasks": false,
            "notes": false,
            "commits": false,
            "dms": false,
        }),
    };

    let status = if warnings.is_empty() { "ok" } else { "warn" };
    let suggested_next_command = suggested_next_command(&warnings, &capabilities);

    output::print_json(
        &json!({
            "status": status,
            "checks": {
                "config": config,
                "identity": identity,
                "server": server,
                "git": git,
                "hooks": hooks,
                "capabilities": capabilities,
            },
            "warnings": warnings,
            "suggested_next_command": suggested_next_command,
        }),
        pretty,
    );
}

fn capabilities_report(cfg: &Config) -> Value {
    let has_session = cfg.session_identity().is_some();
    let has_agent = cfg.agent_uuid.is_some();
    json!({
        "tasks": has_session,
        "notes": has_session,
        "commits": has_session || has_agent,
        "dms": has_session,
    })
}

fn suggested_next_command(warnings: &[String], capabilities: &Value) -> String {
    if warnings.iter().any(|w| w.starts_with("server:")) {
        "start EITS or set EITS_URL".into()
    } else if warnings.iter().any(|w| w.starts_with("hooks:")) {
        "eits hooks install --project".into()
    } else if !capabilities["commits"].as_bool().unwrap_or(false) {
        "eits whoami".into()
    } else {
        "eits workflow status".into()
    }
}

fn present_secretless(value: &Option<String>) -> Value {
    match value {
        Some(value) if !value.is_empty() => json!(value),
        _ => Value::Null,
    }
}

fn config_source(key: &str) -> Value {
    if std::env::var(key).ok().filter(|v| !v.is_empty()).is_some() {
        return json!("process_env");
    }
    if codex_env_file().is_some_and(|path| env_file_contains(&path, key)) {
        return json!("codex_env_file");
    }
    if key == "EITS_URL" {
        if config_dir().join("desktop.json").exists() {
            return json!("desktop_json_or_fallback");
        }
        if config_dir().join(".env").exists() {
            return json!("config_env_file_or_default");
        }
        return json!("default");
    }
    Value::Null
}

fn codex_env_file() -> Option<PathBuf> {
    std::env::var("EITS_CODEX_ENV_FILE")
        .ok()
        .map(PathBuf::from)
        .or_else(|| {
            let session_id = std::env::var("EITS_CODEX_SESSION_ID")
                .or_else(|_| std::env::var("CODEX_THREAD_ID"))
                .or_else(|_| std::env::var("CODEX_SESSION_ID"))
                .ok()?;
            let home = std::env::var("HOME").ok()?;
            Some(
                PathBuf::from(home)
                    .join(".eits")
                    .join("codex")
                    .join("sessions")
                    .join(format!("{}.env", safe_session_id(&session_id))),
            )
        })
}

fn safe_session_id(session_id: &str) -> String {
    session_id
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || matches!(c, '_' | '.' | '-') {
                c
            } else {
                '_'
            }
        })
        .collect()
}

fn env_file_contains(path: &PathBuf, key: &str) -> bool {
    std::fs::read_to_string(path)
        .map(|raw| {
            raw.lines().map(str::trim).any(|line| {
                line.starts_with(&format!("{key}=")) || line.starts_with(&format!("export {key}="))
            })
        })
        .unwrap_or(false)
}

fn config_dir() -> PathBuf {
    std::env::var("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            PathBuf::from(std::env::var("HOME").unwrap_or_default()).join(".config")
        })
        .join("eits")
}

fn git_report() -> Value {
    let root = git_stdout(&["rev-parse", "--show-toplevel"]);
    json!({
        "inside_repo": root.is_some(),
        "root": root,
        "branch": git_stdout(&["rev-parse", "--abbrev-ref", "HEAD"]),
        "head": git_stdout(&["rev-parse", "HEAD"]),
        "project_id": std::env::var("EITS_PROJECT_ID").ok(),
    })
}

fn hooks_report() -> Value {
    let home = std::env::var("HOME").unwrap_or_default();
    let global_settings = PathBuf::from(&home).join(".claude").join("settings.json");
    let project_settings = std::env::current_dir()
        .unwrap_or_default()
        .join(".claude")
        .join("settings.local.json");
    let codex_hooks = std::env::current_dir()
        .unwrap_or_default()
        .join(".codex")
        .join("hooks.json");
    let scripts_dir = config_dir().join("hooks");
    let global_registered = file_mentions_eits(&global_settings);
    let project_registered = file_mentions_eits(&project_settings);
    let codex_registered = codex_hooks.exists();
    json!({
        "scripts_dir": scripts_dir,
        "scripts_installed": scripts_dir.is_dir(),
        "global_settings": global_settings,
        "global_registered": global_registered,
        "project_settings": project_settings,
        "project_registered": project_registered,
        "codex_hooks": codex_hooks,
        "codex_registered": codex_registered,
        "has_any_registration": global_registered || project_registered || codex_registered,
    })
}

fn file_mentions_eits(path: &PathBuf) -> bool {
    std::fs::read_to_string(path)
        .map(|raw| raw.contains("eits") || raw.contains("/api/v1/iam/hook"))
        .unwrap_or(false)
}

fn git_stdout(args: &[&str]) -> Option<String> {
    let output = StdCommand::new("git").args(args).output().ok()?;
    if !output.status.success() {
        return None;
    }
    let text = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if text.is_empty() {
        None
    } else {
        Some(text)
    }
}
