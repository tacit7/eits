# Rail LiveView Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert the Rail from a LiveComponent (remounted on every navigation) to a standalone LiveView in the root layout (persists across all navigation), eliminating sidebar flicker and active-section flash permanently.

**Architecture:** The Rail currently lives in `app.html.heex` as a LiveComponent. The app layout is re-rendered by each page LiveView on navigation, destroying and remounting the Rail. By moving it to `root.html.heex` via `live_render/3`, the Rail gets its own OS process that never restarts. Page LiveViews broadcast `{:rail_context, assigns}` via PubSub when they mount; RailLive subscribes and updates via `handle_info`. The RailState JS hook stops remounting on navigation so the localStorage restore round-trip is no longer needed at all.

**Tech Stack:** Elixir/Phoenix LiveView, PubSub via `EyeInTheSky.Events`, HEEx templates, Tailwind CSS

## Global Constraints

- Never call `Phoenix.PubSub` directly — always go through `EyeInTheSky.Events`
- Always run `mix compile --warnings-as-errors` before committing
- Work in a new worktree: `.claude/worktrees/rail-liveview/` on branch `rail-liveview`
- Worktree is 3 levels deep from project root — symlink deps with `../../../`
- `rm` is aliased to `rm-trash`; use `unlink` to remove symlinks
- `mount/3` runs twice — guard PubSub subscriptions with `if connected?(socket)`
- Don't capture socket in async closures — extract assigns first
- All PubSub: add named functions to `lib/eye_in_the_sky/events.ex`
- No `send_update` across LiveView process boundaries — use PubSub instead
- No Anthropic attribution in commit messages
- Claim an EITS task before editing files: `eitsr tasks begin -t "Rail LiveView refactor: <phase>"`

---

## File Map

| File | Change |
|------|--------|
| `lib/eye_in_the_sky/events.ex` | Add `broadcast_rail_context/1`, `subscribe_rail_context/0`, `broadcast_rail_unread_counts/1`, `subscribe_rail_unread_counts/0` |
| `lib/eye_in_the_sky_web/components/rail.ex` | Convert from `use :live_component` → `use :live_view`, change `mount/1`→`mount/3`, replace `update/2` with `handle_info/2`, subscribe to PubSub in mount, remove `@myself` from assigns |
| `lib/eye_in_the_sky_web/components/layouts/root.html.heex` | Add `live_render(@conn, EyeInTheSkyWeb.RailLive, id: "app-rail", session: %{})` |
| `lib/eye_in_the_sky_web/components/layouts/app.html.heex` | Remove `<.live_component module={Rail} ...>` block |
| `lib/eye_in_the_sky_web/router.ex` | Verify `EyeInTheSkyWeb.RailLive` is accessible from root layout |
| `lib/eye_in_the_sky_web/live/nav_hook.ex` | Replace `send_update(Rail, ..., session_updated:)` with `Events.broadcast_rail_session_updated/1` |
| `lib/eye_in_the_sky_web/live/floating_chat_live.ex` | Replace 3× `send_update(Rail, ...)` with PubSub broadcasts |
| `lib/eye_in_the_sky_web/live/chat_live.ex` | Replace `send_update(Rail, ..., unread_counts:)` with `Events.broadcast_rail_unread_counts/1` |
| `lib/eye_in_the_sky_web/live/chat_live/pubsub_handlers.ex` | Same — replace `send_update` with `Events.broadcast_rail_unread_counts/1` |
| All 41 page LiveViews in `lib/eye_in_the_sky_web/live/` | Add `Events.broadcast_rail_context(socket)` after setting sidebar assigns |
| `lib/eye_in_the_sky_web/components/rail/flyout.ex` | Remove `attr :myself` declaration; change all `phx-target={@myself}` → remove target (events go to enclosing LiveView automatically) |
| `lib/eye_in_the_sky_web/components/rail/flyout/` sub-sections | Remove `myself` attr and `phx-target={@myself}` from all subsection components |
| `assets/js/hooks/rail_state.js` | Remove `destroyed()` anti-flash logic (Rail never destroys on nav); simplify or remove `restore_rail_state` push (state already live in the persistent process) |

---

## Execution Order (for team)

Tasks have three dependency tiers:

- **Tier 1 (no deps):** Task 1 — Events additions
- **Tier 2 (needs Task 1):** Tasks 2+3, 4, 5 — Rail conversion, layout wiring, page broadcasts, send_update fixes (run in parallel)
- **Tier 3 (needs Task 2):** Tasks 6, 7 — `@myself` cleanup, JS hook simplification

---

## Task 1: PubSub Protocol in Events

**Files:**
- Modify: `lib/eye_in_the_sky/events.ex`

**Interfaces:**
- Produces: `Events.subscribe_rail_context/0`, `Events.broadcast_rail_context/1`, `Events.subscribe_rail_unread_counts/0`, `Events.broadcast_rail_unread_counts/1`, `Events.subscribe_rail_session_update/0`, `Events.broadcast_rail_session_updated/1`, `Events.subscribe_rail_notifications/0`, `Events.broadcast_rail_refresh_notifications/0`, `Events.subscribe_rail_projects/0`, `Events.broadcast_rail_refresh_projects/0`, `Events.subscribe_rail_channels/0`, `Events.broadcast_rail_refresh_channels/0`

