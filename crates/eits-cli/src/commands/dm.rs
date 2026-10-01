use super::{items_and_count, uri_encode};
use crate::config::Config;
use crate::error::EitsError;
use crate::http::Client;
use crate::output;
use serde_json::{json, Value};
use std::collections::HashSet;

#[derive(clap::Subcommand)]
pub enum DmCmd {
    /// Show inbound DMs for a session (alias: list)
    #[command(alias = "list")]
    Inbox {
        #[arg(short = 's', long)]
        session: Option<String>,
        #[arg(short = 'f', long)]
        from: Option<String>,
        #[arg(short = 'l', long, short_alias = 'n')]
        limit: Option<String>,
        #[arg(long)]
        since: Option<String>,
        /// Fetch DMs since the session's actual started_at (default unless --since is set).
        #[arg(long = "since-session")]
        since_session: bool,
        /// Fetch all available history without a session-start cutoff.
        #[arg(long, conflicts_with_all = ["since", "since_session", "strict"])]
        all_time: bool,
        /// Fail instead of fetching DMs when the session start cannot be resolved.
        #[arg(long, requires = "since_session")]
        strict: bool,
        #[arg(long = "team-only")]
        team_only: bool,
        /// Accepted for muscle-memory parity with bash; Rust output is always JSON.
        #[arg(short = 'j', long = "json")]
        json_flag: bool,
    },
    /// Fetch one DM by id (full body)
    Read {
        id: String,
        /// Accepted for muscle-memory parity with bash; Rust output is always JSON.
        #[arg(short = 'j', long = "json")]
        json_flag: bool,
    },
    /// Block until the next inbound DM arrives (or timeout), then print and exit.
    ///
    /// Meant for a background process that wants to be woken by a DM rather
    /// than interval-polling `dm inbox`: launch `eits dm wait` detached, and
    /// let its exit re-trigger whatever's watching for it. Exits 0 on arrival
    /// (with the DM as `items`) and 0 on timeout (`{"items":[],"count":0}`)
    /// so a shell `until` loop can re-invoke it freely.
    Wait {
        #[arg(short = 's', long)]
        session: Option<String>,
        #[arg(long)]
        since: Option<String>,
        /// Fetch DMs since the selected session's actual started_at timestamp.
        #[arg(long = "since-session")]
        since_session: bool,
        /// Fail instead of fetching DMs when the session start cannot be resolved.
        #[arg(long, requires = "since_session")]
        strict: bool,
        /// Only keep DMs from sessions that share a team with the current agent.
        #[arg(long = "team-only")]
        team_only: bool,
        /// Seconds to block for; passed straight to the server, which caps it.
        #[arg(short = 't', long, default_value = "25")]
        timeout: u64,
    },
    /// Continuously stream new inbound DMs, reconnecting after transient failures.
    Watch {
        #[arg(short = 's', long)]
        session: Option<String>,
        #[arg(long, conflicts_with = "since_session")]
        since: Option<String>,
        /// Start at the session's actual started_at (also the default).
        #[arg(long = "since-session")]
        since_session: bool,
        /// Only emit DMs from the current agent's team members.
        #[arg(long = "team-only")]
        team_only: bool,
        /// JSONL emits one DM per line; JSON emits an items/count envelope per line.
        #[arg(long, value_enum, default_value = "jsonl")]
        format: WatchFormat,
        /// Server long-poll duration in seconds.
        #[arg(short = 't', long, default_value = "25", value_parser = clap::value_parser!(u64).range(1..=55))]
        timeout: u64,
    },
}

#[derive(Clone, Copy, clap::ValueEnum)]
pub enum WatchFormat {
    Jsonl,
    Json,
}

/// Bash `_dm_post` payload shape: `{from_session_id, to_session_id, message,
/// response_required[, metadata]}`. Shared by `dm` send and `tasks complete
/// --notify` so both build the exact same body.
pub fn build_payload(
    from: &str,
    to: &str,
    message: &str,
    response_required: bool,
    metadata: Option<Value>,
) -> Value {
    let mut body = json!({
        "from_session_id": from,
        "to_session_id": to,
        "message": message,
        "response_required": response_required,
    });
    if let Some(m) = metadata {
        body["metadata"] = m;
    }
    body
}

