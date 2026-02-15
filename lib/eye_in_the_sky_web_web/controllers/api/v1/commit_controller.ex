defmodule EyeInTheSkyWebWeb.Api.V1.CommitController do
  use EyeInTheSkyWebWeb, :controller

  alias EyeInTheSkyWeb.{Agents, Commits}

  @doc """
  POST /api/v1/commits - Track one or more git commits.

  Accepts agent_id (UUID), commit_hashes (list), commit_messages (optional list).
  Looks up the agent by UUID to get the session_id integer FK for the commits table.
  """
  def create(conn, params) do
    agent_uuid = params["agent_id"]
    hashes = params["commit_hashes"] || []
    messages = params["commit_messages"] || []

    cond do
      is_nil(agent_uuid) or agent_uuid == "" ->
        conn |> put_status(:bad_request) |> json(%{error: "agent_id is required"})

      hashes == [] ->
        conn |> put_status(:bad_request) |> json(%{error: "commit_hashes is required"})

      true ->
        case Agents.get_execution_agent_by_uuid(agent_uuid) do
          {:ok, agent} ->
            results =
              hashes
              |> Enum.with_index()
              |> Enum.map(fn {hash, idx} ->
                Commits.create_commit(%{
                  session_id: agent.id,
                  commit_hash: hash,
                  commit_message: Enum.at(messages, idx)
                })
              end)

            created =
              results
              |> Enum.filter(&match?({:ok, _}, &1))
              |> Enum.map(fn {:ok, commit} ->
                %{id: commit.id, commit_hash: commit.commit_hash, commit_message: commit.commit_message}
              end)

            errors =
              results
              |> Enum.filter(&match?({:error, _}, &1))
              |> Enum.map(fn {:error, changeset} -> translate_errors(changeset) end)

            status = if errors == [], do: :created, else: :multi_status

            conn
            |> put_status(status)
            |> json(%{commits: created, errors: errors})

          {:error, :not_found} ->
            conn |> put_status(:not_found) |> json(%{error: "Agent not found"})
        end
    end
  end

  defp translate_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