- [ ] **Step 1: Claim EITS task**

```bash
eitsr tasks begin -t "Rail LiveView refactor: PubSub Events additions" --quiet
```

- [ ] **Step 2: Create worktree**

```bash
cd /Users/urielmaldonado/projects/eits/web
git worktree add .claude/worktrees/rail-liveview -b rail-liveview
cd .claude/worktrees/rail-liveview
ln -s ../../../deps deps
mix compile
```

- [ ] **Step 3: Add rail PubSub functions to Events**

Open `lib/eye_in_the_sky/events.ex`. Find the end of the subscribe/broadcast pairs (around line 164+). Add after the existing entries:

```elixir
  # --- Rail context (page → Rail) -------------------------------------------
  # Broadcast from page LiveViews to tell RailLive which tab and project are active.
  # The Rail subscribes once on mount and receives updates on every navigation.

  @doc "Subscribe to rail context updates (call from RailLive.mount/3)."
  def subscribe_rail_context, do: sub("rail:context")

  @doc """
  Broadcast current rail context from a page LiveView.

  Call this in mount/3 (connected? guard) AND in handle_params/3 when
  sidebar_tab or sidebar_project may have changed.

      Events.broadcast_rail_context(socket)
  """
  def broadcast_rail_context(socket) do
    broadcast("rail:context", {
      :rail_context,
      %{
        sidebar_tab: socket.assigns[:sidebar_tab] || :sessions,
        sidebar_project: socket.assigns[:sidebar_project],
        active_channel_id: socket.assigns[:active_channel_id]
      }
    })
  end

  # --- Rail unread counts (chat_live → Rail) ----------------------------------

  def subscribe_rail_unread_counts, do: sub("rail:unread_counts")
  def broadcast_rail_unread_counts(counts), do: broadcast("rail:unread_counts", {:rail_unread_counts, counts})

  # --- Rail session updates (nav_hook → Rail) ---------------------------------
  # Replaces send_update(Rail, id: "app-rail", session_updated: session).

  def subscribe_rail_session_update, do: sub("rail:session_update")
  def broadcast_rail_session_updated(session), do: broadcast("rail:session_update", {:rail_session_updated, session})

  # --- Rail refresh signals (floating_chat_live → Rail) ----------------------
  # Replaces the three send_update calls for notification, project, channel refresh.

  def subscribe_rail_notifications_refresh, do: sub("rail:refresh:notifications")
  def broadcast_rail_refresh_notifications, do: broadcast("rail:refresh:notifications", :rail_refresh_notifications)

  def subscribe_rail_projects_refresh, do: sub("rail:refresh:projects")
  def broadcast_rail_refresh_projects, do: broadcast("rail:refresh:projects", :rail_refresh_projects)

  def subscribe_rail_channels_refresh, do: sub("rail:refresh:channels")
  def broadcast_rail_refresh_channels, do: broadcast("rail:refresh:channels", :rail_refresh_channels)
```

- [ ] **Step 4: Compile**

```bash
cd /Users/urielmaldonado/projects/eits/web/.claude/worktrees/rail-liveview
mix compile --warnings-as-errors
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add lib/eye_in_the_sky/events.ex
git commit -m "feat: add rail PubSub protocol to Events"
```

---

## Task 2: Convert Rail to Standalone LiveView

**Files:**
- Modify: `lib/eye_in_the_sky_web/components/rail.ex`

**Interfaces:**
- Consumes: `Events.subscribe_rail_context/0`, `Events.subscribe_rail_unread_counts/0`, `Events.subscribe_rail_session_update/0`, `Events.subscribe_rail_notifications_refresh/0`, `Events.subscribe_rail_projects_refresh/0`, `Events.subscribe_rail_channels_refresh/0` (from Task 1)
- Produces: Module `EyeInTheSkyWeb.Components.Rail` as a LiveView; root element must have `id="app-rail"` so the vsbar collapse button (`phx-target="#app-rail"`) still works

**Context — what currently exists in update/2:**

The existing `update/2` has 5 clauses:
1. `%{notification_count: :refresh}` → refreshes notification count
2. `%{unread_counts: counts}` → sets unread_counts
3. `%{refresh_projects: true}` → reloads projects list
4. `%{refresh_channels: true}` → reloads channels
5. `%{session_updated: session}` → updates a single session in flyout_sessions
6. General `update(assigns, socket)` → adopts sidebar_tab, sidebar_project, active_channel_id

All 6 clauses become `handle_info` variants. The trigger mechanism changes from `send_update` to PubSub.

**Context — `@myself` usage in rail.ex:**

Currently `mount/1` passes `myself: @myself` in assigns so child components can send events back. After conversion, `phx-click` events on child components that omit `phx-target` automatically route to the enclosing LiveView. Remove `@myself` entirely.

- [ ] **Step 1: Change module declaration and imports**

At the top of `lib/eye_in_the_sky_web/components/rail.ex`, change:

