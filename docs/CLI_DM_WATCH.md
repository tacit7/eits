# Watching direct messages

`eits dm watch` keeps one long poll open and streams new inbound messages. Use
it as a background process for Codex or Claude automation:

```sh
eits dm watch --since-session --team-only --format jsonl
```

Set `EITS_SESSION_UUID` (or `EITS_SESSION_ID`) to the **watching session**, never
the parent session. `--session` overrides the recipient. `--team-only` requires
`EITS_AGENT_UUID`; membership is resolved once at startup. Restart the watcher
after changing teams. Membership lookup failures stop the watcher.

Without `--since`, the watcher resolves the selected session's actual
`started_at`. `--since-session` explicitly requests the same default. Failure to
resolve it stops the command instead of replaying unbounded history. An explicit
ISO8601 `--since` replaces the session cutoff and conflicts with `--since-session`.
Messages at the initial cutoff are included.

## Output and lifetime

- `--format jsonl` (default): one compact DM object per line.
- `--format json`: one compact `{"items":[...],"count":N}` object per delivered
  batch, on its own line. The indefinite stream is **not** one JSON array.
- Empty long polls produce no output. Every emitted record is flushed immediately.
- `--timeout` is the duration of each server long poll, from 1 to 55 seconds
  (default 25); it is not a limit on the watcher's lifetime.
- Stop with Ctrl-C or terminate the process. Closing its output pipe also stops it.
- Global `--pretty` does not alter watch records. Global `--quiet` does not suppress
  watch records; it only applies to supported mutations.

The CLI's usual terminal JSON error envelope can appear on stdout on failure.
Consumers must distinguish that envelope from a DM or batch. Retry diagnostics
are on stderr. A supervisor should inspect the exit status rather than blindly
restarting permanent failures.

## Reconnects and ordering

The watcher uses the `/dm/wait` long-poll transport with an opt-in ordered cursor.
The server must acknowledge `watch_cursor: true`; older servers fail immediately
with an upgrade error. Inbox and one-shot `dm wait` retain their existing contracts.

Requests send `watch=true`, `since`, and `after_id` (initially zero). The server
must return the oldest available messages strictly after `(since, after_id)`,
ordered by timestamp and numeric ID. Returned timestamps must use canonical UTC
microsecond precision. This preserves messages that share a timestamp and drains
backlogs from the oldest message forward. Filtering advances the same cursor,
including for messages outside the selected teams.

Connection failures and HTTP 429/500/502/503/504 retry with delays of 1, 2, 4, 8,
16, then 30 seconds, up to eight consecutive retries. Successful responses reset
that budget. Other HTTP errors, malformed responses, and configuration failures
stop the command. Empty or repeated immediate responses are paced to
avoid busy loops. Reconnects preserve the last handled timestamp **and** message ID;
repeated older responses do not emit duplicate messages or move the cursor backward.

## Delivery limits

Deduplication is in memory for the life of one process, including reconnects.
Restarting with the same session cutoff can replay already printed messages.
There is no durable consumer acknowledgement or exactly-once side-effect guarantee;
consumers performing work should durably deduplicate on message ID. A crash between
printing and consumer processing cannot be resolved by this command alone.

Timestamp cursors assume that new rows are not later committed with timestamps
behind an already consumed boundary. Backdated/imported messages and out-of-order
database transaction commits require a stronger server delivery log for lossless
consumption. This command does not claim to solve that server limitation.

Tests use loopback mock endpoints only. Do not test the watcher by sending real
DMs, spawning agents, or continuously polling a live EITS service.
