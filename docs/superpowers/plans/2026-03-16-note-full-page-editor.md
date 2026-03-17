# Note Full-Page Editor Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a dedicated `/notes/:id/edit` route with a full-height CodeMirror markdown editor, editable title, and save/back navigation — without touching the existing inline editor.

**Architecture:** New `NoteLive.Edit` LiveView handles the route; a new `NoteFullEditorHook` JS hook drives CodeMirror. The `NotesList` component gains a `current_path` attr and an expand-icon link per note row. Both notes LiveViews (`OverviewLive.Notes`, `ProjectLive.Notes`) pass `current_path` at the render callsite.

**Tech Stack:** Elixir/Phoenix LiveView, HEEx, CodeMirror 6 (`@codemirror/*` packages already installed), Tailwind CSS, ExUnit + Phoenix.LiveViewTest.

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `lib/eye_in_the_sky_web_web/live/note_live/edit.ex` | Full-page editor LiveView |
| Create | `assets/js/hooks/note_full_editor.js` | CodeMirror hook for full-page editor |
| Create | `test/eye_in_the_sky_web_web/live/note_live/edit_test.exs` | LiveView tests |
| Modify | `lib/eye_in_the_sky_web_web/router.ex` | Add route |
| Modify | `lib/eye_in_the_sky_web_web/components/notes_list.ex` | Add `current_path` attr + expand button |
| Modify | `lib/eye_in_the_sky_web_web/live/overview_live/notes.ex` | Pass `current_path` |
| Modify | `lib/eye_in_the_sky_web_web/live/project_live/notes.ex` | Pass `current_path` |
| Modify | `assets/js/app.js` | Register `NoteFullEditor` hook |

---

## Chunk 1: Route + NotesList expand button

### Task 1: Add route

**Files:**
- Modify: `lib/eye_in_the_sky_web_web/router.ex:88` (after the last `live` route in the `:app` live_session block)

- [ ] **Open `router.ex` and add the route after line 87 (`live "/dm/:session_id", DmLive, :show`):**

```elixir
live "/notes/:id/edit", NoteLive.Edit, :edit
```

The surrounding context looks like:
```elixir
      live "/dm/:session_id", DmLive, :show
      live "/notes/:id/edit", NoteLive.Edit, :edit   # <-- add this
    end
  end
```

