defmodule EyeInTheSkyWeb.Components.ProjectSessionsTable do
  @moduledoc false
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: EyeInTheSkyWeb.Endpoint,
    router: EyeInTheSkyWeb.Router,
    statics: EyeInTheSkyWeb.static_paths()

  import EyeInTheSkyWeb.CoreComponents
  import EyeInTheSkyWeb.Components.SessionCard
  import EyeInTheSkyWeb.Components.AgentList, only: [session_row_menu: 1]

  alias EyeInTheSkyWeb.ProjectLive.Sessions.Selection

  @doc "Bulk-action toolbar shown when select mode is active."
  attr :select_mode, :boolean, required: true
  attr :agents, :list, required: true
  attr :selected_ids, :any, required: true
  attr :off_screen_selected_count, :integer, default: 0

  def selection_toolbar(assigns) do
    ~H"""
    <%= if MapSet.size(@selected_ids) > 0 do %>
      <div class="mt-2 flex items-center gap-3 px-2 py-1.5">
        <%
          {all_checked, some_checked} = Selection.select_all_checkbox_state(@selected_ids, @agents)
        %>
        <.square_checkbox
          id="sessions-select-all-checkbox"
          checked={all_checked}
          indeterminate={some_checked}
          phx-click="toggle_select_all"
          aria-label="Select all sessions"
        />
        <span
          data-role="selection-count"
          data-selected-count={MapSet.size(@selected_ids)}
          data-offscreen-count={@off_screen_selected_count}
          class="text-[11px] text-base-content/50 font-medium"
        >
          {MapSet.size(@selected_ids)} selected
          <%= if @off_screen_selected_count > 0 do %>
            <span class="text-base-content/30">({@off_screen_selected_count} not visible)</span>
          <% end %>
        </span>
        <button
          phx-click="confirm_archive_selected"
          class="btn btn-ghost btn-xs text-warning/70 hover:text-warning hover:bg-warning/10 gap-1 min-h-[44px] min-w-[44px]"
        >
          <.icon name="hero-archive-box-mini" class="w-3.5 h-3.5" /> Archive
        </button>
        <button
          phx-click="delete_selected"
          class="btn btn-ghost btn-sm min-h-[44px] text-error/70 hover:text-error hover:bg-error/10 gap-1"
        >
          <.icon name="hero-trash-mini" class="w-3.5 h-3.5" /> Delete
        </button>
        <button
          phx-click="exit_select_mode"
          class="ml-auto btn btn-ghost btn-xs btn-square min-h-[44px] min-w-[44px] text-base-content/40 hover:text-base-content/70"
          aria-label="Exit select mode"
        >
          <.icon name="hero-x-mark" class="w-4 h-4" />
        </button>
      </div>
    <% end %>
    """
  end

  @doc "Stream-backed session list with depth indentation and per-row actions."
  attr :agents, :list, required: true
  attr :streams, :any, required: true
  attr :depths, :map, required: true
  attr :session_filter, :string, required: true
  attr :select_mode, :boolean, default: false
  attr :selected_ids, :any, required: true
  attr :indeterminate_ids, :any, default: MapSet.new()
  attr :editing_session_id, :any, required: true
  attr :search_query, :string, required: true
  attr :canvases, :list, default: []
  attr :show_new_canvas_for, :any, default: nil
  attr :scope, :any, default: nil

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
        <div phx-hook="ShiftSelect" id="ps-list-shift-wrapper">
          <div
            id="ps-list"
            phx-update="stream"
            phx-hook="SessionsDropdownGuard"
            class="divide-y divide-base-content/5"
          >
            <div
              :for={{dom_id, agent} <- @streams.session_list}
              id={dom_id}
              data-row-id={agent.id}
              class={
                if Map.get(@depths, agent.id, 0) > 0,
                  do: "ml-5 border-l-2 pl-3",
                  else: ""
              }
            >
              <.session_row
                session={agent}
                select_mode={@select_mode}
                selected={MapSet.member?(@selected_ids, to_string(agent.id))}
                indeterminate={MapSet.member?(@indeterminate_ids, to_string(agent.id))}
                editing_session_id={@editing_session_id}
                project_name={if @scope == :all, do: Map.get(agent, :project_name), else: nil}
              >
                <:actions>
                  <.session_row_menu
                    agent={agent}
                    canvases={@canvases}
                    show_new_canvas_for={@show_new_canvas_for}
                  />
                </:actions>
              </.session_row>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

end
