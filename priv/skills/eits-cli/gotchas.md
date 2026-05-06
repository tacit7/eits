# EITS CLI — Gotchas & Environment

## Known Gotchas

1. **Exit 7 on every command** — the CLI cannot connect to the API server. The default URL is `http://localhost:5001/api/v1` (no env var required). Exit 7 means the server is not running or is unreachable. Verify the server is up; set `EITS_URL` only if the server is on a non-default host or port.

2. **`tasks begin` without `--id` always creates a new task** — for orchestrator-assigned tasks, prefer `eits tasks claim <task_id>`. `tasks begin --id <task_id>` works as a compatibility alias for claim, but `claim` is clearer and canonical. Without `--id`, `begin` will create a duplicate.

3. **`tasks begin` has weaker 429 retry than annotate/complete** — `begin` relies only on `_curl`'s single-level backoff. `annotate`, `complete`, and `spawn` each have a dedicated 3-attempt retry loop on top of that. If `begin` fails with 429, retry manually.

4. **`tasks list` scopes to current session** — when `EITS_SESSION_UUID` is set, `list` only shows tasks linked to your session. Pass `--all` to see project-wide tasks.

5. **`tasks start` is deprecated** — it prints a deprecation warning and tells you to use `tasks claim` instead. `tasks claim <id>` is canonical for claiming an existing task: it removes all prior session links, adds the caller's session, and sets state to In Progress. `tasks begin --id <id>` calls the same claim endpoint and works, but `claim` is clearer. Never use `tasks start`. Note: when using `tasks begin --id <id>`, `--title` and `--description` are silently ignored, while `--tag` still applies. Prefer `tasks claim <id>` to avoid mixed create/claim semantics.

6. **Write hook requires state 2 (In Progress), not just any active task** — the hook checks `state_id = 2` in the DB. `eits tasks active` returns both In Progress and In Review tasks, but In Review does not unblock writes. If blocked, verify your task is In Progress, not In Review.

7. **`EITS_PROJECT_ID` not injected into spawned agents** — Claude subprocesses don't inherit it. Pass it explicitly in `--instructions` or via `--interpolate-env` with `$EITS_PROJECT_ID` in the instructions string.

8. **DM to inactive session returns 422** — sessions in `completed`, `failed`, or `waiting` states reject DMs. Use `eits teams status --wait` instead of DM polling for completion detection.

9. **`dm inbox --unread` doesn't exist** — there's no `is_read` field. Filter by `--since <iso8601>` or `--since-session` (messages since this session started) instead.

10. **`EITS_AGENT_UUID` unset on resume** — if the hook didn't export it, get it from the session. `sessions get` emits JSON by default: `EITS_AGENT_UUID=$(eits sessions get $EITS_SESSION_UUID | jq -r '.agent_uuid')`.

11. **`commits create` has no `success` field** — response is `{errors, commits, duplicates}`. Check `jq '.duplicates | length > 0'` for duplicates, not a success boolean.

12. **`agents spawn --team-id` bad ID warns, doesn't die** — if the team can't be resolved, spawn continues without team assignment and prints a warning to stderr. Verify the spawned session joined the team after spawn.

13. **`--project-id` is the exception, not the rule** — nearly every subcommand uses `--project|-p`. Only `sessions update` and `agents spawn` use `--project-id`. Don't assume a subcommand takes `--project-id` just because one does.

14. **Agents commit to wrong branch** — spawned agents don't know which branch they're on. Always include `git branch` verification in spawn instructions before any `git commit`.

15. **`sessions get self` hits a CastError server-side** — use explicit `$EITS_SESSION_UUID` instead of the `self` alias until the bug is fixed.

---

## Environment Variables

| Variable            | Purpose                                                                          |
|---------------------|----------------------------------------------------------------------------------|
| `EITS_URL`          | Optional API base URL override; defaults to `http://localhost:5001/api/v1`       |
| `EITS_SESSION_UUID` | Current session UUID                                                             |
| `EITS_SESSION_ID`   | Current session integer ID                                                       |
| `EITS_AGENT_UUID`   | Current agent UUID                                                               |
| `EITS_PROJECT_ID`   | Current project integer ID; not injected into spawned agents — pass explicitly   |

Both `EITS_SESSION_UUID` (UUID) and `EITS_SESSION_ID` (integer) are set in interactive sessions. `dm --to` accepts either. Prefer integers in spawned agent instructions — shorter and unambiguous.
