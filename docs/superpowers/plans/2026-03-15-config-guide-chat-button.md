# Config Guide Chat Button Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Config Guide" button to the `/config` page that opens an inline FAB-style chat window backed by a `--agent claude-config-guide` Claude CLI session.

**Architecture:** A new `ConfigChatGuide` JS hook manages the full chat lifecycle independently — it spawns an agent via REST, manages its own modal, and communicates with the existing FabHook via a dedicated `config_guide_*` event namespace. FabHook is extended to handle these events and route PubSub messages by session ID.

**Tech Stack:** Elixir/Phoenix LiveView, JavaScript (vanilla), Tailwind CSS, PubSub (`EyeInTheSkyWeb.PubSub`), REST API (`POST /api/v1/agents`)

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `lib/eye_in_the_sky_web_web/live/fab_hook.ex` | Modify | Add config guide event handlers + message routing |
| `assets/js/hooks/config_chat_guide.js` | Create | New JS hook: spawn, modal, chat lifecycle |
| `assets/js/app.js` | Modify | Register `ConfigChatGuide` hook |
| `lib/eye_in_the_sky_web_web/live/overview_live/config.ex` | Modify | Add button to toolbar |
| `test/eye_in_the_sky_web_web/live/config_guide_chat_test.exs` | Create | LiveView tests for FabHook config guide handlers |

---

## Chunk 1: FabHook backend — config guide event handlers

### Task 1: Add `:config_guide_active_session_id` assign to FabHook

**Files:**
- Modify: `lib/eye_in_the_sky_web_web/live/fab_hook.ex:17-31`

- [ ] **Step 1: Add the new assign in `on_mount`**

In `on_mount/4`, add `:config_guide_active_session_id` beside `:fab_active_session_id`:

```elixir
socket =
  socket
  |> assign(:fab_mounted, true)
  |> assign(:fab_timer, nil)
  |> assign(:fab_active_session_id, nil)
  |> assign(:config_guide_active_session_id, nil)
  |> attach_hook(:fab_events, :handle_event, &handle_fab_event/3)
  |> attach_hook(:fab_info, :handle_info, &handle_fab_info/2)
```

- [ ] **Step 2: Compile to verify no errors**

```bash
mix compile
```
Expected: no errors, only warnings acceptable.

---

### Task 2: Add `config_guide_open_chat` handler

**Files:**
- Modify: `lib/eye_in_the_sky_web_web/live/fab_hook.ex`

- [ ] **Step 1: Add the handler after `fab_open_chat`**

Insert this function after the existing `handle_fab_event("fab_open_chat", ...)` clause:

```elixir
defp handle_fab_event("config_guide_open_chat", %{"session_id" => session_id}, socket) do
  socket =
    case resolve_session(session_id) do
      {:ok, session} ->
        # Unsubscribe from any previous config guide session first
        socket = unsubscribe_config_guide_session(socket)
        Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "session:#{session.id}")
        socket = assign(socket, :config_guide_active_session_id, session.id)

        messages =
          Messages.list_recent_messages(session.id, 20)
          |> Enum.map(&%{
            id: &1.id,
            session_id: &1.session_id,
            body: &1.body,
            sender_role: &1.sender_role,
            inserted_at: to_string(&1.inserted_at)
          })

        push_event(socket, "config_guide_history", %{messages: messages})

      {:error, reason} ->
        Logger.error("ConfigGuide open_chat error: #{inspect(reason)}")
        push_event(socket, "config_guide_error", %{error: "Failed to open session"})
    end

  {:halt, socket}
end
```

- [ ] **Step 2: Add `config_guide_send_message` handler**

```elixir
defp handle_fab_event(
       "config_guide_send_message",
       %{"session_id" => session_id, "body" => body},
       socket
     ) do
  case send_session_message(session_id, body) do
    {:ok, _session_id_int} ->
      {:halt, socket}

    {:error, reason} ->
      {:halt, push_event(socket, "config_guide_error", %{error: reason})}
  end
end
```

- [ ] **Step 3: Add `config_guide_close_chat` handler**

```elixir
defp handle_fab_event("config_guide_close_chat", _params, socket) do
  {:halt, unsubscribe_config_guide_session(socket)}
end
```

