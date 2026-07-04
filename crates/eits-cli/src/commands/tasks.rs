use crate::error::EitsError;
use crate::http::Client;

#[derive(clap::Subcommand)]
pub enum TasksCmd {
    /// Fetch a single task by id
    Get { id: String },
}

pub fn run(cmd: TasksCmd, client: &Client) -> Result<serde_json::Value, EitsError> {
    match cmd {
        TasksCmd::Get { id } => {
            let resp = client.get(&format!("/tasks/{id}"))?;
            let task = resp.get("task").cloned().unwrap_or(resp);
            Ok(serde_json::json!({ "task": task }))
        }
    }
}
