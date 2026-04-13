# Theme Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a theme picker to Settings > General that persists to both the Settings DB and localStorage, with six themes: custom dark/light plus four Catppuccin flavors.

**Architecture:** Install `@catppuccin/daisyui`, register its CSS plugin, add a `"theme"` key to the Settings module, server-render the initial `data-theme` from DB on `<html>`, and fire a `phx:apply_theme` event from the LiveView on change to update the DOM and localStorage instantly.

**Tech Stack:** DaisyUI v5, `@catppuccin/daisyui`, Phoenix LiveView, `assets/js/theme.js` (existing), Elixir Settings module (meta table)

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `assets/package.json` | Modify | Add `@catppuccin/daisyui` dev dep |
| `assets/css/app.css` | Modify | Register catppuccin plugin |
| `lib/eye_in_the_sky/settings.ex` | Modify | Add `"theme"` to `@defaults` |
| `lib/eye_in_the_sky_web/components/layouts/root.html.heex` | Modify | Server-render `data-theme`; update inline JS |
| `assets/js/theme.js` | Modify | Add `phx:apply_theme` event handler |
| `lib/eye_in_the_sky_web/live/overview_live/settings.ex` | Modify | Add `@themes`, Appearance section in General tab, push_event on theme save |

---

### Task 1: Install `@catppuccin/daisyui` and verify it works

**Files:**
- Modify: `assets/package.json`
- Modify: `assets/css/app.css`

- [ ] **Step 1: Install the package**

```bash
cd /Users/urielmaldonado/projects/eits/web/assets && npm install -D @catppuccin/daisyui
```

Expected: package added to `node_modules/@catppuccin/daisyui`, `package.json` updated with `"@catppuccin/daisyui"` in `devDependencies`.

- [ ] **Step 2: Register the plugin in app.css**

In `assets/css/app.css`, add after the `@plugin "daisyui"` block (after the closing `}`):

```css
@plugin "daisyui" {
  themes: all;
}

@plugin "@catppuccin/daisyui";
```

- [ ] **Step 3: Verify the build**

```bash
cd /Users/urielmaldonado/projects/eits/web && mix compile 2>&1 | tail -10
```

Expected: no errors. If `@plugin "@catppuccin/daisyui"` fails to resolve, check what the package exports:
```bash
cat /Users/urielmaldonado/projects/eits/web/assets/node_modules/@catppuccin/daisyui/package.json | grep -E '"main"|"exports"|"module"'
```
If it exports a CSS file rather than a JS plugin, use `@import "@catppuccin/daisyui"` instead.

- [ ] **Step 4: Confirm theme names**

```bash
grep -r "data-theme\|\"latte\"\|\"mocha\"\|\"frappe\"\|\"macchiato\"\|catppuccin" \
  /Users/urielmaldonado/projects/eits/web/assets/node_modules/@catppuccin/daisyui/ \
  --include="*.css" --include="*.js" -l 2>/dev/null | head -5
```

Then check the theme name format used in the package (prefixed or not):
```bash
grep -m 5 "data-theme" \
  $(find /Users/urielmaldonado/projects/eits/web/assets/node_modules/@catppuccin/daisyui -name "*.css" 2>/dev/null | head -1) 2>/dev/null
```

Note the exact theme names. They are either `catppuccin-latte` / `catppuccin-frappe` / `catppuccin-macchiato` / `catppuccin-mocha` or just `latte` / `frappe` / `macchiato` / `mocha`. Use the correct names in Task 5.

- [ ] **Step 5: Commit**

```bash
cd /Users/urielmaldonado/projects/eits/web && git add assets/package.json assets/package-lock.json assets/css/app.css && git commit -m "feat: add @catppuccin/daisyui theme plugin"
```

---

### Task 2: Add `theme` to the Settings module

**Files:**
- Modify: `lib/eye_in_the_sky/settings.ex`

- [ ] **Step 1: Add the default**

In `lib/eye_in_the_sky/settings.ex`, find `@defaults` and add `"theme" => "dark"` as the last entry:

```elixir
@defaults %{
  "default_model" => "sonnet",
  "cli_idle_timeout_ms" => "300000",
  "log_claude_raw" => "false",
  "log_codex_raw" => "false",
  "tts_voice" => "Ava",
  "tts_rate" => "200",
  "pricing_opus_input" => "15.0",
  "pricing_opus_output" => "75.0",
  "pricing_opus_cache_read" => "3.75",
  "pricing_opus_cache_creation" => "18.75",
  "pricing_sonnet_input" => "3.0",
  "pricing_sonnet_output" => "15.0",
  "pricing_sonnet_cache_read" => "0.30",
  "pricing_sonnet_cache_creation" => "3.75",
  "pricing_haiku_input" => "0.80",
  "pricing_haiku_output" => "4.0",
  "pricing_haiku_cache_read" => "0.08",
  "pricing_haiku_cache_creation" => "1.00",
  "preferred_editor" => "code",
  "eits_workflow_enabled" => "true",
  "theme" => "dark"
}
```

