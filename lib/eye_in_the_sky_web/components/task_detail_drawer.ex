defmodule EyeInTheSkyWeb.Components.TaskDetailDrawer do
  @moduledoc """
  Right-side slide-over panel for viewing and editing task details.
  """

  use EyeInTheSkyWeb, :html

  import EyeInTheSkyWeb.Helpers.ViewHelpers,
    only: [relative_time: 1, overdue?: 1, due_today?: 1, format_date_input: 1]

  attr :id, :string, required: true
  attr :show, :boolean, required: true
  attr :task, :map, default: nil
  attr :notes, :list, default: []
  attr :workflow_states, :list, required: true
  attr :toggle_event, :any, required: true
  attr :close_event_name, :string, default: nil
  attr :close_event_key, :string, default: nil
  attr :update_event, :string, required: true
  attr :delete_event, :string, required: true
  attr :copy_event, :string, default: nil
  attr :projects, :list, default: []
  attr :current_project_id, :any, default: nil
  attr :focus, :string, default: nil

  slot :checklist

  def task_detail_drawer(assigns) do
    ~H"""
    <.side_drawer
      id={@id}
      show={@show}
      on_close={@toggle_event}
      phx-hook="DrawerSwipeClose"
      data-close-event={@close_event_name || to_string(@toggle_event)}
      data-close-key={@close_event_key}
    >
      <%= if @task do %>
        <%!-- Header --%>
        <div class="flex items-center justify-between px-6 py-4 border-b border-base-content/5 flex-shrink-0">
          <div class="flex items-center gap-2 text-xs text-base-content/30">
            <span class="font-mono">
              {String.slice(@task.uuid || to_string(@task.id), 0..7)}
            </span>
            <.priority_badge priority={@task.priority} />
            <button
              type="button"
              phx-hook="CopyToClipboard"
              id={"copy-task-detail-#{@task.id}"}
              data-copy={@task.uuid || to_string(@task.id)}
              onclick="event.stopPropagation(); event.preventDefault();"
              class="hover:text-primary transition-colors"
            >
              <.icon name="hero-clipboard-document" class="size-3" />
            </button>
            <span class="text-base-content/15">&middot;</span>
            <span>{relative_time(@task.created_at)}</span>
          </div>
          <button
            type="button"
            phx-click={@toggle_event}
            class="min-h-[44px] min-w-[44px] flex items-center justify-center rounded-md text-base-content/30 hover:text-base-content/60 hover:bg-base-content/5 transition-colors"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <%!-- Scrollable body --%>
        <div class="flex-1 overflow-y-auto px-6 py-5 space-y-5">
          <%!-- Main edit form (no nested forms) --%>
          <form id="task-edit-form" phx-submit={@update_event}>
            <%!-- Title --%>
            <input
              type="text"
              name="title"
              value={@task.title}
              class="text-lg font-semibold w-full bg-transparent border-none focus:outline-none focus:ring-0 p-0 text-base-content mb-5"
              placeholder="Task title"
              required
            />

            <%!-- Fields grid --%>
            <div class="grid grid-cols-2 gap-3 mb-5">
              <div>
                <.detail_label text="Status" />
                <select
                  name="state_id"
                  class="select select-sm w-full bg-base-200 border-base-300 text-sm focus:border-primary/30"
                >
                  <%= for state <- @workflow_states do %>
                    <option value={state.id} selected={@task.state_id == state.id}>
                      {state.name}
                    </option>
                  <% end %>
                </select>
              </div>
              <div>
                <.detail_label text="Priority" />
                <select
                  name="priority"
                  class="select select-sm w-full bg-base-200 border-base-300 text-sm focus:border-primary/30"
                >
                  <option value="0" selected={@task.priority == 0 || is_nil(@task.priority)}>
                    None
                  </option>
                  <option value="1" selected={@task.priority == 1}>Low</option>
                  <option value="2" selected={@task.priority == 2}>Medium</option>
                  <option value="3" selected={@task.priority == 3}>High</option>
                </select>
              </div>
              <div>
                <label class="text-mini font-medium text-base-content/40 uppercase tracking-wider mb-1.5 flex items-center gap-1.5">
                  <span>Due date</span>
                  <%= cond do %>
                    <% overdue?(@task.due_at) -> %>
                      <span class="text-error text-xs normal-case tracking-normal font-medium">
                        Overdue
                      </span>
                    <% due_today?(@task.due_at) -> %>
                      <span class="text-warning text-xs normal-case tracking-normal font-medium">
                        Today
                      </span>
                    <% true -> %>
                  <% end %>
                </label>
                <input
                  type="date"
                  id="task-detail-due-at"
                  name="due_at"
                  value={format_date_input(@task.due_at)}
                  phx-mounted={if @focus == "due_at", do: JS.focus()}
                  class="input input-sm w-full bg-base-200 border-base-300 text-base focus:border-primary/30 min-h-[44px]"
                />
              </div>
              <div>
                <.detail_label text="Tags" />
                <input
                  type="text"
                  id="task-detail-tags"
                  name="tags"
                  value={format_tags(@task.tags)}
                  placeholder="tag1, tag2"
                  phx-mounted={if @focus == "tags", do: JS.focus()}
                  class="input input-sm w-full bg-base-200 border-base-300 text-base placeholder:text-base-content/20 focus:border-primary/30 min-h-[44px]"
                />
              </div>
            </div>

            <%!-- Description --%>
            <div>
              <.detail_label text="Description" />
              <textarea
                name="description"
                class="w-full min-h-[100px] bg-base-200 border border-base-300 rounded-lg px-3 py-2 text-base focus:border-primary/30 focus:outline-none resize-y"
                placeholder="Add details..."
              >{@task.description}</textarea>
            </div>
          </form>

          <%!-- Checklist (rendered via slot — TaskChecklistComponent from parent LiveView) --%>
          {render_slot(@checklist)}

          <%!-- Annotations --%>
          <%= if not is_nil(@notes) && @notes != [] do %>
            <div>
              <div class="flex items-center gap-2 mb-2">
                <span class="text-mini font-medium text-base-content/40 uppercase tracking-wider">
                  Annotations
                </span>
                <span class="text-mini font-mono tabular-nums text-base-content/25">
                  {length(@notes)}
                </span>
              </div>
              <div class="space-y-2">
                <%= for note <- @notes do %>
                  <div class="rounded-lg bg-base-200 px-3 py-2.5">
                    <%= if note.title do %>
                      <div class="text-xs font-semibold text-base-content/70 mb-1">
                        {note.title}
                      </div>
                    <% end %>
                    <pre class="whitespace-pre-wrap text-xs text-base-content/60 font-mono leading-relaxed">{String.trim(note.body || "")}</pre>
                    <div class="mt-1.5 text-mini text-base-content/25">
                      {relative_time(note.created_at)}
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>

          <%!-- Metadata --%>
          <div class="flex items-center gap-3 text-mini text-base-content/25 pt-2">
            <%= if not is_nil(@task.updated_at) && @task.updated_at != @task.created_at do %>
              <span>Updated {relative_time(@task.updated_at)}</span>
              <span class="text-base-content/10">&middot;</span>
            <% end %>
            <%= if @task.agent_id do %>
              <span class="font-mono">
                <%= if is_list(@task.sessions) && @task.sessions != [] do %>
                  {(List.first(@task.sessions).description || "Agent") |> String.slice(0..30)}
                <% else %>
                  Agent #{@task.agent_id}
                <% end %>
              </span>
            <% end %>
          </div>

          <%!-- Add annotation --%>
          <div class="border-t border-base-content/5 pt-4">
            <span class="text-mini font-medium text-base-content/40 uppercase tracking-wider block mb-2">
              Add Annotation
            </span>
            <form phx-submit="add_task_annotation" class="flex flex-col gap-2">
              <input type="hidden" name="task_id" value={@task.uuid || to_string(@task.id)} />
              <textarea
                name="body"
                rows="3"
                placeholder="Add a note..."
                class="w-full bg-base-200 border border-base-300 rounded-lg px-3 py-2 text-base focus:border-primary/30 focus:outline-none resize-none"
                required
              ></textarea>
              <button
                type="submit"
                class="btn btn-sm btn-ghost text-xs self-end gap-1.5 text-base-content/50 hover:text-base-content/80"
              >
                <.icon name="hero-plus-mini" class="size-3.5" /> Add
              </button>
            </form>
          </div>
        </div>

        <%!-- Footer actions (outside all forms) --%>
        <div class="px-6 py-4 border-t border-base-content/5 flex items-center gap-2 flex-shrink-0">
          <button type="submit" form="task-edit-form" class="btn btn-sm btn-primary text-xs px-4">
            Save
          </button>
          <button
            type="button"
            phx-click="start_agent_for_task"
            phx-value-task_id={@task.uuid || to_string(@task.id)}
            class="btn btn-sm btn-ghost text-xs gap-1.5 text-base-content/50 hover:text-base-content/80"
          >
            <.icon name="hero-play" class="size-3.5" /> Start Agent
          </button>
          <div class="ml-auto flex items-center gap-1">
            <%= if not is_nil(@copy_event) && @projects != [] do %>
              <% other_projects = Enum.reject(@projects, &(&1.id == @current_project_id)) %>
              <%= if other_projects != [] do %>
                <div class="dropdown dropdown-top dropdown-end">
                  <button
                    type="button"
                    tabindex="0"
                    class="btn btn-sm btn-ghost text-xs text-base-content/40 hover:text-primary hover:bg-primary/10"
                    title="Copy to project"
                  >
                    <.icon name="hero-document-duplicate" class="size-3.5" />
                  </button>
                  <ul
                    tabindex="0"
                    class="dropdown-content menu p-1 shadow-lg bg-base-200 rounded-lg w-48 z-50"
                  >
                    <%= for project <- other_projects do %>
                      <li>
                        <button
                          type="button"
                          phx-click={@copy_event}
                          phx-value-project_id={project.id}
                          class="text-xs"
                        >
                          <.icon name="hero-folder" class="size-3.5" />
                          {project.name}
                        </button>
                      </li>
                    <% end %>
                  </ul>
                </div>
              <% end %>
            <% end %>
            <button
              type="button"
              phx-click="archive_task"
              phx-value-task_id={@task.uuid || to_string(@task.id)}
              class="btn btn-sm btn-ghost text-xs text-base-content/40 hover:text-warning hover:bg-warning/10"
              title="Archive task"
            >
              <.icon name="hero-archive-box" class="size-3.5" />
            </button>
            <button
              type="button"
              phx-click={@delete_event}
              phx-value-task_id={@task.uuid || to_string(@task.id)}
              phx-confirm="Delete this task?"
              data-drawer-delete="true"
              class="btn btn-sm btn-ghost text-xs text-error/50 hover:text-error hover:bg-error/10"
            >
              <.icon name="hero-trash" class="size-3.5" />
            </button>
          </div>
        </div>
      <% else %>
        <div class="flex items-center justify-center h-full">
          <span class="text-sm text-base-content/30">No task selected</span>
        </div>
      <% end %>
    </.side_drawer>
    """
  end

  defp format_tags(nil), do: ""
  defp format_tags([]), do: ""

  defp format_tags(tags) when is_list(tags) do
    Enum.map_join(tags, ", ", & &1.name)
  end
end
