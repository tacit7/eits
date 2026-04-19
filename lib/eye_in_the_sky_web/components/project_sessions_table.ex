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
            class="btn btn-ghost btn-sm min-h-[44px] text-error/70 hover:text-error hover:bg-error/10 gap-1"
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
  attr :canvases, :list, default: []
  attr :show_new_canvas_for, :any, default: nil

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
          class="divide-y divide-base-content/5"
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
                <.session_row_menu
                  agent={agent}
                  canvases={@canvases}
                  show_new_canvas_for={@show_new_canvas_for}
                />
              </:actions>
            </.session_row>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
