# Terminal PTY System

Full-stack embedded terminal built on erlexec + xterm.js, exposed at `/terminal`. One bash process per browser session, bidirectional via Phoenix LiveView WebSocket.

---

## Architecture Overview

```
Browser (xterm.js)
    │  keystrokes → pushEvent("pty_input")
    │  pty_output ← handleEvent("pty_output")
    ▼
TerminalLive (LiveView)
    │  handle_event("pty_input") → PtyServer.write/2
    │  handle_info({:pty_output, data}) → push_event("pty_output")
    ▼
PtyServer (GenServer)
    │  :exec.send(os_pid, data)  ← writes to PTY master
    │  {:stdout, os_pid, data}   → forwarded to TerminalLive
    ▼
erlexec (Erlang port driver)
    │  PTY master fd
    ▼
bash process (OS)
    PTY slave fd (stdin + stdout + stderr)
```

---

## Files

| File | Role |
|------|------|
| `lib/eye_in_the_sky/terminal/pty_server.ex` | GenServer owning one PTY session |
| `lib/eye_in_the_sky/terminal/pty_supervisor.ex` | DynamicSupervisor for PtyServer instances |
| `lib/eye_in_the_sky_web/live/terminal_live.ex` | LiveView: event bridge between WebSocket and PTY |
| `assets/js/hooks/pty_hook.js` | xterm.js initialization, resize, input/output wiring |
| `test/eye_in_the_sky/terminal/pty_server_test.exs` | Integration test: echo smoke test |

---

## Dependency

```elixir
# mix.exs
{:erlexec, "~> 2.0"}
# pinned to 2.2.4 in mix.lock
```

erlexec is an Erlang library that manages OS processes via a C port driver. It supports PTY allocation, stdin/stdout piping, process monitoring, and window resize (`SIGWINCH`).

---

## PtyServer — `lib/eye_in_the_sky/terminal/pty_server.ex`

### Lifecycle

```
PtySupervisor.start_pty(opts)
    → DynamicSupervisor.start_child(PtyServer, opts)
    → PtyServer.init/1
        → Process.monitor(subscriber_pid)   # monitor TerminalLive
        → :exec.run(shell_cmd, exec_opts)   # spawn bash with PTY
        → :exec.winsz(os_pid, rows, cols)   # set initial window size
    → {:ok, pid}
```

On LiveView disconnect or `PtyServer.stop/1`:
```
terminate/2
    → :exec.stop(os_pid)   # sends SIGTERM to bash, cleans up PTY fds
```

### State

```elixir
%{
  subscriber: pid,    # TerminalLive process — receives {:pty_output, data}
  os_pid: integer,    # OS PID of the bash process (used by erlexec API)
  cols: integer,      # current PTY width in columns
  rows: integer       # current PTY height in rows
}
```

### erlexec opts — the working configuration

```elixir
opts = [
  :stdin,             # REQUIRED: without this, stdin defaults to /dev/null
  {:stdout, self()},  # deliver PTY output as {:stdout, os_pid, data} messages
  {:stderr, :stdout}, # merge stderr into stdout stream
  :pty,               # allocate a PTY (pseudo-terminal)
  :pty_echo,          # REQUIRED: enable ECHO termios flag so typed chars echo back
  {:env, env},        # environment variables for bash
  :monitor            # send {:DOWN, ...} when process exits
]
```

**Every option here is load-bearing.** See the gotchas section below.

### Shell command

```elixir
shell_cmd = [@shell_bin, "--norc", "--noprofile", "-i"]
```

- **List form** (not a string) — avoids erlexec's `m_shell=true` C port flag
- `--norc --noprofile` — skip user init files that might exit or behave unexpectedly
- `-i` — force interactive mode so bash shows a prompt and reads stdin

### Environment

