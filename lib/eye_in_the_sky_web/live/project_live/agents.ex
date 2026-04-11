defmodule EyeInTheSkyWeb.ProjectLive.Agents do
  use EyeInTheSkyWeb, :live_view

  import EyeInTheSkyWeb.Helpers.ProjectLiveHelpers

  alias EyeInTheSkyWeb.Helpers.FileHelpers
  alias EyeInTheSkyWeb.Helpers.ViewHelpers

  @user_agents_dir Path.expand("~/.claude/agents")

  @impl true
  def mount(%{"id" => _} = params, _session, socket) do
    socket =
      socket
      |> mount_project(params,
        sidebar_tab: :agents,
        page_title_prefix: "Agents",
        preload: [:agents]
      )
      |> assign(:user_agents_dir, @user_agents_dir)
      |> assign(:selected_file, nil)
      |> assign(:selected_file_path, nil)
      |> assign(:file_content, nil)
      |> assign(:selected_scope, nil)
      |> assign(:project_agents, [])
      |> assign(:user_agents, [])

    socket =
      if socket.assigns.project do
        project = socket.assigns.project

        project_agents_dir =
          if project.path, do: Path.join([project.path, ".claude", "agents"]), else: nil

        socket
        |> assign(:project_agents_dir, project_agents_dir)
        |> load_all_agents()
      else
        assign(socket, :project_agents_dir, nil)
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("view_file", %{"path" => path}, socket) do
    project_dir = socket.assigns.project_agents_dir
    user_dir = socket.assigns.user_agents_dir

    allowed =
      (project_dir && String.starts_with?(path, project_dir)) ||
        String.starts_with?(path, user_dir)

    if allowed do
      content =
        case File.read(path) do
          {:ok, data} -> data
          {:error, _} -> "Error: could not read file"
        end

      relative = Path.basename(path)

      scope =
        if project_dir && String.starts_with?(path, project_dir), do: :project, else: :user

      {:noreply,
       socket
       |> assign(:selected_file, relative)
       |> assign(:selected_file_path, path)
       |> assign(:file_content, content)
       |> assign(:selected_scope, scope)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("close_viewer", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_file, nil)
     |> assign(:selected_file_path, nil)
     |> assign(:file_content, nil)
     |> assign(:selected_scope, nil)}
  end

  @impl true
  def handle_event("open_file", _params, socket) do
    path = socket.assigns.selected_file_path
    project_dir = socket.assigns.project_agents_dir
    user_dir = socket.assigns.user_agents_dir

    allowed =
      path &&
        ((project_dir && String.starts_with?(path, project_dir)) ||
           String.starts_with?(path, user_dir)) &&
        File.exists?(path)

    if allowed, do: ViewHelpers.open_in_system(path)

    {:noreply, socket}
  end

  defp load_all_agents(socket) do
    project_agents =
      case socket.assigns.project_agents_dir do
        nil -> []
        dir -> scan_agent_files(dir)
      end

    user_agents = scan_agent_files(@user_agents_dir)

    socket
    |> assign(:project_agents, project_agents)
    |> assign(:user_agents, user_agents)
  end

  defp scan_agent_files(agents_dir) do
    if File.dir?(agents_dir) do
      case File.ls(agents_dir) do
        {:ok, items} ->
          items
          |> Enum.filter(&String.ends_with?(&1, ".md"))
          |> Enum.reject(&(&1 == "README.md"))
          |> Enum.sort()
          |> Enum.map(&build_agent_entry(&1, agents_dir))

        _ ->
          []
      end
    else
      []
    end
  end

  defp build_agent_entry(item, agents_dir) do
    full = Path.join(agents_dir, item)
    size = case File.stat(full) do
      {:ok, %{size: s}} -> s
      _ -> 0
    end
    %{name: Path.rootname(item), filename: item, path: full, size: size}
  end

  defp has_any_agents?(project_agents, user_agents) do
    project_agents != [] || user_agents != []
  end

  attr :agents, :list, required: true
  attr :selected_file, :string, default: nil
  attr :selected_scope, :atom, default: nil
  attr :scope, :atom, required: true

  defp agent_list(assigns) do
    ~H"""
    <%= if @agents != [] do %>
      <div class="space-y-2">
        <%= for agent <- @agents do %>
          <button
            phx-click="view_file"
            phx-value-path={agent.path}
            class={"border border-base-300 bg-base-100 text-left transition-all w-full hover:border-primary cursor-pointer #{if @selected_file == agent.filename && @selected_scope == @scope, do: "border-primary ring-1 ring-primary"}"}
          >
            <div class="py-3 px-4">
              <div class="flex items-center gap-2">
                <.icon name="hero-document-text" class="w-4 h-4 text-base-content/50 shrink-0" />
                <code class="text-sm font-semibold text-base-content">{agent.name}</code>
                <span class="text-xs text-base-content/40 ml-auto">
                  {FileHelpers.format_size(agent.size)}
                </span>
              </div>
            </div>
          </button>
        <% end %>
      </div>
    <% else %>
      <div class="py-4">
        <p class="text-sm text-base-content/40 italic">No agent definitions found</p>
      </div>
    <% end %>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8 py-8">
      <div class="max-w-6xl mx-auto">
        <%= if has_any_agents?(@project_agents, @user_agents) do %>
          <div class={if @selected_file, do: "grid grid-cols-1 lg:grid-cols-2 gap-6", else: ""}>
            <!-- Left: agent files browser -->
            <div>
              <!-- Project-level agents -->
              <div class="flex items-center gap-2 mb-3">
                <.icon name="hero-folder" class="w-4 h-4 text-primary/60" />
                <span class="text-sm font-semibold text-base-content/60 uppercase tracking-wider">
                  Project Agents
                </span>
                <span class="badge badge-ghost badge-xs">{length(@project_agents)}</span>
              </div>
              <div class="mb-6">
                <.agent_list
                  agents={@project_agents}
                  selected_file={@selected_file}
                  selected_scope={@selected_scope}
                  scope={:project}
                />
              </div>
              
    <!-- User-level agents -->
              <div class="flex items-center gap-2 mb-3">
                <.icon name="hero-user" class="w-4 h-4 text-base-content/40" />
                <span class="text-sm font-semibold text-base-content/60 uppercase tracking-wider">
                  User Agents
                </span>
                <span class="badge badge-ghost badge-xs">{length(@user_agents)}</span>
              </div>
              <div class="mb-6">
                <.agent_list
                  agents={@user_agents}
                  selected_file={@selected_file}
                  selected_scope={@selected_scope}
                  scope={:user}
                />
              </div>
            </div>
            
    <!-- Right: file viewer -->
            <%= if @selected_file do %>
              <div class="sticky top-20">
                <div class="card bg-base-100 border border-base-300 shadow-sm">
                  <div class="card-body p-0">
                    <div class="flex items-center justify-between px-4 py-2 border-b border-base-300 bg-base-200/50">
                      <div class="flex items-center gap-2">
                        <span class={"badge badge-xs #{if @selected_scope == :project, do: "badge-primary", else: "badge-ghost"}"}>
                          {if @selected_scope == :project, do: "project", else: "user"}
                        </span>
                        <code class="text-sm font-semibold text-base-content">{@selected_file}</code>
                      </div>
                      <div class="flex items-center gap-1">
                        <button
                          phx-click="open_file"
                          class="btn btn-ghost btn-xs min-h-[44px] min-w-[44px]"
                          title="Open in editor"
                        >
                          <.icon name="hero-pencil-square" class="w-3.5 h-3.5" /> Edit
                        </button>
                        <button phx-click="close_viewer" class="btn btn-ghost btn-xs btn-circle min-h-[44px] min-w-[44px]">
                          <.icon name="hero-x-mark" class="w-4 h-4" />
                        </button>
                      </div>
                    </div>
                    <div class="overflow-auto max-h-[70vh]">
                      <div
                        id="agent-viewer"
                        class="dm-markdown p-4 text-sm text-base-content leading-relaxed"
                        phx-hook="MarkdownMessage"
                        data-raw-body={@file_content}
                      >
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        <% else %>
          <div class="text-center py-12">
            <.icon name="hero-user-circle" class="mx-auto h-12 w-12 text-base-content/40" />
            <h3 class="mt-2 text-sm font-medium text-base-content">No agents directory</h3>
            <p class="mt-1 text-sm text-base-content/60">
              <%= if @project && @project.path do %>
                No .claude/agents directory found at {@project.path} or ~/.claude/agents
              <% else %>
                Project path not configured
              <% end %>
            </p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