- [ ] **Step 4: Add `unsubscribe_config_guide_session/1` private helper**

Add beside the existing `unsubscribe_active_session/1`:

```elixir
defp unsubscribe_config_guide_session(socket) do
  case socket.assigns.config_guide_active_session_id do
    nil ->
      socket

    id ->
      Phoenix.PubSub.unsubscribe(EyeInTheSkyWeb.PubSub, "session:#{id}")
      assign(socket, :config_guide_active_session_id, nil)
  end
end
```

- [ ] **Step 5: Compile**

```bash
mix compile
```
Expected: clean.

---

### Task 3: Update `handle_fab_info` to route messages by session

**Files:**
- Modify: `lib/eye_in_the_sky_web_web/live/fab_hook.ex:93-99`

The existing clause pushes `fab_chat_message` unconditionally. Replace it with routing logic.

- [ ] **Step 1: Replace the `{:new_message, msg}` clause**

Current code (lines ~93-99):
```elixir
defp handle_fab_info(
       {:new_message, %EyeInTheSkyWeb.Messages.Message{sender_role: role, body: body}},
       socket
     )
     when role != "user" do
  {:halt, push_event(socket, "fab_chat_message", %{body: body, sender_role: role})}
end
```

Replace with:
```elixir
# Shared session message router — routes to FAB chat or Config Guide chat by session_id.
defp handle_fab_info(
       {:new_message,
        %EyeInTheSkyWeb.Messages.Message{
          session_id: session_id,
          sender_role: role,
          body: body
        } = msg},
       socket
     )
     when role != "user" do
  cond do
    session_id == socket.assigns.fab_active_session_id ->
      {:halt, push_event(socket, "fab_chat_message", %{body: body, sender_role: role})}

    session_id == socket.assigns.config_guide_active_session_id ->
      {:halt,
       push_event(socket, "config_guide_message", %{
         id: msg.id,
         session_id: session_id,
         body: body,
         sender_role: role,
         inserted_at: to_string(msg.inserted_at)
       })}

    true ->
      {:cont, socket}
  end
end
```

- [ ] **Step 2: Compile**

```bash
mix compile
```
Expected: clean.

- [ ] **Step 3: Commit Chunk 1**

```bash
git add lib/eye_in_the_sky_web_web/live/fab_hook.ex
git commit -m "feat: add config guide chat handlers to FabHook"
```

---

## Chunk 2: FabHook tests

### Task 4: Write LiveView tests for config guide handlers

**Files:**
- Create: `test/eye_in_the_sky_web_web/live/config_guide_chat_test.exs`

Auth note: `AuthHook.on_mount` is a pass-through that assigns `current_user: nil` — no auth setup needed in tests. `%{conn: conn}` from `ConnCase` works directly.

- [ ] **Step 1: Write the test file**

