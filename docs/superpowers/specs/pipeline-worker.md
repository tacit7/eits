# PRD: Pipeline Worker

**Version**: 1.4
**Project**: EITS Web
**Status**: Draft

---

## Terminology

| Term | Definition |
|------|-----------|
| **Pipeline** | The definition: a named DAG of steps with a failure mode and trigger config |
| **PipelineRun** | One execution instance of a Pipeline |
| **Step** | A definition node within a Pipeline (a `PipelineStep` record) |
| **StepRun** | One execution of a Step within a PipelineRun (`PipelineStepRun` record) |
| **ScheduledJob** | An existing independent scheduler entity; a step can delegate to one |
| **Worker** | Runtime execution process (PipelineWorker or StepWorker) |
| **Coordinator** | The logic that advances the graph after each step terminal event |

---

## Overview

A visual workflow orchestration system for EITS. Pipelines are DAGs of steps that execute in dependency order with parallel branches running concurrently. Real-time status feedback via Phoenix PubSub. Triggered manually, via webhook, or on a schedule.

---

## Trust Model

**MVP assumes project members are trusted operators.** Pipeline steps can execute shell commands, Mix tasks, and non-interactive agent actions on server-side infrastructure. There is no sandboxing in MVP. Shell and Mix steps inherit the server process environment and run on the host filesystem. This is a deliberate MVP boundary, not an oversight. It will be revisited when secret injection and multi-tenant isolation are added.

---

## Step Types (MVP)

| Type | What it does |
|------|-------------|
| `inline_shell` | Runs a shell command on the server host |
| `inline_agent` | Spawns a non-interactive Claude agent with an inline prompt |
| `inline_mix` | Runs a Mix task on the server host |
| `scheduled_job` | References an existing ScheduledJob; step does not complete until the delegated job reaches a terminal state |

Nested pipelines (`pipeline` step type) are explicitly out of scope for MVP.

### Step Config Contracts

Each step type requires a specific `config` shape. Config is validated at pipeline save time; missing required fields are rejected with a descriptive error.

| Type | Required fields | Optional fields |
|------|----------------|----------------|
| `inline_shell` | `command` (string) | `working_dir` (string) |
| `inline_agent` | `prompt` (string) | `model` (string), `effort` (string), `working_dir` (string), `tool_policy_id` (integer) |
| `inline_mix` | `task` (string) | `args` (list of strings) |
| `scheduled_job` | `scheduled_job_id` (integer) | — |

`inline_agent.tool_policy_id` references a project-level tool policy. If omitted, the project's default tool policy applies. If the project has no default and no `tool_policy_id` is set, the step fails at runtime with `failure_reason: "no_tool_policy"`.

---

## Entities

### Pipeline
```
id, name, description, project_id,
failure_mode (stop_all | stop_downstream | continue),
webhook_token (high-entropy random string),
webhook_enabled (boolean, default true),
enabled (boolean, default true),
created_by_user_id, updated_by_user_id,
inserted_at, updated_at
```

### PipelineStep
```
id, pipeline_id, name, description,
step_type (inline_shell | inline_agent | inline_mix | scheduled_job),
config (jsonb),
position (integer),   -- stable ordering key for deterministic enqueue and list display
inserted_at, updated_at
```

### PipelineStepDependency
```
step_id, depends_on_step_id
unique_index(step_id, depends_on_step_id)
```

### PipelineRun
```
id, pipeline_id,
status (pending | running | completed | completed_with_errors | failed | cancelled),
triggered_by (manual | webhook | schedule),
trigger_metadata (jsonb),         -- see Audit Trail section for field details per trigger type
pipeline_name_snapshot (text),    -- pipeline name at run start (immutable)
failure_mode_snapshot (text),     -- failure mode at run start (immutable)
started_at, finished_at, inserted_at
```

### PipelineStepRun
```
id, pipeline_run_id, step_id,
status (pending | running | completed | failed | skipped),
skip_reason (nullable text),          -- "upstream_failed" | "run_failed" | "run_cancelled"
failure_reason (nullable text),       -- "timeout" | "non_zero_exit" | "cancelled" | "missing_job" | "exec_exception" | "config_error" | "agent_approval_required" | "no_tool_policy"
failure_details (nullable text),      -- human-readable detail for debugging
step_name_snapshot (text),            -- step name at run start (immutable)
step_type_snapshot (text),            -- step type at run start (immutable)
step_config_snapshot (jsonb),         -- step config at run start (immutable)
log (text, capped at 1MB, tail preserved on overflow),
exit_code, started_at, finished_at
```