/// Validates `--metadata`, resolves `--from` (default: session identity),
/// acquires the DM serialization lock around the POST only, and posts to
/// `/dm`. Shared by `dm` send and `tasks complete --notify`.
pub fn send_dm(
    client: &Client,
    cfg: &Config,
    to: &str,
    message: &str,
    from: Option<&str>,
    metadata: Option<&str>,
    response_required: bool,
) -> Result<Value, EitsError> {
    let from = from
        .map(String::from)
        .or_else(|| cfg.session_identity().map(String::from))
        .ok_or_else(|| {
            EitsError::usage("dm: --from is required (or set EITS_SESSION_UUID/EITS_SESSION_ID)")
        })?;
    let metadata_val = match metadata {
        Some(m) => Some(
            serde_json::from_str::<Value>(m)
                .map_err(|e| EitsError::usage(format!("--metadata must be valid JSON: {e}")))?,
        ),
        None => None,
    };
    let payload = build_payload(&from, to, message, response_required, metadata_val);
    let lock_identity = cfg.session_identity().unwrap_or("default");
    let _guard = crate::lock::DmLock::acquire(lock_identity)?;
    client.post("/dm", payload)
}

#[allow(clippy::too_many_arguments)]
pub fn run(
    client: &Client,
    cfg: &Config,
    cmd: Option<DmCmd>,
    to: Option<String>,
    message: Option<String>,
    from: Option<String>,
    metadata: Option<String>,
    response_required: bool,
    pretty: bool,
    quiet: bool,
) -> Result<(), EitsError> {
    match cmd {
        Some(DmCmd::Inbox {
            session,
            from,
            limit,
            since,
            since_session,
            all_time,
            strict,
            team_only,
            json_flag: _,
        }) => {
            let session = session
                .or_else(|| cfg.session_identity().map(|s| s.to_string()))
                .ok_or_else(|| {
                    EitsError::usage(
                        "dm inbox: session is required (pass --session or set EITS_SESSION_UUID/EITS_SESSION_ID)",
                    )
                })?;

            let use_session_start = since_session || (!all_time && since.is_none());
            let (since, warning) =
                resolve_since(client, &session, since, use_session_start, strict)?;

            let mut qs: Vec<(String, String)> = vec![
                ("session".into(), session),
                ("limit".into(), limit.unwrap_or_else(|| "20".into())),
            ];
            if let Some(f) = &from {
                qs.push(("from".into(), f.clone()));
            }
            if let Some(s) = &since {
                qs.push(("since".into(), uri_encode(s)));
            }
            let query_string = qs
                .iter()
                .map(|(k, v)| format!("{k}={v}"))
                .collect::<Vec<_>>()
                .join("&");
            let mut resp = client.get(&format!("/dm?{query_string}"))?;

            if team_only {
                if let Some(allowed) = team_allowlist(client, cfg) {
                    apply_team_filter(&mut resp, "messages", "from_session_id", &allowed);
                }
            }

            let mut result = items_and_count(&resp, &["messages"]);
            attach_warning(&mut result, warning);
            output::print_json(&result, pretty);
            Ok(())
        }

        Some(DmCmd::Read { id, json_flag: _ }) => {
            let qs = cfg
                .session_identity()
                .map(|s| format!("?session={s}"))
                .unwrap_or_default();
            let resp = client.get(&format!("/dm/{id}{qs}"))?;
            output::print_json(&resp, pretty);
            Ok(())
        }

        Some(DmCmd::Wait {
            session,
            since,
            since_session,
            strict,
            team_only,
            timeout,
        }) => {
            let session = session
                .or_else(|| cfg.session_identity().map(|s| s.to_string()))
                .ok_or_else(|| {
                    EitsError::usage(
                        "dm wait: session is required (pass --session or set EITS_SESSION_UUID/EITS_SESSION_ID)",
                    )
                })?;

            let (mut since, warning) =
                resolve_since(client, &session, since, since_session, strict)?;
            let allowed = if team_only {
                team_allowlist(client, cfg)
            } else {
                None
            };

            let deadline = std::time::Instant::now() + std::time::Duration::from_secs(timeout);
            let mut resp = loop {
                let remaining = deadline.saturating_duration_since(std::time::Instant::now());
                if remaining.is_zero() {
                    break json!({ "items": [], "count": 0 });
                }

                let wait_secs = remaining
                    .as_secs()
                    .saturating_add(u64::from(remaining.subsec_nanos() > 0))
                    .max(1)
                    .min(55);
                let mut qs: Vec<(String, String)> = vec![
                    ("session".into(), session.clone()),
                    ("timeout".into(), wait_secs.to_string()),
                ];
                if let Some(s) = &since {
                    qs.push(("since".into(), uri_encode(s)));
                }
                let query_string = qs
                    .iter()
                    .map(|(k, v)| format!("{k}={v}"))
                    .collect::<Vec<_>>()
                    .join("&");

                // Give the client generous headroom over the server-side wait so
                // the long-poll itself never gets cut short by our own timeout.
                let client_timeout = std::time::Duration::from_secs(wait_secs + 15);
                let mut resp =
                    client.get_long_poll(&format!("/dm/wait?{query_string}"), client_timeout)?;

                let Some(allowed) = &allowed else {
                    break resp;
                };

                let raw_count = resp
                    .get("items")
                    .and_then(|v| v.as_array())
                    .map(|items| items.len())
                    .unwrap_or(0);
                let next_since = resp
                    .get("items")
                    .and_then(|v| v.as_array())
                    .and_then(|items| items.last())
                    .and_then(|msg| msg.get("inserted_at"))
                    .and_then(|t| t.as_str())
                    .map(String::from);
                let filtered_count =
                    apply_team_filter(&mut resp, "items", "from_session_id", allowed);
                if filtered_count > 0 || raw_count == 0 {
                    break resp;
                }
                if let Some(next_since) = next_since {
                    since = Some(next_since);
                } else {
                    break resp;
                }
            };
            attach_warning(&mut resp, warning);
            output::print_json(&resp, pretty);
            Ok(())
        }

        Some(DmCmd::Watch {
            session,
            since,
            since_session: _,
            team_only,
            format,
            timeout,
        }) => watch(client, cfg, session, since, team_only, format, timeout),

        None => {
            let to = to.ok_or_else(|| EitsError::usage("dm: --to is required"))?;
            let message = message.ok_or_else(|| EitsError::usage("dm: --message is required"))?;
            let resp = send_dm(
                client,
                cfg,
                &to,
                &message,
                from.as_deref(),
                metadata.as_deref(),
                response_required,
            )?;
            if quiet {
                match resp.get("message_id") {
                    Some(id) => {
                        println!("{}", value_to_key(id));
                        Ok(())
                    }
                    None => Err(EitsError::usage(
                        "dm: --quiet requires a response with a message id",
                    )),
                }
            } else {
                output::print_json(&resp, pretty);
                Ok(())
            }
        }
    }
}

