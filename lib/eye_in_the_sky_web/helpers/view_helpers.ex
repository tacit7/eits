defmodule EyeInTheSkyWeb.Helpers.ViewHelpers do
  @moduledoc """
  Shared view helpers. Imports focused sub-modules for datetime, status, and task helpers.
  """

  use Phoenix.Component

  import EyeInTheSkyWeb.Helpers.DateHelpers
  import EyeInTheSkyWeb.Helpers.StatusHelpers
  import EyeInTheSkyWeb.Helpers.TaskHelpers

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
  defdelegate is_stale?(agent), to: EyeInTheSkyWeb.Helpers.StatusHelpers
  defdelegate is_stale?(agent, h), to: EyeInTheSkyWeb.Helpers.StatusHelpers
  defdelegate render_status_badge(assigns, agent), to: EyeInTheSkyWeb.Helpers.StatusHelpers
  defdelegate render_project_badge(assigns, name), to: EyeInTheSkyWeb.Helpers.StatusHelpers

  defdelegate format_due_date(v), to: EyeInTheSkyWeb.Helpers.TaskHelpers
  defdelegate due_date_class(v), to: EyeInTheSkyWeb.Helpers.TaskHelpers
  defdelegate is_overdue?(v), to: EyeInTheSkyWeb.Helpers.TaskHelpers
  defdelegate is_due_today?(v), to: EyeInTheSkyWeb.Helpers.TaskHelpers
  defdelegate format_date_input(v), to: EyeInTheSkyWeb.Helpers.TaskHelpers
  defdelegate days_since_update(v), to: EyeInTheSkyWeb.Helpers.TaskHelpers
  defdelegate card_aging_indicator(v), to: EyeInTheSkyWeb.Helpers.TaskHelpers

  # ── Model helpers ──────────────────────────────────────────────────────────

  @doc """
  Returns the list of Claude model {value, label} tuples for select inputs.
  """
  def claude_models do
    [
      {"sonnet", "Sonnet 4.5"},
      {"opus", "Opus 4.6"},
      {"sonnet[1m]", "Sonnet 4.5 (1M)"},
      {"opus[1m]", "Opus 4.6 (1M)"},
      {"haiku", "Haiku 4.5"}
    ]
  end

  @doc """
  Returns the list of Codex model {value, label} tuples for select inputs.
  """
  def codex_models do
    [
      {"gpt-5.3-codex", "GPT-5.3 Codex"},
      {"gpt-5.2-codex", "GPT-5.2 Codex"},
      {"gpt-5.2", "GPT-5.2"},
      {"gpt-5.1", "GPT-5.1"},
      {"gpt-5-codex-mini", "GPT-5 Codex Mini"}
    ]
  end

  @doc """
  Returns {value, label} tuples for the given provider.
  """
  def models_for_provider("codex"), do: codex_models()
  def models_for_provider(_), do: claude_models()

  @doc """
  Returns a flat list of valid model slugs for the given provider.
  """
  def valid_model_slugs(provider) do
    provider |> models_for_provider() |> Enum.map(&elem(&1, 0))
  end

  @doc """
  Returns a map of provider => list of valid model slugs.
  """
  def valid_model_combos do
    %{
      "claude" => valid_model_slugs("claude"),
      "codex" => valid_model_slugs("codex")
    }
  end

  # ── Parse helpers ──────────────────────────────────────────────────────────

  @doc """
  Parse an integer ID from a string route param. Returns nil for invalid input.
  """
  def parse_id(str) when is_binary(str) do
    case Integer.parse(str) do
      {int, ""} -> int
      _ -> nil
    end
  end

  def parse_id(_), do: nil

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

  def truncate_text(nil), do: nil

  def truncate_text(text) when is_binary(text) do
    if String.length(text) > 50 do
      String.slice(text, 0, 50) <> "..."
    else
      text
    end
  end

  @doc """
  Truncate text to a given max length, appending "…" when truncated.
  """
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

  @doc """
  Extract the date portion from a timestamp string (e.g. "2026-01-15 10:30:00" → "2026-01-15").
  """
  def format_date(nil), do: "—"

  def format_date(ts) when is_binary(ts) do
    case String.split(ts, " ") do
      [date | _] -> date
      _ -> ts
    end
  end

  def format_date(_), do: "—"

  @doc """
  Return a short display name for a Claude model ID.
  """
  def short_model(nil), do: "—"

  def short_model(name) do
    case name do
      "claude-opus-4-6" -> "Opus 4.6"
      "claude-sonnet-4-6" -> "Sonnet 4.6"
      "claude-sonnet-4-5-20250929" -> "Sonnet 4.5"
      "claude-haiku-4-5-20251001" -> "Haiku 4.5"
      other -> other
    end
  end

  @doc """
  Open a file with the system's default application (cross-platform).
  """
  def open_in_system(path) when is_binary(path) do
    cmd =
      case :os.type() do
        {:unix, :darwin} -> "open"
        {:unix, _} -> "xdg-open"
        {:win32, _} -> "cmd"
      end

    args =
      case :os.type() do
        {:win32, _} -> ["/c", "start", "", path]
        _ -> [path]
      end

    System.cmd(cmd, args, stderr_to_stdout: true)
  end
end
