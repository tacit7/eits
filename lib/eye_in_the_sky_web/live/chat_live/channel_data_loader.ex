defmodule EyeInTheSkyWeb.ChatLive.ChannelDataLoader do
  @moduledoc """
  Loads all DB data needed for a channel view.

  Returns a plain map consumed by chat_live.ex via assign/2.
  Isolated from socket state to keep queries side-effect-free.
  """

  alias EyeInTheSky.{Agents, ChannelMessages, Prompts, Projects, Sessions}
  alias EyeInTheSkyWeb.ChatLive.ChannelHelpers
  alias EyeInTheSkyWeb.ChatPresenter

  @spec load(integer() | nil, integer() | nil, map()) :: map()
  def load(project_id, channel_id, opts \\ %{}) do
    session_search = Map.get(opts, :session_search, "")
    channels = Map.get(opts, :channels, [])
    session_id = Map.get(opts, :session_id)
    thread_id = Map.get(opts, :thread_id)

    messages =
      if channel_id do
        channel_id
        |> ChannelMessages.list_messages_for_channel()
        |> ChatPresenter.serialize_messages()
      else
        []
      end

    unread_counts = ChannelHelpers.calculate_unread_counts(channels, session_id)
    active_thread = load_thread(thread_id)

    agent_status_counts =
      case Agents.get_agent_status_counts(project_id) do
        counts when is_map(counts) -> counts
        _ -> %{}
      end

    prompts =
      project_id
      |> then(&Prompts.list_prompts(project_id: &1))
      |> ChatPresenter.serialize_prompts()

    agent_templates =
      Agents.list_active_agents()
      |> Enum.filter(fn a -> a.description && a.description != "" end)
      |> Enum.take(50)
      |> Enum.map(&agent_template_option/1)

    channel_members = ChannelHelpers.load_channel_members(channel_id)
    all_projects = Projects.list_projects()

    active_sessions =
      project_id
      |> Sessions.list_active_sessions_for_project()
      |> Enum.map(&serialize_session/1)

    sessions_by_project =
      ChannelHelpers.build_sessions_by_project(channel_members, all_projects, session_search)

    %{
      messages: messages,
      unread_counts: unread_counts,
      active_thread: active_thread,
      agent_status_counts: agent_status_counts,
      prompts: prompts,
      agent_templates: agent_templates,
      channel_members: channel_members,
      all_projects: all_projects,
      active_sessions: active_sessions,
      sessions_by_project: sessions_by_project
    }
  end

  @spec load_thread(integer() | String.t() | nil) :: map() | nil
  def load_thread(nil), do: nil

  def load_thread(message_id) do
    parent_message = ChannelMessages.get_message_with_thread!(message_id)

    %{
      parent_message: ChatPresenter.serialize_message(parent_message),
      replies: Enum.map(parent_message.thread_replies, &ChatPresenter.serialize_message/1)
    }
  end

  defp serialize_session(session) do
    %{
      id: session.id,
      uuid: session.uuid,
      name: session.name,
      description: session.description,
      provider: session.provider || "claude",
      model: session.model,
      project_id: session.project_id,
      agent_description:
        if(Ecto.assoc_loaded?(session.agent) && session.agent,
          do: session.agent.description,
          else: nil
        )
    }
  end

  defp agent_template_option(agent), do: %{id: agent.id, description: agent.description}
end
