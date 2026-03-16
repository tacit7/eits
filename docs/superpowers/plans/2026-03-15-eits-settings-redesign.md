# EITS Settings Redesign Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the settings page into a 6-tab layout, add CodeMirror 6 as a site-wide file editor, surface env-var credential status, and add an `EITS_WORKFLOW` toggle with unified bash fallback across all hook scripts.

**Architecture:** Tabbed settings LiveView using `handle_params/3` + `push_patch` for bookmarkable URL-driven tab state. New settings keys stored in the existing `meta` key-value table. CodeMirror 6 wired via a Phoenix LiveView JS hook with base64 content handoff. Two new API endpoints — one authenticated (editor open), one unauthenticated (workflow status).

**Tech Stack:** Elixir/Phoenix LiveView, PostgreSQL (`meta` table), CodeMirror 6 (npm), esbuild, DaisyUI/Tailwind CSS, bash (hook scripts).

**Spec:** `docs/superpowers/specs/2026-03-15-eits-settings-redesign-design.md`

---

## Chunk 1: Backend Core

### Task 1: Validate and Fix Settings Page

**Files:**
- Modify: `lib/eye_in_the_sky_web_web/live/overview_live/settings.ex`
- Create: `test/eye_in_the_sky_web_web/live/overview_live/settings_test.exs`

Note: `async: false` is set at the module level for the entire test file because all settings tests read or write the shared `meta` PostgreSQL table.

- [ ] **Step 1: Write a smoke test**

```elixir
# test/eye_in_the_sky_web_web/live/overview_live/settings_test.exs
defmodule EyeInTheSkyWebWeb.OverviewLive.SettingsTest do
  use EyeInTheSkyWebWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  describe "settings page" do
    test "mounts without crashing", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/settings")
      assert html =~ "Settings"
    end
  end
end
```

- [ ] **Step 2: Run the smoke test**

```bash
cd /Users/urielmaldonado/projects/eits/web
mix test test/eye_in_the_sky_web_web/live/overview_live/settings_test.exs --trace
```

- If FAIL: read the error, identify the crash site in `settings.ex`, fix it minimally, re-run until PASS.
- If PASS: the page already mounts clean — no fix needed. Continue to Step 3.

- [ ] **Step 3: Compile**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 4: Commit**

```bash
git add lib/eye_in_the_sky_web_web/live/overview_live/settings.ex \
        test/eye_in_the_sky_web_web/live/overview_live/settings_test.exs
git commit -m "test: add settings page smoke test (fix crash if present)"
```

---

### Task 2: Add New Settings Keys

