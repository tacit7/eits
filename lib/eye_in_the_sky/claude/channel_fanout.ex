defmodule EyeInTheSky.Claude.ChannelFanout do
  @moduledoc """
  Core channel fanout logic — routes a message to agent members of a channel.

  Two modes:

  - `fanout_all/4` — routes to every channel member (excluding sender). Each
    member's routing mode is determined by ChannelProtocol: :direct if mentioned
    by ID, :broadcast if @all was used, :ambient otherwise. Used for messages
    posted by humans or agents via the REST API.

  - `fanout_mentions_only/3` — routes only to sessions explicitly @mentioned in
    the body, always as :direct. No ambient fanout. Used when an agent's reply
    contains @mentions — avoids triggering ambient responses and unbounded chains.
  """

  require Logger

  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSky.{Channels, Messages, Sessions}
  alias EyeInTheSky.Claude.ChannelProtocol

  @doc """
  Fan out `body` to all current members of `channel_id`, skipping `sender_session_id`.

  Mentioned sessions that are not yet members are auto-added before fanout.

  `content_blocks` — multimodal blocks to forward (pass `[]` for text-only messages).
  """
  @spec fanout_all(channel_id :: term(), body :: String.t(), sender_session_id :: integer(), content_blocks :: list()) :: :ok
  def fanout_all(channel_id, body, sender_session_id, content_blocks \\ []) do
    {_mode, mentioned_ids, _mention_all} = ChannelProtocol.parse_routing(body, -1)
    Enum.each(mentioned_ids, &maybe_auto_add_member(channel_id, &1))

    case Channels.get_channel(channel_id) do
      nil ->
        Logger.error("ChannelFanout: channel=#{channel_id} not found, skipping fanout")

      channel ->
        channel_ctx = %{id: channel.id, name: channel.name}

        Channels.list_members(channel_id)
        |> Enum.reject(fn m -> ChannelProtocol.skip?(m.session_id, sender_session_id) end)
        |> Task.async_stream(
          fn member ->
            {mode, _mentioned_ids, _mention_all} =
              ChannelProtocol.parse_routing(body, member.session_id)

            route_to_member(member.session_id, body, mode, channel_ctx, channel_id, content_blocks)
          end,
          max_concurrency: 10,
          timeout: 5_000,
          on_timeout: :kill_task
        )
        |> Stream.run()
    end

    :ok
  end

  @doc """
  Route `body` only to sessions explicitly @mentioned in the body, as :direct.

  Does NOT fan out to non-mentioned members — prevents ambient chain reactions
  when an agent reply contains @mentions.

  `sender_session_id` is skipped even if mentioned.
  """
  @spec fanout_mentions_only(channel_id :: term(), body :: String.t(), sender_session_id :: integer()) :: :ok
  def fanout_mentions_only(channel_id, body, sender_session_id) do
    {_mode, mentioned_ids, _mention_all} = ChannelProtocol.parse_routing(body, -1)

    target_ids =
      mentioned_ids
      |> Enum.reject(&(&1 == sender_session_id))
      |> Enum.filter(&Channels.member?(channel_id, &1))

    if target_ids == [] do
      :ok
    else
      case Channels.get_channel(channel_id) do
        nil ->
          Logger.error("ChannelFanout: channel=#{channel_id} not found, skipping mention fanout")

        channel ->
          channel_ctx = %{id: channel.id, name: channel.name}

          target_ids
          |> Task.async_stream(
            fn session_id ->
              route_to_member(session_id, body, :direct, channel_ctx, channel_id, [])
            end,
            max_concurrency: 10,
            timeout: 5_000,
            on_timeout: :kill_task
          )
          |> Stream.run()
      end
    end

    :ok
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp route_to_member(session_id, body, mode, channel_ctx, channel_id, content_blocks) do
    case Messages.send_message(%{
           session_id: session_id,
           sender_role: "user",
           recipient_role: "agent",
           provider: "claude",
           body: body
         }) do
      {:ok, _message} ->
        prompt = ChannelProtocol.build_prompt(mode, body, channel_ctx)
        Logger.info("ChannelFanout: routing to session=#{session_id} mode=#{mode}")

        AgentManager.send_message(session_id, prompt,
          model: "sonnet",
          channel_id: channel_id,
          content_blocks: content_blocks
        )

      {:error, changeset} ->
        Logger.error(
          "ChannelFanout: failed to route to session=#{session_id} errors=#{inspect(changeset.errors)}"
        )
    end
  end

  defp maybe_auto_add_member(channel_id, session_id) do
    unless Channels.member?(channel_id, session_id) do
      case Sessions.get_session(session_id) do
        {:ok, s} ->
          Channels.add_member(channel_id, s.agent_id, session_id)
          Logger.info("ChannelFanout: auto-added session=#{session_id} to channel=#{channel_id}")

        _ ->
          :ok
      end
    end
  end
end
