defmodule EyeInTheSky.Claude.ChannelProtocol do
  @moduledoc """
  Defines the channel messaging protocol for agents.

  Three routing modes:
  - :direct    — agent was @mentioned by ID; must respond
  - :broadcast — @all was used; everyone must respond
  - :ambient   — no mention; agent should respond only if it has something useful to say

  All modes fan out to every channel member. AgentWorker suppresses [NO_RESPONSE]
  replies from DB storage.
  """

  @ambient_instruction """
  You are in a multi-agent channel. A message was posted that was not directed at you.
  Read it and reply ONLY if you have something genuinely useful or relevant to contribute.
  If you have nothing to add, reply with exactly: [NO_RESPONSE]
  Do not explain why you are not responding. Do not acknowledge the message. Just [NO_RESPONSE].
  """

  @direct_instruction """
  You were directly mentioned in a channel message. You must respond.
  """

  @broadcast_instruction """
  A broadcast message was sent to all agents in this channel. You must respond.
  """

  @type routing_mode :: :direct | :ambient | :broadcast

  @doc """
  Parses a raw message body and returns the routing mode for a given session_id,
  the list of explicitly mentioned session IDs, and whether @all was used.
  """
  @spec parse_routing(String.t(), integer()) ::
          {routing_mode(), mentioned_ids :: [integer()], mention_all :: boolean()}
  def parse_routing(body, session_id) when is_binary(body) and is_integer(session_id) do
    mention_all = Regex.match?(~r/@all\b/i, body)

    mentioned_ids =
      Regex.scan(~r/@(\d+)/, body)
      |> Enum.map(fn [_, id_str] -> String.to_integer(id_str) end)
      |> Enum.uniq()

    mode =
      cond do
        mention_all -> :broadcast
        session_id in mentioned_ids -> :direct
        true -> :ambient
      end

    {mode, mentioned_ids, mention_all}
  end

  @doc """
  Builds the prompt to send to an agent based on routing mode, the original message,
  and the channel context (id + name).
  """
  @spec build_prompt(routing_mode(), String.t(), %{id: integer(), name: String.t()}) :: String.t()
  def build_prompt(:direct, body, %{id: channel_id, name: channel_name}) do
    channel_ctx = """
    You are in channel ##{channel_name} (ID: #{channel_id}).
    Your response to this message will be automatically posted to this channel. This IS the group conversation.
    Do NOT use eits dm to communicate with other channel members — reply here in the channel.
    """

    channel_ctx <> @direct_instruction <> "\n\nMessage: #{body}"
  end

  def build_prompt(:broadcast, body, %{id: channel_id, name: channel_name}) do
    channel_ctx = """
    You are in channel ##{channel_name} (ID: #{channel_id}).
    Your response to this message will be automatically posted to this channel. This IS the group conversation.
    Do NOT use eits dm to communicate with other channel members — reply here in the channel.
    """

    channel_ctx <> @broadcast_instruction <> "\n\nMessage: #{body}"
  end

  def build_prompt(:ambient, body, %{id: channel_id, name: channel_name}) do
    channel_ctx = """
    You are in channel ##{channel_name} (ID: #{channel_id}).
    Your response to this message will be automatically posted to this channel. This IS the group conversation.
    Do NOT use eits dm to communicate with other channel members — reply here in the channel.
    """

    channel_ctx <> @ambient_instruction <> "\n\nMessage: #{body}"
  end

  @doc """
  Returns true if this member should be skipped (i.e., they are the sender).
  """
  @spec skip?(integer(), integer()) :: boolean()
  def skip?(member_session_id, sender_session_id), do: member_session_id == sender_session_id
end