/// Resolve from session data, never agent creation or turn/activity timestamps.
/// Keep an explicit --since on best-effort failure, matching inbox's existing behavior.
fn resolve_since(
    client: &Client,
    session: &str,
    since: Option<String>,
    since_session: bool,
    strict: bool,
) -> Result<(Option<String>, Option<Value>), EitsError> {
    if !since_session {
        return Ok((since, None));
    }
    let response = client.get(&format!("/sessions/{}", uri_encode(session)));
    let timestamp = response.as_ref().ok().and_then(|v| {
        v.get("session")
            .unwrap_or(v)
            .get("started_at")
            .and_then(Value::as_str)
            .filter(|s| !s.trim().is_empty())
            .map(String::from)
    });
    if let Some(timestamp) = timestamp {
        return Ok((Some(timestamp), None));
    }
    let message = "--since-session: could not resolve session start timestamp (started_at)";
    if strict {
        return Err(EitsError::config(message)
            .with_hint("ensure the session API exposes started_at, or use an explicit --since without --since-session"));
    }
    let reason = match response {
        Ok(_) => json!("missing_started_at"),
        Err(err) => json!(err.code),
    };
    let warning = json!({
        "code": "session_start_unresolved",
        "message": message,
        "session": session,
        "reason": reason,
        "effective_since": since,
    });
    Ok((since, Some(warning)))
}

fn attach_warning(response: &mut Value, warning: Option<Value>) {
    if let Some(warning) = warning {
        response["warnings"] = json!([warning]);
    }
}

