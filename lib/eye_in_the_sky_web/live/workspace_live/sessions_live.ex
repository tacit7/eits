defmodule EyeInTheSkyWeb.WorkspaceLive.Sessions do
  use EyeInTheSkyWeb, :live_view

  import EyeInTheSkyWeb.Components.ScopeComponents
  import EyeInTheSkyWeb.Components.SessionCard

  on_mount {EyeInTheSkyWeb.WorkspaceLive.Hooks, :require_workspace}

  alias EyeInTheSky.Projects
  alias EyeInTheSky.Sessions
  alias EyeInTheSkyWeb.WorkspaceLive.Sessions.Actions

  @impl true
  def mount(_params, _session, socket) do
    workspace = socket.assigns.workspace

    sessions = Sessions.list_sessions_for_scope(socket.assigns.scope)
    projects = Projects.list_projects_for_workspace(workspace.id)

    socket =
      socket
      |> assign(:page_title, "#{workspace.name} — Sessions")
      |> assign(:projects, projects)
      |> assign(:show_new_session_drawer, false)
      |> stream(:session_list, sessions)

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_new_session_drawer", _params, socket) do
    {:noreply, assign(socket, :show_new_session_drawer, !socket.assigns.show_new_session_drawer)}
  end

  @impl true
  def handle_event("create_new_session", params, socket) do
    Actions.create_new_session(params, socket)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6">
      <div class="flex items-start justify-between mb-6">
        <div>
          <h1 class="text-xl font-semibold"><%= @page_title %></h1>
          <.scope_badge scope={@scope} />
        </div>
        <button
          phx-click="toggle_new_session_drawer"
          class="btn btn-primary btn-sm gap-2"
        >
          <.icon name="hero-plus-mini" class="size-4" />
          New Agent
        </button>
      </div>

      <div
        id="workspace-session-list"
        phx-update="stream"
        class="divide-y divide-base-content/5"
      >
        <div :for={{dom_id, session} <- @streams.session_list} id={dom_id}>
          <.session_row
            session={session}
            project_name={session.project && session.project.name}
          />
        </div>
      </div>

      <.live_component
        module={EyeInTheSkyWeb.Components.NewSessionModal}
        id="new-session-modal-workspace"
        show={@show_new_session_drawer}
        projects={@projects}
        current_project={nil}
        toggle_event="toggle_new_session_drawer"
        submit_event="create_new_session"
        title="New Agent"
      />
    </div>
    """
  end
end
