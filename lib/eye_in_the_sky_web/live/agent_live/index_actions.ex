defmodule EyeInTheSkyWeb.AgentLive.IndexActions do
  @moduledoc """
  Handles non-canvas handle_event callbacks for AgentLive.Index.

  Each public function corresponds to a handle_event in index.ex and is called
  via thin delegation. load_agents/1 is also public so index.ex mount and
  handle_info callbacks can reuse it.
  """

  use Phoenix.VerifiedRoutes,
    endpoint: EyeInTheSkyWeb.Endpoint,
    router: EyeInTheSkyWeb.Router,
    statics: EyeInTheSkyWeb.static_paths()

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, push_navigate: 2]
  import EyeInTheSkyWeb.Helpers.ChannelRoutingHelpers
  import EyeInTheSkyWeb.Helpers.SessionFilters
  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]

  alias EyeInTheSky.Agents
  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSky.Sessions
  alias EyeInTheSkyWeb.Helpers.AgentCreationHelpers

  require Logger

  def load_agents(socket) do
    include_archived = socket.assigns.session_filter == "archived"
    db_agents = Sessions.list_sessions_with_agent(include_archived: include_archived)

    project_map =
      socket.assigns.projects
      |> Enum.into(%{}, fn p -> {p.id, p.name} end)

    agents =
      db_agents
      |> Enum.map(fn s -> Map.put(s, :project_name, project_map[s.project_id]) end)
      |> filter_agents_by_status(socket.assigns.session_filter)
      |> filter_agents_by_search(socket.assigns.search_query)
      |> sort_agents(socket.assigns.sort_by)

    assign(socket, :agents, agents)
  end

  def handle_send_direct_message(
        %{"session_id" => target_session_id, "body" => body},
        socket
      ) do
    with {:channel, {:ok, global_channel}} <-
           {:channel, find_global_channel_for_session(target_session_id)},
         {:send, {:ok, _message}} <-
           {:send, create_dm_channel_message(global_channel.id, body, "web-user")} do
      maybe_continue_session(target_session_id, body)
      {:noreply, socket}
    else
      {:channel, {:error, :session_not_found}} ->
        {:noreply, put_flash(socket, :error, "Session not found")}

      {:channel, _} ->
        {:noreply, put_flash(socket, :error, "Global channel not found")}

      {:send, _} ->
        {:noreply, put_flash(socket, :error, "Failed to send message")}
    end
  end

  def handle_search(%{"query" => query}, socket) do
    effective_query = if String.length(String.trim(query)) >= 3, do: query, else: ""

    socket =
      socket
      |> assign(:search_query, effective_query)
      |> load_agents()

    {:noreply, socket}
  end

  def handle_filter_session(%{"filter" => filter}, socket) do
    socket =
      socket
      |> assign(:session_filter, filter)
      |> assign(:selected_ids, MapSet.new())
      |> load_agents()

    {:noreply, socket}
  end

  def handle_sort(%{"by" => sort_by}, socket) do
    socket =
      socket
      |> assign(:sort_by, sort_by)
      |> load_agents()

    {:noreply, socket}
  end

  def handle_session_action(action, %{"session_id" => session_id}, socket)
      when action in ["archive_session", "unarchive_session", "delete_session"] do
    with {:ok, session} <- Sessions.get_session(session_id),
         {:ok, _} <- apply_session_action(action, session) do
      {:noreply, socket |> load_agents() |> put_flash(:info, "Session #{action_label(action)}")}
    else
      {:error, reason} ->
        Logger.error("#{action} failed for #{session_id}: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Failed to #{action_label(action)}")}
    end
  end

  def handle_toggle_select(%{"id" => id}, socket) do
    selected =
      if MapSet.member?(socket.assigns.selected_ids, id),
        do: MapSet.delete(socket.assigns.selected_ids, id),
        else: MapSet.put(socket.assigns.selected_ids, id)

    {:noreply, assign(socket, :selected_ids, selected)}
  end

  def handle_toggle_select_all(_params, socket) do
    all_ids = MapSet.new(socket.assigns.agents, &to_string(&1.id))

    selected =
      if MapSet.equal?(socket.assigns.selected_ids, all_ids),
        do: MapSet.new(),
        else: all_ids

    {:noreply, assign(socket, :selected_ids, selected)}
  end

  def handle_confirm_delete_selected(_params, socket) do
    {:noreply, assign(socket, :show_delete_confirm, true)}
  end

  def handle_cancel_delete_selected(_params, socket) do
    {:noreply, assign(socket, :show_delete_confirm, false)}
  end

  def handle_delete_selected(_params, socket) do
    ids = socket.assigns.selected_ids

    results =
      Enum.map(ids, fn id ->
        with {:ok, agent} <- Sessions.get_session(id),
             {:ok, _} <- Sessions.delete_session(agent) do
          :ok
        else
          _ -> :error
        end
      end)

    deleted = Enum.count(results, &(&1 == :ok))

    socket =
      socket
      |> assign(:selected_ids, MapSet.new())
      |> assign(:show_delete_confirm, false)
      |> load_agents()
      |> put_flash(:info, "Deleted #{deleted} session#{if deleted != 1, do: "s"}")

    {:noreply, socket}
  end

  def handle_navigate_dm(%{"id" => id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/dm/#{id}")}
  end

  def handle_rename_session(%{"session_id" => session_id}, socket) do
    case parse_int(session_id) do
      nil -> {:noreply, socket}
      id -> {:noreply, assign(socket, :editing_session_id, id)}
    end
  end

  def handle_save_session_name(%{"session_id" => session_id, "name" => name}, socket) do
    name = String.trim(name)

    if name != "", do: rename_session(session_id, name)

    {:noreply, socket |> assign(:editing_session_id, nil) |> load_agents()}
  end

  def handle_cancel_rename(_params, socket) do
    {:noreply, assign(socket, :editing_session_id, nil)}
  end

  def handle_toggle_new_session_drawer(_params, socket) do
    {:noreply, assign(socket, :show_new_session_drawer, !socket.assigns.show_new_session_drawer)}
  end

  def handle_create_new_session(params, socket) do
    project_id = parse_int(params["project_id"])

    if is_nil(project_id) do
      {:noreply, put_flash(socket, :error, "Invalid project")}
    else
      create_new_session_with_project(params, project_id, socket)
    end
  end

  def handle_noop(_params, socket), do: {:noreply, socket}

  # -- Private helpers -------------------------------------------------------

  defp maybe_continue_session(target_session_id, body) do
    with {:ok, session} <- Sessions.get_session(target_session_id),
         {:ok, chat_agent} <- Agents.get_agent(session.agent_id) do
      project_path =
        chat_agent.git_worktree_path ||
          (chat_agent.project && chat_agent.project.path)

      AgentManager.continue_session(
        session.id,
        direct_message_prompt(body),
        model: "sonnet",
        project_path: project_path
      )
    else
      _ ->
        Logger.warning(
          "maybe_continue_session: could not continue session #{target_session_id}, message already sent"
        )
    end
  end

  defp rename_session(session_id, name) do
    case Sessions.get_session(session_id) do
      {:ok, session} ->
        case Sessions.update_session(session, %{name: name}) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            Logger.warning(
              "save_session_name: failed to rename session #{session_id}: #{inspect(reason)}"
            )
        end

      _ ->
        :ok
    end
  end

  defp apply_session_action("archive_session", session), do: Sessions.archive_session(session)
  defp apply_session_action("unarchive_session", session), do: Sessions.unarchive_session(session)
  defp apply_session_action("delete_session", session), do: Sessions.delete_session(session)

  defp action_label("archive_session"), do: "archived"
  defp action_label("unarchive_session"), do: "unarchived"
  defp action_label("delete_session"), do: "deleted"

  defp create_new_session_with_project(params, project_id, socket) do
    case EyeInTheSky.Projects.get_project(project_id) do
      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Project not found")}

      {:ok, project} ->
        do_create_session(params, project, socket)
    end
  end

  defp do_create_session(params, project, socket) do
    description = params["description"]
    agent_name = params["agent_name"] || String.slice(description || "", 0, 60)

    opts =
      AgentCreationHelpers.build_opts(params,
        project_path: project.path,
        description: agent_name,
        instructions: description
      )

    opts =
      opts
      |> Keyword.put(:project_id, project.id)
      |> Keyword.put(:name, if(agent_name != "", do: agent_name))

    Logger.info(
      "create_new_session: model=#{opts[:model]}, effort=#{inspect(opts[:effort_level])}, project_id=#{project.id}, project_path=#{project.path}"
    )

    case AgentManager.create_agent(opts) do
      {:ok, result} ->
        Logger.info(
          "create_new_session: agent created - agent_id=#{result.agent.id}, session_id=#{result.agent.id}, session_uuid=#{result.agent.uuid}"
        )

        {:noreply,
         socket
         |> assign(:show_new_session_drawer, false)
         |> push_navigate(to: ~p"/dm/#{result.session.id}")}

      {:error, reason} ->
        Logger.error("create_new_session: failed - #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Failed to create session: #{inspect(reason)}")}
    end
  end

  defp direct_message_prompt(body) do
    """
    REMINDER: Use i-chat-send MCP tool to send your response to the channel.

    User message: #{body}
    """
  end
end
