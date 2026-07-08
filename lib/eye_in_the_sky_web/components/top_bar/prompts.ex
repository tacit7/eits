defmodule EyeInTheSkyWeb.TopBar.Prompts do
  @moduledoc false
  use Phoenix.Component
  import EyeInTheSkyWeb.CoreComponents

  attr :search_query, :string, default: ""

  def toolbar(assigns) do
    ~H"""
    <.search_bar
      id="prompts-top-bar-search"
      size="xs"
      label="Search prompts"
      placeholder="Search prompts..."
      value={@search_query || ""}
      on_change="search"
      debounce="300"
      class="w-44"
      vim_search={true}
    />
    """
  end
end
