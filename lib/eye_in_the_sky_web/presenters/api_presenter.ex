defmodule EyeInTheSkyWeb.Presenters.ApiPresenter do
  @moduledoc """
  Shared presenter functions for JSON API responses.
  Consolidates all format_*/1 and inline map formatting from API controllers.
  """

  def present_task(task) do
    %{
      id: task.id,
      title: task.title,
      description: task.description,
      priority: task.priority,
      state: if(Ecto.assoc_loaded?(task.state) && task.state, do: task.state.name),
      state_id: task.state_id,
      due_at: task.due_at
    }
  end

  def present_note(note) do
    %{
      id: note.id,
      parent_id: note.parent_id,
      parent_type: note.parent_type,
      title: note.title,
      body: note.body,
      starred: note.starred || false
    }
  end

  def present_channel(ch) do
    %{
      id: to_string(ch.id),
      name: ch.name,
      description: ch.description,
      channel_type: ch.channel_type,
      project_id: ch.project_id
    }
  end

  def present_channel_message(msg) do
    %{
      id: msg.id,
      number: msg.channel_message_number,
      uuid: msg.uuid,
      session_id: msg.session_id,
      session_name:
        if(Ecto.assoc_loaded?(msg.session) && msg.session, do: msg.session.name, else: nil),
      sender_role: msg.sender_role,
      provider: msg.provider,
      body: msg.body,
      status: msg.status,
      inserted_at: msg.inserted_at
    }
  end

  def present_commit(c) do
    %{id: c.id, commit_hash: c.commit_hash, commit_message: c.commit_message}
  end

  def present_agent(agent) do
    %{
      id: agent.id,
      uuid: agent.uuid,
      description: agent.description,
      status: agent.status,
      project_id: agent.project_id,
      project_name: agent.project_name
    }
  end

  def present_project(project) do
    %{
      id: project.id,
      name: project.name,
      path: project.path,
      slug: project.slug,
      active: project.active
    }
  end

  def present_prompt(prompt) do
    %{
      id: prompt.id,
      uuid: prompt.uuid,
      name: prompt.name,
      slug: prompt.slug,
      description: prompt.description,
      project_id: prompt.project_id,
      active: prompt.active
    }
  end

  def present_team(team) do
    %{
      id: team.id,
      uuid: team.uuid,
      name: team.name,
      description: team.description,
      status: team.status,
      project_id: team.project_id,
      member_count: length(team.members),
      created_at: to_string(team.created_at)
    }
  end

  def present_session(session) do
    %{
      id: session.id,
      uuid: session.uuid,
      name: session.name,
      description: session.description,
      status: session.status
    }
  end

  @doc """
  Full session detail shape for the show endpoint.
  `opts` accepts: agent_uuid (string), is_spawned (boolean).
  """
  def present_session_detail(session, opts \\ []) do
    %{
      id: session.id,
      uuid: session.uuid,
      session_id: session.uuid,
      agent_id: Keyword.get(opts, :agent_uuid),
      agent_int_id: session.agent_id,
      project_id: session.project_id,
      status: session.status,
      name: session.name,
      description: session.description,
      is_spawned: Keyword.get(opts, :is_spawned, false),
      initialized: true
    }
  end

  @doc """
  Resolves a human-readable sender name from a session struct.
  Checks for a team member name, falls back to the agent description, then session name.
  Performs DB queries via Agents + Teams — call from controller layer only.
  """
  def resolve_session_sender_name(session) do
    alias EyeInTheSky.{Agents, Teams}

    case session.agent_id do
      nil ->
        session.name || "agent"

      agent_id ->
        case Agents.get_agent(agent_id) do
          {:ok, agent} ->
            case Teams.get_member_by_agent_id(agent.id) do
              {:ok, %{name: name}} when is_binary(name) and name != "" -> name
              _ -> session.name || agent.description || "agent"
            end

          {:error, :not_found} ->
            session.name || "agent"
        end
    end
  end

  def present_bookmark(bookmark) do
    %{
      id: bookmark.id,
      bookmark_type: bookmark.bookmark_type,
      bookmark_id: bookmark.bookmark_id,
      file_path: bookmark.file_path,
      line_number: bookmark.line_number,
      url: bookmark.url,
      title: bookmark.title,
      description: bookmark.description,
      category: bookmark.category,
      priority: bookmark.priority,
      position: bookmark.position,
      project_id: bookmark.project_id,
      agent_id: bookmark.agent_id,
      accessed_at: bookmark.accessed_at,
      inserted_at: bookmark.inserted_at,
      updated_at: bookmark.updated_at
    }
  end

  def present_job(job) do
    alias EyeInTheSky.ScheduledJobs

    %{
      id: job.id,
      name: job.name,
      description: job.description,
      job_type: job.job_type,
      origin: job.origin,
      schedule_type: job.schedule_type,
      schedule_value: job.schedule_value,
      config: ScheduledJobs.decode_config(job),
      enabled: job.enabled,
      project_id: job.project_id,
      last_run_at: job.last_run_at,
      next_run_at: job.next_run_at,
      run_count: job.run_count || 0
    }
  end

  def present_member(m) do
    %{
      id: m.id,
      name: m.name,
      role: m.role,
      status: m.status,
      agent_id: m.agent_id,
      agent_uuid: if(Ecto.assoc_loaded?(m.agent) && m.agent, do: m.agent.uuid),
      session_id: m.session_id,
      session_uuid: if(Ecto.assoc_loaded?(m.session) && m.session, do: m.session.uuid),
      session_status: if(Ecto.assoc_loaded?(m.session) && m.session, do: m.session.status),
      joined_at: m.joined_at && to_string(m.joined_at),
      last_activity_at: m.last_activity_at && to_string(m.last_activity_at)
    }
  end
end
