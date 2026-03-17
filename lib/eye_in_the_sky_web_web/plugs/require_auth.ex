defmodule EyeInTheSkyWebWeb.Plugs.RequireAuth do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    configured_key = Application.get_env(:eye_in_the_sky_web, :api_key)

    if is_nil(configured_key) or configured_key == "" do
      # If no key configured, check environment
      if System.get_env("MIX_ENV") == "prod" do
        # Reject all traffic in production
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, ~s({"error":"unauthorized"}))
        |> halt()
      else
        # Allow passthrough in dev/test
        conn
      end
    else
      with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
           true <- valid_token?(token, configured_key) do
        conn
      else
        _ ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(401, ~s({"error":"unauthorized"}))
          |> halt()
      end
    end
  end

  defp valid_token?(token, configured_key)
       when is_binary(token) and is_binary(configured_key) and
              byte_size(token) == byte_size(configured_key) do
    Plug.Crypto.secure_compare(token, configured_key)
  end

  defp valid_token?(_, _), do: false
end
