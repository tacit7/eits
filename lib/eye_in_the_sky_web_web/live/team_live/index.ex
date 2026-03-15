defmodule EyeInTheSkyWebWeb.TeamLive.Index do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.{Teams, Tasks, Notes}
  alias EyeInTheSkyWeb.Tasks.WorkflowState

  @state_todo WorkflowState.todo_id()
  @state_in_progress WorkflowState.in_progress_id()
  @state_in_review WorkflowState.in_review_id()
  @state_done WorkflowState.done_id()

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "teams")
    end

    {:ok,
     socket
     |> assign(:page_title, "Teams")
     |> assign(:sidebar_tab, :teams)
     |> assign(:sidebar_project, nil)
     |> assign(:show_archived, false)
     |> assign(:teams, load_teams(false))
     |> assign(:selected_team_id, nil)
     |> assign(:selected_team, nil)
     |> assign(:mobile_view, :list)}
  end

  @impl true
  def handle_info({event, _payload}, socket)
      when event in [:team_created, :team_deleted, :member_joined, :member_updated, :member_left] do
    {:noreply,
     socket
     |> assign(:teams, load_teams(socket.assigns.show_archived))
     |> maybe_refresh_selected_team()}
  end

  @impl true
  def handle_event("select_team", %{"id" => id}, socket) do
    team_id = String.to_integer(id)
    team = Teams.get_team!(team_id) |> load_team_detail()
    {:noreply, show_team_detail(socket, team_id, team)}
  end

  @impl true
  def handle_event("close_team", _params, socket) do
    {:noreply, show_team_list(socket)}
  end

  @impl true
  def handle_event("toggle_archived", _params, socket) do
    show_archived = !socket.assigns.show_archived
    {:noreply,
     socket
     |> assign(:show_archived, show_archived)
     |> assign(:teams, load_teams(show_archived))}
  end

  @impl true
  def handle_event("assign_task", %{"task-id" => task_id, "session-id" => session_id}, socket) do
    task_id = String.to_integer(task_id)
    session_id = String.to_integer(session_id)
    Tasks.link_session_to_task(task_id, session_id)

    team = Teams.get_team!(socket.assigns.selected_team_id) |> load_team_detail()
    {:noreply, assign(socket, :selected_team, team)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-full gap-0">
      <%!-- Team list sidebar --%>
      <div class="w-72 border-r border-base-300 flex flex-col shrink-0">
        <div class="px-4 py-3 border-b border-base-300 flex items-center justify-between">
          <div class="flex items-center gap-2">
            <.icon name="hero-user-group" class="w-4 h-4 text-base-content/50" />
            <span class="text-xs font-semibold uppercase tracking-widest text-base-content/60">Teams</span>
          </div>
          <div class="flex items-center gap-2">
            <button
              phx-click="toggle_archived"
              class={["text-[10px] font-medium px-1.5 py-0.5 rounded transition-colors",
                if(@show_archived, do: "bg-base-content/10 text-base-content/60", else: "text-base-content/30 hover:text-base-content/50")
              ]}
              title={if @show_archived, do: "Showing archived", else: "Show archived"}
            >
              <%= if @show_archived, do: "archived", else: "archived" %>
            </button>
            <span class="font-mono text-xs text-base-content/40"><%= length(@teams) %></span>
          </div>
        </div>

        <div class="flex-1 overflow-y-auto">
          <%= if @teams == [] do %>
            <div class="flex flex-col items-center justify-center py-16 px-4 text-center gap-3">
              <div class="w-10 h-10 rounded-full bg-base-200 flex items-center justify-center">
                <.icon name="hero-user-group" class="w-5 h-5 text-base-content/30" />
              </div>
              <p class="text-xs text-base-content/30">No active teams</p>
            </div>
          <% else %>
            <div class="py-1">
              <%= for team <- @teams do %>
                <button
                  class={[
                    "w-full text-left px-3 py-2.5 group transition-colors relative",
                    if(@selected_team_id == team.id,
                      do: "bg-primary/10 border-l-2 border-l-primary",
                      else: "hover:bg-base-200 border-l-2 border-l-transparent"
                    )
                  ]}
                  phx-click="select_team"
                  phx-value-id={team.id}
                >
                  <div class="flex items-start justify-between gap-2 mb-1">
                    <span class={[
                      "font-medium text-sm leading-tight truncate",
                      @selected_team_id == team.id && "text-primary"
                    ]}>
                      <%= team.name %>
                    </span>
                    <div class="flex items-center gap-1 shrink-0 mt-0.5">
                      <%= if team.status == "active" do %>
                        <span class="relative flex h-1.5 w-1.5">
                          <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-success opacity-75"></span>
                          <span class="relative inline-flex rounded-full h-1.5 w-1.5 bg-success"></span>
                        </span>
                      <% end %>
                      <span class={["text-[10px] font-medium uppercase tracking-wide", status_text_class(team.status)]}>
                        <%= team.status %>
                      </span>
                    </div>
                  </div>
                  <div class="flex items-center gap-3 text-[11px] text-base-content/40">
                    <span class="flex items-center gap-1">
                      <.icon name="hero-users" class="w-3 h-3" />
                      <%= length(team.members) %>
                    </span>
                    <%= if active_member_count(team.members) > 0 do %>
                      <span class="flex items-center gap-1 text-success/70">
                        <span class="w-1.5 h-1.5 rounded-full bg-success/70 inline-block"></span>
                        <%= active_member_count(team.members) %> active
                      </span>
                    <% end %>
                  </div>
                </button>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>

      <%!-- Team detail panel --%>
      <div class="flex-1 overflow-y-auto min-w-0">
        <%= if @selected_team do %>
          <.team_detail team={@selected_team} />
        <% else %>
          <div class="flex items-center justify-center h-full">
            <div class="text-center space-y-3">
              <div class="w-16 h-16 rounded-2xl bg-base-200 flex items-center justify-center mx-auto">
                <.icon name="hero-user-group" class="w-8 h-8 text-base-content/20" />
              </div>
              <div>
                <p class="text-sm font-medium text-base-content/30">No team selected</p>
                <p class="text-xs text-base-content/20 mt-1">Choose a team from the list</p>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp team_detail(assigns) do
    active_members = Enum.count(assigns.team.members, &(&1.status == "active"))
    done_tasks = Enum.count(assigns.team.tasks, &(&1.state_id == @state_done))
    total_tasks = length(assigns.team.tasks)
    assigns = assign(assigns, active_members: active_members, done_tasks: done_tasks, total_tasks: total_tasks)

    ~H"""
    <div class="p-6 max-w-4xl space-y-6">
      <%!-- Header --%>
      <div class="flex items-start justify-between gap-4">
        <div class="min-w-0">
          <div class="flex items-center gap-3 mb-1">
            <h1 class="text-2xl font-bold text-base-content tracking-tight"><%= @team.name %></h1>
            <span class={["badge badge-sm font-medium", status_badge_class(@team.status)]}>
              <%= @team.status %>
            </span>
          </div>
          <%= if @team.description do %>
            <p class="text-sm text-base-content/50"><%= @team.description %></p>
          <% end %>
        </div>
      </div>

      <%!-- Stats row --%>
      <div class="grid grid-cols-4 gap-3">
        <div class="bg-base-200 rounded-lg px-4 py-3">
          <div class="text-2xl font-bold font-mono text-base-content"><%= length(@team.members) %></div>
          <div class="text-[11px] text-base-content/40 uppercase tracking-wide mt-0.5">Members</div>
        </div>
        <div class="bg-base-200 rounded-lg px-4 py-3">
          <div class="text-2xl font-bold font-mono text-success"><%= @active_members %></div>
          <div class="text-[11px] text-base-content/40 uppercase tracking-wide mt-0.5">Active</div>
        </div>
        <div class="bg-base-200 rounded-lg px-4 py-3">
          <div class="text-2xl font-bold font-mono text-base-content"><%= @total_tasks %></div>
          <div class="text-[11px] text-base-content/40 uppercase tracking-wide mt-0.5">Tasks</div>
        </div>
        <div class="bg-base-200 rounded-lg px-4 py-3">
          <div class="text-2xl font-bold font-mono text-success"><%= @done_tasks %></div>
          <div class="text-[11px] text-base-content/40 uppercase tracking-wide mt-0.5">Completed</div>
        </div>
      </div>

      <%!-- Task progress bar --%>
      <%= if @total_tasks > 0 do %>
        <div class="space-y-1">
          <div class="flex items-center justify-between text-[11px] text-base-content/40">
            <span>Progress</span>
            <span class="font-mono"><%= @done_tasks %>/<%= @total_tasks %></span>
          </div>
          <div class="h-1.5 bg-base-300 rounded-full overflow-hidden">
            <div
              class="h-full bg-success rounded-full transition-all"
              style={"width: #{Float.round(@done_tasks / @total_tasks * 100, 1)}%"}
            ></div>
          </div>
        </div>
      <% end %>

      <%!-- Members --%>
      <section>
        <div class="flex items-center gap-2 mb-3">
          <h2 class="text-[11px] font-semibold text-base-content/50 uppercase tracking-widest">Members</h2>
          <div class="h-px flex-1 bg-base-300"></div>
          <span class="font-mono text-[11px] text-base-content/30"><%= length(@team.members) %></span>
        </div>

        <div class="space-y-2">
          <%= for member <- @team.members do %>
            <div class="rounded-lg bg-base-200 overflow-hidden">
              <div class="flex items-center gap-3 p-3 hover:bg-base-300/60 transition-colors group">
                <%!-- Avatar initials --%>
                <div class={[
                  "w-8 h-8 rounded-lg flex items-center justify-center text-xs font-bold shrink-0",
                  member_avatar_class(member.status)
                ]}>
                  <%= member_initials(member.name) %>
                </div>
                <div class="flex-1 min-w-0">
                  <div class="flex items-center gap-2">
                    <span class="font-medium text-sm text-base-content truncate"><%= member.name %></span>
                    <%= if member.role && member.role != "" do %>
                      <span class="text-[10px] text-base-content/40 font-mono shrink-0"><%= member.role %></span>
                    <% end %>
                  </div>
                  <div class="flex items-center gap-2 mt-0.5">
                    <span class={["w-1.5 h-1.5 rounded-full shrink-0", member_status_dot(member.status)]}></span>
                    <span class={["text-[11px] font-medium", member_status_text(member.status)]}>
                      <%= member.status %>
                    </span>
                  </div>
                </div>
                <%= if member.session do %>
                  <.link
                    navigate={~p"/dm/#{member.session_id}"}
                    class="opacity-0 group-hover:opacity-100 flex items-center gap-1 text-[10px] font-mono text-base-content/40 bg-base-content/5 px-2 py-1 rounded hover:text-base-content/60 transition-all shrink-0"
                  >
                    <%= String.slice(member.session.uuid || to_string(member.session_id), 0..7) %>
                    <.icon name="hero-arrow-top-right-on-square" class="w-3 h-3" />
                  </.link>
                <% end %>
              </div>
              <%!-- Per-member tasks --%>
              <%= if Map.get(member, :tasks, []) != [] do %>
                <div class="border-t border-base-300/50 px-3 py-2 space-y-1">
                  <%= for task <- member.tasks do %>
                    <div class="flex items-center gap-2">
                      <div class={["w-1.5 h-1.5 rounded-full shrink-0", task_state_dot(task.state_id)]}></div>
                      <%= if task.project_id do %>
                        <.link navigate={~p"/projects/#{task.project_id}/tasks"} class="flex-1 text-xs text-base-content/70 truncate hover:text-base-content/90 hover:underline">
                          <%= task.title %>
                        </.link>
                      <% else %>
                        <span class="flex-1 text-xs text-base-content/70 truncate"><%= task.title %></span>
                      <% end %>
                      <%= if task.state do %>
                        <span class={["text-[10px] font-medium px-1.5 py-0.5 rounded shrink-0", task_state_chip(task.state_id)]}>
                          <%= task.state.name %>
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
          <h2 class="text-[11px] font-semibold text-base-content/50 uppercase tracking-widest">Unassigned Tasks</h2>
          <div class="h-px flex-1 bg-base-300"></div>
          <span class="font-mono text-[11px] text-base-content/30"><%= length(Map.get(@team, :unowned_tasks, [])) %></span>
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
                  <div class={["w-1.5 h-1.5 rounded-full shrink-0", task_state_dot(task.state_id)]}></div>
                  <%= if task.project_id do %>
                    <.link navigate={~p"/projects/#{task.project_id}/tasks"} class="flex-1 text-sm text-base-content min-w-0 truncate hover:underline">
                      <%= task.title %>
                    </.link>
                  <% else %>
                    <span class="flex-1 text-sm text-base-content min-w-0 truncate"><%= task.title %></span>
                  <% end %>
                  <div class="flex items-center gap-1.5 shrink-0">
                    <%= if Map.get(task, :notes, []) != [] do %>
                      <span class="flex items-center gap-1 text-[10px] text-base-content/40 font-mono">
                        <.icon name="hero-chat-bubble-left-ellipsis" class="w-3 h-3" />
                        <%= length(task.notes) %>
                      </span>
                    <% end %>
                    <%= if task.state do %>
                      <span class={["text-[10px] font-medium px-1.5 py-0.5 rounded", task_state_chip(task.state_id)]}>
                        <%= task.state.name %>
                      </span>
                    <% end %>
                    <%!-- Assign to member picker --%>
                    <select
                      class="opacity-0 group-hover:opacity-100 text-[10px] bg-base-300 border-0 rounded px-1.5 py-0.5 text-base-content/60 cursor-pointer focus:outline-none transition-opacity"
                      phx-change="assign_task"
                      phx-value-task-id={task.id}
                      name="session-id"
                    >
                      <option value="">Assign to...</option>
                      <%= for member <- Enum.filter(@team.members, & &1.session_id) do %>
                        <option value={member.session_id}><%= member.name %></option>
                      <% end %>
                    </select>
                  </div>
                </div>
                <%= if Map.get(task, :notes, []) != [] do %>
                  <div class="border-t border-base-300/50 px-3 pb-2.5 pt-2 space-y-2">
                    <%= for note <- task.notes do %>
                      <div class="text-xs text-base-content/50 pl-3 border-l-2 border-base-content/10">
                        <p class="whitespace-pre-wrap leading-relaxed"><%= note.body %></p>
                        <span class="text-[10px] text-base-content/25 mt-1 block font-mono">
                          <%= format_note_time(note.created_at) %>
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

  defp load_teams(show_archived) do
    if show_archived do
      Teams.list_teams(status: "archived")
    else
      Teams.list_teams()
    end
  end

  defp load_team_detail(team) do
    team = EyeInTheSkyWeb.Repo.preload(team, members: [:session])

    tasks =
      Tasks.list_tasks_for_team_with_sessions(team.id)
      |> Notes.with_notes_count()

    # Group tasks by which member session owns them
    member_session_ids = Enum.map(team.members, & &1.session_id) |> MapSet.new()

    tasks_by_session =
      Enum.reduce(tasks, %{}, fn task, acc ->
        matched_sessions = Enum.filter(task.session_ids, &MapSet.member?(member_session_ids, &1))

        case matched_sessions do
          [] -> acc
          sids -> Enum.reduce(sids, acc, fn sid, a -> Map.update(a, sid, [task], &(&1 ++ [task])) end)
        end
      end)

    unowned_tasks = Enum.filter(tasks, fn t ->
      Enum.empty?(Enum.filter(t.session_ids, &MapSet.member?(member_session_ids, &1)))
    end)

    members_with_tasks =
      Enum.map(team.members, fn m ->
        Map.put(m, :tasks, Map.get(tasks_by_session, m.session_id, []))
      end)

    team
    |> Map.put(:tasks, tasks)
    |> Map.put(:members, members_with_tasks)
    |> Map.put(:unowned_tasks, unowned_tasks)
  end

  defp maybe_refresh_selected_team(%{assigns: %{selected_team_id: nil}} = socket), do: socket

  defp maybe_refresh_selected_team(%{assigns: %{selected_team_id: id}} = socket) do
    case Teams.get_team(id) do
      nil -> show_team_list(socket)
      team -> assign(socket, :selected_team, load_team_detail(team))
    end
  end

  defp show_team_detail(socket, team_id, team) do
    socket
    |> assign(:selected_team_id, team_id)
    |> assign(:selected_team, team)
    |> assign(:mobile_view, :detail)
  end

  defp show_team_list(socket) do
    socket
    |> assign(:selected_team_id, nil)
    |> assign(:selected_team, nil)
    |> assign(:mobile_view, :list)
  end

  defp active_member_count(members), do: Enum.count(members, &(&1.status == "active"))

  defp member_initials(nil), do: "?"

  defp member_initials(name) do
    name
    |> String.split()
    |> Enum.take(2)
    |> Enum.map(&String.first/1)
    |> Enum.join()
    |> String.upcase()
  end

  defp format_note_time(nil), do: ""

  defp format_note_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %H:%M")
  defp format_note_time(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %H:%M")

  defp format_note_time(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> Calendar.strftime(dt, "%b %d, %H:%M")
      _ -> str
    end
  end

  defp format_note_time(_), do: ""

  defp status_badge_class("active"), do: "badge-success"
  defp status_badge_class("archived"), do: "badge-ghost"
  defp status_badge_class(_), do: "badge-neutral"

  defp status_text_class("active"), do: "text-success"
  defp status_text_class("archived"), do: "text-base-content/30"
  defp status_text_class(_), do: "text-base-content/40"

  defp member_status_dot("active"), do: "bg-success"
  defp member_status_dot("idle"), do: "bg-warning"
  defp member_status_dot("done"), do: "bg-base-content/30"
  defp member_status_dot(_), do: "bg-base-content/20"

  defp member_status_text("active"), do: "text-success"
  defp member_status_text("idle"), do: "text-warning"
  defp member_status_text("done"), do: "text-base-content/40"
  defp member_status_text(_), do: "text-base-content/30"

  defp member_avatar_class("active"), do: "bg-success/15 text-success"
  defp member_avatar_class("idle"), do: "bg-warning/15 text-warning"
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
