# Agent Schedules — Design Spec

**Date:** 2026-03-16
**Status:** Approved
**Task:** #1357

---

## Overview

Add an "Agent Schedules" tab inside the existing Jobs LiveView. The tab loads active `subagent_prompts` and existing `spawn_agent` scheduled jobs, then builds a prompt-to-job lookup for rendering schedule state per prompt. Creating a schedule generates a `spawn_agent` job using a snapshot of the prompt instructions, selected model, and resolved project path. Scheduled jobs store a `prompt_id` column for traceability.

This is a **prompt-centric** surface with schedule state layered on top — not simply another filtered jobs list.

---

## UI/UX

### Layout

- New "Agent Schedules" tab added to the existing Jobs page tabs (`OverviewLive.Jobs` and `ProjectLive.Jobs`).
- Default tab on mount is `:all_jobs` — existing UI unchanged on load. No URL-based tab persistence.
- The tab renders a card grid: one card per active `subagent_prompt`.
- Each card shows: name, description, schedule status (active cron / not scheduled), and actions.
- A "Detached Schedules" section below the grid shows `spawn_agent` jobs whose `prompt_id` references a soft-deactivated prompt (`active = false`). See "Orphaned Jobs" section for details.

### Scheduling Form

- Triggered by "+ Schedule" (unscheduled card) or "Edit" (scheduled card).
- The agent name is locked at the top — you're seeding from a specific template.
- Fields: schedule type (cron / interval), cron expression or interval seconds, model (haiku / sonnet / opus), optional project override.
- **Project override dropdown:** shows all projects from the `projects` table, plus a "— use prompt default —" option at the top. When on `ProjectLive.Jobs`, the current page project is pre-selected if the prompt has no default.
- **Responsive behavior:**
  - Mobile (`< sm`): drawer slides in from the right.
  - Desktop (`>= sm`): centered modal with backdrop.
  - Same LiveView template, different container class. No JS viewport detection needed — CSS breakpoints handle it.

### Snapshot Semantics

The scheduled job captures a **snapshot** of the prompt's `prompt_text` at creation time. It is not a live reference. Future edits to the prompt do not affect running schedules. The UI shows a note: "Instructions captured from prompt at time of scheduling."

---

## Data Model

### Migration

Add `prompt_id` as a real nullable column on `scheduled_jobs` with `ON DELETE RESTRICT`:

```sql
ALTER TABLE scheduled_jobs ADD COLUMN prompt_id bigint REFERENCES subagent_prompts(id) ON DELETE RESTRICT;
CREATE INDEX idx_scheduled_jobs_prompt_id ON scheduled_jobs(prompt_id);
CREATE UNIQUE INDEX idx_scheduled_jobs_unique_prompt ON scheduled_jobs(prompt_id) WHERE prompt_id IS NOT NULL;
```

**Why `ON DELETE RESTRICT`:** `ON DELETE SET NULL` would silently lose the `prompt_id` reference on hard delete, making orphan detection impossible. With `RESTRICT`, deleting a prompt that has an active schedule fails at the DB level. The application handles this by blocking prompt deletion in the UI when a schedule exists (show an error: "Delete the schedule first").

This is the correct choice because:
1. The "Detached Schedules" section only works if `prompt_id` is preserved.
2. Silent data loss is worse than an explicit constraint.

### Uniqueness

One schedule per prompt globally. The partial unique index above (`WHERE prompt_id IS NOT NULL`) enforces this — it allows multiple non-prompt jobs while enforcing one-per-prompt semantics.

### `spawn_agent` job config shape

```json
{
  "prompt_id": 3,
  "instructions": "<snapshot of prompt_text at creation>",
  "model": "sonnet",
  "project_path": "/Users/urielmaldonado/projects/eits/web"
}
```

`prompt_id` in config is kept for readability in run logs; the canonical relationship lives in the `scheduled_jobs.prompt_id` column.

---

## Project Resolution Order

When resolving `project_path` for a new schedule (step 3 only applies to global prompts where step 2 yields nothing):

1. Explicit project override selected in the form.
2. Prompt's `project_id` default (looked up via `Projects.get_project/1`).
3. Current page context project (only when in `ProjectLive.Jobs` and prompt is global).
4. Validation error if none resolves — form shows an error and Save is blocked.

---

## Prompt Scoping

| Surface | Prompts shown |
|---|---|
| `OverviewLive.Jobs` → Agent Schedules | All active global prompts (`project_id IS NULL`) |
| `ProjectLive.Jobs` → Agent Schedules | That project's prompts + global prompts |

"Active" means `subagent_prompts.active = true`.

---

## Orphaned Jobs

**Definition:** A `spawn_agent` job is orphaned when `prompt_id IS NOT NULL` AND `subagent_prompts.active = false` (soft-deactivated).

Hard deletion of prompts is **blocked** at the DB level (`ON DELETE RESTRICT`) when a schedule exists. The prompt management UI must check for and surface this constraint: "This prompt has an active schedule. Delete the schedule first."

Soft-deactivated prompt jobs appear in a "Detached Schedules" section below the card grid. Each entry shows: job name, cron expression, warning badge ("Prompt deactivated"), and actions: Edit, Run now, Delete.

### `list_orphaned_agent_jobs/0` query shape

```elixir
from j in ScheduledJob,
  join: p in assoc(j, :prompt),
  where: j.job_type == "spawn_agent",
  where: not is_nil(j.prompt_id),
  where: p.active == false
```

---

## LiveView Assigns

New assigns added to the jobs socket:

