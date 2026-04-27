defmodule EyeInTheSkyWeb.TopBar.Generic do
  @moduledoc false
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: EyeInTheSkyWeb.Endpoint,
    router: EyeInTheSkyWeb.Router,
    statics: EyeInTheSkyWeb.static_paths()

  alias Phoenix.LiveView.JS
  import EyeInTheSkyWeb.CoreComponents

  attr :search_query, :string, default: nil

  def toolbar(assigns) do
    ~H"""
    <%!-- Generic search — skills, prompts, teams, notes, etc. --%>
    <.search_bar
      id="top-bar-generic-search"
      size="xs"
      label="Search"
      placeholder="Search..."
      value={@search_query}
      on_change="search"
      class="flex-1 max-w-xs"
    />
    """
  end

  def default_toolbar(assigns) do
    ~H"""
    <%!-- Default: spacer + palette search button --%>
    <div class="flex-1" />
    <button
      phx-click={JS.dispatch("palette:open", to: "#command-palette")}
      class="flex items-center gap-1.5 h-7 px-2.5 rounded-md text-[11px] font-medium text-base-content/45 hover:text-base-content/70 hover:bg-base-content/6 transition-colors"
      title="Search"
      aria-label="Search"
    >
      <.icon name="hero-magnifying-glass" class="size-3.5" />
      Search
      <kbd class="ml-0.5 inline-flex items-center px-1 py-0.5 rounded text-[9px] bg-base-content/8 text-base-content/30 border border-base-content/10 font-sans leading-none">
        ⌘K
      </kbd>
    </button>
    """
  end
end
