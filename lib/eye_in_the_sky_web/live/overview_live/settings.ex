defmodule EyeInTheSkyWeb.OverviewLive.Settings do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.Repo
  alias EyeInTheSky.Settings
  alias EyeInTheSkyWeb.Helpers.ModelHelpers

  alias EyeInTheSkyWeb.OverviewLive.Settings.{
    AuthTab,
    EditorTab,
    GeneralTab,
    PricingTab,
    SystemTab,
    WorkflowTab
  }

  @voices ["Ava", "Isha", "Lee", "Jamie", "Serena"]

  @themes [
    {"dark", "Dark"},
    {"light", "Light"},
    {"dracula", "Dracula"},
    {"tokyonight", "Tokyo Night"},
    {"autumn", "Autumn"}
  ]

  @valid_tabs ~w(general editor auth workflow pricing system)

  @known_editors ~w(code cursor vim nano zed)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      EyeInTheSky.Events.subscribe_settings()
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

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"tab" => tab}, _uri, socket) do
    active = if tab in @valid_tabs, do: String.to_existing_atom(tab), else: :general
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

    cond do
      editor not in @known_editors ->
        {:noreply, put_flash(socket, :error, "Editor #{inspect(editor)} is not allowed")}

      not File.exists?(path) ->
        {:noreply, put_flash(socket, :error, "Path does not exist")}

      true ->
        Task.Supervisor.start_child(EyeInTheSky.TaskSupervisor, fn ->
          System.cmd(editor, [path], stderr_to_stdout: true)
        end)

        {:noreply, put_flash(socket, :info, "Opening in #{editor}...")}
    end
  end

  @impl true
  def handle_event("open_in_editor", _params, socket) do
    {:noreply, put_flash(socket, :error, "No file path provided")}
  end

  @impl true
  def handle_event("save_setting", %{"key" => key, "value" => value}, socket) do
    # Convert seconds to milliseconds for timeout storage; 0 means no timeout
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
      cond do
        key == "theme" ->
          push_event(socket, "apply_theme", %{theme: value})

        key == "cm_font_size" ->
          push_event(socket, "apply_cm_settings", %{cm_font_size: value})

        key == "palette_shortcut" ->
          assign(socket, :palette_shortcut, value)

        true ->
          socket
      end

    socket =
      if key == "cm_tab_size" do
        push_event(socket, "apply_cm_settings", %{cm_tab_size: value})
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

    socket =
      if key == "palette_shortcut" do
        assign(socket, :palette_shortcut, settings["palette_shortcut"] || "auto")
      else
        socket
      end

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
  def handle_event("toggle_setting", %{"key" => "cm_vim"}, socket) do
    current = Settings.get("cm_vim") || "false"
    new_val = if current == "true", do: "false", else: "true"
    Settings.put("cm_vim", new_val)
    settings = Settings.all()
    socket = socket |> assign(:settings, settings) |> flash_saved("cm_vim")
    {:noreply, push_event(socket, "apply_cm_settings", %{cm_vim: new_val})}
  end

  @impl true
  def handle_event("toggle_setting", %{"key" => key}, socket) do
    current = Settings.get_boolean(key)
    Settings.put(key, to_string(!current))
    settings = Settings.all()
    {:noreply, socket |> assign(:settings, settings) |> flash_saved(key)}
  end

  @impl true
  def handle_info(:set_default_theme, socket) do
    if Settings.get("theme") == "" do
      Settings.put("theme", "dark")
    end

    {:noreply, socket}
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
    sql = """
    SELECT 'sessions', COUNT(*) FROM sessions
    UNION ALL SELECT 'agents', COUNT(*) FROM agents
    UNION ALL SELECT 'tasks', COUNT(*) FROM tasks
    UNION ALL SELECT 'notes', COUNT(*) FROM notes
    UNION ALL SELECT 'messages', COUNT(*) FROM messages
    UNION ALL SELECT 'projects', COUNT(*) FROM projects
    UNION ALL SELECT 'commits', COUNT(*) FROM commits
    UNION ALL SELECT 'prompts', COUNT(*) FROM subagent_prompts
    """

    case Repo.query!(sql) do
      %{rows: rows} -> Enum.map(rows, fn [table, count] -> {table, count} end)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8 py-8">
      <div class="max-w-4xl mx-auto space-y-6">
        <div class="tabs tabs-bordered overflow-x-auto flex-nowrap whitespace-nowrap">
          <%= for {label, key} <- [
            {"General", "general"}, {"Editor", "editor"}, {"Auth & Keys", "auth"},
            {"Workflow", "workflow"}, {"Pricing", "pricing"}, {"System", "system"}
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

  defp render_tab(%{active_tab: _} = assigns) do
    ~H[<p class="text-sm text-base-content/50 px-2 py-4">Coming soon</p>]
  end
end
