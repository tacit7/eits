defmodule EyeInTheSkyWeb.Components.Rail.Flyout.TeamsSection do
  @moduledoc false
  use EyeInTheSkyWeb, :html

  alias EyeInTheSkyWeb.Components.Rail.Flyout.Helpers

  attr :team_search, :string, default: ""
  attr :team_status, :string, default: "active"
  attr :myself, :any, required: true

  def teams_filters(assigns) do
    ~H"""
    <div class="px-2.5 py-2 border-b border-base-content/8 flex flex-col gap-2">
      <%!-- Search --%>
      <div class="relative">
        <span class="absolute left-2 top-1/2 -translate-y-1/2 text-base-content/30 pointer-events-none">
          <.icon name="hero-magnifying-glass-mini" class="size-3" />
        </span>
        <input
          type="text"
          value={@team_search}
          placeholder="Search teams…"
          phx-keyup="update_team_search"
          phx-target={@myself}
          phx-debounce="200"
          class="w-full pl-6 pr-2 py-1 text-xs bg-base-content/5 border border-base-content/10 rounded focus:outline-none focus:border-primary/40 placeholder:text-base-content/30"
        />
      </div>

      <%!-- Status pills --%>
      <div class="flex items-center gap-0.5">
        <.status_pill label="Active" value="active" current={@team_status} myself={@myself} />
        <.status_pill label="All" value="all" current={@team_status} myself={@myself} />
        <.status_pill label="Archived" value="archived" current={@team_status} myself={@myself} />
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
      <div class="px-3 py-4 text-xs text-base-content/35 text-center">
        {if @team_search != "" or @team_status != "all", do: "No matching teams", else: "No teams"}
      </div>
    <% end %>
    <.link
      :if={@teams != []}
      navigate={Helpers.teams_route(@sidebar_project)}
      class="block px-3 pb-1 text-xs text-base-content/40 hover:text-base-content/70 transition-colors"
    >
      All Teams &rarr;
    </.link>
    <%= for team <- @teams do %>
      <.link
        navigate={team_route(@sidebar_project, team.id)}
        data-vim-flyout-item
        class="flex items-center gap-2 px-3 py-2 text-sm text-base-content/65 hover:text-base-content/90 hover:bg-base-content/5 transition-colors [&.vim-nav-focused]:ring-2 [&.vim-nav-focused]:ring-primary/50 [&.vim-nav-focused]:rounded"
      >
        <.icon name="hero-users" class="size-3 flex-shrink-0 text-base-content/30" />
        <span class="truncate text-xs font-medium">{team.name}</span>
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
  attr :myself, :any, required: true

  defp status_pill(assigns) do
    ~H"""
    <% active = @current == @value %>
    <button
      phx-click="set_team_status"
      phx-value-status={@value}
      phx-target={@myself}
      class={[
        "text-nano px-1.5 py-0.5 rounded transition-colors",
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
