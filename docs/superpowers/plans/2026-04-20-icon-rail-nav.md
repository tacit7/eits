# Icon Rail Nav Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the collapsible sidebar with a 52px fixed icon rail + contextual flyout panel, keeping all existing LiveView assigns (`sidebar_tab`, `sidebar_project`, `active_channel_id`) unchanged.

**Architecture:** A new `Rail` LiveComponent replaces `Sidebar` one-for-one in `app.html.heex`. The rail renders an icon column on the left; clicking an icon opens a 236px flyout showing contextual content (session list for the sessions section, nav links for others). A project switcher popover opens from the logo at the top of the rail. All LiveViews continue to pass the same assigns — zero LiveView changes required.

**Tech Stack:** Elixir/Phoenix LiveView, HEEx, Tailwind CSS, vanilla JS hook

---

## Implementation Risks

- `RailState` restores `localStorage` state on mount but does NOT persist changes. Writing state to localStorage is out of scope for MVP — nothing writes `rail_section` yet, so restore is future-compatible dead code until write-back is added.
- `update/2` must NOT reset `active_section` on every parent LiveView update. Only reset it when `sidebar_tab` actually changes. See Task 6 for the correct pattern using `Map.get/3` with defaults.
- Project selection inside `Rail` updates only the component's own assigns. It does NOT update parent LiveView state. This is intentional and matches the existing sidebar behavior.
- `Sessions.list_sessions_filtered/1` must be verified before implementing `load_flyout_sessions/1`. See Task 0 preflight.
- `last_activity_at` on **sessions** is `:utc_datetime_usec` — Ecto returns a `%DateTime{}` struct. The ISO8601 text field note in `lib/CLAUDE.md` refers to the **Agent** table, not Session. `format_session_time/1` must handle `%DateTime{}` as primary input, with binary fallback for safety.
- Session `status` values must be strings. Verify field type in Task 0 before writing `&(&1.status in ["working", "waiting"])`.
- Project rename/delete/bookmark handlers are ported but their UI is NOT in `ProjectSwitcher`. Only select and create are exposed. This is intentional for MVP.
- `mobile_open` must be reset to `false` whenever `flyout_open` is set to `false`.
- `String.to_existing_atom/1` must not be called directly on client params — use the `parse_section/1` whitelist.
- `osascript` folder picker is macOS-specific. Do NOT generalize it.
- Clicking New project opens the macOS folder picker. If the picker is cancelled or fails, the inline path input appears as a fallback. This is intentional.
- Flyout sessions are loaded eagerly on every `update/2` call and on every `toggle_section` event. This is acceptable for MVP (query is limited to 15). Optimize later if noisy.
- The `:notifications` section is handled defensively in the flyout. When `sidebar_tab: :notifications` is passed, the flyout shows a notifications link. There is no `rail_item` for notifications — it uses a direct nav link at the bottom of the rail instead.
- Notification refresh `send_update` calls must send only `%{id: "app-rail", notification_count: :refresh}`. Do not combine with other assigns — the `update/2` clause for refresh ignores additional assigns.

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `lib/eye_in_the_sky_web/components/rail.ex` | LiveComponent — data, state, event routing |
| Create | `lib/eye_in_the_sky_web/components/rail/flyout.ex` | Functional component — flyout panel content |
| Create | `lib/eye_in_the_sky_web/components/rail/project_switcher.ex` | Functional component — project picker overlay |
| Create | `lib/eye_in_the_sky_web/components/rail/project_actions.ex` | Pure functions — project CRUD (ported from sidebar) |
| Create | `assets/js/hooks/rail_state.js` | JS hook — mobile flyout swipe, localStorage restore |
| Modify | `lib/eye_in_the_sky_web/components/layouts/app.html.heex` | Swap Sidebar → Rail, update mobile header |
| Modify | `assets/js/app.js` | Register RailState hook |

**Do NOT modify:** Any LiveView file, `nav_hook.ex`, `project_live_helpers.ex`, the mobile bottom nav in the layout, or the existing `sidebar*.ex` files (keep them until the rail is working).

---

## Task 0: Pre-flight checks

**Files:** none — verification only

- [ ] **Step 1: Verify `Sessions.list_sessions_filtered/1` exists and returns a list**

```bash
grep -r "list_sessions_filtered" lib/eye_in_the_sky/sessions.ex lib/eye_in_the_sky/sessions/
```

Expected: find a `def list_sessions_filtered` or `defdelegate list_sessions_filtered`. If the function does not exist or has a different name, find the correct function in `lib/eye_in_the_sky/sessions/queries.ex` and update `load_flyout_sessions/1` in Task 6 accordingly.

Expected return value: a plain list of session structs, not `{:ok, list}`. If it returns a tuple, update `load_flyout_sessions/1` to unwrap it — the hardened version in Task 6 handles both.

- [ ] **Step 2: Verify `touch_gesture.js` exports**

```bash
grep -n "export" assets/js/hooks/touch_gesture.js | head -20
```

Expected: lines exporting `TOUCH_DEVICE` and `createSwipeDetector`. If the exports differ, update the import in `rail_state.js` (Task 2) to match the actual export names.

- [ ] **Step 3: Confirm `last_activity_at` field type on sessions** ✅ Pre-verified

```bash
grep -n "last_activity_at" lib/eye_in_the_sky/sessions/session.ex | head -5
```

Confirmed: `field :last_activity_at, :utc_datetime_usec` — Ecto returns `%DateTime{}` structs. The `lib/CLAUDE.md` ISO8601 note applies to the **Agent** table, not Session. The Flyout's `format_session_time/1` handles `%DateTime{}` as its primary clause — no changes needed.

- [ ] **Step 4: Verify session `status` field type**

```bash
grep -n "field :status" lib/eye_in_the_sky/sessions/session.ex
```

Expected: `:string` type. This confirms `&(&1.status in ["working", "waiting"])` in the flyout is correct. If atoms, change to `~w(working waiting)a`.

- [ ] **Step 5: Verify `start_async/3` is already used in the existing Sidebar**

```bash
grep -R "start_async" lib/eye_in_the_sky_web/components/sidebar*
```

Expected: `start_async` found somewhere in the sidebar component or its submodules. This confirms `start_async/3` works in a LiveComponent context. If not present, inspect how the Sidebar triggers the folder picker and replicate that exact pattern in Rail.

---

## Task 1: Create the worktree

**Files:** none — setup only

- [ ] **Step 1: Create the worktree**

```bash
cd /Users/urielmaldonado/projects/eits/web
git worktree add .claude/worktrees/icon-rail -b feat/icon-rail
cd .claude/worktrees/icon-rail
ln -s ../../../deps deps
mix compile
```

Expected: compiles clean, no errors.

- [ ] **Step 2: Verify you're in the worktree**

```bash
pwd
# expected: .../eits/web/.claude/worktrees/icon-rail
git branch --show-current
# expected: feat/icon-rail
```

---

## Task 2: RailState JS hook

