defmodule EyeInTheSkyWebWeb.Components.TaskCard do
  @moduledoc """
  Reusable task card component for kanban and task list views.
  """

  use Phoenix.Component
  import EyeInTheSkyWebWeb.CoreComponents
  import EyeInTheSkyWebWeb.Helpers.ViewHelpers, only: [format_due_date: 1, card_aging_indicator: 1]

  alias EyeInTheSkyWeb.Tasks.WorkflowState

  @state_todo WorkflowState.todo_id()
  @state_in_progress WorkflowState.in_progress_id()
  @state_in_review WorkflowState.in_review_id()
  @state_done WorkflowState.done_id()

  attr :task, :map, required: true
  attr :variant, :string, default: "kanban", values: ["kanban", "grid", "list"]
  attr :on_click, :string, default: nil
  attr :on_delete, :string, default: nil
  attr :rest, :global

  def task_card(assigns) do
    aging = if assigns.variant == "kanban", do: card_aging_indicator(assigns.task.updated_at), else: nil
    assigns = assign(assigns, :aging, aging)

    ~H"""
    <%= case @variant do %>
      <% "list" -> %>
        <.list_row task={@task} on_click={@on_click} on_delete={@on_delete} />
      <% _ -> %>
        <div class={[card_class(@variant), @aging && elem(@aging, 0)]} {@rest}>
          <div class={card_body_class(@variant)}>
            <%= if @variant == "kanban" do %>
              <.kanban_card_content task={@task} on_click={@on_click} on_delete={@on_delete} aging={@aging} />
            <% else %>
              <.grid_card_content task={@task} on_click={@on_click} />
            <% end %>
          </div>
        </div>
    <% end %>
    """
  end

  defp list_row(assigns) do
    dm_session =
      case assigns.task do
        %{sessions: [session | _]} -> session
        _ -> nil
      end

    assigns = assign(assigns, :dm_session, dm_session)

    ~H"""
    <div
      class="group flex items-center gap-2 py-3.5 cursor-pointer"
      phx-click={@on_click}
      phx-keyup={@on_click}
      phx-key="Enter"
      phx-value-task_id={@task.uuid || to_string(@task.id)}
      role="button"
      tabindex="0"
      aria-label={"Open task #{@task.title}"}
    >
      <div class="flex flex-col gap-1 flex-1 min-w-0">
        <span class={[
          "text-sm font-medium truncate",
          @task.completed_at && "text-base-content/40 line-through",
          !@task.completed_at && "text-base-content/85 group-hover:text-base-content"
        ]}>
          {@task.title}
        </span>
        <div class="flex items-center gap-1.5 text-xs text-base-content/60">
          <%= if @task.state do %>
            <span class={state_text_color(@task.state_id)}>{@task.state.name}</span>
          <% end %>
          <%= if @task.tags && length(@task.tags) > 0 do %>
            <span class="text-base-content/15">&middot;</span>
            <span>{Enum.map_join(Enum.take(@task.tags, 2), ", ", & &1.name)}</span>
          <% end %>
          <span class="text-base-content/15">&middot;</span>
          <span class="font-mono">{String.slice(@task.uuid || "", 0..7)}</span>
        </div>
      </div>
      <%= if @dm_session do %>
        <.link
          navigate={"/dm/#{@dm_session.uuid}"}
          class="flex-shrink-0 md:opacity-0 md:group-hover:opacity-100 min-h-[44px] min-w-[44px] flex items-center justify-center rounded-md text-base-content/40 hover:text-primary hover:bg-primary/10 transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
          title="Open agent DM"
          aria-label="Open agent direct message"
          onclick="event.stopPropagation();"
        >
          <.icon name="hero-chat-bubble-left-ellipsis" class="w-3.5 h-3.5" />
        </.link>
      <% end %>
      <%= if @on_delete do %>
        <.icon_button
          icon="hero-trash-mini"
          on_click={@on_delete}
          aria_label="Delete task"
          color="error"
          values={%{"task_id" => @task.uuid || to_string(@task.id)}}
        />
      <% end %>
    </div>
    """
  end

  defp kanban_card_content(assigns) do
    ~H"""
    <!-- Task Title + Priority -->
    <div class="flex items-start gap-2 mb-2">
      <div
        data-drag-handle
        class="flex-shrink-0 mt-1 touch-none cursor-grab active:cursor-grabbing flex md:hidden items-center justify-center w-5 h-5 rounded text-base-content/20 hover:text-base-content/40"
        aria-label="Drag to reorder"
      >
        <.icon name="hero-bars-2" class="w-3.5 h-3.5" />
      </div>
      <h4
        class={
          "text-sm font-medium flex-1 hover:text-primary transition-colors cursor-pointer " <>
            if @task.completed_at do
              "text-base-content/50 line-through"
            else
              "text-base-content"
            end
        }
      >
        {@task.title}
      </h4>
      <%= if @task.priority && @task.priority > 0 do %>
        <span class={priority_class(@task.priority)}>
          {priority_label(@task.priority)}
        </span>
      <% end %>
      <%= if @on_delete do %>
        <button
          type="button"
          phx-click={@on_delete}
          phx-value-task_id={@task.uuid || to_string(@task.id)}
          phx-confirm="Delete this task?"
          class="flex-shrink-0 opacity-100 md:opacity-0 md:group-hover/card:opacity-100 flex items-center justify-center w-7 h-7 sm:w-5 sm:h-5 rounded text-base-content/25 hover:text-error hover:bg-error/10 transition-all focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-error"
          aria-label={"Delete task #{@task.title}"}
          onclick="event.stopPropagation();"
        >
          <.icon name="hero-x-mark-mini" class="w-3.5 h-3.5" />
        </button>
      <% end %>
    </div>

    <!-- Description -->
    <%= if @task.description do %>
      <p class="text-xs text-base-content/60 line-clamp-2 mb-2">
        {@task.description}
      </p>
    <% end %>

    <!-- Checklist progress -->
    <% checklist = Map.get(@task, :checklist_items, []) %>
    <%= if checklist != [] do %>
      <% cl_total = length(checklist) %>
      <% cl_done = Enum.count(checklist, & &1.completed) %>
      <div class="mb-2 flex items-center gap-2">
        <div class="flex-1 bg-base-300 rounded-full h-1">
          <div
            class={"h-1 rounded-full " <> if(cl_done == cl_total, do: "bg-success", else: "bg-primary")}
            style={"width: #{round(cl_done / cl_total * 100)}%"}
          />
        </div>
        <span class="text-[10px] text-base-content/40 tabular-nums">{cl_done}/{cl_total}</span>
      </div>
    <% end %>

    <!-- Annotations -->
    <%= if Map.get(@task, :notes, []) != [] do %>
      <div class="mb-2 space-y-1">
        <%= for note <- Map.get(@task, :notes, []) do %>
          <div class="text-[11px] text-base-content/50 bg-base-200 rounded px-2 py-1 line-clamp-2">
            <%= if note.title do %>
              <span class="font-semibold text-base-content/60">{note.title}: </span>
            <% end %>
            {note.body}
          </div>
        <% end %>
      </div>
    <% end %>

    <!-- Meta Info -->
    <div class="flex items-center gap-1.5 sm:gap-2 text-xs text-base-content/60 flex-wrap">
      <%= if @aging do %>
        <span class={"flex items-center gap-0.5 " <> if(String.contains?(elem(@aging, 1), "stale"), do: "text-error/70", else: "text-warning/70")}>
          <.icon name="hero-clock" class="w-3 h-3" />
          {elem(@aging, 1)}
        </span>
      <% end %>
      <span class="font-mono text-xs hidden sm:inline">
        {String.slice(@task.uuid || "", 0..7)}
      </span>
      <button
        type="button"
        class="inline-flex items-center justify-center p-1.5 -m-1 cursor-pointer hover:text-primary transition-colors z-10 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary rounded"
        phx-hook="CopyToClipboard"
        id={"copy-task-kanban-#{@task.id}"}
        data-copy={@task.uuid}
        onclick="event.stopPropagation(); event.preventDefault();"
        aria-label="Copy task ID"
      >
        <.icon name="hero-clipboard-document" class="w-3 h-3" />
      </button>
      <%= if @task.due_at do %>
        <span class="flex items-center gap-1">
          <.icon name="hero-calendar" class="w-3 h-3" />
          {format_due_date(@task.due_at)}
        </span>
      <% end %>
      <%= if @task.agent_id do %>
        <span class="flex items-center gap-1">
          <.icon name="hero-user" class="w-3 h-3" /> Agent #{@task.agent_id}
        </span>
      <% end %>
      <%= if @task.tags && length(@task.tags) > 0 do %>
        <%= for tag <- Enum.take(@task.tags, 2) do %>
          <span class="badge badge-xs badge-ghost gap-1">
            <span class="w-1.5 h-1.5 rounded-full inline-block" style={"background-color: #{tag.color || "#6B7280"}"}></span>
            {tag.name}
          </span>
        <% end %>
      <% end %>
      <%= if Map.get(@task, :notes_count, 0) > 0 do %>
        <span class="flex items-center gap-0.5 text-base-content/40">
          <.icon name="hero-chat-bubble-bottom-center-text" class="w-3 h-3" />
          {Map.get(@task, :notes_count)}
        </span>
      <% end %>
    </div>
    """
  end

  defp grid_card_content(assigns) do
    ~H"""
    <!-- Task Header with Priority -->
    <div class="flex items-start justify-between gap-2 mb-3">
      <div class="flex-1 min-w-0">
        <h3
          class="text-base font-semibold text-base-content hover:text-primary transition-colors line-clamp-2 cursor-pointer"
          phx-click={@on_click}
          phx-value-task_id={@task.uuid}
        >
          {@task.title}
        </h3>
      </div>
      <.priority_badge priority={@task.priority} />
    </div>

    <!-- Description -->
    <%= if @task.description do %>
      <p class="text-sm text-base-content/60 line-clamp-3 mb-3">
        {@task.description}
      </p>
    <% end %>

    <!-- Task Metadata -->
    <div class="flex flex-wrap items-center gap-2 mt-auto pt-3 border-t border-base-300">
      <span class="badge badge-ghost badge-sm font-mono text-xs">
        {String.slice(@task.uuid || "", 0..7)}
      </span>
      <button
        type="button"
        class="inline-flex items-center justify-center min-h-[44px] min-w-[44px] cursor-pointer hover:text-primary transition-colors z-10 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary rounded"
        phx-hook="CopyToClipboard"
        id={"copy-task-grid-#{@task.id}"}
        data-copy={@task.uuid}
        onclick="event.stopPropagation(); event.preventDefault();"
        aria-label="Copy task ID"
      >
        <.icon name="hero-clipboard-document" class="w-3 h-3" />
      </button>
      <%= if @task.state do %>
        <.state_badge state_id={@task.state_id} state_name={@task.state.name} />
      <% end %>

      <%= if @task.due_at do %>
        <span class="badge badge-ghost badge-sm">
          <.icon name="hero-calendar" class="w-3 h-3 mr-1" />
          {format_due_date(@task.due_at)}
        </span>
      <% end %>

      <%= if @task.tags && length(@task.tags) > 0 do %>
        <%= for tag <- Enum.take(@task.tags, 3) do %>
          <span class="badge badge-ghost badge-sm">
            {tag.name}
          </span>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp card_class("kanban") do
    "group/card card bg-base-100 dark:bg-[hsl(60,2.1%,18.4%)] border border-base-content/8 hover:shadow-md transition-all cursor-pointer"
  end

  defp card_class("grid") do
    "card bg-base-200 border border-base-300 hover:shadow-lg transition-all group"
  end

  defp card_class(_), do: ""

  defp card_body_class("kanban"), do: "card-body p-3.5 sm:p-3"
  defp card_body_class("grid"), do: "card-body p-5"
  defp card_body_class(_), do: ""

  # State ID -> text color for inline list rows
  defp state_text_color(@state_todo), do: "text-base-content/55"
  defp state_text_color(@state_in_progress), do: "text-info/80"
  defp state_text_color(@state_in_review), do: "text-warning/80"
  defp state_text_color(@state_done), do: "text-success/80"
  defp state_text_color(_), do: "text-base-content/55"

  defp priority_class(priority) do
    cond do
      priority >= 3 -> "text-xs text-error"
      priority == 2 -> "text-xs text-warning"
      priority == 1 -> "text-xs text-info"
      true -> "text-xs text-base-content/40"
    end
  end

  defp priority_label(priority) do
    cond do
      priority >= 3 -> "High"
      priority == 2 -> "Med"
      priority == 1 -> "Low"
      true -> ""
    end
  end

end
