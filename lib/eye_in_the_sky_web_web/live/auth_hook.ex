defmodule EyeInTheSkyWebWeb.AuthHook do
  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  alias EyeInTheSkyWeb.Accounts

  def on_mount(:default, params, session, socket),
    do: on_mount(:require_auth, params, session, socket)

  def on_mount(:require_auth, _params, _session, socket) do
    {:cont, assign(socket, :current_user, nil)}
  end
end