### PipelineStepRunDependency _(run-graph snapshot)_
```
step_run_id, depends_on_step_run_id
unique_index(step_run_id, depends_on_step_run_id)
```

This table persists the dependency edges for each run as they existed at trigger time. The coordinator reads from this table — not from the live `PipelineStepDependency` table — when advancing the graph. This makes the graph truly immutable per run regardless of edits made to the pipeline definition mid-run.

---

## Immutable Run Snapshot

When a PipelineRun is created, the following are captured atomically and never mutated by later definition changes:

- `PipelineRun.pipeline_name_snapshot`
- `PipelineRun.failure_mode_snapshot`
- `PipelineStepRun.step_name_snapshot`, `step_type_snapshot`, `step_config_snapshot` per step
- `PipelineStepRunDependency` rows copied from the live `PipelineStepDependency` table at trigger time

The live pipeline definition and its steps may be edited freely while a run is in progress. Those edits affect future runs only. The coordinator always reads `PipelineStepRunDependency` rows for graph traversal — not the live dependency table.

Historical runs display their snapshotted names, configs, and graph, regardless of any later renames or restructuring.

---

## Trigger Mechanisms

| Trigger | How |
|---------|-----|
| Manual | "Run" button in the pipeline UI |
| Webhook | `POST /api/v1/pipelines/:id/trigger?token=<webhook_token>` |
| Schedule | Pipeline added as a ScheduledJob with `job_type: "pipeline"` |

### Webhook Security

> **MVP compromise**: token is passed as a query parameter (`?token=...`). This is pragmatic for MVP but means the token appears in server access logs and browser history. It must be redacted from application logs. Future versions will migrate to `Authorization: Bearer` header.

- Token is high-entropy (32+ bytes, URL-safe base64), generated on pipeline create
- Token is redacted from application logs
- Rate limited: max 10 trigger requests per minute per pipeline
- Future: migrate token to `Authorization: Bearer` header

### Webhook Response Codes

| Status | Condition |
|--------|-----------|
| `202 Accepted` | Run created; body contains `pipeline_run_id`, `status`, and live run URL |
| `401 Unauthorized` | Token missing or invalid |
| `409 Conflict` | Another run is already active for this pipeline |
| `422 Unprocessable Entity` | Pipeline is disabled, `webhook_enabled: false`, or pipeline fails runnable validation |
| `429 Too Many Requests` | Rate limit exceeded |

Manual and scheduled triggers do not go through this endpoint; their rejection paths are described under Pipeline Validity and Enabled State.

### Trigger Success Response Shape

```json
{
  "pipeline_run_id": 123,
  "status": "running",
  "run_url": "/projects/1/pipelines/5/runs/123"
}
```

### Webhook Token Lifecycle

- Token can be regenerated via UI ("Rotate webhook token" action)
- On rotation, the old token is invalidated immediately
- Webhook triggering can be disabled independently (`webhook_enabled: false`) without affecting manual or scheduled triggers
- Token is never returned in API responses after initial creation (one-time display or secure copy flow)

---

## Failure Modes (per pipeline)

| Mode | Behavior |
|------|----------|
| `stop_all` | Fail the run. Request cancellation of all running steps (best-effort). Mark all not-yet-started steps as skipped. |
| `stop_downstream` | Mark as skipped any not-yet-started steps whose required dependencies can no longer be satisfied because of the failure. Independent parallel branches whose dependency sets are still satisfiable continue running. |
| `continue` | Failed steps do not block any dependents. All remaining steps run regardless of upstream outcomes. PipelineRun finishes as `completed_with_errors` if any step failed. |

### Step Eligibility Per Failure Mode

A step becomes eligible to run when its upstream dependencies reach terminal states. The rules differ per mode:

- **`continue`**: Eligible as soon as all upstream dependencies are in any terminal state (`completed`, `failed`, `skipped`).
- **`stop_downstream`**: Eligible only if all upstream dependencies completed successfully. Any upstream `failed` or `skipped` causes this step to be skipped (`skip_reason: "upstream_failed"`).
- **`stop_all`**: No new steps scheduled after first failure. All not-yet-started steps skipped (`skip_reason: "run_failed"`).

