defmodule EyeInTheSkyWebWeb.Helpers.SessionFilters do
  @moduledoc """
  Helpers for filtering and sorting session listings for the Agents index.
  """

  alias EyeInTheSkyWebWeb.Helpers.ViewHelpers, as: VH

  @stale_threshold_hours 24

  @doc """
  Filters and sorts sessions based on the provided assigns map.

  Expected keys in `params`:
  - `:sessions` - list of sessions
  - `:search_query` - string
  - `:status_filter` - one of "all", "active", "completed", "stale", "discovered"
  - `:sort_by` - one of "recent"
  """
  def filter_and_sort_sessions(%{sessions: sessions} = params) when is_list(sessions) do
    query = String.downcase(params[:search_query] || "")
    status_filter = params[:status_filter] || "all"

    sessions
    |> Enum.filter(fn session ->
      search_match?(session, query) and status_match?(session, status_filter)
    end)
    |> sort_sessions(params[:sort_by] || "recent")
  end

  defp search_match?(_session, ""), do: true

  defp search_match?(session, query) do
    Enum.any?(
      [
        session.id,
        session.name,
        get_in(session, [:agent, :description]),
        get_in(session, [:agent, :project_name])
      ],
      fn val ->
        String.contains?(String.downcase(val || ""), query)
      end
    )
  end

  defp status_match?(session, filter) do
    case filter do
      "all" -> true
      "active" -> is_nil(session.ended_at) and session.status != "discovered"
      "completed" -> not is_nil(session.ended_at)
      "stale" -> is_session_stale?(session, @stale_threshold_hours)
      "discovered" -> session.status == "discovered"
      _ -> true
    end
  end

  defp sort_sessions(sessions, "recent") do
    Enum.sort_by(sessions, &parse_started_at/1, {:desc, DateTime})
  end

  defp parse_started_at(%{started_at: nil}), do: ~U[1970-01-01 00:00:00Z]
  defp parse_started_at(%{started_at: %DateTime{} = dt}), do: dt

  defp parse_started_at(%{started_at: str}) when is_binary(str) do
    case VH.parse_datetime(str) do
      {:ok, dt} -> dt
      :error -> ~U[1970-01-01 00:00:00Z]
    end
  end

  @doc """
  Returns true if the session is stale given a threshold in hours.
  """
  def is_session_stale?(%{ended_at: ended_at}, _hours) when not is_nil(ended_at), do: false

  def is_session_stale?(%{started_at: started_at}, hours) do
    case VH.parse_datetime(started_at) do
      {:ok, dt} ->
        now = DateTime.utc_now()
        DateTime.diff(now, dt, :hour) > hours

      :error ->
        false
    end
  end
end
