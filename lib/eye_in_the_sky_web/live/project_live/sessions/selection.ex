defmodule EyeInTheSkyWeb.ProjectLive.Sessions.Selection do
  @moduledoc """
  Helpers for deriving and applying session selection state.

  Pure derivation functions (normalize_id, off_screen_count, etc.) take plain data.
  `clear_selection/1` takes a socket and is the canonical way to reset all selection assigns.

  All IDs are normalized to strings because LiveView event params arrive as strings.
  """

  import Phoenix.Component, only: [assign: 3]

  @doc "Normalize any session ID to a string."
  def normalize_id(id), do: to_string(id)

  @doc "Build a MapSet of string IDs from the current visible session/agent rows."
  def ids_from_agents(agents) do
    MapSet.new(agents, &normalize_id(&1.id))
  end

  @doc "Number of selected IDs not in the current visible agents list."
  def off_screen_count(selected_ids, agents) do
    visible_ids = ids_from_agents(agents)
    MapSet.size(MapSet.difference(selected_ids, visible_ids))
  end

  @doc """
  Set of parent session IDs (as strings) where some — but not all — currently
  visible direct children are selected.

  Limitation: only considers children present in `agents` (the visible/loaded list).
  If children are filtered out, their absence is not reflected here.
  """
  def compute_indeterminate_ids(selected_ids, agents) do
    children_by_parent =
      agents
      |> Enum.reject(&is_nil(&1.parent_session_id))
      |> Enum.group_by(&normalize_id(&1.parent_session_id))

    Enum.reduce(children_by_parent, MapSet.new(), fn {parent_id, children}, acc ->
      child_ids = MapSet.new(children, &normalize_id(&1.id))
      selected_count = MapSet.size(MapSet.intersection(selected_ids, child_ids))

      cond do
        # Parent is selected — show checked, not indeterminate
        MapSet.member?(selected_ids, parent_id) -> acc
        selected_count == 0 -> acc
        selected_count == MapSet.size(child_ids) -> acc
        true -> MapSet.put(acc, parent_id)
      end
    end)
  end

  @doc """
  Toggle all visible sessions: add all visible IDs if any are unselected; remove
  all visible IDs if all are already selected. Off-screen selected IDs are preserved.
  """
  def select_all_visible(selected_ids, agents) do
    visible_ids = ids_from_agents(agents)

    all_visible_selected? =
      MapSet.size(visible_ids) > 0 and MapSet.subset?(visible_ids, selected_ids)

    if all_visible_selected? do
      MapSet.difference(selected_ids, visible_ids)
    else
      MapSet.union(selected_ids, visible_ids)
    end
  end

  @doc """
  Returns `{checked?, indeterminate?}` for the select-all toolbar checkbox.

  Reflects only currently visible rows. Off-screen selected rows are shown via the
  count text "(N not visible)" — not via the select-all checkbox state.

  - `{true, false}` — all visible rows selected.
  - `{false, true}` — some visible rows selected.
  - `{false, false}` — no visible rows selected.
  """
  def select_all_checkbox_state(selected_ids, agents) do
    visible_ids = ids_from_agents(agents)
    visible_count = MapSet.size(visible_ids)
    visible_selected = MapSet.size(MapSet.intersection(selected_ids, visible_ids))

    cond do
      visible_count == 0 -> {false, false}
      visible_selected == visible_count -> {true, false}
      visible_selected > 0 -> {false, true}
      true -> {false, false}
    end
  end

  @doc """
  Resets all selection assigns to cleared state. Use after bulk operations or
  when the user explicitly exits select mode.
  """
  def clear_selection(socket) do
    socket
    |> assign(:select_mode, false)
    |> assign(:selected_ids, MapSet.new())
    |> assign(:indeterminate_ids, MapSet.new())
    |> assign(:off_screen_selected_count, 0)
  end
end
