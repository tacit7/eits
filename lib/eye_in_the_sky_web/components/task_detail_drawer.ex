defmodule EyeInTheSkyWeb.Components.TaskDetailDrawer do
  @moduledoc """
  Right-side slide-over panel for viewing and editing task details.
  """

  use EyeInTheSkyWeb, :html

  import EyeInTheSkyWeb.Helpers.ViewHelpers,
    only: [relative_time: 1, overdue?: 1, due_today?: 1, format_date_input: 1]

  alias Phoenix.LiveView.JS

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
          <div class="flex items-center gap-2 text-xs text-base-content/30 flex-wrap">
            <span class="font-mono">
              #{@task.id}
            </span>
            <.priority_badge priority={@task.priority} />
            <%!-- Tag pills --%>
            <%= if is_list(@task.tags) && @task.tags != [] do %>
              <%= for tag <- @task.tags do %>
                <span class="px-1.5 py-px rounded text-micro bg-base-content/8 text-base-content/50 font-medium">
                  {tag.name}
                </span>
              <% end %>
            <% end %>
            <button
              type="button"
              phx-hook="CopyToClipboard"
              id={"copy-task-detail-#{@task.id}"}
              data-copy={to_string(@task.id)}
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
            phx-click={clear_selection_and_toggle(@toggle_event)}
            class="min-h-[44px] min-w-[44px] flex items-center justify-center rounded-md text-base-content/30 hover:text-base-content/60 hover:bg-base-content/5 transition-colors"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <%!-- Scrollable body --%>
        <div class="flex-1 overflow-y-auto px-6 py-5 space-y-5">
          <%!-- Main edit form (no nested forms) --%>
          <form id="task-edit-form" phx-submit={@update_event} phx-hook="DrawerDirtyForm">
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

          <%!-- Context: agent, sessions, source --%>
          <% has_context =
            not is_nil(@task.agent_id) ||
              (is_list(@task.sessions) && @task.sessions != []) ||
              not is_nil(@task.created_by_session_id) %>
          <%= if has_context do %>
            <div class="border-t border-base-content/5 pt-4 space-y-2">
              <span class="text-mini font-medium text-base-content/40 uppercase tracking-wider block mb-3">
                Context
              </span>
              <%!-- Agent row --%>
              <%= if not is_nil(@task.agent) do %>
                <% agent = @task.agent %>
                <div class="flex items-center justify-between text-xs">
                  <span class="text-base-content/40 w-20 shrink-0">Agent</span>
                  <div class="flex items-center gap-1.5 min-w-0">
                    <.status_dot status={safe_status_atom(agent.status)} />
                    <span class="font-mono text-base-content/60 truncate">
                      {agent.persona_id || "agent-#{agent.id}"}
                    </span>
                    <span class="text-base-content/20 font-mono">#{agent.id}</span>
                  </div>
                  <.link
                    navigate={"/dm/#{List.first(@task.sessions) && List.first(@task.sessions).uuid}"}
                    class={[
                      "ml-2 shrink-0 text-base-content/30 hover:text-primary transition-colors",
                      if(@task.sessions == [],
                        do: "pointer-events-none opacity-40",
                        else: ""
                      )
                    ]}
                    title="Open session DM"
                  >
                    <.icon name="hero-chat-bubble-left-ellipsis" class="size-3.5" />
                  </.link>
                </div>
              <% else %>
                <%= if not is_nil(@task.agent_id) do %>
                  <div class="flex items-center text-xs gap-1">
                    <span class="text-base-content/40 w-20 shrink-0">Agent</span>
                    <span class="font-mono text-base-content/40">#{@task.agent_id}</span>
                  </div>
                <% end %>
              <% end %>
              <%!-- Sessions --%>
              <%= if is_list(@task.sessions) && @task.sessions != [] do %>
                <%= for session <- @task.sessions do %>
                  <div class="flex items-center justify-between text-xs">
                    <span class="text-base-content/40 w-20 shrink-0">Session</span>
                    <.link
                      navigate={"/dm/#{session.uuid}"}
                      class="flex items-center gap-1 text-base-content/50 hover:text-primary transition-colors min-w-0"
                    >
                      <.custom_icon name="lucide-robot" class="size-3 shrink-0" />
                      <span class="font-mono truncate">{session_label(session)}</span>
                    </.link>
                    <.status_dot status={safe_status_atom(session.status)} />
                  </div>
                <% end %>
              <% end %>
              <%!-- Created by session --%>
              <%= if not is_nil(@task.created_by_session_id) && (is_nil(@task.sessions) || @task.sessions == []) do %>
                <div class="flex items-center text-xs gap-1">
                  <span class="text-base-content/40 w-20 shrink-0">Created by</span>
                  <span class="font-mono text-base-content/40">
                    session #{@task.created_by_session_id}
                  </span>
                </div>
              <% end %>
              <%!-- Worktree --%>
              <%= if not is_nil(@task.agent) && not is_nil(@task.agent.git_worktree_path) do %>
                <div class="flex items-center text-xs gap-1">
                  <span class="text-base-content/40 w-20 shrink-0">Worktree</span>
                  <span class="font-mono text-base-content/40 truncate text-micro">
                    {Path.basename(@task.agent.git_worktree_path)}
                  </span>
                </div>
              <% end %>
            </div>
          <% end %>

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

          <%!-- Metadata timestamps --%>
          <%= if not is_nil(@task.updated_at) && @task.updated_at != @task.created_at do %>
            <div class="text-mini text-base-content/25 pt-2">
              Updated {relative_time(@task.updated_at)}
            </div>
          <% end %>

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
          <div class="flex items-center gap-1.5">
            <button
              type="submit"
              form="task-edit-form"
              class="btn btn-sm btn-primary text-xs px-4 opacity-40 pointer-events-none"
            >
              Save
            </button>
            <span
              id="task-dirty-indicator"
              class="hidden text-micro text-warning/70 ml-0.5"
            >
              unsaved
            </span>
          </div>
          <%!-- Start Agent: disabled when an agent is already assigned or session exists --%>
          <% has_agent = not is_nil(@task.agent_id) || (is_list(@task.sessions) && @task.sessions != []) %>
          <% agent_disabled_reason =
            cond do
              is_list(@task.sessions) && @task.sessions != [] ->
                "Session #{session_label(List.first(@task.sessions))} already running"
              not is_nil(@task.agent_id) ->
                "Agent ##{@task.agent_id} already assigned"
              true ->
                "Start agent for this task"
            end %>
          <button
            type="button"
            phx-click="start_agent_for_task"
            phx-value-task_id={@task.uuid || to_string(@task.id)}
            disabled={has_agent}
            class={[
              "btn btn-sm btn-ghost text-xs gap-1.5",
              if(has_agent,
                do: "text-base-content/25 cursor-not-allowed",
                else: "text-base-content/50 hover:text-base-content/80"
              )
            ]}
            title={agent_disabled_reason}
          >
            <.icon name="hero-play" class="size-3.5" /> Start Agent
          </button>
          <div class="ml-auto flex items-center gap-1">
            <%!-- Copy to project dropdown --%>
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
            <%!-- Overflow menu: archive + delete (demoted, destructive) --%>
            <div class="dropdown dropdown-top dropdown-end">
              <button
                type="button"
                tabindex="0"
                class="btn btn-sm btn-ghost text-xs text-base-content/30 hover:text-base-content/60"
                title="More actions"
              >
                <.icon name="hero-ellipsis-horizontal" class="size-4" />
              </button>
              <ul
                tabindex="0"
                class="dropdown-content menu p-1 shadow-lg bg-base-200 rounded-lg w-40 z-50"
              >
                <li>
                  <button
                    type="button"
                    phx-click="archive_task"
                    phx-value-task_id={@task.uuid || to_string(@task.id)}
                    class="text-xs text-base-content/60 hover:text-warning gap-2"
                  >
                    <.icon name="hero-archive-box" class="size-3.5" /> Archive
                  </button>
                </li>
                <li>
                  <button
                    type="button"
                    phx-click={@delete_event}
                    phx-value-task_id={@task.uuid || to_string(@task.id)}
                    phx-confirm="Delete this task?"
                    data-drawer-delete="true"
                    class="text-xs text-error/60 hover:text-error gap-2"
                  >
                    <.icon name="hero-trash" class="size-3.5" /> Delete
                  </button>
                </li>
              </ul>
            </div>
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

  # Builds a JS command that clears the selected-row indicator before toggling.
  # Scoped to #project-tasks-list to avoid nuking data-drawer-open on unrelated components.
  defp clear_selection_and_toggle(event) when is_binary(event) do
    JS.remove_attribute("data-drawer-open", to: "#project-tasks-list [data-drawer-open]")
    |> JS.push(event)
  end

  defp clear_selection_and_toggle(%JS{} = js), do: js

  defp format_tags(nil), do: ""
  defp format_tags([]), do: ""

  defp format_tags(tags) when is_list(tags) do
    Enum.map_join(tags, ", ", & &1.name)
  end

  # Strip raw "agent-id <uuid>" descriptions down to a short readable label.
  defp session_label(%{description: "agent-id " <> uuid}) do
    "agent " <> String.slice(uuid, 0..7)
  end

  defp session_label(%{description: desc}) when is_binary(desc) and desc != "" do
    String.slice(desc, 0..30)
  end

  defp session_label(_), do: "Agent"

  # Safe conversion of status strings to atoms for status_dot.
  # String.to_existing_atom/1 crashes on unknown strings — use a lookup instead.
  @known_statuses ~w(idle working waiting completed failed)a
  @status_map Map.new(@known_statuses, &{to_string(&1), &1})
  defp safe_status_atom(status) when is_binary(status),
    do: Map.get(@status_map, status, :idle)

  defp safe_status_atom(_), do: :idle
end
