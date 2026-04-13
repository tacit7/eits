defmodule EyeInTheSky.Notes.NoteQueries do
  @moduledoc """
  Shared Ecto query helpers for notes.

  Extracted from EyeInTheSky.Notes to break the circular dependency between
  the Notes and Tasks contexts. Tasks imports NoteQueries directly; Notes
  delegates with_notes_count/1 here for backward compatibility.
  """

  import Ecto.Query, warn: false
  alias EyeInTheSky.Notes.Note
  alias EyeInTheSky.Repo

  @doc """
  Batch-loads notes for a list of tasks and sets :notes and :notes_count on each.
  Notes are stored with parent_type "task" and parent_id as integer string or UUID.
  """
  def with_notes_count(tasks) when is_list(tasks) do
    task_int_ids = Enum.map(tasks, &to_string(&1.id))
    task_uuids = tasks |> Enum.map(& &1.uuid) |> Enum.reject(&is_nil/1)
    all_ids = task_int_ids ++ task_uuids

    notes_by_parent =
      Note
      |> where([n], n.parent_type == "task")
      |> where([n], n.parent_id in ^all_ids)
      |> order_by([n], asc: n.created_at)
      |> Repo.all()
      |> Enum.group_by(& &1.parent_id)

    Enum.map(tasks, fn task ->
      notes =
        (Map.get(notes_by_parent, to_string(task.id), []) ++
           if(task.uuid, do: Map.get(notes_by_parent, task.uuid, []), else: []))
        |> Enum.uniq_by(& &1.id)

      task
      |> Map.put(:notes, notes)
      |> Map.put(:notes_count, length(notes))
    end)
  end
end
