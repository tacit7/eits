use crate::error::EitsError;
use std::path::Path;

#[derive(Debug, Clone)]
pub struct Config {
    pub base_url: String,
    pub api_key: Option<String>,
    pub session_uuid: Option<String>,
    pub session_id: Option<String>,
    // Consumed once commands need project scoping (later task).
    #[allow(dead_code)]
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
        } else {
            fallback_env_file_or_default(config_dir)?
        };
        Ok(Self {
            base_url,
            api_key: env("EITS_API_KEY"),
            session_uuid: env("EITS_SESSION_UUID"),
            session_id: env("EITS_SESSION_ID"),
            project_id: env("EITS_PROJECT_ID"),
        })
    }

    #[allow(dead_code)]
    pub fn session_identity(&self) -> Option<&str> {
        self.session_uuid.as_deref().or(self.session_id.as_deref())
    }
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
