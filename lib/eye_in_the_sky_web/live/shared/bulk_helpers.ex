defmodule EyeInTheSkyWeb.Live.Shared.BulkHelpers do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]
  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1, parse_int: 2]

  alias EyeInTheSky.Tasks

  @doc """
  Canonical bulk-operation flash message builder. **Do not inline this cond pattern.**

  Returns `{flash_level, message}` where level is `:info` or `:error`.

  Options (keyword list):
    - `:verb` (required) — past-tense action, e.g. `"Moved"`, `"Archived"`, `"Deleted"`
    - `:entity` (required) — singular noun, e.g. `"task"`, `"session"`
    - `:destination` (optional) — destination label for move ops, e.g. state name

  ## Examples

      BulkHelpers.build_bulk_flash(3, 3, verb: "Archived", entity: "task")
      # => {:info, "Archived 3 tasks"}

      BulkHelpers.build_bulk_flash(2, 3, verb: "Moved", entity: "task", destination: "Done")
      # => {:info, "Moved 2 tasks to Done; 1 failed"}
  """
  def build_bulk_flash(succeeded, total, opts) do
    verb = Keyword.fetch!(opts, :verb)
    entity = Keyword.fetch!(opts, :entity)
    destination = Keyword.get(opts, :destination)
    failed = total - succeeded
    succ_noun = if succeeded == 1, do: entity, else: "#{entity}s"
    fail_noun = if failed == 1, do: entity, else: "#{entity}s"
    dest_suffix = if destination, do: " to #{destination}", else: ""

    past_negative =
      case verb do
        "Moved" -> "move"
        "Archived" -> "archive"
        "Deleted" -> "delete"
        v -> String.downcase(v)
      end

    cond do
      succeeded > 0 and failed > 0 ->
        {:info, "#{verb} #{succeeded} #{succ_noun}#{dest_suffix}; #{failed} failed"}

      succeeded > 0 ->
        {:info, "#{verb} #{succeeded} #{succ_noun}#{dest_suffix}"}

      true ->
        {:error, "Could not #{past_negative} #{failed} #{fail_noun}"}
    end
  end

  def handle_toggle_bulk_mode(socket) do
    {:noreply,
     socket
     |> assign(:bulk_mode, !socket.assigns.bulk_mode)
     |> assign(:selected_tasks, MapSet.new())}
  end

  def handle_toggle_select_task(%{"task-uuid" => uuid}, socket) do
    selected = socket.assigns.selected_tasks

    updated =
      if MapSet.member?(selected, uuid),
        do: MapSet.delete(selected, uuid),
        else: MapSet.put(selected, uuid)

    {:noreply, assign(socket, :selected_tasks, updated)}
  end

  def handle_toggle_select_task(_params, socket), do: {:noreply, socket}

  def handle_select_all_column(%{"state-id" => state_id_str}, socket) do
    state_id = parse_int(state_id_str, 0)

    column_uuids =
      Map.get(socket.assigns.tasks_by_state, state_id, [])
      |> Enum.map(& &1.uuid)
      |> Enum.reject(&is_nil/1)

    current = socket.assigns.selected_tasks
    all_selected = Enum.all?(column_uuids, &MapSet.member?(current, &1))

    updated =
      if all_selected,
        do: Enum.reduce(column_uuids, current, &MapSet.delete(&2, &1)),
        else: Enum.reduce(column_uuids, current, &MapSet.put(&2, &1))

    {:noreply, assign(socket, :selected_tasks, updated)}
  end

  def handle_bulk_move(%{"state_id" => state_id_str}, socket, reload_fn) do
    state_id = parse_int(state_id_str, 0)

    uuids =
      socket.assigns.selected_tasks
      |> Enum.reject(&is_nil/1)
      |> Enum.to_list()

    Tasks.batch_update_task_state(uuids, state_id)

    {:noreply, socket |> assign(:selected_tasks, MapSet.new()) |> reload_fn.()}
  end

  def handle_bulk_archive(socket, reload_fn) do
    socket.assigns.selected_tasks
    |> Enum.reject(&is_nil/1)
    |> Enum.each(fn uuid ->
      task = Tasks.get_task_by_uuid!(uuid)
      Tasks.archive_task(task)
    end)

    {:noreply,
     socket
     |> assign(:selected_tasks, MapSet.new())
     |> reload_fn.()
     |> put_flash(:info, "Tasks archived")}
  end

  def handle_bulk_delete(socket, reload_fn) do
    socket.assigns.selected_tasks
    |> Enum.reject(&is_nil/1)
    |> Enum.each(fn uuid ->
      task = Tasks.get_task_by_uuid!(uuid)
      Tasks.delete_task_with_associations(task)
    end)

    {:noreply,
     socket
     |> assign(:selected_tasks, MapSet.new())
     |> reload_fn.()
     |> put_flash(:info, "Tasks deleted")}
  end

  # ---------------------------------------------------------------------------
  # Tasks list bulk operations (selected_task_ids + tasks_select_mode pattern)
  # ---------------------------------------------------------------------------

  def handle_tasks_bulk_set_state(ids, state_id_str, socket, reload_fn) do
    state_id = parse_int(state_id_str)

    cond do
      MapSet.size(ids) == 0 ->
        {:noreply, socket}

      is_nil(state_id) ->
        {:noreply, put_flash(socket, :error, "Invalid state")}

      true ->
        id_list = MapSet.to_list(ids)
        total = length(id_list)
        {moved, _} = Tasks.batch_update_task_state(id_list, state_id)
        state_name = Tasks.get_workflow_state!(state_id).name

        {flash_level, flash_msg} =
          build_bulk_flash(moved, total,
            verb: "Moved",
            entity: "task",
            destination: state_name
          )

        {:noreply,
         socket
         |> assign(:selected_task_ids, MapSet.new())
         |> assign(:tasks_select_mode, false)
         |> reload_fn.()
         |> put_flash(flash_level, flash_msg)}
    end
  end

  def handle_tasks_archive_selected(ids, socket, reload_fn) do
    if MapSet.size(ids) == 0 do
      {:noreply, assign(socket, :show_archive_confirm, false)}
    else
      results =
        Enum.map(ids, fn task_id ->
          case Tasks.get_task_by_uuid_or_id(task_id) do
            {:ok, task} -> match?({:ok, _}, Tasks.archive_task(task))
            {:error, :not_found} -> false
          end
        end)

      archived = Enum.count(results, & &1)

      {flash_level, flash_msg} =
        build_bulk_flash(archived, length(results), verb: "Archived", entity: "task")

      {:noreply,
       socket
       |> assign(:show_archive_confirm, false)
       |> assign(:selected_task_ids, MapSet.new())
       |> assign(:tasks_select_mode, false)
       |> reload_fn.()
       |> put_flash(flash_level, flash_msg)}
    end
  end

  def handle_tasks_delete_selected(ids, socket, reload_fn) do
    deleted =
      Enum.count(ids, fn task_id ->
        case Tasks.get_task_by_uuid_or_id(task_id) do
          {:ok, task} -> match?({:ok, _}, Tasks.delete_task_with_associations(task))
          {:error, :not_found} -> false
        end
      end)

    {:noreply,
     socket
     |> assign(:selected_task_ids, MapSet.new())
     |> assign(:tasks_select_mode, false)
     |> reload_fn.()
     |> put_flash(:info, "Deleted #{deleted} task#{if deleted != 1, do: "s"}")}
  end
end
