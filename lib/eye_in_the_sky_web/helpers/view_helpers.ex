defmodule EyeInTheSkyWeb.Helpers.ViewHelpers do
  @moduledoc """
  Shared view helpers. Imports focused sub-modules for datetime, status, and task helpers.
  """

  use Phoenix.Component

  alias EyeInTheSkyWeb.Helpers.ModelHelpers

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
  defdelegate models_for_provider(provider), to: EyeInTheSkyWeb.Helpers.ModelHelpers
  defdelegate valid_model_slugs(provider), to: EyeInTheSkyWeb.Helpers.ModelHelpers
  defdelegate valid_model_combos(), to: EyeInTheSkyWeb.Helpers.ModelHelpers
  defdelegate model_display_name(slug), to: EyeInTheSkyWeb.Helpers.ModelHelpers

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
  Returns nil for nil or non-binary input so callers can use || fallback chains.
  """
  def truncate_text(text), do: truncate_text(text, 50)

  def truncate_text(nil, _max), do: nil

  def truncate_text(text, max) when is_binary(text) do
    if String.length(text) > max do
      String.slice(text, 0, max) <> "…"
    else
      text
    end
  end

  def truncate_text(_, _), do: nil

  # ── Number / cost helpers ──────────────────────────────────────────────────

  @doc """
  Format a cost value as a dollar string (e.g. "$1.23").
  Handles small values (<$0.01) and large values (≥$100) with special formatting.
  """
  def format_cost(cost) when is_float(cost) and cost < 0.01, do: "<$0.01"

  def format_cost(cost) when is_float(cost) and cost < 100,
    do: "$#{:erlang.float_to_binary(cost, decimals: 2)}"

  def format_cost(cost) when is_float(cost), do: "$#{round(cost)}"

  def format_cost(cost) when is_integer(cost), do: format_cost(cost / 1)

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
  def short_model(name), do: ModelHelpers.model_display_name(name)

  defdelegate open_in_system(path), to: EyeInTheSkyWeb.Helpers.SystemHelpers

  @doc """
  Open `path` in the given editor (or preferred editor from settings).
  Returns `{:noreply, socket}` with a flash set on success or error.
  Intended to be called directly from a `handle_event/3` clause.
  """
  def handle_open_in_editor(path, editor_id, socket) do
    case EyeInTheSky.Editors.open(editor_id, path) do
      {:ok, label} ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :info, "Opening in #{label}…")}

      {:error, :unknown_editor} ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Unknown editor")}

      {:error, :not_installed} ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Editor not installed")}

      {:error, :not_allowed} ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Path is outside allowed directories")}

      {:error, :not_found} ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, "File not found")}
    end
  end

  @doc """
  Shared handler for the "open_in_editor" LiveView event with a guard.

  Calls the given guard function with (path, socket) — if it returns true,
  delegates to handle_open_in_editor/3; otherwise returns a :error flash.
  """
  def handle_open_in_editor_with_guard(path, editor_id, socket, guard_fn) do
    if guard_fn.(path, socket) do
      handle_open_in_editor(path, editor_id, socket)
    else
      {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Path not allowed")}
    end
  end
end