```elixir
env = [
  {"TERM", "xterm-256color"},
  {"LANG", "en_US.UTF-8"},
  {"HOME", System.get_env("HOME", "/tmp")},
  {"PATH", System.get_env("PATH", "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin")},
  {"SHELL", @shell_bin},
  {"USER", System.get_env("USER", "user")},
  {"LOGNAME", System.get_env("LOGNAME", ...)}
]
```

`TERM=xterm-256color` is critical — without it many CLI tools disable color output and readline breaks.

### Message handlers

| Message | Source | Action |
|---------|--------|--------|
| `{:write, data}` cast | TerminalLive | `:exec.send(os_pid, data)` — writes to PTY master |
| `{:resize, cols, rows}` cast | TerminalLive | `:exec.winsz(os_pid, rows, cols)` — sends SIGWINCH |
| `{:stdout, os_pid, data}` | erlexec port | `send(subscriber, {:pty_output, data})` |
| `{:DOWN, os_pid, :process, _lwp, :normal}` | erlexec | bash exited code 0 → notify subscriber, stop GenServer |
| `{:DOWN, _ref, :process, _pid, {:exit_status, code}}` | erlexec | bash exited non-zero → notify subscriber, stop GenServer |
| `{:DOWN, _ref, :process, subscriber_pid, _}` | OTP monitor | LiveView died → stop GenServer (no subscriber to notify) |

---

## PtySupervisor — `lib/eye_in_the_sky/terminal/pty_supervisor.ex`

`DynamicSupervisor` with `:one_for_one` strategy and `restart: :temporary` on PtyServer children. Temporary means a crashed PtyServer is NOT restarted — the LiveView will receive `:pty_exited` and display `[process exited]`.

Started in the application supervision tree (`lib/eye_in_the_sky/application.ex`).

```elixir
# application.ex — supervisor tree entry
EyeInTheSky.Terminal.PtySupervisor
```

API:
```elixir
PtySupervisor.start_pty(subscriber: pid, cols: 220, rows: 50)
# Returns {:ok, pty_server_pid}
```

---

## TerminalLive — `lib/eye_in_the_sky_web/live/terminal_live.ex`

Route: `GET /terminal` (inside the `:app` live_session).

### Mount

```elixir
def mount(_params, _session, socket) do
  if connected?(socket) do
    {:ok, pty_pid} = PtySupervisor.start_pty(subscriber: self(), cols: 220, rows: 50)
    {:ok, assign(socket, pty_pid: pty_pid, page_title: "Terminal")}
  else
    {:ok, assign(socket, pty_pid: nil, page_title: "Terminal")}
  end
end
```

`connected?/1` guard prevents spawning a PTY during the dead render (mount runs twice in LiveView — once for the initial HTTP response, once after WebSocket connects).

### Events from client

| Event | Params | Handler |
|-------|--------|---------|
| `pty_input` | `%{"data" => string}` | `PtyServer.write(pid, data)` |
| `pty_resize` | `%{"cols" => int, "rows" => int}` | `PtyServer.resize(pid, cols, rows)` |
| `set_notify_on_stop` | any | `NotificationHelpers.set_notify_on_stop/2` |
| any other | any | ignored (catch-all prevents crashes from command palette events) |

### Messages from PtyServer

| Message | Action |
|---------|--------|
| `{:pty_output, data}` | `push_event("pty_output", %{data: Base.encode64(data)})` |
| `:pty_exited` | assign `pty_pid: nil`, push exit message to xterm.js |

### Why base64?

`push_event` serializes payload as JSON. PTY output is raw binary — it can contain null bytes, invalid UTF-8 sequences, and control characters that break JSON. `Base.encode64/1` converts the binary to a safe ASCII string; the client decodes it with `atob()`.

### Terminate

```elixir
def terminate(_reason, %{assigns: %{pty_pid: pid}}) when is_pid(pid) do
  PtyServer.stop(pid)
end
```

Ensures bash is killed when the user navigates away or the WebSocket drops.

---

