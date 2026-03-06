defmodule EyeInTheSkyWebWeb.MCPPlugTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias EyeInTheSkyWebWeb.MCPPlug

  # Pre-built opts pointing at a definitely-nonexistent transport.
  # GenServer.call raises (EXIT) :noproc when the process doesn't exist,
  # which is what MCPPlug's catch :exit clause is designed to handle.
  @nonexistent_opts %{
    server: :nonexistent_mcp_server,
    transport:
      {:via, Registry,
       {Anubis.Server.Registry, {:transport, :nonexistent_mcp_server, :streamable_http}}},
    session_header: "mcp-session-id",
    timeout: 1_000,
    registry: Anubis.Server.Registry
  }

  defp json_post(path, body) do
    conn(:post, path, body)
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
  end

  describe "init/1" do
    test "delegates to StreamableHTTP.Plug.init and returns opts map" do
      opts = MCPPlug.init(server: EyeInTheSkyWeb.MCP.Server)
      assert is_map(opts)
      assert opts.server == EyeInTheSkyWeb.MCP.Server
      assert opts.session_header == "mcp-session-id"
    end
  end

  describe "call/2 — exit catching" do
    test "returns 503 when transport process is unavailable" do
      conn =
        json_post("/mcp", ~s({"id":1,"method":"tools/list","jsonrpc":"2.0","params":{}}))
        |> MCPPlug.call(@nonexistent_opts)

      assert conn.status == 503
    end

    test "503 body is valid JSON with jsonrpc error structure" do
      conn =
        json_post("/mcp", ~s({"id":1,"method":"tools/list","jsonrpc":"2.0","params":{}}))
        |> MCPPlug.call(@nonexistent_opts)

      body = Jason.decode!(conn.resp_body)
      assert body["error"]["code"] == -32_603
      assert is_binary(body["error"]["message"])
      assert body["error"]["data"]["retry"] == true
    end

    test "503 response has application/json content-type" do
      conn =
        json_post("/mcp", ~s({"id":1,"method":"tools/list","jsonrpc":"2.0","params":{}}))
        |> MCPPlug.call(@nonexistent_opts)

      assert get_resp_header(conn, "content-type") |> List.first() =~ "application/json"
    end

    test "catches exit from non-request messages (notifications) too" do
      # notifications are handled before hitting the transport in some cases,
      # but a :noproc exit from any GenServer.call path is caught
      conn =
        json_post(
          "/mcp",
          ~s({"method":"notifications/initialized","jsonrpc":"2.0","params":{}})
        )
        |> MCPPlug.call(@nonexistent_opts)

      # Notifications return 202 if handled, 503 if transport dies — either is acceptable
      assert conn.status in [202, 503]
      refute conn.halted == false and conn.status == 500
    end
  end
end
