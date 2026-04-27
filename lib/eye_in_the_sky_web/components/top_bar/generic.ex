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
    <form phx-change="search" class="flex-1 max-w-xs">
      <label for="top-bar-generic-search" class="sr-only">Search</label>
      <div class="relative">
        <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-2.5">
          <.icon name="hero-magnifying-glass-mini" class="w-3.5 h-3.5 text-base-content/30" />
        </div>
        <input
          type="text"
          name="query"
          id="top-bar-generic-search"
          value={@search_query}
          phx-debounce="300"
          placeholder="Search..."
          autocomplete="off"
          class="input input-xs w-full pl-8 h-7 bg-base-200/50 border-base-content/8 placeholder:text-base-content/25 focus:border-primary/30 focus:bg-base-100 transition-colors text-[12px]"
        />
      </div>
    </form>
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
      <.icon name="hero-magnifying-glass" class="w-3.5 h-3.5" />
      Search
      <kbd class="ml-0.5 inline-flex items-center px-1 py-0.5 rounded text-[9px] bg-base-content/8 text-base-content/30 border border-base-content/10 font-sans leading-none">
        ⌘K
      </kbd>
    </button>
    """
  end
end
