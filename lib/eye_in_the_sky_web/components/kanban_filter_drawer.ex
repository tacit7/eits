defmodule EyeInTheSkyWeb.Components.KanbanFilterDrawer do
  @moduledoc """
  Filter drawer component for the kanban board.
  """
  use Phoenix.Component

  import EyeInTheSkyWeb.CoreComponents, only: [icon: 1, side_drawer: 1]

  attr :show, :boolean, required: true
  attr :search_query, :string, required: true
  attr :show_completed, :boolean, required: true
  attr :show_archived, :boolean, required: true
  attr :filter_due_date, :atom, default: nil
  attr :filter_priority, :integer, default: nil
  attr :filter_tags, :any, required: true
  attr :filter_tag_mode, :atom, default: :and
  attr :filter_activity, :atom, default: nil
  attr :available_tags, :list, default: []

  def kanban_filter_drawer(assigns) do
    active_filter_count =
      if(assigns.filter_priority, do: 1, else: 0) + MapSet.size(assigns.filter_tags) +
        if(assigns.filter_due_date, do: 1, else: 0) + if(assigns.filter_activity, do: 1, else: 0)

    assigns = assign(assigns, :active_filter_count, active_filter_count)

    ~H"""
    <.side_drawer
      id="kanban-filter-drawer"
      show={@show}
      on_close="toggle_filter_drawer"
      max_width="sm"
      surface={true}
      class="w-72 border-l border-base-content/8 overflow-hidden"
    >
      <%!-- Header --%>
      <div class="flex items-center justify-between px-4 py-3 border-b border-base-content/10">
        <h2 class="text-message font-semibold text-base-content/80">Filter</h2>
        <button
          phx-click="toggle_filter_drawer"
          class="focus-ring inline-flex min-h-[44px] min-w-[44px] items-center justify-center rounded-box text-base-content/45 transition-colors hover:bg-base-content/5 hover:text-base-content/70"
          aria-label="Close"
        >
          <.icon name="hero-x-mark-mini" class="size-4" />
        </button>
      </div>

      <%!-- Scrollable body --%>
      <div class="flex-1 overflow-y-auto px-4 py-4 space-y-5">
        <%!-- Keyword --%>
        <div>
          <h3 class="mb-2 text-mini font-semibold uppercase tracking-normal text-base-content/40">
            Keyword
          </h3>
          <form phx-change="search">
            <div class="relative">
              <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
                <.icon name="hero-magnifying-glass-mini" class="size-3.5 text-base-content/25" />
              </div>
              <input
                type="text"
                name="query"
                value={@search_query}
                placeholder="Enter a keyword..."
                phx-debounce="300"
                data-vim-search
                class="input input-sm focus-ring min-h-[44px] w-full border-base-content/10 bg-base-100 pl-8 text-message placeholder:text-base-content/25"
                autocomplete="off"
              />
            </div>
            <p class="text-mini text-base-content/30 mt-1">Search cards, labels, and more.</p>
          </form>
        </div>

        <%!-- Card Status --%>
        <div>
          <h3 class="mb-2 text-mini font-semibold uppercase tracking-normal text-base-content/40">
            Card status
          </h3>
          <div class="space-y-0.5">
            <label class="flex cursor-pointer items-center gap-3 py-1.5 transition-colors hover:text-base-content">
              <input
                type="checkbox"
                class="checkbox checkbox-primary checkbox-sm focus-ring"
                checked={@show_completed}
                phx-click="toggle_show_completed"
              />
              <span class="text-message text-base-content/70">Marked as complete</span>
            </label>
            <label class="flex cursor-pointer items-center gap-3 py-1.5 transition-colors hover:text-base-content">
              <input
                type="checkbox"
                class="checkbox checkbox-primary checkbox-sm focus-ring"
                checked={@show_archived}
                phx-click="toggle_show_archived"
              />
              <span class="text-message text-base-content/70">Archived</span>
            </label>
          </div>
        </div>

        <%!-- Due Date --%>
        <div>
          <h3 class="mb-2 text-mini font-semibold uppercase tracking-normal text-base-content/40">
            Due date
          </h3>
          <div class="space-y-0.5">
            <%= for {label, value, atom, icon, icon_class} <- [
                  {"No date", "no_date", :no_date, "hero-calendar", "text-base-content/35"},
                  {"Overdue", "overdue", :overdue, "hero-clock", "text-error/80"},
                  {"Due in the next day", "next_day", :next_day, "hero-clock", "text-warning/80"},
                  {"Due in the next week", "next_week", :next_week, "hero-clock", "text-base-content/45"},
                  {"Due in the next month", "next_month", :next_month, "hero-clock", "text-base-content/30"}
                ] do %>
              <label class="flex cursor-pointer items-center gap-3 py-1.5 transition-colors hover:text-base-content">
                <input
                  type="checkbox"
                  class="checkbox checkbox-primary checkbox-sm focus-ring"
                  checked={@filter_due_date == atom}
                  phx-click="update_filter"
                  phx-value-field="due_date"
                  phx-value-value={value}
                />
                <.icon name={icon} class={"size-3.5 flex-shrink-0 #{icon_class}"} />
                <span class="text-message text-base-content/70">{label}</span>
              </label>
            <% end %>
          </div>
        </div>

        <%!-- Priority --%>
        <div>
          <h3 class="mb-2 text-mini font-semibold uppercase tracking-normal text-base-content/40">
            Priority
          </h3>
          <div class="space-y-1.5">
            <%= for {label, value, color} <- [{"High", 3, "hsl(var(--er))"}, {"Med", 2, "hsl(var(--wa))"}, {"Low", 1, "hsl(var(--in))"}] do %>
              <label class="group flex cursor-pointer items-center gap-3 py-0.5">
                <input
                  type="checkbox"
                  class="checkbox checkbox-primary checkbox-sm focus-ring flex-shrink-0"
                  checked={@filter_priority == value}
                  phx-click="update_filter"
                  phx-value-field="priority"
                  phx-value-value={value}
                />
                <div
                  class="h-5 flex-1 rounded-box border border-base-content/8"
                  style={"background-color: #{color}"}
                />
                <span class="text-mini text-base-content/45 w-7 text-right shrink-0">
                  {label}
                </span>
              </label>
            <% end %>
          </div>
        </div>

        <%!-- Labels / Tags --%>
        <%= if @available_tags != [] do %>
          <div>
            <h3 class="mb-2 text-mini font-semibold uppercase tracking-normal text-base-content/40">
              Labels
            </h3>
            <div class="space-y-1.5">
              <%= for tag <- @available_tags do %>
                <label class="group flex cursor-pointer items-center gap-3 py-0.5">
                  <input
                    type="checkbox"
                    class="checkbox checkbox-primary checkbox-sm focus-ring flex-shrink-0"
                    checked={MapSet.member?(@filter_tags, tag.name)}
                    phx-click="update_filter"
                    phx-value-field="tag"
                    phx-value-value={tag.name}
                  />
                  <div
                    class="h-5 w-8 flex-shrink-0 rounded-box border border-base-content/8"
                    style={"background-color: #{tag.color || "hsl(var(--bc) / 0.3)"}"}
                  />
                  <span class="min-w-0 flex-1 truncate text-message font-medium text-base-content/70">
                    {tag.name}
                  </span>
                  <button
                    type="button"
                    phx-click="cycle_tag_color"
                    phx-value-tag-id={tag.id}
                    class="focus-ring flex size-7 flex-shrink-0 items-center justify-center rounded-box text-base-content/45 opacity-0 transition-[background-color,color,opacity] hover:!opacity-100 hover:bg-base-content/6 hover:text-base-content/70 group-hover:opacity-60"
                    onclick="event.stopPropagation();"
                    title="Change color"
                    aria-label={"Change color for #{tag.name}"}
                  >
                    <.icon name="hero-swatch-mini" class="size-3.5" />
                  </button>
                </label>
              <% end %>
            </div>
          </div>
        <% end %>

        <%!-- Activity --%>
        <div>
          <h3 class="mb-2 text-mini font-semibold uppercase tracking-normal text-base-content/40">
            Activity
          </h3>
          <div class="space-y-0.5">
            <%= for {label, value, atom} <- [
                  {"Active in the last week", "week", :week},
                  {"Active in the last two weeks", "two_weeks", :two_weeks},
                  {"Active in the last four weeks", "four_weeks", :four_weeks},
                  {"Without activity in the last four weeks", "inactive", :inactive}
                ] do %>
              <label class="flex cursor-pointer items-center gap-3 py-1.5 transition-colors hover:text-base-content">
                <input
                  type="checkbox"
                  class="checkbox checkbox-primary checkbox-sm focus-ring flex-shrink-0"
                  checked={@filter_activity == atom}
                  phx-click="update_filter"
                  phx-value-field="activity"
                  phx-value-value={value}
                />
                <span class="text-message text-base-content/70">{label}</span>
              </label>
            <% end %>
          </div>
        </div>
      </div>

      <%!-- Footer --%>
      <div class="border-t border-base-content/10 px-4 py-3 space-y-2">
        <%= if MapSet.size(@filter_tags) >= 2 do %>
          <form phx-change="update_filter" class="flex items-center gap-2">
            <input type="hidden" name="field" value="tag_mode" />
            <label class="flex-shrink-0 text-mini text-base-content/40">Tag match</label>
            <select
              name="value"
              class="select select-xs focus-ring flex-1 border-base-content/10 bg-base-100 text-message"
            >
              <option value="or" selected={@filter_tag_mode == :or}>Any match</option>
              <option value="and" selected={@filter_tag_mode == :and}>All match</option>
            </select>
          </form>
        <% end %>
        <%= if @active_filter_count > 0 do %>
          <button
            phx-click="clear_filters"
            class="focus-ring inline-flex min-h-[44px] w-full items-center justify-center rounded-box px-3 text-mini font-medium text-base-content/45 transition-colors hover:bg-base-content/5 hover:text-base-content/80"
          >
            Clear all filters
          </button>
        <% end %>
      </div>
    </.side_drawer>
    """
  end
end