- [ ] **Step 2: Verify compilation**

```bash
cd /Users/urielmaldonado/projects/eits/web && mix compile 2>&1 | tail -5
```

Expected: `Compiled lib/eye_in_the_sky/settings.ex` with no errors.

- [ ] **Step 3: Commit**

```bash
cd /Users/urielmaldonado/projects/eits/web && git add lib/eye_in_the_sky/settings.ex && git commit -m "feat: add theme key to Settings defaults"
```

---

### Task 3: Server-render theme in root layout + update inline JS

**Files:**
- Modify: `lib/eye_in_the_sky_web/components/layouts/root.html.heex`

- [ ] **Step 1: Add `data-theme` to `<html>` tag**

Change line 1 from:
```html
<html lang="en">
```
to:
```heex
<html lang="en" data-theme={EyeInTheSky.Settings.get("theme") || "dark"}>
```

- [ ] **Step 2: Update the inline theme script**

Replace the existing inline script block:
```html
<script>
  // Initialize theme from localStorage on page load (before paint)
  const theme = localStorage.getItem("theme") || "light";
  document.documentElement.setAttribute("data-theme", theme);
</script>
```

With:
```html
<script>
  // Override server-rendered data-theme if localStorage has a saved value
  const saved = localStorage.getItem("theme");
  if (saved) document.documentElement.setAttribute("data-theme", saved);
</script>
```

- [ ] **Step 3: Verify compilation**

```bash
cd /Users/urielmaldonado/projects/eits/web && mix compile 2>&1 | tail -5
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
cd /Users/urielmaldonado/projects/eits/web && git add lib/eye_in_the_sky_web/components/layouts/root.html.heex && git commit -m "feat: server-render initial theme from Settings DB in root layout"
```

---

### Task 4: Add `phx:apply_theme` handler to theme.js

**Files:**
- Modify: `assets/js/theme.js`

- [ ] **Step 1: Add the event handler**

Append inside the `DOMContentLoaded` callback, before its closing `}`. The full file becomes:

```js
// Daisy UI Theme Controller Integration
// Handles theme persistence and synchronization across tabs

document.addEventListener('DOMContentLoaded', () => {
  const themeControllers = document.querySelectorAll('.theme-controller');

  // Initialize theme controllers based on current theme
  const currentTheme = document.documentElement.getAttribute('data-theme');
  themeControllers.forEach(controller => {
    if (controller.type === 'checkbox') {
      controller.checked = currentTheme === 'dark';
    }
  });

  // Listen for theme changes from Daisy UI theme controller
  themeControllers.forEach(controller => {
    controller.addEventListener('change', (e) => {
      const theme = e.target.checked ? 'dark' : 'light';
      localStorage.setItem('theme', theme);
      document.documentElement.setAttribute('data-theme', theme);

      // Sync other theme controllers on the page
      themeControllers.forEach(otherController => {
        if (otherController !== controller) {
          otherController.checked = e.target.checked;
        }
      });
    });
  });

  // Handle phx:set-theme events from LiveView theme toggle buttons
  window.addEventListener('phx:set-theme', (e) => {
    const btn = e.target.closest('[data-phx-theme]') || e.target;
    const theme = btn.getAttribute('data-phx-theme') || 'light';
    if (theme === 'system') {
      const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
      const resolvedTheme = prefersDark ? 'dark' : 'light';
      localStorage.removeItem('theme');
      document.documentElement.setAttribute('data-theme', resolvedTheme);
    } else {
      localStorage.setItem('theme', theme);
      document.documentElement.setAttribute('data-theme', theme);
    }
  });

  // Sync theme across browser tabs
  window.addEventListener('storage', (e) => {
    if (e.key === 'theme') {
      const newTheme = e.newValue || 'light';
      document.documentElement.setAttribute('data-theme', newTheme);
      themeControllers.forEach(controller => {
        controller.checked = newTheme === 'dark';
      });
    }
  });

  // Handle theme changes pushed from LiveView Settings page
  window.addEventListener('phx:apply_theme', ({ detail }) => {
    const theme = detail.theme;
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem('theme', theme);

    // Keep checkbox theme-controllers in sync (dark = any non-light theme)
    themeControllers.forEach(controller => {
      if (controller.type === 'checkbox') {
        controller.checked = theme !== 'light' && theme !== 'catppuccin-latte';
      }
    });
  });
});
```

- [ ] **Step 2: Commit**

