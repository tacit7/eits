# CodeMirror Inline Note Editor Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add inline CodeMirror editing to notes in the project notes view, replacing the read-only markdown renderer with an editor when the user clicks Edit.

**Architecture:** A new `NoteEditorHook` JS hook handles CodeMirror lifecycle and pushes `note_saved`/`note_edit_cancelled` events to the LiveView. The `NotesList` component conditionally renders the editor div or the markdown renderer based on `editing_note_id`. The LiveView tracks which note is being edited and persists changes via `Notes.update_note/2`.

**Tech Stack:** CodeMirror 6 (already installed), Phoenix LiveView hooks, Elixir/Ecto, DaisyUI accordion

**Spec:** `docs/superpowers/specs/2026-03-15-codemirror-note-editor-design.md`

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `lib/eye_in_the_sky_web/notes.ex` | Add `update_note/2` |
| Create | `assets/js/hooks/note_editor.js` | CodeMirror hook for note editing |
| Modify | `assets/js/app.js` | Register `NoteEditor` hook |
| Modify | `lib/eye_in_the_sky_web_web/components/notes_list.ex` | Edit button + conditional editor/viewer |
| Modify | `lib/eye_in_the_sky_web_web/live/project_live/notes.ex` | `editing_note_id` state + event handlers |
| Create | `test/playwright/note_editor_test.js` | Playwright integration tests |

**Key constraint:** `Note.changeset/2` has `validate_required([:body])` — saving an empty body will fail validation and trigger the error flash path. This is correct behavior.

---

## Chunk 1: Backend — `Notes.update_note/2`

### Task 1: Add `update_note/2` to Notes context

**Files:**
- Modify: `lib/eye_in_the_sky_web/notes.ex`

- [ ] **Step 1: Open `lib/eye_in_the_sky_web/notes.ex` and locate `delete_note/1` (around line 176)**

- [ ] **Step 2: Add `update_note/2` directly after `delete_note/1`**

```elixir
@doc """
Updates a note's body (and optionally title).
"""
def update_note(%Note{} = note, attrs) do
  note
  |> Note.changeset(attrs)
  |> Repo.update()
end
```

- [ ] **Step 3: Verify compilation**

```bash
mix compile
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/eye_in_the_sky_web/notes.ex
git commit -m "feat: add Notes.update_note/2"
```

---

## Chunk 2: JS Hook — `NoteEditorHook`

### Task 2: Create the hook and register it

**Files:**
- Create: `assets/js/hooks/note_editor.js`
- Modify: `assets/js/app.js`

**Context:** All CodeMirror packages are already installed — see `assets/js/hooks/codemirror.js` for the existing import pattern. The hook uses `atob()` to decode the base64 note body from `data-body`. Theme detection reads `document.documentElement.dataset.theme`.

- [ ] **Step 1: Create `assets/js/hooks/note_editor.js`**

```javascript
// assets/js/hooks/note_editor.js
import { EditorView, keymap, highlightActiveLine } from "@codemirror/view"
import { EditorState } from "@codemirror/state"
import { defaultKeymap, history, historyKeymap } from "@codemirror/commands"
import { oneDark } from "@codemirror/theme-one-dark"
import { markdown } from "@codemirror/lang-markdown"

export const NoteEditorHook = {
  mounted() {
    const body = atob(this.el.dataset.body || "")
    const noteId = this.el.dataset.noteId
    this._saved = false
    const self = this

    const isDark = document.documentElement.dataset.theme === "dark"

    const saveKeymap = keymap.of([{
      key: "Mod-s",
      run(view) {
        self._saved = true
        self.pushEvent("note_saved", {
          note_id: noteId,
          body: view.state.doc.toString()
        })
        return true
      }
    }, {
      key: "Escape",
      run() {
        self.pushEvent("note_edit_cancelled", { note_id: noteId })
        return true
      }
    }])

    const extensions = [
      highlightActiveLine(),
      history(),
      keymap.of([...defaultKeymap, ...historyKeymap]),
      saveKeymap,
      markdown(),
      EditorView.lineWrapping,
    ]

    if (isDark) extensions.push(oneDark)

    const state = EditorState.create({ doc: body, extensions })
    this._view = new EditorView({ state, parent: this.el })

    // Force the DaisyUI accordion open. LiveView does not re-set checked on
    // existing inputs after initial render, so we must do it imperatively.
    const collapseInput = this.el.closest(".collapse")?.querySelector("input[type=checkbox]")
    if (collapseInput) collapseInput.checked = true

    this._view.focus()
  },

  destroyed() {
    // pushEvent from destroyed() is best-effort — it may not reach the server
    // if the socket is already torn down. The LiveView recovers on the next
    // user interaction (clicking Edit again or page reload).
    if (!this._saved) {
      try { this.pushEvent("note_edit_cancelled", { note_id: this.el.dataset.noteId }) } catch (_) {}
    }
    if (this._view) {
      this._view.destroy()
      this._view = null
    }
  }
}
```

