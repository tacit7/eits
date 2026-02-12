defmodule EyeInTheSkyWebWeb.DmLive do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.{Sessions, Messages, Tasks, Commits, Logs, Agents, Notes}
  alias EyeInTheSkyWeb.Claude.AgentManager

  @impl true
  def mount(%{"session_id" => session_id_param}, _session, socket) do
    # Accept both integer ID and UUID in URL
    session = case Integer.parse(session_id_param) do
      {id, ""} -> Sessions.get_session!(id)
      _ -> Sessions.get_session_by_uuid!(session_id_param)
    end

    agent = Agents.get_agent!(session.agent_id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "session:#{session.id}")
      Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "agent:working")
      send(self(), :sync_from_session_file)
    end

    socket =
      socket
      |> assign(:page_title, session.name || "Session")
      |> assign(:session_id, session.id)
      |> assign(:session_uuid, session.uuid)
      |> assign(:agent_id, session.agent_id)
      |> assign(:agent, agent)
      |> assign(:session, session)
      |> assign(:active_tab, "messages")
      |> assign(:session_ref, nil)
      |> assign(:processing, false)
      |> assign(:message_limit, 20)
      |> assign(:has_more_messages, false)
      |> allow_upload(:files,
        accept: ~w(.jpg .jpeg .png .gif .pdf .txt .md .csv .json .xml .html),
        max_entries: 10,
        max_file_size: 50_000_000,
        auto_upload: true
      )
      |> load_tab_data("messages", session.id)

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
  def handle_event("send_message", %{"body" => body}, socket) when body != "" do
    require Logger
    Logger.info("📤 DM send_message event received, body: #{body}")

    # Consume uploaded files and save to disk
    uploaded_files = consume_uploaded_entries(socket, :files, fn %{path: temp_path}, entry ->
      upload_dir = "#{System.user_home!()}/.config/eye-in-the-sky/uploads"
      date_dir = Date.utc_today() |> to_string()
      filename = "#{Ecto.UUID.generate()}#{Path.extname(entry.client_name)}"
      dest = Path.join([upload_dir, date_dir, filename])

      File.mkdir_p!(Path.dirname(dest))
      File.cp!(temp_path, dest)

      {:ok, %{
        storage_path: dest,
        original_filename: entry.client_name,
        content_type: entry.client_type,
        size_bytes: entry.client_size
      }}
    end)

    # Build message body with file paths appended
    full_body = if uploaded_files != [] do
      file_list = Enum.map(uploaded_files, fn f ->
        "- #{f.storage_path} (#{f.original_filename})"
      end) |> Enum.join("\n")

      "#{body}\n\nAttached files:\n#{file_list}"
    else
      body
    end

    # Create message in database
    case Messages.send_message(%{
      session_id: socket.assigns.session_id,
      sender_role: "user",
      recipient_role: "agent",
      provider: "claude",
      body: full_body
    }) do
      {:ok, message} ->
        Logger.info("✅ Message created in DB with ID: #{message.id}")

        # Create file attachment records
        Enum.each(uploaded_files, fn file_data ->
          EyeInTheSkyWeb.FileAttachments.create_attachment(Map.put(file_data, :message_id, message.id))
        end)

        # Load messages to show the one we just sent
        socket = load_tab_data(socket, "messages", socket.assigns.session_id)

        Logger.info("🔍 After load_tab_data, socket.assigns[:messages] = #{length(socket.assigns[:messages] || [])}")

        # Send to AgentWorker (queues if busy, processes if idle)
        # Processing flag will be set when agent_working message arrives
        session_id = socket.assigns.session_id
        case AgentManager.send_message(session_id, full_body, model: "sonnet") do
          :ok ->
            Logger.info("✅ Message sent to agent worker for processing")
            {:noreply, socket}

          {:error, reason} ->
            Logger.error("❌ Failed to send to agent: #{inspect(reason)}")
            socket =
              socket
              |> assign(:processing, false)
              |> put_flash(:error, "Failed to send to agent: #{inspect(reason)}")

            {:noreply, socket}
        end

      {:error, reason} ->
        Logger.error("❌ Failed to create message in DB: #{inspect(reason)}")
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
  def handle_event("sync_from_session_file", _params, socket) do
    alias EyeInTheSkyWeb.Claude.SessionReader

    session = socket.assigns.session
    agent = socket.assigns.agent
    session_id = socket.assigns.session_id
    session_uuid = socket.assigns.session_uuid

    case resolve_project_path(session, agent) do
      {:ok, project_path} ->
        # Use last source_uuid as cursor to only read new messages
        last_uuid = Messages.get_last_source_uuid(session_id)

        case SessionReader.read_messages_after_uuid(session_uuid, project_path, last_uuid) do
          {:ok, raw_messages} ->
            formatted = SessionReader.format_messages(raw_messages)
            now = DateTime.utc_now() |> DateTime.truncate(:second)

            imported =
              formatted
              |> Enum.filter(fn msg -> msg.uuid end)
              |> Enum.map(fn msg ->
                {sender_role, recipient_role, direction} =
                  case msg.role do
                    "user" -> {"user", "agent", "outbound"}
                    _ -> {"agent", "user", "inbound"}
                  end

                inserted_at =
                  case DateTime.from_iso8601(msg.timestamp) do
                    {:ok, dt, _} -> DateTime.truncate(dt, :second)
                    _ -> now
                  end

                Messages.create_message(%{
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
                })
              end)
              |> Enum.count(fn
                {:ok, _} -> true
                _ -> false
              end)

            socket =
              socket
              |> load_tab_data("messages", session_id)
              |> put_flash(:info, "Synced #{imported} new messages from session file")

            {:noreply, socket}

          {:error, :not_found} ->
            {:noreply, put_flash(socket, :error, "No session file found for this session")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to read session file: #{inspect(reason)}")}
        end

      {:error, :no_project_path} ->
        {:noreply, put_flash(socket, :error, "No project path configured")}
    end
  end

  @impl true
  def handle_event("load_more_messages", _params, socket) do
    new_limit = (socket.assigns[:message_limit] || 20) + 20

    socket =
      socket
      |> assign(:message_limit, new_limit)
      |> load_tab_data("messages", socket.assigns.session_id)

    {:noreply, socket}
  end

  @impl true
  def handle_event("kill_session", _params, socket) do
    if socket.assigns.session_ref do
      EyeInTheSkyWeb.Claude.SessionManager.cancel_session(socket.assigns.session_ref)
      {:noreply, socket |> assign(:processing, false) |> assign(:session_ref, nil)}
    else
      {:noreply, socket}
    end
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
    alias EyeInTheSkyWeb.Claude.SessionReader

    session = socket.assigns.session
    agent = socket.assigns.agent
    session_id = socket.assigns.session_id
    session_uuid = socket.assigns.session_uuid

    with {:ok, project_path} <- resolve_project_path(session, agent),
         last_uuid = Messages.get_last_source_uuid(session_id),
         {:ok, raw_messages} <- SessionReader.read_messages_after_uuid(session_uuid, project_path, last_uuid) do
      formatted = SessionReader.format_messages(raw_messages)
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      formatted
      |> Enum.filter(fn msg -> msg.uuid end)
      |> Enum.each(fn msg ->
        {sender_role, recipient_role, direction} =
          case msg.role do
            "user" -> {"user", "agent", "outbound"}
            _ -> {"agent", "user", "inbound"}
          end

        inserted_at =
          case DateTime.from_iso8601(msg.timestamp) do
            {:ok, dt, _} -> DateTime.truncate(dt, :second)
            _ -> now
          end

        Messages.create_message(%{
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
        })
      end)

      {:noreply, load_tab_data(socket, "messages", session_id)}
    else
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:claude_response, session_ref, response}, socket) do
    require Logger
    Logger.info("🤖 Claude response received - ref: #{inspect(session_ref)}, type: #{inspect(response["type"])}")

    # Claude responded - stop processing state
    socket = socket
    |> assign(:processing, false)
    |> load_tab_data("messages", socket.assigns.session_id)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:new_message, _message}, socket) do
    # New message received - reload messages
    socket = socket
    |> load_tab_data("messages", socket.assigns.session_id)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:nats_message_for_agent, _message_text}, socket) do
    # NATS message received - DISABLED FOR NOW to avoid duplicate messages
    # TODO: Re-enable when deduplication is implemented
    require Logger
    Logger.debug("🔇 NATS message ignored (NATS processing disabled)")
    {:noreply, socket}
  end

  # NATS processing code kept below for reference:
  # def handle_info({:nats_message_for_agent, message_text}, socket) do
  #   # NATS message received - automatically forward to Claude agent
  #   require Logger
  #   session_id = socket.assigns.session_id
  #   session = socket.assigns.session
  #   agent = socket.assigns.agent
  #
  #   Logger.info("Auto-forwarding NATS message to Claude agent for session #{session_id}")
  #
  #   session_uuid = socket.assigns.session_uuid
  #
  #   case resolve_project_path(session, agent) do
  #     {:ok, project_path} ->
  #       has_messages = Messages.count_messages_for_session(session_id) > 1
  #
  #       result =
  #         if has_messages do
  #           EyeInTheSkyWeb.Claude.SessionManager.resume_session(session_uuid, message_text,
  #             model: "sonnet",
  #             project_path: project_path
  #           )
  #         else
  #           EyeInTheSkyWeb.Claude.SessionManager.start_session(session_uuid, message_text,
  #             model: "sonnet",
  #             project_path: project_path
  #           )
  #         end
  #
  #       case result do
  #         {:ok, session_ref} ->
  #           socket =
  #             socket
  #             |> assign(:session_ref, session_ref)
  #             |> assign(:processing, true)
  #             |> load_tab_data("messages", socket.assigns.session_id)
  #
  #           {:noreply, socket}
  #
  #         {:error, reason} ->
  #           Logger.error("Failed to forward NATS message to Claude: #{inspect(reason)}")
  #           {:noreply, socket}
  #       end
  #
  #     {:error, :no_project_path} ->
  #       Logger.error("Cannot forward NATS message: no project path configured")
  #       {:noreply, socket}
  #   end
  # end

  @impl true
  def handle_info({:claude_complete, session_ref, exit_code}, socket) do
    require Logger
    Logger.info("🏁 Claude session completed - ref: #{inspect(session_ref)}, exit: #{exit_code}")

    # Claude session completed - stop processing state
    socket = socket
    |> assign(:processing, false)
    |> assign(:session_ref, nil)
    |> load_tab_data("messages", socket.assigns.session_id)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:agent_working, _session_uuid, session_id}, socket) do
    # Agent started processing - set flag only if this is our session
    if session_id == socket.assigns.session_id do
      {:noreply, assign(socket, :processing, true)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:agent_stopped, _session_uuid, session_id}, socket) do
    # Agent finished processing - clear flag only if this is our session
    if session_id == socket.assigns.session_id do
      {:noreply, assign(socket, :processing, false)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(msg, socket) do
    require Logger
    Logger.debug("📬 Unhandled message in DM LiveView: #{inspect(msg)}")
    {:noreply, socket}
  end

  defp load_tab_data(socket, tab, session_id) do
    require Logger
    Logger.info("📋 load_tab_data called: tab=#{tab}, session_id=#{session_id}")

    {messages, has_more} = if tab == "messages" do
      limit = socket.assigns[:message_limit] || 20
      # Fetch one extra to detect if more exist
      fetched =
        Messages.list_recent_messages(session_id, limit + 1)
        |> EyeInTheSkyWeb.Repo.preload(:attachments)

      Logger.info("📋 Fetched #{length(fetched)} messages for session #{session_id}")

      if length(fetched) > limit do
        {Enum.drop(fetched, 1), true}
      else
        {fetched, false}
      end
    else
      {socket.assigns[:messages] || [], socket.assigns[:has_more_messages] || false}
    end

    socket
    |> assign(:messages, messages)
    |> assign(:has_more_messages, has_more)
    |> assign(:tasks, if(tab == "tasks", do: Tasks.list_tasks_for_session(session_id), else: socket.assigns[:tasks] || []))
    |> assign(:commits, if(tab == "commits", do: Commits.list_commits_for_session(session_id), else: socket.assigns[:commits] || []))
    |> assign(:logs, if(tab == "logs", do: Logs.list_logs_for_session(session_id), else: socket.assigns[:logs] || []))
    |> assign(:notes, if(tab == "notes", do: Notes.list_notes_for_session(session_id), else: socket.assigns[:notes] || []))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto">
      <div class="border-b border-base-content/10 mb-6">
        <div class="px-4 py-4">
          <h1 class="text-2xl font-bold"><%= @session.name || "Session" %></h1>
          <p class="text-sm text-base-content/60">Session ID: <%= @session_uuid %></p>
        </div>

        <nav class="flex gap-6 px-4 -mb-px">
          <button
            class={"px-1 py-2 border-b-2 text-sm font-medium transition-colors #{if @active_tab == "messages", do: "border-primary text-primary", else: "border-transparent text-base-content/60 hover:text-base-content hover:border-base-content/30"}"}
            phx-click="change_tab"
            phx-value-tab="messages"
          >
            Messages
          </button>
          <button
            class={"px-1 py-2 border-b-2 text-sm font-medium transition-colors #{if @active_tab == "tasks", do: "border-primary text-primary", else: "border-transparent text-base-content/60 hover:text-base-content hover:border-base-content/30"}"}
            phx-click="change_tab"
            phx-value-tab="tasks"
          >
            Tasks
          </button>
          <button
            class={"px-1 py-2 border-b-2 text-sm font-medium transition-colors #{if @active_tab == "commits", do: "border-primary text-primary", else: "border-transparent text-base-content/60 hover:text-base-content hover:border-base-content/30"}"}
            phx-click="change_tab"
            phx-value-tab="commits"
          >
            Commits
          </button>
          <button
            class={"px-1 py-2 border-b-2 text-sm font-medium transition-colors #{if @active_tab == "logs", do: "border-primary text-primary", else: "border-transparent text-base-content/60 hover:text-base-content hover:border-base-content/30"}"}
            phx-click="change_tab"
            phx-value-tab="logs"
          >
            Logs
          </button>
          <button
            class={"px-1 py-2 border-b-2 text-sm font-medium transition-colors #{if @active_tab == "notes", do: "border-primary text-primary", else: "border-transparent text-base-content/60 hover:text-base-content hover:border-base-content/30"}"}
            phx-click="change_tab"
            phx-value-tab="notes"
          >
            Notes
          </button>
        </nav>
      </div>

      <div class="px-4 py-6">
        <!-- DEBUG: active_tab = <%= @active_tab %> -->
        <div style="background: red; color: white; padding: 10px; margin-bottom: 10px;">
          DEBUG: Messages length = <%= length(@messages) %>, active_tab = <%= @active_tab %>
        </div>
        <%= case @active_tab do %>
          <% "messages" -> %>
            <!-- DEBUG: rendering messages tab, @messages length = <%= length(@messages) %>, @has_more_messages = <%= @has_more_messages %> -->
            <div class="flex flex-col h-[calc(100vh-16rem)]">
              <div class="flex items-center justify-between mb-2">
                <span class="text-xs text-base-content/40"><%= length(@messages) %> messages</span>
                <button
                  phx-click="sync_from_session_file"
                  class="btn btn-xs btn-ghost gap-1 text-base-content/60 hover:text-primary"
                >
                  <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
                      d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
                  </svg>
                  Sync
                </button>
              </div>
              <div class="flex-1 overflow-y-auto space-y-4 mb-4" id="messages-container" phx-hook="ScrollToBottom" style="scrollbar-width: none; -ms-overflow-style: none;">
                <%= if @messages == [] do %>
                  <div class="text-center text-base-content/60 py-8">
                    <p>No messages yet</p>
                    <p class="text-xs mt-2">Send a message to start the conversation</p>
                  </div>
                <% else %>
                  <%= if @has_more_messages do %>
                    <div class="text-center py-2">
                      <button
                        phx-click="load_more_messages"
                        class="btn btn-xs btn-ghost text-base-content/50 hover:text-primary"
                      >
                        Load older messages
                      </button>
                    </div>
                  <% end %>
                  <%= for message <- @messages do %>
                    <div class="group hover:bg-base-300/30 px-2 py-1.5 -mx-2 rounded">
                      <div class="flex gap-3">
                        <div class="flex-shrink-0">
                          <div class="w-10 h-10 rounded-full bg-primary/20 flex items-center justify-center text-primary font-bold text-sm">
                            <%= if message.sender_role == "user", do: "U", else: String.first(message.provider || "A") |> String.upcase() %>
                          </div>
                        </div>
                        <div class="flex-1 min-w-0">
                          <div class="flex items-baseline gap-2">
                            <span class={"font-semibold text-sm #{if message.sender_role == "user", do: "text-primary", else: "text-accent"}"}>
                              <%= if message.sender_role == "user", do: "You", else: message.provider || "Agent" %>
                            </span>
                            <span class="text-xs text-base-content/40">
                              <%= format_time(message.inserted_at) %>
                            </span>
                          </div>
                          <div id={"msg-body-#{message.id}"} class="dm-markdown text-sm text-base-content mt-0.5 leading-relaxed" phx-hook="MarkdownMessage" data-raw-body={message.body}></div>

                          <%= if message.sender_role == "agent" && message.metadata && message.metadata["total_cost_usd"] do %>
                            <div class="text-xs text-base-content/60 mt-2 flex gap-3 flex-wrap">
                              <%= if message.metadata["total_cost_usd"] do %>
                                <span title="Total cost">$<%= :erlang.float_to_binary(message.metadata["total_cost_usd"], decimals: 4) %></span>
                              <% end %>
                              <%= if message.metadata["usage"] && message.metadata["usage"]["input_tokens"] do %>
                                <span title="Input tokens"><%= message.metadata["usage"]["input_tokens"] %> in</span>
                              <% end %>
                              <%= if message.metadata["usage"] && message.metadata["usage"]["output_tokens"] do %>
                                <span title="Output tokens"><%= message.metadata["usage"]["output_tokens"] %> out</span>
                              <% end %>
                              <%= if message.metadata["duration_ms"] do %>
                                <span title="Duration"><%= :erlang.float_to_binary(message.metadata["duration_ms"] / 1000, decimals: 1) %>s</span>
                              <% end %>
                              <%= if message.metadata["num_turns"] do %>
                                <span title="Number of turns"><%= message.metadata["num_turns"] %> turns</span>
                              <% end %>
                            </div>
                          <% end %>

                          <%= if message.attachments && length(message.attachments) > 0 do %>
                            <div class="mt-2 space-y-1">
                              <%= for attachment <- message.attachments do %>
                                <div class="flex items-center gap-2 bg-base-200/50 rounded px-3 py-1.5 text-xs font-mono">
                                  <svg class="w-3 h-3 text-base-content/40" fill="currentColor" viewBox="0 0 20 20">
                                    <path d="M8 4a3 3 0 00-3 3v4a5 5 0 0010 0V7a1 1 0 112 0v4a7 7 0 11-14 0V7a5 5 0 0110 0v4a3 3 0 11-6 0V7a1 1 0 012 0v4a1 1 0 102 0V7a3 3 0 00-3-3z"/>
                                  </svg>
                                  <span class="text-base-content/70"><%= attachment.original_filename %></span>
                                  <span class="text-base-content/40 ml-auto"><%= attachment.storage_path %></span>
                                </div>
                              <% end %>
                            </div>
                          <% end %>
                        </div>
                      </div>
                    </div>
                  <% end %>
                <% end %>
              </div>

              <form phx-submit="send_message" class="border-t border-base-content/10 pt-4" phx-change="validate_upload" id="message-form">
                <%= if @uploads.files.entries != [] do %>
                  <div class="mb-2 flex flex-wrap gap-2">
                    <%= for entry <- @uploads.files.entries do %>
                      <div class="flex items-center gap-2 bg-base-200 rounded px-3 py-2">
                        <span class="text-sm"><%= entry.client_name %></span>
                        <span class="text-xs text-base-content/50"><%= format_size(entry.client_size) %></span>
                        <button type="button" phx-click="cancel_upload" phx-value-ref={entry.ref} class="btn btn-ghost btn-xs">×</button>
                      </div>
                    <% end %>
                  </div>
                <% end %>

                <div class="flex gap-2">
                  <div class="flex-1 relative">
                    <input
                      type="text"
                      name="body"
                      placeholder="Type a message..."
                      class="input input-bordered w-full focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/20"
                      autocomplete="off"
                      phx-hook="CommandHistory"
                      id="message-input"
                    />
                    <label for={@uploads.files.ref} phx-drop-target={@uploads.files.ref} class="absolute right-2 top-1/2 -translate-y-1/2 cursor-pointer">
                      <svg class="w-5 h-5 text-base-content/40 hover:text-base-content" fill="currentColor" viewBox="0 0 20 20">
                        <path d="M8 4a3 3 0 00-3 3v4a5 5 0 0010 0V7a1 1 0 112 0v4a7 7 0 11-14 0V7a5 5 0 0110 0v4a3 3 0 11-6 0V7a1 1 0 012 0v4a1 1 0 102 0V7a3 3 0 00-3-3z"/>
                      </svg>
                    </label>
                    <.live_file_input upload={@uploads.files} class="hidden" />
                  </div>
                  <%= if @processing do %>
                    <button type="button" phx-click="kill_session" class="btn btn-error gap-2">
                      <span class="loading loading-spinner loading-sm"></span>
                      Stop
                    </button>
                  <% else %>
                    <button type="submit" class="btn btn-primary" phx-disable-with="Sending...">Send</button>
                  <% end %>
                </div>
              </form>
            </div>

          <% "tasks" -> %>
            <div>
              <%= if @tasks == [] do %>
                <div class="text-center py-12">
                  <.icon name="hero-clipboard-document-list" class="mx-auto h-12 w-12 text-base-content/40" />
                  <h3 class="mt-2 text-sm font-medium text-base-content">No tasks yet</h3>
                  <p class="mt-1 text-sm text-base-content/60">
                    Tasks from this session will appear here
                  </p>
                </div>
              <% else %>
                <div class="join join-vertical w-full">
                  <%= for task <- @tasks do %>
                    <div class="collapse collapse-arrow join-item border border-base-300">
                      <input type="checkbox" />
                      <div class="collapse-title bg-base-100 hover:bg-base-100/80 transition-colors">
                        <div class="flex items-center gap-3">
                          <.icon name="hero-clipboard-document-list" class="w-4 h-4 text-base-content/60 flex-shrink-0" />
                          <div class="flex flex-col gap-1">
                            <h3 class="font-semibold text-sm text-base-content"><%= task.title %></h3>
                            <div class="flex items-center gap-2 text-xs text-base-content/60">
                              <span class="font-mono"><%= String.slice(task.uuid || to_string(task.id), 0..7) %></span>
                              <%= if task.state do %>
                                <span>•</span>
                                <span class="badge badge-sm"><%= task.state.name %></span>
                              <% end %>
                            </div>
                          </div>
                        </div>
                      </div>
                      <div class="collapse-content bg-base-50">
                        <div class="text-sm text-base-content whitespace-pre-wrap"><%= task.description || "No description" %></div>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>

          <% "commits" -> %>
            <div>
              <%= if @commits == [] do %>
                <div class="text-center py-12">
                  <.icon name="hero-code-bracket" class="mx-auto h-12 w-12 text-base-content/40" />
                  <h3 class="mt-2 text-sm font-medium text-base-content">No commits yet</h3>
                  <p class="mt-1 text-sm text-base-content/60">
                    Commits from this session will appear here
                  </p>
                </div>
              <% else %>
                <div class="join join-vertical w-full">
                  <%= for commit <- @commits do %>
                    <div class="collapse collapse-arrow join-item border border-base-300">
                      <input type="checkbox" />
                      <div class="collapse-title bg-base-100 hover:bg-base-100/80 transition-colors">
                        <div class="flex items-center gap-3">
                          <.icon name="hero-code-bracket" class="w-4 h-4 text-base-content/60 flex-shrink-0" />
                          <div class="flex flex-col gap-1">
                            <h3 class="font-semibold text-sm text-base-content"><%= extract_commit_title(commit.commit_message) %></h3>
                            <div class="flex items-center gap-2 text-xs text-base-content/60">
                              <span class="font-mono"><%= String.slice(commit.commit_hash || "", 0..7) %></span>
                              <span>•</span>
                              <span><%= format_note_timestamp(commit.created_at) %></span>
                            </div>
                          </div>
                        </div>
                      </div>
                      <div class="collapse-content bg-base-50">
                        <pre class="text-sm text-base-content whitespace-pre-wrap font-mono"><%= commit.commit_message %></pre>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>

          <% "logs" -> %>
            <div>
              <%= if @logs == [] do %>
                <p class="text-center text-base-content/60">No logs</p>
              <% else %>
                <%= for log <- @logs do %>
                  <div class="mb-2 p-2 bg-base-100 rounded">
                    <div class="text-sm"><%= log.message %></div>
                  </div>
                <% end %>
              <% end %>
            </div>

          <% "notes" -> %>
            <div>
              <%= if @notes == [] do %>
                <div class="text-center py-12">
                  <.icon name="hero-document-text" class="mx-auto h-12 w-12 text-base-content/40" />
                  <h3 class="mt-2 text-sm font-medium text-base-content">No notes yet</h3>
                  <p class="mt-1 text-sm text-base-content/60">
                    Notes from this session will appear here
                  </p>
                </div>
              <% else %>
                <div class="join join-vertical w-full">
                  <%= for note <- @notes do %>
                    <div class="collapse collapse-arrow join-item border border-base-300">
                      <input type="checkbox" />
                      <div class="collapse-title bg-base-100 hover:bg-base-100/80 transition-colors">
                        <div class="flex items-center justify-between">
                          <label class="flex items-center gap-3 flex-1 cursor-pointer">
                            <.icon name="hero-document-text" class="w-4 h-4 text-base-content/60 flex-shrink-0" />
                            <div class="flex flex-col gap-1">
                              <h3 class="font-semibold text-sm text-base-content">
                                <%= note.title || extract_title(note.body) %>
                              </h3>
                              <div class="flex items-center gap-2 text-xs text-base-content/60">
                                <span class="font-mono"><%= String.slice(note.uuid || to_string(note.id), 0..7) %></span>
                                <button
                                  type="button"
                                  class="cursor-pointer hover:text-primary transition-colors z-10"
                                  phx-hook="CopyToClipboard"
                                  id={"copy-note-#{note.id}"}
                                  data-copy={note.uuid || to_string(note.id)}
                                  onclick="event.stopPropagation(); event.preventDefault();"
                                >
                                  <.icon name="hero-clipboard-document" class="w-3.5 h-3.5" />
                                </button>
                                <span>•</span>
                                <span><%= format_note_timestamp(note.created_at) %></span>
                              </div>
                            </div>
                          </label>
                          <button
                            type="button"
                            class="star-icon cursor-pointer transition-all z-10 p-1 rounded hover:scale-110 hover:bg-black/5"
                            phx-click={JS.push("toggle_star", value: %{note_id: note.id})}
                          >
                            <.icon
                              name={if note.starred == 1, do: "hero-star-solid", else: "hero-star"}
                              class={"w-5 h-5 #{if note.starred == 1, do: "text-warning", else: "text-base-content/40"}"}
                            />
                          </button>
                        </div>
                      </div>
                      <div class="collapse-content bg-base-50">
                        <div
                          id={"note-body-#{note.id}"}
                          class="dm-markdown text-sm text-base-content leading-relaxed"
                          phx-hook="MarkdownMessage"
                          data-raw-body={note.body}
                        ></div>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp format_time(nil), do: ""
  defp format_time(timestamp) when is_binary(timestamp) do
    # Parse and format timestamp to Discord-style (Today at 12:34 PM)
    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _} ->
        now = DateTime.utc_now()
        time_str = Calendar.strftime(dt, "%I:%M %p")

        cond do
          DateTime.to_date(dt) == DateTime.to_date(now) ->
            "Today at #{time_str}"

          Date.diff(DateTime.to_date(now), DateTime.to_date(dt)) == 1 ->
            "Yesterday at #{time_str}"

          true ->
            Calendar.strftime(dt, "%m/%d/%Y %I:%M %p")
        end

      _ ->
        timestamp
    end
  end
  defp format_time(_), do: ""

  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_size(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp format_note_timestamp(nil), do: ""
  defp format_note_timestamp(timestamp) when is_binary(timestamp), do: timestamp
  defp format_note_timestamp(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  defp format_note_timestamp(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  defp format_note_timestamp(_), do: ""

  defp extract_title(nil), do: "Untitled"
  defp extract_title(body) when is_binary(body) do
    body
    |> String.trim()
    |> String.split("\n")
    |> List.first()
    |> String.replace(~r/^#+\s*/, "")  # Remove markdown headers
    |> String.slice(0..50)
    |> then(fn text ->
      if String.length(text) >= 50, do: text <> "...", else: text
    end)
  end

  defp extract_commit_title(nil), do: "No message"
  defp extract_commit_title(message) when is_binary(message) do
    message
    |> String.trim()
    |> String.split("\n")
    |> List.first()
    |> String.slice(0..60)
    |> then(fn text ->
      if String.length(text) >= 60, do: text <> "...", else: text
    end)
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
