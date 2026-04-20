# Chat Discord Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the main application sidebar from `/chat` entirely and replace it with a self-contained Discord/Slack-style layout — narrow channel list on the left with a back button, message feed filling the rest.

**Architecture:** Move `/chat` into a dedicated `:chat` live_session that reuses the existing `canvas` layout (no sidebar). Add an internal channel sidebar directly in `ChatLive.render/1`. Simplify `chat_section.ex` to a plain nav link — no expandable channel tree.

**Tech Stack:** Phoenix LiveView, HEEx templates, Tailwind CSS, DaisyUI. No new JS hooks.

---

## File Map

| File | Change |
|------|--------|
| `lib/eye_in_the_sky_web/router.ex` | Move `/chat` out of `:app` live_session into new `:chat` live_session with canvas layout |
| `lib/eye_in_the_sky_web/live/chat_live.ex` | New full-viewport render with internal channel sidebar; add `new_channel_name` assign; add `show_new_channel`, `cancel_new_channel`, `update_channel_name` event handlers |
| `lib/eye_in_the_sky_web/live/chat_live/channel_actions.ex` | Implement real `handle_create_channel/2` (replace the stub) |
| `lib/eye_in_the_sky_web/components/sidebar/chat_section.ex` | Remove expandable channel tree; become a simple nav link to `/chat` |

---

### Task 1: Move `/chat` to a sidebar-free layout

**Files:**
- Modify: `lib/eye_in_the_sky_web/router.ex:164`

- [ ] **Step 1: Remove `/chat` from `:app` live_session and add new `:chat` session**

Open `router.ex`. Find the `:app` live_session (line ~133). Remove this line:
```elixir
      live "/chat", ChatLive, :index
```

Then add a new live_session block after the `:canvas` block (around line 131), before `:app`:
```elixir
    live_session :chat,
      layout: {EyeInTheSkyWeb.Layouts, :canvas},
      on_mount: [EyeInTheSkyWeb.AuthHook, EyeInTheSkyWeb.NavHook] do
      live "/chat", ChatLive, :index
    end
```

The canvas layout (`lib/eye_in_the_sky_web/components/layouts/canvas.html.heex`) renders no sidebar. It uses `@palette_shortcut` and `@palette_projects` which NavHook provides. This is a clean reuse.

- [ ] **Step 2: Verify compile**

```bash
cd /Users/urielmaldonado/projects/eits/web && mix compile
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/eye_in_the_sky_web/router.ex
git commit -m "feat(chat): move /chat to canvas layout (no sidebar)"
```

---

### Task 2: Add internal channel sidebar to ChatLive

**Files:**
- Modify: `lib/eye_in_the_sky_web/live/chat_live.ex`

- [ ] **Step 1: Add `new_channel_name` assign in `mount/3`**

In the `mount/3` function, add one line after the existing assigns:
```elixir
|> assign(:new_channel_name, nil)
```

The full `socket =` block should end with:
```elixir
    socket =
      socket
      |> assign(:session_id, session_id)
      |> assign(:working_agents, %{})
      |> assign(:sidebar_tab, :chat)
      |> assign(:sidebar_project, nil)
      |> assign(:new_channel_name, nil)
      |> allow_upload(...)
```

- [ ] **Step 2: Add event handlers for channel name form**

After the existing `handle_event("create_channel", ...)` clause, add three new handlers:

```elixir
  @impl true
  def handle_event("show_new_channel", _params, socket) do
    {:noreply, assign(socket, :new_channel_name, "")}
  end

  @impl true
  def handle_event("cancel_new_channel", _params, socket) do
    {:noreply, assign(socket, :new_channel_name, nil)}
  end

  @impl true
  def handle_event("update_channel_name", %{"value" => value}, socket) do
    {:noreply, assign(socket, :new_channel_name, value)}
  end
```

- [ ] **Step 3: Replace the `render/1` function with the new Discord layout**

Replace the entire `render(assigns)` function (lines 331-367) with:

