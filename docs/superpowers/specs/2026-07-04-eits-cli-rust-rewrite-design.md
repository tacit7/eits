# eits CLI Rust Rewrite — Design

**Date:** 2026-07-04
**Status:** Approved for implementation (direction approved in brainstorm; operational details tightened after review)

## Goal

Replace the agent-facing core of `scripts/eits` (5,132-line bash wrapping the EITS REST API) with a Rust binary. Bash remains permanently for installer, setup, and human-oriented commands ("Rust core + bash extras"). The rewrite ships the new agent-friendly output contract — this is the one breaking change, not two.

> **Consumers get mixed behavior during migration.** The breaking change lands per-command as each is ported: Rust-backed commands speak the new contract, bash-backed commands keep the old one. This is deliberate and must be called out in CLAUDE.md and skill docs at each phase.

## Decisions (settled in brainstorm)

| Axis | Decision |
|---|---|
| Migration | Rust core + bash extras forever — installer/setup/human flows never ported |
| Output contract | New contract in Rust (JSON-by-default, error envelope); bash keeps old behavior |
| Dispatch | Rust binary owns the `eits` name; unknown root subcommands exec through to the bash script |
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
- Dev install: `cargo install --path crates/eits-cli`.

### Installed layout

The installed `eits` entrypoint is always the Rust binary.

```
bin/eits                  # Rust binary, on PATH
libexec/eits-extras       # relocated legacy bash script
```

The Rust binary discovers `eits-extras` in this order:

1. `EITS_EXTRAS` env override
2. `../libexec/eits-extras` relative to the resolved (symlink-followed) binary path
3. sibling `eits-extras` next to the binary
4. bundled app path (see Packaging)

Missing extras script → JSON error envelope (`code: "extras_not_found"`), exit 1.

### Packaging (Tauri)

The Rust CLI ships as a Tauri **external binary / sidecar** (`bundle.externalBin`), not a generic resource: executable permissions must be preserved and the binary must be code-signed/notarized as part of the macOS bundle. The relocated bash script ships as a resource (scripts are signed as part of the bundle seal). Implementation must verify the sidecar path is stable enough for step 4 of extras discovery.

### Command surface

- **Phase 1 (Rust):** `tasks`, `dm`, `sessions`, `whoami`, `commits`, `notes` — ~90% of agent traffic per the documented workflow.
- **Phase 2 (Rust):** `teams`, `channels`, `agents` (list/get/spawn), `projects`, `search`, `timer`, `queue`.
- **Bash forever:** `install`/`uninstall`, `hooks`, `skills`, `worktree`, `codex`, `webhooks`, `standup`, `me` (human-oriented report), setup flows.

### Fallback boundary

Fallback happens **only when the first positional subcommand is unknown to Rust**.

- `eits worktree ...` → exec `eits-extras worktree ...`, argv preserved verbatim
- `eits tasks ...` → handled by Rust; invalid nested subcommands or flags under a Rust-owned command are Rust usage errors (exit 2), never a fallback
- Rust global flags (`--pretty`, `--quiet`) are only accepted for Rust commands and are never forwarded to bash extras; `eits --pretty worktree list` is a usage error
- The exec replaces the process (`execv`) — exit code, stdout, and stderr are the bash script's own

## Output contract (new)

- **JSON to stdout by default.** Compact single-line (agents are the primary consumer); `--pretty` / `EITS_PRETTY=1` pretty-prints for humans. No tables in the Rust core; human-readable tables remain in bash extras only.
- **Stderr carries only retry/progress chatter.** Stdout is never contaminated by non-JSON text (except successful `--quiet`, below).

### Normalized shapes

One canonical top-level object per resource. The CLI normalizes whatever the server sends, so later server-side envelope cleanup does not break consumers again.

