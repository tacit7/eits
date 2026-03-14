defmodule EyeInTheSkyWebWeb.Components.SessionCard do
  use Phoenix.Component
  import EyeInTheSkyWebWeb.CoreComponents, only: [icon: 1]
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
  slot :actions

  def session_row(assigns) do
    display_status = derive_display_status(assigns.session)

    {status_color, status_bg, status_label, is_active} =
      case display_status do
        "working" -> {"text-success", "bg-success", "Working", true}
        "compacting" -> {"text-warning", "bg-warning", "Compacting", true}
        "idle" -> {"text-base-content/55", "bg-base-content/20", "Idle", false}
        "idle_stale" -> {"text-warning", "bg-warning", "Idle", false}
        "idle_dead" -> {"text-error", "bg-error", "Idle", false}
        "completed" -> {"text-base-content/50", "bg-base-content/20", "Done", false}
        _ -> {"text-base-content/55", "bg-base-content/20", "Idle", false}
      end

    assigns =
      assigns
      |> assign(:status_color, status_color)
      |> assign(:status_bg, status_bg)
      |> assign(:status_label, status_label)
      |> assign(:is_active, is_active)

    ~H"""
    <div
      class="group flex items-center gap-4 py-3 px-2 -mx-2 rounded-lg cursor-pointer"
      phx-click={@click_event}
      phx-value-id={@session.id}
      role="button"
      tabindex="0"
      phx-keyup={@click_event}
      phx-key="Enter"
      aria-label={"Open session: #{@session.name || "Unnamed session"} - #{@status_label}"}
    >
      <%!-- Status indicator or checkbox --%>
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
      <% else %>
        <div class="flex-shrink-0 w-6 flex justify-center" title={@status_label}>
          <%= if @is_active do %>
            <span class="relative flex h-2 w-2">
              <span class={"animate-ping absolute inline-flex h-full w-full rounded-full opacity-50 " <> @status_bg}>
              </span>
              <span class={"relative inline-flex rounded-full h-2 w-2 " <> @status_bg}></span>
            </span>
          <% else %>
            <span class={"inline-flex rounded-full h-2 w-2 " <> @status_bg}></span>
          <% end %>
        </div>
      <% end %>

      <%!-- Main content --%>
      <div class="flex-1 min-w-0">
        <div class="flex items-baseline gap-2">
          <span class="text-[13px] font-medium text-base-content/85 truncate">
            {@session.name || "Unnamed session"}
          </span>
          <span class={"text-[11px] font-medium uppercase tracking-wider flex-shrink-0 " <> @status_color}>
            {@status_label}
          </span>
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

      <%!-- Chevron --%>
      <div class="flex-shrink-0">
        <.icon name="hero-chevron-right-mini" class="w-4 h-4 text-base-content/20" />
      </div>
    </div>
    """
  end
end
