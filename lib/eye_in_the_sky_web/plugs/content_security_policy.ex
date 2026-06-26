defmodule EyeInTheSkyWeb.Plugs.ContentSecurityPolicy do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    put_resp_header(conn, "content-security-policy", csp(conn.assigns[:csp_nonce]))
  end

  if Mix.env() == :dev do
    defp csp(_nonce) do
      port = System.get_env("VITE_PORT", "5173")
      origin = "http://localhost:#{port}"
      ws_origin = "ws://localhost:#{port}"
      ip_origin = "http://127.0.0.1:#{port}"
      ip_ws_origin = "ws://127.0.0.1:#{port}"

      "default-src 'self'; " <>
        "script-src 'self' 'unsafe-inline' #{origin} #{ip_origin}; " <>
        "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; " <>
        "font-src 'self' data: https://fonts.gstatic.com; " <>
        "img-src 'self' data: blob: #{origin} #{ip_origin}; " <>
        "connect-src 'self' #{ws_origin} #{ip_ws_origin}; " <>
        "frame-ancestors 'none'; " <>
        "object-src 'none'"
    end
  else
    defp csp(nonce) do
      script_src =
        if nonce, do: "script-src 'self' 'nonce-#{nonce}'; ", else: "script-src 'self'; "

      "default-src 'self'; " <>
        script_src <>
        "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; " <>
        "font-src 'self' data: https://fonts.gstatic.com; " <>
        "img-src 'self' data: blob:; " <>
        "connect-src 'self'; " <>
        "frame-ancestors 'none'; " <>
        "object-src 'none'"
    end
  end
end
