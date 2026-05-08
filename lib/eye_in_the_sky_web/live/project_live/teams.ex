defmodule EyeInTheSkyWeb.ProjectLive.Teams do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.Teams
  alias EyeInTheSky.Teams.Team
  alias EyeInTheSky.Teams.TeamMember
  alias EyeInTheSkyWeb.Live.Shared.NotificationHelpers
  import EyeInTheSkyWeb.Helpers.ProjectLiveHelpers
  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]

  @impl true
  def mount(%{"id" => _} = params, _session, socket) do
    if connected?(socket) do
      EyeInTheSky.Events.subscribe_teams()
    end

    socket =
      socket
      |> mount_project(params, sidebar_tab: :teams, page_title_prefix: "Teams")
      |> assign(:show_archived, false)
      |> assign(:search_query, "")
      |> assign(:show_all, false)
      |> assign(:all_teams, [])
      |> stream(:team_list, [], dom_id: fn t -> "team-#{t.id}" end)

    socket =
      if connected?(socket) do
        teams = load_teams(socket, false, false, "")

        socket
        |> assign(:all_teams, teams)
        |> stream(:team_list, teams, reset: true, dom_id: fn t -> "team-#{t.id}" end)
      else
        socket
      end

    {:ok, socket}
  end

  def mount(_params, _session, socket) do
    if connected?(socket) do
      EyeInTheSky.Events.subscribe_teams()
    end

    socket =
      socket
      |> assign(:project, nil)
      |> assign(:project_id, nil)
      |> assign(:page_title, "Teams")
      |> assign(:sidebar_tab, :teams)
      |> assign(:sidebar_project, nil)
      |> assign(:show_archived, false)
      |> assign(:search_query, "")
      |> assign(:show_all, true)
      |> assign(:all_teams, [])
      |> stream(:team_list, [], dom_id: fn t -> "team-#{t.id}" end)

    socket =
      if connected?(socket) do
        teams = load_teams(socket, false, true, "")

        socket
        |> assign(:all_teams, teams)
        |> stream(:team_list, teams, reset: true, dom_id: fn t -> "team-#{t.id}" end)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"show_all" => "true"}, _uri, socket) do
    socket = assign(socket, :show_all, true)

    socket =
      if connected?(socket) do
        teams = load_teams(socket, socket.assigns.show_archived, true, socket.assigns.search_query)
        assign(socket, :all_teams, teams)
        |> stream(:team_list, teams, reset: true, dom_id: fn t -> "team-#{t.id}" end)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_params(_params, _uri, socket) do
    socket = assign(socket, :show_all, false)

    socket =
      if connected?(socket) do
        teams = load_teams(socket, socket.assigns.show_archived, false, socket.assigns.search_query)
        assign(socket, :all_teams, teams)
        |> stream(:team_list, teams, reset: true, dom_id: fn t -> "team-#{t.id}" end)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:team_created, %Team{} = team}, socket) do
    # Only add to stream if it matches current filters
    case should_include_team?(team, socket) do
      true ->
        socket =
          socket
          |> update(:all_teams, &[team | &1])
          |> stream_insert(:team_list, team)

        {:noreply, socket}

      false ->
        {:noreply, socket}
    end
  end

  def handle_info({:team_deleted, %Team{id: team_id}}, socket) do
    socket =
      socket
      |> update(:all_teams, &Enum.reject(&1, fn t -> t.id == team_id end))
      |> stream_delete_by_dom_id(:team_list, "team-#{team_id}")

    {:noreply, socket}
  end

  def handle_info(
        {:member_joined, %TeamMember{team_id: team_id}},
        socket
      ) do
    update_team_in_stream(socket, team_id)
  end

  def handle_info(
        {:member_updated, %TeamMember{team_id: team_id}},
        socket
      ) do
    update_team_in_stream(socket, team_id)
  end

  def handle_info(
        {:member_left, %TeamMember{team_id: team_id}},
        socket
      ) do
    update_team_in_stream(socket, team_id)
  end

  def handle_info({:new_message, _message}, socket), do: {:noreply, socket}

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    teams = load_teams(socket, socket.assigns.show_archived, socket.assigns.show_all, query)

    socket =
      socket
      |> assign(:search_query, query)
      |> assign(:all_teams, teams)
      |> stream(:team_list, teams, reset: true, dom_id: fn t -> "team-#{t.id}" end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("delete_team", %{"id" => id}, socket) do
    case parse_int(id) do
      nil ->
        {:noreply, socket}

      team_id ->
        case Teams.get_team(team_id) do
          {:ok, team} ->
            {:ok, _} = Teams.delete_team(team)
            # The PubSub handler will update the stream when team_deleted event is received

            {:noreply, socket}

          _ ->
            {:noreply, put_flash(socket, :error, "Team not found")}
        end
    end
  end

  @impl true
  def handle_event("set_notify_on_stop", params, socket),
    do: {:noreply, NotificationHelpers.set_notify_on_stop(socket, params)}

  @impl true
  def handle_event("toggle_archived", _params, socket) do
    show_archived = !socket.assigns.show_archived
    teams = load_teams(socket, show_archived, socket.assigns.show_all, socket.assigns.search_query)

    socket =
      socket
      |> assign(:show_archived, show_archived)
      |> assign(:all_teams, teams)
      |> stream(:team_list, teams, reset: true, dom_id: fn t -> "team-#{t.id}" end)

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="overflow-y-auto px-4 sm:px-6 py-6" style="scrollbar-width: none;">
      <div class="mb-3 flex items-center justify-between">
        <span class="text-mini font-mono tabular-nums text-base-content/45 tracking-wider uppercase">
          {length(@all_teams)} teams
          <%= if @show_all do %>
            <span class="ml-1 text-primary">(all projects)</span>
          <% end %>
        </span>
        <%= if @project do %>
          <.link
            navigate={
              if @show_all,
                do: ~p"/projects/#{@project.id}/teams",
                else: ~p"/projects/#{@project.id}/teams?show_all=true"
            }
            class={[
              "text-xs px-2 py-1 rounded transition-colors",
              if(@show_all,
                do: "bg-base-content/8 text-base-content/60",
                else: "text-base-content/30 hover:text-base-content/60"
              )
            ]}
          >
            {if @show_all, do: "This project", else: "Show all"}
          </.link>
        <% end %>
      </div>

      <%= if @all_teams == [] do %>
        <.empty_state
          id="teams-empty"
          icon="hero-user-group"
          title={if @search_query != "", do: "No teams match your search", else: "No active teams"}
          subtitle={
            if @search_query != "",
              do: "Try a different search",
              else: "Create a team to coordinate agents"
          }
        />
      <% else %>
        <div class="divide-y divide-base-content/8" data-vim-list>
          <%= for {dom_id, team} <- @team_list do %>
            <div id={dom_id} class="py-1 group flex items-center gap-1">
              <.link
                navigate={
                  cond do
                    @project -> ~p"/projects/#{@project.id}/teams/#{team.id}"
                    team.project_id -> ~p"/projects/#{team.project_id}/teams/#{team.id}"
                    true -> "#"
                  end
                }
                class="flex-1 py-2 px-3 flex items-center gap-3 rounded-lg hover:bg-base-200/40 transition-colors min-w-0 [&.vim-nav-focused]:ring-2 [&.vim-nav-focused]:ring-primary/50"
                data-vim-list-item
              >
                <.status_dot status={team_status_atom(team.members)} size="sm" />
                <div class="flex-1 min-w-0">
                  <div class="flex items-center gap-2">
                    <span class="text-sm font-medium text-base-content/85 truncate">
                      {team.name}
                    </span>
                    <%= if team.status == "archived" do %>
                      <span class="text-[10px] text-base-content/35 font-medium">archived</span>
                    <% end %>
                  </div>
                  <div class="flex items-center gap-1.5 mt-0.5 text-[10px] text-base-content/40 font-mono">
                    <span>{length(team.members)} members</span>
                    <%= if active_member_count(team.members) > 0 do %>
                      <span class="text-base-content/20">·</span>
                      <span class="text-success/70">{active_member_count(team.members)} active</span>
                    <% end %>
                    <%= if team.description do %>
                      <span class="text-base-content/20">·</span>
                      <span class="truncate font-sans text-base-content/35">{team.description}</span>
                    <% end %>
                  </div>
                </div>
                <.icon name="hero-chevron-right" class="size-3.5 text-base-content/20 flex-shrink-0" />
              </.link>
              <button
                phx-click="delete_team"
                phx-value-id={team.id}
                class="shrink-0 p-1.5 rounded text-base-content/20 hover:text-error/60 hover:bg-base-200 transition-colors opacity-0 group-hover:opacity-100 min-h-[36px] min-w-[36px] flex items-center justify-center"
                title="Delete team"
              >
                <.icon name="hero-trash" class="size-3.5" />
              </button>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp load_teams(socket, show_archived, show_all, search_query) do
    project_id = if show_all, do: nil, else: socket.assigns[:project_id]
    opts = if show_archived, do: [status: "archived"], else: []
    opts = if project_id, do: Keyword.put(opts, :project_id, project_id), else: opts
    opts = if search_query != "", do: Keyword.put(opts, :name, search_query), else: opts
    Teams.list_teams(opts)
  end

  defp should_include_team?(%Team{} = team, socket) do
    # Check status filter
    status_matches =
      if socket.assigns.show_archived do
        team.status == "archived"
      else
        team.status != "archived"
      end

    # Check project filter
    project_matches =
      if socket.assigns.show_all do
        true
      else
        team.project_id == socket.assigns[:project_id]
      end

    # Check search filter
    search_matches =
      if socket.assigns.search_query == "" do
        true
      else
        String.contains?(
          String.downcase(team.name),
          String.downcase(socket.assigns.search_query)
        )
      end

    status_matches and project_matches and search_matches
  end

  defp update_team_in_stream(socket, team_id) do
    case Teams.get_team(team_id) do
      {:ok, team} ->
        if should_include_team?(team, socket) do
          updated_all_teams =
            Enum.map(socket.assigns.all_teams, fn t ->
              if t.id == team_id, do: team, else: t
            end)

          socket =
            socket
            |> update(:all_teams, fn _ -> updated_all_teams end)
            |> stream_insert(:team_list, team)

          {:noreply, socket}
        else
          # Team no longer matches filters, remove it
          socket =
            socket
            |> update(:all_teams, &Enum.reject(&1, fn t -> t.id == team_id end))
            |> stream_delete_by_dom_id(:team_list, "team-#{team_id}")

          {:noreply, socket}
        end

      {:error, _} ->
        {:noreply, socket}
    end
  end

  defp active_member_count(members), do: Enum.count(members, &(&1.status == "active"))

  defp team_status_atom([]), do: :idle

  defp team_status_atom(members) do
    if Enum.any?(members, &(&1.status == "active")), do: :working, else: :idle
  end
end