## PtyHook — `assets/js/hooks/pty_hook.js`

Phoenix LiveView hook attached to `#terminal-container` via `phx-hook="PtyHook"`. The container has `phx-update="ignore"` so LiveView never touches its DOM after mount.

### xterm.js configuration

```js
new Terminal({
  cursorBlink: true,
  fontSize: 13,
  fontFamily: '"JetBrains Mono", "Fira Code", "Cascadia Code", monospace',
  scrollback: 5000,
  allowProposedApi: true,
  theme: { /* zinc palette */ }
})
```

Addons loaded:
- `FitAddon` — resizes the terminal to fill its container element
- `WebLinksAddon` — makes URLs in terminal output clickable

### Input path

```
User keystroke
  → xterm.js captures via hidden <textarea> (xterm-helper-textarea)
  → term.onData(data => ...)
  → this.pushEvent("pty_input", { data })
  → LiveView WebSocket → TerminalLive.handle_event
```

`data` is a string that may contain single characters, escape sequences (arrow keys: `\x1b[A`), or paste content.

### Output path

```
TerminalLive.push_event("pty_output", %{data: base64})
  → LiveView WebSocket
  → this.handleEvent("pty_output", ({ data }) => ...)
  → atob(data) → Uint8Array
  → term.write(bytes)
```

`term.write()` accepts `Uint8Array` — this handles binary correctly regardless of encoding, including raw control sequences, ANSI colors, and UTF-8 multibyte characters.

### Resize

```
Container size changes (window resize, CSS layout shift)
  → ResizeObserver fires
  → fitAddon.fit()
  → xterm.js recalculates cols/rows
  → term.onResize({ cols, rows }) fires
  → this.pushEvent("pty_resize", { cols, rows })
  → TerminalLive → PtyServer.resize → :exec.winsz
```

`ResizeObserver` on `this.el` catches all layout-driven size changes, not just `window.resize` events.

### Cleanup

```js
destroyed() {
  this._resizeObserver?.disconnect()
  this._term?.dispose()
}
```

Called by LiveView when the hook element is removed from the DOM (navigation away). Disposes xterm.js canvas and DOM nodes.

---

## Data Flow Diagram (complete)

```
User types "ls"
│
├─ xterm.js term.onData("l") fires
├─ pushEvent("pty_input", { data: "l" })
├─ [WebSocket frame]
├─ TerminalLive.handle_event("pty_input", %{"data" => "l"})
├─ PtyServer.write(pid, "l")   [GenServer.cast]
├─ :exec.send(os_pid, "l")     [writes "l" to PTY master fd]
│
│  PTY driver echoes "l" back (ECHO termios flag):
├─ erlexec delivers {:stdout, os_pid, <<"l">>}
├─ PtyServer.handle_info → send(subscriber, {:pty_output, <<"l">>})
├─ TerminalLive.handle_info → push_event("pty_output", %{data: "bA=="})
├─ [WebSocket frame]
├─ PtyHook.handleEvent("pty_output") → term.write(Uint8Array[108])
└─ xterm.js renders "l" at cursor position

User presses Enter:
├─ onData("\r") fires (carriage return, not LF — PTY convention)
├─ bash reads line, executes "ls"
├─ bash writes directory listing to PTY slave stdout
├─ erlexec streams output as multiple {:stdout, os_pid, chunk} messages
└─ each chunk → TerminalLive → push_event → xterm.js renders
```

---

## erlexec Gotchas (confirmed bugs, all fixed)

These were discovered through debugging. All four must be present for the terminal to work correctly.

### 1. String command → `m_shell=true` → bash exits immediately

**Wrong:**
```elixir
:exec.run("/bin/bash", opts)          # string form
```

**Why it fails:** A string argument sets `m_shell=true` in erlexec's C port. This wraps the command as `$SHELL -c "/bin/bash"`. The outer shell runs bash non-interactively and exits immediately.