```bash
cd /Users/urielmaldonado/projects/eits/web && git add assets/js/theme.js && git commit -m "feat: add phx:apply_theme event handler to theme.js"
```

---

### Task 5: Add Appearance section to Settings > General tab

**Files:**
- Modify: `lib/eye_in_the_sky_web/live/overview_live/settings.ex`

> **Note:** Use the exact theme names confirmed in Task 1 Step 4. Adjust the `@themes` list if they lack the `catppuccin-` prefix.

- [ ] **Step 1: Add `@themes` module attribute**

After line 13 (`@voices ["Ava", "Isha", "Lee", "Jamie", "Serena"]`), add:

```elixir
@themes [
  {"dark", "Dark"},
  {"light", "Light"},
  {"catppuccin-latte", "Latte"},
  {"catppuccin-frappe", "Frappé"},
  {"catppuccin-macchiato", "Macchiato"},
  {"catppuccin-mocha", "Mocha"}
]
```

- [ ] **Step 2: Add `:themes` assign in `mount/3`**

In `mount/3`, add after `|> assign(:voices, @voices)`:

```elixir
|> assign(:themes, @themes)
```

- [ ] **Step 3: Update `handle_event("save_setting", ...)` to push theme event**

Find `handle_event("save_setting", %{"key" => key, "value" => value}, socket)`. Replace its return:

```elixir
# Before:
Settings.put(key, value)
settings = Settings.all()
{:noreply, socket |> assign(:settings, settings) |> flash_saved(key)}

# After:
Settings.put(key, value)
settings = Settings.all()

socket =
  socket
  |> assign(:settings, settings)
  |> flash_saved(key)

socket =
  if key == "theme" do
    push_event(socket, "apply_theme", %{theme: value})
  else
    socket
  end

{:noreply, socket}
```

- [ ] **Step 4: Replace `render_tab(:general)` with Appearance + Agent Defaults**

Replace the entire `defp render_tab(%{active_tab: :general} = assigns)` function with:

