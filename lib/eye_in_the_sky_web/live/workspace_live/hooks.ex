defmodule EyeInTheSkyWeb.WorkspaceLive.Hooks do
  @moduledoc """
  Shared `on_mount` hooks for workspace aggregate LiveViews.

  Usage:

      on_mount {EyeInTheSkyWeb.WorkspaceLive.Hooks, :require_workspace}

  The hook resolves the user's default workspace and assigns both
  `:workspace` and `:scope` (an `EyeInTheSky.Scope` struct). If no
  default workspace exists for the user, the socket is halted with a
  redirect to the setup page.
  """

  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  alias EyeInTheSky.Scope
  alias EyeInTheSky.Workspaces

  def on_mount(:require_workspace, _params, _session, socket) do
    user = socket.assigns[:current_user]

    case user && Workspaces.default_workspace_for_user(user) do
      nil ->
        {:halt, redirect(socket, to: "/")}

      workspace ->
        scope = Scope.for_workspace(user, workspace)

        socket =
          socket
          |> assign(:workspace, workspace)
          |> assign(:scope, scope)

        {:cont, socket}
    end
  end
end
