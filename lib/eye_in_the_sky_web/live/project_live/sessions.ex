defmodule EyeInTheSkyWeb.ProjectLive.Sessions do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSkyWeb.Live.Shared.AgentStatusHelpers
  alias EyeInTheSkyWeb.ProjectLive.Sessions.Actions
  alias EyeInTheSkyWeb.ProjectLive.Sessions.FilterHandlers
  alias EyeInTheSkyWeb.ProjectLive.Sessions.Loader
  alias EyeInTheSkyWeb.ProjectLive.Sessions.State

  import EyeInTheSkyWeb.Components.ProjectSessionsPage
  import EyeInTheSkyWeb.Helpers.ProjectLiveHelpers
  import EyeInTheSkyWeb.Helpers.PubSubHelpers

  # ---------------------------------------------------------------------------
  # Mount
  # ---------------------------------------------------------------------------

  @impl true
  def mount(%{"id" => _} = params, _session, socket) do
    socket = mount_project(socket, params, sidebar_tab: :sessions, page_title_prefix: "Sessions")

    if socket.assigns.project do
      if connected?(socket) do
        subscribe_agents()
        subscribe_agent_working()
      end

      {:ok, State.init(socket)}
    else
      {:ok, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Events — filter/search/pagination
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("search", params, socket), do: FilterHandlers.search(params, socket)

  @impl true
  def handle_event("filter_session", params, socket),
    do: FilterHandlers.filter_session(params, socket)

  @impl true
  def handle_event("sort", params, socket), do: FilterHandlers.sort(params, socket)

  @impl true
  def handle_event("load_more", params, socket), do: FilterHandlers.load_more(params, socket)

  @impl true
  def handle_event("open_filter_sheet", params, socket),
    do: FilterHandlers.open_filter_sheet(params, socket)

  @impl true
  def handle_event("close_filter_sheet", params, socket),
    do: FilterHandlers.close_filter_sheet(params, socket)

  @impl true
  def handle_event("toggle_new_session_drawer", params, socket),
    do: FilterHandlers.toggle_new_session_drawer(params, socket)

  # ---------------------------------------------------------------------------
  # Events — session actions
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("create_new_session", params, socket),
    do: Actions.create_new_session(params, socket)

  @impl true
  def handle_event("archive_session", params, socket),
    do: Actions.archive_session(params, socket)

  @impl true
  def handle_event("unarchive_session", params, socket),
    do: Actions.unarchive_session(params, socket)

  @impl true
  def handle_event("delete_session", params, socket),
    do: Actions.delete_session(params, socket)

  @impl true
  def handle_event("toggle_select", params, socket), do: Actions.toggle_select(params, socket)

  @impl true
  def handle_event("toggle_select_all", params, socket),
    do: Actions.toggle_select_all(params, socket)

  @impl true
  def handle_event("delete_selected", params, socket),
    do: Actions.delete_selected(params, socket)

  @impl true
  def handle_event("navigate_dm", params, socket), do: Actions.navigate_dm(params, socket)

  @impl true
  def handle_event("rename_session", params, socket), do: Actions.rename_session(params, socket)

  @impl true
  def handle_event("save_session_name", params, socket),
    do: Actions.save_session_name(params, socket)

  @impl true
  def handle_event("cancel_rename", params, socket), do: Actions.cancel_rename(params, socket)

  @impl true
  def handle_event("noop", params, socket), do: Actions.noop(params, socket)

  @impl true
  def handle_event("set_notify_on_stop", %{"enabled" => enabled}, socket) do
    {:noreply, assign(socket, :notify_on_stop, !!enabled)}
  end

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:agent_updated, _agent}, socket) do
    {:noreply, Loader.load_agents(socket)}
  end

  @impl true
  def handle_info({:agent_working, msg}, socket) do
    AgentStatusHelpers.handle_agent_working(socket, msg, fn socket, session_id ->
      Loader.update_agent_status_in_list(socket, session_id, "working")
    end)
  end

  @impl true
  def handle_info({:agent_stopped, msg}, socket) do
    AgentStatusHelpers.handle_agent_stopped(socket, msg, fn socket, session_id ->
      Loader.update_agent_status_in_list(socket, session_id, "idle")
    end)
  end

  @impl true
  def handle_info(_, socket), do: {:noreply, socket}

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <.page
      has_more={@has_more}
      visible_count={@visible_count}
      agents={@agents}
      streams={@streams}
      depths={@depths}
      session_filter={@session_filter}
      sort_by={@sort_by}
      search_query={@search_query}
      show_filter_sheet={@show_filter_sheet}
      show_new_session_drawer={@show_new_session_drawer}
      selected_ids={@selected_ids}
      editing_session_id={@editing_session_id}
      project={@project}
    />
    """
  end
end
