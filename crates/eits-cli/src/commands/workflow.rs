use crate::commands::work;
use crate::config::Config;
use crate::error::EitsError;
use crate::http::Client;
use crate::output;

#[derive(clap::Subcommand)]
pub enum WorkflowCmd {
    /// Concise current session workflow status
    Status,
}

pub fn run(client: &Client, cfg: &Config, cmd: WorkflowCmd, pretty: bool) -> Result<(), EitsError> {
    match cmd {
        WorkflowCmd::Status => {
            output::print_json(&work::status_report(client, cfg), pretty);
            Ok(())
        }
    }
}
