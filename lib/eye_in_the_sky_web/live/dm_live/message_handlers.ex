defmodule EyeInTheSkyWeb.DmLive.MessageHandlers do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [connected?: 1, put_flash: 3, push_event: 3]

  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSky.Claude.SessionImporter
  alias EyeInTheSky.Codex.SessionImporter, as: CodexImporter
  alias EyeInTheSky.Codex.SessionReader, as: CodexReader
  alias EyeInTheSky.Messages
  alias EyeInTheSkyWeb.DmLive.TabHelpers
  alias EyeInTheSkyWeb.DmLive.UploadHelpers
  alias EyeInTheSkyWeb.Live.Shared.SessionHelpers

  require Logger

  @reload_debounce_ms 300

  def handle_send_message(body, socket) do
    model = socket.assigns.selected_model
    effort_level = socket.assigns.selected_effort
    thinking_enabled = socket.assigns.thinking_enabled
    max_budget_usd = socket.assigns.max_budget_usd
    extra_cli_opts = socket.assigns[:session_cli_opts] || []

    Logger.info(
      "DM send_message received for session=#{socket.assigns.session_id} model=#{model} effort=#{effort_level} body_length=#{String.length(body)}"
    )

    uploaded_files = UploadHelpers.consume_uploaded_files(socket)
    full_body = UploadHelpers.build_message_body(body, uploaded_files)
    session_id = socket.assigns.session_id
    provider = socket.assigns.session.provider

    case create_user_message(session_id, full_body, provider) do
      {:ok, message} ->
        Logger.info("Message created in DB with id=#{message.id}")

        socket = TabHelpers.force_reload_messages(socket, session_id)

        base_opts =
          SessionHelpers.continue_session_opts(
            model,
            effort_level,
            thinking_enabled,
            max_budget_usd
          )

        cli_opts = Keyword.merge(base_opts, extra_cli_opts) ++ [message_id: message.id]

        case AgentManager.continue_session(session_id, full_body, cli_opts) do
          {:ok, _admission} ->
            Logger.info("Message forwarded to AgentManager for session=#{session_id}")
            UploadHelpers.persist_upload_attachments(uploaded_files, message.id)

            {:noreply,
             socket
             |> assign(:processing, true)
             |> push_event("clear-input", %{})}

          {:error, :queue_full} ->
            Logger.warning(
              "Queue full for session=#{session_id}, deleting orphaned message id=#{message.id}"
            )

            cleanup_rejected_message(message, uploaded_files)

            {:noreply,
             socket
             |> TabHelpers.force_reload_messages(session_id)
             |> assign(:processing, false)
             |> put_flash(:error, "Queue is full — max 5 messages pending")}

          {:error, reason} ->
            Logger.error("Failed to send message via AgentManager: #{inspect(reason)}")
            cleanup_rejected_message(message, uploaded_files)

            {:noreply,
             socket
             |> TabHelpers.force_reload_messages(session_id)
             |> assign(:processing, false)
             |> put_flash(:error, "Failed to send message: #{inspect(reason)}")}
        end

      {:error, reason} ->
        Logger.error("Failed to create message: #{inspect(reason)}")
        cleanup_uploaded_files(uploaded_files)
        {:noreply, put_flash(socket, :error, "Failed to create message: #{inspect(reason)}")}
    end
  end

  def sync_messages_from_session_file(socket) do
    case socket.assigns.session.provider do
      "codex" -> sync_codex_session_file(socket)
      "gemini" -> {:ok, socket, 0}
      _ -> sync_claude_session_file(socket)
    end
  end

  def sync_and_reload(socket) do
    case sync_messages_from_session_file(socket) do
      {:ok, socket, _imported} -> socket
      {:error, _reason} -> maybe_reload_messages(socket)
    end
  end

  def maybe_reload_messages(socket) do
    if socket.assigns.active_tab == "messages" do
      TabHelpers.force_reload_messages(socket, socket.assigns.session_id)
    else
      socket
    end
  end

  @doc """
  On connected mount, loads messages from the DB immediately and kicks off an
  async Task to sync from the session file. The sync can involve many individual
  DB round-trips (one per message) and must not block the LiveView process —
  holding a DB connection in the LV for the full sync duration triggers a
  15 s DBConnection timeout for long sessions.

  The Task sends `:do_message_reload` when done so the LV picks up any newly
  imported messages without the user seeing a blank conversation.

  ## Why skip sync for active sessions

  When a session is actively running ("working" or "compacting"), the
  event-driven pipeline — `handle_claude_complete` / `handle_agent_stopped` →
  `sync_and_reload` — handles all JSONL imports. Running the mount Task sync
  concurrently creates a race: both paths call `SessionImporter.sync` at the
  same time, read the same `get_last_source_uuid` cursor before either commits,
  and each inserts the same JSONL entry with its own distinct source_uuid.
  `on_conflict: :nothing` only deduplicates identical UUIDs, so both rows land
  in the DB and the message renders twice. Skipping the Task sync for active
  sessions eliminates this window entirely.
  """
  @active_session_statuses ~w(working compacting)

  def load_messages_on_mount(socket) do
    if connected?(socket) do
      session = socket.assigns.session
      agent = socket.assigns.agent
      session_id = socket.assigns.session_id
      session_uuid = socket.assigns.session_uuid
      lv_pid = self()

      # Skip the file sync when the session is actively running — the
      # claude_complete / agent_stopped event handlers call sync_and_reload and
      # will import any new JSONL entries when Claude finishes. Doing the sync
      # here concurrently causes duplicate DB rows (different source_uuids,
      # same body) because both paths check agent_reply_already_recorded?
      # before either commits.
      unless session.status in @active_session_statuses do
        Task.start(fn ->
          result =
            case session.provider do
              "codex" -> sync_codex_async(session_id, session_uuid)
              "gemini" -> {:error, :no_file_sync}
              _ -> sync_claude_async(session_id, session_uuid, session, agent)
            end

          case result do
            {:ok, _} -> send(lv_pid, :do_message_reload)
            {:error, _} -> :ok
          end
        end)
      end

      TabHelpers.load_tab_data(socket, "messages", session_id)
    else
      # Dead render: load messages only — skip usage stats (file read or 2 aggregate
      # DB queries on all messages) that are discarded when the WebSocket connects.
      TabHelpers.load_messages_only(socket, socket.assigns.session_id)
    end
  end

  def schedule_message_reload(socket) do
    if socket.assigns.reload_timer do
      Process.cancel_timer(socket.assigns.reload_timer)
    end

    timer = Process.send_after(self(), :do_message_reload, @reload_debounce_ms)
    assign(socket, :reload_timer, timer)
  end

  defp sync_claude_session_file(socket) do
    session_id = socket.assigns.session_id
    session_uuid = socket.assigns.session_uuid

    with {:ok, project_path} <-
           SessionHelpers.resolve_project_path(socket.assigns.session, socket.assigns.agent),
         {:ok, imported} <- SessionImporter.sync(session_uuid, project_path, session_id) do
      {:ok, TabHelpers.force_reload_messages(socket, session_id), imported}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp sync_codex_session_file(socket) do
    session_id = socket.assigns.session_id
    thread_id = socket.assigns.session_uuid

    with {:ok, messages} <- CodexReader.read_messages(thread_id) do
      imported = CodexImporter.import_messages(messages, session_id)
      {:ok, TabHelpers.force_reload_messages(socket, session_id), imported}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Async-safe variants — take plain data, no socket. Used by load_messages_on_mount/1.
  defp sync_claude_async(session_id, session_uuid, session, agent) do
    with {:ok, project_path} <- SessionHelpers.resolve_project_path(session, agent) do
      SessionImporter.sync(session_uuid, project_path, session_id)
    end
  end

  defp sync_codex_async(session_id, session_uuid) do
    with {:ok, messages} <- CodexReader.read_messages(session_uuid) do
      {:ok, CodexImporter.import_messages(messages, session_id)}
    end
  end

  defp cleanup_rejected_message(message, uploaded_files) do
    Messages.delete_message(message)
    cleanup_uploaded_files(uploaded_files)
  end

  defp cleanup_uploaded_files([]), do: :ok

  defp cleanup_uploaded_files(uploaded_files) do
    Enum.each(uploaded_files, fn %{storage_path: path} ->
      case File.rm(path) do
        :ok -> Logger.info("Cleaned up rejected upload: #{path}")
        {:error, reason} -> Logger.warning("Failed to clean up upload #{path}: #{reason}")
      end
    end)
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
end
