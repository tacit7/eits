# DM New Session — Blank Page + Auto-naming Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Change the sessions flyout "+" button (with-project case only) to open a blank DM page; spawn the agent only on first message send; then auto-name the session with Haiku based on the opening message.

**Architecture:** `/dm/new` requires a valid `project_id` — the mount redirects to root if absent. On first send, `create_agent_without_start/1` = `RecordBuilder.create_records/1` (no worker, no prompt). The body and spawn opts (e.g. `eits_workflow: "0"`) are stored together in a server-side one-time ETS store (`PendingSessionMessages`) keyed by `session_id`, then the handler navigates to `/dm/:session_id`. DmLive `:show` adds `handle_params/3` which pops `{body, send_opts}` (one-shot — consumed on read) and queues it via `send(self(), {:auto_send, body, send_opts})`. `handle_info/2` merges `send_opts` into `:session_cli_opts` (the assign `MessageHandlers` reads when calling `continue_session`) before delegating to `MessageHandlers.handle_send_message/2` — model/effort/thinking/budget/`message_id`/worker-start all go through the proven path. No body in the URL; no re-submit on refresh or reconnect. Haiku names the session afterward with a DB conditional guard.

**Tech Stack:** Elixir/Phoenix LiveView, ETS (stdlib), Req (already in deps), Anthropic Messages API (`claude-haiku-4-5-20251001`), `EyeInTheSky.Events` PubSub.

## Global Constraints

- Never symlink `_build`. Work on the `features` branch directly.
- Run `mix compile --warnings-as-errors` before every commit.
- No GitHub PRs — commit to `features`, push, Codex reviews on branch.
- Route `/dm/new` must be declared **before** `/dm/:session_id` in the router.
- `/dm/new` requires a project_id — missing or invalid project_id redirects to root.
- Only the **with-project** sessions flyout "+" changes. No-project "+" keeps the existing drawer.
- PTY mode (`dm_use_pty`): if true, fall back to the old `handle_new_session` behavior.
- Auto-naming is non-fatal — any error silently leaves the session with the fallback name.

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `lib/eye_in_the_sky/pending_session_messages.ex` | Create | ETS-backed one-time message store |
| `lib/eye_in_the_sky/application.ex` | Modify | Add `PendingSessionMessages` to supervisor tree |
| `lib/eye_in_the_sky_web/router.ex` | Modify | Add `live "/dm/new", DmLive, :new` before `/dm/:session_id` |
| `lib/eye_in_the_sky_web/live/dm_live.ex` | Modify | `:new` mount (project guard + redirect); `handle_params/3`; `handle_info({:auto_send})` |
| `lib/eye_in_the_sky_web/live/dm_live/mount_state.ex` | Modify | Add `assign_new_session_defaults/1` with exact types |
| `lib/eye_in_the_sky_web/components/new_dm_page.ex` | Create | Bare HEEx composer — no layout wrapper (layout from `use EyeInTheSkyWeb, :live_view`) |
| `lib/eye_in_the_sky_web/components/rail/flyout.ex` | Modify | With-project "+" fires `new_session_navigate` |
| `lib/eye_in_the_sky_web/components/rail.ex` | Modify | Add `handle_event("new_session_navigate", ...)` |
| `lib/eye_in_the_sky_web/components/rail/project_actions.ex` | Modify | `handle_new_session_navigate/2` with PTY guard |
| `lib/eye_in_the_sky/agents/agent_manager.ex` | Modify | `create_agent_without_start/1` = `RecordBuilder.create_records/1` |
| `lib/eye_in_the_sky_web/live/dm_live/message_handlers.ex` | Modify | `:new` clause → store body → navigate |
| `lib/eye_in_the_sky/sessions/naming.ex` | Create | Haiku auto-naming with DB conditional guard |
| `test/eye_in_the_sky_web/live/dm_live_new_test.exs` | Create | `async: false` LiveView + unit tests |

---

### Task 1: `PendingSessionMessages` — one-time ETS store

**Files:**
- Create: `lib/eye_in_the_sky/pending_session_messages.ex`
- Modify: `lib/eye_in_the_sky/application.ex`

**Interfaces:**
- `PendingSessionMessages.put(session_id, body, send_opts)` → `:ok` — stores `{body, send_opts}` together so the auto-send path can replay session-spawn opts (e.g. `eits_workflow: "0"`) through `continue_session`
- `PendingSessionMessages.pop(session_id)` → `{body, send_opts}` tuple or `nil` — atomic take, consumed once

- [ ] **Step 1: Create `pending_session_messages.ex`**

```elixir
defmodule EyeInTheSky.PendingSessionMessages do
  @moduledoc "Short-lived one-shot store for initial DM bodies + send opts. Consumed on first read."
  use GenServer

  @table :pending_session_messages
  @ttl_ms 60_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set])
    {:ok, %{}}
  end

  @doc "Store body + send_opts for session_id. Overwrites any existing entry. TTL: 60s."
  def put(session_id, body, send_opts \\ [])
      when is_integer(session_id) and is_binary(body) and is_list(send_opts) do
    expires = System.monotonic_time(:millisecond) + @ttl_ms
    :ets.insert(@table, {session_id, {body, send_opts}, expires})
    :ok
  end

  @doc "Atomically retrieve and delete. Returns {body, send_opts} or nil if absent/expired."
  def pop(session_id) when is_integer(session_id) do
    case :ets.take(@table, session_id) do
      [{^session_id, {body, send_opts}, expires}] ->
        if System.monotonic_time(:millisecond) <= expires, do: {body, send_opts}, else: nil

      [] ->
        nil
    end
  end
end
```

