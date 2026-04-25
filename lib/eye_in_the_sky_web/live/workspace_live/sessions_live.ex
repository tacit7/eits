defmodule EyeInTheSkyWeb.WorkspaceLive.Sessions do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.Scope
  alias EyeInTheSky.Workspaces

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    {workspace, scope} =
      if user do
        workspace = Workspaces.default_workspace_for_user!(user)
        {workspace, Scope.for_workspace(user, workspace)}
      else
        {nil, nil}
      end

    socket =
      socket
      |> assign(:workspace, workspace)
      |> assign(:scope, scope)
      |> assign(:page_title, workspace_title(workspace, "Sessions"))

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6">
      <h1 class="text-xl font-semibold"><%= @page_title %></h1>
      <p class="mt-4 text-base-content/60">Workspace sessions view — coming soon.</p>
    </div>
    """
  end

  defp workspace_title(nil, resource), do: "Workspace — #{resource}"
  defp workspace_title(workspace, resource), do: "#{workspace.name} — #{resource}"
end
