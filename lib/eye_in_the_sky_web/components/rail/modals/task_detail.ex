defmodule EyeInTheSkyWeb.Components.Rail.Modals.TaskDetail do
  @moduledoc false
  use EyeInTheSkyWeb, :html

  alias EyeInTheSkyWeb.Components.Rail.Flyout.TasksSection

  attr :task, :map, required: true
  attr :index, :integer, required: true
  attr :total, :integer, required: true
  attr :myself, :any, required: true

  def task_detail_modal(assigns) do
    task_link =
      if assigns.task && assigns.task.project_id do
        "/projects/#{assigns.task.project_id}/tasks?task_id=#{assigns.task.id}"
      else
        "/projects"
      end

    assigns = assign(assigns, :task_link, task_link)

    ~H"""
    <div class="fixed left-[296px] top-[48px] z-[100] w-[420px] h-[480px] bg-base-100 border border-base-content/10 rounded-lg shadow-xl p-4 flex flex-col gap-3">
      <%!-- Header --%>
      <div class="flex items-start justify-between gap-2 flex-shrink-0">
        <span class="text-sm font-semibold text-base-content/85 leading-snug">{@task.title}</span>
        <button
          type="button"
          phx-click="close_rail_modal"
          phx-target={@myself}
          class="size-5 flex-shrink-0 flex items-center justify-center rounded text-base-content/40 hover:text-base-content/70 hover:bg-base-content/8 transition-colors"
        >
          <.icon name="hero-x-mark-mini" class="size-3.5" />
        </button>
      </div>

      <%!-- State badge --%>
      <div class="flex items-center gap-2 flex-shrink-0">
        <span class={[
          "w-1.5 h-1.5 rounded-full flex-shrink-0",
          TasksSection.task_state_dot(@task.state_id)
        ]} />
        <span class="text-xs text-base-content/55">{task_state_label(@task.state_id)}</span>
      </div>

      <%!-- Description --%>
      <div class="flex-1 min-h-0 overflow-y-auto">
        <%= if @task.description && @task.description != "" do %>
          <p class="text-xs text-base-content/60 leading-relaxed whitespace-pre-wrap break-words">
            {@task.description}
          </p>
        <% else %>
          <p class="text-xs text-base-content/30 italic">No description.</p>
        <% end %>
      </div>

      <%!-- Footer: prev/next + counter + open link --%>
      <div class="flex items-center justify-between pt-1 border-t border-base-content/8 flex-shrink-0">
        <%!-- Prev / counter / Next --%>
        <div class="flex items-center gap-1">
          <button
            type="button"
            phx-click="task_detail_nav"
            phx-value-dir="prev"
            phx-target={@myself}
            disabled={@total <= 1}
            class="size-6 flex items-center justify-center rounded text-base-content/40 hover:text-base-content/80 hover:bg-base-content/8 transition-colors disabled:opacity-25"
          >
            <.icon name="hero-chevron-left-mini" class="size-3.5" />
          </button>
          <span class="text-nano text-base-content/35 tabular-nums">
            {@index + 1}/{@total}
          </span>
          <button
            type="button"
            phx-click="task_detail_nav"
            phx-value-dir="next"
            phx-target={@myself}
            disabled={@total <= 1}
            class="size-6 flex items-center justify-center rounded text-base-content/40 hover:text-base-content/80 hover:bg-base-content/8 transition-colors disabled:opacity-25"
          >
            <.icon name="hero-chevron-right-mini" class="size-3.5" />
          </button>
        </div>

        <%!-- Open link --%>
        <.link
          navigate={@task_link}
          class="px-3 py-1 text-xs bg-primary text-primary-content rounded hover:opacity-90 transition-opacity font-medium"
        >
          Open task →
        </.link>
      </div>
    </div>
    """
  end

  defp task_state_label(1), do: "To Do"
  defp task_state_label(2), do: "In Progress"
  defp task_state_label(3), do: "Done"
  defp task_state_label(4), do: "In Review"
  defp task_state_label(_), do: "Unknown"
end
