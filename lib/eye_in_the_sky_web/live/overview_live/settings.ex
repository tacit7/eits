defmodule EyeInTheSkyWeb.OverviewLive.Settings do
  use EyeInTheSkyWeb, :live_view

  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]
  import EyeInTheSkyWeb.Helpers.FileHelpers, only: [path_within?: 2]

  alias EyeInTheSky.Events
  alias EyeInTheSky.Settings
  alias EyeInTheSkyWeb.Helpers.ModelHelpers
  alias EyeInTheSkyWeb.Live.Shared.NotificationHelpers

  alias EyeInTheSky.Desktop
  alias EyeInTheSky.Desktop.Config, as: DesktopConfig

  alias EyeInTheSkyWeb.OverviewLive.Settings.{
    AuthTab,
    DesktopTab,
    EditorTab,
    GeneralTab,
    PricingTab,
    ProvidersTab,
    SystemTab,
    WorkflowTab
  }

  alias EyeInTheSky.Pi.ModelDiscoveryCache
  alias EyeInTheSky.Redaction

  @voices ["Ava", "Isha", "Lee", "Jamie", "Serena"]

  @themes [
    {"dark", "Dark"},
    {"light", "Light"},
    {"dracula", "Dracula"},
    {"tokyonight", "Tokyo Night"},
    {"autumn", "Autumn"}
  ]

  @valid_tabs ~w(general editor auth workflow pricing system desktop providers)

  # Function, not attribute: compile-time ~ expansion bakes the build-machine home dir.
  defp allowed_editor_roots, do: [Path.expand("~/.claude")]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      EyeInTheSky.Events.subscribe_settings()
      EyeInTheSky.Events.subscribe_pi_models()
    end

    {settings, db_info} =
      if connected?(socket) do
        s = Settings.all()

        if s["theme"] == "" do
          send(self(), :set_default_theme)
        end

        s = if s["theme"] == "", do: Map.put(s, "theme", "dark"), else: s
        {s, load_db_info()}
      else
        {%{}, %{path: "", size: 0, table_counts: []}}
      end

    socket =
      socket
      |> assign(:page_title, "Settings")
      |> assign(:sidebar_tab, :settings)
      |> assign(:sidebar_project, nil)
      |> assign(:settings, settings)
      |> assign(:db_info, db_info)
      |> assign(:models, ModelHelpers.claude_models())
      |> assign(:voices, @voices)
      |> assign(:themes, @themes)
      |> assign(:flash_key, nil)
      |> assign(:active_tab, :general)
      |> assign(:generated_api_key, nil)
      |> assign(:desktop_mode?, Desktop.desktop_mode?())
      |> assign(:desktop_port, DesktopConfig.configured_port())
      |> assign(:hooks_consent, DesktopConfig.hooks_consent())
      |> assign(:pi_providers, :loading)
      |> assign(:pi_model_status, current_model_status())
      |> assign(:pi_key_op_in_flight, false)

    if connected?(socket), do: Events.broadcast_rail_context(socket)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"tab" => tab}, _uri, socket) do
    active = if tab in @valid_tabs, do: String.to_existing_atom(tab), else: :general
    {:noreply, socket |> assign(:active_tab, active) |> maybe_load_providers(active)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, :active_tab, :general)}
  end

  defp maybe_load_providers(socket, :providers) do
    start_provider_load(self())
    socket
  end

  defp maybe_load_providers(socket, _), do: socket

  defp start_provider_load(pid) do
    control = control_module()

    Task.Supervisor.start_child(EyeInTheSky.TaskSupervisor, fn ->
      result = control.list_providers()
      send(pid, {:pi_providers_loaded, result})
    end)

    :ok
  end

  defp control_module,
    do: Application.get_env(:eye_in_the_sky, :pi_control_module, EyeInTheSky.Pi.Control)

  defp current_model_status do
    case ModelDiscoveryCache.get_cached() do
      {:ok, models, freshness} -> {length(models), freshness}
      :empty -> :empty
    end
  end

  @impl true
  def handle_event("set_tab", %{"tab" => tab}, socket) do
    {:noreply, push_patch(socket, to: ~p"/settings?tab=#{tab}")}
  end

  @impl true
  def handle_event("save_desktop_port", %{"port" => port_str}, socket) do
    with {port, ""} <- Integer.parse(to_string(port_str)),
         :ok <- DesktopConfig.write_port(port) do
      {:noreply,
       socket
       |> assign(:desktop_port, port)
       |> put_flash(:info, "Port saved — restart the desktop app to apply")}
    else
      {:error, :out_of_range} ->
        {:noreply, put_flash(socket, :error, "Port must be between 1024 and 49151")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not save port")}
    end
  end

  @impl true
  def handle_event("toggle_hooks_consent", %{"granted" => granted_str}, socket) do
    granted? = granted_str == "true"

    case DesktopConfig.write_hooks_consent(granted?) do
      :ok ->
        message =
          if granted? do
            "Hooks/skills will be installed next launch"
          else
            "Hooks/skills will not be installed next launch (existing ones are not removed — use eits uninstall)"
          end

        {:noreply,
         socket
         |> assign(:hooks_consent, granted?)
         |> put_flash(:info, message)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not save preference")}
    end
  end

  @impl true
  def handle_event("set_notify_on_stop", params, socket),
    do: {:noreply, NotificationHelpers.set_notify_on_stop(socket, params)}

  @impl true
  def handle_event("regenerate_api_key", _params, socket) do
    key = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    {:noreply, assign(socket, :generated_api_key, key)}
  end

  @impl true
  def handle_event("open_in_editor", %{"path" => path}, socket) when byte_size(path) > 0 do
    editor = Settings.get("preferred_editor") || "code"
    allowed? = Enum.any?(allowed_editor_roots(), &path_within?(path, &1))

    if allowed? do
      case EyeInTheSky.Editors.open(editor, path) do
        {:ok, label} ->
          {:noreply, put_flash(socket, :info, "Opening in #{label}...")}

        {:error, :unknown_editor} ->
          {:noreply, put_flash(socket, :error, "Editor #{inspect(editor)} is not configured")}

        {:error, :not_installed} ->
          {:noreply, put_flash(socket, :error, "Editor #{inspect(editor)} is not installed")}

        {:error, :not_found} ->
          {:noreply, put_flash(socket, :error, "File not found")}

        {:error, :not_allowed} ->
          {:noreply, put_flash(socket, :error, "Path not allowed")}
      end
    else
      {:noreply, put_flash(socket, :error, "Path is outside allowed directories")}
    end
  end

  @impl true
  def handle_event("open_in_editor", _params, socket) do
    {:noreply, put_flash(socket, :error, "No file path provided")}
  end

  @impl true
  def handle_event("save_setting", %{"key" => key, "value" => value}, socket) do
    if key == "theme" do
      {:noreply, apply_theme_setting(socket, value)}
    else
      # Convert seconds to milliseconds for timeout storage; 0 means no timeout
      value =
        if key == "cli_idle_timeout_ms" do
          case parse_int(value) do
            nil -> value
            secs -> to_string(secs * 1000)
          end
        else
          value
        end

      Settings.put(key, value)

      socket =
        socket
        |> reload_settings()
        |> flash_saved(key)

      socket =
        cond do
          key == "cm_font_size" ->
            push_event(socket, "apply_cm_settings", %{cm_font_size: value})

          key == "cm_tab_size" ->
            push_event(socket, "apply_cm_settings", %{cm_tab_size: value})

          true ->
            socket
        end

      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("set_theme", %{"theme" => theme}, socket) do
    {:noreply, apply_theme_setting(socket, theme)}
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

    {:noreply, socket |> reload_settings() |> flash_saved("pricing")}
  end

  @impl true
  def handle_event("reset_setting", %{"key" => key}, socket) do
    Settings.reset(key)
    {:noreply, socket |> reload_settings() |> put_flash(:info, "Reset to default")}
  end

  @impl true
  def handle_event("reset_pricing", _params, socket) do
    defaults = Settings.defaults()

    defaults
    |> Enum.filter(fn {k, _} -> String.starts_with?(k, "pricing_") end)
    |> Enum.each(fn {k, _} -> Settings.reset(k) end)

    {:noreply,
     socket |> reload_settings() |> put_flash(:info, "Pricing reset to defaults")}
  end

  @impl true
  def handle_event("toggle_setting", %{"key" => "cm_vim"}, socket) do
    current = Settings.get("cm_vim") || "false"
    new_val = if current == "true", do: "false", else: "true"
    Settings.put("cm_vim", new_val)
    socket = socket |> reload_settings() |> flash_saved("cm_vim")
    {:noreply, push_event(socket, "apply_cm_settings", %{cm_vim: new_val})}
  end

  @impl true
  def handle_event("toggle_setting", %{"key" => key}, socket) do
    current = Settings.get_boolean(key)
    Settings.put(key, to_string(!current))
    {:noreply, socket |> reload_settings() |> flash_saved(key)}
  end

  @impl true
  def handle_event("pi_set_key", %{"provider_id" => pid, "key" => key}, socket)
      when is_binary(pid) and is_binary(key) and key != "" do
    start_key_op(self(), :set, pid, key)
    {:noreply, assign(socket, :pi_key_op_in_flight, true)}
  end

  @impl true
  def handle_event("pi_set_key", _params, socket) do
    {:noreply, put_flash(socket, :error, "Missing key")}
  end

  @impl true
  def handle_event("pi_clear_key", %{"provider_id" => pid}, socket) when is_binary(pid) do
    start_key_op(self(), :clear, pid, nil)
    {:noreply, assign(socket, :pi_key_op_in_flight, true)}
  end

  @impl true
  def handle_event("pi_refresh_models", _params, socket) do
    ModelDiscoveryCache.refresh_async()
    {:noreply, assign(socket, :pi_model_status, :loading)}
  end

  # ---------------------------------------------------------------------------
  # Private helpers — settings application, Pi operations, rendering
  # ---------------------------------------------------------------------------

  defp apply_theme_setting(socket, theme) do
    Settings.put("theme", theme)
    settings = Settings.all()

    socket
    |> assign(:settings, settings)
    |> flash_saved("theme")
    |> push_event("apply_theme", %{theme: theme})
  end

  # Runs the blocking harness IPC in a supervised Task so the LiveView socket
  # is not held for the length of the Pi.Control timeout (up to 30s). Result is
  # sent back as a :pi_key_op_result message. The closure captures only the
  # LiveView pid — never `socket` — to keep the assign copy out of task memory.
  defp start_key_op(pid, op, provider_id, key) do
    control = control_module()

    Task.Supervisor.start_child(EyeInTheSky.TaskSupervisor, fn ->
      result =
        case op do
          :set -> control.set_api_key(provider_id, key)
          :clear -> control.clear_api_key(provider_id)
        end

      send(pid, {:pi_key_op_result, op, result})
    end)

    :ok
  end

  # Redact any provider-echoed key material out of the flash text before it
  # reaches the DOM. Never inspect/1 a raw crash term unfiltered — it may
  # contain the submitted key inside a Task exit report.
  defp key_op_error_flash(:set, reason),
    do: "Key save failed: #{redact_reason(reason)}"

  defp key_op_error_flash(:clear, reason),
    do: "Key clear failed: #{redact_reason(reason)}"

  defp redact_reason({:pi_control, msg}) when is_binary(msg),
    do: msg |> Redaction.redact() |> String.slice(0, 200)

  defp redact_reason(other), do: Redaction.redact_inspect(other, limit: 200)

  @impl true
  def handle_info(:set_default_theme, socket) do
    if Settings.get("theme") == "" do
      Settings.put("theme", "dark")
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:settings_changed, _key, _value}, socket) do
    {:noreply, reload_settings(socket)}
  end

  @impl true
  def handle_info({:pi_providers_loaded, result}, socket) do
    {:noreply, assign(socket, :pi_providers, result)}
  end

  @impl true
  def handle_info({:pi_key_op_result, op, :ok}, socket) do
    ModelDiscoveryCache.invalidate()
    ModelDiscoveryCache.refresh_async()
    start_provider_load(self())

    flash =
      case op do
        :set -> "Key saved to ~/.pi/agent/auth.json"
        :clear -> "Key cleared"
      end

    {:noreply,
     socket
     |> assign(:pi_key_op_in_flight, false)
     |> put_flash(:info, flash)}
  end

  @impl true
  def handle_info({:pi_key_op_result, op, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:pi_key_op_in_flight, false)
     |> put_flash(:error, key_op_error_flash(op, reason))}
  end

  @impl true
  def handle_info({:pi_models_refreshed, {:ok, models}}, socket) do
    {:noreply, assign(socket, :pi_model_status, {length(models), :fresh})}
  end

  @impl true
  def handle_info({:pi_models_refreshed, {:error, reason}}, socket) do
    {:noreply, assign(socket, :pi_model_status, {:error, reason})}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  defp flash_saved(socket, _key) do
    put_flash(socket, :info, "Saved")
  end

  defp load_db_info do
    Settings.db_info()
  end

  defp reload_settings(socket), do: assign(socket, :settings, Settings.all())

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8 py-8">
      <div class="max-w-4xl mx-auto space-y-6">
        <div class="tabs tabs-bordered overflow-x-auto flex-nowrap whitespace-nowrap">
          <%= for {label, key} <- [
            {"General", "general"}, {"Editor", "editor"}, {"Auth & Keys", "auth"},
            {"Providers", "providers"},
            {"Workflow", "workflow"}, {"Pricing", "pricing"}, {"System", "system"},
            {"Desktop", "desktop"}
          ] do %>
            <button
              class={"tab #{if @active_tab == String.to_existing_atom(key), do: "tab-active", else: ""}"}
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

  defp render_tab(%{active_tab: :general} = assigns), do: GeneralTab.render(assigns)
  defp render_tab(%{active_tab: :auth} = assigns), do: AuthTab.render(assigns)
  defp render_tab(%{active_tab: :editor} = assigns), do: EditorTab.render(assigns)
  defp render_tab(%{active_tab: :workflow} = assigns), do: WorkflowTab.render(assigns)
  defp render_tab(%{active_tab: :pricing} = assigns), do: PricingTab.render(assigns)
  defp render_tab(%{active_tab: :system} = assigns), do: SystemTab.render(assigns)
  defp render_tab(%{active_tab: :desktop} = assigns), do: DesktopTab.render(assigns)
  defp render_tab(%{active_tab: :providers} = assigns), do: ProvidersTab.render(assigns)

  defp render_tab(%{active_tab: _} = assigns) do
    ~H[<p class="text-sm text-base-content/50 px-2 py-4">Coming soon</p>]
  end
end
