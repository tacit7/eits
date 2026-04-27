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
            <h2 class="text-sm font-semibold text-base-content/80">Filter</h2>
            <button
              phx-click="toggle_filter_drawer"
              class="btn btn-ghost btn-sm btn-circle min-h-[44px] min-w-[44px]"
              aria-label="Close"
            >
              <.icon name="hero-x-mark-mini" class="size-4" />
            </button>
          </div>

          <%!-- Scrollable body --%>
          <div class="flex-1 overflow-y-auto px-4 py-4 space-y-5">
            <%!-- Keyword --%>
            <div>
              <h3 class="text-mini font-semibold text-base-content/40 uppercase tracking-wider mb-2">
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
                    class="input input-sm w-full pl-8 bg-base-100 border-base-content/10 placeholder:text-base-content/25 text-base min-h-[44px]"
                    autocomplete="off"
                  />
                </div>
                <p class="text-mini text-base-content/30 mt-1">Search cards, labels, and more.</p>
              </form>
            </div>

            <%!-- Card Status --%>
            <div>
              <h3 class="text-mini font-semibold text-base-content/40 uppercase tracking-wider mb-2">
                Card status
              </h3>
              <div class="space-y-0.5">
                <label class="flex items-center gap-3 cursor-pointer py-1.5 hover:text-base-content transition-colors">
                  <input
                    type="checkbox"
                    class="checkbox checkbox-sm checkbox-primary"
                    checked={@show_completed}
                    phx-click="toggle_show_completed"
                  />
                  <span class="text-sm text-base-content/70">Marked as complete</span>
                </label>
                <label class="flex items-center gap-3 cursor-pointer py-1.5 hover:text-base-content transition-colors">
                  <input
                    type="checkbox"
                    class="checkbox checkbox-sm checkbox-primary"
                    checked={@show_archived}
                    phx-click="toggle_show_archived"
                  />
                  <span class="text-sm text-base-content/70">Archived</span>
                </label>
              </div>
            </div>

            <%!-- Due Date --%>
            <div>
              <h3 class="text-mini font-semibold text-base-content/40 uppercase tracking-wider mb-2">
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
                  <label class="flex items-center gap-3 cursor-pointer py-1.5 hover:text-base-content transition-colors">
                    <input
                      type="checkbox"
                      class="checkbox checkbox-sm checkbox-primary"
                      checked={@filter_due_date == atom}
                      phx-click="update_filter"
                      phx-value-field="due_date"
                      phx-value-value={value}
                    />
                    <.icon name={icon} class={"size-3.5 flex-shrink-0 #{icon_class}"} />
                    <span class="text-sm text-base-content/70">{label}</span>
                  </label>
                <% end %>
              </div>
            </div>

            <%!-- Priority --%>
            <div>
              <h3 class="text-mini font-semibold text-base-content/40 uppercase tracking-wider mb-2">
                Priority
              </h3>
              <div class="space-y-1.5">
                <%= for {label, value, color} <- [{"High", 3, "hsl(var(--er))"}, {"Med", 2, "hsl(var(--wa))"}, {"Low", 1, "hsl(var(--in))"}] do %>
                  <label class="flex items-center gap-3 cursor-pointer py-0.5 group">
                    <input
                      type="checkbox"
                      class="checkbox checkbox-sm checkbox-primary flex-shrink-0"
                      checked={@filter_priority == value}
                      phx-click="update_filter"
                      phx-value-field="priority"
                      phx-value-value={value}
                    />
                    <div class="flex-1 h-5 rounded" style={"background-color: #{color}"} />
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
                <h3 class="text-mini font-semibold text-base-content/40 uppercase tracking-wider mb-2">
                  Labels
                </h3>
                <div class="space-y-1.5">
                  <%= for tag <- @available_tags do %>
                    <label class="flex items-center gap-3 cursor-pointer py-0.5 group">
                      <input
                        type="checkbox"
                        class="checkbox checkbox-sm checkbox-primary flex-shrink-0"
                        checked={MapSet.member?(@filter_tags, tag.name)}
                        phx-click="update_filter"
                        phx-value-field="tag"
                        phx-value-value={tag.name}
                      />
                      <div
                        class="flex-1 h-5 rounded flex items-center px-2"
                        style={"background-color: #{tag.color || "hsl(var(--bc) / 0.3)"}"}
                      >
                        <span class="text-mini font-medium text-white/90 truncate">{tag.name}</span>
                      </div>
                      <button
                        type="button"
                        phx-click="cycle_tag_color"
                        phx-value-tag-id={tag.id}
                        class="opacity-0 group-hover:opacity-60 hover:!opacity-100 transition-opacity flex-shrink-0"
                        onclick="event.stopPropagation();"
                        title="Change color"
                      >
                        <.icon name="hero-swatch-mini" class="size-3.5 text-base-content/50" />
                      </button>
                    </label>
                  <% end %>
                </div>
              </div>
            <% end %>

            <%!-- Activity --%>
            <div>
              <h3 class="text-mini font-semibold text-base-content/40 uppercase tracking-wider mb-2">
                Activity
              </h3>
              <div class="space-y-0.5">
                <%= for {label, value, atom} <- [
                  {"Active in the last week", "week", :week},
                  {"Active in the last two weeks", "two_weeks", :two_weeks},
                  {"Active in the last four weeks", "four_weeks", :four_weeks},
                  {"Without activity in the last four weeks", "inactive", :inactive}
                ] do %>
                  <label class="flex items-center gap-3 cursor-pointer py-1.5 hover:text-base-content transition-colors">
                    <input
                      type="checkbox"
                      class="checkbox checkbox-sm checkbox-primary flex-shrink-0"
                      checked={@filter_activity == atom}
                      phx-click="update_filter"
                      phx-value-field="activity"
                      phx-value-value={value}
                    />
                    <span class="text-sm text-base-content/70">{label}</span>
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
                <label class="text-xs text-base-content/40 flex-shrink-0">Tag match</label>
                <select
                  name="value"
                  class="select select-xs flex-1 bg-base-100 border-base-content/10 text-sm"
                >
                  <option value="or" selected={@filter_tag_mode == :or}>Any match</option>
                  <option value="and" selected={@filter_tag_mode == :and}>All match</option>
                </select>
              </form>
            <% end %>
            <%= if @active_filter_count > 0 do %>
              <button
                phx-click="clear_filters"
                class="btn btn-ghost btn-sm w-full text-base-content/40 hover:text-base-content/80"
              >
                Clear all filters
              </button>
            <% end %>
          </div>
    </.side_drawer>
    """
  end
end