```elixir
  @impl true
  def render(assigns) do
    active_channel =
      Enum.find(assigns.channels, fn c ->
        to_string(c.id) == to_string(assigns.active_channel_id)
      end)

    assigns = assign(assigns, :active_channel, active_channel)

    ~H"""
    <div class="flex h-[var(--app-viewport-height)] bg-base-100">
      <%!-- Channel sidebar --%>
      <nav
        class="w-[200px] flex-shrink-0 flex flex-col border-r border-base-content/8 bg-base-100"
        aria-label="Channels"
      >
        <%!-- Back button --%>
        <div class="px-2 pt-2 pb-1 border-b border-base-content/8">
          <button
            onclick="history.length > 1 ? history.back() : window.location.href = '/'"
            class="btn btn-ghost btn-xs px-1.5 self-center mr-1 text-base-content/50 hover:text-base-content"
            aria-label="Go back"
            title="Go back"
          >
            <.icon name="hero-arrow-left" class="w-4 h-4" />
          </button>
        </div>

        <%!-- Section header --%>
        <div class="flex items-center justify-between px-3 pt-3 pb-1">
          <span class="text-[10px] font-bold uppercase tracking-widest text-base-content/30">
            Channels
          </span>
          <button
            phx-click="show_new_channel"
            class="text-base-content/30 hover:text-base-content/60 transition-colors leading-none text-base"
            title="New channel"
            aria-label="New channel"
          >
            +
          </button>
        </div>

        <%!-- Channel list --%>
        <div class="flex-1 overflow-y-auto py-1">
          <%= for channel <- @channels do %>
            <.link
              navigate={~p"/chat?channel_id=#{channel.id}"}
              class={[
                "flex items-center gap-1 px-2.5 py-1 mx-1.5 rounded text-sm transition-colors",
                if(
                  not is_nil(@active_channel_id) &&
                    to_string(@active_channel_id) == to_string(channel.id),
                  do: "bg-primary/10 text-primary font-semibold",
                  else: "text-base-content/45 hover:text-base-content/70 hover:bg-base-content/5"
                )
              ]}
            >
              <span class="text-base-content/25 text-[13px]">#</span>{channel.name}
            </.link>
          <% end %>

          <%!-- New channel inline form or button --%>
          <%= if @new_channel_name do %>
            <form
              phx-submit="create_channel"
              phx-keydown="cancel_new_channel"
              class="flex items-center gap-1 px-2.5 mx-1.5 py-1"
            >
              <span class="text-base-content/25 text-[13px]">#</span>
              <input
                type="text"
                name="name"
                value={@new_channel_name}
                phx-keyup="update_channel_name"
                placeholder="channel-name"
                class="flex-1 bg-transparent border-b border-base-content/15 text-sm text-base-content/70 placeholder:text-base-content/25 outline-none py-0.5 font-mono"
                autofocus
              />
            </form>
          <% else %>
            <button
              phx-click="show_new_channel"
              class="flex items-center gap-1 px-2.5 mx-1.5 py-1 text-sm text-base-content/30 hover:text-base-content/55 transition-colors w-full text-left"
            >
              + New Channel
            </button>
          <% end %>
        </div>
      </nav>

      <%!-- Main chat area --%>
      <div class="flex-1 flex flex-col min-w-0">
        <ChannelHeader.channel_header
          active_channel={@active_channel}
          agent_status_counts={@agent_status_counts}
          show_members={@show_members}
          channel_members={@channel_members}
          sessions_by_project={@sessions_by_project}
          session_search={@session_search}
        />
        <.message_feed
          active_channel_id={@active_channel_id}
          messages={@messages}
          active_agents={@active_agents}
          channel_members={@channel_members}
          working_agents={@working_agents}
          slash_items={@slash_items}
          socket={@socket}
        />
        <.agent_drawer
          show={@show_agent_drawer}
          all_projects={@all_projects}
          prompts={@prompts}
          agent_templates={@agent_templates}
          uploads={@uploads}
        />
      </div>
    </div>
    """
  end
```

Note: the `message_feed` private component no longer needs `max-w-6xl mx-auto` since the chat area is no longer fighting with the sidebar for viewport space. Remove those classes from `message_feed/1`:

