defmodule EyeInTheSkyWeb.Helpers.ChannelRoutingHelpers do
  @moduledoc """
  Shared helpers for routing direct messages to agent sessions via channels.
  """

  alias EyeInTheSky.{Channels, ChannelMessages, Sessions}

  @doc """
  Creates a channel message for a direct message to a target session.
  Callers are responsible for dispatching the prompt to the agent after this returns.

  Returns {:ok, channel_message} | {:error, reason_atom}
  """
  def create_dm_channel_message(channel_id, body, from_session_id) do
    case ChannelMessages.send_channel_message(%{
           channel_id: channel_id,
           session_id: from_session_id,
           sender_role: "user",
           recipient_role: "agent",
           provider: "claude",
           body: body
         }) do
      {:ok, message} -> {:ok, message}
      {:error, _} -> {:error, :send_failed}
    end
  end

  @doc """
  Finds the #global channel for a session by checking its project channels first,
  then falling back to all channels.

  Returns {:ok, channel} | {:error, :not_found}
  """
  def find_global_channel_for_session(target_session_id) do
    with {:ok, session} <- Sessions.get_session(target_session_id) do
      find_global_channel(session)
    else
      _ -> {:error, :session_not_found}
    end
  end

  # Finds the #global channel for a session by checking its project channels first,
  # then falling back to all channels.
  defp find_global_channel(session) do
    channels =
      if session.project_id,
        do: Channels.list_channels_for_project(session.project_id),
        else: Channels.list_channels()

    case Enum.find(channels, fn c -> c.name == "#global" end) do
      nil -> {:error, :channel_not_found}
      channel -> {:ok, channel}
    end
  end
end
