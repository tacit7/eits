defmodule EyeInTheSkyWebWeb.Plugs.RequireAuth do
  import Plug.Conn

  alias EyeInTheSkyWeb.Accounts.ApiKey

  def init(opts), do: opts

  def call(conn, _opts) do
    configured_key = Application.get_env(:eye_in_the_sky_web, :api_key)
    no_env_key = is_nil(configured_key) or configured_key == ""

    if no_env_key and System.get_env("MIX_ENV") == "prod" do
      # In production with no env key, only DB keys are valid. Fall through to DB check.
      check_token(conn, configured_key)
    else
      check_token(conn, configured_key)
    end
  end

  defp check_token(conn, configured_key) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        if authenticated?(token, configured_key) do
          conn
        else
          reject(conn)
        end

      _ ->
        if is_nil(configured_key) or configured_key == "" do
          # No env key and no bearer token — allow in dev/test, reject in prod
          if System.get_env("MIX_ENV") == "prod" do
            reject(conn)
          else
            conn
          end
        else
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
    try do
      ApiKey.valid_db_token?(token)
    rescue
      _ -> false
    end
  end

  defp reject(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, ~s({"error":"unauthorized"}))
    |> halt()
  end
end