```elixir
  defp message_feed(assigns) do
    ~H"""
    <div class="flex-1 min-h-0 overflow-hidden">
      <.svelte
        name="AgentMessagesPanel"
        ...
      />
    </div>
    """
  end
```

- [ ] **Step 4: Verify compile**

```bash
cd /Users/urielmaldonado/projects/eits/web && mix compile
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add lib/eye_in_the_sky_web/live/chat_live.ex
git commit -m "feat(chat): add internal channel sidebar with back button"
```

---

### Task 3: Implement real channel creation in ChatLive.ChannelActions

**Files:**
- Modify: `lib/eye_in_the_sky_web/live/chat_live/channel_actions.ex`

The current `handle_create_channel/2` is a stub that flashes "Channel creation coming soon". Replace it with real logic.

- [ ] **Step 1: Replace the stub with a working implementation**

Replace:
```elixir
  @spec handle_create_channel(Phoenix.LiveView.Socket.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_create_channel(socket, _params) do
    {:noreply, put_flash(socket, :info, "Channel creation coming soon")}
  end
```

With:
```elixir
  @spec handle_create_channel(Phoenix.LiveView.Socket.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_create_channel(socket, params) do
    name = (params["name"] || socket.assigns[:new_channel_name] || "") |> String.trim()

    if name == "" do
      {:noreply, Phoenix.Component.assign(socket, :new_channel_name, nil)}
    else
      project_id = socket.assigns[:project_id] || 1
      channel_id = EyeInTheSky.Channels.Channel.generate_id(project_id, name)

      case Channels.create_channel(%{
             id: channel_id,
             uuid: Ecto.UUID.generate(),
             name: name,
             channel_type: "public",
             project_id: project_id
           }) do
        {:ok, _channel} ->
          channels = EyeInTheSky.Channels.list_channels_for_project(project_id)

          {:noreply,
           socket
           |> Phoenix.Component.assign(:channels, EyeInTheSkyWeb.ChatPresenter.serialize_channels(channels))
           |> Phoenix.Component.assign(:new_channel_name, nil)
           |> Phoenix.LiveView.push_patch(to: Phoenix.VerifiedRoutes.sigil_p("/chat?channel_id=#{channel_id}", []))}

        {:error, _changeset} ->
          {:noreply, Phoenix.Component.assign(socket, :new_channel_name, nil)}
      end
    end
  end
```

Add `alias EyeInTheSky.Channels` at the top if not already present (it is — line 10).

- [ ] **Step 2: Verify compile**

```bash
cd /Users/urielmaldonado/projects/eits/web && mix compile
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/eye_in_the_sky_web/live/chat_live/channel_actions.ex
git commit -m "feat(chat): implement channel creation in ChatLive"
```

---

### Task 4: Simplify chat_section.ex — remove expandable channel tree

**Files:**
- Modify: `lib/eye_in_the_sky_web/components/sidebar/chat_section.ex`

The channel list no longer belongs in the main sidebar. The `chat_section` becomes a simple nav link to `/chat`.

- [ ] **Step 1: Replace the component with a simple nav link**

Replace the entire `chat_section.ex` content with:

```elixir
defmodule EyeInTheSkyWeb.Components.Sidebar.ChatSection do
  @moduledoc false
  use EyeInTheSkyWeb, :html

  attr :sidebar_tab, :atom, required: true
  attr :collapsed, :boolean, required: true

  def chat_section(assigns) do
    ~H"""
    <.link
      navigate={~p"/chat"}
      class={[
        "flex items-center gap-2.5 w-full text-left text-sm transition-colors min-h-[44px]",
        if(@collapsed, do: "px-4 py-1 justify-center", else: "px-3 py-1"),
        if(@sidebar_tab == :chat,
          do: "text-base-content/80 hover:bg-base-content/5",
          else: "text-base-content/55 hover:text-base-content/80 hover:bg-base-content/5"
        )
      ]}
      title="Chat"
    >
      <.icon name="hero-chat-bubble-left-ellipsis" class="w-4 h-4 flex-shrink-0" />
      <span class={["truncate font-medium", if(@collapsed, do: "hidden")]}>Chat</span>
      <%= if @sidebar_tab == :chat && !@collapsed do %>
        <span class="ml-auto w-1.5 h-1.5 rounded-full bg-primary flex-shrink-0"></span>
      <% end %>
    </.link>
    """
  end
end
```

