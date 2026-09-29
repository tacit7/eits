# Closing out a task with `eits workflow finish`

After implementation and required validation, run:

```bash
eits workflow finish --task 9040 --result 'Implemented helper; focused tests pass' \
  --parent 7016 --branch codex/backlog-7016-9040 --commit <existing-sha>
```

Task, result, parent session (integer ID or UUID), and branch are explicit,
required, nonblank inputs. Session identity comes from the normal EITS config.
`--commit` is optional and repeatable; supplying it requires `EITS_AGENT_UUID`.
No git commit is created. Without hashes, the notification says `commit=none`.
`--checks-reminder 'Run required checks'` prints a reminder, not a validation
result: finish never executes tests or shell commands.

The sequence is:

1. Resolve the current session's `started_at`, then fetch its inbox since that
   timestamp. Print the checkpoint to stderr.
2. Print the optional checks reminder.
3. Log supplied commits and link them to the task. Any creation/link error,
   including a partial batch failure, stops closeout.
4. Complete the task with the result as its annotation.
5. Send the parent `done task=<task> result=<result> branch=<branch> commit=<hashes-or-none>`.
6. Fetch the inbox again and return one JSON success report containing both polls.

Inbox polls include all senders so team lookup failures cannot hide instructions.
They fetch up to 200 messages and report `possibly_truncated` at the limit. They
are checkpoints, not an unread-message acknowledgement or an automatic response
system. Review actionable instructions with `eits dm inbox` before invoking finish;
review the final inbox afterward. The helper does not pause for message review.

Every request failure returns nonzero with its failing step and previously
confirmed mutations. Missing/malformed confirmations also fail. No `finished`
report is printed until the final inbox succeeds. A task may already be done or
a DM sent when a later step fails, and a lost response may hide a successful
mutation. Inspect remote state and use the lower-level commands to recover;
blind retries may duplicate annotations or notifications. This is sequential
orchestration, not a transaction or an idempotent retry protocol.

`eits workflow status`, `eits commits create`, `eits tasks complete`, `eits dm`,
and `eits dm inbox` remain available with unchanged behavior. Task completion
uses the existing endpoint, including its team-member settlement behavior.
This helper does not claim tasks, update session status, push, or merge.

## Recommended agent use

Claim the assigned task before editing, check the inbox during work, run required
validation, and create any intended git commit before finish. Include files,
tests, and limitations in `--result`. Use finish only when authorized to close the
explicit task and message the explicit parent. Handle final inbox instructions
before ending the session. Existing installed skills are not modified by this
command; agents may adopt this sequence in their own task instructions.

## Tests

`cargo test -p eits-cli --test workflow_finish` uses only local mock HTTP servers;
it does not mutate real tasks or send live DMs.
