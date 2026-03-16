# CodeMirror Inline Note Editor — Design Spec

**Date:** 2026-03-15
**Status:** Approved

## Overview

Add inline editing to project notes using CodeMirror with markdown language support. Notes are currently read-only (star + delete only). This adds an Edit button per note that replaces the rendered markdown with a CodeMirror editor in place.

## Scope

- `assets/js/hooks/note_editor.js` — new Phoenix hook
- `assets/js/app.js` — register new hook
- `lib/eye_in_the_sky_web_web/components/notes_list.ex` — add edit button, conditional editor/viewer rendering
- `lib/eye_in_the_sky_web_web/live/project_live/notes.ex` — add editing state and event handlers
- `lib/eye_in_the_sky_web/notes.ex` — add `update_note/2`

Out of scope: overview notes LiveView, session/agent notes views (can be added later using the same pattern).

## JS — `NoteEditorHook`

File: `assets/js/hooks/note_editor.js`

Reuses the same CodeMirror packages already installed (`@codemirror/view`, `@codemirror/state`, `@codemirror/commands`, `@codemirror/lang-markdown`, `@codemirror/theme-one-dark`).

Differences from existing `CodeMirrorHook`:
- Markdown language only; no language switcher
- No line numbers (prose editing)
- Theme: checks `document.documentElement.dataset.theme` — if dark, applies `oneDark`; otherwise uses default light theme
- On `Mod-s`: pushes `note_saved` event with `{ note_id, body }` where `body` is the raw UTF-8 string from the editor (NOT base64 — base64 is only used for the initial load)
- On `Escape`: pushes `note_edit_cancelled` with `{ note_id }`
- `data-note-id` attribute on the element identifies the note
- `data-body` attribute contains base64-encoded note body for initial load (avoids XSS via attribute injection)
- `destroyed()` fires if the accordion is collapsed while editing — this acts as an implicit cancel. The LiveView handles the hook's absence gracefully because `editing_note_id` will be cleared on the next user interaction (Edit click or page reload). To avoid silent state drift, the hook should also push `note_edit_cancelled` in `destroyed()` if the editor has not yet saved.
- Destroys CodeMirror view on `destroyed()`

## UI — `NotesList` Component

Each note accordion item gets an **Edit** button in the action row (alongside Star and Delete).

```
[Star] [Edit] [Delete]
```

When the note's ID matches `@editing_note_id`, the collapse-content renders the `NoteEditorHook` div instead of the `MarkdownMessage` div. Below the editor, **Save (⌘S)** and **Cancel** buttons are shown. When not editing, the existing markdown renderer shows.

The collapse input (DaisyUI accordion) is controlled — when editing starts, the accordion is forced open via `checked` attribute.

## LiveView — `ProjectLive.Notes`

New assigns:
- `editing_note_id` — integer or nil

New event handlers:
- `edit_note` (phx-click) — sets `editing_note_id` to the note's ID. If another note is already being edited (`editing_note_id != nil`), the previous edit is discarded silently (no save). The new note's editor mounts.
- `note_saved` (from JS hook) — fetches note by `note_id`, calls `Notes.update_note/2` with `%{body: body}`, clears `editing_note_id`, reloads notes. On failure: puts flash error, keeps `editing_note_id` set so the editor stays mounted with content intact.
- `note_edit_cancelled` (from JS hook) — clears `editing_note_id`

## Backend — `Notes.update_note/2`

```elixir
def update_note(%Note{} = note, attrs) do
  note
  |> Note.changeset(attrs)
  |> Repo.update()
end
```

The `Note.changeset/2` already casts `body` and `title`. No schema changes required.

## Data Flow

```
User clicks Edit
  → phx-click="edit_note" note_id=N
  → LiveView sets editing_note_id = N
  → NotesList renders CodeMirror div for note N
  → NoteEditorHook mounts, loads body from data-body

User presses Cmd+S
  → NoteEditorHook pushEvent("note_saved", {note_id, body})
  → LiveView handle_event("note_saved") → Notes.update_note → reload notes → editing_note_id = nil

User presses Escape
  → NoteEditorHook pushEvent("note_edit_cancelled", {note_id})
  → LiveView clears editing_note_id → markdown renderer restores
```

## Error Handling

- If `update_note` fails: put_flash error, keep `editing_note_id` set so the editor stays mounted with content intact. LiveView patch will not re-create the hook DOM node when only assigns change (not the element itself), so unsaved content in CodeMirror is preserved.
- Note body is passed base64-encoded in `data-body` for initial load only. Saved body is sent as raw UTF-8 via `pushEvent` — no base64 decoding needed in the LiveView handler.
- Empty body is accepted (agents can create empty notes). No length cap is enforced at this layer; DB column is text/unlimited.
- Concurrent edits across tabs: last write wins. This is acceptable for a single-user tool; not addressed in this spec.

## Testing

After implementation, verify with Playwright:
1. Notes page loads and each note has an Edit button visible in the action row
2. Click Edit on a note → CodeMirror editor mounts and the note's original body text is visible in the editor
3. Modify content, press Cmd+S → editor closes, the markdown renderer re-appears with the new text content visible (assert the changed text is present in the DOM)
4. Click Edit, press Escape → editor closes, the markdown renderer shows the original unchanged text
5. Click Edit on note A, then click Edit on note B → note A's editor closes (no save), note B's editor opens
6. Collapse the accordion while editing → editor is unmounted, no crash, state resets cleanly on next interaction
