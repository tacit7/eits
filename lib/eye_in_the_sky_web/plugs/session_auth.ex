defmodule EyeInTheSkyWeb.Plugs.SessionAuth do
  @moduledoc """
  Plug for browser-facing routes that need session-cookie authentication.
  Redirects to /auth/login if no user_id in session.
  Used for admin/debug surfaces like the Oban dashboard and dev LiveDashboard.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if Application.get_env(:eye_in_the_sky, :bypass_auth, false) do
      conn
    else
      case get_session(conn, :user_id) do
        nil ->
          conn
          |> put_resp_header("location", "/auth/login")
          |> send_resp(302, "")
          |> halt()

        _user_id ->
          conn
      end
    end
  end
end
