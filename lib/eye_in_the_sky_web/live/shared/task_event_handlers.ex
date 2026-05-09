defmodule EyeInTheSkyWeb.Live.Shared.TaskEventHandlers do
  @moduledoc """
  Consolidated task event handlers for LiveViews that manage tasks.

  This module provides a unified interface for task event handling shared across
  multiple LiveViews (dm_live, project_live/tasks, project_live/kanban).
  It delegates to TasksHelpers while adding support for context-specific cleanup.

  Each LiveView can import or alias this module and provide its own reload_fn callback
  that reloads tasks in the context appropriate for that view.
  """

  alias EyeInTheSkyWeb.Live.Shared.TasksHelpers

  # Re-export core task handlers from TasksHelpers
  defdelegate handle_update_task(params, socket, reload_fn), to: TasksHelpers
  defdelegate handle_create_new_task(params, socket, reload_fn), to: TasksHelpers
  defdelegate handle_add_task_annotation(params, socket), to: TasksHelpers
  defdelegate handle_quick_add_task(params, socket, reload_fn), to: TasksHelpers
  defdelegate handle_open_task_detail(params, socket), to: TasksHelpers
  defdelegate handle_open_task_detail_with_overlay(params, socket, overlay_value), to: TasksHelpers
  defdelegate handle_toggle_task_detail_drawer(params, socket), to: TasksHelpers
  defdelegate handle_toggle_select_task(task_id, socket), to: TasksHelpers
  defdelegate handle_toggle_select_all_tasks(socket), to: TasksHelpers
  defdelegate handle_enter_select_mode(socket), to: TasksHelpers
  defdelegate handle_exit_select_mode(socket), to: TasksHelpers
  defdelegate handle_open_filter_sheet(params, socket), to: TasksHelpers
  defdelegate handle_close_filter_sheet(params, socket), to: TasksHelpers
  defdelegate handle_search(params, socket, reload_fn), to: TasksHelpers
  defdelegate handle_load_more(params, socket, load_page_fn), to: TasksHelpers
  defdelegate handle_tasks_changed(socket, reload_fn), to: TasksHelpers

  @doc """
  Handles task delete event with optional pre-delete cleanup.

  For LiveViews that use overlay-based UI (dm_live), pass cleanup_fn
  to close the overlay before deletion. Default cleanup_fn is identity function.

  Example:
    cleanup_fn = fn s -> assign(s, :active_overlay, nil) end
    handle_delete_task(params, socket, &reload_tasks/1, cleanup_fn)
  """
  def handle_delete_task(params, socket, reload_fn, cleanup_fn \\ fn s -> s end) do
    socket = cleanup_fn.(socket)
    TasksHelpers.handle_delete_task(params, socket, reload_fn)
  end

  @doc """
  Handles task archive event with optional pre-archive cleanup.

  For LiveViews that use overlay-based UI (dm_live), pass cleanup_fn
  to close the overlay before archiving. Default cleanup_fn is identity function.
  """
  def handle_archive_task(params, socket, reload_fn, cleanup_fn \\ fn s -> s end) do
    socket = cleanup_fn.(socket)
    TasksHelpers.handle_archive_task(params, socket, reload_fn)
  end

  @doc """
  Generic task event dispatcher that routes events to appropriate handlers.

  This is useful for LiveViews that want to consolidate event handling,
  though it requires all reload_fn and cleanup_fn context to be available
  in socket assigns.

  Expected assign keys:
  - :reload_fn - function reference to reload tasks in appropriate context
  - :cleanup_fn (optional) - function to call before delete/archive operations

  Returns {:noreply, socket} for unknown events.
  """
  def dispatch_task_event(event, params, socket) do
    reload_fn = socket.assigns[:reload_fn]
    cleanup_fn = socket.assigns[:cleanup_fn] || fn s -> s end

    case event do
      "update_task" -> handle_update_task(params, socket, reload_fn)
      "delete_task" -> handle_delete_task(params, socket, reload_fn, cleanup_fn)
      "archive_task" -> handle_archive_task(params, socket, reload_fn, cleanup_fn)
      "create_new_task" -> handle_create_new_task(params, socket, reload_fn)
      "add_task_annotation" -> handle_add_task_annotation(params, socket)
      "quick_add_task" -> handle_quick_add_task(params, socket, reload_fn)
      _ -> {:noreply, socket}
    end
  end
end
