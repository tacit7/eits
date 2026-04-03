defmodule EyeInTheSkyWeb.ChatLive.ChannelHelpers do
  alias EyeInTheSky.{Channels, Sessions}

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
