defmodule EyeInTheSky.TasksReorderTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  alias EyeInTheSky.{Repo, Tasks}
  alias EyeInTheSky.Tasks.Task

  describe "reorder_tasks/1" do
    test "reorders tasks by UUID list" do
      {:ok, t1} = Tasks.create_task(%{title: "Task 1", state_id: 1, position: 3})
      {:ok, t2} = Tasks.create_task(%{title: "Task 2", state_id: 1, position: 1})
      {:ok, t3} = Tasks.create_task(%{title: "Task 3", state_id: 1, position: 2})

      ordered_uuids = [t3.uuid, t1.uuid, t2.uuid]

      assert :ok = Tasks.reorder_tasks(ordered_uuids)

      assert Repo.get!(Task, t3.id).position == 1
      assert Repo.get!(Task, t1.id).position == 2
      assert Repo.get!(Task, t2.id).position == 3
    end

    test "updates updated_at on all reordered tasks" do
      {:ok, t1} = Tasks.create_task(%{title: "Task 1", state_id: 1})
      {:ok, t2} = Tasks.create_task(%{title: "Task 2", state_id: 1})

      original_t1_updated_at = t1.updated_at
      original_t2_updated_at = t2.updated_at

      Process.sleep(1100)

      Tasks.reorder_tasks([t2.uuid, t1.uuid])

      t1_updated = Repo.get!(Task, t1.id)
      t2_updated = Repo.get!(Task, t2.id)

      refute t1_updated.updated_at == original_t1_updated_at
      refute t2_updated.updated_at == original_t2_updated_at
    end

    test "returns :ok for empty list" do
      assert :ok = Tasks.reorder_tasks([])
    end

    test "handles single task" do
      {:ok, task} = Tasks.create_task(%{title: "Solo", state_id: 1, position: 5})

      assert :ok = Tasks.reorder_tasks([task.uuid])
      assert Repo.get!(Task, task.id).position == 1
    end
  end
end