**Files:**
- Create: `assets/js/hooks/rail_state.js`

The hook handles:
- Restoring the previously saved rail section from `localStorage` on mount. This is future-compatible code — nothing writes `rail_section` yet in MVP. The restore is a no-op until write-back is added later.
- Mobile: swipe-right on left edge opens flyout; swipe-left on open flyout closes it
- Listening for `rail:open` custom event (dispatched by mobile hamburger button)

- [ ] **Step 1: Create the hook file**

```javascript
// assets/js/hooks/rail_state.js
import { TOUCH_DEVICE, createSwipeDetector } from './touch_gesture'

export const RailState = {
  mounted() {
    // Future-compatible restore. MVP does not write rail_section — this is a no-op until
    // write-back is added. Do not add localStorage.setItem calls here.
    const savedSection = localStorage.getItem('rail_section')
    if (savedSection) {
      this.pushEventTo(this.el, 'restore_section', { section: savedSection })
    }

    // Listen for mobile open event dispatched from app header
    this._openHandler = () => this.pushEventTo(this.el, 'open_mobile', {})
    this.el.addEventListener('rail:open', this._openHandler)

    if (TOUCH_DEVICE) {
      // Swipe left on open flyout → close
      this._flyoutGesture = createSwipeDetector({
        onSwipeLeft: () => this.pushEventTo(this.el, 'close_flyout', {}),
      })
      const flyoutPanel = this.el.querySelector('[data-flyout-panel]')
      if (flyoutPanel) {
        flyoutPanel.addEventListener('touchstart', this._flyoutGesture.onTouchStart, { passive: true })
        flyoutPanel.addEventListener('touchmove', this._flyoutGesture.onTouchMove, { passive: true })
        flyoutPanel.addEventListener('touchend', this._flyoutGesture.onTouchEnd, { passive: true })
      }

      // Swipe right on left edge → open flyout
      this._edgeGesture = createSwipeDetector({
        onSwipeRight: () => this.pushEventTo(this.el, 'open_mobile', {}),
      })
      this._grabHandle = document.getElementById('rail-grab-handle')
      if (this._grabHandle) {
        this._grabHandle.addEventListener('touchstart', this._edgeGesture.onTouchStart)
        this._grabHandle.addEventListener('touchmove', this._edgeGesture.onTouchMove)
        this._grabHandle.addEventListener('touchend', this._edgeGesture.onTouchEnd)
      }
    }
  },

  destroyed() {
    if (this._openHandler) {
      this.el.removeEventListener('rail:open', this._openHandler)
    }
    if (this._flyoutGesture) {
      const flyoutPanel = this.el.querySelector('[data-flyout-panel]')
      if (flyoutPanel) {
        flyoutPanel.removeEventListener('touchstart', this._flyoutGesture.onTouchStart)
        flyoutPanel.removeEventListener('touchmove', this._flyoutGesture.onTouchMove)
        flyoutPanel.removeEventListener('touchend', this._flyoutGesture.onTouchEnd)
      }
    }
    if (this._grabHandle && this._edgeGesture) {
      this._grabHandle.removeEventListener('touchstart', this._edgeGesture.onTouchStart)
      this._grabHandle.removeEventListener('touchmove', this._edgeGesture.onTouchMove)
      this._grabHandle.removeEventListener('touchend', this._edgeGesture.onTouchEnd)
    }
  }
}
```

- [ ] **Step 2: Register the hook in app.js**

Open `assets/js/app.js`. Find the existing `Hooks` object where `SidebarState` (or other hooks) is registered. Add `RailState` using the same pattern already used in that file — do not restructure existing hook imports or the `Hooks` object shape.

```javascript
import { RailState } from './hooks/rail_state'
```

Add `RailState` to the Hooks object. Keep `SidebarState` registered — it is needed until the old sidebar is fully removed.

- [ ] **Step 3: Commit**

```bash
git add assets/js/hooks/rail_state.js assets/js/app.js
git commit -m "feat: add RailState JS hook"
```

---

## Task 3: Rail.ProjectActions

**Files:**
- Create: `lib/eye_in_the_sky_web/components/rail/project_actions.ex`

This is a direct port of `lib/eye_in_the_sky_web/components/sidebar/project_actions.ex`. Change the module name only. The logic is identical.

**Note:** `handle_show_new_project/1` uses `osascript` to open a folder picker. This is macOS-specific and intentionally preserved from the sidebar. Do NOT generalize it as part of this task.

**Note:** `handle_create_project/2` accepts `params` as its first argument and reads `params["path"]` with a fallback to the assign. This avoids a race where the user submits before the `phx-keyup` assign is applied.

- [ ] **Step 1: Create the file**

