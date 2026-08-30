defmodule EyeInTheSkyWeb.Components.Rail.Flyout.TeamsSection do
  @moduledoc false
  use EyeInTheSkyWeb, :html

  alias EyeInTheSkyWeb.Components.Rail.Flyout.Helpers

  attr :team_search, :string, default: ""
  attr :team_status, :string, default: "active"

  def teams_filters(assigns) do
    ~H"""
    <div class="px-2.5 py-2 border-b border-base-content/8 flex flex-col gap-2">
      <%!-- Search --%>
      <div class="relative">
        <span class="absolute left-2 top-1/2 -translate-y-1/2 text-base-content/30 pointer-events-none">
          <.icon name="hero-magnifying-glass-mini" class="size-3" />
        </span>
        <input
          id="rail-team-search"
          type="text"
          value={@team_search}
          placeholder="Search teams..."
          phx-keyup="update_team_search"
          phx-debounce="200"
          class="focus-ring h-7 w-full rounded-box border border-base-content/10 bg-base-content/5 pl-6 pr-2 text-micro text-base-content/80 placeholder:text-base-content/30 focus:border-primary/40"
        />
      </div>

      <%!-- Status pills --%>
      <div class="flex items-center gap-0.5">
        <.status_pill label="Active" value="active" current={@team_status} />
        <.status_pill label="All" value="all" current={@team_status} />
        <.status_pill label="Archived" value="archived" current={@team_status} />
      </div>
    </div>
    """
  end

  attr :teams, :list, default: []
  attr :team_search, :string, default: ""
  attr :team_status, :string, default: "active"
  attr :sidebar_project, :any, default: nil

  def teams_content(assigns) do
    ~H"""
    <%= if @teams == [] do %>
      <div class="px-3 py-4 text-mini text-base-content/35 text-center">
        {if @team_search != "" or @team_status != "all", do: "No matching teams", else: "No teams"}
      </div>
    <% end %>
    <.link
      :if={@teams != []}
      navigate={Helpers.teams_route(@sidebar_project)}
      class="focus-ring block rounded-box px-3 pb-1 text-micro text-base-content/40 transition-colors hover:text-base-content/70"
    >
      All Teams &rarr;
    </.link>
    <%= for team <- @teams do %>
      <.link
        navigate={team_route(@sidebar_project, team.id)}
        data-vim-flyout-item
        class="focus-ring flex h-8 items-center gap-2 rounded-box px-3 text-mini text-base-content/65 transition-colors hover:bg-base-content/5 hover:text-base-content/90 [&.vim-nav-focused]:ring-2 [&.vim-nav-focused]:ring-primary/50"
      >
        <.icon name="hero-users" class="size-3 flex-shrink-0 text-base-content/30" />
        <span class="truncate text-mini font-medium">{team.name}</span>
        <span :if={team.status == "archived"} class="text-micro text-base-content/30 flex-shrink-0">
          archived
        </span>
        <span class="ml-auto text-micro text-base-content/30 flex-shrink-0">
          {if is_list(team.members), do: length(team.members), else: 0}
        </span>
      </.link>
    <% end %>
    """
  end

  defp team_route(%{id: project_id}, team_id), do: "/projects/#{project_id}/teams/#{team_id}"
  defp team_route(_, _team_id), do: "/teams"

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :current, :string, default: "active"

  defp status_pill(assigns) do
    ~H"""
    <% active = @current == @value %>
    <button
      type="button"
      phx-click="set_team_status"
      phx-value-status={@value}
      class={[
        "focus-ring rounded-box px-1.5 py-0.5 text-nano transition-colors",
        if(active,
          do: "bg-primary/15 text-primary font-medium",
          else: "text-base-content/45 hover:text-base-content/70 hover:bg-base-content/8"
        )
      ]}
    >
      {@label}
    </button>
    """
  end
end
