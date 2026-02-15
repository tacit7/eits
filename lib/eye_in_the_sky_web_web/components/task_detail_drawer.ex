defmodule EyeInTheSkyWebWeb.Components.TaskDetailDrawer do
  @moduledoc """
  Right-side slide-over panel for viewing and editing task details.
  """

  use Phoenix.LiveComponent
  import EyeInTheSkyWebWeb.CoreComponents

  @impl true
  def render(assigns) do
    ~H"""
    <div id="task-detail-wrapper">
    <%= if @show do %>
      <%!-- Backdrop --%>
      <div
        class="fixed inset-0 z-40 bg-black/30 transition-opacity"
        phx-click={@toggle_event}
      />

      <%!-- Panel --%>
      <div class="fixed inset-y-0 right-0 z-50 w-full max-w-lg bg-base-100 shadow-xl overflow-y-auto">
        <%= if @task do %>
          <form phx-submit={@update_event} class="flex flex-col h-full">
            <%!-- Header --%>
            <div class="flex items-center justify-between px-6 py-4 border-b border-base-content/5">
              <div class="flex items-center gap-2 text-xs text-base-content/30">
                <span class="font-mono">{String.slice(@task.uuid || to_string(@task.id), 0..7)}</span>
                <button
                  type="button"
                  phx-hook="CopyToClipboard"
                  id={"copy-task-detail-#{@task.id}"}
                  data-copy={@task.uuid || to_string(@task.id)}
                  onclick="event.stopPropagation(); event.preventDefault();"
                  class="hover:text-primary transition-colors"
                >
                  <.icon name="hero-clipboard-document" class="w-3 h-3" />
                </button>
                <span class="text-base-content/15">&middot;</span>
                <span>{format_relative_time(@task.created_at)}</span>
              </div>
              <button
                type="button"
                phx-click={@toggle_event}
                class="p-1 rounded-md text-base-content/30 hover:text-base-content/60 hover:bg-base-content/5 transition-colors"
              >
                <.icon name="hero-x-mark" class="w-5 h-5" />
              </button>
            </div>

            <%!-- Body --%>
            <div class="flex-1 px-6 py-5 space-y-5 overflow-y-auto">
              <%!-- Title --%>
              <input
                type="text"
                name="title"
                value={@task.title}
                class="text-lg font-semibold w-full bg-transparent border-none focus:outline-none focus:ring-0 p-0 text-base-content"
                placeholder="Task title"
                required
              />

              <%!-- Fields grid --%>
              <div class="grid grid-cols-2 gap-3">
                <%!-- Status --%>
                <div>
                  <label class="text-[11px] font-medium text-base-content/40 uppercase tracking-wider mb-1.5 block">
                    Status
                  </label>
                  <select
                    name="state_id"
                    class="select select-sm w-full bg-base-content/[0.03] border-base-content/8 text-sm focus:border-primary/30"
                  >
                    <%= for state <- @workflow_states do %>
                      <option value={state.id} selected={@task.state_id == state.id}>
                        {state.name}
                      </option>
                    <% end %>
                  </select>
                </div>

                <%!-- Priority --%>
                <div>
                  <label class="text-[11px] font-medium text-base-content/40 uppercase tracking-wider mb-1.5 block">
                    Priority
                  </label>
                  <select
                    name="priority"
                    class="select select-sm w-full bg-base-content/[0.03] border-base-content/8 text-sm focus:border-primary/30"
                  >
                    <option value="0" selected={@task.priority == 0 || is_nil(@task.priority)}>None</option>
                    <option value="1" selected={@task.priority == 1}>Low</option>
                    <option value="2" selected={@task.priority == 2}>Medium</option>
                    <option value="3" selected={@task.priority == 3}>High</option>
                  </select>
                </div>

                <%!-- Due date --%>
                <div>
                  <label class="text-[11px] font-medium text-base-content/40 uppercase tracking-wider mb-1.5 block">
                    Due date
                  </label>
                  <input
                    type="date"
                    name="due_at"
                    value={format_date_input(@task.due_at)}
                    class="input input-sm w-full bg-base-content/[0.03] border-base-content/8 text-sm focus:border-primary/30"
                  />
                </div>

                <%!-- Tags --%>
                <div>
                  <label class="text-[11px] font-medium text-base-content/40 uppercase tracking-wider mb-1.5 block">
                    Tags
                  </label>
                  <input
                    type="text"
                    name="tags"
                    value={format_tags(@task.tags)}
                    placeholder="tag1, tag2"
                    class="input input-sm w-full bg-base-content/[0.03] border-base-content/8 text-sm placeholder:text-base-content/20 focus:border-primary/30"
                  />
                </div>
              </div>

              <%!-- Description --%>
              <div>
                <label class="text-[11px] font-medium text-base-content/40 uppercase tracking-wider mb-1.5 block">
                  Description
                </label>
                <textarea
                  name="description"
                  class="w-full min-h-[100px] bg-base-content/[0.03] border border-base-content/8 rounded-lg px-3 py-2 text-sm focus:border-primary/30 focus:outline-none resize-y"
                  placeholder="Add details..."
                >{@task.description}</textarea>
              </div>

              <%!-- Annotations --%>
              <%= if @notes && length(@notes) > 0 do %>
                <div>
                  <div class="flex items-center gap-2 mb-2">
                    <span class="text-[11px] font-medium text-base-content/40 uppercase tracking-wider">
                      Annotations
                    </span>
                    <span class="text-[11px] font-mono tabular-nums text-base-content/25">
                      {length(@notes)}
                    </span>
                  </div>
                  <div class="space-y-2">
                    <%= for note <- @notes do %>
                      <div class="rounded-lg bg-base-content/[0.03] px-3 py-2.5">
                        <%= if note.title do %>
                          <div class="text-xs font-semibold text-base-content/70 mb-1">{note.title}</div>
                        <% end %>
                        <pre class="whitespace-pre-wrap text-xs text-base-content/60 font-mono leading-relaxed">{note.body}</pre>
                        <div class="mt-1.5 text-[11px] text-base-content/25">
                          {format_relative_time(note.created_at)}
                        </div>
                      </div>
                    <% end %>
                  </div>
                </div>
              <% end %>

              <%!-- Metadata --%>
              <div class="flex items-center gap-3 text-[11px] text-base-content/25 pt-2">
                <%= if @task.updated_at && @task.updated_at != @task.created_at do %>
                  <span>Updated {format_relative_time(@task.updated_at)}</span>
                  <span class="text-base-content/10">&middot;</span>
                <% end %>
                <%= if @task.agent_id do %>
                  <span class="font-mono">Agent {String.slice(@task.agent_id, 0..7)}</span>
                <% end %>
              </div>
            </div>

            <%!-- Footer actions --%>
            <div class="px-6 py-4 border-t border-base-content/5 flex items-center gap-2">
              <button type="submit" class="btn btn-sm btn-primary text-xs px-4">
                Save
              </button>
              <button
                type="button"
                phx-click="start_agent_for_task"
                phx-value-task_id={@task.uuid || to_string(@task.id)}
                class="btn btn-sm btn-ghost text-xs gap-1.5 text-base-content/50 hover:text-base-content/80"
              >
                <.icon name="hero-play" class="w-3.5 h-3.5" /> Start Agent
              </button>
              <div class="ml-auto">
                <button
                  type="button"
                  phx-click={@delete_event}
                  phx-value-task_id={@task.uuid || to_string(@task.id)}
                  data-confirm="Delete this task?"
                  class="btn btn-sm btn-ghost text-xs text-error/50 hover:text-error hover:bg-error/10"
                >
                  <.icon name="hero-trash" class="w-3.5 h-3.5" />
                </button>
              </div>
            </div>
          </form>
        <% else %>
          <div class="flex items-center justify-center h-full">
            <span class="text-sm text-base-content/30">No task selected</span>
          </div>
        <% end %>
      </div>
    <% end %>
    </div>
    """
  end

  defp format_date_input(nil), do: ""

  defp format_date_input(datetime) when is_binary(datetime) do
    String.slice(datetime, 0..9)
  end

  defp format_date_input(_), do: ""

  defp format_tags(nil), do: ""
  defp format_tags([]), do: ""

  defp format_tags(tags) when is_list(tags) do
    tags
    |> Enum.map(& &1.name)
    |> Enum.join(", ")
  end

  defp format_relative_time(nil), do: ""

  defp format_relative_time(timestamp) when is_binary(timestamp) do
    case NaiveDateTime.from_iso8601(timestamp) do
      {:ok, dt} ->
        now = NaiveDateTime.utc_now()
        diff_seconds = NaiveDateTime.diff(now, dt)

        cond do
          diff_seconds < 60 -> "just now"
          diff_seconds < 3600 -> "#{div(diff_seconds, 60)}m ago"
          diff_seconds < 86400 -> "#{div(diff_seconds, 3600)}h ago"
          diff_seconds < 604_800 -> "#{div(diff_seconds, 86400)}d ago"
          true -> Calendar.strftime(dt, "%b %d, %Y")
        end

      _ ->
        timestamp
    end
  end

  defp format_relative_time(_), do: ""
end
