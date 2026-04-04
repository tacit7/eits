defmodule EyeInTheSkyWeb.Components.DmPage.NotesTab do
  @moduledoc false

  use EyeInTheSkyWeb, :html

  import EyeInTheSkyWeb.Components.DmHelpers, only: [extract_title: 1, to_utc_string: 1]

  attr :notes, :list, default: []

  def notes_tab(assigns) do
    ~H"""
    <%= if @notes == [] do %>
      <.empty_state
        id="dm-notes-empty"
        icon="hero-document-text"
        title="No notes yet"
        subtitle="Notes from this session will appear here"
      />
    <% else %>
      <div
        class="space-y-1 bg-base-200 rounded-xl shadow-sm p-4"
        id="dm-note-list"
      >
        <%= for note <- @notes do %>
          <div
            class="collapse collapse-arrow rounded-lg border border-base-content/5 bg-base-200 hover:border-base-content/10 transition-colors"
            id={"dm-note-#{note.id}"}
          >
            <input type="checkbox" />
            <div class="collapse-title py-3 px-4 min-h-0">
              <div class="flex items-center gap-3">
                <%!-- Star button --%>
                <button
                  type="button"
                  phx-click={JS.push("toggle_star", value: %{note_id: note.id})}
                  onclick="event.stopPropagation(); event.preventDefault();"
                  class="flex-shrink-0 p-0.5 rounded transition-transform hover:scale-110"
                  id={"toggle-note-star-#{note.id}"}
                >
                  <.icon
                    name={if note.starred == 1, do: "hero-star-solid", else: "hero-star"}
                    class={"w-4 h-4 #{if note.starred == 1, do: "text-warning", else: "text-base-content/15 hover:text-base-content/30"}"}
                  />
                </button>
                <%!-- Title + meta --%>
                <div class="flex-1 min-w-0">
                  <h3 class="text-[13px] font-semibold text-base-content/85 truncate">
                    {note.title || extract_title(note.body)}
                  </h3>
                  <div class="flex items-center gap-1.5 mt-0.5 text-[11px] text-base-content/30">
                    <span class="font-mono">
                      {String.slice(note.uuid || to_string(note.id), 0..7)}
                    </span>

                    <button
                      type="button"
                      class="z-10 cursor-pointer transition-colors hover:text-primary"
                      phx-hook="CopyToClipboard"
                      id={"copy-note-#{note.id}"}
                      data-copy={note.uuid || to_string(note.id)}
                      onclick="event.stopPropagation(); event.preventDefault();"
                    >
                      <.icon name="hero-clipboard-document" class="h-3 w-3" />
                    </button>

                    <span class="text-base-content/15">/</span>
                    <time
                      id={"note-time-#{note.id}"}
                      class="tabular-nums"
                      data-utc={to_utc_string(note.created_at)}
                      data-fmt="short"
                      phx-hook="LocalTime"
                    >
                    </time>
                  </div>
                </div>
              </div>
            </div>

            <div class="collapse-content px-4 pb-4">
              <div class="pl-[30px]">
                <div
                  id={"note-body-#{note.id}"}
                  class="dm-markdown text-sm text-base-content/70 leading-relaxed"
                  phx-hook="MarkdownMessage"
                  data-raw-body={note.body}
                >
                </div>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    <% end %>
    """
  end

end
