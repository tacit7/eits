defmodule EyeInTheSkyWeb.ProjectLive.Show do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.Agents
  alias EyeInTheSky.Commits
  alias EyeInTheSky.Notes
  alias EyeInTheSky.Projects
  alias EyeInTheSky.Sessions
  alias EyeInTheSky.Tasks
  alias EyeInTheSkyWeb.Live.Shared.NotificationHelpers
  import EyeInTheSkyWeb.Helpers.ViewHelpers, only: [relative_time: 1, truncate_text: 1]
  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    project_id = parse_int(id)

    socket =
      if project_id do
        project = Projects.get_project!(project_id)

        socket =
          socket
          |> assign(:page_title, "Project: #{project.name}")
          |> assign(:project, project)
          |> assign(:sidebar_tab, :overview)
          |> assign(:sidebar_project, project)
          |> assign_empty_project_data()

        if connected?(socket) do
          tasks = Tasks.list_tasks_for_project(project_id)

          active_sessions =
            Sessions.list_project_sessions_with_agent(project_id, active_only: true, limit: 5)

          recent_notes = Notes.list_notes_for_project(project_id, limit: 5)
          {agent_count, working_agent_count} = Agents.count_agents_for_project(project_id)
          {session_count, session_ids} = Sessions.count_and_ids_for_project(project_id)
          recent_commits = Commits.list_commits_for_sessions(session_ids, limit: 10)
          open_tasks = Enum.count(tasks, &is_nil(&1.completed_at))
          done_tasks = Enum.count(tasks, & &1.completed_at)
          claude_files = scan_claude_files(project.path)

          recent_tasks =
            tasks
            |> Enum.sort_by(& &1.created_at, {:desc, DateTime})
            |> Enum.take(5)

          socket
          |> assign(:tasks, tasks)
          |> assign(:recent_tasks, recent_tasks)
          |> assign(:active_sessions, active_sessions)
          |> assign(:recent_notes, recent_notes)
          |> assign(:agent_count, agent_count)
          |> assign(:working_agent_count, working_agent_count)
          |> assign(:session_count, session_count)
          |> assign(:recent_commits, recent_commits)
          |> assign(:open_tasks, open_tasks)
          |> assign(:done_tasks, done_tasks)
          |> assign(:claude_files, claude_files)
        else
          socket
        end
      else
        socket
        |> assign(:page_title, "Project Not Found")
        |> assign(:project, nil)
        |> assign(:sidebar_tab, :overview)
        |> assign(:sidebar_project, nil)
        |> assign_empty_project_data()
        |> put_flash(:error, "Invalid project ID")
      end

    {:ok, socket}
  end

  defp assign_empty_project_data(socket) do
    socket
    |> assign(:tasks, [])
    |> assign(:recent_tasks, [])
    |> assign(:active_sessions, [])
    |> assign(:recent_notes, [])
    |> assign(:agent_count, 0)
    |> assign(:working_agent_count, 0)
    |> assign(:session_count, 0)
    |> assign(:recent_commits, [])
    |> assign(:open_tasks, 0)
    |> assign(:done_tasks, 0)
    |> assign(:claude_files, [])
  end

  @impl true
  def handle_event("set_notify_on_stop", params, socket),
    do: {:noreply, NotificationHelpers.set_notify_on_stop(socket, params)}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8 py-4">
      <div class="max-w-7xl mx-auto">
        <!-- Stats bar -->
        <div class="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-4">
          <div class="card bg-base-100 shadow-sm">
            <div class="card-body p-3">
              <p class="text-xs text-base-content/50 uppercase tracking-wider">Sessions</p>
              <p class="text-2xl font-semibold text-base-content">{@session_count}</p>
              <p class="text-xs text-base-content/40">{length(@active_sessions)} active</p>
            </div>
          </div>
          <div class="card bg-base-100 shadow-sm">
            <div class="card-body p-3">
              <p class="text-xs text-base-content/50 uppercase tracking-wider">Tasks</p>
              <p class="text-2xl font-semibold text-base-content">{length(@tasks)}</p>
              <p class="text-xs text-base-content/40">{@open_tasks} open · {@done_tasks} done</p>
            </div>
          </div>
          <div class="card bg-base-100 shadow-sm">
            <div class="card-body p-3">
              <p class="text-xs text-base-content/50 uppercase tracking-wider">Agents</p>
              <p class="text-2xl font-semibold text-base-content">{@agent_count}</p>
              <p class="text-xs text-base-content/40">
                {@working_agent_count} running
              </p>
            </div>
          </div>
          <div class="card bg-base-100 shadow-sm">
            <div class="card-body p-3">
              <p class="text-xs text-base-content/50 uppercase tracking-wider">Commits</p>
              <p class="text-2xl font-semibold text-base-content">{length(@recent_commits)}</p>
              <p class="text-xs text-base-content/40">recent</p>
            </div>
          </div>
        </div>
        
    <!-- Responsive Grid Layout -->
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
          <!-- Claude Files -->
          <div class="card bg-base-100 shadow-sm">
            <div class="card-body p-4">
              <h2 class="card-title text-base mb-2">Claude Files</h2>
              <%= if @project.path do %>
                <div class="mb-2 pb-2 border-b border-base-300">
                  <p class="text-xs text-base-content/60 mb-1">Project Path</p>
                  <p class="text-xs font-mono text-base-content/90 break-all">{@project.path}</p>
                </div>
              <% end %>
              <%= if @claude_files != [] do %>
                <div class="space-y-1">
                  <%= for entry <- @claude_files do %>
                    <a
                      href={~p"/projects/#{@project.id}/files?path=#{entry.rel_path}"}
                      class="flex items-center gap-2 p-2 rounded-lg hover:bg-base-200 transition-colors"
                    >
                      <.icon
                        name={if entry.type == :dir, do: "hero-folder", else: "hero-document-text"}
                        class={"size-4 flex-shrink-0 #{if entry.type == :dir, do: "text-secondary", else: "text-primary"}"}
                      />
                      <div class="flex-1 min-w-0">
                        <p class="text-sm font-medium text-base-content">
                          {entry.rel_path}{if entry.type == :dir, do: "/"}
                        </p>
                        <p class="text-xs text-base-content/60">{entry.detail}</p>
                      </div>
                    </a>
                  <% end %>
                </div>
              <% else %>
                <p class="text-sm text-base-content/50">No Claude files found</p>
              <% end %>
            </div>
          </div>
          
    <!-- Active Sessions -->
          <%= if @active_sessions != [] do %>
            <div class="card bg-base-100 shadow-sm">
              <div class="card-body p-4">
                <h2 class="card-title text-base mb-3">Active Sessions</h2>
                <div class="space-y-2">
                  <%= for session <- @active_sessions do %>
                    <div class="flex items-center justify-between gap-3 p-2 rounded-lg hover:bg-base-200 transition-colors">
                      <div class="flex-1 min-w-0">
                        <div class="flex items-center gap-2 mb-1">
                          <code class="text-xs font-mono text-base-content/70">
                            {String.slice(session.uuid || to_string(session.id), 0..7)}
                          </code>
                          <span class="text-sm text-base-content/80 truncate">
                            {session.name ||
                              truncate_text(if session.agent, do: session.agent.description) ||
                              "Unnamed"}
                          </span>
                        </div>
                      </div>
                      <%= if session.id do %>
                        <.link
                          navigate={~p"/dm/#{session.id}"}
                          class="btn btn-ghost btn-xs text-base-content/60 hover:text-primary transition-colors min-h-[44px] min-w-[44px]"
                          title="Direct message"
                          onclick="event.stopPropagation()"
                        >
                          <.icon name="hero-chat-bubble-left-right" class="size-4" />
                        </.link>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>
          
    <!-- Recent Tasks -->
          <%= if @tasks != [] do %>
            <div class="card bg-base-100 shadow-sm">
              <div class="card-body p-4">
                <h2 class="card-title text-base mb-2">Recent Tasks</h2>
                <div class="space-y-1">
                  <%= for task <- @recent_tasks do %>
                    <div class="flex items-center gap-2 p-2 rounded-lg hover:bg-base-200 transition-colors">
                      <div class="flex-shrink-0">
                        <%= if task.completed_at do %>
                          <.icon name="hero-check-circle-solid" class="size-4 text-success" />
                        <% else %>
                          <div class="size-4 rounded-full border-2 border-base-content/30"></div>
                        <% end %>
                      </div>
                      <div class="flex-1 min-w-0">
                        <p class="text-sm font-medium text-base-content truncate">{task.title}</p>
                        <%= if task.description do %>
                          <p class="text-xs text-base-content/60 truncate">{task.description}</p>
                        <% end %>
                      </div>
                      <%= if not is_nil(task.priority) && task.priority > 0 do %>
                        <span class="badge badge-xs">P{task.priority}</span>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>
          
    <!-- Recent Notes -->
          <%= if @recent_notes != [] do %>
            <div class="card bg-base-100 shadow-sm">
              <div class="card-body p-4">
                <h2 class="card-title text-base mb-2">Recent Notes</h2>
                <div class="space-y-2 max-h-64 overflow-y-auto">
                  <%= for note <- @recent_notes do %>
                    <div class="p-2 rounded-lg bg-base-200/30 border border-base-300">
                      <p class="text-xs text-base-content/60 mb-1">
                        <%= if note.created_at do %>
                          {relative_time(note.created_at)}
                        <% end %>
                      </p>
                      <p class="text-sm text-base-content line-clamp-3">{note.body}</p>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>
          <!-- Recent Commits -->
          <%= if @recent_commits != [] do %>
            <div class="card bg-base-100 shadow-sm">
              <div class="card-body p-4">
                <h2 class="card-title text-base mb-2">Recent Commits</h2>
                <div class="space-y-1">
                  <%= for commit <- @recent_commits do %>
                    <div class="flex items-start gap-2 p-2 rounded-lg hover:bg-base-200 transition-colors">
                      <.icon
                        name="hero-code-bracket"
                        class="size-3.5 text-base-content/30 flex-shrink-0 mt-0.5"
                      />
                      <div class="flex-1 min-w-0">
                        <p class="text-xs font-mono text-base-content/40 mb-0.5">
                          {String.slice(commit.commit_hash || "", 0, 7)}
                        </p>
                        <p class="text-sm text-base-content truncate">
                          {commit.commit_message}
                        </p>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp scan_claude_files(nil), do: []

  defp scan_claude_files(project_path) do
    entries = []

    # CLAUDE.md at project root
    claude_md = Path.join(project_path, "CLAUDE.md")

    entries =
      if File.exists?(claude_md) do
        size = file_size_label(claude_md)

        entries ++
          [%{rel_path: "CLAUDE.md", type: :file, detail: "Project instructions · #{size}"}]
      else
        entries
      end

    # .claude/ directory contents
    claude_dir = Path.join(project_path, ".claude")

    entries =
      if File.dir?(claude_dir) do
        case File.ls(claude_dir) do
          {:error, _} ->
            entries

          {:ok, children} ->
            mapped =
              children
              |> Enum.reject(&String.starts_with?(&1, "."))
              |> Enum.sort()
              |> Enum.map(&build_claude_entry(&1, claude_dir))

            entries ++ mapped
        end
      else
        entries
      end

    entries
  end

  defp build_claude_entry(name, claude_dir) do
    full = Path.join(claude_dir, name)
    rel = ".claude/#{name}"

    if File.dir?(full) do
      count =
        case File.ls(full) do
          {:ok, entries} -> length(entries)
          _ -> 0
        end

      %{rel_path: rel, type: :dir, detail: "#{count} #{if count == 1, do: "item", else: "items"}"}
    else
      %{rel_path: rel, type: :file, detail: file_size_label(full)}
    end
  end

  defp file_size_label(path) do
    case File.stat(path) do
      {:ok, %{size: s}} when s >= 1024 -> "#{Float.round(s / 1024, 1)} KB"
      {:ok, %{size: s}} -> "#{s} B"
      _ -> ""
    end
  end
end
