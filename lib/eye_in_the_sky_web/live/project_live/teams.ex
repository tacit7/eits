defmodule EyeInTheSkyWeb.ProjectLive.Teams do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.{Notes, Tasks, Teams}
  import EyeInTheSkyWeb.Helpers.ProjectLiveHelpers
  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]

  @impl true
  def mount(%{"id" => _} = params, _session, socket) do
    if connected?(socket) do
      EyeInTheSky.Events.subscribe_teams()
    end

    socket = mount_project(socket, params, sidebar_tab: :teams, page_title_prefix: "Teams")

    show_all = false

    {:ok,
     socket
     |> assign(:show_archived, false)
     |> assign(:search_query, "")
     |> assign(:show_all, show_all)
     |> assign(:teams, if(connected?(socket), do: load_teams(socket, false, show_all), else: []))
     |> assign(:selected_team_id, nil)
     |> assign(:selected_team, nil)
     |> assign(:mobile_view, :list)
     |> assign(:agent_session_id, nil)}
  end

  @impl true
  def handle_params(%{"show_all" => "true"} = _params, _uri, socket) do
    teams = load_teams(socket, socket.assigns.show_archived, true)
    {:noreply, socket |> assign(:show_all, true) |> assign(:teams, teams)}
  end

  def handle_params(_params, _uri, socket) do
    teams = load_teams(socket, socket.assigns.show_archived, false)
    {:noreply, socket |> assign(:show_all, false) |> assign(:teams, teams)}
  end

  @impl true
  def handle_info({event, _payload}, socket)
      when event in [:team_created, :team_deleted, :member_joined, :member_updated, :member_left] do
    {:noreply,
     socket
     |> assign(:teams, load_teams(socket, socket.assigns.show_archived, socket.assigns.show_all))
     |> maybe_refresh_selected_team()}
  end

  @impl true
  def handle_info({:new_message, _message}, socket), do: {:noreply, socket}

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, assign(socket, :search_query, query)}
  end

  @impl true
  def handle_event("delete_team", %{"id" => id}, socket) do
    with_parsed_int(socket, id, fn team_id ->
      team = Teams.get_team!(team_id)
      {:ok, _} = Teams.delete_team(team)

      socket =
        socket
        |> assign(:teams, load_teams(socket, socket.assigns.show_archived, socket.assigns.show_all))
        |> maybe_close_if_deleted(team.id)

      {:noreply, socket}
    end)
  end

  @impl true
  def handle_event("select_team", %{"id" => id}, socket) do
    with_parsed_int(socket, id, fn team_id ->
      team = Teams.get_team!(team_id) |> load_team_detail()
      {:noreply, socket |> assign(:agent_session_id, nil) |> show_team_detail(team_id, team)}
    end)
  end

  @impl true
  def handle_event("close_team", _params, socket) do
    {:noreply, socket |> assign(:agent_session_id, nil) |> show_team_list()}
  end

  @impl true
  def handle_event("select_agent", %{"id" => session_id_str}, socket) do
    with_parsed_int(socket, session_id_str, fn session_id ->
      member = Enum.find(socket.assigns.selected_team.members, &(&1.session_id == session_id))

      socket =
        socket
        |> assign(:agent_session_id, session_id)
        |> maybe_open_fab_chat(member)

      {:noreply, socket}
    end)
  end

  # No-ops for session_row swipe actions (not applicable in teams context)
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
  def handle_event("toggle_archived", _params, socket) do
    show_archived = !socket.assigns.show_archived

    {:noreply,
     socket
     |> assign(:show_archived, show_archived)
     |> assign(:teams, load_teams(socket, show_archived, socket.assigns.show_all))}
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
        team = Teams.get_team!(socket.assigns.selected_team_id) |> load_team_detail()
        {:noreply, assign(socket, :selected_team, team)}
    end
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :filtered_teams, filter_teams(assigns.teams, assigns.search_query))

    ~H"""
    <div class="bg-base-100 min-h-full px-4 sm:px-6 lg:px-8">
      <div class="max-w-4xl mx-auto">
        <%!-- LIST VIEW --%>
        <div class={@mobile_view == :detail && "hidden"}>
          <%!-- Header --%>
          <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between py-5">
            <span class="text-[11px] font-mono tabular-nums text-base-content/45 tracking-wider uppercase">
              {length(@filtered_teams)} teams
              <%= if @show_all do %>
                <span class="ml-1 text-primary">(all projects)</span>
              <% end %>
            </span>
            <div class="flex items-center gap-2">
              <%= if @project do %>
                <.link
                  navigate={~p"/projects/#{@project.id}/teams?show_all=true"}
                  class={[
                    "text-xs font-medium px-2 py-1 rounded transition-colors min-h-[44px] inline-flex items-center",
                    if(@show_all,
                      do: "bg-base-content/10 text-base-content/60",
                      else: "text-base-content/30 hover:text-base-content/50"
                    )
                  ]}
                >
                  {if @show_all, do: "Showing all", else: "Show all projects"}
                </.link>
              <% end %>
              <button
                phx-click="toggle_archived"
                class={[
                  "text-xs font-medium px-2 py-1 rounded transition-colors min-h-[44px] inline-flex items-center",
                  if(@show_archived,
                    do: "bg-base-content/10 text-base-content/60",
                    else: "text-base-content/30 hover:text-base-content/50"
                  )
                ]}
              >
                {if @show_archived, do: "Hide archived", else: "Show archived"}
              </button>
            </div>
          </div>

          <%!-- Teams list --%>
          <div class="rounded-xl shadow-sm">
            <%= if @filtered_teams == [] do %>
              <div class="flex flex-col items-center justify-center py-16 px-4 text-center gap-3 bg-base-100 rounded-xl">
                <div class="w-10 h-10 rounded-full bg-base-200 flex items-center justify-center">
                  <.icon name="hero-user-group" class="w-5 h-5 text-base-content/30" />
                </div>
                <p class="text-xs text-base-content/30">
                  {if @search_query != "", do: "No teams match your search", else: "No active teams"}
                </p>
              </div>
            <% else %>
              <div class="divide-y divide-base-content/5 bg-base-100 rounded-xl px-4">
                <%= for team <- @filtered_teams do %>
                  <div class={"relative overflow-hidden border-l-2 #{team_status_border(team.members)}"}>
                    <div class="group flex items-center gap-4 py-3">
                      <div
                        class="flex-1 min-w-0 cursor-pointer"
                        phx-click="select_team"
                        phx-value-id={team.id}
                        role="button"
                        tabindex="0"
                      >
                        <span class="text-[13px] font-medium text-base-content/85 truncate block">
                          {team.name}
                        </span>
                        <div class="flex items-center gap-1.5 mt-1 text-[11px] text-base-content/30">
                          <span class="font-mono">{length(team.members)} members</span>
                          <%= if active_member_count(team.members) > 0 do %>
                            <span class="text-base-content/15">/</span>
                            <span class="text-success/70">
                              {active_member_count(team.members)} active
                            </span>
                          <% end %>
                          <%= if team.description do %>
                            <span class="text-base-content/15">/</span>
                            <span class="truncate text-base-content/40">{team.description}</span>
                          <% end %>
                        </div>
                      </div>
                      <button
                        phx-click="delete_team"
                        phx-value-id={team.id}
                        class="shrink-0 p-1.5 rounded hover:bg-base-200 text-base-content/20 hover:text-error/60 transition-colors opacity-0 group-hover:opacity-100 max-sm:opacity-30 pointer-events-none group-hover:pointer-events-auto max-sm:pointer-events-auto min-h-[44px] min-w-[44px] flex items-center justify-center"
                        title="Delete team"
                      >
                        <.icon name="hero-trash" class="w-3.5 h-3.5" />
                      </button>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>

        <%!-- DETAIL VIEW --%>
        <div class={@mobile_view == :list && "hidden"}>
          <%!-- Back button --%>
          <button
            phx-click="close_team"
            class="flex items-center gap-2 py-4 text-sm text-base-content/50 hover:text-base-content/80 transition-colors"
          >
            <.icon name="hero-arrow-left" class="w-4 h-4" /> Teams
          </button>

          <%= if @selected_team do %>
            <div id="team-detail" class="overflow-hidden rounded-xl bg-base-100">
              <.live_component
                module={EyeInTheSkyWeb.TeamDetailComponent}
                id="team-detail-component"
                team={@selected_team}
                selected_agent_session_id={@agent_session_id}
              />
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp load_teams(socket, show_archived, show_all) do
    project_id =
      if show_all, do: nil, else: socket.assigns[:project_id]

    opts =
      if show_archived,
        do: [status: "archived"],
        else: []

    opts = if project_id, do: Keyword.put(opts, :project_id, project_id), else: opts

    Teams.list_teams(opts)
  end

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

  defp maybe_refresh_selected_team(%{assigns: %{selected_team_id: nil}} = socket), do: socket

  defp maybe_refresh_selected_team(%{assigns: %{selected_team_id: id}} = socket) do
    case Teams.get_team(id) do
      {:error, :not_found} -> show_team_list(socket)
      {:ok, team} -> assign(socket, :selected_team, load_team_detail(team))
    end
  end

  defp show_team_detail(socket, team_id, team) do
    socket
    |> assign(:selected_team_id, team_id)
    |> assign(:selected_team, team)
    |> assign(:mobile_view, :detail)
  end

  defp show_team_list(socket) do
    socket
    |> assign(:selected_team_id, nil)
    |> assign(:selected_team, nil)
    |> assign(:mobile_view, :list)
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

  defp active_member_count(members), do: Enum.count(members, &(&1.status == "active"))

  defp team_status_border([]), do: "border-transparent"

  defp team_status_border(members) do
    active = Enum.count(members, &(&1.status == "active"))

    cond do
      active > 0 and active == length(members) -> "border-success"
      active > 0 -> "border-success/40"
      true -> "border-transparent"
    end
  end

  defp filter_teams(teams, ""), do: teams

  defp filter_teams(teams, query) do
    q = String.downcase(query)
    Enum.filter(teams, fn t -> String.contains?(String.downcase(t.name), q) end)
  end

  defp maybe_close_if_deleted(socket, deleted_id) do
    if socket.assigns.selected_team_id == deleted_id do
      socket |> assign(:agent_session_id, nil) |> show_team_list()
    else
      socket
    end
  end

  defp with_parsed_int(socket, value, fun) do
    case parse_int(value) do
      nil -> {:noreply, socket}
      id -> fun.(id)
    end
  end
end