```elixir
# BEFORE
defmodule EyeInTheSkyWeb.Components.Rail do
  @moduledoc false
  use EyeInTheSkyWeb, :live_component
  ...
  import Phoenix.LiveView, only: [start_async: 3, connected?: 1]
```

```elixir
# AFTER
defmodule EyeInTheSkyWeb.Components.Rail do
  @moduledoc false
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.Events
  ...
  import Phoenix.LiveView, only: [start_async: 3, connected?: 1]
```

- [ ] **Step 2: Change mount/1 to mount/3**

```elixir
# BEFORE
@impl true
def mount(socket) do
  socket =
    assign(socket,
      ...
    )

  if connected?(socket) do
    {:ok,
     assign(socket,
       projects: Projects.list_projects_for_sidebar(),
       flyout_sessions: Loader.load_flyout_sessions(nil),
       notification_count: Notifications.unread_count()
     )}
  else
    {:ok, socket}
  end
end
```

```elixir
# AFTER
@impl true
def mount(_params, _session, socket) do
  socket =
    assign(socket,
      projects: [],
      flyout_open: true,
      proj_picker_open: false,
      active_section: nil,
      flyout_sessions: [],
      flyout_channels: [],
      unread_counts: %{},
      notification_count: 0,
      new_project_path: nil,
      renaming_project_id: nil,
      rename_value: "",
      mobile_open: false,
      sidebar_project: nil,
      sidebar_tab: :sessions,
      active_channel_id: nil,
      workspace: nil,
      scope_type: :project,
      flyout_canvases: [],
      flyout_teams: [],
      team_search: "",
      team_status: "active",
      flyout_tasks: [],
      task_search: "",
      task_state_filter: nil,
      session_sort: :last_activity,
      session_name_filter: "",
      session_show: :twenty,
      session_scope: :current,
      session_project_visible: %{},
      session_project_collapsed: MapSet.new(),
      rail_modal: nil,
      flyout_agents: [],
      agent_search: "",
      agent_scope: "all",
      flyout_notes: [],
      note_search: "",
      note_parent_type: nil,
      flyout_skills: [],
      skill_search: "",
      skill_scope: "all",
      flyout_prompts: [],
      prompt_search: "",
      prompt_scope: "all",
      flyout_jobs: [],
      flyout_file_nodes: [],
      flyout_file_expanded: MapSet.new(),
      flyout_file_children: %{},
      flyout_file_error: nil,
      flyout_usage: nil,
      file_tabs: [],
      active_tab_path: nil,
      show_new_session_form: false,
      show_new_channel_form: false,
      prefill_agent_slug: nil,
      prefill_agent_name: nil,
      disable_auth: Application.get_env(:eye_in_the_sky, :disable_auth, false)
    )

  if connected?(socket) do
    Events.subscribe_rail_context()
    Events.subscribe_rail_unread_counts()
    Events.subscribe_rail_session_update()
    Events.subscribe_rail_notifications_refresh()
    Events.subscribe_rail_projects_refresh()
    Events.subscribe_rail_channels_refresh()

    {:ok,
     assign(socket,
       projects: Projects.list_projects_for_sidebar(),
       flyout_sessions: Loader.load_flyout_sessions(nil),
       notification_count: Notifications.unread_count()
     )}
  else
    {:ok, socket}
  end
end
```

Note: also delete `def handle_params(_params, _uri, socket), do: {:noreply, socket}` — LiveViews require `handle_params/3` unless using `@impl true def handle_params(_, _, socket), do: {:noreply, socket}`. Add this stub:

```elixir
@impl true
def handle_params(_params, _uri, socket), do: {:noreply, socket}
```

- [ ] **Step 3: Replace update/2 clauses with handle_info/2**

Remove ALL `def update(...)` clauses. Replace with:

```elixir
@impl true
# Page LiveView navigation — adopt new sidebar context
def handle_info({:rail_context, %{sidebar_tab: sidebar_tab, sidebar_project: sidebar_project, active_channel_id: active_channel_id}}, socket) do
  previous_tab = socket.assigns[:sidebar_tab]
  previous_project = socket.assigns[:sidebar_project]
  next_section = Map.get(@section_map, sidebar_tab, :sessions)

  socket =
    socket
    |> assign(:sidebar_tab, sidebar_tab)
    |> assign(:active_channel_id, active_channel_id)

  # Only adopt parent's sidebar_project if it's non-nil — prevents a page without a project
  # from clearing a project locally selected via the rail's own project picker.
  socket =
    if not is_nil(sidebar_project) do
      assign(socket, :sidebar_project, sidebar_project)
    else
      socket
    end

  socket = maybe_reload_on_project_change(socket, previous_project, sidebar_project)
  socket = maybe_reload_on_tab_change(socket, previous_tab, sidebar_tab, next_section)

  {:noreply, socket}
end

# Chat unread counts pushed by chat_live / chat_live/pubsub_handlers
def handle_info({:rail_unread_counts, counts}, socket) do
  {:noreply, assign(socket, :unread_counts, counts)}
end

# Session update pushed by nav_hook
def handle_info({:rail_session_updated, session}, socket) do
  sessions = socket.assigns[:flyout_sessions] || []

  updated_sessions =
    if Enum.any?(sessions, &(&1.id == session.id)) do
      Enum.map(sessions, fn s -> if s.id == session.id, do: session, else: s end)
    else
      Loader.load_flyout_sessions(
        socket.assigns[:sidebar_project],
        socket.assigns[:session_sort] || :last_activity,
        socket.assigns[:session_name_filter] || "",
        socket.assigns[:session_show] || :twenty
      )
    end

  {:noreply, assign(socket, :flyout_sessions, updated_sessions)}
end

# Notification refresh from floating_chat_live
def handle_info(:rail_refresh_notifications, socket) do
  {:noreply, assign(socket, :notification_count, Notifications.unread_count())}
end

# Project list refresh from floating_chat_live
def handle_info(:rail_refresh_projects, socket) do
  {:noreply, assign(socket, :projects, Projects.list_projects_for_sidebar())}
end

# Channel list refresh from floating_chat_live
def handle_info(:rail_refresh_channels, socket) do
  {:noreply, assign(socket, :flyout_channels, Loader.load_flyout_channels(socket.assigns.sidebar_project))}
end
```

