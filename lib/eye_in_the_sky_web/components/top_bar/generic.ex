defmodule EyeInTheSkyWeb.TopBar.Generic do
  @moduledoc false
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: EyeInTheSkyWeb.Endpoint,
    router: EyeInTheSkyWeb.Router,
    statics: EyeInTheSkyWeb.static_paths()

  import EyeInTheSkyWeb.CoreComponents
  alias Phoenix.LiveView.JS

  attr :search_query, :string, default: nil

  def toolbar(assigns) do
    ~H"""
    <%!-- TODO: migrate content from layouts.ex generic_search_toolbar/1 --%>
    """
  end

  def default_toolbar(assigns) do
    ~H"""
    <%!-- TODO: migrate content from layouts.ex default_toolbar/1 --%>
    """
  end
end
