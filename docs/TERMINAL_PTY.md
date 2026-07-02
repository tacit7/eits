# Terminal PTY System

Full-stack embedded terminal built on erlexec + xterm.js. Three surfaces exist:

- **`/terminal`** — standalone single-terminal LiveView page (`TerminalLive`)
- **Canvas** — draggable/resizable terminal windows on the canvas page, multiple per canvas (`TerminalWindowComponent`)
- **DM Sessions** — optional PTY-backed terminal mode in DM conversations, toggled via `dm_use_pty` setting (`DmLive`)

All surfaces share `PtyServer` and `PtySupervisor`. The wiring layer differs.

---

## Architecture Overview

### Standalone Terminal (`/terminal`)

```
Browser (xterm.js / PtyHook)
    │  keystrokes → pushEvent("pty_input")
    │  pty_output ← handleEvent("pty_output")
    ▼
TerminalLive (LiveView)
    │  handle_event("pty_input") → PtyServer.write/2
    │  handle_info({:pty_output, data}) → push_event("pty_output")
    ▼
PtyServer (GenServer)
    │  :exec.send(os_pid, data)
    │  {:stdout, os_pid, data} → forwarded to TerminalLive
    ▼
erlexec → bash (OS process)
```

### Canvas Terminal Windows

```
Browser (xterm.js / TerminalHook)
    │  keystrokes → pushEventTo(el, "pty_input")   ← must use pushEventTo
    │  pty_output_<id> ← handleEvent("pty_output_<id>")
    ▼
TerminalWindowComponent (LiveComponent)
    │  handle_event("pty_input") → PtyServer.write/2
    │  update(%{pty_output: data}) → push_event("pty_output_<ct.id>")
    ▲
CanvasLive (LiveView, parent)
    │  handle_info({:pty_output, id, data})
    │    → send_update(TerminalWindowComponent, id: "terminal-window-<id>", pty_output: data)
    │  handle_info({:pty_exited, id}) → remove_terminal
    │  handle_info({:remove_terminal_window, id}) → PtyServer.stop, delete DB row
    ▼
PtyServer (GenServer, subscriber_tag: ct.id)
    │  {:stdout, os_pid, data} → send(subscriber, {:pty_output, tag, data})
    ▼
erlexec → bash (OS process)
```

**Key difference:** Canvas terminals use `subscriber_tag` so `CanvasLive` can route output from multiple PTYs to the correct `TerminalWindowComponent` by matching on the tag.

---

## Files

| File | Role |
|------|------|
| `lib/eye_in_the_sky/terminal/pty_server.ex` | GenServer owning one PTY; `subscriber_tag` for multi-terminal routing |
| `lib/eye_in_the_sky/terminal/pty_supervisor.ex` | DynamicSupervisor for PtyServer instances |
| `lib/eye_in_the_sky/agents/agent_manager.ex` | `create_pty_session/1` and `create_agent/1`; session creation entry point |
| `lib/eye_in_the_sky_web/live/terminal_live.ex` | Standalone LiveView (`/terminal`) |
| `lib/eye_in_the_sky_web/live/canvas_live.ex` | Canvas LiveView; manages terminal lifecycle, PTY map |
| `lib/eye_in_the_sky_web/live/dm_live.ex` | DM LiveView; optional PTY mode via `dm_use_pty` setting |
| `lib/eye_in_the_sky_web/live/agent_live/index_actions.ex` | Session creation actions; branches on `dm_use_pty` |
| `lib/eye_in_the_sky_web/live/project_live/sessions/actions.ex` | Session creation actions; branches on `dm_use_pty` |
| `lib/eye_in_the_sky_web/live/workspace_live/sessions/actions.ex` | Session creation actions; branches on `dm_use_pty` |
| `lib/eye_in_the_sky_web/components/terminal_window_component.ex` | LiveComponent for canvas terminal windows |
| `lib/eye_in_the_sky/canvases/canvas_terminal.ex` | Ecto schema for persisted terminal layout |
| `lib/eye_in_the_sky/settings.ex` | Settings schema; defines `dm_use_pty` default |
| `priv/repo/migrations/…add_canvas_terminals.exs` | Migration: canvas_terminals table |
| `assets/js/hooks/pty_hook.js` | xterm.js hook for standalone terminal (pushEvent to LiveView) |
| `assets/js/hooks/terminal_hook.js` | xterm.js hook for canvas windows (pushEventTo LiveComponent) |
| `assets/js/hooks/terminal_window_hook.js` | Drag/resize chrome for canvas terminal windows |
| `test/eye_in_the_sky/terminal/pty_server_test.exs` | Integration regression: echo smoke test |