- [ ] **Step 4: Remove @myself from render/1**

In the `render/1` function (or template), search for all occurrences of `myself: @myself` being passed to child components. Remove them. Examples:

```heex
<%!-- BEFORE --%>
<.flyout
  open={@flyout_open}
  ...
  myself={@myself}
/>

<%!-- AFTER --%>
<.flyout
  open={@flyout_open}
  ...
/>
```

Do the same for any other component call that receives `myself={@myself}`.

- [ ] **Step 5: Verify root element has id="app-rail"**

In the `render/1` template (or `rail.html.heex`), the outermost `<div>` must have `id="app-rail"`:

```heex
<div
  id="app-rail"
  phx-hook="RailState"
  ...
>
```

This is required so the vsbar toggle button in `app.html.heex` (`phx-target="#app-rail"`) still routes events to this LiveView.

- [ ] **Step 6: Add @impl true before handle_event/3 clauses**

The first `handle_event/3` clause needs `@impl true`. Verify it's present:

```elixir
@impl true
def handle_event("toggle_section", params, socket) do
```

- [ ] **Step 7: Compile**

```bash
cd /Users/urielmaldonado/projects/eits/web/.claude/worktrees/rail-liveview
mix compile --warnings-as-errors
```

Fix any warnings/errors. Common issues:
- `update/2` no longer exists — if anything calls `send_update(Rail, ...)` with a key not yet handled in handle_info, it will silently fail (not a compile error; catch in testing)
- Missing `alias EyeInTheSky.Events` at top

- [ ] **Step 8: Commit**

```bash
git add lib/eye_in_the_sky_web/components/rail.ex
git commit -m "feat: convert Rail LiveComponent to standalone LiveView"
```

---

## Task 3: Wire Root Layout, Remove from App Layout

**Files:**
- Modify: `lib/eye_in_the_sky_web/components/layouts/root.html.heex`
- Modify: `lib/eye_in_the_sky_web/components/layouts/app.html.heex`

**Interfaces:**
- Consumes: `EyeInTheSkyWeb.Components.Rail` as a LiveView (from Task 2)
- Produces: Rail rendered persistently in root layout; app layout no longer mounts Rail

- [ ] **Step 1: Add live_render to root.html.heex**

Open `lib/eye_in_the_sky_web/components/layouts/root.html.heex`. The current body is:

```heex
<body class="bg-base-100 min-h-[100dvh] overflow-hidden">
  {@inner_content}
</body>
```

Change to:

```heex
<body class="bg-base-100 min-h-[100dvh] overflow-hidden">
  <%= live_render(@conn, EyeInTheSkyWeb.Components.Rail, id: "app-rail-lv", session: %{}) %>
  {@inner_content}
</body>
```

Wait — `live_render` in a root layout uses `@conn`, not `@socket`. The root layout in Phoenix LiveView receives `@conn`. Confirm this is not a `@socket` context.

Actually, `live_render/3` in HEEx needs either a `Plug.Conn` or `Phoenix.LiveView.Socket`. In `root.html.heex`, the assigns come from a Plug pipeline (not a LiveView), so use `@conn`. But there's a subtlety: during a LiveView live render cycle, `root.html.heex` may receive a socket instead. Check the Phoenix LiveView docs — in LiveView live sessions, the root layout renders with a socket that has a corresponding conn. Use:

```heex
<%= Phoenix.LiveView.live_render(@conn, EyeInTheSkyWeb.Components.Rail, id: "app-rail") %>
```

If `@conn` is not available in this context, use the `socket` approach via a helper. Phoenix LiveView 0.20+ supports `live_render(assigns, module, ...)` in root layouts. Verify by checking the current Phoenix LiveView version:

```bash
grep phoenix_live_view mix.lock | head -1
```

For Phoenix LiveView 0.20+:

