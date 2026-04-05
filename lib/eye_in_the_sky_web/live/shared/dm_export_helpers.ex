defmodule EyeInTheSkyWeb.Live.Shared.DmExportHelpers do
  @moduledoc false
  import Phoenix.LiveView, only: [push_event: 3, put_flash: 3]

  alias EyeInTheSky.Claude.SessionImporter
  alias EyeInTheSky.Claude.SessionReader
  alias EyeInTheSky.Codex.SessionImporter, as: CodexImporter
  alias EyeInTheSky.Codex.SessionReader, as: CodexReader
  alias EyeInTheSky.Messages
  alias EyeInTheSkyWeb.Live.Shared.SessionHelpers

  def handle_export_jsonl(socket) do
    messages = socket.assigns[:messages] || []

    text =
      Enum.map_join(messages, "\n", fn msg ->
        Jason.encode!(%{
          role: msg.sender_role,
          body: msg.body,
          timestamp: msg.inserted_at
        })
      end)

    {:noreply, push_event(socket, "copy_to_clipboard", %{text: text, format: "JSONL"})}
  end

  def handle_export_markdown(socket) do
    messages = socket.assigns[:messages] || []

    text =
      Enum.map_join(messages, "\n\n", fn msg ->
        role = String.capitalize(to_string(msg.sender_role))
        "**#{role}**: #{msg.body}"
      end)

    {:noreply, push_event(socket, "copy_to_clipboard", %{text: text, format: "Markdown"})}
  end

  def handle_reload_from_session_file(socket, load_messages_fn) do
    provider = socket.assigns.session.provider

    if provider == "codex" do
      reload_codex_session(socket, load_messages_fn)
    else
      reload_claude_session(socket, load_messages_fn)
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp reload_claude_session(socket, load_messages_fn) do
    session_id = socket.assigns.session_id
    session_uuid = socket.assigns.session_uuid

    with {:ok, project_path} <-
           SessionHelpers.resolve_project_path(socket.assigns.session, socket.assigns.agent),
         {:ok, raw_messages} <-
           SessionReader.read_messages_after_uuid(session_uuid, project_path, nil) do
      Messages.delete_session_messages(session_id)
      imported = SessionImporter.import_messages(raw_messages, session_id)
      socket = load_messages_fn.(socket)
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

  defp reload_codex_session(socket, load_messages_fn) do
    session_id = socket.assigns.session_id
    thread_id = socket.assigns.session_uuid

    case CodexReader.read_messages(thread_id) do
      {:ok, messages} ->
        Messages.delete_session_messages(session_id)
        imported = CodexImporter.import_messages(messages, session_id)
        socket = load_messages_fn.(socket)
        {:noreply, put_flash(socket, :info, "Reloaded #{imported} messages from Codex session file")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "No Codex session file found for thread #{thread_id}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to reload Codex session: #{inspect(reason)}")}
    end
  end
end
