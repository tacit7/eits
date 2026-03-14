defmodule EyeInTheSkyWeb.MCP.Tools.Commits do
  @moduledoc "Track git commits"

  use Anubis.Server.Component, type: :tool

  alias EyeInTheSkyWeb.MCP.Tools.ResponseHelper
  alias EyeInTheSkyWeb.Sessions

  schema do
    field :agent_id, :string,
      description:
        "Agent or session identifier. Accepts an integer agent ID (resolves to most recent session) or a session UUID string. Defaults to current session."

    field :commit_hashes, {:list, :string}, required: true, description: "List of commit hashes"
    field :commit_messages, {:list, :string}, description: "List of commit messages"
  end

  @impl true
  def execute(params, frame) do
    alias EyeInTheSkyWeb.Commits

    agent_id = params[:agent_id] || frame.assigns[:eits_session_id]
    hashes = params[:commit_hashes] || []
    messages = params[:commit_messages] || []

    # Resolve session ID — agent_id may be an integer agent ID or a session UUID
    session_int_id =
      case Integer.parse(to_string(agent_id)) do
        {int_id, ""} ->
          # It's an integer agent ID — get the most recent session for this agent
          case Sessions.list_sessions_for_agent(int_id) do
            [session | _] -> session.id
            _ -> nil
          end

        _ ->
          # Try as session UUID
          case Sessions.get_session_by_uuid(agent_id) do
            {:ok, session} -> session.id
            _ -> nil
          end
      end

    if is_nil(session_int_id) do
      result = %{success: false, message: "Could not resolve session for agent_id: #{agent_id}"}
      response = ResponseHelper.json_response(result)
      {:reply, response, frame}
    else
      results =
        hashes
        |> Enum.with_index()
        |> Enum.map(fn {hash, idx} ->
          message = Enum.at(messages, idx, "")

          case Commits.create_commit(%{
                 commit_hash: hash,
                 commit_message: message,
                 session_id: session_int_id
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

      response = ResponseHelper.json_response(result)
      {:reply, response, frame}
    end
  end
end