```heex
<body class="bg-base-100 min-h-[100dvh] overflow-hidden">
  {live_render(@conn, EyeInTheSkyWeb.Components.Rail, id: "app-rail")}
  {@inner_content}
</body>
```

The `id` must match what the vsbar collapse button targets: `phx-target="#app-rail"` in `app.html.heex`.

- [ ] **Step 2: Remove live_component from app.html.heex**

In `lib/eye_in_the_sky_web/components/layouts/app.html.heex`, find and remove:

```heex
<.live_component
  module={EyeInTheSkyWeb.Components.Rail}
  id="app-rail"
  sidebar_tab={assigns[:sidebar_tab] || :sessions}
  sidebar_project={assigns[:sidebar_project]}
  active_channel_id={assigns[:active_channel_id]}
/>
```

The Rail is now rendered in root layout, not here.

- [ ] **Step 3: Verify vsbar button still works**

In `app.html.heex` around line 87-93:

```heex
<button
  phx-click="toggle_collapsed"
  phx-target="#app-rail"
  ...
>
```

This still works because `#app-rail` targets the root element of the RailLive LiveView by CSS selector. No change needed.

- [ ] **Step 4: Compile**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 5: Commit**

```bash
git add lib/eye_in_the_sky_web/components/layouts/root.html.heex \
        lib/eye_in_the_sky_web/components/layouts/app.html.heex
git commit -m "feat: wire Rail LiveView into root layout, remove from app layout"
```

---

## Task 4: Page LiveViews — Broadcast Rail Context

**Files (41 total, split into 3 groups for parallel execution):**

**Group A — project_live/ (12 files):**
- `lib/eye_in_the_sky_web/live/project_live/agents.ex`
- `lib/eye_in_the_sky_web/live/project_live/config.ex`
- `lib/eye_in_the_sky_web/live/project_live/files.ex`
- `lib/eye_in_the_sky_web/live/project_live/jobs.ex`
- `lib/eye_in_the_sky_web/live/project_live/kanban.ex`
- `lib/eye_in_the_sky_web/live/project_live/notes.ex`
- `lib/eye_in_the_sky_web/live/project_live/prompt_new.ex`
- `lib/eye_in_the_sky_web/live/project_live/prompt_show.ex`
- `lib/eye_in_the_sky_web/live/project_live/prompts.ex`
- `lib/eye_in_the_sky_web/live/project_live/sessions.ex`
- `lib/eye_in_the_sky_web/live/project_live/skills.ex`
- `lib/eye_in_the_sky_web/live/project_live/tasks.ex`
- `lib/eye_in_the_sky_web/live/project_live/team_show.ex`
- `lib/eye_in_the_sky_web/live/project_live/teams.ex`
- `lib/eye_in_the_sky_web/live/project_live/show.ex`

**Group B — overview_live/ + iam_live/ (14 files):**
- `lib/eye_in_the_sky_web/live/overview_live/agents.ex`
- `lib/eye_in_the_sky_web/live/overview_live/config.ex`
- `lib/eye_in_the_sky_web/live/overview_live/jobs.ex`
- `lib/eye_in_the_sky_web/live/overview_live/keybindings.ex`
- `lib/eye_in_the_sky_web/live/overview_live/notifications.ex`
- `lib/eye_in_the_sky_web/live/overview_live/prompts.ex`
- `lib/eye_in_the_sky_web/live/overview_live/settings.ex`
- `lib/eye_in_the_sky_web/live/overview_live/skills.ex`
- `lib/eye_in_the_sky_web/live/overview_live/usage.ex`
- `lib/eye_in_the_sky_web/live/iam_live/agent_type_show.ex`
- `lib/eye_in_the_sky_web/live/iam_live/agent_types.ex`
- `lib/eye_in_the_sky_web/live/iam_live/policies.ex`
- `lib/eye_in_the_sky_web/live/iam_live/policy_document_edit.ex`
- `lib/eye_in_the_sky_web/live/iam_live/policy_document_new.ex`
- `lib/eye_in_the_sky_web/live/iam_live/policy_document_show.ex`
- `lib/eye_in_the_sky_web/live/iam_live/policy_documents.ex`
- `lib/eye_in_the_sky_web/live/iam_live/policy_edit.ex`
- `lib/eye_in_the_sky_web/live/iam_live/policy_new.ex`
- `lib/eye_in_the_sky_web/live/iam_live/simulator.ex`

**Group C — misc live files (5 files):**
- `lib/eye_in_the_sky_web/live/agent_live/index.ex`
- `lib/eye_in_the_sky_web/live/bookmark_live/index.ex`
- `lib/eye_in_the_sky_web/live/canvas_live.ex`
- `lib/eye_in_the_sky_web/live/chat_live.ex`
- `lib/eye_in_the_sky_web/live/dm_live/mount_state.ex`
- `lib/eye_in_the_sky_web/live/note_live/edit.ex`
- `lib/eye_in_the_sky_web/live/note_live/new.ex`

**Interfaces:**
- Consumes: `Events.broadcast_rail_context/1` (from Task 1)

**Pattern to apply to every file:**

