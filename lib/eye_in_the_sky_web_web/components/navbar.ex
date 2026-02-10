defmodule EyeInTheSkyWebWeb.Components.Navbar do
  use EyeInTheSkyWebWeb, :live_component

  alias EyeInTheSkyWeb.Projects
  @impl true
  def mount(socket) do
    projects = Projects.list_projects()
    {:ok, assign(socket, projects: projects, current_project: nil)}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="navbar bg-base-100 shadow-sm">
        <div class="navbar-start">
          <a href="/" class="btn btn-ghost text-xl">
            <img src="/images/logo.svg" width="36" /> Eye in the Sky
          </a>
        </div>
        <div class="navbar-center hidden lg:flex">
          <ul class="menu menu-horizontal px-1">
            <li><a href="/">Overview</a></li>
            <li><a href="/prompts">Prompts</a></li>
            <li><a href="/chat">Chat</a></li>
            <li><a href="/nats">NATS</a></li>
          </ul>
        </div>
        <div class="navbar-end gap-2">
          <EyeInTheSkyWebWeb.Layouts.project_switcher
            projects={@projects}
            current_project={@current_project}
          />
        </div>
      </div>

    </div>
    """
  end
end
