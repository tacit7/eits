# Spec: Consolidate the two cron→human-readable translators

## Problem

There are **two independent implementations** that translate a schedule into English, with
divergent output, divergent failure behavior, and one carrying visible bugs. They will drift —
the create/edit form preview and the jobs table can describe the *same* expression differently.

| Module | Location | Used by | Parser | On failure |
|--------|----------|---------|--------|------------|
| `ScheduledJobs.CronPreview` | `lib/eye_in_the_sky/scheduled_jobs/cron_preview.ex` | job create/edit form live preview (`job_form_drawer.ex:180`) | real `Crontab.CronExpression.Parser` | returns `nil` |
| `JobsFormatters.describe_cron` (+ `format_schedule`) | `lib/eye_in_the_sky_web/live/shared/jobs_formatters.ex` | jobs table (`jobs_table.ex:88`), jobs page (`jobs_page.ex:683`) | hand-rolled `String.split` | returns raw expr |

### Concrete divergence
- **Wording:** CronPreview → `"Runs daily at 09:00 AM"`; JobsFormatters → `"Daily at 9 AM"`.
- **Coverage:** CronPreview handles cron only. JobsFormatters also handles `interval`
  (`"Every 45m"`) but *only via `format_schedule/1`*, not `describe_cron/1`.
- **Bugs in JobsFormatters** (enshrined in its own tests):
  - `describe_cron("0 */4 * * *")` → `"Daily at Every 4h"` (grammatically broken)
  - `describe_cron("*/15 * * * *")` → `"Daily at Every 15m"` (broken)
- **Robustness:** CronPreview uses the real crontab parser; JobsFormatters splits strings by
  hand and will mis-describe ranges/steps/lists it doesn't special-case.

## Goal

One canonical schedule-description function. Both the form preview and the table render from it,
so they can never disagree. Fix the broken "Daily at Every 15m" output along the way.

## Design

### New single source of truth
Rename/repurpose `ScheduledJobs.CronPreview` → **`EyeInTheSky.ScheduledJobs.ScheduleDescription`**
(domain layer, not web — it's pure logic, already parser-backed). It exposes:

```elixir
# Full schedule (cron OR interval) → human string, always returns something usable.
# Fallback = the raw schedule_value (table needs to show *something*).
@spec describe(job_or_map) :: String.t()
def describe(%{schedule_type: "interval", schedule_value: v}) # "Every 45 minutes"
def describe(%{schedule_type: "cron", schedule_value: v})     # "Runs daily at 8:22 AM"

# Preview variant for the FORM: returns nil on unparseable/unknown so the UI hides the hint.
@spec preview(cron_expr :: String.t()) :: String.t() | nil
```

Two entry points because the two consumers genuinely differ on failure semantics
(table wants a fallback string; form wants `nil` to hide the preview). Both share one parser
and one description core — the divergence that caused this bug is eliminated.

### Interval support (currently missing from the cron translator)
`describe/1` handles `interval` directly, normalized to whole units:
- `2700` → `"Every 45 minutes"`, `3600` → `"Every 1 hour"`, `30` → `"Every 30 seconds"`.

### Output style — DECISION NEEDED (see below)
Pick ONE canonical wording used in both the table and the form.

### Wiring
- `job_form_drawer.ex`: `CronPreview.preview/1` → `ScheduleDescription.preview/1` (behavior identical).
- `JobsFormatters.format_schedule/1` + `describe_cron/1` + their private cron helpers
  (`format_cron_time`, `format_cron_day`, `format_dow`, `day_name`, `parse_cron_num`, `to_12h`):
  **deleted**, replaced by a thin delegate `format_schedule(job) -> ScheduleDescription.describe(job)`.
  - Keep the *unrelated* helpers in `JobsFormatters` (badges, `job_row_state/3`, timezone
    detection, `cfg/2`) — those are not part of this dedupe.
- Callers of `format_schedule/1` (jobs_table, jobs_page) are unchanged — same function, same arity.

### Tests
- Merge `test/.../cron_preview_test.exs` + the `describe_cron`/`format_schedule` cases from
  `jobs_formatters_test.exs` into one `schedule_description_test.exs`.
- The two known-bad assertions (`"Daily at Every 4h"`, `"Daily at Every 15m"`) are **corrected**,
  not preserved — they were bugs.
- Add interval cases (`2700 → "Every 45 minutes"`).

## Out of scope
- The `next_run_at = NULL` disable-job bug (job 20) — separate issue.
- Any change to how jobs are scheduled/executed. This is display-only.

## Risk / blast radius
Display-only. No schema, no migration, no execution-path change. Worst case a schedule renders
with different wording than before — caught by tests + visual check on `/projects/1/jobs`.

## Verification
- `mix test` on both new + touched test files.
- `mix compile --warnings-as-errors`.
- Load `/projects/1/jobs` in the worktree server, confirm job 18 → "Runs daily at 8:22 AM"
  and job 19 → "Every 45 minutes"; open the create form, type a cron, confirm live preview matches.
- Codex review before merge (per project rule).

---

## The one decision I need from you: output style

Same expression `0 9 * * 1-5`, two house styles currently in the codebase:

| Style | Example (cron) | Example (interval) | Notes |
|-------|----------------|--------------------|-------|
| **A — Verbose** (CronPreview's) | `Runs Monday-Friday at 9:00 AM` | `Every 45 minutes` | Reads nicely; long for a narrow table column |
| **B — Terse** (JobsFormatters') | `Weekdays at 9 AM` | `Every 45m` | Compact; fits the table; abbreviations |

**My recommendation: B (terse)**, fixed and made consistent. The table is the space-constrained
consumer and the form has room to spare, so optimizing for the tight surface wins; "Weekdays at
9 AM" is unambiguous. I'd drop the `m`/`h` abbreviation for intervals in favor of `Every 45 min`
for readability. Tell me A or B (or a tweak) and I'll implement.
