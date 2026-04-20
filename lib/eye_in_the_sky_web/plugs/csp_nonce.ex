defmodule EyeInTheSkyWeb.Plugs.CspNonce do
  @moduledoc """
  Generates a random CSP nonce per request and stores it in conn.assigns.

  The nonce is a base64-encoded random string used to allow specific inline scripts
  and styles while maintaining CSP security without unsafe-inline.
  """

  def init(opts) do
    opts
  end

  def call(conn, _opts) do
    nonce = generate_nonce()
    Plug.Conn.assign(conn, :csp_nonce, nonce)
  end

  defp generate_nonce do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.encode64()
  end
end