---

## Dependency

```elixir
# mix.exs
{:erlexec, "~> 2.0"}
# pinned to 2.2.4 in mix.lock
```

erlexec manages OS processes via a C port driver. Supports PTY allocation, stdin/stdout piping, process monitoring, and window resize (`SIGWINCH`).

---

## PtyServer — `lib/eye_in_the_sky/terminal/pty_server.ex`

### Lifecycle

```
PtySupervisor.start_pty(opts)
    → DynamicSupervisor.start_child(PtyServer, opts)
    → PtyServer.init/1
        → Process.monitor(subscriber_pid)
        → :exec.run(shell_cmd, exec_opts)
        → :exec.winsz(os_pid, rows, cols)
    → {:ok, pid}
```

### Options

```elixir
PtySupervisor.start_pty(
  subscriber: pid,          # required: process receiving {:pty_output, data} messages
  subscriber_tag: term,     # optional: when set, output is {:pty_output, tag, data}
  cols: 220,                # default: 220
  rows: 50                  # default: 50
)
```

**`subscriber_tag`** — enables multi-terminal setups. `CanvasLive` passes `ct.id` (integer) as the tag so it can pattern-match on `{:pty_output, id, data}` and route each chunk to the right `TerminalWindowComponent`.

Without a tag: `{:pty_output, data}` (backward-compatible, used by `TerminalLive`).
With a tag: `{:pty_output, tag, data}`.

### State

```elixir
%{
  subscriber: pid,    # process receiving output messages
  tag: term | nil,   # subscriber_tag (nil = untagged mode)
  os_pid: integer,   # OS PID of the bash process
  cols: integer,
  rows: integer
}
```

### erlexec opts — the working configuration

```elixir
env = [
  {"TERM", "xterm-256color"},
  {"LANG", "en_US.UTF-8"},
  {"HOME", System.get_env("HOME", "/tmp")},
  {"PATH", System.get_env("PATH", "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin")},
  {"SHELL", @shell_bin},
  {"USER", System.get_env("USER", "user")},
  {"LOGNAME", System.get_env("LOGNAME", System.get_env("USER", "user"))},
  {"COLORFGBG", "15;0"}
]

opts = [
  :stdin,             # CRITICAL: without this, stdin defaults to /dev/null
  {:stdout, self()},  # deliver PTY output as {:stdout, os_pid, data}
  {:stderr, :stdout}, # merge stderr into stdout stream
  :pty,               # allocate a PTY
  :pty_echo,          # REQUIRED: enable ECHO termios flag so typed chars echo back
  {:env, env},
  :monitor
]
```

**Every option is load-bearing.** See the gotchas section.

#### Environment Variables

**`COLORFGBG`** — Hint to vim about background color when OSC 11 is unavailable. Format is `"foreground;background"` with ANSI color indices (15=white, 0=black). Without it, vim may guess wrong and colorscheme appearance may be inverted or washed out.

Other variables (`TERM`, `LANG`, etc.) are standard and follow conventional PTY setup.

### Shell command

```elixir
shell_cmd = [@shell_bin, "--norc", "--noprofile", "-i"]
```

- **List form** — avoids erlexec's `m_shell=true` C port flag
- `--norc --noprofile` — skip user init files
- `-i` — force interactive mode

### Message handlers

| Message | Source | Action |
|---------|--------|--------|
| `{:write, data}` cast | subscriber | `:exec.send(os_pid, data)` |
| `{:resize, cols, rows}` cast | subscriber | `:exec.winsz(os_pid, rows, cols)` |
| `{:stdout, os_pid, data}` | erlexec | `send(sub, {:pty_output, data})` or `{:pty_output, tag, data}` |
| `{:DOWN, os_pid, :process, _lwp, :normal}` | erlexec | bash exit 0 → notify, stop |
| `{:DOWN, _ref, :process, _pid, {:exit_status, n}}` | erlexec | bash exit N → notify, stop |
| `{:DOWN, _ref, :process, subscriber_pid, _}` | OTP monitor | LiveView died → stop |