Each file that sets `sidebar_tab:` or `sidebar_project:` in socket assigns must call `Events.broadcast_rail_context(socket)` after those assigns are set, inside a `if connected?(socket)` guard.

There are two call sites per file:

1. **In `mount/3`** — after sidebar assigns are set, before `{:ok, socket}`:

```elixir
# BEFORE
if connected?(socket) do
  subscribe_agents()
  ...
end

socket =
  socket
  |> assign(:sidebar_tab, :sessions)
  |> assign(:sidebar_project, project)

{:ok, socket}
```

```elixir
# AFTER
if connected?(socket) do
  subscribe_agents()
  ...
  Events.broadcast_rail_context(socket)  # <-- ADD THIS
end

socket =
  socket
  |> assign(:sidebar_tab, :sessions)
  |> assign(:sidebar_project, project)

{:ok, socket}
```

**Wait** — `broadcast_rail_context/1` reads `socket.assigns`, so it must be called AFTER the assigns are set. If the `connected?` block happens before assigns, restructure:

```elixir
socket =
  socket
  |> assign(:sidebar_tab, :sessions)
  |> assign(:sidebar_project, project)

if connected?(socket), do: Events.broadcast_rail_context(socket)

{:ok, socket}
```

2. **In `handle_params/3`** — when sidebar assigns may change (project navigation). Only add if the function actually changes `sidebar_tab` or `sidebar_project`. Many `handle_params/3` just handle filter/search changes and don't touch sidebar assigns — skip those.

```elixir
def handle_params(%{"id" => id}, _uri, socket) do
  project = load_project(id)
  socket = socket
    |> assign(:sidebar_project, project)
    |> assign(:sidebar_tab, :tasks)

  Events.broadcast_rail_context(socket)  # <-- ADD if sidebar assigns changed

  {:noreply, socket}
end
```

**Special case — `mount_project` helper** (`lib/eye_in_the_sky_web/helpers/project_live_helpers.ex`):

Many project LiveViews call `mount_project(socket, params, sidebar_tab: :X, ...)` which sets sidebar assigns internally. For files that use `mount_project`, add the broadcast call after it:

```elixir
socket = mount_project(socket, params, sidebar_tab: :sessions, page_title_prefix: "Sessions")
if connected?(socket), do: Events.broadcast_rail_context(socket)
```

**Special case — `dm_live/mount_state.ex`**:

This is a shared mount helper module (not a LiveView itself). The broadcast needs to happen in the calling LiveView (`dm_live.ex`), not in `mount_state.ex`.

- [ ] **Step 1: Claim EITS task (one per group, or one total)**

```bash
eitsr tasks begin -t "Rail LiveView: broadcast rail_context from page LiveViews" --quiet
```

- [ ] **Step 2: Add alias to each file that doesn't already have it**

For each file, add near the top with other aliases:

```elixir
alias EyeInTheSky.Events
```

- [ ] **Step 3: Add broadcast call in mount/3 for each file**

Follow the pattern above. Each file is different — read the existing mount carefully before editing. The key rule: broadcast AFTER sidebar assigns are set, inside `if connected?(socket)`.

- [ ] **Step 4: Add broadcast call in handle_params/3 where sidebar assigns change**

Only for `handle_params` clauses that assign `sidebar_tab` or `sidebar_project`. Skip clauses that only handle search/filter/sort params.

- [ ] **Step 5: Compile**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 6: Commit (per group)**

```bash
git add lib/eye_in_the_sky_web/live/project_live/
git commit -m "feat: broadcast rail_context from project_live page views"

git add lib/eye_in_the_sky_web/live/overview_live/ lib/eye_in_the_sky_web/live/iam_live/
git commit -m "feat: broadcast rail_context from overview_live and iam_live views"

git add lib/eye_in_the_sky_web/live/agent_live/ lib/eye_in_the_sky_web/live/bookmark_live/ \
        lib/eye_in_the_sky_web/live/canvas_live.ex lib/eye_in_the_sky_web/live/chat_live.ex \
        lib/eye_in_the_sky_web/live/dm_live/ lib/eye_in_the_sky_web/live/note_live/
git commit -m "feat: broadcast rail_context from misc live views"
```

---

## Task 5: Replace send_update Callers with PubSub Broadcasts

**Files:**
- Modify: `lib/eye_in_the_sky_web/live/floating_chat_live.ex`
- Modify: `lib/eye_in_the_sky_web/live/nav_hook.ex`
- Modify: `lib/eye_in_the_sky_web/live/chat_live.ex`
- Modify: `lib/eye_in_the_sky_web/live/chat_live/pubsub_handlers.ex`

**Interfaces:**
- Consumes: `Events.broadcast_rail_refresh_notifications/0`, `Events.broadcast_rail_refresh_projects/0`, `Events.broadcast_rail_refresh_channels/0`, `Events.broadcast_rail_session_updated/1`, `Events.broadcast_rail_unread_counts/1` (from Task 1)

`send_update(Module, ...)` only works within the SAME LiveView process. Once Rail is its own process, these calls silently drop. Replace each one.

- [ ] **Step 1: Fix floating_chat_live.ex (3 replacements)**

