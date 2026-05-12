defmodule EyeInTheSkyWeb.Components.Rail.Flyout.NotesSection do
  @moduledoc false
  use EyeInTheSkyWeb, :html

  attr :note_search, :string, default: ""
  attr :note_parent_type, :any, default: nil
  attr :myself, :any, required: true

  def notes_filters(assigns) do
    ~H"""
    <div class="px-2.5 py-2 border-b border-base-content/8 flex flex-col gap-2">
      <%!-- Search --%>
      <div class="relative">
        <span class="absolute left-2 top-1/2 -translate-y-1/2 text-base-content/30 pointer-events-none">
          <.icon name="hero-magnifying-glass-mini" class="size-3" />
        </span>
        <input
          type="text"
          value={@note_search}
          placeholder="Search notes…"
          phx-keyup="update_note_search"
          phx-target={@myself}
          phx-debounce="200"
          class="w-full pl-6 pr-2 py-1 text-xs bg-base-content/5 border border-base-content/10 rounded focus:outline-none focus:border-primary/40 placeholder:text-base-content/30"
        />
      </div>

      <%!-- Parent type pills — toggleable --%>
      <div class="flex items-center gap-0.5">
        <.type_pill label="Session" value="session" current={@note_parent_type} myself={@myself} />
        <.type_pill label="Task" value="task" current={@note_parent_type} myself={@myself} />
        <.type_pill label="Project" value="project" current={@note_parent_type} myself={@myself} />
      </div>
    </div>
    """
  end

  attr :notes, :list, default: []
  attr :note_search, :string, default: ""
  attr :note_parent_type, :any, default: nil
  attr :myself, :any, required: true

  def notes_content(assigns) do
    ~H"""
    <.note_row :for={note <- @notes} note={note} myself={@myself} />
    <%= if @notes == [] do %>
      <% filtering = @note_search != "" or not is_nil(@note_parent_type) %>
      <div class="px-3 py-4 text-xs text-base-content/35 text-center">
        {if filtering, do: "No matching notes", else: "No notes"}
      </div>
    <% end %>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :current, :any, default: nil
  attr :myself, :any, required: true

  defp type_pill(assigns) do
    ~H"""
    <% active = to_string(@current) == @value %>
    <button
      phx-click="set_note_parent_type"
      phx-value-type={if active, do: "all", else: @value}
      phx-target={@myself}
      class={[
        "text-nano px-1.5 py-0.5 rounded transition-colors",
        if(active,
          do: "bg-primary/15 text-primary font-medium",
          else: "text-base-content/45 hover:text-base-content/70 hover:bg-base-content/8"
        )
      ]}
    >
      {@label}
    </button>
    """
  end

  attr :note, :map, required: true
  attr :myself, :any, required: true

  defp note_row(assigns) do
    ~H"""
    <button
      phx-click="open_note_detail"
      phx-value-note_id={@note.id}
      phx-target={@myself}
      data-vim-flyout-item
      class="w-full flex flex-col gap-0.5 px-3 py-2 text-xs text-base-content/65 hover:text-base-content/90 hover:bg-base-content/5 transition-colors text-left [&.vim-nav-focused]:ring-2 [&.vim-nav-focused]:ring-primary/50 [&.vim-nav-focused]:rounded"
    >
      <span class={[
        "truncate",
        if(@note.title && @note.title != "", do: "font-medium text-base-content/80")
      ]}>
        {note_label(@note)}
      </span>
      <span
        :if={@note.body && @note.body != ""}
        class="truncate text-base-content/35"
      >
        {String.slice(@note.body, 0, 60)}
      </span>
      <span class="text-micro text-base-content/30 uppercase tracking-wide">
        {@note.parent_type}
      </span>
    </button>
    """
  end

  defp note_label(note) do
    label = note.title || String.slice(note.body || "", 0, 60)
    if label == "", do: "(empty)", else: label
  end
end
