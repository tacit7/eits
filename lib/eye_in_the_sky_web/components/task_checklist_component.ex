defmodule EyeInTheSkyWeb.Components.TaskChecklistComponent do
  @moduledoc """
  LiveComponent that owns checklist CRUD for a task.
  Handles add_checklist_item, toggle_checklist_item, delete_checklist_item internally
  and notifies the parent LiveView via send/2 when the task is updated.
  """

  use EyeInTheSkyWeb, :live_component

  import Phoenix.LiveView, only: [put_flash: 3]

  alias EyeInTheSky.Tasks

  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 2]

  attr :task, :any, required: true
  attr :id, :string, required: true

  @impl true
  def render(assigns) do
    items = if is_list(assigns.task.checklist_items), do: assigns.task.checklist_items, else: []
    total = length(items)
    done = Enum.count(items, & &1.completed)
    assigns = assign(assigns, items: items, total: total, done: done)

    ~H"""
    <div>
      <div class="flex items-center gap-2 mb-2">
        <span class="text-mini font-medium text-base-content/40 uppercase tracking-wider">
          Checklist
        </span>
        <%= if @total > 0 do %>
          <span class="text-mini font-mono tabular-nums text-base-content/25">
            {@done}/{@total}
          </span>
        <% end %>
      </div>
      <%= if @total > 0 do %>
        <div class="w-full bg-base-300 rounded-full h-1.5 mb-3">
          <div
            class={"h-1.5 rounded-full transition-all " <> if(@done == @total, do: "bg-success", else: "bg-primary")}
            style={"width: #{if @total > 0, do: round(@done / @total * 100), else: 0}%"}
          />
        </div>
      <% end %>
      <div class="space-y-1 mb-2">
        <%= for item <- @items do %>
          <div class="flex items-center gap-2 group/item">
            <input
              type="checkbox"
              class="checkbox checkbox-xs checkbox-primary"
              checked={item.completed}
              phx-click="toggle_checklist_item"
              phx-value-item-id={item.id}
              phx-target={@myself}
            />
            <span class={[
              "text-sm flex-1",
              item.completed && "line-through text-base-content/40"
            ]}>
              {item.title}
            </span>
            <button
              type="button"
              phx-click="delete_checklist_item"
              phx-value-item-id={item.id}
              phx-target={@myself}
              class="opacity-0 group-hover/item:opacity-100 text-base-content/25 hover:text-error transition-all"
            >
              <.icon name="hero-x-mark-mini" class="size-3.5" />
            </button>
          </div>
        <% end %>
      </div>
      <form phx-submit="add_checklist_item" phx-target={@myself} class="flex items-center gap-2">
        <input type="hidden" name="task_id" value={@task.uuid || to_string(@task.id)} />
        <input
          type="text"
          name="title"
          placeholder="Add item..."
          class="input input-xs flex-1 bg-base-200 border-base-300 text-base placeholder:text-base-content/20 focus:border-primary/30"
        />
        <button
          type="submit"
          class="btn btn-xs btn-ghost text-base-content/30 hover:text-base-content/60"
        >
          <.icon name="hero-plus-mini" class="size-3.5" />
        </button>
      </form>
    </div>
    """
  end

  @impl true
  def handle_event("add_checklist_item", %{"task_id" => task_id, "title" => title}, socket) do
    title = String.trim(title)

    if title != "" do
      task = Tasks.get_task_by_uuid_or_id!(task_id)
      items = Tasks.list_checklist_items(task.id)
      next_position = if items == [], do: 0, else: length(items)

      case Tasks.create_checklist_item(%{task_id: task.id, title: title, position: next_position}) do
        {:ok, _} ->
          updated_task = Tasks.get_task!(task.id)
          send(self(), {:checklist_updated, updated_task})
          {:noreply, assign(socket, :task, updated_task)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to add checklist item")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_checklist_item", %{"item-id" => item_id_str}, socket) do
    item_id = parse_int(item_id_str, 0)

    case Tasks.toggle_checklist_item(item_id) do
      {:ok, item} ->
        updated_task = Tasks.get_task!(item.task_id)
        send(self(), {:checklist_updated, updated_task})
        {:noreply, assign(socket, :task, updated_task)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete_checklist_item", %{"item-id" => item_id_str}, socket) do
    item_id = parse_int(item_id_str, 0)

    case Tasks.delete_checklist_item(item_id) do
      {:ok, item} ->
        updated_task = Tasks.get_task!(item.task_id)
        send(self(), {:checklist_updated, updated_task})
        {:noreply, assign(socket, :task, updated_task)}

      {:error, _} ->
        {:noreply, socket}
    end
  end
end
