defmodule EyeInTheSkyWeb.ChatLive.ChannelHelpers do
  require Logger

  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSky.{Channels, Messages, Sessions}
  alias EyeInTheSky.Claude.ChannelProtocol

  def calculate_unread_counts(channels, session_id) do
    channel_ids = Enum.map(channels, & &1.id)
    counts = Channels.count_unread_for_channels(channel_ids, session_id)
    Map.new(channels, fn channel -> {channel.id, Map.get(counts, channel.id, 0)} end)
  end

  def load_channel_members(nil), do: []

  def load_channel_members(channel_id) do
    Channels.list_members_with_sessions(channel_id)
  end

  @doc """
  Auto-joins mentioned sessions to the channel, then routes the message
  to every existing agent member (excluding the sender).

  Extracted from ChatLive.handle_event("send_channel_message") to keep
  the LiveView handler thin.
  """
  def route_to_members(channel_id, body, sender_session_id, content_blocks) do
    {_mode, mentioned_ids, _mention_all} = ChannelProtocol.parse_routing(body, -1)

    Enum.each(mentioned_ids, &maybe_auto_add_member(channel_id, &1))

    case Channels.get_channel(channel_id) do
      nil ->
        Logger.error("ChannelHelpers: channel=#{channel_id} not found, skipping fanout")

      channel ->
        channel_ctx = %{id: channel.id, name: channel.name}

        # Parallelize fanout: each member gets its own DB insert + AgentManager
        # call in a supervised task. Previously serial (N × insert latency);
        # now concurrent (~1 × insert latency for any channel size).
        # max_concurrency caps connection-pool pressure; on_timeout: :kill_task
        # prevents a slow agent from blocking delivery to the rest.
        Channels.list_members(channel_id)
        |> Enum.reject(fn m -> ChannelProtocol.skip?(m.session_id, sender_session_id) end)
        |> Task.async_stream(
          fn member ->
            {mode, _mentioned_ids, _mention_all} =
              ChannelProtocol.parse_routing(body, member.session_id)

            case Messages.send_message(%{
                   session_id: member.session_id,
                   sender_role: "user",
                   recipient_role: "agent",
                   provider: "claude",
                   body: body
                 }) do
              {:ok, _message} ->
                prompt = ChannelProtocol.build_prompt(mode, body, channel_ctx)
                Logger.info("Routing to session=#{member.session_id} mode=#{mode}")

                AgentManager.send_message(member.session_id, prompt,
                  model: "sonnet",
                  channel_id: channel_id,
                  content_blocks: content_blocks
                )

              {:error, changeset} ->
                Logger.error(
                  "ChannelHelpers: failed to route message to session=#{member.session_id} errors=#{inspect(changeset.errors)}"
                )
            end
          end,
          max_concurrency: 10,
          timeout: 5_000,
          on_timeout: :kill_task
        )
        |> Stream.run()
    end
  end

  defp maybe_auto_add_member(channel_id, mid) do
    unless Channels.member?(channel_id, mid) do
      case Sessions.get_session(mid) do
        {:ok, s} ->
          Channels.add_member(channel_id, s.agent_id, mid)
          Logger.info("Auto-added session=#{mid} to channel=#{channel_id}")

        _ ->
          :ok
      end
    end
  end

  def build_sessions_by_project(channel_members, all_projects, search) do
    member_session_ids = channel_members |> Enum.map(& &1.session_id) |> MapSet.new()
    projects_by_id = Enum.into(all_projects, %{}, fn p -> {p.id, p} end)

    all_sessions =
      Sessions.list_sessions_filtered(
        status_filter: "all",
        search_query: search,
        limit: 100
      )

    all_sessions
    |> Enum.reject(fn s -> MapSet.member?(member_session_ids, s.id) end)
    |> Enum.group_by(fn s -> s.project_id end)
    |> Enum.map(fn {pid, sessions} ->
      project = Map.get(projects_by_id, pid)

      %{
        project_id: pid,
        project_name: if(project, do: project.name, else: "Unassigned"),
        sessions:
          Enum.map(sessions, fn s ->
            %{
              id: s.id,
              name: s.name,
              model: s.model,
              ended_at: s.ended_at,
              agent_description:
                if(Ecto.assoc_loaded?(s.agent) && s.agent,
                  do: s.agent.description,
                  else: nil
                )
            }
          end)
      }
    end)
    |> Enum.sort_by(fn g -> g.project_name end)
  end
end
