defmodule EyeInTheSkyWeb.DmLive do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.{Sessions, Agents}
  alias EyeInTheSky.Claude.AgentWorker
  alias EyeInTheSkyWeb.Components.DmPage
  alias EyeInTheSkyWeb.DmLive.TaskHandlers
  alias EyeInTheSkyWeb.DmLive.{MountState, MessageHandlers, AgentLifecycle, ExternalActions}
  alias EyeInTheSkyWeb.DmLive.TabHelpers
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
    session_result =
      case Integer.parse(session_id_param) do
        {id, ""} -> Sessions.get_session(id)
        _ -> Sessions.get_session_by_uuid(session_id_param)
      end

    with {:session, {:ok, session}} <- {:session, session_result},
         {:agent, {:ok, agent}} <- {:agent, Agents.get_agent(session.agent_id)} do
      MountState.maybe_subscribe(socket, session.id)

      socket =
        socket
        |> MountState.assign_sidebar_context(params)
        |> MountState.assign_session_state(session, agent)
        |> MountState.assign_defaults(session)
        |> TabHelpers.load_tab_data("messages", session.id)

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
  def handle_event("toggle_thinking", _params, socket), do: handle_toggle_thinking(socket)

  @impl true
  def handle_event("toggle_live_stream", params, socket), do: handle_toggle_live_stream(params, socket)

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
    MessageHandlers.handle_send_message(body, socket)
  end

  @impl true
  def handle_event("send_message", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("remove_queued_prompt", %{"id" => id_str}, socket) do
    case Integer.parse(id_str) do
      {id, ""} -> AgentWorker.remove_queued_prompt(socket.assigns.session_id, id)
      _ -> :ok
    end

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
    send(self(), :do_reload_from_session_file)
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
        session_uuid={@session_uuid}
        active_tab={@active_tab}
        messages={@messages}
        has_more_messages={@has_more_messages}
        uploads={@uploads}
        selected_model={@selected_model}
        selected_effort={@selected_effort}
        show_effort_menu={@active_overlay == :effort_menu}
        show_model_menu={@active_overlay == :model_menu}
        processing={@processing}
        show_live_stream={@show_live_stream}
        stream_content={@stream_content}
        stream_tool={@stream_tool}
        stream_thinking={@stream_thinking}
        session={@session}
        tasks={@tasks}
        commits={@commits}
        diff_cache={@diff_cache}
        notes={@notes}
        slash_items={@slash_items}
        show_new_task_drawer={@active_overlay == :task_drawer}
        workflow_states={@workflow_states}
        current_task={@current_task}
        total_tokens={@total_tokens}
        total_cost={@total_cost}
        queued_prompts={@queued_prompts}
        thinking_enabled={@thinking_enabled}
        max_budget_usd={@max_budget_usd}
        compacting={@compacting}
        context_used={@context_used}
        context_window={@context_window}
        message_search_query={@message_search_query}
        session_context={@session_context}
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
end
