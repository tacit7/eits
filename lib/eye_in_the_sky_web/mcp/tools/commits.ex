defmodule EyeInTheSkyWeb.MCP.Tools.Commits do
  @moduledoc "Track git commits"

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias EyeInTheSkyWeb.Sessions

  schema do
    field :agent_id, :string, required: true, description: "Agent identifier"
    field :commit_hashes, {:list, :string}, required: true, description: "List of commit hashes"
    field :commit_messages, {:list, :string}, description: "List of commit messages"
  end

  @impl true
  def execute(params, frame) do
    alias EyeInTheSkyWeb.Commits

    agent_id = params["agent_id"]
    hashes = params["commit_hashes"] || []
    messages = params["commit_messages"] || []

    # Resolve agent integer ID
    agent_int_id =
      case Sessions.get_session_by_uuid(agent_id) do
        {:ok, agent} -> agent.id
        _ -> nil
      end

    results =
      hashes
      |> Enum.with_index()
      |> Enum.map(fn {hash, idx} ->
        message = Enum.at(messages, idx, "")

        case Commits.create_commit(%{
               hash: hash,
               message: message,
               agent_id: agent_int_id
             }) do
          {:ok, _} -> :ok
          {:error, _} -> :error
        end
      end)

    ok_count = Enum.count(results, &(&1 == :ok))

    result = %{
      success: true,
      message: "Logged #{ok_count}/#{length(hashes)} commits"
    }

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end
end
