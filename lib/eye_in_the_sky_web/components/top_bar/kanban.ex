defmodule EyeInTheSkyWeb.TopBar.Kanban do
  @moduledoc false
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: EyeInTheSkyWeb.Endpoint,
    router: EyeInTheSkyWeb.Router,
    statics: EyeInTheSkyWeb.static_paths()

  import EyeInTheSkyWeb.CoreComponents

  attr :search_query, :string, default: nil
  attr :show_completed, :boolean, default: false
  attr :bulk_mode, :boolean, default: false
  attr :active_filter_count, :integer, default: 0
  attr :sidebar_project, :any, default: nil

  def toolbar(assigns) do
    ~H"""
    <%!-- TODO: migrate content from layouts.ex kanban_toolbar/1 --%>
    """
  end
end
