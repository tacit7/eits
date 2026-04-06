defmodule EyeInTheSkyWeb.DmLive do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.{Agents, Sessions}
  alias EyeInTheSky.Claude.AgentWorker
  alias EyeInTheSkyWeb.Components.DmPage
  alias EyeInTheSkyWeb.DmLive.{AgentLifecycle, ExternalActions, MessageHandlers, MountState, SlashCommands}
  alias EyeInTheSkyWeb.DmLive.TabHelpers
  alias EyeInTheSkyWeb.DmLive.TaskHandlers
  alias EyeInTheSkyWeb.DmLive.TimerHandlers
  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]
  import EyeInTheSkyWeb.Live.Shared.TasksHelpers
  import EyeInTheSkyWeb.Live.Shared.DmExportHelpers
  import EyeInTheSkyWeb.Live.Shared.DmModelHelpers
  import EyeInTheSkyWeb.Live.Shared.DmSessionHelpers
  import EyeInTheSkyWeb.Live.Shared.DmStreamHelpers

  require Logger

  @default_message_limit 20
  @message_page_size 20

  @impl true
  def mount(%{"session_id" => session_id_param} = params, _session, socket) do
    session_result = Sessions.resolve(session_id_param)

    with {:session, {:ok, session}} <- {:session, session_result},
         {:agent, {:ok, agent}} <- {:agent, Agents.get_agent(session.agent_id)} do
      MountState.maybe_subscribe(socket, session.id)

      socket =
        socket
        |> MountState.assign_sidebar_context(params)
        |> MountState.assign_session_state(session, agent)
        |> MountState.assign_defaults(session)
        |> load_messages_on_mount()

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

  @impl true
  def handle_event("toggle_model_menu", _params, socket), do: handle_toggle_model_menu(socket)

  @impl true
  def handle_event("toggle_effort_menu", _params, socket), do: handle_toggle_effort_menu(socket)

  @impl true
  def handle_event("toggle_new_task_drawer", _params, socket) do
    overlay = if socket.assigns.active_overlay == :task_drawer, do: nil, else: :task_drawer
    {:noreply, assign(socket, :active_overlay, overlay)}
  end

  @impl true
  def handle_event("toggle_task_detail_drawer", _params, socket) do
    overlay = if socket.assigns.active_overlay == :task_detail, do: nil, else: :task_detail
    {:noreply, assign(socket, :active_overlay, overlay)}
  end

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
  def handle_event("keydown", %{"key" => "k", "ctrlKey" => true}, socket) do
    overlay = if socket.assigns.active_overlay == :task_drawer, do: nil, else: :task_drawer
    {:noreply, assign(socket, :active_overlay, overlay)}
  end

  def handle_event("keydown", _params, socket), do: {:noreply, socket}

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
    socket = apply_server_commands(server_cmds, socket)
    socket = apply_session_opts(session_opts, socket)

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
      |> TabHelpers.load_tab_data("messages", socket.assigns.session_id)

    {:noreply, socket}
  end

  @impl true
  def handle_event("search_messages", %{"query" => query}, socket) do
    query = String.trim(query)

    socket =
      socket
      |> assign(:message_search_query, query)
      |> TabHelpers.load_tab_data("messages", socket.assigns.session_id)

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
    do: handle_toggle_star(params, socket, &TabHelpers.load_tab_data(&1, "notes", &1.assigns.session_id))

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
        &TabHelpers.load_tab_data(&1, "messages", &1.assigns.session_id)
      )

    {:noreply, assign(new_socket, :reloading, false)}
  end

  @impl true
  def handle_info(:do_message_reload, socket) do
    {:noreply,
     socket
     |> assign(:reload_timer, nil)
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

  # 3-tuple form from AgentWorkerEvents: {:agent_working, provider_conv_id, session_int_id}
  @impl true
  def handle_info({:agent_working, _ref, session_id}, socket),
    do: AgentLifecycle.handle_agent_working(session_id, socket)

  @impl true
  def handle_info({:agent_stopped, msg}, socket),
    do: AgentLifecycle.handle_agent_stopped(msg, socket)

  # 3-tuple form from AgentWorkerEvents: {:agent_stopped, provider_conv_id, session_int_id}
  @impl true
  def handle_info({:agent_stopped, _ref, session_id}, socket),
    do: AgentLifecycle.handle_agent_stopped(session_id, socket)

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

  @impl true
  def handle_info(msg, socket) do
    Logger.debug("Unhandled message in DM LiveView: #{inspect(msg)}")
    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div id="dm-live-root" phx-hook="GlobalKeydown">
      <DmPage.dm_page
        agent={@session}
        agent_record={@agent}
        session_uuid={@session_uuid}
        active_tab={@active_tab}
        active_overlay={@active_overlay}
        messages={@messages}
        has_more_messages={@has_more_messages}
        uploads={@uploads}
        stream={%{show: @show_live_stream, content: @stream_content, tool: @stream_tool, thinking: @stream_thinking}}
        selected_model={@selected_model}
        selected_effort={@selected_effort}
        processing={@processing}
        session={@session}
        tasks={@tasks}
        commits={@commits}
        diff_cache={@diff_cache}
        notes={@notes}
        slash_items={@slash_items}
        current_task={@current_task}
        queued_prompts={@queued_prompts}
        thinking_enabled={@thinking_enabled}
        max_budget_usd={@max_budget_usd}
        compacting={@compacting}
        context_used={@context_used}
        context_window={@context_window}
        message_search_query={@message_search_query}
        session_context={@session_context}
        reloading={@reloading}
        active_timer={@active_timer}
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

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  # On connected mount, sync messages from the session file into the DB first
  # so navigating back after an agent run shows the full conversation (including
  # tool blocks), not just the final text saved by on_result_received.
  # Falls back to a plain DB query if no session file / project path found.
  defp load_messages_on_mount(socket) do
    if connected?(socket) do
      case MessageHandlers.sync_messages_from_session_file(socket) do
        {:ok, socket, _imported} -> socket
        {:error, _reason} -> TabHelpers.load_tab_data(socket, "messages", socket.assigns.session_id)
      end
    else
      TabHelpers.load_tab_data(socket, "messages", socket.assigns.session_id)
    end
  end

  # Apply server-side commands to socket state
  defp apply_server_commands([], socket), do: socket

  defp apply_server_commands([{:rename, name} | rest], socket) do
    socket =
      case Sessions.update_session(socket.assigns.session, %{name: name}) do
        {:ok, updated_session} ->
          socket
          |> assign(:session, updated_session)
          |> assign(:page_title, name)

        {:error, _} ->
          socket
      end

    apply_server_commands(rest, socket)
  end

  defp apply_server_commands([{:model, model} | rest], socket) do
    apply_server_commands(rest, assign(socket, :selected_model, model))
  end

  defp apply_server_commands([{:effort, level} | rest], socket) do
    apply_server_commands(rest, assign(socket, :selected_effort, level))
  end

  defp apply_server_commands([_ | rest], socket), do: apply_server_commands(rest, socket)

  # Merge session-level CLI opts into socket assigns.
  # _noop entries are dropped. For keyed flags (chrome: false), the value is stored
  # so --no-chrome fires on every message. Omitting a key entirely means no flag sent.
  defp apply_session_opts([], socket), do: socket

  defp apply_session_opts([{:_noop, _} | rest], socket),
    do: apply_session_opts(rest, socket)

  defp apply_session_opts([{:_clear, key} | rest], socket) do
    updated = Keyword.delete(socket.assigns.session_cli_opts, key)
    apply_session_opts(rest, assign(socket, :session_cli_opts, updated))
  end

  defp apply_session_opts([{k, v} | rest], socket) do
    updated = Keyword.put(socket.assigns.session_cli_opts, k, v)
    apply_session_opts(rest, assign(socket, :session_cli_opts, updated))
  end
end
