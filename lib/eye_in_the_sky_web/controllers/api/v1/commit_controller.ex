defmodule EyeInTheSkyWeb.Api.V1.CommitController do
  use EyeInTheSkyWeb, :controller

  action_fallback EyeInTheSkyWeb.Api.V1.FallbackController

  import EyeInTheSkyWeb.ControllerHelpers

  alias EyeInTheSky.{Agents, Commits, Sessions}
  alias EyeInTheSkyWeb.Presenters.ApiPresenter

  @doc """
  GET /api/v1/commits - List commits for a session or agent.
  Query params: session_id (UUID), agent_id (UUID), limit (default 20)
  """
  def index(conn, params) do
    limit = parse_int(params["limit"], 20)
    since_hash = params["since_hash"]

    commits =
      cond do
        params["session_id"] ->
          case Sessions.get_session_by_uuid(params["session_id"]) do
            {:ok, session} -> Commits.list_commits_for_session(session.id, limit: limit)
            _ -> []
          end

        params["agent_id"] ->
          case Agents.get_agent_by_uuid(params["agent_id"]) do
            {:ok, agent} ->
              case Sessions.list_sessions_for_agent(agent.id, limit: 1) do
                [session | _] -> Commits.list_recent_commits(session.id, limit)
                [] -> []
              end

            _ ->
              []
          end

        true ->
          Commits.list_commits(limit: limit)
      end

    # Apply since_hash filter: return only commits newer than the given hash.
    # Commits are ordered oldest-first by list_commits_for_session; we find the
    # anchor and drop everything up to and including it.
    {commits, since_hash_found} =
      if since_hash do
        idx = Enum.find_index(commits, &(&1.commit_hash == since_hash))

        if idx do
          {Enum.drop(commits, idx + 1), true}
        else
          {commits, false}
        end
      else
        {commits, nil}
      end

    resp = %{
      success: true,
      commits: Enum.map(commits, &ApiPresenter.present_commit/1)
    }

    resp =
      if since_hash do
        Map.merge(resp, %{since_hash: since_hash, since_hash_found: since_hash_found})
      else
        resp
      end

    json(conn, resp)
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
        {:error, :bad_request, "agent_id is required"}

      not is_list(hashes) ->
        {:error, :bad_request, "commit_hashes must be a list"}

      hashes == [] ->
        {:error, :bad_request, "commit_hashes is required"}

      true ->
        do_create_commits(conn, agent_uuid, hashes, messages)
    end
  end

  defp do_create_commits(conn, agent_uuid, hashes, messages) do
    with {:ok, agent} <- Agents.get_agent_by_uuid(agent_uuid),
         [session | _] <- Sessions.list_sessions_for_agent(agent.id, limit: 1) do
      results =
        Enum.zip(hashes, messages)
        |> Enum.map(fn {hash, message} ->
          Commits.create_commit(%{
            session_id: session.id,
            commit_hash: hash,
            commit_message: message
          })
        end)

      # on_conflict: :nothing returns {:ok, %Commit{id: nil}} on hash collision.
      # Split into created (id present), duplicate (id nil), and errors (changeset failures).
      created =
        results
        |> Enum.filter(fn
          {:ok, %{id: id}} when not is_nil(id) -> true
          _ -> false
        end)
        |> Enum.map(fn {:ok, commit} ->
          commit |> ApiPresenter.present_commit() |> Map.put(:status, "created")
        end)

      duplicates =
        results
        |> Enum.filter(fn
          {:ok, %{id: nil}} -> true
          _ -> false
        end)
        |> Enum.map(fn {:ok, commit} -> %{commit_hash: commit.commit_hash, status: "duplicate"} end)

      errors =
        results
        |> Enum.filter(&match?({:error, _}, &1))
        |> Enum.map(fn {:error, changeset} -> translate_errors(changeset) end)

      http_status = if errors == [], do: :created, else: :multi_status

      conn
      |> put_status(http_status)
      |> json(%{
        commits: created,
        duplicates: duplicates,
        errors: errors,
        already_tracked: duplicates != [] and created == [] and errors == []
      })
    else
      {:error, :not_found} ->
        {:error, :not_found, "Agent not found"}

      [] ->
        {:error, :not_found, "No session found for agent"}
    end
  end
end
