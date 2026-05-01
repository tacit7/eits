defmodule EyeInTheSkyWeb.WorkspaceLive.Sessions do
  use EyeInTheSkyWeb, :live_view

  import EyeInTheSkyWeb.Components.ScopeComponents
  import EyeInTheSkyWeb.Components.SessionCard

  on_mount {EyeInTheSkyWeb.WorkspaceLive.Hooks, :require_workspace}

  alias EyeInTheSky.Projects
  alias EyeInTheSky.Sessions
  alias EyeInTheSkyWeb.WorkspaceLive.Sessions.Actions

  @page_size 50

  @impl true
  def mount(_params, _session, socket) do
    workspace = socket.assigns.workspace

    sessions = Sessions.list_sessions_for_scope(socket.assigns.scope, limit: @page_size + 1)
    {sessions, has_more} = split_page(sessions, @page_size)
    projects = Projects.list_projects_for_workspace(workspace.id)

    socket =
      socket
      |> assign(:page_title, "#{workspace.name} — Sessions")
      |> assign(:projects, projects)
      |> assign(:show_new_session_drawer, false)
      |> assign(:visible_count, @page_size)
      |> assign(:has_more, has_more)
      |> stream(:session_list, sessions)

    {:ok, socket}
  end

  @impl true
  def handle_event("load_more", _params, socket) do
    current_count = socket.assigns.visible_count

    sessions =
      Sessions.list_sessions_for_scope(socket.assigns.scope,
        limit: @page_size + 1,
        offset: current_count
      )

    {sessions, has_more} = split_page(sessions, @page_size)

    socket =
      socket
      |> assign(:visible_count, current_count + @page_size)
      |> assign(:has_more, has_more)
      |> stream(:session_list, sessions)

    {:noreply, socket}
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

      <div
        id="workspace-sessions-sentinel"
        phx-hook="InfiniteScroll"
        data-has-more={to_string(@has_more)}
        data-page={@visible_count}
        class="py-4 flex justify-center"
      >
        <%= if @has_more do %>
          <span class="loading loading-spinner loading-sm text-base-content/30"></span>
        <% end %>
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

  defp split_page(sessions, page_size) do
    if length(sessions) > page_size do
      {Enum.take(sessions, page_size), true}
    else
      {sessions, false}
    end
  end
end
