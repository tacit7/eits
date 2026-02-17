defmodule EyeInTheSkyWebWeb.ProjectLive.Show do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.Projects
  alias EyeInTheSkyWeb.Agents
  alias EyeInTheSkyWeb.Notes
  alias EyeInTheSkyWeb.Repo
  alias EyeInTheSkyWeb.Sessions

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    # Parse project ID safely, handling both integer and UUID inputs
    project_id =
      case Integer.parse(id) do
        {int, ""} -> int
        # Not a valid integer
        _ -> nil
      end

    # Load project only if ID is valid
    socket =
      if project_id do
        project =
          Projects.get_project!(project_id)
          |> Repo.preload([:agents])

        # Load tasks manually due to type mismatch (projects.id is INT, tasks.project_id is TEXT)
        tasks = Projects.get_project_tasks(project_id)

        # Load active sessions for this project (max 5)
        active_sessions =
          Sessions.list_sessions_with_agent()
          |> Enum.filter(&(is_nil(&1.ended_at) and &1.project_id == project_id))
          |> Enum.sort_by(& &1.started_at, :desc)
          |> Enum.take(5)

        # Load recent notes for this project (max 5)
        recent_notes =
          Notes.list_notes()
          |> Enum.filter(&(&1.parent_type == "project" and &1.parent_id == to_string(project_id)))
          |> Enum.sort_by(& &1.inserted_at, :desc)
          |> Enum.take(5)

        socket
        |> assign(:page_title, "Project: #{project.name}")
        |> assign(:project, project)
        |> assign(:sidebar_tab, :overview)
        |> assign(:sidebar_project, project)
        |> assign(:tasks, tasks)
        |> assign(:active_sessions, active_sessions)
        |> assign(:recent_notes, recent_notes)
      else
        # Invalid project ID - show error
        socket
        |> assign(:page_title, "Project Not Found")
        |> assign(:project, nil)
        |> assign(:tasks, [])
        |> put_flash(:error, "Invalid project ID")
      end

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8 py-4">
      <div class="max-w-7xl mx-auto">
        <!-- Responsive Grid Layout -->
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
          <!-- Quick Access -->
          <div class="card bg-base-100 shadow-sm">
            <div class="card-body p-4">
              <h2 class="card-title text-base mb-2">Quick Access</h2>
              <%= if @project.path do %>
                <div class="mb-2 pb-2 border-b border-base-300">
                  <p class="text-xs text-base-content/60 mb-1">Project Path</p>
                  <p class="text-xs font-mono text-base-content/90 break-all">{@project.path}</p>
                </div>
              <% end %>
              <div class="space-y-1">
                <a
                  href={~p"/projects/#{@project.id}/files?path=CLAUDE.md"}
                  class="flex items-center gap-2 p-2 rounded-lg hover:bg-base-200 transition-colors"
                >
                  <svg
                    class="w-4 h-4 text-primary flex-shrink-0"
                    fill="currentColor"
                    viewBox="0 0 16 16"
                  >
                    <path d="M4 0a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2V2a2 2 0 0 0-2-2H4zm0 1h8a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V2a1 1 0 0 1 1-1z" />
                  </svg>
                  <div class="flex-1 min-w-0">
                    <p class="text-sm font-medium text-base-content">CLAUDE.md</p>
                    <p class="text-xs text-base-content/60">Project instructions</p>
                  </div>
                </a>
                <a
                  href={~p"/projects/#{@project.id}/files?path=.claude/hooks"}
                  class="flex items-center gap-2 p-2 rounded-lg hover:bg-base-200 transition-colors"
                >
                  <svg
                    class="w-4 h-4 text-secondary flex-shrink-0"
                    fill="currentColor"
                    viewBox="0 0 16 16"
                  >
                    <path d="M1.75 1A1.75 1.75 0 0 0 0 2.75v10.5C0 14.216.784 15 1.75 15h12.5A1.75 1.75 0 0 0 16 13.25v-8.5A1.75 1.75 0 0 0 14.25 3H7.5a.25.25 0 0 1-.2-.1l-.9-1.2C6.07 1.26 5.55 1 5 1H1.75Z" />
                  </svg>
                  <div class="flex-1 min-w-0">
                    <p class="text-sm font-medium text-base-content">.claude/hooks/</p>
                    <p class="text-xs text-base-content/60">Hooks configuration</p>
                  </div>
                </a>
              </div>
            </div>
          </div>
          
    <!-- Active Sessions -->
          <%= if length(@active_sessions) > 0 do %>
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
                            {session.name || (session.chat_agent && session.chat_agent.description) ||
                              "Unnamed"}
                          </span>
                        </div>
                      </div>
                      <%= if session.id do %>
                        <.link
                          navigate={~p"/dm/#{session.id}"}
                          class="btn btn-ghost btn-xs text-base-content/60 hover:text-primary transition-colors"
                          title="Direct message"
                          onclick="event.stopPropagation()"
                        >
                          <.icon name="hero-chat-bubble-left-right" class="w-4 h-4" />
                        </.link>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>
          
    <!-- Recent Tasks -->
          <%= if length(@tasks) > 0 do %>
            <div class="card bg-base-100 shadow-sm">
              <div class="card-body p-4">
                <h2 class="card-title text-base mb-2">Recent Tasks</h2>
                <div class="space-y-1">
                  <%= for task <- @tasks |> Enum.sort_by(& &1.created_at, :desc) |> Enum.take(5) do %>
                    <div class="flex items-center gap-2 p-2 rounded-lg hover:bg-base-200 transition-colors">
                      <div class="flex-shrink-0">
                        <%= if task.completed_at do %>
                          <svg class="w-4 h-4 text-success" fill="currentColor" viewBox="0 0 20 20">
                            <path
                              fill-rule="evenodd"
                              d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                              clip-rule="evenodd"
                            />
                          </svg>
                        <% else %>
                          <div class="w-4 h-4 rounded-full border-2 border-base-content/30"></div>
                        <% end %>
                      </div>
                      <div class="flex-1 min-w-0">
                        <p class="text-sm font-medium text-base-content truncate">{task.title}</p>
                        <%= if task.description do %>
                          <p class="text-xs text-base-content/60 truncate">{task.description}</p>
                        <% end %>
                      </div>
                      <%= if task.priority && task.priority > 0 do %>
                        <span class="badge badge-xs">P{task.priority}</span>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>
          
    <!-- Recent Notes -->
          <%= if length(@recent_notes) > 0 do %>
            <div class="card bg-base-100 shadow-sm">
              <div class="card-body p-4">
                <h2 class="card-title text-base mb-2">Recent Notes</h2>
                <div class="space-y-2 max-h-64 overflow-y-auto">
                  <%= for note <- @recent_notes do %>
                    <div class="p-2 rounded-lg bg-base-200/30 border border-base-300">
                      <p class="text-xs text-base-content/60 mb-1">
                        <%= if note.inserted_at do %>
                          {format_relative_time(note.inserted_at)}
                        <% end %>
                      </p>
                      <p class="text-sm text-base-content line-clamp-3">{note.body}</p>
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

  defp format_relative_time(datetime) when is_nil(datetime), do: "—"

  defp format_relative_time(%DateTime{} = datetime) do
    now = DateTime.utc_now()
    seconds = DateTime.diff(now, datetime)

    cond do
      seconds < 60 -> "just now"
      seconds < 3600 -> "#{div(seconds, 60)}m ago"
      seconds < 86400 -> "#{div(seconds, 3600)}h ago"
      seconds < 604_800 -> "#{div(seconds, 86400)}d ago"
      true -> "#{div(seconds, 604_800)}w ago"
    end
  end

  defp format_relative_time(%NaiveDateTime{} = naive_datetime) do
    # Convert NaiveDateTime to DateTime assuming UTC
    case DateTime.from_naive(naive_datetime, "Etc/UTC") do
      {:ok, datetime} -> format_relative_time(datetime)
      :error -> "—"
    end
  end

  defp format_relative_time(_), do: "—"
end
