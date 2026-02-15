defmodule EyeInTheSkyWebWeb.SessionLive.Index do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.Agents
  import EyeInTheSkyWebWeb.Components.SessionCard

  @impl true
  def mount(_params, _session, socket) do
    agents = Agents.list_execution_agent_overview_rows(limit: 20)

    socket =
      socket
      |> assign(:page_title, "Session Overview")
      |> assign(:agents, agents)
      |> assign(:sidebar_tab, :sessions)
      |> assign(:sidebar_project, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("start_session", %{"agent_id" => _agent_id}, socket) do
    # Mocked button - just show a message for now
    {:noreply, socket}
  end

  @impl true
  def handle_event("start_session_global", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-6 lg:px-8">
      <div class="max-w-5xl mx-auto">
        <div class="flex items-center justify-between py-6">
          <div>
            <h1 class="text-lg font-semibold text-base-content/90">Sessions</h1>
            <p class="text-xs text-base-content/35 mt-0.5">
              Recent sessions across all projects
            </p>
          </div>
          <div class="flex items-center gap-2">
            <button
              phx-click="start_session_global"
              class="btn btn-sm btn-primary gap-1.5 min-h-0 h-7 text-xs"
            >
              <.icon name="hero-plus-mini" class="w-3.5 h-3.5" /> New Session
            </button>
            <label class="swap swap-rotate btn btn-ghost btn-xs btn-circle">
              <input type="checkbox" class="theme-controller" value="dark" />
              <.icon name="hero-sun" class="swap-on w-4 h-4" />
              <.icon name="hero-moon" class="swap-off w-4 h-4" />
            </label>
          </div>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
          <%= for agent <- @agents do %>
            <.session_card session={agent} />
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
