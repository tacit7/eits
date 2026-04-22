defmodule EyeInTheSkyWeb.TeamDetailComponent do
  @moduledoc false
  use EyeInTheSkyWeb, :live_component

  import EyeInTheSkyWeb.Components.SessionCard, only: [session_row: 1]

  alias EyeInTheSky.Tasks.WorkflowState
  alias EyeInTheSkyWeb.Helpers.ViewHelpers

  @state_todo WorkflowState.todo_id()
  @state_in_progress WorkflowState.in_progress_id()
  @state_in_review WorkflowState.in_review_id()
  @state_done WorkflowState.done_id()

  @impl true
  def update(assigns, socket) do
    team = assigns.team
    active_members = Enum.count(team.members, &(&1.status == "active"))
    done_tasks = Enum.count(team.tasks, &(&1.state_id == @state_done))
    total_tasks = length(team.tasks)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:active_members, active_members)
     |> assign(:done_tasks, done_tasks)
     |> assign(:total_tasks, total_tasks)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-4 max-w-4xl space-y-6">
      <%!-- Header --%>
      <div class="flex items-start justify-between gap-4">
        <div class="min-w-0">
          <div class="flex items-center flex-wrap gap-3 mb-1">
            <h1 class="text-2xl font-bold text-base-content tracking-tight">{@team.name}</h1>
            <span class={["badge badge-sm font-medium", status_badge_class(@team.status)]}>
              {@team.status}
            </span>
          </div>
          <%= if @team.description do %>
            <p class="text-sm text-base-content/50">{@team.description}</p>
          <% end %>
        </div>
      </div>

      <%!-- Stats row --%>
      <div class="flex items-center gap-3 text-[11px] text-base-content/40">
        <span>
          <span class="font-mono font-semibold text-base-content/70">{length(@team.members)}</span>
          members
        </span>
        <span class="text-base-content/20">·</span>
        <span>
          <span class="font-mono font-semibold text-success">{@active_members}</span> active
        </span>
        <span class="text-base-content/20">·</span>
        <span>
          <span class="font-mono font-semibold text-base-content/70">
            {@done_tasks}/{@total_tasks}
          </span>
          tasks done
        </span>
      </div>

      <%!-- Task progress bar --%>
      <%= if @total_tasks > 0 do %>
        <div class="space-y-1">
          <div class="flex items-center justify-between text-[11px] text-base-content/40">
            <span>Progress</span>
            <span class="font-mono">{@done_tasks}/{@total_tasks}</span>
          </div>
          <div class="h-1.5 bg-base-300 rounded-full overflow-hidden">
            <div
              class="h-full bg-success rounded-full transition-all"
              style={"width: #{Float.round(@done_tasks / @total_tasks * 100, 1)}%"}
            >
            </div>
          </div>
        </div>
      <% end %>

      <%!-- Members --%>
      <section>
        <div class="flex items-center gap-2 mb-3">
          <h2 class="text-[11px] font-semibold text-base-content/50 uppercase tracking-widest">
            Members
          </h2>
          <div class="h-px flex-1 bg-base-300"></div>
          <span class="font-mono text-[11px] text-base-content/30">{length(@team.members)}</span>
        </div>

        <div class="space-y-2">
          <%= for member <- @team.members do %>
            <div class={[
              "rounded-lg overflow-hidden",
              member.session_id && @selected_agent_session_id == member.session_id &&
                "ring-1 ring-primary/40"
            ]}>
              <%= if member.session do %>
                <.session_row
                  session={member.session}
                  click_event="select_agent"
                  project_name={if member.role not in [nil, ""], do: member.role}
                />
              <% else %>
                <%!-- Member without an associated session --%>
                <div class="flex items-center gap-3 p-3 bg-base-200">
                  <div class={[
                    "w-8 h-8 rounded-lg flex items-center justify-center text-xs font-bold shrink-0",
                    member_avatar_class(member.status)
                  ]}>
                    {ViewHelpers.member_initials(member.name)}
                  </div>
                  <div class="flex-1 min-w-0">
                    <span class="font-medium text-sm text-base-content truncate">{member.name}</span>
                    <div class="flex items-center gap-2 mt-0.5">
                      <span class={[
                        "w-1.5 h-1.5 rounded-full shrink-0",
                        member_status_dot(member.status)
                      ]}>
                      </span>
                      <span class={["text-[11px] font-medium", member_status_text(member.status)]}>
                        {member.status}
                      </span>
                    </div>
                  </div>
                </div>
              <% end %>
              <%!-- Per-member tasks --%>
              <%= if Map.get(member, :tasks, []) != [] do %>
                <div class="border-t border-base-300/50 px-3 py-2 space-y-1 bg-base-200">
                  <%= for task <- member.tasks do %>
                    <div class="flex items-center gap-2">
                      <div class={["w-1.5 h-1.5 rounded-full shrink-0", task_state_dot(task.state_id)]}>
                      </div>
                      <%= if task.project_id do %>
                        <.link
                          navigate={~p"/projects/#{task.project_id}/tasks"}
                          class="flex-1 text-xs text-base-content/70 truncate hover:text-base-content/90 hover:underline"
                        >
                          {task.title}
                        </.link>
                      <% else %>
                        <span class="flex-1 text-xs text-base-content/70 truncate">{task.title}</span>
                      <% end %>
                      <%= if task.state do %>
                        <span class={[
                          "text-xs font-medium px-1.5 py-0.5 rounded shrink-0",
                          task_state_chip(task.state_id)
                        ]}>
                          {task.state.name}
                        </span>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </section>

      <%!-- Unowned Tasks --%>
      <section>
        <div class="flex items-center gap-2 mb-3">
          <h2 class="text-[11px] font-semibold text-base-content/50 uppercase tracking-widest">
            Unassigned Tasks
          </h2>
          <div class="h-px flex-1 bg-base-300"></div>
          <span class="font-mono text-[11px] text-base-content/30">
            {length(Map.get(@team, :unowned_tasks, []))}
          </span>
        </div>

        <%= if Map.get(@team, :unowned_tasks, []) == [] do %>
          <div class="flex items-center gap-3 p-4 rounded-lg border border-dashed border-base-300 text-base-content/30">
            <.icon name="hero-clipboard-document-list" class="w-4 h-4" />
            <p class="text-sm">No unassigned tasks</p>
          </div>
        <% else %>
          <div class="space-y-1.5">
            <%= for task <- @team.unowned_tasks do %>
              <div class="rounded-lg bg-base-200 overflow-hidden">
                <div class="flex items-center gap-3 px-3 py-2.5 group">
                  <div class={["w-1.5 h-1.5 rounded-full shrink-0", task_state_dot(task.state_id)]}>
                  </div>
                  <%= if task.project_id do %>
                    <.link
                      navigate={~p"/projects/#{task.project_id}/tasks"}
                      class="flex-1 text-sm text-base-content min-w-0 truncate hover:underline"
                    >
                      {task.title}
                    </.link>
                  <% else %>
                    <span class="flex-1 text-sm text-base-content min-w-0 truncate">
                      {task.title}
                    </span>
                  <% end %>
                  <div class="flex items-center gap-1.5 shrink-0">
                    <%= if Map.get(task, :notes, []) != [] do %>
                      <span class="flex items-center gap-1 text-xs text-base-content/40 font-mono">
                        <.icon name="hero-chat-bubble-left-ellipsis" class="w-3 h-3" />
                        {length(task.notes)}
                      </span>
                    <% end %>
                    <%= if task.state do %>
                      <span class={[
                        "text-xs font-medium px-1.5 py-0.5 rounded",
                        task_state_chip(task.state_id)
                      ]}>
                        {task.state.name}
                      </span>
                    <% end %>
                    <%!-- Assign to member picker — no phx-target, event handled by parent LiveView --%>
                    <select
                      class="text-xs bg-base-300 border-0 rounded px-1.5 py-0.5 text-base-content/60 cursor-pointer focus:outline-none"
                      phx-change="assign_task"
                      phx-value-task-id={task.id}
                      name="session-id"
                    >
                      <option value="">Assign to...</option>
                      <%= for member <- Enum.filter(@team.members, & &1.session_id) do %>
                        <option value={member.session_id}>{member.name}</option>
                      <% end %>
                    </select>
                  </div>
                </div>
                <%= if Map.get(task, :notes, []) != [] do %>
                  <div class="border-t border-base-300/50 px-3 pb-2.5 pt-2 space-y-2">
                    <%= for note <- task.notes do %>
                      <div class="text-xs text-base-content/50 pl-3 border-l-2 border-base-content/10">
                        <p class="whitespace-pre-wrap leading-relaxed">{note.body}</p>
                        <span class="text-xs text-base-content/25 mt-1 block font-mono">
                          {ViewHelpers.format_datetime_short_time(note.created_at)}
                        </span>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        <% end %>
      </section>
    </div>
    """
  end

  defp status_badge_class("active"), do: "badge-success"
  defp status_badge_class("archived"), do: "badge-ghost"
  defp status_badge_class(_), do: "badge-neutral"

  defp member_status_dot("active"), do: "bg-success"
  defp member_status_dot("idle"), do: "bg-base-content/30"
  defp member_status_dot("done"), do: "bg-base-content/30"
  defp member_status_dot(_), do: "bg-base-content/20"

  defp member_status_text("active"), do: "text-success"
  defp member_status_text("idle"), do: "text-base-content/50"
  defp member_status_text("done"), do: "text-base-content/40"
  defp member_status_text(_), do: "text-base-content/30"

  defp member_avatar_class("active"), do: "bg-success/15 text-success"
  defp member_avatar_class("idle"), do: "bg-base-300 text-base-content/50"
  defp member_avatar_class("done"), do: "bg-base-300 text-base-content/40"
  defp member_avatar_class(_), do: "bg-base-300 text-base-content/30"

  defp task_state_dot(@state_todo), do: "bg-base-content/30"
  defp task_state_dot(@state_in_progress), do: "bg-info"
  defp task_state_dot(@state_done), do: "bg-success"
  defp task_state_dot(@state_in_review), do: "bg-warning"
  defp task_state_dot(_), do: "bg-base-content/20"

  defp task_state_chip(@state_todo), do: "bg-base-300 text-base-content/40"
  defp task_state_chip(@state_in_progress), do: "bg-info/15 text-info"
  defp task_state_chip(@state_done), do: "bg-success/15 text-success"
  defp task_state_chip(@state_in_review), do: "bg-warning/15 text-warning"
  defp task_state_chip(_), do: "bg-base-300 text-base-content/30"
end
