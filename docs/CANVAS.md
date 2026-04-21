# Canvas Page Architecture

## Overview

The Canvas page is a dedicated LiveView interface for managing multiple collaborative work sessions simultaneously on a visual canvas. Users can organize sessions in named canvases, arrange windows with draggable positioning, and maintain real-time synchronization via PubSub events.

**Key Change (PR #56):** Canvas was promoted from an overlay component mounted in `app.html.heex` to a dedicated `CanvasLive` page with its own routes and full-page layout.

## Before & After

### Previous Architecture (Overlay Component)
- Canvas overlay was mounted directly in `app.html.heex` as a modal component
- Overlay component managed canvas state within the larger app layout
- Accessed via toggle or modal trigger on the main navigation
- Limited to overlay positioning on top of other page content

### Current Architecture (Dedicated Page)
- Canvas is now a standalone LiveView page at `/canvases` and `/canvases/:id`
- Full-page layout with dedicated canvas tabs and session windows
- Accessible via main navigation routing to `CanvasLive`
- Provides complete visual workspace without overlay constraints

## Route Structure

```elixir
# lib/eye_in_the_sky_web/router.ex
scope "/", EyeInTheSkyWeb do
  pipe_through :browser

  live "/canvases", CanvasLive, :index      # List/default canvas view
  live "/canvases/:id", CanvasLive, :show   # View specific canvas with sessions
end
```

The router defines two action atoms (`:index` and `:show`) but the `CanvasLive` module uses `handle_params/3` to branch logic based on the `:id` parameter presence rather than action-based callbacks.

## CanvasLive Module

Located at: `lib/eye_in_the_sky_web/live/canvas_live.ex`

### State Initialization

`mount/3` initializes the canvas page with:
- `:canvases` — list of all available canvases
- `:active_canvas_id` — currently selected canvas (nil until routed with ID)
- `:canvas_sessions` — sessions pinned to the active canvas
- `:subscribed_session_ids` — session IDs with active PubSub subscriptions
- `:creating_canvas` — boolean flag for new canvas form display
- `:sidebar_tab` — set to `:canvas` to activate canvas sidebar section

### Route Handling

```elixir
# handle_params/3 — activates canvas on route change
def handle_params(%{"id" => id_str}, _url, socket)
  # Parse canvas ID, validate, and activate
  # Subscribes to all sessions in that canvas
  # Sets up window position defaults (cascade layout if not set)

def handle_params(_params, _url, socket)
  # No ID — redirect to first canvas or stay on empty canvas list
```

## Keyboard Shortcuts & Controls

### Global Keyboard Handling
Keyboard events are managed via the `GlobalKeydown` hook registered in `assets/js/app.js`. This centralized hook:
- Listens for keyboard events at the window level
- Routes commands to appropriate handlers (canvas tab navigation, viewport panning, window minimization)
- Prevents duplicate handling across multiple pages (canvas, DM, etc.)
- Previously, CanvasLive had a catch-all event handler; now canvas-specific keydown events are handled by `GlobalKeydown` hook instead with explicit logging of unhandled events

### Keyboard Shortcuts Help
- **`?` key** — Toggle keyboard shortcuts help panel. Lazily creates modal overlay listing all canvas shortcuts. Escape or backdrop click closes; input fields guarded so typing in search boxes doesn't trigger.

### Canvas & Tab Navigation
- **`Cmd+1` through `Cmd+9`** — Tab switcher to quickly jump between open canvas tabs
- **`Esc`** — Minimize focused window

### Viewport Controls
- **`Spacebar + drag`** — Pan viewport to reposition all windows without moving them individually

### Chat Window
- **Auto-scroll toggle** — Click button in chat window footer to enable/disable. When enabled (default), new messages scroll to bottom. When disabled, stays in current position and shows unread message count pill; clicking pill re-enables auto-scroll and jumps to bottom.

### Event Handlers

#### Canvas Management
- **`switch_tab`** — User clicks canvas tab; routes to `/canvases/:id` via `push_patch`
- **`start_new_canvas`** — Toggles `:creating_canvas` flag to show name input form
- **`create_canvas`** — Validates name, creates canvas, appends to list, routes to new canvas
- **`tidy_canvas`** — Tidy button in the canvas header cascades all windows into a clean layout via `Canvases.tidy/1`, which resets positions and applies consistent spacing

#### Window Management
- **`window_moved`** — Records x/y position delta; calls `Canvases.update_window_layout/2`
- **`window_resized`** — Records width/height delta; calls `Canvases.update_window_layout/2`
- **`remove_window`** — Removes session from canvas and unsubscribes from PubSub
- **`raise_window`** — Clicking any canvas window raises it to the front by updating z-order state in `CanvasLive`
- **`minimize_window`** — Minimize/collapse toggle for individual windows. Minimized windows show unread indicator dot.
- **`maximize_window`** — Restore window to full size if minimized. Includes unread dot on minimized windows.

### Canvas Management Events

#### Toolbar Controls
- **`+` button** — Opens Add Session submenu directly via command palette (jumps to session picker without full search). Implemented via `palette:open-command` event with `commandId=canvas-add-session`.
- **Delete canvas button** — Wired event handler to delete canvas from toolbar.
- **Tidy button** — Cascades all windows into clean layout via `Canvases.tidy/1`, which resets positions and applies consistent spacing.

#### Tab Operations
- **Double-click tab** — Rename canvas inline. Updates page title on successful rename.
- **Page title** — Shows active canvas name; resets on last canvas delete.

### PubSub Integration

The canvas page subscribes to session event streams via `EyeInTheSky.Events`:

**In `activate_canvas/2`:**
```elixir
subscribe_all(session_ids)  # Subscribe to events for all canvas sessions
```

**Event handlers for real-time updates:**
- `{:new_message, message}` — New message received in canvas session; calls `refresh_window` to update chat window
- `{:new_dm, message}` — Direct message received in a canvas session
- `{:claude_response, _ref, parsed}` — Agent response received
- `{:session_status, session_id, status}` — Session status changed (working → stopped)
- `{:remove_canvas_window, cs_id}` — Remote signal to close a window (e.g., session cleanup)
- `{:canvas_session_added, session_id}` — Session added to canvas; updates session list and badge counts

When events arrive, the handler calls `send_update/3` to update the `ChatWindowComponent` for that canvas session, keeping UI synchronized without full page refresh.

## JavaScript Hooks

### Canvas Layout Hook
- **File:** `assets/js/hooks/canvas_layout_hook.js`
- **Purpose:** Manages preset layout buttons (2up, 4up) and localStorage persistence
- **Exports:**
  - `saveWindowLayout(csId, x, y, w, h, z)` — Persists window position, size, and optionally z-index to localStorage
  - `loadWindowLayout(csId)` — Retrieves saved layout from localStorage
  - `saveWindowZ(csId, z)` — Saves z-index separately (used when only stacking order changes)
- **Events:** Dispatches `canvas:layout-applied` custom event to notify ChatWindowHook of preset layout application

### Chat Window Hook
- **File:** `assets/js/hooks/chat_window_hook.js`
- **Purpose:** Handles window drag, resize, focus, minimize/maximize, and snap-to-edge detection
- **Lifecycle:**
  - On mount: Loads position/size/z-index from localStorage and dispatches layout-applied event listener
  - During drag: Saves position to localStorage with 50ms debounce
  - During resize: Saves dimensions to localStorage with 400ms debounce
  - On focus/blur: Saves z-index to localStorage
- **Snap zones:** Configurable threshold (40px) for edge snapping; snap zones detected based on cursor proximity to viewport edges
- **Instance variables:** Maintains `_width`, `_height`, `_dragLeft`, `_dragTop`, `_zIndex` to track window state; these are synced when layout buttons are applied

### Global Keydown Hook
- **File:** `assets/js/hooks/global_keydown.js`
- **Purpose:** Centralized keyboard event handling across all pages
- **Registration:** Added to `Hooks` object in `assets/js/app.js`
- **Prevents:** Duplicate keyboard handling in individual LiveViews (canvas, DM, etc.)

## Component Integration

### ChatWindowComponent
- **Located:** `lib/eye_in_the_sky_web/components/chat_window_component.ex`
- **Role:** Renders draggable, resizable windows for each canvas session
- **Props:** `canvas_session` (struct with pos_x, pos_y, width, height, session_id)
- **Events:** Emits `window_moved`, `window_resized`, `remove_window`, `raise_window` to parent `CanvasLive`
- **Updates:** Receives `send_update` calls from PubSub event handlers to re-render with latest message
- **Message rendering:** Uses DM-style message display with provider icons, sender name, model badge, timestamp, markdown via MarkdownMessage hook, tool call widgets, thinking section, and tool result output blocks. Matches DM page styling for consistent message presentation.
- **Status indicator:** Session status dot uses `status_dot_class` with classes for all states: working (primary color with pulse animation), completed, failed, and idle.
- **Focus ring:** Active window shows visible focus ring to indicate interaction target.
- **Scroll behavior:** ChatWindowHook owns all scroll behavior. Auto-scroll enabled by default; disabled when user scrolls up and shows unread message count pill. Clicking pill re-enables auto-scroll and jumps to bottom. Automatically scrolls to bottom when user sends new message.

### AgentList Integration
- **File:** `lib/eye_in_the_sky_web/components/agent_list.ex`
- **Canvas Actions:** Session cards include two dropdown options:
  - "Add to Canvas" — Opens modal to select existing canvas
  - "Add to New Canvas" — Creates canvas and adds session in one action
- **Navigation:** Both trigger `push_navigate` to `/canvases/:id` after adding session

### AllProjectsSection Integration
- **File:** `lib/eye_in_the_sky_web/components/sidebar/all_projects_section.ex`
- **Canvas Tab:** Sidebar includes a "Canvas" tab that routes to `/canvases`
- **Sidebar Tab:** When viewing canvas, `:sidebar_tab` is set to `:canvas` to highlight active section

## Canvas Handlers Module

Located at: `lib/eye_in_the_sky_web/live/agent_live/canvas_handlers.ex`

This extracted module handles canvas-related events fired from the **AgentLive** page when users interact with "Add to Canvas" buttons on session cards:

### Event Handlers

**`show_new_canvas_form`**
- User clicks "Create and add to canvas" on a session card
- Sets `:show_new_canvas_for` flag in AgentLive to display canvas name input

**`add_to_canvas`**
- User selects existing canvas from dropdown
- Calls `Canvases.add_session/2` to link session to canvas
- Routes user to `/canvases/:id` with success flash

**`add_to_new_canvas`**
- User submits new canvas form with optional name
- If no name provided, generates default: `"Canvas {unix_timestamp}"`
- Creates canvas, adds session, routes to new canvas with success flash
- Flash message: `"Added to {canvas_name}"`

## State Management & Data Flow

### Session Lifecycle in Canvas

1. **Adding to Canvas**
   - User clicks "Add to Canvas" on a session card in AgentLive
   - CanvasHandlers.handle_event validates IDs and calls `Canvases.add_session/2`
   - Canvas page receives PubSub event (if open) or user navigates to canvas

2. **Activation**
   - User navigates to `/canvases/:id` (via tab click or redirect)
   - CanvasLive.activate_canvas loads sessions for that canvas
   - Subscribes to session event streams (messages, status, etc.)
   - Sets initial window positions (cascade layout if not persisted)

3. **Real-Time Sync**
   - Events arrive via PubSub: new messages, status changes
   - CanvasLive.handle_info dispatches `send_update` to ChatWindowComponent
   - Components re-render without full page reload

4. **Removal**
   - User clicks close button on window (via ChatWindowComponent)
   - CanvasLive.handle_event removes session and unsubscribes
   - Session remains in database; only canvas link removed

### Window Position & Z-Index Persistence

**Database Storage:**
Window layout (x, y, width, height) is stored in the `canvas_sessions` join table:
- `pos_x`, `pos_y` — Top-left corner offset (pixels)
- `width`, `height` — Window dimensions

When canvas is activated, positions are restored from database. If both are 0, a cascade layout is applied (each window offset by `24 + i*32` pixels) to avoid stack overlap.

**localStorage Persistence:**
In addition to database persistence, window layout and z-index are persisted to browser localStorage for immediate restoration across sessions:
- **Position & size**: `canvas_layout_hook.js` provides `saveWindowLayout(csId, x, y, w, h)` and `loadWindowLayout(csId)` functions that store layout in `cw_{csId}` localStorage entry
- **Z-index**: `saveWindowZ(csId, z)` persists window stacking order alongside layout data
- **Restoration**: `ChatWindowHook` loads saved layout and z-index on mount, restoring windows to their last-known state
- **Sync events**: When layout buttons (2up, 4up) apply preset positions, a `canvas:layout-applied` custom event is dispatched so ChatWindowHook can sync its instance variables (width, height, drag position)
- **Drag/Resize debounce**: Window moves and resizes are debounced before localStorage save (50ms for move, 400ms for resize) to avoid excessive writes

**Z-Index Lifecycle:**
- **Mount**: Restored from localStorage if available, otherwise defaults to "1"
- **Focus**: When user clicks window or tab to focus, z-index updates to "20" and is persisted
- **Minimize/Maximize**: Z-index saved when toggling window state
- **Other windows**: When a window is focused, all other windows reset to z-index "1" and are persisted

## Navigation Flow

### Accessing Canvas

1. **From Agent List**
   - Session card dropdown → "Add to Canvas"
   - Navigates to `/canvases/:id` after adding

2. **From Sidebar**
   - Click "Canvas" tab in sidebar
   - Routes to `/canvases` (redirects to first canvas if available)

3. **Direct URL**
   - User navigates to `/canvases` or `/canvases/:id` directly

### Canvas-to-Agent Navigation

While canvas page is standalone, chat windows display session messages. Clicking a session name or message link should route back to `/agents/:id` (AgentLive) for full session context (code history, status details, etc.).

## Key Architectural Patterns

### Route Branching vs Action Atoms
- `CanvasLive` defines two routes (`:index` and `:show`) but doesn't use action-specific callbacks
- Logic is branched in `handle_params/3` based on `id` param presence
- This pattern avoids action-based render clauses and keeps state management centralized

### Extracted Handlers
- `CanvasHandlers` module extracts canvas-related event logic from AgentLive
- Keeps AgentLive focused on session list and agent card UI
- Enables canvas operations (add, create) from session context

### PubSub Subscription Lifecycle
- Subscriptions are created during `activate_canvas/2`
- All subscriptions cleared when switching canvases or leaving page
- Prevents stale event delivery and connection leak

### Component Isolation
- ChatWindowComponent is a live_component with its own event handling
- Parent (CanvasLive) owns layout and routing; children own rendering
- send_update patterns allow parent to trigger re-renders without full replacement

## Layout & Display

### Canvas Page Layout
- **Full-screen mode:** Dedicated canvas page with full viewport. Back button available to return to previous page. No sidebar visible during canvas interactions.
- **Page title:** Browser tab shows active canvas name for easy identification when multiple canvases are open.
- **Window positioning:** Cascade layout applied by default if window positions not previously persisted. Tidy button resets all windows and cascades them into clean grid layout.

### Status & Visual Feedback
- **Working status pulse** — Session status dot animates with continuous pulse effect when session is in working state
- **Unread indicators** — Minimized windows show unread message dot; unread count pill appears when auto-scroll is disabled and new messages arrive
- **Session added badge** — Refresh badge displayed on add_session to provide visual feedback that canvas was updated

## Related Files

- **Routes:** `lib/eye_in_the_sky_web/router.ex` (lines 157-158)
- **LiveView:** `lib/eye_in_the_sky_web/live/canvas_live.ex` (264 lines)
- **Handlers:** `lib/eye_in_the_sky_web/live/agent_live/canvas_handlers.ex`
- **Components:**
  - `lib/eye_in_the_sky_web/components/chat_window_component.ex`
  - `lib/eye_in_the_sky_web/components/agent_list.ex` (canvas buttons)
  - `lib/eye_in_the_sky_web/components/sidebar/all_projects_section.ex` (canvas tab)
- **Schema:** `lib/eye_in_the_sky/canvases/canvas.ex` and related Ecto context
- **PubSub:** `lib/eye_in_the_sky/events.ex` (subscription logic)