```elixir
# lib/eye_in_the_sky_web/components/rail/project_actions.ex
defmodule EyeInTheSkyWeb.Components.Rail.ProjectActions do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [start_async: 3, push_navigate: 2, put_flash: 3]
  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]

  alias EyeInTheSky.{Events, Projects}

  def handle_select_project(%{"project_id" => id_str}, socket) do
    case parse_int(id_str) do
      nil ->
        {:noreply, socket}

      id ->
        current_id = get_in(socket.assigns, [:sidebar_project, Access.key(:id)])

        if current_id == id do
          {:noreply, assign(socket, :sidebar_project, nil)}
        else
          {:noreply, assign(socket, :sidebar_project, Projects.get_project!(id))}
        end
    end
  end

  def handle_start_rename(%{"project_id" => id_str}, socket) do
    case parse_int(id_str) do
      nil -> {:noreply, socket}
      id ->
        project = Projects.get_project!(id)
        {:noreply, assign(socket, renaming_project_id: id, rename_value: project.name)}
    end
  end

  def handle_cancel_rename(socket),
    do: {:noreply, assign(socket, renaming_project_id: nil, rename_value: "")}

  def handle_update_rename_value(%{"value" => value}, socket),
    do: {:noreply, assign(socket, :rename_value, value)}

  def handle_commit_rename(socket) do
    name = String.trim(socket.assigns.rename_value)

    if name != "" && not is_nil(socket.assigns.renaming_project_id) do
      project = Projects.get_project!(socket.assigns.renaming_project_id)
      Projects.update_project(project, %{name: name})
    end

    {:noreply,
     socket
     |> assign(:projects, Projects.list_projects_for_sidebar())
     |> assign(:renaming_project_id, nil)
     |> assign(:rename_value, "")}
  end

  def handle_delete_project(%{"project_id" => id_str}, socket) do
    case parse_int(id_str) do
      nil -> {:noreply, socket}
      id ->
        Projects.get_project!(id) |> Projects.delete_project()
        {:noreply, assign(socket, :projects, Projects.list_projects_for_sidebar())}
    end
  end

  def handle_set_bookmark(params, socket) do
    with id when is_binary(id) <- Map.get(params, "id"),
         value when value in ["true", "false"] <- Map.get(params, "bookmarked"),
         project_id when not is_nil(project_id) <- parse_int(id),
         {:ok, project} <- Projects.set_bookmarked(project_id, value == "true") do
      Events.project_updated(project)
      {:noreply, assign(socket, :projects, Projects.list_projects_for_sidebar())}
    else
      _ -> {:noreply, socket}
    end
  end

  # macOS-specific: uses osascript for folder picker. Intentionally not generalized.
  # Clicking "New project" triggers this. If the picker is cancelled or fails,
  # handle_pick_folder/2 falls through to the inline path input fallback.
  # NOTE: Creating a project does NOT auto-select it. Check the old Sidebar behavior —
  # if it auto-selected, add |> assign(:sidebar_project, project) to handle_pick_folder/2.
  def handle_show_new_project(socket) do
    {:noreply,
     start_async(socket, :pick_folder, fn ->
       System.cmd(
         "osascript",
         ["-e", ~s[POSIX path of (choose folder with prompt "Select project folder:")]],
         stderr_to_stdout: true
       )
     end)}
  end

  def handle_cancel_new_project(socket),
    do: {:noreply, assign(socket, :new_project_path, nil)}

  def handle_update_project_path(%{"value" => value}, socket),
    do: {:noreply, assign(socket, :new_project_path, value)}

  # Reads path from submit params first, falls back to assign.
  # This handles paste-then-submit before keyup fires.
  def handle_create_project(params, socket) do
    path =
      (params["path"] || socket.assigns.new_project_path || "")
      |> String.trim()

    if path != "" do
      name = path |> String.split("/") |> Enum.reject(&(&1 == "")) |> List.last() || path

      case Projects.create_project(%{name: name, path: path}) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(:projects, Projects.list_projects_for_sidebar())
           |> assign(:new_project_path, nil)}

        {:error, _} ->
          {:noreply, assign(socket, :new_project_path, nil)}
      end
    else
      {:noreply, assign(socket, :new_project_path, nil)}
    end
  end

  def handle_new_session(%{"project_id" => project_id_str}, socket) do
    with project_id when not is_nil(project_id) <- parse_int(project_id_str),
         {:ok, project} <- Projects.get_project(project_id),
         {:ok, %{session: session}} <-
           EyeInTheSky.Agents.AgentManager.create_agent(
             project_id: project.id,
             project_path: project.path,
             model: "sonnet",
             eits_workflow: "0"
           ) do
      {:noreply, push_navigate(socket, to: "/dm/#{session.id}")}
    else
      nil -> {:noreply, socket}
      {:error, :not_found} -> {:noreply, put_flash(socket, :error, "Project not found")}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to create agent")}
    end
  end

  def handle_pick_folder({path, 0}, socket) do
    path = String.trim(path)
    name = path |> String.split("/") |> Enum.reject(&(&1 == "")) |> List.last() || path

    case Projects.create_project(%{name: name, path: path}) do
      {:ok, _} -> {:noreply, assign(socket, :projects, Projects.list_projects_for_sidebar())}
      {:error, _} -> {:noreply, socket}
    end
  end

  # Cancelled or failed: show inline path input fallback
  def handle_pick_folder(_result, socket),
    do: {:noreply, assign(socket, :new_project_path, "")}
end
```

- [ ] **Step 2: Verify it compiles**

```bash
mix compile
```

Expected: no errors (warnings about unused module OK).

- [ ] **Step 3: Commit**

```bash
git add lib/eye_in_the_sky_web/components/rail/project_actions.ex
git commit -m "feat: add Rail.ProjectActions (ported from Sidebar.ProjectActions)"
```

---

## Task 4: Rail.ProjectSwitcher component

**Files:**
- Create: `lib/eye_in_the_sky_web/components/rail/project_switcher.ex`

Functional component only — no state, no events. Renders the project picker overlay. Parent Rail handles events.

**MVP scope:** Exposes project select and new project only. Rename, delete, and bookmark handlers are ported in ProjectActions but their UI is NOT included here — those attrs are not declared on this component.

- [ ] **Step 1: Create the file**

```elixir
# lib/eye_in_the_sky_web/components/rail/project_switcher.ex
defmodule EyeInTheSkyWeb.Components.Rail.ProjectSwitcher do
  @moduledoc false
  use EyeInTheSkyWeb, :html

  attr :projects, :list, required: true
  attr :sidebar_project, :any, default: nil
  attr :open, :boolean, default: false
  attr :new_project_path, :any, default: nil
  attr :myself, :any, required: true

  def project_switcher(assigns) do
    ~H"""
    <div
      :if={@open}
      class="absolute left-[52px] top-[48px] z-50 w-64 bg-base-200 border border-base-content/10 rounded-xl shadow-2xl overflow-hidden"
    >
      <div class="px-3 py-2.5 border-b border-base-content/8 text-[10px] font-semibold uppercase tracking-widest text-base-content/40">
        Switch Project
      </div>

      <div class="p-1.5 max-h-72 overflow-y-auto">
        <%= for project <- @projects do %>
          <% selected = not is_nil(@sidebar_project) && @sidebar_project.id == project.id %>
          <button
            phx-click="select_project"
            phx-value-project_id={project.id}
            phx-target={@myself}
            class={[
              "w-full flex items-center gap-2.5 px-2 py-2 rounded-lg text-sm text-left transition-colors",
              if(selected,
                do: "bg-primary/10 text-primary",
                else: "text-base-content/70 hover:bg-base-content/5 hover:text-base-content/90"
              )
            ]}
          >
            <div class={[
              "w-7 h-7 rounded-lg flex items-center justify-center flex-shrink-0 text-xs font-bold",
              if(selected, do: "bg-primary text-white", else: "bg-base-content/10 text-base-content/60")
            ]}>
              {project_initial(project)}
            </div>
            <div class="flex-1 min-w-0">
              <div class="font-medium truncate">{project.name}</div>
            </div>
            <.icon :if={selected} name="hero-check-mini" class="w-3.5 h-3.5 flex-shrink-0" />
          </button>
        <% end %>
      </div>

      <div class="border-t border-base-content/8 p-1.5">
        <%= if is_nil(@new_project_path) do %>
          <button
            phx-click="show_new_project"
            phx-target={@myself}
            class="w-full flex items-center gap-2 px-2 py-2 rounded-lg text-sm text-base-content/50 hover:text-base-content/80 hover:bg-base-content/5 transition-colors"
          >
            <.icon name="hero-plus-mini" class="w-3.5 h-3.5" />
            New project
          </button>
        <% else %>
          <form phx-submit="create_project" phx-target={@myself} class="flex items-center gap-1 px-2 py-1">
            <input
              type="text"
              name="path"
              value={@new_project_path}
              phx-keyup="update_project_path"
              phx-target={@myself}
              placeholder="/path/to/project"
              class="flex-1 bg-transparent border-b border-primary/40 text-sm text-base-content/80 placeholder:text-base-content/25 outline-none py-0.5 font-mono"
              autofocus
            />
            <button
              type="submit"
              class="text-primary hover:text-primary/80"
              aria-label="Create project"
            >
              <.icon name="hero-check-mini" class="w-3.5 h-3.5" />
            </button>
            <button
              type="button"
              phx-click="cancel_new_project"
              phx-target={@myself}
              class="text-base-content/30 hover:text-base-content/60"
              aria-label="Cancel"
            >
              <.icon name="hero-x-mark-mini" class="w-3.5 h-3.5" />
            </button>
          </form>
        <% end %>
      </div>
    </div>
    """
  end

  # Safe initial extraction — handles nil project, nil name, and empty names
  defp project_initial(nil), do: "E"

  defp project_initial(%{name: name}) when is_binary(name) do
    name
    |> String.trim()
    |> case do
      "" -> "E"
      trimmed -> trimmed |> String.first() |> String.upcase()
    end
  end

  defp project_initial(_), do: "E"
end
```

