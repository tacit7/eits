# Top Bar Refactor — Phase 2 Agent Contract

Phase 1 complete (commit `03d7e668`). This doc is the contract for Phase 2 migration agents.

---

## Context

The old `top_bar/1` in `layouts.ex` was a god-object: 18+ attrs, 7-branch `cond`, all toolbar variants
crammed into private `defp` functions. Phase 1 split it into:

- An inline shell in `app.html.heex` — `<div class="hidden md:flex h-10...">` with a `case sidebar_tab`
  dispatch to typed module functions
- 6 skeleton modules in `lib/eye_in_the_sky_web/components/top_bar/`
- Public shared helpers in `layouts.ex`: `top_bar_breadcrumb/1`, `top_bar_cta/1`,
  `top_bar_section_label/1`
- The old `top_bar/1` is marked `@deprecated` — still compiles, still in place until cleanup

---

## Chrome System Alignment

The new architecture maps directly to the chrome system spec
(`docs/CHROME_SYSTEM.md`, `.claude/agent-memory/product-designer/chrome_system.md`):

```
Shell structure: [breadcrumb] [toolbar module content] [CTA]
Spec structure:  [object identity / breadcrumb] [flex-1: toolbar slot] [CTA slot]
```

### Control rules each toolbar module must enforce

| Control | Rule |
|---|---|
| Search input | `input-xs h-7 bg-base-200/50 border-base-content/8 placeholder:text-base-content/25` |
| Filter pills | `bg-base-200/40 rounded-lg p-0.5` container; active: `bg-base-100 shadow-sm text-base-content`; inactive: `text-base-content/45` |
| Sort control | `Sort: X ▾` dropdown button — see Sort Dropdown Pattern below |
| CTA | Lives in the shell (`top_bar_cta/1`) — do NOT add a CTA inside a toolbar module |
| All controls | `h-7` height, `text-[11px]` – `text-[12px]` |

### Intentional spec exceptions (do NOT revert these)

- **Notes type filter** uses a `Type: X ▾` dropdown button, not pills. 6 options is too many for
  a pill group in a top bar. This is a documented exception.
- **Notes sort** uses a `Sort: X ▾` dropdown button (Newest/Oldest). Two-option pill group was
  evaluated and rejected — it reads as a toggle, not a sort.

---

## Sort Dropdown Button Pattern

Used by sessions (sort), tasks (sort), notes (type + sort). Required: `phx-update="ignore"` +
`onclick` close on each option button.

```heex
<details id="UNIQUE-STABLE-ID" phx-update="ignore" class="dropdown">
  <summary class="flex items-center gap-1 h-7 px-2 rounded-md text-[11px] font-medium border border-base-content/8 bg-base-100 text-base-content/60 hover:text-base-content cursor-pointer select-none [list-style:none] [&::-webkit-details-marker]:hidden">
    Prefix: {current_label} <.icon name="hero-chevron-down-mini" class="w-3 h-3 opacity-50" />
  </summary>
  <ul class="dropdown-content z-50 mt-1 bg-base-100 border border-base-content/10 rounded-lg shadow-lg p-1 min-w-[120px]">
    <%= for {value, label} <- @options do %>
      <li>
        <button
          phx-click="EVENT"
          phx-value-KEY={value}
          onclick="this.closest('details').removeAttribute('open')"
          class={"block w-full px-3 py-1.5 text-left text-[11px] rounded hover:bg-base-content/5 " <>
            if(@current_assign == value, do: "text-base-content font-medium", else: "text-base-content/60")}>
          {label}
        </button>
      </li>
    <% end %>
  </ul>
</details>
```

**Why `onclick`:** Clicking a `<button>` inside `<details>` does not auto-close the `<details>`.
Without `onclick`, the dropdown stays open AND `phx-update="ignore"` prevents the summary label from
updating. The `onclick` closes the `<details>` before LiveView re-renders, allowing morphdom to
patch the summary text. Do not remove either attribute.

---

## Your job

Each agent migrates ONE toolbar's private `defp` into its own module. Steps:

1. Open `lib/eye_in_the_sky_web/components/layouts.ex`
2. Find your `defp <name>_toolbar(assigns)` function
3. Copy the `~H"""..."""` body into `def toolbar(assigns)` in your module file
4. The template uses `@assigns` — in the new module only declared `attr`s are available. Verify
   every assign referenced in the template is declared in the module's `attr` list. Add any missing
   ones.
5. Remove any `{assigns}` spread calls to nested components (not applicable here — these are leaf
   functions)
6. Run `mix compile` — no errors (unused import warnings from OTHER empty skeleton files are fine)
7. Do NOT remove the `defp` from `layouts.ex` — cleanup is a separate commit after all modules land

---

## Per-agent file assignments

### agent-sessions

**Module:** `lib/eye_in_the_sky_web/components/top_bar/sessions.ex`
**Source:** `defp sessions_toolbar(assigns)` in `layouts.ex`
**Attrs declared:** `search_query`, `session_filter`, `sort_by`
**Events:** `phx-change="search"`, `phx-click="filter_session" phx-value-filter`,
`phx-click="sort" phx-value-by`
**Note:** Sort is already a dropdown button (migrated 2026-04-27). Migrate verbatim.

### agent-tasks