Exit notification: `send(sub, :pty_exited)` (no tag) or `send(sub, {:pty_exited, tag})` (tagged).

---

## PtySupervisor — `lib/eye_in_the_sky/terminal/pty_supervisor.ex`

`DynamicSupervisor` with `restart: :temporary` children. A crashed PtyServer is NOT restarted — subscriber receives `:pty_exited` / `{:pty_exited, tag}`.

---

## Standalone Terminal — `TerminalLive`

Route: `GET /terminal`.

### Mount

```elixir
if connected?(socket) do
  {:ok, pty_pid} = PtySupervisor.start_pty(subscriber: self(), cols: 220, rows: 50)
  assign(socket, pty_pid: pty_pid)
end
```

`connected?` guard — mount runs twice in LiveView. Only start the PTY after WebSocket connects.

### Events / Messages

| Event | Handler |
|-------|---------|
| `pty_input` | `PtyServer.write(pid, data)` |
| `pty_resize` | `PtyServer.resize(pid, cols, rows)` |
| `{:pty_output, data}` | `push_event("pty_output", %{data: Base64.encode64(data)})` |
| `:pty_exited` | `assign(pty_pid: nil)`, push exit message |

### Terminate

```elixir
def terminate(_reason, %{assigns: %{pty_pid: pid}}) when is_pid(pid) do
  PtyServer.stop(pid)
end
```

---

## Canvas Terminal Windows

### Database

`canvas_terminals` table stores layout per terminal window:

```elixir
schema "canvas_terminals" do
  belongs_to :canvas, Canvas
  field :pos_x,  :integer, default: 0
  field :pos_y,  :integer, default: 0
  field :width,  :integer, default: 620
  field :height, :integer, default: 400
  timestamps()
end
```

Context functions in `EyeInTheSky.Canvases`:
- `list_terminals(canvas_id)` — load all terminals for a canvas
- `create_terminal(canvas_id, attrs)` — insert new row
- `delete_terminal(id)` — remove row
- `update_terminal_layout(id, attrs)` — persist drag/resize

### CanvasLive

Assigns:

```elixir
:canvas_terminals   # [%CanvasTerminal{}, ...]
:terminal_pty_map   # %{ct.id => pty_pid}
```

On canvas activate: loads terminals from DB, starts one `PtyServer` per terminal with `subscriber_tag: ct.id`.

On canvas switch: stops all running PTYs via `base_canvas_assigns/2`, which iterates `terminal_pty_map` and calls `PtyServer.stop/1`.

#### Event handlers

| Event | Action |
|-------|--------|
| `"add_terminal"` | `create_terminal`, `start_pty(subscriber_tag: ct.id)`, update assigns |
| `"terminal_moved"` | `update_terminal_layout(id, %{pos_x: x, pos_y: y})` |
| `"terminal_resized"` | `update_terminal_layout(id, %{width: w, height: h})` |

Note: terminal window events use `"terminal_moved"` / `"terminal_resized"` — **not** `"window_moved"` / `"window_resized"`. This avoids ID collisions with chat windows (which share the same canvas and the same event handler, but use `canvas_session` IDs from a different table).

#### Info handlers

| Message | Action |
|---------|--------|
| `{:pty_output, id, data}` | `send_update(TerminalWindowComponent, id: "terminal-window-#{id}", pty_output: data)` |
| `{:pty_exited, id}` | `remove_terminal(socket, id)` |
| `{:remove_terminal_window, id}` | `PtyServer.stop(pid)`, `delete_terminal(id)`, `remove_terminal(socket, id)` |

### TerminalWindowComponent

LiveComponent (`id: "terminal-window-<ct.id>"`).

`update/2` has two clauses:

```elixir
# PTY output path — push to xterm.js hook
def update(%{pty_output: data} = assigns, socket) do
  {:ok,
   socket
   |> assign(assigns)
   |> push_event("pty_output_#{socket.assigns.ct.id}", %{data: Base.encode64(data)})}
end

# Normal assign update
def update(assigns, socket) do
  {:ok, assign(socket, assigns)}
end
```

