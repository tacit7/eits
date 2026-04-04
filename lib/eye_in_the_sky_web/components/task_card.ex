defmodule EyeInTheSkyWeb.Components.TaskCard do
  @moduledoc """
  Thin dispatcher for task card variants.

  Delegates to:
  - `TaskCard.KanbanCard` — kanban board cards
  - `TaskCard.GridCard` — grid view cards
  - `TaskCard.ListRow` — list view rows
  """

  use Phoenix.Component

  import EyeInTheSkyWeb.Components.TaskCard.KanbanCard, only: [kanban_card: 1]
  import EyeInTheSkyWeb.Components.TaskCard.GridCard, only: [grid_card: 1]
  import EyeInTheSkyWeb.Components.TaskCard.ListRow, only: [list_row: 1]

  attr :task, :map, required: true
  attr :variant, :string, default: "kanban", values: ["kanban", "grid", "list"]
  attr :on_click, :string, default: nil
  attr :on_delete, :string, default: nil
  attr :working_session_ids, :any, default: nil
  attr :workflow_states, :list, default: []
  attr :rest, :global

  def task_card(assigns) do
    ~H"""
    <%= case @variant do %>
      <% "list" -> %>
        <.list_row task={@task} on_click={@on_click} on_delete={@on_delete} />
      <% "grid" -> %>
        <.grid_card task={@task} on_click={@on_click} {@rest} />
      <% _ -> %>
        <.kanban_card
          task={@task}
          on_click={@on_click}
          on_delete={@on_delete}
          working_session_ids={@working_session_ids}
          workflow_states={@workflow_states}
          {@rest}
        />
    <% end %>
    """
  end
end
