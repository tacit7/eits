defmodule EyeInTheSkyWeb.Presenters.ApiPresenter do
  @moduledoc """
  Shared presenter functions for JSON API responses.
  Consolidates all format_*/1 and inline map formatting from API controllers.
  """

  alias EyeInTheSky.{Agents, Teams}
  alias EyeInTheSky.ScheduledJobs

  def present_task(task) do
    %{
      id: task.id,
      title: task.title,
      description: task.description,
      priority: task.priority,
      state: loaded_field(task.state, :name),
      state_id: task.state_id,
      due_at: task.due_at,
      created_at: format_dt(task.created_at),
      updated_at: format_dt(task.updated_at)
    }
  end

  def present_note(note) do
    %{
      id: note.id,
      parent_id: note.parent_id,
      parent_type: note.parent_type,
      title: note.title,
      body: note.body,
      body_length: if(note.body, do: byte_size(note.body), else: 0),
      starred: note.starred || false,
      created_at: if(note.created_at, do: to_string(note.created_at), else: nil)
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

  def present_channel_member(m) do
    %{
      id: m.id,
      channel_id: m.channel_id,
      agent_id: m.agent_id,
      session_id: m.session_id,
      role: m.role,
      notifications: m.notifications,
      joined_at: if(m.joined_at, do: to_string(m.joined_at))
    }
  end

  def present_channel_message(msg) do
    %{
      id: msg.id,
      number: msg.channel_message_number,
      uuid: msg.uuid,
      session_id: msg.session_id,
      session_name: loaded_field(msg.session, :name),
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
      status: session.status,
      status_reason: session.status_reason,
      read_only: session.read_only || false
    }
  end

  @doc """
  Full session detail shape for the show endpoint.
  `opts` accepts: agent_uuid (string), is_spawned (boolean),
  tasks (list), recent_notes (list), recent_commits (list),
  worktree_path (string | nil), branch_name (string | nil).
  """
  def present_session_detail(session, opts \\ []) do
    tasks = Keyword.get(opts, :tasks, [])
    recent_notes = Keyword.get(opts, :recent_notes, [])
    recent_commits = Keyword.get(opts, :recent_commits, [])

    %{
      id: session.id,
      uuid: session.uuid,
      session_id: session.uuid,
      agent_id: Keyword.get(opts, :agent_uuid),
      agent_int_id: session.agent_id,
      project_id: session.project_id,
      status: session.status,
      status_reason: session.status_reason,
      name: session.name,
      description: session.description,
      is_spawned: Keyword.get(opts, :is_spawned, false),
      read_only: session.read_only || false,
      initialized: true,
      worktree_path: Keyword.get(opts, :worktree_path),
      branch_name: Keyword.get(opts, :branch_name),
      tasks: Enum.map(tasks, &present_session_task/1),
      recent_notes: Enum.map(recent_notes, &present_session_note/1),
      recent_commits: Enum.map(recent_commits, &present_session_commit/1)
    }
  end

  defp present_session_task(task) do
    %{
      id: task.id,
      title: task.title,
      state: loaded_field(task.state, :name),
      state_id: task.state_id
    }
  end

  defp present_session_note(note) do
    %{
      id: note.id,
      title: note.title,
      body: if(note.body, do: String.slice(note.body, 0, 120), else: nil),
      starred: note.starred || false,
      created_at: to_string(note.created_at)
    }
  end

  defp present_session_commit(commit) do
    %{
      id: commit.id,
      commit_hash: commit.commit_hash,
      commit_message: commit.commit_message,
      inserted_at: to_string(commit.created_at)
    }
  end

  @doc """
  Resolves a human-readable sender name from a session struct.
  Checks for a team member name, falls back to the agent description, then session name.
  Performs DB queries via Agents + Teams — call from controller layer only.
  """
  def resolve_session_sender_name(session) do
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
      member_status: m.status,
      status: m.status,
      agent_id: m.agent_id,
      agent_uuid: loaded_field(m.agent, :uuid),
      session_id: m.session_id,
      session_uuid: loaded_field(m.session, :uuid),
      session_status: loaded_field(m.session, :status),
      session_status_reason: loaded_field(m.session, :status_reason),
      claimed_task: format_claimed_task(m.claimed_task),
      joined_at: if(m.joined_at, do: to_string(m.joined_at)),
      last_activity_at: if(m.last_activity_at, do: to_string(m.last_activity_at))
    }
  end

  defp format_claimed_task(nil), do: nil

  defp format_claimed_task(%{} = task) do
    %{
      id: task.id,
      title: task.title,
      state_id: task.state_id
    }
  end

  defp loaded_field(assoc, field) when is_struct(assoc), do: Map.get(assoc, field)
  defp loaded_field(_, _), do: nil

  defp format_dt(nil), do: nil
  defp format_dt(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_dt(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
end