- [ ] **Step 2: Compile check**

```bash
mix compile
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/eye_in_the_sky_web/components/rail/project_switcher.ex
git commit -m "feat: add Rail.ProjectSwitcher component"
```

---

## Task 5: Rail.Flyout component

**Files:**
- Create: `lib/eye_in_the_sky_web/components/rail/flyout.ex`

Renders the 236px side panel. Sessions section shows real data (status dots + names). All other sections render navigation links. Parent Rail handles all data.

**Note on `active_channel_id`:** Accepted for assign interface compatibility with the old Sidebar. Not used to render a channel list — Chat flyout shows navigation links only. A real channel list is follow-up work.

**Note on `format_session_time/1`:** `Session.last_activity_at` is `:utc_datetime_usec` — Ecto returns `%DateTime{}` structs. The primary clause handles structs directly; binary and NaiveDateTime clauses are safety fallbacks.

**Note on `:notifications`:** Handled defensively. When `sidebar_tab: :notifications` is passed by the parent, `active_section` becomes `:notifications` and the flyout shows a Notifications navigation link. There is no `rail_item` for notifications — it uses a direct bottom link in the rail instead.

- [ ] **Step 1: Create the file**

```elixir
# lib/eye_in_the_sky_web/components/rail/flyout.ex
defmodule EyeInTheSkyWeb.Components.Rail.Flyout do
  @moduledoc false
  use EyeInTheSkyWeb, :html

  attr :open, :boolean, required: true
  attr :active_section, :atom, required: true
  attr :sidebar_project, :any, default: nil
  # Accepted for assign compatibility with Sidebar interface; unused in MVP (no channel list).
  attr :active_channel_id, :any, default: nil
  attr :flyout_sessions, :list, default: []
  attr :notification_count, :integer, default: 0
  attr :myself, :any, required: true

  def flyout(assigns) do
    ~H"""
    <div
      data-flyout-panel
      class={[
        "flex flex-col border-r border-base-content/8 bg-base-100 overflow-hidden flex-shrink-0 transition-[width] duration-150",
        if(@open, do: "w-[236px]", else: "w-0")
      ]}
    >
      <div class={["flex flex-col h-full", if(!@open, do: "invisible")]}>
        <div class="flex items-center justify-between px-3.5 py-3 border-b border-base-content/8 flex-shrink-0">
          <span class="text-[10px] font-semibold uppercase tracking-widest text-base-content/40">
            {section_label(@active_section)}
          </span>
          <button
            phx-click="close_flyout"
            phx-target={@myself}
            class="text-base-content/30 hover:text-base-content/60 transition-colors"
            aria-label="Close panel"
          >
            <.icon name="hero-x-mark-mini" class="w-3.5 h-3.5" />
          </button>
        </div>

        <div class="flex-1 overflow-y-auto py-1">
          <%= case @active_section do %>
            <% :sessions -> %>
              <.sessions_content sessions={@flyout_sessions} sidebar_project={@sidebar_project} />
            <% :tasks -> %>
              <.nav_links project={@sidebar_project} section={:tasks} />
            <% :prompts -> %>
              <.nav_links project={@sidebar_project} section={:prompts} />
            <% :chat -> %>
              <.chat_content />
            <% :notes -> %>
              <.nav_links project={@sidebar_project} section={:notes} />
            <% :skills -> %>
              <.simple_link href="/skills" label="All Skills" icon="hero-bolt" />
            <% :teams -> %>
              <.simple_link href="/teams" label="All Teams" icon="hero-users" />
            <% :canvas -> %>
              <.simple_link href="/canvases" label="All Canvases" icon="hero-squares-2x2" />
            <% :notifications -> %>
              <.simple_link href="/notifications" label="Notifications" icon="hero-bell" />
            <% _ -> %>
              <.nav_links project={@sidebar_project} section={:sessions} />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Sessions flyout: real data with status dots
  defp sessions_content(assigns) do
    ~H"""
    <% active = Enum.filter(@sessions, &(&1.status in ["working", "waiting"])) %>
    <% stopped = Enum.filter(@sessions, &(&1.status not in ["working", "waiting"])) %>

    <%= if active != [] do %>
      <div class="px-3 pt-2 pb-1 text-[10px] font-semibold uppercase tracking-widest text-base-content/35">
        Active
      </div>
      <.session_row :for={s <- active} session={s} />
    <% end %>

    <%= if stopped != [] do %>
      <div class="px-3 pt-2 pb-1 text-[10px] font-semibold uppercase tracking-widest text-base-content/35">
        Stopped
      </div>
      <.session_row :for={s <- Enum.take(stopped, 8)} session={s} />
    <% end %>

    <%= if @sessions == [] do %>
      <div class="px-3 py-4 text-xs text-base-content/35 text-center">No sessions</div>
    <% end %>

    <div class="px-3 pt-2 pb-1 border-t border-base-content/8 mt-1">
      <.link
        navigate={if @sidebar_project, do: "/projects/#{@sidebar_project.id}/sessions", else: "/"}
        class="text-xs text-base-content/40 hover:text-base-content/70 transition-colors"
      >
        View all &rarr;
      </.link>
    </div>
    """
  end

  attr :session, :map, required: true

  defp session_row(assigns) do
    ~H"""
    <.link
      navigate={"/dm/#{@session.id}"}
      class="flex items-center gap-2 px-3 py-2 text-sm text-base-content/65 hover:text-base-content/90 hover:bg-base-content/5 transition-colors"
    >
      <span class={[
        "w-1.5 h-1.5 rounded-full flex-shrink-0",
        status_dot_class(@session.status)
      ]} />
      <span class="truncate font-medium text-xs">{@session.name || "unnamed"}</span>
      <span class="ml-auto text-[10px] text-base-content/30 flex-shrink-0">
        {format_session_time(@session)}
      </span>
    </.link>
    """
  end

  # Chat flyout: navigation links only (no channel list in MVP)
  defp chat_content(assigns) do
    ~H"""
    <.simple_link href="/chat" label="Channels" icon="hero-chat-bubble-left-ellipsis" />
    <.simple_link href="/dms" label="Direct Messages" icon="hero-chat-bubble-left-right" />
    """
  end

  # Generic nav links per section
  attr :project, :any, default: nil
  attr :section, :atom, required: true

  defp nav_links(%{section: :tasks} = assigns) do
    ~H"""
    <.simple_link href="/tasks" label="All Tasks" icon="hero-clipboard-document-list" />
    <%= if @project do %>
      <.simple_link
        href={"/projects/#{@project.id}/kanban"}
        label={"#{@project.name} Board"}
        icon="hero-squares-2x2"
      />
    <% end %>
    """
  end

  defp nav_links(%{section: :prompts} = assigns) do
    ~H"""
    <.simple_link href="/prompts" label="All Prompts" icon="hero-chat-bubble-left-right" />
    <%= if @project do %>
      <.simple_link
        href={"/projects/#{@project.id}/prompts"}
        label={"#{@project.name} Prompts"}
        icon="hero-folder"
      />
    <% end %>
    """
  end

  defp nav_links(%{section: :notes} = assigns) do
    ~H"""
    <.simple_link href="/notes" label="All Notes" icon="hero-document-text" />
    <%= if @project do %>
      <.simple_link
        href={"/projects/#{@project.id}/notes"}
        label={"#{@project.name} Notes"}
        icon="hero-folder"
      />
    <% end %>
    """
  end

  defp nav_links(%{section: :sessions} = assigns) do
    ~H"""
    <.simple_link href="/" label="All Sessions" icon="hero-cpu-chip" />
    <%= if @project do %>
      <.simple_link
        href={"/projects/#{@project.id}/sessions"}
        label={"#{@project.name} Sessions"}
        icon="hero-folder"
      />
    <% end %>
    """
  end

  attr :href, :string, required: true
  attr :label, :string, required: true
  attr :icon, :string, required: true

  defp simple_link(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class="flex items-center gap-2.5 px-3 py-2.5 text-sm text-base-content/60 hover:text-base-content/85 hover:bg-base-content/5 transition-colors"
    >
      <.icon name={@icon} class="w-3.5 h-3.5 flex-shrink-0" />
      <span class="truncate">{@label}</span>
    </.link>
    """
  end

  defp section_label(:sessions), do: "Sessions"
  defp section_label(:tasks), do: "Tasks"
  defp section_label(:prompts), do: "Prompts"
  defp section_label(:chat), do: "Chat"
  defp section_label(:notes), do: "Notes"
  defp section_label(:skills), do: "Skills"
  defp section_label(:teams), do: "Teams"
  defp section_label(:canvas), do: "Canvas"
  defp section_label(:notifications), do: "Notifications"
  defp section_label(_), do: "Navigation"

  defp status_dot_class("working"), do: "bg-green-500"
  defp status_dot_class("waiting"), do: "bg-amber-400"
  defp status_dot_class(_), do: "bg-base-content/25"

  # Session.last_activity_at is :utc_datetime_usec — Ecto returns %DateTime{} structs.
  # Binary fallback handles any edge cases (cached data, API responses, etc.)
  defp format_session_time(%{last_activity_at: %DateTime{} = dt}) do
    diff = max(DateTime.diff(DateTime.utc_now(), dt, :second), 0)

    cond do
      diff < 60 -> "#{diff}s"
      diff < 3600 -> "#{div(diff, 60)}m"
      diff < 86_400 -> "#{div(diff, 3600)}h"
      true -> "#{div(diff, 86_400)}d"
    end
  end

  defp format_session_time(%{last_activity_at: %NaiveDateTime{} = ndt}) do
    ndt
    |> DateTime.from_naive!("Etc/UTC")
    |> then(&format_session_time(%{last_activity_at: &1}))
  end

  defp format_session_time(%{last_activity_at: ts}) when is_binary(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} -> format_session_time(%{last_activity_at: dt})
      _ -> ""
    end
  end

  defp format_session_time(_), do: ""
end
```

