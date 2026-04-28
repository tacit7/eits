defmodule EyeInTheSkyWeb.TopBar.Teams do
  @moduledoc false
  use Phoenix.Component
  import EyeInTheSkyWeb.CoreComponents

  attr :search_query, :string, default: ""
  attr :show_archived, :boolean, default: false

  def toolbar(assigns) do
    ~H"""
    <.search_bar
      id="teams-top-bar-search"
      size="xs"
      label="Search teams"
      placeholder="Search teams..."
      value={@search_query || ""}
      on_change="search"
      class="w-44"
    />
    <div class="w-px h-4 bg-base-content/10 mx-0.5" />
    <button
      phx-click="toggle_archived"
      class={[
        "flex items-center gap-1 h-7 px-2 rounded-md text-mini font-medium border transition-colors select-none",
        if(@show_archived,
          do: "border-base-content/15 bg-base-content/5 text-base-content/70",
          else: "border-base-content/8 bg-base-100 text-base-content/45 hover:text-base-content/70"
        )
      ]}
    >
      {if @show_archived, do: "Hide archived", else: "Archived"}
    </button>
    """
  end
end
