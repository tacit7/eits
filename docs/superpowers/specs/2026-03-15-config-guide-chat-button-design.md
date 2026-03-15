# Config Guide Chat Button — Design Spec
**Date:** 2026-03-15

## Summary

Add a "Config Guide" button to the Claude Config page (`/config`) that launches an inline FAB-style chat window backed by a `--agent claude-config-guide` Claude CLI session.

---

## Requirements

- Button appears in the Config page toolbar (next to Explore/List toggles), always visible, icon + label, no hiding at narrow widths.
- Clicking it spawns a new agent via `POST /api/v1/agents` with `agent: "claude-config-guide"` and `model: "sonnet"`.
- A floating chat modal appears (same visual style as the FAB chat) for inline interaction.
- The button is disabled while spawning (guarded against double-spawn via `isOpening` flag).
- After spawning, the chat opens immediately; the user can send/receive messages.
- Independent of the FAB bookmark chat — no shared state, no event name collisions.

---

## Architecture

### New event namespace: `config_guide_*`

Separate from `fab_*` events to prevent conflicts when both FAB chat and config guide are active simultaneously.

| Direction | Event | Purpose |
|---|---|---|
| JS → Server | `config_guide_open_chat` | Subscribe to session, load history |
| JS → Server | `config_guide_send_message` | Send a user message |
| JS → Server | `config_guide_close_chat` | Unsubscribe from session |
| Server → JS | `config_guide_history` | Load recent messages |
| Server → JS | `config_guide_message` | Append new incoming message |
| Server → JS | `config_guide_error` | Surface send/subscribe errors |

### FabHook (`fab_hook.ex`) additions

**Subscriptions are owned by the LiveView process**, not the JS hooks. The hooks trigger events; the server process subscribes. The LiveView may hold subscriptions to multiple session topics simultaneously and routes messages manually based on which assign matches.

- New assign in `on_mount`: `:config_guide_active_session_id` (initialized to `nil`)
- Handle `config_guide_open_chat`:
  1. Resolve session via UUID lookup
  2. Only on success: `PubSub.subscribe("session:<id>")`
  3. Store integer session id in `:config_guide_active_session_id`
  4. Load recent messages and push `config_guide_history`
  5. On any error: push `config_guide_error`, do NOT set assign
- Handle `config_guide_send_message`:
  - Resolve session by UUID, create Message record, continue session via `AgentManager`
  - On error: push `config_guide_error`
- Handle `config_guide_close_chat`:
  - If `:config_guide_active_session_id` is non-nil: `PubSub.unsubscribe("session:<id>")`
  - Reset `:config_guide_active_session_id` to `nil` immediately after unsubscribe
- `handle_fab_info` for `{:new_message, msg}` — updated to route by `msg.session_id` (integer DB id):
  - If `msg.session_id == fab_active_session_id`: push `fab_chat_message`
  - Else if `msg.session_id == config_guide_active_session_id`: push `config_guide_message`
  - Else: ignore (not subscribed to this session)
  - Note: this function now acts as a shared session message router and should be documented as such
- On LiveView process termination: all PubSub subscriptions are automatically dropped by process exit

**Message payload shape** pushed from server (both `config_guide_history` items and `config_guide_message`):
```json
{ "id": 123, "session_id": 456, "body": "...", "sender_role": "assistant", "inserted_at": "2026-03-15T..." }
```
Including `id` and `inserted_at` enables future dedupe and ordering. `session_id` is an integer.

### New JS hook: `ConfigChatGuide`

File: `assets/js/hooks/config_chat_guide.js`

Mounted on the button element in the Config page.

**State:**
- `this._isOpening` — boolean, set `true` synchronously before fetch, cleared on failure or after modal is initialized
- `this._sessionUuid` — UUID string of the active session (set after successful spawn)
- `this._messages` — array of rendered messages

**Click handler — race guard:**
```
if (this._isOpening || document.getElementById('config-guide-chat-modal')) return
this._isOpening = true
disable button, show loading state
```
This is set synchronously before the async fetch. Any subsequent click before modal appears is a no-op.

**Spawn flow:**
1. `POST /api/v1/agents` with `{ instructions: "Help me configure Claude Code.", agent: "claude-config-guide", model: "sonnet" }`
   - The `agent` param is authoritative for persona/behavior. `instructions` provides user-facing context for the initial task.
   - Auth relies on existing session cookies (same origin).
2. On REST failure (network error or non-2xx): re-enable button, clear `isOpening`, show error near button
3. On success: store `session_uuid`, **create modal immediately in loading skeleton state**, then push `config_guide_open_chat`

**Modal creation order:**
- Create modal with loading skeleton as soon as REST responds successfully
- User gets immediate visual feedback
- Push `config_guide_open_chat` after modal is in DOM
- When `config_guide_history` arrives: replace skeleton with messages
- If `config_guide_error` arrives before history: show error state inside modal with a close button

