defmodule EyeInTheSkyWeb.NATS.Publisher do
  @moduledoc """
  Outbound NATS publishing for the Phoenix app.

  Publishes messages to NATS subjects using the `:gnat` registered connection.
  """

  require Logger

  @doc """
  Publish a JSON payload to a NATS subject.
  """
  def publish(subject, payload) when is_binary(subject) and is_map(payload) do
    case Process.whereis(:gnat) do
      nil ->
        Logger.warning("[NATS.Publisher] No NATS connection, skipping publish to #{subject}")
        {:error, :not_connected}

      gnat ->
        body = Jason.encode!(payload)
        Gnat.pub(gnat, subject, body)
    end
  end

  def publish_session_start(session_data) do
    publish("events.session.start", session_data)
  end

  def publish_session_update(session_data) do
    publish("events.session.update", session_data)
  end

  def publish_commits(commit_data) do
    publish("events.commits", commit_data)
  end

  def publish_note(note_data) do
    publish("events.notes", note_data)
  end

  def publish_context(context_data) do
    publish("events.session.context", context_data)
  end

  def publish_tool_use(tool_data) do
    publish("events.tool.use", tool_data)
  end

  def publish_todo(todo_data) do
    publish("events.todo", todo_data)
  end
end