**Module:** `lib/eye_in_the_sky_web/components/top_bar/tasks.ex`
**Source:** `defp tasks_toolbar(assigns)` in `layouts.ex`
**Attrs declared:** `search_query`, `filter_state_id`, `workflow_states`, `sort_by`
**Events:** `phx-change="search"`, `phx-click="filter_status" phx-value-state_id`,
`phx-click="sort_by" phx-value-value`
**Note:** Sort is already a dropdown button. Migrate verbatim.

### agent-notes

**Module:** `lib/eye_in_the_sky_web/components/top_bar/notes.ex`
**Source:** `defp notes_toolbar(assigns)` in `layouts.ex`
**Attrs declared:** `search_query`, `notes_sort_by`, `notes_starred_filter`, `notes_type_filter`,
`notes_new_href`
**Events:** `phx-change="search"`, `phx-click="toggle_starred_filter"`,
`phx-click="filter_type" phx-value-value`, `phx-click="sort_notes" phx-value-value`
**Note:** Type filter and sort are already dropdown buttons (migrated 2026-04-27). Migrate verbatim.

### agent-dm

**Module:** `lib/eye_in_the_sky_web/components/top_bar/dm.ex`
**Source:** `defp dm_toolbar(assigns)` in `layouts.ex`
**Attrs declared:** `dm_active_tab`, `dm_message_search_query`, `dm_active_timer`
**Events:** `phx-change="search_messages"`, `phx-click="change_tab" phx-value-tab`,
`JS.dispatch("dm:reload-check", ...)`, `phx-click="export_markdown"`,
`phx-click="open_schedule_timer"`, `phx-click="cancel_timer"`
**Note:** The DM toolbar has an ellipsis dropdown menu (Reload / Export / Schedule). The `JS` alias
is already imported in `dm.ex`. Migrate verbatim.

### agent-kanban

**Module:** `lib/eye_in_the_sky_web/components/top_bar/kanban.ex`
**Source:** `defp kanban_toolbar(assigns)` in `layouts.ex`
**Attrs declared:** `search_query`, `show_completed`, `bulk_mode`, `active_filter_count`,
`sidebar_project`
**Events:** `phx-change="search"`, `phx-click="toggle_show_completed"`,
`phx-click="toggle_bulk_mode"`, `phx-click="toggle_filter_drawer"`, navigate to list view
**IMPORTANT — Board selection mode:** The chrome system spec requires that when `@bulk_mode == true`,
the toolbar swaps entirely. Do NOT just migrate the existing defp verbatim. The existing defp shows
both the search and the action buttons together regardless of bulk_mode.

Implement this conditional:
- When `@bulk_mode == false` (default): render the existing search + Done/Select/Filter/List buttons
- When `@bulk_mode == true`: hide everything and render a selection mode bar:
  `[flex-1 spacer][{N selected — you don't have the count, just "Selection mode"}][Done btn][Cancel btn]`
  Done fires `phx-click="toggle_show_completed"` (keep Done for "show completed" toggle separate —
  actually Done here should mean "exit bulk + apply"; look at the kanban LiveView for the right event).
  Cancel fires `phx-click="toggle_bulk_mode"` (exits bulk mode).
  **Check `lib/eye_in_the_sky_web/live/project_live/kanban.ex` for the handle_event names before
  implementing.**

**Do NOT confuse with:** `lib/eye_in_the_sky_web/components/kanban_toolbar.ex` — that is the
in-page mobile-responsive toolbar. You are migrating the TOP BAR version (compact h-7 controls).

### agent-generic

**Module:** `lib/eye_in_the_sky_web/components/top_bar/generic.ex`
**Sources:**
- `defp generic_search_toolbar(assigns)` → `def toolbar(assigns)`
- `defp default_toolbar(assigns)` → `def default_toolbar(assigns)`

**Attrs declared (toolbar):** `search_query`
**Attrs declared (default_toolbar):** none
**Events (toolbar):** `phx-change="search"`
**Events (default_toolbar):** `JS.dispatch("palette:open", to: "#command-palette")`
**Note:** The `JS` alias is already imported in `generic.ex`. Migrate both functions.

---

## File ownership (CRITICAL — enforces zero merge conflicts)

Each agent:
- **OWNS:** their single `lib/eye_in_the_sky_web/components/top_bar/<name>.ex` file
- **READS (do not edit):** `layouts.ex` — source of truth for template content
- **DO NOT TOUCH:** `app.html.heex`, any LiveView file, any other component, any other top_bar module

---

## Completion checklist

1. `mix compile` in the worktree — no errors
2. `eits tasks complete <task_id> --message "Migrated <name>_toolbar to EyeInTheSkyWeb.TopBar.<Name>"`
3. `eits commits create --hash <hash>`
4. `eits dm --to 1751d04f-699f-41e4-bf5d-89f70d7a6479 --message "agent-<name> done: <branch>"`

---

## After all agents complete (orchestrator cleanup)

Once all 6 modules have content:
1. Remove all `defp *_toolbar(assigns)` private functions from `layouts.ex`
2. Remove the `@deprecated top_bar/1` function entirely
3. Remove the old `attr` declarations from `top_bar/1` (already removed with the function)
4. Final `mix compile` — at this point all unused import warnings in top_bar modules disappear
