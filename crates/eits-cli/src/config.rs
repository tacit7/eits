use crate::error::EitsError;
use std::collections::HashMap;
use std::path::Path;

#[derive(Debug, Clone)]
pub struct Config {
    pub base_url: String,
    pub api_key: Option<String>,
    pub session_uuid: Option<String>,
    pub session_id: Option<String>,
    pub agent_uuid: Option<String>,
    pub project_id: Option<String>,
}

impl Config {
    pub fn resolve() -> Result<Self, EitsError> {
        let cfg_dir = std::env::var("XDG_CONFIG_HOME")
            .map(std::path::PathBuf::from)
            .unwrap_or_else(|_| {
                std::path::PathBuf::from(std::env::var("HOME").unwrap_or_default()).join(".config")
            })
            .join("eits");
        Self::resolve_from(&|k| std::env::var(k).ok(), &cfg_dir)
    }

    pub fn resolve_from(
        env: &dyn Fn(&str) -> Option<String>,
        config_dir: &Path,
    ) -> Result<Self, EitsError> {
        let codex_env = load_codex_env(env);
        let base_url = if let Some(url) = env("EITS_URL") {
            validate_url(&url)?
        } else if config_dir.join("desktop.json").exists() {
            let raw = std::fs::read_to_string(config_dir.join("desktop.json"))
                .map_err(|e| EitsError::config(format!("cannot read desktop.json: {e}")))?;
            let v: serde_json::Value = serde_json::from_str(&raw).map_err(|e| {
                EitsError::config(format!("invalid JSON in desktop.json: {e}"))
                    .with_hint("fix or delete ~/.config/eits/desktop.json")
            })?;
            match v.get("port").and_then(|p| p.as_u64()) {
                // Bash rejects ports outside 1024-49151; an in-range port
                // builds the URL, an out-of-range one falls through silently
                // (matching bash's silent-skip), same as no "port" key at all.
                Some(port) if (1024..=49151).contains(&port) => {
                    format!("http://localhost:{port}/api/v1")
                }
                _ => fallback_env_file_or_default(config_dir)?,
            }
        } else if let Some(url) = codex_env.get("EITS_URL") {
            validate_url(url)?
        } else {
            fallback_env_file_or_default(config_dir)?
        };
        Ok(Self {
            base_url,
            api_key: env("EITS_API_KEY").or_else(|| codex_env.get("EITS_API_KEY").cloned()),
            session_uuid: env_or_codex(env, &codex_env, "EITS_SESSION_UUID"),
            session_id: env_or_codex(env, &codex_env, "EITS_SESSION_ID"),
            agent_uuid: env_or_codex(env, &codex_env, "EITS_AGENT_UUID"),
            project_id: env_or_codex(env, &codex_env, "EITS_PROJECT_ID"),
        })
    }

    pub fn session_identity(&self) -> Option<&str> {
        self.session_uuid.as_deref().or(self.session_id.as_deref())
    }
}

fn env_or_codex(
    env: &dyn Fn(&str) -> Option<String>,
    codex_env: &HashMap<String, String>,
    key: &str,
) -> Option<String> {
    env(key).or_else(|| codex_env.get(key).cloned())
}