```elixir
defmodule EyeInTheSkyWebWeb.Live.ConfigGuideChatTest do
  use EyeInTheSkyWebWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.{Agents, Messages, Sessions}

  setup do
    {:ok, agent} =
      Agents.create_agent(%{
        uuid: Ecto.UUID.generate(),
        status: "working"
      })

    {:ok, session} =
      Sessions.create_session(%{
        uuid: Ecto.UUID.generate(),
        agent_id: agent.id,
        name: "Config Guide Test",
        provider: "claude",
        status: "working",
        started_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    %{session: session}
  end

  test "config_guide_open_chat pushes history for valid session", %{conn: conn, session: session} do
    {:ok, view, _html} = live(conn, ~p"/config")

    view |> render_hook("config_guide_open_chat", %{"session_id" => session.uuid})

    assert_push_event(view, "config_guide_history", %{messages: messages})
    assert is_list(messages)
  end

  test "config_guide_open_chat pushes error for unknown session", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/config")

    view |> render_hook("config_guide_open_chat", %{"session_id" => Ecto.UUID.generate()})

    assert_push_event(view, "config_guide_error", %{error: _})
  end

  test "config_guide_close_chat does not crash when no session is active", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/config")
    # Should not raise
    view |> render_hook("config_guide_close_chat", %{})
  end

  test "config_guide_open_chat then close_chat allows re-opening", %{conn: conn, session: session} do
    {:ok, view, _html} = live(conn, ~p"/config")

    view |> render_hook("config_guide_open_chat", %{"session_id" => session.uuid})
    assert_push_event(view, "config_guide_history", %{})

    view |> render_hook("config_guide_close_chat", %{})
    # After close, re-opening should work (assign reset, not stale)
    view |> render_hook("config_guide_open_chat", %{"session_id" => session.uuid})
    assert_push_event(view, "config_guide_history", %{})
  end

  # Test Task 3's routing: incoming PubSub messages are routed to config_guide_message
  # when the message belongs to the active config guide session.
  test "incoming message on config guide session routes to config_guide_message", %{
    conn: conn,
    session: session
  } do
    {:ok, view, _html} = live(conn, ~p"/config")

    # Open the config guide chat — this subscribes the LiveView to "session:<id>"
    view |> render_hook("config_guide_open_chat", %{"session_id" => session.uuid})
    assert_push_event(view, "config_guide_history", %{})

    # Build a fake Message struct matching the pattern the handler expects
    msg = %EyeInTheSkyWeb.Messages.Message{
      id: 999,
      session_id: session.id,
      body: "Hello from agent",
      sender_role: "assistant",
      inserted_at: ~N[2026-03-15 12:00:00]
    }

    # Simulate the PubSub broadcast that the real system would send
    send(view.pid, {:new_message, msg})

    # Should push config_guide_message, NOT fab_chat_message
    assert_push_event(view, "config_guide_message", %{body: "Hello from agent", sender_role: "assistant"})
  end

  test "incoming message on config guide session does NOT emit fab_chat_message", %{
    conn: conn,
    session: session
  } do
    {:ok, view, _html} = live(conn, ~p"/config")

    view |> render_hook("config_guide_open_chat", %{"session_id" => session.uuid})
    assert_push_event(view, "config_guide_history", %{})

    msg = %EyeInTheSkyWeb.Messages.Message{
      id: 1000,
      session_id: session.id,
      body: "Test message",
      sender_role: "assistant",
      inserted_at: ~N[2026-03-15 12:00:00]
    }

    send(view.pid, {:new_message, msg})

    # Use timeout argument — no sleep needed
    refute_push_event(view, "fab_chat_message", %{}, timeout: 100)
  end
end
```

- [ ] **Step 2: Run the tests to verify they pass**

```bash
mix test test/eye_in_the_sky_web_web/live/config_guide_chat_test.exs --trace
```
Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add test/eye_in_the_sky_web_web/live/config_guide_chat_test.exs
git commit -m "test: add config guide chat LiveView tests"
```

---

## Chunk 3: JS hook — ConfigChatGuide

### Task 5: Create `assets/js/hooks/config_chat_guide.js`

**Files:**
- Create: `assets/js/hooks/config_chat_guide.js`

> **SVG note:** CLAUDE.md prohibits inline SVG in HEEx templates and requires `<.icon>`. This JS hook builds DOM directly (not HEEx) so `<.icon>` is unavailable client-side. Inline SVG paths in `_createModal()` are intentional and necessary here. This is an approved exception.

- [ ] **Step 1: Write the hook**

DaisyUI v5 loading pattern: `<span class="loading loading-spinner loading-sm">` inside the button, not a `loading` class on the button itself.

```javascript
const MODAL_ID = 'config-guide-chat-modal'
const OPEN_TIMEOUT_MS = 10_000

