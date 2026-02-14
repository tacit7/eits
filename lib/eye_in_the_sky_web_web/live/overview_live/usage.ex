defmodule EyeInTheSkyWebWeb.OverviewLive.Usage do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.Repo

  @impl true
  def mount(_params, _session, socket) do
    {totals, model_breakdown, top_sessions} = load_metrics()

    socket =
      socket
      |> assign(:page_title, "Usage")
      |> assign(:totals, totals)
      |> assign(:model_breakdown, model_breakdown)
      |> assign(:top_sessions, top_sessions)

    {:ok, socket}
  end

  @impl true
  def handle_event("recalculate", _params, socket) do
    {ingested, skipped, errors} =
      EyeInTheSkyWeb.Metrics.TokenIngestion.ingest_all(force: true)

    {totals, model_breakdown, top_sessions} = load_metrics()

    socket =
      socket
      |> assign(:totals, totals)
      |> assign(:model_breakdown, model_breakdown)
      |> assign(:top_sessions, top_sessions)
      |> put_flash(:info, "Ingested #{ingested}, skipped #{skipped}, errors #{errors}")

    {:noreply, socket}
  end

  defp load_metrics do
    totals = load_totals()
    model_breakdown = load_model_breakdown()
    top_sessions = load_top_sessions()
    {totals, model_breakdown, top_sessions}
  end

  defp load_totals do
    {:ok, %{rows: [[cost, tokens, requests, sessions, subagents]]}} =
      Repo.query("""
      SELECT
        COALESCE(SUM(estimated_cost_usd), 0),
        COALESCE(SUM(tokens_used), 0),
        COALESCE(SUM(request_count), 0),
        COUNT(*),
        COALESCE(SUM(subagent_count), 0)
      FROM session_metrics
      """)

    %{
      cost: cost || 0.0,
      tokens: tokens || 0,
      requests: requests || 0,
      sessions: sessions || 0,
      subagents: subagents || 0
    }
  end

  defp load_model_breakdown do
    {:ok, %{rows: rows}} =
      Repo.query("""
      SELECT
        model_name,
        COUNT(*) as sessions,
        COALESCE(SUM(input_tokens), 0),
        COALESCE(SUM(output_tokens), 0),
        COALESCE(SUM(cache_read_input_tokens), 0),
        COALESCE(SUM(cache_creation_input_tokens), 0),
        COALESCE(SUM(estimated_cost_usd), 0),
        COALESCE(SUM(request_count), 0)
      FROM session_metrics
      WHERE model_name IS NOT NULL AND model_name != 'unknown'
      GROUP BY model_name
      ORDER BY SUM(estimated_cost_usd) DESC
      """)

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

  defp load_top_sessions do
    {:ok, %{rows: rows}} =
      Repo.query("""
      SELECT
        s.name,
        s.uuid,
        sm.model_name,
        COALESCE(sm.input_tokens, 0),
        COALESCE(sm.output_tokens, 0),
        COALESCE(sm.cache_read_input_tokens, 0),
        COALESCE(sm.cache_creation_input_tokens, 0),
        COALESCE(sm.request_count, 0),
        COALESCE(sm.subagent_count, 0),
        COALESCE(sm.estimated_cost_usd, 0)
      FROM session_metrics sm
      JOIN sessions s ON s.id = sm.session_id
      ORDER BY sm.estimated_cost_usd DESC
      LIMIT 15
      """)

    Enum.map(rows, fn [name, uuid, model, input, output, cache_read, cache_create, requests, subagents, cost] ->
      %{
        name: name || "Unnamed session",
        uuid: uuid,
        model: model,
        input_tokens: input,
        output_tokens: output,
        cache_read: cache_read,
        cache_create: cache_create,
        requests: requests,
        subagents: subagents,
        cost: cost
      }
    end)
  end

  defp format_cost(value) when is_float(value), do: "$#{:erlang.float_to_binary(value, decimals: 2)}"
  defp format_cost(value) when is_integer(value), do: "$#{:erlang.float_to_binary(value / 1, decimals: 2)}"
  defp format_cost(_), do: "$0.00"

  defp format_number(value) when is_integer(value) do
    value
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end

  defp format_number(value) when is_float(value), do: format_number(trunc(value))
  defp format_number(_), do: "0"

  defp short_model(name) do
    case name do
      "claude-opus-4-6" -> "Opus 4.6"
      "claude-sonnet-4-5-20250929" -> "Sonnet 4.5"
      "claude-haiku-4-5-20251001" -> "Haiku 4.5"
      other -> other
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.live_component module={EyeInTheSkyWebWeb.Components.Navbar} id="navbar" />
    <EyeInTheSkyWebWeb.Components.OverviewNav.render current_tab={:usage} />

    <div class="px-4 sm:px-6 lg:px-8 py-8">
      <div class="max-w-7xl mx-auto space-y-8">
        <div class="flex justify-end">
          <button phx-click="recalculate" class="btn btn-sm btn-outline">
            <.icon name="hero-arrow-path" class="size-4" />
            Recalculate
          </button>
        </div>
        <%!-- Top-level stat cards --%>
        <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-5 gap-4">
          <div class="card bg-base-100 border border-base-300 shadow-sm">
            <div class="card-body p-4 text-center">
              <p class="text-xs text-base-content/60 uppercase tracking-wider">Total Cost</p>
              <p class="text-3xl font-bold text-warning">{format_cost(@totals.cost)}</p>
            </div>
          </div>
          <div class="card bg-base-100 border border-base-300 shadow-sm">
            <div class="card-body p-4 text-center">
              <p class="text-xs text-base-content/60 uppercase tracking-wider">Total Tokens</p>
              <p class="text-3xl font-bold text-base-content">{format_number(@totals.tokens)}</p>
            </div>
          </div>
          <div class="card bg-base-100 border border-base-300 shadow-sm">
            <div class="card-body p-4 text-center">
              <p class="text-xs text-base-content/60 uppercase tracking-wider">Total Requests</p>
              <p class="text-3xl font-bold text-base-content">{format_number(@totals.requests)}</p>
            </div>
          </div>
          <div class="card bg-base-100 border border-base-300 shadow-sm">
            <div class="card-body p-4 text-center">
              <p class="text-xs text-base-content/60 uppercase tracking-wider">Sessions w/ Metrics</p>
              <p class="text-3xl font-bold text-info">{format_number(@totals.sessions)}</p>
            </div>
          </div>
          <div class="card bg-base-100 border border-base-300 shadow-sm">
            <div class="card-body p-4 text-center">
              <p class="text-xs text-base-content/60 uppercase tracking-wider">Total Subagents</p>
              <p class="text-3xl font-bold text-base-content">{format_number(@totals.subagents)}</p>
            </div>
          </div>
        </div>

        <%!-- Model Breakdown --%>
        <div class="card bg-base-100 border border-base-300 shadow-sm">
          <div class="card-body p-4">
            <h2 class="text-lg font-semibold mb-3">Per-Model Breakdown</h2>
            <div class="overflow-x-auto">
              <table class="table table-sm">
                <thead>
                  <tr class="text-base-content/60">
                    <th>Model</th>
                    <th class="text-right">Sessions</th>
                    <th class="text-right">Input Tokens</th>
                    <th class="text-right">Output Tokens</th>
                    <th class="text-right">Cache Read</th>
                    <th class="text-right">Cache Create</th>
                    <th class="text-right">Requests</th>
                    <th class="text-right">Cost</th>
                    <th class="text-right">Avg/Session</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={row <- @model_breakdown} class="hover">
                    <td class="font-medium">{short_model(row.model)}</td>
                    <td class="text-right">{format_number(row.sessions)}</td>
                    <td class="text-right">{format_number(row.input_tokens)}</td>
                    <td class="text-right">{format_number(row.output_tokens)}</td>
                    <td class="text-right">{format_number(row.cache_read)}</td>
                    <td class="text-right">{format_number(row.cache_create)}</td>
                    <td class="text-right">{format_number(row.requests)}</td>
                    <td class="text-right font-medium text-warning">{format_cost(row.cost)}</td>
                    <td class="text-right">{format_cost(row.avg_cost)}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>

        <%!-- Top Sessions by Cost --%>
        <div class="card bg-base-100 border border-base-300 shadow-sm">
          <div class="card-body p-4">
            <h2 class="text-lg font-semibold mb-3">Top Sessions by Cost</h2>
            <div class="overflow-x-auto">
              <table class="table table-sm">
                <thead>
                  <tr class="text-base-content/60">
                    <th>Session</th>
                    <th>Model</th>
                    <th class="text-right">Input</th>
                    <th class="text-right">Output</th>
                    <th class="text-right">Cache Read</th>
                    <th class="text-right">Cache Create</th>
                    <th class="text-right">Requests</th>
                    <th class="text-right">Subagents</th>
                    <th class="text-right">Cost</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={row <- @top_sessions} class="hover">
                    <td class="max-w-xs truncate">
                      <a href={"/dm/#{row.uuid}"} class="link link-hover link-primary">
                        {row.name}
                      </a>
                    </td>
                    <td class="whitespace-nowrap">{short_model(row.model)}</td>
                    <td class="text-right">{format_number(row.input_tokens)}</td>
                    <td class="text-right">{format_number(row.output_tokens)}</td>
                    <td class="text-right">{format_number(row.cache_read)}</td>
                    <td class="text-right">{format_number(row.cache_create)}</td>
                    <td class="text-right">{format_number(row.requests)}</td>
                    <td class="text-right">{format_number(row.subagents)}</td>
                    <td class="text-right font-medium text-warning">{format_cost(row.cost)}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
