defmodule EyeInTheSkyWeb.TopBar.Sessions do
  @moduledoc false
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: EyeInTheSkyWeb.Endpoint,
    router: EyeInTheSkyWeb.Router,
    statics: EyeInTheSkyWeb.static_paths()

  attr :search_query, :string, default: nil
  attr :session_filter, :string, default: "all"
  attr :sort_by, :string, default: "last_message"

  def toolbar(assigns) do
    ~H"""
    <%!-- TODO: migrate content from layouts.ex sessions_toolbar/1 --%>
    """
  end
end