`handle_event("close", ...)` sends `{:remove_terminal_window, socket.assigns.ct.id}` to the parent LiveView (integer, not component id string).

### JS Hooks

#### `TerminalHook` — `assets/js/hooks/terminal_hook.js`

Mounted on the xterm.js container inside `TerminalWindowComponent`. Uses **`pushEventTo`** (not `pushEvent`) to target the LiveComponent:

```js
term.onData(data => {
  this.pushEventTo(this.el, "pty_input", { data })
})

term.onResize(({ cols, rows }) => {
  this.pushEventTo(this.el, "pty_resize", { cols, rows })
})
```

Receives output on a scoped event name:

```js
const terminalId = this.el.dataset.terminalId   // ct.id integer
this.handleEvent(`pty_output_${terminalId}`, ({ data }) => {
  term.write(Uint8Array.from(atob(data), c => c.charCodeAt(0)))
})
```

`data-terminal-id={@ct.id}` on the div ensures the JS event name matches the Elixir `push_event` name.

#### `TerminalWindowHook` — `assets/js/hooks/terminal_window_hook.js`

Drag + resize + z-index chrome. Mirrors `ChatWindowHook` but pushes `"terminal_moved"` / `"terminal_resized"` events (distinct names from chat windows). Restores JS-tracked position/size in `updated()` after LiveView patches the style attribute.

---

## DM PTY Mode — `DmLive`

DM sessions can optionally use a PTY terminal instead of the text-message interface. This is controlled via the `dm_use_pty` setting (default: `false`).

### Settings Integration

The `dm_use_pty` toggle is stored in the settings schema:

```elixir
# lib/eye_in_the_sky/settings.ex
@defaults %{
  ...
  "agent_notifications" => "false",
  "dm_use_pty" => "false"   # Terminal section in UI
}
```

### UI

A new "Terminal" section in `/settings` → General tab exposes the toggle:

```
Terminal
├─ Use PTY terminal in DM sessions (checkbox)
└─ Note: "Requires a page reload to take effect"
```

### DmLive Integration

`DmLive` checks the setting at mount time and conditionally subscribes to PTY output:

```elixir
use_pty = EyeInTheSky.Settings.get_boolean("dm_use_pty")

socket =
  if connected?(socket) && use_pty,
    do: subscribe_dm_pty(socket, session.uuid),
    else: socket
```

When `use_pty` is `true` and the socket is connected, the DM page subscribes to PTY messages for the session. When `false`, the page displays the standard text message interface.

**Page reload requirement:** Changing this setting does not hot-reload the DM page — the user must manually refresh to switch modes. This is because mount-time subscription setup happens once at page load.

### Session Creation

Three session creation call sites — `AgentLive.IndexActions`, `ProjectLive.Sessions.Actions`, and `WorkspaceLive.Sessions.Actions` — all branch on `dm_use_pty` when spawning a new session:

```elixir
create_fn =
  if EyeInTheSky.Settings.get_boolean("dm_use_pty"),
    do: &AgentManager.create_pty_session/1,
    else: &AgentManager.create_agent/1

case create_fn.(opts) do
  ...
end
```

When `dm_use_pty=false` (the default), `create_agent/1` is used (SDK/messages mode). When `true`, `create_pty_session/1` is used. Previously all three callers unconditionally called `create_pty_session/1`, which meant the DM page was always blank for newly created sessions because `DmLive` only subscribes to PTY output when `dm_use_pty=true`.

**`create_pty_session` working directory fix (`AgentManager`):** The launch command issued to the PTY now uses `agent.git_worktree_path` as the working directory, falling back to `opts[:project_path]` when `git_worktree_path` is nil:

```elixir
working_path = agent.git_worktree_path || opts[:project_path]
cd_part = if working_path && working_path != "", do: "cd #{working_path} && ", else: ""
launch_cmd = "#{cd_part}claude --session-id #{session.uuid}\n"
```

Previously `opts[:project_path]` was always used, which is the base project directory. This ignored any agent-specific git worktree path resolved by `RecordBuilder` after creating the worktree. The non-PTY path (`create_agent/1`, SDK/messages mode) was not affected by this bug.

