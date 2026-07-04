mod commands;
mod config;
mod duration;
mod error;
mod extras;
mod http;
mod lock;
mod output;

use clap::Parser;
use commands::tasks::TasksCmd;
use error::{Code, EitsError};
use std::ffi::OsString;

#[derive(Parser)]
#[command(
    name = "eitsr",
    version,
    about = "EITS CLI (Rust core; bash fallback for extras)"
)]
struct Cli {
    /// Pretty-print JSON output (default: compact; or EITS_PRETTY=1)
    #[arg(long, global = true)]
    pretty: bool,
    /// Print only the created/affected ID on success (mutations)
    #[arg(long, short, global = true)]
    quiet: bool,
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(clap::Subcommand)]
enum Cmd {
    /// Task queries and mutations
    Tasks {
        #[command(subcommand)]
        cmd: TasksCmd,
    },
    /// Resolve and print session/agent identity (mirrors bash `eits whoami`)
    Whoami,
    /// Anything not Rust-owned falls through to the bash extras script
    #[command(external_subcommand)]
    External(Vec<OsString>),
}

fn main() {
    // Global flags before an external subcommand are a usage error per spec:
    // detect them by comparing raw argv length against the parsed external args.
    let raw: Vec<OsString> = std::env::args_os().skip(1).collect();
    let cli = Cli::parse();
    let pretty = output::pretty_enabled(cli.pretty);
    match cli.cmd {
        Cmd::Tasks { cmd } => {
            let cfg = match config::Config::resolve() {
                Ok(cfg) => cfg,
                Err(err) => error::exit_with(err, pretty),
            };
            let client = http::Client::new(cfg);
            match commands::tasks::run(cmd, &client) {
                Ok(v) => output::print_json(&v, pretty),
                Err(err) => error::exit_with(err, pretty),
            }
        }
        Cmd::Whoami => {
            let cfg = match config::Config::resolve() {
                Ok(cfg) => cfg,
                Err(err) => error::exit_with(err, pretty),
            };
            let client = http::Client::new(cfg.clone());
            if let Err(err) = commands::whoami::run(&client, &cfg, pretty) {
                error::exit_with(err, pretty);
            }
        }
        Cmd::External(args) => {
            let had_global_flags = raw.len() > args.len();
            if had_global_flags {
                // Global flags are rejected before extras run, so there's no
                // pretty-print preference to honor here.
                error::exit_with(
                    EitsError::usage("global flags are not supported for bash-extras subcommands")
                        .with_hint("drop --pretty/--quiet or use a Rust-owned command"),
                    false,
                );
            }
            match extras::find_extras() {
                Ok(path) => {
                    let e = extras::exec_extras(&path, &args);
                    error::exit_with(
                        EitsError::api(
                            format!("failed to exec extras: {e}"),
                            Code::ExtrasExecFailed,
                            None,
                        ),
                        pretty,
                    );
                }
                Err(err) => error::exit_with(err, pretty),
            }
        }
    }
}
