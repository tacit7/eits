defmodule EyeInTheSkyWeb.DmLive do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.{Sessions, Agents, Messages, Tasks, Projects}
  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSky.Claude.{AgentWorker, SessionImporter}
  alias EyeInTheSkyWeb.Components.DmPage
  alias EyeInTheSkyWeb.DmLive.{StreamState, TaskHandlers}
  alias EyeInTheSkyWeb.Live.Shared.{SessionHelpers, AgentStatusHelpers}
  import EyeInTheSkyWeb.Helpers.PubSubHelpers
  import EyeInTheSkyWeb.Live.Shared.TasksHelpers
  import EyeInTheSkyWeb.Live.Shared.DmExportHelpers
  import EyeInTheSkyWeb.Live.Shared.DmModelHelpers
  import EyeInTheSkyWeb.Live.Shared.DmSessionHelpers
  import EyeInTheSkyWeb.Live.Shared.DmStreamHelpers
  import EyeInTheSkyWeb.DmLive.TabHelpers
  import EyeInTheSkyWeb.DmLive.UploadHelpers

  require Logger

  @default_message_limit 20
  @message_page_size 20

  @impl true
  def mount(%{"session_id" => session_id_param} = params, _session, socket) do
    # Accept both integer ID and UUID in URL
    session_result =
      case Integer.parse(session_id_param) do
        {id, ""} -> Sessions.get_session(id)
        _ -> Sessions.get_session_by_uuid(session_id_param)
      end

    with {:session, {:ok, session}} <- {:session, session_result},
         {:agent, {:ok, agent}} <- {:agent, Agents.get_agent(session.agent_id)} do
      if connected?(socket), do: setup_subscriptions(session.id)

      socket =
        socket
        |> assign_sidebar_context(params)
        |> assign_session_state(session, agent)
        |> assign_defaults(session)
        |> load_tab_data("messages", session.id)

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
      |> load_tab_data(tab, socket.assigns.session_id)

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
    do: handle_update_task(params, socket, &reload_tasks/1)

  @impl true
  def handle_event("delete_task", %{"task_id" => _} = params, socket) do
    socket = assign(socket, :active_overlay, nil)
    handle_delete_task(params, socket, &reload_tasks/1)
  end

  @impl true
  def handle_event("archive_task", %{"task_id" => _} = params, socket) do
    socket = assign(socket, :active_overlay, nil)
    handle_archive_task(params, socket, &reload_tasks/1)
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
      |> load_tab_data("tasks", session_id)
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
    handle_send_message(body, socket)
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
      |> load_tab_data("messages", socket.assigns.session_id)

    {:noreply, socket}
  end

  @impl true
  def handle_event("search_messages", %{"query" => query}, socket) do
    query = String.trim(query)

    socket =
      socket
      |> assign(:message_search_query, query)
      |> load_tab_data("messages", socket.assigns.session_id)

    {:noreply, socket}
  end

  @impl true
  def handle_event("export_jsonl", _params, socket), do: handle_export_jsonl(socket)

  @impl true
  def handle_event("export_markdown", _params, socket), do: handle_export_markdown(socket)

  @impl true
  def handle_event("reload_from_session_file", _params, socket),
    do: handle_reload_from_session_file(socket, &load_tab_data(&1, "messages", &1.assigns.session_id))

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
  def handle_event("load_diff", %{"hash" => hash}, socket) do
    if Map.has_key?(socket.assigns.diff_cache, hash) do
      {:noreply, socket}
    else
      diff =
        case SessionHelpers.resolve_project_path(socket.assigns.session, socket.assigns.agent) do
          {:ok, project_path} ->
            case System.cmd("git", ["-C", project_path, "show", hash, "--unified=5"],
                   stderr_to_stdout: false
                 ) do
              {output, 0} -> output
              _ -> :error
            end

          _ ->
            :error
        end

      cache = Map.put(socket.assigns.diff_cache, hash, diff)
      {:noreply, assign(socket, :diff_cache, cache)}
    end
  end

  @impl true
  def handle_event("open_iterm", _params, socket) do
    session_uuid = socket.assigns.session_uuid

    # Reject anything that isn't a canonical UUID to prevent AppleScript injection
    unless Regex.match?(
             ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/,
             session_uuid
           ) do
      {:noreply, put_flash(socket, :error, "Invalid session UUID")}
    else
      dir =
        case SessionHelpers.resolve_project_path(socket.assigns.session, socket.assigns.agent) do
          {:ok, path} -> path
          {:error, _} -> "~"
        end

      # Escape double quotes in the path to prevent AppleScript string injection
      safe_dir = String.replace(dir, "\"", "\\\"")

      script = """
      tell application "iTerm"
        activate
        set newWindow to (create window with default profile)
        tell current session of newWindow
          write text "cd #{safe_dir} && claude --dangerously-skip-permissions -r #{session_uuid}"
        end tell
      end tell
      """

      System.cmd("osascript", ["-e", script], stderr_to_stdout: true)
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_star", params, socket),
    do: handle_toggle_star(params, socket, &load_tab_data(&1, "notes", &1.assigns.session_id))

  @impl true
  def handle_event("kill_session", _params, socket), do: handle_kill_session(socket)

  # ---------------------------------------------------------------------------
  # handle_info: message reload (event-driven, debounced)
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info(:do_message_reload, socket) do
    {:noreply, socket |> assign(:reload_timer, nil) |> maybe_reload_messages()}
  end

  @impl true
  def handle_info({:new_message, _message}, socket) do
    {:noreply, schedule_message_reload(socket)}
  end

  @impl true
  def handle_info({:new_dm, _msg}, socket) do
    {:noreply, schedule_message_reload(socket)}
  end

  # ---------------------------------------------------------------------------
  # handle_info: agent lifecycle
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:claude_response, session_ref, response}, socket) do
    Logger.info(
      "Claude response received ref=#{inspect(session_ref)} type=#{inspect(response["type"])}"
    )

    socket =
      socket
      |> assign(:processing, false)
      |> sync_and_reload()
      |> push_event("focus-input", %{})

    {:noreply, socket}
  end

  @impl true
  def handle_info({:claude_complete, session_ref, exit_code}, socket) do
    Logger.info("Claude session completed ref=#{inspect(session_ref)} exit=#{exit_code}")

    socket =
      socket
      |> assign(:processing, false)
      |> assign(:session_ref, nil)
      |> sync_and_reload()
      |> push_event("focus-input", %{})

    {:noreply, socket}
  end

  @impl true
  def handle_info({:agent_working, msg}, socket) do
    AgentStatusHelpers.handle_agent_working_if_match(
      socket, msg, :session_id,
      fn socket, _session_id ->
        case msg do
          %{status: "compacting"} ->
            assign(socket, :compacting, true)

          _other ->
            socket
            |> assign(:compacting, false)
            |> assign(:processing, true)
        end
      end
    )
  end

  @impl true
  def handle_info({:agent_stopped, msg}, socket) do
    AgentStatusHelpers.handle_agent_stopped_if_match(
      socket, msg, :session_id,
      fn socket, _session_id ->
        socket
        |> assign(:compacting, false)
        |> assign(:processing, false)
        |> sync_and_reload()
        |> push_event("focus-input", %{})
      end
    )
  end

  @impl true
  def handle_info({:agent_updated, %{id: session_id} = updated_session}, socket) do
    if session_id == socket.assigns.session_id do
      {:noreply, assign(socket, :session, updated_session)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:tasks_changed, socket) do
    {:noreply,
     assign(socket, :current_task, Tasks.get_current_task_for_session(socket.assigns.session_id))}
  end

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
  # Mount helpers
  # ---------------------------------------------------------------------------

  defp setup_subscriptions(session_id) do
    subscribe_session(session_id)
    subscribe_agent_working()
    subscribe_agents()
    subscribe_dm_stream(session_id)
    subscribe_dm_queue(session_id)
    subscribe_tasks()
  end

  defp assign_sidebar_context(socket, %{"from" => "project", "project_id" => project_id_str}) do
    case Integer.parse(project_id_str) do
      {pid, ""} ->
        socket
        |> assign(:sidebar_tab, :sessions)
        |> assign(:sidebar_project, Projects.get_project!(pid))

      _ ->
        socket
        |> assign(:sidebar_tab, :chat)
        |> assign(:sidebar_project, nil)
    end
  end

  defp assign_sidebar_context(socket, _params) do
    socket
    |> assign(:sidebar_tab, :chat)
    |> assign(:sidebar_project, nil)
  end

  defp assign_session_state(socket, session, agent) do
    socket
    |> assign(:page_title, session.name || "Session")
    |> assign(:hide_mobile_header, true)
    |> assign(:session_id, session.id)
    |> assign(:session_uuid, session.uuid)
    |> assign(:agent_id, session.agent_id)
    |> assign(:session, session)
    |> assign(:agent, agent)
  end

  defp assign_defaults(socket, session) do
    socket
    |> assign(:active_tab, "messages")
    |> assign(:session_ref, nil)
    |> assign(:processing, AgentWorker.is_processing?(session.id))
    |> assign(:message_limit, @default_message_limit)
    |> assign(:has_more_messages, false)
    |> assign(:selected_model, session.model || "opus")
    |> assign(:selected_effort, "medium")
    |> assign(:active_overlay, nil)
    |> assign(:show_live_stream, false)
    |> assign(:stream_content, AgentWorker.get_stream_state(session.id))
    |> assign(:stream_tool, nil)
    |> assign(:stream_thinking, nil)
    |> assign(:slash_items, build_slash_items())
    |> assign(:diff_cache, %{})
    |> assign(:selected_task, nil)
    |> assign(:task_notes, [])
    |> assign(:workflow_states, Tasks.list_workflow_states())
    |> assign(:current_task, Tasks.get_current_task_for_session(session.id))
    |> assign(:reload_timer, nil)
    |> assign(:total_tokens, 0)
    |> assign(:total_cost, 0.0)
    |> assign(:context_used, 0)
    |> assign(:context_window, 0)
    |> assign(:queued_prompts, AgentWorker.get_queue(session.id))
    |> assign(:thinking_enabled, false)
    |> assign(:max_budget_usd, nil)
    |> assign(:compacting, session.status == "compacting")
    |> assign(:message_search_query, "")
    |> allow_upload(:files,
      accept: ~w(.jpg .jpeg .png .gif .pdf .txt .md .csv .json .xml .html),
      max_entries: 10,
      max_file_size: 50_000_000,
      auto_upload: true
    )
  end

  # ---------------------------------------------------------------------------
  # Messaging internals
  # ---------------------------------------------------------------------------

  defp handle_send_message(body, socket) do
    model = socket.assigns.selected_model
    effort_level = socket.assigns.selected_effort
    thinking_enabled = socket.assigns.thinking_enabled
    max_budget_usd = socket.assigns.max_budget_usd

    Logger.info(
      "DM send_message received for session=#{socket.assigns.session_id} model=#{model} effort=#{effort_level} body_length=#{String.length(body)}"
    )

    uploaded_files = consume_uploaded_files(socket)
    full_body = build_message_body(body, uploaded_files)
    session_id = socket.assigns.session_id
    provider = socket.assigns.session.provider

    case create_user_message(session_id, full_body, provider) do
      {:ok, message} ->
        Logger.info("Message created in DB with id=#{message.id}")
        persist_upload_attachments(uploaded_files, message.id)

        socket = load_tab_data(socket, "messages", session_id)

        case AgentManager.continue_session(
               session_id,
               full_body,
               SessionHelpers.continue_session_opts(model, effort_level, thinking_enabled, max_budget_usd)
             ) do
          {:ok, _admission} ->
            Logger.info("Message forwarded to AgentManager for session=#{session_id}")

            {:noreply,
             socket
             |> assign(:processing, true)
             |> push_event("clear-input", %{})}

          {:error, reason} ->
            Logger.error("Failed to send message via AgentManager: #{inspect(reason)}")

            socket =
              socket
              |> assign(:processing, false)
              |> put_flash(:error, "Failed to send message: #{inspect(reason)}")

            {:noreply, socket}
        end

      {:error, reason} ->
        Logger.error("Failed to create message: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Failed to create message: #{inspect(reason)}")}
    end
  end

  defp create_user_message(session_id, body, provider) do
    Messages.send_message(%{
      session_id: session_id,
      sender_role: "user",
      recipient_role: "agent",
      provider: provider || "claude",
      body: body
    })
  end

  # ---------------------------------------------------------------------------
  # Session file sync
  # ---------------------------------------------------------------------------

  defp sync_messages_from_session_file(socket) do
    session_id = socket.assigns.session_id
    session_uuid = socket.assigns.session_uuid

    with {:ok, project_path} <-
           SessionHelpers.resolve_project_path(socket.assigns.session, socket.assigns.agent),
         {:ok, imported} <- SessionImporter.sync(session_uuid, project_path, session_id) do
      {:ok, load_tab_data(socket, "messages", session_id), imported}
    end
  end

  # ---------------------------------------------------------------------------
  # Reload helpers (event-driven, debounced)
  # ---------------------------------------------------------------------------

  @reload_debounce_ms 300

  defp schedule_message_reload(socket) do
    if socket.assigns.reload_timer do
      Process.cancel_timer(socket.assigns.reload_timer)
    end

    timer = Process.send_after(self(), :do_message_reload, @reload_debounce_ms)
    assign(socket, :reload_timer, timer)
  end

  defp sync_and_reload(socket) do
    case sync_messages_from_session_file(socket) do
      {:ok, socket, _imported} -> socket
      {:error, _reason} -> maybe_reload_messages(socket)
    end
  end

  defp maybe_reload_messages(socket) do
    if socket.assigns.active_tab == "messages" do
      load_tab_data(socket, "messages", socket.assigns.session_id)
    else
      socket
    end
  end

  # ---------------------------------------------------------------------------
  # Misc helpers
  # ---------------------------------------------------------------------------

  defp build_slash_items do
    EyeInTheSkyWeb.Helpers.SlashItems.build()
  end
end
