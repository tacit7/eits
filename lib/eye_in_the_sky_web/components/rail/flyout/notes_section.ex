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
          phx-change="update_note_search"
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

  def notes_content(assigns) do
    ~H"""
    <%= for note <- @notes do %>
      <.note_row note={note} />
    <% end %>
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

  defp note_row(assigns) do
    assigns = assign(assigns, :small, small_note?(assigns.note))
    ~H"""
    <%= if @small do %>
      <%!-- Small note: expandable inline popup via <details> --%>
      <%!--
        We can't use phx-update="ignore" here since this is not a stream.
        <details> open/close is native browser state — LiveView won't interfere
        unless morphdom reinserts the element. The stable key is note.id.
      --%>
      <details
        id={"note-row-#{@note.id}"}
        class="group px-3 py-2 text-xs text-base-content/65 hover:bg-base-content/5 transition-colors cursor-pointer [&.vim-nav-focused]:ring-2 [&.vim-nav-focused]:ring-primary/50 [&.vim-nav-focused]:rounded"
      >
        <summary class="flex items-start gap-2 list-none select-none" data-vim-flyout-item>
          <.icon
            name="hero-chevron-right-mini"
            class="size-3 flex-shrink-0 mt-px text-base-content/30 group-open:rotate-90 transition-transform"
          />
          <div class="min-w-0 flex-1">
            <span class={[
              "truncate block",
              if(@note.title && @note.title != "", do: "font-medium text-base-content/80")
            ]}>
              {note_label(@note)}
            </span>
            <span class="text-micro text-base-content/30 uppercase tracking-wide">
              {@note.parent_type}
            </span>
          </div>
        </summary>
        <div class="mt-1 ml-5 text-base-content/60 whitespace-pre-wrap break-words leading-relaxed">
          {@note.body}
        </div>
        <div class="mt-1.5 ml-5">
          <.link
            navigate={"/notes/#{@note.id}/edit"}
            class="text-nano text-primary/60 hover:text-primary transition-colors"
          >
            Edit →
          </.link>
        </div>
      </details>
    <% else %>
      <%!-- Large note: navigate to edit page --%>
      <.link
        navigate={"/notes/#{@note.id}/edit"}
        data-vim-flyout-item
        class="flex flex-col gap-0.5 px-3 py-2 text-xs text-base-content/65 hover:text-base-content/90 hover:bg-base-content/5 transition-colors [&.vim-nav-focused]:ring-2 [&.vim-nav-focused]:ring-primary/50 [&.vim-nav-focused]:rounded"
      >
        <span class={[
          "truncate",
          if(@note.title && @note.title != "", do: "font-medium text-base-content/80")
        ]}>
          {note_label(@note)}
        </span>
        <span :if={@note.title && @note.title != "" && @note.body && @note.body != ""}
              class="truncate text-base-content/40">
          {@note.body}
        </span>
        <span class="text-micro text-base-content/30 uppercase tracking-wide">
          {@note.parent_type}
        </span>
      </.link>
    <% end %>
    """
  end

  defp note_label(note) do
    label = note.title || String.slice(note.body || "", 0, 60)
    if label == "", do: "(empty)", else: label
  end

  defp small_note?(note) do
    byte_size(note.body || "") < 200
  end
end
