# Canvas Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persistent canvas overlay that lets users add sessions to named floating-window surfaces from any page in the app.

**Architecture:** Two Ecto migrations create `canvases` and `canvas_sessions` tables; a `Canvases` context wraps all DB access; a `CanvasOverlayComponent` LiveComponent mounts once in `app.html.heex` and owns the overlay state; a `ChatWindowComponent` renders each floating chat window; a single `ChatWindowHook` JS hook handles both drag and resize on the same element; the sidebar and session cards get canvas-aware UI additions.

**Tech Stack:** Elixir/Phoenix LiveView, Ecto (PostgreSQL), DaisyUI, Tailwind CSS, vanilla JS hooks.

**Spec:** `docs/superpowers/specs/2026-03-18-workspace-overlay-design.md`

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `priv/repo/migrations/20260319000001_create_canvases.exs` | `canvases` table |
| Create | `priv/repo/migrations/20260319000002_create_canvas_sessions.exs` | `canvas_sessions` table |
| Create | `lib/eye_in_the_sky_web/canvases/canvas.ex` | Ecto schema |
| Create | `lib/eye_in_the_sky_web/canvases/canvas_session.ex` | Ecto schema — `session_id` is bare integer field (intentional: avoids cross-context Ecto association) |
| Create | `lib/eye_in_the_sky_web/canvases.ex` | Context — all DB access |
| Create | `test/eye_in_the_sky_web/canvases_test.exs` | Context unit tests |
| Modify | `lib/eye_in_the_sky_web/events.ex` | Add `unsubscribe_session/1` and `unsubscribe_session_status/1` helpers |
| Create | `assets/js/hooks/chat_window_hook.js` | Single hook — handles drag AND resize on the same element |
| Modify | `assets/js/app.js` | Register `ChatWindowHook` |
| Create | `lib/eye_in_the_sky_web_web/components/canvas_overlay_component.ex` | Full-screen overlay LiveComponent |
| Create | `lib/eye_in_the_sky_web_web/components/chat_window_component.ex` | Floating chat window LiveComponent |
| Modify | `lib/eye_in_the_sky_web_web/components/layouts/app.html.heex` | Mount overlay component |
| Modify | `lib/eye_in_the_sky_web_web/components/sidebar.ex` | Add Canvas section |
| Modify | `lib/eye_in_the_sky_web_web/components/session_card.ex` | Add `attr :canvases` only — dropdown goes in the `:actions` slot in each calling LiveView |
| Modify | `lib/eye_in_the_sky_web_web/live/agent_live/index.ex` | Handle add_to_canvas + add_to_new_canvas events; pass dropdown via :actions slot |
| Modify | `lib/eye_in_the_sky_web_web/live/project_live/sessions.ex` | Handle add_to_canvas + add_to_new_canvas events; pass dropdown via :actions slot |
| Modify | `lib/eye_in_the_sky_web_web/live/session_live/index.ex` | Same handlers + :actions slot dropdown |
| Modify | `lib/eye_in_the_sky_web_web/live/team_live/index.ex` | Same handlers + :actions slot dropdown |

---

## Task 1: Database Migrations

**Files:**
- Create: `priv/repo/migrations/20260319000001_create_canvases.exs`
- Create: `priv/repo/migrations/20260319000002_create_canvas_sessions.exs`

- [ ] **Step 1: Create canvases migration**

```elixir
# priv/repo/migrations/20260319000001_create_canvases.exs
defmodule EyeInTheSkyWeb.Repo.Migrations.CreateCanvases do
  use Ecto.Migration

  def change do
    create table(:canvases) do
      add :name, :text, null: false
      timestamps()
    end
  end
end
```

- [ ] **Step 2: Create canvas_sessions migration**

```elixir
# priv/repo/migrations/20260319000002_create_canvas_sessions.exs
defmodule EyeInTheSkyWeb.Repo.Migrations.CreateCanvasSessions do
  use Ecto.Migration

  def change do
    create table(:canvas_sessions) do
      add :canvas_id, references(:canvases, on_delete: :delete_all), null: false
      add :session_id, references(:sessions, on_delete: :delete_all), null: false
      add :pos_x, :integer, default: 0, null: false
      add :pos_y, :integer, default: 0, null: false
      add :width, :integer, default: 320, null: false
      add :height, :integer, default: 260, null: false
      timestamps()
    end

    create index(:canvas_sessions, [:canvas_id])
    create unique_index(:canvas_sessions, [:canvas_id, :session_id])
  end
end
```

- [ ] **Step 3: Run migrations**

```bash
mix ecto.migrate
```

Expected: two migrations applied, no errors.

- [ ] **Step 4: Verify schema**

```bash
psql -d eits_dev -c "\d canvas_sessions"
```

Expected: table with all columns and the unique index on `(canvas_id, session_id)`.

---

## Task 2: Ecto Schemas

**Files:**
- Create: `lib/eye_in_the_sky_web/canvases/canvas.ex`
- Create: `lib/eye_in_the_sky_web/canvases/canvas_session.ex`

- [ ] **Step 1: Write Canvas schema**

```elixir
# lib/eye_in_the_sky_web/canvases/canvas.ex
defmodule EyeInTheSkyWeb.Canvases.Canvas do
  use Ecto.Schema
  import Ecto.Changeset

  schema "canvases" do
    field :name, :string
    has_many :canvas_sessions, EyeInTheSkyWeb.Canvases.CanvasSession
    timestamps()
  end

  def changeset(canvas, attrs) do
    canvas
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
  end
end
```

