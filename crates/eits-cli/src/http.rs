use crate::config::Config;
use crate::error::{code_for_status, EitsError};
use serde_json::Value;
use std::time::Duration;

pub struct Client {
    cfg: Config,
    http: reqwest::blocking::Client,
}

impl Client {
    pub fn new(cfg: Config) -> Self {
        let http = reqwest::blocking::Client::builder()
            .timeout(Duration::from_secs(10))
            .connect_timeout(Duration::from_secs(10))
            .danger_accept_invalid_certs(true) // parity with bash `curl -k`
            .build()
            .expect("client");
        Self { cfg, http }
    }

    pub fn get(&self, pq: &str) -> Result<Value, EitsError> {
        self.send(reqwest::Method::GET, pq, None)
    }
    /// GET with a per-request timeout override, no retries. Used for long-poll
    /// endpoints (e.g. `/dm/wait`) where the server intentionally holds the
    /// connection open past the default 10s client timeout.
    pub fn get_long_poll(&self, pq: &str, timeout: Duration) -> Result<Value, EitsError> {
        self.send_once(reqwest::Method::GET, pq, None, timeout)
    }
    pub fn post(&self, p: &str, b: Value) -> Result<Value, EitsError> {
        self.send(reqwest::Method::POST, p, Some(b))
    }
    pub fn patch(&self, p: &str, b: Value) -> Result<Value, EitsError> {
        self.send(reqwest::Method::PATCH, p, Some(b))
    }
    pub fn delete(&self, p: &str) -> Result<Value, EitsError> {
        self.send(reqwest::Method::DELETE, p, None)
    }

    fn send(
        &self,
        method: reqwest::Method,
        path: &str,
        body: Option<Value>,
    ) -> Result<Value, EitsError> {
        let url = format!("{}{}", self.cfg.base_url, path);
        let base_ms: u64 = std::env::var("EITS_RETRY_BASE_MS")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(2000);
        let mut delay_ms = base_ms;
        for attempt in 0..4 {
            let mut req = self.http.request(method.clone(), &url);
            if let Some(k) = &self.cfg.api_key {
                req = req.bearer_auth(k);
            }
            if let Some(u) = &self.cfg.session_uuid {
                req = req
                    .header("x-eits-role", "orchestrator")
                    .header("x-eits-session", u);
            }
            if let Some(b) = &body {
                req = req.json(b);
            }
            match req.send() {
                Ok(resp) => {
                    let status = resp.status().as_u16();
                    if matches!(status, 429 | 502 | 503 | 504) && attempt < 3 {
                        eprintln!("[eits] {status}, retrying in {}ms...", jitter(delay_ms));
                        std::thread::sleep(Duration::from_millis(jitter(delay_ms)));
                        delay_ms = (delay_ms * 2).min(30_000);
                        continue;
                    }
                    let text = resp.text().unwrap_or_default();
                    if status >= 400 {
                        return Err(status_error(status, &text));
                    }
                    return serde_json::from_str(&text).map_err(|_| {
                        EitsError::api(
                            format!(
                                "non-JSON response: {}",
                                text.chars().take(200).collect::<String>()
                            ),
                            crate::error::Code::ServerError,
                            Some(status),
                        )
                    });
                }
                Err(e) if (e.is_connect() || e.is_timeout()) && attempt < 3 => {
                    eprintln!(
                        "[eits] connection error, retrying in {}ms... (server restarting?)",
                        jitter(delay_ms)
                    );
                    std::thread::sleep(Duration::from_millis(jitter(delay_ms)));
                    delay_ms = (delay_ms * 2).min(30_000);
                }
                Err(e) => {
                    return Err(EitsError::api(
                        format!("cannot reach {url}: {e}"),
                        crate::error::Code::ConnectionFailed,
                        None,
                    )
                    .with_hint("is the EITS server running? (mix phx.server, or set EITS_URL)"));
                }
            }
        }
        Err(EitsError::api(
            format!("cannot reach {url} after 4 attempts"),
            crate::error::Code::ConnectionFailed,
            None,
        )
        .with_hint("is the EITS server running? (mix phx.server, or set EITS_URL)"))
    }

    /// Single attempt, no retry-with-backoff loop — the caller (a long-poll)
    /// is already blocking for `timeout`, so retrying on top would just stack
    /// waits. Still maps connect/timeout errors the same way `send` does.
    fn send_once(
        &self,
        method: reqwest::Method,
        path: &str,
        body: Option<Value>,
        timeout: Duration,
    ) -> Result<Value, EitsError> {
        let url = format!("{}{}", self.cfg.base_url, path);
        let mut req = self.http.request(method, &url).timeout(timeout);
        if let Some(k) = &self.cfg.api_key {
            req = req.bearer_auth(k);
        }
        if let Some(u) = &self.cfg.session_uuid {
            req = req
                .header("x-eits-role", "orchestrator")
                .header("x-eits-session", u);
        }
        if let Some(b) = &body {
            req = req.json(b);
        }
        match req.send() {
            Ok(resp) => {
                let status = resp.status().as_u16();
                let text = resp.text().unwrap_or_default();
                if status >= 400 {
                    return Err(status_error(status, &text));
                }
                serde_json::from_str(&text).map_err(|_| {
                    EitsError::api(
                        format!(
                            "non-JSON response: {}",
                            text.chars().take(200).collect::<String>()
                        ),
                        crate::error::Code::ServerError,
                        Some(status),
                    )
                })
            }
            Err(e) => Err(EitsError::api(
                format!("cannot reach {url}: {e}"),
                crate::error::Code::ConnectionFailed,
                None,
            )
            .with_hint("is the EITS server running? (mix phx.server, or set EITS_URL)")),
        }
    }
}

fn jitter(ms: u64) -> u64 {
    use rand::Rng;
    let pct: i64 = rand::thread_rng().gen_range(-20..=20);
    ((ms as i64) + (ms as i64) * pct / 100).max(1) as u64
}

fn status_error(status: u16, body: &str) -> EitsError {
    let code = code_for_status(status);
    let msg = serde_json::from_str::<Value>(body)
        .ok()
        .and_then(|v| {
            v.get("error")
                .or(v.get("message"))
                .and_then(|m| m.as_str())
                .map(String::from)
        })
        .unwrap_or_else(|| {
            if body.contains("<html") || body.contains("<!DOCTYPE") {
                "server returned HTML — check server logs".into()
            } else {
                body.chars().take(300).collect()
            }
        });
    EitsError::api(msg, code, Some(status))
}
