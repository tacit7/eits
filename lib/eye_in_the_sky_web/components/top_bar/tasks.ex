defmodule EyeInTheSkyWeb.TopBar.Tasks do
  @moduledoc false
  use Phoenix.Component
  import EyeInTheSkyWeb.CoreComponents
  alias EyeInTheSkyWeb.TopBar.Helpers

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
    <%!-- Tasks: state filter pills + view toggle + sort + search --%>
    <%!-- Status filter pills --%>
    <div class="flex items-center gap-0.5 rounded-box bg-base-200/40 p-0.5">
      <button
        phx-click="filter_status"
        phx-value-state_id=""
        class={[
          "focus-ring flex items-center gap-1.5 rounded-box px-2.5 py-1 text-mini font-medium transition-all duration-150",
          if(is_nil(@filter_state_id),
            do: "bg-base-100 text-base-content shadow-sm",
            else: "text-base-content/45 hover:text-base-content/70"
          )
        ]}
      >
        All <% total = @state_counts |> Map.values() |> Enum.sum() %>
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
            "focus-ring flex items-center gap-1.5 rounded-box px-2.5 py-1 text-mini font-medium transition-all duration-150",
            if(active,
              do: "bg-base-100 text-base-content shadow-sm",
              else: "text-base-content/45 hover:text-base-content/70"
            )
          ]}
        >
          <%= if active do %>
            <span
              class="size-1.5 rounded-full flex-shrink-0"
              style={"background-color: #{state.color}"}
            >
            </span>
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
      <div class="flex items-center rounded-box bg-base-200/40 p-0.5">
        <span
          class="flex items-center gap-1 h-6 px-2 rounded-box text-mini font-medium bg-base-100 shadow-sm text-base-content cursor-default"
          title="List view"
        >
          <.icon name="hero-list-bullet-mini" class="size-3.5" /> List
        </span>
        <.link
          navigate={~p"/projects/#{@sidebar_project.id}/kanban"}
          class="focus-ring flex h-6 items-center gap-1 rounded-box px-2 text-mini font-medium text-base-content/45 transition-colors hover:text-base-content/70"
          title="Board view"
        >
          <.icon name="hero-view-columns-mini" class="size-3.5" /> Board
        </.link>
      </div>
    <% end %>
    <div class="flex-1" />
    <%!-- Sort relative --%>
    <details
      id="tasks-sort-relative"
      phx-update="ignore"
      phx-hook="SortDropdown"
      data-label={Helpers.sort_label(@sort_by, sort_options(), "Newest")}
      class="relative"
    >
      <summary class="focus-ring flex h-7 cursor-pointer select-none items-center gap-1 rounded-box border border-base-content/8 bg-base-100 px-2 text-mini font-medium text-base-content/60 hover:text-base-content [list-style:none] [&::-webkit-details-marker]:hidden">
        <span class="js-sort-label">{Helpers.sort_label(@sort_by, sort_options(), "Newest")}</span>
        <.icon name="hero-chevron-down-mini" class="size-3 opacity-50" />
      </summary>
      <ul class="eits-menu absolute z-50 mt-1 min-w-[120px] rounded-box border border-base-content/10 bg-base-100 p-1 shadow-lg">
        <%= for {value, label} <- sort_options() do %>
          <li>
            <button
              phx-click="sort_by"
              phx-value-by={value}
              onclick="var d=this.closest('details');d.querySelector('.js-sort-label').textContent=this.textContent.trim();d.removeAttribute('open')"
              class={"focus-ring block w-full rounded-box px-3 py-1.5 text-left text-mini hover:bg-base-content/5 " <>
                if(@sort_by == value, do: "text-base-content font-medium", else: "text-base-content/60")}
            >
              {label}
            </button>
          </li>
        <% end %>
      </ul>
    </details>
    <.search_bar
      id="top-bar-tasks-search"
      size="xs"
      label="Search tasks"
      placeholder="Search tasks..."
      value={@search_query || ""}
      on_change="search"
      class="w-48"
      vim_search={true}
    />
    """
  end

  defp sort_options do
    [
      {"created_desc", "Newest"},
      {"created_asc", "Oldest"},
      {"priority", "Priority"}
    ]
  end
end