export const ConfigChatGuide = {
  mounted() {
    this._isOpening = false
    this._sessionUuid = null
    this._messages = []   // tracks rendered messages for state management
    this._openTimer = null

    this.el.addEventListener('click', () => this._handleClick())

    this.handleEvent('config_guide_history', ({ messages }) => {
      clearTimeout(this._openTimer)
      this._openTimer = null
      this._isOpening = false
      this._messages = messages || []
      this._renderMessages(this._messages)
    })

    this.handleEvent('config_guide_message', ({ id, body, sender_role, inserted_at }) => {
      if (sender_role === 'user') return // ignore server echo of user messages (dedup)
      const msg = { id, body, sender_role, inserted_at }
      this._messages.push(msg)
      this._appendMessage(msg)
    })

    this.handleEvent('config_guide_error', ({ error }) => {
      clearTimeout(this._openTimer)
      this._openTimer = null
      this._isOpening = false
      this._showError(error)
    })
  },

  destroyed() {
    clearTimeout(this._openTimer)
    this._removeModal()
  },

  _handleClick() {
    // Double-spawn guard: if opening is in flight OR modal already exists, bail
    if (this._isOpening || document.getElementById(MODAL_ID)) return

    this._isOpening = true
    this._setButtonLoading(true)

    fetch('/api/v1/agents', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        instructions: 'Help me configure Claude Code.',
        agent: 'claude-config-guide',
        model: 'sonnet',
      }),
    })
      .then(res => {
        if (!res.ok) throw new Error(`HTTP ${res.status}`)
        return res.json()
      })
      .then(data => {
        this._sessionUuid = data.session_uuid
        this._createModal()
        this.pushEvent('config_guide_open_chat', { session_id: this._sessionUuid })

        // Timeout: if no history arrives within OPEN_TIMEOUT_MS, show error in modal
        this._openTimer = setTimeout(() => {
          this._showError('Config Guide did not respond. Try closing and reopening.')
        }, OPEN_TIMEOUT_MS)
      })
      .catch(err => {
        this._isOpening = false
        this._setButtonLoading(false)
        this._showButtonError(`Failed to start Config Guide: ${err.message}`)
      })
  },

  _createModal() {
    if (document.getElementById(MODAL_ID)) return

    // Note: inline SVG is intentional here — this is JS-built DOM, <.icon> (HEEx) is unavailable.
    const modal = document.createElement('div')
    modal.id = MODAL_ID
    modal.innerHTML = `
      <div class="fixed bottom-24 right-4 w-[520px] z-[1000] flex flex-col bg-base-100 border border-base-content/10 rounded-xl shadow-2xl max-h-[850px] overflow-hidden">
        <div class="flex items-center justify-between px-4 py-2.5 border-b border-base-content/5 bg-base-200/30">
          <div class="flex items-center gap-2">
            <span class="font-bold text-xs bg-primary/10 text-primary rounded-full w-7 h-7 flex items-center justify-center">CG</span>
            <div>
              <span class="text-xs font-semibold text-base-content/70">Config Guide</span>
            </div>
          </div>
          <button id="config-guide-close" class="btn btn-ghost btn-xs btn-square text-base-content/30" title="Close">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-3.5 h-3.5">
              <path d="M6.28 5.22a.75.75 0 0 0-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 1 0 1.06 1.06L10 11.06l3.72 3.72a.75.75 0 1 0 1.06-1.06L11.06 10l3.72-3.72a.75.75 0 0 0-1.06-1.06L10 8.94 6.28 5.22Z" />
            </svg>
          </button>
        </div>

        <div id="config-guide-messages" class="flex-1 overflow-y-auto p-3 space-y-2.5 min-h-[400px] max-h-[720px]">
          <div id="config-guide-loading" class="text-center text-base-content/25 text-xs py-10">
            Starting Config Guide...
          </div>
        </div>

        <div class="px-3 py-2.5 border-t border-base-content/5">
          <div class="flex gap-2">
            <input
              type="text"
              id="config-guide-input"
              placeholder="Ask about Claude configuration..."
              class="input input-sm flex-1 bg-base-200/50 border-base-content/8 text-sm placeholder:text-base-content/25"
              autocomplete="off"
            />
            <button id="config-guide-send" class="btn btn-primary btn-sm btn-square">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-3.5 h-3.5">
                <path d="M3.105 2.288a.75.75 0 0 0-.826.95l1.414 4.926A1.5 1.5 0 0 0 5.135 9.25h6.115a.75.75 0 0 1 0 1.5H5.135a1.5 1.5 0 0 0-1.442 1.086l-1.414 4.926a.75.75 0 0 0 .826.95 28.897 28.897 0 0 0 15.293-7.154.75.75 0 0 0 0-1.115A28.897 28.897 0 0 0 3.105 2.289Z" />
              </svg>
            </button>
          </div>
        </div>
      </div>`

    document.body.appendChild(modal)

    document.getElementById('config-guide-close')?.addEventListener('click', () => this._close())
    document.getElementById('config-guide-send')?.addEventListener('click', () => this._send())

    const input = document.getElementById('config-guide-input')
    if (input) {
      input.addEventListener('keydown', e => {
        if (e.key === 'Enter' && !e.shiftKey) {
          e.preventDefault()
          this._send()
        }
      })
    }
  },

  _renderMessages(messages) {
    const container = document.getElementById('config-guide-messages')
    if (!container) return

    if (messages.length === 0) {
      container.innerHTML = `<div class="text-center text-base-content/25 text-xs py-10">No messages yet. Ask anything about Claude configuration.</div>`
    } else {
      container.innerHTML = messages.map(m => this._messageHtml(m)).join('')
    }
    container.scrollTop = container.scrollHeight
    this._setButtonLoading(false)
  },

  _appendMessage(msg) {
    const container = document.getElementById('config-guide-messages')
    if (!container) return

    const loading = document.getElementById('config-guide-loading')
    if (loading) loading.remove()

    const div = document.createElement('div')
    div.innerHTML = this._messageHtml(msg)
    container.appendChild(div.firstChild)
    container.scrollTop = container.scrollHeight
  },

  _messageHtml(m) {
    if (m.sender_role === 'error') {
      // Error state includes a close affordance per spec
      return `<div class="flex justify-start">
        <div class="bg-error/10 text-error rounded-xl px-3 py-2 text-sm max-w-[80%]">
          <p>${this._escape(m.body)}</p>
          <button onclick="document.getElementById('${MODAL_ID}')?.remove()" class="text-xs underline mt-1 opacity-70">Close</button>
        </div>
      </div>`
    }
    const isUser = m.sender_role === 'user'
    return `<div class="flex ${isUser ? 'justify-end' : 'justify-start'}">
      <div class="${isUser ? 'bg-primary/90 text-primary-content rounded-xl rounded-br-sm' : 'bg-base-200/60 rounded-xl rounded-bl-sm'} px-3 py-2 text-sm max-w-[80%] whitespace-pre-wrap">${this._escape(m.body)}</div>
    </div>`
  },

  _send() {
    const input = document.getElementById('config-guide-input')
    if (!input || !input.value.trim() || !this._sessionUuid) return

    const body = input.value.trim()
    input.value = ''
    input.focus()

    // Optimistic local echo (server echo of user messages is ignored by sender_role check)
    const msg = { body, sender_role: 'user' }
    this._messages.push(msg)
    this._appendMessage(msg)

    this.pushEvent('config_guide_send_message', {
      session_id: this._sessionUuid,
      body,
    })
  },

  _close() {
    this._removeModal()
    this.pushEvent('config_guide_close_chat', {})
    // Clear all state after pushEvent
    this._sessionUuid = null
    this._messages = []
    this._isOpening = false
    clearTimeout(this._openTimer)
    this._openTimer = null
    this._setButtonLoading(false)
  },

  _removeModal() {
    document.getElementById(MODAL_ID)?.remove()
  },

  _showError(message) {
    const container = document.getElementById('config-guide-messages')
    if (container) {
      // Error message includes inline close affordance (via _messageHtml 'error' branch)
      this._appendMessage({ body: message, sender_role: 'error' })
    }
    this._setButtonLoading(false)
    this._isOpening = false
  },

  _showButtonError(message) {
    const existing = document.getElementById('config-guide-btn-error')
    if (existing) existing.remove()

    const el = document.createElement('span')
    el.id = 'config-guide-btn-error'
    el.className = 'text-error text-xs ml-2'
    el.textContent = message
    this.el.insertAdjacentElement('afterend', el)
    setTimeout(() => el.remove(), 4000)
  },

  // DaisyUI v5 loading: inject/remove a spinner span inside the button
  _setButtonLoading(loading) {
    this.el.disabled = loading
    const existing = this.el.querySelector('.loading-spinner')
    if (loading && !existing) {
      this.el.insertAdjacentHTML('afterbegin', '<span class="loading loading-spinner loading-xs mr-1"></span>')
    } else if (!loading && existing) {
      existing.remove()
    }
  },

  _escape(str) {
    const div = document.createElement('div')
    div.textContent = str
    return div.innerHTML
  },
}
```

- [ ] **Step 2: No automated JS unit test — verified via LiveView + Playwright test in Chunk 5**

---

### Task 6: Register hook in `app.js` and add import

**Files:**
- Modify: `assets/js/app.js`

- [ ] **Step 1: Read app.js to confirm exact line numbers**

Use Read tool on `assets/js/app.js` lines 26-100 to verify where the hook imports and registrations are before editing.

- [ ] **Step 2: Add import alongside other hook imports**

After the `FileAttach` import line (currently ~line 38):
```javascript
import {ConfigChatGuide} from "./hooks/config_chat_guide"
```

- [ ] **Step 3: Register the hook after `Hooks.FileAttach = FileAttach` (~line 95)**

```javascript
Hooks.ConfigChatGuide = ConfigChatGuide
```

- [ ] **Step 4: Compile**

```bash
mix compile
```
Expected: clean.

- [ ] **Step 5: Commit Chunk 3**

```bash
git add assets/js/hooks/config_chat_guide.js assets/js/app.js
git commit -m "feat: add ConfigChatGuide JS hook"
```

---

## Chunk 4: Config page button

### Task 7: Add button to Config page toolbar

**Files:**
- Modify: `lib/eye_in_the_sky_web_web/live/overview_live/config.ex:308-330`

- [ ] **Step 1: Read the actual file before editing**

```bash
# Read lines 308-335 to confirm exact current content before making changes
```

Use the Read tool on `lib/eye_in_the_sky_web_web/live/overview_live/config.ex` lines 308-335. Verify the toolbar content matches what is shown below before applying the edit. If it differs, adjust accordingly.

- [ ] **Step 2: Update toolbar div to flex layout and add button**

Current toolbar inner div (line ~310):
```heex
<div class="px-4 sm:px-6 lg:px-8 py-2">
  <div class="join">
    ...
  </div>