- [ ] **Verify the router compiles (don't run the server):**

```bash
mix compile
```

Expected: no errors (the module `NoteLive.Edit` doesn't exist yet — you'll see a warning about undefined module, that's fine at this stage, or it may error; if it errors, create an empty stub first — see step below).

**If `mix compile` errors on the missing module**, create a stub at `lib/eye_in_the_sky_web_web/live/note_live/edit.ex`:

```elixir
defmodule EyeInTheSkyWebWeb.NoteLive.Edit do
  use EyeInTheSkyWebWeb, :live_view
  def mount(_params, _session, socket), do: {:ok, socket}
  def render(assigns), do: ~H"<div>stub</div>"
end
```

Then re-run `mix compile`.

- [ ] **Commit:**

```bash
git add lib/eye_in_the_sky_web_web/router.ex
git commit -m "feat: add /notes/:id/edit route"
```

---

### Task 2: Add `current_path` attr and expand button to `NotesList`

**Files:**
- Modify: `lib/eye_in_the_sky_web_web/components/notes_list.ex`

- [ ] **Write the failing test first** in a new test file `test/eye_in_the_sky_web_web/components/notes_list_test.exs`:

```elixir
defmodule EyeInTheSkyWebWeb.Components.NotesListTest do
  use EyeInTheSkyWebWeb.ConnCase
  import Phoenix.LiveViewTest
  import Phoenix.Component

  alias EyeInTheSkyWeb.Notes
  alias EyeInTheSkyWeb.Projects

  defp build_note(overrides \\ %{}) do
    {:ok, project} = Projects.create_project(%{
      name: "test-#{System.unique_integer()}",
      path: "/tmp/test",
      slug: "test-#{System.unique_integer()}"
    })
    {:ok, note} = Notes.create_note(Map.merge(%{
      parent_type: "project",
      parent_id: to_string(project.id),
      body: "# Test note\n\nsome content"
    }, overrides))
    note
  end

  test "renders expand button linking to full editor" do
    note = build_note()

    html =
      render_component(
        &EyeInTheSkyWebWeb.Components.NotesList.notes_list/1,
        notes: [note],
        starred_filter: false,
        search_query: "",
        empty_id: "test-empty",
        editing_note_id: nil,
        current_path: "/notes"
      )

    assert html =~ ~s(/notes/#{note.id}/edit)
    assert html =~ "Open full editor"
  end

  test "expand button encodes return_to from current_path" do
    note = build_note()

    html =
      render_component(
        &EyeInTheSkyWebWeb.Components.NotesList.notes_list/1,
        notes: [note],
        starred_filter: false,
        search_query: "",
        empty_id: "test-empty",
        editing_note_id: nil,
        current_path: "/projects/99/notes"
      )

    assert html =~ "return_to=%2Fprojects%2F99%2Fnotes"
  end
end
```

- [ ] **Run test to verify it fails:**

```bash
mix test test/eye_in_the_sky_web_web/components/notes_list_test.exs
```

Expected: FAIL — `current_path` attr not accepted, button not present.

- [ ] **Add `current_path` attr and expand button to `NotesList`:**

In `lib/eye_in_the_sky_web_web/components/notes_list.ex`, add the attr after the existing attrs:

```elixir
attr :current_path, :string, default: "/notes"
```

Then in the action buttons section (between the existing Edit button and Delete button), add:

```heex
<.link
  navigate={~p"/notes/#{note.id}/edit?return_to=#{@current_path}"}
  class="flex items-center gap-1 text-xs text-base-content/30 hover:text-secondary transition-colors px-1 py-0.5"
  aria-label="Open full editor"
>
  <.icon name="hero-arrows-pointing-out" class="w-3.5 h-3.5" />
</.link>
```

The existing action buttons block currently looks like:
```heex
<div class="flex items-center gap-1 flex-shrink-0">
  <!-- star button -->
  <button ... phx-click="toggle_star" ...>...</button>
  <!-- edit button -->
  <button ... phx-click="edit_note" ...>Edit</button>
  <!-- delete button -->
  <button ... phx-click="delete_note" ...>...</button>
</div>
```

Insert the expand `<.link>` between the edit button and delete button.

- [ ] **Run test to verify it passes:**

```bash
mix test test/eye_in_the_sky_web_web/components/notes_list_test.exs
```

Expected: PASS.

- [ ] **Compile check:**

```bash
mix compile
```

- [ ] **Commit:**

```bash
git add lib/eye_in_the_sky_web_web/components/notes_list.ex \
        test/eye_in_the_sky_web_web/components/notes_list_test.exs
git commit -m "feat: add expand-to-full-editor button to NotesList"
```

---

### Task 3: Pass `current_path` in both notes LiveViews

**Files:**
- Modify: `lib/eye_in_the_sky_web_web/live/overview_live/notes.ex`
- Modify: `lib/eye_in_the_sky_web_web/live/project_live/notes.ex`

- [ ] **In `OverviewLive.Notes` render, add `current_path` to `<.notes_list>`:**

The current call is:
```heex
<.notes_list
  notes={@notes}
  starred_filter={@starred_filter}
  search_query={@search_query}
  empty_id="overview-notes-empty"
/>
```

Change to:
```heex
<.notes_list
  notes={@notes}
  starred_filter={@starred_filter}
  search_query={@search_query}
  empty_id="overview-notes-empty"
  current_path="/notes"
/>
```

- [ ] **In `ProjectLive.Notes` render, add `current_path` to `<.notes_list>`:**

The current call is:
```heex
<.notes_list
  notes={@notes}
  starred_filter={@starred_filter}
  search_query={@search_query}
  empty_id="project-notes-empty"
  editing_note_id={@editing_note_id}
/>
```

Change to:
```heex
<.notes_list
  notes={@notes}
  starred_filter={@starred_filter}
  search_query={@search_query}
  empty_id="project-notes-empty"
  editing_note_id={@editing_note_id}
  current_path={~p"/projects/#{@project.id}/notes"}
/>
```

- [ ] **Compile check:**

```bash
mix compile
```

Expected: clean (no warnings about unset required attrs).

- [ ] **Commit:**

```bash
git add lib/eye_in_the_sky_web_web/live/overview_live/notes.ex \
        lib/eye_in_the_sky_web_web/live/project_live/notes.ex
git commit -m "feat: pass current_path to NotesList in notes LiveViews"
```

---

## Chunk 2: `NoteLive.Edit` LiveView

### Task 4: Write tests for `NoteLive.Edit`

**Files:**
- Create: `test/eye_in_the_sky_web_web/live/note_live/edit_test.exs`

- [ ] **Create the test file:**

```elixir
defmodule EyeInTheSkyWebWeb.NoteLive.EditTest do
  use EyeInTheSkyWebWeb.ConnCase
  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.{Notes, Projects}

  defp create_note(overrides \\ %{}) do
    {:ok, project} = Projects.create_project(%{
      name: "test-#{System.unique_integer()}",
      path: "/tmp/test",
      slug: "test-#{System.unique_integer()}"
    })
    {:ok, note} = Notes.create_note(Map.merge(%{
      parent_type: "project",
      parent_id: to_string(project.id),
      body: "# Hello\n\nWorld",
      title: "Test Note"
    }, overrides))
    note
  end

  describe "mount and render" do
    test "renders editor page with note title", %{conn: conn} do
      note = create_note()
      {:ok, view, html} = live(conn, ~p"/notes/#{note.id}/edit")

      assert html =~ "Test Note"
      assert has_element?(view, "input[name='title']")
      assert has_element?(view, "[data-body]")
    end

    test "404 redirects when note does not exist", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/notes"}}} =
               live(conn, ~p"/notes/99999999/edit")
    end

    test "return_to defaults to /notes when not provided", %{conn: conn} do
      note = create_note()
      {:ok, _view, html} = live(conn, ~p"/notes/#{note.id}/edit")

      assert html =~ "href=\"/notes\""
    end

    test "return_to accepts valid project notes path", %{conn: conn} do
      note = create_note()
      {:ok, _view, html} = live(conn, ~p"/notes/#{note.id}/edit?return_to=/projects/1/notes")

      assert html =~ "href=\"/projects/1/notes\""
    end

    test "return_to rejects external URLs", %{conn: conn} do
      note = create_note()
      {:ok, _view, html} = live(conn, ~p"/notes/#{note.id}/edit?return_to=http://evil.com")

      # Falls back to /notes
      assert html =~ "href=\"/notes\""
    end

    test "renders parent context badge for project note", %{conn: conn} do
      note = create_note()
      {:ok, _view, html} = live(conn, ~p"/notes/#{note.id}/edit")

      assert html =~ "Project"
    end
  end

  describe "note_saved event" do
    test "saves body and shows saved state", %{conn: conn} do
      note = create_note()
      {:ok, view, _html} = live(conn, ~p"/notes/#{note.id}/edit")

      render_hook(view, "note_saved", %{"body" => "# Updated\n\nNew content"})

      html = render(view)
      assert html =~ "Saved"

      updated = Notes.get_note!(note.id)
      assert updated.body == "# Updated\n\nNew content"
    end
  end

  describe "update_title event" do
    test "saves non-blank title", %{conn: conn} do
      note = create_note()
      {:ok, view, _html} = live(conn, ~p"/notes/#{note.id}/edit")

      render_hook(view, "update_title", %{"title" => "  New Title  "})

      updated = Notes.get_note!(note.id)
      assert updated.title == "New Title"
    end

    test "ignores blank title", %{conn: conn} do
      note = create_note(title: "Original")
      {:ok, view, _html} = live(conn, ~p"/notes/#{note.id}/edit")

      render_hook(view, "update_title", %{"title" => "   "})

      updated = Notes.get_note!(note.id)
      assert updated.title == "Original"
    end
  end
end
```

- [ ] **Run tests to verify they all fail:**

```bash
mix test test/eye_in_the_sky_web_web/live/note_live/edit_test.exs
```

Expected: all FAIL (module doesn't exist yet).

---

### Task 5: Implement `NoteLive.Edit`

**Files:**
- Create: `lib/eye_in_the_sky_web_web/live/note_live/edit.ex`

- [ ] **Create the directory and LiveView:**

```bash
mkdir -p lib/eye_in_the_sky_web_web/live/note_live
```

```elixir
defmodule EyeInTheSkyWebWeb.NoteLive.Edit do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.Notes
  import EyeInTheSkyWebWeb.Components.NotesList, only: [
    parent_type_label: 1,
    parent_type_class: 1,
    parent_type_icon: 1
  ]

  @valid_return_paths ["/notes", ~r|^/projects/\d+/notes$|]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:note, nil)
      |> assign(:return_to, "/notes")
      |> assign(:saved, false)
      |> assign(:saved_timer, nil)
      |> assign(:sidebar_tab, :notes)
      |> assign(:sidebar_project, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id} = params, _uri, socket) do
    # Cancel any existing timer before loading
    if socket.assigns.saved_timer do
      Process.cancel_timer(socket.assigns.saved_timer)
    end

    case Integer.parse(id) do
      {int_id, ""} ->
        case Notes.get_note(int_id) do
          nil ->
            socket =
              socket
              |> put_flash(:error, "Note not found.")
              |> push_navigate(to: "/notes")

            {:noreply, socket}

          note ->
            return_to = safe_return_to(params["return_to"])

            socket =
              socket
              |> assign(:note, note)
              |> assign(:return_to, return_to)
              |> assign(:saved, false)
              |> assign(:saved_timer, nil)
              |> assign(:page_title, "Edit Note")

            {:noreply, socket}
        end

      _ ->
        socket =
          socket
          |> put_flash(:error, "Invalid note ID.")
          |> push_navigate(to: "/notes")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("note_saved", %{"body" => body}, socket) do
    case Notes.update_note(socket.assigns.note, %{body: body}) do
      {:ok, updated_note} ->
        if socket.assigns.saved_timer do
          Process.cancel_timer(socket.assigns.saved_timer)
        end

        timer = Process.send_after(self(), :clear_saved, 3000)

        socket =
          socket
          |> assign(:note, updated_note)
          |> assign(:saved, true)
          |> assign(:saved_timer, timer)

        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save note.")}
    end
  end

  @impl true
  def handle_event("update_title", %{"title" => title}, socket) do
    trimmed = String.trim(title)

    if trimmed == "" do
      {:noreply, socket}
    else
      case Notes.update_note(socket.assigns.note, %{title: trimmed}) do
        {:ok, updated_note} ->
          {:noreply, assign(socket, :note, updated_note)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to update title.")}
      end
    end
  end

  @impl true
  def handle_info(:clear_saved, socket) do
    {:noreply, assign(socket, saved: false, saved_timer: nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-[calc(100vh-0px)] overflow-hidden">
      <%!-- Header --%>
      <div class="flex items-center gap-3 px-4 py-2.5 border-b border-base-content/8 bg-base-100 flex-shrink-0">
        <.link
          navigate={@return_to}
          class="flex items-center gap-1.5 text-xs text-base-content/40 hover:text-base-content/70 border border-base-content/10 rounded-md px-2.5 py-1.5 transition-colors flex-shrink-0"
        >
          <.icon name="hero-arrow-left" class="w-3.5 h-3.5" /> Notes
        </.link>

        <input
          type="text"
          name="title"
          value={@note.title || ""}
          placeholder="Untitled note"
          phx-blur="update_title"
          class="flex-1 bg-transparent border-none outline-none text-sm font-semibold text-base-content/90 placeholder:text-base-content/30 min-w-0 px-1 rounded focus:bg-base-200/40"
        />

        <%= if @note.parent_type do %>
          <span class={[
            "hidden sm:inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-medium flex-shrink-0",
            parent_type_class(@note.parent_type)
          ]}>
            <.icon name={parent_type_icon(@note.parent_type)} class="w-2.5 h-2.5" />
            <%= parent_type_label(@note.parent_type) %>
            <%= context_suffix(@note) %>
          </span>
        <% end %>

        <button
          type="button"
          phx-click="note_saved"
          phx-value-body=""
          id="note-save-btn"
          class={[
            "flex items-center gap-1.5 text-xs font-medium px-3 py-1.5 rounded-md transition-all flex-shrink-0",
            if(@saved,
              do: "bg-success/10 text-success border border-success/30",
              else: "bg-primary text-primary-content hover:bg-primary/80"
            )
          ]}
        >
          <%= if @saved do %>
            <.icon name="hero-check" class="w-3.5 h-3.5" /> Saved
          <% else %>
            Save <kbd class="text-[9px] opacity-70 ml-0.5">⌘S</kbd>
          <% end %>
        </button>
      </div>

      <%!-- Editor area --%>
      <div class="flex flex-1 overflow-hidden">
        <div
          id={"note-full-editor-#{@note.id}"}
          phx-hook="NoteFullEditor"
          data-body={@note.body || ""}
          data-return-to={@return_to}
          class="flex-1 overflow-hidden"
        ></div>
      </div>

      <%!-- Status bar --%>
      <div class="flex items-center justify-between px-4 py-1 border-t border-base-content/8 bg-base-100 flex-shrink-0 text-[10px] text-base-content/35">
        <div class="flex items-center gap-4">
          <span class="flex items-center gap-1">
            <span class="w-1.5 h-1.5 rounded-full bg-success inline-block"></span>
            Markdown
          </span>
          <span id="note-editor-status">Ln 1, Col 1</span>
        </div>
        <div class="flex items-center gap-4">
          <span>Esc to go back</span>
          <span>⌘S to save</span>
        </div>
      </div>
    </div>
    """
  end

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

  defp context_suffix(note) do
    case note.parent_type do
      t when t in ["session", "sessions"] ->
        " · #{String.slice(note.parent_id || "", 0, 8)}"
      t when t in ["task", "tasks"] ->
        " · ##{note.parent_id}"
      _ ->
        ""
    end
  end
end
```

**Note on the Save button:** The Save button in the header uses `phx-click="note_saved"` with an empty `phx-value-body`. The actual body comes from the hook via `pushEvent("note_saved", {body})`. The button click is a fallback visible trigger — the primary save path is ⌘S in CodeMirror which calls `pushEvent` with the real body. For the button click to work correctly, move the save logic to a JS `liveSocket.pushEvent` call triggered by the button, OR use the same `pushEvent` from the hook when the button is clicked. The simplest approach: add a `phx-click` JS hook on the button that calls the hook's save method. However, for simplicity in v1, the ⌘S shortcut is the primary save path and the button can be wired via JS (see Task 6 in the hook). Update the save button to remove `phx-click` and give it an ID the hook can reference:

```heex
<button
  type="button"
  id="note-save-btn"
  class={[...]}
>
```

The hook will attach a click listener to `#note-save-btn` and call the same save logic.

- [ ] **Run the tests:**

```bash
mix test test/eye_in_the_sky_web_web/live/note_live/edit_test.exs
```

Expected: all PASS (or close — JS hook tests won't run in LiveViewTest but server-side events will).

- [ ] **Compile check:**

```bash
mix compile --warnings-as-errors
```

- [ ] **Commit:**

```bash
git add lib/eye_in_the_sky_web_web/live/note_live/edit.ex \
        test/eye_in_the_sky_web_web/live/note_live/edit_test.exs
git commit -m "feat: add NoteLive.Edit full-page note editor"
```

---

## Chunk 3: JS Hook + App Registration

### Task 6: Implement `NoteFullEditorHook`

**Files:**
- Create: `assets/js/hooks/note_full_editor.js`
- Modify: `assets/js/app.js`

- [ ] **Create `assets/js/hooks/note_full_editor.js`:**

```javascript
// assets/js/hooks/note_full_editor.js
import {
  EditorView,
  keymap,
  highlightActiveLine,
  lineNumbers
} from "@codemirror/view"
import { EditorState } from "@codemirror/state"
import { defaultKeymap, history, historyKeymap } from "@codemirror/commands"
import { oneDark } from "@codemirror/theme-one-dark"
import { markdown } from "@codemirror/lang-markdown"

export const NoteFullEditorHook = {
  mounted() {
    const body = this.el.dataset.body || ""
    const returnTo = this.el.dataset.returnTo || "/notes"
    const self = this

    const isDark = document.documentElement.dataset.theme === "dark"

    // Status bar element (outside hook el, in the same page)
    const statusEl = document.getElementById("note-editor-status")

    const saveKeymap = keymap.of([
      {
        key: "Mod-s",
        run(view) {
          self.pushEvent("note_saved", { body: view.state.doc.toString() })
          return true
        }
      },
      {
        key: "Escape",
        run() {
          window.location.href = returnTo
          return true
        }
      }
    ])

    const statusUpdate = EditorView.updateListener.of((update) => {
      if (!update.selectionSet && !update.docChanged) return
      if (!statusEl) return
      const pos = update.state.selection.main.head
      const line = update.state.doc.lineAt(pos)
      const col = pos - line.from + 1
      statusEl.textContent = `Ln ${line.number}, Col ${col}`
    })

    const extensions = [
      lineNumbers(),
      highlightActiveLine(),
      history(),
      keymap.of([...defaultKeymap, ...historyKeymap]),
      saveKeymap,
      markdown(),
      EditorView.lineWrapping,
      statusUpdate,
    ]

    if (isDark) extensions.push(oneDark)

    const state = EditorState.create({ doc: body, extensions })
    this._view = new EditorView({ state, parent: this.el })

    // Wire save button click (button is outside hook el)
    const saveBtn = document.getElementById("note-save-btn")
    if (saveBtn) {
      this._saveBtnHandler = () => {
        self.pushEvent("note_saved", { body: self._view.state.doc.toString() })
      }
      saveBtn.addEventListener("click", this._saveBtnHandler)
    }

    this._view.focus()
  },

  destroyed() {
    const saveBtn = document.getElementById("note-save-btn")
    if (saveBtn && this._saveBtnHandler) {
      saveBtn.removeEventListener("click", this._saveBtnHandler)
    }
    if (this._view) {
      this._view.destroy()
      this._view = null
    }
  }
}
```

- [ ] **Register the hook in `assets/js/app.js`:**

Find the existing hook imports (around line 43-44):
```javascript
import {CodeMirrorHook} from "./hooks/codemirror"
import {NoteEditorHook} from "./hooks/note_editor"
```

Add after `NoteEditorHook` import:
```javascript
import {NoteFullEditorHook} from "./hooks/note_full_editor"
```

Then find where hooks are registered (search for `Hooks.CodeMirror` or `Hooks.NoteEditor`) and add:
```javascript
Hooks.NoteFullEditor = NoteFullEditorHook
```

- [ ] **Check for any JS build errors:**

```bash
cd assets && npm run build 2>&1 | head -30
```

Or just rely on Phoenix watcher output. The key check is that `mix compile` passes:

```bash
mix compile
```

- [ ] **Verify the save button in the LiveView template already has `id="note-save-btn"`** (set in Task 5). No change needed.

- [ ] **Commit:**

```bash
git add assets/js/hooks/note_full_editor.js assets/js/app.js
git commit -m "feat: add NoteFullEditorHook CodeMirror hook for full-page editor"
```

---

### Task 7: Final compile + full test run

- [ ] **Run all tests:**

```bash
mix test
```

Expected: all existing tests pass; new tests pass.

- [ ] **Compile with warnings-as-errors:**

```bash
mix compile --warnings-as-errors
```

Expected: clean.

- [ ] **Manual smoke test** (requires running server):

```bash
mix phx.server
```

1. Navigate to `/notes`
2. Find a note row — verify the expand icon (`⤢`) appears between Edit and Delete
3. Click expand icon — verify navigation to `/notes/:id/edit`
4. Verify CodeMirror loads with the note content
5. Edit text, press ⌘S — verify "Saved ✓" appears and note updates in DB
6. Press Esc — verify navigation back to `/notes`
7. Click `← Notes` back button — same result
8. Navigate from `/projects/:id/notes` expand icon — verify `return_to` takes you back to project notes

- [ ] **Final commit if any fixups were needed:**

```bash
git add -p
git commit -m "fix: note full-page editor polish"
```
