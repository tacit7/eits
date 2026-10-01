# Session visibility diagnostics

Run `eits sessions doctor self` to inspect the current registered session, or
`eits sessions doctor <uuid-or-id>` to inspect another session. `self` follows
`sessions get self`: it requires the resolved `EITS_SESSION_UUID` and does not
fall back to an integer session ID. `--pretty` formats the JSON report.

The command performs one GET of the existing session-detail API. It never
updates a session, imports messages, starts a provider, or repairs metadata.
Existing `sessions get` output remains unchanged. Authentication, lookup, and
transport errors retain the normal CLI error contract; unavailable diagnostic
fields in a successful report do not make the command fail.

## Reading the report

- `metadata` reports API-provided `provider`, `entrypoint`, `project_id`, and
  `archived`, each with a status and source. Missing fields are explicitly
  `unavailable`; an explicit API null is preserved as an available null value.
  The current API may omit provider, entrypoint, and archived. The command
  cannot establish their values without a server API change.
- `reader_routing` describes the repository's DM session-file sync rule:
  `provider == "codex"` uses Codex; other strings or explicit null use Claude.
  Missing or invalid provider data leaves routing unavailable. This is a rule
  derived from metadata, not verification of execution by a running server.
  `model_provider`, entrypoint, and local runtime environment are not substitutes
  for the session's provider.
- `local.env_file` checks the current process's selected Codex env file, using
  the same selection order as CLI config: `EITS_CODEX_ENV_FILE`, otherwise
  `EITS_CODEX_SESSION_ID`, `CODEX_THREAD_ID`, or `CODEX_SESSION_ID` under
  `~/.eits/codex/sessions/<sanitized-id>.env`. It reports only regular-file
  presence. It does not prove the file belongs to the queried session or that
  its contents are valid. No selected path means unavailable.
- `local.message_file` checks the API's session UUID on the CLI host. Codex
  discovery searches `~/.codex/sessions` recursively for filenames ending in
  `<uuid>.jsonl`, matching the server reader's convention. Claude checks
  `~/.claude/projects/<escaped-worktree-path>/<uuid>.jsonl`, replacing `/` and
  `.` with `-`. If the session worktree path is absent, the agent/project fallback
  path is unavailable from session detail, so discovery is unavailable.

Local discovery reports `found`, `missing`, or `unavailable`. It does not read
message contents or validate a transcript. Codex traversal skips symlink entries
and stops after 100,000 entries; errors, skipped symlinks without a match, or
exhausted limits are unavailable,
not proof of absence. Unsupported UUID path characters also yield unavailable.
The server reader currently uses `~/.codex/sessions`, so this diagnostic does
not substitute `CODEX_HOME` or search archived Codex transcripts.

The CLI host and server may have different home directories and files. Local
presence does not establish app visibility, server file access, message import,
or list-filter eligibility. Paths, env contents, credentials, session descriptions,
and message contents are excluded from diagnostic output. Normal CLI config
resolution still happens before this command and can load its selected env file.
