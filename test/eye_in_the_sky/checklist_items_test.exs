defmodule EyeInTheSky.ChecklistItemsTest do
  use EyeInTheSky.DataCase, async: true

  import EyeInTheSky.Factory

  alias EyeInTheSky.ChecklistItems
  alias EyeInTheSky.Tasks
  alias EyeInTheSky.Tasks.ChecklistItem

  defp task_fixture(attrs \\ %{}) do
    project = project_fixture()

    {:ok, task} =
      Tasks.create_task(
        Map.merge(
          %{
            title: "Test task #{uniq()}",
            state_id: 1,
            priority: 0,
            project_id: project.id
          },
          attrs
        )
      )

    task
  end

  defp item_fixture(task, attrs \\ %{}) do
    {:ok, item} =
      ChecklistItems.create_checklist_item(
        Map.merge(
          %{title: "item #{uniq()}", task_id: task.id},
          attrs
        )
      )

    item
  end

  describe "list_checklist_items/1" do
    test "returns items for the given task ordered by position then id" do
      task = task_fixture()
      i_a = item_fixture(task, %{title: "a", position: 2})
      i_b = item_fixture(task, %{title: "b", position: 0})
      i_c = item_fixture(task, %{title: "c", position: 0})

      ids = ChecklistItems.list_checklist_items(task.id) |> Enum.map(& &1.id)
      # position 0 first (b, c by id asc), then position 2 (a)
      assert ids == [i_b.id, i_c.id, i_a.id]
    end

    test "scopes results to the task_id" do
      task1 = task_fixture()
      task2 = task_fixture()
      _kept = item_fixture(task1, %{title: "kept"})
      other = item_fixture(task2, %{title: "other"})

      results = ChecklistItems.list_checklist_items(task1.id)
      assert Enum.all?(results, &(&1.task_id == task1.id))
      refute Enum.any?(results, &(&1.id == other.id))
    end

    test "returns [] when task has no items" do
      task = task_fixture()
      assert ChecklistItems.list_checklist_items(task.id) == []
    end

    test "returns [] for non-existent task_id" do
      assert ChecklistItems.list_checklist_items(-1) == []
    end
  end

  describe "create_checklist_item/1" do
    test "creates an item with required attrs and defaults" do
      task = task_fixture()
      assert {:ok, %ChecklistItem{} = item} =
               ChecklistItems.create_checklist_item(%{title: "thing", task_id: task.id})

      assert item.title == "thing"
      assert item.completed == false
      assert item.position == 0
      assert item.task_id == task.id
    end

    test "respects supplied position and completed" do
      task = task_fixture()
      assert {:ok, item} =
               ChecklistItems.create_checklist_item(%{
                 title: "thing",
                 task_id: task.id,
                 position: 5,
                 completed: true
               })

      assert item.position == 5
      assert item.completed == true
    end

    test "errors when title missing" do
      task = task_fixture()
      assert {:error, changeset} =
               ChecklistItems.create_checklist_item(%{task_id: task.id})

      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end

    test "errors when task_id missing" do
      assert {:error, changeset} =
               ChecklistItems.create_checklist_item(%{title: "x"})

      assert %{task_id: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "toggle_checklist_item/1" do
    test "flips completed false -> true" do
      task = task_fixture()
      item = item_fixture(task, %{completed: false})

      assert {:ok, toggled} = ChecklistItems.toggle_checklist_item(item.id)
      assert toggled.id == item.id
      assert toggled.completed == true
    end

    test "flips completed true -> false" do
      task = task_fixture()
      item = item_fixture(task, %{completed: true})

      assert {:ok, toggled} = ChecklistItems.toggle_checklist_item(item.id)
      assert toggled.completed == false
    end

    test "persists the toggled state" do
      task = task_fixture()
      item = item_fixture(task, %{completed: false})
      {:ok, _} = ChecklistItems.toggle_checklist_item(item.id)

      reloaded = Repo.get!(ChecklistItem, item.id)
      assert reloaded.completed == true
    end

    test "returns error for non-existent id" do
      assert {:error, :not_found} = ChecklistItems.toggle_checklist_item(-1)
    end

    test "returned struct preserves identity fields" do
      task = task_fixture()
      item = item_fixture(task, %{title: "preserve", position: 7})

      assert {:ok, toggled} = ChecklistItems.toggle_checklist_item(item.id)
      assert toggled.title == "preserve"
      assert toggled.position == 7
      assert toggled.task_id == task.id
    end
  end

  describe "delete_checklist_item/1" do
    test "deletes an existing item and returns :ok" do
      task = task_fixture()
      item = item_fixture(task)

      assert :ok = ChecklistItems.delete_checklist_item(item.id)
      assert Repo.get(ChecklistItem, item.id) == nil
    end

    test "returns {:error, :not_found} for non-existent id" do
      assert {:error, :not_found} = ChecklistItems.delete_checklist_item(-1)
    end

    test "does not affect other items" do
      task = task_fixture()
      keep = item_fixture(task)
      drop = item_fixture(task)

      assert :ok = ChecklistItems.delete_checklist_item(drop.id)
      assert Repo.get(ChecklistItem, keep.id) != nil
    end
  end
end
