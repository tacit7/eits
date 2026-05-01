defmodule EyeInTheSkyWeb.Components.Rail.Flyout.TeamsSection do
  @moduledoc false
  use EyeInTheSkyWeb, :html

  alias EyeInTheSkyWeb.Components.Rail.Flyout.Helpers

  attr :teams, :list, default: []
  attr :sidebar_project, :any, default: nil

  def teams_content(assigns) do
    ~H"""
    <div class="px-3 pb-1">
      <.link
        navigate={Helpers.teams_route(@sidebar_project)}
        class="text-xs text-base-content/40 hover:text-base-content/70 transition-colors"
      >
        All Teams &rarr;
      </.link>
    </div>
    <%= if @teams == [] do %>
      <div class="px-3 py-4 text-xs text-base-content/35 text-center">No teams</div>
    <% end %>
    <%= for team <- @teams do %>
      <.link
        navigate={team_route(@sidebar_project, team.id)}
        data-vim-flyout-item
        class="flex items-center gap-2 px-3 py-2 text-sm text-base-content/65 hover:text-base-content/90 hover:bg-base-content/5 transition-colors"
      >
        <.icon name="hero-users" class="size-3 flex-shrink-0 text-base-content/30" />
        <span class="truncate text-xs font-medium">{team.name}</span>
        <span class="ml-auto text-micro text-base-content/30 flex-shrink-0">
          {length(team.members)}
        </span>
      </.link>
    <% end %>
    """
  end

  defp team_route(%{id: project_id}, team_id), do: "/projects/#{project_id}/teams/#{team_id}"
  defp team_route(_, _team_id), do: "/teams"
end