- [ ] **Step 2: Write CanvasSession schema**

`session_id` is intentionally a bare integer field — it's a FK to `sessions.id` but we do not define an Ecto `belongs_to :session` association to avoid coupling the Canvases context to the Sessions schema. The DB-level FK (migration) still enforces referential integrity.

```elixir
# lib/eye_in_the_sky_web/canvases/canvas_session.ex
defmodule EyeInTheSkyWeb.Canvases.CanvasSession do
  use Ecto.Schema
  import Ecto.Changeset

  schema "canvas_sessions" do
    belongs_to :canvas, EyeInTheSkyWeb.Canvases.Canvas
    # Bare integer field — FK to sessions.id (integer PK, not UUID).
    # No belongs_to :session to keep Canvases context decoupled from Sessions context.
    field :session_id, :integer
    field :pos_x, :integer, default: 0
    field :pos_y, :integer, default: 0
    field :width, :integer, default: 320
    field :height, :integer, default: 260
    timestamps()
  end

  def changeset(cs, attrs) do
    cs
    |> cast(attrs, [:canvas_id, :session_id, :pos_x, :pos_y, :width, :height])
    |> validate_required([:canvas_id, :session_id])
    |> unique_constraint([:canvas_id, :session_id])
  end
end
```

- [ ] **Step 3: Compile**

```bash
mix compile
```

Expected: no errors.

---

## Task 3: Canvases Context

**Files:**
- Create: `lib/eye_in_the_sky_web/canvases.ex`
- Test: `test/eye_in_the_sky_web/canvases_test.exs`

- [ ] **Step 1: Write failing tests**

```elixir
# test/eye_in_the_sky_web/canvases_test.exs
defmodule EyeInTheSkyWeb.CanvasesTest do
  use EyeInTheSkyWeb.DataCase, async: true

  alias EyeInTheSkyWeb.Canvases

  defp uniq, do: System.unique_integer([:positive])

  defp create_session do
    {:ok, agent} = EyeInTheSkyWeb.Agents.create_agent(%{
      name: "canvas-test-#{uniq()}",
      status: "active"
    })
    {:ok, session} = EyeInTheSkyWeb.Sessions.create_session(%{
      name: "canvas-session-#{uniq()}",
      agent_id: agent.id,
      status: "stopped"
    })
    session
  end

  test "create_canvas/1 creates a canvas with a name" do
    assert {:ok, canvas} = Canvases.create_canvas(%{name: "My Canvas"})
    assert canvas.name == "My Canvas"
  end

  test "create_canvas/1 rejects blank name" do
    assert {:error, changeset} = Canvases.create_canvas(%{name: ""})
    assert %{name: [_ | _]} = errors_on(changeset)
  end

  test "list_canvases/0 returns all canvases" do
    {:ok, c1} = Canvases.create_canvas(%{name: "A-#{uniq()}"})
    {:ok, c2} = Canvases.create_canvas(%{name: "B-#{uniq()}"})
    ids = Canvases.list_canvases() |> Enum.map(& &1.id)
    assert c1.id in ids
    assert c2.id in ids
  end

  test "add_session/2 creates a canvas_session record" do
    {:ok, canvas} = Canvases.create_canvas(%{name: "C-#{uniq()}"})
    session = create_session()
    assert {:ok, cs} = Canvases.add_session(canvas.id, session.id)
    assert cs.canvas_id == canvas.id
    assert cs.session_id == session.id
    assert cs.width == 320
  end

  test "add_session/2 is idempotent — calling twice returns ok both times" do
    {:ok, canvas} = Canvases.create_canvas(%{name: "D-#{uniq()}"})
    session = create_session()
    assert {:ok, cs1} = Canvases.add_session(canvas.id, session.id)
    assert {:ok, cs2} = Canvases.add_session(canvas.id, session.id)
    # Both calls return a struct with a real id (not nil)
    assert cs1.id != nil
    assert cs2.id != nil
  end

  test "list_canvas_sessions/1 returns sessions for a canvas" do
    {:ok, canvas} = Canvases.create_canvas(%{name: "E-#{uniq()}"})
    s1 = create_session()
    s2 = create_session()
    Canvases.add_session(canvas.id, s1.id)
    Canvases.add_session(canvas.id, s2.id)
    session_ids = Canvases.list_canvas_sessions(canvas.id) |> Enum.map(& &1.session_id)
    assert s1.id in session_ids
    assert s2.id in session_ids
  end

  test "update_window_layout/2 persists position and size" do
    {:ok, canvas} = Canvases.create_canvas(%{name: "F-#{uniq()}"})
    session = create_session()
    {:ok, cs} = Canvases.add_session(canvas.id, session.id)
    assert {:ok, updated} = Canvases.update_window_layout(cs.id, %{pos_x: 100, pos_y: 200, width: 400, height: 300})
    assert updated.pos_x == 100
    assert updated.width == 400
  end

  test "remove_session/2 deletes the canvas_session record" do
    {:ok, canvas} = Canvases.create_canvas(%{name: "G-#{uniq()}"})
    session = create_session()
    {:ok, _} = Canvases.add_session(canvas.id, session.id)
    assert :ok = Canvases.remove_session(canvas.id, session.id)
    assert Canvases.list_canvas_sessions(canvas.id) == []
  end
end
```

