defmodule EyeInTheSkyWeb.DmLive do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.{Agents, Sessions}
  alias EyeInTheSky.Claude.AgentWorker
  alias EyeInTheSky.Settings.JsonSettings
  alias EyeInTheSkyWeb.Components.DmPage

  alias EyeInTheSkyWeb.DmLive.{
    AgentLifecycle,
    ExternalActions,
    MessageHandlers,
    MountState,
    SlashCommands
  }

  alias EyeInTheSkyWeb.DmLive.TabHelpers
  alias EyeInTheSkyWeb.DmLive.TaskHandlers
  alias EyeInTheSkyWeb.DmLive.TimerHandlers
  alias EyeInTheSkyWeb.Live.Shared.NotificationHelpers
  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]
  import EyeInTheSkyWeb.Live.Shared.TasksHelpers
  import EyeInTheSkyWeb.Live.Shared.DmExportHelpers
  import EyeInTheSkyWeb.Live.Shared.DmModelHelpers
  import EyeInTheSkyWeb.Live.Shared.DmSessionHelpers
  import EyeInTheSkyWeb.Live.Shared.DmStreamHelpers
  import EyeInTheSkyWeb.Live.Shared.OverlayHelpers

  require Logger

  @default_message_limit 50
  @message_page_size 20

  @impl true
  def mount(%{"session_id" => session_id_param} = params, _session, socket) do
    session_result = Sessions.resolve(session_id_param)

    with {:session, {:ok, session}} <- {:session, session_result},
         {:agent, {:ok, agent}} <- {:agent, Agents.get_agent(session.agent_id)} do
      MountState.maybe_subscribe(connected?(socket), session.id, socket.assigns.current_user)

      socket =
        socket
        |> assign(:allow_split, true)
        |> MountState.assign_sidebar_context(params)
        |> MountState.assign_session_state(session, agent)
        |> MountState.assign_essential_defaults(session)
        |> then(fn s ->
          if connected?(socket), do: MountState.assign_connected_defaults(s, session), else: s
        end)
        |> MessageHandlers.load_messages_on_mount()

      {:ok, socket}
    else
      {:session, {:error, :not_found}} ->
        {:ok, socket |> put_flash(:error, "Session not found") |> redirect(to: "/")}

      {:agent, {:error, :not_found}} ->
        {:ok,
         socket |> put_flash(:error, "Agent not found for this session") |> redirect(to: "/")}
    end
  end

  # ---------------------------------------------------------------------------
  # Tab & UI toggles
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("change_tab", %{"tab" => tab}, socket) do
    socket =
      socket
      |> assign(:active_tab, tab)
      |> TabHelpers.load_tab_data(tab, socket.assigns.session_id)

    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # DM Settings tab — scope toggle + field updates
  # (Stub persistence: assigns only. JSONB columns + contexts not built yet.)
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("dm_setting_scope", %{"scope" => scope}, socket)
      when scope in ["session", "agent"] do
    {:noreply, assign(socket, :dm_settings_scope, scope)}
  end

  @impl true
  def handle_event("dm_setting_subtab", %{"subtab" => subtab}, socket)
      when subtab in ["general", "anthropic", "openai"] do
    {:noreply, assign(socket, :dm_settings_subtab, subtab)}
  end

  # Text/number/select inputs fire with an explicit "value" — coerce + persist as-is.
  @impl true
  def handle_event(
        "dm_setting_update",
        %{"scope" => scope, "key" => key, "value" => value},
        socket
      )
      when scope in ["session", "agent"] do
    case persist_setting_update(scope, key, value, socket.assigns) do
      {:ok, assigns} ->
        {:noreply, assign(socket, assigns)}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Setting update failed: #{format_setting_error(reason)}")}
    end
  end

  # Toggle inputs (checkbox phx-click) fire WITHOUT a "value" — flip the current
  # effective value. NOTE: the explicit-value clause above MUST require "value"
  # in its pattern; matching only on scope+key would shadow this clause and
  # boolean toggles would silently fail with :type_mismatch.
  @impl true
  def handle_event("dm_setting_update", %{"scope" => scope, "key" => key}, socket)
      when scope in ["session", "agent"] do
    current = JsonSettings.get_setting(socket.assigns.dm_settings_effective || %{}, key)
    new_value = not (current == true)

    case persist_setting_update(scope, key, new_value, socket.assigns) do
      {:ok, assigns} ->
        {:noreply, assign(socket, assigns)}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Setting update failed: #{format_setting_error(reason)}")}
    end
  end

  @impl true
  def handle_event("reset_dm_settings", %{"scope" => scope}, socket)
      when scope in ["session", "agent"] do
    case reset_scoped_settings(scope, socket.assigns) do
      {:ok, assigns} ->
        {:noreply, assign(socket, assigns)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Reset failed: #{format_setting_error(reason)}")}
    end
  end

  @impl true
  def handle_event("toggle_model_menu", _params, socket), do: handle_toggle_model_menu(socket)

  @impl true
  def handle_event("toggle_effort_menu", _params, socket), do: handle_toggle_effort_menu(socket)

  @impl true
  def handle_event("toggle_context_meter", _params, socket),
    do: toggle_active_overlay(socket, :context_meter)

  @impl true
  def handle_event("toggle_new_session_drawer", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("toggle_new_task_drawer", _params, socket),
    do: toggle_active_overlay(socket, :task_drawer)

  @impl true
  def handle_event("toggle_task_detail_drawer", _params, socket),
    do: toggle_active_overlay(socket, :task_detail)

  @impl true
  def handle_event("open_schedule_timer", _params, socket) do
    {:noreply, assign(socket, :active_overlay, :schedule_timer)}
  end

  @impl true
  def handle_event("close_schedule_modal", _params, socket) do
    {:noreply, assign(socket, :active_overlay, nil)}
  end

  @impl true
  def handle_event("schedule_timer", params, socket),
    do: TimerHandlers.handle_schedule_timer(params, socket)

  @impl true
  def handle_event("cancel_timer", _params, socket),
    do: TimerHandlers.handle_cancel_timer(socket)

  @impl true
  def handle_event("toggle_thinking", _params, socket), do: handle_toggle_thinking(socket)

  @impl true
  def handle_event("set_notify_on_stop", params, socket),
    do: {:noreply, NotificationHelpers.set_notify_on_stop(socket, params)}

  # ---------------------------------------------------------------------------
  # Task CRUD — delegates to TasksHelpers; overlay close handled here
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("open_task_detail", params, socket),
    do: handle_open_task_detail_with_overlay(params, socket, :task_detail)

  @impl true
  def handle_event("update_task", params, socket),
    do: handle_update_task(params, socket, &TabHelpers.reload_tasks/1)

  @impl true
  def handle_event("delete_task", %{"task_id" => _} = params, socket) do
    socket = assign(socket, :active_overlay, nil)
    handle_delete_task(params, socket, &TabHelpers.reload_tasks/1)
  end

  @impl true
  def handle_event("archive_task", %{"task_id" => _} = params, socket) do
    socket = assign(socket, :active_overlay, nil)
    handle_archive_task(params, socket, &TabHelpers.reload_tasks/1)
  end

  @impl true
  def handle_event("add_task_annotation", params, socket),
    do: handle_add_task_annotation(params, socket)

  @impl true
  def handle_event("start_agent_for_task", params, socket),
    do: TaskHandlers.handle_start_agent_for_task(params, socket)

  @impl true
  def handle_event("create_new_task", params, socket) do
    session_id = socket.assigns.session_id

    reload_fn = fn s ->
      s
      |> assign(:active_overlay, nil)
      |> assign(:active_tab, "tasks")
      |> TabHelpers.load_tab_data("tasks", session_id)
    end

    handle_create_new_task(params, socket, reload_fn)
  end

  # ---------------------------------------------------------------------------
  # Session & model settings
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("select_model", params, socket), do: handle_select_model(params, socket)

  @impl true
  def handle_event("select_effort", params, socket), do: handle_select_effort(params, socket)

  @impl true
  def handle_event("set_max_budget", params, socket), do: handle_set_max_budget(params, socket)

  @impl true
  def handle_event("update_session_name", params, socket),
    do: handle_update_session_name(params, socket)

  @impl true
  def handle_event("update_session_description", params, socket),
    do: handle_update_session_description(params, socket)

  # ---------------------------------------------------------------------------
  # Messaging
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("send_message", %{"body" => body}, socket) when body != "" do
    {server_cmds, session_opts, clean_body} = SlashCommands.parse(body)
    socket = SlashCommands.apply_server_commands(server_cmds, socket)
    socket = SlashCommands.apply_session_opts(session_opts, socket)

    trimmed = String.trim(clean_body)

    if trimmed != "" do
      MessageHandlers.handle_send_message(trimmed, socket)
    else
      {:noreply, push_event(socket, "clear-input", %{})}
    end
  end

  @impl true
  def handle_event("send_message", _params, socket) do
    {:noreply, socket}
  end

  # Compact/Clear buttons in the context meter popover dispatch a slash command
  # directly without going through the textarea.
  @impl true
  def handle_event("send_slash_command", %{"command" => cmd}, socket)
      when cmd in ["/compact", "/clear"] do
    socket = assign(socket, :active_overlay, nil)
    MessageHandlers.handle_send_message(cmd, socket)
  end

  @impl true
  def handle_event("remove_queued_prompt", %{"id" => id_str}, socket) do
    if id = parse_int(id_str), do: AgentWorker.remove_queued_prompt(socket.assigns.session_id, id)

    {:noreply, socket}
  end

  @impl true
  def handle_event("load_more_messages", _params, socket) do
    new_limit = (socket.assigns[:message_limit] || @default_message_limit) + @message_page_size

    socket =
      socket
      |> assign(:message_limit, new_limit)
      |> TabHelpers.force_reload_messages(socket.assigns.session_id)

    {:noreply, socket}
  end

  @impl true
  def handle_event("search_messages", %{"query" => query}, socket) do
    query = String.trim(query)

    # When clearing search (blank query), force a fresh DB load — the cache
    # holds the filtered result set and must not be reused for the full list.
    socket =
      if query == "" do
        socket
        |> assign(:message_search_query, query)
        |> TabHelpers.force_reload_messages(socket.assigns.session_id)
      else
        socket
        |> assign(:message_search_query, query)
        |> TabHelpers.load_tab_data("messages", socket.assigns.session_id)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("export_jsonl", _params, socket), do: handle_export_jsonl(socket)

  @impl true
  def handle_event("export_markdown", _params, socket), do: handle_export_markdown(socket)

  @impl true
  def handle_event("reload_from_session_file", _params, socket) do
    Process.send_after(self(), :do_reload_from_session_file, 50)
    {:noreply, assign(socket, :reloading, true)}
  end

  # ---------------------------------------------------------------------------
  # File uploads
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :files, ref)}
  end

  @impl true
  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # File autocomplete
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("list_files", %{"partial" => partial, "root" => root}, socket) do
    session = socket.assigns.session
    result = EyeInTheSkyWeb.DmLive.FileAutocomplete.list_entries(partial, root, session)
    {:reply, result, socket}
  end

  # ---------------------------------------------------------------------------
  # Diffs & external tools
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("load_diff", %{"hash" => hash}, socket),
    do: ExternalActions.handle_load_diff(hash, socket)

  @impl true
  def handle_event("open_iterm", _params, socket),
    do: ExternalActions.handle_open_iterm(socket)

  @impl true
  def handle_event("toggle_star", params, socket),
    do:
      handle_toggle_star(
        params,
        socket,
        &TabHelpers.load_tab_data(&1, "notes", &1.assigns.session_id)
      )

  @impl true
  def handle_event("kill_session", _params, socket), do: handle_kill_session(socket)

  # ---------------------------------------------------------------------------
  # handle_info: message reload (event-driven, debounced)
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info(:do_reload_from_session_file, socket) do
    {_reply, new_socket} =
      handle_reload_from_session_file(
        socket,
        &TabHelpers.force_reload_messages(&1, &1.assigns.session_id)
      )

    {:noreply, assign(new_socket, :reloading, false)}
  end

  @impl true
  def handle_info(:do_message_reload, socket) do
    {:noreply,
     socket
     |> assign(:reload_timer, nil)
     |> assign(:stream_content, "")
     |> MessageHandlers.maybe_reload_messages()}
  end

  @impl true
  def handle_info({:new_message, _message}, socket) do
    {:noreply, MessageHandlers.schedule_message_reload(socket)}
  end

  @impl true
  def handle_info({:new_dm, _msg}, socket) do
    {:noreply, MessageHandlers.schedule_message_reload(socket)}
  end

  # ---------------------------------------------------------------------------
  # handle_info: agent lifecycle
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:claude_response, session_ref, response}, socket),
    do: AgentLifecycle.handle_claude_response(session_ref, response, socket)

  @impl true
  def handle_info({:claude_complete, session_ref, exit_code}, socket),
    do: AgentLifecycle.handle_claude_complete(session_ref, exit_code, socket)

  @impl true
  def handle_info({:agent_working, msg}, socket),
    do: AgentLifecycle.handle_agent_working(msg, socket)

  @impl true
  def handle_info({:agent_stopped, msg}, socket),
    do: AgentLifecycle.handle_agent_stopped(msg, socket)

  @impl true
  def handle_info({:agent_updated, updated_session}, socket),
    do: AgentLifecycle.handle_agent_updated(updated_session, socket)

  @impl true
  def handle_info(:tasks_changed, socket),
    do: AgentLifecycle.handle_tasks_changed(socket)

  # ---------------------------------------------------------------------------
  # handle_info: streaming — delegated to DmStreamHelpers
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:stream_delta, type, content}, socket),
    do: handle_stream_delta(type, content, socket)

  @impl true
  def handle_info({:stream_replace, type, content}, socket),
    do: handle_stream_replace(type, content, socket)

  @impl true
  def handle_info(:stream_clear, socket), do: handle_stream_clear(socket)

  @impl true
  def handle_info({:stream_tool_input, name, input}, socket),
    do: handle_stream_tool_input(name, input, socket)

  @impl true
  def handle_info({:tool_use, tool_name, _params}, socket),
    do: handle_tool_use(tool_name, socket)

  @impl true
  def handle_info({:tool_result, _tool_name, _is_error}, socket),
    do: handle_tool_result(socket)

  @impl true
  def handle_info({:queue_updated, prompts}, socket),
    do: handle_queue_updated(prompts, socket)

  @impl true
  def handle_info({:timer_scheduled, timer}, socket) do
    {:noreply, assign(socket, :active_timer, timer)}
  end

  @impl true
  def handle_info(:timer_cancelled, socket) do
    {:noreply, assign(socket, :active_timer, nil)}
  end

  @impl true
  def handle_info({:timer_fired, timer_or_nil}, socket) do
    {:noreply, assign(socket, :active_timer, timer_or_nil)}
  end

  # Raw Codex JSONL line — prepend, cap at 100
  @impl true
  def handle_info({:codex_raw_line, line}, socket) do
    lines = [line | socket.assigns.codex_raw_lines] |> Enum.take(100)
    {:noreply, assign(socket, :codex_raw_lines, lines)}
  end

  @impl true
  def handle_info(msg, socket) do
    Logger.debug("Unhandled message in DM LiveView: #{inspect(msg)}")
    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp toggle_active_overlay(socket, overlay) do
    {:noreply,
     assign(socket, :active_overlay, toggle_overlay(socket.assigns.active_overlay, overlay))}
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div id="dm-live-root">
      <DmPage.dm_page
        agent={@session}
        agent_record={@agent}
        session_uuid={@session_uuid}
        active_tab={@active_tab}
        uploads={@uploads}
        stream={
          %{
            show: @show_live_stream,
            content: @stream_content,
            tool: @stream_tool,
            thinking: @stream_thinking
          }
        }
        session_state={
          %{
            model: @selected_model,
            effort: @selected_effort,
            processing: @processing,
            thinking_enabled: @thinking_enabled,
            max_budget_usd: @max_budget_usd,
            compacting: @compacting,
            context_used: @context_used,
            context_window: @context_window,
            total_cost: @total_cost
          }
        }
        message_data={
          %{
            messages: @messages,
            has_more_messages: @has_more_messages,
            message_search_query: @message_search_query,
            queued_prompts: @queued_prompts
          }
        }
        task_data={%{tasks: @tasks, current_task: @current_task}}
        overlay_data={
          %{
            active_overlay: @active_overlay,
            active_timer: @active_timer,
            reloading: @reloading
          }
        }
        commits={@commits}
        diff_cache={@diff_cache}
        notes={@notes}
        codex_raw_lines={@codex_raw_lines}
        slash_items={@slash_items}
        session_context={@session_context}
        notify_on_stop={@notify_on_stop}
        dm_settings_scope={@dm_settings_scope}
        dm_settings_subtab={@dm_settings_subtab}
      />

      <EyeInTheSkyWeb.Components.NewTaskDrawer.new_task_drawer
        id="dm-new-task-drawer"
        show={@active_overlay == :task_drawer}
        workflow_states={@workflow_states}
        toggle_event="toggle_new_task_drawer"
        submit_event="create_new_task"
      />

      <EyeInTheSkyWeb.Components.TaskDetailDrawer.task_detail_drawer
        id="dm-task-detail-drawer"
        show={@active_overlay == :task_detail}
        task={@selected_task}
        notes={@task_notes}
        workflow_states={@workflow_states}
        toggle_event="toggle_task_detail_drawer"
        update_event="update_task"
        delete_event="delete_task"
      />
    </div>
    """
  end

  # ---- settings persistence helpers ----------------------------------------

  defp persist_setting_update("session", key, value, assigns) do
    with {:ok, fresh_session} <- Sessions.put_setting(assigns.session, key, value) do
      agent_settings = (assigns.agent && assigns.agent.settings) || %{}
      session_settings = fresh_session.settings || %{}

      {:ok,
       build_settings_assigns(:session, fresh_session, agent_settings, session_settings, assigns)}
    end
  end

  defp persist_setting_update("agent", _key, _value, %{agent: nil}),
    do: {:error, :no_agent_loaded}

  defp persist_setting_update("agent", key, value, assigns) do
    with {:ok, fresh_agent} <- Agents.put_setting(assigns.agent, key, value) do
      agent_settings = fresh_agent.settings || %{}
      session_settings = (assigns.session && assigns.session.settings) || %{}

      {:ok,
       build_settings_assigns(:agent, fresh_agent, agent_settings, session_settings, assigns)}
    end
  end

  defp reset_scoped_settings("session", assigns) do
    with {:ok, fresh_session} <- Sessions.reset_settings(assigns.session) do
      agent_settings = (assigns.agent && assigns.agent.settings) || %{}
      {:ok, build_settings_assigns(:session, fresh_session, agent_settings, %{}, assigns)}
    end
  end

  defp reset_scoped_settings("agent", %{agent: nil}), do: {:error, :no_agent_loaded}

  defp reset_scoped_settings("agent", assigns) do
    with {:ok, fresh_agent} <- Agents.reset_settings(assigns.agent) do
      session_settings = (assigns.session && assigns.session.settings) || %{}
      {:ok, build_settings_assigns(:agent, fresh_agent, %{}, session_settings, assigns)}
    end
  end

  # Build the full assign map after a settings write. CRITICAL: this updates
  # both the dm_settings_* introspection assigns AND the runtime assigns
  # (:thinking_enabled, :max_budget_usd, :show_live_stream, :notify_on_stop)
  # that message handlers and stream code read. Without this, settings changes
  # only take effect on remount.
  defp build_settings_assigns(
         written_scope,
         fresh_record,
         agent_settings,
         session_settings,
         assigns
       ) do
    effective = JsonSettings.effective_settings(agent_settings, session_settings)
    general = Map.get(effective, "general", %{})

    # Preserve current runtime values when the effective key is nil (e.g.
    # max_budget_usd has nil as a legitimate "no limit" default).
    base = %{
      dm_settings_effective: effective,
      dm_settings_agent_overrides: agent_settings,
      dm_settings_session_overrides: session_settings,
      show_live_stream: Map.get(general, "show_live_stream", assigns.show_live_stream),
      thinking_enabled: Map.get(general, "thinking_enabled", assigns.thinking_enabled),
      max_budget_usd: Map.get(general, "max_budget_usd", assigns.max_budget_usd),
      notify_on_stop: Map.get(general, "notify_on_stop", assigns.notify_on_stop)
    }

    case written_scope do
      :session -> Map.put(base, :session, fresh_record)
      :agent -> Map.put(base, :agent, fresh_record)
    end
  end

  defp format_setting_error(:unknown_setting_key), do: "unknown setting"

  defp format_setting_error(:scope_not_allowed),
    do: "this setting cannot be changed at this scope"

  defp format_setting_error(:invalid_float), do: "must be a number"
  defp format_setting_error(:invalid_integer), do: "must be a whole number"
  defp format_setting_error(:invalid_enum_value), do: "value not allowed"
  defp format_setting_error(:type_mismatch), do: "wrong type"
  defp format_setting_error(:no_agent_loaded), do: "agent not loaded"
  defp format_setting_error(%Ecto.Changeset{} = cs), do: inspect(cs.errors)
  defp format_setting_error(other), do: inspect(other)
end
