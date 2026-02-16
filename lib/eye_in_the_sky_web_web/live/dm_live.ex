defmodule EyeInTheSkyWebWeb.DmLive do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.{Agents, ChatAgents, Commits, Logs, Messages, Notes, Repo, Tasks}
  alias EyeInTheSkyWeb.Claude.{AgentManager, SessionReader}
  alias EyeInTheSkyWeb.FileAttachments
  alias EyeInTheSkyWebWeb.Components.DmPage

  require Logger

  @default_message_limit 20
  @message_page_size 20

  @impl true
  def mount(%{"session_id" => session_id_param}, _session, socket) do
    # Accept both integer ID and UUID in URL
    agent =
      case Integer.parse(session_id_param) do
        {id, ""} -> Agents.get_execution_agent!(id)
        _ -> Agents.get_execution_agent_by_uuid!(session_id_param)
      end

    chat_agent = ChatAgents.get_chat_agent!(agent.agent_id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "session:#{agent.id}")
      Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "agent:working")
      Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "dm:#{agent.id}:stream")
      send(self(), :sync_from_session_file)
    end

    socket =
      socket
      |> assign(:page_title, agent.name || "Session")
      |> assign(:sidebar_tab, :chat)
      |> assign(:sidebar_project, nil)
      |> assign(:session_id, agent.id)
      |> assign(:session_uuid, agent.uuid)
      |> assign(:agent_id, agent.agent_id)
      |> assign(:agent, agent)
      |> assign(:chat_agent, chat_agent)
      |> assign(:active_tab, "messages")
      |> assign(:session_ref, nil)
      |> assign(:processing, false)
      |> assign(:message_limit, @default_message_limit)
      |> assign(:has_more_messages, false)
      |> assign(:selected_model, "opus")
      |> assign(:selected_effort, "")
      |> assign(:show_model_menu, false)
      |> assign(:show_live_stream, false)
      |> assign(:stream_content, "")
      |> assign(:stream_tool, nil)
      |> allow_upload(:files,
        accept: ~w(.jpg .jpeg .png .gif .pdf .txt .md .csv .json .xml .html),
        max_entries: 10,
        max_file_size: 50_000_000,
        auto_upload: true
      )
      |> load_tab_data("messages", agent.id)

    {:ok, socket}
  end

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
    {:noreply, assign(socket, :show_model_menu, !socket.assigns.show_model_menu)}
  end

  @impl true
  def handle_event("select_model", %{"model" => model, "effort" => effort}, socket) do
    socket =
      socket
      |> assign(:selected_model, model)
      |> assign(:selected_effort, effort)
      |> assign(:show_model_menu, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_live_stream", params, socket) do
    enabled = case params do
      %{"enabled" => true} -> true
      %{"enabled" => "true"} -> true
      _ -> !socket.assigns.show_live_stream
    end

    {:noreply, assign(socket, :show_live_stream, enabled)}
  end

  @impl true
  def handle_event("send_message", %{"body" => body}, socket) when body != "" do
    if socket.assigns.processing do
      {:noreply, socket}
    else
      handle_send_message(body, socket)
    end
  end

  defp handle_send_message(body, socket) do
    model = socket.assigns.selected_model
    effort_level = socket.assigns.selected_effort

    Logger.info(
      "DM send_message received for session=#{socket.assigns.session_id} model=#{model} effort=#{effort_level} body_length=#{String.length(body)}"
    )

    uploaded_files = consume_uploaded_files(socket)
    full_body = build_message_body(body, uploaded_files)
    session_id = socket.assigns.session_id

    case create_user_message(session_id, full_body) do
      {:ok, message} ->
        Logger.info("Message created in DB with id=#{message.id}")
        persist_upload_attachments(uploaded_files, message.id)

        socket = load_tab_data(socket, "messages", session_id)

        case AgentManager.continue_session(
               session_id,
               full_body,
               continue_session_opts(model, effort_level)
             ) do
          :ok ->
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

  @impl true
  def handle_event("send_message", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :files, ref)}
  end

  @impl true
  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end


  @impl true
  def handle_event("reload_from_session_file", _params, socket) do
    session_id = socket.assigns.session_id
    session_uuid = socket.assigns.session_uuid

    with {:ok, project_path} <-
           resolve_project_path(socket.assigns.agent, socket.assigns.chat_agent),
         {:ok, raw_messages} <- SessionReader.read_messages_after_uuid(session_uuid, project_path, nil) do
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
  def handle_event("kill_session", _params, socket) do
    AgentManager.cancel_session(socket.assigns.session_id)
    {:noreply, assign(socket, :processing, false)}
  end

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

  @impl true
  def handle_info(:sync_from_session_file, socket) do
    case sync_messages_from_session_file(socket) do
      {:ok, socket, _imported} -> {:noreply, socket}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:claude_response, session_ref, response}, socket) do
    Logger.info(
      "Claude response received ref=#{inspect(session_ref)} type=#{inspect(response["type"])}"
    )

    # Claude responded - stop processing state
    socket =
      socket
      |> assign(:processing, false)
      |> load_tab_data("messages", socket.assigns.session_id)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:new_message, _message}, socket) do
    # New message received - reload messages
    socket =
      socket
      |> load_tab_data("messages", socket.assigns.session_id)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:claude_complete, session_ref, exit_code}, socket) do
    Logger.info("Claude session completed ref=#{inspect(session_ref)} exit=#{exit_code}")

    # Claude session completed - stop processing state
    socket =
      socket
      |> assign(:processing, false)
      |> assign(:session_ref, nil)
      |> load_tab_data("messages", socket.assigns.session_id)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:agent_working, _session_uuid, session_id}, socket) do
    if session_id == socket.assigns.session_id do
      {:noreply, assign(socket, :processing, true)}
    else
      {:noreply, socket}
    end
  end

  # NATS handler broadcasts {agent_working, %Agent{}} — match by agent struct
  @impl true
  def handle_info({:agent_working, %{id: id}}, socket) do
    if id == socket.assigns.session_id do
      {:noreply, assign(socket, :processing, true)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:agent_stopped, _session_uuid, session_id}, socket) do
    if session_id == socket.assigns.session_id do
      {:noreply, assign(socket, :processing, false)}
    else
      {:noreply, socket}
    end
  end

  # NATS handler broadcasts {agent_stopped, %Agent{}}
  @impl true
  def handle_info({:agent_stopped, %{id: id}}, socket) do
    if id == socket.assigns.session_id do
      {:noreply, assign(socket, :processing, false)}
    else
      {:noreply, socket}
    end
  end

  # DM received via MCP i-dm tool
  @impl true
  def handle_info({:new_dm, _msg}, socket) do
    {:noreply, load_tab_data(socket, "messages", socket.assigns.session_id)}
  end

  # NATS handler broadcasts tool events on "session:#{agent.id}"
  @impl true
  def handle_info({:tool_use, tool_name, _params}, socket) do
    {:noreply, assign(socket, :stream_tool, tool_name)}
  end

  @impl true
  def handle_info({:tool_result, _tool_name, _is_error}, socket) do
    # Tool finished — reload messages to show the new tool messages
    socket =
      socket
      |> assign(:stream_tool, nil)
      |> load_tab_data("messages", socket.assigns.session_id)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:stream_delta, :text, text}, socket) do
    new_content = socket.assigns.stream_content <> text
    Logger.info("[DmLive] stream_delta text, total_len=#{String.length(new_content)}, show=#{socket.assigns.show_live_stream}")
    {:noreply, assign(socket, :stream_content, new_content)}
  end

  @impl true
  def handle_info({:stream_replace, :text, text}, socket) do
    Logger.info("[DmLive] stream_replace text, len=#{String.length(text)}, show=#{socket.assigns.show_live_stream}")
    {:noreply, assign(socket, :stream_content, text)}
  end

  @impl true
  def handle_info({:stream_delta, :tool_use, name}, socket) do
    Logger.info("[DmLive] stream_delta tool_use=#{name}, show=#{socket.assigns.show_live_stream}")
    {:noreply, assign(socket, :stream_tool, name)}
  end

  @impl true
  def handle_info({:stream_delta, :thinking, _}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info(:stream_clear, socket) do
    Logger.info("[DmLive] stream_clear")
    socket =
      socket
      |> assign(:stream_content, "")
      |> assign(:stream_tool, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_info(msg, socket) do
    Logger.debug("Unhandled message in DM LiveView: #{inspect(msg)}")
    {:noreply, socket}
  end

  defp load_tab_data(socket, tab, session_id) do
    Logger.info("Loading DM tab data tab=#{tab} session_id=#{session_id}")
    {messages, has_more} = load_message_data(socket, tab, session_id)

    socket
    |> assign(:messages, messages)
    |> assign(:has_more_messages, has_more)
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
      :logs,
      maybe_load_tab_data(tab, "logs", socket.assigns[:logs], fn ->
        Logs.list_logs_for_session(session_id)
      end)
    )
    |> assign(
      :notes,
      maybe_load_tab_data(tab, "notes", socket.assigns[:notes], fn ->
        Notes.list_notes_for_session(session_id)
      end)
    )
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

  defp sync_messages_from_session_file(socket) do
    session_id = socket.assigns.session_id
    session_uuid = socket.assigns.session_uuid

    with {:ok, project_path} <-
           resolve_project_path(socket.assigns.agent, socket.assigns.chat_agent),
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

  defp session_message_roles("user"), do: {"user", "agent", "outbound"}
  defp session_message_roles(_role), do: {"agent", "user", "inbound"}

  defp parse_session_timestamp(timestamp, fallback) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _offset} -> DateTime.truncate(dt, :second)
      _ -> fallback
    end
  end

  defp parse_session_timestamp(_timestamp, fallback), do: fallback

  defp consume_uploaded_files(socket) do
    consume_uploaded_entries(socket, :files, fn %{path: temp_path}, entry ->
      destination = upload_destination(entry.client_name)

      File.mkdir_p!(Path.dirname(destination))
      File.cp!(temp_path, destination)

      {:ok,
       %{
         storage_path: destination,
         original_filename: entry.client_name,
         content_type: entry.client_type,
         size_bytes: entry.client_size
       }}
    end)
  end

  defp upload_destination(client_name) do
    base_upload_dir = Path.join([System.user_home!(), ".config", "eye-in-the-sky", "uploads"])
    date_dir = Date.utc_today() |> Date.to_string()
    filename = "#{Ecto.UUID.generate()}#{Path.extname(client_name)}"

    Path.join([base_upload_dir, date_dir, filename])
  end

  defp build_message_body(body, []), do: body

  defp build_message_body(body, uploaded_files) do
    file_list =
      uploaded_files
      |> Enum.map(fn file_data ->
        "- #{file_data.storage_path} (#{file_data.original_filename})"
      end)
      |> Enum.join("\n")

    "#{body}\n\nAttached files:\n#{file_list}"
  end

  defp create_user_message(session_id, body) do
    Messages.send_message(%{
      session_id: session_id,
      sender_role: "user",
      recipient_role: "agent",
      provider: "claude",
      body: body
    })
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

  defp continue_session_opts(model, effort_level) do
    opts = [model: model]

    if is_binary(effort_level) and effort_level != "" do
      opts ++ [effort_level: effort_level]
    else
      opts
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <DmPage.dm_page
      agent={@agent}
      session_uuid={@session_uuid}
      active_tab={@active_tab}
      messages={@messages}
      has_more_messages={@has_more_messages}
      uploads={@uploads}
      selected_model={@selected_model}
      selected_effort={@selected_effort}
      show_model_menu={@show_model_menu}
      processing={@processing}
      show_live_stream={@show_live_stream}
      stream_content={@stream_content}
      stream_tool={@stream_tool}
      tasks={@tasks}
      commits={@commits}
      logs={@logs}
      notes={@notes}
    />
    """
  end

  defp resolve_project_path(agent, chat_agent) do
    cond do
      agent.git_worktree_path ->
        {:ok, agent.git_worktree_path}

      chat_agent.git_worktree_path ->
        {:ok, chat_agent.git_worktree_path}

      chat_agent.project && chat_agent.project.path ->
        {:ok, chat_agent.project.path}

      true ->
        {:error, :no_project_path}
    end
  end
end