- [ ] **Step 2: Run tests — confirm they fail**

```bash
mix test test/eye_in_the_sky_web/canvases_test.exs
```

Expected: compile error — `EyeInTheSkyWeb.Canvases` not defined.

- [ ] **Step 3: Write the context**

Key: `add_session/2` uses `on_conflict: {:replace, [:updated_at]}` — `on_conflict: :nothing` with `returning: true` returns `{:ok, %CanvasSession{id: nil}}` on conflict, which breaks subsequent `update_window_layout` calls.

```elixir
# lib/eye_in_the_sky_web/canvases.ex
defmodule EyeInTheSkyWeb.Canvases do
  import Ecto.Query

  alias EyeInTheSkyWeb.Repo
  alias EyeInTheSkyWeb.Canvases.{Canvas, CanvasSession}

  def list_canvases do
    Repo.all(from c in Canvas, order_by: [asc: c.inserted_at])
  end

  def get_canvas!(id), do: Repo.get!(Canvas, id)

  def create_canvas(attrs) do
    %Canvas{}
    |> Canvas.changeset(attrs)
    |> Repo.insert()
  end

  def delete_canvas(id) do
    case Repo.get(Canvas, id) do
      nil -> {:error, :not_found}
      canvas -> Repo.delete(canvas)
    end
  end

  def list_canvas_sessions(canvas_id) do
    Repo.all(
      from cs in CanvasSession,
        where: cs.canvas_id == ^canvas_id,
        order_by: [asc: cs.inserted_at]
    )
  end

  # on_conflict: {:replace, [:updated_at]} ensures the returned struct always
  # has a real id (not nil), even when the row already exists.
  def add_session(canvas_id, session_id) do
    %CanvasSession{}
    |> CanvasSession.changeset(%{canvas_id: canvas_id, session_id: session_id})
    |> Repo.insert(
      on_conflict: {:replace, [:updated_at]},
      conflict_target: [:canvas_id, :session_id],
      returning: true
    )
  end

  def remove_session(canvas_id, session_id) do
    from(cs in CanvasSession,
      where: cs.canvas_id == ^canvas_id and cs.session_id == ^session_id
    )
    |> Repo.delete_all()

    :ok
  end

  def update_window_layout(canvas_session_id, attrs) do
    case Repo.get(CanvasSession, canvas_session_id) do
      nil -> {:error, :not_found}
      cs -> cs |> CanvasSession.changeset(attrs) |> Repo.update()
    end
  end
end
```

- [ ] **Step 4: Run tests — confirm they pass**

```bash
mix test test/eye_in_the_sky_web/canvases_test.exs
```

Expected: 8 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add priv/repo/migrations/ lib/eye_in_the_sky_web/canvases* test/eye_in_the_sky_web/canvases_test.exs
git commit -m "feat: add canvases context, schemas, migrations, and tests"
```

---

## Task 4: Add Events Unsubscribe Helpers

**Files:**
- Modify: `lib/eye_in_the_sky_web/events.ex`

`CanvasOverlayComponent` needs to unsubscribe from session topics when tabs switch or the overlay closes. CLAUDE.md prohibits calling `Phoenix.PubSub` directly — all PubSub calls go through the `Events` module. Add the missing helpers.

- [ ] **Step 1: Read the current Events module**

```bash
# Identify where subscribe_session/1 and subscribe_session_status/1 are defined
grep -n "def subscribe_session" lib/eye_in_the_sky_web/events.ex
```

- [ ] **Step 2: Add unsubscribe helpers next to the subscribe functions**

Directly after `subscribe_session/1` and `subscribe_session_status/1`, add:

```elixir
def unsubscribe_session(session_id) do
  Phoenix.PubSub.unsubscribe(EyeInTheSkyWeb.PubSub, "session:#{session_id}")
end

def unsubscribe_session_status(session_id) do
  Phoenix.PubSub.unsubscribe(EyeInTheSkyWeb.PubSub, "session:#{session_id}:status")
