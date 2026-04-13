defmodule EyeInTheSkyWeb.TaskBadges do
  @moduledoc """
  Badge components for task priority and workflow state.
  """
  use Phoenix.Component

  alias EyeInTheSky.Tasks.WorkflowState

  @state_todo WorkflowState.todo_id()
  @state_in_progress WorkflowState.in_progress_id()
  @state_in_review WorkflowState.in_review_id()
  @state_done WorkflowState.done_id()

  @doc """
  Renders a priority badge for a task.
  """
  attr :priority, :integer, default: nil

  def priority_badge(assigns) do
    ~H"""
    <%= cond do %>
      <% is_integer(@priority) && @priority >= 3 -> %>
        <span class="badge badge-error badge-sm flex-shrink-0">High</span>
      <% @priority == 2 -> %>
        <span class="badge badge-warning badge-sm flex-shrink-0">Med</span>
      <% @priority == 1 -> %>
        <span class="badge badge-info badge-sm flex-shrink-0">Low</span>
      <% true -> %>
        <span></span>
    <% end %>
    """
  end

  @doc """
  Renders a state badge for a task, colored by workflow state.
  """
  attr :state_id, :integer, required: true
  attr :state_name, :string, required: true

  def state_badge(assigns) do
    ~H"""
    <span class={["badge badge-sm flex-shrink-0", state_badge_class(@state_id)]}>
      {@state_name}
    </span>
    """
  end

  defp state_badge_class(@state_todo), do: "badge-ghost"
  defp state_badge_class(@state_in_progress), do: "badge-info"
  defp state_badge_class(@state_in_review), do: "badge-warning"
  defp state_badge_class(@state_done), do: "badge-success"
  defp state_badge_class(_), do: "badge-ghost"
end
