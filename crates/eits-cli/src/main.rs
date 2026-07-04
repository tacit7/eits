mod error;
mod extras;
mod output;

use clap::Parser;
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