end
```

- [ ] **Step 3: Compile**

```bash
mix compile
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/eye_in_the_sky_web/events.ex
git commit -m "feat: add unsubscribe_session and unsubscribe_session_status helpers to Events"
```

---

## Task 5: JS Hook — ChatWindowHook (drag + resize, single hook)

**Files:**
- Create: `assets/js/hooks/chat_window_hook.js`
- Modify: `assets/js/app.js`

**Important:** A Phoenix LiveView element can only have one `phx-hook` attribute. Two hooks on the same element silently drops the first. Drag and resize must live in a single `ChatWindowHook`.

- [ ] **Step 1: Write ChatWindowHook**

```js
// assets/js/hooks/chat_window_hook.js
export const ChatWindowHook = {
  mounted() {
    // --- Drag ---
    const handle = this.el.querySelector("[data-drag-handle]")
    if (handle) {
      let startX, startY, startLeft, startTop
      let dragPersistTimer = null

      const onMouseMove = (e) => {
        const dx = e.clientX - startX
        const dy = e.clientY - startY
        this.el.style.left = `${startLeft + dx}px`
        this.el.style.top = `${startTop + dy}px`
      }

      const onMouseUp = () => {
        document.removeEventListener("mousemove", onMouseMove)
        document.removeEventListener("mouseup", onMouseUp)
        clearTimeout(dragPersistTimer)
        dragPersistTimer = setTimeout(() => {
          this.pushEvent("window_moved", {
            id: this.el.dataset.csId,
            x: parseInt(this.el.style.left, 10) || 0,
            y: parseInt(this.el.style.top, 10) || 0
          })
        }, 300)
      }

      handle.addEventListener("mousedown", (e) => {
        e.preventDefault()
        startX = e.clientX
        startY = e.clientY
        startLeft = parseInt(this.el.style.left, 10) || 0
        startTop = parseInt(this.el.style.top, 10) || 0

        document.querySelectorAll("[data-chat-window]").forEach(w => { w.style.zIndex = "1" })
        this.el.style.zIndex = "10"

        document.addEventListener("mousemove", onMouseMove)
        document.addEventListener("mouseup", onMouseUp)
      })
    }

    // --- Resize ---
    let resizePersistTimer = null
    const observer = new ResizeObserver(() => {
      clearTimeout(resizePersistTimer)
      resizePersistTimer = setTimeout(() => {
        this.pushEvent("window_resized", {
          id: this.el.dataset.csId,
          w: this.el.offsetWidth,
          h: this.el.offsetHeight
        })
      }, 400)
    })
    observer.observe(this.el)
    this._resizeObserver = observer
  },

  destroyed() {
    if (this._resizeObserver) this._resizeObserver.disconnect()
  }
}
```

- [ ] **Step 2: Register hook in app.js**

Add to the import block (alongside other hook imports):

```js
import {ChatWindowHook} from "./hooks/chat_window_hook"
```

Add to the Hooks assignment block:

```js
Hooks.ChatWindowHook = ChatWindowHook
```

- [ ] **Step 3: Compile**

```bash
mix compile
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add assets/js/hooks/chat_window_hook.js assets/js/app.js
git commit -m "feat: add ChatWindowHook (drag + resize in single hook)"
```

---

## Task 6: ChatWindowComponent

**Files:**
- Create: `lib/eye_in_the_sky_web_web/components/chat_window_component.ex`

Renders one floating window for a single session. Parent passes a `canvas_session` struct. The component loads messages on mount and handles send/remove events.

Note: `phx-hook="ChatWindowHook"` appears **once** on the container div — drag and resize share the same hook.

- [ ] **Step 1: Write the component**

```elixir
# lib/eye_in_the_sky_web_web/components/chat_window_component.ex
defmodule EyeInTheSkyWebWeb.Components.ChatWindowComponent do
  use EyeInTheSkyWebWeb, :live_component

  alias EyeInTheSkyWeb.{Messages, Sessions}
  alias EyeInTheSkyWeb.Agents.AgentManager

  @impl true
  def update(%{canvas_session: cs} = assigns, socket) do
    # Sessions.get_session/1 returns {:ok, session} | {:error, :not_found} — unwrap it
    session = case Sessions.get_session(cs.session_id) do
      {:ok, s} -> s
      {:error, _} -> nil
    end
    messages = if session, do: Messages.list_recent_messages(cs.session_id, 50), else: []

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:session, session)
     |> assign(:messages, messages)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={"chat-window-#{@canvas_session.id}"}
      data-chat-window
      data-cs-id={@canvas_session.id}
      phx-hook="ChatWindowHook"
      style={"position: absolute; left: #{@canvas_session.pos_x}px; top: #{@canvas_session.pos_y}px; width: #{@canvas_session.width}px; height: #{@canvas_session.height}px; resize: both; overflow: auto; z-index: 1;"}
      class="bg-base-100 rounded-xl shadow-2xl border border-base-300 flex flex-col"
    >
      <div
        data-drag-handle
        class="flex items-center justify-between px-3 py-2 bg-base-200 border-b border-base-300 rounded-t-xl cursor-move select-none shrink-0"
      >
        <div class="flex items-center gap-2 min-w-0">
          <span class={["w-2 h-2 rounded-full inline-block shrink-0", status_dot_class(@session)]}></span>
          <span class="text-xs font-medium truncate"><%= session_label(@session) %></span>
        </div>
        <button
          class="w-3 h-3 rounded-full bg-error/70 hover:bg-error transition-colors shrink-0"
          phx-click="remove_window"
          phx-value-cs-id={@canvas_session.id}
          phx-target={@myself}
          title="Remove from canvas"
        ></button>
      </div>

      <div class="flex-1 overflow-y-auto p-2 space-y-1.5 text-xs min-h-0">
        <%= for msg <- @messages do %>
          <div class={if msg.sender_role == "user", do: "chat chat-end", else: "chat chat-start"}>
            <div class={["chat-bubble text-xs py-1 px-2", if(msg.sender_role == "user", do: "chat-bubble-primary", else: "bg-base-200")]}>
              <%= msg.body %>
            </div>
          </div>
        <% end %>
      </div>

      <div class="shrink-0 border-t border-base-300">
        <.form for={%{}} phx-submit="send_message" phx-target={@myself} class="flex gap-1 p-1.5">
          <input
            type="text"
            name="body"
            class="input input-xs flex-1 bg-base-200 text-xs"
            placeholder="Message..."
            autocomplete="off"
          />
          <button type="submit" class="btn btn-primary btn-xs px-2">↑</button>
        </.form>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("send_message", %{"body" => ""}, socket), do: {:noreply, socket}

  def handle_event("send_message", %{"body" => body}, socket) do
    session_id = socket.assigns.canvas_session.session_id
    provider = (socket.assigns.session && socket.assigns.session.provider) || "claude"

    case Messages.send_message(%{
      session_id: session_id,
      sender_role: "user",
      recipient_role: "agent",
      provider: provider,
      body: body
    }) do
      {:ok, _} ->
        AgentManager.continue_session(session_id, body, [])
        {:noreply, socket}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("remove_window", %{"cs-id" => cs_id}, socket) do
    send_update(EyeInTheSkyWebWeb.Components.CanvasOverlayComponent,
      id: "canvas-overlay",
      action: :remove_window,
      canvas_session_id: String.to_integer(cs_id)
    )
    {:noreply, socket}
  end

  defp status_dot_class(nil), do: "bg-base-content/20"
  defp status_dot_class(%{status: "working"}), do: "bg-success"
  defp status_dot_class(%{status: "waiting"}), do: "bg-warning"
  defp status_dot_class(_), do: "bg-base-content/30"

  defp session_label(nil), do: "Unknown session"
  defp session_label(%{name: name}) when is_binary(name) and name != "", do: name
  defp session_label(%{uuid: uuid}), do: String.slice(uuid, 0, 8)
