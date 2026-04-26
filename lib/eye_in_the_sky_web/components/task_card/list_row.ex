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
  attr :select_mode, :boolean, default: false
  attr :selected, :boolean, default: false

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
        "group/row relative",
        @task.completed_at && "opacity-60 hover:opacity-80"
      ]}
    >
      <%!-- Checkbox: absolute, outside row flow, hover-reveal --%>
      <div class={[
        "p-1 absolute z-10 top-1/2 -translate-y-1/2 -translate-x-1/2 left-0 transition duration-100",
        if(@select_mode,
          do: "opacity-100 scale-100",
          else: "opacity-0 scale-75 group-hover/row:opacity-100 group-hover/row:scale-100"
        )
      ]}>
        <.square_checkbox
          checked={@selected}
          phx-click="toggle_select_task"
          phx-value-task_id={@task.uuid || to_string(@task.id)}
          aria-label={"Select task #{@task.title}"}
        />
      </div>

      <%!-- Row body --%>
      <div
        class="flex items-center gap-4 py-3 pr-2 pl-2 hover:bg-base-200/40 rounded-lg cursor-pointer"
        phx-click={if @select_mode, do: "toggle_select_task", else: @on_click}
        phx-keyup={if !@select_mode, do: @on_click}
        phx-key="Enter"
        phx-value-task_id={@task.uuid || to_string(@task.id)}
        role="button"
        tabindex="0"
        aria-label={"Open task #{@task.title}"}
      >
        <%!-- Completion icon --%>
        <.icon
          name={if @task.completed_at, do: "hero-check-circle-mini", else: "hero-circle-mini"}
          class={
            if(@task.completed_at,
              do: "size-3.5 shrink-0 text-success/60",
              else: "size-3.5 shrink-0 text-base-content/20 group-hover/row:text-base-content/35"
            )
          }
        />

        <%!-- Content --%>
        <div class="flex-1 min-w-0">
          <span class={[
            "text-[13px] font-medium truncate block",
            if(@task.completed_at,
              do: "text-base-content/45 line-through",
              else: "text-base-content/85 group-hover/row:text-base-content"
            )
          ]}>
            {@task.title}
          </span>

          <%!-- Metadata line --%>
          <div class="flex items-center gap-1.5 flex-wrap mt-1 text-[11px]">
            <%!-- State pill --%>
            <%= if @task.state do %>
              <span class={["px-1.5 py-px rounded-full font-medium text-[10px]", state_pill_class(@task.state_id)]}>
                {@task.state.name}
              </span>
            <% end %>

            <%!-- Priority badge (only when set) --%>
            <%= if is_integer(@task.priority) && @task.priority > 0 do %>
              <span class={["px-1.5 py-px rounded-full font-medium text-[10px]", priority_pill_class(@task.priority)]}>
                {priority_label(@task.priority)}
              </span>
            <% end %>

            <%!-- Agent name (replaces UUID — much more useful scan anchor) --%>
            <%= if @task.agent do %>
              <span class="text-base-content/15">&middot;</span>
              <span class="text-base-content/40 truncate max-w-[160px]">{@task.agent.description}</span>
            <% end %>

            <%!-- Notes count --%>
            <%= if @task.notes_count > 0 do %>
              <span class="text-base-content/15">&middot;</span>
              <span class="flex items-center gap-0.5 text-base-content/35">
                <.icon name="hero-chat-bubble-left-mini" class="size-3" />
                {@task.notes_count}
              </span>
            <% end %>

            <%!-- Updated time --%>
            <span class="text-base-content/15">&middot;</span>
            <span class="tabular-nums text-base-content/35">
              {relative_time(@task.updated_at || @task.created_at)}
            </span>
          </div>
        </div>

        <%!-- Hover actions --%>
        <div class="flex items-center gap-0.5 shrink-0 md:opacity-0 md:group-hover/row:opacity-100 transition-opacity">
          <%= if @dm_session do %>
            <.link
              navigate={"/dm/#{@dm_session.uuid}"}
              class="btn btn-ghost btn-xs btn-square text-base-content/40 hover:text-primary focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
              title="Open agent DM"
              aria-label="Open agent direct message"
              onclick="event.stopPropagation();"
            >
              <.icon name="hero-chat-bubble-left-ellipsis" class="size-3.5" />
            </.link>
          <% end %>

          <%= if @on_delete do %>
            <button
              type="button"
              phx-click={@on_delete}
              phx-value-task_id={@task.uuid || to_string(@task.id)}
              aria-label="Delete task"
              class="btn btn-ghost btn-xs btn-square text-base-content/40 hover:text-error focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-error"
              onclick="event.stopPropagation();"
            >
              <.icon name="hero-trash-mini" class="size-3.5" />
            </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # State pill — muted bg-*/15 pattern, not full DaisyUI badge saturation
  defp state_pill_class(@state_todo), do: "bg-base-content/10 text-base-content/50"
  defp state_pill_class(@state_in_progress), do: "bg-info/15 text-info"
  defp state_pill_class(@state_in_review), do: "bg-warning/15 text-warning"
  defp state_pill_class(@state_done), do: "bg-success/15 text-success"
  defp state_pill_class(_), do: "bg-base-content/10 text-base-content/50"

  defp priority_pill_class(p) when p >= 3, do: "bg-error/15 text-error"
  defp priority_pill_class(2), do: "bg-warning/15 text-warning"
  defp priority_pill_class(1), do: "bg-base-content/10 text-base-content/50"
  defp priority_pill_class(_), do: ""

  defp priority_label(p) when p >= 3, do: "High"
  defp priority_label(2), do: "Med"
  defp priority_label(1), do: "Low"
  defp priority_label(_), do: ""
end