The removed attrs (`expanded_chat`, `channels`, `active_channel_id`, `new_channel_name`, `myself`) were only needed for the channel tree. Remove them here.

- [ ] **Step 2: Update callers of `chat_section` — remove now-deleted attrs**

Find all usages:

```bash
grep -rn "chat_section" lib/
```

Each call site that passes `expanded_chat`, `channels`, `active_channel_id`, `new_channel_name`, `myself` must have those attrs removed. The expected call site is in `lib/eye_in_the_sky_web/components/sidebar.ex` (or `sidebar/` directory). Remove the deleted attrs from the call.

- [ ] **Step 3: Update Sidebar LiveComponent — remove channel-related assigns and event handlers**

Search for the sidebar LiveComponent that manages `toggle_chat`, `show_new_channel`, `update_channel_name`, `cancel_new_channel`, `expanded_chat`, `new_channel_name`:

```bash
grep -rn "toggle_chat\|expanded_chat\|show_new_channel\|update_channel_name" lib/eye_in_the_sky_web/components/
```

In that module (likely `lib/eye_in_the_sky_web/components/sidebar.ex`):
- Remove `expanded_chat` from state/assigns
- Remove `new_channel_name` from state/assigns
- Remove `handle_event("toggle_chat", ...)` handler
- Remove `handle_event("show_new_channel", ...)` handler
- Remove `handle_event("cancel_new_channel", ...)` handler
- Remove `handle_event("update_channel_name", ...)` handler
- Remove `channels` assign and the channel-loading logic that fed the sidebar

- [ ] **Step 4: Verify compile**

```bash
cd /Users/urielmaldonado/projects/eits/web && mix compile
```

Expected: no errors. Compiler will catch any remaining attr references.

- [ ] **Step 5: Commit**

```bash
git add lib/eye_in_the_sky_web/components/sidebar/chat_section.ex lib/eye_in_the_sky_web/components/sidebar.ex
git commit -m "feat(chat): remove channel tree from sidebar, simplify to nav link"
```

---

### Task 5: Visual verification with Playwright

- [ ] **Step 1: Start test server**

```bash
PORT=5002 DISABLE_AUTH=true mix phx.server &
```

Wait ~5 seconds for startup.

- [ ] **Step 2: Verify no sidebar on `/chat`**

Navigate to `http://localhost:5002/chat`. Take a screenshot. Confirm:
- No left sidebar (sessions list, nav items)
- Channel panel visible on the far left (~200px)
- Back button (`←`) visible at top of channel panel
- Channels listed below it
- Message feed fills remaining space

- [ ] **Step 3: Verify sidebar still works on other pages**

Navigate to `http://localhost:5002/`. Confirm:
- Main sidebar is present
- "Chat" nav item is a plain link (no expand arrow, no channel list)
- Clicking it navigates to `/chat`

- [ ] **Step 4: Verify channel switching**

On `/chat`, click a different channel. Confirm URL updates to `?channel_id=X` and the channel highlights as active.

- [ ] **Step 5: Verify back button**

Click the `←` button. Confirm it navigates back (or to `/` if no history).

- [ ] **Step 6: Close browser and kill test server**

```bash
kill %1
```

---

## Spec Coverage Check

- [x] `/chat` route shows no main sidebar → Task 1 (new layout)
- [x] Channel list in left panel → Task 2 (new render)
- [x] Back button icon-only, history fallback → Task 2
- [x] `+` creates new channel inline → Tasks 2 + 3
- [x] Active channel highlighted → Task 2
- [x] Channel list removed from main sidebar → Task 4
- [x] Clicking "Chat" in sidebar navigates to `/chat` (no expandable tree) → Task 4
- [x] Message feed unchanged → Task 2 (passed through unchanged)
