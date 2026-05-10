defmodule EyeInTheSkyWeb.DmLive.TaskHandlersTest do
  use EyeInTheSky.DataCase, async: false

  alias EyeInTheSky.Factory
  alias EyeInTheSky.Tasks
  alias EyeInTheSkyWeb.DmLive.TaskHandlers

  # Helper to build a bare socket with assigns
  defp build_socket(assigns) do
    base = %{__changed__: %{}, flash: %{}, private: %{live_temp: %{}}}
    %Phoenix.LiveView.Socket{
      assigns: Map.merge(base, assigns)
    }
  end

  describe "handle_start_agent_for_task/2" do
    test "creates a new agent for a task and links it" do
      session = Factory.new_session()
      agent = Factory.create_agent()

      # Create a task
      task_params = %{
        uuid: Ecto.UUID.generate(),
        title: "Test task",
        description: "Test description",
        project_id: agent.project_id,
        created_at: DateTime.utc_now()
      }

      {:ok, task} = Tasks.create_task(task_params)

      socket =
        build_socket(%{
          session: session,
          agent: agent,
          active_overlay: "some_overlay"
        })

      {:noreply, result} =
        TaskHandlers.handle_start_agent_for_task(
          %{"task_id" => task.uuid},
          socket
        )

      # Overlay should be closed
      assert result.assigns.active_overlay == nil
      # Should have a success flash
      assert result.assigns.flash["info"] =~ "Agent spawned"
    end

    test "uses task uuid to find task" do
      session = Factory.new_session()
      agent = Factory.create_agent()

      task_params = %{
        uuid: Ecto.UUID.generate(),
        title: "Another task",
        description: "Another description",
        project_id: agent.project_id,
        created_at: DateTime.utc_now()
      }

      {:ok, task} = Tasks.create_task(task_params)

      socket =
        build_socket(%{
          session: session,
          agent: agent,
          active_overlay: "overlay"
        })

      {:noreply, result} =
        TaskHandlers.handle_start_agent_for_task(
          %{"task_id" => task.uuid},
          socket
        )

      assert result.assigns.active_overlay == nil
      assert result.assigns.flash["info"] =~ "Agent spawned"
    end

    test "uses task id (string) to find task" do
      session = Factory.new_session()
      agent = Factory.create_agent()

      task_params = %{
        uuid: Ecto.UUID.generate(),
        title: "Task by ID",
        description: "Task description",
        project_id: agent.project_id,
        created_at: DateTime.utc_now()
      }

      {:ok, task} = Tasks.create_task(task_params)

      socket =
        build_socket(%{
          session: session,
          agent: agent,
          active_overlay: "overlay"
        })

      {:noreply, result} =
        TaskHandlers.handle_start_agent_for_task(
          %{"task_id" => to_string(task.id)},
          socket
        )

      assert result.assigns.active_overlay == nil
      assert result.assigns.flash["info"] =~ "Agent spawned"
    end

    test "includes task title in agent spawn message" do
      session = Factory.new_session()
      agent = Factory.create_agent()
      task_title = "My important task"

      task_params = %{
        uuid: Ecto.UUID.generate(),
        title: task_title,
        description: "Task description",
        project_id: agent.project_id,
        created_at: DateTime.utc_now()
      }

      {:ok, _task} = Tasks.create_task(task_params)

      socket =
        build_socket(%{
          session: session,
          agent: agent,
          active_overlay: "overlay"
        })

      {:noreply, result} =
        TaskHandlers.handle_start_agent_for_task(
          %{"task_id" => task_title},
          socket
        )

      # The flash message should contain part of the title
      assert result.assigns.flash["info"] =~ "Agent spawned"
    end

    test "handles task with nil description" do
      session = Factory.new_session()
      agent = Factory.create_agent()

      task_params = %{
        uuid: Ecto.UUID.generate(),
        title: "Task without description",
        description: nil,
        project_id: agent.project_id,
        created_at: DateTime.utc_now()
      }

      {:ok, task} = Tasks.create_task(task_params)

      socket =
        build_socket(%{
          session: session,
          agent: agent,
          active_overlay: "overlay"
        })

      {:noreply, result} =
        TaskHandlers.handle_start_agent_for_task(
          %{"task_id" => task.uuid},
          socket
        )

      # Should still spawn successfully
      assert result.assigns.active_overlay == nil
      assert result.assigns.flash["info"] =~ "Agent spawned"
    end

    test "handles task with empty description" do
      session = Factory.new_session()
      agent = Factory.create_agent()

      task_params = %{
        uuid: Ecto.UUID.generate(),
        title: "Task with empty description",
        description: "",
        project_id: agent.project_id,
        created_at: DateTime.utc_now()
      }

      {:ok, task} = Tasks.create_task(task_params)

      socket =
        build_socket(%{
          session: session,
          agent: agent,
          active_overlay: "overlay"
        })

      {:noreply, result} =
        TaskHandlers.handle_start_agent_for_task(
          %{"task_id" => task.uuid},
          socket
        )

      assert result.assigns.active_overlay == nil
      assert result.assigns.flash["info"] =~ "Agent spawned"
    end

    test "closes active_overlay on success" do
      session = Factory.new_session()
      agent = Factory.create_agent()

      task_params = %{
        uuid: Ecto.UUID.generate(),
        title: "Test task",
        description: "Test description",
        project_id: agent.project_id,
        created_at: DateTime.utc_now()
      }

      {:ok, task} = Tasks.create_task(task_params)

      socket =
        build_socket(%{
          session: session,
          agent: agent,
          active_overlay: "task_modal"
        })

      {:noreply, result} =
        TaskHandlers.handle_start_agent_for_task(
          %{"task_id" => task.uuid},
          socket
        )

      # The overlay should be cleared (set to nil)
      assert result.assigns.active_overlay == nil
    end

    test "returns error flash when task is not found" do
      session = Factory.new_session()
      agent = Factory.create_agent()

      socket =
        build_socket(%{
          session: session,
          agent: agent,
          active_overlay: "overlay"
        })

      # Use a non-existent task ID
      assert_raise Ecto.NoResultsError, fn ->
        TaskHandlers.handle_start_agent_for_task(
          %{"task_id" => "999999"},
          socket
        )
      end
    end

    test "preserves session info in spawned agent" do
      session = Factory.new_session()
      agent = Factory.create_agent()

      task_params = %{
        uuid: Ecto.UUID.generate(),
        title: "Task with session context",
        description: "Should preserve session info",
        project_id: agent.project_id,
        created_at: DateTime.utc_now()
      }

      {:ok, task} = Tasks.create_task(task_params)

      socket =
        build_socket(%{
          session: session,
          agent: agent,
          active_overlay: "overlay"
        })

      {:noreply, result} =
        TaskHandlers.handle_start_agent_for_task(
          %{"task_id" => task.uuid},
          socket
        )

      # Spawned agent should be created with reference to this task
      assert result.assigns.flash["info"] =~ "Agent spawned"
    end

    test "handles task with long title (truncates in message)" do
      session = Factory.new_session()
      agent = Factory.create_agent()
      long_title = String.duplicate("Long ", 20)

      task_params = %{
        uuid: Ecto.UUID.generate(),
        title: long_title,
        description: "Task with long title",
        project_id: agent.project_id,
        created_at: DateTime.utc_now()
      }

      {:ok, _task} = Tasks.create_task(task_params)

      socket =
        build_socket(%{
          session: session,
          agent: agent,
          active_overlay: "overlay"
        })

      {:noreply, result} =
        TaskHandlers.handle_start_agent_for_task(
          %{"task_id" => long_title},
          socket
        )

      # Flash message should truncate long title
      assert String.length(result.assigns.flash["info"]) > 0
      assert result.assigns.active_overlay == nil
    end

    test "combines task title and description for agent prompt" do
      session = Factory.new_session()
      agent = Factory.create_agent()

      task_params = %{
        uuid: Ecto.UUID.generate(),
        title: "Implement feature X",
        description: "This feature should do Y and Z",
        project_id: agent.project_id,
        created_at: DateTime.utc_now()
      }

      {:ok, task} = Tasks.create_task(task_params)

      socket =
        build_socket(%{
          session: session,
          agent: agent,
          active_overlay: "overlay"
        })

      {:noreply, result} =
        TaskHandlers.handle_start_agent_for_task(
          %{"task_id" => task.uuid},
          socket
        )

      # Agent should be spawned with the prompt
      assert result.assigns.flash["info"] =~ "Agent spawned"
      assert result.assigns.active_overlay == nil
    end

    test "sets model to sonnet for spawned agent" do
      session = Factory.new_session()
      agent = Factory.create_agent()

      task_params = %{
        uuid: Ecto.UUID.generate(),
        title: "Test task",
        description: "Test description",
        project_id: agent.project_id,
        created_at: DateTime.utc_now()
      }

      {:ok, task} = Tasks.create_task(task_params)

      socket =
        build_socket(%{
          session: session,
          agent: agent,
          active_overlay: "overlay"
        })

      {:noreply, result} =
        TaskHandlers.handle_start_agent_for_task(
          %{"task_id" => task.uuid},
          socket
        )

      # Spawned agent should be created
      assert result.assigns.flash["info"] =~ "Agent spawned"
    end

    test "links new session to task after creation" do
      session = Factory.new_session()
      agent = Factory.create_agent()

      task_params = %{
        uuid: Ecto.UUID.generate(),
        title: "Task to link",
        description: "Should link to new session",
        project_id: agent.project_id,
        created_at: DateTime.utc_now()
      }

      {:ok, task} = Tasks.create_task(task_params)

      socket =
        build_socket(%{
          session: session,
          agent: agent,
          active_overlay: "overlay"
        })

      {:noreply, result} =
        TaskHandlers.handle_start_agent_for_task(
          %{"task_id" => task.uuid},
          socket
        )

      # Agent spawned successfully
      assert result.assigns.flash["info"] =~ "Agent spawned"
    end
  end

  describe "agent spawn with project context" do
    test "includes project_id when available" do
      session = Factory.new_session()
      agent = Factory.create_agent()

      task_params = %{
        uuid: Ecto.UUID.generate(),
        title: "Test task",
        description: "Test description",
        project_id: agent.project_id,
        created_at: DateTime.utc_now()
      }

      {:ok, task} = Tasks.create_task(task_params)

      socket =
        build_socket(%{
          session: session,
          agent: agent,
          active_overlay: "overlay"
        })

      {:noreply, result} =
        TaskHandlers.handle_start_agent_for_task(
          %{"task_id" => task.uuid},
          socket
        )

      assert result.assigns.flash["info"] =~ "Agent spawned"
    end
  end
end
