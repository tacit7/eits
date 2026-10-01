# Work status

`eits work status` reports the current session's work without changing task,
message, team, or registration state. `eits work checkpoint` and
`eits workflow status` share the same implementation.

```sh
eits work status
eits work status --pretty
eits work status --quiet
```

Output is JSON by default. `--pretty` changes formatting only. `--quiet` retains
the JSON report, consistent with other read commands; bare IDs are for mutations.
A partial report exits successfully: inspect `health`, section `available` flags,
and `warnings` before interpreting an empty list as no work. Configuration or
client construction errors still use the normal CLI error envelope and exit code.

## Fields

- `current_session`: resolved session UUID/integer ID, agent, project ID,
  registration worktree path, status, and `started_at`. Unresolved fields are
  null; `resolved` distinguishes API data from environment hints.
- `tasks.items`: tasks linked/assigned to this session through the existing
  session-task API, including completed tasks. `active_items` retains states 2
  (In Progress) and 4 (In Review); `in_progress_items` contains only state 2.
  Counts describe the returned lists. The request is limited to 200 tasks;
  `possibly_truncated` is true when that limit is reached.
- `team_memberships`: teams associated with the resolved agent UUID, with the
  configured agent UUID as a fallback. This is agent membership, not proof that
  every team has a member registered for the current session.
- `inbox`: up to 20 recent inbound DMs, scoped by session `started_at` when
  available (legacy `created_at` is accepted as a fallback). A missing timestamp
  produces a warning and uses the recent inbox without a cutoff. `count` is the
  returned message count, and `possibly_truncated` flags a full page.
- `inbox.unread_count`: always null, with `unread_status: "unsupported_by_api"`.
  The existing DM API does not expose read markers or an unread-count endpoint;
  recent messages must not be described as unread. No messages are marked read.
- `health.registration`: `registered` or `not_initialized` from the session's
  `initialized` field; `unknown` if that field is missing; `missing_identity` if
  no session identity is configured; `unavailable` if resolution fails.
  Existing `health.agent_uuid` and `health.project_id` describe configuration
  presence, while `current_session` contains resolved values.
- `git`: local working directory, repository root, branch, HEAD and dirty paths.
  These are separate from the registered `current_session.worktree_path`.
- `commit_tracking` and `suggested_next_command`: existing checkpoint diagnostics
  for recently unlogged commits and a suggested action. Suggestions are never run.

Task, team and inbox failures (including malformed collection responses) set
availability/health false and add a warning. Their compatibility count fields
remain zero and lists remain empty. Lookup errors report only a stable error
code and HTTP status, never raw error bodies, request URLs, or credentials.
The command performs GET requests and local Git inspection only; it does not
register sessions, claim/complete tasks, send DMs, or log commits.

The original command shipped in `e8abf919` and was extended in `2e7137c9`.
This implementation reuses that command and the existing APIs.
