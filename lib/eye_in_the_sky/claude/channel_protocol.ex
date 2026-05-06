defmodule EyeInTheSky.Claude.ChannelProtocol do
  @moduledoc """
  Defines the channel messaging protocol for agents.

  Three routing modes:
  - :direct    — agent was @mentioned by ID; must respond
  - :broadcast — @all was used; everyone must respond
  - :ambient   — no mention; agent should respond only if it has something useful to say

  Ambient messages are never routed to agents per the chat channel protocol spec.
  AgentWorker suppresses [NO_RESPONSE] replies from DB storage.
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
  Builds the prompt to send to an agent for a channel-routed message.

  Accepts a single map:
    %{
      mode:    :direct | :broadcast | :ambient,
      channel: %{id: integer, name: string},
      sender:  string,
      body:    string
    }

  Output format:
    MSG from Channel #<name> (<id>)
    Mode: <mode>
    From: <sender>

    <body>

    ---
    Important:
    Do not answer this prompt directly unless you are explaining that you cannot respond.
    To respond to the channel, use:

      eits channels send <id> --body "your response"

    To read recent context:
      eits channels messages <id> --limit 20

    A normal DM response will NOT be posted to the channel.
  """
  @spec build_prompt(%{
          mode: routing_mode(),
          channel: %{id: integer(), name: String.t()},
          sender: String.t(),
          body: String.t()
        }) :: String.t()
  def build_prompt(%{
        mode: mode,
        channel: %{id: channel_id, name: channel_name},
        sender: sender,
        body: body
      }) do
    mode_str = Atom.to_string(mode)

    instruction =
      case mode do
        :ambient ->
          """
          Read this message and reply ONLY if you have something genuinely useful to contribute.
          If you have nothing to add, reply with exactly: [NO_RESPONSE]
          Do not explain why you are not responding. Just [NO_RESPONSE].
          """

        _ ->
          ""
      end

    base = """
    MSG from Channel ##{channel_name} (#{channel_id})
    Mode: #{mode_str}
    From: #{sender}

    #{body}

    ---
    Important:
    Do not answer this prompt directly unless you are explaining that you cannot respond.
    To respond to the channel, use:

      eits channels send #{channel_id} --body "your response"

    To read recent context:
      eits channels messages #{channel_id} --limit 20

    A normal DM response will NOT be posted to the channel.
    """

    (base <> instruction) |> String.trim_trailing()
  end

  @doc """
  Returns true if this member should be skipped (i.e., they are the sender).
  """
  @spec skip?(integer(), integer()) :: boolean()
  def skip?(member_session_id, sender_session_id), do: member_session_id == sender_session_id
end
