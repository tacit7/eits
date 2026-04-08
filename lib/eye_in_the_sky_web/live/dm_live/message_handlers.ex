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

        socket = TabHelpers.load_tab_data(socket, "messages", session_id)

        base_opts = SessionHelpers.continue_session_opts(model, effort_level, thinking_enabled, max_budget_usd)
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
            Logger.warning("Queue full for session=#{session_id}, deleting orphaned message id=#{message.id}")
            cleanup_rejected_message(message, uploaded_files)

            {:noreply,
             socket
             |> TabHelpers.load_tab_data("messages", session_id)
             |> assign(:processing, false)
             |> put_flash(:error, "Queue is full — max 5 messages pending")}

          {:error, reason} ->
            Logger.error("Failed to send message via AgentManager: #{inspect(reason)}")
            cleanup_rejected_message(message, uploaded_files)

            {:noreply,
             socket
             |> TabHelpers.load_tab_data("messages", session_id)
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
    provider = socket.assigns.session.provider

    if provider == "codex" do
      sync_codex_session_file(socket)
    else
      sync_claude_session_file(socket)
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
      TabHelpers.load_tab_data(socket, "messages", socket.assigns.session_id)
    else
      socket
    end
  end

  @doc """
  On connected mount, syncs messages from the session file into the DB first
  so navigating back after an agent run shows the full conversation.
  Falls back to a plain DB query if no session file / project path found.
  """
  def load_messages_on_mount(socket) do
    if connected?(socket) do
      case sync_messages_from_session_file(socket) do
        {:ok, socket, _imported} -> socket
        {:error, _reason} -> TabHelpers.load_tab_data(socket, "messages", socket.assigns.session_id)
      end
    else
      TabHelpers.load_tab_data(socket, "messages", socket.assigns.session_id)
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
      {:ok, TabHelpers.load_tab_data(socket, "messages", session_id), imported}
    end
  end

  defp sync_codex_session_file(socket) do
    session_id = socket.assigns.session_id
    thread_id = socket.assigns.session_uuid

    with {:ok, messages} <- CodexReader.read_messages(thread_id) do
      imported = CodexImporter.import_messages(messages, session_id)
      {:ok, TabHelpers.load_tab_data(socket, "messages", session_id), imported}
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
