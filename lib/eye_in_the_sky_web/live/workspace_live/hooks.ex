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

  alias EyeInTheSky.Accounts
  alias EyeInTheSky.Scope
  alias EyeInTheSky.Workspaces

  def on_mount(:require_workspace, _params, _session, socket) do
    case resolve_workspace(socket.assigns[:current_user]) do
      nil ->
        {:halt, redirect(socket, to: "/")}

      {user, workspace} ->
        scope = Scope.for_workspace(user, workspace)

        socket =
          socket
          |> assign(:current_user, user)
          |> assign(:workspace, workspace)
          |> assign(:scope, scope)

        {:cont, socket}
    end
  end

  defp resolve_workspace(%{} = user) do
    case Workspaces.default_workspace_for_user(user) do
      nil -> nil
      workspace -> {user, workspace}
    end
  end

  defp resolve_workspace(nil) do
    if Application.get_env(:eye_in_the_sky, :disable_auth, false) do
      with %{owner_user_id: owner_user_id} = workspace <- Workspaces.default_workspace(),
           {:ok, user} <- Accounts.get_user(owner_user_id) do
        {user, workspace}
      else
        _ -> nil
      end
    end
  end
end
