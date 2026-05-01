defmodule EyeInTheSkyWeb.Components.Rail.Flyout.NotesSection do
  @moduledoc false
  use EyeInTheSkyWeb, :html

  attr :notes, :list, default: []

  def notes_content(assigns) do
    ~H"""
    <%= for note <- @notes do %>
      <% label = note.title || String.slice(note.body || "", 0, 60) %>
      <% preview = if note.title && note.title != "", do: note.body %>
      <.link
        navigate={"/notes/#{note.id}/edit"}
        data-vim-flyout-item
        class="flex flex-col gap-0.5 px-3 py-2 text-xs text-base-content/65 hover:text-base-content/90 hover:bg-base-content/5 transition-colors"
      >
        <span class={[
          "truncate",
          if(note.title && note.title != "", do: "font-medium text-base-content/80")
        ]}>
          {if label == "", do: "(empty)", else: label}
        </span>
        <span :if={preview && preview != ""} class="truncate text-base-content/40">{preview}</span>
        <span class="text-micro text-base-content/30 uppercase tracking-wide">
          {note.parent_type}
        </span>
      </.link>
    <% end %>
    <%= if @notes == [] do %>
      <div class="px-3 py-4 text-xs text-base-content/35 text-center">No notes</div>
    <% end %>
    """
  end
end
