defmodule EyeInTheSkyWeb.Components.BookmarkButton do
  @moduledoc """
  Bookmark button component with toggle behavior handled by the parent LiveView.
  """

  use EyeInTheSkyWeb, :html

  attr :is_bookmarked, :boolean, required: true
  attr :click_event, :string, default: "toggle_bookmark"

  def bookmark_button(assigns) do
    ~H"""
    <button
      phx-click={@click_event}
      class="btn btn-ghost btn-sm gap-2 transition-colors"
      title={if @is_bookmarked, do: "Remove bookmark", else: "Bookmark this file"}
      aria-pressed={@is_bookmarked}
      aria-label={if @is_bookmarked, do: "Remove bookmark", else: "Add bookmark"}
    >
      <%= if @is_bookmarked do %>
        <.icon name="hero-bookmark-solid" class="h-5 w-5 text-warning transition-colors" />
        <span class="text-sm">Bookmarked</span>
      <% else %>
        <.icon
          name="hero-bookmark"
          class="h-5 w-5 text-base-content/40 group-hover:text-warning transition-colors"
        />
        <span class="text-sm">Bookmark</span>
      <% end %>
    </button>
    """
  end
end
