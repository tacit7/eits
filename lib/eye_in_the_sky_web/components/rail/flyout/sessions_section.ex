defmodule EyeInTheSkyWeb.Components.Rail.Flyout.SessionsSection do
  @moduledoc false
  use EyeInTheSkyWeb, :html

  attr :sessions, :list, required: true
  attr :sidebar_project, :any, default: nil

  def sessions_content(assigns) do
    ~H"""
    <.session_row :for={s <- @sessions} session={s} />

    <%= if @sessions == [] do %>
      <div class="px-3 py-4 text-xs text-base-content/35 text-center">No sessions</div>
    <% end %>
    """
  end

  attr :session, :map, required: true

  def session_row(assigns) do
    ~H"""
    <.link
      navigate={"/dm/#{@session.id}"}
      data-vim-flyout-item
      class="flex items-center gap-2 px-3 py-2 text-sm text-base-content/65 hover:text-base-content/90 hover:bg-base-content/5 transition-colors"
    >
      <.status_dot status={@session.status} size="xs" />
      <span class="truncate font-medium text-xs">{@session.name || "unnamed"}</span>
    </.link>
    """
  end
end