- [ ] **Step 2: Add import to `assets/js/app.js` after the CodeMirror import (line ~43)**

```javascript
import {NoteEditorHook} from "./hooks/note_editor"
```

- [ ] **Step 3: Register the hook in `assets/js/app.js` after `Hooks.CodeMirror = CodeMirrorHook` (line ~100)**

```javascript
Hooks.NoteEditor = NoteEditorHook
```

- [ ] **Step 4: Compile to verify the JS builds**

```bash
mix compile
```

Expected: clean compile.

- [ ] **Step 5: Commit**

```bash
git add assets/js/hooks/note_editor.js assets/js/app.js
git commit -m "feat: add NoteEditorHook for inline note editing"
```

---

## Chunk 3: Component — `NotesList` with Edit button

### Task 3: Update `NotesList` to support inline editing

**Files:**
- Modify: `lib/eye_in_the_sky_web_web/components/notes_list.ex`

**Context:** The component renders a DaisyUI collapse/accordion per note. The `<input type="checkbox">` inside the collapse controls open/closed state. Setting `checked={note.id == @editing_note_id}` in HEEx handles the initial render, but LiveView does not re-patch `checked` on existing inputs after the initial mount — so the accordion is forced open **imperatively** from inside `NoteEditorHook.mounted()` by finding and setting the parent collapse input. The `MarkdownMessage` div and `NoteEditorHook` div are mutually exclusive based on `@editing_note_id`.

- [ ] **Step 1: Add `editing_note_id` attr to `notes_list/1`**

In `lib/eye_in_the_sky_web_web/components/notes_list.ex`, add to the attr declarations at the top of `notes_list/1`:

```elixir
attr :editing_note_id, :integer, default: nil
```

- [ ] **Step 2: Replace the entire per-note collapse block (the `for note <- @notes` body, roughly lines 57–115)**

Replace the existing `<div class="collapse collapse-arrow">` block with:

```heex
<div class="collapse collapse-arrow">
  <input type="checkbox" class="min-h-0 p-0" checked={note.id == @editing_note_id} />
  <div class="collapse-title py-3.5 px-0 min-h-0 flex flex-col gap-1">
    <div class="flex items-center gap-2 pr-6">
      <%= if note.starred == 1 do %>
        <.icon name="hero-star-solid" class="w-3.5 h-3.5 text-warning flex-shrink-0" />
      <% end %>
      <span class="text-sm font-medium text-base-content/85 truncate">
        {note.title || extract_title(note.body)}
      </span>
    </div>
    <div class="flex items-center gap-1.5 text-xs text-base-content/40">
      <span class={[
        "inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-medium",
        parent_type_class(note.parent_type)
      ]}>
        <.icon name={parent_type_icon(note.parent_type)} class="w-2.5 h-2.5" />
        {parent_type_label(note.parent_type)}
      </span>
      <span class="text-base-content/20">&middot;</span>
      <span class="font-mono tabular-nums">{format_date(note.created_at)}</span>
    </div>
  </div>
  <div class="collapse-content px-0 pb-4">
    <%= if note.id == @editing_note_id do %>
      <div
        id={"note-editor-#{note.id}"}
        phx-hook="NoteEditor"
        data-note-id={note.id}
        data-body={Base.encode64(note.body || "")}
        class="border border-base-content/10 rounded-lg overflow-hidden min-h-[200px]"
      ></div>
      <div class="mt-2 flex items-center gap-3">
        <span class="text-xs text-base-content/40">⌘S to save</span>
        <button
          type="button"
          phx-click="note_edit_cancelled"
          phx-value-note_id={note.id}
          class="flex items-center gap-1.5 text-xs text-base-content/30 hover:text-base-content/60 transition-colors px-1"
        >
          Cancel
        </button>
      </div>
    <% else %>
      <div
        id={"note-body-#{note.id}"}
        class="dm-markdown text-sm text-base-content/70 leading-relaxed"
        phx-hook="MarkdownMessage"
        data-raw-body={note.body}
      >
      </div>
      <div class="mt-3 flex items-center gap-3">
        <button
          type="button"
          phx-click="toggle_star"
          phx-value-note_id={note.id}
          class="flex items-center gap-1.5 text-xs text-base-content/30 hover:text-warning transition-colors min-h-[44px] md:min-h-0 px-1"
          aria-label={if note.starred == 1, do: "Unstar note", else: "Star note"}
          aria-pressed={note.starred == 1}
        >
          <.icon
            name={if note.starred == 1, do: "hero-star-solid", else: "hero-star"}
            class={"w-3.5 h-3.5 #{if note.starred == 1, do: "text-warning", else: ""}"}
          />
          {if note.starred == 1, do: "Starred", else: "Star"}
        </button>
        <button
          type="button"
          phx-click="edit_note"
          phx-value-note_id={note.id}
          class="flex items-center gap-1.5 text-xs text-base-content/30 hover:text-primary transition-colors min-h-[44px] md:min-h-0 px-1"
          aria-label="Edit note"
        >
          <.icon name="hero-pencil-square" class="w-3.5 h-3.5" /> Edit
        </button>
        <button
          type="button"
          phx-click="delete_note"
          phx-value-note_id={note.id}
          data-confirm="Delete this note?"
          class="flex items-center gap-1.5 text-xs text-base-content/30 hover:text-error transition-colors min-h-[44px] md:min-h-0 px-1"
          aria-label="Delete note"
        >
          <.icon name="hero-trash" class="w-3.5 h-3.5" /> Delete
        </button>
      </div>
    <% end %>
  </div>
</div>
```