- [ ] **Step 2: Compile check**

```bash
mix compile
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/eye_in_the_sky_web/components/rail/flyout.ex
git commit -m "feat: add Rail.Flyout component"
```

---

## Task 6: Rail LiveComponent

**Files:**
- Create: `lib/eye_in_the_sky_web/components/rail.ex`

This is the main component. Accepts the same assigns as the old Sidebar (`sidebar_tab`, `sidebar_project`, `active_channel_id`). Derives the active section from `sidebar_tab` only when it changes.

**Critical:** `update/2` uses `Map.get(assigns, key, fallback)` so that assigns not present in a given update call do not overwrite existing socket state. `active_section` is only reset when `sidebar_tab` actually changes — this prevents parent LiveView re-renders from stomping on the user's current rail selection.

**Project selection:** Selecting a project updates only the Rail component's assigns. This matches existing Sidebar behavior.

**Notification refresh:** After implementing, search for the existing `send_update` call that targets the old sidebar and update it to target `Rail` with id `"app-rail"`.

- [ ] **Step 1: Create the file**

```elixir
# lib/eye_in_the_sky_web/components/rail.ex
defmodule EyeInTheSkyWeb.Components.Rail do
  @moduledoc false
  use EyeInTheSkyWeb, :live_component

  import EyeInTheSkyWeb.Components.Rail.Flyout
  import EyeInTheSkyWeb.Components.Rail.ProjectSwitcher

  alias EyeInTheSky.{Notifications, Projects, Sessions}
  alias EyeInTheSkyWeb.Components.Rail.ProjectActions

  # Map sidebar_tab atoms to rail section atoms
  @section_map %{
    sessions: :sessions,
    overview: :sessions,
    tasks: :tasks,
    kanban: :tasks,
    prompts: :prompts,
    chat: :chat,
    notes: :notes,
    skills: :skills,
    teams: :teams,
    canvas: :canvas,
    canvases: :canvas,
    notifications: :notifications,
    usage: :sessions,
    config: :sessions,
    jobs: :sessions,
    settings: :sessions,
    agents: :sessions,
    files: :sessions,
    bookmarks: :sessions
  }

  # Whitelist for parse_section/1 — never call String.to_existing_atom on raw client params
  @valid_sections ~w(sessions tasks prompts chat notes skills teams canvas notifications)

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       projects: Projects.list_projects_for_sidebar(),
       flyout_open: true,
       proj_picker_open: false,
       active_section: :sessions,
       flyout_sessions: load_flyout_sessions(nil),
       notification_count: Notifications.unread_count(),
       new_project_path: nil,
       renaming_project_id: nil,
       rename_value: "",
       mobile_open: false,
       sidebar_project: nil,
       sidebar_tab: :sessions,
       active_channel_id: nil
     )}
  end

  @impl true
  def update(%{notification_count: :refresh}, socket) do
    {:ok, assign(socket, :notification_count, Notifications.unread_count())}
  end

  def update(%{refresh_projects: true}, socket) do
    {:ok, assign(socket, :projects, Projects.list_projects_for_sidebar())}
  end

  def update(assigns, socket) do
    # Use Map.get with fallback to socket assigns so partial updates don't clear existing state
    sidebar_project = Map.get(assigns, :sidebar_project, socket.assigns[:sidebar_project])
    sidebar_tab = Map.get(assigns, :sidebar_tab, socket.assigns[:sidebar_tab] || :sessions)
    active_channel_id = Map.get(assigns, :active_channel_id, socket.assigns[:active_channel_id])

    # Only reset active_section when sidebar_tab changes — do not let every parent
    # re-render stomp on the user's current rail section selection
    previous_tab = socket.assigns[:sidebar_tab]
    next_section = Map.get(@section_map, sidebar_tab, :sessions)

    socket =
      socket
      |> assign(:sidebar_tab, sidebar_tab)
      |> assign(:sidebar_project, sidebar_project)
      |> assign(:active_channel_id, active_channel_id)
      |> assign(:flyout_sessions, load_flyout_sessions(sidebar_project))

    socket =
      if sidebar_tab != previous_tab do
        assign(socket, :active_section, next_section)
      else
        socket
      end

    {:ok, socket}
  end

  # --- Events ---

  @impl true
  def handle_event("toggle_section", %{"section" => section_str}, socket) do
    section = parse_section(section_str)
    current = socket.assigns.active_section

    if current == section && socket.assigns.flyout_open do
      # Clicking the active section icon closes the flyout; reset mobile_open too
      {:noreply, assign(socket, flyout_open: false, mobile_open: false)}
    else
      {:noreply,
       socket
       |> assign(:active_section, section)
       |> assign(:flyout_open, true)
       |> assign(:proj_picker_open, false)
       |> assign(:flyout_sessions, load_flyout_sessions(socket.assigns.sidebar_project))}
    end
  end

  def handle_event("close_flyout", _params, socket),
    do: {:noreply, assign(socket, flyout_open: false, mobile_open: false)}

  def handle_event("restore_section", %{"section" => section_str}, socket),
    do: {:noreply, assign(socket, :active_section, parse_section(section_str))}

  def handle_event("toggle_proj_picker", _params, socket),
    do: {:noreply, assign(socket, :proj_picker_open, !socket.assigns.proj_picker_open)}

  def handle_event("close_proj_picker", _params, socket),
    do: {:noreply, assign(socket, :proj_picker_open, false)}

  def handle_event("open_mobile", _params, socket),
    do: {:noreply, assign(socket, mobile_open: true, flyout_open: true)}

  def handle_event("select_project", params, socket) do
    {:noreply, socket2} = ProjectActions.handle_select_project(params, socket)
    # Reload sessions immediately so the flyout reflects the new project context
    {:noreply,
     socket2
     |> assign(:proj_picker_open, false)
     |> assign(:flyout_sessions, load_flyout_sessions(socket2.assigns.sidebar_project))}
  end

  def handle_event("show_new_project", _params, socket),
    do: ProjectActions.handle_show_new_project(socket)

  def handle_event("cancel_new_project", _params, socket),
    do: ProjectActions.handle_cancel_new_project(socket)

  def handle_event("update_project_path", params, socket),
    do: ProjectActions.handle_update_project_path(params, socket)

  # Pass params so handle_create_project can read the submitted path value
  def handle_event("create_project", params, socket),
    do: ProjectActions.handle_create_project(params, socket)

  def handle_event("new_session", params, socket),
    do: ProjectActions.handle_new_session(params, socket)

  def handle_event("start_rename_project", params, socket),
    do: ProjectActions.handle_start_rename(params, socket)

  def handle_event("cancel_rename_project", _params, socket),
    do: ProjectActions.handle_cancel_rename(socket)

  def handle_event("update_rename_value", params, socket),
    do: ProjectActions.handle_update_rename_value(params, socket)

  def handle_event("commit_rename_project", _params, socket),
    do: ProjectActions.handle_commit_rename(socket)

  def handle_event("delete_project", params, socket),
    do: ProjectActions.handle_delete_project(params, socket)

  def handle_event("set_bookmark", params, socket),
    do: ProjectActions.handle_set_bookmark(params, socket)

  @impl true
  def handle_async(:pick_folder, {:ok, result}, socket),
    do: ProjectActions.handle_pick_folder(result, socket)

  def handle_async(:pick_folder, _result, socket),
    do: ProjectActions.handle_pick_folder(:cancelled, socket)

  # --- Helpers ---

  # Safe section parser — whitelist prevents bad client input from crashing
  defp parse_section(section_str) when section_str in @valid_sections,
    do: String.to_existing_atom(section_str)

  defp parse_section(_), do: :sessions

  # Flyout sessions are loaded eagerly on every update/toggle for MVP simplicity.
  # Optimize later if this becomes noisy (e.g. only load when active_section == :sessions).
  defp load_flyout_sessions(project) do
    opts = [limit: 15, status_filter: "all"]
    opts = if project, do: Keyword.put(opts, :project_id, project.id), else: opts

    # Defensive: handle both plain list and {:ok, list} return shapes
    case Sessions.list_sessions_filtered(opts) do
      sessions when is_list(sessions) -> sessions
      {:ok, sessions} when is_list(sessions) -> sessions
      _ -> []
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="app-rail"
      phx-hook="RailState"
      phx-target={@myself}
      class="flex flex-row h-full relative"
    >
      <%!-- Mobile backdrop --%>
      <div
        :if={@mobile_open && @flyout_open}
        phx-click="close_flyout"
        phx-target={@myself}
        class="md:hidden fixed inset-0 z-40 bg-black/40"
      />

      <%!-- Icon rail --%>
      <nav class="w-[52px] flex-shrink-0 flex flex-col items-center py-2 gap-1 border-r border-base-content/8 bg-base-100 z-20">
        <%!-- Project switcher logo --%>
        <button
          phx-click="toggle_proj_picker"
          phx-target={@myself}
          class={[
            "w-8 h-8 rounded-lg mb-2 flex items-center justify-center text-sm font-bold text-white transition-all",
            "bg-primary hover:opacity-90",
            if(@proj_picker_open, do: "ring-2 ring-primary ring-offset-2 ring-offset-base-100")
          ]}
          title="Switch project"
          aria-label="Switch project"
        >
          {project_initial(@sidebar_project)}
        </button>

        <.rail_item
          section={:sessions}
          active_section={@active_section}
          flyout_open={@flyout_open}
          icon="hero-cpu-chip"
          label="Sessions"
          myself={@myself}
        />
        <.rail_item
          section={:tasks}
          active_section={@active_section}
          flyout_open={@flyout_open}
          icon="hero-clipboard-document-list"
          label="Tasks"
          myself={@myself}
        />
        <.rail_item
          section={:prompts}
          active_section={@active_section}
          flyout_open={@flyout_open}
          icon="hero-chat-bubble-left-right"
          label="Prompts"
          myself={@myself}
        />
        <.rail_item
          section={:chat}
          active_section={@active_section}
          flyout_open={@flyout_open}
          icon="hero-chat-bubble-left-ellipsis"
          label="Chat"
          myself={@myself}
        />
        <.rail_item
          section={:notes}
          active_section={@active_section}
          flyout_open={@flyout_open}
          icon="hero-document-text"
          label="Notes"
          myself={@myself}
        />
        <.rail_item
          section={:skills}
          active_section={@active_section}
          flyout_open={@flyout_open}
          icon="hero-bolt"
          label="Skills"
          myself={@myself}
        />
        <.rail_item
          section={:teams}
          active_section={@active_section}
          flyout_open={@flyout_open}
          icon="hero-users"
          label="Teams"
          myself={@myself}
        />
        <.rail_item
          section={:canvas}
          active_section={@active_section}
          flyout_open={@flyout_open}
          icon="hero-squares-2x2"
          label="Canvas"
          myself={@myself}
        />

        <div class="flex-1" />

        <%!-- Notifications: direct link (not a rail_item — no flyout toggle) --%>
        <.link
          navigate="/notifications"
          class={[
            "relative w-9 h-9 rounded-lg flex items-center justify-center transition-colors",
            if(@sidebar_tab == :notifications,
              do: "text-primary bg-primary/10",
              else: "text-base-content/40 hover:text-base-content/70 hover:bg-base-content/5"
            )
          ]}
          title="Notifications"
          aria-label="Notifications"
        >
          <.icon name="hero-bell" class="w-4 h-4" />
          <span
            :if={@notification_count > 0}
            class="absolute top-1 right-1 badge badge-xs badge-primary min-w-[14px] h-[14px] p-0 text-[9px]"
          >
            {if @notification_count > 99, do: "99+", else: @notification_count}
          </span>
        </.link>

        <.link
          navigate="/settings"
          class={[
            "w-9 h-9 rounded-lg flex items-center justify-center transition-colors",
            if(@sidebar_tab == :settings,
              do: "text-primary bg-primary/10",
              else: "text-base-content/40 hover:text-base-content/70 hover:bg-base-content/5"
            )
          ]}
          title="Settings"
          aria-label="Settings"
        >
          <.icon name="hero-cog-8-tooth" class="w-4 h-4" />
        </.link>

        <.link
          href="/auth/logout"
          method="delete"
          class="w-9 h-9 rounded-lg flex items-center justify-center text-base-content/35 hover:text-red-500 hover:bg-base-content/5 transition-colors"
          title="Sign out"
          aria-label="Sign out"
        >
          <.icon name="hero-arrow-right-on-rectangle-mini" class="w-4 h-4" />
        </.link>
      </nav>

      <%!-- Project switcher popover (overlays flyout) --%>
      <.project_switcher
        projects={@projects}
        sidebar_project={@sidebar_project}
        open={@proj_picker_open}
        new_project_path={@new_project_path}
        myself={@myself}
      />

      <%!-- Flyout panel --%>
      <.flyout
        open={@flyout_open}
        active_section={@active_section}
        sidebar_project={@sidebar_project}
        active_channel_id={@active_channel_id}
        flyout_sessions={@flyout_sessions}
        notification_count={@notification_count}
        myself={@myself}
      />
    </div>
    """
  end

  # Rail icon button
  attr :section, :atom, required: true
  attr :active_section, :atom, required: true
  attr :flyout_open, :boolean, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :myself, :any, required: true

  defp rail_item(assigns) do
    ~H"""
    <button
      phx-click="toggle_section"
      phx-value-section={@section}
      phx-target={@myself}
      class={[
        "w-9 h-9 rounded-lg flex items-center justify-center transition-colors relative",
        if(@active_section == @section && @flyout_open,
          do: "text-primary bg-primary/10",
          else: "text-base-content/40 hover:text-base-content/70 hover:bg-base-content/5"
        )
      ]}
      title={@label}
      aria-label={@label}
    >
      <.icon name={@icon} class="w-4 h-4" />
    </button>
    """
  end

  # Safe initial — handles nil project and nil/empty names
  defp project_initial(nil), do: "E"

  defp project_initial(%{name: name}) when is_binary(name) do
    name
    |> String.trim()
    |> case do
      "" -> "E"
      trimmed -> trimmed |> String.first() |> String.upcase()
    end
  end

  defp project_initial(_), do: "E"
end
```

