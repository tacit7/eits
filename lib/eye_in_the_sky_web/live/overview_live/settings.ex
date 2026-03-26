defmodule EyeInTheSkyWeb.OverviewLive.Settings do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.Settings
  alias EyeInTheSky.Repo

  @models [
    {"haiku", "Haiku"},
    {"sonnet", "Sonnet"},
    {"opus", "Opus"}
  ]

  @voices ["Ava", "Isha", "Lee", "Jamie", "Serena"]

  @themes [
    {"dark", "Dark"},
    {"light", "Light"},
    {"dracula", "Dracula"},
    {"latte", "Latte"},
    {"frappe", "Frappé"},
    {"macchiato", "Macchiato"},
    {"mocha", "Mocha"}
  ]

  @valid_tabs ~w(general editor auth workflow pricing system)

  @known_editors ~w(code cursor vim nano zed)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      EyeInTheSky.Events.subscribe_settings()
    end

    settings = Settings.all()
    # Normalize empty theme to default
    if settings["theme"] == "" do
      Settings.put("theme", "dark")
    end
    settings = if settings["theme"] == "", do: Map.put(settings, "theme", "dark"), else: settings
    db_info = load_db_info()

    socket =
      socket
      |> assign(:page_title, "Settings")
      |> assign(:sidebar_tab, :settings)
      |> assign(:sidebar_project, nil)
      |> assign(:settings, settings)
      |> assign(:db_info, db_info)
      |> assign(:models, @models)
      |> assign(:voices, @voices)
      |> assign(:themes, @themes)
      |> assign(:flash_key, nil)
      |> assign(:active_tab, :general)
      |> assign(:generated_api_key, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"tab" => tab}, _uri, socket) do
    active = if tab in @valid_tabs, do: String.to_atom(tab), else: :general
    {:noreply, assign(socket, :active_tab, active)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, :active_tab, :general)}
  end

  @impl true
  def handle_event("set_tab", %{"tab" => tab}, socket) do
    {:noreply, push_patch(socket, to: ~p"/settings?tab=#{tab}")}
  end

  @impl true
  def handle_event("regenerate_api_key", _params, socket) do
    key = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    {:noreply, assign(socket, :generated_api_key, key)}
  end

  @impl true
  def handle_event("open_in_editor", %{"path" => path}, socket) when byte_size(path) > 0 do
    editor = Settings.get("preferred_editor") || "code"

    unless editor in @known_editors do
      require Logger
      Logger.warning("open_in_editor: unrecognized editor command #{inspect(editor)}")
    end

    Task.start(fn -> System.cmd(editor, [path], stderr_to_stdout: true) end)
    {:noreply, put_flash(socket, :info, "Opening in #{editor}...")}
  end

  @impl true
  def handle_event("open_in_editor", _params, socket) do
    {:noreply, put_flash(socket, :error, "No file path provided")}
  end

  @impl true
  def handle_event("save_setting", %{"key" => key, "value" => value}, socket) do
    # Convert seconds to milliseconds for timeout storage
    value =
      if key == "cli_idle_timeout_ms" do
        case Integer.parse(value) do
          {secs, _} -> to_string(secs * 1000)
          :error -> value
        end
      else
        value
      end

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
  end

  @impl true
  def handle_event("set_theme", %{"theme" => theme}, socket) do
    Settings.put("theme", theme)
    settings = Settings.all()
    socket =
      socket
      |> assign(:settings, settings)
      |> flash_saved("theme")
      |> push_event("apply_theme", %{theme: theme})

    {:noreply, socket}
  end

  @impl true
  def handle_event("save_pricing", params, socket) do
    pricing_keys =
      for model <- ["opus", "sonnet", "haiku"],
          type <- ["input", "output", "cache_read", "cache_creation"],
          do: "pricing_#{model}_#{type}"

    Enum.each(pricing_keys, fn key ->
      if val = params[key] do
        Settings.put(key, val)
      end
    end)

    settings = Settings.all()
    {:noreply, socket |> assign(:settings, settings) |> flash_saved("pricing")}
  end

  @impl true
  def handle_event("reset_setting", %{"key" => key}, socket) do
    Settings.reset(key)
    settings = Settings.all()
    {:noreply, socket |> assign(:settings, settings) |> put_flash(:info, "Reset to default")}
  end

  @impl true
  def handle_event("reset_pricing", _params, socket) do
    defaults = Settings.defaults()

    defaults
    |> Enum.filter(fn {k, _} -> String.starts_with?(k, "pricing_") end)
    |> Enum.each(fn {k, _} -> Settings.reset(k) end)

    settings = Settings.all()

    {:noreply,
     socket |> assign(:settings, settings) |> put_flash(:info, "Pricing reset to defaults")}
  end

  @impl true
  def handle_event("toggle_setting", %{"key" => key}, socket) do
    current = Settings.get_boolean(key)
    Settings.put(key, to_string(!current))
    settings = Settings.all()
    {:noreply, socket |> assign(:settings, settings) |> flash_saved(key)}
  end

  @impl true
  def handle_info({:settings_changed, _key, _value}, socket) do
    settings = Settings.all()
    {:noreply, assign(socket, :settings, settings)}
  end

  defp flash_saved(socket, _key) do
    put_flash(socket, :info, "Saved")
  end

  defp load_db_info do
    db_config = Application.get_env(:eye_in_the_sky, EyeInTheSky.Repo)
    db_name = db_config[:database] || "unknown"

    size =
      case Repo.query("SELECT pg_database_size(current_database())") do
        {:ok, %{rows: [[s]]}} -> s
        _ -> 0
      end

    table_counts = load_table_counts()

    %{
      path: db_name,
      size: size,
      table_counts: table_counts
    }
  end

  defp load_table_counts do
    tables = ~w(sessions agents tasks notes messages projects commits prompts)

    Enum.map(tables, fn table ->
      count =
        case Repo.query("SELECT COUNT(*) FROM #{table}") do
          {:ok, %{rows: [[c]]}} -> c
          _ -> 0
        end

      {table, count}
    end)
  end

  defp format_db_size(bytes) when bytes >= 1_048_576 do
    "#{Float.round(bytes / 1_048_576, 1)} MB"
  end

  defp format_db_size(bytes) when bytes >= 1024 do
    "#{Float.round(bytes / 1024, 1)} KB"
  end

  defp format_db_size(bytes), do: "#{bytes} B"

  defp is_default?(settings, key) do
    defaults = Settings.defaults()
    settings[key] == defaults[key]
  end

  defp mask_env_var(var_name) do
    case System.get_env(var_name) do
      nil ->
        {:not_set, nil}

      val when byte_size(val) >= 4 ->
        {:set, "****" <> String.slice(val, -4, 4)}

      val ->
        {:set, String.duplicate("*", byte_size(val))}
    end
  end

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
    <div class="space-y-6">
      <section>
        <h2 class="text-sm font-semibold text-base-content/60 uppercase tracking-wider mb-4">
          Appearance
        </h2>
        <div class="card bg-base-100 border border-base-300 shadow-sm">
          <div class="card-body px-5 py-4">
            <p class="text-sm font-medium text-base-content mb-3">Theme</p>
            <div class="flex flex-wrap gap-2">
              <button
                :for={{val, label} <- @themes}
                phx-click="set_theme"
                phx-value-theme={val}
                class={"btn btn-sm #{if @settings["theme"] == val, do: "btn-primary", else: "btn-outline"}"}
              >
                {label}
              </button>
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
                <p class="text-xs text-base-content/50 mt-0.5">
                  Set via ANTHROPIC_API_KEY in your .env
                </p>
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
                    Add to .env: <code class="font-mono">EITS_API_KEY=&lt;value&gt;</code>
                    then restart.
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

  defp render_tab(%{active_tab: :pricing} = assigns) do
    ~H"""
    <section>
      <h2 class="text-sm font-semibold text-base-content/60 uppercase tracking-wider mb-4">
        Token Pricing
      </h2>
      <div class="card bg-base-100 border border-base-300 shadow-sm">
        <div class="card-body p-5">
          <div class="flex items-center justify-between mb-4">
            <p class="text-xs text-base-content/50">
              Cost per 1M tokens (USD). Used for usage cost estimates.
            </p>
            <button phx-click="reset_pricing" class="btn btn-ghost btn-xs">
              <.icon name="hero-arrow-uturn-left" class="w-3.5 h-3.5" /> Reset All
            </button>
          </div>
          <form phx-change="save_pricing" phx-debounce="500">
            <div class="overflow-x-auto">
              <table class="table table-sm">
                <thead>
                  <tr class="text-base-content/60">
                    <th>Model</th>
                    <th class="text-right">Input</th>
                    <th class="text-right">Output</th>
                    <th class="text-right">Cache Read</th>
                    <th class="text-right">Cache Create</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={model <- ["opus", "sonnet", "haiku"]} class="hover">
                    <td class="font-medium capitalize">{model}</td>
                    <td
                      :for={type <- ["input", "output", "cache_read", "cache_creation"]}
                      class="text-right"
                    >
                      <input
                        type="number"
                        name={"pricing_#{model}_#{type}"}
                        value={@settings["pricing_#{model}_#{type}"]}
                        step="0.01"
                        min="0"
                        class="input input-bordered input-xs w-20 text-right"
                      />
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </form>
        </div>
      </div>
    </section>
    """
  end

  defp render_tab(%{active_tab: :system} = assigns) do
    ~H"""
    <section>
      <h2 class="text-sm font-semibold text-base-content/60 uppercase tracking-wider mb-4">
        System
      </h2>
      <div class="card bg-base-100 border border-base-300 shadow-sm">
        <div class="card-body p-0 divide-y divide-base-300">
          <%!-- Debug Logging --%>
          <div class="flex items-center justify-between px-5 py-4">
            <div>
              <p class="text-sm font-medium text-base-content">Log Raw Claude Output</p>
              <p class="text-xs text-base-content/50 mt-0.5">
                Log raw JSONL output from Claude CLI to console
              </p>
            </div>
            <input
              type="checkbox"
              class="toggle toggle-sm toggle-primary"
              checked={@settings["log_claude_raw"] == "true"}
              phx-click="toggle_setting"
              phx-value-key="log_claude_raw"
            />
          </div>

          <div class="flex items-center justify-between px-5 py-4">
            <div>
              <p class="text-sm font-medium text-base-content">Log Raw Codex Output</p>
              <p class="text-xs text-base-content/50 mt-0.5">
                Log raw output from Codex CLI to console
              </p>
            </div>
            <input
              type="checkbox"
              class="toggle toggle-sm toggle-primary"
              checked={@settings["log_codex_raw"] == "true"}
              phx-click="toggle_setting"
              phx-value-key="log_codex_raw"
            />
          </div>

          <%!-- Database Info --%>
          <div class="px-5 py-4">
            <p class="text-sm font-medium text-base-content mb-3">Database</p>
            <div class="grid grid-cols-2 gap-x-8 gap-y-2 text-xs">
              <div class="text-base-content/50">Path</div>
              <div class="font-mono text-base-content truncate" title={@db_info.path}>
                {@db_info.path}
              </div>
              <div class="text-base-content/50">Size</div>
              <div class="text-base-content">{format_db_size(@db_info.size)}</div>
            </div>
            <div class="mt-3">
              <p class="text-xs text-base-content/50 mb-2">Table Counts</p>
              <div class="flex flex-wrap gap-2">
                <span
                  :for={{table, count} <- @db_info.table_counts}
                  class="badge badge-ghost badge-sm gap-1"
                >
                  {table}
                  <span class="font-semibold">{count}</span>
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end

  defp render_tab(%{active_tab: _} = assigns) do
    ~H[<p class="text-sm text-base-content/50 px-2 py-4">Coming soon</p>]
  end
end
