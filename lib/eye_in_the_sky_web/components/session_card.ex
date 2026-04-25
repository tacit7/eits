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
    * `:select_mode` - Whether bulk-select mode is active (checkboxes always visible)
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

    %{label: status_label, border: status_border, class: status_class} =
      session_status_display(display_status)

    assigns =
      assigns
      |> assign(:status_label, status_label)
      |> assign(:status_border, status_border)
      |> assign(:status_class, status_class)

    ~H"""
    <div
      id={"session-row-#{@session.id}"}
      class={[
        "relative border-l-2 pl-2",
        if(@selected, do: "bg-primary/5 ring-1 ring-primary/20 ring-inset rounded-lg", else: "bg-base-100"),
        @status_border
      ]}
    >
      <%!-- Row content --%>
      <div
        class="group flex items-center gap-4 py-3 px-2 -mx-2 rounded-lg cursor-pointer relative"
        phx-click={if @select_mode, do: "toggle_select", else: @click_event}
        phx-value-id={@session.id}
        role="button"
        tabindex="0"
        phx-keyup={if !@select_mode, do: @click_event}
        phx-key="Enter"
        aria-label={"Open session: #{@session.name || "Unnamed session"} - #{@status_label}"}
      >
        <%!-- Select checkbox — hidden until hover, always visible in select mode --%>
        <div class={[
          "flex-shrink-0 w-6 flex justify-center",
          if(@select_mode, do: "", else: "hidden group-hover:flex")
        ]}>
          <input
            type="checkbox"
            checked={@selected}
            phx-click="toggle_select"
            phx-value-id={@session.id}
            class="checkbox checkbox-xs checkbox-primary"
            aria-label={"Select session #{@session.name || @session.id}"}
          />
        </div>

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
          <div class="flex flex-wrap items-center gap-1.5 mt-1 text-[11px] text-base-content/30">
            <span class="font-mono tabular-nums text-base-content/30 shrink-0">#{@session.id}</span>
            <span class="text-base-content/15">/</span>
            <%= if @session.entrypoint == "cli" do %>
              <.icon name="hero-command-line" class="w-3 h-3 text-base-content/40 flex-shrink-0" />
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
    with agent when not is_nil(agent) <- Map.get(session, :agent),
         false <- match?(%Ecto.Association.NotLoaded{}, agent),
         defn when is_map(defn) <- Map.get(agent, :agent_definition),
         false <- match?(%Ecto.Association.NotLoaded{}, defn),
         name when not is_nil(name) <- Map.get(defn, :display_name) do
      name
    else
      _ -> nil
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