### skip_reason Values

| Value | When set |
|-------|----------|
| `upstream_failed` | `stop_downstream` mode: a required upstream step failed |
| `run_failed` | `stop_all` mode: first failure policy triggered; unstarted steps are skipped as a consequence of the run being failed, not cancelled |
| `run_cancelled` | A user-initiated cancellation was requested; pending steps are skipped |

`run_failed` and `run_cancelled` are distinct: one is policy-driven (failure mode), the other is user-driven.

### Pipeline Terminal Status

| Mode | Outcome |
|------|---------|
| `stop_all` | `failed` |
| `stop_downstream` | `failed` if any step failed; `completed` if all completed |
| `continue` | `completed_with_errors` if any step failed; `completed` if all completed |

`completed_with_errors` means the graph ran to completion but not cleanly. `failed` means the run was cut short.

---

## Cancellation Semantics

When a PipelineRun is cancelled:

| Step state at cancellation time | Result |
|---------------------------------|--------|
| `pending` | Immediately set to `skipped` (`skip_reason: "run_cancelled"`) |
| `running` | Cancellation request sent best-effort; step may still complete or fail |
| `completed` / `failed` / `skipped` | Unchanged |

The PipelineRun transitions to `cancelled` once all in-flight steps have reached a terminal state. There is no per-step `cancelled` status in MVP; `skipped` + `skip_reason` covers it.

---

## Coordinator Architecture

**PipelineWorker** owns the pipeline run lifecycle:

1. Receives trigger (manual / webhook / schedule)
2. Rejects if another run is already active (409) or pipeline is disabled/invalid (422)
3. Creates `PipelineRun` (status: `running`) with snapshot fields
4. Validates DAG is acyclic
5. Creates `PipelineStepRun` records for all steps (status: `pending`) with snapshot fields
6. Copies `PipelineStepDependency` rows into `PipelineStepRunDependency` (run-graph snapshot)
7. Enqueues `StepWorker` jobs for all steps with no upstream dependencies (in ascending `position` order)

**StepWorker** executes one step:

1. Updates `PipelineStepRun` to `running`, records `started_at`
2. Executes step (shell / agent / mix / delegate to ScheduledJob runner)
   - `scheduled_job` steps: delegate execution and wait synchronously; step does not complete until the delegated job reaches a terminal state
3. Streams log output to `PipelineStepRun.log`; on overflow, oldest content is truncated (tail preserved), "log truncated" marker prepended
4. On completion: writes `failure_reason`/`failure_details` if failed, updates status + `finished_at`, signals coordinator via DB write

**Coordinator advances the graph on each step terminal event:**

Graph traversal reads from `PipelineStepRunDependency`, not the live `PipelineStepDependency` table.

```
step completed (success)
  → query PipelineStepRunDependency to find dependents with all parents terminal
  → enqueue StepWorker for newly eligible steps (ascending position order)
  → if all step_runs terminal → mark PipelineRun completed/completed_with_errors/failed
  → PubSub broadcasts updated status to UI subscribers
  → if PipelineRun terminal → send notification

step failed
  → apply failure_mode
  → write failure_reason + failure_details on PipelineStepRun
  → PubSub broadcasts status update to UI subscribers
  → if PipelineRun reaches terminal state → send notification
```

> **Signaling vs UI**: The coordinator is advanced by DB state changes (reliable). PubSub is used exclusively for pushing incremental updates to connected UI clients — it is not part of the coordinator's decision logic.

DB state is the source of truth. PubSub broadcasts are incremental updates only — the UI can always recover full state from DB on reconnect.

---

## Shell and Mix Execution Environment

For `inline_shell` and `inline_mix` steps:

- **Default working directory**: project root on the server host
- **Override**: step config `working_dir` overrides the default; path must be absolute or relative to project root
- **Base environment**: server process environment is inherited; additionally the following are injected:
  - `EITS_PIPELINE_RUN_ID`
  - `EITS_STEP_RUN_ID`
  - `EITS_PIPELINE_ID`
  - `EITS_PROJECT_ID`