- [ ] **Step 3: Compile to verify no HEEx errors**

```bash
mix compile
```

Expected: clean compile.

- [ ] **Step 4: Commit**

```bash
git add lib/eye_in_the_sky_web_web/components/notes_list.ex
git commit -m "feat: add Edit button and conditional CodeMirror/markdown rendering to NotesList"
```

---

## Chunk 4: LiveView — Event Handlers

### Task 4: Add `editing_note_id` state and handlers to `ProjectLive.Notes`

**Files:**
- Modify: `lib/eye_in_the_sky_web_web/live/project_live/notes.ex`

**Context:** `note_edit_cancelled` is handled by both the JS hook (via `pushEvent`) and the Cancel button (via `phx-click`). The handler ignores params with `_params` since both sources send different shapes. The `note_saved` handler fetches the note by integer ID before updating.

- [ ] **Step 1: Add `editing_note_id: nil` to BOTH branches of `mount/3`**

The `mount/3` has an `if project_id do ... else ... end` block. Add `|> assign(:editing_note_id, nil)` in **both** branches — after `|> assign(:notes, [])` in the success branch, and after `|> assign(:notes, [])` in the error branch. Missing it in the else branch will crash the LiveView when the project ID is invalid.

```elixir
# success branch — add after |> assign(:notes, [])
|> assign(:editing_note_id, nil)
|> load_notes()

# error branch — add after |> assign(:notes, [])
|> assign(:editing_note_id, nil)
|> put_flash(:error, "Invalid project ID")
```

- [ ] **Step 2: Update the `<.notes_list>` call in `render/1` to pass `editing_note_id`**

```heex
<.notes_list
  notes={@notes}
  starred_filter={@starred_filter}
  search_query={@search_query}
  empty_id="project-notes-empty"
  editing_note_id={@editing_note_id}
/>
```

- [ ] **Step 3: Add `edit_note` handler after the existing `handle_event` clauses**

```elixir
@impl true
def handle_event("edit_note", %{"note_id" => note_id}, socket) do
  {:noreply, assign(socket, :editing_note_id, String.to_integer(note_id))}
end
```

- [ ] **Step 4: Add `note_saved` handler**

```elixir
@impl true
def handle_event("note_saved", %{"note_id" => note_id, "body" => body}, socket) do
  note = Notes.get_note!(String.to_integer(note_id))

  case Notes.update_note(note, %{body: body}) do
    {:ok, _note} ->
      socket =
        socket
        |> assign(:editing_note_id, nil)
        |> load_notes()
      {:noreply, socket}

    {:error, _changeset} ->
      {:noreply, put_flash(socket, :error, "Failed to save note.")}
  end
end
```

- [ ] **Step 5: Add `note_edit_cancelled` handler**

```elixir
@impl true
def handle_event("note_edit_cancelled", _params, socket) do
  {:noreply, assign(socket, :editing_note_id, nil)}
end
```

- [ ] **Step 6: Compile to verify**

```bash
mix compile
```

Expected: clean compile, no errors.

- [ ] **Step 7: Commit**

```bash
git add lib/eye_in_the_sky_web_web/live/project_live/notes.ex
git commit -m "feat: add editing_note_id state and note save/cancel handlers to ProjectLive.Notes"
```

---

## Chunk 5: Playwright Tests

### Task 5: Write and run Playwright integration tests

**Files:**
- Create: `test/playwright/note_editor_test.js`

**Before running:** The dev server must be running (`mix phx.server`). At least one note must exist for project 1 — create one via the UI or API if needed.

- [ ] **Step 1: Check Playwright availability**

