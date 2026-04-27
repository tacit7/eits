# Postmortem — CI Test Failures, 2026-04-26 → 2026-04-27

## TL;DR

Took **7 rounds of fixes** over ~12 hours to get CI green. Surface symptom was
"tests fail on CI but pass locally." Real causes were five different bugs
stacked on top of each other, plus a meta-bug in CI infrastructure that made
diagnosis painfully slow: the workflow only ran on PRs, never on direct main
pushes, so "is main green?" had no answer.

End state: 2160 tests, 0 failures on `main` (run 24983824065). All fixes
landed directly on `main`.

---

## What broke (in chronological order of discovery)

### Round 1 — Sandbox teardown races on `Task.Supervisor.start_child`

`Task.Supervisor.start_child(EyeInTheSky.TaskSupervisor, fn -> Repo.insert(...) end)`
calls scattered across controllers and contexts (messaging fanout, cmd
dispatcher, teams handler) didn't propagate `$callers` to the spawned task.
When the test process (sandbox owner) exited, in-flight tasks crashed
mid-DB-op with `Postgrex.disconnected: owner #PID exited`. The crash
contaminated the DB connection pool, cascading failures into subsequent
tests.

**Fix:** `EyeInTheSky.AsyncTask` wrapper module + `async_tasks_sync: true`
config flag in `config/test.exs`. In test mode, all `AsyncTask.start/1`
calls run synchronously in the caller process so they finish before the
sandbox tears down.

### Round 2 — Same race in three more places

`Notifications.maybe_push`, `messaging_controller.notify_channel_members`,
and a few others were still using raw `Task.Supervisor.start_child`.

Also discovered:
- `cli_test.exs` called `to_string(reason)` on a tuple — `Protocol.UndefinedError`.
- VS Code editor test used `System.cmd("code", ...)` which `:enoent` on CI.
- `tasks_filter_test` had a stale `phx-value-value` selector after a
  refactor renamed it to `phx-value-by`.

**Fix:** Convert remaining call sites to `AsyncTask.start`; switch
`to_string` → `inspect`; tag editor test `:host_dependent`; update selector.

### Round 3 — `notify_agent_complete` synchronous in test mode crashed AgentWorker

Making `notify_agent_complete` synchronous via the round-1 mechanism caused
it to run *inside* `AgentWorker.handle_info`. Test cleanup (`on_exit` →
`DynamicSupervisor.terminate_child`) raced with `handle_info` completion.
If the sandbox tore down mid-operation, the GenServer crashed repeatedly
until `AgentSupervisor` hit its restart limit and died — taking all
subsequent agent_worker tests with it.

**Fix:** Skip `notify_agent_complete` entirely in test mode. Notifications
are tested directly in `notifications_test.exs`.

**Lesson:** "Make it synchronous" is not always safe. If the call lives
inside a GenServer's `handle_info`, sync execution is bounded by
GenServer shutdown timeouts and exposes you to a different class of race.

### Round 4 — Confusion: most "failures" weren't real

Spent significant time chasing failures from CI logs the user pasted, only
to discover the suite passed locally with seed 0. The CI log was from a
*PR branch* (`remove/gitea-webhook` at `5ffa77a0`), not from `main`. That
PR had been branched off main *before* the round 1-3 fixes landed.

The CI workflow only triggered `on: pull_request: branches: [main]` — never
on direct main pushes. So "is main green?" had no current data, and stale
PRs kept producing red CI runs that looked like main was broken.

**Fix:** Add `push: branches: [main]` trigger.

**Lesson — biggest one of the whole exercise:** When the user pastes a CI
failure, the *first* move is to verify the run SHA matches main HEAD. Not
to start debugging.

### Round 5 — Long-running pollers crash and kill the Endpoint

`EyeInTheSky.Tasks.Poller` (polls every 2s) and `EyeInTheSky.Teams.Subscriber`
(reacts to every session pulse) hold sandbox connections during their
queries. When a test sandbox owner exits while the poller is mid-query,
the poller crashes. Repeated crashes hit the supervisor's restart limit,
the supervisor escalates, the **Endpoint dies** — and its ETS table goes
with it. Every subsequent test failed with `the table identifier does not
refer to an existing ETS table` on `:ets.lookup(EyeInTheSkyWeb.Endpoint, :secret_key_base)`.

**Fix:** Gate both pollers behind `Application.get_env(:eye_in_the_sky, :start_pollers, true)`. Set `start_pollers: false` in `config/test.exs`.

### Round 6 — CI ran tests it shouldn't have

The workflow ran bare `mix test` with no `--exclude` flags. So
`:integration`, `:host_dependent`, and `:sdk_e2e` tests ran on GitHub
Actions runners that have no `claude` binary, no `code` binary, and no
Anthropic API key. They failed deterministically every time.

**Fix:** `mix test --exclude integration --exclude host_dependent --exclude sdk_e2e`.

### Round 7 — `_build` cache poisoning

