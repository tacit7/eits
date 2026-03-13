defmodule EyeInTheSkyWebWeb.Components.SessionCard do
  use Phoenix.Component
  import EyeInTheSkyWebWeb.CoreComponents, only: [icon: 1]
  import EyeInTheSkyWebWeb.Helpers.ViewHelpers, only: [relative_time: 1, derive_display_status: 1]

  alias EyeInTheSkyWeb.Sessions

  @doc """
  Renders a session card (grid layout) with status pulse, name, and timestamp.

  ## Attrs
    * `:session` - Map from list_session_overview_rows with session_id, session_name, started_at, etc.
    * `:show_project` - Whether to show project name (default: true)
  """
  attr :session, :map, required: true
  attr :show_project, :boolean, default: true

  def session_card(assigns) do
    status = session_status(assigns.session)
    assigns = assign(assigns, :status, status)

    ~H"""
    <.link
      navigate={"/dm/#{@session.session_id}"}
      class="group relative block rounded-xl bg-base-100 border border-base-content/6 hover:border-primary/30 transition-all duration-300 overflow-hidden"
      aria-label={"#{@session.session_name || "Unnamed session"} - #{to_string(@status)}"}
    >
      <%!-- Subtle top accent line --%>
      <div class={[
        "absolute top-0 left-0 right-0 h-[2px] transition-all duration-300",
        case @status do
          :working ->
            "bg-gradient-to-r from-success/60 via-success to-success/60"

          :compacting ->
            "bg-gradient-to-r from-warning/60 via-warning to-warning/60"

          _ ->
            "bg-gradient-to-r from-transparent via-base-content/6 to-transparent group-hover:via-primary/20"
        end
      ]} />

      <div class="p-4 pt-5 space-y-3">
        <%!-- Top row: status badge + time --%>
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2">
            <%= case @status do %>
              <% :working -> %>
                <span class="relative flex h-2 w-2">
                  <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-success opacity-60">
                  </span>
                  <span class="relative inline-flex rounded-full h-2 w-2 bg-success"></span>
                </span>
                <span class="text-[11px] font-semibold tracking-wide uppercase text-success/80">
                  Working
                </span>
              <% :compacting -> %>
                <span class="relative flex h-2 w-2">
                  <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-warning opacity-60">
                  </span>
                  <span class="relative inline-flex rounded-full h-2 w-2 bg-warning"></span>
                </span>
                <span class="text-[11px] font-semibold tracking-wide uppercase text-warning/80">
                  Compacting
                </span>
              <% :idle -> %>
                <span class="inline-flex rounded-full h-2 w-2 bg-base-content/25"></span>
                <span class="text-[11px] tracking-wide uppercase text-base-content/55">Idle</span>
              <% _ -> %>
                <span class="inline-flex rounded-full h-2 w-2 bg-base-content/20"></span>
                <span class="text-[11px] tracking-wide uppercase text-base-content/50">Ended</span>
            <% end %>
          </div>
          <span class="text-[11px] tabular-nums text-base-content/50">
            {relative_time(@session.started_at)}
          </span>
        </div>

        <%!-- Session name --%>
        <p class="text-[13px] font-semibold text-base-content/90 line-clamp-1 group-hover:text-primary transition-colors duration-200">
          {@session.session_name || "Unnamed session"}
        </p>
      </div>
    </.link>
    """
  end

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
        "idle" -> {"text-base-content/25", "bg-base-content/20", "Idle", false}
        "idle_stale" -> {"text-warning", "bg-warning", "Idle", false}
        "idle_dead" -> {"text-error", "bg-error", "Idle", false}
        "completed" -> {"text-base-content/25", "bg-base-content/20", "Done", false}
        _ -> {"text-base-content/25", "bg-base-content/20", "Idle", false}
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
            <span class="truncate text-base-content/45">{@project_name}</span>
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

  defp session_status(%{ended_at: ended_at}) when is_binary(ended_at) and ended_at != "",
    do: :ended

  defp session_status(%{status: "working"}), do: :working
  defp session_status(%{status: "compacting"}), do: :compacting
  defp session_status(%{status: "idle"}), do: :idle
  defp session_status(_), do: :ended
end