```bash
ls /Users/urielmaldonado/projects/eits/web/assets/node_modules/.bin/playwright 2>/dev/null && echo "found" || echo "not found"
```

If not found, install: `cd assets && npm install --save-dev @playwright/test && npx playwright install chromium`

- [ ] **Step 2: Create `test/playwright/note_editor_test.js`**

```javascript
// test/playwright/note_editor_test.js
const { test, expect, chromium } = require('@playwright/test')

const BASE_URL = 'http://localhost:5001'

test.describe('Note inline editor', () => {
  let browser, page

  test.beforeAll(async () => {
    browser = await chromium.launch()
  })

  test.afterAll(async () => {
    await browser.close()
  })

  test.beforeEach(async () => {
    page = await browser.newPage()
    await page.goto(`${BASE_URL}/projects/1/notes`)
    await page.waitForSelector('[phx-click="edit_note"]', { timeout: 5000 })
  })

  test.afterEach(async () => {
    await page.close()
  })

  test('1. notes page shows Edit button per note', async () => {
    const editButtons = await page.locator('[phx-click="edit_note"]').count()
    expect(editButtons).toBeGreaterThan(0)
  })

  test('2. clicking Edit mounts CodeMirror with note content', async () => {
    await page.locator('[phx-click="edit_note"]').first().click()
    const editor = page.locator('[phx-hook="NoteEditor"]').first()
    await expect(editor).toBeVisible({ timeout: 3000 })
    await expect(editor.locator('.cm-content')).toBeVisible()
  })

  test('3. Cmd+S saves and shows updated content in markdown', async () => {
    await page.locator('[phx-click="edit_note"]').first().click()
    const editor = page.locator('[phx-hook="NoteEditor"]').first()
    await expect(editor).toBeVisible({ timeout: 3000 })

    await editor.locator('.cm-content').click()
    await page.keyboard.press('Meta+a')
    const uniqueText = `Test save ${Date.now()}`
    await page.keyboard.type(uniqueText)
    await page.keyboard.press('Meta+s')

    await expect(editor).not.toBeVisible({ timeout: 3000 })
    await expect(page.locator('[id^="note-body-"]').first()).toContainText(uniqueText, { timeout: 3000 })
  })

  test('4. Escape cancels edit and restores markdown renderer', async () => {
    await page.locator('[phx-click="edit_note"]').first().click()
    const editor = page.locator('[phx-hook="NoteEditor"]').first()
    await expect(editor).toBeVisible({ timeout: 3000 })

    await page.keyboard.press('Escape')

    await expect(editor).not.toBeVisible({ timeout: 3000 })
    await expect(page.locator('[id^="note-body-"]').first()).toBeVisible()
  })

  test('5. clicking Edit on note B while editing note A switches editors', async () => {
    const editButtons = page.locator('[phx-click="edit_note"]')
    if (await editButtons.count() < 2) test.skip()

    await editButtons.nth(0).click()
    await expect(page.locator('[phx-hook="NoteEditor"]').first()).toBeVisible({ timeout: 3000 })

    const secondNoteId = await editButtons.nth(1).getAttribute('phx-value-note_id')
    await editButtons.nth(1).click()

    await expect(page.locator(`#note-editor-${secondNoteId}`)).toBeVisible({ timeout: 3000 })
  })
})
```

- [ ] **Step 3: Run the tests**

```bash
cd /Users/urielmaldonado/projects/eits/web/assets && npx playwright test ../test/playwright/note_editor_test.js --reporter=line
```

Expected: all 5 tests pass. If any fail, fix the relevant LiveView/component code and re-run before proceeding.

- [ ] **Step 4: Commit**

```bash
git add test/playwright/note_editor_test.js
git commit -m "test: add Playwright tests for CodeMirror inline note editor"
```

---

## Completion Checklist

- [ ] `mix compile` clean
- [ ] All 5 Playwright tests pass
- [ ] Accordion forced open when editing (no manual expand needed)
- [ ] Cancel button, Escape key, and accordion collapse all clear editing state
- [ ] Save failure shows flash error and preserves the editor

## Notes for Implementer

- `note_edit_cancelled` is fired from both the JS hook (`pushEvent`) and the Cancel button (`phx-click`). The handler uses `_params` intentionally — both sources send different shapes and neither is needed.
- `data-body` uses `Base.encode64/1` (Elixir) to safely embed the body in an HTML attribute. The hook decodes it with `atob()`.
- `validate_required([:body])` is already on `Note.changeset/2` — saving empty content will fail and show the error flash. Correct behavior.
- The `checked` attribute on the DaisyUI accordion `<input>` is patched by LiveView as long as the wrapper element is not inside `phx-update="ignore"`.
