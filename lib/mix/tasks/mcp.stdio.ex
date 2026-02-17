defmodule Mix.Tasks.Mcp.Stdio do
  @moduledoc """
  Runs the Eye in the Sky MCP server over stdio.

  This task starts the MCP server using stdio transport for communication
  with Claude Code and other stdio-based MCP clients.

  ## Usage

      mix mcp.stdio

  The server will read JSON-RPC messages from stdin and write responses to stdout.
  """

  use Mix.Task

  @shortdoc "Runs the EITS MCP server over stdio"

  @impl Mix.Task
  def run(_args) do
    EyeInTheSkyWeb.MCP.StdioRunner.run()
  end
end