</div>
```

Replace with:
```heex
<div class="px-4 sm:px-6 lg:px-8 py-2 flex items-center gap-2">
  <div class="join">
    <button
      class={"btn btn-sm join-item" <> if @view_mode == :tree, do: " btn-active", else: ""}
      phx-click="toggle_view_mode"
      phx-value-mode="tree"
    >
      <.icon name="hero-folder" class="w-4 h-4" />
      Explore
    </button>
    <button
      class={"btn btn-sm join-item" <> if @view_mode == :list, do: " btn-active", else: ""}
      phx-click="toggle_view_mode"
      phx-value-mode="list"
    >
      <.icon name="hero-bars-3" class="w-4 h-4" />
      List
    </button>
  </div>
  <button
    id="config-guide-chat-btn"
    phx-hook="ConfigChatGuide"
    class="btn btn-sm btn-ghost ml-auto"
  >
    <.icon name="hero-chat-bubble-left-ellipsis" class="w-4 h-4" />
    Config Guide
  </button>
</div>
```

- [ ] **Step 2: Compile**

```bash
mix compile
```
Expected: clean.

- [ ] **Step 4: Compile**

```bash
mix compile
```
Expected: clean.

- [ ] **Step 5: Commit Chunk 4**

```bash
git add lib/eye_in_the_sky_web_web/live/overview_live/config.ex
git commit -m "feat: add Config Guide chat button to config page toolbar"
```

---

## Chunk 5: Final verification

### Task 8: Playwright browser test

**Files:**
- Create: `test/playwright/config_guide_chat.spec.js`

> CLAUDE.md requires Playwright verification. This test mocks the agent spawn endpoint to avoid requiring live API keys.

- [ ] **Step 1: Check if Playwright is configured**

```bash
ls test/playwright/ 2>/dev/null || echo "No playwright dir"
ls playwright.config.js 2>/dev/null || ls playwright.config.ts 2>/dev/null || echo "No playwright config"
```

If no config exists, create `playwright.config.js` in the project root:

```javascript
// playwright.config.js
import { defineConfig } from '@playwright/test'