fn load_codex_env(env: &dyn Fn(&str) -> Option<String>) -> HashMap<String, String> {
    let path = env("EITS_CODEX_ENV_FILE")
        .map(std::path::PathBuf::from)
        .or_else(|| {
            let session_id = env("EITS_CODEX_SESSION_ID")
                .or_else(|| env("CODEX_THREAD_ID"))
                .or_else(|| env("CODEX_SESSION_ID"));
            session_id.and_then(|session_id| {
                env("HOME").map(|home| {
                    std::path::PathBuf::from(home)
                        .join(".eits")
                        .join("codex")
                        .join("sessions")
                        .join(format!("{}.env", safe_session_id(&session_id)))
                })
            })
        });
    let Some(path) = path else {
        return HashMap::new();
    };
    let Ok(raw) = std::fs::read_to_string(path) else {
        return HashMap::new();
    };

    raw.lines()
        .filter_map(parse_env_line)
        .filter(|(key, _)| key.starts_with("EITS_"))
        .collect()
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

fn parse_env_line(line: &str) -> Option<(String, String)> {
    let line = line.trim();
    if line.is_empty() || line.starts_with('#') {
        return None;
    }
    let line = line.strip_prefix("export ").unwrap_or(line);
    let (key, value) = line.split_once('=')?;
    let key = key.trim();
    if key.is_empty() {
        return None;
    }
    Some((key.to_string(), unquote_env_value(value.trim())))
}

fn unquote_env_value(value: &str) -> String {
    if value.len() >= 2 {
        let first = value.as_bytes()[0];
        let last = value.as_bytes()[value.len() - 1];
        if (first == b'\'' && last == b'\'') || (first == b'"' && last == b'"') {
            return value[1..value.len() - 1].to_string();
        }
    }
    value.replace("\\ ", " ")
}

fn fallback_env_file_or_default(config_dir: &Path) -> Result<String, EitsError> {
    let env_file = config_dir.join(".env");
    if let Ok(raw) = std::fs::read_to_string(&env_file) {
        if let Some(line) = raw.lines().find(|l| l.starts_with("EITS_URL=")) {
            return validate_url(line.trim_start_matches("EITS_URL="));
        }
    }
    Ok("http://localhost:5001/api/v1".to_string())
}

fn validate_url(url: &str) -> Result<String, EitsError> {
    let trimmed = url.trim_end_matches('/').to_string();
    if !(trimmed.starts_with("http://") || trimmed.starts_with("https://")) || trimmed.contains(' ')
    {
        return Err(
            EitsError::config(format!("invalid EITS_URL: {url}")).with_hint(
                "expected full base URL including /api/v1, e.g. http://localhost:5001/api/v1",
            ),
        );
    }
    Ok(trimmed)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn env<'a>(pairs: &'a [(&'a str, &'a str)]) -> impl Fn(&str) -> Option<String> + 'a {
        move |k| {
            pairs
                .iter()
                .find(|(n, _)| *n == k)
                .map(|(_, v)| v.to_string())
        }
    }

    #[test]
    fn eits_url_env_wins_and_trailing_slash_trimmed() {
        let d = tempfile::tempdir().unwrap();
        let c =
            Config::resolve_from(&env(&[("EITS_URL", "http://x:9/api/v1/")]), d.path()).unwrap();
        assert_eq!(c.base_url, "http://x:9/api/v1");
    }
    #[test]
    fn malformed_eits_url_is_config_error() {
        let d = tempfile::tempdir().unwrap();
        let e = Config::resolve_from(&env(&[("EITS_URL", "not a url")]), d.path()).unwrap_err();
        assert_eq!(e.exit_code(), 2);
    }
    #[test]
    fn desktop_json_port_builds_url() {
        let d = tempfile::tempdir().unwrap();
        std::fs::write(d.path().join("desktop.json"), r#"{"port": 34877}"#).unwrap();
        let c = Config::resolve_from(&env(&[]), d.path()).unwrap();
        assert_eq!(c.base_url, "http://localhost:34877/api/v1");
    }
    #[test]
    fn invalid_desktop_json_is_config_error_not_silent_skip() {
        let d = tempfile::tempdir().unwrap();
        std::fs::write(d.path().join("desktop.json"), "{oops").unwrap();
        assert_eq!(
            Config::resolve_from(&env(&[]), d.path())
                .unwrap_err()
                .exit_code(),
            2
        );
    }
    #[test]
    fn out_of_range_port_falls_through_silently() {
        let d = tempfile::tempdir().unwrap();
        std::fs::write(d.path().join("desktop.json"), r#"{"port": 70000}"#).unwrap();
        let c = Config::resolve_from(&env(&[]), d.path()).unwrap();
        assert_eq!(c.base_url, "http://localhost:5001/api/v1");
    }
    #[test]
    fn env_file_url_then_default() {
        let d = tempfile::tempdir().unwrap();
        std::fs::write(
            d.path().join(".env"),
            "FOO=1\nEITS_URL=http://y:5001/api/v1\n",
        )
        .unwrap();
        let c = Config::resolve_from(&env(&[]), d.path()).unwrap();
        assert_eq!(c.base_url, "http://y:5001/api/v1");
        let d2 = tempfile::tempdir().unwrap();
        let c2 = Config::resolve_from(&env(&[]), d2.path()).unwrap();
        assert_eq!(c2.base_url, "http://localhost:5001/api/v1");
    }
    #[test]
    fn explicit_codex_env_file_provides_identity_fallbacks() {
        let cfg = tempfile::tempdir().unwrap();
        let home = tempfile::tempdir().unwrap();
        let codex_dir = home.path().join(".eits").join("codex");
        std::fs::create_dir_all(&codex_dir).unwrap();
        let env_file = codex_dir.join("custom.env");
        std::fs::write(
            &env_file,
            "export EITS_URL=http://codex:5001/api/v1\n\
             export EITS_SESSION_UUID=thr_123\n\
             export EITS_SESSION_ID=42\n\
             export EITS_AGENT_UUID=agent-uuid\n\
             export EITS_AGENT_ID=17\n\
             export EITS_PROJECT_ID=9\n",
        )
        .unwrap();

        let env_file_str = env_file.to_string_lossy().to_string();
        let c = Config::resolve_from(&env(&[("EITS_CODEX_ENV_FILE", &env_file_str)]), cfg.path())
            .unwrap();

        assert_eq!(c.base_url, "http://codex:5001/api/v1");
        assert_eq!(c.session_uuid.as_deref(), Some("thr_123"));
        assert_eq!(c.session_id.as_deref(), Some("42"));
        assert_eq!(c.agent_uuid.as_deref(), Some("agent-uuid"));
        assert_eq!(c.project_id.as_deref(), Some("9"));
    }
    #[test]
    fn codex_session_id_selects_session_specific_env_file() {
        let cfg = tempfile::tempdir().unwrap();
        let home = tempfile::tempdir().unwrap();
        let sessions_dir = home.path().join(".eits").join("codex").join("sessions");
        std::fs::create_dir_all(&sessions_dir).unwrap();
        std::fs::write(
            sessions_dir.join("thr_123.env"),
            "export EITS_SESSION_UUID=thr_123\nexport EITS_AGENT_UUID=agent-uuid\n",
        )
        .unwrap();

        let home_str = home.path().to_string_lossy().to_string();
        let c = Config::resolve_from(
            &env(&[("HOME", &home_str), ("CODEX_THREAD_ID", "thr_123")]),
            cfg.path(),
        )
        .unwrap();

        assert_eq!(c.session_uuid.as_deref(), Some("thr_123"));
        assert_eq!(c.agent_uuid.as_deref(), Some("agent-uuid"));
    }
    #[test]
    fn codex_env_does_not_fall_back_to_current_file() {
        let cfg = tempfile::tempdir().unwrap();
        let home = tempfile::tempdir().unwrap();
        let codex_dir = home.path().join(".eits").join("codex");
        std::fs::create_dir_all(&codex_dir).unwrap();
        std::fs::write(
            codex_dir.join("current.env"),
            "export EITS_SESSION_UUID=from-current\nexport EITS_AGENT_UUID=agent-current\n",
        )
        .unwrap();

        let home_str = home.path().to_string_lossy().to_string();
        let c = Config::resolve_from(&env(&[("HOME", &home_str)]), cfg.path()).unwrap();

        assert_eq!(c.session_uuid, None);
        assert_eq!(c.agent_uuid, None);
    }
    #[test]
    fn process_env_wins_over_codex_env_file() {
        let cfg = tempfile::tempdir().unwrap();
        let home = tempfile::tempdir().unwrap();
        let codex_dir = home.path().join(".eits").join("codex").join("sessions");
        std::fs::create_dir_all(&codex_dir).unwrap();
        std::fs::write(
            codex_dir.join("thr_123.env"),
            "export EITS_SESSION_UUID=from-file\nexport EITS_AGENT_UUID=agent-file\n",
        )
        .unwrap();

        let home_str = home.path().to_string_lossy().to_string();
        let c = Config::resolve_from(
            &env(&[
                ("HOME", &home_str),
                ("CODEX_THREAD_ID", "thr_123"),
                ("EITS_SESSION_UUID", "from-env"),
                ("EITS_AGENT_UUID", "agent-env"),
            ]),
            cfg.path(),
        )
        .unwrap();

        assert_eq!(c.session_uuid.as_deref(), Some("from-env"));
        assert_eq!(c.agent_uuid.as_deref(), Some("agent-env"));
    }
    #[test]
    fn identity_prefers_uuid() {
        let d = tempfile::tempdir().unwrap();
        let c = Config::resolve_from(
            &env(&[("EITS_SESSION_UUID", "u-1"), ("EITS_SESSION_ID", "7")]),
            d.path(),
        )
        .unwrap();
        assert_eq!(c.session_identity(), Some("u-1"));
    }
}
