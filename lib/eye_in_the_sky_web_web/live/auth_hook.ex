defmodule EyeInTheSkyWebWeb.AuthHook do
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [redirect: 2]

  alias EyeInTheSkyWeb.Accounts

  # :env is set only in compile-time configs (config/dev.exs, config/test.exs);
  # resolve it once at compile time rather than on every mount.
  @env Application.compile_env(:eye_in_the_sky_web, :env, :prod)

  def on_mount(:default, params, session, socket),
    do: on_mount(:require_auth, params, session, socket)

  def on_mount(:require_auth, _params, session, socket) do
    # :disable_auth is configured in runtime.exs via DISABLE_AUTH env var;
    # must remain Application.get_env (resolved at startup, not compile time).
    disable_auth = Application.get_env(:eye_in_the_sky_web, :disable_auth, false)

    if disable_auth and @env != :prod do
      {:cont, assign(socket, :current_user, nil)}
    else
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
end
