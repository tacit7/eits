defmodule EyeInTheSkyWeb.MCP.Tools.ResponseHelper do
  @moduledoc "Shared response helpers for MCP tools."

  alias Anubis.Server.Response

  def json_response(result) do
    Response.tool() |> Response.json(result)
  end

  def error_response(message) do
    Response.tool() |> Response.error(message)
  end
end