### Mode Contrast

| Mode | Interface | Behavior |
|------|-----------|----------|
| Text (default) | Web chat UI | Messages display in a list, send button, composer |
| PTY (`dm_use_pty=true`) | xterm.js terminal | Raw terminal output/input, persistent bash session if available |

---

## Data Flow — Canvas Terminal (complete)

```
User types "ls" in canvas terminal window
│
├─ TerminalHook: term.onData("l")
├─ pushEventTo(this.el, "pty_input", { data: "l" })   ← targets LiveComponent
├─ [WebSocket]
├─ TerminalWindowComponent.handle_event("pty_input", %{"data" => "l"})
├─ PtyServer.write(pid, "l")
├─ :exec.send(os_pid, "l")
│
│  PTY ECHO (termios ECHO flag):
├─ erlexec delivers {:stdout, os_pid, <<"l">>}
├─ PtyServer → send(canvas_live_pid, {:pty_output, ct.id, <<"l">>})
├─ CanvasLive.handle_info → send_update(TerminalWindowComponent, pty_output: <<"l">>)
├─ TerminalWindowComponent.update → push_event("pty_output_42", %{data: "bA=="})
├─ [WebSocket]
├─ TerminalHook.handleEvent("pty_output_42") → term.write(Uint8Array[108])
└─ xterm.js renders "l"
```

---

## erlexec Gotchas (all fixed)

Five load-bearing bugs fixed in commits e7ed7f1b, a6c076cf, 3effe5cc. Each must be correct for terminals to work.

### 1. String command → `m_shell=true` → bash wrapped and exits

String form triggers `m_shell=true` in erlexec's C port, wrapping the command as `$SHELL -c "..."`. This runs bash as a sub-shell of sh -c, which exits immediately. The outer shell exits, killing bash before it can accept input.

**Fix:** Pass command as a **list** (not a string): `[@shell_bin, "--norc", "--noprofile", "-i"]`

**Diagnostic:** `{:DOWN, os_pid, :process, pid, :normal}` with zero stdout messages immediately after spawn (no prompt bytes).

---

### 2. Missing `:stdin` → stdin is `/dev/null` → bash exits on EOF

Without `:stdin`, erlexec initializes `stream_fd[STDIN_FILENO]` to `/dev/null`. Bash reads EOF and exits immediately. `:exec.send/2` silently no-ops.

**Fix:** Add `:stdin` as first element in opts.

**Diagnostic:** Bash prompt bytes appear (~292b) then immediate clean exit.

---

### 3. Missing `:normal` exit handler → clean bash exit unhandled

When bash exits with code 0, erlexec sends `{:DOWN, os_pid, :process, lwp_pid, :normal}` (not `{:exit_status, 0}`). Non-zero exits use the `{:exit_status, code}` form. Without a `:normal` handler, the exit message is unmatched and PtyServer lingers until the parent LiveView dies.

**Fix:**
```elixir
def handle_info({:DOWN, os_pid, :process, _lwp, :normal}, %{os_pid: os_pid} = state) do
  send(state.subscriber, :pty_exited)
  {:stop, :normal, state}
end
```

The `os_pid` pin in both message and state guard distinguishes this from the LiveView monitor's `:DOWN`.

---

### 4. Missing `:pty_echo` → typed characters invisible

erlexec allocates PTYs with the `ECHO` termios flag **off** by default. Input reaches bash (commands execute) but characters are never echoed back to xterm.js.

**Fix:** Add `:pty_echo` to opts.

**Diagnostic:** Press Enter — new prompt appears (bash is running), but typed characters never render.

---

### 5. `pushEvent` vs `pushEventTo` in LiveComponent hooks

`this.pushEvent(...)` in a LiveView hook always routes to the **parent LiveView**. When the hook element lives inside a LiveComponent (with `phx-target={@myself}`), input events need to target the component.

**Fix:** `this.pushEventTo(this.el, "pty_input", { data })` — routes via the `phx-target` attribute on `this.el`.

**Diagnostic:** Typing does nothing. No `pty_input` events reach the component. The parent LiveView logs an unhandled event warning.

---

## PtyHook vs TerminalHook

