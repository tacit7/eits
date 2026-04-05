defmodule EyeInTheSkyWeb.ChatLive.ChannelHelpers do
  require Logger

  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSky.{Channels, Messages, Sessions}
  alias EyeInTheSky.Claude.ChannelProtocol

  def calculate_unread_counts(channels, session_id) do
    Enum.reduce(channels, %{}, fn channel, acc ->
      count = Channels.count_unread_messages(channel.id, session_id)
      Map.put(acc, channel.id, count)
    end)
  end

  def load_channel_members(nil), do: []

  def load_channel_members(channel_id) do
    Channels.list_members(channel_id)
    |> Enum.map(fn member ->
      session_data =
        case Sessions.get_session(member.session_id) do
          {:ok, s} -> s
          _ -> nil
        end

      %{
        id: member.id,
        session_id: member.session_id,
        agent_id: member.agent_id,
        role: member.role,
        joined_at: member.joined_at,
        session_name: session_data && session_data.name,
        session_uuid: session_data && session_data.uuid
      }
    end)
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

    agent_members = Channels.list_members(channel_id)

    Enum.each(agent_members, fn member ->
      unless ChannelProtocol.skip?(member.session_id, sender_session_id) do
        {mode, _mentioned_ids, _mention_all} =
          ChannelProtocol.parse_routing(body, member.session_id)

        Messages.send_message(%{
          session_id: member.session_id,
          sender_role: "user",
          recipient_role: "agent",
          provider: "claude",
          body: body
        })

        prompt = ChannelProtocol.build_prompt(mode, body)
        Logger.info("Routing to session=#{member.session_id} mode=#{mode}")

        AgentManager.send_message(member.session_id, prompt,
          model: "sonnet",
          channel_id: channel_id,
          content_blocks: content_blocks
        )
      end
    end)
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
