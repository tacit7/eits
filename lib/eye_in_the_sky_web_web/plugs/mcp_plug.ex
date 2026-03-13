defmodule EyeInTheSkyWebWeb.MCPPlug do
  @moduledoc """
  Wrapper around Anubis.Server.Transport.StreamableHTTP.Plug that catches
  GenServer exit signals. During Phoenix hot code reloads in development,
  the Anubis supervisor (which uses :one_for_all internally) restarts all
  its children including the transport GenServer. Any in-flight request gets
  an (EXIT) shutdown from GenServer.call, which is otherwise an unhandled
  exit crashing the HTTP handler. This plug converts that to a 503 so
  clients can retry cleanly.
  """

  @behaviour Plug

  alias Anubis.Server.Transport.StreamableHTTP

  @impl Plug
  def init(opts), do: StreamableHTTP.Plug.init(opts)

  @impl Plug
  def call(conn, opts) do
    conn = ensure_json_accept(conn)
    StreamableHTTP.Plug.call(conn, opts)
  catch
    :exit, reason ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        503,
        Jason.encode!(%{
          jsonrpc: "2.0",
          error: %{
            code: -32_603,
            message: "MCP server unavailable",
            data: %{reason: inspect(reason), retry: true}
          },
          id: nil
        })
      )
  end

  # Anubis requires Accept to include application/json. Claude Code sends only
  # text/event-stream. Inject application/json if it's missing so both clients work.
  defp ensure_json_accept(conn) do
    accept = Plug.Conn.get_req_header(conn, "accept") |> Enum.join(", ")

    if String.contains?(accept, "application/json") do
      conn
    else
      merged = if accept == "", do: "application/json", else: "#{accept}, application/json"
      %{conn | req_headers: List.keystore(conn.req_headers, "accept", 0, {"accept", merged})}
    end
  end
end
