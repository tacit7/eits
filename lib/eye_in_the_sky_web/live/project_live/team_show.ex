defmodule EyeInTheSkyWeb.ProjectLive.TeamShow do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.{Notes, Tasks, Teams}
  import EyeInTheSkyWeb.Helpers.ProjectLiveHelpers
  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]

  @impl true
  def mount(%{"id" => _, "team_id" => team_id_str} = params, _session, socket) do
    socket = mount_project(socket, params, sidebar_tab: :teams, page_title_prefix: "Team")

    team_id = parse_int(team_id_str)

    socket =
      case team_id && Teams.get_team(team_id) do
        {:ok, team} ->
          if connected?(socket) do
            EyeInTheSky.Events.subscribe_teams()
            team = load_team_detail(team)
            socket
            |> assign(:team, team)
            |> assign(:team_id, team_id)
            |> assign(:team_loaded, true)
            |> assign(:agent_session_id, nil)
            |> assign(:page_title_prefix, team.name)
          else
            socket
            |> assign(:team, team)
            |> assign(:team_id, team_id)
            |> assign(:team_loaded, false)
            |> assign(:agent_session_id, nil)
          end

        _ ->
          socket
          |> assign(:team, nil)
          |> assign(:team_id, nil)
          |> assign(:team_loaded, false)
          |> assign(:agent_session_id, nil)
      end

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_info({event, _payload}, %{assigns: %{team_id: nil}} = socket)
      when event in [:team_created, :team_deleted, :member_joined, :member_updated, :member_left],
      do: {:noreply, socket}

  def handle_info({event, _payload}, socket)
      when event in [:team_created, :team_deleted, :member_joined, :member_updated, :member_left] do
    socket =
      case Teams.get_team(socket.assigns.team_id) do
        {:ok, team} -> assign(socket, :team, load_team_detail(team))
        _ -> push_navigate(socket, to: back_path(socket))
      end

    {:noreply, socket}
  end

  def handle_info({:new_message, _message}, socket), do: {:noreply, socket}

  @impl true
  def handle_event("select_agent", %{"id" => session_id_str}, socket) do
    case parse_int(session_id_str) do
      nil ->
        {:noreply, socket}

      session_id ->
        member = Enum.find(socket.assigns.team.members, &(&1.session_id == session_id))

        socket =
          socket
          |> assign(:agent_session_id, session_id)
          |> maybe_open_fab_chat(member)

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("assign_task", %{"task-id" => task_id, "session-id" => session_id}, socket) do
    case {parse_int(task_id), parse_int(session_id)} do
      {nil, _} ->
        {:noreply, socket}

      {_, nil} ->
        {:noreply, socket}

      {task_id_int, session_id_int} ->
        Tasks.link_session_to_task(task_id_int, session_id_int)
        team = Teams.get_team!(socket.assigns.team_id) |> load_team_detail()
        {:noreply, assign(socket, :team, team)}
    end
  end

  @impl true
  def handle_event(event, _params, socket)
      when event in [
             "archive_session",
             "rename_session",
             "save_session_name",
             "cancel_rename",
             "toggle_select",
             "noop"
           ] do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="overflow-y-auto" style="scrollbar-width: none;">
      <%= if @team do %>
        <div class="px-4 sm:px-6 pt-4 pb-2 border-b border-base-content/8">
          <.link
            navigate={back_path(assigns)}
            class="inline-flex items-center gap-1.5 text-xs text-base-content/45 hover:text-base-content/70 transition-colors mb-2"
          >
            <.icon name="hero-arrow-left" class="size-3.5" /> Teams
          </.link>
        </div>
        <%= if @team_loaded do %>
          <.live_component
            module={EyeInTheSkyWeb.TeamDetailComponent}
            id="team-show-detail"
            team={@team}
            selected_agent_session_id={@agent_session_id}
          />
        <% end %>
      <% else %>
        <div class="px-4 sm:px-6 pt-4">
          <.link
            navigate={back_path(assigns)}
            class="inline-flex items-center gap-1.5 text-xs text-base-content/45 hover:text-base-content/70 transition-colors mb-4"
          >
            <.icon name="hero-arrow-left" class="size-3.5" /> Teams
          </.link>
          <.empty_state
            id="team-not-found"
            icon="hero-user-group"
            title="Team not found"
            subtitle="It may have been deleted"
          />
        </div>
      <% end %>
    </div>
    """
  end

  defp back_path(%{assigns: %{project: %{id: id}}}), do: ~p"/projects/#{id}/teams"
  defp back_path(_), do: ~p"/"

  defp load_team_detail(team) do
    team = Teams.preload_members(team)

    tasks =
      Tasks.list_tasks_for_team_with_sessions(team.id)
      |> Notes.with_notes_count()

    member_session_ids = Enum.map(team.members, & &1.session_id) |> MapSet.new()

    tasks_by_session =
      Enum.reduce(tasks, %{}, &group_task_by_sessions(&1, &2, member_session_ids))

    unowned_tasks =
      Enum.filter(tasks, fn t ->
        Enum.empty?(Enum.filter(t.session_ids, &MapSet.member?(member_session_ids, &1)))
      end)

    members_with_tasks =
      Enum.map(team.members, fn m ->
        Map.put(m, :tasks, tasks_by_session |> Map.get(m.session_id, []) |> Enum.reverse())
      end)

    team
    |> Map.put(:tasks, tasks)
    |> Map.put(:members, members_with_tasks)
    |> Map.put(:unowned_tasks, unowned_tasks)
  end

  defp group_task_by_sessions(task, acc, member_session_ids) do
    matched = Enum.filter(task.session_ids, &MapSet.member?(member_session_ids, &1))

    case matched do
      [] -> acc
      sids -> Enum.reduce(sids, acc, fn sid, a -> Map.update(a, sid, [task], &[task | &1]) end)
    end
  end

  defp maybe_open_fab_chat(socket, nil), do: socket

  defp maybe_open_fab_chat(socket, member) do
    session_id =
      if member.session,
        do: to_string(member.session.uuid || member.session_id),
        else: to_string(member.session_id)

    push_event(socket, "open_fab_chat", %{
      session_id: session_id,
      name: member.name || "Agent",
      status: member.status || "idle"
    })
  end
end
