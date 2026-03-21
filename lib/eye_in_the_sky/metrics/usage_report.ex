defmodule EyeInTheSky.Metrics.UsageReport do
  @moduledoc """
  Query functions for the Usage LiveView dashboard.
  All queries operate on the session_metrics table.
  """

  alias EyeInTheSky.Repo

  @doc """
  Aggregate totals (cost, tokens, requests, sessions, subagents) for the given cutoff.
  """
  def totals(cutoff) do
    {join, params} =
      case cutoff do
        nil ->
          {"", []}

        ts ->
          {"JOIN sessions s ON s.id = session_metrics.session_id AND s.started_at >= $1", [ts]}
      end

    {:ok, %{rows: [[cost, tokens, requests, sessions, subagents]]}} =
      Repo.query(
        """
        SELECT
          COALESCE(SUM(estimated_cost_usd), 0),
          COALESCE(SUM(tokens_used), 0),
          COALESCE(SUM(request_count), 0),
          COUNT(*),
          COALESCE(SUM(subagent_count), 0)
        FROM session_metrics
        #{join}
        """,
        params
      )

    %{
      cost: cost || 0.0,
      tokens: tokens || 0,
      requests: requests || 0,
      sessions: sessions || 0,
      subagents: subagents || 0
    }
  end

  @doc """
  Per-model breakdown sorted by cost desc for the given cutoff.
  """
  def model_breakdown(cutoff) do
    {join, params} =
      case cutoff do
        nil -> {"", []}
        ts -> {"JOIN sessions s ON s.id = sm.session_id AND s.started_at >= $1", [ts]}
      end

    {:ok, %{rows: rows}} =
      Repo.query(
        """
        SELECT
          sm.model_name,
          COUNT(*) as sessions,
          COALESCE(SUM(sm.input_tokens), 0),
          COALESCE(SUM(sm.output_tokens), 0),
          COALESCE(SUM(sm.cache_read_input_tokens), 0),
          COALESCE(SUM(sm.cache_creation_input_tokens), 0),
          COALESCE(SUM(sm.estimated_cost_usd), 0),
          COALESCE(SUM(sm.request_count), 0)
        FROM session_metrics sm
        #{join}
        WHERE sm.model_name IS NOT NULL AND sm.model_name != 'unknown'
        GROUP BY sm.model_name
        ORDER BY SUM(sm.estimated_cost_usd) DESC
        """,
        params
      )

    Enum.map(rows, fn [model, sessions, input, output, cache_read, cache_create, cost, requests] ->
      avg_cost = if sessions > 0, do: cost / sessions, else: 0.0

      %{
        model: model,
        sessions: sessions,
        input_tokens: input,
        output_tokens: output,
        cache_read: cache_read,
        cache_create: cache_create,
        cost: cost,
        requests: requests,
        avg_cost: avg_cost
      }
    end)
  end

  @doc """
  Per-project breakdown sorted by cost desc for the given cutoff.
  """
  def by_project(cutoff) do
    {where, params} = date_filter(cutoff)

    {:ok, %{rows: rows}} =
      Repo.query(
        """
        SELECT
          COALESCE(p.name, 'No Project') as project_name,
          COUNT(DISTINCT sm.session_id) as session_count,
          COALESCE(SUM(sm.input_tokens), 0),
          COALESCE(SUM(sm.output_tokens), 0),
          COALESCE(SUM(sm.request_count), 0),
          COALESCE(SUM(sm.subagent_count), 0),
          COALESCE(SUM(sm.estimated_cost_usd), 0)
        FROM session_metrics sm
        JOIN sessions s ON s.id = sm.session_id
        LEFT JOIN projects p ON p.id = s.project_id
        WHERE 1=1 #{where}
        GROUP BY p.name
        ORDER BY SUM(sm.estimated_cost_usd) DESC
        """,
        params
      )

    Enum.map(rows, fn [project, sessions, input, output, requests, subagents, cost] ->
      %{
        project: project,
        sessions: sessions,
        input_tokens: input,
        output_tokens: output,
        requests: requests,
        subagents: subagents,
        cost: cost
      }
    end)
  end

  @doc """
  Top 50 sessions by cost for the given cutoff.
  """
  def top_sessions(cutoff) do
    {where, params} = date_filter(cutoff)

    {:ok, %{rows: rows}} =
      Repo.query(
        """
        SELECT
          s.name,
          s.uuid,
          COALESCE(p.name, 'No Project') as project_name,
          sm.model_name,
          COALESCE(sm.input_tokens, 0),
          COALESCE(sm.output_tokens, 0),
          COALESCE(sm.cache_read_input_tokens, 0),
          COALESCE(sm.cache_creation_input_tokens, 0),
          COALESCE(sm.request_count, 0),
          COALESCE(sm.subagent_count, 0),
          COALESCE(sm.estimated_cost_usd, 0),
          s.started_at
        FROM session_metrics sm
        JOIN sessions s ON s.id = sm.session_id
        LEFT JOIN projects p ON p.id = s.project_id
        WHERE 1=1 #{where}
        ORDER BY sm.estimated_cost_usd DESC
        LIMIT 50
        """,
        params
      )

    Enum.map(rows, fn [
                        name,
                        uuid,
                        project,
                        model,
                        input,
                        output,
                        cache_read,
                        cache_create,
                        requests,
                        subagents,
                        cost,
                        started_at
                      ] ->
      %{
        name: name || "Unnamed session",
        uuid: uuid,
        project: project,
        model: model,
        input_tokens: input,
        output_tokens: output,
        cache_read: cache_read,
        cache_create: cache_create,
        requests: requests,
        subagents: subagents,
        cost: cost,
        started_at: started_at
      }
    end)
  end

  @doc """
  Monthly aggregates, all time, descending.
  """
  def by_month do
    {:ok, %{rows: rows}} =
      Repo.query("""
      SELECT
        TO_CHAR(s.started_at::timestamp, 'YYYY-MM') as month,
        COUNT(DISTINCT sm.session_id),
        COALESCE(SUM(sm.input_tokens), 0),
        COALESCE(SUM(sm.output_tokens), 0),
        COALESCE(SUM(sm.request_count), 0),
        COALESCE(SUM(sm.estimated_cost_usd), 0)
      FROM session_metrics sm
      JOIN sessions s ON s.id = sm.session_id
      WHERE s.started_at IS NOT NULL
      GROUP BY month
      ORDER BY month DESC
      """)

    Enum.map(rows, fn [month, sessions, input, output, requests, cost] ->
      %{
        period: month,
        sessions: sessions,
        input_tokens: input,
        output_tokens: output,
        total_tokens: input + output,
        requests: requests,
        cost: cost
      }
    end)
  end

  @doc """
  Weekly aggregates for the last 26 weeks, descending.
  """
  def by_week do
    {:ok, %{rows: rows}} =
      Repo.query("""
      SELECT
        TO_CHAR(DATE_TRUNC('week', s.started_at::timestamp), 'YYYY-MM-DD') as week_start,
        COUNT(DISTINCT sm.session_id),
        COALESCE(SUM(sm.input_tokens), 0),
        COALESCE(SUM(sm.output_tokens), 0),
        COALESCE(SUM(sm.request_count), 0),
        COALESCE(SUM(sm.estimated_cost_usd), 0)
      FROM session_metrics sm
      JOIN sessions s ON s.id = sm.session_id
      WHERE s.started_at IS NOT NULL
      GROUP BY week_start
      ORDER BY week_start DESC
      LIMIT 26
      """)

    Enum.map(rows, fn [week, sessions, input, output, requests, cost] ->
      %{
        period: week,
        sessions: sessions,
        input_tokens: input,
        output_tokens: output,
        total_tokens: input + output,
        requests: requests,
        cost: cost
      }
    end)
  end

  # ── Private helpers ──────────────────────────────────────────────────────

  defp date_filter(nil), do: {"", []}
  defp date_filter(cutoff), do: {"AND s.started_at >= $1", [cutoff]}
end
