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
# Canvas routes are in the :app live_session (includes rail layout)
live "/canvases", CanvasLive, :index      # List/default canvas view
live "/canvases/:id", CanvasLive, :show   # View specific canvas with sessions
```

The router defines two action atoms (`:index` and `:show`) but the `CanvasLive` module uses `handle_params/3` to branch logic based on the `:id` parameter presence rather than action-based callbacks.

**Route placement:** Canvas routes are in the `:app` live_session (not `:canvas`) so they receive the rail layout by default, consistent with other app pages like chat.

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
- `:focus_session_id` — session ID to focus/raise when canvas loads (set from `?focus=` URL param)
- `:canvas_terminals` — list of CanvasTerminal records for active canvas
- `:terminal_pty_map` — map of `terminal_id => pty_server_pid` for running terminals

`mount/3` also subscribes to the global `agent:working` topic to receive working/stopped broadcasts for all sessions.

### Route Handling

```elixir
# handle_params/3 — activates canvas on route change and reads focus param
def handle_params(%{"id" => id_str} = params, _url, socket)
  # Parse canvas ID, validate, and activate
  # Parse optional focus param: focus_session_id = parse_int(params["focus"])
  # Assign focus_session_id which triggers phx-mounted span to dispatch canvas:focus-session event
  # Subscribes to all sessions in that canvas
  # Sets up window position defaults (cascade layout if not set)

def handle_params(_params, _url, socket)
  # No ID — redirect to first canvas or stay on empty canvas list
```

### Canvas Activation Helper

The `base_canvas_assigns/2` helper function (private) initializes the core canvas state to reduce duplication in `activate_canvas/2`. It sets all default canvas-related assigns:

```elixir
defp base_canvas_assigns(socket, canvas_id) do
  socket
  |> assign(:active_canvas_id, canvas_id)
  |> assign(:canvas_sessions, [])
  |> assign(:subscribed_session_ids, [])
  |> assign(:canvas_session_counts, %{})
  |> assign(:show_session_picker, false)
  |> assign(:filtered_sessions, [])
  |> assign(:session_search, "")
