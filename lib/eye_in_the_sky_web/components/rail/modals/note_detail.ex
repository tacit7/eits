defmodule EyeInTheSkyWeb.Components.Rail.Modals.NoteDetail do
  @moduledoc false
  use EyeInTheSkyWeb, :html

  attr :note, :map, required: true
  attr :index, :integer, required: true
  attr :total, :integer, required: true

  def note_detail_modal(assigns) do
    edit_link = "/notes/#{assigns.note.id}/edit"
    assigns = assign(assigns, :edit_link, edit_link)

    ~H"""
    <div class="fixed left-[296px] top-[48px] z-[100] w-[420px] h-[480px] bg-base-100 border border-base-content/10 rounded-box shadow-xl p-4 flex flex-col gap-3">
      <%!-- Header --%>
      <div class="flex items-start justify-between gap-2 flex-shrink-0">
        <div class="min-w-0 flex-1">
          <span class="text-message font-semibold text-base-content/85 leading-snug block truncate">
            {note_label(@note)}
          </span>
          <span class="text-micro text-base-content/30 uppercase tracking-normal">
            {@note.parent_type}
          </span>
        </div>
        <button
          type="button"
          phx-click="close_rail_modal"
          class="focus-ring size-5 flex-shrink-0 flex items-center justify-center rounded-box text-base-content/40 hover:text-base-content/70 hover:bg-base-content/8 transition-colors"
        >
          <.icon name="hero-x-mark-mini" class="size-3.5" />
        </button>
      </div>

      <%!-- Body --%>
      <div class="flex-1 min-h-0 overflow-y-auto">
        <%= if @note.body && @note.body != "" do %>
          <p class="text-message text-base-content/60 leading-relaxed break-words">
            <span class="whitespace-pre-wrap">{@note.body}</span>
          </p>
        <% else %>
          <p class="text-mini text-base-content/30 italic">No content.</p>
        <% end %>
      </div>

      <%!-- Footer: prev/next + counter + edit link --%>
      <div class="flex items-center justify-between pt-1 border-t border-base-content/8 flex-shrink-0">
        <div class="flex items-center gap-1">
          <button
            type="button"
            phx-click="note_detail_nav"
            phx-value-dir="prev"
            disabled={@total <= 1}
            class="focus-ring size-6 flex items-center justify-center rounded-box text-base-content/40 hover:text-base-content/80 hover:bg-base-content/8 transition-colors disabled:opacity-25"
          >
            <.icon name="hero-chevron-left-mini" class="size-3.5" />
          </button>
          <span class="text-nano text-base-content/35 tabular-nums">
            {@index + 1}/{@total}
          </span>
          <button
            type="button"
            phx-click="note_detail_nav"
            phx-value-dir="next"
            disabled={@total <= 1}
            class="focus-ring size-6 flex items-center justify-center rounded-box text-base-content/40 hover:text-base-content/80 hover:bg-base-content/8 transition-colors disabled:opacity-25"
          >
            <.icon name="hero-chevron-right-mini" class="size-3.5" />
          </button>
        </div>

        <.link
          navigate={@edit_link}
          class="focus-ring inline-flex items-center gap-1 px-3 py-1 text-mini bg-primary text-primary-content rounded-box hover:opacity-90 transition-opacity font-medium"
        >
          <span>Edit note</span>
          <.icon name="hero-arrow-top-right-on-square-mini" class="size-3.5" />
        </.link>
      </div>
    </div>
    """
  end

  defp note_label(note) do
    label = note.title || String.slice(note.body || "", 0, 60)
    if label == "", do: "(empty)", else: label
  end
end
