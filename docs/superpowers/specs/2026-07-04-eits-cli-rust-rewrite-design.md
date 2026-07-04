# eits CLI Rust Rewrite — Design

**Date:** 2026-07-04
**Status:** Approved for implementation (direction approved in brainstorm; operational details tightened after review)

## Goal

Replace the agent-facing core of `scripts/eits` (5,132-line bash wrapping the EITS REST API) with a Rust binary. Bash remains permanently for installer, setup, and human-oriented commands ("Rust core + bash extras"). The rewrite ships the new agent-friendly output contract. Treat this as one coordinated breaking change.

> **Consumers get mixed behavior during migration.** The breaking change lands per-command as each is ported: **Rust-backed commands use the new JSON contract; bash-backed commands do not.** This is deliberate and must be called out in CLAUDE.md and skill docs at each phase.

## Decisions (settled in brainstorm)

| Axis | Decision |
|---|---|
| Migration | Rust core + bash extras forever — installer/setup/human flows never ported |
| Output contract | New contract in Rust (JSON-by-default, error envelope); bash keeps old behavior |
| Dispatch | Rust binary ships as **`eitsr` during migration**; unknown root subcommands exec through to the bash script. At cutover it takes the `eits` name |
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

**During migration:** the Rust binary is installed as **`eitsr`**, coexisting with the untouched bash `eits`:

```
bin/eitsr                 # Rust binary, on PATH
scripts/eits              # bash script, unchanged, still the `eits` on PATH
```

`eitsr` is a full drop-in — its bash fallback execs `scripts/eits` for unported subcommands, so `eitsr <anything>` always works. Agents opt in per-session/per-doc; nothing breaks for consumers still calling `eits`.

**After cutover** (all phases ported, consumers migrated): the binary is renamed/installed as `eits` and the bash script relocates in the same commit:

```
bin/eits                  # Rust binary (was eitsr), on PATH
libexec/eits-extras       # relocated legacy bash script
```

The Rust binary discovers the extras script in this order:

1. `EITS_EXTRAS` env override
2. `../libexec/eits-extras` relative to the resolved (symlink-followed) binary path
3. sibling `eits-extras` next to the binary
4. the bash `eits` on `PATH` (migration period — but only if it is not the Rust binary itself; guard against self-exec loops)
5. bundled app path (see Packaging)

If the discovered extras path is missing, not a regular file, or not executable → JSON error envelope `code: "extras_not_found"`, exit 1. If `exec` fails after discovery → `code: "extras_exec_failed"`, exit 1.

### Packaging (Tauri)

The Rust CLI ships as a Tauri **external binary / sidecar** (`bundle.externalBin`), not a generic resource: executable permissions must be preserved and the binary must be code-signed/notarized as part of the macOS bundle. The relocated bash script ships as a resource (scripts are signed as part of the bundle seal). Implementation must verify the sidecar path is stable enough for step 4 of extras discovery.

### Command surface

- **Phase 1 (Rust):** `tasks`, `dm`, `sessions`, `whoami`, `commits`, `notes` — approximately 90% of agent traffic in the documented workflow.
- **Phase 2 (Rust):** `teams`, `channels`, `agents` (list/get/spawn), `projects`, `search`, `timer`, `queue`.
- **Bash forever:** `install`/`uninstall`, `hooks`, `skills`, `worktree`, `codex`, `webhooks`, `standup`, `me` (human-oriented report), setup flows.

### Phase 1 command coverage

A root command is ported **whole-family**: once Rust owns the root, every nested subcommand is Rust's, and invalid nested commands are usage errors — never a fallback.

| Family | Subcommands owned by Rust in Phase 1 |
|---|---|
| `tasks` | `list`, `get`, `begin`, `complete`, `annotate`, `update`, `search`, `states`, `create`, `claim`, `delete`, `active`, `bulk-update` |
| `dm` | `inbox`/`list`, `read`, send (`--to --message`, incl. `--from`, `--metadata`, `--response-required`) |
| `sessions` | `list`, `get`, `create`, `update`, `end`, `context` |
| `whoami` | root command |
| `commits` | `list` (incl. `--since-time`), `create` |
| `notes` | `list`, `get`, `add`, `create`, `update`, `search` |

