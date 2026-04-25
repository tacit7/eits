defmodule EyeInTheSkyWeb.Components.ProjectSessionsPage do
  @moduledoc false
  use Phoenix.Component

  import EyeInTheSkyWeb.CoreComponents
  import EyeInTheSkyWeb.Components.ProjectSessionsFilters
  import EyeInTheSkyWeb.Components.ProjectSessionsTable
  import EyeInTheSkyWeb.Components.AgentList, only: [archive_confirm_modal: 1]

  @doc "Full sessions page layout. Pass `{assigns}` from the LiveView render."
  attr :has_more, :boolean, required: true
  attr :visible_count, :integer, required: true
  attr :agents, :list, required: true
  attr :streams, :any, required: true
  attr :depths, :map, required: true
  attr :session_filter, :string, required: true
  attr :sort_by, :string, required: true
  attr :search_query, :string, required: true
  attr :show_filter_sheet, :boolean, required: true
  attr :show_new_session_drawer, :boolean, required: true
  attr :selected_ids, :any, required: true
  attr :select_mode, :boolean, default: false
  attr :off_screen_selected_count, :integer, default: 0
  attr :indeterminate_ids, :any, default: MapSet.new()
  attr :show_archive_confirm, :boolean, default: false
  attr :editing_session_id, :any, required: true
  attr :project, :any, required: true
  attr :canvases, :list, default: []
  attr :show_new_canvas_for, :any, default: nil
  attr :scope, :any, default: nil
  attr :projects, :list, default: nil

  def page(assigns) do
    ~H"""
    <div class="bg-base-100 min-h-full px-4 sm:px-6 lg:px-8">
      <div class="max-w-4xl mx-auto">
        <%!-- Toolbar --%>
        <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between py-5">
          <%!-- Mobile action bar (desktop uses top bar) --%>
          <div class="flex md:hidden items-center gap-2">
            <button
              :if={!@select_mode && @agents != []}
              phx-click="enter_select_mode"
              class="btn btn-ghost btn-sm gap-1 h-11 text-xs text-base-content/40 hover:text-base-content/70"
            >
              <.icon name="hero-check-circle-mini" class="w-3.5 h-3.5" /> Select
            </button>
            <button
              phx-click="open_filter_sheet"
              aria-label="Open filters"
              aria-haspopup="dialog"
              class="relative btn btn-ghost btn-sm btn-square h-11 w-11"
            >
              <.icon name="hero-funnel-mini" class="w-4 h-4" />
              <%= if @session_filter != "all" || @sort_by != "last_message" do %>
                <span class="absolute top-0.5 right-0.5 w-2 h-2 bg-primary rounded-full" aria-hidden="true">
                </span>
              <% end %>
            </button>
            <button
              phx-click="toggle_new_session_drawer"
              class="btn btn-sm btn-primary gap-1.5 min-h-0 h-11 text-xs"
            >
              <.icon name="hero-plus-mini" class="w-3.5 h-3.5" /> New Agent
            </button>
          </div>
        </div>

        <%= if @show_filter_sheet do %>
          <.filter_sheet session_filter={@session_filter} sort_by={@sort_by} />
        <% end %>

        <.selection_toolbar
          select_mode={@select_mode}
          agents={@agents}
          selected_ids={@selected_ids}
          off_screen_selected_count={@off_screen_selected_count}
        />

        <.session_list
          agents={@agents}
          streams={@streams}
          depths={@depths}
          session_filter={@session_filter}
          select_mode={@select_mode}
          selected_ids={@selected_ids}
          indeterminate_ids={@indeterminate_ids}
          editing_session_id={@editing_session_id}
          search_query={@search_query}
          canvases={@canvases}
          show_new_canvas_for={@show_new_canvas_for}
          scope={@scope}
        />

        <div
          id="project-sessions-sentinel"
          phx-hook="InfiniteScroll"
          data-has-more={to_string(@has_more)}
          data-page={@visible_count}
          class="py-4 flex justify-center"
        >
          <%= if @has_more do %>
            <span class="loading loading-spinner loading-sm text-base-content/30"></span>
          <% end %>
        </div>
      </div>
    </div>

    <.live_component
      module={EyeInTheSkyWeb.Components.NewSessionModal}
      id="new-session-modal-project"
      show={@show_new_session_drawer}
      projects={if @scope == :all, do: @projects, else: nil}
      current_project={if @scope == :all, do: nil, else: @project}
      toggle_event="toggle_new_session_drawer"
      submit_event="create_new_session"
    />
    <.archive_confirm_modal
      show_archive_confirm={@show_archive_confirm}
      selected_ids={@selected_ids}
    />
    """
  end
end
