defmodule EyeInTheSkyWeb.AuthHook do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [redirect: 2]

  alias EyeInTheSky.Accounts

  def on_mount(:default, params, session, socket),
    do: on_mount(:require_auth, params, session, socket)

  def on_mount(:require_auth, _params, session, socket) do
    # :disable_auth is configured in runtime.exs via DISABLE_AUTH env var;
    # must remain Application.get_env (resolved at startup, not compile time).
    # NOTE: Tauri POC — prod guard on @env dropped so the bundled desktop app
    # (which runs as a prod release) can bypass auth entirely. DO NOT set
    # DISABLE_AUTH=true in any deployment where the app is network-reachable.
    disable_auth = Application.get_env(:eye_in_the_sky, :disable_auth, false)

    if disable_auth do
      {:cont, assign(socket, :current_user, nil)}
    else
      authenticate_from_session(session, socket)
    end
  end

  defp authenticate_from_session(session, socket) do
    case session["user_id"] do
      nil ->
        {:halt, redirect(socket, to: "/auth/login")}

      user_id ->
        case Accounts.get_user(user_id) do
          {:error, :not_found} -> {:halt, redirect(socket, to: "/auth/login")}
          {:ok, user} -> {:cont, assign(socket, :current_user, user)}
        end
    end
  end
end