- **Secrets**: no secret injection beyond what is already in the server environment (see Secrets Handling)
- **Mix tasks**: run in `MIX_ENV=dev` unless `EITS_MIX_ENV` is set in server env. `inline_mix` is host execution with a Mix wrapper — it is not sandboxed. Any task and any args are permitted. Shared-state mutations, destructive tasks, and environment-sensitive operations are the user's responsibility. This is a **trusted-operator-only feature** in MVP.
- **Permissions**: any project member can trigger shell/mix steps; no separate elevated role in MVP (see Trust Model)

---

## Secrets Handling

MVP boundary: **no secret injection mechanism**. Steps inherit only what is already in the server process environment. Users must not embed secrets in `step_config` fields — config is stored in plaintext in the DB and is visible to anyone with DB or UI access to the pipeline.

Log scrubbing in MVP: webhook tokens are redacted from application logs. No other automated secret scrubbing.

Out of scope for MVP:
- Project-scoped encrypted key/value secrets
- Secret masking in step logs
- Secrets vault integration

---

## Permission Model

| Action | Required permission |
|--------|-------------------|
| View pipelines in a project | Project member |
| Create / edit / delete pipelines | Project member |
| Trigger a run (manual) | Project member |
| View run history and logs | Project member |
| Trigger via webhook | Token possession (no user auth required) |
| Rotate webhook token | Project member |
| Disable/enable pipeline | Project member |

**MVP trust assumption**: project membership grants access to host-level execution surfaces (shell, mix, agent). This is appropriate for EITS's current trusted-team context. Role-based elevation for execution steps is deferred to post-MVP, when secret injection and multi-tenant isolation are designed.

---

## Audit Trail

Lightweight audit fields in MVP:

- `Pipeline.created_by_user_id` — who created the pipeline
- `Pipeline.updated_by_user_id` — who last edited it
- `PipelineRun.trigger_metadata` — per trigger type:
  - Manual: `{ "user_id": ..., "user_email": ... }`
  - Webhook: `{ "source_ip": ..., "user_agent": ..., "request_id": ... }` (token is NOT stored; only anonymous request metadata)
  - Schedule: `{ "scheduled_job_id": ..., "scheduled_job_name": ... }`
- Token rotation is logged as an application event (not a separate audit table); full audit log table is post-MVP

---

## Pipeline Validity and Enabled State

A pipeline has two independent state dimensions:

| Dimension | Values | Meaning |
|-----------|--------|---------|
| `enabled` | true / false | Whether any trigger may start a new run |
| Runnable | valid / invalid | Whether the definition passes all execution-time checks |

**Editor validation** (runs on save): produces warnings or errors, displayed inline. Does not block save. This is feedback for the author.

**Runnable validation** (runs on trigger): all conditions must pass or the trigger is rejected with 422. This is an execution gate.

Runnable validation checks:
1. `enabled: true`
2. `webhook_enabled: true` (webhook trigger only)
3. At least one step
4. All steps have valid config shapes
5. All `scheduled_job` references point to non-deleted jobs
6. DAG is acyclic

**Disabled pipeline behavior by trigger type**:

| Trigger type | Result when pipeline is disabled |
|-------------|----------------------------------|
| Manual (UI) | "Run" button disabled; no request sent |
| Webhook | `422 Unprocessable Entity` returned to caller |
| Schedule (ScheduledJob) | Trigger attempt is skipped and logged with reason `"pipeline_disabled"`; no PipelineRun is created |

The scheduler skip is an internal no-op with a log entry, not an API rejection. These are operationally different paths.

---

## Empty Pipeline and Graph Semantics

- **Zero steps**: pipeline saves but runnable validation blocks trigger (422)
- **Multiple root steps** (steps with no dependencies): allowed; all enqueued at run start
- **Disconnected subgraphs** within the same pipeline: allowed; all subgraphs run concurrently
- **Self-dependency** (`step_id == depends_on_step_id`): rejected at save

---

## Step Data Passing

**There is no cross-step data passing in MVP.** This is a control-flow pipeline, not a data-flow pipeline.

Steps cannot consume the output of upstream steps. Stdout/stderr is captured as a log only, not as structured consumable output. Users who need to pass data between steps must use an external mechanism (shared filesystem path, DB table, environment variable set before the pipeline runs).

Structured artifact passing and step output extraction are post-MVP.

---

## Step Ordering and Determinism

