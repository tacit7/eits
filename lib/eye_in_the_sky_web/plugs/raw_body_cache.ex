defmodule EyeInTheSkyWeb.Plugs.RawBodyCache do
  @moduledoc """
  Reads and caches the raw request body into conn.assigns[:raw_body]
  before Plug.Parsers consumes it. Route-scope this plug to webhook
  endpoints only — caching raw bodies application-wide is wasteful.
  """

  @behaviour Plug

  @impl Plug
  def init(opts), do: Keyword.get(opts, :only, nil)

  @impl Plug
  def call(%{request_path: path} = conn, only_path) when is_binary(only_path) do
    if String.starts_with?(path, only_path) do
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      Plug.Conn.assign(conn, :raw_body, body)
    else
      conn
    end
  end

  def call(conn, _), do: conn
end
