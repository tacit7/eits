defmodule EyeInTheSkyWeb.Components.Rail.FilterActionsTest do
  use EyeInTheSkyWeb.ConnCase

  alias EyeInTheSkyWeb.Components.Rail.FilterActions

  setup do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        session_sort: :recent,
        session_show: :active,
        session_name_filter: "",
        session_scope: :current,
        sidebar_project: %{id: 1},
        task_search: "",
        task_state_filter: nil,
        note_search: "",
        note_parent_type: nil,
        agent_search: "",
        agent_scope: "all",
        skill_search: "",
        skill_scope: "all",
        team_search: "",
        team_status: "active",
        prompt_search: "",
        prompt_scope: "all",
        flyout_sessions: [],
        flyout_tasks: [],
        flyout_notes: [],
        flyout_agents: [],
        flyout_skills: [],
        flyout_teams: [],
        flyout_prompts: [],
        session_project_visible: %{},
        session_project_collapsed: MapSet.new()
      },
      private: %{live_temp: %{}}
    }

    {:ok, socket: socket}
  end

  describe "handle_set_session_sort/2" do
    test "updates session_sort assign", %{socket: socket} do
      params = %{"sort" => "name"}

      {:noreply, updated_socket} = FilterActions.handle_set_session_sort(params, socket)

      # Sort should be updated
      assert is_map_key(updated_socket.assigns, :session_sort)
    end
  end

  describe "handle_update_session_name_filter/2" do
    test "updates session_name_filter", %{socket: socket} do
      params = %{"value" => "test-session"}

      {:noreply, updated_socket} = FilterActions.handle_update_session_name_filter(params, socket)

      assert updated_socket.assigns.session_name_filter == "test-session"
    end
  end

  describe "handle_set_session_show/2" do
    test "updates session_show with valid value", %{socket: socket} do
      params = %{"show" => "completed"}

      {:noreply, updated_socket} = FilterActions.handle_set_session_show(params, socket)

      # show should be updated
      assert is_map_key(updated_socket.assigns, :session_show)
    end
  end

  describe "handle_set_session_scope/2" do
    test "sets scope to :all when scope_str is 'all'", %{socket: socket} do
      params = %{"scope" => "all"}

      {:noreply, updated_socket} = FilterActions.handle_set_session_scope(params, socket)

      assert updated_socket.assigns.session_scope == :all
    end

    test "sets scope to :current when scope_str is not 'all'", %{socket: socket} do
      params = %{"scope" => "current"}

      {:noreply, updated_socket} = FilterActions.handle_set_session_scope(params, socket)

      assert updated_socket.assigns.session_scope == :current
      assert updated_socket.assigns.sidebar_project == %{id: 1}
    end

    test "resets session_project_visible and session_project_collapsed", %{socket: socket} do
      socket = %{
        socket
        | assigns: %{
            socket.assigns
            | session_project_visible: %{1 => true},
              session_project_collapsed: MapSet.new([1])
          }
      }

      params = %{"scope" => "all"}

      {:noreply, updated_socket} = FilterActions.handle_set_session_scope(params, socket)

      assert updated_socket.assigns.session_project_visible == %{}
      assert updated_socket.assigns.session_project_collapsed == MapSet.new()
    end
  end

  describe "handle_update_task_search/2" do
    test "updates task_search", %{socket: socket} do
      params = %{"value" => "fix bug"}

      {:noreply, updated_socket} = FilterActions.handle_update_task_search(params, socket)

      assert updated_socket.assigns.task_search == "fix bug"
    end
  end

  describe "handle_set_task_state_filter/2" do
    test "updates task_state_filter", %{socket: socket} do
      params = %{"state" => "in_progress"}

      {:noreply, updated_socket} = FilterActions.handle_set_task_state_filter(params, socket)

      # state_id should be parsed and set
      assert is_map_key(updated_socket.assigns, :task_state_filter)
    end
  end

  describe "handle_update_note_search/2" do
    test "updates note_search", %{socket: socket} do
      params = %{"value" => "important note"}

      {:noreply, updated_socket} = FilterActions.handle_update_note_search(params, socket)

      assert updated_socket.assigns.note_search == "important note"
    end
  end

  describe "handle_set_note_parent_type/2" do
    test "sets note_parent_type to nil when 'all'", %{socket: socket} do
      socket = %{socket | assigns: %{socket.assigns | note_parent_type: "project"}}

      params = %{"type" => "all"}

      {:noreply, updated_socket} = FilterActions.handle_set_note_parent_type(params, socket)

      assert updated_socket.assigns.note_parent_type == nil
    end

    test "sets note_parent_type to type value when not 'all'", %{socket: socket} do
      params = %{"type" => "session"}

      {:noreply, updated_socket} = FilterActions.handle_set_note_parent_type(params, socket)

      assert updated_socket.assigns.note_parent_type == "session"
    end
  end

  describe "handle_update_agent_search/2" do
    test "updates agent_search", %{socket: socket} do
      params = %{"value" => "code-reviewer"}

      {:noreply, updated_socket} = FilterActions.handle_update_agent_search(params, socket)

      assert updated_socket.assigns.agent_search == "code-reviewer"
    end
  end

  describe "handle_set_agent_scope/2" do
    test "updates agent_scope", %{socket: socket} do
      params = %{"scope" => "project"}

      {:noreply, updated_socket} = FilterActions.handle_set_agent_scope(params, socket)

      assert updated_socket.assigns.agent_scope == "project"
    end
  end

  describe "handle_update_skill_search/2" do
    test "updates skill_search", %{socket: socket} do
      params = %{"value" => "testing"}

      {:noreply, updated_socket} = FilterActions.handle_update_skill_search(params, socket)

      assert updated_socket.assigns.skill_search == "testing"
    end
  end

  describe "handle_set_skill_scope/2" do
    test "updates skill_scope", %{socket: socket} do
      params = %{"scope" => "global"}

      {:noreply, updated_socket} = FilterActions.handle_set_skill_scope(params, socket)

      assert updated_socket.assigns.skill_scope == "global"
    end
  end

  describe "handle_update_team_search/2" do
    test "updates team_search", %{socket: socket} do
      params = %{"value" => "refactoring"}

      {:noreply, updated_socket} = FilterActions.handle_update_team_search(params, socket)

      assert updated_socket.assigns.team_search == "refactoring"
    end
  end

  describe "handle_set_team_status/2" do
    test "updates team_status", %{socket: socket} do
      params = %{"status" => "completed"}

      {:noreply, updated_socket} = FilterActions.handle_set_team_status(params, socket)

      assert updated_socket.assigns.team_status == "completed"
    end
  end

  describe "handle_update_prompt_search/2" do
    test "updates prompt_search", %{socket: socket} do
      params = %{"value" => "system prompt"}

      {:noreply, updated_socket} = FilterActions.handle_update_prompt_search(params, socket)

      assert updated_socket.assigns.prompt_search == "system prompt"
    end
  end

  describe "handle_set_prompt_scope/2" do
    test "updates prompt_scope", %{socket: socket} do
      params = %{"scope" => "project"}

      {:noreply, updated_socket} = FilterActions.handle_set_prompt_scope(params, socket)

      assert updated_socket.assigns.prompt_scope == "project"
    end
  end
end
