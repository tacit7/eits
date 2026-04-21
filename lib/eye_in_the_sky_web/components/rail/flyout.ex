defmodule EyeInTheSkyWeb.Components.Rail.Flyout do
  @moduledoc false
  use EyeInTheSkyWeb, :html

  attr :open, :boolean, required: true
  # On mobile (<md), the flyout is hidden even when open unless mobile_open is also true.
  # This prevents the 236px panel from compressing content on first load.
  attr :mobile_open, :boolean, default: false
  attr :active_section, :atom, required: true
  attr :sidebar_project, :any, default: nil
  attr :active_channel_id, :any, default: nil
  attr :flyout_sessions, :list, default: []
  attr :flyout_channels, :list, default: []
  attr :flyout_canvases, :list, default: []
  attr :flyout_teams, :list, default: []
  attr :flyout_tasks, :list, default: []
  attr :task_search, :string, default: ""
  attr :task_state_filter, :any, default: nil
  attr :task_filter_open, :boolean, default: false
  attr :session_filter_open, :boolean, default: false
  attr :session_sort, :atom, default: :last_activity
  attr :session_name_filter, :string, default: ""
  attr :notification_count, :integer, default: 0
  attr :myself, :any, required: true

  def flyout(assigns) do
    ~H"""
    <div
      data-flyout-panel
      class={[
        "flex flex-col border-r border-base-content/8 bg-base-100 overflow-hidden flex-shrink-0 transition-[width] duration-150",
        # w-0 is always the mobile base; md:w-[236px] overrides on desktop when open.
        # w-[236px] overrides on mobile only when mobile_open is also true.
        if(@open, do: "w-0 md:w-[236px]", else: "w-0"),
        if(@open && @mobile_open, do: "w-[236px]"),
        # On mobile, sit above the z-40 backdrop so the flyout is interactive.
        # md:z-auto resets to normal stacking on desktop where the backdrop is hidden.
        "z-50 md:z-auto"
      ]}
    >
      <div class={["flex flex-col h-full", if(!@open, do: "invisible")]}>
        <div class="px-3.5 py-3 border-b border-base-content/8 flex-shrink-0">
          <span class="text-[10px] font-semibold uppercase tracking-widest text-base-content/40">
            {section_label(@active_section)}
          </span>
        </div>

        <div class="flex-1 overflow-y-auto py-1">
          <%= case @active_section do %>
            <% :sessions -> %>
              <.sessions_content
                sessions={@flyout_sessions}
                sidebar_project={@sidebar_project}
                filter_open={@session_filter_open}
                sort={@session_sort}
                name_filter={@session_name_filter}
                myself={@myself}
              />
            <% :tasks -> %>
              <.tasks_content
                tasks={@flyout_tasks}
                task_search={@task_search}
                state_filter={@task_state_filter}
                filter_open={@task_filter_open}
                sidebar_project={@sidebar_project}
                myself={@myself}
              />
            <% :prompts -> %>
              <.nav_links project={@sidebar_project} section={:prompts} />
            <% :chat -> %>
              <.chat_content channels={@flyout_channels} active_channel_id={@active_channel_id} myself={@myself} />
            <% :notes -> %>
              <.nav_links project={@sidebar_project} section={:notes} />
            <% :skills -> %>
              <.simple_link href="/skills" label="All Skills" icon="hero-bolt" />
            <% :teams -> %>
              <.teams_content teams={@flyout_teams} sidebar_project={@sidebar_project} />
            <% :canvas -> %>
              <.canvas_content canvases={@flyout_canvases} sidebar_project={@sidebar_project} />
            <% :notifications -> %>
              <.simple_link href="/notifications" label="Notifications" icon="hero-bell" />
            <% _ -> %>
              <.nav_links project={@sidebar_project} section={:sessions} />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Sessions flyout: real data with status dots and filter bar
  attr :sessions, :list, required: true
  attr :sidebar_project, :any, default: nil
  attr :filter_open, :boolean, default: false
  attr :sort, :atom, default: :last_activity
  attr :name_filter, :string, default: ""
  attr :myself, :any, required: true

  defp sessions_content(assigns) do
    ~H"""
    <%!-- Filter toggle bar --%>
    <div class="px-3 py-2 border-b border-base-content/8 flex items-center gap-2">
      <input
        type="text"
        name="value"
        value={@name_filter}
        placeholder="Filter by name…"
        phx-change="update_session_name_filter"
        phx-target={@myself}
        phx-debounce="300"
        class="flex-1 bg-base-200 text-xs text-base-content/80 placeholder-base-content/30 rounded px-2 py-1 outline-none focus:ring-1 focus:ring-primary/40 min-w-0"
      />
      <button
        phx-click="toggle_session_filter"
        phx-target={@myself}
        title="Sort options"
        class={[
          "w-6 h-6 flex items-center justify-center rounded transition-colors flex-shrink-0",
          if(@filter_open or @sort != :last_activity,
            do: "text-primary bg-primary/10",
            else: "text-base-content/35 hover:text-base-content/70 hover:bg-base-content/8"
          )
        ]}
      >
        <.icon name="hero-bars-arrow-down-mini" class="w-3.5 h-3.5" />
      </button>
    </div>

    <%!-- Sort popup --%>
    <%= if @filter_open do %>
      <div class="px-3 py-2 border-b border-base-content/8 bg-base-200/40">
        <div class="text-[9px] font-semibold uppercase tracking-widest text-base-content/35 mb-1.5">Sort by</div>
        <div class="flex flex-col gap-0.5">
          <.sort_option label="Last activity" value="last_activity" current={@sort} myself={@myself} />
          <.sort_option label="Created" value="created" current={@sort} myself={@myself} />
          <.sort_option label="Name" value="name" current={@sort} myself={@myself} />
        </div>
      </div>
    <% end %>

    <.session_row :for={s <- @sessions} session={s} />

    <%= if @sessions == [] do %>
      <div class="px-3 py-4 text-xs text-base-content/35 text-center">No sessions</div>
    <% end %>

    <div class="px-3 pt-2 pb-1 border-t border-base-content/8 mt-1">
      <.link
        navigate={if @sidebar_project, do: "/projects/#{@sidebar_project.id}/sessions", else: "/"}
        class="text-xs text-base-content/40 hover:text-base-content/70 transition-colors"
      >
        View all &rarr;
      </.link>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :current, :atom, required: true
  attr :myself, :any, required: true

  defp sort_option(assigns) do
    ~H"""
    <button
      phx-click="set_session_sort"
      phx-value-sort={@value}
      phx-target={@myself}
      class={[
        "flex items-center gap-2 w-full text-left text-xs px-2 py-1 rounded transition-colors",
        if(to_string(@current) == @value,
          do: "text-primary bg-primary/10 font-medium",
          else: "text-base-content/55 hover:text-base-content/80 hover:bg-base-content/8"
        )
      ]}
    >
      <span class={["w-1.5 h-1.5 rounded-full flex-shrink-0", if(to_string(@current) == @value, do: "bg-primary", else: "bg-transparent")]} />
      {@label}
    </button>
    """
  end

  attr :session, :map, required: true

  defp session_row(assigns) do
    ~H"""
    <.link
      navigate={"/dm/#{@session.id}"}
      class="flex items-center gap-2 px-3 py-2 text-sm text-base-content/65 hover:text-base-content/90 hover:bg-base-content/5 transition-colors"
    >
      <span class={[
        "w-1.5 h-1.5 rounded-full flex-shrink-0",
        status_dot_class(@session.status)
      ]} />
      <span class="truncate font-medium text-xs">{@session.name || "unnamed"}</span>
      <span class="ml-auto text-[10px] text-base-content/30 flex-shrink-0">
        {format_session_time(@session)}
      </span>
    </.link>
    """
  end

  # Chat flyout: real channel list
  attr :channels, :list, default: []
  attr :active_channel_id, :any, default: nil
  attr :myself, :any, required: true

  defp chat_content(assigns) do
    ~H"""
    <%= for channel <- @channels do %>
      <% active = not is_nil(@active_channel_id) && to_string(@active_channel_id) == to_string(channel.id) %>
      <.link
        navigate={"/chat?channel_id=#{channel.id}"}
        class={[
          "flex items-center gap-2 px-3 py-2 text-sm transition-colors",
          if(active,
            do: "text-primary bg-primary/8 font-medium",
            else: "text-base-content/60 hover:text-base-content/85 hover:bg-base-content/5"
          )
        ]}
      >
        <span class={["text-[13px] flex-shrink-0", if(active, do: "text-primary/60", else: "text-base-content/25")]}>
          #
        </span>
        <span class="truncate">{channel.name}</span>
      </.link>
    <% end %>
    <%= if @channels == [] do %>
      <div class="px-3 py-4 text-xs text-base-content/35 text-center">No channels</div>
    <% end %>
    """
  end

  # Tasks flyout: list tasks with search and state filter
  attr :tasks, :list, default: []
  attr :task_search, :string, default: ""
  attr :state_filter, :any, default: nil
  attr :filter_open, :boolean, default: false
  attr :sidebar_project, :any, default: nil
  attr :myself, :any, required: true

  defp tasks_content(assigns) do
    ~H"""
    <div class="px-3 pt-2 pb-1.5 border-b border-base-content/8 flex items-center gap-3">
      <.link navigate="/tasks" class="text-xs text-base-content/50 hover:text-base-content/80 transition-colors">All</.link>
      <.link
        navigate={if @sidebar_project, do: "/projects/#{@sidebar_project.id}/tasks", else: "/tasks"}
        class="text-xs text-base-content/50 hover:text-base-content/80 transition-colors"
      >List</.link>
      <%= if @sidebar_project do %>
        <.link
          navigate={"/projects/#{@sidebar_project.id}/kanban"}
          class="text-xs text-base-content/50 hover:text-base-content/80 transition-colors"
        >Kanban</.link>
      <% end %>
    </div>

    <div class="px-3 py-2 border-b border-base-content/8 flex items-center gap-2">
      <input
        type="text"
        name="value"
        value={@task_search}
        placeholder="Search tasks…"
        phx-change="update_task_search"
        phx-target={@myself}
        phx-debounce="300"
        class="flex-1 bg-base-200 text-xs text-base-content/80 placeholder-base-content/30 rounded px-2 py-1 outline-none focus:ring-1 focus:ring-primary/40 min-w-0"
      />
      <button
        phx-click="toggle_task_filter"
        phx-target={@myself}
        title="Filter by state"
        class={[
          "w-6 h-6 flex items-center justify-center rounded transition-colors flex-shrink-0",
          if(@filter_open or not is_nil(@state_filter),
            do: "text-primary bg-primary/10",
            else: "text-base-content/35 hover:text-base-content/70 hover:bg-base-content/8"
          )
        ]}
      >
        <.icon name="hero-funnel-mini" class="w-3.5 h-3.5" />
      </button>
    </div>

    <%= if @filter_open do %>
      <div class="px-3 py-2 border-b border-base-content/8 bg-base-200/40">
        <div class="text-[9px] font-semibold uppercase tracking-widest text-base-content/35 mb-1.5">State</div>
        <div class="flex flex-col gap-0.5">
          <.task_state_option label="All" value="all" current={@state_filter} myself={@myself} />
          <.task_state_option label="To Do" value="1" current={@state_filter} myself={@myself} />
          <.task_state_option label="In Progress" value="2" current={@state_filter} myself={@myself} />
          <.task_state_option label="In Review" value="4" current={@state_filter} myself={@myself} />
          <.task_state_option label="Done" value="3" current={@state_filter} myself={@myself} />
        </div>
      </div>
    <% end %>

    <.task_row :for={t <- @tasks} task={t} />

    <%= if @tasks == [] do %>
      <div class="px-3 py-4 text-xs text-base-content/35 text-center">No tasks</div>
    <% end %>

    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :current, :any, default: nil
  attr :myself, :any, required: true

  defp task_state_option(assigns) do
    ~H"""
    <% active = (@value == "all" and is_nil(@current)) or to_string(@current) == @value %>
    <button
      phx-click="set_task_state_filter"
      phx-value-state={@value}
      phx-target={@myself}
      class={[
        "flex items-center gap-2 w-full text-left text-xs px-2 py-1 rounded transition-colors",
        if(active,
          do: "text-primary bg-primary/10 font-medium",
          else: "text-base-content/55 hover:text-base-content/80 hover:bg-base-content/8"
        )
      ]}
    >
      <span class={["w-1.5 h-1.5 rounded-full flex-shrink-0", if(active, do: "bg-primary", else: "bg-transparent")]} />
      {@label}
    </button>
    """
  end

  attr :task, :map, required: true

  defp task_row(assigns) do
    ~H"""
    <.link
      navigate="/tasks"
      class="flex items-center gap-2 px-3 py-2 text-xs text-base-content/65 hover:text-base-content/90 hover:bg-base-content/5 transition-colors"
    >
      <span class={["w-1.5 h-1.5 rounded-full flex-shrink-0 mt-px", task_state_dot(@task.state_id)]} />
      <span class="truncate">{@task.title}</span>
    </.link>
    """
  end

  defp task_state_dot(1), do: "bg-base-content/30"
  defp task_state_dot(2), do: "bg-blue-500"
  defp task_state_dot(3), do: "bg-green-500"
  defp task_state_dot(4), do: "bg-amber-400"
  defp task_state_dot(_), do: "bg-base-content/20"

  # Teams flyout: list teams for the current project
  attr :teams, :list, default: []
  attr :sidebar_project, :any, default: nil

  defp teams_content(assigns) do
    ~H"""
    <div class="px-3 pt-2 pb-1">
      <.link
        navigate="/teams"
        class="text-xs text-base-content/40 hover:text-base-content/70 transition-colors"
      >
        All Teams &rarr;
      </.link>
    </div>
    <%= if @teams == [] do %>
      <div class="px-3 py-4 text-xs text-base-content/35 text-center">No teams</div>
    <% end %>
    <%= for team <- @teams do %>
      <.link
        navigate="/teams"
        class="flex items-center gap-2 px-3 py-2 text-sm text-base-content/65 hover:text-base-content/90 hover:bg-base-content/5 transition-colors"
      >
        <.icon name="hero-users" class="w-3 h-3 flex-shrink-0 text-base-content/30" />
        <span class="truncate text-xs font-medium">{team.name}</span>
        <span class="ml-auto text-[10px] text-base-content/30 flex-shrink-0">
          {length(team.members)}
        </span>
      </.link>
    <% end %>
    """
  end

  # Canvas flyout: canvases with their sessions
  attr :canvases, :list, default: []
  attr :sidebar_project, :any, default: nil

  defp canvas_content(assigns) do
    ~H"""
    <div class="px-3 pt-2 pb-1">
      <.link
        navigate={canvas_base_url(@sidebar_project)}
        class="text-xs text-base-content/40 hover:text-base-content/70 transition-colors"
      >
        All Canvases &rarr;
      </.link>
    </div>
    <%= if @canvases == [] do %>
      <div class="px-3 py-4 text-xs text-base-content/35 text-center">No canvases</div>
    <% end %>
    <%= for canvas <- @canvases do %>
      <.link
        navigate={canvas_url(@sidebar_project, canvas.id)}
        class="flex items-center gap-2 px-3 py-1.5 text-sm text-base-content/70 hover:text-base-content/90 hover:bg-base-content/5 transition-colors"
      >
        <.icon name="hero-squares-2x2" class="w-3 h-3 flex-shrink-0 text-base-content/30" />
        <span class="truncate font-medium text-xs">{canvas.name}</span>
      </.link>
      <%= for session <- canvas.sessions do %>
        <div class="flex items-center hover:bg-base-content/5 transition-colors group">
          <.link
            navigate={canvas_url(@sidebar_project, canvas.id, session.id)}
            class="flex items-center gap-2 pl-7 py-1 flex-1 min-w-0 text-xs text-base-content/50 group-hover:text-base-content/80"
          >
            <span class={["w-1.5 h-1.5 rounded-full flex-shrink-0", canvas_session_dot(session.status)]} />
            <span class="truncate">{session.name || "unnamed"}</span>
          </.link>
          <.link
            navigate={"/dm/#{session.id}"}
            class={["flex-shrink-0 px-3 py-1 transition-opacity hover:opacity-80", if(session.status == "working", do: "opacity-80", else: "opacity-30")]}
            title="Open DM"
          >
            <img
              src={canvas_provider_icon(session.provider)}
              class={["w-3.5 h-3.5", canvas_provider_icon_class(session.provider), session.status == "working" && "animate-pulse"]}
              alt={session.provider || "agent"}
            />
          </.link>
        </div>
      <% end %>
      <%= if canvas.sessions == [] do %>
        <div class="pl-7 pr-3 py-1 text-[10px] text-base-content/30">no sessions</div>
      <% end %>
    <% end %>
    """
  end

  defp canvas_session_dot("working"), do: "bg-green-500"
  defp canvas_session_dot("waiting"), do: "bg-amber-400"
  defp canvas_session_dot(_), do: "bg-base-content/20"

  defp canvas_provider_icon("openai"), do: "/images/openai.svg"
  defp canvas_provider_icon("codex"), do: "/images/openai.svg"
  defp canvas_provider_icon(_), do: "/images/claude.svg"

  defp canvas_provider_icon_class("openai"), do: "dark:invert"
  defp canvas_provider_icon_class("codex"), do: "dark:invert"
  defp canvas_provider_icon_class(_), do: ""

  # Generic nav links per section
  attr :project, :any, default: nil
  attr :section, :atom, required: true

  defp nav_links(%{section: :tasks} = assigns) do
    ~H"""
    <.simple_link href="/tasks" label="All Tasks" icon="hero-clipboard-document-list" />
    <%= if @project do %>
      <.simple_link
        href={"/projects/#{@project.id}/kanban"}
        label={"#{@project.name} Board"}
        icon="hero-squares-2x2"
      />
    <% end %>
    """
  end

  defp nav_links(%{section: :prompts} = assigns) do
    ~H"""
    <.simple_link href="/prompts" label="All Prompts" icon="hero-chat-bubble-left-right" />
    <%= if @project do %>
      <.simple_link
        href={"/projects/#{@project.id}/prompts"}
        label={"#{@project.name} Prompts"}
        icon="hero-folder"
      />
    <% end %>
    """
  end

  defp nav_links(%{section: :notes} = assigns) do
    ~H"""
    <.simple_link href="/notes" label="All Notes" icon="hero-document-text" />
    <%= if @project do %>
      <.simple_link
        href={"/projects/#{@project.id}/notes"}
        label={"#{@project.name} Notes"}
        icon="hero-folder"
      />
    <% end %>
    """
  end

  defp nav_links(%{section: :sessions} = assigns) do
    ~H"""
    <.simple_link href="/" label="All Sessions" icon="hero-cpu-chip" />
    <%= if @project do %>
      <.simple_link
        href={"/projects/#{@project.id}/sessions"}
        label={"#{@project.name} Sessions"}
        icon="hero-folder"
      />
    <% end %>
    """
  end

  attr :href, :string, required: true
  attr :label, :string, required: true
  attr :icon, :string, required: true

  defp simple_link(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class="flex items-center gap-2.5 px-3 py-2.5 text-sm text-base-content/60 hover:text-base-content/85 hover:bg-base-content/5 transition-colors"
    >
      <.icon name={@icon} class="w-3.5 h-3.5 flex-shrink-0" />
      <span class="truncate">{@label}</span>
    </.link>
    """
  end

  defp section_label(:sessions), do: "Sessions"
  defp section_label(:tasks), do: "Tasks"
  defp section_label(:prompts), do: "Prompts"
  defp section_label(:chat), do: "Chat"
  defp section_label(:notes), do: "Notes"
  defp section_label(:skills), do: "Skills"
  defp section_label(:teams), do: "Teams"
  defp section_label(:canvas), do: "Canvas"
  defp section_label(:notifications), do: "Notifications"
  defp section_label(_), do: "Navigation"

  defp status_dot_class("working"), do: "bg-green-500"
  defp status_dot_class("waiting"), do: "bg-amber-400"
  defp status_dot_class(_), do: "bg-base-content/25"

  # Session.last_activity_at is :utc_datetime_usec — Ecto returns %DateTime{} structs.
  # Binary fallback handles any edge cases (cached data, API responses, etc.)
  defp format_session_time(%{last_activity_at: %DateTime{} = dt}) do
    diff = max(DateTime.diff(DateTime.utc_now(), dt, :second), 0)

    cond do
      diff < 60 -> "#{diff}s"
      diff < 3600 -> "#{div(diff, 60)}m"
      diff < 86_400 -> "#{div(diff, 3600)}h"
      true -> "#{div(diff, 86_400)}d"
    end
  end

  defp format_session_time(%{last_activity_at: %NaiveDateTime{} = ndt}) do
    ndt
    |> DateTime.from_naive!("Etc/UTC")
    |> then(&format_session_time(%{last_activity_at: &1}))
  end

  defp format_session_time(%{last_activity_at: ts}) when is_binary(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} -> format_session_time(%{last_activity_at: dt})
      _ -> ""
    end
  end

  defp format_session_time(_), do: ""

  # Canvas URL helpers — preserve project context as a query param so CanvasLive
  # can restore sidebar_project on mount, keeping the Kanban link visible.
  defp canvas_base_url(nil), do: "/canvases"
  defp canvas_base_url(project), do: "/canvases?project_id=#{project.id}"

  defp canvas_url(nil, canvas_id), do: "/canvases/#{canvas_id}"
  defp canvas_url(project, canvas_id), do: "/canvases/#{canvas_id}?project_id=#{project.id}"

  defp canvas_url(nil, canvas_id, focus_id), do: "/canvases/#{canvas_id}?focus=#{focus_id}"
  defp canvas_url(project, canvas_id, focus_id), do: "/canvases/#{canvas_id}?project_id=#{project.id}&focus=#{focus_id}"
end
