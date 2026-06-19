defmodule EyeInTheSkyWeb.TopBar.Tasks do
  @moduledoc false
  use Phoenix.Component
  import EyeInTheSkyWeb.CoreComponents

  use Phoenix.VerifiedRoutes,
    endpoint: EyeInTheSkyWeb.Endpoint,
    router: EyeInTheSkyWeb.Router,
    statics: EyeInTheSkyWeb.static_paths()

  attr :search_query, :string, default: nil
  attr :filter_state_id, :any, default: nil
  attr :workflow_states, :list, default: []
  attr :state_counts, :map, default: %{}
  attr :sort_by, :string, default: "created_desc"
  attr :sidebar_project, :any, default: nil

  def toolbar(assigns) do
    ~H"""
    <%!-- Tasks: search + state filter pills + view toggle + sort --%>
    <.search_bar
      id="top-bar-tasks-search"
      size="xs"
      label="Search tasks"
      placeholder="Search tasks..."
      value={@search_query || ""}
      on_change="search"
      class="flex-1 max-w-xs"
      vim_search={true}
    />
    <%!-- Status filter pills --%>
    <div class="flex items-center gap-0.5 bg-base-200/40 rounded-lg p-0.5">
      <button
        phx-click="filter_status"
        phx-value-state_id=""
        class={[
          "flex items-center gap-1.5 px-2.5 py-1 rounded-md text-mini font-medium transition-all duration-150",
          if(is_nil(@filter_state_id),
            do: "bg-base-100 text-base-content shadow-sm",
            else: "text-base-content/45 hover:text-base-content/70"
          )
        ]}
      >
        All
        <% total = @state_counts |> Map.values() |> Enum.sum() %>
        <%= if total > 0 do %>
          <span class={[
            "tabular-nums text-micro px-1 min-w-[16px] text-center rounded-full leading-4",
            if(is_nil(@filter_state_id),
              do: "bg-base-content/10 text-base-content/60",
              else: "bg-base-content/8 text-base-content/35"
            )
          ]}>
            {total}
          </span>
        <% end %>
      </button>
      <%= for state <- @workflow_states do %>
        <% active = @filter_state_id == state.id %>
        <% count = Map.get(@state_counts, state.id, 0) %>
        <button
          phx-click="filter_status"
          phx-value-state_id={state.id}
          class={[
            "flex items-center gap-1.5 px-2.5 py-1 rounded-md text-mini font-medium transition-all duration-150",
            if(active,
              do: "bg-base-100 text-base-content shadow-sm",
              else: "text-base-content/45 hover:text-base-content/70"
            )
          ]}
        >
          <%= if active do %>
            <span class="size-1.5 rounded-full flex-shrink-0" style={"background-color: #{state.color}"}></span>
          <% end %>
          {state.name}
          <%= if count > 0 do %>
            <span class={[
              "tabular-nums text-micro px-1 min-w-[16px] text-center rounded-full leading-4",
              if(active,
                do: "bg-base-content/10 text-base-content/60",
                else: "bg-base-content/8 text-base-content/35"
              )
            ]}>
              {count}
            </span>
          <% end %>
        </button>
      <% end %>
    </div>
    <%!-- View toggle --%>
    <%= if @sidebar_project do %>
      <div class="flex items-center bg-base-200/40 rounded-lg p-0.5">
        <span
          class="flex items-center gap-1 h-6 px-2 rounded-md text-mini font-medium bg-base-100 shadow-sm text-base-content cursor-default"
          title="List view"
        >
          <.icon name="hero-list-bullet-mini" class="size-3.5" /> List
        </span>
        <.link
          navigate={~p"/projects/#{@sidebar_project.id}/kanban"}
          class="flex items-center gap-1 h-6 px-2 rounded-md text-mini font-medium text-base-content/45 hover:text-base-content/70 transition-colors"
          title="Board view"
        >
          <.icon name="hero-view-columns-mini" class="size-3.5" /> Board
        </.link>
      </div>
    <% end %>
    <%!-- Sort dropdown --%>
    <details
      id="tasks-sort-dropdown"
      phx-update="ignore"
      phx-hook="SortDropdown"
      data-label={
        case @sort_by do
          "created_asc" -> "Oldest"
          "priority" -> "Priority"
          _ -> "Newest"
        end
      }
      class="dropdown"
    >
      <summary class="flex items-center gap-1 h-7 px-2 rounded-md text-mini font-medium border border-base-content/8 bg-base-100 text-base-content/60 hover:text-base-content cursor-pointer select-none [list-style:none] [&::-webkit-details-marker]:hidden">
        Sort:
        <span class="js-sort-label">
          {case @sort_by do
            "created_asc" -> "Oldest"
            "priority" -> "Priority"
            _ -> "Newest"
          end}
        </span>
        <.icon name="hero-chevron-down-mini" class="size-3 opacity-50" />
      </summary>
      <ul class="dropdown-content z-50 mt-1 bg-base-100 border border-base-content/10 rounded-lg shadow-lg p-1 min-w-[120px]">
        <%= for {value, label} <- [{"created_desc", "Newest"}, {"created_asc", "Oldest"}, {"priority", "Priority"}] do %>
          <li>
            <button
              phx-click="sort_by"
              phx-value-by={value}
              onclick="var d=this.closest('details');d.querySelector('.js-sort-label').textContent=this.textContent.trim();d.removeAttribute('open')"
              class={"block w-full px-3 py-1.5 text-left text-mini rounded hover:bg-base-content/5 " <>
                if(@sort_by == value, do: "text-base-content font-medium", else: "text-base-content/60")}
            >
              {label}
            </button>
          </li>
        <% end %>
      </ul>
    </details>
    """
  end
end
