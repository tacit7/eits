defmodule EyeInTheSkyWebWeb.AuthHook do
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [redirect: 2]

  alias EyeInTheSkyWeb.Accounts

  def on_mount(:default, params, session, socket),
    do: on_mount(:require_auth, params, session, socket)

  def on_mount(:require_auth, _params, session, socket) do
    case session["user_id"] do
      nil ->
        {:halt, redirect(socket, to: "/auth/login")}

      user_id ->
        case Accounts.get_user(user_id) do
          nil -> {:halt, redirect(socket, to: "/auth/login")}
          user -> {:cont, assign(socket, :current_user, user)}
        end
    end
  end
end
