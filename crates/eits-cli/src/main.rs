mod commands;
mod config;
mod duration;
mod error;
mod extras;
mod http;
mod lock;
mod output;

use clap::error::ErrorKind;
use clap::Parser;
use commands::commits::CommitsCmd;
use commands::dm::DmCmd;
use commands::notes::NotesCmd;
use commands::sessions::SessionsCmd;
use commands::tasks::TasksCmd;
use error::{Code, EitsError};
use std::ffi::OsString;

#[derive(Parser)]
#[command(
    name = "eits",
    version,
    about = "EITS CLI (Rust core; legacy extras fallback)"
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
    /// Note queries and mutations
    Notes {
        #[command(subcommand)]
        cmd: NotesCmd,
    },
    /// Commit tracking queries and mutations
    Commits {
        #[command(subcommand)]
        cmd: CommitsCmd,
    },
    /// Session queries and mutations
    Sessions {
        #[command(subcommand)]
        cmd: SessionsCmd,
    },
    /// Send or read direct messages (root form: `eits dm --to <id> --message <text>`)
    Dm {
        #[command(subcommand)]
        cmd: Option<DmCmd>,
        #[arg(long)]
        to: Option<String>,
        #[arg(long)]
        message: Option<String>,
        #[arg(long)]
        from: Option<String>,
        #[arg(long)]
        metadata: Option<String>,
        #[arg(long = "response-required")]
        response_required: bool,
    },
    /// Resolve and print session/agent identity (mirrors bash `eits whoami`)
    Whoami,
    /// Anything not Rust-owned falls through to the legacy extras script
    #[command(external_subcommand)]
    External(Vec<OsString>),
}

fn main() {
    // Global flags before an external subcommand are a usage error per spec:
    // detect them by comparing raw argv length against the parsed external args.
    let raw: Vec<OsString> = std::env::args_os().skip(1).collect();
    let cli = match Cli::try_parse() {
        Ok(cli) => cli,
        Err(e) => match e.kind() {
            // Human-readable text on stdout, exit 0 — these are not errors.
            ErrorKind::DisplayHelp | ErrorKind::DisplayVersion => e.exit(),
            // Everything else (missing required arg, unknown flag, bare
            // invocation, etc.) is a usage error per the JSON-stdout contract.
            _ => {
                let msg = e.to_string();
                let first_line = msg.lines().next().unwrap_or("invalid arguments");
                error::exit_with(
                    EitsError::usage(first_line).with_hint("run `eits <cmd> --help`"),
                    false,
                );
            }
        },
    };
    let pretty = output::pretty_enabled(cli.pretty);
    match cli.cmd {
        Cmd::Tasks { cmd } => {
            let cfg = match config::Config::resolve() {
                Ok(cfg) => cfg,
                Err(err) => error::exit_with(err, pretty),
            };
            let client = http::Client::new(cfg.clone());
            if let Err(err) = commands::tasks::run(&client, &cfg, cmd, pretty, cli.quiet) {
                error::exit_with(err, pretty);
            }
        }
        Cmd::Notes { cmd } => {
            let cfg = match config::Config::resolve() {
                Ok(cfg) => cfg,
                Err(err) => error::exit_with(err, pretty),
            };
            let client = http::Client::new(cfg.clone());
            if let Err(err) = commands::notes::run(&client, &cfg, cmd, pretty, cli.quiet) {
                error::exit_with(err, pretty);
            }
        }
        Cmd::Commits { cmd } => {
            let cfg = match config::Config::resolve() {
                Ok(cfg) => cfg,
                Err(err) => error::exit_with(err, pretty),
            };
            let client = http::Client::new(cfg.clone());
            if let Err(err) = commands::commits::run(&client, &cfg, cmd, pretty, cli.quiet) {
                error::exit_with(err, pretty);
            }
        }
        Cmd::Sessions { cmd } => {
            let cfg = match config::Config::resolve() {
                Ok(cfg) => cfg,
                Err(err) => error::exit_with(err, pretty),
            };
            let client = http::Client::new(cfg.clone());
            if let Err(err) = commands::sessions::run(&client, &cfg, cmd, pretty, cli.quiet) {
                error::exit_with(err, pretty);
            }
        }
        Cmd::Dm {
            cmd,
            to,
            message,
            from,
            metadata,
            response_required,
        } => {
            let cfg = match config::Config::resolve() {
                Ok(cfg) => cfg,
                Err(err) => error::exit_with(err, pretty),
            };
            let client = http::Client::new(cfg.clone());
            if let Err(err) = commands::dm::run(
                &client,
                &cfg,
                cmd,
                to,
                message,
                from,
                metadata,
                response_required,
                pretty,
                cli.quiet,
            ) {
                error::exit_with(err, pretty);
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
                    EitsError::usage("global flags are not supported for extras subcommands")
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
