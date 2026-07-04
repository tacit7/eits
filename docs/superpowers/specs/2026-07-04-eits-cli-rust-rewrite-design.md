# eits CLI Rust Rewrite — Design

**Date:** 2026-07-04
**Status:** Approved (brainstorm with Uriel)

## Goal

Replace the agent-facing core of `scripts/eits` (5,132-line bash wrapping the EITS REST API) with a Rust binary. Bash remains permanently for installer/human commands ("Rust core + bash extras"). The rewrite ships the new agent-friendly output contract — this is the one breaking change, not two.

## Decisions (settled in brainstorm)

| Axis | Decision |
|---|---|
| Migration | Rust core + bash extras forever — installer/human flows never ported |
| Output contract | New contract in Rust (JSON-by-default, error envelope); bash keeps old behavior |
| Dispatch | Rust binary owns the `eits` name; unknown subcommands exec through to the bash script |
| Layout | Cargo workspace member alongside `src-tauri` |

## Architecture

```
crates/eits-cli/          # new cargo workspace member
  src/main.rs             # clap dispatch + bash-fallback exec
  src/api.rs              # HTTP client: base-URL resolution, retry/backoff, auth/role/session headers
  src/output.rs           # JSON printer (compact/pretty/quiet), error envelope
  src/commands/           # one module per command family
libexec/eits-extras       # today's scripts/eits, relocated
```

- Workspace root `Cargo.toml` lists `src-tauri` and `crates/eits-cli`.
- Tauri bundle gains the compiled binary as a resource (replacing `scripts/eits` in `tauri.conf.json` resources as commands are ported); desktop installs get it for free.
- Dev install: `cargo install --path crates/eits-cli`.

### Command surface

- **Phase 1 (Rust):** `tasks`, `dm`, `sessions`, `whoami`, `commits`, `notes` — ~90% of agent traffic per the documented workflow.
- **Phase 2 (Rust):** `teams`, `channels`, `agents` (list/get/spawn), `projects`, `search`, `timer`, `queue`.
- **Bash forever:** `install`/`uninstall`, `hooks`, `skills`, `worktree`, `codex`, `webhooks`, `standup`, `me` (decorative human report), setup flows.

### Dispatch

clap with `external_subcommand`: any subcommand the binary doesn't recognize is `exec`'d to `eits-extras` with argv passed through untouched. Extras script resolution order:

1. `EITS_EXTRAS` env override
2. sibling of the binary
3. bundled Tauri resource path

Missing extras script → JSON error envelope, exit 1.

### Behavior parity (non-negotiable carryovers from bash)

- Base-URL resolution chain: `EITS_URL` → `~/.config/eits/desktop.json` port → `~/.config/eits/.env` → `http://localhost:5001/api/v1`.
- `EITS_API_KEY` bearer auth; `x-eits-role: orchestrator` and `x-eits-session` headers when `EITS_SESSION_UUID` is set.
- Retry: connection-refused and 429/503 with jittered exponential backoff (4 attempts, cap 30s), chatter on stderr.
- Identity fallback: `EITS_SESSION_UUID` preferred, `EITS_SESSION_ID` integer fallback; `EITS_PROJECT_ID` defaulting.
- DM serialization lock: same lock path/protocol as bash so Rust and bash never race each other.

## Output contract (new)

- **JSON to stdout, always.** Compact by default (agents are the primary consumer); `--pretty` / `EITS_PRETTY=1` for humans. No tables in the Rust core — tables remain a bash-extras affordance.
- **Normalized shapes:** one canonical top-level object per resource. `tasks get` returns the task once (today's bash duplicates it top-level and under `.task`). Lists return `{"items": [...], "count": N}` uniformly. The CLI normalizes server responses, so later server-side envelope cleanup does not break consumers again.
- **Errors:** `{"error": "...", "status": 404, "hint": "..."}` on **stdout**, non-zero exit. Stderr carries only retry/progress chatter.
- **Exit codes:** 0 ok · 1 API/permanent error · 2 usage error · 3 connection failure after retries.
- **`--quiet`** on mutations prints only the created/affected ID (enables `ID=$(eits tasks begin -t X --quiet)` without jq).
- **Idempotency envelopes:** `{"status":"already_closed"}`-style responses (exit 0) preserved on `tasks complete`, extended to `commits create` duplicate hashes and `teams join`/`channels join`.

### Consumer migration

The breaking change lands per-command as each is ported (bash keeps old behavior for everything unported). Each phase includes a grep of hooks, skills, and CLAUDE.md examples for consumers of that phase's commands, with updates in the same change.

## Stack

- **clap** (derive) — arg parsing, `external_subcommand` for bash fallback.
- **reqwest blocking** — a CLI makes one request per invocation; async buys nothing.
- **serde_json**, **thiserror**.
- No `jq` runtime dependency — that's the point.

## Testing

- Unit tests: URL/config/identity resolution, output normalization, error envelope mapping.
- Integration tests against the live dev server (`EITS_URL` → :5001) as a `cargo test -- --ignored` suite.
- Golden-file check that `--help` output stays stable.

## Rollout

Phase 1 binary takes the `eits` name only after its six commands pass parity checks against the dev server. The bash script relocates to `libexec/eits-extras` in the same commit — there is never a window with two `eits` entrypoints on PATH.