Find the three `send_update(EyeInTheSkyWeb.Components.Rail, ...)` calls:

```elixir
# BEFORE (notification refresh)
send_update(EyeInTheSkyWeb.Components.Rail,
  id: "app-rail",
  notification_count: :refresh
)

# AFTER
Events.broadcast_rail_refresh_notifications()
```

```elixir
# BEFORE (project refresh)
send_update(EyeInTheSkyWeb.Components.Rail,
  id: "app-rail",
  refresh_projects: true
)

# AFTER
Events.broadcast_rail_refresh_projects()
```

```elixir
# BEFORE (channel refresh)
send_update(EyeInTheSkyWeb.Components.Rail,
  id: "app-rail",
  refresh_channels: true
)

# AFTER
Events.broadcast_rail_refresh_channels()
```

Add `alias EyeInTheSky.Events` to the file if not already present.

- [ ] **Step 2: Fix nav_hook.ex (1 replacement)**

```elixir
# BEFORE
send_update(EyeInTheSkyWeb.Components.Rail, id: "app-rail", session_updated: session)

# AFTER
Events.broadcast_rail_session_updated(session)
```

Add `alias EyeInTheSky.Events` if not already present.

- [ ] **Step 3: Fix chat_live.ex (1 replacement)**

```elixir
# BEFORE
Phoenix.LiveView.send_update(EyeInTheSkyWeb.Components.Rail,
  id: "app-rail",
  unread_counts: unread_counts
)

# AFTER
Events.broadcast_rail_unread_counts(unread_counts)
```

- [ ] **Step 4: Fix chat_live/pubsub_handlers.ex (1 replacement)**

Same pattern as chat_live.ex step above.

- [ ] **Step 5: Compile**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 6: Commit**

```bash
git add lib/eye_in_the_sky_web/live/floating_chat_live.ex \
        lib/eye_in_the_sky_web/live/nav_hook.ex \
        lib/eye_in_the_sky_web/live/chat_live.ex \
        lib/eye_in_the_sky_web/live/chat_live/pubsub_handlers.ex
git commit -m "feat: replace send_update(Rail) with PubSub broadcasts"
```

---

## Task 6: Remove @myself from Flyout and Sub-Sections

**Files:**
- Modify: `lib/eye_in_the_sky_web/components/rail/flyout.ex`
- Modify: all `lib/eye_in_the_sky_web/components/rail/flyout/*.ex` that declare or pass `myself`

**Context:**

In a LiveComponent, `@myself` is the component's own handle, needed so `phx-target={@myself}` routes events back to the component (not the parent LiveView). Now that Rail is a LiveView, events sent without `phx-target` go to the LiveView by default — which is exactly where we want them. `@myself` is no longer needed.

- [ ] **Step 1: Find all @myself usages in flyout components**

```bash
grep -rn "myself" lib/eye_in_the_sky_web/components/rail/
```

- [ ] **Step 2: Remove from flyout.ex**

In `flyout.ex`:
- Remove `attr :myself, :any, required: true` from the attr declarations
- Remove all `phx-target={@myself}` from button/form elements
- Remove `myself={@myself}` from all sub-component calls

- [ ] **Step 3: Remove from each sub-section component**

For each file in `lib/eye_in_the_sky_web/components/rail/flyout/` that has `attr :myself`:
- Remove the `attr :myself` declaration
- Remove all `phx-target={@myself}` occurrences
- Remove `myself={...}` from inner component calls

- [ ] **Step 4: Compile**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 5: Commit**

```bash
git add lib/eye_in_the_sky_web/components/rail/
git commit -m "refactor: remove @myself from Rail flyout components (Rail is now a LiveView)"
```

---

## Task 7: Simplify RailState JS Hook

**Files:**
- Modify: `assets/js/hooks/rail_state.js`

**Context:**

The `destroyed()` callback in `RailState` currently sets `data-rail-collapsed` on `<html>` so the next mount doesn't flash the open flyout briefly before restore. Since Rail is now a persistent LiveView process, `destroyed()` **never fires** during live navigation. The anti-flash logic in `destroyed()` is dead code. The `restore_rail_state` push in `mounted()` is still valid for the first page load (cold start), but not needed on subsequent navigations.

The localStorage-based `restore_rail_state` round-trip is still needed on first load (server has no state before the hook fires). After that, the Rail's state is live in the persistent process — no round-trips on navigation.

- [ ] **Step 1: Remove the destroyed() anti-flash workaround**

In `rail_state.js`, the `destroyed()` method has:

```javascript
destroyed() {
  // Live navigation: the root inline script (full loads only) can't re-arm
  // the anti-flash override, and the next Rail mount defaults to open. If
  // the persisted state is collapsed, hide the flyout NOW — the next
  // mount's restore reply removes the attribute again.
  if (readState().flyout_open === false) {
    document.documentElement.setAttribute('data-rail-collapsed', '1')
  }
  // ... event listener cleanup ...
}
```

Remove ONLY the `data-rail-collapsed` set. Keep the event listener cleanup (those still fire if the hook is ever destroyed, e.g. during a full page reload):

