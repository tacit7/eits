defmodule EyeInTheSkyWebWeb.Components.DmPage.TasksTab do
  @moduledoc false

  use EyeInTheSkyWebWeb, :html

  import EyeInTheSkyWebWeb.Helpers.ViewHelpers, only: [relative_time: 1]

  alias EyeInTheSkyWeb.Tasks.WorkflowState

  attr :tasks, :list, default: []

  def tasks_tab(assigns) do
    ~H"""
    <div class="flex flex-col gap-2">
      <%= if @tasks == [] do %>
        <.empty_state
          id="dm-tasks-empty"
          icon="hero-clipboard-document-list"
          title="No tasks yet"
          subtitle="Tasks from this session will appear here"
        />
      <% else %>
        <div
          class="divide-y divide-base-content/5 bg-base-200 rounded-xl shadow-sm px-4"
          id="dm-task-list"
        >
          <%= for task <- @tasks do %>
            <% has_expandable = task.description || Map.get(task, :notes, []) != [] %>
            <div class="flex items-start" id={"dm-task-#{task.id}"}>
              <%!-- Edit button — outside collapse so checkbox overlay can't intercept --%>
              <button
                type="button"
                phx-click="open_task_detail"
                phx-value-task_id={task.uuid || to_string(task.id)}
                class="flex-shrink-0 min-w-[44px] min-h-[44px] flex items-center justify-center rounded-md text-base-content/25 hover:text-base-content/70 active:text-primary transition-all z-10 md:min-w-0 md:min-h-0 md:mt-3 md:p-1.5"
                title="Edit task"
              >
                <.icon name="hero-pencil-square" class="w-4 h-4 md:w-3.5 md:h-3.5" />
              </button>

              <%!-- Collapse (status dot + title + expandable content) --%>
              <div class={["collapse flex-1", has_expandable && "collapse-arrow"]}>
                <input type="checkbox" class="min-h-0 p-0" disabled={!has_expandable} />
                <div class="collapse-title py-3.5 px-0 min-h-0 flex items-center gap-3">
                  <%!-- Status dot --%>
                  <div class="flex-shrink-0 w-5 flex justify-center">
                    <%= if task.state_id == WorkflowState.in_progress_id() do %>
                      <span class="relative flex h-2 w-2">
                        <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-info opacity-50">
                        </span>
                        <span class="relative inline-flex rounded-full h-2 w-2 bg-info"></span>
                      </span>
                    <% else %>
                      <span class={[
                        "inline-flex rounded-full h-2 w-2",
                        task.state_id == WorkflowState.done_id() && "bg-success",
                        task.state_id == WorkflowState.in_review_id() && "bg-warning",
                        task.state_id not in [
                          WorkflowState.in_progress_id(),
                          WorkflowState.done_id(),
                          WorkflowState.in_review_id()
                        ] && "bg-base-content/20"
                      ]}>
                      </span>
                    <% end %>
                  </div>

                  <%!-- Content --%>
                  <div class="flex-1 min-w-0">
                    <span class={[
                      "text-[13px] font-medium truncate block",
                      task.completed_at && "text-base-content/40 line-through",
                      !task.completed_at && "text-base-content/85"
                    ]}>
                      {String.trim(task.title || "")}
                    </span>
                    <div class="flex items-center gap-1.5 mt-0.5 text-[11px]">
                      <%= if task.state do %>
                        <span class={[
                          "font-medium",
                          task.state_id == WorkflowState.in_progress_id() && "text-info/80",
                          task.state_id == WorkflowState.done_id() && "text-success/80",
                          task.state_id == WorkflowState.in_review_id() && "text-warning/80",
                          task.state_id not in [
                            WorkflowState.in_progress_id(),
                            WorkflowState.done_id(),
                            WorkflowState.in_review_id()
                          ] && "text-base-content/45"
                        ]}>
                          {task.state.name}
                        </span>
                      <% end %>
                      <%= if task.tags && length(task.tags) > 0 do %>
                        <span class="text-base-content/15">&middot;</span>
                        <span class="text-base-content/35">
                          {Enum.map_join(Enum.take(task.tags, 2), ", ", & &1.name)}
                        </span>
                      <% end %>
                      <span class="text-base-content/15">&middot;</span>
                      <span class="font-mono text-base-content/30">
                        {String.slice(task.uuid || to_string(task.id), 0..7)}
                      </span>
                      <span class="text-base-content/15">&middot;</span>
                      <span class="tabular-nums text-base-content/30">
                        {relative_time(task.created_at)}
                      </span>
                      <%= if Map.get(task, :notes_count, 0) > 0 do %>
                        <span class="text-base-content/15">&middot;</span>
                        <span class="flex items-center gap-0.5 text-base-content/35">
                          <.icon name="hero-chat-bubble-bottom-center-text" class="w-3 h-3" />
                          {Map.get(task, :notes_count)}
                        </span>
                      <% end %>
                    </div>
                  </div>
                </div>
                <%= if has_expandable do %>
                  <div class="collapse-content px-0 pt-0 pb-4 pl-8">
                    <%= if task.description do %>
                      <div class="text-sm text-base-content/65 leading-relaxed whitespace-pre-wrap mb-2">
                        {String.trim(task.description)}
                      </div>
                    <% end %>
                    <%= for note <- Map.get(task, :notes, []) do %>
                      <div class="mt-1.5 rounded-lg bg-base-200/60 px-3 py-2">
                        <%= if note.title do %>
                          <div class="text-[11px] font-semibold text-base-content/60 mb-0.5">
                            {note.title}
                          </div>
                        <% end %>
                        <pre class="whitespace-pre-wrap text-xs text-base-content/55 font-mono leading-relaxed">{note.body}</pre>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
      <button
        phx-click="toggle_new_task_drawer"
        class="flex items-center gap-2 w-full px-3 py-3 rounded-xl text-sm text-base-content/40 hover:text-base-content/70 hover:bg-base-content/5 active:bg-base-content/10 transition-colors border border-dashed border-base-content/15 hover:border-base-content/25"
      >
        <.icon name="hero-plus" class="w-4 h-4" /> Add task
      </button>
    </div>
    """
  end
end