### Duration arguments

`commits list --since-time` accepts `<N>m`, `<N>h`, `<N>d` (minutes/hours/days), converted to ISO8601 UTC — same grammar as bash `_parse_duration`.

### Fallback boundary

Fallback happens **only when the first positional subcommand is unknown to Rust**.

- `eits worktree ...` → exec `eits-extras worktree ...`, argv preserved verbatim
- `eits tasks ...` → handled by Rust; invalid nested subcommands or flags under a Rust-owned command are Rust usage errors (exit 2), never a fallback
- Rust global flags (`--pretty`, `--quiet`) are only accepted for Rust commands and are never forwarded to bash extras; `eits --pretty worktree list` is a usage error
- The exec replaces the process (`execv`) — exit code, stdout, and stderr are the bash script's own

## Output contract (new)

- **JSON to stdout by default.** Compact single-line (agents are the primary consumer). No tables in the Rust core; human-readable tables remain in bash extras only.
- **Errors go to stdout too, deliberately:** agents parse one structured stream for every command outcome. Stderr is reserved for retry/progress chatter only. Do not "fix" this by moving errors to stderr — it is the contract.
- **Exceptions to JSON stdout:** `--help` and `--version` are human-readable text; successful `--quiet` prints a raw identifier (below).
- **Pretty precedence:** `--pretty` pretty-prints for that invocation; `EITS_PRETTY=1` makes pretty the default. `--quiet` wins over both for successful mutation output.

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
- `code` — stable machine-readable identifier; automation branches on this, never on `error` text. Initial set: `not_found`, `validation`, `unauthorized`, `forbidden`, `conflict`, `server_error`, `connection_failed`, `config_invalid`, `usage`, `extras_not_found`, `extras_exec_failed`, `lock_timeout`.
- `status` — HTTP status; omitted or `null` for non-HTTP failures.
- `hint` — optional recovery hint, for humans.

### Exit codes

0 ok · 1 API/permanent error · 2 usage/config error · 3 connection failure after retries.

Exit codes are intentionally coarse. Automation that needs specific failure causes must inspect the JSON `code` and/or `status`.

### Usage errors

Rust must override clap's default error renderer: usage errors print the JSON error envelope to stdout with `code: "usage"` and exit 2 — clap's default human text on stderr would violate the contract. `--help` remains human-readable text (see exceptions above).

### Quiet mode

`--quiet` affects **successful mutation output only**: it prints the created/affected identifier as raw text with a trailing newline (enables `ID=$(eits tasks begin -t X --quiet)` without jq). Errors still print the JSON error envelope.

Phase 1 quiet identifiers:

| Command | Quiet output |
|---|---|
| `tasks begin` / `create` / `claim` | task ID (integer) |
| `tasks complete` / `update` / `annotate` | task ID (integer) |
| `notes add` / `create` / `update` | note ID (integer) |
| `commits create` | commit record ID (integer; the input hash would be redundant) |
| `sessions create` | session UUID |
| `dm` send | message ID if the API returns one; otherwise `--quiet` is a usage error for this command |

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

#### Parity sweep findings (2026-07-04, live dev server)

Read-only commands compared bash `scripts/eits <cmd> --json` vs `cargo run -p eits-cli -- <cmd>` for the same data; shapes intentionally differ (normalized vs raw), only the underlying field values were diffed.

