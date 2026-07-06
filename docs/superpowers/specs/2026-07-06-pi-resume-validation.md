# Pi Resume-Semantics Validation — Phase 1 Gate (Task 14)

**Date:** 2026-07-06
**Environment:** real harness (`priv/bin/eits-pi-harness`, pi-coding-agent 0.74.0), real provider
(`anthropic/claude-haiku-4-5` via `~/.pi/agent/auth.json` OAuth), driven through `Pi.SDK.start/2`
with `EITS_PI_SESSION_ROOT=/tmp/pi-task14-root`. Driver script: `validate_resume.exs` (committed
alongside this doc).

## Verdict

**PASS on all four cases. `continueRecent` is deterministic for our usage — the spec's
pinned-transcript harness fallback is NOT needed.**

Key observation: each session directory contains exactly **one** transcript file across all
turns and all failure modes. Pi's `SessionManager.continueRecent` appends every subsequent turn
to the same `.jsonl` lineage rather than creating per-turn files, so "most recent transcript"
cannot mis-pick.

## Case results

| Case | Procedure | Outcome | Session dir after |
|---|---|---|---|
| 1. Resume after success | turn1 "remember FLAMINGO" → fresh process turn2 "what word?" | turn1 `:complete`; turn2 `:complete`, answered `FLAMINGO` — **recall PASS** | 1 file |
| 2. Resume after cancel | turn1 long count, `Pi.SDK.cancel/1` at 4 s → turn2 "Say OK" | turn1 `{:error, :user_canceled}` (terminal, non-retryable — codex round-3 fix verified live); turn2 `:complete` | 1 file |
| 3. Resume after crash | turn1 long count, `kill -9` of harness OS pid at 4 s → turn2 "Say OK" | turn1 `{:error, {:exit_code, 137}}` (exit-before-turn_end = failure invariant held); turn2 `:complete`, no corrupted-transcript error | 1 file |
| 4. Repeated resume | 3 sequential turns (FLAMINGO, OSTRICH, "what two words?") | all `:complete`; turn3 answered `FLAMINGO\nOSTRICH` — **recall-both PASS** | 1 file |

## Incidental findings

- `anthropic/claude-3-5-haiku-20241022` (present in Pi 0.74.0's static registry) 404s on the
  live Anthropic API. Discovery output cannot be assumed live-valid — a stale registry entry
  surfaces as a mid-turn `turn_error` (`HTTP 404 not_found`), which the sticky-error path
  reported cleanly. Reinforces the Phase 2 plan: model pickers should prefer discovery but
  errors must remain user-legible (they are).
- The provider-error path, cancel path, and crash path all produced exactly one terminal
  outcome each — no duplicate terminals observed (exactly-once guard held under real traffic).