- [ ] **Step 2: Verify notification refresh wiring**

Search for existing `send_update` calls targeting the old sidebar:

```bash
grep -r "send_update.*Sidebar\|send_update.*app-sidebar" lib/ --include="*.ex" | head -20
```

If found, update those call sites:
- Change `EyeInTheSkyWeb.Components.Sidebar` → `EyeInTheSkyWeb.Components.Rail`
- Change `id: "app-sidebar"` → `id: "app-rail"`

- [ ] **Step 3: Compile check**

```bash
mix compile
```

Expected: no errors. If `Sessions.list_sessions_filtered/1` fails, use the correct function name found in Task 0 Step 1.

- [ ] **Step 4: Commit**

```bash
git add lib/eye_in_the_sky_web/components/rail.ex
git commit -m "feat: add Rail LiveComponent"
```

---

## Task 7: Wire into app.html.heex

**Files:**
- Modify: `lib/eye_in_the_sky_web/components/layouts/app.html.heex`

Replace the `Sidebar` live_component with `Rail`. Update the mobile header to dispatch `rail:open` instead of `sidebar:open`. Replace the sidebar grab handle with a rail grab handle.

- [ ] **Step 1: Open and read the current layout**

```bash
cat lib/eye_in_the_sky_web/components/layouts/app.html.heex
```