**Correct:**
```elixir
:exec.run(["/bin/bash", "--norc", "--noprofile", "-i"], opts)   # list form
```

**Diagnostic:** Server logs show `{:DOWN, os_pid, :process, pid, :normal}` with zero stdout messages immediately after spawn.

---

### 2. Missing `:stdin` → stdin is `/dev/null` → bash exits on EOF

**Wrong:**
```elixir
opts = [{:stdout, self()}, :pty, ...]   # :stdin omitted
```

**Why it fails:** Without `:stdin`, erlexec's C port initializes `stream_fd[STDIN_FILENO]` to `{REDIRECT_NULL, REDIRECT_NONE}` (source: `exec_impl.cpp` lines 372–376). Bash reads EOF from `/dev/null` and exits cleanly (code 0) before you can type anything. Additionally, `:exec.send/2` silently fails — it cannot write to a process whose stdin was never connected.

**Correct:**
```elixir
opts = [:stdin, {:stdout, self()}, :pty, ...]
```

**Diagnostic:** Server logs show bash prompt bytes (~292b) immediately followed by a clean exit. No user interaction between spawn and exit.

---

### 3. Missing `:normal` exit handler → clean bash exit unhandled

**Wrong:**
```elixir
def handle_info({:DOWN, _ref, :process, _pid, {:exit_status, code}}, state) do
  # only handles non-zero exits
end
```

