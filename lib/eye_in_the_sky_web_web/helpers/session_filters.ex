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

  defp parse_started_at(%{started_at: value}), do: VH.coerce_datetime(value)

  @doc """
  Filters sessions by status/archive state.

  Filters: "active", "completed", "archived", or any other value passes all through.
  """
  def filter_agents_by_status(sessions, filter) do
    case filter do
      "active" ->
        Enum.filter(sessions, &(&1.status in ["working", "idle", nil] and is_nil(&1.archived_at)))

      "completed" ->
        Enum.filter(sessions, &(&1.status == "completed" and is_nil(&1.archived_at)))

      "archived" ->
        Enum.filter(sessions, &(!is_nil(&1.archived_at)))

      _ ->
        sessions
    end
  end

  @doc """
  Filters sessions by a free-text search query against uuid, name, agent description, and project name.
  """
  def filter_agents_by_search(sessions, query) do
    q = (query || "") |> String.trim() |> String.downcase()

    if q == "" do
      sessions
    else
      Enum.filter(sessions, fn s ->
        haystack =
          [
            s.uuid,
            s.name,
            s.agent && s.agent.description,
            s.agent && s.agent.project_name
          ]
          |> Enum.map(&to_string_or_empty/1)
          |> Enum.join(" ")
          |> String.downcase()

        String.contains?(haystack, q)
      end)
    end
  end

  @doc """
  Sorts sessions by "name", "status", or "recent" (default).
  """
  def sort_agents(sessions, sort_by) do
    case sort_by do
      "name" ->
        Enum.sort_by(sessions, fn s -> (s.name || "") |> String.downcase() end)

      "status" ->
        Enum.sort_by(sessions, &session_status_rank/1)

      _ ->
        Enum.sort_by(
          sessions,
          fn s -> sort_datetime(s.last_activity_at || s.started_at) end,
          {:desc, NaiveDateTime}
        )
    end
  end

  @doc """
  Returns a numeric rank for a session's status (lower = more prominent).
  """
  def session_status_rank(agent) do
    case agent.status do
      "discovered" -> 0
      "working" -> 1
      "idle" -> 1
      "completed" -> 2
      nil -> 1
      _ -> 2
    end
  end

  @doc """
  Converts a value to a string, returning empty string for nil.
  """
  def to_string_or_empty(nil), do: ""
  def to_string_or_empty(v) when is_binary(v), do: v
  def to_string_or_empty(v), do: to_string(v)

  @doc """
  Normalizes a datetime value to NaiveDateTime for sorting, returning epoch for nil/unknown.
  """
  def sort_datetime(%NaiveDateTime{} = ndt), do: ndt
  def sort_datetime(%DateTime{} = dt), do: DateTime.to_naive(dt)
  def sort_datetime(_), do: ~N[0000-01-01 00:00:00]

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