/// Port of bash `--team-only`: collect session ids of every member across
/// every team the given agent belongs to. Failures degrade to an empty
/// allow-list (matching bash's best-effort `|| _teams_json="{}"`).
fn resolve_team_session_ids(client: &Client, agent_uuid: &str) -> HashSet<String> {
    let mut allowed = HashSet::new();
    let teams_resp = client
        .get(&format!(
            "/teams?member_agent_uuid={}",
            uri_encode(agent_uuid)
        ))
        .unwrap_or_else(|_| json!({}));
    let Some(team_ids) = teams_resp.get("teams").and_then(|v| v.as_array()) else {
        return allowed;
    };
    for t in team_ids {
        let Some(tid) = t.get("id") else { continue };
        let tid = value_to_key(tid);
        if let Ok(members_resp) = client.get(&format!("/teams/{tid}/members")) {
            if let Some(members) = members_resp.get("members").and_then(|v| v.as_array()) {
                for m in members {
                    if let Some(sid) = m.get("session_id") {
                        allowed.insert(value_to_key(sid));
                    }
                }
            }
        }
    }
    allowed
}

fn team_allowlist(client: &Client, cfg: &Config) -> Option<HashSet<String>> {
    match &cfg.agent_uuid {
        None => {
            eprintln!("warning: --team-only requires EITS_AGENT_UUID; showing all DMs");
            None
        }
        Some(agent_uuid) => Some(resolve_team_session_ids(client, agent_uuid)),
    }
}

fn apply_team_filter(
    resp: &mut Value,
    collection_key: &str,
    session_key: &str,
    allowed: &HashSet<String>,
) -> usize {
    let Some(items) = resp.get(collection_key).and_then(|v| v.as_array()) else {
        return 0;
    };

    let filtered: Vec<Value> = items
        .iter()
        .filter(|m| {
            m.get(session_key)
                .map(|fid| allowed.contains(&value_to_key(fid)))
                .unwrap_or(false)
        })
        .cloned()
        .collect();
    let count = filtered.len();
    resp[collection_key] = json!(filtered);
    resp["count"] = json!(count);
    count
}

fn value_to_key(v: &Value) -> String {
    match v {
        Value::String(s) => s.clone(),
        other => other.to_string(),
    }
}

/// Watch deliberately fails closed; inbox/wait retain their best-effort contracts.
fn watch_team_allowlist(client: &Client, cfg: &Config) -> Result<HashSet<String>, EitsError> {
    let agent = cfg
        .agent_uuid
        .as_deref()
        .ok_or_else(|| EitsError::config("dm watch: --team-only requires EITS_AGENT_UUID"))?;
    let response = client.get(&format!("/teams?member_agent_uuid={}", uri_encode(agent)))?;
    let teams = response["teams"]
        .as_array()
        .ok_or_else(|| EitsError::config("dm watch: malformed team list"))?;
    let mut allowed = HashSet::new();
    for team in teams {
        let id = team
            .get("id")
            .ok_or_else(|| EitsError::config("dm watch: missing team id"))?;
        let response = client.get(&format!("/teams/{}/members", uri_encode(&value_to_key(id))))?;
        let members = response["members"]
            .as_array()
            .ok_or_else(|| EitsError::config("dm watch: malformed team members"))?;
        for member in members {
            if let Some(id) = member.get("session_id").filter(|id| !id.is_null()) {
                allowed.insert(value_to_key(id));
            }
        }
    }
    Ok(allowed)
}

