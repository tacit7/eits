# Canvas Overlay

The Canvas system provides a floating multi-window interface for monitoring multiple sessions simultaneously. Users can organize sessions into named canvases and interact with each one from a single overlay view.

## Overview

A **Canvas** is a named workspace that groups one or more sessions as floating chat windows. The overlay takes over the full viewport, rendering each session in a draggable, resizable window. Window positions and sizes persist in the database per canvas/session pair.

## Schemas

### Canvas (`canvases` table)

```elixir
defmodule EyeInTheSkyWeb.Canvases.Canvas do
  schema "canvases" do
    field :name, :string               # max 100 chars
    has_many :canvas_sessions, CanvasSession
    timestamps()
  end
end
```

A canvas is just a named container. Sessions are added to it via `CanvasSession` records.

### CanvasSession (`canvas_sessions` table)

```elixir
defmodule EyeInTheSkyWeb.Canvases.CanvasSession do
  schema "canvas_sessions" do
    belongs_to :canvas, Canvas
    field :session_id, :integer        # FK to sessions.id (bare integer, no association)
    field :pos_x, :integer, default: 0
    field :pos_y, :integer, default: 0
    field :width, :integer, default: 320
    field :height, :integer, default: 260
    timestamps()
  end
end
```

`session_id` is a bare integer field, not a `belongs_to`. This keeps the `Canvases` context decoupled from the `Sessions` context.

The `[:canvas_id, :session_id]` pair has a unique constraint — a session can only appear once per canvas.

## Canvases Context

`EyeInTheSkyWeb.Canvases` (`lib/eye_in_the_sky_web/canvases.ex`) provides the data layer:

| Function | Description |
|---|---|
| `list_canvases/0` | All canvases, ordered by `inserted_at` |
| `get_canvas/1` | Get by ID, returns nil if not found |
| `get_canvas!/1` | Get by ID, raises if not found |
| `create_canvas/1` | Create a new canvas with `%{name: name}` |
| `delete_canvas/1` | Delete a canvas by ID |
| `list_canvas_sessions/1` | All CanvasSessions for a canvas |
| `add_session/2` | Add a session to a canvas (upsert on conflict) |
| `remove_session/2` | Remove a session from a canvas |
| `update_window_layout/2` | Persist position/size changes for a CanvasSession |

`add_session/2` uses `on_conflict: {:replace, [:updated_at]}` with `returning: true` to guarantee the returned struct has a real `id` even when the row already existed.

## CanvasOverlayComponent

`EyeInTheSkyWeb.Components.CanvasOverlayComponent` (`lib/eye_in_the_sky_web/components/canvas_overlay_component.ex`) is a LiveComponent that manages the full overlay.

### State

| Assign | Type | Description |
|---|---|---|
| `open` | boolean | Whether the overlay is visible |
| `canvases` | list | All Canvas records |
| `active_canvas_id` | integer \| nil | Currently selected canvas |
| `canvas_sessions` | list | CanvasSessions for the active canvas |
| `subscribed_session_ids` | list | Session IDs currently subscribed via PubSub |
| `creating_canvas` | boolean | Whether the inline canvas-creation form is visible |

### Opening and Switching Canvases

The overlay can be opened in two ways:

1. **Toggle action** — `send_update(CanvasOverlayComponent, id: "canvas-overlay", action: :toggle)`: toggles open/closed. On open, auto-activates the first canvas if one exists.
2. **Direct open** — `send_update(CanvasOverlayComponent, id: "canvas-overlay", action: :open_canvas, canvas_id: id)`: opens the overlay on a specific canvas.

When a canvas is activated, the component:
1. Unsubscribes from the previous canvas's session PubSub topics.
2. Loads all `CanvasSession` records for the new canvas.
3. Applies cascade-offset positioning for any windows that still have `pos_x == 0, pos_y == 0` (24 + i*32 px offset per window).
4. Subscribes to `session:<id>` and `session:<id>:status` PubSub topics for each session.

### PubSub Events

The component subscribes to two topics per session in the active canvas:

| Topic | Event | Effect |
|---|---|---|
| `session:<id>` | `{:new_dm, message}` | Refreshes the ChatWindowComponent for that session |
| `session:<id>` | `{:claude_response, ref, parsed}` | Refreshes the ChatWindowComponent for that session |
| `session:<id>:status` | `{:session_status, session_id, status}` | Triggers `send_update` to ChatWindowComponent to re-render status dot |

All subscriptions and unsubscriptions go through `EyeInTheSky.Events` — never directly via `Phoenix.PubSub`.

### Canvas UI Layout

The overlay renders as a full-viewport fixed `div` with `z-index: 60` and a blurred backdrop. The header contains:

- A **tab bar** for switching between canvases (DaisyUI `tabs-boxed`).
- A **"+ New"** tab that shows an inline form for creating a new canvas.
- A **Close** button.

The body is a relative container where each `ChatWindowComponent` is positioned absolutely.

## ChatWindowComponent

`EyeInTheSkyWeb.Components.ChatWindowComponent` (`lib/eye_in_the_sky_web/components/chat_window_component.ex`) renders a single floating session window.

### Rendering

Each window is an absolutely-positioned `div` initialized from `CanvasSession.pos_x/pos_y/width/height`. It contains:

- A **drag handle** (`data-drag-handle`) in the header — the title bar with session name and a colored status dot.
- A **message list** showing the last 50 messages (via `Messages.list_recent_messages/2`).
- A **message input form** for sending messages directly from the canvas window.
- A **close button** (red dot, top-right of header) that removes the window from the canvas.

Status dot colors:

| Session status | Color |
|---|---|
| `"working"` | Green (`bg-success`) |
| `"waiting"` | Yellow (`bg-warning`) |
| nil or other | Muted gray |

### Sending Messages

Submitting the message form calls `Messages.send_message/1` then `AgentManager.continue_session/3` to forward the message to the running agent.

### Window Removal

The close button sends a `remove_window` event to `ChatWindowComponent`, which delegates to `CanvasOverlayComponent` via `send_update/3`. The overlay calls `Canvases.remove_session/2` and removes the session from its PubSub subscriptions.

## ChatWindowHook (Client-Side)

`assets/js/hooks/chat_window_hook.js` attaches to each window element via `phx-hook="ChatWindowHook"`.

### Drag

- Listens for `mousedown` on `[data-drag-handle]`.
- Tracks delta from start position, updating `style.left` and `style.top` live.
- On `mousedown`, resets all `[data-chat-window]` elements to `z-index: 1` and raises the dragged window to `z-index: 10` (z-index stacking: active window always on top).
- On `mouseup`, debounces 300ms then pushes `window_moved` to the server with the new `x`/`y`.

### Resize

- Uses a `ResizeObserver` on the window element (native CSS `resize: both`).
- Debounces 400ms after resize stops, then pushes `window_resized` with the new `w`/`h`.
- The observer is disconnected in `destroyed()` to avoid memory leaks.

### Server Events

Both `window_moved` and `window_resized` events are handled by `ChatWindowComponent` which calls `Canvases.update_window_layout/2` to persist the new position or size in the `canvas_sessions` table.

## Adding a Session to a Canvas

Sessions are added to a canvas externally (e.g., from a session card's "Add to Canvas" action) by calling:

```elixir
Canvases.add_session(canvas_id, session_id)
```

The overlay reloads on next activation and the new session window appears.

## Z-Index Stacking

All windows start at `z-index: 1`. When a user begins dragging a window, the hook sets all windows back to `1` and raises the active window to `10`. This is purely client-side — no server round-trip for focus management.
