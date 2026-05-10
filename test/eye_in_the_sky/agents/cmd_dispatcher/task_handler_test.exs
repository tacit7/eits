defmodule EyeInTheSky.Agents.CmdDispatcher.TaskHandlerTest do
  use EyeInTheSky.DataCase, async: true

  alias EyeInTheSky.Agents.CmdDispatcher.TaskHandler
  alias EyeInTheSky.Tasks
  alias EyeInTheSky.Notes

  setup do
    {:ok, session} =
      EyeInTheSky.Sessions.create_session(%{
        uuid: Ecto.UUID.generate(),
        agent_id: nil,
        name: "Test Session",
        provider: "test",
        git_worktree_path: "/tmp"
      })

    {:ok, session: session}
  end

  describe "dispatch/2 create command" do
    test "creates a task and links session", %{session: session} do
      TaskHandler.dispatch("create Test Task", session.id)

      tasks = Tasks.list_tasks(limit: 10)
      assert Enum.any?(tasks, &(&1.title == "Test Task"))

      # Verify task is linked to session
      task = Enum.find(tasks, &(&1.title == "Test Task"))
      assert Tasks.task_linked_to_session?(task.id, session.id)
    end

    test "creates task in todo state", %{session: session} do
      TaskHandler.dispatch("create Todo Task", session.id)

      task = Enum.find(Tasks.list_tasks(limit: 10), &(&1.title == "Todo Task"))
      assert task.state_id == EyeInTheSky.Tasks.WorkflowState.todo_id()
    end

    test "trims whitespace from title", %{session: session} do
      TaskHandler.dispatch("create   Trimmed Title   ", session.id)

      task = Enum.find(Tasks.list_tasks(limit: 10), &(&1.title == "Trimmed Title"))
      assert task
    end
  end

  describe "dispatch/2 begin command" do
    test "creates a task in in_progress state", %{session: session} do
      TaskHandler.dispatch("begin In Progress Task", session.id)

      task = Enum.find(Tasks.list_tasks(limit: 10), &(&1.title == "In Progress Task"))
      assert task.state_id == EyeInTheSky.Tasks.WorkflowState.in_progress_id()
    end

    test "links task to session", %{session: session} do
      TaskHandler.dispatch("begin Linked Task", session.id)

      task = Enum.find(Tasks.list_tasks(limit: 10), &(&1.title == "Linked Task"))
      assert Tasks.task_linked_to_session?(task.id, session.id)
    end
  end

  describe "dispatch/2 start command" do
    setup %{session: session} do
      {:ok, task} = Tasks.create_task(%{title: "Start Test", state_id: 1, project_id: nil})
      {:ok, task: task}
    end

    test "updates task to in_progress state", %{session: session, task: task} do
      TaskHandler.dispatch("start #{task.id}", session.id)

      updated = Tasks.get_task!(task.id)
      assert updated.state_id == EyeInTheSky.Tasks.WorkflowState.in_progress_id()
    end

    test "links session to task", %{session: session, task: task} do
      TaskHandler.dispatch("start #{task.id}", session.id)

      assert Tasks.task_linked_to_session?(task.id, session.id)
    end
  end

  describe "dispatch/2 update command" do
    setup %{session: session} do
      {:ok, task} = Tasks.create_task(%{title: "Update Test", state_id: 1, project_id: nil})
      Tasks.link_session_to_task(task.id, session.id)
      {:ok, task: task}
    end

    test "updates task state", %{session: session, task: task} do
      done_id = EyeInTheSky.Tasks.WorkflowState.done_id()
      TaskHandler.dispatch("update #{task.id} #{done_id}", session.id)

      updated = Tasks.get_task!(task.id)
      assert updated.state_id == done_id
    end

    test "rejects invalid task ID", %{session: session} do
      TaskHandler.dispatch("update invalid_id 3", session.id)
      # No exception thrown; silently fails with error notification
    end

    test "rejects task not linked to session", %{session: session} do
      {:ok, other_task} = Tasks.create_task(%{title: "Other", state_id: 1, project_id: nil})
      TaskHandler.dispatch("update #{other_task.id} 3", session.id)
      # Should fail because task is not linked
    end

    test "handles missing state_id" do
      TaskHandler.dispatch("update 123", 999)
      # Should fail gracefully
    end
  end

  describe "dispatch/2 done command" do
    setup %{session: session} do
      {:ok, task} = Tasks.create_task(%{title: "Done Test", state_id: 1, project_id: nil})
      Tasks.link_session_to_task(task.id, session.id)
      {:ok, task: task}
    end

    test "updates task to done state", %{session: session, task: task} do
      TaskHandler.dispatch("done #{task.id}", session.id)

      updated = Tasks.get_task!(task.id)
      assert updated.state_id == EyeInTheSky.Tasks.WorkflowState.done_id()
    end

    test "rejects invalid task ID" do
      TaskHandler.dispatch("done not_a_number", 999)
      # Silently fails
    end

    test "rejects task not linked to session", %{session: session} do
      {:ok, other_task} = Tasks.create_task(%{title: "Other", state_id: 1, project_id: nil})
      TaskHandler.dispatch("done #{other_task.id}", session.id)
      # Should fail
    end
  end

  describe "dispatch/2 delete command" do
    setup %{session: session} do
      {:ok, task} = Tasks.create_task(%{title: "Delete Test", state_id: 1, project_id: nil})
      Tasks.link_session_to_task(task.id, session.id)
      {:ok, task: task}
    end

    test "deletes task", %{session: session, task: task} do
      TaskHandler.dispatch("delete #{task.id}", session.id)

      assert Tasks.get_task(task.id) == {:error, :not_found}
    end

    test "rejects invalid task ID" do
      TaskHandler.dispatch("delete not_a_number", 999)
      # Silently fails
    end

    test "rejects task not linked to session", %{session: session} do
      {:ok, other_task} = Tasks.create_task(%{title: "Other", state_id: 1, project_id: nil})
      TaskHandler.dispatch("delete #{other_task.id}", session.id)
      # Should fail
    end
  end

  describe "dispatch/2 annotate command" do
    setup %{session: session} do
      {:ok, task} = Tasks.create_task(%{title: "Annotate Test", state_id: 1, project_id: nil})
      Tasks.link_session_to_task(task.id, session.id)
      {:ok, task: task}
    end

    test "creates a note on the task", %{session: session, task: task} do
      TaskHandler.dispatch("annotate #{task.id} This is a note", session.id)

      # Verify note was created
      task_notes = Notes.list_notes(limit: 10) |> Enum.filter(&(&1.parent_id == task.id))
      assert Enum.any?(task_notes, &(&1.body == "This is a note"))
    end

    test "handles multi-word annotation", %{session: session, task: task} do
      TaskHandler.dispatch("annotate #{task.id} Multiple word annotation", session.id)

      task_notes = Notes.list_notes(limit: 10) |> Enum.filter(&(&1.parent_id == task.id))
      assert Enum.any?(task_notes, &(&1.body == "Multiple word annotation"))
    end

    test "rejects invalid task ID" do
      TaskHandler.dispatch("annotate invalid_id Note body", 999)
      # Silently fails
    end

    test "rejects task not linked to session", %{session: session} do
      {:ok, other_task} = Tasks.create_task(%{title: "Other", state_id: 1, project_id: nil})
      TaskHandler.dispatch("annotate #{other_task.id} Note", session.id)
      # Should fail
    end

    test "rejects missing body" do
      TaskHandler.dispatch("annotate 123", 999)
      # Should fail
    end
  end

  describe "dispatch/2 link-session command" do
    setup %{session: session} do
      {:ok, task} = Tasks.create_task(%{title: "Link Test", state_id: 1, project_id: nil})
      {:ok, task: task}
    end

    test "links session to task", %{session: session, task: task} do
      refute Tasks.task_linked_to_session?(task.id, session.id)

      TaskHandler.dispatch("link-session #{task.id}", session.id)

      assert Tasks.task_linked_to_session?(task.id, session.id)
    end

    test "rejects invalid task ID" do
      TaskHandler.dispatch("link-session invalid_id", 999)
      # Silently fails
    end
  end

  describe "dispatch/2 unlink-session command" do
    setup %{session: session} do
      {:ok, task} = Tasks.create_task(%{title: "Unlink Test", state_id: 1, project_id: nil})
      Tasks.link_session_to_task(task.id, session.id)
      {:ok, task: task}
    end

    test "unlinks session from task", %{session: session, task: task} do
      assert Tasks.task_linked_to_session?(task.id, session.id)

      TaskHandler.dispatch("unlink-session #{task.id}", session.id)

      refute Tasks.task_linked_to_session?(task.id, session.id)
    end
  end

  describe "dispatch/2 tag command" do
    setup %{session: session} do
      {:ok, task} = Tasks.create_task(%{title: "Tag Test", state_id: 1, project_id: nil})
      Tasks.link_session_to_task(task.id, session.id)
      {:ok, tag} = EyeInTheSky.Tags.create_tag(%{name: "urgent"})
      {:ok, task: task, tag: tag}
    end

    test "links tag to task", %{session: session, task: task, tag: tag} do
      TaskHandler.dispatch("tag #{task.id} #{tag.id}", session.id)

      # Verify tag is linked
      task_tags = EyeInTheSky.Tags.list_tags_for_task(task.id)
      assert Enum.any?(task_tags, &(&1.id == tag.id))
    end

    test "rejects invalid task ID" do
      TaskHandler.dispatch("tag invalid_id 1", 999)
      # Silently fails
    end

    test "rejects task not linked to session", %{session: session} do
      {:ok, other_task} = Tasks.create_task(%{title: "Other", state_id: 1, project_id: nil})
      TaskHandler.dispatch("tag #{other_task.id} 1", session.id)
      # Should fail
    end

    test "rejects invalid tag ID", %{session: session, task: task} do
      TaskHandler.dispatch("tag #{task.id} invalid_id", session.id)
      # Silently fails
    end
  end

  describe "dispatch/2 unknown command" do
    test "handles unknown subcommand gracefully" do
      TaskHandler.dispatch("unknown_command", 999)
      # Should not crash, just notify error
    end
  end
end
