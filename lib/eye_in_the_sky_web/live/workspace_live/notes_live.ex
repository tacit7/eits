defmodule EyeInTheSkyWeb.WorkspaceLive.Notes do
  use EyeInTheSkyWeb, :live_view

  on_mount {EyeInTheSkyWeb.WorkspaceLive.Hooks, :require_workspace}

  @impl true
  def mount(_params, _session, socket) do
    workspace = socket.assigns.workspace

    socket = assign(socket, :page_title, "#{workspace.name} — Notes")

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6">
      <h1 class="text-xl font-semibold"><%= @page_title %></h1>
      <p class="mt-4 text-base-content/60">Workspace notes view — coming soon.</p>
    </div>
    """
  end
end