| | `PtyHook` | `TerminalHook` |
|--|-----------|----------------|
| Used by | `TerminalLive` (standalone) | `TerminalWindowComponent` (canvas) |
| Event target | `pushEvent` → LiveView | `pushEventTo(this.el)` → LiveComponent |
| Output event | `"pty_output"` (shared) | `"pty_output_<ct.id>"` (scoped per terminal) |
| Multiple instances | No (one per page) | Yes (many per canvas) |

---

## Theme Handling and xterm.js Configuration

### Theme Updates and escape sequence injection

**Previous behavior (broken):** When the DaisyUI theme changed, a `MutationObserver` on the document root would:
1. Update xterm.js theme options with new colors
2. Write `\x1b[H\x1b[2J` (cursor-home + erase-display) to force a redraw

The escape sequence injection was intended to align xterm.js's buffer redraw with Ink/Claude Code TUI re-renders, but it had a critical side effect: when vim was open in the PTY, these escape sequences landed in vim's input stream and corrupted its internal cursor tracking and redraw state.

**Current behavior (fixed):** The `MutationObserver` now updates only the xterm.js theme options and does NOT write escape sequences. xterm.js automatically re-renders the buffer with new colors when its `options.theme` is updated. This is safe for vim and other TUI applications that expect a clean input stream.

**Code location:** `assets/js/hooks/pty_hook.js`, `PtyHook.mount()`, `this._themeObserver`.

### Background color detection for vim

vim detects terminal background color using two methods:
1. Query OSC 11 (Operating System Command 11: "what is your background color?")
2. Check the `COLORFGBG` environment variable

When OSC 11 is unavailable or unsupported, vim falls back to `COLORFGBG`. Without it, vim may guess wrong and colorscheme appearance breaks (inversion, washed-out colors).

**Current setup:** `PtyServer` sets `COLORFGBG=15;0` in the bash process environment:
- `15` = ANSI white (foreground)
- `0` = ANSI black (background)

This correctly hints dark background mode to vim. See `lib/eye_in_the_sky/terminal/pty_server.ex`, `build_env/0`.

---

## Testing

```bash
mix test test/eye_in_the_sky/terminal/pty_server_test.exs
```

- Starts a PtyServer, drains initial prompt
- Sends `"echo pty_echo_smoke\n"` via `PtyServer.write/2`
- Asserts echoed input and command output both appear

Tests `async: false` — PTY tests touch OS file descriptors, must not run concurrently.

---

## Window Resize Flow

```
Container size changes
  → ResizeObserver → fitAddon.fit()
  → term.onResize({ cols, rows })
  → pushEvent / pushEventTo "pty_resize"
  → PtyServer.resize → :exec.winsz(os_pid, rows, cols)
```

**Note:** `:exec.winsz(os_pid, rows, cols)` — rows first, cols second (opposite of conventional ordering).

---

## Supervision and Cleanup

```
Application
└── PtySupervisor (DynamicSupervisor)
    └── PtyServer (restart: :temporary)
        └── bash (OS process)
```

**On LiveView disconnect:**
1. `TerminalLive.terminate/2` → `PtyServer.stop/1`
2. `PtyServer.terminate/2` → `:exec.stop(os_pid)`
3. bash receives SIGHUP and exits

**On canvas switch (CanvasLive):**
`base_canvas_assigns/2` iterates `terminal_pty_map` and stops all PTYs before loading the new canvas.

**On terminal close (canvas):**
`{:remove_terminal_window, id}` → `PtyServer.stop(pid)` → `delete_terminal(id)` → remove from assigns.

**On bash exit:**
1. erlexec sends `:DOWN` message
2. PtyServer notifies subscriber (`:pty_exited` or `{:pty_exited, tag}`)
3. `PtyServer.terminate/2` → `:exec.stop` (no-op, already dead)
4. LiveView/CanvasLive handles `:pty_exited`

---

## Known Limitations

- **No session persistence** — navigating away or closing the window kills bash. Working directory and history are lost.
- **No scrollback sync** — scrollback buffer is client-side only. Page reload loses history.
- **bash only** — no shell selection UI.
- **One PTY per `PtyServer`** — each terminal window is its own GenServer and bash process.