end
```

This helper is called by `activate_canvas/2` in both the connected and disconnected branches, eliminating the need to repeat these assignments twice and ensuring consistent initialization across different canvas activation paths.

**Focus parameter handling:**
- If `:focus_session_id` is assigned, a hidden `<span>` with `phx-mounted` is rendered
- On mount, the span dispatches a `canvas:focus-session` event with `{sessionId: @focus_session_id}` as detail
- This defers the focus event until after all windows are rendered in the DOM

## Keyboard Shortcuts & Controls

### Global Keyboard Handling
Keyboard events are managed via the `GlobalKeydown` hook registered in `assets/js/app.js`. This centralized hook:
- Listens for keyboard events at the window level
- Routes commands to appropriate handlers (canvas tab navigation, viewport panning, window minimization)
- Prevents duplicate handling across multiple pages (canvas, DM, etc.)
- Previously, CanvasLive had a catch-all event handler; now canvas-specific keydown events are handled by `GlobalKeydown` hook instead with explicit logging of unhandled events

### Keyboard Shortcuts Help
- **`?` key** — Toggle keyboard shortcuts help panel. Lazily creates modal overlay listing all canvas shortcuts.
  - **Closing:** Panel closes correctly on `Esc` key press or backdrop click via `style.display` manipulation
  - **Input guarding:** Typing in search boxes or form inputs does not trigger shortcuts (guarded by input type check)

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
- **`delete_canvas`** — Deletes canvas and delegates state cleanup to `handle_canvas_deleted/2` helper (refactored to flatten nesting). Updates canvas list, unsubscribes from sessions if active, and redirects to first canvas or empty list.

#### Window Management
- **`window_moved`** — Records x/y position delta; calls `Canvases.update_window_layout/2` with guards against hook destruction (pushEvent checked)
- **`window_resized`** — Records width/height delta; calls `Canvases.update_window_layout/2` with guards against hook destruction; server clamps width/height to 100px minimum to prevent corrupt layouts (2x2 px windows)
- **`remove_window`** — Removes session from canvas and unsubscribes from PubSub
- **`raise_window`** — Clicking any canvas window raises it to the front by updating z-order state in `CanvasLive`
- **`minimize_window`** — Minimize/hide toggle for individual windows (display:none). Minimized windows show unread indicator dot. Accessed via canvas rail flyout or URL parameter.
- **`canvas:focus-session` (JS event)** — When a session name is clicked in the canvas rail flyout or triggered via `?focus=` URL param, this event restores a minimized window, reconnects ResizeObserver, scrolls to bottom, raises to z-index 20, and persists the changes.

### Canvas Management Events

#### Toolbar Controls
- **`+` button** — Opens Add Session submenu directly via command palette (jumps to session picker without full search). Implemented via `palette:open-command` event with `commandId=canvas-add-session`.
- **Delete canvas button** — Wired event handler to delete canvas from toolbar.
- **Tidy button** — Cascades all windows into clean layout via `Canvases.tidy/1`, which resets positions and applies consistent spacing.

#### Session Picker Performance
- **`open_session_picker`** — Caps unscoped `Sessions.list_sessions()` calls with `Sessions.list_sessions_filtered(limit: 100)` to prevent loading all sessions into memory when opening the picker.
- **`search_sessions`** — Caps session list with `Sessions.list_sessions_filtered(limit: 50)` to avoid expensive queries when filtering results. Search filtering is applied client-side on the capped results.

#### Tab Operations
- **Double-click tab** — Rename canvas inline. Updates page title on successful rename.
- **Page title** — Shows active canvas name; resets on last canvas delete.

### PubSub Integration

The canvas page subscribes to multiple event streams for real-time synchronization:

**Global subscriptions (in `mount/3`):**
- `agent:working` — Subscribes to all agent working/stopped broadcasts globally; handlers trigger window refresh for any visible session

**Per-canvas subscriptions (in `activate_canvas/2`):**
```elixir
Events.subscribe_all(session_ids)  # Subscribe to events for all canvas sessions
```

**Event handlers for real-time updates:**
- `{:new_message, message}` — New message received in canvas session; calls `refresh_window` to update chat window
- `{:new_dm, message}` — Direct message received in a canvas session
- `{:session_status, session_id, status}` — Session status changed (working → stopped); triggers `refresh_window` to pulse indicator
- `{:agent_working, %{id: session_id}}` — Agent transitioned to working state (from `agent:working` subscription); triggers `refresh_window` to update pulse
- `{:agent_stopped, %{id: session_id}}` — Agent transitioned to stopped state (from `agent:working` subscription); triggers `refresh_window` to stop pulse
- `{:remove_canvas_window, cs_id}` — Remote signal to close a window (e.g., session cleanup)
- `{:canvas_session_added, session_id}` — Session added to canvas; updates session list and badge counts

**Belt-and-suspenders approach:** Both `session_status` and `agent:working`/`agent:stopped` trigger `refresh_window`, ensuring working indicator pulses regardless of which code path transitions the session status.

When events arrive, the handler calls `refresh_window/2` which calls `send_update/3` to update the `ChatWindowComponent` for that canvas session, keeping UI synchronized without full page refresh.

### TerminalWindowComponent
- **Located:** `lib/eye_in_the_sky_web/components/terminal_window_component.ex`
- **Role:** Renders draggable, resizable terminal windows for each canvas terminal
- **Props:** `ct` (CanvasTerminal struct with pos_x, pos_y, width, height), `pty_pid` (process ID of running PtyServer), `id` (component ID for routing)
- **Events:** Emits `pty_input`, `pty_resize`, `close` to parent `CanvasLive`; receives `pty_output` via `send_update` from parent
- **PTY Output Routing:** Routes PTY output to TerminalHook using scoped event names (`pty_output_<terminal_id>`) to prevent cross-terminal interference
- **Drag/Resize:** Uses TerminalWindowHook for drag/resize chrome, distinct event names from chat windows (`terminal_moved`/`terminal_resized`) to avoid ID collisions
- **Layout:** Title bar with terminal icon and close button; xterm.js container with ResizeObserver for responsive sizing

## JavaScript Hooks

### Canvas Layout Hook
- **File:** `assets/js/hooks/canvas_layout_hook.js`
- **Purpose:** Manages smart auto-layout button that adapts to session count, applies tiled positioning with precise edge padding and gaps, and exports localStorage persistence utilities
- **Layout constants:**
  - `EDGE = 8` — Pixel padding on all four edges of the canvas area in tiled layouts
  - `GAP = 8` — Pixel gap between adjacent windows in tiled layouts
- **Auto-layout algorithm (`computePositions()`):** Single button adapts to session count:
  - **1 session**: Full canvas (width=W-2*EDGE, height=H-2*EDGE)
  - **2 sessions**: Side-by-side columns; each `width = (W - GAP) / 2`, `height = H`
  - **3–4 sessions**: 2×2 grid; each window `width = (W - GAP) / 2`, `height = (H - GAP) / 2`
  - **>4 sessions**: Tiles first 4 in grid layout, cascades overflow windows below with 24px + i*32px offset, displays a dismissing banner: "Auto-layout supports up to 4 sessions — drag to arrange the rest"
- **Exports:**
  - `saveWindowLayout(csId, x, y, w, h, z)` — Persists window position, size, and optionally z-index to localStorage under key `cw_{csId}`
  - `loadWindowLayout(csId)` — Retrieves saved layout from localStorage, returns `{x, y, w, h, z}` or null
  - `saveWindowZ(csId, z)` — Saves z-index separately to existing layout entry (used when only stacking order changes)
- **Events:** Dispatches `canvas:layout-applied` custom event with detail `{x, y, w, h}` to notify ChatWindowHook of layout application and allow syncing of instance variables
- **Banner display:** `showCanvasBanner(message)` creates a dismissing overlay at bottom-center of canvas that auto-removes after 3 seconds

### Chat Window Hook
- **File:** `assets/js/hooks/chat_window_hook.js`
- **Purpose:** Handles window drag, resize, focus, minimize/maximize, snap-to-edge detection, localStorage persistence, autoscroll, and chat submission
- **Lifecycle:**
  - On mount: Loads position/size/z-index from localStorage via `loadWindowLayout(csId)`, guards against corrupt layouts (width/height < 120px), syncs instance variables, adds canvas:layout-applied event listener
  - During drag: Guards `pushEvent` against hook destruction; saves position to localStorage with 50ms debounce via `saveWindowLayout()`
  - During resize: Guards `pushEvent` against hook destruction; prevents window from resizing when a message is being sent; saves dimensions to localStorage with 400ms debounce via `saveWindowLayout()`
  - On focus: Saves z-index to localStorage via `saveWindowZ()` and dispatches `canvas:focus-session` event
  - On message send: Prevents window resize by temporarily disabling the resize handler
  - On minimize: Hides entire element (display:none); restores window visibility and ReizeObserver subscription on un-minimize
  - On maximize: Restores minimized window, reconnects ResizeObserver, scrolls to bottom, raises to front (z-index 20)
- **ResizeObserver:** Late-rendering content (LocalTime hooks, markdown) expands scrollHeight after initial scrollToBottom. Observer re-fires on content growth and scrolls to bottom when `_autoScroll` is true; re-observes children after each LiveView patch to track new message nodes.
- **Autoscroll fixes:** Post-mount force-scroll sequence (rAF + 150ms + 400ms timeouts) ensures initial scrollToBottom runs after late-rendering content expands; `beforeUpdate()`/`updated()` `_patching` flag prevents morphdom DOM patches from briefly resetting scrollTop which was falsely triggering scroll-up detection and disabling autoscroll.
- **Close button fix:** Drag handle's mousedown handler now returns early when target is a button element, preventing preventDefault from suppressing click events on the red close button.
- **Snap zones:** Configurable threshold (80px) for edge snapping; snap zones detected based on cursor proximity to viewport edges
- **Instance variables:** Maintains `_width`, `_height`, `_dragLeft`, `_dragTop`, `_zIndex`, `_userScrolled`, `_autoScroll`, `_patching` to track window state; these are synced when layout buttons dispatch canvas:layout-applied event
- **Z-Index Stacking:** When a window is focused (clicked), z-index updates to "20" and is persisted; all other windows reset to z-index "1". Z-index is restored from localStorage on mount, allowing window stacking order to persist across sessions.
- **Auto-scroll toggle:** Click button in chat window footer to enable/disable. When enabled (default), new messages scroll to bottom and ResizeObserver keeps tracking content growth. When disabled, stays in current position and shows unread message count pill; clicking pill re-enables auto-scroll and jumps to bottom.
- **Chat submission:** Submit listener is delegated to the window root element (not the textarea) to capture events from nested components like the chat window. Scrolling to bottom is deferred by one rAF to allow DOM reflow to complete before measuring scroll position.

### Terminal Hook
- **File:** `assets/js/hooks/terminal_hook.js`
- **Purpose:** Manages xterm.js terminal instance for canvas terminal windows
- **Scoping:** Identical to PtyHook but scopes all events to terminal ID via `data-terminal-id` attribute to support multiple terminals on same canvas
- **Events:**
  - Pushed to server: `pty_input` (user typing), `pty_resize` (terminal resized)
  - Received from server: `pty_output_<terminal_id>` (scoped event prevents cross-terminal data interference)
- **Lifecycle:**
  - On mount: Creates xterm.js Terminal, loads FitAddon and WebLinksAddon, opens in container element, sets up ResizeObserver for responsive sizing, establishes event handlers
  - On data/resize: Pushes events to server via pushEvent (same event names as TerminalLive, routed by phx-target)
  - On received output: Decodes base64-encoded data and writes to terminal
  - On destroy: Disconnects ResizeObserver, disposes Terminal instance
- **Theme:** Dark theme (zinc palette, background #09090b, foreground #e4e4e7)

### Terminal Window Hook
- **File:** `assets/js/hooks/terminal_window_hook.js`
- **Purpose:** Handles drag, resize, and z-index management for terminal windows on canvas
- **Distinct from ChatWindowHook:** Uses `data-terminal-id` and events `terminal_moved`/`terminal_resized` instead of `data-cs-id` and `window_moved`/`window_resized` to avoid ID collisions when both chat and terminal windows exist on same canvas
- **Features:**
  - Drag via data-drag-handle element (title bar)
  - Resize via ResizeObserver on the window element
  - Z-index management: clicking window raises it to front, manages both chat and terminal windows (`[data-chat-window], [data-terminal-window]`)
  - Focus ring added/removed during z-index transitions
  - Debounced persistence: 50ms for move, 400ms for resize
- **Instance variables:** `_zIndex`, `_dragLeft`, `_dragTop`, `_width`, `_height` restored after LiveView patches
- **Guards:** Checks for `_destroyed` flag before pushing events (guards against hook destruction race)

### Global Keydown Hook
- **File:** `assets/js/hooks/global_keydown.js`
- **Purpose:** Centralized keyboard event handling across all pages
- **Registration:** Added to `Hooks` object in `assets/js/app.js`
- **Prevents:** Duplicate keyboard handling in individual LiveViews (canvas, DM, etc.)

## Terminal Management

### Persisted Terminal Layout

Terminal windows are persisted in the `canvas_terminals` table with layout metadata:
- `canvas_id` — Canvas the terminal belongs to
- `pos_x`, `pos_y` — Top-left corner position (pixels)
- `width`, `height` — Window dimensions (clamped to 100px minimum on server, 120px on client)

When a canvas is activated, all persisted terminals are loaded and PTY servers are started.

### PTY Lifecycle in CanvasLive

**Starting terminals:**
1. `activate_canvas/2` calls `Canvases.list_terminals(canvas_id)` to load persisted terminals
2. For each terminal, `start_pty_for_terminal/1` creates a PtyServer with `subscriber_tag: terminal.id`
3. Server routes tagged PTY output to CanvasLive as `{:pty_output, terminal_id, data}`
4. Terminal ID and PtyServer PID are stored in `socket.assigns.terminal_pty_map`
5. TerminalWindowComponent is rendered with `id: "terminal-window-#{id}"`, `pty_pid: pid`, `ct: terminal`

**Running terminals:**
- TerminalHook manages xterm.js, sends input/resize events to server
- TerminalWindowComponent routes events to running PtyServer
- PtyServer output arrives as `{:pty_output, terminal_id, data}`
- CanvasLive dispatches via `send_update(TerminalWindowComponent, id: "terminal-window-#{terminal_id}", pty_output: data)`
- Component calls `push_event("pty_output_#{terminal_id}", ...)` to deliver to scoped hook listener

**Cleanup:**
- On canvas switch: All terminal PTYs stopped via `stop_all_terminals/1`
- On terminal close (close button): Component sends `{:remove_terminal_window, terminal_id}` message
- CanvasLive handler stops PTY server, deletes terminal from DB, removes from state
- On PTY exit: `{:pty_exited, terminal_id}` message triggers cleanup via `remove_terminal/2`

### Terminal Event Handlers

**`add_terminal`**
- Creates new CanvasTerminal record with default positions
- Starts PTY with `subscriber_tag: terminal.id`
- Adds to `canvas_terminals` and `terminal_pty_map`

**`terminal_moved`**
- Receives `{id, x, y}` from TerminalWindowHook drag handler
- Updates terminal layout via `Canvases.update_terminal_layout/2`

**`terminal_resized`**
- Receives `{id, w, h}` from TerminalWindowHook resize observer
- Updates terminal layout via `Canvases.update_terminal_layout/2`

**`{:pty_output, terminal_id, data}`**
- PubSub message from PtyServer (routed via `subscriber_tag`)
- Dispatches output to TerminalWindowComponent via `send_update`

**`{:pty_exited, terminal_id}`**
- PtyServer process exited abnormally
- Cleans up terminal state via `remove_terminal/2`

**`{:remove_terminal_window, terminal_id}`**
- Component requested close (user clicked close button)
- Stops PtyServer, deletes terminal from DB, removes from state

### Toolbar Support

Canvas toolbar includes **"Add Terminal" button** that:
- Creates new CanvasTerminal record
- Starts PTY server with subscriber_tag
- Adds to visible terminal list on canvas
- Button wired to `add_terminal` event handler

## Component Integration

### ChatWindowComponent
- **Located:** `lib/eye_in_the_sky_web/components/chat_window_component.ex`
- **Role:** Renders draggable, resizable windows for each canvas session
- **Props:** `canvas_session` (struct with pos_x, pos_y, width, height, session_id), `focus_session_id` (for cross-canvas focus highlighting)
- **Events:** Emits `window_moved`, `window_resized`, `remove_window`, `raise_window` to parent `CanvasLive`
- **Updates:** Receives `send_update` calls from PubSub event handlers (`:session_status`, `:agent_working`, `:agent_stopped`, `:new_message`) to re-render with latest message
- **Data attributes:** Window root has `data-session-id` attribute for session matching in focus events
- **Message rendering:** Uses iMessage-style bubble layout with provider icons, timestamps, and markdown via MarkdownMessage hook.
  - **User messages:** Right-aligned with base-200 background bubble and base-content text
  - **Agent messages:** Left-aligned, plain (no bubble) with base-content text
  - **Tool call messages:** Full-width, no bubble, centered; detected via body segment parsing (messages where all segments are tool_call types); capped at 85% max-width
  - **Tool result messages:** Centered, muted styling (base-300/40 background, base-content/40 text), capped at 90% max-width
  - **Regular DM-style messages:** Standard bubble layout with optional left-border styling for explicit DMs
- **Status indicator:** Provider logo (replaced status dot) displays in window header and animates with `animate-pulse` when session is working. Logo also appears in chat message body and pulses during working state.
- **Focus ring:** Active window shows visible focus ring to indicate interaction target.
- **Scroll behavior:** ChatWindowHook owns all scroll behavior. Auto-scroll enabled by default; disabled when user scrolls up and shows unread message count pill. Clicking pill re-enables auto-scroll and jumps to bottom. Automatically scrolls to bottom when user sends new message. Scroll-to-bottom is deferred by one rAF to allow DOM layout to stabilize before scrolling.

### AgentList Integration
- **File:** `lib/eye_in_the_sky_web/components/agent_list.ex`
- **Canvas Actions:** Session cards include two dropdown options:
  - "Add to Canvas" — Opens modal to select existing canvas
  - "Add to New Canvas" — Creates canvas and adds session in one action
- **Navigation:** Both trigger `push_navigate` to `/canvases/:id` after adding session

### Rail Menu Canvas Integration
- **File:** `lib/eye_in_the_sky_web/components/rail.ex` and `lib/eye_in_the_sky_web/components/rail/flyout.ex`
- **Canvas Section:** Rail includes a canvas section with an icon that navigates to `/canvases` when not on a canvas page
- **Flyout behavior:** When already on a canvas or chat page, the flyout locks open and displays:
  - List of all canvases with their nested sessions
  - Each session shows status indicator (dot with working animation) and session name
  - Session name click navigates to `/canvases/:id?focus=:session_id` to focus that window (raise to front and un-minimize)
  - Provider logo button dispatches `canvas:focus-session` event instead of navigating, enabling in-place focus within current canvas
  - DM button navigates to `/dm/:session_id` for direct messaging with that session
- **Navigation:** Clicking canvas icon on canvas/chat pages displays the flyout; clicking away closes it (unless locked). On other pages, canvas icon navigates directly to `/canvases`.
- **Sidebar Tab:** When viewing canvas, `:sidebar_tab` is set to `:canvas` to highlight active section

### AllProjectsSection Integration
- **File:** `lib/eye_in_the_sky_web/components/sidebar/all_projects_section.ex`
- **Canvas Tab:** Sidebar includes a "Canvas" tab that routes to `/canvases`

## Canvas Handlers Module

Located at: `lib/eye_in_the_sky_web/live/agent_live/canvas_handlers.ex`

This extracted module handles canvas-related events fired from the **AgentLive** page when users interact with "Add to Canvas" buttons on session cards:

### Event Handlers

**`add_to_canvas`**
- User selects existing canvas from dropdown
- Calls `Canvases.add_session/2` to link session to canvas
- Routes user to `/canvases/:id` with success flash

**`add_to_new_canvas`**
- User submits new canvas form with optional name
- If no name provided, generates default: `"Canvas {unix_timestamp}"`
- Creates canvas, adds session, routes to new canvas with success flash
- Flash message: `"Added to {canvas_name}"`

### New Canvas Button Implementation

The "New Canvas" button in the agent list dropdown uses **client-side JS commands** (`JS.hide`/`JS.show`/`JS.focus`) instead of server-side state toggling. This enables the button→form swap to work inside the frozen `phx-update="ignore"` dropdown subtree:

- **Button state**: `id="new-canvas-btn-{agent_id}"` visible by default
- **Form state**: `id="new-canvas-form-{agent_id}"` hidden (`style="display:none"`) until clicked
- **Interaction**: Clicking button dispatches:
  - `JS.hide(to: "#new-canvas-btn-#{@agent.id}")` — Hides button
  - `JS.show(to: "#new-canvas-form-#{@agent.id}")` — Shows form
  - `JS.focus(to: "#new-canvas-input-#{@agent.id}")` — Focus canvas name input
- **Submission**: Form submits `add_to_new_canvas` event via `phx-submit`

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
- `width`, `height` — Window dimensions (clamped to 100px minimum on server, 120px on client)

When canvas is activated, positions are restored from database. If both are 0, a cascade layout is applied (each window offset by `24 + i*32` pixels) to avoid stack overlap. **Three-layer minimum dimension defense prevents invisible windows:**
- **Server**: `update_window_layout/2` clamps width/height to 100px minimum
- **JS applyPosition**: Clamps before writing to DOM/localStorage (MIN_DIM=120)
- **JS ChatWindowHook.mounted**: Discards localStorage entries with width/height < 120px; layout button bails early if canvas area < 200px in either dimension

**localStorage Persistence:**
In addition to database persistence, window layout and z-index are persisted to browser localStorage for immediate restoration across page reloads and browser sessions:
- **Storage key**: `cw_{csId}` — Each canvas session has its own localStorage entry containing `{x, y, w, h, z}`
- **Position & size**: `saveWindowLayout(csId, x, y, w, h, z?)` stores or updates all fields; `loadWindowLayout(csId)` retrieves them
- **Z-index only**: `saveWindowZ(csId, z)` updates z-index without touching position/size (used when only stacking changes)
- **Restoration**: `ChatWindowHook` calls `loadWindowLayout(csId)` on mount, applying saved position, size, and z-index before rendering
- **Sync events**: When layout buttons (2up, 4up) apply preset positions, they dispatch a `canvas:layout-applied` custom event so `ChatWindowHook` can sync its instance variables (`_width`, `_height`, `_dragLeft`, `_dragTop`) for drag/resize tracking
- **Drag/Resize debounce**: Window moves are saved with 50ms debounce; resizes with 400ms debounce to avoid excessive localStorage writes

**Z-Index Lifecycle:**
- **Mount**: Restored from localStorage if available (`saved.z`), otherwise defaults to `"1"`
- **Focus**: When user clicks window to focus, z-index updates to `"20"` and is persisted via `saveWindowZ()`
- **Minimize/Maximize**: Z-index is updated and persisted when toggling window state
- **Defocusing**: When a window is focused, all other windows reset to z-index `"1"` and are persisted
- **Focus parameter**: URL param `?focus=:session_id` dispatches `canvas:focus-session` event which also raises the window to z-index `"20"` and persists it

## Navigation Flow

### Accessing Canvas

1. **From Agent List**
   - Session card dropdown → "Add to Canvas"
   - Navigates to `/canvases/:id` after adding

2. **From Sidebar**
   - Click "Canvas" tab in sidebar
   - Routes to `/canvases` (redirects to first canvas if available)
   - Clicking a session name in the canvas rail navigates to `/canvases/:id?focus=:session_id` to focus that window

3. **Direct URL**
   - User navigates to `/canvases` or `/canvases/:id` directly
   - Optional `?focus=:session_id` parameter focuses (brings to front) the specified canvas session window

### Focus Parameter

The `?focus=` query parameter enables cross-canvas window focusing via a deferred focus event:
- **Rail navigation:** Clicking a session name in the canvas rail flyout navigates to `/canvases/:id?focus=:session_id`
- **CanvasLive handling:** `handle_params/3` parses the `focus` param and assigns it as `:focus_session_id`
- **Deferred focus event:** Renders a hidden span with `phx-mounted` attribute that dispatches `canvas:focus-session` event with `{sessionId: @focus_session_id}` after all windows are rendered in DOM
- **ChatWindowHook listener:** Listens for `canvas:focus-session` event, matches the window via `data-session-id` attribute, and raises the matching window to z-index `"20"`, un-minimizes it, and persists the z-index to localStorage
- **Component prop:** The `:focus_session_id` is also passed to ChatWindowComponent for potential visual highlighting or focus ring indication

### Canvas-to-Agent Navigation

While canvas page is standalone, chat windows display session messages. The canvas rail provides two distinct interactions on each session:

- **Session name click**: Navigates to `/canvases/:id?focus=:session_id` to focus (bring to front and un-minimize) that window within the canvas, or navigates to `/canvases/:id` if clicking from another canvas
- **Provider logo click** (in rail): Dispatches `canvas:focus-session` event when already on a canvas page, raising the window to z-index 20 and un-minimizing without navigation. On non-canvas pages, the logo navigates to the canvas page.
- **DM button click**: Navigates directly to `/dm/:session_id` to open direct messaging with that session

Clicking a session name or message link within the canvas should route back to `/agents/:id` (AgentLive) for full session context (code history, status details, etc.).

## Key Architectural Patterns

### Route Branching vs Action Atoms
- `CanvasLive` defines two routes (`:index` and `:show`) but doesn't use action-specific callbacks
- Logic is branched in `handle_params/3` based on `id` param presence
- This pattern avoids action-based render clauses and keeps state management centralized

### Extracted Handlers
- `CanvasHandlers` module extracts canvas-related event logic from AgentLive
- Keeps AgentLive focused on session list and agent card UI
- Enables canvas operations (add, create) from session context
- `handle_canvas_deleted/2` is a private helper in CanvasLive that handles state cleanup when a canvas is deleted (removing from list, unsubscribing from sessions, redirecting). Extracted to flatten nested case statements in the event handler.

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
- **Window positioning:** Cascade layout applied by default if window positions not previously persisted. Auto-layout button adapts to session count (1: full canvas, 2: columns, 3-4: grid, >4: tiles first 4 + cascade).

### Status & Visual Feedback
- **Working status indicator** — Session status badge animates with continuous pulse effect (`animate-pulse`) when session is in `working` state; provider icon in message body also pulses during working state
- **Status badge styling** — `session_status_class/1` maps session statuses to badge styles:
  - `working` → badge-primary (animated pulse)
  - `idle` → badge-ghost (no activity)
  - `waiting` → badge-warning (paused, can resume)
  - `completed` → badge-success (finished)
  - `failed` → badge-error (error state)
  - `compacting` → badge-warning (in progress)
  - `archived` → badge-ghost (inactive)
- **Unread indicators** — Minimized windows show unread message dot; unread count pill appears when auto-scroll is disabled and new messages arrive
- **Session added badge** — Refresh badge displayed on add_session to provide visual feedback that canvas was updated
- **Window focus ring** — Active window displays a visible focus ring to indicate interaction target

## Related Files

- **Routes:** `lib/eye_in_the_sky_web/router.ex` (canvas routes in `:app` live_session)
- **LiveView:** `lib/eye_in_the_sky_web/live/canvas_live.ex`
- **Handlers:** `lib/eye_in_the_sky_web/live/agent_live/canvas_handlers.ex`
- **Components:**
  - `lib/eye_in_the_sky_web/components/chat_window_component.ex` (chat message windows)
  - `lib/eye_in_the_sky_web/components/terminal_window_component.ex` (terminal windows)
  - `lib/eye_in_the_sky_web/components/rail.ex` and `lib/eye_in_the_sky_web/components/rail/flyout.ex` (canvas rail section)
  - `lib/eye_in_the_sky_web/components/agent_list.ex` (canvas buttons)
  - `lib/eye_in_the_sky_web/components/sidebar/all_projects_section.ex` (canvas tab)
- **JavaScript Hooks:**
  - `assets/js/hooks/canvas_layout_hook.js` (layout presets)
  - `assets/js/hooks/chat_window_hook.js` (chat window drag/resize, focus, scroll)
  - `assets/js/hooks/terminal_hook.js` (xterm.js terminal instance management)
  - `assets/js/hooks/terminal_window_hook.js` (terminal window drag/resize chrome)
  - `assets/js/hooks/canvas_tab_hook.js` (keyboard shortcuts)
  - `assets/js/hooks/global_keydown.js` (centralized keyboard handling)
- **Schema:**
  - `lib/eye_in_the_sky/canvases/canvas.ex` (Canvas schema)
  - `lib/eye_in_the_sky/canvases/canvas_session.ex` (CanvasSession join schema)
  - `lib/eye_in_the_sky/canvases/canvas_terminal.ex` (CanvasTerminal schema)
- **Context:** `lib/eye_in_the_sky/canvases.ex` (Ecto context with terminal CRUD)
- **Terminal:** `lib/eye_in_the_sky/terminal/pty_server.ex` (PTY server with subscriber_tag routing)
- **PubSub:** `lib/eye_in_the_sky/events.ex` (subscription logic)
