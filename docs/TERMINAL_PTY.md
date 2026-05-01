# Terminal PTY System

Full-stack embedded terminal built on erlexec + xterm.js. Two surfaces exist:

- **`/terminal`** — standalone single-terminal LiveView page (`TerminalLive`)
- **Canvas** — draggable/resizable terminal windows on the canvas page, multiple per canvas (`TerminalWindowComponent`)

Both surfaces share `PtyServer` and `PtySupervisor`. The wiring layer differs.

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
| `lib/eye_in_the_sky_web/live/terminal_live.ex` | Standalone LiveView (`/terminal`) |
| `lib/eye_in_the_sky_web/live/canvas_live.ex` | Canvas LiveView; manages terminal lifecycle, PTY map |
| `lib/eye_in_the_sky_web/components/terminal_window_component.ex` | LiveComponent for canvas terminal windows |
| `lib/eye_in_the_sky/canvases/canvas_terminal.ex` | Ecto schema for persisted terminal layout |
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
opts = [
  :stdin,             # REQUIRED: without this, stdin defaults to /dev/null
  {:stdout, self()},  # deliver PTY output as {:stdout, os_pid, data}
  {:stderr, :stdout}, # merge stderr into stdout stream
  :pty,               # allocate a PTY
  :pty_echo,          # REQUIRED: enable ECHO termios flag so typed chars echo back
  {:env, env},
  :monitor
]
```

**Every option is load-bearing.** See the gotchas section.

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

Five confirmed bugs. All must be present for terminals to work correctly.

### 1. String command → `m_shell=true` → bash exits immediately

String form triggers `m_shell=true` in erlexec's C port, wrapping the command as `$SHELL -c "..."`. Outer shell exits immediately.

**Fix:** Pass command as a list: `[@shell_bin, "--norc", "--noprofile", "-i"]`

**Diagnostic:** `{:DOWN, os_pid, :process, pid, :normal}` with zero stdout messages immediately after spawn.

---

### 2. Missing `:stdin` → stdin is `/dev/null` → bash exits on EOF

Without `:stdin`, erlexec initializes `stream_fd[STDIN_FILENO]` to `/dev/null`. Bash reads EOF and exits immediately. `:exec.send/2` silently no-ops.

**Fix:** Add `:stdin` as first element in opts.

**Diagnostic:** Bash prompt bytes appear (~292b) then immediate clean exit.

---

### 3. Missing `:normal` exit handler → clean bash exit unhandled

erlexec sends `{:DOWN, os_pid, :process, lwp_pid, :normal}` for exit code 0. The `{:exit_status, code}` form only fires for non-zero exits.

**Fix:**
```elixir
def handle_info({:DOWN, os_pid, :process, _lwp, :normal}, %{os_pid: os_pid} = state) do
  notify_exit(state)
  {:stop, :normal, state}
end
```

The `os_pid` pin in both message and state distinguishes this from the LiveView monitor's `:DOWN`.

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
