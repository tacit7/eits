defmodule EyeInTheSkyWebWeb.Components.TaskCard do
  @moduledoc """
  Reusable task card component for kanban and task list views.
  """

  use Phoenix.Component
  import EyeInTheSkyWebWeb.CoreComponents

  attr :task, :map, required: true
  attr :variant, :string, default: "kanban", values: ["kanban", "grid", "list"]
  attr :on_click, :string, default: nil

  def task_card(assigns) do
    ~H"""
    <%= case @variant do %>
      <% "list" -> %>
        <.list_row task={@task} on_click={@on_click} />
      <% _ -> %>
        <div class={card_class(@variant)}>
          <div class={card_body_class(@variant)}>
            <%= if @variant == "kanban" do %>
              <.kanban_card_content task={@task} on_click={@on_click} />
            <% else %>
              <.grid_card_content task={@task} on_click={@on_click} />
            <% end %>
          </div>
        </div>
    <% end %>
    """
  end

  defp list_row(assigns) do
    ~H"""
    <div
      class="group flex flex-col gap-1 py-3.5 cursor-pointer"
      phx-click={@on_click}
      phx-value-task_id={@task.uuid}
    >
      <span class={[
        "text-sm font-medium truncate",
        @task.completed_at && "text-base-content/40 line-through",
        !@task.completed_at && "text-base-content/85 group-hover:text-base-content"
      ]}>
        {@task.title}
      </span>
      <div class="flex items-center gap-1.5 text-xs text-base-content/35">
        <%= if @task.state do %>
          <span class={state_text_color(@task.state_id)}>{@task.state.name}</span>
        <% end %>
        <%= if @task.tags && length(@task.tags) > 0 do %>
          <span class="text-base-content/15">&middot;</span>
          <span>{Enum.map_join(Enum.take(@task.tags, 2), ", ", & &1.name)}</span>
        <% end %>
        <span class="text-base-content/15">&middot;</span>
        <span class="font-mono">{String.slice(@task.uuid, 0..7)}</span>
      </div>
    </div>
    """
  end

  defp kanban_card_content(assigns) do
    ~H"""
    <!-- Task Title with Checkbox -->
    <div class="flex items-start gap-2 mb-2">
      <button class={
        "mt-0.5 flex-shrink-0 w-4 h-4 rounded-sm border-2 transition-all " <>
          if @task.completed_at do
            "bg-success border-success"
          else
            "border-base-content/30 hover:border-base-content/60"
          end
      }>
        <%= if @task.completed_at do %>
          <svg
            class="w-full h-full text-white p-0.5"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="3"
              d="M5 13l4 4L19 7"
            />
          </svg>
        <% end %>
      </button>
      <h4
        class={
          "text-sm font-medium flex-1 hover:text-primary transition-colors cursor-pointer " <>
            if @task.completed_at do
              "text-base-content/50 line-through"
            else
              "text-base-content"
            end
        }
        phx-click={@on_click}
        phx-value-task_id={@task.uuid}
      >
        {@task.title}
      </h4>
      <%= if @task.priority && @task.priority > 0 do %>
        <span class={priority_class(@task.priority)}>
          {priority_label(@task.priority)}
        </span>
      <% end %>
    </div>

    <!-- Description -->
    <%= if @task.description do %>
      <p class="text-xs text-base-content/60 line-clamp-2 mb-2">
        {@task.description}
      </p>
    <% end %>

    <!-- Meta Info -->
    <div class="flex items-center gap-2 text-xs text-base-content/50 flex-wrap">
      <span class="font-mono text-xs">
        {String.slice(@task.uuid, 0..7)}
      </span>
      <button
        type="button"
        class="cursor-pointer hover:text-primary transition-colors z-10"
        phx-hook="CopyToClipboard"
        id={"copy-task-kanban-#{@task.id}"}
        data-copy={@task.uuid}
        onclick="event.stopPropagation(); event.preventDefault();"
      >
        <.icon name="hero-clipboard-document" class="w-3 h-3" />
      </button>
      <%= if @task.due_at do %>
        <span class="flex items-center gap-1">
          <.icon name="hero-calendar" class="w-3 h-3" />
          {format_date(@task.due_at)}
        </span>
      <% end %>
      <%= if @task.agent_id do %>
        <span class="flex items-center gap-1">
          <.icon name="hero-user" class="w-3 h-3" /> Agent #{@task.agent_id}
        </span>
      <% end %>
      <%= if @task.tags && length(@task.tags) > 0 do %>
        <%= for tag <- Enum.take(@task.tags, 2) do %>
          <span class="badge badge-xs badge-ghost">
            {tag.name}
          </span>
        <% end %>
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
      <%= cond do %>
        <% @task.priority >= 70 -> %>
          <span class="badge badge-error badge-sm flex-shrink-0">High</span>
        <% @task.priority >= 40 -> %>
          <span class="badge badge-warning badge-sm flex-shrink-0">Med</span>
        <% @task.priority >= 20 -> %>
          <span class="badge badge-info badge-sm flex-shrink-0">Low</span>
        <% true -> %>
          <span></span>
      <% end %>
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
        {String.slice(@task.uuid, 0..7)}
      </span>
      <button
        type="button"
        class="cursor-pointer hover:text-primary transition-colors z-10"
        phx-hook="CopyToClipboard"
        id={"copy-task-grid-#{@task.id}"}
        data-copy={@task.uuid}
        onclick="event.stopPropagation(); event.preventDefault();"
      >
        <.icon name="hero-clipboard-document" class="w-3 h-3" />
      </button>
      <%= if @task.state do %>
        <span class="badge badge-ghost badge-sm">
          {@task.state.name}
        </span>
      <% end %>

      <%= if @task.due_at do %>
        <span class="badge badge-ghost badge-sm">
          <.icon name="hero-calendar" class="w-3 h-3 mr-1" />
          {format_date(@task.due_at)}
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
    "card bg-base-100 border border-base-300 hover:shadow-md transition-all"
  end

  defp card_class("grid") do
    "card bg-base-200 border border-base-300 hover:shadow-lg transition-all group"
  end

  defp card_class(_), do: ""

  defp card_body_class("kanban"), do: "card-body p-3"
  defp card_body_class("grid"), do: "card-body p-5"
  defp card_body_class(_), do: ""

  defp priority_dot_color(priority) when is_integer(priority) do
    cond do
      priority >= 70 -> "bg-error"
      priority >= 40 -> "bg-warning"
      priority >= 20 -> "bg-info"
      priority > 0 -> "bg-base-content/20"
      true -> "bg-base-content/10"
    end
  end

  defp priority_dot_color(_), do: "bg-base-content/10"

  # State ID -> badge class mapping (matches workflow_states table)
  defp state_badge_class(1), do: "bg-base-content/[0.06] text-base-content/50"
  defp state_badge_class(2), do: "bg-info/10 text-info"
  defp state_badge_class(4), do: "bg-warning/10 text-warning"
  defp state_badge_class(3), do: "bg-success/10 text-success"
  defp state_badge_class(_), do: "bg-base-content/[0.06] text-base-content/40"

  # State ID -> text color for inline list rows
  defp state_text_color(1), do: "text-base-content/40"
  defp state_text_color(2), do: "text-info/70"
  defp state_text_color(4), do: "text-warning/70"
  defp state_text_color(3), do: "text-success/70"
  defp state_text_color(_), do: "text-base-content/35"

  defp priority_class(priority) do
    cond do
      priority >= 4 -> "text-xs text-error"
      priority >= 3 -> "text-xs text-warning"
      priority >= 2 -> "text-xs text-info"
      true -> "text-xs text-base-content/40"
    end
  end

  defp priority_label(priority) do
    cond do
      priority >= 4 -> "P1"
      priority >= 3 -> "P2"
      priority >= 2 -> "P3"
      true -> "P#{priority}"
    end
  end

  defp format_date(nil), do: ""

  defp format_date(datetime) when is_binary(datetime) do
    case NaiveDateTime.from_iso8601(datetime) do
      {:ok, naive_dt} -> format_date(naive_dt)
      _ -> datetime
    end
  end

  defp format_date(datetime) do
    today = Date.utc_today()
    date = NaiveDateTime.to_date(datetime)

    cond do
      Date.compare(date, today) == :eq -> "Today"
      Date.compare(date, Date.add(today, 1)) == :eq -> "Tomorrow"
      true -> Calendar.strftime(datetime, "%b %d")
    end
  end
end
