defmodule EyeInTheSkyWeb.DmLive.Actions do
  @moduledoc """
  Handles core handle_event callbacks for DmLive.

  Keeps general-purpose UI events and CRUD operations out of the main LiveView,
  including modal toggles, note creation, message pagination, file operations, and
  display mode toggles for diffs and commits.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, push_event: 3, cancel_upload: 3]
  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]

  alias EyeInTheSky.{Notes, FileAttachments}
  alias EyeInTheSky.Claude.AgentWorker
  alias EyeInTheSkyWeb.DmLive.{FileAutocomplete, TabHelpers, ExternalActions}


  @default_message_limit 50
  @message_page_size 20

  # ---------------------------------------------------------------------------
  # PTY terminal events
  # ---------------------------------------------------------------------------

  @spec handle_pty_input(Phoenix.LiveView.Socket.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_pty_input(socket, %{"data" => data}) do
    if pid = socket.assigns[:pty_pid] do
      alias EyeInTheSky.Terminal.PtyServer
      PtyServer.write(pid, data)
    end

    {:noreply, socket}
  end

  @spec handle_pty_resize(Phoenix.LiveView.Socket.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_pty_resize(socket, %{"cols" => cols, "rows" => rows}) do
    alias EyeInTheSky.Terminal.PtyServer

    if pid = socket.assigns[:pty_pid] do
      PtyServer.resize(pid, cols, rows)
    end

    # Fire the launch command on the first resize so claude starts with correct
    # dimensions, not the 220-col PTY default from spawn time.
    socket =
      if socket.assigns[:pty_pending_launch] && socket.assigns[:pty_pid] do
        PtyServer.write(socket.assigns.pty_pid, build_launch_command(socket.assigns))
        PtyServer.mark_launched(socket.assigns.pty_pid)

        socket
        |> assign(:pty_pending_launch, false)
        |> assign(:pty_launched_at, DateTime.utc_now())
      else
        socket
      end

    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Tab & UI toggles
  # ---------------------------------------------------------------------------

  @spec handle_change_tab(Phoenix.LiveView.Socket.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_change_tab(socket, %{"tab" => tab}) do
    socket =
      socket
      |> assign(:active_tab, tab)
      |> TabHelpers.load_tab_data(tab, socket.assigns.session_id)

    {:noreply, socket}
  end

  @spec handle_toggle_context_meter(Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_toggle_context_meter(socket) do
    {:noreply, toggle_active_overlay(socket, :context_meter)}
  end

  @spec handle_toggle_new_task_drawer(Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_toggle_new_task_drawer(socket) do
    {:noreply, toggle_active_overlay(socket, :task_drawer)}
  end

  @spec handle_toggle_task_detail_drawer(Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_toggle_task_detail_drawer(socket) do
    {:noreply, toggle_active_overlay(socket, :task_detail)}
  end

  @spec handle_open_schedule_timer(Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_open_schedule_timer(socket) do
    {:noreply, assign(socket, :active_overlay, :schedule_timer)}
  end

  @spec handle_close_schedule_modal(Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_close_schedule_modal(socket) do
    {:noreply, assign(socket, :active_overlay, nil)}
  end

  # ---------------------------------------------------------------------------
  # Note CRUD — create notes on DM page
  # ---------------------------------------------------------------------------

  @spec handle_open_create_note_modal(Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_open_create_note_modal(socket) do
    {:noreply, assign(socket, :active_overlay, :create_note)}
  end

  @spec handle_close_create_note_modal(Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_close_create_note_modal(socket) do
    {:noreply, assign(socket, :active_overlay, nil)}
  end

  @spec handle_create_note(Phoenix.LiveView.Socket.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_create_note(socket, %{"title" => title, "body" => body}) do
    session_id = socket.assigns.session_id

    note_attrs = %{
      parent_type: "session",
      parent_id: to_string(session_id),
      title: if(title != "", do: title, else: nil),
      body: body
    }

    case Notes.create_note(note_attrs) do
      {:ok, _note} ->
        updated_notes = Notes.list_notes_for_session(session_id)

        socket =
          socket
          |> assign(:notes, updated_notes)
          |> assign(:active_overlay, nil)
          |> put_flash(:info, "Note created")

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create note: #{inspect(reason)}")}
    end
  end

  # ---------------------------------------------------------------------------
  # Messaging — pagination and search
  # ---------------------------------------------------------------------------

  @spec handle_remove_queued_prompt(Phoenix.LiveView.Socket.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_remove_queued_prompt(socket, %{"id" => id_str}) do
    if id = parse_int(id_str), do: AgentWorker.remove_queued_prompt(socket.assigns.session_id, id)

    {:noreply, socket}
  end

  @spec handle_load_more_messages(Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_load_more_messages(socket) do
    new_limit = (socket.assigns[:message_limit] || @default_message_limit) + @message_page_size

    socket =
      socket
      |> assign(:message_limit, new_limit)
      |> TabHelpers.force_reload_messages(socket.assigns.session_id)

    {:noreply, socket}
  end

  @spec handle_search_messages(Phoenix.LiveView.Socket.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_search_messages(socket, %{"query" => query}) do
    query = String.trim(query)

    # When clearing search (blank query), force a fresh DB load — the cache
    # holds the filtered result set and must not be reused for the full list.
    socket =
      if query == "" do
        socket
        |> assign(:message_search_query, query)
        |> TabHelpers.force_reload_messages(socket.assigns.session_id)
      else
        socket
        |> assign(:message_search_query, query)
        |> TabHelpers.load_tab_data("messages", socket.assigns.session_id)
      end

    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # File uploads & attachments
  # ---------------------------------------------------------------------------

  @spec handle_cancel_upload(Phoenix.LiveView.Socket.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_cancel_upload(socket, %{"ref" => ref}) do
    {:noreply, do_cancel_upload(socket, :files, ref)}
  end

  @spec handle_validate_upload(Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_validate_upload(socket) do
    {:noreply, socket}
  end

  @spec handle_delete_attachment(Phoenix.LiveView.Socket.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_delete_attachment(socket, %{"id" => attachment_id}) do
    case parse_int(attachment_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Invalid attachment ID")}

      id ->
        case FileAttachments.delete_attachment(id) do
          :ok ->
            {:noreply,
             put_flash(socket, :info, "Attachment deleted successfully")
             |> push_event("refresh_messages", %{})}

          {:error, reason} ->
            {:noreply,
             put_flash(socket, :error, "Failed to delete attachment: #{inspect(reason)}")}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # File autocomplete
  # ---------------------------------------------------------------------------

  @spec handle_list_files(Phoenix.LiveView.Socket.t(), map()) ::
          {:reply, any(), Phoenix.LiveView.Socket.t()}
  def handle_list_files(socket, %{"partial" => partial, "root" => root}) do
    session = socket.assigns.session
    result = FileAutocomplete.list_entries(partial, root, session)
    {:reply, result, socket}
  end

  # ---------------------------------------------------------------------------
  # Diffs & display modes
  # ---------------------------------------------------------------------------

  @spec handle_set_diff_mode(Phoenix.LiveView.Socket.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_set_diff_mode(socket, %{"mode" => mode}) when mode in ["unified", "side_by_side"] do
    {:noreply, assign(socket, :diff_mode, String.to_existing_atom(mode))}
  end

  @spec handle_set_commits_view(Phoenix.LiveView.Socket.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_set_commits_view(socket, %{"view" => view}) when view in ["list", "cumulative"] do
    socket = assign(socket, :commits_view, String.to_existing_atom(view))

    socket =
      if view == "cumulative" and socket.assigns.cumulative_diff == nil,
        do: elem(ExternalActions.handle_load_cumulative_diff(socket), 1),
        else: socket

    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp toggle_active_overlay(socket, overlay) do
    assign(socket, :active_overlay, toggle_overlay(socket.assigns.active_overlay, overlay))
  end

  defp toggle_overlay(current, target) do
    if current == target, do: nil, else: target
  end

  defp build_launch_command(assigns) do
    session = assigns[:session]
    agent = assigns[:agent]
    uuid = assigns[:session_uuid]

    # Resolve working path: session.git_worktree_path → agent.git_worktree_path → project.path
    working_path =
      nonempty(session && session.git_worktree_path) ||
        nonempty(agent && agent.git_worktree_path) ||
        nonempty(project_path(session))

    cd_part = if working_path, do: "cd #{working_path} && ", else: ""

    "#{cd_part}claude --resume #{uuid}\n"
  end

  defp nonempty(nil), do: nil
  defp nonempty(""), do: nil
  defp nonempty(val), do: val

  defp project_path(%{project: %{path: path}}), do: path
  defp project_path(_), do: nil

  defp do_cancel_upload(socket, upload_key, ref) do
    cancel_upload(socket, upload_key, ref)
  end
end
