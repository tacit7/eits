defmodule EyeInTheSkyWebWeb.DmLive do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.{
    Sessions,
    Agents,
    Commits,
    Messages,
    Notes,
    Repo,
    Tasks,
    Projects
  }

  alias EyeInTheSkyWeb.Agents.AgentManager
  alias EyeInTheSkyWeb.Claude.{AgentWorker, SessionReader}
  alias EyeInTheSkyWeb.FileAttachments
  alias EyeInTheSkyWebWeb.Components.DmPage
  alias EyeInTheSkyWebWeb.DmLive.StreamState
  import EyeInTheSkyWebWeb.Helpers.PubSubHelpers
  import EyeInTheSkyWebWeb.Live.Shared.TasksHelpers

  require Logger

  @default_message_limit 20
  @message_page_size 20
  @sync_interval 3_000

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
  def handle_event("toggle_model_menu", _params, socket) do
    overlay = if socket.assigns.active_overlay == :model_menu, do: nil, else: :model_menu
    {:noreply, assign(socket, :active_overlay, overlay)}
  end

  @impl true
  def handle_event("toggle_effort_menu", _params, socket) do
    overlay = if socket.assigns.active_overlay == :effort_menu, do: nil, else: :effort_menu
    {:noreply, assign(socket, :active_overlay, overlay)}
  end

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
  def handle_event("toggle_thinking", _params, socket) do
    {:noreply, assign(socket, :thinking_enabled, !socket.assigns.thinking_enabled)}
  end

  @impl true
  def handle_event("toggle_live_stream", params, socket) do
    enabled =
      case params do
        %{"enabled" => true} -> true
        %{"enabled" => "true"} -> true
        _ -> !socket.assigns.show_live_stream
      end

    {:noreply, assign(socket, :show_live_stream, enabled)}
  end

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
  def handle_event("open_task_detail", %{"task_id" => task_id}, socket) do
    task = Tasks.get_task_by_uuid_or_id!(task_id)
    notes = Notes.list_notes_for_task(task.id)

    {:noreply,
     socket
     |> assign(:selected_task, task)
     |> assign(:task_notes, notes)
     |> assign(:active_overlay, :task_detail)}
  end

  def handle_event("open_task_detail", _params, socket), do: {:noreply, socket}

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
  def handle_event("start_agent_for_task", %{"task_id" => task_id}, socket) do
    task = Tasks.get_task_by_uuid_or_id!(task_id)
    session = socket.assigns.session
    agent = socket.assigns.agent

    project_id = agent.project_id

    project_path =
      case resolve_project_path(session, agent) do
        {:ok, path} -> path
        _ -> nil
      end

    task_prompt = "#{task.title}\n\n#{task.description || ""}" |> String.trim()

    opts =
      [description: task.title, instructions: task_prompt, model: "sonnet"]
      |> then(fn o -> if project_id, do: o ++ [project_id: project_id], else: o end)
      |> then(fn o -> if project_path, do: o ++ [project_path: project_path], else: o end)

    case AgentManager.create_agent(opts) do
      {:ok, %{session: new_session}} ->
        Tasks.link_session_to_task(task.id, new_session.id)

        {:noreply,
         socket
         |> assign(:active_overlay, nil)
         |> put_flash(:info, "Agent spawned for: #{String.slice(task.title, 0..40)}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to spawn agent: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("create_new_task", params, socket) do
    session_id = socket.assigns.session_id

    case Tasks.create_task_from_form(params, session_id: session_id) do
      {:ok, _task} ->
        socket =
          socket
          |> assign(:active_overlay, nil)
          |> assign(:active_tab, "tasks")
          |> load_tab_data("tasks", session_id)
          |> put_flash(:info, "Task created")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply,
         put_flash(socket, :error, "Failed to create task: #{inspect(changeset.errors)}")}
    end
  end

  # ---------------------------------------------------------------------------
  # Session & model settings
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("select_model", %{"model" => model, "effort" => effort}, socket) do
    session = socket.assigns.session

    socket =
      case Sessions.update_session(session, %{model: model}) do
        {:ok, _updated} ->
          socket

        {:error, changeset} ->
          Logger.error("Failed to persist model selection: #{inspect(changeset.errors)}")
          put_flash(socket, :error, "Failed to save model selection")
      end

    effort = if effort == "" and model == "opus", do: "medium", else: effort

    socket =
      socket
      |> assign(:selected_model, model)
      |> assign(:selected_effort, effort)
      |> assign(:active_overlay, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_effort", %{"effort" => effort}, socket) do
    {:noreply, socket |> assign(:selected_effort, effort) |> assign(:active_overlay, nil)}
  end

  @impl true
  def handle_event("set_max_budget", %{"value" => value}, socket) do
    budget =
      case Float.parse(value) do
        {f, _} when f > 0 -> f
        _ -> nil
      end

    {:noreply, assign(socket, :max_budget_usd, budget)}
  end

  @impl true
  def handle_event("update_session_name", %{"value" => value}, socket) do
    session = socket.assigns.session
    value = String.trim(value)

    case Sessions.update_session(session, %{name: if(value == "", do: nil, else: value)}) do
      {:ok, updated} ->
        {:noreply, assign(socket, :session, updated)}

      {:error, changeset} ->
        Logger.error("Failed to update session name: #{inspect(changeset.errors)}")
        {:noreply, put_flash(socket, :error, "Failed to update session name")}
    end
  end

  @impl true
  def handle_event("update_session_description", %{"value" => value}, socket) do
    session = socket.assigns.session
    value = String.trim(value)

    case Sessions.update_session(session, %{description: if(value == "", do: nil, else: value)}) do
      {:ok, updated} ->
        {:noreply, assign(socket, :session, updated)}

      {:error, changeset} ->
        Logger.error("Failed to update session description: #{inspect(changeset.errors)}")
        {:noreply, put_flash(socket, :error, "Failed to update session description")}
    end
  end

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
  def handle_event("export_jsonl", _params, socket) do
    messages = socket.assigns[:messages] || []

    text =
      messages
      |> Enum.map(fn msg ->
        Jason.encode!(%{
          role: msg.sender_role,
          body: msg.body,
          timestamp: msg.inserted_at
        })
      end)
      |> Enum.join("\n")

    {:noreply, push_event(socket, "copy_to_clipboard", %{text: text, format: "JSONL"})}
  end

  @impl true
  def handle_event("export_markdown", _params, socket) do
    messages = socket.assigns[:messages] || []

    text =
      messages
      |> Enum.map(fn msg ->
        role = String.capitalize(to_string(msg.sender_role))
        "**#{role}**: #{msg.body}"
      end)
      |> Enum.join("\n\n")

    {:noreply, push_event(socket, "copy_to_clipboard", %{text: text, format: "Markdown"})}
  end

  @impl true
  def handle_event("reload_from_session_file", _params, socket) do
    session_id = socket.assigns.session_id
    session_uuid = socket.assigns.session_uuid

    with {:ok, project_path} <-
           resolve_project_path(socket.assigns.session, socket.assigns.agent),
         {:ok, raw_messages} <-
           SessionReader.read_messages_after_uuid(session_uuid, project_path, nil) do
      Messages.delete_session_messages(session_id)
      imported = import_session_messages(raw_messages, session_id)
      socket = load_tab_data(socket, "messages", session_id)
      {:noreply, put_flash(socket, :info, "Reloaded #{imported} messages from session file")}
    else
      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "No session file found for this session")}

      {:error, :no_project_path} ->
        {:noreply, put_flash(socket, :error, "No project path configured")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to reload: #{inspect(reason)}")}
    end
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
  def handle_event("load_diff", %{"hash" => hash}, socket) do
    if Map.has_key?(socket.assigns.diff_cache, hash) do
      {:noreply, socket}
    else
      diff =
        case resolve_project_path(socket.assigns.session, socket.assigns.agent) do
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
        case resolve_project_path(socket.assigns.session, socket.assigns.agent) do
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

  # ---------------------------------------------------------------------------
  # Notes
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("toggle_star", params, socket) do
    note_id = params["note_id"] || params["note-id"] || params["value"]

    case Notes.toggle_starred(note_id) do
      {:ok, _note} ->
        {:noreply, load_tab_data(socket, "notes", socket.assigns.session_id)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to toggle star")}
    end
  end

  # ---------------------------------------------------------------------------
  # Session control
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("kill_session", _params, socket) do
    session_id = socket.assigns.session_id

    # Properly stop the worker — GenServer.stop calls terminate/2 which cancels the SDK subprocess.
    # Process.exit does NOT call terminate/2 for non-trapping GenServers, so the CLI keeps running.
    case Registry.lookup(EyeInTheSkyWeb.Claude.AgentRegistry, {:session, session_id}) do
      [{pid, _}] ->
        Logger.warning(
          "kill_session: stopping worker pid=#{inspect(pid)} for session=#{session_id}"
        )

        try do
          GenServer.stop(pid, :shutdown, 3000)
        catch
          :exit, _ -> :ok
        end

      [] ->
        # Worker not running — just cancel via AgentManager in case SDK ref exists elsewhere
        AgentManager.cancel_session(session_id)
    end

    # Update session status so stale agent_working PubSub events don't revive the UI
    case Sessions.get_session(session_id) do
      {:ok, session} ->
        Sessions.update_session(session, %{status: "stopped"})
        EyeInTheSkyWeb.Events.agent_stopped(session)

      _ ->
        :ok
    end

    {:noreply, socket |> assign(:processing, false) |> stop_sync_timer()}
  end

  # ---------------------------------------------------------------------------
  # handle_info: sync & reload
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info(:sync_from_session_file, socket) do
    case sync_messages_from_session_file(socket) do
      {:ok, socket, _imported} -> {:noreply, socket}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:periodic_sync, socket) do
    actually_processing = AgentWorker.is_processing?(socket.assigns.session_id)

    if socket.assigns.processing && actually_processing do
      case sync_messages_from_session_file(socket) do
        {:ok, socket, _imported} ->
          {:noreply, start_sync_timer(socket)}

        {:error, _reason} ->
          {:noreply, start_sync_timer(socket)}
      end
    else
      {:noreply, socket |> assign(:processing, false) |> assign(:sync_timer, nil)}
    end
  end

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
      |> stop_sync_timer()
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
      |> stop_sync_timer()
      |> sync_and_reload()
      |> push_event("focus-input", %{})

    {:noreply, socket}
  end

  @impl true
  def handle_info({:agent_working, %{id: session_id, status: "compacting"}}, socket) do
    if session_id == socket.assigns.session_id do
      {:noreply, assign(socket, :compacting, true)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:agent_working, %{id: session_id}}, socket) do
    if session_id == socket.assigns.session_id do
      {:noreply,
       socket
       |> assign(:compacting, false)
       |> assign(:processing, true)
       |> start_sync_timer()}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:agent_working, _session_uuid, session_id}, socket) do
    if session_id == socket.assigns.session_id do
      {:noreply,
       socket
       |> assign(:processing, true)
       |> start_sync_timer()}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:agent_stopped, %{id: session_id}}, socket) do
    if session_id == socket.assigns.session_id do
      {:noreply,
       socket
       |> assign(:compacting, false)
       |> assign(:processing, false)
       |> stop_sync_timer()
       |> sync_and_reload()
       |> push_event("focus-input", %{})}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:agent_stopped, _session_uuid, session_id}, socket) do
    if session_id == socket.assigns.session_id do
      {:noreply,
       socket
       |> assign(:compacting, false)
       |> assign(:processing, false)
       |> stop_sync_timer()
       |> sync_and_reload()
       |> push_event("focus-input", %{})}
    else
      {:noreply, socket}
    end
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
  # handle_info: streaming — delegated to DmLive.StreamState
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:stream_delta, type, content}, socket),
    do: StreamState.handle_stream_delta(type, content, socket)

  @impl true
  def handle_info({:stream_replace, type, content}, socket),
    do: StreamState.handle_stream_replace(type, content, socket)

  @impl true
  def handle_info(:stream_clear, socket),
    do: StreamState.handle_stream_clear(socket)

  @impl true
  def handle_info({:stream_tool_input, name, input}, socket),
    do: StreamState.handle_stream_tool_input(name, input, socket)

  @impl true
  def handle_info({:tool_use, tool_name, _params}, socket),
    do: StreamState.handle_tool_use(tool_name, socket)

  @impl true
  def handle_info({:tool_result, _tool_name, _is_error}, socket) do
    {:noreply, socket |> assign(:stream_tool, nil) |> schedule_message_reload()}
  end

  @impl true
  def handle_info({:queue_updated, prompts}, socket),
    do: StreamState.handle_queue_updated(prompts, socket)

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
      />

      <EyeInTheSkyWebWeb.Components.NewTaskDrawer.new_task_drawer
        id="dm-new-task-drawer"
        show={@active_overlay == :task_drawer}
        workflow_states={@workflow_states}
        toggle_event="toggle_new_task_drawer"
        submit_event="create_new_task"
      />

      <EyeInTheSkyWebWeb.Components.TaskDetailDrawer.task_detail_drawer
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
    send(self(), :sync_from_session_file)
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
    |> assign(:sync_timer, nil)
    |> assign(:reload_timer, nil)
    |> assign(:total_tokens, 0)
    |> assign(:total_cost, 0.0)
    |> assign(:context_used, 0)
    |> assign(:context_window, 0)
    |> assign(:queued_prompts, AgentWorker.get_queue(session.id))
    |> assign(:thinking_enabled, false)
    |> assign(:max_budget_usd, nil)
    |> assign(:compacting, session.status == "compacting")
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
               continue_session_opts(model, effort_level, thinking_enabled, max_budget_usd)
             ) do
          {:ok, _admission} ->
            Logger.info("Message forwarded to AgentManager for session=#{session_id}")

            {:noreply,
             socket
             |> assign(:processing, true)
             |> start_sync_timer()
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

  defp continue_session_opts(model, effort_level, thinking_enabled, max_budget_usd) do
    opts = [model: model]

    opts =
      if is_binary(effort_level) and effort_level != "" do
        opts ++ [effort_level: effort_level]
      else
        opts
      end

    opts =
      if thinking_enabled do
        budget =
          case model do
            "opus" -> 16000
            _ -> 10000
          end

        opts ++ [thinking_budget: budget]
      else
        opts
      end

    if max_budget_usd do
      opts ++ [max_budget_usd: max_budget_usd]
    else
      opts
    end
  end

  # ---------------------------------------------------------------------------
  # Tab data loading
  # ---------------------------------------------------------------------------

  defp load_tab_data(socket, tab, session_id) do
    Logger.info("Loading DM tab data tab=#{tab} session_id=#{session_id}")
    {messages, has_more} = load_message_data(socket, tab, session_id)

    {total_tokens, total_cost} =
      maybe_load_value(
        tab,
        "messages",
        {socket.assigns[:total_tokens], socket.assigns[:total_cost]},
        fn ->
          read_session_usage_stats(socket, session_id)
        end
      )

    current_task =
      maybe_load_value(tab, ["messages", "tasks"], socket.assigns[:current_task], fn ->
        Tasks.get_current_task_for_session(session_id)
      end)

    {context_used, context_window} =
      maybe_load_value(
        tab,
        "messages",
        {socket.assigns[:context_used], socket.assigns[:context_window]},
        fn ->
          extract_context_window(messages)
        end
      )

    socket
    |> assign(:messages, messages)
    |> assign(:has_more_messages, has_more)
    |> assign(:total_tokens, total_tokens)
    |> assign(:total_cost, total_cost)
    |> assign(:context_used, context_used || 0)
    |> assign(:context_window, context_window || 0)
    |> assign(:current_task, current_task)
    |> assign(
      :tasks,
      maybe_load_tab_data(tab, "tasks", socket.assigns[:tasks], fn ->
        Tasks.list_tasks_for_session(session_id)
      end)
    )
    |> assign(
      :commits,
      maybe_load_tab_data(tab, "commits", socket.assigns[:commits], fn ->
        Commits.list_commits_for_session(session_id)
      end)
    )
    |> assign(
      :notes,
      maybe_load_tab_data(tab, "notes", socket.assigns[:notes], fn ->
        Notes.list_notes_for_session(session_id)
      end)
    )
  end

  defp reload_tasks(socket) do
    assign(socket, :tasks, Tasks.list_tasks_for_session(socket.assigns.session_id))
  end

  defp load_message_data(socket, "messages", session_id) do
    limit = socket.assigns[:message_limit] || @default_message_limit

    fetched_messages =
      Messages.list_recent_messages(session_id, limit + 1)
      |> Repo.preload(:attachments)

    Logger.info("Loaded #{length(fetched_messages)} messages for session=#{session_id}")

    if length(fetched_messages) > limit do
      {Enum.drop(fetched_messages, 1), true}
    else
      {fetched_messages, false}
    end
  end

  defp load_message_data(socket, _tab, _session_id) do
    {socket.assigns[:messages] || [], socket.assigns[:has_more_messages] || false}
  end

  defp maybe_load_tab_data(active_tab, target_tab, existing_data, loader) do
    if active_tab == target_tab do
      loader.()
    else
      existing_data || []
    end
  end

  defp maybe_load_value(active_tab, target_tabs, existing_value, loader) do
    targets = List.wrap(target_tabs)

    if active_tab in targets do
      loader.()
    else
      existing_value
    end
  end

  # ---------------------------------------------------------------------------
  # Session file sync
  # ---------------------------------------------------------------------------

  defp sync_messages_from_session_file(socket) do
    session_id = socket.assigns.session_id
    session_uuid = socket.assigns.session_uuid

    with {:ok, project_path} <-
           resolve_project_path(socket.assigns.session, socket.assigns.agent),
         {:ok, raw_messages} <- read_session_messages(session_uuid, project_path, session_id) do
      imported = import_session_messages(raw_messages, session_id)
      {:ok, load_tab_data(socket, "messages", session_id), imported}
    end
  end

  defp read_session_messages(session_uuid, project_path, session_id) do
    last_uuid = Messages.get_last_source_uuid(session_id)
    SessionReader.read_messages_after_uuid(session_uuid, project_path, last_uuid)
  end

  defp import_session_messages(raw_messages, session_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    raw_messages
    |> SessionReader.format_messages()
    |> Enum.filter(& &1.uuid)
    |> Enum.count(&import_single_session_message(&1, session_id, now))
  end

  defp import_single_session_message(msg, session_id, now) do
    {sender_role, recipient_role, direction} = session_message_roles(msg.role)
    inserted_at = parse_session_timestamp(msg.timestamp, now)

    # Check for an existing unlinked message (created before sync) with matching content.
    # This prevents duplicates when save_result or create_user_message already persisted the
    # message without a source_uuid, and the session file sync tries to create it again.
    metadata =
      cond do
        msg[:stream_type] == "tool_result" -> %{"stream_type" => "tool_result"}
        msg.usage -> %{"usage" => msg.usage}
        true -> nil
      end

    case Messages.find_unlinked_message(session_id, sender_role, msg.content) do
      {:ok, existing} ->
        update_attrs = %{source_uuid: msg.uuid, updated_at: now}

        update_attrs =
          if metadata, do: Map.put(update_attrs, :metadata, metadata), else: update_attrs

        Messages.update_message(existing, update_attrs)
        true

      :not_found ->
        case Messages.create_message(%{
               uuid: Ecto.UUID.generate(),
               source_uuid: msg.uuid,
               session_id: session_id,
               sender_role: sender_role,
               recipient_role: recipient_role,
               direction: direction,
               body: msg.content,
               status: "delivered",
               provider: "claude",
               metadata: metadata,
               inserted_at: inserted_at,
               updated_at: now
             }) do
          {:ok, _message} ->
            true

          {:error, reason} ->
            Logger.debug("Skipping imported message source_uuid=#{msg.uuid}: #{inspect(reason)}")
            false
        end
    end
  end

  defp session_message_roles("user"), do: {"user", "agent", "outbound"}
  defp session_message_roles(_role), do: {"agent", "user", "inbound"}

  defp parse_session_timestamp(timestamp, fallback) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _offset} -> DateTime.truncate(dt, :second)
      _ -> fallback
    end
  end

  defp parse_session_timestamp(_timestamp, fallback), do: fallback

  # ---------------------------------------------------------------------------
  # Context window extraction
  # ---------------------------------------------------------------------------

  defp extract_context_window(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(fn msg ->
      case msg.metadata do
        # Claude CLI result messages: model_usage map with camelCase keys
        %{"model_usage" => model_usage} when is_map(model_usage) and map_size(model_usage) > 0 ->
          model_usage
          |> Map.values()
          |> Enum.find_value(fn entry when is_map(entry) ->
            input = entry["inputTokens"] || 0
            cache_read = entry["cacheReadInputTokens"] || 0
            cache_creation = entry["cacheCreationInputTokens"] || 0
            ctx_window = entry["contextWindow"] || 200_000
            used = input + cache_read + cache_creation

            if used > 0, do: {used, ctx_window}
          end)

        # Anubis/streaming messages: usage map with snake_case keys
        %{"usage" => %{"input_tokens" => _} = usage} ->
          input = usage["input_tokens"] || 0
          cache_read = usage["cache_read_input_tokens"] || 0
          cache_creation = usage["cache_creation_input_tokens"] || 0
          used = input + cache_read + cache_creation

          if used > 0, do: {used, 200_000}

        _ ->
          nil
      end
    end) || {0, 0}
  end

  defp read_session_usage_stats(socket, session_id) do
    case resolve_project_path(socket.assigns.session, socket.assigns.agent) do
      {:ok, project_path} ->
        case SessionReader.read_usage(socket.assigns.session_uuid, project_path) do
          {:ok, tokens, cost} ->
            {tokens, cost}

          _ ->
            {Messages.total_tokens_for_session(session_id),
             Messages.total_cost_for_session(session_id)}
        end

      _ ->
        {Messages.total_tokens_for_session(session_id),
         Messages.total_cost_for_session(session_id)}
    end
  end

  # ---------------------------------------------------------------------------
  # File uploads
  # ---------------------------------------------------------------------------

  defp consume_uploaded_files(socket) do
    consume_uploaded_entries(socket, :files, fn %{path: temp_path}, entry ->
      destination = upload_destination(entry.client_name)

      File.mkdir_p!(Path.dirname(destination))
      File.cp!(temp_path, destination)

      {:ok,
       %{
         storage_path: destination,
         filename: Path.basename(destination),
         original_filename: entry.client_name,
         content_type: entry.client_type,
         size_bytes: entry.client_size
       }}
    end)
  end

  defp upload_destination(client_name) do
    base_upload_dir = Path.join([:code.priv_dir(:eye_in_the_sky_web), "static", "uploads", "dm"])
    date_dir = Date.utc_today() |> Date.to_string()
    filename = "#{Ecto.UUID.generate()}#{Path.extname(client_name)}"

    Path.join([base_upload_dir, date_dir, filename])
  end

  defp build_message_body(body, []), do: body

  defp build_message_body(body, uploaded_files) do
    file_list =
      uploaded_files
      |> Enum.map(fn file_data ->
        relative = relative_upload_path(file_data.storage_path)
        "- #{relative} (#{file_data.original_filename})"
      end)
      |> Enum.join("\n")

    "#{body}\n\nAttached files:\n#{file_list}"
  end

  defp relative_upload_path(abs_path) do
    priv_static = Path.join(:code.priv_dir(:eye_in_the_sky_web), "static")

    case String.split(abs_path, priv_static, parts: 2) do
      [_, relative] -> relative
      _ -> Path.basename(abs_path)
    end
  end

  defp persist_upload_attachments(uploaded_files, message_id) do
    Enum.each(uploaded_files, fn file_data ->
      case FileAttachments.create_attachment(Map.put(file_data, :message_id, message_id)) do
        {:ok, _attachment} ->
          :ok

        {:error, reason} ->
          Logger.warning(
            "Failed to persist attachment for message_id=#{message_id}: #{inspect(reason)}"
          )
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Timer helpers
  # ---------------------------------------------------------------------------

  defp start_sync_timer(socket) do
    if socket.assigns.sync_timer do
      Process.cancel_timer(socket.assigns.sync_timer)
    end

    timer = Process.send_after(self(), :periodic_sync, @sync_interval)
    assign(socket, :sync_timer, timer)
  end

  defp stop_sync_timer(socket) do
    if socket.assigns.sync_timer do
      Process.cancel_timer(socket.assigns.sync_timer)
    end

    assign(socket, :sync_timer, nil)
  end

  # Debounce rapid bursts of reload triggers (new_message, new_dm, tool_result).
  # Messages context broadcasts immediately; Broadcaster re-broadcasts 2s later for the same
  # messages. Without debounce, each message causes at least 2 DB queries.
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
    EyeInTheSkyWebWeb.Helpers.SlashItems.build()
  end

  defp resolve_project_path(session, agent) do
    cond do
      session.git_worktree_path ->
        {:ok, session.git_worktree_path}

      agent.git_worktree_path ->
        {:ok, agent.git_worktree_path}

      agent.project && agent.project.path ->
        {:ok, agent.project.path}

      true ->
        {:error, :no_project_path}
    end
  end
end
