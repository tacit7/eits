defmodule EyeInTheSkyWeb.Components.TaskCard.GridCard do
  @moduledoc """
  Grid-view task card component.
  """

  use Phoenix.Component
  import EyeInTheSkyWeb.CoreComponents

  import EyeInTheSkyWeb.Helpers.ViewHelpers,
    only: [format_due_date: 1, relative_time: 1]

  attr :task, :map, required: true
  attr :on_click, :string, default: nil
  attr :rest, :global

  def grid_card(assigns) do
    ~H"""
    <div class="card bg-base-200 border border-base-300 hover:shadow-lg transition-all group" {@rest}>
      <div class="card-body p-5">
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
          <%= if @task.uuid do %>
            <span class="badge badge-ghost badge-sm font-mono text-xs">
              {String.slice(@task.uuid, 0..7)}
            </span>
          <% end %>
          <%= if @task.created_at do %>
            <span class="badge badge-ghost badge-sm text-xs tabular-nums">
              {relative_time(@task.created_at)}
            </span>
          <% end %>
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

          <%= if not is_nil(@task.tags) && @task.tags != [] do %>
            <%= for tag <- Enum.take(@task.tags, 3) do %>
              <span class="badge badge-ghost badge-sm">
                {tag.name}
              </span>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
