defmodule EyeInTheSkyWeb.Helpers.ChannelRoutingHelpers do
  @moduledoc """
  Shared helpers for routing direct messages to agent sessions via channels.
  """

  alias EyeInTheSky.{Channels, ChannelMessages, Sessions}
  alias EyeInTheSky.Agents.AgentManager

  @doc """
  Sends a direct message to a target session via its global channel.
  Creates the channel message and routes the prompt to the agent worker.

  Returns {:ok, channel_message} | {:error, reason_atom}
  """
  def send_dm_to_session(target_session_id, body, from_session_id, opts \\ []) do
    content_blocks = Keyword.get(opts, :content_blocks, [])

    with {:session, {:ok, session}} <- {:session, Sessions.get_session(target_session_id)},
         {:channel, {:ok, global_channel}} <- {:channel, find_global_channel(session)},
         {:send, {:ok, message}} <-
           {:send,
            ChannelMessages.send_channel_message(%{
              channel_id: global_channel.id,
              session_id: from_session_id,
              sender_role: "user",
              recipient_role: "agent",
              provider: "claude",
              body: body
            })} do
      AgentManager.send_message(target_session_id, body,
        channel_id: global_channel.id,
        content_blocks: content_blocks
      )

      {:ok, message}
    else
      {:session, _} -> {:error, :session_not_found}
      {:channel, _} -> {:error, :channel_not_found}
      {:send, _} -> {:error, :send_failed}
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
      nil -> {:error, :not_found}
      channel -> {:ok, channel}
    end
  end
end
