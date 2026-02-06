# Phoenix Web FAQ

## Getting Started

### How do I start the app?

```bash
cd eye_in_the_sky_web

# First time setup
mix setup

# Start the server
mix phx.server

# Or with IEx for debugging
iex -S mix phx.server
```

Visit `http://localhost:4000`

### What does `mix setup` do?

Runs these tasks in order:
1. `deps.get` - Install Elixir dependencies
2. `ecto.setup` - Create database and run migrations
3. `assets.setup` - Install Tailwind and npm dependencies
4. `assets.build` - Compile Tailwind CSS and build JS with Svelte

---

## Build System

### Why use a custom build.js instead of Phoenix's built-in esbuild?

Phoenix's default esbuild doesn't support plugins. We need `esbuild-svelte` to compile `.svelte` files. The custom `build.js` in `assets/` configures esbuild with the Svelte plugin.

### Where are the build outputs?

| Source | Output |
|--------|--------|
| `assets/js/app.js` | `priv/static/assets/app.js` |
| `assets/css/app.css` | `priv/static/assets/css/app.css` |
| `assets/js/server.js` | `priv/svelte/server.js` (SSR) |

### How do I rebuild assets manually?

```bash
# From eye_in_the_sky_web directory
cd assets && node build.js

# Or use mix alias
mix assets.build
```

---

## Common Errors

### `No loader is configured for ".svelte" files`

**Cause:** Phoenix is using built-in esbuild instead of custom `build.js`.

**Fix:**
1. Remove esbuild config from `config/config.exs`
2. Ensure `config/dev.exs` has the node watcher:
   ```elixir
   watchers: [
     node: ["build.js", "--watch", cd: Path.expand("../assets", __DIR__)],
     ...
   ]
   ```

### `import_meta.glob is not a function`

**Cause:** `import.meta.glob` is a Vite feature, not supported by esbuild.

**Fix:** Import Svelte components explicitly in `app.js`:
```javascript
import SessionsSidebar from "../svelte/components/SessionsSidebar.svelte"
// ... other imports

let Hooks = getHooks({
  SessionsSidebar,
  // ... other components
})
```

### `No matching export for import "Hooks"` from live_svelte

**Cause:** LiveSvelte 0.16+ changed the export API.

**Fix:** Use `getHooks` instead:
```javascript
// Old (broken)
import {Hooks as LiveSvelteHooks} from "live_svelte"

// New (correct)
import {getHooks} from "live_svelte"
let Hooks = getHooks({ Component1, Component2, ... })
```

### `no route found for GET /assets/js/app.js`

**Cause:** `root.html.heex` points to wrong path. Custom build outputs to `/assets/app.js`, not `/assets/js/app.js`.

**Fix:** In `lib/eye_in_the_sky_web_web/components/layouts/root.html.heex`:
```heex
<!-- Wrong -->
<script src={~p"/assets/js/app.js"}></script>

<!-- Correct -->
<script src={~p"/assets/app.js"}></script>
```

### Two app.js files causing conflicts

**Cause:** Old built-in esbuild output at `priv/static/assets/js/app.js` conflicts with custom build at `priv/static/assets/app.js`.

**Fix:** Delete the old file:
```bash
rm priv/static/assets/js/app.js
```

---

## LiveSvelte Integration

### How do I add a new Svelte component?

1. Create the component in `assets/svelte/components/`:
   ```svelte
   <!-- assets/svelte/components/MyComponent.svelte -->
   <script>
     export let name = "World"
   </script>

   <h1>Hello {name}!</h1>
   ```

2. Import it in `assets/js/app.js`:
   ```javascript
   import MyComponent from "../svelte/components/MyComponent.svelte"

   let Hooks = getHooks({
     // ... existing components
     MyComponent,
   })
   ```

3. Use it in a LiveView:
   ```elixir
   def render(assigns) do
     ~H"""
     <.svelte name="MyComponent" props={%{name: "Phoenix"}} socket={@socket} />
     """
   end
   ```

### What props does LiveSvelte automatically pass?

- `live` - Reference to the LiveView for pushing events back

### How do I push events from Svelte to LiveView?

```svelte
<script>
  export let live

  function handleClick() {
    live.pushEvent("my_event", {data: "value"})
  }
</script>

<button on:click={handleClick}>Click me</button>
```

Then handle in LiveView:
```elixir
def handle_event("my_event", %{"data" => value}, socket) do
  {:noreply, socket}
end
```

### Why do I get "unused export property 'live'" warnings?

These are harmless warnings from Svelte 5. The `live` prop is passed by LiveSvelte but may not be used in every component. You can ignore them or use `live` in the component to silence.

---

## Database

### Where is the database?

`~/.config/eye-in-the-sky/eits.db` (SQLite)

This is the same database used by the Go TUI, allowing both interfaces to coexist.

### How do I reset the database?

```bash
# This drops and recreates with migrations
mix ecto.reset
```

---

## Development

### How do I run tests?

```bash
mix test
```

### How do I run precommit checks?

```bash
mix precommit
```

This runs: compile with warnings-as-errors, unlock unused deps, format, and test.

### How do I format code?

```bash
mix format
```

---

## Project Structure

