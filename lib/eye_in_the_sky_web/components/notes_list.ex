defmodule EyeInTheSkyWeb.Components.NotesList do
  @moduledoc false
  use Phoenix.Component
  import EyeInTheSkyWeb.CoreComponents
  import EyeInTheSkyWeb.Helpers.ViewHelpers, only: [relative_time: 1]
  import EyeInTheSkyWeb.ControllerHelpers, only: [normalize_parent_type: 1]

  attr :notes, :list, required: true
  attr :starred_filter, :boolean, default: false
  attr :search_query, :string, default: ""
  attr :sort_by, :string, default: "newest"
  attr :type_filter, :string, default: "all"
  attr :empty_id, :string, default: "notes-empty"
  attr :editing_note_id, :integer, default: nil
  attr :current_path, :string, default: "/notes"
  attr :selected_ids, :any, default: %MapSet{}
  attr :select_mode, :boolean, default: false
  attr :installed_editors, :list, default: []
  attr :preferred_editor, :string, default: "code"

  def notes_list(assigns) do
    ~H"""
    <%!-- Bulk-select toolbar --%>
    <%= if @select_mode && @notes != [] do %>
      <div class="mb-3 flex items-center gap-3 px-2 py-1.5">
        <div phx-click="toggle_select_all_notes" class="cursor-pointer">
          <.square_checkbox
            checked={MapSet.size(@selected_ids) == length(@notes)}
            indeterminate={
              MapSet.size(@selected_ids) > 0 && MapSet.size(@selected_ids) < length(@notes)
            }
            aria-label="Select all notes"
          />
        </div>
        <%= if MapSet.size(@selected_ids) > 0 do %>
          <span class="text-mini text-base-content/50 font-medium">
            {MapSet.size(@selected_ids)} selected
          </span>
          <button
            phx-click="delete_selected_notes"
            data-confirm={"Delete #{MapSet.size(@selected_ids)} note#{if MapSet.size(@selected_ids) != 1, do: "s"}?"}
            class="focus-ring inline-flex min-h-[44px] min-w-[44px] items-center justify-center gap-1 rounded-box px-3 text-mini font-medium text-error/70 transition-colors hover:bg-error/10 hover:text-error"
          >
            <.icon name="hero-trash-mini" class="size-3.5" /> Delete
          </button>
        <% else %>
          <span class="text-mini text-base-content/30">{length(@notes)} notes</span>
        <% end %>
        <button
          phx-click="exit_select_mode_notes"
          class="focus-ring ml-auto inline-flex min-h-[44px] min-w-[44px] items-center justify-center rounded-box text-base-content/40 transition-colors hover:bg-base-content/5 hover:text-base-content/70"
          aria-label="Exit select mode"
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>
    <% end %>

    <%= if @notes != [] do %>
      <div data-vim-list class="divide-y divide-base-content/5">
        <%= for note <- @notes do %>
          <div
            class="py-0.5 relative group/row flex items-start"
            data-ctx="note"
            data-ctx-id={note.id}
            data-ctx-starred={to_string(starred?(note))}
          >
            <%!-- Select checkbox: absolute, outside row flow, hover-reveal --%>
            <div
              class={[
                "p-1 absolute z-10 top-1/2 -translate-y-1/2 -translate-x-1/2",
                "left-4 sm:left-[-0.875rem]",
                if(@select_mode,
                  do: "opacity-100 scale-100",
                  else:
                    "opacity-0 scale-75 group-hover/row:opacity-100 group-hover/row:scale-100 transition duration-100"
                )
              ]}
              aria-hidden={to_string(!@select_mode)}
              phx-click="toggle_select_note"
              phx-value-note_id={note.id}
            >
              <.square_checkbox
                checked={MapSet.member?(@selected_ids, to_string(note.id))}
                checkbox_area={true}
                aria-label={"Select note #{note.title || note.id}"}
              />
            </div>
            <%!-- Collapse: chevron expands inline body --%>
            <div class="eits-disclosure eits-disclosure--row flex-1 overflow-visible">
              <input
                id={"note-disclosure-#{note.id}"}
                type="checkbox"
                class="min-h-0 p-0"
                checked={note.id == @editing_note_id}
              />
              <label
                for={"note-disclosure-#{note.id}"}
                data-vim-list-item
                data-vim-item-type="note"
                data-vim-item-id={note.id}
                data-vim-item-title={note.title || extract_title(note.body)}
                data-vim-item-url={"/notes/#{note.id}/edit"}
                class="eits-disclosure__summary py-2.5 px-3 min-h-0 flex flex-col gap-0.5"
              >
                <%!-- Title — clicking expands the inline note body --%>
                <div class="flex items-center gap-2 pr-6">
                  <.custom_icon
                    name="lucide-robot"
                    class="size-3.5 flex-shrink-0 text-base-content/35"
                  />
                  <span class="text-message font-medium text-base-content/85 truncate [&.vim-nav-focused]:ring-2 [&.vim-nav-focused]:ring-primary/50 [&.vim-nav-focused]:rounded-box">
                    {note.title || extract_title(note.body)}
                  </span>
                  <%= if starred?(note) do %>
                    <.icon name="hero-star-solid" class="size-3 text-warning flex-shrink-0" />
                  <% end %>
                </div>
                <%!-- Metadata: type badge | source ref | age --%>
                <div class="flex items-center gap-1.5 pl-5 text-mini text-base-content/40">
                  <span class={[
                    "inline-flex items-center gap-1 px-1.5 py-0.5 rounded-box text-mini font-medium",
                    parent_type_class(note.parent_type)
                  ]}>
                    <%= if String.starts_with?(parent_type_icon(note.parent_type), "lucide-") do %>
                      <.custom_icon name={parent_type_icon(note.parent_type)} class="w-2.5 h-2.5" />
                    <% else %>
                      <.icon name={parent_type_icon(note.parent_type)} class="w-2.5 h-2.5" />
                    <% end %>
                    {parent_type_label(note.parent_type)}
                  </span>
                  <%= if ref = format_parent_ref(note.parent_id) do %>
                    <span class="text-base-content/20">|</span>
                    <span class="font-mono text-base-content/30">{ref}</span>
                  <% end %>
                  <span class="text-base-content/20">|</span>
                  <span class="tabular-nums">{relative_time(note.created_at)}</span>
                </div>
                <%!-- Snippet preview --%>
                <%= if snippet = extract_snippet(note.body) do %>
                  <p class="text-mini text-base-content/55 truncate leading-snug mt-0.5 pl-5 pr-6">
                    {snippet}
                  </p>
                <% end %>
              </label>
              <div class="eits-disclosure__content px-3 pb-3">
                <%= if note.id == @editing_note_id do %>
                  <div
                    id={"note-editor-#{note.id}"}
                    phx-hook="NoteEditor"
                    data-note-id={note.id}
                    data-body={Base.encode64(note.body || "")}
                    class="border border-base-content/10 rounded-box overflow-hidden min-h-[200px] mb-2"
                  >
                  </div>
                  <div class="mb-2 flex items-center gap-3">
                    <span class="text-mini text-base-content/40">⌘S to save</span>
                    <button
                      type="button"
                      phx-click="note_edit_cancelled"
                      phx-value-note_id={note.id}
                      class="flex items-center gap-1.5 text-mini text-base-content/30 hover:text-base-content/60 transition-colors px-1"
                    >
                      Cancel
                    </button>
                  </div>
                <% else %>
                  <div
                    id={"note-body-#{note.id}"}
                    class="dm-markdown text-message text-base-content/70 leading-relaxed pb-2"
                    phx-hook="MarkdownMessage"
                    data-raw-body={note.body}
                  >
                  </div>
                <% end %>
              </div>
            </div>

            <%!-- Right: star always visible, kebab on hover --%>
            <div class="flex items-center gap-0.5 flex-shrink-0 pt-3">
              <button
                type="button"
                phx-click="toggle_star"
                phx-value-note_id={note.id}
                class={"flex items-center justify-center min-h-[44px] min-w-[44px] px-1 py-1 rounded-box transition-colors " <>
                  if(starred?(note),
                    do: "text-warning",
                    else: "text-base-content/20 hover:text-warning"
                  )}
                aria-label={if starred?(note), do: "Unstar note", else: "Star note"}
              >
                <.icon
                  name={if starred?(note), do: "hero-star-solid", else: "hero-star"}
                  class="size-3.5"
                />
              </button>
              <div class="eits-dropdown" id={"note-actions-#{note.id}"} phx-update="ignore">
                <button
                  tabindex="0"
                  role="button"
                  class="flex items-center justify-center min-h-[44px] min-w-[44px] px-1 py-1 rounded-box text-base-content/20 hover:text-base-content/60 hover:bg-base-200/50 transition-colors sm:opacity-0 sm:group-hover:opacity-100"
                  aria-label="More actions"
                >
                  <.icon name="hero-ellipsis-vertical" class="size-4" />
                </button>
                <ul
                  tabindex="0"
                  class="eits-menu absolute z-50 eits-menu-list  p-1 shadow-lg bg-base-200 rounded-box w-48 border border-base-content/8"
                >
                  <li>
                    <button
                      type="button"
                      phx-click="edit_note"
                      phx-value-note_id={note.id}
                      class="flex items-center gap-2 text-mini"
                    >
                      <.icon name="hero-pencil-square" class="size-3.5" /> Edit inline
                    </button>
                  </li>
                  <li>
                    <.link
                      navigate={"/notes/#{note.id}/edit?return_to=#{URI.encode_www_form(@current_path)}"}
                      class="flex items-center gap-2 text-mini"
                    >
                      <.icon name="hero-arrows-pointing-out" class="size-3.5" /> Open full editor
                    </.link>
                  </li>
                  <%= if @installed_editors != [] do %>
                    <% preferred =
                      Enum.find(@installed_editors, &(&1.id == @preferred_editor)) ||
                        List.first(@installed_editors) %>
                    <li>
                      <button
                        type="button"
                        phx-click="open_in_editor"
                        phx-value-editor={preferred && preferred.id}
                        phx-value-id={note.id}
                        class="flex items-center gap-2 text-mini"
                      >
                        <.icon name="hero-arrow-top-right-on-square" class="size-3.5" />
                        Open in {preferred && preferred.label}
                      </button>
                    </li>
                  <% end %>
                  <li class="mt-1 border-t border-base-content/8 pt-1">
                    <button
                      type="button"
                      phx-click="delete_note"
                      phx-value-note_id={note.id}
                      data-confirm="Delete this note?"
                      class="flex items-center gap-2 text-mini text-error/70 hover:!text-error hover:!bg-error/10"
                    >
                      <.icon name="hero-trash" class="size-3.5" /> Delete
                    </button>
                  </li>
                </ul>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    <% else %>
      <.empty_state
        id={@empty_id}
        icon="hero-document-text"
        title="No notes yet"
        subtitle="Notes from agents will appear here"
      />
    <% end %>
    """
  end

  defp parent_type_label(type) do
    case normalize_parent_type(type) do
      "session" -> "Session"
      "agent" -> "Agent"
      "project" -> "Project"
      "task" -> "Task"
      t when is_binary(t) -> String.capitalize(t)
      _ -> "Note"
    end
  end

  defp parent_type_icon(type) do
    case normalize_parent_type(type) do
      "session" -> "hero-clock-mini"
      "agent" -> "lucide-robot"
      "project" -> "hero-folder-mini"
      "task" -> "hero-clipboard-document-list-mini"
      _ -> "hero-document-text-mini"
    end
  end

  defp parent_type_class(type) do
    case normalize_parent_type(type) do
      "session" -> "bg-info/10 text-info/70"
      "agent" -> "bg-primary/10 text-primary/70"
      "project" -> "bg-success/10 text-success/70"
      _ -> "bg-base-content/[0.06] text-base-content/50"
    end
  end

  # UUID (36 chars) -> first 8 chars; integer string -> "#N"; nil/empty -> nil
  defp format_parent_ref(nil), do: nil
  defp format_parent_ref(""), do: nil

  defp format_parent_ref(id) when is_binary(id) do
    if String.length(id) == 36 and String.contains?(id, "-") do
      String.slice(id, 0, 8)
    else
      "#" <> id
    end
  end

  def extract_title(nil), do: "Untitled"

  def extract_title(body) when is_binary(body) do
    body
    |> String.trim()
    |> String.split("\n")
    |> List.first()
    |> String.replace(~r/^#+\s*/, "")
    |> String.slice(0..50)
    |> then(fn text ->
      if String.length(text) >= 50, do: text <> "...", else: text
    end)
  end

  defp starred?(note), do: note.starred == true

  defp extract_snippet(nil), do: nil

  defp extract_snippet(body) when is_binary(body) do
    body
    |> String.trim()
    |> String.split("\n")
    |> Enum.drop(1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(fn line ->
      line == "" or String.starts_with?(line, "#") or String.starts_with?(line, "---")
    end)
    |> List.first()
    |> case do
      nil ->
        nil

      line ->
        stripped =
          line
          |> String.replace(~r/^[-*+]\s+/, "")
          |> String.replace(~r/^\d+\.\s+/, "")
          |> String.replace(~r/\*\*(.+?)\*\*/, "\\1")
          |> String.replace(~r/\*(.+?)\*/, "\\1")
          |> String.replace(~r/`(.+?)`/, "\\1")
          |> String.replace(~r/\[(.+?)\]\(.+?\)/, "\\1")

        if String.length(stripped) > 0, do: String.slice(stripped, 0, 120), else: nil
    end
  end
end
