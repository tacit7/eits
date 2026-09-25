# Task ownership commands

```sh
eits tasks claim 42
eits tasks release 42
eits tasks handoff 42 --to 73
```

The current session comes from `EITS_SESSION_UUID` or `EITS_SESSION_ID`.
The handoff target accepts either a registered session UUID or integer ID.
All commands return JSON; `--quiet` prints the task ID on success.

- Claim changes To Do to In Progress, replacing existing creator/session links
  with exactly one executor. Retrying as that executor is a no-op; another
  session receives a conflict.
- Release changes an owned In Progress or In Review task to To Do and removes
  all session links.
- Handoff transfers an owned In Progress or In Review task to exactly one target
  session, preserving its workflow state and clearing the target's stale intent.
  Handoff to yourself is a no-op.
- Done and archived tasks cannot be claimed, released, or handed off.

The API endpoints are `POST /api/v1/tasks/:id/claim`, `/release`, and `/handoff`.
Each requires `session_id`; handoff additionally requires `to`.
Missing/invalid sessions return 400, missing tasks 404, non-owner mutations 403,
and incompatible task states 409. These endpoints use the existing shared API-key
boundary and caller-supplied session identity, just like claim; the API key is
not bound to an individual session.

Ownership checks, session-link replacement, workflow changes, intent clearing,
and release/handoff annotations commit in one transaction under a task-row lock.
Concurrent claims cannot assign two executors through these endpoints.

Release and handoff annotations record the caller, target, action and resulting
`updated_at` revision. The same caller can safely retry the same operation while
that revision remains current, even after relinquishing ownership. Retries add
no duplicate annotation or event. Subsequent task changes invalidate the receipt;
an old request cannot release or transfer a newly claimed task. Retain these
annotations when retry support is needed. Legacy session-link endpoints remain
separate association operations, not exclusive ownership commands.
