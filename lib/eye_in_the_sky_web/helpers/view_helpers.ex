defmodule EyeInTheSkyWeb.Helpers.ViewHelpers do
  @moduledoc """
  Shared view helpers. Imports focused sub-modules for datetime, status, and task helpers.
  """

  use Phoenix.Component

  # Re-export so callers that `import ViewHelpers` get everything.
  defdelegate coerce_datetime(v), to: EyeInTheSkyWeb.Helpers.DateHelpers
  defdelegate parse_updated_at(v), to: EyeInTheSkyWeb.Helpers.DateHelpers
  defdelegate parse_datetime(v), to: EyeInTheSkyWeb.Helpers.DateHelpers
  defdelegate relative_time(v), to: EyeInTheSkyWeb.Helpers.DateHelpers
  defdelegate format_datetime_full(v), to: EyeInTheSkyWeb.Helpers.DateHelpers
  defdelegate format_datetime_short(v), to: EyeInTheSkyWeb.Helpers.DateHelpers
  defdelegate format_time(v), to: EyeInTheSkyWeb.Helpers.DateHelpers
  defdelegate format_datetime_short_time(v), to: EyeInTheSkyWeb.Helpers.DateHelpers
  defdelegate format_relative_time(v), to: EyeInTheSkyWeb.Helpers.DateHelpers
  defdelegate month_name(v), to: EyeInTheSkyWeb.Helpers.DateHelpers

  defdelegate derive_display_status(agent), to: EyeInTheSkyWeb.Helpers.StatusHelpers
  defdelegate derive_display_status(agent, h), to: EyeInTheSkyWeb.Helpers.StatusHelpers
  defdelegate idle_tier(agent), to: EyeInTheSkyWeb.Helpers.StatusHelpers
  defdelegate stale?(agent), to: EyeInTheSkyWeb.Helpers.StatusHelpers
  defdelegate stale?(agent, h), to: EyeInTheSkyWeb.Helpers.StatusHelpers
  defdelegate render_status_badge(assigns, agent), to: EyeInTheSkyWeb.Helpers.StatusHelpers
  defdelegate render_project_badge(assigns, name), to: EyeInTheSkyWeb.Helpers.StatusHelpers

  defdelegate format_due_date(v), to: EyeInTheSkyWeb.Helpers.TaskHelpers
  defdelegate due_date_class(v), to: EyeInTheSkyWeb.Helpers.TaskHelpers
  defdelegate overdue?(v), to: EyeInTheSkyWeb.Helpers.TaskHelpers
  defdelegate due_today?(v), to: EyeInTheSkyWeb.Helpers.TaskHelpers
  defdelegate format_date_input(v), to: EyeInTheSkyWeb.Helpers.TaskHelpers
  defdelegate days_since_update(v), to: EyeInTheSkyWeb.Helpers.TaskHelpers
  defdelegate card_aging_indicator(v), to: EyeInTheSkyWeb.Helpers.TaskHelpers

  # ── Model helpers ──────────────────────────────────────────────────────────

  defdelegate claude_models(), to: EyeInTheSkyWeb.Helpers.ModelHelpers
  defdelegate codex_models(), to: EyeInTheSkyWeb.Helpers.ModelHelpers
  defdelegate gemini_models(), to: EyeInTheSkyWeb.Helpers.ModelHelpers
  defdelegate models_for_provider(provider), to: EyeInTheSkyWeb.Helpers.ModelHelpers
  defdelegate valid_model_slugs(provider), to: EyeInTheSkyWeb.Helpers.ModelHelpers
  defdelegate valid_model_combos(), to: EyeInTheSkyWeb.Helpers.ModelHelpers

  # ── Parse helpers ──────────────────────────────────────────────────────────

  defdelegate parse_id(val), to: EyeInTheSkyWeb.ControllerHelpers, as: :parse_int

  @doc """
  Parse a USD budget string from form params. Returns a positive float or nil.
  """
  def parse_budget(nil), do: nil
  def parse_budget(""), do: nil

  def parse_budget(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} when f > 0 -> f
      _ -> nil
    end
  end

  # ── String helpers ─────────────────────────────────────────────────────────

  @doc """
  Extract uppercase initials from a name (e.g. "John Doe" -> "JD").
  """
  def member_initials(nil), do: "?"

  def member_initials(name) when is_binary(name) do
    name
    |> String.split()
    |> Enum.take(2)
    |> Enum.map_join("", &String.first/1)
    |> String.upcase()
  end

  @doc """
  Truncate text to a given max length (default 50), appending "…" when truncated.
  Returns empty string for nil input.
  """
  def truncate_text(text), do: truncate_text(text, 50)

  def truncate_text(nil, _max), do: ""

  def truncate_text(text, max) when is_binary(text) do
    if String.length(text) > max do
      String.slice(text, 0, max) <> "…"
    else
      text
    end
  end

  def truncate_text(_, _), do: ""

  # ── Number / cost helpers ──────────────────────────────────────────────────

  @doc """
  Format a cost value as a dollar string (e.g. "$1.23").
  """
  def format_cost(value) when is_float(value),
    do: "$#{:erlang.float_to_binary(value, decimals: 2)}"

  def format_cost(value) when is_integer(value),
    do: "$#{:erlang.float_to_binary(value / 1, decimals: 2)}"

  def format_cost(_), do: "$0.00"

  @doc """
  Format an integer with comma separators (e.g. 1_000_000 -> "1,000,000").
  """
  def format_number(value) when is_integer(value) do
    value
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end

  def format_number(value) when is_float(value), do: format_number(trunc(value))
  def format_number(_), do: "0"

  # ── Misc helpers ───────────────────────────────────────────────────────────

  defdelegate format_date(v), to: EyeInTheSkyWeb.Helpers.DateHelpers

  @doc """
  Return a short display name for a Claude model ID.
  """
  def short_model(nil), do: "—"
  def short_model(name), do: EyeInTheSkyWeb.Helpers.ModelHelpers.model_display_name(name)

  defdelegate open_in_system(path), to: EyeInTheSkyWeb.Helpers.SystemHelpers
end
