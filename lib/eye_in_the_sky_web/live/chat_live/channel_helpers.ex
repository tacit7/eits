defmodule EyeInTheSkyWeb.ChatLive.ChannelHelpers do
  require Logger

  alias EyeInTheSky.{Channels, Sessions}
  alias EyeInTheSky.Claude.ChannelFanout

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

  Delegates to ChannelFanout.fanout_all/4.
  """
  def route_to_members(channel_id, body, sender_session_id, content_blocks) do
    ChannelFanout.fanout_all(channel_id, body, sender_session_id, content_blocks)
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