**Why it fails:** erlexec sends `{:DOWN, os_pid, :process, lwp_pid, :normal}` when the OS process exits with code 0 (via `ospid_loop` in erlexec's Erlang layer). The `{:exit_status, code}` form only fires for non-zero exits. Without the `:normal` clause, clean bash exits are silently dropped by the catch-all `handle_info(_msg, state)`.

**Correct:**
```elixir
def handle_info({:DOWN, os_pid, :process, _lwp, :normal}, %{os_pid: os_pid} = state) do
  send(state.subscriber, :pty_exited)
  {:stop, :normal, state}
end
```

Note the `os_pid` pattern match on both the message and the state — this distinguishes the OS process exit from the LiveView monitor's `:DOWN` message.

---

### 4. Missing `:pty_echo` → typed characters invisible

**Wrong:**
```elixir
opts = [:stdin, {:stdout, self()}, :pty, ...]   # :pty_echo omitted
```

**Why it fails:** erlexec allocates PTYs with the `ECHO` termios flag **disabled** by default. The ECHO flag controls whether the PTY driver echoes received input back to the master fd. Without it:
- Keystrokes reach bash via `:exec.send` ✓
- Bash executes commands ✓  
- But characters are never echoed back, so xterm.js never renders them ✗
- Result: cursor blinks, commands silently execute, screen appears frozen

**Correct:**
```elixir
opts = [:stdin, {:stdout, self()}, :pty, :pty_echo, ...]
```

**Diagnostic:** Press Enter in the terminal — if a new prompt appears, bash is running but echo is off. Typed characters are invisible but commands execute.

---

## Testing

```bash
mix test test/eye_in_the_sky/terminal/pty_server_test.exs
```

The test:
1. Starts a PtyServer with `self()` as subscriber
2. Drains initial output (bash prompt)
3. Sends `"echo pty_echo_smoke\n"` via `PtyServer.write/2`
4. Collects output for up to 2 seconds
5. Asserts both the echoed input (`echo pty_echo_smoke`) and the command output (`pty_echo_smoke\r\n`) appear

This regression catches bugs 2 and 4 simultaneously — if `:stdin` is missing, nothing echoes; if `:pty_echo` is missing, the echo assertion fails.

```elixir
assert output =~ "echo pty_echo_smoke"   # echo of typed input
assert output =~ "pty_echo_smoke\r\n"    # command output (CRLF in PTY mode)
```

Note `async: false` — PTY tests touch OS-level file descriptors and must not run concurrently.

---

## Window Resize Flow

```
xterm.js FitAddon.fit()
  → measures container pixel size
  → calculates cols/rows based on character cell dimensions
  → fires term.onResize({ cols, rows })
  → pushEvent("pty_resize", { cols, rows })
  → TerminalLive.handle_event("pty_resize")
  → PtyServer.resize(pid, cols, rows)
  → handle_cast({:resize, cols, rows})
  → :exec.winsz(os_pid, rows, cols)   # NOTE: rows first, then cols
```

`:exec.winsz/3` sends `SIGWINCH` to the child process. Bash and readline respond by re-rendering the current prompt at the new width.

**Important:** `:exec.winsz(os_pid, rows, cols)` — rows comes first, cols second. This is the opposite of the conventional (cols, rows) ordering.

Initial window size is set via `:exec.winsz` after spawn. `{:winsz, {rows, cols}}` is documented as a valid `exec:run` option in some erlexec versions but was unreliable — calling it post-spawn is more reliable.

---

## Supervision and Cleanup

```
Application
└── PtySupervisor (DynamicSupervisor, :one_for_one)
    └── PtyServer (restart: :temporary)
        └── bash (OS process, managed by erlexec C port)
```

**PtyServer restart: :temporary** — if PtyServer crashes, it is NOT restarted. The LiveView receives `:pty_exited`, displays `[process exited]`, and sets `pty_pid: nil`. The user must navigate away and back to get a new session.

**Cleanup chain on LiveView disconnect:**
1. Phoenix detects WebSocket close
2. `TerminalLive.terminate/2` fires → `PtyServer.stop(pid)`
3. `PtyServer.terminate/2` fires → `:exec.stop(os_pid)` → SIGTERM to bash
4. erlexec C port closes PTY master fd
5. bash receives SIGHUP (controlling terminal closed) and exits

**Cleanup chain on bash exit:**
1. erlexec detects OS process exit
2. Sends `{:DOWN, os_pid, :process, lwp, :normal}` (exit 0) or `{:DOWN, _, :process, _, {:exit_status, n}}` (exit N)
3. `PtyServer.handle_info` → `send(subscriber, :pty_exited)` → `{:stop, :normal, state}`
4. `PtyServer.terminate/2` → `:exec.stop(os_pid)` (no-op, already dead)
5. `TerminalLive.handle_info(:pty_exited)` → push exit message, set `pty_pid: nil`

---

## Adding a New Terminal Surface

To embed the PTY in a component other than `TerminalLive` (e.g., a panel, modal, or canvas window), the pattern is:

1. **Start a PtyServer** with `subscriber: self()` and desired dimensions
2. **Add handle_event** for `pty_input` and `pty_resize` — delegate to `PtyServer.write/2` and `PtyServer.resize/3`
3. **Add handle_info** for `{:pty_output, data}` — `push_event("pty_output", %{data: Base.encode64(data)})`
4. **Add handle_info** for `:pty_exited` — handle UI state
5. **Add catch-all handle_event** — prevents crashes from command palette and other global events
6. **Stop PtyServer in terminate/2** — prevents orphaned bash processes
7. **Mount PtyHook** on a container element with `phx-hook="PtyHook"` and `phx-update="ignore"`

The xterm.js hook (`PtyHook`) is reusable as-is. The container element needs a stable `id` and must not be touched by LiveView after mount (`phx-update="ignore"`).

---

## Known Limitations

- **One session per LiveView** — no multiplexing. Each `/terminal` page load is one bash process.
- **No session persistence** — navigating away kills the bash process. Working directory and shell history are lost.
- **No scrollback sync** — scrollback buffer lives only in xterm.js on the client. If the page reloads, history is gone.
- **bash only** — `@shell_bin` hardcodes bash. No shell selection UI.
- **No pty_echo from commands** — the ECHO flag echoes typed input. Command output (e.g., `ls`) is delivered via `{:stdout, ...}` messages regardless of echo state.
