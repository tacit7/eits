defmodule EyeInTheSkyWeb.TeamLive.Index do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.{Teams, Tasks, Notes, Messages}
  alias EyeInTheSkyWeb.Helpers.ViewHelpers

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      EyeInTheSky.Events.subscribe_teams()
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
     |> assign(:mobile_view, :list)
     |> assign(:selected_agent, nil)
     |> assign(:agent_messages, [])
     |> assign(:agent_session_id, nil)}
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
  def handle_info({:new_message, message}, socket) do
    if socket.assigns.agent_session_id && message.session_id == socket.assigns.agent_session_id do
      {:noreply, assign(socket, :agent_messages, socket.assigns.agent_messages ++ [message])}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_team", %{"id" => id}, socket) do
    team_id = String.to_integer(id)
    team = Teams.get_team!(team_id) |> load_team_detail()
    {:noreply, socket |> clear_agent_selection() |> show_team_detail(team_id, team)}
  end

  @impl true
  def handle_event("close_team", _params, socket) do
    {:noreply, socket |> clear_agent_selection() |> show_team_list()}
  end

  @impl true
  def handle_event("select_agent", %{"id" => session_id_str}, socket) do
    session_id = String.to_integer(session_id_str)

    # Unsubscribe from previous session if switching agents
    if socket.assigns.agent_session_id && socket.assigns.agent_session_id != session_id do
      EyeInTheSky.Events.unsubscribe_session(socket.assigns.agent_session_id)
    end

    if is_nil(socket.assigns.agent_session_id) || socket.assigns.agent_session_id != session_id do
      EyeInTheSky.Events.subscribe_session(session_id)
    end

    messages = Messages.list_messages_for_session(session_id) |> Enum.take(-50)
    member = Enum.find(socket.assigns.selected_team.members, &(&1.session_id == session_id))

    {:noreply,
     socket
     |> assign(:selected_agent, member)
     |> assign(:agent_messages, messages)
     |> assign(:agent_session_id, session_id)}
  end

  @impl true
  def handle_event("close_agent", _params, socket) do
    {:noreply, clear_agent_selection(socket)}
  end

  # No-ops for session_row swipe actions (not applicable in teams context)
  @impl true
  def handle_event(event, _params, socket)
      when event in [
             "archive_session",
             "rename_session",
             "save_session_name",
             "cancel_rename",
             "toggle_select",
             "noop"
           ] do
    {:noreply, socket}
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
    <div class="flex h-full gap-0 flex-col">
      <%!-- Team list sidebar --%>
      <div class={[
        "border-b border-base-300 flex flex-col flex-1 w-full",
        @mobile_view == :detail && "hidden"
      ]}>
        <div class="px-4 py-3 border-b border-base-300 flex items-center justify-between">
          <div class="flex items-center gap-2">
            <.icon name="hero-user-group" class="w-4 h-4 text-base-content/50" />
            <span class="text-xs font-semibold uppercase tracking-widest text-base-content/60">
              Teams
            </span>
          </div>
          <div class="flex items-center gap-2">
            <button
              phx-click="toggle_archived"
              class={[
                "text-[10px] font-medium px-1.5 py-0.5 rounded transition-colors",
                if(@show_archived,
                  do: "bg-base-content/10 text-base-content/60",
                  else: "text-base-content/30 hover:text-base-content/50"
                )
              ]}
              title={if @show_archived, do: "Showing archived", else: "Show archived"}
            >
              {if @show_archived, do: "archived", else: "archived"}
            </button>
            <span class="font-mono text-xs text-base-content/40">{length(@teams)}</span>
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
            <div class="space-y-px">
              <%= for team <- @teams do %>
                <div class={[
                  "relative overflow-hidden bg-[oklch(97%_0.005_80)] dark:bg-[hsl(60,2.1%,18.4%)] border-l-2 pl-2",
                  team_status_border(team.status),
                  @selected_team_id == team.id && "ring-inset ring-1 ring-primary/30"
                ]}>
                  <div
                    class="group flex items-center gap-3 py-3 px-2 cursor-pointer"
                    phx-click="select_team"
                    phx-value-id={team.id}
                    role="button"
                    tabindex="0"
                  >
                    <div class="flex-1 min-w-0">
                      <span class="text-[13px] font-medium text-base-content/85 truncate block">
                        {team.name}
                      </span>
                      <div class="flex items-center gap-1.5 mt-1 text-[11px] text-base-content/30">
                        <span class="font-mono">{length(team.members)} members</span>
                        <%= if active_member_count(team.members) > 0 do %>
                          <span class="text-base-content/15">/</span>
                          <span class="text-success/70">
                            {active_member_count(team.members)} active
                          </span>
                        <% end %>
                      </div>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>

      <%!-- Team detail panel --%>
      <div class={[
        "flex-1 min-w-0 w-full flex",
        @mobile_view == :list && "hidden sm:block"
      ]}>
        <%!-- Left: team detail --%>
        <div class={[
          "flex flex-col overflow-hidden",
          @selected_agent && "w-1/2 border-r border-base-300",
          !@selected_agent && "flex-1"
        ]}>
          <%= if @mobile_view == :detail do %>
            <button
              class="flex items-center gap-2 px-4 py-3 text-sm text-base-content/60 border-b border-base-300 w-full hover:bg-base-200 shrink-0"
              phx-click="close_team"
            >
              <.icon name="hero-arrow-left" class="w-4 h-4" /> Teams
            </button>
          <% end %>
          <div class="flex-1 overflow-y-auto">
            <%= if @selected_team do %>
              <.live_component
                module={EyeInTheSkyWeb.TeamDetailComponent}
                id="team-detail"
                team={@selected_team}
                selected_agent_session_id={@agent_session_id}
              />
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

        <%!-- Right: agent messages pane --%>
        <%= if @selected_agent do %>
          <div class="w-1/2 flex flex-col overflow-hidden">
            <div class="px-4 py-3 border-b border-base-300 flex items-center justify-between shrink-0">
              <div class="flex items-center gap-2 min-w-0">
                <div class={[
                  "w-6 h-6 rounded-md shrink-0 flex items-center justify-center text-[10px] font-bold",
                  member_avatar_class(@selected_agent.status)
                ]}>
                  {ViewHelpers.member_initials(@selected_agent.name)}
                </div>
                <span class="font-medium text-sm truncate">{@selected_agent.name}</span>
                <span class={[
                  "text-[10px] font-medium shrink-0",
                  member_status_text(@selected_agent.status)
                ]}>
                  {@selected_agent.status}
                </span>
              </div>
              <button
                phx-click="close_agent"
                class="shrink-0 p-1 rounded hover:bg-base-200 text-base-content/40 hover:text-base-content/70 transition-colors"
              >
                <.icon name="hero-x-mark" class="w-4 h-4" />
              </button>
            </div>

            <%= if @agent_messages == [] do %>
              <div class="flex-1 flex items-center justify-center">
                <div class="text-center space-y-2">
                  <.icon
                    name="hero-chat-bubble-left-right"
                    class="w-8 h-8 text-base-content/15 mx-auto"
                  />
                  <p class="text-sm text-base-content/30">No messages</p>
                </div>
              </div>
            <% else %>
              <div class="flex-1 overflow-y-auto px-3 py-3 space-y-3" id="agent-messages-panel">
                <%= for message <- @agent_messages do %>
                  <.agent_message message={message} />
                <% end %>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp agent_message(assigns) do
    assigns = assign(assigns, :is_user, assigns.message.sender_role == "user")

    ~H"""
    <div class="flex items-start gap-2">
      <%= if @is_user do %>
        <div class="w-3.5 h-3.5 rounded-full mt-1 shrink-0 bg-success/20 flex items-center justify-center">
          <div class="w-1 h-1 rounded-full bg-success" />
        </div>
      <% else %>
        <div class="w-3.5 h-3.5 rounded-full mt-1 shrink-0 bg-primary/20 flex items-center justify-center">
          <div class="w-1 h-1 rounded-full bg-primary" />
        </div>
      <% end %>
      <div class="min-w-0 flex-1">
        <div class="flex items-baseline gap-2 mb-0.5">
          <span class={[
            "text-[11px] font-semibold",
            @is_user && "text-success/80",
            !@is_user && "text-primary/80"
          ]}>
            {if @is_user, do: "You", else: "Agent"}
          </span>
          <span class="text-[10px] text-base-content/25 font-mono">
            {ViewHelpers.format_time(@message.inserted_at)}
          </span>
        </div>
        <p class="text-xs text-base-content/70 whitespace-pre-wrap leading-relaxed break-words">
          {ViewHelpers.truncate_text(@message.body, 500)}
        </p>
      </div>
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
    team = Teams.preload_members(team)

    tasks =
      Tasks.list_tasks_for_team_with_sessions(team.id)
      |> Notes.with_notes_count()

    # Group tasks by which member session owns them
    member_session_ids = Enum.map(team.members, & &1.session_id) |> MapSet.new()

    tasks_by_session =
      Enum.reduce(tasks, %{}, fn task, acc ->
        matched_sessions = Enum.filter(task.session_ids, &MapSet.member?(member_session_ids, &1))

        case matched_sessions do
          [] ->
            acc

          sids ->
            Enum.reduce(sids, acc, fn sid, a -> Map.update(a, sid, [task], &(&1 ++ [task])) end)
        end
      end)

    unowned_tasks =
      Enum.filter(tasks, fn t ->
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

  defp clear_agent_selection(socket) do
    if socket.assigns.agent_session_id do
      EyeInTheSky.Events.unsubscribe_session(socket.assigns.agent_session_id)
    end

    socket
    |> assign(:selected_agent, nil)
    |> assign(:agent_messages, [])
    |> assign(:agent_session_id, nil)
  end

  defp active_member_count(members), do: Enum.count(members, &(&1.status == "active"))

  defp team_status_border("active"), do: "border-success"
  defp team_status_border(_), do: "border-transparent"

  defp member_status_text("active"), do: "text-success"
  defp member_status_text("idle"), do: "text-warning"
  defp member_status_text("done"), do: "text-base-content/40"
  defp member_status_text(_), do: "text-base-content/30"

  defp member_avatar_class("active"), do: "bg-success/15 text-success"
  defp member_avatar_class("idle"), do: "bg-warning/15 text-warning"
  defp member_avatar_class("done"), do: "bg-base-300 text-base-content/40"
  defp member_avatar_class(_), do: "bg-base-300 text-base-content/30"
end
