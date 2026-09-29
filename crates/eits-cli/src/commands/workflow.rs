use crate::commands::{dm, uri_encode, work};
use crate::config::Config;
use crate::error::{Code, EitsError};
use crate::http::Client;
use crate::output;
use serde_json::{json, Value};

#[derive(clap::Subcommand)]
pub enum WorkflowCmd {
    /// Concise current session workflow status
    Status,
    /// Log commits, close a task, notify its parent, and check the inbox
    Finish {
        #[arg(long, value_parser = nonblank)]
        task: String,
        #[arg(long, value_parser = nonblank)]
        result: String,
        /// Orchestrator session UUID or integer ID
        #[arg(long, value_parser = nonblank)]
        parent: String,
        /// Branch reported in the completion DM (explicit; never inferred)
        #[arg(long, value_parser = nonblank)]
        branch: String,
        /// Existing commit hash to log and link to the task (repeatable)
        #[arg(long = "commit", value_parser = nonblank)]
        commits: Vec<String>,
        /// Print a reminder; does not execute or verify checks
        #[arg(long, value_parser = nonblank)]
        checks_reminder: Option<String>,
    },
}

fn nonblank(value: &str) -> Result<String, String> {
    if value.trim().is_empty() {
        Err("must not be blank".into())
    } else {
        Ok(value.into())
    }
}

pub fn run(client: &Client, cfg: &Config, cmd: WorkflowCmd, pretty: bool) -> Result<(), EitsError> {
    match cmd {
        WorkflowCmd::Status => {
            output::print_json(&work::status_report(client, cfg), pretty);
            Ok(())
        }
        WorkflowCmd::Finish {
            task,
            result,
            parent,
            branch,
            commits,
            checks_reminder,
        } => {
            let session = cfg
                .session_identity()
                .filter(|s| !s.trim().is_empty())
                .ok_or_else(|| EitsError::config("workflow finish requires a session identity"))?;
            if !commits.is_empty()
                && cfg
                    .agent_uuid
                    .as_deref()
                    .is_none_or(|s| s.trim().is_empty())
            {
                return Err(EitsError::config(
                    "workflow finish --commit requires EITS_AGENT_UUID",
                ));
            }
            let mut completed = Vec::new();
            let mut step = "session";
            let operation = (|| {
                let response = client.get(&format!("/sessions/{}", uri_encode(session)))?;
                let started = response
                    .get("session")
                    .unwrap_or(&response)
                    .get("started_at")
                    .and_then(Value::as_str)
                    .filter(|s| !s.trim().is_empty())
                    .ok_or_else(|| EitsError::config("missing session started_at"))?;
                let inbox_path = format!(
                    "/dm?session={}&limit=200&since={}",
                    uri_encode(session),
                    uri_encode(started)
                );
                step = "checkpoint";
                let checkpoint = inbox(client, &inbox_path)?;
                // Visible even if a later mutation fails; no success envelope until the last poll.
                eprintln!("workflow finish checkpoint: {checkpoint}");
                if let Some(reminder) = checks_reminder {
                    eprintln!("Checks reminder (not executed): {reminder}");
                }
                if !commits.is_empty() {
                    step = "commit_log";
                    let response = client.post(
                        "/commits",
                        json!({
                            "agent_id": cfg.agent_uuid, "session_id": session,
                            "commit_hashes": commits, "task_ids": [task],
                        }),
                    )?;
                    for field in ["errors", "link_errors"] {
                        if response.get(field).is_some_and(|v| {
                            !v.is_null() && v.as_array().is_none_or(|a| !a.is_empty())
                        }) {
                            return Err(EitsError::api("commit logging or task linking failed; inspect tracked commits before retrying", Code::Validation, None));
                        }
                    }
                    let logged = ["commits", "duplicates"]
                        .iter()
                        .filter_map(|k| response.get(k).and_then(Value::as_array))
                        .map(Vec::len)
                        .sum::<usize>();
                    if logged < commits.len() {
                        return Err(EitsError::config(
                            "commit response did not confirm every requested hash",
                        ));
                    }
                    completed.push("commit_log");
                }
                step = "task_complete";
                let response = client.post(
                    &format!("/tasks/{}/complete", uri_encode(&task)),
                    json!({"message": result, "session_id": session}),
                )?;
                if response.get("success").and_then(Value::as_bool) != Some(true) {
                    return Err(EitsError::config("task completion was not confirmed"));
                }
                completed.push("task_complete");
                step = "parent_dm";
                let commit = if commits.is_empty() {
                    "none".into()
                } else {
                    commits.join(",")
                };
                let message =
                    format!("done task={task} result={result} branch={branch} commit={commit}");
                let response = dm::send_dm(client, cfg, &parent, &message, None, None, false)?;
                if response.get("message_id").is_none_or(Value::is_null) {
                    return Err(EitsError::config("parent DM was not confirmed"));
                }
                completed.push("parent_dm");
                step = "final_inbox";
                let final_inbox = inbox(client, &inbox_path)?;
                Ok(
                    json!({"status": "finished", "task_id": task, "parent": parent,
                    "branch": branch, "commits": commits, "checkpoint": checkpoint,
                    "final_inbox": final_inbox, "completed_steps": completed}),
                )
            })();
            match operation {
                Ok(report) => { output::print_json(&report, pretty); Ok(()) }
                Err(error) => Err(EitsError::api(
                    format!("workflow finish failed at {step}: {}", error.message), error.code, error.status
                ).with_hint(format!("Confirmed steps: {}. The failed request may have taken effect. Inspect remote state and recover with eits commits create, tasks complete, dm, or dm inbox; do not blindly repeat finish.", completed.join(", ")))),
            }
        }
    }
}

fn inbox(client: &Client, path: &str) -> Result<Value, EitsError> {
    let response = client.get(path)?;
    let messages = response
        .get("messages")
        .and_then(Value::as_array)
        .ok_or_else(|| EitsError::config("malformed inbox response"))?;
    Ok(
        json!({"items": messages, "count": messages.len(), "possibly_truncated": messages.len() >= 200}),
    )
}
