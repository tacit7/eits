defmodule EyeInTheSkyWebWeb.ChatPresenter do
  @moduledoc """
  Serialization and presentation helpers for ChatLive.
  Handles data shaping before assigns hit the template.
  """

  alias EyeInTheSkyWeb.Sessions

  def serialize_channels(channels) do
    Enum.map(channels, fn channel ->
      %{
        id: channel.id,
        name: channel.name,
        description: channel.description,
        channel_type: channel.channel_type
      }
    end)
  end

  def serialize_messages(messages), do: Enum.map(messages, &serialize_message/1)

  def serialize_message(message) do
    session_name =
      if Ecto.assoc_loaded?(message.session) && message.session do
        message.session.name
      else
        nil
      end

    %{
      id: message.id,
      number: message.channel_message_number,
      session_id: message.session_id,
      session_name: session_name,
      sender_role: message.sender_role,
      direction: message.direction,
      body: message.body,
      provider: message.provider,
      status: message.status,
      inserted_at: message.inserted_at,
      thread_reply_count: message.thread_reply_count || 0,
      reactions: serialize_reactions(message),
      metadata: message.metadata || %{}
    }
  end

  def serialize_reactions(message) do
    if Ecto.assoc_loaded?(message.reactions) do
      message.reactions
      |> Enum.group_by(& &1.emoji)
      |> Enum.map(fn {emoji, reactions} ->
        %{
          emoji: emoji,
          count: length(reactions),
          session_ids: Enum.map(reactions, & &1.session_id)
        }
      end)
    else
      []
    end
  end

  def serialize_prompts(prompts) do
    Enum.map(prompts, fn prompt ->
      %{
        id: prompt.id,
        name: prompt.name,
        slug: prompt.slug,
        description: prompt.description,
        prompt_text: prompt.prompt_text
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
