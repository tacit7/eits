defmodule EyeInTheSkyWeb.Plugs.ValidateSession do
  @moduledoc """
  Validates that the session_token in the cookie exists in the user_sessions table
  and has not expired. Redirects to /auth/login if invalid or expired.
  """
  import Plug.Conn

  alias EyeInTheSky.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, :session_token) do
      nil ->
        conn

      token ->
        case Accounts.get_valid_user_session(token) do
          {:error, _} ->
            conn
            |> clear_session()
            |> put_resp_header("location", "/auth/login")
            |> send_resp(302, "")
            |> halt()

          {:ok, _session} ->
            conn
        end
    end
  end
end
