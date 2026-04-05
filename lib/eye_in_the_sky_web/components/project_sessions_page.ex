defmodule EyeInTheSkyWeb.Components.ProjectSessionsPage do
  @moduledoc false
  use Phoenix.Component

  import EyeInTheSkyWeb.CoreComponents
  import EyeInTheSkyWeb.Components.ProjectSessionsFilters
  import EyeInTheSkyWeb.Components.ProjectSessionsTable

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
  attr :editing_session_id, :any, required: true
  attr :project, :any, required: true

  def page(assigns) do
    ~H"""
    <div class="bg-base-100 min-h-full px-4 sm:px-6 lg:px-8">
      <div class="max-w-4xl mx-auto">
        <%!-- Toolbar --%>
        <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between py-5">
          <span class="text-[11px] font-mono tabular-nums text-base-content/45 tracking-wider uppercase">
            <%= if @has_more do %>
              {min(@visible_count, length(@agents))} of {length(@agents)} sessions
            <% else %>
              {length(@agents)} sessions
            <% end %>
          </span>
          <button
            phx-click="toggle_new_session_drawer"
            class="btn btn-sm btn-primary gap-1.5 min-h-0 h-8 sm:h-7 text-xs w-full sm:w-auto"
          >
            <.icon name="hero-plus-mini" class="w-3.5 h-3.5" /> New Agent
          </button>
        </div>

        <.filter_bar
          search_query={@search_query}
          session_filter={@session_filter}
          sort_by={@sort_by}
        />

        <%= if @show_filter_sheet do %>
          <.filter_sheet session_filter={@session_filter} sort_by={@sort_by} />
        <% end %>

        <.selection_toolbar
          session_filter={@session_filter}
          agents={@agents}
          selected_ids={@selected_ids}
        />

        <.session_list
          agents={@agents}
          streams={@streams}
          depths={@depths}
          session_filter={@session_filter}
          selected_ids={@selected_ids}
          editing_session_id={@editing_session_id}
          search_query={@search_query}
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
      projects={nil}
      current_project={@project}
      toggle_event="toggle_new_session_drawer"
      submit_event="create_new_session"
    />
    """
  end
end