- When multiple steps become eligible at once, `StepWorker` jobs are enqueued in ascending `PipelineStep.position` order
- `position` is an integer set at step creation; the editor assigns it by insertion order and allows reordering
- Run history and step lists use `position` as the stable display sort order
- Actual execution order within a concurrency window is determined by the Oban queue scheduler, not guaranteed to match `position`

---

## Real-Time UI

Phoenix PubSub broadcasts `PipelineStepRun` status changes on each transition. LiveView receives and pushes updated props to the SvelteFlow component via live_svelte.

The live run view loads a full snapshot of the `PipelineRun`, all `PipelineStepRun` records, and `PipelineStepRunDependency` edges from the DB on mount, then subscribes to PubSub for incremental updates. This ensures correct state on page load or reconnect without depending on in-flight PubSub messages.

**Node status colors:**

| Status | Color |
|--------|-------|
| pending | gray |
| running | blue, pulsing ring |
| completed | green |
| failed | red |
| skipped | gray, strikethrough label |
| completed_with_errors | amber (pipeline-level only) |

Clicking a node opens a drawer with the step's snapshotted name, type, config, and live log output. Log streams while the step is running. If the log was truncated, a "log truncated (tail shown)" banner is displayed at the top of the log drawer.

---

## Agent Step Semantics

`inline_agent` steps are **non-interactive only**. No human approval is supported mid-step.

- Creates an ephemeral Claude agent session linked to the `PipelineStepRun`
- The session appears in the Sessions UI, tagged as pipeline-owned
- Agent output is streamed to `PipelineStepRun.log`
- If the agent would require human approval or an interactive tool policy prompt, the step fails with `failure_reason: "agent_approval_required"`
- Agent steps require a resolved tool policy: either `tool_policy_id` in step config or the project default. If neither is set, step fails with `failure_reason: "no_tool_policy"`
- User can navigate from a StepRun to its agent session for full output context
- Agent step runtime counts against step timeout; default timeout applies

---

## Queue Architecture (Oban)

Dedicated Oban queues to prevent pipeline work from starving unrelated system jobs:

| Queue | Purpose | Concurrency cap |
|-------|---------|----------------|
| `pipeline_coordinator` | PipelineWorker (run lifecycle) | 10 |
| `pipeline_step` | StepWorker (shell, mix, scheduled_job steps) | 20 |
| `pipeline_agent_step` | StepWorker for inline_agent steps (heavyweight) | 5 |

Agent steps run in a separate queue because they hold long-lived processes and can monopolize workers.

---

## Run and Log Retention

MVP: no automatic pruning. PipelineRun and PipelineStepRun records are retained indefinitely. Log content is capped at 1 MB per StepRun at write time (tail preserved).

Log pruning, run archiving, and retention policies are post-MVP.

---

## Observability

Run duration and step duration are directly computable from `started_at`/`finished_at` on PipelineRun and PipelineStepRun. No additional metrics infrastructure in MVP.

The run history list shows per-run duration and step counts. Individual step drawers show step duration.

Dashboards, queue metrics, and success/failure rate aggregates are post-MVP.

---

## DAG Validation

Validated on save (editor validation):

1. No self-dependency (`step_id == depends_on_step_id`)
2. No cycles (topological sort; reject if one cannot be produced)
3. All referenced `depends_on_step_id` values belong to the same pipeline
4. `config` shape matches the step type's contract

Validated on trigger (runnable validation, additionally):

5. At least one step
6. All `scheduled_job` step references point to existing, non-deleted jobs
7. All `inline_agent` steps have a resolvable tool policy

---

## Editor Validation UX

- Cycle detection runs client-side on edge creation; invalid edges are rejected immediately with an inline error message
- Server-side editor validation runs on save; errors are returned as a structured list and displayed inline per step or per edge. Save is allowed even with warnings.
- A pipeline with outstanding validation errors shows a warning badge; the "Run" button is disabled until runnable validation passes
- Runnable validation errors are shown inline on the trigger attempt with specific fields identified

---

## ScheduledJob Boundary

Pipelines and ScheduledJobs are intentionally separate entities in MVP:

- ScheduledJobs are independently schedulable units with their own triggers and history
- Pipelines compose ScheduledJobs as steps but do not replace them
- A ScheduledJob can be used in multiple pipelines simultaneously
- There is no plan to merge the two concepts; if the overlap creates confusion, a unified job primitive can be designed in a later version