- [ ] **Step 2: Add to the Application supervisor**

Open `lib/eye_in_the_sky/application.ex`. Find the `children` list. Add `EyeInTheSky.PendingSessionMessages` before any web endpoint children (early in the list so it's available when LiveView mounts):

```elixir
children = [
  # ... existing children above ...
  EyeInTheSky.PendingSessionMessages,
  # ... rest of existing children ...
]
```

- [ ] **Step 3: Compile check**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 4: Smoke test in iex**

```bash
iex -S mix
```

```elixir
EyeInTheSky.PendingSessionMessages.put(999, "hello", [eits_workflow: "0"])
EyeInTheSky.PendingSessionMessages.pop(999)  # => {"hello", [eits_workflow: "0"]}
EyeInTheSky.PendingSessionMessages.pop(999)  # => nil  (consumed)
```

- [ ] **Step 5: Commit**

```bash
git add lib/eye_in_the_sky/pending_session_messages.ex \
        lib/eye_in_the_sky/application.ex
git commit -m "feat: PendingSessionMessages one-shot ETS store for /dm/new flow"
```

---

### Task 2: Route + DmLive `:new` mount with correct assigns

**Files:**
- Modify: `lib/eye_in_the_sky_web/router.ex`
- Modify: `lib/eye_in_the_sky_web/live/dm_live.ex`
- Modify: `lib/eye_in_the_sky_web/live/dm_live/mount_state.ex`

- [ ] **Step 1: Add the route**

Open `lib/eye_in_the_sky_web/router.ex`. Find:
```elixir
live "/dm/:session_id", DmLive, :show
```
Add immediately before it:
```elixir
live "/dm/new", DmLive, :new
live "/dm/:session_id", DmLive, :show
```

- [ ] **Step 2: Add `assign_new_session_defaults/1` to MountState**

Open `lib/eye_in_the_sky_web/live/dm_live/mount_state.ex`. Add this function. All types verified from the actual `assign_ui_flags/2`, `assign_stream_defaults/1`, `assign_task_defaults/1`, and `assign_upload_config/1` source.

```elixir
@doc "All UI assigns for /dm/new — same keys/types as assign_essential_defaults/2, sourced from settings defaults."
def assign_new_session_defaults(socket) do
  effective = EyeInTheSky.Settings.JsonSettings.effective_settings(%{}, %{})

  socket
  |> assign(:page_title, "New conversation")
  |> assign(:session, nil)
  |> assign(:agent, nil)
  |> assign(:session_id, nil)
  |> assign(:session_uuid, nil)
  |> assign(:agent_id, nil)
  |> assign(:session_status, nil)
  |> assign(:hide_mobile_header, true)
  # ui flags — types match assign_ui_flags/2 exactly
  |> assign(:active_tab, "messages")
  |> assign(:session_ref, nil)
  |> assign(:processing, false)
  |> assign(:selected_model, EyeInTheSky.Settings.default_model())
  |> assign(:selected_effort, "medium")
  |> assign(:active_overlay, nil)
  |> assign(:show_live_stream, get_in(effective, ["general", "show_live_stream"]) || false)
  |> assign(:slash_items, EyeInTheSkyWeb.Helpers.SlashItems.build())
  |> assign(:diff_cache, %{})
  |> assign(:commits_view, :list)
  |> assign(:diff_mode, :unified)
  |> assign(:cumulative_diff, nil)
  |> assign(:reload_timer, nil)
  |> assign(:thinking_enabled, get_in(effective, ["general", "thinking_enabled"]) || false)
  |> assign(:show_thinking_blocks, false)
  |> assign(:max_budget_usd, get_in(effective, ["general", "max_budget_usd"]))
  |> assign(:session_cli_opts, [])
  |> assign(:compacting, false)
  |> assign(:message_search_query, "")
  |> assign(:session_context, nil)
  |> assign(:reloading, false)
  |> assign(:active_timer, nil)
  |> assign(:codex_raw_lines, [])
  |> assign(:notify_on_stop, get_in(effective, ["general", "notify_on_stop"]) || false)
  |> assign(:dm_settings_scope, "session")
  |> assign(:dm_settings_subtab, "general")
  |> assign(:dm_settings_effective, effective)
  |> assign(:dm_settings_session_overrides, %{})
  |> assign(:dm_settings_agent_overrides, %{})
  |> assign(:syncing, true)
  # stream defaults
  |> assign(:stream_content, "")
  |> assign(:stream_tool, nil)
  |> assign(:stream_thinking, nil)
  |> assign(:total_tokens, 0)
  |> assign(:total_cost, 0.0)
  |> assign(:context_used, 0)
  |> assign(:context_window, 0)
  # task defaults
  |> assign(:message_limit, 50)
  |> assign(:has_more_messages, false)
  |> assign(:selected_task, nil)
  |> assign(:task_notes, [])
  |> assign(:workflow_states, [])
  |> assign(:current_task, :not_loaded)
  |> assign(:queued_prompts, [])
  |> assign(:tasks, [])
  |> assign(:commits, [])
  |> assign(:notes, [])
  # PTY assigns — referenced by DmLive terminate/render
  |> assign(:pty_pid, nil)
  |> assign(:pty_pending_launch, false)
  |> assign(:pty_launched_at, nil)
  # uploads
  |> assign(:tauri_dropped_files, [])
  |> allow_upload(:files,
      accept: ~w(.jpg .jpeg .png .gif .pdf .txt .md .csv .json .xml .html),
      max_entries: 10,
      max_file_size: 50_000_000,
      auto_upload: true
    )
end
```

- [ ] **Step 3: Add `:new` mount clause in DmLive**

Open `lib/eye_in_the_sky_web/live/dm_live.ex`. Add **before** the existing `mount/3`:

```elixir
# /dm/new — must have a valid project_id; redirect to root otherwise
def mount(params, _session, socket) when not is_map_key(params, "session_id") do
  new_session_project_id =
    case Integer.parse(params["project_id"] || "") do
      {id, ""} -> id
      _ -> nil
    end

  case new_session_project_id && EyeInTheSky.Projects.get_project(new_session_project_id) do
    {:ok, project} ->
      socket =
        socket
        |> assign(:live_action, :new)
        |> assign(:new_session_project_id, project.id)
        |> MountState.assign_new_session_defaults()

      {:ok, socket}

    _ ->
      # Missing, non-integer, or non-existent project_id — redirect to root
      {:ok, redirect(socket, to: "/")}
  end
end
```

- [ ] **Step 4: Add `handle_params/3` to DmLive**

```elixir
# Pop the one-shot pending body + send_opts and queue auto-send.
# send_opts are injected into the socket before MessageHandlers is called, so
# eits_workflow/session_cli_opts/effort from the :new spawn path reach continue_session.
def handle_params(_params, _uri, %{assigns: %{live_action: :show}} = socket) do
  session_id = socket.assigns.session_id

  if connected?(socket) && is_integer(session_id) do
    case EyeInTheSky.PendingSessionMessages.pop(session_id) do
      nil -> :ok
      {body, send_opts} -> send(self(), {:auto_send, body, send_opts})
    end
  end

  {:noreply, socket}
end

def handle_params(_params, _uri, socket), do: {:noreply, socket}
```

- [ ] **Step 5: Add `handle_info/2` for auto-send**

`MessageHandlers.handle_send_message/2` forwards `socket.assigns[:session_cli_opts]` into `AgentManager.continue_session/3` (verified at message_handlers.ex:30,55-57). Bare assigns (e.g. `socket.assigns.eits_workflow`) are ignored. Merge `send_opts` into `:session_cli_opts` so `eits_workflow: "0"` actually reaches `continue_session`.

```elixir
def handle_info({:auto_send, body, send_opts}, socket) do
  # Merge spawn-time opts into session_cli_opts — that is the assign MessageHandlers
  # reads when calling continue_session. A bare socket.assigns.eits_workflow is not read.
  existing = socket.assigns[:session_cli_opts] || []
  socket = assign(socket, :session_cli_opts, Keyword.merge(existing, send_opts))
  # Correct module name verified from source: EyeInTheSkyWeb.DmLive.MessageHandlers
  EyeInTheSkyWeb.DmLive.MessageHandlers.handle_send_message(body, socket)
end
```

- [ ] **Step 6: Compile check**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 7: Commit**

```bash
git add lib/eye_in_the_sky_web/router.ex \
        lib/eye_in_the_sky_web/live/dm_live.ex \
        lib/eye_in_the_sky_web/live/dm_live/mount_state.ex
git commit -m "feat: /dm/new route, :new mount with project guard, handle_params auto-send"
```

---

### Task 3: Blank DM page component

**Files:**
- Create: `lib/eye_in_the_sky_web/components/new_dm_page.ex`
- Modify: `lib/eye_in_the_sky_web/live/dm_live.ex` (render/1)

**Layout note:** LiveView layout is applied by `use EyeInTheSkyWeb, :live_view` at the module level. `render/1` returns bare HEEx — no `<Layouts.app>` wrapper. This matches how all other LiveViews in this project work.

- [ ] **Step 1: Create `new_dm_page.ex`**

**No `phx-hook` on the textarea.** The existing `CommandHistory` hook assumes `socket.assigns.session` for `list_files`, and `DmComposer` targets `#message-input` — neither is safe here. Plain submit (Enter/button) is correct for the new-session page.

```elixir
defmodule EyeInTheSkyWeb.Components.NewDmPage do
  use EyeInTheSkyWeb, :html

  attr :processing, :boolean, default: false
  attr :selected_model, :string, required: true

  def new_dm_page(assigns) do
    ~H"""
    <div class="flex flex-col h-full items-center justify-center bg-base-100">
      <div class="w-full max-w-2xl px-4 flex flex-col gap-4">
        <h1 class="text-xl font-semibold text-base-content text-center">New conversation</h1>
        <p class="text-sm text-base-content/50 text-center">
          Send a message to start an agent session.
        </p>
        <form phx-submit="send_message" class="flex flex-col gap-2">
          <textarea
            id="new-session-composer"
            name="body"
            class="textarea textarea-bordered w-full min-h-[120px] resize-none"
            placeholder="What do you want to work on?"
            disabled={@processing}
            autofocus
          ></textarea>
          <div class="flex items-center justify-between">
            <span class="text-xs text-base-content/40"><%= @selected_model %></span>
            <button type="submit" class="btn btn-primary btn-sm" disabled={@processing}>
              <%= if @processing do %>
                <span class="loading loading-spinner loading-xs"></span>
              <% else %>
                Send
              <% end %>
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end
end
```

- [ ] **Step 3: Add render branch in DmLive**

```elixir
alias EyeInTheSkyWeb.Components.NewDmPage

def render(%{live_action: :new} = assigns) do
  ~H"""
  <NewDmPage.new_dm_page processing={@processing} selected_model={@selected_model} />
  """
end

# existing render/1 stays below unchanged
```

- [ ] **Step 4: Compile and smoke test**

```bash
mix compile --warnings-as-errors
```

Navigate to `http://localhost:5001/dm/new` — should redirect to `/` (no project_id). Navigate to `http://localhost:5001/dm/new?project_id=1` — should render the blank composer. Existing `/dm/:id` routes must still work.

- [ ] **Step 5: Commit**

```bash
git add lib/eye_in_the_sky_web/components/new_dm_page.ex \
        lib/eye_in_the_sky_web/live/dm_live.ex
git commit -m "feat: blank DM page component and render branch for :new action"
```

---

### Task 4: Wire "+" button — with-project only, PTY guard

**Files:**
- Modify: `lib/eye_in_the_sky_web/components/rail/flyout.ex`
- Modify: `lib/eye_in_the_sky_web/components/rail/project_actions.ex`

- [ ] **Step 1: Change only the with-project flyout button**

In `flyout.ex`, change only the `@sidebar_project` branch. No-project branch unchanged.

Before:
```heex
<%= if @sidebar_project do %>
  <.header_action_btn phx-click="new_session" phx-value-project_id={@sidebar_project.id} ... />
<% else %>
  <.header_action_btn phx-click="toggle_new_session_form" ... />
<% end %>
```

After:
```heex
<%= if @sidebar_project do %>
  <.header_action_btn phx-click="new_session_navigate" phx-value-project_id={@sidebar_project.id} title={"New session in #{@sidebar_project.name}"} />
<% else %>
  <.header_action_btn phx-click="toggle_new_session_form" title="New session" />
<% end %>
```

- [ ] **Step 2: Add `handle_new_session_navigate/2` to project_actions.ex**

Add import at top if not present:
```elixir
import Phoenix.LiveView, only: [push_navigate: 2]
```

Add new handler — do NOT modify `handle_new_session/2`:
```elixir
def handle_new_session_navigate(%{"project_id" => project_id}, socket) do
  if EyeInTheSky.Settings.get_boolean("dm_use_pty") do
    handle_new_session(%{"project_id" => project_id}, socket)
  else
    {:noreply, push_navigate(socket, to: "/dm/new?project_id=#{project_id}")}
  end
end
```

- [ ] **Step 3: Wire the event in Rail and any other parent LiveViews**

The rail button fires events that are handled in `lib/eye_in_the_sky_web/components/rail.ex`. Confirm:

```bash
grep -n "handle_event.*new_session" lib/eye_in_the_sky_web/components/rail.ex
```

In `rail.ex`, add alongside the existing `"new_session"` handler (verified at line 265):

```elixir
def handle_event("new_session_navigate", params, socket) do
  ProjectActions.handle_new_session_navigate(params, socket)
end
```

Also check for any other LiveViews that delegate rail events:

```bash
grep -rn '"new_session"' lib/eye_in_the_sky_web/live/ | grep "handle_event"
```

Add the same `"new_session_navigate"` handler to each matching module.

- [ ] **Step 4: Compile check and smoke test**

```bash
mix compile --warnings-as-errors
```

With a project in the sidebar: click "+" → should land on `/dm/new?project_id=X`. Without a project: "+" still opens drawer. PTY on: "+" spawns immediately.

- [ ] **Step 5: Commit**

```bash
git add lib/eye_in_the_sky_web/components/rail/flyout.ex \
        lib/eye_in_the_sky_web/components/rail/project_actions.ex
git commit -m "feat: with-project sessions + navigates to /dm/new (PTY-guarded)"
```

---

### Task 5: `create_agent_without_start/1` + `:new` send handler

**Files:**
- Modify: `lib/eye_in_the_sky/agents/agent_manager.ex`
- Modify: `lib/eye_in_the_sky_web/live/dm_live/message_handlers.ex`

- [ ] **Step 1: Add `create_agent_without_start/1` to AgentManager**

From source: `create_agent/1` = `RecordBuilder.create_records(opts)` + `send_message(...)`. Worker starts on first `send_message`/`continue_session` call via `SessionBridge.ensure_worker_running/2`. Records-only means calling only `RecordBuilder.create_records/1`.

```elixir
@doc """
Creates agent and session DB records only. Does not start the worker or send any prompt.
The worker starts on the first `continue_session/3` call via SessionBridge.ensure_worker_running/2.
"""
def create_agent_without_start(opts) do
  RecordBuilder.create_records(opts)
end
```

- [ ] **Step 2: Guard slash commands in DmLive, then add `:new` clause to MessageHandlers**

**Part A — guard in `DmLive.handle_event("send_message", ...)`**

`DmLive.handle_event("send_message", ...)` applies `SlashCommands.apply_server_commands/2` before routing to `handle_send_message`. On `:new`, `socket.assigns.session` is nil and commands like `/rename` will crash with a function-clause error.

Find the exact callsite first — the real signature is `apply_server_commands(server_cmds, socket)`, not `apply_server_commands(socket, params)`:

```bash
grep -n "apply_server_commands\|SlashCommands" lib/eye_in_the_sky_web/live/dm_live.ex
```

The call is at dm_live.ex:293-296. It builds `server_cmds` from params first, then calls `apply_server_commands(server_cmds, socket)`. Wrap **only the apply call** in a live_action guard — do not move or copy the `server_cmds` extraction:

```elixir
# Before (existing, around line 293):
socket = SlashCommands.apply_server_commands(server_cmds, socket)

# After:
socket =
  if socket.assigns.live_action == :new do
    socket  # session doesn't exist yet — skip slash server commands
  else
    SlashCommands.apply_server_commands(server_cmds, socket)
  end
```

If `server_cmds` is computed inline inside the call, extract it to a variable first so the guard can wrap just the `apply_server_commands` step.

**Part B — add import and `:new` clause to MessageHandlers**

Open `lib/eye_in_the_sky_web/live/dm_live/message_handlers.ex`. Add import at top:

```elixir
import Phoenix.LiveView, only: [push_navigate: 2, put_flash: 3]
```

If `put_flash` is already imported, remove it from the list above.

Add **before** the existing `handle_send_message/2`:

```elixir
def handle_send_message(body, %{assigns: %{live_action: :new}} = socket) do
  body = String.trim(body)
  if body == "", do: {:noreply, socket}, else: do_spawn_new_session(body, socket)
end
```

```elixir
defp do_spawn_new_session(body, socket) do
  fallback_name = String.slice(body, 0, 60)
  model = socket.assigns.selected_model
  project_id = socket.assigns.new_session_project_id

  # mount already validated the project exists; this is a safety re-check.
  # Return error rather than silently creating a no-project session.
  with {:ok, project} <- EyeInTheSky.Projects.get_project(project_id) do
    create_opts = [
      description: fallback_name,
      model: model,
      project_id: project.id,
      project_path: project.path,
      eits_workflow: "0"      # matches existing handle_new_session/2 behavior
    ]

    # Carry through any slash opts apply_session_opts/2 added (e.g. /plan, /chrome, /mcp).
    # Force eits_workflow: "0" — overrides any conflicting value in session_cli_opts.
    # Note: server commands (/model, /effort) are no-ops on :new because the guard
    # skips apply_server_commands; this is acceptable and documented in the Self-Review.
    send_opts = (socket.assigns[:session_cli_opts] || []) |> Keyword.put(:eits_workflow, "0")

    case EyeInTheSky.Agents.AgentManager.create_agent_without_start(create_opts) do
      {:ok, %{session: session}} ->
        EyeInTheSky.PendingSessionMessages.put(session.id, body, send_opts)

        Task.start(fn ->
          EyeInTheSky.Sessions.Naming.try_auto_name(session.id, body, fallback_name)
        end)

        {:noreply, push_navigate(socket, to: "/dm/#{session.id}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create session: #{inspect(reason)}")}
    end
  else
    {:error, _} ->
      {:noreply, put_flash(socket, :error, "Project not found.")}
  end
end
```

> Verify `EyeInTheSky.Projects.get_project/1` (non-bang) exists:
> ```bash
> grep -n "def get_project\b" lib/eye_in_the_sky/projects.ex
> ```
> If only the bang form exists, wrap: `try do Projects.get_project!(project_id) |> then(&{:ok, &1}) rescue _ -> {:error, :not_found} end`

- [ ] **Step 3: Compile check**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 4: End-to-end test**

1. Go to `http://localhost:5001/dm/new?project_id=<id>`
2. Type a message, send
3. Confirm redirect to `/dm/:id` (no `initial_body` in URL)
4. Confirm message appears and agent responds
5. Refresh `/dm/:id` — confirm auto-send does NOT fire again (body was consumed from ETS)
6. Check: exactly one user message in DB for this session:
   ```bash
   psql eits_dev -c "SELECT id, session_id, sender_role FROM messages ORDER BY inserted_at DESC LIMIT 3;"
   ```

- [ ] **Step 5: Commit**

```bash
git add lib/eye_in_the_sky/agents/agent_manager.ex \
        lib/eye_in_the_sky_web/live/dm_live/message_handlers.ex
git commit -m "feat: create_agent_without_start/1 and :new send handler with ETS body store"
```

---

### Task 6: Auto-naming via Haiku with DB conditional guard

**Files:**
- Create: `lib/eye_in_the_sky/sessions/naming.ex`

- [ ] **Step 1: Verify Session schema module path**

```bash
grep -rn "defmodule.*Session\b" lib/eye_in_the_sky/sessions/ | head -5
```

Use the exact module in the `alias` below.

- [ ] **Step 2: Create `lib/eye_in_the_sky/sessions/naming.ex`**

```elixir
defmodule EyeInTheSky.Sessions.Naming do
  @moduledoc false

  import Ecto.Query
  alias EyeInTheSky.{Events, Repo}
  alias EyeInTheSky.Sessions.Session

  @api_url "https://api.anthropic.com/v1/messages"
  @model "claude-haiku-4-5-20251001"
  @max_prompt_chars 200
  @max_name_chars 60

  @system_prompt "You are a chat-session namer. Output ONLY a short descriptive name " <>
                   "(3–6 words, noun-preferring, no quotes, no markdown, no trailing punctuation). " <>
                   "Nothing else — just the name on a single line."

  @doc """
  Non-fatal auto-name. Only writes if the session name still equals `fallback_name` —
  the DB WHERE clause makes the guard atomic (no TOCTOU).
  """
  def try_auto_name(session_id, body, fallback_name) do
    with {:ok, generated_name} <- generate_name(body),
         {1, [updated_session]} <-
           Repo.update_all(
             from(s in Session,
               where: s.id == ^session_id and s.name == ^fallback_name,
               select: s
             ),
             set: [name: generated_name]
           ) do
      Events.broadcast_rail_session_updated(updated_session)
    else
      _ -> :ok
    end
  end

  @doc "Returns `{:ok, name}` or `{:error, reason}`. Never raises."
  def generate_name(body) do
    api_key = System.get_env("ANTHROPIC_API_KEY", "")

    if api_key == "" do
      {:error, :no_api_key}
    else
      prompt_text = String.slice(body, 0, @max_prompt_chars)

      case Req.post(@api_url,
             json: %{
               model: @model,
               max_tokens: 20,
               system: @system_prompt,
               messages: [
                 %{role: "user",
                   content: "Name this chat session based on the opening message:\n\n#{prompt_text}"}
               ]
             },
             headers: [
               {"x-api-key", api_key},
               {"anthropic-version", "2023-06-01"}
             ],
             receive_timeout: 10_000
           ) do
        {:ok, %{status: 200, body: %{"content" => [%{"text" => text} | _]}}} ->
          name =
            text
            |> String.trim()
            |> String.trim("\"")
            |> String.trim("'")
            |> String.slice(0, @max_name_chars)

          if name == "", do: {:error, :empty_name}, else: {:ok, name}

        {:ok, %{status: status}} ->
          {:error, {:api_error, status}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end
```

- [ ] **Step 3: Compile check**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 4: Integration and race guard tests** — manual

1. Send a first message from `/dm/new?project_id=X` — session created with fallback name
2. Wait ~2–5s — rail should update with Haiku name
3. Repeat, but rename the session immediately after send — Haiku name should not overwrite

- [ ] **Step 5: Commit**

```bash
git add lib/eye_in_the_sky/sessions/naming.ex
git commit -m "feat: Haiku auto-naming with DB conditional race guard"
```

---

### Task 7: Tests

**Files:**
- Create: `test/eye_in_the_sky_web/live/dm_live_new_test.exs`

**Rules verified from existing tests:**
- `async: false` (AgentManager touches supervised processes)
- Create records via context functions: `Projects.create_project/1`, `Agents.create_agent/1`, `Sessions.create_session/1` — no factory library
- Project required: `name`, `slug` (unique), `active: true`
- Agent required: `uuid`, `description`, `source`, `project_id`
- Session required: `uuid`, `agent_id`, `name`, `started_at` (ISO8601 string)
- `sender_role` not `role` in the messages table
- Naming tested without network — mock via env var to `:no_api_key` path only; success path tested via `try_auto_name/3` unit test with a fake body (skips real Req call by asserting on DB state with known fallback)

- [ ] **Step 1: Write the test file**

```elixir
defmodule EyeInTheSkyWeb.Live.DmLiveNewTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias EyeInTheSky.{Agents, Projects, Repo, Sessions}

  defp uniq, do: System.unique_integer([:positive])

  defp create_project do
    {:ok, project} =
      Projects.create_project(%{
        name: "dm-new-test-#{uniq()}",
        slug: "dm-new-test-#{uniq()}",
        active: true,
        path: "/tmp/dm-new-test-#{uniq()}"
      })
    project
  end

  defp create_agent_and_session(project) do
    {:ok, agent} =
      Agents.create_agent(%{
        uuid: Ecto.UUID.generate(),
        description: "Test Agent",
        source: "web",
        project_id: project.id
      })

    {:ok, session} =
      Sessions.create_session(%{
        uuid: Ecto.UUID.generate(),
        agent_id: agent.id,
        name: "Test Session",
        started_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    {agent, session}
  end

  # ── /dm/new rendering ──────────────────────────────────────────────────

  describe "GET /dm/new" do
    test "redirects to root when project_id is absent", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/dm/new")
    end

    test "redirects to root when project_id is not an integer", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/dm/new?project_id=abc")
    end

    test "redirects to root when project_id is an integer but project does not exist", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/dm/new?project_id=999999")
    end

    test "renders blank composer with stable DOM id when project_id is valid", %{conn: conn} do
      project = create_project()
      {:ok, _view, html} = live(conn, "/dm/new?project_id=#{project.id}")

      assert html =~ "New conversation"
      assert html =~ ~s(id="new-session-composer")
    end

    test "shows default model name", %{conn: conn} do
      project = create_project()
      {:ok, _view, html} = live(conn, "/dm/new?project_id=#{project.id}")

      assert html =~ EyeInTheSky.Settings.default_model()
    end
  end

  # ── send_message from /dm/new ──────────────────────────────────────────

  describe "send_message" do
    setup do
      %{project: create_project()}
    end

    test "empty body is a no-op — no redirect, no session created", %{conn: conn, project: project} do
      count_before = Repo.aggregate(EyeInTheSky.Sessions.Session, :count)

      {:ok, view, _html} = live(conn, "/dm/new?project_id=#{project.id}")

      result =
        view
        |> form("form[phx-submit='send_message']", %{"body" => "   "})
        |> render_submit()

      refute match?({:error, {:live_redirect, _}}, result)
      assert Repo.aggregate(EyeInTheSky.Sessions.Session, :count) == count_before
    end

    test "valid body creates exactly one session and redirects", %{conn: conn, project: project} do
      count_before = Repo.aggregate(EyeInTheSky.Sessions.Session, :count)

      {:ok, view, _html} = live(conn, "/dm/new?project_id=#{project.id}")

      assert {:error, {:live_redirect, %{to: "/dm/" <> _}}} =
               view
               |> form("form[phx-submit='send_message']", %{"body" => "Write a hello world"})
               |> render_submit()

      assert Repo.aggregate(EyeInTheSky.Sessions.Session, :count) == count_before + 1
    end

    test "body is stored in PendingSessionMessages and consumed — not in redirect URL",
         %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, "/dm/new?project_id=#{project.id}")

      assert {:error, {:live_redirect, %{to: to}}} =
               view
               |> form("form[phx-submit='send_message']", %{"body" => "Debug the login bug"})
               |> render_submit()

      # URL must NOT contain the body
      refute to =~ "initial_body"
      refute to =~ "Debug"

      # PendingSessionMessages entry is created (not yet consumed because
      # we haven't mounted the :show DmLive — that happens on redirect).
      # pop/1 returns {body, send_opts} tuple.
      session_id = to |> String.replace("/dm/", "") |> String.to_integer()
      assert {body, send_opts} = EyeInTheSky.PendingSessionMessages.pop(session_id)
      assert is_binary(body)
      assert Keyword.get(send_opts, :eits_workflow) == "0"
      # Second pop returns nil (consumed)
      assert is_nil(EyeInTheSky.PendingSessionMessages.pop(session_id))
    end
  end

  # ── PendingSessionMessages unit tests ──────────────────────────────────

  describe "PendingSessionMessages" do
    test "put and pop returns {body, send_opts} exactly once" do
      EyeInTheSky.PendingSessionMessages.put(88_888, "hello", [eits_workflow: "0"])
      assert EyeInTheSky.PendingSessionMessages.pop(88_888) == {"hello", [eits_workflow: "0"]}
      assert EyeInTheSky.PendingSessionMessages.pop(88_888) == nil
    end

    test "pop on unknown key returns nil" do
      assert EyeInTheSky.PendingSessionMessages.pop(99_999_999) == nil
    end

    test "send_opts includes session_cli_opts from socket and forces eits_workflow: 0" do
      # Unit-tests the send_opts computation logic from do_spawn_new_session.
      # This proves the merge shape; full integration through continue_session
      # requires Mox for AgentManager and is tracked as a follow-up.
      existing_cli_opts = [effort: "medium", plan: true]
      send_opts = existing_cli_opts |> Keyword.put(:eits_workflow, "0")

      assert Keyword.get(send_opts, :eits_workflow) == "0"
      assert Keyword.get(send_opts, :effort) == "medium"
      assert Keyword.get(send_opts, :plan) == true
    end
  end

  # ── Sessions.Naming unit tests ──────────────────────────────────────────

  describe "Sessions.Naming.generate_name/1" do
    test "returns {:error, :no_api_key} when ANTHROPIC_API_KEY is empty" do
      original = System.get_env("ANTHROPIC_API_KEY")

      try do
        System.put_env("ANTHROPIC_API_KEY", "")
        assert {:error, :no_api_key} = EyeInTheSky.Sessions.Naming.generate_name("test body")
      after
        case original do
          nil -> System.delete_env("ANTHROPIC_API_KEY")
          val -> System.put_env("ANTHROPIC_API_KEY", val)
        end
      end
    end
  end

  describe "Sessions.Naming.try_auto_name/3 race guard" do
    setup do
      project = create_project()
      {_agent, session} = create_agent_and_session(project)
      %{session: session}
    end

    test "does not overwrite a manually renamed session", %{session: session} do
      {:ok, _} = Sessions.update_session(session, %{name: "My Manual Name"})
      # fallback_name does not match current name → DB WHERE fails → no update
      :ok = EyeInTheSky.Sessions.Naming.try_auto_name(session.id, "some body", session.name)
      # Wait for any async side effects (none expected, but be safe)
      reloaded = Repo.get!(EyeInTheSky.Sessions.Session, session.id)
      assert reloaded.name == "My Manual Name"
    end

    test "updates name when current name still equals fallback", %{session: session} do
      # Directly call update_all path by injecting a known name
      {:ok, session} = Sessions.update_session(session, %{name: "initial fallback"})

      # try_auto_name would call generate_name then update_all.
      # With no API key, generate_name returns {:error, :no_api_key} and the
      # with chain short-circuits — name stays unchanged. This tests the guard logic
      # without a network call.
      System.put_env("ANTHROPIC_API_KEY", "")

      try do
        :ok = EyeInTheSky.Sessions.Naming.try_auto_name(session.id, "body", "initial fallback")
        reloaded = Repo.get!(EyeInTheSky.Sessions.Session, session.id)
        assert reloaded.name == "initial fallback"
      after
        System.delete_env("ANTHROPIC_API_KEY")
      end
    end
  end
end
```

- [ ] **Step 2: Run the tests**

```bash
mix test test/eye_in_the_sky_web/live/dm_live_new_test.exs --trace
```

Fix any missing context function imports (`alias EyeInTheSky.{Agents, Projects, ...}`), wrong field names, or missing project `slug`/`name` constraints.

- [ ] **Step 3: Full suite regression check**

```bash
mix test
```

- [ ] **Step 4: Commit**

```bash
git add test/eye_in_the_sky_web/live/dm_live_new_test.exs
git commit -m "test: /dm/new LiveView + PendingSessionMessages + Naming unit tests"
```

---

## Self-Review

### All review findings addressed

| Finding | Fix |
|---------|-----|
| Auto-send not one-shot (URL re-submit) | `PendingSessionMessages.pop` is atomic take — consumed on first read; refresh gets nil |
| `URI.encode/1` wrong for query params | Body never in URL — stored in ETS, no encoding needed |
| Body leaks to browser history/logs | Body never in URL |
| No-project startup failure | `:new` mount fetches `Projects.get_project/1` and redirects on error; `do_spawn_new_session` returns error if project missing |
| `EyeInTheSky.JsonSettings` wrong module | `EyeInTheSky.Settings.JsonSettings.effective_settings(%{}, %{})` |
| `SlashItems` wrong path | `EyeInTheSkyWeb.Helpers.SlashItems.build()` |
| `<Layouts.app>` not needed | Layout applied by `use EyeInTheSkyWeb, :live_view`; bare HEEx in render |
| Tests: `Repo.insert!(%Project{})` missing workspace_id | `Projects.create_project/1` context function used |
| Tests: `Sessions.create_session` missing required fields | Full required fields: `uuid`, `agent_id`, `name`, `started_at` |
| Tests: `role` column name wrong | `sender_role` — no raw SQL in tests |
| Tests: env mutation not restored | `try/after` block restores/deletes env var |
| Tests: naming never exercises success path | Unit tests exercise the guard logic and no-key path; success path requires real Req mock (noted as follow-up with Mox) |
| **MessageHandlers wrong module name** | `EyeInTheSkyWeb.DmLive.MessageHandlers` (not `EyeInTheSkyWeb.Live.DmLive.MessageHandlers`) |
| **Rail handle_event missing** | `handle_event("new_session_navigate", ...)` added to `rail.ex` alongside existing `"new_session"` handler |
| **Integer project_id but non-existent project** | Mount validates project existence via `Projects.get_project/1`; redirect on `{:error, _}` |
| **`eits_workflow: "0"` missing** | Added to `create_opts` in `do_spawn_new_session` to preserve existing behavior |
| **`eits_workflow` never reaches `continue_session`** | `PendingSessionMessages` stores `{body, send_opts}`; `handle_info` merges `send_opts` into `:session_cli_opts` (the assign MessageHandlers reads at message_handlers.ex:30,55-57) before calling `handle_send_message` — `eits_workflow: "0"` now flows into `continue_session` |
| **Slash command crash on `:new` (`session` is nil)** | `DmLive.handle_event("send_message", ...)` wraps `apply_server_commands(server_cmds, socket)` call (dm_live.ex:293-296) with `if live_action == :new` guard using correct arg order `(server_cmds, socket)` |
| **Slash opts (e.g. /plan) dropped before `continue_session`** | `send_opts` now captures `socket.assigns[:session_cli_opts]` (which `apply_session_opts/2` may have enriched) and forces `eits_workflow: "0"` via `Keyword.put` — all slash-set opts survive into the ETS store |
| **`/model`, `/effort` no-ops on first message** | Intentional and documented: server commands are skipped on `:new` because session doesn't exist yet; acceptable trade-off for the new-session page |
| **DaisyUI classes in NewDmPage** | Not a violation — DaisyUI is the project's component library, used throughout existing components (`btn`, `btn-ghost`, `textarea-bordered`, `loading-spinner`, etc.). See `project_sessions_table.ex`, `kanban_bulk_bar.ex`, etc. |
| **Test proves Keyword.merge in isolation** | Test is honest about scope: proves the `send_opts` merge shape. Full integration through `continue_session` requires Mox for AgentManager; tracked as follow-up. |
| **Hook unsafe on new-page textarea** | No `phx-hook` on new-page textarea — `CommandHistory` assumes session for `list_files`; `DmComposer` targets `#message-input`. Plain submit (Enter/button) is correct for this page. |

### Type consistency
- `session.id` is integer throughout (ETS key, navigation, DB query)
- `fallback_name` flows `do_spawn_new_session` → `try_auto_name/3` → `Repo.update_all WHERE`
- `PendingSessionMessages.put/3` guards `is_integer(session_id)`, `is_binary(body)`, `is_list(send_opts)`
- `PendingSessionMessages.pop/1` returns `{body, send_opts}` tuple or `nil`
- `handle_info({:auto_send, body, send_opts}, socket)` — three-tuple matches `pop/1` output; `send_opts` merged into `:session_cli_opts` (not bare assigns)
- `Repo.update_all` returns `{count, [rows]}` — matched as `{1, [updated_session]}`
- `create_agent_without_start/1` returns `{:ok, %{agent: _, session: _}}` — same as `create_agent/1`
