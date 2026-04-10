defmodule EyeInTheSky.NotesTaskLookupTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  alias EyeInTheSky.Notes
  alias EyeInTheSky.Tasks

  setup do
    {:ok, task} = Tasks.create_task(%{title: "test task", state_id: 1})

    {:ok, note} =
      Notes.create_note(%{
        parent_type: "task",
        parent_id: to_string(task.id),
        body: "note for task"
      })

    %{task: task, note: note}
  end

  describe "list_notes_for_task/1" do
    test "returns notes when given integer task id", %{task: task, note: note} do
      results = Notes.list_notes_for_task(task.id)
      assert Enum.any?(results, &(&1.id == note.id))
    end

    test "returns notes when given stringified integer id", %{task: task, note: note} do
      results = Notes.list_notes_for_task(to_string(task.id))
      assert Enum.any?(results, &(&1.id == note.id))
    end

    test "returns notes when given task UUID", %{task: task, note: note} do
      results = Notes.list_notes_for_task(task.uuid)
      assert Enum.any?(results, &(&1.id == note.id))
    end

    test "raises when task does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Notes.list_notes_for_task("00000000-0000-0000-0000-000000000000")
      end
    end
  end
end