end
```

- [ ] **Step 2: Compile**

```bash
mix compile
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/eye_in_the_sky_web_web/components/chat_window_component.ex
git commit -m "feat: add ChatWindowComponent"
```

---

## Task 7: CanvasOverlayComponent

**Files:**
- Create: `lib/eye_in_the_sky_web_web/components/canvas_overlay_component.ex`

The main overlay LiveComponent. Owns open/closed state, active canvas tab, PubSub subscriptions, and renders `ChatWindowComponent` children.

Key fixes in this task vs naive implementation:
- `window_moved`/`window_resized`: `cs_id` arrives from JS as a string — must call `String.to_integer/1`
- `unsubscribe_session/1` private helper uses `Events.unsubscribe_session/1` (not direct PubSub calls)

- [ ] **Step 1: Write the component**

```elixir
# lib/eye_in_the_sky_web_web/components/canvas_overlay_component.ex
defmodule EyeInTheSkyWebWeb.Components.CanvasOverlayComponent do
  use EyeInTheSkyWebWeb, :live_component

  alias EyeInTheSkyWeb.{Canvases, Events}
  alias EyeInTheSkyWebWeb.Components.ChatWindowComponent

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:open, false)
     |> assign(:canvases, [])
     |> assign(:active_canvas_id, nil)
     |> assign(:canvas_sessions, [])
     |> assign(:subscribed_session_ids, [])
     |> assign(:creating_canvas, false)}
  end

  @impl true
  def update(%{action: :toggle}, socket), do: {:ok, toggle_open(socket)}

  def update(%{action: :open_canvas, canvas_id: canvas_id}, socket) do
    {:ok,
     socket
     |> assign(:open, true)
     |> load_canvases()
     |> activate_canvas(canvas_id)}
  end

  def update(%{action: :remove_window, canvas_session_id: cs_id}, socket) do
    cs = Enum.find(socket.assigns.canvas_sessions, &(&1.id == cs_id))

    if cs do
      Canvases.remove_session(socket.assigns.active_canvas_id, cs.session_id)
      unsubscribe_session(cs.session_id)

      {:ok,
       socket
       |> assign(:canvas_sessions, Enum.reject(socket.assigns.canvas_sessions, &(&1.id == cs_id)))
       |> assign(:subscribed_session_ids, Enum.reject(socket.assigns.subscribed_session_ids, &(&1 == cs.session_id)))}
    else
      {:ok, socket}
    end
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:canvases, fn -> Canvases.list_canvases() end)}
  end

  @impl true
  def handle_info({:new_dm, message}, socket) do
    {:noreply, refresh_window(socket, message.session_id)}
  end

  def handle_info({:claude_response, _ref, parsed}, socket) do
    session_id = parsed[:session_id] || parsed["session_id"]
    {:noreply, if(session_id, do: refresh_window(socket, session_id), else: socket)}
  end

  def handle_info({:session_status, session_id, _status}, socket) do
    cs = Enum.find(socket.assigns.canvas_sessions, &(&1.session_id == session_id))
    if cs, do: send_update(ChatWindowComponent, id: "chat-window-#{cs.id}", canvas_session: cs)
    {:noreply, socket}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def handle_event("toggle", _params, socket), do: {:noreply, toggle_open(socket)}

  def handle_event("open", %{"canvas-id" => id_str}, socket) do
    canvas_id = String.to_integer(id_str)
    {:noreply, socket |> assign(:open, true) |> load_canvases() |> activate_canvas(canvas_id)}
  end

  def handle_event("switch_tab", %{"canvas-id" => id_str}, socket) do
    {:noreply, activate_canvas(socket, String.to_integer(id_str))}
  end

  def handle_event("start_new_canvas", _params, socket) do
    {:noreply, assign(socket, :creating_canvas, true)}
  end

  def handle_event("create_canvas", %{"name" => name}, socket) when name != "" do
    case Canvases.create_canvas(%{name: name}) do
      {:ok, canvas} ->
        {:noreply,
         socket
         |> assign(:canvases, socket.assigns.canvases ++ [canvas])
         |> assign(:creating_canvas, false)
         |> activate_canvas(canvas.id)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("create_canvas", _params, socket) do
    {:noreply, assign(socket, :creating_canvas, false)}
  end

  # cs_id arrives from JS as a string — must convert to integer for Canvases.update_window_layout/2
  def handle_event("window_moved", %{"id" => cs_id, "x" => x, "y" => y}, socket) do
    Canvases.update_window_layout(String.to_integer(cs_id), %{pos_x: x, pos_y: y})
    {:noreply, socket}
  end

  def handle_event("window_resized", %{"id" => cs_id, "w" => w, "h" => h}, socket) do
    Canvases.update_window_layout(String.to_integer(cs_id), %{width: w, height: h})
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%= if @open do %>
      <div style="position: fixed; inset: 0; z-index: 60;" class="bg-base-100/80 backdrop-blur-md flex flex-col">
        <div class="flex items-center justify-between px-4 py-2 border-b border-base-300 bg-base-200/70 shrink-0">
          <div class="flex items-center gap-3">
            <span class="text-secondary font-semibold text-sm">⬡ Canvas</span>
            <div class="tabs tabs-boxed tabs-xs bg-base-300">
              <%= for canvas <- @canvases do %>
                <a
                  class={["tab tab-xs", if(@active_canvas_id == canvas.id, do: "tab-active")]}
                  phx-click="switch_tab"
                  phx-value-canvas-id={canvas.id}
                  phx-target={@myself}
                >
                  <%= canvas.name %>
                </a>
              <% end %>
              <%= if @creating_canvas do %>
                <form phx-submit="create_canvas" phx-target={@myself} class="flex gap-1 ml-1">
                  <input type="text" name="name" class="input input-xs w-28" placeholder="Canvas name" autofocus />
                  <button type="submit" class="btn btn-primary btn-xs">+</button>
                </form>
              <% else %>
                <a
                  class="tab tab-xs text-base-content/40"
                  phx-click="start_new_canvas"
                  phx-target={@myself}
                >+ New</a>
              <% end %>
            </div>
          </div>
          <button class="btn btn-ghost btn-xs" phx-click="toggle" phx-target={@myself}>✕ Close</button>
        </div>

        <div class="relative flex-1 overflow-hidden">
          <%= for cs <- @canvas_sessions do %>
            <.live_component
              module={ChatWindowComponent}
              id={"chat-window-#{cs.id}"}
              canvas_session={cs}
            />
          <% end %>
          <%= if @canvas_sessions == [] and @active_canvas_id != nil do %>
            <div class="flex items-center justify-center h-full text-base-content/30 text-sm select-none">
              No sessions — use "Add to Canvas" on a session card.
            </div>
          <% end %>
        </div>
      </div>
    <% end %>
    """
  end

  # --- Helpers ---

  defp toggle_open(socket) do
    if socket.assigns.open do
      unsubscribe_all(socket.assigns.subscribed_session_ids)
      socket |> assign(:open, false) |> assign(:subscribed_session_ids, [])
    else
      socket = socket |> load_canvases() |> assign(:open, true)
      case socket.assigns.canvases do
        [first | _] -> activate_canvas(socket, first.id)
        [] -> socket
      end
    end
  end

  defp load_canvases(socket), do: assign(socket, :canvases, Canvases.list_canvases())

  defp activate_canvas(socket, canvas_id) do
    unsubscribe_all(socket.assigns.subscribed_session_ids)
    sessions = Canvases.list_canvas_sessions(canvas_id)
    session_ids = Enum.map(sessions, & &1.session_id)
    subscribe_all(session_ids)

    sessions =
      sessions
      |> Enum.with_index()
      |> Enum.map(fn {cs, i} ->
        if cs.pos_x == 0 and cs.pos_y == 0,
          do: %{cs | pos_x: 24 + i * 32, pos_y: 16 + i * 32},
          else: cs
      end)

    socket
    |> assign(:active_canvas_id, canvas_id)
    |> assign(:canvas_sessions, sessions)
    |> assign(:subscribed_session_ids, session_ids)
  end

  defp subscribe_all(ids) do
    Enum.each(ids, fn id ->
      Events.subscribe_session(id)
      Events.subscribe_session_status(id)
    end)
  end

  defp unsubscribe_all(ids), do: Enum.each(ids, &unsubscribe_session/1)

  # Uses Events module helpers — never calls Phoenix.PubSub directly (CLAUDE.md rule)
  defp unsubscribe_session(id) do
    Events.unsubscribe_session(id)
    Events.unsubscribe_session_status(id)
  end

  defp refresh_window(socket, session_id) do
    cs = Enum.find(socket.assigns.canvas_sessions, &(&1.session_id == session_id))
    if cs, do: send_update(ChatWindowComponent, id: "chat-window-#{cs.id}", canvas_session: cs)
    socket
  end
end
```

- [ ] **Step 2: Compile**

```bash
mix compile
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/eye_in_the_sky_web_web/components/canvas_overlay_component.ex
git commit -m "feat: add CanvasOverlayComponent"
```

---

## Task 8: Mount Overlay in App Layout

**Files:**
- Modify: `lib/eye_in_the_sky_web_web/components/layouts/app.html.heex`

- [ ] **Step 1: Add mount after the Sidebar live_component (around line 15)**

```heex
  <.live_component
    module={EyeInTheSkyWebWeb.Components.CanvasOverlayComponent}
    id="canvas-overlay"
  />
```

- [ ] **Step 2: Compile and start server**

```bash
mix compile && mix phx.server
```

Open `http://localhost:5000`. No errors in terminal. Overlay is hidden.

- [ ] **Step 3: Commit**

```bash
git add lib/eye_in_the_sky_web_web/components/layouts/app.html.heex
git commit -m "feat: mount CanvasOverlayComponent in app layout"
```

---

## Task 9: Sidebar — Canvas Section

**Files:**
- Modify: `lib/eye_in_the_sky_web_web/components/sidebar.ex`

**Note on stale canvas list:** The sidebar loads canvases once at mount. It will not reflect canvases created via the "Add to Canvas → New canvas" flow on session cards unless the page reloads. This is a known limitation. The overlay itself always calls `load_canvases()` on open, so the overlay tab list is always fresh.

- [ ] **Step 1: Add alias and canvases to mount assigns**

In `mount/1`, add `canvases: EyeInTheSkyWeb.Canvases.list_canvases()` to the assign block.

Add at the top of the module: `alias EyeInTheSkyWeb.Canvases`

- [ ] **Step 2: Add Canvas section in the render template**

Find the nav section in `sidebar.ex` (look for existing nav links like Sessions, Tasks, Chat). After the last nav entry, add:

```heex
<%!-- Canvas section --%>
<div class="pt-4 pb-1 px-3">
  <span class="text-[10px] uppercase tracking-widest text-base-content/30 font-semibold">Canvas</span>
</div>

<button
  class="flex w-full items-center gap-2 px-3 py-2 rounded bg-secondary/15 border border-secondary/30 text-secondary hover:bg-secondary/25 transition-colors text-sm"
  phx-click="toggle"
  phx-target="#canvas-overlay"
>
  <span>⬡</span>
  <span class="font-medium">Open Canvas</span>
</button>

<div class="pl-2 space-y-0.5 mt-0.5">
  <%= for canvas <- @canvases do %>
    <button
      class="flex w-full items-center gap-2 px-3 py-1.5 rounded hover:bg-base-300 text-base-content/60 text-xs"
      phx-click="open"
      phx-value-canvas-id={canvas.id}
      phx-target="#canvas-overlay"
    >
      <span class="w-1.5 h-1.5 rounded-full bg-base-content/20 inline-block shrink-0"></span>
      <span class="truncate"><%= canvas.name %></span>
    </button>
  <% end %>
</div>
```

- [ ] **Step 3: Verify in browser**

Sidebar shows Canvas section. "Open Canvas" button opens the overlay. "✕ Close" closes it.

- [ ] **Step 4: Commit**

```bash
git add lib/eye_in_the_sky_web_web/components/sidebar.ex
git commit -m "feat: add Canvas section to sidebar"
```

---

## Task 10: "Add to Canvas" on Session Cards

**Files:**
- Modify: `lib/eye_in_the_sky_web_web/components/session_card.ex`
- Modify: `lib/eye_in_the_sky_web_web/live/agent_live/index.ex`
- Modify: `lib/eye_in_the_sky_web_web/live/project_live/sessions.ex`

**Coverage note:** The `add_to_canvas` and `add_to_new_canvas` events have no `phx-target`, so they bubble to the nearest parent LiveView. Add the handlers to every LiveView that renders `session_row`. Check the codebase for additional callers:

```bash
grep -rn "session_row\|session_card" lib/eye_in_the_sky_web_web/live/
```

Add both handler clauses and the `canvases` mount assign to every LiveView that shows up.

- [ ] **Step 1: Add canvases attr to session_row and render the dropdown**

In `session_card.ex`, add to the `attr` declarations at the top of `session_row`:

```elixir
attr :canvases, :list, default: []
```

**Important — click propagation:** The `session_row` root div has `phx-click={@click_event}` which navigates to the session DM page. Placing the dropdown inside the component body (outside the slot) means any click on it will also fire navigation. The `:actions` slot wrapper at line 189 has `phx-click="noop"` which stops propagation — put the dropdown there.

Do NOT add the dropdown to `session_row`'s function body. Instead, pass it via the `:actions` slot in each calling LiveView (see Steps 2-4 below).

In the render template of each LiveView, where `session_row` is called, add a `:actions` slot with the dropdown:

```heex
<.session_row session={session} canvases={@canvases} ...>
  <:actions>
    <div class="dropdown dropdown-top" id={"canvas-dropdown-#{session.id}"}>
      <button tabindex="0" class="btn btn-secondary btn-xs gap-1">⬡ Add to Canvas</button>
      <ul tabindex="0" class="dropdown-content menu bg-base-100 rounded-box z-10 w-48 p-1 shadow-xl border border-base-300 text-xs">
        <li class="menu-title text-[10px]">Select canvas</li>
        <%= for canvas <- @canvases do %>
          <li>
            <a phx-click="add_to_canvas" phx-value-canvas-id={canvas.id} phx-value-session-id={session.id}>
              ⬡ <%= canvas.name %>
            </a>
          </li>
        <% end %>
        <li><hr class="border-base-content/10 my-1" /></li>
        <%# "New canvas" row — JS toggles between the label and the inline form %>
        <li id={"new-canvas-label-#{session.id}"}>
          <a
            class="text-secondary"
            onclick={"document.getElementById('new-canvas-label-#{session.id}').style.display='none'; document.getElementById('new-canvas-form-#{session.id}').style.display='block';"}
          >
            + New canvas
          </a>
        </li>
        <li id={"new-canvas-form-#{session.id}"} style="display:none">
          <form phx-submit="add_to_new_canvas" class="flex flex-col gap-1 p-1">
            <input type="hidden" name="session_id" value={session.id} />
            <input
              type="text"
              name="canvas_name"
              class="input input-xs w-full"
              placeholder="Canvas name..."
              autocomplete="off"
            />
            <button type="submit" class="btn btn-primary btn-xs w-full">Create &amp; Add</button>
          </form>
        </li>
      </ul>
    </div>
  </:actions>
</.session_row>
```

Since the dropdown is in the slot (not in `session_card.ex`'s body), no changes to `session_card.ex` are needed for the dropdown itself — only the `attr :canvases` declaration.

- [ ] **Step 2: Handle add_to_canvas and add_to_new_canvas in AgentLive.Index**

Add alias `alias EyeInTheSkyWeb.Canvases` and the following handler clauses to `agent_live/index.ex`:

```elixir
def handle_event("add_to_canvas", %{"canvas-id" => cid, "session-id" => sid}, socket) do
  canvas_id = String.to_integer(cid)
  session_id = String.to_integer(sid)
  canvas = Canvases.get_canvas!(canvas_id)
  Canvases.add_session(canvas_id, session_id)
  send_update(EyeInTheSkyWebWeb.Components.CanvasOverlayComponent,
    id: "canvas-overlay", action: :open_canvas, canvas_id: canvas_id)
  {:noreply, put_flash(socket, :info, "Added to #{canvas.name}")}
end

def handle_event("add_to_new_canvas", %{"session_id" => sid, "canvas_name" => name}, socket) do
  session_id = String.to_integer(sid)
  canvas_name = if name && String.trim(name) != "", do: String.trim(name), else: "Canvas #{:os.system_time(:second)}"
  {:ok, canvas} = Canvases.create_canvas(%{name: canvas_name})
  Canvases.add_session(canvas.id, session_id)
  send_update(EyeInTheSkyWebWeb.Components.CanvasOverlayComponent,
    id: "canvas-overlay", action: :open_canvas, canvas_id: canvas.id)
  {:noreply, put_flash(socket, :info, "Added to #{canvas.name}")}
end
```

- [ ] **Step 3: Load canvases in AgentLive.Index mount and pass to session_row**

In `mount/2`, add `canvases: Canvases.list_canvases()` to the socket assigns.

In the template where `session_row` is called, add `canvases={@canvases}`.

- [ ] **Step 4: Repeat steps 2-3 for ProjectLive.Sessions**

Same two `handle_event` clauses and same mount assign in `project_live/sessions.ex`.

- [ ] **Step 5: Add handlers to ALL session_row callers**

Known callers that need both `add_to_canvas` and `add_to_new_canvas` handlers plus `canvases` mount assign:

1. `lib/eye_in_the_sky_web_web/live/agent_live/index.ex` (Step 2-3 above)
2. `lib/eye_in_the_sky_web_web/live/project_live/sessions.ex` (Step 4 above)
3. `lib/eye_in_the_sky_web_web/live/session_live/index.ex` — add same two handlers + `canvases: Canvases.list_canvases()` in mount
4. `lib/eye_in_the_sky_web_web/live/team_live/index.ex` — add same two handlers + `canvases: Canvases.list_canvases()` in mount

Verify no callers were missed:

```bash
grep -rn "session_row" lib/eye_in_the_sky_web_web/live/
```

For any LiveView not in the list above, add the same two handlers and mount assign.

- [ ] **Step 6: Compile**

```bash
mix compile
```

Expected: no errors.

- [ ] **Step 7: End-to-end smoke test**

1. Open `http://localhost:5000`
2. Click "Add to Canvas" on a session card → dropdown shows canvas list and "+ New canvas"
3. Click an existing canvas → overlay opens on that tab with the session window visible
4. Click "Add to Canvas" → "+ New canvas" → type a name → submit → overlay opens with a new tab
5. Type a message in a chat window and send → message appears in the window
6. Drag the window to a new position → reload the page → window returns to the saved position
7. Resize the window → reload → window keeps the new size

- [ ] **Step 8: Commit**

```bash
git add lib/eye_in_the_sky_web_web/components/session_card.ex \
        lib/eye_in_the_sky_web_web/live/agent_live/index.ex \
        lib/eye_in_the_sky_web_web/live/project_live/sessions.ex \
        lib/eye_in_the_sky_web_web/live/session_live/index.ex \
        lib/eye_in_the_sky_web_web/live/team_live/index.ex
git commit -m "feat: add Add to Canvas dropdown on session cards"
```

---

## Task 11: Final Verification

- [ ] **Run full test suite**

```bash
mix test
```

Expected: all tests pass.

- [ ] **Run clean compile**

```bash
mix compile --warnings-as-errors
```

Expected: no errors, no warnings.

- [ ] **Manual checklist**

- [ ] Overlay opens/closes from sidebar on Sessions, Tasks, Chat, and Project pages
- [ ] Switching canvas tabs loads the correct session windows and re-subscribes PubSub
- [ ] Drag persists position after page reload
- [ ] Resize persists dimensions after page reload
- [ ] Sending a message from a chat window triggers a Claude response (verify in the session's DM page)
- [ ] Adding the same session to a canvas twice does not duplicate the window
- [ ] Removing a window (red dot) removes it from the surface
- [ ] Creating a new canvas from the session card dropdown opens the overlay on the new tab

- [ ] **Final commit**

```bash
git add -A
git commit -m "feat: canvas overlay — complete"
```
