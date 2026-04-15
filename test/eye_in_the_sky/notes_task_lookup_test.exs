defmodule EyeInTheSky.NotesTaskLookupTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  alias EyeInTheSky.Notes
  alias EyeInTheSky.Tasks

  setup do
    {:ok, task} = Tasks.create_task(%{title: "test task", state_id: 1})

    # One note stored with integer id as parent_id
    {:ok, note_by_id} =
      Notes.create_note(%{
        parent_type: "task",
        parent_id: to_string(task.id),
        body: "note stored with integer id"
      })

    # One note stored with uuid as parent_id
    {:ok, note_by_uuid} =
      Notes.create_note(%{
        parent_type: "task",
        parent_id: task.uuid,
        body: "note stored with uuid"
      })

    %{task: task, note_by_id: note_by_id, note_by_uuid: note_by_uuid}
  end

  describe "list_notes_for_task/1" do
    test "finds notes stored with integer parent_id when given integer id", %{
      task: task,
      note_by_id: note
    } do
      results = Notes.list_notes_for_task(task.id)
      assert Enum.any?(results, &(&1.id == note.id))
    end

    test "finds notes stored with integer parent_id when given stringified id", %{
      task: task,
      note_by_id: note
    } do
      results = Notes.list_notes_for_task(to_string(task.id))
      assert Enum.any?(results, &(&1.id == note.id))
    end

    test "finds notes stored with uuid parent_id when given integer id", %{
      task: task,
      note_by_uuid: note
    } do
      results = Notes.list_notes_for_task(task.id)
      assert Enum.any?(results, &(&1.id == note.id))
    end

    test "finds notes stored with uuid parent_id when given task UUID", %{
      task: task,
      note_by_uuid: note
    } do
      results = Notes.list_notes_for_task(task.uuid)
      assert Enum.any?(results, &(&1.id == note.id))
    end

    test "finds both note styles when looking up by integer id", %{
      task: task,
      note_by_id: n1,
      note_by_uuid: n2
    } do
      results = Notes.list_notes_for_task(task.id)
      ids = Enum.map(results, & &1.id)
      assert n1.id in ids
      assert n2.id in ids
    end

    test "returns [] for nonexistent task id" do
      assert [] == Notes.list_notes_for_task(999_999_999)
    end

    test "returns [] for nonexistent task UUID" do
      assert [] == Notes.list_notes_for_task("00000000-0000-0000-0000-000000000000")
    end
  end
end
