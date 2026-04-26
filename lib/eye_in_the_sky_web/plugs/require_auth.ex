defmodule EyeInTheSkyWeb.Plugs.RequireAuth do
  @moduledoc false
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    configured_key = Application.get_env(:eye_in_the_sky, :api_key)

    # When no API key is configured (nil), bypass auth entirely.
    # This is intended for test and development environments.
    # An empty string is NOT treated as bypass — it means misconfiguration and
    # all requests will be rejected (no token can match "").
    if is_nil(configured_key) do
      conn
    else
      case get_req_header(conn, "authorization") do
        ["Bearer " <> token] ->
          if authenticated?(token, configured_key) do
            conn
          else
            reject(conn)
          end

        _ ->
          reject(conn)
      end
    end
  end

  # Returns true if the token matches the env-var key OR any active DB key.
  defp authenticated?(token, configured_key) do
    env_key_match =
      is_binary(configured_key) and
        configured_key != "" and
        byte_size(token) == byte_size(configured_key) and
        Plug.Crypto.secure_compare(token, configured_key)

    env_key_match or db_key_match?(token)
  end

  defp db_key_match?(token) do
    EyeInTheSky.Accounts.ApiKey.valid_db_token?(token)
  rescue
    DBConnection.ConnectionError -> false
  end

  defp reject(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, ~s({"error":"unauthorized"}))
    |> halt()
  end
end
