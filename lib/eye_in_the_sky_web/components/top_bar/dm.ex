defmodule EyeInTheSkyWeb.TopBar.DM do
  @moduledoc false
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: EyeInTheSkyWeb.Endpoint,
    router: EyeInTheSkyWeb.Router,
    statics: EyeInTheSkyWeb.static_paths()

  import EyeInTheSkyWeb.CoreComponents
  import Phoenix.LiveView.Helpers, only: []

  alias Phoenix.LiveView.JS

  attr :dm_active_tab, :string, default: "messages"
  attr :dm_message_search_query, :string, default: nil
  attr :dm_active_timer, :map, default: nil

  def toolbar(assigns) do
    ~H"""
    <%!-- TODO: migrate content from layouts.ex dm_toolbar/1 --%>
    """
  end
end
