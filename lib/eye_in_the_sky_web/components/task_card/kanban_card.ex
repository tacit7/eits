defmodule EyeInTheSkyWeb.Components.TaskCard.KanbanCard do
  @moduledoc """
  Kanban card content components: card body, context menu, and footer.
  """

  use Phoenix.Component
  import EyeInTheSkyWeb.CoreComponents

  import EyeInTheSkyWeb.Helpers.ViewHelpers,
    only: [format_due_date: 1, card_aging_indicator: 1, relative_time: 1]

  attr :task, :map, required: true
  attr :on_click, :string, default: nil
  attr :on_delete, :string, default: nil
  attr :working_session_ids, :any, default: nil
  attr :waiting_session_ids, :any, default: nil
  attr :workflow_states, :list, default: []
  attr :rest, :global

  def kanban_card(assigns) do
    aging = card_aging_indicator(Map.get(assigns.task, :updated_at))
    task_id = assigns.task.uuid || to_string(assigns.task.id)

    assigns =
      assigns
      |> assign(:aging, aging)
      |> assign(:task_id, task_id)

    ~H"""
    <div
      class={[
        "group/card card bg-base-200 hover:bg-base-300 border border-base-content/8 transition-all cursor-pointer",
        @aging && elem(@aging, 0)
      ]}
      {@rest}
    >
      <%= if Map.get(@task, :priority, 0) > 0 do %>
        <div
          class="h-0.5 w-full rounded-t"
          style={"background-color: #{priority_bar_color(Map.get(@task, :priority))}"}
        />
      <% end %>
      <div class="card-body p-2">
        <.kanban_card_content
          task={@task}
          task_id={@task_id}
          on_click={@on_click}
          on_delete={@on_delete}
          aging={@aging}
          working_session_ids={@working_session_ids}
          waiting_session_ids={@waiting_session_ids}
          workflow_states={@workflow_states}
        />
      </div>
    </div>
    """
  end

  defp kanban_card_content(assigns) do
    dm_session = resolve_dm_session(assigns.task)

    assigns =
      assigns
      |> assign(:dm_session, dm_session)
      |> assign_new(:workflow_states, fn -> [] end)
      |> assign_new(:waiting_session_ids, fn -> nil end)

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
        phx-value-task_id={@task_id}
        aria-label={if @task.completed_at, do: "Mark task incomplete", else: "Mark task complete"}
        aria-pressed={to_string(not is_nil(@task.completed_at))}
        class="flex-shrink-0 mt-0.5 flex items-center justify-center min-w-[44px] min-h-[44px] rounded text-base-content/30 hover:text-success transition-colors"
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
        phx-value-task_id={@task_id}
      >
        {@task.title}
      </h4>
      <.kanban_context_menu
        task={@task}
        task_id={@task_id}
        on_click={@on_click}
        on_delete={@on_delete}
        workflow_states={@workflow_states}
      />
    </div>

    <%!-- Tags --%>
    <%= if not is_nil(@task.tags) && @task.tags != [] do %>
      <div class="flex flex-wrap gap-1 mt-2">
        <%= for tag <- Enum.take(@task.tags, 3) do %>
          <span
            class="text-xs px-1.5 py-0.5 rounded font-medium leading-none"
            style={"background-color: #{tag.color || "hsl(var(--bc) / 0.3)"}26; color: #{tag.color || "hsl(var(--bc) / 0.3)"}"}
          >
            {tag.name}
          </span>
        <% end %>
      </div>
    <% end %>

    <.kanban_card_footer
      task={@task}
      aging={@aging}
      dm_session={@dm_session}
      working_session_ids={@working_session_ids}
      waiting_session_ids={@waiting_session_ids}
    />
    """
  end

  defp kanban_context_menu(assigns) do
    ~H"""
    <div class="flex-shrink-0 md:opacity-0 md:group-hover/card:opacity-100 transition-opacity">
      <details class="dropdown dropdown-end">
        <summary class="flex items-center justify-center min-w-[44px] min-h-[44px] -mx-2.5 rounded text-base-content/25 hover:text-base-content/60 hover:bg-base-content/8 cursor-pointer list-none transition-colors">
          <.icon name="hero-ellipsis-horizontal-mini" class="w-3.5 h-3.5" />
        </summary>
        <div class="dropdown-content z-50 mt-1 w-48 rounded-xl bg-base-300 shadow-xl p-1.5 flex flex-col gap-0.5">
          <%!-- Open card --%>
          <button
            type="button"
            phx-click={@on_click}
            phx-value-task_id={@task_id}
            class="w-full flex items-center gap-3 px-3 py-3 rounded-lg text-sm text-base-content hover:bg-base-content/10 transition-colors text-left"
          >
            <.icon
              name="hero-rectangle-stack-mini"
              class="w-4 h-4 text-base-content/60 flex-shrink-0"
            /> Open card
          </button>
          <%!-- Edit labels --%>
          <button
            type="button"
            phx-click="open_task_detail"
            phx-value-task_id={@task_id}
            phx-value-focus="tags"
            class="w-full flex items-center gap-3 px-3 py-3 rounded-lg text-sm text-base-content hover:bg-base-content/10 transition-colors text-left"
          >
            <.icon name="hero-tag-mini" class="w-4 h-4 text-base-content/60 flex-shrink-0" />
            Edit labels
          </button>
          <%!-- Edit dates --%>
          <button
            type="button"
            phx-click="open_date_picker"
            phx-value-task_id={@task_id}
            class="w-full flex items-center gap-3 px-3 py-3 rounded-lg text-sm text-base-content hover:bg-base-content/10 transition-colors text-left"
          >
            <.icon name="hero-clock-mini" class="w-4 h-4 text-base-content/60 flex-shrink-0" />
            Edit dates
          </button>
          <%!-- Copy link --%>
          <button
            type="button"
            phx-hook="CopyToClipboard"
            id={"copy-task-kanban-#{@task.id}"}
            data-copy={@task_id}
            onclick="event.preventDefault();"
            class="w-full flex items-center gap-3 px-3 py-3 rounded-lg text-sm text-base-content hover:bg-base-content/10 transition-colors text-left"
          >
            <.icon name="hero-link-mini" class="w-4 h-4 text-base-content/60 flex-shrink-0" />
            Copy link
          </button>
          <%!-- Move submenu --%>
          <%= if @workflow_states != [] do %>
            <div class="border-t border-base-content/10 my-0.5" />
            <details class="group/move">
              <summary class="w-full flex items-center gap-3 px-3 py-3 rounded-lg text-sm text-base-content hover:bg-base-content/10 transition-colors cursor-pointer list-none">
                <.icon
                  name="hero-arrow-right-mini"
                  class="w-4 h-4 text-base-content/60 flex-shrink-0"
                />
                <span class="flex-1">Move</span>
                <.icon name="hero-chevron-right-mini" class="w-3 h-3 text-base-content/40" />
              </summary>
              <div class="mt-0.5 ml-3 flex flex-col gap-0.5">
                <%= for state <- @workflow_states do %>
                  <button
                    type="button"
                    phx-click="move_task"
                    phx-value-task_id={@task_id}
                    phx-value-state_id={state.id}
                    class="w-full flex items-center gap-2 px-3 py-3 rounded-lg text-sm text-base-content/80 hover:bg-base-content/10 transition-colors text-left"
                  >
                    <span
                      class="w-2 h-2 rounded-full flex-shrink-0"
                      style={"background-color: #{state.color || "hsl(var(--bc) / 0.3)"}"}
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
              phx-value-task_id={@task_id}
              phx-confirm="Archive this task?"
              class="w-full flex items-center gap-3 px-3 py-3 rounded-lg text-sm text-base-content hover:bg-base-content/10 transition-colors text-left"
            >
              <.icon name="hero-archive-box-mini" class="w-4 h-4 text-base-content/60 flex-shrink-0" />
              Archive
            </button>
            <button
              type="button"
              phx-click={@on_delete}
              phx-value-task_id={@task_id}
              phx-confirm="Delete this task?"
              class="w-full flex items-center gap-3 px-3 py-3 rounded-lg text-sm text-error hover:bg-error/10 transition-colors text-left"
            >
              <.icon name="hero-trash-mini" class="w-4 h-4 flex-shrink-0" /> Delete
            </button>
          <% end %>
        </div>
      </details>
    </div>
    """
  end

  defp kanban_card_footer(assigns) do
    checklist = Map.get(assigns.task, :checklist_items, [])
    notes_count = Map.get(assigns.task, :notes_count, 0)

    has_footer =
      not is_nil(assigns.task.description) || not is_nil(assigns.aging) ||
        not is_nil(assigns.task.due_at) || checklist != [] ||
        notes_count > 0 || not is_nil(assigns.dm_session) ||
        not is_nil(Map.get(assigns.task, :created_at))

    assigns =
      assigns
      |> assign(:checklist, checklist)
      |> assign(:notes_count, notes_count)
      |> assign(:has_footer, has_footer)
      |> assign_new(:waiting_session_ids, fn -> nil end)

    ~H"""
    <%= if @has_footer do %>
      <div class="flex items-center gap-2 mt-2 text-base-content/35 text-[11px]">
        <%= if @task.created_at do %>
          <span class="tabular-nums">{relative_time(@task.created_at)}</span>
        <% end %>
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
        <%= if @checklist != [] do %>
          <% cl_done = Enum.count(@checklist, & &1.completed) %>
          <span class="flex items-center gap-0.5">
            <.icon name="hero-check-circle" class="w-3 h-3" />
            <span>{cl_done}/{length(@checklist)}</span>
          </span>
        <% end %>
        <%= if @notes_count > 0 do %>
          <span class="flex items-center gap-0.5">
            <.icon name="hero-chat-bubble-bottom-center-text" class="w-3 h-3" />
            <span>{@notes_count}</span>
          </span>
        <% end %>
        <%= if @dm_session do %>
          <% is_working =
            not is_nil(@working_session_ids) && MapSet.member?(@working_session_ids, @dm_session.id) %>
          <% is_waiting =
            not is_working && not is_nil(@waiting_session_ids) &&
              MapSet.member?(@waiting_session_ids, @dm_session.id) %>
          <a
            href={"/dm/#{@dm_session.uuid}"}
            target="_blank"
            class="ml-auto flex-shrink-0 text-base-content/30 hover:text-primary transition-colors"
            onclick="event.stopPropagation();"
            title={
              cond do
                is_working -> "Agent is working"
                is_waiting -> "Agent is waiting"
                true -> "Open agent DM"
              end
            }
          >
            <span class="relative inline-flex">
              <.icon
                name="hero-user-circle"
                class={"w-3.5 h-3.5 #{cond do
                  is_working -> "text-primary"
                  is_waiting -> "text-warning"
                  true -> ""
                end}"}
              />
              <%= if is_working do %>
                <span class="absolute -top-0.5 -right-0.5 w-1.5 h-1.5 bg-success rounded-full animate-pulse" />
              <% end %>
              <%= if is_waiting do %>
                <span class="absolute -top-0.5 -right-0.5 w-1.5 h-1.5 bg-warning rounded-full animate-pulse" />
              <% end %>
            </span>
          </a>
        <% end %>
      </div>
    <% end %>
    """
  end

  defp priority_bar_color(priority) do
    cond do
      priority >= 3 -> "hsl(var(--er))"
      priority == 2 -> "hsl(var(--wa))"
      priority == 1 -> "hsl(var(--in))"
      true -> "transparent"
    end
  end

  defp resolve_dm_session(%{sessions: [s | _]}), do: s
  defp resolve_dm_session(_), do: nil
end
