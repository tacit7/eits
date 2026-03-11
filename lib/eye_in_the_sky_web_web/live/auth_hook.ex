defmodule EyeInTheSkyWebWeb.AuthHook do
  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  alias EyeInTheSkyWeb.Accounts

  def on_mount(:default, params, session, socket), do: on_mount(:require_auth, params, session, socket)

  def on_mount(:require_auth, _params, session, socket) do
    case session["user_id"] && Accounts.get_user(session["user_id"]) do
      nil ->
        {:halt, redirect(socket, to: "/auth/login")}

      user ->
        {:cont, assign(socket, :current_user, user)}
    end
  end
end
