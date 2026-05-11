defmodule EyeInTheSkyWeb.DmLive.MessageHandlers do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [connected?: 1, put_flash: 3, push_event: 3, stream: 4, stream_insert: 3]

  # stream/4 requires LiveView lifecycle infrastructure (live_temp.lifecycle).
  # Mock sockets in unit tests lack this; safe_stream skips gracefully.
  defp safe_stream(socket, name, items, opts) do
    stream(socket, name, items, opts)
  rescue
    KeyError -> socket
  end

  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSky.Claude.SessionImporter
  alias EyeInTheSky.Codex.SessionImporter, as: CodexImporter
  alias EyeInTheSky.Codex.SessionReader, as: CodexReader
  alias EyeInTheSky.Gemini.SessionImporter, as: GeminiImporter
  alias EyeInTheSky.Messages
  alias EyeInTheSky.Repo
  alias EyeInTheSkyWeb.DmLive.MessageGrouper
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
      "codex" ->
        sync_codex_session_file(socket)

      "gemini" ->
        sync_gemini_session_file(socket)

      _ ->
        sync_claude_session_file(socket)
    end
  end

  defp sync_gemini_session_file(socket) do
    session_id = socket.assigns.session_id
    session_uuid = socket.assigns.session_uuid

    project_path =
      case SessionHelpers.resolve_project_path(socket.assigns.session, socket.assigns.agent) do
        {:ok, path} -> path
        _ -> nil
      end

    case GeminiImporter.sync(session_uuid, project_path, session_id) do
      {:ok, %{inserted: _, updated: _} = counts} ->
        {:ok, socket, counts}

      {:error, reason} ->
        {:error, reason}
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

  @sync_timeout_ms 5_000

  @doc """
  On mount, shows a loading skeleton and defers message loading until after the
  session file sync completes. This prevents the "one by one" loading effect
  caused by a stream reset mid-render.

  Both dead and connected renders start with `syncing: true` (set in
  `assign_ui_flags`). The connected render kicks off an async sync Task that
  sends `{:sync_done, result}` on completion. DmLive.handle_info dismisses the
  skeleton and loads messages all at once.

  A 5-second timeout fires `:sync_timeout` as a failsafe for large sessions
  or slow disk — the skeleton is dismissed and messages load from DB directly.

  ## Stream initialization

  The `:grouped_messages` stream must be initialized in mount even when the
  skeleton is showing, otherwise later `stream_insert` / `stream reset` calls
  would crash with an uninitialized stream error.
  """
  def load_messages_on_mount(socket) do
    if connected?(socket) do
      session = socket.assigns.session
      agent = socket.assigns.agent
      session_id = socket.assigns.session_id
      session_uuid = socket.assigns.session_uuid
      lv_pid = self()

      # Schedule failsafe — dismisses skeleton if Task takes too long.
      Process.send_after(lv_pid, :sync_timeout, @sync_timeout_ms)

      Task.start(fn ->
        result =
          case session.provider do
            "codex" ->
              sync_codex_async(session_id, session_uuid)

            "gemini" ->
              sync_gemini_async(session_id, session_uuid, session, agent)

            _ ->
              sync_claude_async(session_id, session_uuid, session, agent)
          end

        case result do
          {:ok, %{inserted: 0, updated: 0}} ->
            Logger.debug("DM mount sync: no new messages",
              session_id: session_id
            )

            send(lv_pid, {:sync_done, :clean})

          {:ok, %{inserted: inserted, updated: updated}} ->
            Logger.info(
              "DM mount sync imported messages inserted=#{inserted} updated=#{updated}",
              session_id: session_id
            )

            send(lv_pid, {:sync_done, :dirty})

          {:error, reason} ->
            Logger.warning("DM mount sync failed",
              session_id: session_id,
              reason: inspect(reason)
            )

            send(lv_pid, {:sync_done, :clean})
        end
      end)

      init_empty_stream(socket)
    else
      # Dead render: initialize stream empty and show skeleton.
      # Messages load after the connected sync Task completes.
      init_empty_stream(socket)
    end
  end

  # Initializes stream assigns for the skeleton state — no DB load.
  # Messages are populated later by handle_info({:sync_done, _}).
  defp init_empty_stream(socket) do
    socket
    |> assign(:messages, nil)
    |> assign(:last_stream_tail, [])
    |> safe_stream(:grouped_messages, [], reset: true)
  end

  @doc """
  Appends a single message from a PubSub broadcast to @messages and
  stream_inserts only the changed grouped rows.

  This replaces the previous schedule_message_reload approach for {:new_message} and
  {:new_dm} events, which threw away the already-delivered payload and debounced a
  full DB reload of all N messages.

  Deduplication by id is required: handle_send_message calls force_reload_messages
  immediately after persisting the user message, so @messages already contains it
  when the PubSub {:new_message} event arrives. Without the check we'd duplicate it.

  Attachments are preloaded here because broadcast_and_return only preloads
  [:session, :reactions] at insert time — the :attachments association would be
  %Ecto.Association.NotLoaded{}, which crashes the message_attachments template
  component (the `attachments != []` guard does not rescue NotLoaded structs).

  Rather than re-rendering the entire grouped list, MessageGrouper.diff_tail/2
  re-runs group_events on the last #{MessageGrouper.tail_window()} messages and
  returns only rows that are new or changed. Typically 1 new row (standalone
  assistant message). A tool event appended to an existing cluster produces 1
  updated cluster row (same id → morphdom patches, no delete+reinsert).

  Cancels any pending debounced reload timer so a stale :do_message_reload cannot
  clobber the list after we have already appended the new entry.
  """
  def append_message_from_pubsub(socket, message) do
    existing = socket.assigns[:messages] || []

    if Enum.any?(existing, &(&1.id == message.id)) do
      socket
    else
      message = Repo.preload(message, :attachments)
      new_messages = existing ++ [message]
      cached_tail = socket.assigns[:last_stream_tail] || []
      {changed_rows, new_tail} = MessageGrouper.diff_from_cached_tail(cached_tail, new_messages)

      socket =
        socket
        |> cancel_reload_timer()
        |> assign(:messages, new_messages)
        |> assign(:last_stream_tail, new_tail)
        |> push_event("new_message", %{})

      Enum.reduce(changed_rows, socket, fn row, acc ->
        stream_insert(acc, :grouped_messages, row)
      end)
    end
  end

  def schedule_message_reload(socket) do
    if socket.assigns.reload_timer do
      Process.cancel_timer(socket.assigns.reload_timer)
    end

    timer = Process.send_after(self(), :do_message_reload, @reload_debounce_ms)
    assign(socket, :reload_timer, timer)
  end

  defp cancel_reload_timer(socket) do
    case socket.assigns[:reload_timer] do
      nil ->
        socket

      timer ->
        Process.cancel_timer(timer)
        assign(socket, :reload_timer, nil)
    end
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

  # Conditional auto-sync for Gemini:
  # * DB has messages: skip to avoid duplicate inserts (UUID spaces differ).
  # * DB is empty: full file sync so conversation history appears on first load.
  defp sync_gemini_async(session_id, session_uuid, session, agent) do
    db_count = EyeInTheSky.Messages.count_messages_for_session(session_id)

    if db_count > 0 do
      {:ok, %{inserted: 0, updated: 0}}
    else
      project_path =
        case SessionHelpers.resolve_project_path(session, agent) do
          {:ok, path} -> path
          _ -> nil
        end

      GeminiImporter.sync(session_uuid, project_path, session_id)
    end
  end

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
