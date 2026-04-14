defmodule EyeInTheSky.Sessions.ToolEventRecorder do
  @moduledoc """
  Records tool pre/post events, creates Message records, and fires PubSub events.
  Extracted from EyeInTheSky.Sessions to keep orchestration logic separate from
  session lifecycle management.
  """

  alias EyeInTheSky.Messages
  alias EyeInTheSky.Events

  @doc """
  Records a tool pre/post event, creates a Message record, and fires PubSub events.

  Takes the session, event type ("pre" or "post"), and params containing
  tool_name and tool_input.

  Returns :ok or {:error, reason}.
  """
  def record_tool_event(session, type, params) do
    tool_name = params["tool_name"]
    tool_input = params["tool_input"] || %{}
    provider = params["provider"] || "claude"

    case type do
      "pre" ->
        input_json = Jason.encode!(tool_input)
        body = "Tool: #{tool_name}\n#{input_json}" |> String.slice(0..3999)

        case Messages.create_message(%{
               uuid: Ecto.UUID.generate(),
               session_id: session.id,
               sender_role: "tool",
               recipient_role: "user",
               direction: "inbound",
               body: body,
               status: "delivered",
               provider: provider,
               metadata: %{
                 "stream_type" => "tool_use",
                 "tool_name" => tool_name,
                 "input" => tool_input
               }
             }) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            require Logger
            Logger.warning("tool_event_recorder: failed to insert pre-event for #{tool_name}: #{inspect(reason)}")
        end

        Events.agent_working(session)
        Events.session_tool_use(session.id, tool_name, tool_input)
        :ok

      "post" ->
        input_json = Jason.encode!(tool_input)
        body = "Tool: #{tool_name} (completed)\n#{input_json}" |> String.slice(0..3999)

        case Messages.create_message(%{
               uuid: Ecto.UUID.generate(),
               session_id: session.id,
               sender_role: "tool",
               recipient_role: "user",
               direction: "inbound",
               body: body,
               status: "delivered",
               provider: provider,
               metadata: %{"stream_type" => "tool_result", "tool_name" => tool_name}
             }) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            require Logger
            Logger.warning("tool_event_recorder: failed to insert post-event for #{tool_name}: #{inspect(reason)}")
        end

        Events.session_tool_result(session.id, tool_name, false)
        :ok

      _ ->
        {:error, "Invalid type"}
    end
  end
end
