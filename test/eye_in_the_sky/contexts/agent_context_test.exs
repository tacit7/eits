defmodule EyeInTheSky.Contexts.AgentContextTest do
  use EyeInTheSky.DataCase, async: true

  import EyeInTheSky.Factory

  alias EyeInTheSky.Contexts.AgentContext
  alias EyeInTheSky.Repo

  describe "changeset/2" do
    setup do
      project = project_fixture()
      agent = create_agent()
      %{project: project, agent: agent}
    end

    test "valid attrs produce a valid changeset", %{project: project, agent: agent} do
      attrs = %{agent_id: agent.id, project_id: project.id, context: "some context"}
      changeset = AgentContext.changeset(%AgentContext{}, attrs)
      assert changeset.valid?
    end

    test "missing agent_id is invalid", %{project: project} do
      attrs = %{project_id: project.id, context: "ctx"}
      changeset = AgentContext.changeset(%AgentContext{}, attrs)
      refute changeset.valid?
      assert %{agent_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "missing project_id is invalid", %{agent: agent} do
      attrs = %{agent_id: agent.id, context: "ctx"}
      changeset = AgentContext.changeset(%AgentContext{}, attrs)
      refute changeset.valid?
      assert %{project_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "missing context is invalid", %{project: project, agent: agent} do
      attrs = %{agent_id: agent.id, project_id: project.id}
      changeset = AgentContext.changeset(%AgentContext{}, attrs)
      refute changeset.valid?
      assert %{context: ["can't be blank"]} = errors_on(changeset)
    end

    test "missing all required fields is invalid" do
      changeset = AgentContext.changeset(%AgentContext{}, %{})
      refute changeset.valid?
      errors = errors_on(changeset)
      assert Map.has_key?(errors, :agent_id)
      assert Map.has_key?(errors, :project_id)
      assert Map.has_key?(errors, :context)
    end

    test "optional updated_at can be set", %{project: project, agent: agent} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      attrs = %{agent_id: agent.id, project_id: project.id, context: "ctx", updated_at: now}
      changeset = AgentContext.changeset(%AgentContext{}, attrs)
      assert changeset.valid?
      assert get_change(changeset, :updated_at) == now
    end

    test "unique constraint prevents duplicate [agent_id, project_id]", %{
      project: project,
      agent: agent
    } do
      attrs = %{agent_id: agent.id, project_id: project.id, context: "first"}

      %AgentContext{}
      |> AgentContext.changeset(attrs)
      |> Repo.insert!()

      {:error, changeset} =
        %AgentContext{}
        |> AgentContext.changeset(%{attrs | context: "second"})
        |> Repo.insert()

      refute changeset.valid?
      assert %{agent_id: [_]} = errors_on(changeset)
    end
  end
end
