defmodule EyeInTheSkyWebWeb.Components.TaskCard do
  @moduledoc """
  Reusable task card component for kanban and task list views.
  """

  use Phoenix.Component
  import EyeInTheSkyWebWeb.CoreComponents

  import EyeInTheSkyWebWeb.Helpers.ViewHelpers,
    only: [format_due_date: 1, card_aging_indicator: 1, relative_time: 1]

  alias EyeInTheSkyWeb.Tasks.WorkflowState

  @state_todo WorkflowState.todo_id()
  @state_in_progress WorkflowState.in_progress_id()
  @state_in_review WorkflowState.in_review_id()
  @state_done WorkflowState.done_id()

  attr :task, :map, required: true
  attr :variant, :string, default: "kanban", values: ["kanban", "grid", "list"]
  attr :on_click, :string, default: nil
  attr :on_delete, :string, default: nil
  attr :working_session_ids, :any, default: nil
  attr :workflow_states, :list, default: []
  attr :rest, :global

  def task_card(assigns) do
    aging =
      if assigns.variant == "kanban",
        do: card_aging_indicator(Map.get(assigns.task, :updated_at)),
        else: nil

    assigns = assign(assigns, :aging, aging)

    ~H"""
    <%= case @variant do %>
      <% "list" -> %>
        <.list_row task={@task} on_click={@on_click} on_delete={@on_delete} />
      <% _ -> %>
        <div class={[card_class(@variant), @aging && elem(@aging, 0)]} {@rest}>
          <%= if @variant == "kanban" && Map.get(@task, :priority, 0) > 0 do %>
            <div class="h-0.5 w-full rounded-t" style={"background-color: #{priority_bar_color(Map.get(@task, :priority))}"} />
          <% end %>
          <div class={card_body_class(@variant)}>
            <%= if @variant == "kanban" do %>
              <.kanban_card_content
                task={@task}
                on_click={@on_click}
                on_delete={@on_delete}
                aging={@aging}
                working_session_ids={@working_session_ids}
                workflow_states={@workflow_states}
              />
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
          <span class="text-base-content/15">&middot;</span>
          <span class="tabular-nums">{relative_time(@task.created_at)}</span>
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
    dm_session =
      case assigns.task do
        %{sessions: [s | _]} -> s
        _ -> nil
      end

    assigns =
      assigns
      |> assign(:dm_session, dm_session)
      |> assign_new(:workflow_states, fn -> [] end)

    ~H"""
    <%!-- Title + drag handle + delete --%>
    <div class="flex items-start gap-1.5">
      <div
        data-drag-handle
        class="flex-shrink-0 mt-0.5 touch-none cursor-grab active:cursor-grabbing flex md:hidden text-base-content/20 hover:text-base-content/40"
        aria-label="Drag to reorder"
      >
        <.icon name="hero-bars-2" class="w-3.5 h-3.5" />
      </div>
      <%!-- Completion toggle --%>
      <button
        type="button"
        phx-click="toggle_task_complete"
        phx-value-task_id={@task.uuid || to_string(@task.id)}
        aria-label={if @task.completed_at, do: "Mark task incomplete", else: "Mark task complete"}
        aria-pressed={to_string(!is_nil(@task.completed_at))}
        class="flex-shrink-0 mt-0.5 flex items-center justify-center w-4 h-4 rounded text-base-content/30 hover:text-success transition-colors"
      >
        <.icon
          name={if @task.completed_at, do: "hero-check-circle-mini", else: "hero-circle-mini"}
          class="w-4 h-4"
        />
      </button>
      <h4
        class={[
          "text-xs font-medium flex-1 leading-snug cursor-pointer hover:text-primary transition-colors",
          @task.completed_at && "text-base-content/40 line-through",
          !@task.completed_at && "text-base-content"
        ]}
        phx-click={@on_click}
        phx-value-task_id={@task.uuid || to_string(@task.id)}
      >
        {@task.title}
      </h4>
      <%!-- ... menu --%>
      <div
        class="flex-shrink-0 opacity-0 group-hover/card:opacity-100 transition-opacity"
        onclick="event.stopPropagation();"
      >
        <details class="dropdown dropdown-end">
          <summary class="flex items-center justify-center w-6 h-6 rounded text-base-content/25 hover:text-base-content/60 hover:bg-base-content/8 cursor-pointer list-none transition-colors">
            <.icon name="hero-ellipsis-horizontal-mini" class="w-3.5 h-3.5" />
          </summary>
          <div class="dropdown-content z-50 mt-1 w-48 rounded-xl bg-base-300 dark:bg-[hsl(220,13%,18%)] shadow-xl p-1.5 flex flex-col gap-0.5">
            <%!-- Open card --%>
            <button
              type="button"
              phx-click={@on_click}
              phx-value-task_id={@task.uuid || to_string(@task.id)}
              class="w-full flex items-center gap-3 px-3 py-2 rounded-lg text-sm text-base-content hover:bg-base-content/10 transition-colors text-left"
            >
              <.icon name="hero-rectangle-stack-mini" class="w-4 h-4 text-base-content/60 flex-shrink-0" />
              Open card
            </button>
            <%!-- Edit labels --%>
            <button
              type="button"
              phx-click={@on_click}
              phx-value-task_id={@task.uuid || to_string(@task.id)}
              class="w-full flex items-center gap-3 px-3 py-2 rounded-lg text-sm text-base-content hover:bg-base-content/10 transition-colors text-left"
            >
              <.icon name="hero-tag-mini" class="w-4 h-4 text-base-content/60 flex-shrink-0" />
              Edit labels
            </button>
            <%!-- Edit dates --%>
            <button
              type="button"
              phx-click={@on_click}
              phx-value-task_id={@task.uuid || to_string(@task.id)}
              class="w-full flex items-center gap-3 px-3 py-2 rounded-lg text-sm text-base-content hover:bg-base-content/10 transition-colors text-left"
            >
              <.icon name="hero-clock-mini" class="w-4 h-4 text-base-content/60 flex-shrink-0" />
              Edit dates
            </button>
            <%!-- Copy link --%>
            <button
              type="button"
              phx-hook="CopyToClipboard"
              id={"copy-task-kanban-#{@task.id}"}
              data-copy={@task.uuid || to_string(@task.id)}
              onclick="event.preventDefault();"
              class="w-full flex items-center gap-3 px-3 py-2 rounded-lg text-sm text-base-content hover:bg-base-content/10 transition-colors text-left"
            >
              <.icon name="hero-link-mini" class="w-4 h-4 text-base-content/60 flex-shrink-0" />
              Copy link
            </button>
            <%!-- Move submenu --%>
            <%= if @workflow_states != [] do %>
              <div class="border-t border-base-content/10 my-0.5" />
              <details class="group/move">
                <summary class="w-full flex items-center gap-3 px-3 py-2 rounded-lg text-sm text-base-content hover:bg-base-content/10 transition-colors cursor-pointer list-none">
                  <.icon name="hero-arrow-right-mini" class="w-4 h-4 text-base-content/60 flex-shrink-0" />
                  <span class="flex-1">Move</span>
                  <.icon name="hero-chevron-right-mini" class="w-3 h-3 text-base-content/40" />
                </summary>
                <div class="mt-0.5 ml-3 flex flex-col gap-0.5">
                  <%= for state <- @workflow_states do %>
                    <button
                      type="button"
                      phx-click="move_task"
                      phx-value-task_id={@task.uuid || to_string(@task.id)}
                      phx-value-state_id={state.id}
                      onclick="event.stopPropagation();"
                      class="w-full flex items-center gap-2 px-3 py-1.5 rounded-lg text-sm text-base-content/80 hover:bg-base-content/10 transition-colors text-left"
                    >
                      <span
                        class="w-2 h-2 rounded-full flex-shrink-0"
                        style={"background-color: #{state.color || "#6B7280"}"}
                      />
                      {state.name}
                    </button>
                  <% end %>
                </div>
              </details>
            <% end %>
            <%!-- Archive / Delete --%>
            <%= if @on_delete do %>
              <div class="border-t border-base-content/10 my-0.5" />
              <button
                type="button"
                phx-click="archive_task"
                phx-value-task_id={@task.uuid || to_string(@task.id)}
                phx-confirm="Archive this task?"
                onclick="event.stopPropagation();"
                class="w-full flex items-center gap-3 px-3 py-2 rounded-lg text-sm text-base-content hover:bg-base-content/10 transition-colors text-left"
              >
                <.icon name="hero-archive-box-mini" class="w-4 h-4 text-base-content/60 flex-shrink-0" />
                Archive
              </button>
              <button
                type="button"
                phx-click={@on_delete}
                phx-value-task_id={@task.uuid || to_string(@task.id)}
                phx-confirm="Delete this task?"
                onclick="event.stopPropagation();"
                class="w-full flex items-center gap-3 px-3 py-2 rounded-lg text-sm text-error hover:bg-error/10 transition-colors text-left"
              >
                <.icon name="hero-trash-mini" class="w-4 h-4 flex-shrink-0" />
                Delete
              </button>
            <% end %>
          </div>
        </details>
      </div>
    </div>

    <%!-- Tags --%>
    <%= if @task.tags && length(@task.tags) > 0 do %>
      <div class="flex flex-wrap gap-1 mt-2">
        <%= for tag <- Enum.take(@task.tags, 3) do %>
          <span
            class="text-[10px] px-1.5 py-0.5 rounded font-medium leading-none"
            style={"background-color: #{tag.color || "#6B7280"}26; color: #{tag.color || "#6B7280"}"}
          >
            {tag.name}
          </span>
        <% end %>
      </div>
    <% end %>

    <%!-- Footer icon row --%>
    <% checklist = Map.get(@task, :checklist_items, []) %>
    <% notes_count = Map.get(@task, :notes_count, 0) %>
    <% has_footer =
      @task.description || @aging || @task.due_at || checklist != [] || notes_count > 0 ||
        @dm_session || Map.get(@task, :created_at) %>
    <%= if has_footer do %>
      <div class="flex items-center gap-2 mt-2 text-base-content/35 text-[11px]">
        <span class="tabular-nums">{relative_time(@task.created_at)}</span>
        <%= if @task.description do %>
          <.icon name="hero-document-text" class="w-3 h-3 flex-shrink-0" />
        <% end %>
        <%= if @aging do %>
          <span
            class={
              if String.contains?(elem(@aging, 1), "stale"),
                do: "text-error/60",
                else: "text-warning/60"
            }
            title={elem(@aging, 1)}
          >
            <.icon name="hero-clock-mini" class="w-3 h-3 flex-shrink-0" />
          </span>
        <% end %>
        <%= if @task.due_at do %>
          <span class="flex items-center gap-0.5">
            <.icon name="hero-calendar" class="w-3 h-3" />
            <span>{format_due_date(@task.due_at)}</span>
          </span>
        <% end %>
        <%= if checklist != [] do %>
          <% cl_done = Enum.count(checklist, & &1.completed) %>
          <span class="flex items-center gap-0.5">
            <.icon name="hero-check-circle" class="w-3 h-3" />
            <span>{cl_done}/{length(checklist)}</span>
          </span>
        <% end %>
        <%= if notes_count > 0 do %>
          <span class="flex items-center gap-0.5">
            <.icon name="hero-chat-bubble-bottom-center-text" class="w-3 h-3" />
            <span>{notes_count}</span>
          </span>
        <% end %>
        <%= if @dm_session do %>
          <% is_working = @working_session_ids && MapSet.member?(@working_session_ids, @dm_session.id) %>
          <a
            href={"/dm/#{@dm_session.uuid}"}
            target="_blank"
            class="ml-auto flex-shrink-0 text-base-content/30 hover:text-primary transition-colors"
            onclick="event.stopPropagation();"
            title={if is_working, do: "Agent is working", else: "Open agent DM"}
          >
            <span class="relative inline-flex">
              <.icon
                name="hero-user-circle"
                class={"w-3.5 h-3.5 #{if is_working, do: "text-primary", else: ""}"}
              />
              <%= if is_working do %>
                <span class="absolute -top-0.5 -right-0.5 w-1.5 h-1.5 bg-success rounded-full animate-pulse" />
              <% end %>
            </span>
          </a>
        <% end %>
      </div>
    <% end %>
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
      <span class="badge badge-ghost badge-sm text-xs tabular-nums">
        {relative_time(@task.created_at)}
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

  defp card_body_class("kanban"), do: "card-body p-2"
  defp card_body_class("grid"), do: "card-body p-5"
  defp card_body_class(_), do: ""

  # State ID -> text color for inline list rows
  defp state_text_color(@state_todo), do: "text-base-content/55"
  defp state_text_color(@state_in_progress), do: "text-info/80"
  defp state_text_color(@state_in_review), do: "text-warning/80"
  defp state_text_color(@state_done), do: "text-success/80"
  defp state_text_color(_), do: "text-base-content/55"

  defp priority_bar_color(priority) do
    cond do
      priority >= 3 -> "#EF4444"
      priority == 2 -> "#F59E0B"
      priority == 1 -> "#3B82F6"
      true -> "transparent"
    end
  end
end
