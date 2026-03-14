defmodule EyeInTheSkyWebWeb.Presenters.ApiPresenter do
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
    %{id: note.id, title: note.title, body: note.body, starred: note.starred || 0}
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
    %{id: session.id, uuid: session.uuid, description: session.description, status: session.status}
  end
end