fn watch(
    client: &Client,
    cfg: &Config,
    session: Option<String>,
    since: Option<String>,
    team_only: bool,
    format: WatchFormat,
    timeout: u64,
) -> Result<(), EitsError> {
    use crate::error::Code;
    use std::io::Write;
    use std::time::{Duration, Instant};

    // Client maps builder errors to ConnectionFailed too: validate persistent
    // configuration before entering the reconnect loop.
    let url = reqwest::Url::parse(&cfg.base_url)
        .map_err(|_| EitsError::config("dm watch: invalid EITS_URL"))?;
    if !matches!(url.scheme(), "http" | "https") || url.host_str().is_none() {
        return Err(EitsError::config(
            "dm watch: EITS_URL must be HTTP(S) with a host",
        ));
    }
    for header in [cfg.api_key.as_deref(), cfg.session_uuid.as_deref()]
        .into_iter()
        .flatten()
    {
        reqwest::header::HeaderValue::from_str(header).map_err(|_| {
            EitsError::config("dm watch: invalid authentication header configuration")
        })?;
    }
    let session = session
        .or_else(|| cfg.session_identity().map(String::from))
        .ok_or_else(|| EitsError::usage("dm watch: session is required"))?;
    let mut since = match since {
        Some(since) => since,
        None => {
            let response = client.get(&format!("/sessions/{}", uri_encode(&session)))?;
            response.get("session").unwrap_or(&response)["started_at"]
                .as_str()
                .filter(|s| !s.trim().is_empty())
                .ok_or_else(|| {
                    EitsError::config(
                        "dm watch: could not resolve session started_at; supply --since",
                    )
                })?
                .to_owned()
        }
    };
    let allowed = if team_only {
        Some(watch_team_allowlist(client, cfg)?)
    } else {
        None
    };
    let mut after_id = 0u64;
    let mut failures = 0u32;
    let stdout = std::io::stdout();
    let mut output = stdout.lock();
    loop {
        let started = Instant::now();
        let path = format!(
            "/dm/wait?watch=true&session={}&since={}&after_id={after_id}&timeout={timeout}",
            uri_encode(&session),
            uri_encode(&since)
        );
        let response = match client.get_long_poll(&path, Duration::from_secs(timeout + 15)) {
            Ok(response) => {
                failures = 0;
                response
            }
            Err(err)
                if (err.code == Code::ConnectionFailed
                    || matches!(err.status, Some(429 | 500 | 502 | 503 | 504)))
                    && failures < 8 =>
            {
                let delay = Duration::from_secs((1u64 << failures).min(30));
                failures += 1;
                eprintln!(
                    "dm watch: transient failure, reconnecting in {}s (attempt {failures}/8)",
                    delay.as_secs()
                );
                std::thread::sleep(delay);
                continue;
            }
            Err(err) => return Err(err),
        };
        if response["watch_cursor"] != true {
            return Err(EitsError::config(
                "dm watch: server lacks ordered watch cursor support; upgrade the server",
            ));
        }
        let items = response["items"]
            .as_array()
            .ok_or_else(|| EitsError::config("dm watch: malformed items response"))?;
        let mut emitted = Vec::new();
        let mut advanced = false;
        for item in items {
            let id = item["id"]
                .as_u64()
                .filter(|id| *id > 0)
                .ok_or_else(|| EitsError::config("dm watch: missing numeric message id"))?;
            let timestamp = item["inserted_at"]
                .as_str()
                .ok_or_else(|| EitsError::config("dm watch: missing message timestamp"))?;
            let canonical = timestamp.len() == 27
                && timestamp
                    .bytes()
                    .enumerate()
                    .all(|(index, byte)| match index {
                        4 | 7 => byte == b'-',
                        10 => byte == b'T',
                        13 | 16 => byte == b':',
                        19 => byte == b'.',
                        26 => byte == b'Z',
                        _ => byte.is_ascii_digit(),
                    });
            if !canonical {
                return Err(EitsError::config(
                    "dm watch: server timestamp must use canonical UTC microseconds",
                ));
            }
            // The opt-in API returns canonical UTC microseconds in ascending
            // (inserted_at, id) order. Keep the entire boundary, including IDs
            // for equal timestamps, and never regress on a repeated response.
            if after_id != 0 && (timestamp, id) <= (since.as_str(), after_id) {
                continue;
            }
            since = timestamp.to_owned();
            after_id = id;
            advanced = true;
            if allowed.as_ref().is_none_or(|set| {
                item.get("from_session_id")
                    .is_some_and(|id| set.contains(&value_to_key(id)))
            }) {
                emitted.push(item.clone());
            }
        }
        if !emitted.is_empty() {
            let records = match format {
                WatchFormat::Jsonl => emitted,
                WatchFormat::Json => vec![json!({"count": emitted.len(), "items": emitted})],
            };
            for record in records {
                if let Err(err) = writeln!(output, "{record}").and_then(|_| output.flush()) {
                    if err.kind() == std::io::ErrorKind::BrokenPipe {
                        return Ok(());
                    }
                    return Err(EitsError::config(format!(
                        "dm watch: cannot write output: {err}"
                    )));
                }
            }
        }
        // Empty or duplicate-only responses must not spin. Filtered messages
        // still advance the cursor, so finite backlogs can drain immediately.
        if !advanced {
            std::thread::sleep(Duration::from_secs(1).saturating_sub(started.elapsed()));
        }
    }
}