**Modal identity:**
- ID: `config-guide-chat-modal`
- Only one may exist. Click guard (modal existence check + `isOpening`) ensures this.
- `_createModal()` should query for existing element by ID and bail if found.

**Event handlers:**
- `handleEvent('config_guide_history', { messages })` — replace skeleton, render message list, scroll to bottom. Each message includes `{ id, session_id, body, sender_role, inserted_at }`.
- `handleEvent('config_guide_message', { id, body, sender_role })` — **only append if `sender_role !== 'user'`** (dedup: user messages are echoed locally on send; server should not broadcast user messages back). Scroll to bottom.
- `handleEvent('config_guide_error', { error })` — show error in modal (or in button area if modal not yet open)

**Send:**
1. Read input value, clear input
2. **Optimistic local echo**: append user message immediately to modal
3. Push `config_guide_send_message` with `{ session_id: this._sessionUuid, body }`
4. Server persists user message and continues agent. Server-side PubSub message for user role is ignored client-side (see dedupe rule above).

**Close:**
1. Remove `config-guide-chat-modal` from DOM
2. Push `config_guide_close_chat`
3. Clear `this._sessionUuid`, `this._messages`, `this._isOpening`
4. Re-enable button
5. If a message send was in flight: server continues the session normally; client simply stops receiving updates (no error needed — LiveView unsubscribes cleanly)

**No-reply timeout:** If `config_guide_history` does not arrive within 10 seconds of pushing `config_guide_open_chat`, show an error state in the modal with a retry/close option. Re-enable button if user closes.

### Config page HEEx (`config.ex`)

Add button to existing toolbar row (right side of the Explore/List join group):

```heex
<button id="config-guide-chat-btn" phx-hook="ConfigChatGuide"
  class="btn btn-sm btn-ghost ml-auto">
  <.icon name="hero-chat-bubble-left-ellipsis" class="w-4 h-4" />
  Config Guide
</button>
```

The toolbar `<div class="join">` stays as-is; the button sits outside it on the right via `ml-auto` on the parent row's flex layout.

### `app.js`

Register `ConfigChatGuide` hook alongside existing hooks.

---

## Data Flow

```
User clicks button (isOpening = false, no modal)
  isOpening = true, button disabled
  -> POST /api/v1/agents { agent: "claude-config-guide", model: "sonnet", instructions: "..." }

  On REST failure:
    isOpening = false, button re-enabled, show error

  On REST success:
    sessionUuid = data.session_uuid
    Create modal in DOM (loading skeleton)
    -> pushEvent("config_guide_open_chat", { session_id: sessionUuid })
      -> FabHook resolves session, subscribes PubSub, loads history
      -> push_event("config_guide_history", { messages: [...] })
    Modal populated, isOpening = false

    [10s timeout if no history arrives -> error state in modal]

User sends message:
  Local optimistic echo in modal
  -> pushEvent("config_guide_send_message", { session_id: sessionUuid, body })
    -> Messages.send_message (user message persisted)
    -> AgentManager.continue_session
  Agent responds:
    -> PubSub {:new_message, msg} fires on LiveView process
    -> handle_fab_info routes by msg.session_id -> push_event("config_guide_message", ...)
    -> Modal appends assistant message (sender_role != "user", so no dedupe skip)

User closes modal:
  Modal removed from DOM
  -> pushEvent("config_guide_close_chat", {})
    -> FabHook unsubscribes PubSub, resets :config_guide_active_session_id = nil
  Button re-enabled, state cleared
```

---

## Conflict Avoidance

The LiveView process tracks two independent integer session IDs:
- `:fab_active_session_id` — set by FAB chat events
- `:config_guide_active_session_id` — set by config guide events

Incoming `{:new_message, msg}` is routed by `msg.session_id` match. Both chats can be active simultaneously without cross-talk. Event names are completely separate namespaces.

---

## Orphaned Sessions

Closing the modal unsubscribes the UI from the session PubSub topic but does **not** terminate the underlying agent process. The spawned Claude CLI session continues running until it completes or times out normally. Re-clicking the button spawns a new session; the previous one is abandoned.

This is acceptable for the current scope. Session lifecycle management (termination on close) is out of scope.

---

## Scope Clarifications

- **Config page scope**: Overview Config page only (`/config`, `overview_live/config.ex`). Not added to project-level config pages.
- **CSRF**: `/api/v1/agents` is in the `:api` pipeline which skips CSRF. Auth relies on session cookies (same-origin request).
- **Double-click guard**: `isOpening` flag set synchronously before fetch; modal existence check as secondary guard.
- **Re-open**: Closing the modal and clicking again spawns a fresh agent session.
- **Button visibility**: Always visible regardless of viewport width.

## Out of Scope

- Persisting/reusing config guide sessions across page navigations
- Multiple simultaneous config guide sessions
- Mobile-specific layout changes
- Terminating the agent on modal close
