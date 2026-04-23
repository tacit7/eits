defmodule EyeInTheSkyWeb.Components.TaskCard.ListRow do
  @moduledoc """
  List-view task row component.
  """

  use Phoenix.Component
  import EyeInTheSkyWeb.CoreComponents

  import EyeInTheSkyWeb.Helpers.ViewHelpers,
    only: [relative_time: 1]

  alias EyeInTheSky.Tasks.WorkflowState

  @state_todo WorkflowState.todo_id()
  @state_in_progress WorkflowState.in_progress_id()
  @state_in_review WorkflowState.in_review_id()
  @state_done WorkflowState.done_id()

  attr :task, :map, required: true
  attr :on_click, :string, default: nil
  attr :on_delete, :string, default: nil

  def list_row(assigns) do
    dm_session =
      case assigns.task do
        %{sessions: [session | _]} -> session
        _ -> nil
      end

    assigns = assign(assigns, :dm_session, dm_session)

    ~H"""
    <div
      class={[
        "group flex items-center gap-3 py-3.5 cursor-pointer",
        @task.completed_at && "opacity-60"
      ]}
      phx-click={@on_click}
      phx-keyup={@on_click}
      phx-key="Enter"
      phx-value-task_id={@task.uuid || to_string(@task.id)}
      role="button"
      tabindex="0"
      aria-label={"Open task #{@task.title}"}
    >
      <%!-- Completion indicator --%>
      <div class="flex-shrink-0">
        <.icon
          name={if @task.completed_at, do: "hero-check-circle-mini", else: "hero-circle-mini"}
          class={
            if @task.completed_at,
              do: "w-3.5 h-3.5 text-success/60",
              else: "w-3.5 h-3.5 text-base-content/20"
          }
        />
      </div>

      <%!-- Title + metadata --%>
      <div class="flex flex-col gap-0.5 flex-1 min-w-0">
        <span class={[
          "text-sm font-medium truncate",
          @task.completed_at && "text-base-content/50 line-through",
          !@task.completed_at && "text-base-content/85 group-hover:text-base-content"
        ]}>
          {@task.title}
        </span>
        <div class="flex items-center gap-1.5 text-xs">
          <%!-- State with color --%>
          <%= if @task.state do %>
            <span class={state_text_color(@task.state_id)}>{@task.state.name}</span>
            <span class="text-base-content/15">&middot;</span>
          <% end %>
          <%!-- Session link (scan anchor) or task UUID fallback --%>
          <%= if @dm_session do %>
            <.link
              navigate={"/dm/#{@dm_session.uuid}"}
              class="font-mono text-base-content/45 hover:text-primary transition-colors"
              onclick="event.stopPropagation();"
              title="Open session"
            >
              {String.slice(@dm_session.uuid, 0..7)}
            </.link>
          <% else %>
            <span class="font-mono text-base-content/25">
              {String.slice(@task.uuid || "", 0..7)}
            </span>
          <% end %>
          <%!-- Updated time --%>
          <span class="text-base-content/15">&middot;</span>
          <span class="tabular-nums text-base-content/45">
            {relative_time(@task.updated_at || @task.created_at)}
          </span>
          <%!-- Tags (compact, lower priority) --%>
          <%= if not is_nil(@task.tags) && @task.tags != [] do %>
            <span class="text-base-content/15">&middot;</span>
            <span class="text-base-content/35">
              {Enum.map_join(Enum.take(@task.tags, 2), ", ", & &1.name)}
            </span>
          <% end %>
        </div>
      </div>

      <%!-- Hover actions — always same position, hidden until hover --%>
      <div class="flex items-center flex-shrink-0 md:opacity-0 md:group-hover:opacity-100 transition-opacity">
        <%= if @dm_session do %>
          <.link
            navigate={"/dm/#{@dm_session.uuid}"}
            class="min-h-[44px] min-w-[44px] flex items-center justify-center rounded-md text-base-content/40 hover:text-primary hover:bg-primary/10 transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
            title="Open agent DM"
            aria-label="Open agent direct message"
            onclick="event.stopPropagation();"
          >
            <.icon name="hero-chat-bubble-left-ellipsis" class="w-3.5 h-3.5" />
          </.link>
        <% end %>
        <%= if @on_delete do %>
          <button
            type="button"
            phx-click={@on_delete}
            phx-value-task_id={@task.uuid || to_string(@task.id)}
            aria-label="Delete task"
            class="min-h-[44px] min-w-[44px] flex items-center justify-center rounded-md text-base-content/40 hover:text-error hover:bg-error/10 transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-error"
          >
            <.icon name="hero-trash-mini" class="w-3.5 h-3.5" />
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  defp state_text_color(@state_todo), do: "text-base-content/55"
  defp state_text_color(@state_in_progress), do: "text-info/80"
  defp state_text_color(@state_in_review), do: "text-warning/80"
  defp state_text_color(@state_done), do: "text-success/80"
  defp state_text_color(_), do: "text-base-content/55"
end
