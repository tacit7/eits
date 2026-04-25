defmodule EyeInTheSkyWeb.ProjectLive.Sessions.Actions do
  @moduledoc """
  Session CRUD, bulk operations, navigation, and rename actions for the
  project sessions LiveView.
  """

  require Logger

  use Phoenix.VerifiedRoutes,
    endpoint: EyeInTheSkyWeb.Endpoint,
    router: EyeInTheSkyWeb.Router,
    statics: EyeInTheSkyWeb.static_paths()

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_navigate: 2, put_flash: 3, stream_insert: 3]

  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSky.Canvases
  alias EyeInTheSky.Sessions
  alias EyeInTheSkyWeb.ControllerHelpers
  import EyeInTheSkyWeb.Helpers.AgentCreationHelpers, only: [build_opts: 2]
  alias EyeInTheSkyWeb.ProjectLive.Sessions.Loader
  alias EyeInTheSkyWeb.ProjectLive.Sessions.Selection

  # ---------------------------------------------------------------------------
  # Session lifecycle
  # ---------------------------------------------------------------------------

  def create_new_session(params, socket) do
    project = socket.assigns.project
    description = params["description"]
    agent_name = params["agent_name"] || String.slice(description || "", 0, 60)

    opts =
      build_opts(params,
        project_path: project.path,
        description: agent_name,
        instructions: description
      )
      |> Keyword.put(:project_id, project.id)

    case AgentManager.create_agent(opts) do
      {:ok, _result} ->
        socket =
          socket
          |> assign(:show_new_session_drawer, false)
          |> Loader.load_agents()
          |> put_flash(:info, "Session launched")

        {:noreply, socket}

      {:error, reason} ->
        Logger.error("create_new_session failed: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Failed to create session: #{inspect(reason)}")}
    end
  end

  def archive_session(%{"session_id" => session_id}, socket) do
    with {:ok, session} <- Sessions.get_session(session_id),
         {:ok, _} <- Sessions.archive_session(session) do
      {:noreply, socket |> Loader.load_agents() |> put_flash(:info, "Session archived")}
    else
      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Session not found")}

      {:error, reason} ->
        Logger.warning("archive_session failed for #{session_id}: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Failed to archive session")}
    end
  end

  def unarchive_session(%{"session_id" => session_id}, socket) do
    with {:ok, session} <- Sessions.get_session(session_id),
         {:ok, _} <- Sessions.unarchive_session(session) do
      {:noreply, socket |> Loader.load_agents() |> put_flash(:info, "Session unarchived")}
    else
      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Session not found")}

      {:error, reason} ->
        Logger.warning("unarchive_session failed for #{session_id}: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Failed to unarchive session")}
    end
  end

  def delete_session(%{"session_id" => session_id}, socket) do
    with {:ok, session} <- Sessions.get_session(session_id),
         {:ok, _} <- Sessions.delete_session(session) do
      {:noreply, socket |> Loader.load_agents() |> put_flash(:info, "Session deleted")}
    else
      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Session not found")}

      {:error, reason} ->
        Logger.warning("delete_session failed for #{session_id}: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Failed to delete session")}
    end
  end

  # ---------------------------------------------------------------------------
  # Bulk selection
  # ---------------------------------------------------------------------------

  def toggle_select(%{"id" => raw_id}, socket) do
    id = Selection.normalize_id(raw_id)
    prev_indeterminate = socket.assigns.indeterminate_ids

    selected =
      if MapSet.member?(socket.assigns.selected_ids, id),
        do: MapSet.delete(socket.assigns.selected_ids, id),
        else: MapSet.put(socket.assigns.selected_ids, id)

    new_indeterminate = Selection.compute_indeterminate_ids(selected, socket.assigns.agents)

    socket =
      socket
      |> assign(:selected_ids, selected)
      |> assign(:select_mode, MapSet.size(selected) > 0)
      |> assign(:indeterminate_ids, new_indeterminate)
      |> assign(:off_screen_selected_count, Selection.off_screen_count(selected, socket.assigns.agents))

    # Stream-insert the toggled row so its selected class re-renders immediately.
    # Also re-insert any rows whose indeterminate state changed (parent rows).
    changed_ids = MapSet.union(
      MapSet.symmetric_difference(prev_indeterminate, new_indeterminate),
      MapSet.new([id])
    )

    socket =
      Enum.reduce(socket.assigns.agents, socket, fn agent, acc ->
        if MapSet.member?(changed_ids, Selection.normalize_id(agent.id)) do
          stream_insert(acc, :session_list, agent)
        else
          acc
        end
      end)

    {:noreply, socket}
  end

  def exit_select_mode(_params, socket) do
    {:noreply, Selection.clear_selection(socket)}
  end

  def enter_select_mode(_params, socket) do
    {:noreply, assign(socket, :select_mode, true)}
  end

  def toggle_select_all(_params, socket) do
    selected = Selection.select_all_visible(socket.assigns.selected_ids, socket.assigns.agents)

    socket =
      socket
      |> assign(:selected_ids, selected)
      |> assign(:select_mode, MapSet.size(selected) > 0)
      |> assign(:indeterminate_ids, Selection.compute_indeterminate_ids(selected, socket.assigns.agents))
      |> assign(:off_screen_selected_count, Selection.off_screen_count(selected, socket.assigns.agents))

    {:noreply, socket}
  end

  def select_range(
        %{"anchor_id" => anchor_id, "target_id" => target_id, "ordered_ids" => raw_ordered_ids},
        socket
      ) do
    # Filter client-provided IDs against visible agents to prevent scope leakage
    visible_ids = Selection.ids_from_agents(socket.assigns.agents)

    ordered_ids =
      raw_ordered_ids
      |> Enum.map(&Selection.normalize_id/1)
      |> Enum.filter(&MapSet.member?(visible_ids, &1))

    anchor = Selection.normalize_id(anchor_id)
    target = Selection.normalize_id(target_id)

    anchor_idx = Enum.find_index(ordered_ids, &(&1 == anchor))
    target_idx = Enum.find_index(ordered_ids, &(&1 == target))

    # If anchor or target are not in visible rows (invalid/stale), do nothing
    if is_nil(anchor_idx) or is_nil(target_idx) do
      {:noreply, socket}
    else
      range_ids =
        ordered_ids
        |> Enum.slice(min(anchor_idx, target_idx)..max(anchor_idx, target_idx))
        |> MapSet.new()

      selected = MapSet.union(socket.assigns.selected_ids, range_ids)

      socket =
        socket
        |> assign(:selected_ids, selected)
        |> assign(:select_mode, MapSet.size(selected) > 0)
        |> assign(:indeterminate_ids, Selection.compute_indeterminate_ids(selected, socket.assigns.agents))
        |> assign(:off_screen_selected_count, Selection.off_screen_count(selected, socket.assigns.agents))

      {:noreply, socket}
    end
  end

  def confirm_archive_selected(_params, socket) do
    {:noreply, assign(socket, :show_archive_confirm, true)}
  end

  def cancel_archive_selected(_params, socket) do
    {:noreply, assign(socket, :show_archive_confirm, false)}
  end

  def archive_selected(_params, socket) do
    if MapSet.size(socket.assigns.selected_ids) == 0 do
      {:noreply, assign(socket, :show_archive_confirm, false)}
    else
      project_id = socket.assigns.project.id

      results =
        Enum.map(socket.assigns.selected_ids, fn id ->
          with {:ok, session} <- fetch_project_session(project_id, id),
               :ok <- archive_project_session(session) do
            :ok
          else
            {:error, :not_found} -> :error
            {:error, reason} ->
              Logger.warning("bulk archive: failed for session #{id}: #{inspect(reason)}")
              :error
          end
        end)

      archived = Enum.count(results, &(&1 == :ok))
      failed = length(results) - archived

      {flash_level, flash_msg} =
        cond do
          archived > 0 and failed > 0 ->
            {:info, "Archived #{archived} #{pluralize_session(archived)}; #{failed} could not be archived"}
          archived > 0 ->
            {:info, "Archived #{archived} #{pluralize_session(archived)}"}
          true ->
            {:error, "Could not archive #{failed} #{pluralize_session(failed)}"}
        end

      socket =
        socket
        |> assign(:show_archive_confirm, false)
        |> Selection.clear_selection()
        |> Loader.load_agents()
        |> put_flash(flash_level, flash_msg)

      {:noreply, socket}
    end
  end

  defp pluralize_session(count), do: if(count == 1, do: "session", else: "sessions")

  defp fetch_project_session(project_id, raw_id) do
    id = Selection.normalize_id(raw_id)

    with {:ok, session} <- Sessions.get_session(id) do
      if session.project_id == project_id, do: {:ok, session}, else: {:error, :not_found}
    end
  end

  defp archive_project_session(session) do
    case Sessions.archive_session(session) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
      _ -> :ok
    end
  end

  def delete_selected(_params, socket) do
    results =
      Enum.map(socket.assigns.selected_ids, fn id ->
        with {:ok, session} <- Sessions.get_session(id),
             {:ok, _} <- Sessions.delete_session(session) do
          :ok
        else
          {:error, :not_found} ->
            :error

          {:error, reason} ->
            Logger.warning("bulk delete: failed to delete session #{id}: #{inspect(reason)}")
            :error
        end
      end)

    deleted = Enum.count(results, &(&1 == :ok))

    socket =
      socket
      |> assign(:selected_ids, MapSet.new())
      |> Loader.load_agents()
      |> put_flash(:info, "Deleted #{deleted} session#{if deleted != 1, do: "s"}")

    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Navigation & rename
  # ---------------------------------------------------------------------------

  def navigate_dm(%{"id" => id}, socket) do
    path =
      case socket.assigns do
        %{scope: :all} -> ~p"/dm/#{id}"
        %{project_id: project_id} -> ~p"/dm/#{id}?from=project&project_id=#{project_id}"
      end

    {:noreply, push_navigate(socket, to: path)}
  end

  def rename_session(%{"session_id" => session_id}, socket) do
    session_id_int = ControllerHelpers.parse_int(session_id)
    socket = assign(socket, :editing_session_id, session_id_int)

    socket =
      case Enum.find(socket.assigns.agents, &(&1.id == session_id_int)) do
        nil -> socket
        session -> stream_insert(socket, :session_list, session)
      end

    {:noreply, socket}
  end

  def save_session_name(%{"session_id" => session_id, "name" => name}, socket) do
    name = String.trim(name)

    if name != "" do
      case Sessions.get_session(session_id) do
        {:ok, session} -> Sessions.update_session(session, %{name: name})
        _ -> :noop
      end
    end

    {:noreply, assign(socket, :editing_session_id, nil) |> Loader.load_agents()}
  end

  def cancel_rename(_params, socket) do
    editing_id = socket.assigns.editing_session_id
    socket = assign(socket, :editing_session_id, nil)

    socket =
      case editing_id && Enum.find(socket.assigns.agents, &(&1.id == editing_id)) do
        nil -> socket
        session -> stream_insert(socket, :session_list, session)
      end

    {:noreply, socket}
  end

  def noop(_params, socket), do: {:noreply, socket}

  # ---------------------------------------------------------------------------
  # Canvas actions
  # ---------------------------------------------------------------------------

  def show_new_canvas_form(%{"agent-id" => id}, socket) do
    {:noreply, assign(socket, :show_new_canvas_for, id)}
  end

  def add_to_canvas(%{"canvas-id" => cid, "session-id" => sid}, socket) do
    with canvas_id when not is_nil(canvas_id) <- ControllerHelpers.parse_int(cid),
         session_id when not is_nil(session_id) <- ControllerHelpers.parse_int(sid),
         {:ok, canvas} <- Canvases.get_canvas(canvas_id) do
      Canvases.add_session(canvas_id, session_id)

      {:noreply,
       socket
       |> put_flash(:info, "Added to #{canvas.name}")
       |> push_navigate(to: "/canvases/#{canvas_id}")}
    else
      nil -> {:noreply, put_flash(socket, :error, "Invalid canvas or session ID")}
      {:error, :not_found} -> {:noreply, put_flash(socket, :error, "Canvas not found")}
    end
  end

  def add_to_new_canvas(%{"session_id" => sid, "canvas_name" => name}, socket) do
    case ControllerHelpers.parse_int(sid) do
      nil ->
        {:noreply, socket}

      session_id ->
        canvas_name =
          if not is_nil(name) && String.trim(name) != "",
            do: String.trim(name),
            else: "Canvas #{:os.system_time(:second)}"

        case Canvases.create_canvas(%{name: canvas_name}) do
          {:ok, canvas} ->
            Canvases.add_session(canvas.id, session_id)

            {:noreply,
             socket
             |> put_flash(:info, "Added to #{canvas.name}")
             |> push_navigate(to: "/canvases/#{canvas.id}")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to create canvas")}
        end
    end
  end
end
