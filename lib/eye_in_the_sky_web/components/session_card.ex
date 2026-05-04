defmodule EyeInTheSkyWeb.Components.SessionCard do
  @moduledoc false
  use Phoenix.Component
  import EyeInTheSkyWeb.CoreComponents

  import EyeInTheSkyWeb.Helpers.ViewHelpers,
    only: [relative_time: 1, derive_display_status: 1, truncate_text: 1]

  alias EyeInTheSky.Sessions

  @doc """
  Renders a session list row (used in project sessions view).

  ## Attrs
    * `:session` - Session struct with :agent preloaded
    * `:select_mode` - Whether bulk-select mode is active (all checkboxes forced visible)
    * `:selected` - Whether this row is checked
    * `:indeterminate` - Whether this row's checkbox is in indeterminate state
  ## Slots
    * `:actions` - Action buttons rendered on the right side
  """
  attr :session, :map, required: true
  attr :select_mode, :boolean, default: false
  attr :selected, :boolean, default: false
  attr :indeterminate, :boolean, default: false
  attr :click_event, :string, default: "navigate_dm"
  attr :project_name, :string, default: nil
  attr :editing_session_id, :any, default: nil
  slot :actions

  def session_row(assigns) do
    display_status = derive_display_status(assigns.session)

    %{label: status_label} = session_status_display(display_status)

    assigns =
      assigns
      |> assign(:status_label, status_label)
      |> assign(:status_atom, String.to_existing_atom(display_status))

    ~H"""
    <%!--
      Outer wrapper owns `group/row` so both the animated checkbox and the
      three-dot menu (md:group-hover:opacity-100) respond to the same hover area.
    --%>
    <div
      id={"session-row-#{@session.id}"}
      class={[
        "relative group/row",
        if(@selected, do: "bg-primary/5 ring-1 ring-primary/20 ring-inset rounded-lg", else: "bg-base-100")
      ]}
    >
      <%!--
        Animated checkbox — absolutely positioned, never pushes content.
        No pointer-events-none: keeping events active lets hover on the invisible
        checkbox bubble up to group/row and trigger the reveal from outside the row.
        select_mode: forced visible without transition (avoids reinsert flicker on streams).
      --%>
      <div
        class={[
          "p-1 absolute z-10 top-1/2 -translate-y-1/2 -translate-x-1/2",
          "left-4 sm:left-[-0.875rem]",
          if(@select_mode,
            do: "opacity-100 scale-100",
            else: "opacity-0 scale-75 group-hover/row:opacity-100 group-hover/row:scale-100 transition duration-100"
          )
        ]}
        aria-hidden={to_string(!@select_mode)}
        phx-click="toggle_select"
        phx-value-id={@session.id}
      >
        <.square_checkbox
          id={"session-checkbox-#{@session.id}"}
          checked={@selected}
          indeterminate={@indeterminate}
          checkbox_area={true}
          aria-label={"Select session #{@session.name || @session.id}"}
        />
      </div>

      <%!-- Row content --%>
      <div
        class={[
          "flex items-center gap-4 py-3 pr-2 -mx-2 rounded-lg cursor-pointer relative",
          "[&.vim-nav-focused]:ring-2 [&.vim-nav-focused]:ring-primary/50",
          if(@select_mode, do: "pl-10 sm:pl-2", else: "pl-2")
        ]}
        data-vim-list-item
        data-vim-item-type="session"
        data-vim-item-id={@session.id}
        data-vim-item-title={@session.name || "Unnamed session"}
        data-session-id={@session.id}
        data-session-uuid={@session.uuid}
        phx-click={if @select_mode, do: "toggle_select", else: @click_event}
        phx-value-id={@session.id}
        role="button"
        tabindex="0"
        phx-keyup={if !@select_mode, do: @click_event}
        phx-key="Enter"
        aria-label={"Open session: #{@session.name || "Unnamed session"} - #{@status_label}"}
      >
        <%!-- Status dot — idle variants are silent (no dot) --%>
        <%= if @status_atom in [:idle, :idle_stale, :idle_dead, :completed] do %>
          <span class="size-2 shrink-0" />
        <% else %>
          <.status_dot status={@status_atom} size="sm" />
        <% end %>

        <%!-- Main content --%>
        <div class="flex-1 min-w-0">
          <div class="flex items-baseline gap-2">
            <%= if @editing_session_id == @session.id do %>
              <form
                phx-submit="save_session_name"
                phx-click="noop"
                class="flex-1 min-w-0"
              >
                <%!-- No phx-click-away: it's mouse-only and won't fire on mobile touch.
                     phx-blur on the input fires cancel_rename on all platforms. --%>
                <input type="hidden" name="session_id" value={@session.id} />
                <input
                  type="text"
                  name="name"
                  value={@session.name || ""}
                  class="input input-xs w-full text-[13px] font-medium border-primary/40 focus:border-primary bg-base-100 text-base"
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
                {@session.name ||
                  truncate_text(session_agent_description(@session)) ||
                  "Unnamed session"}
              </span>
            <% end %>
          </div>
          <div class="flex flex-wrap items-center gap-1.5 mt-1 text-mini text-base-content/30">
            <span class="font-mono tabular-nums text-base-content/30 shrink-0">#{@session.id}</span>
            <span class="text-base-content/15">/</span>
            <%= if @session.entrypoint == "cli" do %>
              <.icon name="hero-command-line" class="size-3 text-base-content/40 flex-shrink-0" />
            <% end %>
            <%= if name = agent_display_name(@session) do %>
              <span class="text-base-content/50 truncate min-w-0">{name}</span>
              <span class="text-base-content/15">/</span>
            <% end %>
            <span class="font-mono">{Sessions.format_model_info(@session)}</span>
            <span class="text-base-content/15">/</span>
            <span class="tabular-nums">{relative_time(@session.started_at)}</span>
            <%= if @project_name do %>
              <span class="text-base-content/15">/</span>
              <span class="truncate text-base-content/50">{@project_name}</span>
            <% end %>
            <%= if task_title = @session.current_task_title do %>
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

  # Extracts the agent definition display name from a session, guarding against
  # unloaded associations and nil values.
  defp agent_display_name(session) do
    case Map.get(session, :agent) do
      nil -> nil
      %Ecto.Association.NotLoaded{} -> nil
      agent ->
        case Map.get(agent, :agent_definition) do
          nil -> nil
          %Ecto.Association.NotLoaded{} -> nil
          defn -> Map.get(defn, :display_name)
        end
    end
  end

  defp session_agent_description(session) do
    case Map.get(session, :agent) do
      nil -> nil
      %Ecto.Association.NotLoaded{} -> nil
      agent -> Map.get(agent, :description)
    end
  end

  defp session_status_display(status) do
    case status do
      "working" ->
        %{label: "Working", border: "border-success", class: "text-success"}

      "waiting" ->
        %{label: "Waiting", border: "border-warning", class: "text-warning"}

      "compacting" ->
        %{label: "Compacting", border: "border-orange-500", class: "text-orange-500"}

      "idle" ->
        %{label: "Idle", border: "border-transparent", class: "text-base-content/50"}

      "completed" ->
        %{label: "Done", border: "border-transparent", class: "text-base-content/50"}

      _ ->
        %{label: "Idle", border: "border-transparent", class: "text-base-content/55"}
    end
  end
end
