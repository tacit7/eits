defmodule EyeInTheSkyWeb.Plugs.CaptureRawBody do
  @moduledoc """
  Custom body reader for Plug.Parsers that caches the raw request body
  in conn.assigns[:raw_body] while still allowing normal parsing.

  Pass as `body_reader` option to Plug.Parsers in endpoint.ex:

      plug Plug.Parsers,
        parsers: [...],
        body_reader: {EyeInTheSkyWeb.Plugs.CaptureRawBody, :read_body, []},
        ...
  """

  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        existing = conn.assigns[:raw_body] || ""
        conn = Plug.Conn.assign(conn, :raw_body, existing <> body)
        {:ok, body, conn}

      {:more, chunk, conn} ->
        existing = conn.assigns[:raw_body] || ""
        conn = Plug.Conn.assign(conn, :raw_body, existing <> chunk)
        {:more, chunk, conn}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
