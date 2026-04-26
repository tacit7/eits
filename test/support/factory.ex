defmodule EyeInTheSky.Factory do
  @moduledoc """
  Shared test factory helpers for controller and MCP tool tests.
  """

  alias EyeInTheSky.{Accounts, Agents, Projects, Sessions, Workspaces}

  def user_fixture(attrs \\ %{}) do
    username = Map.get(attrs, :username, "user_#{System.unique_integer([:positive])}")
    {:ok, user} = Accounts.get_or_create_user(username)
    user
  end

  def uniq, do: System.unique_integer([:positive])

  @doc """
  Creates a project with a provisioned user + default workspace.
  Accepts the same attrs as `Projects.create_project/1`.
  Always injects workspace_id — callers do not need to supply it.
  """
  def project_fixture(attrs \\ %{}) do
    user = user_fixture()
    workspace = Workspaces.default_workspace_for_user!(user)

    n = uniq()

    defaults = %{
      name: "Test project #{n}",
      path: "/tmp/test_project_#{n}",
      slug: "test-project-#{n}"
    }

    {:ok, project} =
      defaults
      |> Map.merge(Map.new(attrs))
      |> Map.put(:workspace_id, workspace.id)
      |> Projects.create_project()

    project
  end

  def create_agent(overrides \\ %{}) do
    {:ok, agent} =
      Agents.create_agent(
        Map.merge(
          %{
            uuid: Ecto.UUID.generate(),
            description: "Test agent #{uniq()}",
            source: "test"
          },
          overrides
        )
      )

    agent
  end

  def create_session(agent, overrides \\ %{}) do
    {:ok, session} =
      Sessions.create_session(
        Map.merge(
          %{
            uuid: Ecto.UUID.generate(),
            agent_id: agent.id,
            name: "Test session #{uniq()}",
            status: "working",
            started_at: DateTime.utc_now() |> DateTime.to_iso8601()
          },
          overrides
        )
      )

    session
  end

  def new_session do
    agent = create_agent()
    create_session(agent)
  end
end