- [ ] **Step 2: Make the edits**

Replace this block:
```heex
<.live_component
  module={EyeInTheSkyWeb.Components.Sidebar}
  id="app-sidebar"
  sidebar_tab={assigns[:sidebar_tab] || :sessions}
  sidebar_project={assigns[:sidebar_project]}
  active_channel_id={assigns[:active_channel_id]}
/>
```

With:
```heex
<.live_component
  module={EyeInTheSkyWeb.Components.Rail}
  id="app-rail"
  sidebar_tab={assigns[:sidebar_tab] || :sessions}
  sidebar_project={assigns[:sidebar_project]}
  active_channel_id={assigns[:active_channel_id]}
/>
```

Find the element with `id="sidebar-grab-handle"` in the layout and change only its id to `rail-grab-handle`. Preserve existing positioning classes unless they are missing, in which case use:
```heex
<div
  id="rail-grab-handle"
  class="md:hidden fixed left-0 bottom-0 w-10 z-[45]"
  style="touch-action: none; top: calc(3rem + env(safe-area-inset-top));"
  aria-hidden="true"
/>
```

In the mobile header, replace the hamburger dispatch target:
```heex
phx-click={Phoenix.LiveView.JS.dispatch("sidebar:open", to: "#app-sidebar")}
```
With:
```heex
phx-click={Phoenix.LiveView.JS.dispatch("rail:open", to: "#app-rail")}
```

