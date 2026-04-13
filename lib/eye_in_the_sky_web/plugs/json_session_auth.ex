defmodule EyeInTheSkyWeb.Plugs.JsonSessionAuth do
  @moduledoc """
  Session-cookie auth for browser-facing JSON endpoints.

  Validates that:
  1. A session_token exists in the session cookie and is valid in the DB.
  2. A user_id is present in the session.

  Returns JSON 401 (not a redirect) when unauthenticated or expired — preserving
  API semantics for fetch() callers that expect JSON responses.
  """
  import Plug.Conn

  alias EyeInTheSky.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    if Application.get_env(:eye_in_the_sky, :bypass_auth, false) do
      conn
    else
      conn
      |> check_user_id()
      |> check_session_token()
    end
  end

  defp check_user_id(%Plug.Conn{halted: true} = conn), do: conn

  defp check_user_id(conn) do
    case get_session(conn, :user_id) do
      nil -> reject(conn)
      _user_id -> conn
    end
  end

  defp check_session_token(%Plug.Conn{halted: true} = conn), do: conn

  defp check_session_token(conn) do
    case get_session(conn, :session_token) do
      nil ->
        reject(conn)

      token ->
        case Accounts.get_valid_user_session(token) do
          {:ok, _} -> conn
          {:error, _} -> reject(conn |> clear_session())
        end
    end
  end

  defp reject(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, ~s({"error":"unauthorized"}))
    |> halt()
  end
end
