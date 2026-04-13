defmodule EyeInTheSkyWeb.OverviewLive.Usage do
  use EyeInTheSkyWeb, :live_view

  import EyeInTheSkyWeb.Components.UsageComponents

  alias EyeInTheSky.Metrics.TokenIngestion
  alias EyeInTheSky.Metrics.UsageReport

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
    %{ingested: ingested, skipped: skipped, errors: errors} =
      TokenIngestion.ingest_all(force: true)

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
        DateTime.utc_now()
        |> DateTime.add(-days * 86_400, :second)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8 py-8">
      <div class="max-w-7xl mx-auto space-y-8">
        <.usage_header date_range={@date_range} recalculating={@recalculating} />
        <.usage_totals totals={@totals} recalculating={@recalculating} />
        <.project_breakdown_table by_project={@by_project} recalculating={@recalculating} />
        <.by_month_table by_month={@by_month} />
        <.by_week_table by_week={@by_week} />
        <.model_breakdown_table model_breakdown={@model_breakdown} recalculating={@recalculating} />
        <.top_sessions_table top_sessions={@top_sessions} recalculating={@recalculating} />
      </div>
    </div>
    """
  end
end
