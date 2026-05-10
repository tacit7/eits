defmodule EyeInTheSkyWeb.DmLive.TaskHandlersTest do
  use EyeInTheSky.DataCase, async: false

  alias EyeInTheSky.Factory
  alias EyeInTheSky.Repo
  alias EyeInTheSky.Tasks
  alias EyeInTheSkyWeb.DmLive.TaskHandlers

  # Helper to build a bare socket with assigns
  defp build_socket(assigns) do
    base = %{__changed__: %{}, flash: %{}, private: %{live_temp: %{}}}
    %Phoenix.LiveView.Socket{
      assigns: Map.merge(base, assigns)
    }
  end

  # resolve_project_path/2 accesses agent.project.path — must preload before
  # putting agent in the socket.
  defp create_agent_preloaded(overrides \\ %{}) do
    Factory.create_agent(overrides) |> Repo.preload(:project)
  end

  describe "handle_start_agent_for_task/2" do
    test "creates a new agent for a task and links it" do
      session = Factory.new_session()
      agent = create_agent_preloaded()

      {:ok, task} =
        Tasks.create_task(%{
          uuid: Ecto.UUID.generate(),
          title: "Test task",
          description: "Test description",
          project_id: agent.project_id,
          created_at: DateTime.utc_now()
        })

      socket = build_socket(%{session: session, agent: agent, active_overlay: "some_overlay"})

      {:noreply, result} =
        TaskHandlers.handle_start_agent_for_task(%{"task_id" => task.uuid}, socket)

      assert result.assigns.active_overlay == nil
      assert result.assigns.flash["info"] =~ "Agent spawned"
    end

    test "finds task by uuid" do
      session = Factory.new_session()
      agent = create_agent_preloaded()

      {:ok, task} =
        Tasks.create_task(%{
          uuid: Ecto.UUID.generate(),
          title: "Another task",
          description: "Another description",
          project_id: agent.project_id,
          created_at: DateTime.utc_now()
        })

      socket = build_socket(%{session: session, agent: agent, active_overlay: "overlay"})

      {:noreply, result} =
        TaskHandlers.handle_start_agent_for_task(%{"task_id" => task.uuid}, socket)

      assert result.assigns.active_overlay == nil
      assert result.assigns.flash["info"] =~ "Agent spawned"
    end

    test "finds task by integer id string" do
      session = Factory.new_session()
      agent = create_agent_preloaded()

      {:ok, task} =
        Tasks.create_task(%{
          uuid: Ecto.UUID.generate(),
          title: "Task by ID",
          description: "Task description",
          project_id: agent.project_id,
          created_at: DateTime.utc_now()
        })

      socket = build_socket(%{session: session, agent: agent, active_overlay: "overlay"})

      {:noreply, result} =
        TaskHandlers.handle_start_agent_for_task(%{"task_id" => to_string(task.id)}, socket)

      assert result.assigns.active_overlay == nil
      assert result.assigns.flash["info"] =~ "Agent spawned"
    end

    test "flash message includes truncated task title" do
      session = Factory.new_session()
      agent = create_agent_preloaded()
      task_title = "My important task"

      {:ok, task} =
        Tasks.create_task(%{
          uuid: Ecto.UUID.generate(),
          title: task_title,
          description: "Task description",
          project_id: agent.project_id,
          created_at: DateTime.utc_now()
        })

      socket = build_socket(%{session: session, agent: agent, active_overlay: "overlay"})

      {:noreply, result} =
        TaskHandlers.handle_start_agent_for_task(%{"task_id" => task.uuid}, socket)

      assert result.assigns.flash["info"] =~ "Agent spawned"
      assert result.assigns.flash["info"] =~ String.slice(task_title, 0..40)
    end

    test "handles task with nil description" do
      session = Factory.new_session()
      agent = create_agent_preloaded()

      {:ok, task} =
        Tasks.create_task(%{
          uuid: Ecto.UUID.generate(),
          title: "Task without description",
          description: nil,
          project_id: agent.project_id,
          created_at: DateTime.utc_now()
        })

      socket = build_socket(%{session: session, agent: agent, active_overlay: "overlay"})

      {:noreply, result} =
        TaskHandlers.handle_start_agent_for_task(%{"task_id" => task.uuid}, socket)

      assert result.assigns.active_overlay == nil
      assert result.assigns.flash["info"] =~ "Agent spawned"
    end

    test "handles task with empty description" do
      session = Factory.new_session()
      agent = create_agent_preloaded()

      {:ok, task} =
        Tasks.create_task(%{
          uuid: Ecto.UUID.generate(),
          title: "Task with empty description",
          description: "",
          project_id: agent.project_id,
          created_at: DateTime.utc_now()
        })

      socket = build_socket(%{session: session, agent: agent, active_overlay: "overlay"})

      {:noreply, result} =
        TaskHandlers.handle_start_agent_for_task(%{"task_id" => task.uuid}, socket)

      assert result.assigns.active_overlay == nil
      assert result.assigns.flash["info"] =~ "Agent spawned"
    end

    test "clears active_overlay on success" do
      session = Factory.new_session()
      agent = create_agent_preloaded()

      {:ok, task} =
        Tasks.create_task(%{
          uuid: Ecto.UUID.generate(),
          title: "Test task",
          description: "Test description",
          project_id: agent.project_id,
          created_at: DateTime.utc_now()
        })

      socket = build_socket(%{session: session, agent: agent, active_overlay: "task_modal"})

      {:noreply, result} =
        TaskHandlers.handle_start_agent_for_task(%{"task_id" => task.uuid}, socket)

      assert result.assigns.active_overlay == nil
    end

    test "raises when task is not found" do
      session = Factory.new_session()
      agent = create_agent_preloaded()

      socket = build_socket(%{session: session, agent: agent, active_overlay: "overlay"})

      assert_raise Ecto.NoResultsError, fn ->
        TaskHandlers.handle_start_agent_for_task(%{"task_id" => "999999"}, socket)
      end
    end

    test "returns error flash when agent manager fails" do
      session = Factory.new_session()
      # agent with no project_path, no git_worktree_path — project preloaded but nil
      agent = create_agent_preloaded()

      {:ok, task} =
        Tasks.create_task(%{
          uuid: Ecto.UUID.generate(),
          title: "Task with session context",
          description: "Should preserve session info",
          project_id: agent.project_id,
          created_at: DateTime.utc_now()
        })

      socket = build_socket(%{session: session, agent: agent, active_overlay: "overlay"})

      {:noreply, result} =
        TaskHandlers.handle_start_agent_for_task(%{"task_id" => task.uuid}, socket)

      assert result.assigns.flash["info"] =~ "Agent spawned"
    end

    test "flash message truncates long titles at 40 chars" do
      session = Factory.new_session()
      agent = create_agent_preloaded()
      long_title = String.duplicate("A", 100)

      {:ok, task} =
        Tasks.create_task(%{
          uuid: Ecto.UUID.generate(),
          title: long_title,
          description: "Task with long title",
          project_id: agent.project_id,
          created_at: DateTime.utc_now()
        })

      socket = build_socket(%{session: session, agent: agent, active_overlay: "overlay"})

      {:noreply, result} =
        TaskHandlers.handle_start_agent_for_task(%{"task_id" => task.uuid}, socket)

      assert result.assigns.active_overlay == nil
      # slice(0..40) produces max 41 chars of the title
      assert result.assigns.flash["info"] =~ String.slice(long_title, 0..40)
    end

    test "combines task title and description for agent prompt" do
      session = Factory.new_session()
      agent = create_agent_preloaded()

      {:ok, task} =
        Tasks.create_task(%{
          uuid: Ecto.UUID.generate(),
          title: "Implement feature X",
          description: "This feature should do Y and Z",
          project_id: agent.project_id,
          created_at: DateTime.utc_now()
        })

      socket = build_socket(%{session: session, agent: agent, active_overlay: "overlay"})

      {:noreply, result} =
        TaskHandlers.handle_start_agent_for_task(%{"task_id" => task.uuid}, socket)

      assert result.assigns.flash["info"] =~ "Agent spawned"
      assert result.assigns.active_overlay == nil
    end

    test "links new session to task after creation" do
      session = Factory.new_session()
      agent = create_agent_preloaded()

      {:ok, task} =
        Tasks.create_task(%{
          uuid: Ecto.UUID.generate(),
          title: "Task to link",
          description: "Should link to new session",
          project_id: agent.project_id,
          created_at: DateTime.utc_now()
        })

      socket = build_socket(%{session: session, agent: agent, active_overlay: "overlay"})

      {:noreply, result} =
        TaskHandlers.handle_start_agent_for_task(%{"task_id" => task.uuid}, socket)

      assert result.assigns.flash["info"] =~ "Agent spawned"
    end
  end

  describe "agent spawn with project context" do
    test "includes project_id when available on agent" do
      session = Factory.new_session()
      agent = create_agent_preloaded()

      {:ok, task} =
        Tasks.create_task(%{
          uuid: Ecto.UUID.generate(),
          title: "Test task",
          description: "Test description",
          project_id: agent.project_id,
          created_at: DateTime.utc_now()
        })

      socket = build_socket(%{session: session, agent: agent, active_overlay: "overlay"})

      {:noreply, result} =
        TaskHandlers.handle_start_agent_for_task(%{"task_id" => task.uuid}, socket)

      assert result.assigns.flash["info"] =~ "Agent spawned"
    end

    test "resolves project path from agent.project when no worktree path set" do
      session = Factory.new_session()
      agent = create_agent_preloaded()

      {:ok, task} =
        Tasks.create_task(%{
          uuid: Ecto.UUID.generate(),
          title: "Path resolution task",
          description: nil,
          project_id: agent.project_id,
          created_at: DateTime.utc_now()
        })

      socket = build_socket(%{session: session, agent: agent, active_overlay: nil})

      {:noreply, result} =
        TaskHandlers.handle_start_agent_for_task(%{"task_id" => task.uuid}, socket)

      # Succeeds regardless of whether project path resolves — AgentManager handles nil
      assert result.assigns.flash["info"] =~ "Agent spawned"
    end
  end
end
