defmodule EyeInTheSkyWebWeb.Components.TaskCard do
  @moduledoc """
  Reusable task card component for kanban and task list views.
  """

  use Phoenix.Component
  import EyeInTheSkyWebWeb.CoreComponents

  attr :task, :map, required: true
  attr :variant, :string, default: "kanban", values: ["kanban", "grid"]
  attr :on_click, :string, default: nil

  def task_card(assigns) do
    ~H"""
    <div
      class={card_class(@variant)}
      phx-click={@on_click}
      phx-value-task_id={@task.id}
    >
      <div class={card_body_class(@variant)}>
        <%= if @variant == "kanban" do %>
          <.kanban_card_content task={@task} />
        <% else %>
          <.grid_card_content task={@task} />
        <% end %>
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
      <h4 class={
        "text-sm font-medium flex-1 " <>
          if @task.completed_at do
            "text-base-content/50 line-through"
          else
            "text-base-content"
          end
      }>
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
        {String.slice(@task.id, 0..7)}
      </span>
      <%= if @task.due_at do %>
        <span class="flex items-center gap-1">
          <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 16 16">
            <path d="M3.5 0a.5.5 0 0 1 .5.5V1h8V.5a.5.5 0 0 1 1 0V1h1a2 2 0 0 1 2 2v11a2 2 0 0 1-2 2H2a2 2 0 0 1-2-2V3a2 2 0 0 1 2-2h1V.5a.5.5 0 0 1 .5-.5zM1 4v10a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V4H1z" />
          </svg>
          {format_date(@task.due_at)}
        </span>
      <% end %>
      <%= if @task.agent_id do %>
        <span class="flex items-center gap-1">
          <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 16 16">
            <path d="M11 6a3 3 0 1 1-6 0 3 3 0 0 1 6 0z" />
            <path
              fill-rule="evenodd"
              d="M0 8a8 8 0 1 1 16 0A8 8 0 0 1 0 8zm8-7a7 7 0 0 0-5.468 11.37C3.242 11.226 4.805 10 8 10s4.757 1.225 5.468 2.37A7 7 0 0 0 8 1z"
            />
          </svg>
          {String.slice(@task.agent_id, 0..7)}
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
        <h3 class="text-base font-semibold text-base-content group-hover:text-primary transition-colors line-clamp-2">
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
        {String.slice(@task.id, 0..7)}
      </span>
      <%= if @task.state do %>
        <span class="badge badge-ghost badge-sm">
          {@task.state.name}
        </span>
      <% end %>

      <%= if @task.due_at do %>
        <span class="badge badge-ghost badge-sm">
          <svg class="w-3 h-3 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"
            />
          </svg>
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
    "card bg-base-100 border border-base-300 hover:border-primary hover:shadow-md transition-all cursor-pointer"
  end

  defp card_class("grid") do
    "card bg-base-200 border border-base-300 hover:border-primary hover:shadow-lg transition-all cursor-pointer group"
  end

  defp card_body_class("kanban"), do: "card-body p-3"
  defp card_body_class("grid"), do: "card-body p-5"

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