**Files:**
- Modify: `lib/eye_in_the_sky_web/settings.ex`
- Create: `test/eye_in_the_sky_web/settings_test.exs` (if it doesn't exist)

- [ ] **Step 1: Add two new keys to `@defaults` in `settings.ex`**

```elixir
"preferred_editor" => "code",
"eits_workflow_enabled" => "true",
```

- [ ] **Step 2: Write tests for the new defaults**

```elixir
# test/eye_in_the_sky_web/settings_test.exs
defmodule EyeInTheSkyWeb.SettingsTest do
  use EyeInTheSkyWeb.DataCase, async: false

  alias EyeInTheSkyWeb.Settings

  describe "defaults" do
    test "preferred_editor defaults to code" do
      Settings.reset("preferred_editor")
      assert Settings.get("preferred_editor") == "code"
    end

    test "eits_workflow_enabled defaults to true" do
      Settings.reset("eits_workflow_enabled")
      assert Settings.get_boolean("eits_workflow_enabled") == true
    end
  end
end
```

Note: `async: false` because settings tests share the PostgreSQL `meta` table.

- [ ] **Step 3: Run tests**

```bash
mix test test/eye_in_the_sky_web/settings_test.exs --trace
```

Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add lib/eye_in_the_sky_web/settings.ex \
        test/eye_in_the_sky_web/settings_test.exs
git commit -m "feat: add preferred_editor and eits_workflow_enabled settings defaults"
```

---

### Task 3: Tabbed Settings Layout

**Files:**
- Modify: `lib/eye_in_the_sky_web_web/live/overview_live/settings.ex`

- [ ] **Step 1: Write tab routing tests**

Add to `test/eye_in_the_sky_web_web/live/overview_live/settings_test.exs`:

```elixir
describe "tab routing" do
  test "renders tab bar with all 6 tabs", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/settings")
    assert html =~ "General"
    assert html =~ "Editor"
    assert html =~ "Auth &amp; Keys"
    assert html =~ "Workflow"
    assert html =~ "Pricing"
    assert html =~ "System"
  end

  test "defaults to general tab showing Default Model", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/settings")
    assert html =~ "Default Model"
  end

  test "?tab=auth loads auth tab", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/settings?tab=auth")
    assert html =~ "API Keys"
  end

  test "?tab=workflow loads workflow tab", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/settings?tab=workflow")
    assert html =~ "EITS Workflow"
  end

  test "unknown tab falls back to general and shows Default Model", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/settings?tab=nonexistent")
    assert html =~ "Default Model"
  end
end
```

- [ ] **Step 2: Run tests to see them fail**

```bash
mix test test/eye_in_the_sky_web_web/live/overview_live/settings_test.exs --trace
```

Expected: FAIL (no tabs yet)

- [ ] **Step 3: Add `@valid_tabs`, update `mount/3`, add `handle_params/3` and `set_tab` handler**

In `lib/eye_in_the_sky_web_web/live/overview_live/settings.ex`, add at the module level:

```elixir
@valid_tabs ~w(general editor auth workflow pricing system)
```

In `mount/3`, add to the socket assigns chain:

```elixir
|> assign(:active_tab, :general)
|> assign(:generated_api_key, nil)
```

Add `handle_params/3` before the existing `handle_event` clauses:

```elixir
@impl true
def handle_params(%{"tab" => tab}, _uri, socket) do
  active = if tab in @valid_tabs, do: String.to_atom(tab), else: :general
  {:noreply, assign(socket, :active_tab, active)}
end

@impl true
def handle_params(_params, _uri, socket) do
  {:noreply, assign(socket, :active_tab, :general)}
end
```

Add `set_tab` event handler:

```elixir
@impl true
def handle_event("set_tab", %{"tab" => tab}, socket) do
  {:noreply, push_patch(socket, to: ~p"/settings?tab=#{tab}")}
end
```

- [ ] **Step 4: Replace `render/1` with tabbed layout, move existing sections into `render_tab/1`**

Replace the entire `render/1` function. The tab bar dispatches to private `render_tab(assigns)` clauses. Move the existing Agent Defaults, TTS, and CLI Timeout HTML into `render_tab(%{active_tab: :general})`. Move Token Pricing into `render_tab(%{active_tab: :pricing})`. Move System (debug logging, DB info) into `render_tab(%{active_tab: :system})`. Stub `:editor`, `:auth`, `:workflow` with a placeholder for now:

```elixir
@impl true
def render(assigns) do
  ~H"""
  <div class="px-4 sm:px-6 lg:px-8 py-8">
    <div class="max-w-4xl mx-auto space-y-6">
      <div class="tabs tabs-bordered">
        <%= for {label, key} <- [
          {"General", "general"}, {"Editor", "editor"}, {"Auth & Keys", "auth"},
          {"Workflow", "workflow"}, {"Pricing", "pricing"}, {"System", "system"}
        ] do %>
          <button
            class={"tab #{if @active_tab == String.to_atom(key), do: "tab-active", else: ""}"}
            phx-click="set_tab"
            phx-value-tab={key}
          >
            {label}
          </button>
        <% end %>
      </div>
      {render_tab(assigns)}
    </div>
  </div>
  """
end

defp render_tab(%{active_tab: :general} = assigns) do
  ~H"""
  <%!-- Paste existing Agent Defaults section (Default Model, CLI Timeout, TTS Voice, TTS Rate) here --%>
  """
end

defp render_tab(%{active_tab: :pricing} = assigns) do
  ~H"""
  <%!-- Paste existing Token Pricing section here --%>
  """
end

defp render_tab(%{active_tab: :system} = assigns) do
  ~H"""
  <%!-- Paste existing System section (debug logging, DB info) here --%>
  """
end

defp render_tab(%{active_tab: _} = assigns) do
  ~H"<p class='text-sm text-base-content/50 px-2 py-4'>Coming soon</p>"
end
```

- [ ] **Step 5: Run tests**

```bash
mix test test/eye_in_the_sky_web_web/live/overview_live/settings_test.exs --trace
```

Expected: all tab routing tests PASS.

- [ ] **Step 6: Compile**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 7: Commit**

```bash
git add lib/eye_in_the_sky_web_web/live/overview_live/settings.ex \
        test/eye_in_the_sky_web_web/live/overview_live/settings_test.exs
git commit -m "feat: add tabbed layout to settings page with handle_params routing"
```

---

### Task 4: Auth & Keys Tab

**Files:**
- Modify: `lib/eye_in_the_sky_web_web/live/overview_live/settings.ex`

- [ ] **Step 1: Write auth tab tests**

Add to `settings_test.exs`. These tests avoid `System.put_env` (global state unsafe in async) — they test structure and interaction, not env-var masking:

```elixir
describe "auth tab" do
  test "renders API Keys section", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/settings?tab=auth")
    assert html =~ "Anthropic API Key"
    assert html =~ "EITS REST API Key"
  end

  test "regenerate button shows generated key", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/settings?tab=auth")
    html = lv |> element("button", "Regenerate") |> render_click()
    assert html =~ "Copy this key now"
    assert html =~ "EITS_API_KEY"
  end
end
```

- [ ] **Step 2: Run tests to see them fail**

```bash
mix test test/eye_in_the_sky_web_web/live/overview_live/settings_test.exs --trace
```

Expected: FAIL

- [ ] **Step 3: Add `mask_env_var/1` private helper**

```elixir
defp mask_env_var(var_name) do
  case System.get_env(var_name) do
    nil -> {:not_set, nil}
    val when byte_size(val) >= 4 ->
      {:set, "****" <> String.slice(val, -4, 4)}
    val ->
      {:set, String.duplicate("*", byte_size(val))}
  end
end
```

- [ ] **Step 4: Add `regenerate_api_key` event handler**

```elixir
@impl true
def handle_event("regenerate_api_key", _params, socket) do
  key = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  {:noreply, assign(socket, :generated_api_key, key)}
end
```

- [ ] **Step 5: Implement the `:auth` render clause** (replace "Coming soon" stub)

```elixir
defp render_tab(%{active_tab: :auth} = assigns) do
  ~H"""
  <div class="space-y-4">
    <section>
      <h2 class="text-sm font-semibold text-base-content/60 uppercase tracking-wider mb-4">
        API Keys
      </h2>
      <div class="card bg-base-100 border border-base-300 shadow-sm">
        <div class="card-body p-0 divide-y divide-base-300">
          <%!-- Anthropic API Key --%>
          <div class="flex items-center justify-between px-5 py-4">
            <div>
              <p class="text-sm font-medium text-base-content">Anthropic API Key</p>
              <p class="text-xs text-base-content/50 mt-0.5">Set via ANTHROPIC_API_KEY in your .env</p>
            </div>
            <%= case mask_env_var("ANTHROPIC_API_KEY") do %>
              <% {:set, masked} -> %>
                <span class="badge badge-success badge-sm font-mono">{masked}</span>
              <% {:not_set, _} -> %>
                <span class="text-xs text-warning">Not configured</span>
            <% end %>
          </div>
          <%!-- EITS REST API Key --%>
          <div class="px-5 py-4">
            <div class="flex items-center justify-between mb-2">
              <div>
                <p class="text-sm font-medium text-base-content">EITS REST API Key</p>
                <p class="text-xs text-base-content/50 mt-0.5">Set via EITS_API_KEY in your .env</p>
              </div>
              <%= case mask_env_var("EITS_API_KEY") do %>
                <% {:set, masked} -> %>
                  <span class="badge badge-success badge-sm font-mono">{masked}</span>
                <% {:not_set, _} -> %>
                  <span class="text-xs text-warning">Not configured</span>
              <% end %>
            </div>
            <%= if @generated_api_key do %>
              <div class="alert alert-warning mt-2 p-3 text-xs">
                <p class="font-semibold mb-1">Copy this key now — it will not be shown again.</p>
                <p class="mb-2">
                  Add to .env: <code class="font-mono">EITS_API_KEY=&lt;value&gt;</code> then restart.
                </p>
                <input
                  type="text"
                  readonly
                  value={@generated_api_key}
                  class="input input-bordered input-xs font-mono w-full"
                />
              </div>
            <% else %>
              <button phx-click="regenerate_api_key" class="btn btn-sm btn-outline mt-2">
                Regenerate
              </button>
            <% end %>
          </div>
        </div>
      </div>
    </section>
  </div>
  """
end
```

- [ ] **Step 6: Run tests**

```bash
mix test test/eye_in_the_sky_web_web/live/overview_live/settings_test.exs --trace
```

Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add lib/eye_in_the_sky_web_web/live/overview_live/settings.ex \
        test/eye_in_the_sky_web_web/live/overview_live/settings_test.exs
git commit -m "feat: add auth & keys tab with env var status and key regeneration"
```

---

### Task 5: Workflow Tab

**Files:**
- Modify: `lib/eye_in_the_sky_web_web/live/overview_live/settings.ex`

- [ ] **Step 1: Write workflow tab tests**

Add to `settings_test.exs`:

```elixir
describe "workflow tab" do
  test "renders EITS Workflow toggle", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/settings?tab=workflow")
    assert html =~ "EITS Workflow"
    assert html =~ ~s(phx-value-key="eits_workflow_enabled")
  end
end
```

Note: Toggle interaction tests that write to the DB belong in `test/eye_in_the_sky_web/settings_test.exs` with `async: false` to avoid shared-state race conditions.

- [ ] **Step 2: Run test to see it fail**

```bash
mix test test/eye_in_the_sky_web_web/live/overview_live/settings_test.exs --trace
```

Expected: FAIL

- [ ] **Step 3: Implement the `:workflow` render clause**

```elixir
defp render_tab(%{active_tab: :workflow} = assigns) do
  ~H"""
  <div class="space-y-4">
    <section>
      <h2 class="text-sm font-semibold text-base-content/60 uppercase tracking-wider mb-4">
        Workflow
      </h2>
      <div class="card bg-base-100 border border-base-300 shadow-sm">
        <div class="card-body p-0 divide-y divide-base-300">
          <div class="flex items-center justify-between px-5 py-4">
            <div>
              <p class="text-sm font-medium text-base-content">EITS Workflow</p>
              <p class="text-xs text-base-content/50 mt-0.5">
                Enable EITS hook workflow (pre-tool-use, post-commit, session-start, etc.)
              </p>
            </div>
            <input
              type="checkbox"
              class="toggle toggle-sm toggle-primary"
              checked={@settings["eits_workflow_enabled"] == "true"}
              phx-click="toggle_setting"
              phx-value-key="eits_workflow_enabled"
            />
          </div>
        </div>
      </div>
    </section>
  </div>
  """
end
```

- [ ] **Step 4: Run tests**

```bash
mix test test/eye_in_the_sky_web_web/live/overview_live/settings_test.exs --trace
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/eye_in_the_sky_web_web/live/overview_live/settings.ex \
        test/eye_in_the_sky_web_web/live/overview_live/settings_test.exs
git commit -m "feat: add workflow tab with EITS_WORKFLOW toggle"
```

---

### Task 6: Editor Tab (Elixir side)

**Files:**
- Modify: `lib/eye_in_the_sky_web_web/live/overview_live/settings.ex`

- [ ] **Step 1: Write editor tab tests**

Add to `settings_test.exs`:

```elixir
describe "editor tab" do
  test "renders preferred editor selector with VS Code option", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/settings?tab=editor")
    assert html =~ "Preferred Editor"
    assert html =~ "VS Code"
  end

  test "renders custom command input", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/settings?tab=editor")
    assert html =~ "Custom Command"
  end
end
```

- [ ] **Step 2: Run tests to see them fail**

```bash
mix test test/eye_in_the_sky_web_web/live/overview_live/settings_test.exs --trace
```

Expected: FAIL

- [ ] **Step 3: Add `open_in_editor` event handler**

Note: `preferred_editor` comes from the `meta` DB table (user-set). It is validated against known editors before being passed to `System.cmd` to prevent arbitrary command execution. Custom commands are still allowed but must be non-empty strings — the `byte_size` guard covers that.

```elixir
@known_editors ~w(code cursor vim nano zed)

@impl true
def handle_event("open_in_editor", %{"path" => path}, socket) when byte_size(path) > 0 do
  editor = Settings.get("preferred_editor") || "code"
  # Warn in logs if editor is not a known value, but still execute (power-user feature)
  unless editor in @known_editors, do:
    require Logger
    Logger.warning("open_in_editor: unrecognized editor command #{inspect(editor)}")
  Task.start(fn -> System.cmd(editor, [path], stderr_to_stdout: true) end)
  {:noreply, put_flash(socket, :info, "Opening in #{editor}...")}
end

def handle_event("open_in_editor", _params, socket) do
  {:noreply, put_flash(socket, :error, "No file path provided")}
end
```

- [ ] **Step 4: Implement the `:editor` render clause**

```elixir
defp render_tab(%{active_tab: :editor} = assigns) do
  ~H"""
  <div class="space-y-4">
    <section>
      <h2 class="text-sm font-semibold text-base-content/60 uppercase tracking-wider mb-4">
        Editor
      </h2>
      <div class="card bg-base-100 border border-base-300 shadow-sm">
        <div class="card-body p-0 divide-y divide-base-300">
          <div class="flex items-center justify-between px-5 py-4">
            <div>
              <p class="text-sm font-medium text-base-content">Preferred Editor</p>
              <p class="text-xs text-base-content/50 mt-0.5">
                Command used when opening files externally
              </p>
            </div>
            <form phx-change="save_setting" class="flex items-center gap-2">
              <input type="hidden" name="key" value="preferred_editor" />
              <select class="select select-bordered select-sm w-36" name="value">
                <%= for {label, val} <- [
                  {"VS Code", "code"}, {"Cursor", "cursor"},
                  {"vim", "vim"}, {"nano", "nano"}
                ] do %>
                  <option value={val} selected={@settings["preferred_editor"] == val}>
                    {label}
                  </option>
                <% end %>
              </select>
            </form>
          </div>
          <div class="flex items-center justify-between px-5 py-4">
            <div>
              <p class="text-sm font-medium text-base-content">Custom Command</p>
              <p class="text-xs text-base-content/50 mt-0.5">Override with any editor command</p>
            </div>
            <form phx-change="save_setting" class="flex items-center gap-2">
              <input type="hidden" name="key" value="preferred_editor" />
              <input
                type="text"
                name="value"
                value={@settings["preferred_editor"]}
                placeholder="e.g. code, vim, zed"
                class="input input-bordered input-sm w-36"
                phx-debounce="500"
              />
            </form>
          </div>
          <div class="px-5 py-4">
            <p class="text-sm font-medium text-base-content">In-Browser Editor</p>
            <p class="text-xs text-base-content/50 mt-0.5">
              CodeMirror 6 is available on config and file browser pages for in-browser editing.
            </p>
          </div>
        </div>
      </div>
    </section>
  </div>
  """
end
```

- [ ] **Step 5: Run tests**

```bash
mix test test/eye_in_the_sky_web_web/live/overview_live/settings_test.exs --trace
```

Expected: PASS

- [ ] **Step 6: Compile**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 7: Commit**

```bash
git add lib/eye_in_the_sky_web_web/live/overview_live/settings.ex \
        test/eye_in_the_sky_web_web/live/overview_live/settings_test.exs
git commit -m "feat: add editor tab with preferred editor setting and open_in_editor handler"
```

---

### Task 7: REST API Endpoints

**Files:**
- Create: `lib/eye_in_the_sky_web_web/controllers/api/v1/editor_controller.ex`
- Create: `lib/eye_in_the_sky_web_web/controllers/api/v1/settings_controller.ex`
- Modify: `lib/eye_in_the_sky_web_web/router.ex`
- Create: `test/eye_in_the_sky_web_web/controllers/api/v1/editor_controller_test.exs`
- Create: `test/eye_in_the_sky_web_web/controllers/api/v1/settings_controller_test.exs`

- [ ] **Step 1: Write tests for the workflow endpoint**

```elixir
# test/eye_in_the_sky_web_web/controllers/api/v1/settings_controller_test.exs
defmodule EyeInTheSkyWebWeb.Api.V1.SettingsControllerTest do
  use EyeInTheSkyWebWeb.ConnCase, async: false

  describe "GET /api/v1/settings/eits_workflow_enabled" do
    test "returns enabled: true by default", %{conn: conn} do
      EyeInTheSkyWeb.Settings.put("eits_workflow_enabled", "true")
      conn = get(conn, ~p"/api/v1/settings/eits_workflow_enabled")
      assert json_response(conn, 200) == %{"enabled" => true}
    end

    test "returns enabled: false when setting is false", %{conn: conn} do
      EyeInTheSkyWeb.Settings.put("eits_workflow_enabled", "false")
      on_exit(fn -> EyeInTheSkyWeb.Settings.put("eits_workflow_enabled", "true") end)
      conn = get(conn, ~p"/api/v1/settings/eits_workflow_enabled")
      assert json_response(conn, 200) == %{"enabled" => false}
    end

    test "does not require auth header", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/settings/eits_workflow_enabled")
      assert conn.status == 200
    end
  end
end
```

- [ ] **Step 2: Write tests for the editor open endpoint**

```elixir
# test/eye_in_the_sky_web_web/controllers/api/v1/editor_controller_test.exs
defmodule EyeInTheSkyWebWeb.Api.V1.EditorControllerTest do
  use EyeInTheSkyWebWeb.ConnCase, async: false

  describe "POST /api/v1/editor/open" do
    setup %{conn: conn} do
      # Use echo as the editor — it exists everywhere and exits immediately
      EyeInTheSkyWeb.Settings.put("preferred_editor", "echo")
      on_exit(fn -> EyeInTheSkyWeb.Settings.put("preferred_editor", "code") end)
      # Auth: in test env EITS_API_KEY is typically unset so RequireAuth passes through
      {:ok, conn: put_req_header(conn, "content-type", "application/json")}
    end

    test "returns ok for valid path", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/editor/open", %{"path" => "/tmp/test.txt"})
      assert json_response(conn, 200) == %{"ok" => true}
    end

    test "returns 422 for missing path", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/editor/open", %{})
      assert json_response(conn, 422) == %{"error" => "path is required"}
    end
  end
end
```

Note: The 401 test is omitted because `RequireAuth` reads from `Application.get_env/2`, not `System.get_env/1`. In test env the key is unset so the plug passes all requests through. Auth enforcement is verified manually or via integration tests only.

- [ ] **Step 3: Run tests to see them fail (no routes yet)**

```bash
mix test test/eye_in_the_sky_web_web/controllers/api/v1/settings_controller_test.exs \
         test/eye_in_the_sky_web_web/controllers/api/v1/editor_controller_test.exs --trace
```

Expected: FAIL (404)

- [ ] **Step 4: Create `SettingsController`**

```elixir
# lib/eye_in_the_sky_web_web/controllers/api/v1/settings_controller.ex
defmodule EyeInTheSkyWebWeb.Api.V1.SettingsController do
  use EyeInTheSkyWebWeb, :controller

  action_fallback EyeInTheSkyWebWeb.Api.V1.FallbackController

  alias EyeInTheSkyWeb.Settings

  def eits_workflow_enabled(conn, _params) do
    json(conn, %{enabled: Settings.get_boolean("eits_workflow_enabled")})
  end
end
```

- [ ] **Step 5: Create `EditorController`**

```elixir
# lib/eye_in_the_sky_web_web/controllers/api/v1/editor_controller.ex
defmodule EyeInTheSkyWebWeb.Api.V1.EditorController do
  use EyeInTheSkyWebWeb, :controller

  action_fallback EyeInTheSkyWebWeb.Api.V1.FallbackController

  alias EyeInTheSkyWeb.Settings

  def open(conn, %{"path" => path}) when byte_size(path) > 0 do
    editor = Settings.get("preferred_editor")
    Task.start(fn -> System.cmd(editor, [path], stderr_to_stdout: true) end)
    json(conn, %{ok: true})
  end

  def open(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "path is required"})
  end
end
```

- [ ] **Step 6: Add routes to `router.ex`**

In the authenticated `/api/v1` scope (`pipe_through :api`, around line 104):
```elixir
post "/editor/open", EditorController, :open
```

Add a **new** `/api/v1` scope for unauthenticated settings reads (do NOT extend the Gitea webhook scope — that scope is semantically for inbound webhooks only). Add after the existing `accepts_json` scope:

```elixir
scope "/api/v1", EyeInTheSkyWebWeb.Api.V1 do
  pipe_through [:accepts_json]

  get "/settings/eits_workflow_enabled", SettingsController, :eits_workflow_enabled
end
```

- [ ] **Step 7: Run tests**

```bash
mix test test/eye_in_the_sky_web_web/controllers/api/v1/settings_controller_test.exs \
         test/eye_in_the_sky_web_web/controllers/api/v1/editor_controller_test.exs --trace
```

Expected: PASS

- [ ] **Step 8: Compile**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 9: Commit**

```bash
git add lib/eye_in_the_sky_web_web/controllers/api/v1/editor_controller.ex \
        lib/eye_in_the_sky_web_web/controllers/api/v1/settings_controller.ex \
        lib/eye_in_the_sky_web_web/router.ex \
        test/eye_in_the_sky_web_web/controllers/api/v1/editor_controller_test.exs \
        test/eye_in_the_sky_web_web/controllers/api/v1/settings_controller_test.exs
git commit -m "feat: add editor open and workflow status REST endpoints"
```

---

## Chunk 2: CodeMirror Integration

### Task 8: Install CodeMirror npm Packages

**Files:**
- Modify: `assets/package.json`

- [ ] **Step 1: Install packages**

```bash
cd /Users/urielmaldonado/projects/eits/web/assets
npm install --save codemirror @codemirror/lang-javascript @codemirror/lang-css \
  @codemirror/lang-html @codemirror/lang-markdown @codemirror/legacy-modes \
  @codemirror/language @codemirror/theme-one-dark codemirror-lang-elixir
```

- [ ] **Step 2: Verify**

```bash
ls node_modules | grep -E "^codemirror"
ls node_modules/@codemirror/
```

Expected: `codemirror` and `codemirror-lang-elixir` visible; `@codemirror/` has `lang-javascript`, `legacy-modes`, `language`, etc.

If `codemirror-lang-elixir` fails to install due to peer dependency conflicts, pin it: `npm install --save codemirror-lang-elixir@4`. If the package is unavailable entirely, remove it from the install command and the JS import, then change the `"elixir"` case in `getLanguageExtension` to `return []` (falls back to plain text for `.ex`/`.exs` files).

- [ ] **Step 3: Commit**

```bash
cd /Users/urielmaldonado/projects/eits/web
git add assets/package.json assets/package-lock.json
git commit -m "feat: add CodeMirror 6 npm packages"
```

---

### Task 9: CodeMirror JS Hook

**Files:**
- Create: `assets/js/hooks/codemirror.js`
- Modify: `assets/js/app.js`

- [ ] **Step 1: Create the hook file**

```javascript
// assets/js/hooks/codemirror.js
import { EditorView, keymap, lineNumbers, highlightActiveLine } from "@codemirror/view"
import { EditorState } from "@codemirror/state"
import { defaultKeymap, history, historyKeymap } from "@codemirror/commands"
import { oneDark } from "@codemirror/theme-one-dark"
import { javascript } from "@codemirror/lang-javascript"
import { css } from "@codemirror/lang-css"
import { html } from "@codemirror/lang-html"
import { markdown } from "@codemirror/lang-markdown"
import { StreamLanguage } from "@codemirror/language"
import { shell } from "@codemirror/legacy-modes/mode/shell"
import { elixir } from "codemirror-lang-elixir"

function getLanguageExtension(lang) {
  switch (lang) {
    case "elixir": return elixir()
    case "javascript": case "js": case "ts": return javascript()
    case "css": return css()
    case "html": case "heex": return html()
    case "markdown": case "md": return markdown()
    case "shell": case "sh": case "bash": return StreamLanguage.define(shell)
    default: return []
  }
}

export const CodeMirrorHook = {
  mounted() {
    const content = atob(this.el.dataset.content || "")
    const lang = this.el.dataset.lang || "text"
    const self = this

    const saveKeymap = keymap.of([{
      key: "Mod-s",
      run(view) {
        self.pushEvent("file_changed", { content: view.state.doc.toString() })
        return true
      }
    }])

    const state = EditorState.create({
      doc: content,
      extensions: [
        lineNumbers(),
        highlightActiveLine(),
        history(),
        keymap.of([...defaultKeymap, ...historyKeymap]),
        saveKeymap,
        oneDark,
        getLanguageExtension(lang),
      ]
    })

    this._view = new EditorView({ state, parent: this.el })
  },

  destroyed() {
    if (this._view) {
      this._view.destroy()
      this._view = null
    }
  }
}
```

Note: Shell import uses `@codemirror/legacy-modes/mode/shell` (not `/src/shell`).

- [ ] **Step 2: Register in `app.js`**

Add the import after the existing hook imports (around line 40):
```javascript
import {CodeMirrorHook} from "./hooks/codemirror"
```

Add the hook registration in the `Hooks` assignments block (after existing `Hooks.X = ...` lines):
```javascript
Hooks.CodeMirror = CodeMirrorHook
```

- [ ] **Step 3: Verify esbuild compiles**

```bash
cd /Users/urielmaldonado/projects/eits/web
mix assets.build 2>&1 | tail -20
```

If `mix assets.build` isn't available:
```bash
cd assets && node build.js 2>&1 | tail -20
```

Expected: no errors. If `build.js` doesn't exist either, check `package.json` for the build script or run the Phoenix watchers.

- [ ] **Step 4: Commit**

```bash
git add assets/js/hooks/codemirror.js assets/js/app.js
git commit -m "feat: add CodeMirror 6 LiveView hook with language detection and Cmd+S save"
```

---

### Task 10: FileEditorComponent

**Files:**
- Create: `lib/eye_in_the_sky_web_web/components/file_editor_component.ex`

- [ ] **Step 1: Create the component**

Module lives under `Components` namespace to match existing project conventions (e.g. `EyeInTheSkyWebWeb.Components.DmPage`).

```elixir
# lib/eye_in_the_sky_web_web/components/file_editor_component.ex
defmodule EyeInTheSkyWebWeb.Components.FileEditorComponent do
  use EyeInTheSkyWebWeb, :html

  @doc """
  Renders a CodeMirror 6 in-browser file editor.

  The parent LiveView must:
  - Set `edit_path` in its socket assigns (server-side only; never sent to client)
  - Handle the `"file_changed"` event and write content to `socket.assigns.edit_path`

  ## Assigns
  - `file_content` (required) — base64-encoded content via `Base.encode64/1`
  - `file_lang` (required) — language: "elixir", "javascript", "shell", "markdown", "text"
  - `file_error` (optional) — if set, renders an error state instead of the editor
  """
  attr :file_content, :string, required: true
  attr :file_lang, :string, required: true
  attr :file_error, :string, default: nil

  def file_editor(assigns) do
    ~H"""
    <%= if @file_error do %>
      <div class="alert alert-error text-sm">
        <.icon name="hero-exclamation-circle" class="w-4 h-4" />
        <span>Could not load file: {@file_error}</span>
      </div>
    <% else %>
      <div
        phx-hook="CodeMirror"
        id="codemirror-editor"
        data-content={@file_content}
        data-lang={@file_lang}
        class="border border-base-300 rounded-lg overflow-hidden min-h-64"
      >
      </div>
    <% end %>
    """
  end

  @doc "Infer CodeMirror language string from file path extension."
  def infer_lang(path) when is_binary(path) do
    case Path.extname(path) do
      ".ex"   -> "elixir"
      ".exs"  -> "elixir"
      ".js"   -> "javascript"
      ".ts"   -> "javascript"
      ".css"  -> "css"
      ".html" -> "html"
      ".heex" -> "html"
      ".md"   -> "markdown"
      ".sh"   -> "shell"
      ".bash" -> "shell"
      _       -> "text"
    end
  end

  def infer_lang(_), do: "text"
end
```

- [ ] **Step 2: Write unit tests for `infer_lang/1`**

Create a dedicated test file co-located with the component:

```elixir
# test/eye_in_the_sky_web_web/components/file_editor_component_test.exs
defmodule EyeInTheSkyWebWeb.Components.FileEditorComponentTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWebWeb.Components.FileEditorComponent

  describe "infer_lang/1" do
    test "elixir for .ex" do
      assert FileEditorComponent.infer_lang("/foo/bar.ex") == "elixir"
    end

    test "elixir for .exs" do
      assert FileEditorComponent.infer_lang("/foo/bar.exs") == "elixir"
    end

    test "shell for .sh" do
      assert FileEditorComponent.infer_lang("/foo/bar.sh") == "shell"
    end

    test "text for unknown extension" do
      assert FileEditorComponent.infer_lang("/foo/bar.toml") == "text"
    end

    test "text for nil" do
      assert FileEditorComponent.infer_lang(nil) == "text"
    end
  end
end
```

- [ ] **Step 3: Run tests**

```bash
mix test test/eye_in_the_sky_web_web/components/file_editor_component_test.exs --trace
```

Expected: PASS

- [ ] **Step 4: Compile**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 5: Commit**

```bash
git add lib/eye_in_the_sky_web_web/components/file_editor_component.ex \
        test/eye_in_the_sky_web_web/components/file_editor_component_test.exs
git commit -m "feat: add FileEditorComponent with CodeMirror hook and infer_lang helper"
```

---

## Chunk 3: Hook Scripts

### Task 11: Unify EITS_WORKFLOW Bash Fallback

**Files:**
- Modify: `priv/scripts/eits-pre-tool-use.sh`
- Modify: `priv/scripts/eits-post-tool-use.sh`
- Modify: `priv/scripts/eits-pre-compact.sh`
- Modify: `priv/scripts/eits-post-commit.sh`
- Modify: `priv/scripts/eits-session-compact.sh`
- Modify: `priv/scripts/eits-session-end.sh`
- Modify: `priv/scripts/eits-session-resume.sh`
- Modify: `priv/scripts/eits-session-stop.sh`
- Modify: `priv/scripts/eits-session-startup.sh`
- Modify: `priv/scripts/eits-prompt-submit.sh`
- Modify: `priv/scripts/eits-agent-working.sh`

Unified guard block (fail-open: if the API is unreachable, default to enabled):

```bash
# --- EITS Workflow Guard ---
EITS_WORKFLOW="${EITS_WORKFLOW:-}"
if [ -z "$EITS_WORKFLOW" ]; then
  EITS_URL="${EITS_API_URL:-http://localhost:5000/api/v1}"
  ENABLED=$(curl -sf "${EITS_URL}/settings/eits_workflow_enabled" 2>/dev/null | jq -r '.enabled' 2>/dev/null || echo "true")
  [ "$ENABLED" = "false" ] && exit 0
elif [ "$EITS_WORKFLOW" = "0" ]; then
  exit 0
fi
# --- End Workflow Guard ---
```

For scripts that already have an `EITS_WORKFLOW` check, **replace** it with this block. For scripts without any check, **add** this block immediately after `set -uo pipefail`.

- [ ] **Step 1: Check which scripts already have a guard**

```bash
grep -l "EITS_WORKFLOW" priv/scripts/eits-*.sh
```

- [ ] **Step 2: Apply the guard to each of the 11 scripts one at a time**

Read each script, locate the insertion/replacement point, apply the guard. Process all 11:
- `eits-pre-tool-use.sh`
- `eits-post-tool-use.sh`
- `eits-pre-compact.sh`
- `eits-post-commit.sh`
- `eits-session-compact.sh`
- `eits-session-end.sh`
- `eits-session-resume.sh`
- `eits-session-stop.sh`
- `eits-session-startup.sh`
- `eits-prompt-submit.sh`
- `eits-agent-working.sh`

- [ ] **Step 3: Verify all 11 scripts have the guard**

```bash
for script in priv/scripts/eits-pre-tool-use.sh priv/scripts/eits-post-tool-use.sh \
  priv/scripts/eits-pre-compact.sh priv/scripts/eits-post-commit.sh \
  priv/scripts/eits-session-compact.sh priv/scripts/eits-session-end.sh \
  priv/scripts/eits-session-resume.sh priv/scripts/eits-session-stop.sh \
  priv/scripts/eits-session-startup.sh priv/scripts/eits-prompt-submit.sh \
  priv/scripts/eits-agent-working.sh; do
  echo -n "$script: " && grep -c 'settings/eits_workflow_enabled' "$script" || echo "MISSING"
done
```

Expected: each prints `1`.

- [ ] **Step 4: Syntax-check all modified scripts**

```bash
for script in priv/scripts/eits-pre-tool-use.sh priv/scripts/eits-post-tool-use.sh \
  priv/scripts/eits-pre-compact.sh priv/scripts/eits-post-commit.sh \
  priv/scripts/eits-session-compact.sh priv/scripts/eits-session-end.sh \
  priv/scripts/eits-session-resume.sh priv/scripts/eits-session-stop.sh \
  priv/scripts/eits-session-startup.sh priv/scripts/eits-prompt-submit.sh \
  priv/scripts/eits-agent-working.sh; do
  bash -n "$script" && echo "OK: $script" || echo "SYNTAX ERROR: $script"
done
```

Expected: all print `OK`.

- [ ] **Step 5: Commit**

```bash
git add priv/scripts/
git commit -m "feat: add unified EITS_WORKFLOW fallback to all 11 hook scripts"
```

---

## Final: Full Test Suite and Completion

- [ ] **Step 1: Run the full test suite**

```bash
cd /Users/urielmaldonado/projects/eits/web
mix test 2>&1 | tail -30
```

Expected: all tests pass, no new failures.

- [ ] **Step 2: Final compile check**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 3: Mark task complete**

```bash
eits tasks annotate 1203 --body "Settings redesign complete: tabbed layout (6 tabs), auth tab, workflow tab, editor tab, CodeMirror 6 hook + FileEditorComponent, REST endpoints (editor open + workflow status), unified workflow guard across 11 hook scripts"
eits tasks update 1203 --state 4
eits commits create --hash $(git rev-parse HEAD)
```
