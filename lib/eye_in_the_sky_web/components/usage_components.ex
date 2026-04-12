defmodule EyeInTheSkyWeb.Components.UsageComponents do
  use EyeInTheSkyWeb, :html

  alias EyeInTheSkyWeb.Helpers.ViewHelpers

  attr :date_range, :string, required: true
  attr :recalculating, :boolean, required: true

  def usage_header(assigns) do
    ~H"""
    <div class="flex items-center justify-between">
      <div class="join">
        <button
          phx-click="set_range"
          phx-value-range="7d"
          class={[
            "join-item btn btn-sm min-h-[44px]",
            if(@date_range == "7d", do: "btn-primary", else: "btn-outline")
          ]}
        >
          7d
        </button>
        <button
          phx-click="set_range"
          phx-value-range="30d"
          class={[
            "join-item btn btn-sm min-h-[44px]",
            if(@date_range == "30d", do: "btn-primary", else: "btn-outline")
          ]}
        >
          30d
        </button>
        <button
          phx-click="set_range"
          phx-value-range="all"
          class={[
            "join-item btn btn-sm min-h-[44px]",
            if(@date_range == "all", do: "btn-primary", else: "btn-outline")
          ]}
        >
          All time
        </button>
      </div>
      <button phx-click="recalculate" disabled={@recalculating} class="btn btn-sm min-h-[44px] btn-outline">
        <.icon
          name="hero-arrow-path"
          class={if @recalculating, do: "size-4 animate-spin", else: "size-4"}
        />
        {if @recalculating, do: "Recalculating...", else: "Recalculate"}
      </button>
    </div>
    """
  end

  attr :totals, :map, required: true
  attr :recalculating, :boolean, required: true

  def usage_totals(assigns) do
    ~H"""
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
    """
  end

  # ── Generic usage table ──────────────────────────────────────────────────────
  #
  # Each column_def is a map with:
  #   label       - header text (required)
  #   key         - atom key to read from each row map (required)
  #   format      - :plain | :number | :cost | :short_model | :date | :link (required)
  #   class       - <td> CSS class string (optional, default "")
  #   link_key    - atom key for the href suffix (required when format: :link)
  #   link_prefix - URL prefix string, e.g. "/dm/" (required when format: :link)

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :rows, :list, required: true
  attr :column_defs, :list, required: true
  attr :recalculating, :boolean, default: false
  attr :empty_message, :string, default: "No data"
  attr :loading_rows, :integer, default: 5

  def usage_table(assigns) do
    ~H"""
    <div class="card bg-base-100 border border-base-300 shadow-sm">
      <div class="card-body p-4">
        <h2 class="text-lg font-semibold mb-3">
          {@title}
          <span :if={@subtitle} class="text-sm font-normal text-base-content/40">{@subtitle}</span>
        </h2>
        <div class="overflow-x-auto">
          <table class="table table-sm">
            <thead>
              <tr class="text-base-content/60">
                <th :for={col <- @column_defs} class={header_class(col)}>
                  {col.label}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr :if={@rows == [] && !@recalculating} class="hover">
                <td colspan={length(@column_defs)} class="text-center text-base-content/40 py-6">
                  {@empty_message}
                </td>
              </tr>
              <%= if @recalculating do %>
                <tr :for={_ <- 1..@loading_rows} class="hover">
                  <td :for={_ <- 1..length(@column_defs)}>
                    <div class="skeleton h-4 w-full"></div>
                  </td>
                </tr>
              <% else %>
                <tr :for={row <- @rows} class="hover">
                  <td :for={col <- @column_defs} class={col[:class] || ""}>
                    <%= if col.format == :link do %>
                      <a
                        href={"#{col.link_prefix}#{Map.get(row, col.link_key)}"}
                        class="link link-hover link-primary"
                      >
                        {Map.get(row, col.key)}
                      </a>
                    <% else %>
                      {render_cell(Map.get(row, col.key), col.format)}
                    <% end %>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  # ── Table wrappers (preserve existing public API) ────────────────────────────

  attr :by_project, :list, required: true
  attr :recalculating, :boolean, required: true

  def project_breakdown_table(assigns) do
    ~H"""
    <.usage_table
      title="By Project"
      rows={@by_project}
      column_defs={project_column_defs()}
      recalculating={@recalculating}
      empty_message="No data for this period"
    />
    """
  end

  attr :by_month, :list, required: true

  def by_month_table(assigns) do
    ~H"""
    <.usage_table title="By Month" rows={@by_month} column_defs={month_column_defs()} />
    """
  end

  attr :by_week, :list, required: true

  def by_week_table(assigns) do
    ~H"""
    <.usage_table
      title="By Week"
      subtitle="(last 26 weeks)"
      rows={@by_week}
      column_defs={week_column_defs()}
    />
    """
  end

  attr :model_breakdown, :list, required: true
  attr :recalculating, :boolean, required: true

  def model_breakdown_table(assigns) do
    ~H"""
    <.usage_table
      title="By Model"
      rows={@model_breakdown}
      column_defs={model_column_defs()}
      recalculating={@recalculating}
    />
    """
  end

  attr :top_sessions, :list, required: true
  attr :recalculating, :boolean, required: true

  def top_sessions_table(assigns) do
    ~H"""
    <.usage_table
      title="Top Sessions by Cost"
      rows={@top_sessions}
      column_defs={sessions_column_defs()}
      recalculating={@recalculating}
      loading_rows={10}
    />
    """
  end

  # ── Column definitions ───────────────────────────────────────────────────────

  defp project_column_defs do
    [
      %{label: "Project", key: :project, format: :plain, class: "font-medium"},
      %{label: "Sessions", key: :sessions, format: :number, class: "text-right"},
      %{label: "Input Tokens", key: :input_tokens, format: :number, class: "text-right"},
      %{label: "Output Tokens", key: :output_tokens, format: :number, class: "text-right"},
      %{label: "Requests", key: :requests, format: :number, class: "text-right"},
      %{label: "Subagents", key: :subagents, format: :number, class: "text-right"},
      %{label: "Cost", key: :cost, format: :cost, class: "text-right font-medium text-warning"}
    ]
  end

  defp month_column_defs do
    [
      %{label: "Month", key: :period, format: :plain, class: "font-medium tabular-nums"},
      %{label: "Sessions", key: :sessions, format: :number, class: "text-right"},
      %{label: "Input Tokens", key: :input_tokens, format: :number, class: "text-right"},
      %{label: "Output Tokens", key: :output_tokens, format: :number, class: "text-right"},
      %{label: "Total Tokens", key: :total_tokens, format: :number, class: "text-right"},
      %{label: "Requests", key: :requests, format: :number, class: "text-right"},
      %{label: "Cost", key: :cost, format: :cost, class: "text-right font-medium text-warning"}
    ]
  end

  defp week_column_defs do
    [
      %{label: "Week of", key: :period, format: :plain, class: "font-medium tabular-nums"},
      %{label: "Sessions", key: :sessions, format: :number, class: "text-right"},
      %{label: "Input Tokens", key: :input_tokens, format: :number, class: "text-right"},
      %{label: "Output Tokens", key: :output_tokens, format: :number, class: "text-right"},
      %{label: "Total Tokens", key: :total_tokens, format: :number, class: "text-right"},
      %{label: "Requests", key: :requests, format: :number, class: "text-right"},
      %{label: "Cost", key: :cost, format: :cost, class: "text-right font-medium text-warning"}
    ]
  end

  defp model_column_defs do
    [
      %{label: "Model", key: :model, format: :short_model, class: "font-medium"},
      %{label: "Sessions", key: :sessions, format: :number, class: "text-right"},
      %{label: "Input Tokens", key: :input_tokens, format: :number, class: "text-right"},
      %{label: "Output Tokens", key: :output_tokens, format: :number, class: "text-right"},
      %{label: "Cache Read", key: :cache_read, format: :number, class: "text-right"},
      %{label: "Cache Create", key: :cache_create, format: :number, class: "text-right"},
      %{label: "Requests", key: :requests, format: :number, class: "text-right"},
      %{label: "Cost", key: :cost, format: :cost, class: "text-right font-medium text-warning"},
      %{label: "Avg/Session", key: :avg_cost, format: :cost, class: "text-right"}
    ]
  end

  defp sessions_column_defs do
    [
      %{
        label: "Session",
        key: :name,
        format: :link,
        class: "max-w-xs truncate",
        link_key: :uuid,
        link_prefix: "/dm/"
      },
      %{label: "Project", key: :project, format: :plain, class: "text-base-content/60 whitespace-nowrap"},
      %{label: "Model", key: :model, format: :short_model, class: "whitespace-nowrap"},
      %{label: "Date", key: :started_at, format: :date, class: "text-base-content/60 whitespace-nowrap"},
      %{label: "Input", key: :input_tokens, format: :number, class: "text-right"},
      %{label: "Output", key: :output_tokens, format: :number, class: "text-right"},
      %{label: "Cache Read", key: :cache_read, format: :number, class: "text-right"},
      %{label: "Cache Create", key: :cache_create, format: :number, class: "text-right"},
      %{label: "Requests", key: :requests, format: :number, class: "text-right"},
      %{label: "Subagents", key: :subagents, format: :number, class: "text-right"},
      %{label: "Cost", key: :cost, format: :cost, class: "text-right font-medium text-warning"}
    ]
  end

  # Derives <th> alignment class from the cell class. Headers mirror data alignment.
  defp header_class(col) do
    if String.contains?(col[:class] || "", "text-right"), do: "text-right", else: ""
  end

  defp render_cell(val, :number), do: ViewHelpers.format_number(val)
  defp render_cell(val, :cost), do: ViewHelpers.format_cost(val)
  defp render_cell(val, :short_model), do: ViewHelpers.short_model(val)
  defp render_cell(val, :date), do: ViewHelpers.format_date(val)
  defp render_cell(val, _), do: val
end
