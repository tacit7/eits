defmodule EyeInTheSkyWebWeb.Components.SessionCard do
  use Phoenix.Component
  import EyeInTheSkyWebWeb.CoreComponents
  import EyeInTheSkyWebWeb.Helpers.ViewHelpers, only: [relative_time: 1, derive_display_status: 1]

  alias EyeInTheSkyWeb.Sessions

  @doc """
  Renders a session list row (used in project sessions view).

  ## Attrs
    * `:session` - Session struct with :agent preloaded
    * `:select_mode` - Show checkbox instead of status dot (archive mode)
    * `:selected` - Whether this row is checked
  ## Slots
    * `:actions` - Action buttons rendered on the right side
  """
  attr :session, :map, required: true
  attr :select_mode, :boolean, default: false
  attr :selected, :boolean, default: false
  attr :click_event, :string, default: "navigate_dm"
  attr :project_name, :string, default: nil
  attr :editing_session_id, :any, default: nil
  slot :actions

  def session_row(assigns) do
    display_status = derive_display_status(assigns.session)

    {status_label, status_border} =
      case display_status do
        "working" -> {"Working", "border-success"}
        "compacting" -> {"Compacting", "border-warning"}
        "idle" -> {"Idle", "border-transparent"}
        "idle_stale" -> {"Idle", "border-transparent"}
        "idle_dead" -> {"Idle", "border-transparent"}
        "completed" -> {"Done", "border-transparent"}
        _ -> {"Idle", "border-transparent"}
      end

    assigns =
      assigns
      |> assign(:status_label, status_label)
      |> assign(:status_border, status_border)

    ~H"""
    <div
      id={"swipe-row-#{@session.id}"}
      class="relative overflow-hidden bg-[oklch(97%_0.005_80)] dark:bg-[hsl(60,2.1%,18.4%)]"
      phx-hook="SwipeRow"
    >
      <%!-- Action panel (mobile only, sits behind the row, revealed by swipe) --%>
      <div class="md:hidden absolute right-0 top-0 bottom-0 flex items-stretch" aria-hidden="true">
        <%!-- Fav --%>
        <button
          type="button"
          id={"swipe-fav-#{@session.id}"}
          phx-hook="BookmarkAgent"
          phx-update="ignore"
          data-agent-id={@session.agent && @session.agent.uuid}
          data-session-id={@session.uuid}
          data-agent-name={@session.name || (@session.agent && @session.agent.description) || "Agent"}
          data-agent-status={@session.status}
          class="bookmark-button w-[53px] flex flex-col items-center justify-center gap-1 bg-[#f43f5e] text-white text-[9px] font-bold uppercase tracking-wide border-none"
          aria-label="Bookmark session"
        >
          <.icon name="hero-heart" class="w-5 h-5" />
          Fav
        </button>
        <%!-- Rename --%>
        <button
          type="button"
          phx-click="rename_session"
          phx-value-session_id={@session.id}
          class="w-[53px] flex flex-col items-center justify-center gap-1 bg-[#6366f1] text-white text-[9px] font-bold uppercase tracking-wide border-none"
          aria-label="Rename session"
        >
          <.icon name="hero-pencil-square" class="w-5 h-5" />
          Rename
        </button>
        <%!-- Archive --%>
        <button
          type="button"
          phx-click="archive_session"
          phx-value-session_id={@session.id}
          class="w-[53px] flex flex-col items-center justify-center gap-1 bg-[#f59e0b] text-white text-[9px] font-bold uppercase tracking-wide border-none"
          aria-label="Archive session"
        >
          <.icon name="hero-archive-box" class="w-5 h-5" />
          Archive
        </button>
      </div>

      <%!-- Row content (slides left on swipe) --%>
      <div
        data-swipe-row
        class={"group flex items-center gap-4 py-3 px-2 -mx-2 rounded-lg cursor-pointer border-l-2 bg-inherit relative z-[1] will-change-transform " <> @status_border}
        phx-click={if !@select_mode, do: @click_event}
        phx-value-id={@session.id}
        role="button"
        tabindex="0"
        phx-keyup={@click_event}
        phx-key="Enter"
        aria-label={"Open session: #{@session.name || "Unnamed session"} - #{@status_label}"}
      >
        <%!-- Select checkbox (archive mode only) --%>
        <%= if @select_mode do %>
          <div class="flex-shrink-0 w-6 flex justify-center">
            <input
              type="checkbox"
              checked={@selected}
              phx-click="toggle_select"
              phx-value-id={@session.id}
              class="checkbox checkbox-xs checkbox-primary"
              aria-label={"Select session #{@session.name || @session.id}"}
            />
          </div>
        <% end %>

        <%!-- Main content --%>
        <div class="flex-1 min-w-0">
          <div class="flex items-baseline gap-2">
            <%= if @editing_session_id == @session.id do %>
              <form
                phx-submit="save_session_name"
                class="flex-1 min-w-0"
              >
                <%!-- No phx-click-away: it's mouse-only and won't fire on mobile touch.
                     phx-blur on the input fires cancel_rename on all platforms. --%>
                <input type="hidden" name="session_id" value={@session.id} />
                <input
                  type="text"
                  name="name"
                  value={@session.name || ""}
                  class="input input-xs w-full text-[13px] font-medium border-primary/40 focus:border-primary bg-base-100"
                  phx-keyup="cancel_rename"
                  phx-key="Escape"
                  phx-blur="cancel_rename"
                  autofocus
                  maxlength="120"
                  aria-label="Edit session name"
                />
              </form>
            <% else %>
              <span class="text-[13px] font-medium text-base-content/85 truncate">
                {@session.name || "Unnamed session"}
              </span>
            <% end %>
          </div>
          <div class="flex items-center gap-1.5 mt-1 text-[11px] text-base-content/30">
            <span class="font-mono">{Sessions.format_model_info(@session)}</span>
            <span class="text-base-content/15">/</span>
            <span class="tabular-nums">{relative_time(@session.started_at)}</span>
            <%= if @project_name do %>
              <span class="text-base-content/15">/</span>
              <span class="truncate text-base-content/50">{@project_name}</span>
            <% end %>
            <%= if task_title = Map.get(@session, :current_task_title) do %>
              <span class="text-base-content/15">/</span>
              <span class="truncate text-primary/60 font-medium">{task_title}</span>
            <% end %>
          </div>
        </div>

        <%!-- Actions slot --%>
        <%= if @actions != [] do %>
          <div class="flex items-center gap-0 flex-shrink-0" phx-click="noop">
            {render_slot(@actions)}
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
