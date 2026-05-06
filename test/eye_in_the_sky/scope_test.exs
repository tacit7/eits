defmodule EyeInTheSky.ScopeTest do
  use EyeInTheSky.DataCase, async: true

  import EyeInTheSky.Factory

  alias EyeInTheSky.{Notes, Projects, Scope, Sessions, Tasks, Workspaces}

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp setup_workspace_and_project(_ctx \\ %{}) do
    user = user_fixture()
    workspace = Workspaces.default_workspace_for_user!(user)

    {:ok, project} =
      Projects.create_project(%{name: "scope-test-#{uniq()}", workspace_id: workspace.id})

    %{user: user, workspace: workspace, project: project}
  end

  defp setup_second_project(workspace) do
    {:ok, project} =
      Projects.create_project(%{name: "scope-test-other-#{uniq()}", workspace_id: workspace.id})

    project
  end

  # ---------------------------------------------------------------------------
  # Scope struct
  # ---------------------------------------------------------------------------

  describe "Scope.for_workspace/2" do
    test "builds a workspace scope" do
      ctx = setup_workspace_and_project()
      scope = Scope.for_workspace(ctx.user, ctx.workspace)

      assert scope.type == :workspace
      assert scope.user_id == ctx.user.id
      assert scope.workspace_id == ctx.workspace.id
      assert scope.workspace == ctx.workspace
      assert scope.project_id == nil
      assert scope.project == nil
    end
  end

  describe "Scope.for_project/3" do
    test "builds a project scope" do
      ctx = setup_workspace_and_project()
      scope = Scope.for_project(ctx.user, ctx.workspace, ctx.project)

      assert scope.type == :project
      assert scope.user_id == ctx.user.id
      assert scope.workspace_id == ctx.workspace.id
      assert scope.project_id == ctx.project.id
      assert scope.project == ctx.project
    end
  end

  describe "Scope.workspace?/1 and Scope.project?/1" do
    test "predicates return correct booleans" do
      ctx = setup_workspace_and_project()
      ws_scope = Scope.for_workspace(ctx.user, ctx.workspace)
      proj_scope = Scope.for_project(ctx.user, ctx.workspace, ctx.project)

      assert Scope.workspace?(ws_scope) == true
      assert Scope.workspace?(proj_scope) == false
      assert Scope.project?(proj_scope) == true
      assert Scope.project?(ws_scope) == false
    end
  end

  # ---------------------------------------------------------------------------
  # Sessions scope queries
  # ---------------------------------------------------------------------------

  describe "Sessions.list_sessions_for_scope/2" do
    test "project scope returns only sessions for that project" do
      ctx = setup_workspace_and_project()
      other = setup_second_project(ctx.workspace)

      agent = create_agent()
      s1 = create_session(agent, %{project_id: ctx.project.id, status: "working"})
      s2 = create_session(agent, %{project_id: other.id, status: "working"})

      scope = Scope.for_project(ctx.user, ctx.workspace, ctx.project)
      results = Sessions.list_sessions_for_scope(scope)

      ids = Enum.map(results, & &1.id)
      assert s1.id in ids
      refute s2.id in ids
    end

    test "workspace scope returns sessions across all projects in workspace" do
      ctx = setup_workspace_and_project()
      other = setup_second_project(ctx.workspace)

      agent = create_agent()
      s1 = create_session(agent, %{project_id: ctx.project.id, status: "working"})
      s2 = create_session(agent, %{project_id: other.id, status: "working"})

      scope = Scope.for_workspace(ctx.user, ctx.workspace)
      results = Sessions.list_sessions_for_scope(scope)

      ids = Enum.map(results, & &1.id)
      assert s1.id in ids
      assert s2.id in ids
    end

    test "workspace scope excludes sessions from other workspaces" do
      ctx = setup_workspace_and_project()

      # Second workspace with its own project
      other_user = user_fixture()
      other_ws = Workspaces.default_workspace_for_user!(other_user)

      {:ok, other_proj} =
        Projects.create_project(%{name: "other-ws-proj-#{uniq()}", workspace_id: other_ws.id})

      agent = create_agent()
      other_session = create_session(agent, %{project_id: other_proj.id, status: "working"})
      mine = create_session(agent, %{project_id: ctx.project.id, status: "working"})

      scope = Scope.for_workspace(ctx.user, ctx.workspace)
      results = Sessions.list_sessions_for_scope(scope)

      ids = Enum.map(results, & &1.id)
      assert mine.id in ids
      refute other_session.id in ids
    end
  end

  # ---------------------------------------------------------------------------
  # Tasks scope queries
  # ---------------------------------------------------------------------------

  describe "Tasks.list_tasks_for_scope/2" do
    test "project scope returns only tasks for that project" do
      ctx = setup_workspace_and_project()
      other = setup_second_project(ctx.workspace)

      {:ok, t1} = Tasks.create_task(%{title: "mine", project_id: ctx.project.id, state_id: 1})
      {:ok, _t2} = Tasks.create_task(%{title: "theirs", project_id: other.id, state_id: 1})

      scope = Scope.for_project(ctx.user, ctx.workspace, ctx.project)
      results = Tasks.list_tasks_for_scope(scope)

      ids = Enum.map(results, & &1.id)
      assert t1.id in ids
      refute Enum.any?(results, &(&1.project_id == other.id))
    end

    test "workspace scope returns tasks across all projects in workspace" do
      ctx = setup_workspace_and_project()
      other = setup_second_project(ctx.workspace)

      {:ok, t1} = Tasks.create_task(%{title: "p1 task", project_id: ctx.project.id, state_id: 1})
      {:ok, t2} = Tasks.create_task(%{title: "p2 task", project_id: other.id, state_id: 1})

      scope = Scope.for_workspace(ctx.user, ctx.workspace)
      results = Tasks.list_tasks_for_scope(scope)

      ids = Enum.map(results, & &1.id)
      assert t1.id in ids
      assert t2.id in ids
    end
  end

  # ---------------------------------------------------------------------------
  # Notes scope queries
  # ---------------------------------------------------------------------------

  describe "Notes.list_notes_for_scope/2" do
    test "project scope returns project notes for that project" do
      ctx = setup_workspace_and_project()
      other = setup_second_project(ctx.workspace)

      {:ok, n1} =
        Notes.create_note(%{
          parent_type: "project",
          parent_id: to_string(ctx.project.id),
          body: "mine"
        })

      {:ok, _n2} =
        Notes.create_note(%{
          parent_type: "project",
          parent_id: to_string(other.id),
          body: "theirs"
        })

      scope = Scope.for_project(ctx.user, ctx.workspace, ctx.project)
      results = Notes.list_notes_for_scope(scope)

      ids = Enum.map(results, & &1.id)
      assert n1.id in ids
      refute Enum.any?(results, &(&1.parent_id == to_string(other.id)))
    end

    test "workspace scope returns project notes across all projects in workspace" do
      ctx = setup_workspace_and_project()
      other = setup_second_project(ctx.workspace)

      {:ok, n1} =
        Notes.create_note(%{
          parent_type: "project",
          parent_id: to_string(ctx.project.id),
          body: "p1 note"
        })

      {:ok, n2} =
        Notes.create_note(%{
          parent_type: "project",
          parent_id: to_string(other.id),
          body: "p2 note"
        })

      scope = Scope.for_workspace(ctx.user, ctx.workspace)
      results = Notes.list_notes_for_scope(scope)

      ids = Enum.map(results, & &1.id)
      assert n1.id in ids
      assert n2.id in ids
    end

    test "workspace scope excludes notes from other workspaces" do
      ctx = setup_workspace_and_project()

      other_user = user_fixture()
      other_ws = Workspaces.default_workspace_for_user!(other_user)

      {:ok, other_proj} =
        Projects.create_project(%{name: "other-ws-#{uniq()}", workspace_id: other_ws.id})

      {:ok, mine} =
        Notes.create_note(%{
          parent_type: "project",
          parent_id: to_string(ctx.project.id),
          body: "mine"
        })

      {:ok, theirs} =
        Notes.create_note(%{
          parent_type: "project",
          parent_id: to_string(other_proj.id),
          body: "theirs"
        })

      scope = Scope.for_workspace(ctx.user, ctx.workspace)
      results = Notes.list_notes_for_scope(scope)

      ids = Enum.map(results, & &1.id)
      assert mine.id in ids
      refute theirs.id in ids
    end
  end
end
