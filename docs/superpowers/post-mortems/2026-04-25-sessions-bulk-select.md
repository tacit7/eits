# Post Mortem: Sessions Bulk Select

**Feature:** Sessions bulk-select UX (archive, delete, shift-click range, indeterminate state)
**Plan:** `docs/superpowers/plans/2026-04-24-sessions-bulk-select.md`
**Worktree:** `.claude/worktrees/2026-04-25-bulk-select`
**PR reverted:** #296 (merged without manual testing, reverted, re-implemented on dedicated port)

---

## What Went Wrong

### 1. `phx-click` on a hidden input — clicks never reached LiveView

**Plan assumed:** Pass `phx-click="toggle_select"` and `phx-value-id` into `square_checkbox` via `@rest`. The `@rest` spread puts those attrs on the hidden `<input class="sr-only">`. Clicks land on the `<label>` or the visual `<div>` inside it — not the input. LiveView never saw the click.

**Fix:** Move `phx-click` and `phx-value-id` onto the outer wrapper `<div>`, not into `square_checkbox` at all. The wrapper div is visible and receives all pointer events.

```heex
<div
  class="... absolute ... left-4 sm:left-[-0.875rem]"
  phx-click="toggle_select"
  phx-value-id={@session.id}
>
  <.square_checkbox id={"session-checkbox-#{@session.id}"} checked={@selected} ... />
</div>
```

---

### 2. `onclick="event.stopPropagation()"` killed LiveView event delegation

**Plan assumed:** Adding `onclick="event.stopPropagation()"` to the checkbox prevents the row's navigation handler from firing. In practice, LiveView registers all `phx-click` handlers at the `document` level in the bubble phase. Calling `stopPropagation()` anywhere before the event reaches `document` silently kills it — no error, no event.

**Fix:** Remove `stopPropagation()` entirely. Row navigation fires from a `phx-click` on the row element. The checkbox wrapper intercepts the click with its own `phx-click="toggle_select"` — but LiveView will fire both if they're on nested elements. The real isolation comes from not nesting the checkbox inside the navigation-triggering element, or accepting that `toggle_select` fires on checkbox click and `navigate_dm` fires elsewhere on the row.

---

### 3. Stream rows don't re-render on assign changes alone

**Plan assumed:** Updating `selected_ids` and `select_mode` assigns would cause stream rows to reflect the new state. Phoenix streams (`phx-update="stream"`) only re-render a row when `stream_insert` is explicitly called for that row. Assign changes on the socket have no effect on already-rendered stream items.

**Three places this bit us:**

#### 3a. `toggle_select` — entering select mode

When the very first row is selected (`select_mode` flips `false → true`), all other visible rows need re-insertion so their CSS classes update (checkbox visibility, `phx-click` handler changes). The plan only re-inserted the toggled row and rows whose indeterminate state changed.

**Fix:** Detect when `select_mode` changes (either direction) and bulk re-insert all visible rows.

```elixir
select_mode_changed? = prev_select_mode != new_select_mode

socket =
  Enum.reduce(visible_agents, socket, fn agent, acc ->
    if select_mode_changed? or MapSet.member?(changed_ids, Selection.normalize_id(agent.id)) do
      stream_insert(acc, :session_list, agent)
    else
      acc
    end
  end)
```

#### 3b. `toggle_select` — exiting select mode

Same issue in reverse. When the last item is deselected, `select_mode` goes `true → false` but rows stay in select-mode HTML. Users get stuck: they can't click a session to navigate, and the toolbar remains visible with 0 selected.

**Fix:** Same `select_mode_changed?` check handles both directions.

#### 3c. `select_range` — shift-click did nothing visually

`select_range` computed the correct `selected_ids` but never called `stream_insert` at all. Shift-clicking a range visually did nothing — server state updated correctly but no rows re-rendered.

**Fix:** After computing the range, bulk re-insert all visible rows.

---

### 4. Select-all toolbar checkbox alignment was off

The plan didn't account for visual alignment between the select-all checkbox in the toolbar and the per-row checkboxes. At `sm:` breakpoints the per-row checkbox overhangs the left edge of the list, so the toolbar checkbox needed a matching negative margin (`sm:-ml-5`) to align centers. Measured using `getBoundingClientRect()` via Playwright.

---

### 5. PR merged before any manual testing

The first implementation was merged to `main` as PR #296 without being tested manually in a browser. Issues 1–3 above were only discovered after the merge. The PR was reverted.

**Root cause:** The worktree server was never started; testing was deferred to "after merge."

**Fix applied:** Revert the merge, restart the worktree on a dedicated port (5002/5174), symlink assets, and test every interaction manually before re-committing.

---

### 6. Worktree had no assets on first start

Starting the worktree server without symlinking `assets/node_modules` from main resulted in unstyled pages — Vite couldn't resolve `daisyui`, `phoenix`, or any other dep.

**Fix:**

```bash
cd .claude/worktrees/2026-04-25-bulk-select/assets
ln -sf ../../../../assets/node_modules node_modules
```

This is documented in root `CLAUDE.md` but was skipped.

---

## What the Plan Got Right

- `Selection` helper module design was solid — pure functions, no socket coupling, correct MapSet invariants.
- The security requirement (scope bulk archive to `project_id`) was correctly flagged and implemented.
- `data-row-id` + `ShiftSelect` capture-phase hook design was correct.
- `select_range` server-side filtering of client-provided IDs against visible agents was correct.
- `IndeterminateCheckbox` hook via the `id`-gated `:if` branch on `square_checkbox` was the right pattern.

---

## Process Changes for Future Plans

### Always specify that `phx-click` must go on a visible, pointer-receiving element

When using `square_checkbox` (or any component with `sr-only` internals), never route `phx-click` through `@rest`. Put it on the wrapper.

### Document the stream_insert requirement explicitly in plans

Any plan that involves LiveView streams must state: "After updating assigns that affect row appearance, call `stream_insert` for every affected visible row. Assigns alone do not re-render stream items."

The plan's `select_range` step was missing this entirely.

### Mandate a dedicated port smoke-test step before any merge

Add a required step to the finishing checklist:

```
- [ ] Start worktree server on dedicated port (e.g. PORT=5002 VITE_PORT=5174)
- [ ] Symlink assets/node_modules from main
- [ ] Manually test every user-facing interaction described in the plan
- [ ] Only after manual verification: push and create PR
```

### Never rely on `stopPropagation` to isolate LiveView handlers

If two `phx-click` handlers would conflict, restructure the DOM so they don't overlap — or use a single handler that disambiguates by target. `stopPropagation` breaks document-level LiveView delegation.

---

## Files Changed (vs. Plan)

| File | Planned | Actual delta |
|------|---------|--------------|
| `session_card.ex` | Add bg tint, indeterminate attr | Also: moved phx-click to wrapper div, removed stopPropagation |
| `core_components.ex` | Add id/indeterminate/checkbox_area attrs | As planned |
| `project_sessions_table.ex` | Archive button, off-screen count, ShiftSelect wrapper | Also: toolbar checkbox alignment fix (sm:-ml-5) |
| `actions.ex` | Fix toggle_select, toggle_select_all, add select_range + archive handlers | Also: bulk stream_insert on mode change in toggle_select; stream_insert added to select_range (was missing from plan) |
| `selection.ex` | New module | As planned |
| `shift_select.js` | New hook | As planned |
| `filter_handlers.ex` | Remove selection clear | As planned |
| `loader.ex` | Add recompute_selection_metadata | As planned |
| `state.ex` | Add off_screen_selected_count, indeterminate_ids, show_archive_confirm | As planned |
