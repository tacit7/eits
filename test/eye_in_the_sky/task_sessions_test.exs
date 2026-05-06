defmodule EyeInTheSky.TaskSessionsTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  import Ecto.Query, only: [from: 2]
  import EyeInTheSky.Factory

  alias EyeInTheSky.{Repo, TaskSessions, Tasks}

  defp create_task do
    {:ok, task} =
      Tasks.create_task(%{
        uuid: Ecto.UUID.generate(),
        title: "Test task #{uniq()}",
        state_id: 1,
        created_at: DateTime.utc_now()
      })

    task
  end

  describe "transfer_session_ownership/2" do
    test "removes existing links and adds new session" do
      task = create_task()
      creator = new_session()
      claimer = new_session()

      Repo.insert_all("task_sessions", [%{task_id: task.id, session_id: creator.id}],
        on_conflict: :nothing
      )

      assert {:ok, _} = TaskSessions.transfer_session_ownership(task.id, claimer.id)

      linked_ids =
        Repo.all(from ts in "task_sessions", where: ts.task_id == ^task.id, select: ts.session_id)

      assert linked_ids == [claimer.id]
      refute creator.id in linked_ids
    end

    test "transfers ownership when no prior links exist" do
      task = create_task()
      session = new_session()

      assert {:ok, _} = TaskSessions.transfer_session_ownership(task.id, session.id)

      linked_ids =
        Repo.all(from ts in "task_sessions", where: ts.task_id == ^task.id, select: ts.session_id)

      assert linked_ids == [session.id]
    end

    test "transfers ownership when multiple sessions were previously linked" do
      task = create_task()
      s1 = new_session()
      s2 = new_session()
      claimer = new_session()

      Repo.insert_all(
        "task_sessions",
        [%{task_id: task.id, session_id: s1.id}, %{task_id: task.id, session_id: s2.id}]
      )

      assert {:ok, _} = TaskSessions.transfer_session_ownership(task.id, claimer.id)

      linked_ids =
        Repo.all(from ts in "task_sessions", where: ts.task_id == ^task.id, select: ts.session_id)

      assert linked_ids == [claimer.id]
    end

    test "returns task_not_found for non-existent task id" do
      session = new_session()

      assert {:error, :task_not_found} =
               TaskSessions.transfer_session_ownership(999_999_999, session.id)
    end
  end

  describe "claim_task/2 (Tasks context)" do
    test "atomically transitions state and transfers ownership" do
      task = create_task()
      creator = new_session()
      claimer = new_session()

      Repo.insert_all("task_sessions", [%{task_id: task.id, session_id: creator.id}],
        on_conflict: :nothing
      )

      assert {:ok, updated} = Tasks.claim_task(task, claimer.id)
      assert updated.state_id == 2

      linked_ids =
        Repo.all(from ts in "task_sessions", where: ts.task_id == ^task.id, select: ts.session_id)

      assert linked_ids == [claimer.id]
    end
  end
end
