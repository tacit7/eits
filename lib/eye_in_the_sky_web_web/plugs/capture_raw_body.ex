defmodule EyeInTheSkyWebWeb.Plugs.CaptureRawBody do
  @moduledoc """
  Reads and buffers the raw request body into conn.assigns[:raw_body]
  before Plug.Parsers consumes it.

  Must be inserted before Plug.Parsers in endpoint.ex.
  Only buffers bodies up to @max_length bytes to avoid memory issues.
  """

  @behaviour Plug
  @max_length 1_000_000

  def init(opts), do: opts

  def call(conn, _opts) do
    case Plug.Conn.read_body(conn, length: @max_length) do
      {:ok, body, conn} ->
        Plug.Conn.assign(conn, :raw_body, body)

      {:more, partial, conn} ->
        # Body exceeds max_length; store partial — HMAC will fail, which is correct
        Plug.Conn.assign(conn, :raw_body, partial)

      {:error, _reason} ->
        Plug.Conn.assign(conn, :raw_body, "")
    end
  end
end
