defmodule EyeInTheSkyWeb.Components.AgentList do
  @moduledoc false
  use EyeInTheSkyWeb, :html


  @filter_tabs [
    {"all", "All", "text-base-content"},
    {"active", "Active", "text-success"},
    {"completed", "Completed", "text-base-content"},
    {"archived", "Archived", "text-warning"}
  ]

  def filter_tabs(assigns) do
    assigns = assign(assigns, :tabs, @filter_tabs)

    ~H"""
    <div class="flex items-center gap-1 bg-base-200/40 rounded-lg p-0.5">
      <button
        :for={{value, label, active_color} <- @tabs}
        phx-click="filter_session"
        phx-value-filter={value}
        class={"px-3 py-2 rounded-md text-xs font-medium transition-all duration-150 min-h-[44px] flex items-center " <>
          if(@current == value,
            do: "bg-base-100 #{active_color} shadow-sm",
            else: "text-base-content/40 hover:text-base-content/60"
          )}
      >
        {label}
      </button>
    </div>
    """
  end

  def search_toolbar(assigns) do
    ~H"""
    <div class="sticky top-[calc(3rem+env(safe-area-inset-top))] md:top-16 z-10 bg-base-100/85 backdrop-blur-md -mx-4 sm:-mx-6 lg:-mx-8 px-4 sm:px-6 lg:px-8 py-3 border-b border-base-content/5">
      <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:gap-3">
        <.search_bar
          id="agent-search"
          label="Search agents"
          placeholder="Search..."
          value={@search_query}
          on_change="search"
          class="flex-1 max-w-sm"
        />
        <.filter_tabs current={@session_filter} />
      </div>
    </div>
    """
  end

  attr :agents, :list, required: true
  attr :selected_ids, :any, required: true
  attr :select_mode, :boolean, default: false
  attr :session_filter, :string, default: "all"

  def bulk_action_bar(assigns) do
    ~H"""
    <div
      :if={@select_mode && @agents != []}
      class="mt-2 flex items-center gap-3 px-2 py-1.5"
    >
      <input
        type="checkbox"
        checked={MapSet.size(@selected_ids) == length(@agents)}
        phx-click="toggle_select_all"
        class="checkbox checkbox-xs checkbox-primary"
        aria-label="Select all sessions"
      />
      <%= if MapSet.size(@selected_ids) > 0 do %>
        <span class="text-[11px] text-base-content/50 font-medium">
          {MapSet.size(@selected_ids)} selected
        </span>
        <button
          phx-click="confirm_delete_selected"
          class="btn btn-ghost btn-xs text-error/70 hover:text-error hover:bg-error/10 gap-1 min-h-[44px] min-w-[44px]"
        >
          <.icon name="hero-trash-mini" class="size-3.5" /> Delete
        </button>
      <% else %>
        <span class="text-[11px] text-base-content/30">{length(@agents)} sessions</span>
      <% end %>
      <button
        phx-click="exit_select_mode"
        class="ml-auto btn btn-ghost btn-xs btn-square min-h-[44px] min-w-[44px] text-base-content/40 hover:text-base-content/70"
        aria-label="Exit select mode"
      >
        <.icon name="hero-x-mark" class="size-4" />
      </button>
    </div>
    """
  end

  def agent_row_menu(assigns) do
    ~H"""
    <.session_row_menu
      agent={@agent}
      canvases={@canvases}
      show_new_canvas_for={@show_new_canvas_for}
    />
    """
  end

  def session_row_menu(assigns) do
    ~H"""
    <details
      id={"session-menu-#{@agent.id}"}
      phx-update="ignore"
      class="md:opacity-0 md:group-hover/row:opacity-100 open:opacity-100 relative dropdown dropdown-end"
    >
      <summary
        class="min-h-[44px] min-w-[44px] flex items-center justify-center rounded-md text-base-content/35 hover:text-base-content/70 hover:bg-base-content/5 transition-colors cursor-pointer list-none"
        aria-label="More options"
      >
        <.icon name="hero-ellipsis-horizontal-mini" class="size-4" />
      </summary>
      <ul class="dropdown-content z-50 menu menu-xs bg-base-200 border border-base-content/10 rounded-lg shadow-lg w-44 p-1">
        <%= if @agent.id do %>
          <li>
            <a href={~p"/dm/#{@agent.id}"} target="_blank" class="flex items-center gap-2">
              <.icon name="hero-arrow-top-right-on-square-mini" class="size-3.5" />
              Open in new tab
            </a>
          </li>
        <% end %>
        <li>
          <button
            type="button"
            phx-click="rename_session"
            phx-value-session_id={@agent.id}
            class="flex items-center gap-2"
          >
            <.icon name="hero-pencil-square-mini" class="size-3.5" /> Rename
          </button>
        </li>
        <%!-- Canvas inline expand --%>
        <.canvas_submenu
          agent={@agent}
          canvases={@canvases}
          show_new_canvas_for={@show_new_canvas_for}
        />
        <%= if not is_nil(@agent.agent) && not is_nil(@agent.agent.uuid) && not is_nil(@agent.uuid) do %>
          <li>
            <button
              id={"bookmark-btn-#{@agent.uuid}"}
              type="button"
              phx-hook="BookmarkAgent"
              data-agent-id={@agent.agent.uuid}
              data-session-id={@agent.uuid}
              data-agent-name={@agent.name || @agent.agent.description || "Agent"}
              data-agent-status={@agent.status}
              class="bookmark-button flex items-center gap-2"
              aria-label="Bookmark agent"
            >
              <.icon name="hero-heart" class="bookmark-icon size-3.5" />
              <span class="bookmark-label">Favorite</span>
            </button>
          </li>
        <% end %>
        <%= if @agent.uuid do %>
          <li class="pointer-events-none"><hr class="border-base-content/10 my-1" /></li>
          <%= if @agent.archived_at do %>
            <li>
              <button
                type="button"
                phx-click="unarchive_session"
                phx-value-session_id={@agent.id}
                class="flex items-center gap-2 text-info"
              >
                <.icon name="hero-arrow-up-tray-mini" class="size-3.5" /> Unarchive
              </button>
            </li>
            <li>
              <button
                type="button"
                phx-click="delete_session"
                phx-value-session_id={@agent.id}
                class="flex items-center gap-2 text-error"
              >
                <.icon name="hero-trash-mini" class="size-3.5" /> Delete
              </button>
            </li>
          <% else %>
            <li>
              <button
                type="button"
                phx-click="archive_session"
                phx-value-session_id={@agent.id}
                class="flex items-center gap-2 text-warning"
              >
                <.icon name="hero-archive-box-mini" class="size-3.5" /> Archive
              </button>
            </li>
          <% end %>
        <% end %>
      </ul>
    </details>
    """
  end

  def delete_confirm_modal(assigns) do
    ~H"""
    <dialog
      id="delete-confirm-modal"
      class={"modal modal-bottom sm:modal-middle " <> if(@show_delete_confirm, do: "modal-open", else: "")}
    >
      <div class="modal-box w-full sm:max-w-sm pb-[env(safe-area-inset-bottom)]">
        <h3 class="text-lg font-bold">Delete sessions</h3>
        <p class="py-4 text-sm text-base-content/70">
          Permanently delete {MapSet.size(@selected_ids)} selected session{if MapSet.size(
                                                                                @selected_ids
                                                                              ) != 1, do: "s"}? This cannot be undone.
        </p>
        <div class="modal-action">
          <button phx-click="cancel_delete_selected" class="btn btn-sm btn-ghost min-h-[44px]">
            Cancel
          </button>
          <button phx-click="delete_selected" class="btn btn-sm btn-error min-h-[44px]">
            Delete
          </button>
        </div>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button phx-click="cancel_delete_selected">close</button>
      </form>
    </dialog>
    """
  end

  def canvas_submenu(assigns) do
    ~H"""
    <li>
      <details>
        <summary class="flex items-center gap-2">
          <.icon name="hero-squares-2x2-mini" class="size-3.5" /> Add to Canvas
        </summary>
        <ul>
          <%= for canvas <- @canvases do %>
            <li>
              <button
                type="button"
                phx-click="add_to_canvas"
                phx-value-canvas-id={canvas.id}
                phx-value-session-id={@agent.id}
                class="flex items-center gap-2"
              >
                {canvas.name}
              </button>
            </li>
          <% end %>
          <li class="pointer-events-none"><hr class="border-base-content/10 my-0.5" /></li>
          <%= if @show_new_canvas_for != to_string(@agent.id) do %>
            <li>
              <button
                type="button"
                phx-click="show_new_canvas_form"
                phx-value-agent-id={@agent.id}
                class="flex items-center gap-2 text-secondary"
              >
                + New canvas
              </button>
            </li>
          <% else %>
            <li>
              <form phx-submit="add_to_new_canvas" class="flex flex-col gap-1 p-1 w-full">
                <input type="hidden" name="session_id" value={@agent.id} />
                <input
                  type="text"
                  name="canvas_name"
                  class="input input-xs w-full text-base"
                  placeholder="Canvas name..."
                  autocomplete="off"
                />
                <button type="submit" class="btn btn-primary btn-xs w-full">
                  Create &amp; Add
                </button>
              </form>
            </li>
          <% end %>
        </ul>
      </details>
    </li>
    """
  end

  attr :show_archive_confirm, :boolean, required: true
  attr :selected_ids, :any, required: true

  def archive_confirm_modal(assigns) do
    ~H"""
    <dialog
      id="archive-confirm-modal"
      class={"modal modal-bottom sm:modal-middle " <> if(@show_archive_confirm, do: "modal-open", else: "")}
    >
      <div class="modal-box w-full sm:max-w-sm pb-[env(safe-area-inset-bottom)]">
        <h3 class="text-lg font-bold">Archive sessions</h3>
        <p class="py-4 text-sm text-base-content/70">
          <% count = MapSet.size(@selected_ids) %>
          Archive {count} selected session{if count == 1, do: "", else: "s"}?
          Archived sessions can be unarchived later.
        </p>
        <div class="modal-action">
          <button phx-click="cancel_archive_selected" class="btn btn-sm btn-ghost min-h-[44px]">
            Cancel
          </button>
          <button phx-click="archive_selected" class="btn btn-sm btn-warning min-h-[44px]">
            Archive
          </button>
        </div>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button phx-click="cancel_archive_selected">close</button>
      </form>
    </dialog>
    """
  end
end
