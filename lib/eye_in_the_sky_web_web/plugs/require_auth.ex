defmodule EyeInTheSkyWebWeb.Plugs.RequireAuth do
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    if get_session(conn, :user_id) do
      conn
    else
      conn
      |> redirect(to: "/auth/login")
      |> halt()
    end
  end
end
