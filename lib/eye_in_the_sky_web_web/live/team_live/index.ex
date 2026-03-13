defmodule EyeInTheSkyWebWeb.TeamLive.Index do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.{Teams, Tasks}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "teams")
    end

    {:ok,
     socket
     |> assign(:page_title, "Teams")
     |> assign(:sidebar_tab, :teams)
     |> assign(:sidebar_project, nil)
     |> assign(:teams, load_teams())
     |> assign(:selected_team_id, nil)
     |> assign(:selected_team, nil)}
  end

  @impl true
  def handle_info({event, _payload}, socket)
      when event in [:team_created, :team_deleted, :member_joined, :member_updated, :member_left] do
    {:noreply,
     socket
     |> assign(:teams, load_teams())
     |> maybe_refresh_selected_team()}
  end

  @impl true
  def handle_event("select_team", %{"id" => id}, socket) do
    team_id = String.to_integer(id)
    team = Teams.get_team!(team_id) |> load_team_detail()
    {:noreply, socket |> assign(:selected_team_id, team_id) |> assign(:selected_team, team)}
  end

  @impl true
  def handle_event("close_team", _params, socket) do
    {:noreply, socket |> assign(:selected_team_id, nil) |> assign(:selected_team, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-full gap-0">
      <%!-- Team list sidebar --%>
      <div class="w-72 border-r border-base-300 flex flex-col">
        <div class="p-4 border-b border-base-300 flex items-center justify-between">
          <h2 class="font-semibold text-base-content">Teams</h2>
          <span class="badge badge-sm badge-neutral"><%= length(@teams) %></span>
        </div>

        <div class="flex-1 overflow-y-auto">
          <%= if @teams == [] do %>
            <div class="p-4 text-sm text-base-content/40 text-center mt-8">
              No active teams
            </div>
          <% else %>
            <%= for team <- @teams do %>
              <button
                class={[
                  "w-full text-left px-4 py-3 border-b border-base-300/50 hover:bg-base-200 transition-colors",
                  @selected_team_id == team.id && "bg-base-200 border-l-2 border-l-primary"
                ]}
                phx-click="select_team"
                phx-value-id={team.id}
              >
                <div class="flex items-center justify-between mb-1">
                  <span class="font-medium text-sm truncate"><%= team.name %></span>
                  <span class={["badge badge-xs", status_badge_class(team.status)]}>
                    <%= team.status %>
                  </span>
                </div>
                <div class="flex items-center gap-2 text-xs text-base-content/50">
                  <.icon name="hero-users" class="w-3 h-3" />
                  <span><%= length(team.members) %> members</span>
                </div>
              </button>
            <% end %>
          <% end %>
        </div>
      </div>

      <%!-- Team detail panel --%>
      <div class="flex-1 overflow-y-auto">
        <%= if @selected_team do %>
          <.team_detail team={@selected_team} />
        <% else %>
          <div class="flex items-center justify-center h-full text-base-content/30">
            <div class="text-center">
              <.icon name="hero-users" class="w-12 h-12 mx-auto mb-3" />
              <p class="text-sm">Select a team to view details</p>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp team_detail(assigns) do
    ~H"""
    <div class="p-6 max-w-3xl">
      <div class="flex items-start justify-between mb-6">
        <div>
          <h1 class="text-xl font-bold text-base-content"><%= @team.name %></h1>
          <%= if @team.description do %>
            <p class="text-sm text-base-content/60 mt-1"><%= @team.description %></p>
          <% end %>
        </div>
        <div class="flex items-center gap-2">
          <span class={["badge", status_badge_class(@team.status)]}><%= @team.status %></span>
        </div>
      </div>

      <%!-- Members --%>
      <section class="mb-6">
        <h2 class="text-sm font-semibold text-base-content/70 uppercase tracking-wide mb-3">
          Members (<%= length(@team.members) %>)
        </h2>
        <div class="space-y-2">
          <%= for member <- @team.members do %>
            <div class="flex items-center justify-between p-3 rounded-lg bg-base-200">
              <div class="flex items-center gap-3">
                <div class={["w-2 h-2 rounded-full", member_status_dot(member.status)]}></div>
                <div>
                  <span class="font-medium text-sm"><%= member.name %></span>
                  <span class="text-xs text-base-content/50 ml-2"><%= member.role %></span>
                </div>
              </div>
              <span class={["badge badge-xs", member_status_badge(member.status)]}>
                <%= member.status %>
              </span>
            </div>
          <% end %>
        </div>
      </section>

      <%!-- Tasks --%>
      <section>
        <h2 class="text-sm font-semibold text-base-content/70 uppercase tracking-wide mb-3">
          Tasks (<%= length(@team.tasks) %>)
        </h2>
        <%= if @team.tasks == [] do %>
          <p class="text-sm text-base-content/40">No tasks assigned to this team</p>
        <% else %>
          <div class="space-y-2">
            <%= for task <- @team.tasks do %>
              <div class="flex items-center justify-between p-3 rounded-lg bg-base-200">
                <div class="flex items-center gap-2">
                  <span class={["w-2 h-2 rounded-full flex-shrink-0", task_state_dot(task.state_id)]}></span>
                  <span class="text-sm"><%= task.title %></span>
                </div>
                <div class="flex items-center gap-2">
                  <%= if task.state do %>
                    <span class="badge badge-xs badge-ghost"><%= task.state.name %></span>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </section>
    </div>
    """
  end

  defp load_teams do
    Teams.list_teams()
  end

  defp load_team_detail(team) do
    tasks = Tasks.list_tasks_for_team(team.id)
    Map.put(team, :tasks, tasks)
  end

  defp maybe_refresh_selected_team(%{assigns: %{selected_team_id: nil}} = socket), do: socket

  defp maybe_refresh_selected_team(%{assigns: %{selected_team_id: id}} = socket) do
    case Teams.get_team(id) do
      nil -> socket |> assign(:selected_team_id, nil) |> assign(:selected_team, nil)
      team -> assign(socket, :selected_team, load_team_detail(team))
    end
  end

  defp status_badge_class("active"), do: "badge-success"
  defp status_badge_class("archived"), do: "badge-ghost"
  defp status_badge_class(_), do: "badge-neutral"

  defp member_status_dot("active"), do: "bg-success"
  defp member_status_dot("idle"), do: "bg-warning"
  defp member_status_dot("done"), do: "bg-base-content/30"
  defp member_status_dot(_), do: "bg-base-content/20"

  defp member_status_badge("active"), do: "badge-success"
  defp member_status_badge("idle"), do: "badge-warning"
  defp member_status_badge("done"), do: "badge-ghost"
  defp member_status_badge(_), do: "badge-neutral"

  defp task_state_dot(1), do: "bg-base-content/30"
  defp task_state_dot(2), do: "bg-info"
  defp task_state_dot(3), do: "bg-success"
  defp task_state_dot(4), do: "bg-warning"
  defp task_state_dot(_), do: "bg-base-content/20"
end