---

## Execution Semantics

- Pipeline definitions must form an acyclic graph. Cycles are rejected on save.
- Step eligibility is determined per failure mode as described above.
- Independent branches run concurrently. "Dependency order" does not mean serial execution.
- Only one active run per pipeline is allowed in MVP. A new trigger while a run is active returns `409 Conflict`.
- Step cancellation is best-effort.
- Nested pipeline steps are out of scope for MVP.

---

## Execution Limits

| Limit | Value |
|-------|-------|
| Max steps per pipeline | 50 |
| Max parallel steps executing (per pipeline) | 10 |
| Step log cap | 1 MB (tail preserved) |
| Step timeout (default) | 30 minutes |
| Pipeline timeout (default) | none (optional per pipeline in v2) |
| Concurrent runs per pipeline | 1 (MVP) |

---

## Testing Strategy

Required test coverage before shipping:

| Area | Cases |
|------|-------|
| DAG validation | cycle detection, self-dependency, cross-pipeline reference, missing scheduled_job, bad config shape, no tool policy on agent step |
| Concurrency lock | reject trigger when run active (409), allow trigger after run completes |
| `stop_all` | first failure skips all pending (`skip_reason: run_failed`), best-effort cancel on running |
| `stop_downstream` | failed step propagates skip to dependents only, sibling branches continue |
| `continue` | all steps run, terminal status is `completed_with_errors` |
| Timeout | step exceeds timeout → `failed` with `failure_reason: "timeout"` |
| Skipped propagation | skip_reason set correctly for upstream_failed, run_failed, run_cancelled |
| Webhook auth | valid token accepts (202), invalid rejects (401), missing rejects (401), rate limit enforced (429) |
| Webhook disabled | `webhook_enabled: false` returns 422 |
| Disabled pipeline | all trigger types rejected; scheduler logs skipped |
| Empty pipeline | trigger returns 422 |
| Log cap | overflow truncates oldest, tail preserved, truncation marker set |
| Snapshot immutability | editing pipeline after run start does not affect coordinator graph or in-progress run display |
| Run-graph snapshot | `PipelineStepRunDependency` rows created at trigger time; coordinator reads them, not live table |
| `completed_with_errors` | `continue` mode with mixed outcomes produces correct terminal status |
| Cancellation | pending → skipped (run_cancelled), running → best-effort, completed unchanged |
| Trigger response | success returns pipeline_run_id, status, run_url |

---

## Routes

```
/projects/:id/pipelines              → pipeline list
/projects/:id/pipelines/new          → create pipeline
/projects/:id/pipelines/:pid         → visual editor (SvelteFlow)
/projects/:id/pipelines/:pid/runs    → run history
/projects/:id/pipelines/:pid/runs/:rid → live run view

POST /api/v1/pipelines/:id/trigger      → webhook/manual trigger
POST /api/v1/pipelines/:id/rotate_token → rotate webhook token
```

---

## Migrations Required

1. `create_pipelines`
2. `create_pipeline_steps`
3. `create_pipeline_step_dependencies`
4. `create_pipeline_runs`
5. `create_pipeline_step_runs`
6. `create_pipeline_step_run_dependencies`
7. Add `"pipeline"` to `ScheduledJob` `job_type` validation

---

## Open Questions

- Concurrency policy beyond MVP: queue triggers, parallel runs with isolation, or per-step concurrency limits?
- Max parallel step count: should 10 be configurable per pipeline or global?
- Whether nested pipelines belong in v2 or require a separate coordinator design
- Secret injection mechanism: project-scoped encrypted KV or server-env-only for v2?
- Role elevation for shell/mix/agent steps: separate `pipeline_operator` role or project-level permission flags?

---

## Out of Scope (MVP)

- Nested pipeline steps
- Step retry on failure
- Pipeline versioning / rollback
- Conditional branching (if/else on step output)
- Cross-project pipeline steps
- Pipeline import/export
- Header-based webhook auth
- Per-pipeline timeout configuration
- Per-step cancellation status tracking
- Secret injection beyond server environment
- Full audit log table
- Run/log pruning and retention policies
- Observability dashboards and metrics aggregates
- Cross-step data/artifact passing
- Interactive agent steps (human-in-the-loop)
- Role-based elevation for execution steps
