# EITS CLI — Gotchas & Environment

## Known Gotchas

1. **Exit 7 on every command** — `EITS_URL` not set. `export EITS_URL=http://localhost:5001/api/v1` before any `eits` call.

2. **`tasks begin` without `--id` always creates a new task** — to claim an orchestrator-assigned task atomically, use `eits tasks begin --id <task_id>`. Without `--id`, you get a duplicate.

3. **`tasks begin` has no auto-retry on 429** — unlike annotate/complete, `begin` fails hard. Retry manually with backoff.

4. **`tasks list` scopes to current session** — when `EITS_SESSION_UUID` is set, `list` only shows tasks linked to your session. Pass `--all` to see project-wide tasks.

5. **`tasks start` vs `tasks begin`** — `start` sets state=2 and links the session on an *existing* task. `begin` creates a new one. Never use `begin` to claim a pre-created task without `--id`.

6. **Write hook blocks without an active task** — the pre-tool-use hook denies file edits if you have no task in state 2 linked to your session. Run `eits tasks begin` first.

7. **`EITS_PROJECT_ID` not injected into spawned agents** — Claude subprocesses don't inherit it. Pass it explicitly in `--instructions` or via `--interpolate-env` with `$EITS_PROJECT_ID` in the instructions string.

8. **DM to inactive session returns 422** — sessions in `completed`, `failed`, or `waiting` states reject DMs. Use `eits teams status --wait` instead of DM polling for completion detection.

9. **`dm inbox --unread` doesn't exist** — there's no `is_read` field. Filter by `--since <iso8601>` or `--since-session` (messages since this session started) instead.

10. **`EITS_AGENT_UUID` unset on resume** — if the hook didn't export it, get it from the session: `EITS_AGENT_UUID=$(eits sessions get $EITS_SESSION_UUID | jq -r '.agent_uuid')`.

11. **`commits create` has no `success` field** — response is `{errors, commits, duplicates}`. Check `jq '.duplicates | length > 0'` for duplicates, not a success boolean.

12. **`agents spawn --team-id` bad ID warns, doesn't die** — if the team can't be resolved, spawn continues without team assignment and prints a warning to stderr.

13. **`teams create --project` not `--project-id`** — the flag for teams create is `--project`, not `--project-id` (unlike most other subcommands that use `--project-id`).

14. **Agents commit to wrong branch** — spawned agents don't know which branch they're on. Always include `git branch` verification in spawn instructions before any `git commit`.

15. **`sessions get self` hits a CastError server-side** — use explicit `$EITS_SESSION_UUID` instead of the `self` alias until the bug is fixed.

---

## Environment Variables

| Variable            | Purpose                                   |
|---------------------|-------------------------------------------|
| `EITS_URL`          | `http://localhost:5001/api/v1` (required) |
| `EITS_SESSION_UUID` | Current session UUID                      |
| `EITS_SESSION_ID`   | Current session integer ID                |
| `EITS_AGENT_UUID`   | Current agent UUID                        |
| `EITS_PROJECT_ID`   | Current project integer ID                |

Both `EITS_SESSION_UUID` (UUID) and `EITS_SESSION_ID` (integer) are set in interactive sessions. `dm --to` accepts either. Prefer integers in spawned agent instructions — shorter and unambiguous.
