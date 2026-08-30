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
      class="focus-ring inline-flex h-7 items-center gap-2 rounded-box px-2 text-mini font-medium text-base-content/55 transition-colors hover:bg-base-content/5 hover:text-base-content/80"
      title={if @is_bookmarked, do: "Remove bookmark", else: "Bookmark this file"}
      aria-pressed={@is_bookmarked}
      aria-label={if @is_bookmarked, do: "Remove bookmark", else: "Add bookmark"}
    >
      <%= if @is_bookmarked do %>
        <.icon name="hero-bookmark-solid" class="size-5 text-warning transition-colors" />
        <span>Bookmarked</span>
      <% else %>
        <.icon
          name="hero-bookmark"
          class="size-5 text-base-content/40 group-hover:text-warning transition-colors"
        />
        <span>Bookmark</span>
      <% end %>
    </button>
    """
  end
end
