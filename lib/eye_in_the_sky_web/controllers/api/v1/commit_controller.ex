defmodule EyeInTheSkyWeb.Api.V1.CommitController do
  use EyeInTheSkyWeb, :controller

  import EyeInTheSkyWeb.ControllerHelpers

  alias EyeInTheSky.{Agents, Commits, Sessions}
  alias EyeInTheSkyWeb.Presenters.ApiPresenter

  @doc """
  GET /api/v1/commits - List commits for a session or agent.
  Query params: session_id (UUID), agent_id (UUID), limit (default 20)
  """
  def index(conn, params) do
    limit = parse_int(params["limit"], 20)

    commits =
      cond do
        params["session_id"] ->
          case Sessions.get_session_by_uuid(params["session_id"]) do
            {:ok, session} -> Commits.list_commits_for_session(session.id, limit: limit)
            _ -> []
          end

        params["agent_id"] ->
          case Agents.get_agent_by_uuid(params["agent_id"]) do
            {:ok, agent} -> Commits.list_commits_for_agent(agent.id) |> Enum.take(limit)
            _ -> []
          end

        true ->
          Commits.list_commits() |> Enum.take(limit)
      end

    json(conn, %{
      success: true,
      commits: Enum.map(commits, &ApiPresenter.present_commit/1)
    })
  end

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

      not is_list(hashes) ->
        conn |> put_status(:bad_request) |> json(%{error: "commit_hashes must be a list"})

      hashes == [] ->
        conn |> put_status(:bad_request) |> json(%{error: "commit_hashes is required"})

      true ->
        do_create_commits(conn, agent_uuid, hashes, messages)
    end
  end

  defp do_create_commits(conn, agent_uuid, hashes, messages) do
    with {:ok, agent} <- Agents.get_agent_by_uuid(agent_uuid),
         [session | _] <- Sessions.list_sessions_for_agent(agent.id, limit: 1) do
      results =
        hashes
        |> Enum.with_index()
        |> Enum.map(fn {hash, idx} ->
          Commits.create_commit(%{
            session_id: session.id,
            commit_hash: hash,
            commit_message: Enum.at(messages, idx)
          })
        end)

      created =
        results
        |> Enum.filter(&match?({:ok, _}, &1))
        |> Enum.map(fn {:ok, commit} -> ApiPresenter.present_commit(commit) end)

      errors =
        results
        |> Enum.filter(&match?({:error, _}, &1))
        |> Enum.map(fn {:error, changeset} -> translate_errors(changeset) end)

      status = if errors == [], do: :created, else: :multi_status

      conn
      |> put_status(status)
      |> json(%{commits: created, errors: errors})
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Agent not found"})

      [] ->
        conn |> put_status(:not_found) |> json(%{error: "No session found for agent"})
    end
  end
end
