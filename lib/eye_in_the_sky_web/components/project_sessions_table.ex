defmodule EyeInTheSkyWeb.Components.ProjectSessionsTable do
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: EyeInTheSkyWeb.Endpoint,
    router: EyeInTheSkyWeb.Router,
    statics: EyeInTheSkyWeb.static_paths()

  import EyeInTheSkyWeb.CoreComponents
  import EyeInTheSkyWeb.Components.Icons
  import EyeInTheSkyWeb.Components.SessionCard

  @doc "Bulk-action toolbar shown in archived view."
  attr :session_filter, :string, required: true
  attr :agents, :list, required: true
  attr :selected_ids, :any, required: true

  def selection_toolbar(assigns) do
    ~H"""
    <%= if @session_filter == "archived" && @agents != [] do %>
      <div class="mt-2 flex items-center gap-3 px-2 py-1.5">
        <input
          type="checkbox"
          checked={MapSet.size(@selected_ids) == length(@agents) && @agents != []}
          phx-click="toggle_select_all"
          class="checkbox checkbox-xs checkbox-primary"
          aria-label="Select all archived sessions"
        />
        <%= if MapSet.size(@selected_ids) > 0 do %>
          <span class="text-[11px] text-base-content/50 font-medium">
            {MapSet.size(@selected_ids)} selected
          </span>
          <button
            phx-click="delete_selected"
            class="btn btn-ghost btn-xs text-error/70 hover:text-error hover:bg-error/10 gap-1"
          >
            <.icon name="hero-trash-mini" class="w-3.5 h-3.5" /> Delete
          </button>
        <% else %>
          <span class="text-[11px] text-base-content/30">{length(@agents)} archived</span>
        <% end %>
      </div>
    <% end %>
    """
  end

  @doc "Stream-backed session list with depth indentation and per-row actions."
  attr :agents, :list, required: true
  attr :streams, :any, required: true
  attr :depths, :map, required: true
  attr :session_filter, :string, required: true
  attr :selected_ids, :any, required: true
  attr :editing_session_id, :any, required: true
  attr :search_query, :string, required: true

  def session_list(assigns) do
    ~H"""
    <div class="mt-2 rounded-xl shadow-sm">
      <%= if @agents == [] do %>
        <.empty_state
          id="project-sessions-empty"
          title="No sessions found"
          subtitle={
            if @search_query != "" || @session_filter != "all",
              do: "Try adjusting your search or filters",
              else: "Sessions will appear here when agents start working on this project"
          }
        />
      <% else %>
        <div
          id="ps-list"
          phx-update="stream"
          class="divide-y divide-base-content/5 bg-base-200 rounded-xl px-4"
        >
          <div
            :for={{dom_id, agent} <- @streams.session_list}
            id={dom_id}
            class={
              if Map.get(@depths, agent.id, 0) > 0,
                do: "ml-5 border-l-2 border-primary/20 pl-3",
                else: ""
            }
          >
            <.session_row
              session={agent}
              select_mode={@session_filter == "archived"}
              selected={MapSet.member?(@selected_ids, to_string(agent.id))}
              editing_session_id={@editing_session_id}
            >
              <:actions>
                <div class="md:opacity-0 md:group-hover:opacity-100 relative dropdown dropdown-end transition-all">
                  <button
                    tabindex="0"
                    type="button"
                    class="min-h-[44px] min-w-[44px] flex items-center justify-center rounded-md text-base-content/35 hover:text-base-content/70 hover:bg-base-content/5 transition-colors"
                    aria-label="More options"
                    phx-click="noop"
                  >
                    <.icon name="hero-ellipsis-horizontal-mini" class="w-4 h-4" />
                  </button>
                  <ul
                    tabindex="0"
                    class="dropdown-content z-50 menu menu-xs bg-base-200 border border-base-content/10 rounded-lg shadow-lg w-44 p-1"
                  >
                    <%= if agent.id do %>
                      <li>
                        <a
                          href={~p"/dm/#{agent.id}"}
                          target="_blank"
                          class="flex items-center gap-2"
                        >
                          <.icon name="hero-arrow-top-right-on-square-mini" class="w-3.5 h-3.5" />
                          Open in new tab
                        </a>
                      </li>
                    <% end %>
                    <li>
                      <button
                        type="button"
                        phx-click="rename_session"
                        phx-value-session_id={agent.id}
                        class="flex items-center gap-2"
                      >
                        <.icon name="hero-pencil-square-mini" class="w-3.5 h-3.5" />
                        Rename
                      </button>
                    </li>
                    <%= if agent.agent && agent.agent.uuid && agent.uuid do %>
                      <li>
                        <button
                          id={"bookmark-btn-#{agent.uuid}"}
                          type="button"
                          phx-hook="BookmarkAgent"
                          data-agent-id={agent.agent.uuid}
                          data-session-id={agent.uuid}
                          data-agent-name={agent.name || agent.agent.description || "Agent"}
                          data-agent-status={agent.status}
                          class="bookmark-button flex items-center gap-2"
                          aria-label="Bookmark agent"
                        >
                          <.heart class="bookmark-icon w-3.5 h-3.5" />
                          <span class="bookmark-label">Favorite</span>
                        </button>
                      </li>
                    <% end %>
                    <%= if agent.uuid do %>
                      <%= if agent.archived_at do %>
                        <li>
                          <button
                            type="button"
                            phx-click="unarchive_session"
                            phx-value-session_id={agent.id}
                            class="flex items-center gap-2 text-info"
                          >
                            <.icon name="hero-arrow-up-tray-mini" class="w-3.5 h-3.5" />
                            Unarchive
                          </button>
                        </li>
                        <li>
                          <button
                            type="button"
                            phx-click="delete_session"
                            phx-value-session_id={agent.id}
                            class="flex items-center gap-2 text-error"
                          >
                            <.icon name="hero-trash-mini" class="w-3.5 h-3.5" />
                            Delete
                          </button>
                        </li>
                      <% else %>
                        <li>
                          <button
                            type="button"
                            phx-click="archive_session"
                            phx-value-session_id={agent.id}
                            class="flex items-center gap-2 text-warning"
                          >
                            <.icon name="hero-archive-box-mini" class="w-3.5 h-3.5" />
                            Archive
                          </button>
                        </li>
                      <% end %>
                    <% end %>
                  </ul>
                </div>
              </:actions>
            </.session_row>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
