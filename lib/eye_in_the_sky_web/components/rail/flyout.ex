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
  attr :flyout_agents, :list, default: []
  attr :flyout_notes, :list, default: []
  attr :flyout_jobs, :list, default: []
  attr :flyout_file_nodes, :list, default: []
  attr :flyout_file_expanded, :any, default: nil
  attr :flyout_file_children, :map, default: %{}
  attr :flyout_file_error, :string, default: nil
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
        <div class="px-2.5 py-2.5 border-b border-base-content/8 flex-shrink-0 flex items-center gap-1">
          <%!-- Icon + label: agents always links to /agents; dual-page sections link to project route when available --%>
          <%= cond do %>
            <% @active_section == :agents -> %>
              <.link
                navigate={agents_route(@sidebar_project)}
                class="flex-1 min-w-0 flex items-center gap-1.5 rounded hover:bg-base-content/5 -mx-1 px-1 py-0.5 transition-colors group"
              >
                <span class="flex-shrink-0 flex items-center justify-center text-base-content/35 group-hover:text-base-content/60 transition-colors">
                  <.custom_icon name="lucide-robot" class="size-3.5" />
                </span>
                <span class="text-micro font-semibold uppercase tracking-widest text-base-content/40 group-hover:text-base-content/60 truncate transition-colors">
                  Agents
                </span>
              </.link>
            <% dual_page_section?(@active_section) && project_route_for(@active_section, @sidebar_project) -> %>
              <.link
                navigate={project_route_for(@active_section, @sidebar_project)}
                title={"#{@sidebar_project.name} #{section_label(@active_section)}"}
                class="flex-1 min-w-0 flex items-center gap-1.5 rounded hover:bg-base-content/5 -mx-1 px-1 py-0.5 transition-colors group"
              >
                <span class="flex-shrink-0 flex items-center justify-center text-base-content/35 group-hover:text-base-content/60 transition-colors">
                  <%= if @active_section == :tasks do %>
                    <.custom_icon name="lucide-kanban" class="size-3.5" />
                  <% else %>
                    <.icon name="hero-list-bullet" class="size-3.5" />
                  <% end %>
                </span>
                <span class="text-micro font-semibold uppercase tracking-widest text-base-content/40 group-hover:text-base-content/60 truncate transition-colors">
                  {section_label(@active_section)}
                </span>
              </.link>
            <% true -> %>
              <div class="flex-1 min-w-0 flex items-center gap-1.5">
                <%= if dual_page_section?(@active_section) do %>
                  <span class="flex-shrink-0 flex items-center justify-center text-base-content/20">
                    <%= if @active_section == :tasks do %>
                      <.custom_icon name="lucide-kanban" class="size-3.5" />
                    <% else %>
                      <.icon name="hero-list-bullet" class="size-3.5" />
                    <% end %>
                  </span>
                <% end %>
                <span class="text-micro font-semibold uppercase tracking-widest text-base-content/40 truncate">
                  {section_label(@active_section)}
                </span>
              </div>
          <% end %>
          <%= if @active_section == :notes do %>
            <button
              phx-click="new_note"
              phx-target={@myself}
              title="New note"
              class="size-5 flex items-center justify-center rounded text-base-content/35 hover:text-base-content/70 hover:bg-base-content/8 transition-colors flex-shrink-0"
            >
              <.icon name="hero-plus-mini" class="size-3.5" />
            </button>
          <% end %>
          <%= if @active_section == :sessions do %>
            <%= if @sidebar_project do %>
              <button
                phx-click="new_session"
                phx-value-project_id={@sidebar_project.id}
                phx-target={@myself}
                title={"New session in #{@sidebar_project.name}"}
                class="size-5 flex items-center justify-center rounded text-base-content/35 hover:text-base-content/70 hover:bg-base-content/8 transition-colors flex-shrink-0"
              >
                <.icon name="hero-plus-mini" class="size-3.5" />
              </button>
            <% else %>
              <button
                phx-click="toggle_new_session_form"
                phx-target={@myself}
                title="New agent"
                class="size-5 flex items-center justify-center rounded text-base-content/35 hover:text-base-content/70 hover:bg-base-content/8 transition-colors flex-shrink-0"
              >
                <.icon name="hero-plus-mini" class="size-3.5" />
              </button>
            <% end %>
          <% end %>
        </div>

        <div class="flex-1 overflow-y-auto py-1">
          <%= case @active_section do %>
            <% :sessions -> %>
              <.sessions_content
                sessions={@flyout_sessions}
                sidebar_project={@sidebar_project}
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
              <.notes_content notes={@flyout_notes} />
            <% :skills -> %>
              <.simple_link href="/skills" label="All Skills" icon="hero-bolt" />
            <% :teams -> %>
              <.teams_content teams={@flyout_teams} sidebar_project={@sidebar_project} />
            <% :canvas -> %>
              <.canvas_content canvases={@flyout_canvases} />
            <% :agents -> %>
              <.agents_content agents={@flyout_agents} myself={@myself} />
            <% :notifications -> %>
              <.simple_link href="/notifications" label="Notifications" icon="hero-bell" />
            <% :usage -> %>
              <.usage_content />
            <% :jobs -> %>
              <.jobs_content jobs={@flyout_jobs} sidebar_project={@sidebar_project} />
            <% :files -> %>
              <.files_content
                file_nodes={@flyout_file_nodes}
                file_expanded={@flyout_file_expanded || MapSet.new()}
                file_children={@flyout_file_children}
                file_error={@flyout_file_error}
                sidebar_project={@sidebar_project}
                myself={@myself}
              />
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

  defp sessions_content(assigns) do
    ~H"""
    <.session_row :for={s <- @sessions} session={s} />

    <%= if @sessions == [] do %>
      <div class="px-3 py-4 text-xs text-base-content/35 text-center">No sessions</div>
    <% end %>

    """
  end

  attr :session, :map, required: true

  defp session_row(assigns) do
    ~H"""
    <.link
      navigate={"/dm/#{@session.id}"}
      class="flex items-center gap-2 px-3 py-2 text-sm text-base-content/65 hover:text-base-content/90 hover:bg-base-content/5 transition-colors"
    >
      <.status_dot status={@session.status} size="xs" />
      <span class="truncate font-medium text-xs">{@session.name || "unnamed"}</span>
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

    <%= if @filter_open do %>
      <div class="px-3 py-2 border-b border-base-content/8 bg-base-200/40">
        <div class="text-nano font-semibold uppercase tracking-widest text-base-content/35 mb-1.5">State</div>
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
      <% filtering = @task_search != "" or not is_nil(@state_filter) %>
      <div class="px-3 py-4 text-xs text-base-content/35 text-center">
        {if filtering, do: "No matching tasks", else: "No tasks"}
      </div>
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
      navigate={if @task.project_id, do: "/projects/#{@task.project_id}/tasks?task_id=#{@task.id}", else: "/projects"}
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

  # Notes flyout: last 20 notes with body preview
  attr :notes, :list, default: []

  defp notes_content(assigns) do
    ~H"""
    <%= for note <- @notes do %>
      <% label = note.title || String.slice(note.body || "", 0, 60) %>
      <% preview = if note.title && note.title != "", do: note.body %>
      <.link
        navigate={"/notes/#{note.id}/edit"}
        class="flex flex-col gap-0.5 px-3 py-2 text-xs text-base-content/65 hover:text-base-content/90 hover:bg-base-content/5 transition-colors"
      >
        <span class={["truncate", if(note.title && note.title != "", do: "font-medium text-base-content/80")]}>
          {if label == "", do: "(empty)", else: label}
        </span>
        <span :if={preview && preview != ""} class="truncate text-base-content/40">{preview}</span>
        <span class="text-micro text-base-content/30 uppercase tracking-wide">{note.parent_type}</span>
      </.link>
    <% end %>
    <%= if @notes == [] do %>
      <div class="px-3 py-4 text-xs text-base-content/35 text-center">No notes</div>
    <% end %>
    """
  end

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
        <.icon name="hero-users" class="size-3 flex-shrink-0 text-base-content/30" />
        <span class="truncate text-xs font-medium">{team.name}</span>
        <span class="ml-auto text-micro text-base-content/30 flex-shrink-0">
          {length(team.members)}
        </span>
      </.link>
    <% end %>
    """
  end

  # Canvas flyout: canvases with their sessions
  attr :canvases, :list, default: []

  defp canvas_content(assigns) do
    ~H"""
    <div class="px-3 pt-2 pb-1">
      <.link
        navigate="/canvases"
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
        navigate={"/canvases/#{canvas.id}"}
        class="flex items-center gap-2 px-3 py-1.5 text-sm text-base-content/70 hover:text-base-content/90 hover:bg-base-content/5 transition-colors"
      >
        <.icon name="hero-squares-2x2" class="size-3 flex-shrink-0 text-base-content/30" />
        <span class="truncate font-medium text-xs">{canvas.name}</span>
      </.link>
      <%= for session <- canvas.sessions do %>
        <div class="flex items-center hover:bg-base-content/5 transition-colors group">
          <.link
            navigate={"/canvases/#{canvas.id}?focus=#{session.id}"}
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
              class={["size-3.5", canvas_provider_icon_class(session.provider), session.status == "working" && "animate-pulse"]}
              alt={session.provider || "agent"}
            />
          </.link>
        </div>
      <% end %>
      <%= if canvas.sessions == [] do %>
        <div class="pl-7 pr-3 py-1 text-micro text-base-content/30">no sessions</div>
      <% end %>
    <% end %>
    """
  end

  defp canvas_session_dot("working"), do: "bg-green-500"
  defp canvas_session_dot("waiting"), do: "bg-amber-400"
  defp canvas_session_dot(_), do: "bg-base-content/20"

  defp canvas_provider_icon("openai"), do: "/images/openai.svg"
  defp canvas_provider_icon("codex"), do: "/images/openai.svg"
  defp canvas_provider_icon("gemini"), do: "/images/gemini.svg"
  defp canvas_provider_icon(_), do: "/images/claude.svg"

  defp canvas_provider_icon_class("openai"), do: "dark:invert"
  defp canvas_provider_icon_class("codex"), do: "dark:invert"
  defp canvas_provider_icon_class("gemini"), do: ""
  defp canvas_provider_icon_class(_), do: ""

  # Generic nav links per section
  attr :project, :any, default: nil
  attr :section, :atom, required: true

  defp nav_links(%{project: nil} = assigns) do
    ~H"""
    <div class="px-3 py-4 text-xs text-base-content/35 text-center">Select a project</div>
    """
  end

  defp nav_links(%{section: :tasks} = assigns) do
    ~H"""
      <.simple_link
        href={"/projects/#{@project.id}/kanban"}
        label={"#{@project.name} Board"}
        icon="hero-squares-2x2"
      />
    """
  end

  defp nav_links(%{section: :prompts} = assigns) do
    ~H"""
      <.simple_link
        href={"/projects/#{@project.id}/prompts"}
        label={"#{@project.name} Prompts"}
        icon="hero-folder"
      />
    """
  end

  defp nav_links(%{section: :notes} = assigns) do
    ~H"""
      <.simple_link
        href={"/projects/#{@project.id}/notes"}
        label={"#{@project.name} Notes"}
        icon="hero-folder"
      />
    """
  end

  defp nav_links(%{section: :sessions} = assigns) do
    ~H"""
    <.simple_link
      href={"/projects/#{@project.id}/sessions"}
      label="List"
      icon="hero-list-bullet"
    />
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
      <.icon name={@icon} class="size-3.5 flex-shrink-0" />
      <span class="truncate">{@label}</span>
    </.link>
    """
  end

  # Agents flyout: list of agent definitions scoped to the selected project (or global)
  attr :agents, :list, default: []
  attr :myself, :any, required: true

  defp agents_content(assigns) do
    ~H"""
    <.agent_row :for={agent <- @agents} agent={agent} myself={@myself} />
    <%= if @agents == [] do %>
      <div class="px-3 py-4 text-xs text-base-content/35 text-center">No agents</div>
    <% end %>
    """
  end

  attr :agent, :map, required: true
  attr :myself, :any, required: true

  defp agent_row(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="open_new_session_with_agent"
      phx-value-slug={@agent.slug}
      phx-value-name={@agent.name || @agent.slug}
      phx-target={@myself}
      class="w-full flex items-center gap-2 px-3 py-2 text-sm text-base-content/65 hover:text-base-content/90 hover:bg-base-content/5 transition-colors text-left"
    >
      <.custom_icon name="lucide-robot" class="size-3 flex-shrink-0 text-base-content/30" />
      <span class="truncate text-xs font-medium">{@agent.name || @agent.slug}</span>
    </button>
    """
  end

  # Usage flyout: links to the usage dashboard
  defp usage_content(assigns) do
    ~H"""
    <.simple_link href="/usage" label="Usage Dashboard" icon="hero-chart-bar" />
    """
  end

  # Jobs flyout: list of scheduled jobs with name, schedule, and enabled state
  attr :jobs, :list, default: []
  attr :sidebar_project, :any, default: nil

  defp jobs_content(assigns) do
    ~H"""
    <div class="px-3 pt-2 pb-1 border-b border-base-content/8 flex items-center gap-3">
      <.link navigate="/jobs" class="text-xs text-base-content/50 hover:text-base-content/80 transition-colors">All Jobs</.link>
      <%= if @sidebar_project do %>
        <.link navigate={"/projects/#{@sidebar_project.id}/jobs"} class="text-xs text-base-content/50 hover:text-base-content/80 transition-colors">Project Jobs</.link>
      <% end %>
    </div>

    <%= for job <- @jobs do %>
      <.link
        navigate="/jobs"
        class="flex items-center gap-2 px-3 py-2 text-xs text-base-content/65 hover:text-base-content/90 hover:bg-base-content/5 transition-colors"
      >
        <span class={[
          "w-1.5 h-1.5 rounded-full flex-shrink-0",
          if(job.enabled, do: "bg-green-500", else: "bg-base-content/20")
        ]} />
        <span class="truncate font-medium flex-1">{job.name}</span>
        <span class="text-micro text-base-content/30 flex-shrink-0 font-mono">{job.schedule_value}</span>
      </.link>
    <% end %>

    <%= if @jobs == [] do %>
      <div class="px-3 py-4 text-xs text-base-content/35 text-center">No jobs</div>
    <% end %>
    """
  end

  # Files flyout: expand/collapse tree backed by FileTree service
  attr :file_nodes, :list, default: []
  attr :file_expanded, :any, default: nil
  attr :file_children, :map, default: %{}
  attr :file_error, :string, default: nil
  attr :sidebar_project, :any, default: nil
  attr :myself, :any, required: true

  defp files_content(assigns) do
    assigns =
      assign(
        assigns,
        :flat_rows,
        flatten_file_tree(
          assigns.file_nodes,
          assigns.file_children,
          assigns.file_expanded || MapSet.new(),
          0
        )
      )

    ~H"""
    <%= if is_nil(@sidebar_project) || is_nil(@sidebar_project.path) do %>
      <div class="px-3 py-4 text-xs text-base-content/35 text-center">No project path configured</div>
    <% else %>
      <%!-- Error state --%>
      <%= if @file_error do %>
        <div class="px-3 py-2 text-xs text-error/70">{@file_error}</div>
      <% end %>

      <%!-- Tree rows --%>
      <%= for {node, depth} <- @flat_rows do %>
        <% indent = depth * 12 %>
        <%= case node.type do %>
          <% :directory -> %>
            <% expanded = MapSet.member?(@file_expanded, node.path) %>
            <button
              phx-click={if expanded, do: "file_collapse", else: "file_expand"}
              phx-value-path={node.path}
              phx-target={@myself}
              class="w-full flex items-center gap-1.5 pr-3 py-[3px] text-left text-xs text-base-content/70 hover:text-base-content/90 hover:bg-base-content/5 transition-colors"
              style={"padding-left: #{indent + 8}px"}
            >
              <.icon
                name={if expanded, do: "hero-chevron-down-mini", else: "hero-chevron-right-mini"}
                class="size-3 text-base-content/30 flex-shrink-0"
              />
              <.icon name={if expanded, do: "hero-folder-open-mini", else: "hero-folder-mini"} class="size-3.5 text-base-content/40 flex-shrink-0" />
              <span class="truncate">{node.name}</span>
            </button>
          <% :file -> %>
            <button
              phx-click="file_open"
              phx-value-path={node.path}
              phx-target={@myself}
              class="w-full flex items-center gap-1.5 pr-3 py-[3px] text-left text-xs text-base-content/55 hover:text-base-content/85 hover:bg-base-content/5 transition-colors"
              style={"padding-left: #{indent + 20}px"}
            >
              <%= if node.sensitive? do %>
                <.icon name="hero-lock-closed-mini" class="size-3.5 text-warning/50 flex-shrink-0" />
              <% else %>
                <.icon name="hero-document-mini" class="size-3.5 text-base-content/20 flex-shrink-0" />
              <% end %>
              <span class="truncate">{node.name}</span>
            </button>
          <% :warning -> %>
            <div class="px-3 py-1 text-micro text-base-content/25 italic" style={"padding-left: #{indent + 8}px"}>{node.name}</div>
          <% _ -> %>
        <% end %>
      <% end %>

      <%= if @flat_rows == [] && is_nil(@file_error) do %>
        <div class="px-3 py-4 text-xs text-base-content/35 text-center">Empty</div>
      <% end %>

      <%!-- Footer --%>
      <div class="border-t border-base-content/8 mt-2">
        <.simple_link
          href={"/projects/#{@sidebar_project.id}/files"}
          label="Open File Browser"
          icon="hero-arrow-top-right-on-square"
        />
      </div>
    <% end %>
    """
  end

  defp flatten_file_tree(nodes, children_cache, expanded, depth) do
    Enum.flat_map(nodes, fn node ->
      if node.type == :directory && MapSet.member?(expanded, node.path) do
        kids = Map.get(children_cache, node.path, [])
        [{node, depth} | flatten_file_tree(kids, children_cache, expanded, depth + 1)]
      else
        [{node, depth}]
      end
    end)
  end

  defp section_label(:agents), do: "Agents"
  defp section_label(:sessions), do: "Sessions"
  defp section_label(:tasks), do: "Tasks"
  defp section_label(:prompts), do: "Prompts"
  defp section_label(:chat), do: "Chat"
  defp section_label(:notes), do: "Notes"
  defp section_label(:skills), do: "Skills"
  defp section_label(:teams), do: "Teams"
  defp section_label(:canvas), do: "Canvas"
  defp section_label(:notifications), do: "Notifications"
  defp section_label(:usage), do: "Usage"
  defp section_label(:jobs), do: "Jobs"
  defp section_label(:files), do: "Files"
  defp section_label(_), do: "Navigation"

  # Sections that have both a global page and a project-scoped page.
  # These get the list icon header treatment.
  defp dual_page_section?(section),
    do: section in [:sessions, :tasks, :prompts, :notes, :skills, :jobs]

  defp agents_route(%{id: id}), do: "/projects/#{id}/agents"
  defp agents_route(_), do: "/agents"

  # Returns the project-scoped route for a section, or nil if none exists
  # or no project is selected.
  defp project_route_for(:sessions, %{id: id}), do: "/projects/#{id}/sessions"
  defp project_route_for(:tasks, %{id: id}), do: "/projects/#{id}/kanban"
  defp project_route_for(:prompts, %{id: id}), do: "/projects/#{id}/prompts"
  defp project_route_for(:notes, %{id: id}), do: "/projects/#{id}/notes"
  defp project_route_for(:jobs, %{id: id}), do: "/projects/#{id}/jobs"
  defp project_route_for(_, _), do: nil

end