```elixir
defp render_tab(%{active_tab: :general} = assigns) do
  ~H"""
  <div class="space-y-6">
    <section>
      <h2 class="text-sm font-semibold text-base-content/60 uppercase tracking-wider mb-4">
        Appearance
      </h2>
      <div class="card bg-base-100 border border-base-300 shadow-sm">
        <div class="card-body px-5 py-4">
          <p class="text-sm font-medium text-base-content mb-3">Theme</p>
          <div class="flex flex-wrap gap-2">
            <form :for={{val, label} <- @themes} phx-change="save_setting">
              <input type="hidden" name="key" value="theme" />
              <button
                type="submit"
                name="value"
                value={val}
                class={"btn btn-sm #{if @settings["theme"] == val, do: "btn-primary", else: "btn-outline"}"}
              >
                {label}
              </button>
            </form>
          </div>
        </div>
      </div>
    </section>

    <section>
      <h2 class="text-sm font-semibold text-base-content/60 uppercase tracking-wider mb-4">
        Agent Defaults
      </h2>
      <div class="card bg-base-100 border border-base-300 shadow-sm">
        <div class="card-body p-0 divide-y divide-base-300">
          <%!-- Default Model --%>
          <div class="flex items-center justify-between px-5 py-4">
            <div>
              <p class="text-sm font-medium text-base-content">Default Model</p>
              <p class="text-xs text-base-content/50 mt-0.5">
                Model used when spawning new agents and sessions
              </p>
            </div>
            <div class="flex items-center gap-2">
              <form phx-change="save_setting">
                <input type="hidden" name="key" value="default_model" />
                <select
                  class="select select-bordered select-sm w-36"
                  name="value"
                >
                  <option
                    :for={{val, label} <- @models}
                    value={val}
                    selected={@settings["default_model"] == val}
                  >
                    {label}
                  </option>
                </select>
              </form>
              <button
                :if={!is_default?(@settings, "default_model")}
                phx-click="reset_setting"
                phx-value-key="default_model"
                class="btn btn-ghost btn-xs"
                title="Reset to default"
              >
                <.icon name="hero-arrow-uturn-left" class="w-3.5 h-3.5" />
              </button>
            </div>
          </div>

          <%!-- CLI Idle Timeout --%>
          <div class="flex items-center justify-between px-5 py-4">
            <div>
              <p class="text-sm font-medium text-base-content">CLI Idle Timeout</p>
              <p class="text-xs text-base-content/50 mt-0.5">
                How long before an idle Claude process is killed (seconds)
              </p>
            </div>
            <div class="flex items-center gap-2">
              <form phx-change="save_setting" class="flex items-center gap-2">
                <input type="hidden" name="key" value="cli_idle_timeout_ms" />
                <input
                  type="number"
                  name="value"
                  value={
                    div(
                      String.to_integer(
                        case @settings["cli_idle_timeout_ms"] do
                          v when v in [nil, ""] -> "300000"
                          v -> v
                        end
                      ),
                      1000
                    )
                  }
                  min="30"
                  max="3600"
                  step="30"
                  class="input input-bordered input-sm w-24 text-right"
                  phx-debounce="500"
                />
                <span class="text-xs text-base-content/50">sec</span>
              </form>
              <button
                :if={!is_default?(@settings, "cli_idle_timeout_ms")}
                phx-click="reset_setting"
                phx-value-key="cli_idle_timeout_ms"
                class="btn btn-ghost btn-xs"
                title="Reset to default"
              >
                <.icon name="hero-arrow-uturn-left" class="w-3.5 h-3.5" />
              </button>
            </div>
          </div>

          <%!-- TTS Voice --%>
          <div class="flex items-center justify-between px-5 py-4">
            <div>
              <p class="text-sm font-medium text-base-content">TTS Voice</p>
              <p class="text-xs text-base-content/50 mt-0.5">
                Default voice for text-to-speech notifications
              </p>
            </div>
            <div class="flex items-center gap-2">
              <form phx-change="save_setting">
                <input type="hidden" name="key" value="tts_voice" />
                <select
                  class="select select-bordered select-sm w-36"
                  name="value"
                >
                  <option :for={v <- @voices} value={v} selected={@settings["tts_voice"] == v}>
                    {v}
                  </option>
                </select>
              </form>
              <button
                :if={!is_default?(@settings, "tts_voice")}
                phx-click="reset_setting"
                phx-value-key="tts_voice"
                class="btn btn-ghost btn-xs"
                title="Reset to default"
              >
                <.icon name="hero-arrow-uturn-left" class="w-3.5 h-3.5" />
              </button>
            </div>
          </div>

          <%!-- TTS Rate --%>
          <div class="flex items-center justify-between px-5 py-4">
            <div>
              <p class="text-sm font-medium text-base-content">TTS Rate</p>
              <p class="text-xs text-base-content/50 mt-0.5">
                Speech rate in words per minute
              </p>
            </div>
            <div class="flex items-center gap-2">
              <form phx-change="save_setting">
                <input type="hidden" name="key" value="tts_rate" />
                <input
                  type="number"
                  name="value"
                  value={@settings["tts_rate"]}
                  min="90"
                  max="450"
                  step="10"
                  class="input input-bordered input-sm w-24 text-right"
                  phx-debounce="500"
                />
              </form>
              <span class="text-xs text-base-content/50">wpm</span>
              <button
                :if={!is_default?(@settings, "tts_rate")}
                phx-click="reset_setting"
                phx-value-key="tts_rate"
                class="btn btn-ghost btn-xs"
                title="Reset to default"
              >
                <.icon name="hero-arrow-uturn-left" class="w-3.5 h-3.5" />
              </button>
            </div>
          </div>
        </div>
      </div>
    </section>
  </div>
  """
end
```

- [ ] **Step 5: Verify compilation**

```bash
cd /Users/urielmaldonado/projects/eits/web && mix compile 2>&1 | tail -10
```

Expected: no errors.

- [ ] **Step 6: Commit**

```bash
cd /Users/urielmaldonado/projects/eits/web && git add lib/eye_in_the_sky_web/live/overview_live/settings.ex && git commit -m "feat: add Appearance/theme picker to Settings General tab"
```

---

### Task 6: Manual verification

- [ ] **Step 1: Start the server**

```bash
cd /Users/urielmaldonado/projects/eits/web && PORT=5002 DISABLE_AUTH=true mix phx.server
```

- [ ] **Step 2: Open Settings > General**

Navigate to `http://localhost:5002/settings`. Verify the Appearance section appears at the top with six theme buttons: Dark, Light, Latte, Frappé, Macchiato, Mocha.

- [ ] **Step 3: Click each theme**

Click "Mocha" — page should immediately switch to Catppuccin Mocha colors. Inspect `<html>` in DevTools, confirm `data-theme="catppuccin-mocha"`.

Click "Latte" — page switches to a light lavender/rose palette.

Click "Dark" — returns to the custom Claude.ai dark palette.

- [ ] **Step 4: Verify persistence**

While on "Macchiato", open DevTools console and run:
```js
localStorage.getItem("theme") // should return "catppuccin-macchiato"
```

Reload the page — theme should persist (localStorage).

Clear localStorage:
```js
localStorage.removeItem("theme")
```

Reload — theme should still be Macchiato (from DB server render).

- [ ] **Step 5: Stop the server and run final compile check**

```bash
cd /Users/urielmaldonado/projects/eits/web && mix compile --warnings-as-errors 2>&1 | tail -10
```

Expected: clean compile, no errors or warnings.