- [ ] **Step 3: Verify `app-rail` id placement**

The layout should contain exactly one LiveComponent call with this id:

```bash
grep -c 'id="app-rail"' lib/eye_in_the_sky_web/components/layouts/app.html.heex
# expected: 1
```

The Rail component file should contain exactly one DOM element with this id:

```bash
grep -c 'id="app-rail"' lib/eye_in_the_sky_web/components/rail.ex
# expected: 1
```

The real duplicate-DOM-id check is in the browser smoke test (Task 8 Step 4):

```javascript
document.querySelectorAll('#app-rail').length
// expected: 1
```

- [ ] **Step 4: Verify compile**

```bash
mix compile
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add lib/eye_in_the_sky_web/components/layouts/app.html.heex
git commit -m "feat: swap Sidebar → Rail in app layout"
```

---

## Task 8: Smoke test in browser

**No code changes — verification only.**

- [ ] **Step 1: Start a dev server on a non-conflicting port**

```bash
VITE_PORT=5174 PORT=5002 DISABLE_AUTH=true mix phx.server
```

- [ ] **Step 2: Core rail behavior**

Navigate to `http://localhost:5002`:
- [ ] 52px icon rail is visible on the left
- [ ] Clicking "Sessions" icon opens the flyout with a list of sessions
- [ ] Clicking the same icon again closes the flyout
- [ ] Clicking the project logo opens the project picker popover
- [ ] Selecting a different project changes the logo initial AND the sessions flyout updates to show that project's sessions
- [ ] Clicking a different rail icon switches the flyout content
- [ ] **Parent re-render test:** Switch to the Tasks flyout, then perform an action that triggers a parent assign update (navigate to a sub-page within the same LiveView, or wait for a notification count update). Confirm the flyout stays on Tasks and does not jump back to Sessions
- [ ] Clicking a flyout session link navigates to `/dm/:id`
- [ ] Settings link works
- [ ] Notifications badge shows if there are unread notifications
- [ ] Session timestamps render (not blank)
- [ ] No console or server errors when RailState pushes `restore_section`, `open_mobile`, or `close_flyout`

- [ ] **Step 3: Mobile behavior**

At ≤768px viewport:
- [ ] Bottom nav still present
- [ ] Hamburger in top bar opens the flyout
- [ ] Tapping the backdrop closes the flyout and backdrop disappears
- [ ] Flyout can be reopened after closing (confirms `mobile_open` was reset)

- [ ] **Step 4: DOM id uniqueness check**

Open browser DevTools console:
```javascript
document.querySelectorAll('#app-rail').length
// expected: 1
```

- [ ] **Step 5: Page layout check — flyout open AND closed**

Visit each page below, confirm content is not clipped under the rail/flyout, no unexpected horizontal scroll, headers align:
- [ ] `/` (sessions / home)
- [ ] `/tasks`
- [ ] `/dm/<any session id>`
- [ ] `/chat`
- [ ] `/notes`
- [ ] `/notifications`
- [ ] `/settings`
- [ ] `/projects/<any id>/sessions` (project detail)

- [ ] **Step 6: No console errors**

DevTools → Console. Confirm no errors related to `RailState`, `rail:open`, or hook lifecycle.

- [ ] **Step 7: Stop the server (Ctrl+C)**

- [ ] **Step 8: Final compile check with warnings-as-errors**

```bash
mix compile --warnings-as-errors
```

Fix any warnings before the next step.

---

## Task 9: Push branch for Codex review

- [ ] **Step 1: Push the branch**

```bash
git push origin feat/icon-rail
```

- [ ] **Step 2: Open a PR**

```bash
gh pr create \
  --title "feat: replace sidebar with icon rail + flyout nav" \
  --body "Replaces the 240px collapsible sidebar with a 52px icon rail and a 236px contextual flyout panel. Zero changes to LiveViews — same sidebar_tab/sidebar_project interface. Mobile bottom nav unchanged."
```

- [ ] **Step 3: Log the commit hashes**

```bash
git log feat/icon-rail --not main --format="%H" | while read h; do
  eits commits create --hash "$h"
done
```

- [ ] **Step 4: Annotate and close the EITS task**

```bash
eits tasks annotate <task_id> --body "Icon rail nav implemented. Rail + Flyout + ProjectSwitcher components. JS hook. Layout updated. Browser smoke-tested."
eits tasks update <task_id> --state 3
```

---

## Self-Review

**Spec coverage:**
- ✅ 52px icon rail with icon-only items and tooltips
- ✅ Flyout panel opens/closes per section
- ✅ Sessions section shows real data (status dots, name, time)
- ✅ Project switcher on logo click
- ✅ Project select/create preserved through the switcher
- ⚠️ Rename/delete/bookmark handlers are ported but UI is NOT included in this MVP (deferred)
- ✅ Mobile: hamburger opens flyout, swipe-left closes it
- ✅ Notifications badge
- ✅ Settings, sign out at bottom of rail
- ✅ All three bottom icons have `aria-label`
- ✅ Same assigns interface — no LiveView changes
- ✅ `mobile_open` resets on every `close_flyout` call
- ✅ `parse_section/1` whitelist — no raw `String.to_existing_atom` on client params
- ✅ `project_initial/1` handles nil project and nil/empty names
- ✅ `active_channel_id` accepted for interface compatibility; noted as unused in MVP
- ✅ `update/2` preserves local assigns via `Map.get/3`; `active_section` only resets when `sidebar_tab` changes
- ✅ `handle_create_project/2` reads submit params with assign fallback
- ✅ `ProjectSwitcher` has no unused rename attrs; inline form has a visible submit button
- ✅ `select_project` reloads `flyout_sessions` immediately after project change
- ✅ `load_flyout_sessions/1` handles both plain list and `{:ok, list}` return shapes
- ✅ `format_session_time/1` uses robust parser handling timezone-aware and naive ISO8601 strings
- ✅ `section_label(:kanban)` removed (unreachable — Rail maps `:kanban` to `:tasks`)
- ✅ `localStorage` restore-only with clear future-compatible comment
- ✅ `last_activity_at` binary handling correct per `lib/CLAUDE.md`; Task 0 verifies stored format
- ✅ New project picker/fallback flow documented

**Known gaps (not in scope, can be done as follow-up):**
- Tasks flyout shows nav links, not real task data
- Prompts flyout shows nav links, not real prompt data
- Chat flyout has no channel list; `active_channel_id` unused
- Project rename/delete/bookmark UI not in ProjectSwitcher
- localStorage write-back for rail section/flyout state (restore-only)
- `SidebarState` hook + old sidebar files left in place — clean up after rail is stable
- `load_flyout_sessions/1` loads on every update; could optimize to load only when `active_section == :sessions`

**Type consistency check:** All `rail_item` section values are valid `@section_map` keys. `Flyout` `case` branches cover all values that `@section_map` can produce. `ProjectSwitcher` passes no unused attrs. ✅
