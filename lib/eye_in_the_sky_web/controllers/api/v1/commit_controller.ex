defmodule EyeInTheSkyWeb.Api.V1.CommitController do
  use EyeInTheSkyWeb, :controller

  action_fallback EyeInTheSkyWeb.Api.V1.FallbackController

  import EyeInTheSkyWeb.ControllerHelpers

  alias EyeInTheSky.{Agents, Commits, Sessions, Tasks}
  alias EyeInTheSkyWeb.MCP.Tools.SessionResolver
  alias EyeInTheSkyWeb.Presenters.ApiPresenter

  @doc """
  GET /api/v1/commits - List or search commits.
  Query params:
    q           - search commit messages via ILIKE (returns session_uuid/session_name alongside)
    session_id  - filter by session UUID
    agent_id    - filter by agent UUID
    limit       - max results (default 20)
    since_hash  - return only commits newer than this hash
  """
  def index(conn, params) do
    limit = parse_int(params["limit"], 20)
    search_query = params["q"]

    # Search mode: full-text across commit messages, joins sessions for context.
    if search_query && search_query != "" do
      results = Commits.search_commits(search_query, limit: limit)

      json(conn, %{
        success: true,
        count: length(results),
        commits:
          Enum.map(results, fn c ->
            %{
              id: c.id,
              commit_hash: c.commit_hash,
              commit_message: c.commit_message,
              created_at: c.created_at,
              session_id: c.session_id,
              session_uuid: c.session_uuid,
              session_name: c.session_name
            }
          end)
      })
    else
      since_hash = params["since_hash"]

      commits =
        cond do
          params["session_id"] ->
            case SessionResolver.resolve(params["session_id"]) do
              {:ok, session} -> Commits.list_commits_for_session(session.id, limit: limit)
              _ -> []
            end

          params["agent_id"] ->
            case resolve_agent(params["agent_id"]) do
              {:ok, agent} -> Commits.list_commits_for_agent(agent.id, limit: limit)
              _ -> []
            end

          true ->
            Commits.list_commits(limit: limit)
        end

      # Apply since_hash filter: return only commits newer than the given hash.
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
  end

  @doc """
  POST /api/v1/commits - Track one or more git commits.

  Accepts session_id (UUID or integer), agent_id (UUID), commit_hashes (list),
  commit_messages (optional list), and task_ids (optional list). When session_id
  is present, it is used as the authoritative commit target; otherwise the latest
  session for agent_id is used for compatibility.
  """
  def create(conn, params) do
    session_identity = params["session_id"]
    agent_uuid = params["agent_id"]
    hashes = params["commit_hashes"] || []
    messages = params["commit_messages"] || []
    task_ids = params["task_ids"] || []

    cond do
      blank?(session_identity) and blank?(agent_uuid) ->
        {:error, :bad_request, "session_id or agent_id is required"}

      not is_list(hashes) ->
        {:error, :bad_request, "commit_hashes must be a list"}

      not is_list(task_ids) ->
        {:error, :bad_request, "task_ids must be a list"}

      hashes == [] ->
        {:error, :bad_request, "commit_hashes is required"}

      true ->
        do_create_commits(conn, session_identity, agent_uuid, hashes, messages, task_ids)
    end
  end

  defp do_create_commits(conn, session_identity, agent_uuid, hashes, messages, task_ids) do
    with {:ok, session, agent_id} <- resolve_commit_target(session_identity, agent_uuid) do
      results =
        hashes
        |> Enum.with_index()
        |> Enum.map(fn {hash, idx} ->
          message = Enum.at(messages, idx)

          Commits.create_commit(%{
            session_id: session.id,
            agent_id: agent_id,
            commit_hash: hash,
            commit_message: message
          })
        end)

      # on_conflict: :nothing returns {:ok, %Commit{id: nil}} on hash collision.
      # Split into created (id present), duplicate (id nil), and errors (changeset failures).
      created =
        for {:ok, %{id: id} = commit} <- results, not is_nil(id) do
          commit |> ApiPresenter.present_commit() |> Map.put(:status, "created")
        end

      duplicates =
        for {:ok, %{id: nil} = commit} <- results do
          %{commit_hash: commit.commit_hash, status: "duplicate"}
        end

      errors =
        for {:error, changeset} <- results, do: translate_errors(changeset)

      link_errors = link_commits_to_tasks(session.id, hashes, task_ids)

      http_status = if errors == [] and link_errors == [], do: :created, else: :multi_status

      conn
      |> put_status(http_status)
      |> json(%{
        commits: created,
        duplicates: duplicates,
        errors: errors,
        link_errors: link_errors,
        already_tracked: duplicates != [] and created == [] and errors == []
      })
    else
      {:error, :session_not_found} ->
        {:error, :not_found, "Session not found"}

      {:error, :not_found} ->
        {:error, :not_found, "Agent not found"}

      [] ->
        {:error, :not_found, "No session found for agent"}
    end
  end

  defp link_commits_to_tasks(_session_id, _hashes, []), do: []

  defp link_commits_to_tasks(session_id, hashes, task_ids) do
    case resolve_task_ids(task_ids) do
      {:ok, resolved_task_ids} ->
        hashes
        |> Enum.flat_map(fn hash ->
          case Commits.get_commit_by_session_and_hash(session_id, hash) do
            %{id: commit_id} ->
              Enum.each(resolved_task_ids, &Commits.link_commit_to_task(commit_id, &1))
              []

            _ ->
              [%{commit_hash: hash, error: "commit not found for task linkage"}]
          end
        end)

      {:error, errors} ->
        errors
    end
  end

  defp resolve_task_ids(task_ids) do
    {ids, errors} =
      task_ids
      |> Enum.reduce({[], []}, fn task_id, {ids, errors} ->
        case Tasks.get_task_ids(task_id) do
          {:ok, {id, _uuid}} ->
            {[id | ids], errors}

          {:error, _reason} ->
            {ids, [%{task_id: task_id, error: "task not found"} | errors]}
        end
      end)

    if errors == [] do
      {:ok, Enum.reverse(ids)}
    else
      {:error, Enum.reverse(errors)}
    end
  end

  defp resolve_commit_target(session_identity, _agent_uuid)
       when is_binary(session_identity) and session_identity != "" do
    case SessionResolver.resolve(session_identity) do
      {:ok, session} -> {:ok, session, session.agent_id}
      _ -> {:error, :session_not_found}
    end
  end

  defp resolve_commit_target(session_identity, _agent_uuid) when is_integer(session_identity) do
    case SessionResolver.resolve(session_identity) do
      {:ok, session} -> {:ok, session, session.agent_id}
      _ -> {:error, :session_not_found}
    end
  end

  defp resolve_commit_target(_session_identity, agent_uuid) do
    with {:ok, agent} <- resolve_agent(agent_uuid),
         [session | _] <- Sessions.list_sessions_for_agent(agent.id, limit: 1) do
      {:ok, session, agent.id}
    end
  end

  defp resolve_agent(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> Agents.get_agent(id)
      _ -> Agents.get_agent_by_uuid(value)
    end
  end

  defp resolve_agent(id) when is_integer(id), do: Agents.get_agent(id)

  defp blank?(value), do: is_nil(value) or value == ""
end
