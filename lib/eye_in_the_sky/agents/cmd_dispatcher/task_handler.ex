defmodule EyeInTheSky.Agents.CmdDispatcher.TaskHandler do
  @moduledoc """
  Handles EITS-CMD task subcommands.

  Supported:
      task create <title>
      task begin <title>
      task start <id>
      task update <id> <state_id>
      task done <id>
      task delete <id>
      task annotate <id> <body>
      task link-session <id>
      task unlink-session <id>
      task tag <id> <tag_id>
  """

  require Logger

  alias EyeInTheSky.Agents.CmdDispatcher.Helpers
  alias EyeInTheSky.{Notes, Tasks}
  alias EyeInTheSky.Utils.ToolHelpers

  import Helpers, only: [notify_success: 2, notify_error: 3, get_session!: 1, with_task: 4]

  def dispatch("create " <> title, from_session_id) do
    title = String.trim(title)
    session = get_session!(from_session_id)

    case Tasks.create_task(%{title: title, state_id: 1, project_id: session && session.project_id}) do
      {:ok, task} ->
        Tasks.link_session_to_task(task.id, from_session_id)
        notify_success(from_session_id, "task created id=#{task.id} title=#{title}")

      {:error, reason} ->
        notify_error(from_session_id, "task create", reason)
    end
  end

  def dispatch("begin " <> title, from_session_id) do
    title = String.trim(title)
    session = get_session!(from_session_id)

    case Tasks.create_task(%{title: title, state_id: 2, project_id: session && session.project_id}) do
      {:ok, task} ->
        Tasks.link_session_to_task(task.id, from_session_id)
        notify_success(from_session_id, "task begun id=#{task.id} title=#{title}")

      {:error, reason} ->
        notify_error(from_session_id, "task begin", reason)
    end
  end

  def dispatch("start " <> id_str, from_session_id) do
    with_task(id_str, from_session_id, "task start", fn id, task ->
      Tasks.update_task_state(task, 2)
      Tasks.link_session_to_task(id, from_session_id)
      notify_success(from_session_id, "task #{id} started (in_progress)")
    end)
  end

  def dispatch("update " <> rest, from_session_id) do
    case String.split(rest, " ", parts: 2) do
      [id_str, state_str] ->
        with id when not is_nil(id) <- id_str |> String.trim() |> ToolHelpers.parse_int(),
             state_id when not is_nil(state_id) <- state_str |> String.trim() |> ToolHelpers.parse_int(),
             true <- Tasks.task_linked_to_session?(id, from_session_id),
             {:ok, task} <- Tasks.get_task(id) do
          Tasks.update_task_state(task, state_id)
          notify_success(from_session_id, "task #{id} state -> #{state_id}")
        else
          false -> notify_error(from_session_id, "task update", {:not_linked, rest})
          {:error, :not_found} -> notify_error(from_session_id, "task update", :not_found)
          _ -> notify_error(from_session_id, "task update", :invalid_id_or_state_id)
        end

      _ ->
        notify_error(from_session_id, "task update", :expected_id_and_state_id)
    end
  end

  def dispatch("done " <> id_str, from_session_id) do
    id_str = String.trim(id_str)

    case ToolHelpers.parse_int(id_str) do
      nil -> notify_error(from_session_id, "task done", {:invalid_id, id_str})
      id -> do_task_done(id_str, id, from_session_id)
    end
  end

  def dispatch("delete " <> id_str, from_session_id) do
    id_str = String.trim(id_str)

    case ToolHelpers.parse_int(id_str) do
      nil -> notify_error(from_session_id, "task delete", {:invalid_id, id_str})
      id -> do_task_delete(id_str, id, from_session_id)
    end
  end

  def dispatch("annotate " <> rest, from_session_id) do
    case String.split(rest, " ", parts: 2) do
      [id_str, body] ->
        case id_str |> String.trim() |> ToolHelpers.parse_int() do
          nil -> notify_error(from_session_id, "task annotate", {:invalid_id, id_str})
          id -> do_annotate_task(id, body, from_session_id)
        end

      _ ->
        notify_error(from_session_id, "task annotate", :missing_body)
    end
  end

  def dispatch("link-session " <> id_str, from_session_id) do
    with_task(id_str, from_session_id, "task link-session", fn id, _task ->
      Tasks.link_session_to_task(id, from_session_id)
      notify_success(from_session_id, "task #{id} linked to session #{from_session_id}")
    end)
  end

  def dispatch("unlink-session " <> id_str, from_session_id) do
    with_task(id_str, from_session_id, "task unlink-session", fn id, _task ->
      Tasks.unlink_session_from_task(id, from_session_id)
      notify_success(from_session_id, "task #{id} unlinked from session #{from_session_id}")
    end)
  end

  def dispatch("tag " <> rest, from_session_id) do
    case String.split(rest, " ", parts: 2) do
      [id_str, tag_id_str] ->
        with id when not is_nil(id) <- id_str |> String.trim() |> ToolHelpers.parse_int(),
             tag_id when not is_nil(tag_id) <- tag_id_str |> String.trim() |> ToolHelpers.parse_int(),
             true <- Tasks.task_linked_to_session?(id, from_session_id),
             {:ok, _task} <- Tasks.get_task(id) do
          Tasks.link_tag_to_task(id, tag_id)
          notify_success(from_session_id, "task #{id} tagged with #{tag_id}")
        else
          false -> notify_error(from_session_id, "task tag", {:not_linked, id_str})
          {:error, :not_found} -> notify_error(from_session_id, "task tag", :not_found)
          _ -> notify_error(from_session_id, "task tag", {:invalid_id_or_tag_id, rest})
        end

      _ ->
        notify_error(from_session_id, "task tag", :expected_id_and_tag_id)
    end
  end

  def dispatch(unknown, from_session_id),
    do: notify_error(from_session_id, "task", {:unknown_subcommand, unknown})

  defp do_task_done(id_str, id, from_session_id) do
    if Tasks.task_linked_to_session?(id, from_session_id) do
      with_task(id_str, from_session_id, "task done", fn id, task ->
        Tasks.update_task_state(task, 3)
        notify_success(from_session_id, "task #{id} -> done")
      end)
    else
      notify_error(from_session_id, "task done", {:not_linked, id})
    end
  end

  defp do_task_delete(id_str, id, from_session_id) do
    if Tasks.task_linked_to_session?(id, from_session_id) do
      with_task(id_str, from_session_id, "task delete", fn _id, task ->
        Tasks.delete_task(task)
        notify_success(from_session_id, "task #{id} deleted")
      end)
    else
      notify_error(from_session_id, "task delete", {:not_linked, id})
    end
  end

  defp do_annotate_task(id, body, from_session_id) do
    if Tasks.task_linked_to_session?(id, from_session_id) do
      Notes.create_note(%{
        title: "Agent annotation",
        body: body,
        parent_id: id,
        parent_type: "task"
      })

      notify_success(from_session_id, "task #{id} annotated")
    else
      notify_error(from_session_id, "task annotate", {:not_linked, id})
    end
  end
end