```javascript
destroyed() {
  // (removed anti-flash logic — Rail is now a persistent LiveView, destroyed() won't
  //  fire during live navigation)
  if (this._openHandler) {
    this.el.removeEventListener('rail:open', this._openHandler)
  }
  // ... keep rest of cleanup ...
}
```

- [ ] **Step 2: Update mounted() comment**

The comment in `mounted()` says:
```javascript
// Send the full blob to the server once on mount.
// The server applies each field defensively. Once the round-trip lands,
// drop the pre-paint anti-flash override (set in root.html.heex) —
// LiveView state is authoritative from here on.
```

Update to:
```javascript
// Send the full blob to the server on first load (cold start).
// On subsequent live navigations, Rail is a persistent LiveView and already
// has state — this fires once at connection time, not on every nav.
// Once the round-trip lands, drop the pre-paint anti-flash override.
```

- [ ] **Step 3: Compile JS assets (optional — vitest)**

```bash
cd assets
ln -sf ../../../../assets/node_modules node_modules 2>/dev/null || true
npx vitest run js/hooks/rail_state.test.js 2>/dev/null || echo "no test file — skip"
```

- [ ] **Step 4: Commit**

```bash
git add assets/js/hooks/rail_state.js
git commit -m "refactor: simplify RailState hook (Rail is now a persistent LiveView)"
```

---

## Task 8: End-to-End Verification

- [ ] **Step 1: Start worktree server**

```bash
cd /Users/urielmaldonado/projects/eits/web/.claude/worktrees/rail-liveview
cd assets && ln -sf ../../../../assets/node_modules node_modules && cd ..
nohup env VITE_PORT=5174 PORT=5002 DISABLE_AUTH=true mix phx.server \
  > /tmp/rail-liveview-server.log 2>&1 & disown
sleep 10
```

- [ ] **Step 2: Playwright smoke tests**

```javascript
// Test 1: Flyout stays open across navigation
// Open Sessions flyout, navigate to Tasks page, verify Sessions flyout is still open
// and still shows sessions content (no flicker, no wrong-section flash)

// Test 2: File flyout persists when clicking Tasks in rail
// Open Files flyout, click Tasks icon in rail, verify Files flyout stays open

// Test 3: Active section highlight is stable
// Navigate from Sessions to Tasks page — verify Tasks icon highlights immediately
// (no Sessions flash first)

// Test 4: VSBar collapse button still works
// Click the collapse button in VSBar, verify sidebar collapses
```

Run with:
```bash
PORT=5002 DISABLE_AUTH=true npx playwright test --headed
```

- [ ] **Step 3: Kill server after testing**

```bash
lsof -ti:5002 | xargs kill -9 2>/dev/null || true
lsof -ti:5174 | xargs kill -9 2>/dev/null || true
```

---

## Task 9: Merge to Main

- [ ] **Step 1: Final compile check**

```bash
cd /Users/urielmaldonado/projects/eits/web/.claude/worktrees/rail-liveview
mix compile --warnings-as-errors
```

- [ ] **Step 2: Merge**

```bash
cd /Users/urielmaldonado/projects/eits/web
git checkout features
git merge rail-liveview
```

- [ ] **Step 3: Complete EITS task**

```bash
eitsr tasks complete <task_id> --message "Rail converted to standalone LiveView in root layout. No more flicker on navigation."
```

- [ ] **Step 4: Log commit**

```bash
HASH=$(git rev-parse HEAD)
eitsr commits create --hash $HASH
```

---

## Known Gotchas

1. **`live_render` in root layout**: In Phoenix LiveView root layouts, the render context is a `Plug.Conn`, not a `Phoenix.LiveView.Socket`. Use `live_render(@conn, ...)`, NOT `live_render(@socket, ...)`. If you see an undefined `@conn` error, verify the layout is `root.html.heex` and not a sub-layout.

2. **`@myself` removal order**: Remove `@myself` from flyout.ex AFTER removing it from Rail's render. Otherwise the flyout complains about a required attr that's no longer passed.

3. **`handle_params/3` stub**: LiveViews that use `live_render` in root layout require a `handle_params/3` callback even if it's a no-op. Add `def handle_params(_, _, socket), do: {:noreply, socket}` to Rail.

4. **Double mount**: `mount/3` runs on dead render AND connected render. All PubSub subscriptions MUST be inside `if connected?(socket)`. Without the guard, you get double subscriptions and double PubSub messages.

5. **Context broadcast ordering**: In page LiveViews, `Events.broadcast_rail_context(socket)` reads `socket.assigns[:sidebar_tab]` and `socket.assigns[:sidebar_project]`. Call it AFTER those assigns are set on the socket.

6. **`send_update` silently fails cross-process**: After Rail becomes its own process, existing `send_update(Rail, ...)` calls in other LiveViews silently no-op. There's no compile error. The only symptom is unread counts / notification count not updating. Task 5 fixes this.

7. **Tauri worktree isolation**: Do NOT touch `.claude/worktrees/tauri/`. It has its own isolated deps and _build. This refactor does not apply to Tauri builds.
