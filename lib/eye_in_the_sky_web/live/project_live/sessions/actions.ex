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

  alias EyeInTheSky.Sessions
  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSkyWeb.ProjectLive.Sessions.Loader

  # ---------------------------------------------------------------------------
  # Session lifecycle
  # ---------------------------------------------------------------------------

  def create_new_session(params, socket) do
    agent_type = params["agent_type"] || "claude"
    model = params["model"]
    effort_level = params["effort_level"]
    project = socket.assigns.project
    description = params["description"]
    agent_name = params["agent_name"] || String.slice(description || "", 0, 60)

    opts = [
      agent_type: agent_type,
      model: model,
      effort_level: effort_level,
      project_id: project.id,
      project_path: project.path,
      description: agent_name,
      instructions: description,
      agent: params["agent"]
    ]

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
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to archive session")}
    end
  end

  def unarchive_session(%{"session_id" => session_id}, socket) do
    with {:ok, session} <- Sessions.get_session(session_id),
         {:ok, _} <- Sessions.unarchive_session(session) do
      {:noreply, socket |> Loader.load_agents() |> put_flash(:info, "Session unarchived")}
    else
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to unarchive session")}
    end
  end

  def delete_session(%{"session_id" => session_id}, socket) do
    with {:ok, session} <- Sessions.get_session(session_id),
         {:ok, _} <- Sessions.delete_session(session) do
      {:noreply, socket |> Loader.load_agents() |> put_flash(:info, "Session deleted")}
    else
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to delete session")}
    end
  end

  # ---------------------------------------------------------------------------
  # Bulk selection
  # ---------------------------------------------------------------------------

  def toggle_select(%{"id" => id}, socket) do
    selected =
      if MapSet.member?(socket.assigns.selected_ids, id),
        do: MapSet.delete(socket.assigns.selected_ids, id),
        else: MapSet.put(socket.assigns.selected_ids, id)

    {:noreply, assign(socket, :selected_ids, selected)}
  end

  def toggle_select_all(_params, socket) do
    all_ids = MapSet.new(socket.assigns.agents, &to_string(&1.id))

    selected =
      if MapSet.equal?(socket.assigns.selected_ids, all_ids),
        do: MapSet.new(),
        else: all_ids

    {:noreply, assign(socket, :selected_ids, selected)}
  end

  def delete_selected(_params, socket) do
    results =
      Enum.map(socket.assigns.selected_ids, fn id ->
        with {:ok, session} <- Sessions.get_session(id),
             {:ok, _} <- Sessions.delete_session(session) do
          :ok
        else
          _ -> :error
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
    project_id = socket.assigns.project_id
    {:noreply, push_navigate(socket, to: ~p"/dm/#{id}?from=project&project_id=#{project_id}")}
  end

  def rename_session(%{"session_id" => session_id}, socket) do
    session_id_int = String.to_integer(session_id)
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
end