After all the above, CI *still* showed `cli_test.exs` failing with a code
snippet (`to_string(reason)`) that did not exist in the source on disk
(which had `inspect(reason)`). Cause: `actions/checkout` does not preserve
git source-file mtimes. Every checkout writes "now." Mix's incremental
recompile detection compares source mtime to `.beam` mtime; if the cached
`.beam` was newer than the freshly-checked-out source, Mix skipped
recompilation. The test ran old compiled code.

**Fix:** Drop `_build` caching from the workflow. Recompile from scratch
takes ~30s and eliminates an entire class of phantom failures. Deps cache
(keyed on `mix.lock`) is unaffected.

### Round 7b — The one real test bug

`scope_test.exs:74` did:
```elixir
ids = Enum.map(results, & &1.id)
assert s1.id in ids
refute other.id in ids   # other is a Project, ids are session_ids
```
Refuting a `project_id` against a list of `session_ids` is type-confused
and accidentally passed only because PG sequence values for the two tables
were always far apart locally. On CI's fresh DB, sequences started low
enough that `project.id == 12` collided with `session.id == 12`. Refute
flipped to fail.

**Fix:** Compare against `s2.id` (the session in the other project), which
is what the test was always meant to check.

---

## Key takeaways

### 1. Verify the SHA before debugging

Most "CI failures" the user reported turned out to be on stale PR branches.
The diagnostic discipline is:

```
gh run list --workflow=ci.yml --limit 5
gh pr view <N> --json headRefOid
git log --oneline main
```

If the PR HEAD is behind main, the fix is `gh pr update-branch <N>`, not
a code change. **Do not start reading test failures until you've confirmed
the run is on a SHA that contains the code you think it does.**

### 2. CI must run on `push: main`

A workflow that only runs on `pull_request` cannot answer "is main green?"
You will be permanently in a state where the only CI signal comes from
PRs whose branches are arbitrarily far behind main. Add the push trigger.

### 3. Don't cache `_build` unless you have a story for stale `.beam` files

`actions/checkout` strips mtimes. Mix's incremental compile is mtime-based.
A restored cache from a prior commit will silently serve stale compiled
code. If you want the speed, key the cache on `${{ github.sha }}` with no
`restore-keys` fallback, *or* run `mix clean` before `mix compile`.

### 4. `Task.Supervisor.start_child` doing DB work is a sandbox-teardown bomb

Anywhere fire-and-forget tasks call into `Repo.*`, you have a race with
sandbox teardown. The pattern that works in this codebase:

- Wrap the spawn in `EyeInTheSky.AsyncTask.start/1`.
- Set `config :eye_in_the_sky, async_tasks_sync: true` in `test.exs`.
- This makes the task synchronous in test (completes before owner exits)
  and async in prod (fire-and-forget as intended).

### 5. Synchronous-in-test is not always safe

If the wrapped task runs inside a GenServer's `handle_info`, making it
synchronous now ties the GenServer's response time to the DB op, and ties
the test's cleanup race to the GenServer's shutdown timeout. Some
synchronous-in-test conversions need a third option: skip in test entirely.

### 6. Long-running app GenServers need a `:start_*` flag

`Tasks.Poller`, `Teams.Subscriber`, and similar always-running pollers
must be gated behind a config flag and disabled in test. Otherwise their
periodic queries will eventually catch a sandbox-teardown moment and
crash, which cascades into Endpoint death and ETS errors on every
subsequent test.

### 7. Test bugs hide behind PG sequence luck

`refute X.id in ids` where `X` and the `ids` come from different tables
is a latent flake. It passes when sequences are at different values and
explodes the moment they collide. CI with a fresh DB is the most likely
place to hit the collision. Always compare `id` checks against the same
record type.

### 8. Tag-based test exclusion only works if the workflow honors the tags

Tagging a test `:integration` or `:host_dependent` does nothing if the
workflow runs `mix test` with no `--exclude` flags. Adding a new
"skip-on-CI" tag requires updating both the test AND `.github/workflows/ci.yml`.

---

## Process notes

- Working in worktrees throughout (per project convention) — but had to
  fight `cd` not persisting between Bash tool calls. Always re-`cd` to
  the worktree at the start of any commit/push sequence.
- `git push origin main` only pushes the linear chain. Divergent worktree
  branches must be `git merge`'d into main first; then push.
- `gh pr update-branch <N>` is the right tool to refresh stale PRs.
- The `eits` CLI requires an active In Progress task before any file edit
  (hook-enforced). Don't fight it; just `eits tasks begin --title "..."`
  at the start of any new work session.

---

## What this would have looked like with better tooling

If we'd had any one of these from the start, this would have been a single
round instead of seven:

1. **CI on `push: main`** from day one — would have caught every fix the
   moment it landed instead of waiting for someone to open a PR.
2. **No `_build` cache** — would have prevented the `to_string` ghost that
   ate hours of "but the source says `inspect`!" confusion.
3. **A pre-push test script** that ran the same exclude flags as CI would
   have caught the host-dependent test failures locally.

The single biggest leverage point is #1. The whole "is the user looking at
a stale PR or at main?" confusion went away the moment main started
running CI on every push.
