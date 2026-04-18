defmodule EyeInTheSky.Tasks.Associations do
  @moduledoc false

  alias EyeInTheSky.Sessions
  alias EyeInTheSky.TaskSessions
  alias EyeInTheSky.TaskTags
  alias EyeInTheSky.Utils.ToolHelpers

  @doc """
  Handles post-create associations: session linking, tag replacement, and tag ID linking.
  Accepts a raw params map with string keys (as received from the HTTP layer).
  """
  def associate_task(task, params) do
    do_link_session(task.id, params["session_id"])
    do_add_tags(task, params["tags"])
    do_add_tag_ids(task, params["tag_ids"])
    :ok
  end

  defp do_link_session(_task_id, nil), do: :ok

  defp do_link_session(task_id, session_id) when is_binary(session_id) do
    int_id =
      case ToolHelpers.parse_int(session_id) do
        nil ->
          case Sessions.get_session_by_uuid(session_id) do
            {:ok, %{id: id}} -> id
            _ -> nil
          end

        n ->
          n
      end

    if int_id, do: TaskSessions.link_session_to_task(task_id, int_id)
    :ok
  end

  defp do_add_tags(_task, nil), do: :ok
  defp do_add_tags(_task, []), do: :ok

  defp do_add_tags(task, tags) when is_list(tags) do
    TaskTags.replace_task_tags(task.id, tags)
  end

  defp do_add_tag_ids(_task, nil), do: :ok
  defp do_add_tag_ids(_task, []), do: :ok

  defp do_add_tag_ids(task, tag_ids) when is_list(tag_ids) do
    Enum.each(tag_ids, fn tag_id ->
      case ToolHelpers.parse_int(tag_id) do
        nil -> :ok
        id -> TaskTags.link_tag_to_task(task.id, id)
      end
    end)
  end
end
