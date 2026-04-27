defmodule EyeInTheSkyWeb.TopBar.Notes do
  @moduledoc false
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: EyeInTheSkyWeb.Endpoint,
    router: EyeInTheSkyWeb.Router,
    statics: EyeInTheSkyWeb.static_paths()

  import EyeInTheSkyWeb.CoreComponents

  attr :search_query, :string, default: nil
  attr :notes_sort_by, :string, default: "newest"
  attr :notes_starred_filter, :boolean, default: false
  attr :notes_type_filter, :string, default: "all"
  attr :notes_new_href, :string, default: nil

  def toolbar(assigns) do
    ~H"""
    <%!-- TODO: migrate content from layouts.ex notes_toolbar/1 --%>
    """
  end
end
