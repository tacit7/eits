defmodule EyeInTheSkyWeb.Components.Rail.Flyout.UsageSection do
  @moduledoc false
  use EyeInTheSkyWeb, :html

  # ── Public entry-point ────────────────────────────────────────────────────

  attr :usage, :any, default: nil

  def usage_content(assigns) do
    ~H"""
    <%= case @usage do %>
      <% nil -> %>
        <.usage_loading />
      <% {:error, :token_expired} -> %>
        <.usage_error message="OAuth token expired. Re-authenticate via Claude CLI." />
      <% {:error, :no_credentials} -> %>
        <.usage_error message="No Claude credentials found." />
      <% {:error, _} -> %>
        <.usage_error message="Could not load rate limits." />
      <% {:ok, data} -> %>
        <.rate_limit_bars data={data} />
    <% end %>
    """
  end

  # ── Loading state ─────────────────────────────────────────────────────────

  defp usage_loading(assigns) do
    ~H"""
    <div class="px-3 py-4 flex flex-col gap-4">
      <div :for={_ <- 1..3} class="flex flex-col gap-1.5">
        <div class="flex justify-between">
          <div class="skeleton h-3 w-28 rounded"></div>
          <div class="skeleton h-3 w-14 rounded"></div>
        </div>
        <div class="skeleton h-1.5 w-full rounded-full"></div>
        <div class="skeleton h-2.5 w-20 rounded"></div>
      </div>
    </div>
    """
  end

  # ── Error state ───────────────────────────────────────────────────────────

  attr :message, :string, required: true

  defp usage_error(assigns) do
    ~H"""
    <div class="px-3 py-4 text-xs text-base-content/40 italic">
      {@message}
    </div>
    """
  end

  # ── Rate-limit bars ───────────────────────────────────────────────────────

  attr :data, :map, required: true

  defp rate_limit_bars(assigns) do
    ~H"""
    <div class="flex flex-col divide-y divide-base-content/8">
      <.rate_row
        :if={@data.five_hour}
        label="Current session"
        rate={@data.five_hour}
      />
      <.rate_row
        :if={@data.seven_day}
        label="Current week (all models)"
        rate={@data.seven_day}
      />
      <.rate_row
        :if={@data.seven_day_sonnet}
        label="Current week (Sonnet)"
        rate={@data.seven_day_sonnet}
      />
      <.extra_usage_row :if={@data.extra_usage} extra={@data.extra_usage} />
    </div>
    """
  end

  # ── Individual rate-limit row ─────────────────────────────────────────────

  attr :label, :string, required: true
  attr :rate, :map, required: true

  defp rate_row(assigns) do
    assigns = assign(assigns, :pct, rate_pct(assigns.rate.utilization))

    ~H"""
    <div class="px-3 py-3 flex flex-col gap-1.5">
      <div class="flex items-baseline justify-between gap-2">
        <span class="text-xs font-medium text-base-content/80 truncate">{@label}</span>
        <span class="text-xs font-medium text-primary flex-shrink-0">{@pct}% used</span>
      </div>
      <div class="w-full h-1.5 rounded-full bg-base-content/15 overflow-hidden">
        <div
          class="h-full rounded-full bg-primary transition-[width] duration-300"
          style={"width: #{@pct}%"}
        >
        </div>
      </div>
      <span :if={@rate.resets_at} class="text-[10px] text-base-content/40 leading-none">
        resets in {format_reset(@rate.resets_at)}
      </span>
    </div>
    """
  end

  # ── Monthly spend row ─────────────────────────────────────────────────────

  attr :extra, :map, required: true

  defp extra_usage_row(assigns) do
    assigns =
      assign(assigns,
        monthly_pct: monthly_pct(assigns.extra),
        spend_label: spend_label(assigns.extra)
      )

    ~H"""
    <div class="px-3 py-3 flex flex-col gap-1.5">
      <div class="flex items-baseline justify-between gap-2">
        <span class="text-xs font-medium text-base-content/80">Monthly spend</span>
        <span class="text-xs font-medium text-primary flex-shrink-0">{@spend_label}</span>
      </div>
      <div class="w-full h-1.5 rounded-full bg-base-content/15 overflow-hidden">
        <div
          class="h-full rounded-full bg-primary transition-[width] duration-300"
          style={"width: #{@monthly_pct}%"}
        >
        </div>
      </div>
    </div>
    """
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  defp rate_pct(nil), do: 0
  defp rate_pct(util) when is_float(util), do: round(util)
  defp rate_pct(util) when is_integer(util), do: util

  # used_credits is in dollars (float), monthly_limit is in cents (integer).
  # Convert limit to dollars before computing the percentage.
  defp monthly_pct(%{used_credits: used, monthly_limit: limit})
       when is_number(used) and is_number(limit) and limit > 0 do
    limit_dollars = limit / 100.0
    min(100, round(used / limit_dollars * 100))
  end

  defp monthly_pct(_), do: 0

  # The API returns used_credits as a float in dollars (e.g. 0.0),
  # and monthly_limit as cents (e.g. 3000 = $30.00).
  defp spend_label(%{used_credits: used, monthly_limit: limit})
       when is_number(used) and is_number(limit) do
    limit_dollars = limit / 100.0
    "$#{format_dollars(used)} / $#{format_dollars(limit_dollars)}"
  end

  defp spend_label(_), do: "—"

  defp format_dollars(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 2)
  defp format_dollars(n) when is_integer(n), do: :erlang.float_to_binary(n * 1.0, decimals: 2)

  # Converts ISO8601 resets_at to "57m" / "1d 19h" / "3h 20m" style string.
  defp format_reset(nil), do: nil

  defp format_reset(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _} ->
        diff_s = DateTime.diff(dt, DateTime.utc_now())

        cond do
          diff_s <= 0 -> "soon"
          diff_s < 3600 -> "#{div(diff_s, 60)}m"
          diff_s < 86_400 -> "#{div(diff_s, 3600)}h #{rem(div(diff_s, 60), 60)}m"
          true -> "#{div(diff_s, 86_400)}d #{rem(div(diff_s, 3600), 24)}h"
        end

      _ ->
        nil
    end
  end
end