| Assign | Type | Description |
|---|---|---|
| `@active_tab` | `:all_jobs` \| `:agent_schedules` | Selected tab; default `:all_jobs` on mount |
| `@prompts` | `[%Prompt{}]` | Active prompts for current scope; lazy-loaded on first tab visit |
| `@prompt_job_map` | `%{prompt_id => %ScheduledJob{}}` | App-side lookup built from two queries |
| `@scheduling_prompt` | `%Prompt{} \| nil` | Prompt being scheduled; nil = form closed |
| `@scheduling_job` | `%ScheduledJob{} \| nil` | Existing job when editing; nil = new |
| `@orphaned_jobs` | `[%ScheduledJob{}]` | Jobs with `prompt_id` referencing inactive prompt |
| `@projects` | `[%Project{}]` | All projects for the override dropdown |

---

## Events

| Event | Triggered by | Action |
|---|---|---|
| `"switch_tab"` | Tab click | Updates `@active_tab`; loads prompts/orphans on first visit to `:agent_schedules` |
| `"schedule_prompt"` | "+ Schedule" button | Sets `@scheduling_prompt`, opens form |
| `"edit_schedule"` | "Edit" button | Sets `@scheduling_prompt` and `@scheduling_job` |
| `"cancel_schedule"` | Cancel / backdrop click | Clears scheduling assigns |
| `"save_schedule"` | Form submit | Creates or updates `spawn_agent` job |
| `"delete_job"` | Delete button | Deletes job (reuses existing handler) |

---

## Backend Changes

### `ScheduledJobs` context

- `list_spawn_agent_jobs_by_prompt_ids/1` — `WHERE prompt_id IN (ids)`:

```elixir
from j in ScheduledJob,
  where: j.prompt_id in ^ids
```
- `list_orphaned_agent_jobs/0` — JOIN to `subagent_prompts` where `active = false` (see query above).
- `create_job/1` — on `{:error, %Ecto.Changeset{}}`, check `has_error?(cs, :prompt_id)` and return `{:error, :already_scheduled}`:

```elixir
case Repo.insert(changeset) do
  {:ok, job} -> ...
  {:error, %Ecto.Changeset{} = cs} ->
    if Keyword.has_key?(cs.errors, :prompt_id),
      do: {:error, :already_scheduled},
      else: {:error, cs}
end
```

### `ScheduledJob` schema

- Add `field :prompt_id, :id` (use `:id` to match `bigint` PK on `subagent_prompts`).
- Add `belongs_to :prompt, EyeInTheSkyWeb.Prompts.Prompt, foreign_key: :prompt_id, references: :id, define_field: false`.
- Add `:prompt_id` to the `cast/2` list in the changeset — without this, `prompt_id` will not persist on insert.
- Add `unique_constraint(:prompt_id, name: :idx_scheduled_jobs_unique_prompt)` to changeset.

### PubSub

Reuse the existing `"scheduled_jobs"` topic and `:jobs_updated` message. On `:jobs_updated`, reload `@prompt_job_map` and `@orphaned_jobs` when `@active_tab == :agent_schedules`. The guard prevents work when the tab hasn't been opened, but all new assigns (`@prompts`, `@prompt_job_map`, `@orphaned_jobs`) must be initialized to `[]` / `%{}` on mount so the template never hits an unset assign.

### Prompt Deletion Guard (`Prompts` context)

`ON DELETE RESTRICT` raises a `Postgrex.Error` (FK violation) if a prompt is deleted while a schedule exists. The `Prompts` context must rescue this and return a clean error:

```elixir
def delete_prompt(%Prompt{} = prompt) do
  case Repo.delete(prompt) do
    {:ok, p} -> {:ok, p}
    {:error, %Ecto.Changeset{} = cs} -> {:error, cs}
    {:error, %Postgrex.Error{postgres: %{code: :foreign_key_violation}}} ->
      {:error, :has_active_schedule}
  end
end
```

The prompt management LiveView surfaces `{:error, :has_active_schedule}` as: "This prompt has an active schedule. Delete the schedule first."

### Migration

`mix ecto.gen.migration add_prompt_id_to_scheduled_jobs`

---

## Out of Scope

- Live prompt reference (jobs always snapshot).
- Bulk scheduling.
- Per-project uniqueness (one schedule per prompt globally).
- Prompt versioning or snapshot diffing.
- URL-based tab persistence.

---

## Acceptance Criteria

- [ ] Agent Schedules tab visible in both `OverviewLive.Jobs` and `ProjectLive.Jobs`. Default tab is All Jobs.
- [ ] Cards populated from `subagent_prompts`, scoped correctly per surface.
- [ ] Scheduled cards show cron expression and Edit / Run now actions.
- [ ] Unscheduled cards show "+ Schedule" button.
- [ ] Scheduling form opens as drawer on mobile, modal on desktop.
- [ ] Project override dropdown shows all projects + "— use prompt default —". Resolution follows the defined 4-step order.
- [ ] Duplicate schedule rejected at DB level; LiveView shows flash "Already scheduled".
- [ ] Deleting a prompt with an active schedule is blocked; UI shows "Delete the schedule first".
- [ ] Soft-deactivated prompt jobs appear in "Detached Schedules" section with "Prompt deactivated" badge.
- [ ] PubSub `:jobs_updated` refreshes prompt job map when Agent Schedules tab is active.
- [ ] `mix compile` passes with no errors after migration and schema changes.
- [ ] Verify `SpawnAgentWorker` reads `config["project_path"]` and `config["model"]` — confirm key names match the config shape defined in this spec before implementation.
