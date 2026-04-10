defmodule EyeInTheSkyWeb.Components.KanbanBoard do
  @moduledoc false
  use Phoenix.Component
  import EyeInTheSkyWeb.CoreComponents
  import EyeInTheSkyWeb.Components.TaskCard, only: [task_card: 1]
  import EyeInTheSkyWeb.Live.Shared.KanbanFilters, only: [state_dot_color: 1]

  attr :workflow_states, :list, required: true
  attr :tasks_by_state, :map, required: true
  attr :bulk_mode, :boolean, required: true
  attr :selected_tasks, :any, required: true
  attr :quick_add_column, :any, required: true
  attr :working_session_ids, :any, required: true
  attr :waiting_session_ids, :any, default: nil

  def kanban_board(assigns) do
    ~H"""
    <div
      class="flex-1 min-h-0 overflow-x-auto"
      id="kanban-scroll"
      phx-hook="KanbanScrollDots"
      data-column-count={length(@workflow_states)}
    >
      <div
        id="kanban-columns"
        phx-hook="SortableColumns"
        class="inline-flex gap-3 h-full min-w-full pb-2 snap-x snap-mandatory"
      >
        <%= for state <- @workflow_states do %>
          <% column_tasks = Map.get(@tasks_by_state, state.id, []) %>
          <% task_count = length(column_tasks) %>
          <div
            class="flex-shrink-0 w-[84vw] max-w-80 md:w-72 flex flex-col h-full snap-start"
            data-column-id={state.id}
          >
            <%!-- Column header --%>
            <div class="mb-2">
              <div
                class="h-0.5 rounded-full mx-1 mb-2"
                style={"background-color: #{state_dot_color(state.color)}"}
              />
              <div class="flex items-center gap-2 px-3 py-1">
                <%= if @bulk_mode do %>
                  <input
                    type="checkbox"
                    class="checkbox checkbox-sm sm:checkbox-xs checkbox-primary"
                    checked={
                      column_tasks != [] and
                        Enum.all?(column_tasks, &MapSet.member?(@selected_tasks, &1.uuid))
                    }
                    phx-click="select_all_column"
                    phx-value-state-id={state.id}
                  />
                <% end %>
                <div class="flex items-center gap-1.5 cursor-grab active:cursor-grabbing" data-column-handle>
                  <.icon
                    name="hero-bars-2"
                    class="w-3 h-3 text-base-content/20 hover:text-base-content/40"
                  />
                  <div
                    class="w-2 h-2 rounded-full flex-shrink-0"
                    style={"background-color: #{state_dot_color(state.color)}"}
                  />
                </div>
                <span class="text-xs font-semibold text-base-content/70 uppercase tracking-wider">
                  {state.name}
                </span>
                <span class="ml-auto inline-flex items-center justify-center min-w-[20px] h-5 px-1.5 rounded-full text-[11px] font-medium tabular-nums bg-base-content/[0.06] text-base-content/40">
                  {task_count}
                </span>
                <%= if state.name == "Done" and task_count > 0 do %>
                  <button
                    type="button"
                    phx-click="archive_column"
                    phx-value-state-id={state.id}
                    phx-confirm={"Archive all #{task_count} done tasks?"}
                    class="p-1 rounded text-base-content/20 hover:text-warning hover:bg-warning/10 transition-colors"
                    title="Archive all done tasks"
                  >
                    <.icon name="hero-archive-box-mini" class="w-3.5 h-3.5" />
                  </button>
                <% end %>
              </div>
            </div>

            <%!-- Column body --%>
            <div
              class="flex-1 min-h-0 overflow-y-auto rounded-xl bg-base-content/[0.04] p-2 space-y-1.5"
              id={"kanban-col-#{state.id}"}
              phx-hook="SortableKanban"
              data-state-id={state.id}
            >
              <%= if column_tasks == [] do %>
                <div
                  data-empty-placeholder
                  class="flex flex-col items-center justify-center h-24 border border-dashed border-base-content/8 rounded-lg pointer-events-none"
                >
                  <.icon name="hero-inbox" class="w-5 h-5 text-base-content/15 mb-1" />
                  <span class="text-[11px] text-base-content/20">No tasks</span>
                </div>
              <% end %>
              <%= for task <- column_tasks do %>
                <div class="flex items-start gap-1.5" data-task-id={task.uuid}>
                  <%= if @bulk_mode do %>
                    <input
                      type="checkbox"
                      class="checkbox checkbox-sm sm:checkbox-xs checkbox-primary mt-3 flex-shrink-0"
                      checked={MapSet.member?(@selected_tasks, task.uuid)}
                      phx-click="toggle_select_task"
                      phx-value-task-uuid={task.uuid}
                    />
                  <% end %>
                  <div class="flex-1 min-w-0">
                    <.task_card
                      variant="kanban"
                      task={task}
                      on_click="open_task_detail"
                      on_delete="delete_task"
                      id={"kanban-task-#{task.id}"}
                      working_session_ids={@working_session_ids}
                      waiting_session_ids={@waiting_session_ids}
                      workflow_states={@workflow_states}
                    />
                  </div>
                </div>
              <% end %>

              <%!-- Quick-add --%>
              <%= if @quick_add_column == state.id do %>
                <form phx-submit="quick_add_task" class="mt-1">
                  <input type="hidden" name="state_id" value={state.id} />
                  <input
                    type="text"
                    name="title"
                    placeholder="Task title... (Esc to cancel)"
                    autofocus
                    phx-keydown="hide_quick_add"
                    phx-key="Escape"
                    class="input input-md sm:input-sm w-full bg-base-100 border-base-content/10 text-base placeholder:text-base-content/25 focus:border-primary/30"
                  />
                </form>
              <% else %>
                <button
                  phx-click="show_quick_add"
                  phx-value-state_id={state.id}
                  class="mt-1 w-full flex items-center gap-1.5 px-2 py-2.5 sm:py-1.5 rounded-lg text-xs sm:text-[11px] text-base-content/25 hover:text-base-content/50 hover:bg-base-content/[0.04] transition-colors"
                >
                  <.icon name="hero-plus-mini" class="w-4 h-4 sm:w-3.5 sm:h-3.5" />
                  <span>Add task</span>
                </button>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
      <%!-- Column indicator dots (mobile only) --%>
      <div id="kanban-dots" class="flex justify-center gap-1.5 py-2 md:hidden">
        <%= for {state, idx} <- Enum.with_index(@workflow_states) do %>
          <span
            class="w-2 h-2 rounded-full transition-colors duration-200"
            style={"background-color: #{state_dot_color(state.color)}"}
            data-dot-index={idx}
            id={"kanban-dot-#{idx}"}
          />
        <% end %>
      </div>
    </div>
    """
  end
end
