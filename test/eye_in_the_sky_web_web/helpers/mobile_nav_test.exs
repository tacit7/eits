defmodule EyeInTheSkyWebWeb.Helpers.MobileNavTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWebWeb.Helpers.MobileNav

  describe "active_tab_for_path/1" do
    test "returns :sessions for root path" do
      assert MobileNav.active_tab_for_path("/") == :sessions
    end

    test "returns :sessions for /sessions" do
      assert MobileNav.active_tab_for_path("/sessions") == :sessions
    end

    test "returns :sessions for nil (fallback)" do
      assert MobileNav.active_tab_for_path(nil) == :sessions
    end

    test "returns :tasks for /tasks" do
      assert MobileNav.active_tab_for_path("/tasks") == :tasks
    end

    test "returns :notes for /notes" do
      assert MobileNav.active_tab_for_path("/notes") == :notes
    end

    test "returns :project for /projects/:id" do
      assert MobileNav.active_tab_for_path("/projects/1") == :project
      assert MobileNav.active_tab_for_path("/projects/42") == :project
      assert MobileNav.active_tab_for_path("/projects/9999") == :project
    end

    test "returns :project for all /projects/:id/* sub-routes" do
      assert MobileNav.active_tab_for_path("/projects/1/sessions") == :project
      assert MobileNav.active_tab_for_path("/projects/1/tasks") == :project
      assert MobileNav.active_tab_for_path("/projects/1/kanban") == :project
      assert MobileNav.active_tab_for_path("/projects/1/notes") == :project
      assert MobileNav.active_tab_for_path("/projects/1/files") == :project
      assert MobileNav.active_tab_for_path("/projects/1/config") == :project
      assert MobileNav.active_tab_for_path("/projects/1/agents") == :project
      assert MobileNav.active_tab_for_path("/projects/1/jobs") == :project
      assert MobileNav.active_tab_for_path("/projects/1/prompts") == :project
    end

    test "returns :none for DM routes without project context" do
      assert MobileNav.active_tab_for_path("/dm/123") == :none
      assert MobileNav.active_tab_for_path("/dm/abc-uuid-123") == :none
    end

    test "returns :none for unrelated top-level routes" do
      assert MobileNav.active_tab_for_path("/usage") == :none
      assert MobileNav.active_tab_for_path("/prompts") == :none
      assert MobileNav.active_tab_for_path("/settings") == :none
      assert MobileNav.active_tab_for_path("/config") == :none
      assert MobileNav.active_tab_for_path("/jobs") == :none
      assert MobileNav.active_tab_for_path("/notifications") == :none
      assert MobileNav.active_tab_for_path("/skills") == :none
      assert MobileNav.active_tab_for_path("/chat") == :none
    end

    test "does not match /projects without numeric id" do
      assert MobileNav.active_tab_for_path("/projects") == :none
      assert MobileNav.active_tab_for_path("/projects/notanid/sessions") == :none
    end
  end

  describe "project_route?/1" do
    test "returns true for /projects/:id" do
      assert MobileNav.project_route?("/projects/1") == true
      assert MobileNav.project_route?("/projects/123") == true
    end

    test "returns true for all /projects/:id/* routes" do
      assert MobileNav.project_route?("/projects/1/sessions") == true
      assert MobileNav.project_route?("/projects/1/kanban") == true
    end

    test "returns false for non-project routes" do
      refute MobileNav.project_route?("/")
      refute MobileNav.project_route?("/tasks")
      refute MobileNav.project_route?("/projects")
      refute MobileNav.project_route?("/projects/notanid")
      refute MobileNav.project_route?("/dm/123")
    end

    test "returns false for nil" do
      refute MobileNav.project_route?(nil)
    end
  end

  describe "project_id_from_path/1" do
    test "extracts project ID from /projects/:id" do
      assert MobileNav.project_id_from_path("/projects/5") == 5
      assert MobileNav.project_id_from_path("/projects/42") == 42
    end

    test "extracts project ID from sub-routes" do
      assert MobileNav.project_id_from_path("/projects/7/sessions") == 7
      assert MobileNav.project_id_from_path("/projects/3/kanban") == 3
      assert MobileNav.project_id_from_path("/projects/99/tasks") == 99
    end

    test "returns nil for non-project routes" do
      assert MobileNav.project_id_from_path("/tasks") == nil
      assert MobileNav.project_id_from_path("/") == nil
      assert MobileNav.project_id_from_path(nil) == nil
    end

    test "returns nil for non-numeric project id" do
      assert MobileNav.project_id_from_path("/projects/abc") == nil
      assert MobileNav.project_id_from_path("/projects/notanid/sessions") == nil
    end
  end
end
