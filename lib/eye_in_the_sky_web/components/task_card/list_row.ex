defmodule EyeInTheSkyWeb.Components.TaskCard.ListRow do
  @moduledoc """
  List-view task row component.
  """

  use Phoenix.Component
  import EyeInTheSkyWeb.CoreComponents

  import EyeInTheSkyWeb.Helpers.ViewHelpers,
    only: [relative_time: 1, overdue?: 1, due_today?: 1, format_due_date: 1]

  alias EyeInTheSky.Tasks.WorkflowState
  alias Phoenix.LiveView.JS

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
    <%!--
      Row state legend:
      default  → no bg, dim text
      hover    → bg-base-200/40, brighter text, reveal checkbox+actions
      focus-visible (keyboard) → focus-visible:ring-2 ring-primary/50
      vim-nav-focused → [&.vim-nav-focused]:ring-2 ring-primary/50
      selected/open   → data-drawer-open: left accent + bg-base-200/60 + ring-1 ring-primary/20
      checked (bulk)  → outer wrapper bg-primary/8
      done            → opacity-60, title line-through, dimmer metadata
    --%>
    <div
      id={"task-row-#{@task.id}"}
      class={[
        "group/row relative",
        @task.completed_at && "opacity-60 hover:opacity-80",
        @selected && @select_mode && "bg-primary/8 rounded-lg"
      ]}
    >
      <%!-- Left accent bar — visible when this row is open in the drawer --%>
      <div class="absolute left-0 top-1 bottom-1 w-0.5 rounded-full bg-primary opacity-0 group-[[data-drawer-open]]/row:opacity-100 transition-opacity pointer-events-none" />

      <%!-- Checkbox — revealed on hover, selected, focus, and bulk mode --%>
      <div
        class={[
          "p-1 absolute z-10 top-1/2 -translate-y-1/2 -translate-x-1/2",
          "left-4 sm:left-[-0.875rem]",
          if(@select_mode,
            do: "opacity-100 scale-100",
            else:
              "opacity-0 scale-75 transition duration-100 " <>
                "group-hover/row:opacity-100 group-hover/row:scale-100 " <>
                "group-[[data-drawer-open]]/row:opacity-100 group-[[data-drawer-open]]/row:scale-100"
          )
        ]}
        aria-hidden={to_string(!@select_mode)}
        phx-click="toggle_select_task"
        phx-value-task_id={@task.uuid || to_string(@task.id)}
      >
        <.square_checkbox
          checked={@selected}
          checkbox_area={true}
          aria-label={"Select task #{@task.title}"}
        />
      </div>

      <%!-- Row body --%>
      <div
        class={[
          "flex items-center gap-4 py-3 pr-2 pl-2 rounded-lg cursor-pointer",
          "hover:bg-base-200/40",
          "focus:outline-none focus-visible:ring-2 focus-visible:ring-primary/50",
          "[&.vim-nav-focused]:ring-2 [&.vim-nav-focused]:ring-primary/50",
          "group-[[data-drawer-open]]/row:bg-base-200/60",
          "group-[[data-drawer-open]]/row:ring-1 group-[[data-drawer-open]]/row:ring-inset group-[[data-drawer-open]]/row:ring-primary/20"
        ]}
        data-vim-list-item
        data-vim-item-type="task"
        data-vim-item-id={@task.id}
        data-vim-item-title={@task.title}
        data-vim-item-url={"/projects/#{@task.project_id}/tasks?task=#{@task.uuid}"}
        phx-click={
          if @select_mode do
            "toggle_select_task"
          else
            JS.remove_attribute("data-drawer-open", to: "[data-drawer-open]")
            |> JS.set_attribute({"data-drawer-open", ""}, to: "#task-row-#{@task.id}")
            |> JS.push(@on_click || "")
          end
        }
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

          <%!-- Metadata line — extra dim when task is done --%>
          <div class={["flex items-center gap-1.5 flex-wrap mt-1 text-mini", @task.completed_at && "opacity-70"]}>
            <%!-- State pill --%>
            <%= if is_struct(@task.state, EyeInTheSky.Tasks.WorkflowState) do %>
              <span class={[
                "px-1.5 py-px rounded-full font-medium text-micro",
                state_pill_class(@task.state_id)
              ]}>
                {@task.state.name}
              </span>
            <% end %>

            <%!-- Priority badge (only when set) --%>
            <%= if is_integer(@task.priority) && @task.priority > 0 do %>
              <span class={[
                "px-1.5 py-px rounded-full font-medium text-micro",
                priority_pill_class(@task.priority)
              ]}>
                {priority_label(@task.priority)}
              </span>
            <% end %>

            <%!-- Agent ID --%>
            <%= if @task.agent_id do %>
              <span class="text-base-content/15">&middot;</span>
              <span class="flex items-center gap-0.5 text-base-content/40">
                <.custom_icon name="lucide-robot" class="size-3 shrink-0" />
                <span class="font-mono">#{@task.agent_id}</span>
              </span>
            <% end %>

            <%!-- Due date --%>
            <%= if @task.due_at do %>
              <span class="text-base-content/15">&middot;</span>
              <span class={[
                "flex items-center gap-0.5 text-micro font-medium",
                cond do
                  overdue?(@task.due_at) -> "text-error"
                  due_today?(@task.due_at) -> "text-warning"
                  true -> "text-base-content/35"
                end
              ]}>
                <.icon name="hero-calendar-mini" class="size-3" />
                {format_due_date(@task.due_at)}
              </span>
            <% end %>

            <%!-- Tags --%>
            <%= if is_list(@task.tags) && @task.tags != [] do %>
              <%= for tag <- Enum.take(@task.tags, 3) do %>
                <span class="text-base-content/15">&middot;</span>
                <span class="px-1 py-px rounded text-micro bg-base-content/8 text-base-content/40">
                  {tag.name}
                </span>
              <% end %>
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

        <%!-- Hover actions — also revealed when row is selected (data-drawer-open) or focused via vim-nav --%>
        <div class="flex items-center gap-0.5 shrink-0 md:opacity-0 md:group-hover/row:opacity-100 md:group-[[data-drawer-open]]/row:opacity-100 transition-opacity">
          <%= if @dm_session do %>
            <.link
              navigate={"/dm/#{@dm_session.uuid}"}
              class="btn btn-ghost btn-xs btn-square text-base-content/40 hover:text-primary focus-ring"
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
