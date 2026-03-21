defmodule EyeInTheSky.Metrics.TokenIngestion do
  @moduledoc """
  Orchestrates token usage ingestion from Claude JSONL session files
  into the session_metrics table. All DB writes use raw SQL via Repo.query!/2.
  """

  alias EyeInTheSky.Repo
  alias EyeInTheSky.Claude.SessionReader
  alias EyeInTheSky.Metrics.TokenParser
  alias EyeInTheSky.Settings

  @doc """
  Ingest token usage for all discovered sessions.

  Options:
  - `:force` - re-process sessions that already have metrics (default: false)

  Returns `{ingested, skipped, errors}` counts.
  """
  def ingest_all(opts \\ []) do
    force = Keyword.get(opts, :force, false)
    sessions = SessionReader.discover_all_sessions()

    existing_session_ids =
      if force do
        MapSet.new()
      else
        fetch_existing_metric_session_ids()
      end

    sessions
    |> Enum.reduce({0, 0, 0}, fn session_info, {ingested, skipped, errors} ->
      session_uuid = session_info.session_id

      case lookup_session_by_uuid(session_uuid) do
        nil ->
          {ingested, skipped + 1, errors}

        %{id: session_id, agent_id: agent_id} ->
          if MapSet.member?(existing_session_ids, session_id) do
            {ingested, skipped + 1, errors}
          else
            file_path = build_file_path(session_info)

            case ingest_one(file_path, session_id, agent_id) do
              :ok -> {ingested + 1, skipped, errors}
              {:error, _reason} -> {ingested, skipped, errors + 1}
            end
          end
      end
    end)
  end

  @doc """
  Ingest token usage for a single session by UUID.

  Returns `:ok` or `{:error, reason}`.
  """
  def ingest_session(session_uuid) do
    case lookup_session_by_uuid(session_uuid) do
      nil ->
        {:error, :session_not_found}

      %{id: session_id, agent_id: agent_id} ->
        sessions = SessionReader.discover_all_sessions()

        case Enum.find(sessions, fn s -> s.session_id == session_uuid end) do
          nil ->
            {:error, :jsonl_not_found}

          session_info ->
            file_path = build_file_path(session_info)
            ingest_one(file_path, session_id, agent_id)
        end
    end
  end

  # -- Private --

  defp ingest_one(file_path, session_id, agent_id) do
    case TokenParser.parse_session(file_path) do
      {:ok, usage} ->
        primary_model = primary_model_name(usage.models)
        cost = calculate_cost(usage, primary_model)
        notes_json = Jason.encode!(%{models: usage.models})

        upsert_metrics(
          session_id,
          agent_id,
          usage,
          cost,
          primary_model,
          notes_json
        )

        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp upsert_metrics(session_id, agent_id, usage, cost, model_name, notes_json) do
    sql = """
    INSERT INTO session_metrics (
      session_id, agent_id, tokens_used, tokens_budget, tokens_remaining,
      input_tokens, output_tokens, cache_creation_input_tokens, cache_read_input_tokens,
      estimated_cost_usd, model_name, request_count, subagent_count, notes, timestamp
    ) VALUES ($1, $2, $3, 0, 0, $4, $5, $6, $7, $8, $9, $10, $11, $12, NOW())
    ON CONFLICT(session_id) DO UPDATE SET
      agent_id = excluded.agent_id,
      tokens_used = excluded.tokens_used,
      input_tokens = excluded.input_tokens,
      output_tokens = excluded.output_tokens,
      cache_creation_input_tokens = excluded.cache_creation_input_tokens,
      cache_read_input_tokens = excluded.cache_read_input_tokens,
      estimated_cost_usd = excluded.estimated_cost_usd,
      model_name = excluded.model_name,
      request_count = excluded.request_count,
      subagent_count = excluded.subagent_count,
      notes = excluded.notes,
      timestamp = excluded.timestamp
    """

    Repo.query!(sql, [
      session_id,
      agent_id,
      usage.total_tokens,
      usage.input_tokens,
      usage.output_tokens,
      usage.cache_creation_input_tokens,
      usage.cache_read_input_tokens,
      cost,
      model_name,
      usage.request_count,
      usage.subagent_count,
      notes_json
    ])
  end

  defp lookup_session_by_uuid(uuid) do
    result = Repo.query!("SELECT id, agent_id FROM sessions WHERE uuid = $1", [uuid])

    case result.rows do
      [[id, agent_id] | _] -> %{id: id, agent_id: agent_id}
      _ -> nil
    end
  end

  defp fetch_existing_metric_session_ids do
    result = Repo.query!("SELECT session_id FROM session_metrics", [])

    result.rows
    |> Enum.map(fn [sid] -> sid end)
    |> MapSet.new()
  end

  defp build_file_path(session_info) do
    home = System.get_env("HOME")
    escaped_path = SessionReader.escape_project_path(session_info.project_path)
    Path.join([home, ".claude", "projects", escaped_path, "#{session_info.session_id}.jsonl"])
  end

  defp primary_model_name(models) when map_size(models) == 0, do: "unknown"

  defp primary_model_name(models) do
    models
    |> Enum.max_by(fn {_model, count} -> count end)
    |> elem(0)
  end

  @doc false
  def calculate_cost(usage, model_name) do
    pricing = Settings.pricing()
    tier = detect_pricing_tier(model_name)
    prices = Map.get(pricing, tier, pricing["sonnet"])

    input_cost = usage.input_tokens * prices.input / 1_000_000
    output_cost = usage.output_tokens * prices.output / 1_000_000
    cache_read_cost = usage.cache_read_input_tokens * prices.cache_read / 1_000_000
    cache_creation_cost = usage.cache_creation_input_tokens * prices.cache_creation / 1_000_000

    Float.round(input_cost + output_cost + cache_read_cost + cache_creation_cost, 6)
  end

  defp detect_pricing_tier(model_name) when is_binary(model_name) do
    cond do
      String.contains?(model_name, "opus") -> "opus"
      String.contains?(model_name, "haiku") -> "haiku"
      String.contains?(model_name, "sonnet") -> "sonnet"
      true -> "sonnet"
    end
  end

  defp detect_pricing_tier(_), do: "sonnet"
end