export default defineConfig({
  testDir: './test/playwright',
  use: {
    baseURL: 'http://localhost:5000',
  },
})
```

Then create the directory:
```bash
mkdir -p test/playwright
```

- [ ] **Step 2: Write the Playwright test**

```javascript
// test/playwright/config_guide_chat.spec.js
import { test, expect } from '@playwright/test'

test.describe('Config Guide chat button', () => {
  test.beforeEach(async ({ page }) => {
    // Mock the agent spawn endpoint so tests don't require a live Claude API
    await page.route('/api/v1/agents', async route => {
      await route.fulfill({
        status: 201,
        contentType: 'application/json',
        body: JSON.stringify({
          success: true,
          message: 'Agent spawned',
          agent_id: 'test-agent-uuid',
          session_id: 1,
          session_uuid: 'test-session-uuid-1234',
        }),
      })
    })
  })

  test('Config Guide button renders on /config', async ({ page }) => {
    await page.goto('http://localhost:5000/config')
    const btn = page.locator('#config-guide-chat-btn')
    await expect(btn).toBeVisible()
    await expect(btn).toContainText('Config Guide')
  })

  test('clicking button creates chat modal', async ({ page }) => {
    await page.goto('http://localhost:5000/config')

    await page.click('#config-guide-chat-btn')

    // Modal should appear
    await expect(page.locator('#config-guide-chat-modal')).toBeVisible({ timeout: 5000 })
    // Loading skeleton appears while waiting for history
    await expect(page.locator('#config-guide-loading')).toBeVisible()
  })

  test('double-clicking button does not create two modals', async ({ page }) => {
    await page.goto('http://localhost:5000/config')

    await page.click('#config-guide-chat-btn')
    await page.click('#config-guide-chat-btn')

    const modals = await page.locator('#config-guide-chat-modal').count()
    expect(modals).toBe(1)
  })

  test('close button removes modal and re-enables button', async ({ page }) => {
    await page.goto('http://localhost:5000/config')

    await page.click('#config-guide-chat-btn')
    await expect(page.locator('#config-guide-chat-modal')).toBeVisible({ timeout: 5000 })

    await page.click('#config-guide-close')

    await expect(page.locator('#config-guide-chat-modal')).not.toBeVisible()
    await expect(page.locator('#config-guide-chat-btn')).toBeEnabled()
  })

  test('clicking button again after close opens a fresh modal', async ({ page }) => {
    await page.goto('http://localhost:5000/config')

    await page.click('#config-guide-chat-btn')
    await expect(page.locator('#config-guide-chat-modal')).toBeVisible({ timeout: 5000 })
    await page.click('#config-guide-close')
    await expect(page.locator('#config-guide-chat-modal')).not.toBeVisible()

    await page.click('#config-guide-chat-btn')
    await expect(page.locator('#config-guide-chat-modal')).toBeVisible({ timeout: 5000 })
  })
})
```

- [ ] **Step 3: Run Playwright tests (requires dev server running)**

```bash
# Terminal 1: start server (if not already running)
mix phx.server

# Terminal 2: run tests
npx playwright test test/playwright/config_guide_chat.spec.js
```
Expected: all 5 tests pass. If browser binaries are missing: `npx playwright install chromium`.

- [ ] **Step 4: Close browser**

Playwright closes the browser automatically after the test run. No manual cleanup needed.

---

### Task 9: Run full test suite and compile check

- [ ] **Step 1: Run all tests**

```bash
mix test
```
Expected: all tests pass, including the new `config_guide_chat_test.exs`.

- [ ] **Step 2: Compile with warnings-as-errors**

```bash
mix compile --warnings-as-errors
```
Expected: clean.

- [ ] **Step 3: Final commit if any cleanup needed**

```bash
git add lib/eye_in_the_sky_web_web/live/fab_hook.ex \
        lib/eye_in_the_sky_web_web/live/overview_live/config.ex \
        assets/js/hooks/config_chat_guide.js \
        assets/js/app.js \
        test/eye_in_the_sky_web_web/live/config_guide_chat_test.exs \
        test/playwright/config_guide_chat.spec.js
git commit -m "feat: config guide chat button on /config page"
```
