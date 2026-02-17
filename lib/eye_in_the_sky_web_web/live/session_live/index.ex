defmodule EyeInTheSkyWebWeb.SessionLive.Index do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.Agents
  alias EyeInTheSkyWeb.Sessions
  import EyeInTheSkyWebWeb.Components.SessionCard

  @impl true
  def mount(_params, _session, socket) do
    agents = Sessions.list_session_overview_rows(limit: 20)
    projects = EyeInTheSkyWeb.Projects.list_projects()

    socket =
      socket
      |> assign(:page_title, "Session Overview")
      |> assign(:agents, agents)
      |> assign(:projects, projects)
      |> assign(:show_new_session_modal, false)
      |> assign(:sidebar_tab, :sessions)
      |> assign(:sidebar_project, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("start_session", %{"agent_id" => _agent_id}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_new_session_modal", _params, socket) do
    {:noreply, assign(socket, :show_new_session_modal, !socket.assigns.show_new_session_modal)}
  end

  @impl true
  def handle_event("create_new_session", params, socket) do
    model = params["model"]
    effort_level = params["effort_level"]
    project_id = String.to_integer(params["project_id"])
    description = params["description"]
    agent_name = String.slice(description || "", 0, 60)

    project = EyeInTheSkyWeb.Projects.get_project!(project_id)

    opts = [
      model: model,
      effort_level: effort_level,
      project_id: project_id,
      project_path: project.path,
      description: agent_name,
      instructions: description
    ]

    case EyeInTheSkyWeb.Claude.AgentManager.create_agent(opts) do
      {:ok, _result} ->
        agents = Sessions.list_session_overview_rows(limit: 20)

        socket =
          socket
          |> assign(:show_new_session_modal, false)
          |> assign(:agents, agents)
          |> put_flash(:info, "Session launched")

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create session: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-6 lg:px-8">
      <div class="max-w-5xl mx-auto">
        <div class="flex items-center justify-between py-6">
          <div>
            <h1 class="text-lg font-semibold text-base-content/90">Sessions</h1>
            <p class="text-xs text-base-content/35 mt-0.5">
              Recent sessions across all projects
            </p>
          </div>
          <div class="flex items-center gap-2">
            <button
              phx-click="toggle_new_session_modal"
              class="btn btn-sm btn-primary gap-1.5 min-h-0 h-7 text-xs"
            >
              <.icon name="hero-plus-mini" class="w-3.5 h-3.5" /> New Agent
            </button>
            <label class="swap swap-rotate btn btn-ghost btn-xs btn-circle">
              <input type="checkbox" class="theme-controller" value="dark" />
              <.icon name="hero-sun" class="swap-on w-4 h-4" />
              <.icon name="hero-moon" class="swap-off w-4 h-4" />
            </label>
          </div>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
          <%= for agent <- @agents do %>
            <.session_card session={agent} />
          <% end %>
        </div>
      </div>
    </div>

    <.live_component
      module={EyeInTheSkyWebWeb.Components.NewSessionModal}
      id="new-session-modal"
      show={@show_new_session_modal}
      projects={@projects}
      current_project={nil}
      toggle_event="toggle_new_session_modal"
      submit_event="create_new_session"
    />
    """
  end
end
