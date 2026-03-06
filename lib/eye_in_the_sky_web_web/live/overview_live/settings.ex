defmodule EyeInTheSkyWebWeb.OverviewLive.Settings do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.Settings
  alias EyeInTheSkyWeb.Repo

  @models [
    {"haiku", "Haiku"},
    {"sonnet", "Sonnet"},
    {"opus", "Opus"}
  ]

  @voices ["Ava", "Isha", "Lee", "Jamie", "Serena"]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "settings")
    end

    settings = Settings.all()
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
      |> assign(:flash_key, nil)

    {:ok, socket}
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
    {:noreply, socket |> assign(:settings, settings) |> flash_saved(key)}
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
    {:noreply, socket |> assign(:settings, settings) |> put_flash(:info, "Pricing reset to defaults")}
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
    db_path = Application.get_env(:eye_in_the_sky_web, EyeInTheSkyWeb.Repo)[:database]
    db_path = db_path || "unknown"

    size =
      case File.stat(db_path) do
        {:ok, %{size: s}} -> s
        _ -> 0
      end

    table_counts = load_table_counts()

    %{
      path: db_path,
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

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8 py-8">
      <div class="max-w-4xl mx-auto space-y-8">
        <%!-- Agent Defaults --%>
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
                      value={div(String.to_integer(@settings["cli_idle_timeout_ms"] || "300000"), 1000)}
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

        <%!-- Token Pricing --%>
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
                        <td :for={type <- ["input", "output", "cache_read", "cache_creation"]} class="text-right">
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

        <%!-- System --%>
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
      </div>
    </div>
    """
  end
end
