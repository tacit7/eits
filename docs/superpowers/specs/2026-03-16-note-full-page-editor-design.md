# Note Full-Page Editor — Design Spec

**Date:** 2026-03-16
**Task:** #1372
**Route:** `/notes/:id/edit`

---

## Overview

Add a dedicated full-page CodeMirror markdown editor for notes. The existing inline editor stays untouched. A new "Open in full editor" button (expand icon, no label) on each note row navigates to the dedicated page.

---

## Route

```
live "/notes/:id/edit", NoteLive.Edit, :edit
```

Added to the authenticated LiveView scope in `router.ex`.

---

## New Files

| File | Purpose |
|------|---------|
| `lib/eye_in_the_sky_web_web/live/note_live/edit.ex` | New LiveView |
| `assets/js/hooks/note_full_editor.js` | New CodeMirror hook |

---

## Modified Files

| File | Change |
|------|--------|
| `lib/eye_in_the_sky_web_web/components/notes_list.ex` | Add `current_path` attr; add expand button per note row |
| `lib/eye_in_the_sky_web_web/router.ex` | Register new route |
| `assets/js/app.js` | Register `NoteFullEditor` hook |
| All LiveViews that render `<.notes_list>` | Pass `current_path` value |

---

## `NotesList` — expand button

Add a `current_path` attr (default `"/notes"`) to `NotesList`. Add an expand link between Edit and Delete:

```heex
<.link
  navigate={~p"/notes/#{note.id}/edit?return_to=#{@current_path}"}
  class="flex items-center gap-1 text-xs text-base-content/30 hover:text-secondary transition-colors px-1 py-0.5"
  aria-label="Open full editor"
>
  <.icon name="hero-arrows-pointing-out" class="w-3.5 h-3.5" />
</.link>
```

No `editing_note_id` logic is involved — the full-page editor is a separate page.

---

## LiveView: `NoteLive.Edit`

### Lifecycle

Following the existing codebase pattern (e.g., `PromptLive.Show`, `ProjectLive.Files`):

- `mount/3` — assigns defaults only: `note: nil`, `return_to: "/notes"`, `saved: false`, `saved_timer: nil`.
- `handle_params/3` — loads note by `:id`; loads and validates `return_to`; resets transient state (`saved: false`, cancels existing timer). Redirects with flash if note not found.

Resetting `saved` on `handle_params` prevents stale "Saved ✓" state if the LiveView process is reused for a different note ID.

### `return_to` validation

`return_to` must be validated before use to prevent open redirect:

```elixir
@valid_return_paths ["/notes", ~r|^/projects/\d+/notes$|]

defp safe_return_to(path) when is_binary(path) do
  if String.starts_with?(path, "/") and
     Enum.any?(@valid_return_paths, fn
       p when is_binary(p) -> p == path
       r -> Regex.match?(r, path)
     end),
     do: path,
     else: "/notes"
end
defp safe_return_to(_), do: "/notes"
```

### Assigns

| Key | Type | Purpose |
|-----|------|---------|
| `note` | `%Note{}` | Loaded note struct |
| `return_to` | `string` | Validated back-navigation path |
| `saved` | `boolean` | Controls save button state |
| `saved_timer` | `reference \| nil` | Timer ref; cancelled on rapid re-save to avoid early reset |

No `editing_note_id` assign — inline editing does not exist on this page.

### Events

#### `note_saved` — `%{"body" => body}`

- **Success:** `Notes.update_note(socket.assigns.note, %{body: body})`; update `@note` with returned struct; cancel existing `saved_timer` if set; set `saved: true`; schedule `:clear_saved` after 3s, store ref in `saved_timer`.
- **Failure:** do not set `saved: true`; `put_flash(:error, "Failed to save note.")`; editor contents preserved client-side.

Uses `socket.assigns.note.id` — the hook sends no `note_id`.

#### `update_title` — `%{"title" => title}`

- Trim the value. If blank after trimming, ignore (do not save empty title).
- **Success:** `Notes.update_note(socket.assigns.note, %{title: title})`; update `@note` with returned struct. Input keeps the typed value.
- **Failure:** `put_flash(:error, "Failed to update title.")`; input reverts to prior value on next render.

### Messages

| Message | Action |
|---------|--------|
| `:clear_saved` | Set `saved: false`, `saved_timer: nil` |

### Render layout

- **Header:** back link (`← Notes`, `<.link navigate={@return_to}>`), editable title `<input>` (`phx-blur="update_title"`), parent context badge, save button.
- **Editor:** `NoteFullEditorHook` div fills remaining height (`flex-1`, `overflow-hidden`). Body passed via `data-body` (HEEx attribute escaping handles HTML-special chars). For v1, this transport is acceptable; revisit if body sizes become an issue.
- **Status bar:** Markdown label, line/col display (client-side DOM only), hints: `⌘S to save` and `Esc to go back`.

Save button: "Save ⌘S" normally; green "Saved ✓" for 3s after save. No redirect on save.

### Concurrent edits / note deleted elsewhere

Out of scope for v1. Last write wins. If the note is deleted externally, the next save fails and shows a flash error.

### Parent context badge

Shows parent type and identifier — not clickable in v1:

- **Session:** `Session · <first 8 chars of UUID>`
- **Agent:** `Agent · <agent name or short UUID>`
- **Project:** `Project · <project name>`
- **Task:** `Task · #<task ID>`
- **Other / nil:** badge omitted

Reuses `parent_type_label/1` and `parent_type_class/1` helpers from `NotesList`.

---

## JS Hook: `NoteFullEditorHook`

Standalone hook object registered as `Hooks.NoteFullEditor`. Does not share stateful behavior with `NoteEditorHook`; small stateless utilities (e.g., theme detection) may be shared if they emerge naturally.

Key differences from `NoteEditorHook`:

| Concern | `NoteEditorHook` | `NoteFullEditorHook` |
|---------|-----------------|---------------------|
| Content source | `atob(dataset.body)` (base64) | `dataset.body` (plain UTF-8, HEEx-escaped) |
| Line numbers | off | `lineNumbers()` enabled |
| Status bar | none | Client-side DOM update only |
| Save payload | `{ note_id, body }` | `{ body }` only |
| Escape behavior | `pushEvent("note_edit_cancelled")` | `window.location.href = dataset.returnTo` |
| DaisyUI hack | yes | no |

### Status bar (Ln/Col)

`updateListener` extension; on cursor/selection change, reads `view.state.selection.main.head`, converts to line/col via `view.state.doc.lineAt(pos)`, updates `#note-editor-status` DOM element. No server event.

### Escape navigation

`window.location.href = this.el.dataset.returnTo`. Full browser navigation is intentional — user is leaving the editor; no LiveView next/prev note navigation exists to justify client-side routing here. `data-return-to` set from `@return_to` in template.

---

## `current_path` threading

Passed directly from each LiveView's `render/1` callsite, not stored as a dedicated assign:

| LiveView | Value passed |
|----------|-------------|
| `ProjectLive.Notes` | `~p"/projects/#{@project.id}/notes"` (computed from `@project` during render) |
| `OverviewLive.Notes` | `"/notes"` (hardcoded literal — no `handle_params` change needed) |

---

## Navigation flow

```
Notes list → expand icon → /notes/:id/edit?return_to=<origin>
  → edit → ⌘S (stays on page, button goes green for 3s)
  → ← Notes or Esc → full browser navigation back to origin
```

---

## Out of scope

- Split editor/preview (deferred)
- Auto-save / dirty-state warning on navigation
- New note creation via this route
- Real-time conflict detection
