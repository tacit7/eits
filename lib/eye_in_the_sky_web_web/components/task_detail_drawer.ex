defmodule EyeInTheSkyWebWeb.Components.TaskDetailDrawer do
  @moduledoc """
  Left-side drawer for viewing and editing task details.
  """

  use Phoenix.LiveComponent
  import EyeInTheSkyWebWeb.CoreComponents

  @impl true
  def render(assigns) do
    ~H"""
    <div class="drawer drawer-start z-50">
      <input
        id="task-detail-drawer"
        type="checkbox"
        class="drawer-toggle"
        checked={@show}
        phx-click={@toggle_event}
      />
      <div class="drawer-side">
        <label for="task-detail-drawer" class="drawer-overlay"></label>
        <div class="menu p-0 w-[768px] min-h-full bg-base-100 text-base-content flex flex-row">
          <%= if @task do %>
            <!-- Main Content -->
            <div class="flex-1 overflow-y-auto">
              <!-- Header with close button -->
              <div class="p-6 pb-4">
                <div class="flex items-start justify-between mb-6">
                  <.icon name="hero-document-text" class="w-6 h-6 text-base-content/60 mt-1" />
                  <button
                    phx-click={@toggle_event}
                    class="btn btn-ghost btn-sm btn-circle -mt-2 -mr-2"
                  >
                    ✕
                  </button>
                </div>
                <form phx-submit={@update_event} class="space-y-6">
                  <!-- Title -->
                  <div>
                    <input
                      type="text"
                      name="title"
                      value={@task.title}
                      class="text-xl font-semibold w-full bg-transparent border-none focus:outline-none focus:ring-0 p-0"
                      placeholder="Task title"
                      required
                    />
                  </div>

                  <!-- Badges -->
                  <div class="flex flex-wrap gap-2 items-center">
                    <!-- Status Badge -->
                    <%= if @task.state do %>
                      <div class="badge badge-lg gap-2">
                        <.icon name="hero-queue-list" class="w-4 h-4" />
                        {String.capitalize(@task.state.name)}
                      </div>
                    <% end %>
                    <!-- Priority Badge -->
                    <%= if @task.priority && @task.priority > 0 do %>
                      <div class={
                        "badge badge-lg gap-2 " <>
                          cond do
                            @task.priority >= 3 -> "badge-error"
                            @task.priority >= 2 -> "badge-warning"
                            true -> "badge-info"
                          end
                      }>
                        <.icon name="hero-flag" class="w-4 h-4" />
                        {priority_text(@task.priority)}
                      </div>
                    <% end %>
                    <!-- Due Date Badge -->
                    <%= if @task.due_at do %>
                      <div class="badge badge-lg gap-2">
                        <.icon name="hero-calendar" class="w-4 h-4" />
                        {format_due_date(@task.due_at)}
                      </div>
                    <% end %>
                    <!-- Tags -->
                    <%= if @task.tags && length(@task.tags) > 0 do %>
                      <%= for tag <- @task.tags do %>
                        <div class="badge badge-outline badge-lg">
                          {tag.name}
                        </div>
                      <% end %>
                    <% end %>
                    <!-- Task ID -->
                    <div class="badge badge-ghost badge-sm font-mono gap-1">
                      {String.slice(@task.id, 0..7)}
                      <button
                        type="button"
                        class="cursor-pointer hover:text-primary transition-colors"
                        phx-hook="CopyToClipboard"
                        id={"copy-task-detail-#{@task.id}"}
                        data-copy={@task.id}
                        onclick="event.stopPropagation(); event.preventDefault();"
                      >
                        <.icon name="hero-clipboard-document" class="w-3 h-3" />
                      </button>
                    </div>
                  </div>

                  <!-- Description -->
                  <div class="space-y-2">
                    <div class="flex items-center gap-2">
                      <.icon name="hero-bars-3-bottom-left" class="w-5 h-5 text-base-content/60" />
                      <h3 class="font-semibold">Description</h3>
                    </div>
                    <textarea
                      name="description"
                      class="textarea textarea-bordered w-full min-h-[120px] text-sm"
                      placeholder="Add a more detailed description..."
                    >{@task.description}</textarea>
                    <p class="text-xs text-base-content/50">Markdown supported</p>
                  </div>

                  <!-- Annotations -->
                  <%= if @notes && length(@notes) > 0 do %>
                    <div class="space-y-2">
                      <div class="flex items-center gap-2">
                        <.icon name="hero-document-text" class="w-5 h-5 text-base-content/60" />
                        <h3 class="font-semibold">Annotations</h3>
                        <span class="badge badge-sm">{length(@notes)}</span>
                      </div>
                      <div class="space-y-3">
                        <%= for note <- @notes do %>
                          <div class="border border-base-300 rounded-lg p-3 bg-base-50">
                            <%= if note.title do %>
                              <h4 class="font-semibold text-sm mb-2">{note.title}</h4>
                            <% end %>
                            <pre class="whitespace-pre-wrap text-sm text-base-content/80 font-mono leading-relaxed">{note.body}</pre>
                            <div class="flex items-center gap-2 mt-2 text-xs text-base-content/50">
                              <.icon name="hero-clock" class="w-3 h-3" />
                              <span>{format_relative_time(note.created_at)}</span>
                            </div>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  <% end %>

                  <!-- Hidden form fields -->
                  <input type="hidden" name="state_id" value={@task.state_id} />
                  <input type="hidden" name="priority" value={@task.priority || 0} />
                  <input type="hidden" name="due_at" value={format_date_input(@task.due_at)} />
                  <input type="hidden" name="tags" value={format_tags(@task.tags)} />

                  <!-- Metadata -->
                  <div class="space-y-2 text-xs text-base-content/60">
                    <div class="flex items-center gap-2">
                      <.icon name="hero-clock" class="w-4 h-4" />
                      <span>Created {format_relative_time(@task.created_at)}</span>
                    </div>
                    <%= if @task.updated_at && @task.updated_at != @task.created_at do %>
                      <div class="flex items-center gap-2">
                        <.icon name="hero-arrow-path" class="w-4 h-4" />
                        <span>Updated {format_relative_time(@task.updated_at)}</span>
                      </div>
                    <% end %>
                    <%= if @task.agent_id do %>
                      <div class="flex items-center gap-2">
                        <.icon name="hero-user" class="w-4 h-4" />
                        <span class="font-mono">{String.slice(@task.agent_id, 0..7)}</span>
                      </div>
                    <% end %>
                  </div>

                  <!-- Save Button -->
                  <div class="pt-4">
                    <button type="submit" class="btn btn-primary btn-sm">Save Changes</button>
                  </div>
                </form>
              </div>
            </div>

            <!-- Sidebar -->
            <div class="w-48 border-l border-base-300 p-4 space-y-4">
              <div>
                <h4 class="text-xs font-semibold text-base-content/60 uppercase mb-2">Quick Edit</h4>
                <div class="space-y-2">
                  <!-- Note: These update the hidden fields in the main form -->
                  <!-- Edit Status -->
                  <div class="form-control">
                    <label class="label py-1">
                      <span class="label-text text-xs">Status</span>
                    </label>
                    <select
                      name="sidebar_state_id"
                      class="select select-bordered select-sm w-full"
                      onchange="document.querySelector('input[name=state_id]').value = this.value"
                    >
                      <%= for state <- @workflow_states do %>
                        <option value={state.id} selected={@task.state_id == state.id}>
                          {String.capitalize(state.name)}
                        </option>
                      <% end %>
                    </select>
                  </div>

                  <!-- Edit Priority -->
                  <div class="form-control">
                    <label class="label py-1">
                      <span class="label-text text-xs">Priority</span>
                    </label>
                    <select
                      name="sidebar_priority"
                      class="select select-bordered select-sm w-full"
                      onchange="document.querySelector('input[name=priority]').value = this.value"
                    >
                      <option value="0" selected={@task.priority == 0}>No Priority</option>
                      <option value="1" selected={@task.priority == 1}>Low</option>
                      <option value="2" selected={@task.priority == 2}>Medium</option>
                      <option value="3" selected={@task.priority == 3}>High</option>
                    </select>
                  </div>

                  <!-- Due Date -->
                  <div class="form-control">
                    <label class="label py-1">
                      <span class="label-text text-xs">Due Date</span>
                    </label>
                    <input
                      type="date"
                      name="sidebar_due_at"
                      value={format_date_input(@task.due_at)}
                      class="input input-bordered input-sm w-full"
                      onchange="document.querySelector('input[name=due_at]').value = this.value"
                    />
                  </div>

                  <!-- Start Agent Button -->
                  <button
                    type="button"
                    phx-click="start_agent_for_task"
                    phx-value-task_id={@task.id}
                    class="btn btn-accent btn-sm w-full"
                  >
                    <.icon name="hero-play" class="w-4 h-4" />
                    Start Agent
                  </button>

                  <!-- Delete Button -->
                  <button
                    type="button"
                    phx-click={@delete_event}
                    phx-value-task_id={@task.id}
                    class="btn btn-error btn-outline btn-sm w-full"
                    data-confirm="Delete this task?"
                  >
                    <.icon name="hero-trash" class="w-4 h-4" />
                    Delete
                  </button>
                </div>
              </div>
            </div>
          <% else %>
            <!-- No task selected -->
            <div class="flex items-center justify-center h-full p-6">
              <p class="text-base-content/60">No task selected</p>
            </div>
          <% end %>
        </div>
      </div>
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

  defp format_timestamp(nil), do: ""

  defp format_timestamp(timestamp) when is_binary(timestamp) do
    case NaiveDateTime.from_iso8601(timestamp) do
      {:ok, dt} -> Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
      _ -> timestamp
    end
  end

  defp format_timestamp(_), do: ""

  defp format_due_date(nil), do: ""

  defp format_due_date(datetime) when is_binary(datetime) do
    case Date.from_iso8601(String.slice(datetime, 0..9)) do
      {:ok, date} ->
        today = Date.utc_today()

        cond do
          Date.compare(date, today) == :eq -> "Today"
          Date.compare(date, Date.add(today, 1)) == :eq -> "Tomorrow"
          Date.compare(date, today) == :lt -> "Overdue"
          true -> Calendar.strftime(date, "%b %d, %Y")
        end

      _ ->
        datetime
    end
  end

  defp format_due_date(_), do: ""

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

  defp priority_text(priority) do
    cond do
      priority >= 3 -> "High"
      priority >= 2 -> "Medium"
      priority >= 1 -> "Low"
      true -> "None"
    end
  end
end