- Single resources: `{"task": {...}}`, `{"session": {...}}` — the resource exactly once (today's bash `tasks get` duplicates it top-level and under `.task`).
- Lists: `{"items": [...], "count": N}` uniformly.
- Pagination fields are **not** included in Phase 1. If added later, they must be additive only (e.g. `next_cursor`).

### Error envelope

Errors use this canonical shape, printed to **stdout**, with a non-zero exit:

```json
{
  "error": "Task not found",
  "code": "not_found",
  "status": 404,
  "hint": "Run `eits tasks list` to find a valid task ID."
}
```

- `error` — human-readable message; may change between versions.
- `code` — stable machine-readable identifier; automation branches on this, never on `error` text. Initial set: `not_found`, `validation`, `unauthorized`, `forbidden`, `conflict`, `server_error`, `connection_failed`, `config_invalid`, `usage`, `extras_not_found`, `lock_timeout`.
- `status` — HTTP status; omitted or `null` for non-HTTP failures.
- `hint` — optional recovery hint, for humans.

### Exit codes

0 ok · 1 API/permanent error · 2 usage/config error · 3 connection failure after retries.

Exit codes are intentionally coarse. Automation that needs specific failure causes must inspect the JSON `code` and/or `status`.

### Quiet mode

`--quiet` affects **successful mutation output only**: it prints the created/affected identifier as raw text with a trailing newline (enables `ID=$(eits tasks begin -t X --quiet)` without jq). Errors still print the JSON error envelope.

### Idempotency envelopes

`{"status":"already_closed"}`-style responses (exit 0) preserved on `tasks complete`, extended to `commits create` duplicate hashes and `teams join`/`channels join` (`already_tracked`, `already_member`).

### Output examples

`eits tasks get 123`
```json
{"task":{"id":123,"title":"Implement Rust CLI","state":"in_progress","session_id":6239}}
```

`eits tasks list`
```json
{"items":[{"id":123,"title":"Implement Rust CLI","state":"in_progress"}],"count":1}
```

`eits tasks begin -t "Write tests" --quiet`
```
123
```

`eits tasks get 999999` (exit 1)
```json
{"error":"Task not found","code":"not_found","status":404,"hint":"Run `eits tasks list` to find a valid task ID."}
```

### Consumer migration

Each phase includes a grep of hooks, skills, and CLAUDE.md examples for consumers of that phase's commands, with updates landing in the same change.

## Behavior parity with bash

### Base URL resolution

`EITS_URL` → `~/.config/eits/desktop.json` `port` field → `~/.config/eits/.env` `EITS_URL=` line → `http://localhost:5001/api/v1`.

- `EITS_URL` (env or `.env`) must be the **full base including `/api/v1`** — same as bash; the client does not append path segments.
- Resolution skips missing files and missing keys, but errors on malformed values from an explicitly provided source:
  - Invalid/unparseable `EITS_URL` → config error, exit 2
  - Invalid JSON in `desktop.json` → config error, exit 2 (bash silently skips; Rust is stricter on purpose — silent fallback to the wrong server is worse)
  - Missing `port` key in valid `desktop.json` → skip source
- Final URL is normalized by trimming trailing slashes.
- `XDG_CONFIG_HOME` honored for the config dir, `~/.config` fallback.

### Headers & auth

- `Authorization: Bearer <EITS_API_KEY>` — only when `EITS_API_KEY` is set; otherwise the request is sent unauthenticated (matches bash; auth failures surface as API JSON errors).
- `x-eits-role: orchestrator` and `x-eits-session: <uuid>` — only when `EITS_SESSION_UUID` is set (matches bash).

### Identity

`EITS_SESSION_UUID` preferred, `EITS_SESSION_ID` integer fallback; `EITS_PROJECT_ID` defaulting for `--project`/`tasks begin`.

### Retry & timeouts

Each request has a 10s timeout (connect + read). Retryable failures — jittered exponential backoff, 4 attempts, base 2s doubling, cap 30s, chatter on stderr:

- connection refused / connection timeout / request timeout
- HTTP 429, 502, 503, 504

Non-retryable: all other 4xx, malformed responses, TLS errors, auth failures.

> Note: this **expands** bash's retry set (bash retries only curl exit 7 and 429/503). 502/504/timeouts are added deliberately — they are transient in this deployment (Phoenix restarts behind the desktop app).

### DM serialization lock

Rust must match the existing bash lock exactly (`_dm_post`, scripts/eits):

- **Path:** `/tmp/eits_dm_<EITS_SESSION_UUID | EITS_SESSION_ID | "default">.lock` — but constructed from `std::env::temp_dir()` on the Rust side only if bash is updated in the same commit; otherwise keep the literal `/tmp` prefix so both implementations contend on the same lock. **Decision: keep literal `/tmp` for parity; revisit when bash DM path retires.**
- **Acquisition:** atomic `mkdir`; on failure poll every 0.5s.
- **Timeout:** 60 attempts (~30s) → error envelope `code: "lock_timeout"`, exit 1.
- **Release:** `rmdir` after the POST completes, success or failure.
- **Stale locks:** bash has no stale-lock recovery (a crashed holder blocks until callers time out). Rust replicates this in Phase 1 — do not "improve" unilaterally, both sides must change together.

## Stack

- **clap** (derive) — arg parsing; unknown-root-subcommand handling for bash fallback.
- **reqwest blocking** — the CLI performs one request per invocation, so the blocking client keeps the implementation simpler with no meaningful performance loss.
- **serde_json**, **thiserror**.
- No `jq` runtime dependency.

## Testing

- **Unit:** URL/config/identity resolution (incl. malformed-config error cases), output normalization, error envelope mapping, duration parsing.
- **Fallback:** unknown root subcommands exec `eits-extras` with argv preserved; invalid nested args under Rust-owned commands do NOT fall back; Rust global flags rejected before unported subcommands.
- **Contract:** stdout is valid JSON for every Rust command outcome except successful `--quiet`; stderr chatter never contaminates stdout (assert under forced retry).
- **Integration:** against the live dev server (`EITS_URL` → :5001) as a `cargo test -- --ignored` suite.
- **Golden files:** top-level `--help` and Phase 1 command `--help` only; intentional clap upgrades update goldens in the same commit.

## Rollout

Phase 1 binary takes the `eits` name only after its six commands pass parity checks against the dev server. The bash script relocates to `libexec/eits-extras` in the same commit — there is never a window with two `eits` entrypoints on PATH.
