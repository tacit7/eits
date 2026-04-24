defmodule EyeInTheSkyWeb.AgentLive.Index do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSkyWeb.AgentLive.CanvasHandlers
  alias EyeInTheSkyWeb.AgentLive.IndexActions
  alias EyeInTheSkyWeb.Live.Shared.AgentStatusHelpers
  alias EyeInTheSkyWeb.Live.Shared.NotificationHelpers
  import EyeInTheSkyWeb.Helpers.PubSubHelpers
  import EyeInTheSkyWeb.Components.SessionCard
  import EyeInTheSkyWeb.Components.AgentList

  require Logger

  @default_refresh_ms 300_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      subscribe_agents()
      subscribe_agent_working()
    end

    socket =
      socket
      |> assign(:page_title, "Eye in the Sky - Agents")
      |> assign(:search_query, "")
      |> assign(:sort_by, "recent")
      |> assign(:session_filter, "all")
      |> assign(:agents, [])
      |> assign(:show_new_session_drawer, false)
      |> assign(:projects, [])
      |> assign(:timer_ref, nil)
      |> assign(:sidebar_tab, :sessions)
      |> assign(:sidebar_project, nil)
      |> assign(:top_bar_cta, %{label: "New Session", event: "toggle_new_session_drawer"})
      |> assign(:selected_ids, MapSet.new())
      |> assign(:select_mode, false)
      |> assign(:show_delete_confirm, false)
      |> assign(:editing_session_id, nil)
      |> assign(:canvases, [])
      |> assign(:show_new_canvas_for, nil)

    socket =
      if connected?(socket) do
        socket
        |> assign(:projects, EyeInTheSky.Projects.list_projects())
        |> assign(:canvases, EyeInTheSky.Canvases.list_canvases())
        |> IndexActions.load_agents()
        |> schedule_refresh()
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_event("send_direct_message", params, socket),
    do: IndexActions.handle_send_direct_message(params, socket)

  @impl true
  def handle_event("search", params, socket),
    do: IndexActions.handle_search(params, socket)

  @impl true
  def handle_event("filter_session", params, socket),
    do: IndexActions.handle_filter_session(params, socket)

  @impl true
  def handle_event("sort", params, socket),
    do: IndexActions.handle_sort(params, socket)

  @impl true
  def handle_event(action, params, socket)
      when action in ["archive_session", "unarchive_session", "delete_session"],
      do: IndexActions.handle_session_action(action, params, socket)

  @impl true
  def handle_event("toggle_select", params, socket),
    do: IndexActions.handle_toggle_select(params, socket)

  @impl true
  def handle_event("toggle_select_all", params, socket),
    do: IndexActions.handle_toggle_select_all(params, socket)

  @impl true
  def handle_event("confirm_delete_selected", params, socket),
    do: IndexActions.handle_confirm_delete_selected(params, socket)

  @impl true
  def handle_event("cancel_delete_selected", params, socket),
    do: IndexActions.handle_cancel_delete_selected(params, socket)

  @impl true
  def handle_event("delete_selected", params, socket),
    do: IndexActions.handle_delete_selected(params, socket)

  @impl true
  def handle_event("exit_select_mode", params, socket),
    do: IndexActions.handle_exit_select_mode(params, socket)

  @impl true
  def handle_event("enter_select_mode", params, socket),
    do: IndexActions.handle_enter_select_mode(params, socket)

  @impl true
  def handle_event("navigate_dm", params, socket),
    do: IndexActions.handle_navigate_dm(params, socket)

  @impl true
  def handle_event("rename_session", params, socket),
    do: IndexActions.handle_rename_session(params, socket)

  @impl true
  def handle_event("save_session_name", params, socket),
    do: IndexActions.handle_save_session_name(params, socket)

  @impl true
  def handle_event("cancel_rename", params, socket),
    do: IndexActions.handle_cancel_rename(params, socket)

  @impl true
  def handle_event("toggle_new_session_drawer", params, socket),
    do: IndexActions.handle_toggle_new_session_drawer(params, socket)

  @impl true
  def handle_event("create_new_session", params, socket),
    do: IndexActions.handle_create_new_session(params, socket)

  @impl true
  def handle_event("set_notify_on_stop", params, socket),
    do: {:noreply, NotificationHelpers.set_notify_on_stop(socket, params)}

  @impl true
  def handle_event("noop", params, socket),
    do: IndexActions.handle_noop(params, socket)

  @impl true
  def handle_event("show_new_canvas_form", params, socket),
    do: CanvasHandlers.handle_event("show_new_canvas_form", params, socket)

  @impl true
  def handle_event("add_to_canvas", params, socket),
    do: CanvasHandlers.handle_event("add_to_canvas", params, socket)

  @impl true
  def handle_event("add_to_new_canvas", params, socket),
    do: CanvasHandlers.handle_event("add_to_new_canvas", params, socket)

  @impl true
  def handle_info(:refresh_agents, socket) do
    socket = socket |> IndexActions.load_agents() |> schedule_refresh()
    {:noreply, socket}
  end

  @impl true
  def handle_info({event, _agent}, socket)
      when event in [:agent_created, :agent_updated, :agent_deleted] do
    {:noreply, IndexActions.load_agents(socket)}
  end

  @impl true
  def handle_info({:agent_working, msg}, socket) do
    AgentStatusHelpers.handle_agent_working(socket, msg, fn socket, session_id ->
      update_agent_status_in_list(socket, session_id, "working")
    end)
  end

  @impl true
  def handle_info({:agent_stopped, msg}, socket) do
    AgentStatusHelpers.handle_agent_stopped(socket, msg, fn socket, session_id ->
      status = extract_stopped_status(msg)
      update_agent_status_in_list(socket, session_id, status)
    end)
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp extract_stopped_status(%{status: status}) when is_binary(status) and status != "",
    do: status

  defp extract_stopped_status(%{status: _}), do: "completed"
  defp extract_stopped_status(_), do: "idle"

  defp apply_action(socket, :index, %{"new" => "1"}) do
    socket
    |> assign(:page_title, "Agents")
    |> assign(:show_new_session_drawer, true)
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, :page_title, "Agents")
  end

  defp schedule_refresh(socket) do
    socket = cancel_timer(socket)
    ref = Process.send_after(self(), :refresh_agents, @default_refresh_ms)
    assign(socket, :timer_ref, ref)
  end

  defp cancel_timer(%{assigns: %{timer_ref: ref}} = socket) when is_reference(ref) do
    Process.cancel_timer(ref)
    assign(socket, :timer_ref, nil)
  end

  defp cancel_timer(socket), do: socket

  defp update_agent_status_in_list(socket, session_id, new_status) do
    now = DateTime.utc_now()

    updated_agents =
      socket.assigns.agents
      |> Enum.map(&AgentStatusHelpers.apply_agent_status(&1, session_id, new_status, now))
      |> EyeInTheSkyWeb.Helpers.SessionFilters.sort_agents(socket.assigns.sort_by)

    assign(socket, :agents, updated_agents)
  end

  # -- Render ---------------------------------------------------------------

  # This LiveView is large by necessity: it owns the full agents list page with
  # filtering, search, bulk selection, per-row context menus, canvas management,
  # inline rename, and a new-agent drawer. The render function is broken into
  # defp components (search_bar, bulk_action_bar, agent_row_menu,
  # delete_confirm_modal) to keep each section navigable.

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-base-100 min-h-full px-4 sm:px-6 lg:px-8">
      <div class="max-w-3xl mx-auto">
        <div class="flex items-center justify-between py-5">
          <span class="text-[11px] font-mono tabular-nums text-base-content/30 tracking-wider uppercase">
            {length(@agents)} agents
          </span>
          <div class="flex items-center gap-2">
            <label
              :if={!@select_mode && @agents != []}
              class="flex items-center gap-1.5 cursor-pointer text-xs text-base-content/40 hover:text-base-content/70 min-h-[44px] sm:min-h-0 px-1 transition-colors"
              phx-click="enter_select_mode"
            >
              <input type="checkbox" class="checkbox checkbox-xs checkbox-primary pointer-events-none" />
              Select
            </label>
            <button
              phx-click="toggle_new_session_drawer"
              class="btn btn-sm btn-primary gap-1.5 min-h-0 h-11 sm:h-7 text-xs"
            >
              <.icon name="hero-plus-mini" class="w-3.5 h-3.5" /> New Agent
            </button>
            <label class="swap swap-rotate btn btn-ghost btn-xs btn-circle min-h-[44px] min-w-[44px]">
              <input type="checkbox" class="theme-controller" value="dark" />
              <.icon name="hero-sun" class="swap-on w-4 h-4" />
              <.icon name="hero-moon" class="swap-off w-4 h-4" />
            </label>
          </div>
        </div>

        <.bulk_action_bar
          session_filter={@session_filter}
          select_mode={@select_mode}
          agents={@agents}
          selected_ids={@selected_ids}
        />

        <div class="mt-2 divide-y divide-base-content/5 bg-base-100 rounded-xl shadow-sm px-4">
          <%= if @agents == [] do %>
            <.empty_state
              id="agents-empty"
              title="No agents found"
              subtitle="Try adjusting your search or filters"
            />
          <% else %>
            <div :for={agent <- @agents}>
              <.session_row
                session={agent}
                select_mode={@select_mode}
                selected={MapSet.member?(@selected_ids, to_string(agent.id))}
                project_name={agent.project_name}
                editing_session_id={@editing_session_id}
              >
                <:actions>
                  <.agent_row_menu
                    agent={agent}
                    canvases={@canvases}
                    show_new_canvas_for={@show_new_canvas_for}
                  />
                </:actions>
              </.session_row>
            </div>
          <% end %>
        </div>
      </div>
    </div>

    <.delete_confirm_modal show_delete_confirm={@show_delete_confirm} selected_ids={@selected_ids} />

    <.live_component
      module={EyeInTheSkyWeb.Components.NewSessionModal}
      id="new-session-modal"
      show={@show_new_session_drawer}
      projects={@projects}
      current_project={nil}
      toggle_event="toggle_new_session_drawer"
      submit_event="create_new_session"
    />
    """
  end
end