```
eye_in_the_sky_web/
├── assets/
│   ├── js/app.js           # Main JS entry point
│   ├── js/server.js        # SSR entry point
│   ├── js/hooks/           # Custom LiveView hooks
│   ├── svelte/components/  # Svelte components
│   ├── css/app.css         # Tailwind CSS
│   ├── build.js            # Custom esbuild config
│   └── package.json        # npm dependencies
├── config/
│   ├── config.exs          # Base config
│   ├── dev.exs             # Dev config (watchers here)
│   └── prod.exs            # Production config
├── lib/
│   ├── eye_in_the_sky_web/ # Business logic (contexts, schemas)
│   └── eye_in_the_sky_web_web/
│       ├── live/           # LiveView modules
│       ├── components/     # Phoenix components
│       └── router.ex       # Routes
└── priv/
    ├── static/assets/      # Compiled assets
    └── svelte/             # Compiled SSR bundle
```

---

## Architecture

### LiveView Structure

Three main LiveViews:

| Route | Module | Description |
|-------|--------|-------------|
| `/` | `AgentLive.Index` | Agent list with status badges |
| `/agents/:id` | `AgentLive.Show` | Agent detail with 3-column layout |
| `/sessions` | `SessionLive.Index` | Session overview across agents |

### AgentLive.Show Layout

Uses 3 Svelte components in a grid layout:
- **Left:** `SessionsSidebar` - List of sessions for the agent
- **Center:** `MainWorkArea` - Tabbed view (tasks, commits, logs)
- **Right:** `ContextPanel` - Session context and notes

### Data Flow: LiveView → Svelte

Ecto structs must be serialized to plain maps before passing to Svelte:

```elixir
# In LiveView
defp serialize_tasks(tasks) do
  Enum.map(tasks, fn task ->
    %{
      id: task.id,
      title: task.title,
      state_name: task.state && task.state.name,
      # ... other fields
    }
  end)
end

# Usage
socket
|> assign(:tasks, tasks)
|> assign(:tasks_serialized, serialize_tasks(tasks))
```

```heex
<.svelte
  name="TaskList"
  props={%{tasks: @tasks_serialized}}
  socket={@socket}
/>
```

---

## Svelte Components

### Current Components

| Component | Location | Purpose |
|-----------|----------|---------|
| `SessionsSidebar` | `svelte/components/` | Session list with selection |
| `MainWorkArea` | `svelte/components/` | Tabbed content area |
| `ContextPanel` | `svelte/components/` | Context and notes display |
| `TasksTab` | `svelte/components/tabs/` | Task list view |
| `CommitsTab` | `svelte/components/tabs/` | Commit list view |
| `LogsTab` | `svelte/components/tabs/` | Log viewer |

### Adding Components Checklist

1. Create `.svelte` file in `assets/svelte/components/`
2. Add import to `assets/js/app.js`
3. Add to `getHooks({...})` object
4. Use `<.svelte name="..." />` in LiveView

### Svelte 5 Notes

This project uses Svelte 5 which has some differences from Svelte 4:
- Uses runes system (`$state`, `$derived`, `$effect`) for reactivity
- `export let` props still work but may show warnings
- The `live` prop warning is harmless; Svelte 5 is stricter about unused exports

---

## Timestamps and Go Interop

### Go Timestamp Format

The database stores timestamps from Go in string format like:
```
2025-01-15 10:30:45.123456789 -0700 MST
```

LiveViews have helpers to parse these:

```elixir
defp format_datetime(datetime) when is_binary(datetime) do
  case String.split(datetime, " ", parts: 3) do
    [date, time | _] -> "#{date} #{String.slice(time, 0..7)}"
    _ -> datetime
  end
end
```

---

## Mix Aliases

| Alias | Commands | Purpose |
|-------|----------|---------|
| `mix setup` | deps.get, ecto.setup, assets.setup, assets.build | Full project setup |
| `mix assets.setup` | tailwind.install, npm install | Install asset tooling |
| `mix assets.build` | compile, tailwind, node build.js | Build all assets |
| `mix assets.deploy` | tailwind --minify, build.js --deploy, phx.digest | Production build |
| `mix precommit` | compile --warnings-as-errors, format, test | Pre-commit checks |

---

## Troubleshooting

### Assets not updating?

1. Check the node watcher is running (look for `node build.js --watch` in terminal)
2. Hard refresh browser: `Cmd+Shift+R`
3. Manually rebuild: `cd assets && node build.js`

### LiveView not connecting?

Check browser console for WebSocket errors. Common causes:
- CSRF token mismatch (clear cookies)
- Asset loading failed (check network tab)

### Svelte component not rendering?

1. Verify component is imported in `app.js`
2. Verify component is in `getHooks({...})`
3. Check `data-name` attribute matches component name exactly
4. Check browser console for hydration errors

### Database errors?

Ensure the Go MCP server isn't holding a write lock:
```bash
# Check for locks
lsof ~/.config/eye-in-the-sky/eits.db
```

SQLite WAL mode allows concurrent reads but only one writer.

---

## Technology Stack

| Tech | Version | Purpose |
|------|---------|---------|
| Phoenix | 1.8.1 | Web framework |
| Phoenix LiveView | 1.1.x | Real-time UI |
| LiveSvelte | 0.16.0 | Svelte integration |
| Svelte | 5.43.6 | Component framework |
| Tailwind CSS | 4.1.7 | Styling |
| Ecto SQLite3 | 0.22+ | Database adapter |
| esbuild | 0.27.0 | JS bundler |
| esbuild-svelte | 0.9.3 | Svelte plugin |

---

## Reference Files

| File | Purpose |
|------|---------|
| `AGENTS.md` | Phoenix 1.8 coding guidelines |
| `docs/PHOENIX_MIGRATION_PLAN.md` | Full architecture plan |
| `config/dev.exs` | Development configuration |
| `assets/build.js` | Custom esbuild configuration |
| `assets/js/app.js` | Main JS entry with hooks |