| Command | Parity | Note |
|---|---|---|
| `tasks get <id>` | match | same `id`/`title`/`state`/`state_id` values under `eitsr`'s single `task` key vs bash's duplicated top-level+nested fields |
| `tasks list --all` | match | same row count (200) once bash's `.tasks` array is compared against `eitsr`'s `count` |
| `notes list --mine` | match | identical note fields; `eitsr` normalizes bash's `results` key to `items`/`count` |
| `commits list --limit 3` | match | identical `id`/`commit_hash`/`commit_message` values and ordering |
| `sessions get self` | match | identical field values; `eitsr` nests under `session`, bash returns flat |
| `dm inbox --limit 3` | match | identical message `id`/`body`/`from_session_id`/`to_session_id` values |
| `whoami` | **bash broken** | bash `cmd_whoami` 404s resolving `/agents/:agent_id` because the session response's `agent_id` field is actually the session's own uuid, not an agent uuid — confirmed live (`error: whoami: agent id not found in agent response`). `eitsr` avoids the bug by preferring `agent_int_id` off the session response when present, only falling back to the `/agents` lookup otherwise. `tests/live.rs::whoami_matches_sessions_get_self_fields` cross-checks `eitsr whoami` against `eits sessions get self` instead of against bash `whoami`. |

**Bug found and fixed during the live sweep:** `tasks begin` (`crates/eits-cli/src/commands/tasks.rs`) parsed the create response's `task_id` with `.as_i64()` only, which silently rejected the live server's numeric-string form (`"task_id":"8070"`) and failed every real `tasks begin` call with `{"code":"server_error","error":"task creation failed"}` — this never showed up against the mock server because the fixtures always used a bare JSON number. Fixed to accept both a JSON number and a numeric string; regression test `begin_accepts_string_task_id_from_server` added to `tests/contract.rs`, and `tests/live.rs::tasks_begin_quiet_then_complete_round_trip` exercises the real create+complete round trip.

## Behavior parity with bash

### Base URL resolution

`EITS_URL` → `~/.config/eits/desktop.json` `port` field → `~/.config/eits/.env` `EITS_URL=` line → `http://localhost:5001/api/v1`.

- `EITS_URL` (env or `.env`) must be the **full base including `/api/v1`** — same as bash; Rust treats the value as authoritative and does not append `/api/v1`.
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

Three distinct uses — do not blend them:

- **HTTP headers:** `x-eits-role` and `x-eits-session` are sent **only when `EITS_SESSION_UUID` is set** (verified: bash line 40–42 gates both on the UUID). If only `EITS_SESSION_ID` exists, **no session headers are sent** — do not invent a header from the integer ID.
- **CLI argument defaults:** `EITS_SESSION_UUID` preferred, `EITS_SESSION_ID` integer fallback for `--session`/`--from`/`--mine`; `EITS_PROJECT_ID` defaulting for `--project`/`tasks begin`. Endpoints accept either form in the request body/query — that is server contract, unchanged.
- **DM lock identity (local only):** `EITS_SESSION_UUID`, else `EITS_SESSION_ID`, else the literal `default` — used solely to build the lock path.

### Retry & timeouts

Each request has a 10s overall timeout; the client also sets a connect timeout no greater than 10s. Retryable failures — jittered exponential backoff, 4 attempts, base 2s doubling, cap 30s, chatter on stderr:

- connection refused / connection timeout / request timeout
- HTTP 429, 502, 503, 504

Non-retryable: all other 4xx, malformed responses, TLS errors, auth failures.

> Note: this **expands** bash's retry set (bash retries only curl exit 7 and 429/503). 502/504/timeouts are added deliberately — they are transient in this deployment (Phoenix restarts behind the desktop app).

### Annotation offline queue

`tasks annotate` (and the annotate step inside failure paths) must keep bash's offline queue: if the POST to `/tasks/:id/annotations` fails after retries, append `{"task_id":N,"body":"...","title":"..."}` as one JSON line to `~/.eits/pending-annotations.log` (creating `~/.eits/` if needed), warn on stderr, exit 1. The queue is drained by `eits queue flush` (bash in Phase 1) — the line format must stay byte-compatible.

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

1. **Phase 1 ships as `eitsr`.** The bash `eits` is untouched; agents and docs opt in to `eitsr` incrementally. Parity checks run against the dev server with both binaries side by side.
2. **Phase 2 lands in `eitsr`** the same way.
3. **Cutover** (separate, deliberate step once consumers are migrated): the Rust binary takes the `eits` name and the bash script relocates to `libexec/eits-extras` in the same commit. `eitsr` remains as an alias for one release, then retires.

The DM lock protocol makes `eitsr` and bash `eits` safe to run concurrently during the migration window.
