defmodule EyeInTheSky.TasksTimestampsTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  alias EyeInTheSky.Tasks

  describe "create_task/1 timestamp defaults" do
    test "injects created_at, updated_at, and uuid when not provided" do
      {:ok, task} = Tasks.create_task(%{title: "bare minimum", state_id: 1})

      assert task.uuid != nil
      assert task.created_at != nil
      assert task.updated_at != nil
    end

    test "preserves caller-provided timestamps" do
      now = ~U[2025-06-15 12:00:00.000000Z]

      {:ok, task} =
        Tasks.create_task(%{
          title: "explicit timestamps",
          state_id: 1,
          uuid: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
          created_at: now,
          updated_at: now
        })

      assert task.uuid == "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
      assert task.created_at == now
      assert task.updated_at == now
    end
  end

  describe "update_task/2 updated_at default" do
    test "sets updated_at when not provided" do
      {:ok, task} = Tasks.create_task(%{title: "original", state_id: 1})
      original_updated_at = task.updated_at

      # Small delay to ensure different timestamp
      Process.sleep(10)

      {:ok, updated} = Tasks.update_task(task, %{title: "changed"})

      assert DateTime.compare(updated.updated_at, original_updated_at) == :gt
    end

    test "preserves caller-provided updated_at" do
      {:ok, task} = Tasks.create_task(%{title: "original", state_id: 1})
      explicit_time = ~U[2030-01-01 00:00:00.000000Z]

      {:ok, updated} = Tasks.update_task(task, %{title: "changed", updated_at: explicit_time})

      assert updated.updated_at == explicit_time
    end
  end
end
