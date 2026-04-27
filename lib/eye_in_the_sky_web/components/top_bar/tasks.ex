defmodule EyeInTheSkyWeb.TopBar.Tasks do
  @moduledoc false
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: EyeInTheSkyWeb.Endpoint,
    router: EyeInTheSkyWeb.Router,
    statics: EyeInTheSkyWeb.static_paths()

  import EyeInTheSkyWeb.CoreComponents

  attr :search_query, :string, default: nil
  attr :filter_state_id, :any, default: nil
  attr :workflow_states, :list, default: []
  attr :sort_by, :string, default: "created_desc"

  def toolbar(assigns) do
    ~H"""
    <%!-- TODO: migrate content from layouts.ex tasks_toolbar/1 --%>
    """
  end
end
