defmodule EyeInTheSkyWeb.MCP.Tools.SpawnClaude do
  @moduledoc "Spawn a Claude Code process and capture its session ID from the init message"

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  schema do
    field :prompt, :string, required: true, description: "Prompt to send to Claude Code"

    field :model, :string,
      required: true,
      description: "Model to use (haiku, sonnet, opus, or full model ID)"

    field :project_path, :string, description: "Working directory for Claude Code"
  end

  @impl true
  def execute(params, frame) do
    alias EyeInTheSkyWeb.Claude.SDK

    opts = [
      model: params["model"],
      project_path: params["project_path"]
    ]

    result =
      case SDK.start(params["prompt"], [to: self()] ++ opts) do
        {:ok, _ref} ->
          %{
            success: true,
            message: "Claude Code process spawned"
          }

        {:error, reason} ->
          %{success: false, message: "Spawn failed: #{inspect(reason)}"}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end
end
