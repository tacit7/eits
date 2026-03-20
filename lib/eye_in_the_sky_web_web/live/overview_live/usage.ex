defmodule EyeInTheSkyWebWeb.OverviewLive.Usage do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.Metrics.UsageReport
  alias EyeInTheSkyWebWeb.Helpers.ViewHelpers

  @date_ranges %{"7d" => 7, "30d" => 30, "all" => nil}

  @impl true
  def mount(_params, _session, socket) do
    range = "30d"

    socket =
      socket
      |> assign(:page_title, "Usage")
      |> assign(:sidebar_tab, :usage)
      |> assign(:sidebar_project, nil)
      |> assign(:recalculating, false)
      |> assign(:date_range, range)
      |> load_all(range)

    {:ok, socket}
  end

  @impl true
  def handle_event("set_range", %{"range" => range}, socket)
      when is_map_key(@date_ranges, range) do
    {:noreply, socket |> assign(:date_range, range) |> load_all(range)}
  end

  def handle_event("set_range", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("recalculate", _params, socket) do
    send(self(), :do_recalculate)
    {:noreply, assign(socket, :recalculating, true)}
  end

  @impl true
  def handle_info(:do_recalculate, socket) do
    {ingested, skipped, errors} =
      EyeInTheSkyWeb.Metrics.TokenIngestion.ingest_all(force: true)

    socket =
      socket
      |> load_all(socket.assigns.date_range)
      |> assign(:recalculating, false)
      |> put_flash(:info, "Ingested #{ingested}, skipped #{skipped}, errors #{errors}")

    {:noreply, socket}
  end

  defp load_all(socket, range) do
    cutoff = cutoff_timestamp(range)

    socket
    |> assign(:totals, UsageReport.totals(cutoff))
    |> assign(:model_breakdown, UsageReport.model_breakdown(cutoff))
    |> assign(:by_project, UsageReport.by_project(cutoff))
    |> assign(:top_sessions, UsageReport.top_sessions(cutoff))
    |> assign(:by_month, UsageReport.by_month())
    |> assign(:by_week, UsageReport.by_week())
  end

  defp cutoff_timestamp(range) do
    case Map.get(@date_ranges, range) do
      nil ->
        nil

      days ->
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-days * 86400, :second)
        |> NaiveDateTime.to_string()
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8 py-8">
      <div class="max-w-7xl mx-auto space-y-8">
        <%!-- Header --%>
        <div class="flex items-center justify-between">
          <div class="join">
            <button
              phx-click="set_range"
              phx-value-range="7d"
              class={[
                "join-item btn btn-sm",
                if(@date_range == "7d", do: "btn-primary", else: "btn-outline")
              ]}
            >
              7d
            </button>
            <button
              phx-click="set_range"
              phx-value-range="30d"
              class={[
                "join-item btn btn-sm",
                if(@date_range == "30d", do: "btn-primary", else: "btn-outline")
              ]}
            >
              30d
            </button>
            <button
              phx-click="set_range"
              phx-value-range="all"
              class={[
                "join-item btn btn-sm",
                if(@date_range == "all", do: "btn-primary", else: "btn-outline")
              ]}
            >
              All time
            </button>
          </div>
          <button phx-click="recalculate" disabled={@recalculating} class="btn btn-sm btn-outline">
            <.icon
              name="hero-arrow-path"
              class={if @recalculating, do: "size-4 animate-spin", else: "size-4"}
            />
            {if @recalculating, do: "Recalculating...", else: "Recalculate"}
          </button>
        </div>

        <%!-- Top-level stat cards --%>
        <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-5 gap-4">
          <%= if @recalculating do %>
            <div :for={_ <- 1..5} class="card bg-base-100 border border-base-300 shadow-sm">
              <div class="card-body p-4 text-center space-y-2">
                <div class="skeleton h-3 w-20 mx-auto"></div>
                <div class="skeleton h-8 w-24 mx-auto"></div>
              </div>
            </div>
          <% else %>
            <div class="card bg-base-100 border border-base-300 shadow-sm">
              <div class="card-body p-4 text-center">
                <p class="text-xs text-base-content/60 uppercase tracking-wider">Total Cost</p>
                <p class="text-3xl font-bold text-warning">
                  {ViewHelpers.format_cost(@totals.cost)}
                </p>
              </div>
            </div>
            <div class="card bg-base-100 border border-base-300 shadow-sm">
              <div class="card-body p-4 text-center">
                <p class="text-xs text-base-content/60 uppercase tracking-wider">Total Tokens</p>
                <p class="text-3xl font-bold text-base-content">
                  {ViewHelpers.format_number(@totals.tokens)}
                </p>
              </div>
            </div>
            <div class="card bg-base-100 border border-base-300 shadow-sm">
              <div class="card-body p-4 text-center">
                <p class="text-xs text-base-content/60 uppercase tracking-wider">Total Requests</p>
                <p class="text-3xl font-bold text-base-content">
                  {ViewHelpers.format_number(@totals.requests)}
                </p>
              </div>
            </div>
            <div class="card bg-base-100 border border-base-300 shadow-sm">
              <div class="card-body p-4 text-center">
                <p class="text-xs text-base-content/60 uppercase tracking-wider">
                  Sessions w/ Metrics
                </p>
                <p class="text-3xl font-bold text-info">
                  {ViewHelpers.format_number(@totals.sessions)}
                </p>
              </div>
            </div>
            <div class="card bg-base-100 border border-base-300 shadow-sm">
              <div class="card-body p-4 text-center">
                <p class="text-xs text-base-content/60 uppercase tracking-wider">Total Subagents</p>
                <p class="text-3xl font-bold text-base-content">
                  {ViewHelpers.format_number(@totals.subagents)}
                </p>
              </div>
            </div>
          <% end %>
        </div>

        <%!-- Per-Project Breakdown --%>
        <div class="card bg-base-100 border border-base-300 shadow-sm">
          <div class="card-body p-4">
            <h2 class="text-lg font-semibold mb-3">By Project</h2>
            <div class="overflow-x-auto">
              <table class="table table-sm">
                <thead>
                  <tr class="text-base-content/60">
                    <th>Project</th>
                    <th class="text-right">Sessions</th>
                    <th class="text-right">Input Tokens</th>
                    <th class="text-right">Output Tokens</th>
                    <th class="text-right">Requests</th>
                    <th class="text-right">Subagents</th>
                    <th class="text-right">Cost</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :if={@by_project == [] && !@recalculating} class="hover">
                    <td colspan="7" class="text-center text-base-content/40 py-6">
                      No data for this period
                    </td>
                  </tr>
                  <%= if @recalculating do %>
                    <tr :for={_ <- 1..5} class="hover">
                      <td :for={_ <- 1..7}>
                        <div class="skeleton h-4 w-full"></div>
                      </td>
                    </tr>
                  <% else %>
                    <tr :for={row <- @by_project} class="hover">
                      <td class="font-medium">{row.project}</td>
                      <td class="text-right">{ViewHelpers.format_number(row.sessions)}</td>
                      <td class="text-right">{ViewHelpers.format_number(row.input_tokens)}</td>
                      <td class="text-right">{ViewHelpers.format_number(row.output_tokens)}</td>
                      <td class="text-right">{ViewHelpers.format_number(row.requests)}</td>
                      <td class="text-right">{ViewHelpers.format_number(row.subagents)}</td>
                      <td class="text-right font-medium text-warning">
                        {ViewHelpers.format_cost(row.cost)}
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>
        </div>

        <%!-- Month by Month --%>
        <div class="card bg-base-100 border border-base-300 shadow-sm">
          <div class="card-body p-4">
            <h2 class="text-lg font-semibold mb-3">By Month</h2>
            <div class="overflow-x-auto">
              <table class="table table-sm">
                <thead>
                  <tr class="text-base-content/60">
                    <th>Month</th>
                    <th class="text-right">Sessions</th>
                    <th class="text-right">Input Tokens</th>
                    <th class="text-right">Output Tokens</th>
                    <th class="text-right">Total Tokens</th>
                    <th class="text-right">Requests</th>
                    <th class="text-right">Cost</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :if={@by_month == []} class="hover">
                    <td colspan="7" class="text-center text-base-content/40 py-6">No data</td>
                  </tr>
                  <tr :for={row <- @by_month} class="hover">
                    <td class="font-medium tabular-nums">{row.period}</td>
                    <td class="text-right">{ViewHelpers.format_number(row.sessions)}</td>
                    <td class="text-right">{ViewHelpers.format_number(row.input_tokens)}</td>
                    <td class="text-right">{ViewHelpers.format_number(row.output_tokens)}</td>
                    <td class="text-right">{ViewHelpers.format_number(row.total_tokens)}</td>
                    <td class="text-right">{ViewHelpers.format_number(row.requests)}</td>
                    <td class="text-right font-medium text-warning">
                      {ViewHelpers.format_cost(row.cost)}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>

        <%!-- Week by Week --%>
        <div class="card bg-base-100 border border-base-300 shadow-sm">
          <div class="card-body p-4">
            <h2 class="text-lg font-semibold mb-3">
              By Week <span class="text-sm font-normal text-base-content/40">(last 26 weeks)</span>
            </h2>
            <div class="overflow-x-auto">
              <table class="table table-sm">
                <thead>
                  <tr class="text-base-content/60">
                    <th>Week of</th>
                    <th class="text-right">Sessions</th>
                    <th class="text-right">Input Tokens</th>
                    <th class="text-right">Output Tokens</th>
                    <th class="text-right">Total Tokens</th>
                    <th class="text-right">Requests</th>
                    <th class="text-right">Cost</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :if={@by_week == []} class="hover">
                    <td colspan="7" class="text-center text-base-content/40 py-6">No data</td>
                  </tr>
                  <tr :for={row <- @by_week} class="hover">
                    <td class="font-medium tabular-nums">{row.period}</td>
                    <td class="text-right">{ViewHelpers.format_number(row.sessions)}</td>
                    <td class="text-right">{ViewHelpers.format_number(row.input_tokens)}</td>
                    <td class="text-right">{ViewHelpers.format_number(row.output_tokens)}</td>
                    <td class="text-right">{ViewHelpers.format_number(row.total_tokens)}</td>
                    <td class="text-right">{ViewHelpers.format_number(row.requests)}</td>
                    <td class="text-right font-medium text-warning">
                      {ViewHelpers.format_cost(row.cost)}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>

        <%!-- Model Breakdown --%>
        <div class="card bg-base-100 border border-base-300 shadow-sm">
          <div class="card-body p-4">
            <h2 class="text-lg font-semibold mb-3">By Model</h2>
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
                  <%= if @recalculating do %>
                    <tr :for={_ <- 1..5} class="hover">
                      <td :for={_ <- 1..9}>
                        <div class="skeleton h-4 w-full"></div>
                      </td>
                    </tr>
                  <% else %>
                    <tr :for={row <- @model_breakdown} class="hover">
                      <td class="font-medium">{ViewHelpers.short_model(row.model)}</td>
                      <td class="text-right">{ViewHelpers.format_number(row.sessions)}</td>
                      <td class="text-right">{ViewHelpers.format_number(row.input_tokens)}</td>
                      <td class="text-right">{ViewHelpers.format_number(row.output_tokens)}</td>
                      <td class="text-right">{ViewHelpers.format_number(row.cache_read)}</td>
                      <td class="text-right">{ViewHelpers.format_number(row.cache_create)}</td>
                      <td class="text-right">{ViewHelpers.format_number(row.requests)}</td>
                      <td class="text-right font-medium text-warning">
                        {ViewHelpers.format_cost(row.cost)}
                      </td>
                      <td class="text-right">{ViewHelpers.format_cost(row.avg_cost)}</td>
                    </tr>
                  <% end %>
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
                    <th>Project</th>
                    <th>Model</th>
                    <th>Date</th>
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
                  <%= if @recalculating do %>
                    <tr :for={_ <- 1..10} class="hover">
                      <td :for={_ <- 1..11}>
                        <div class="skeleton h-4 w-full"></div>
                      </td>
                    </tr>
                  <% else %>
                    <tr :for={row <- @top_sessions} class="hover">
                      <td class="max-w-xs truncate">
                        <a href={"/dm/#{row.uuid}"} class="link link-hover link-primary">
                          {row.name}
                        </a>
                      </td>
                      <td class="text-base-content/60 whitespace-nowrap">{row.project}</td>
                      <td class="whitespace-nowrap">{ViewHelpers.short_model(row.model)}</td>
                      <td class="text-base-content/60 whitespace-nowrap">
                        {ViewHelpers.format_date(row.started_at)}
                      </td>
                      <td class="text-right">{ViewHelpers.format_number(row.input_tokens)}</td>
                      <td class="text-right">{ViewHelpers.format_number(row.output_tokens)}</td>
                      <td class="text-right">{ViewHelpers.format_number(row.cache_read)}</td>
                      <td class="text-right">{ViewHelpers.format_number(row.cache_create)}</td>
                      <td class="text-right">{ViewHelpers.format_number(row.requests)}</td>
                      <td class="text-right">{ViewHelpers.format_number(row.subagents)}</td>
                      <td class="text-right font-medium text-warning">
                        {ViewHelpers.format_cost(row.cost)}
                      </td>
                    </tr>
                  <% end %>
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
