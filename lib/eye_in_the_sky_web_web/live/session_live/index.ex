defmodule EyeInTheSkyWebWeb.SessionLive.Index do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.Sessions

  @impl true
  def mount(_params, _session, socket) do
    sessions = Sessions.list_session_overview_rows(limit: 20)

    socket =
      socket
      |> assign(:page_title, "Session Overview")
      |> assign(:sessions, sessions)

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
    <.live_component module={EyeInTheSkyWebWeb.Components.Navbar} id="navbar" />
    <div class="px-4 sm:px-6 lg:px-8">
      <div class="flex items-center justify-between mb-6">
        <div>
          <h1 class="text-2xl font-semibold text-gray-900 dark:text-gray-100">Session Overview</h1>
          <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
            View all sessions across agents and projects
          </p>
        </div>

        <div class="flex items-center gap-3">
          <label class="swap swap-rotate btn btn-ghost btn-sm btn-circle">
            <input type="checkbox" class="theme-controller" value="dark" />
            <!-- sun icon -->
            <svg class="swap-on h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M12 3v1m0 16v1m9-9h-1M4 12H3m15.364 6.364l-.707-.707M6.343 6.343l-.707-.707m12.728 0l-.707.707M6.343 17.657l-.707.707M16 12a4 4 0 11-8 0 4 4 0 018 0z"
              />
            </svg>
            <!-- moon icon -->
            <svg class="swap-off h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M20.354 15.354A9 9 0 018.646 3.646 9.003 9.003 0 0012 21a9.003 9.003 0 008.354-5.646z"
              />
            </svg>
          </label>

          <button
            phx-click="start_session_global"
            class="btn btn-outline"
          >
            Start New Session
          </button>
        </div>
      </div>

      <div class="mt-8">
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          <%= for session <- @sessions do %>
            <.link
              navigate={~p"/agents/#{session.agent_id}?s=#{session.session_id}"}
              class="card bg-base-100 shadow-sm hover:shadow-md transition-shadow border border-base-300 hover:border-primary"
            >
              <div class="card-body p-4">
                <!-- Header with Session ID and Actions -->
                <div class="flex items-start justify-between gap-2 mb-3">
                  <div class="flex-1 min-w-0">
                    <p class="text-xs text-base-content/60 mb-1">Session ID</p>
                    <code class="text-sm font-mono font-semibold text-base-content break-all">
                      {String.slice(session.session_id, 0..11)}...
                    </code>
                  </div>
                  <button
                    phx-hook="CopyToClipboard"
                    id={"copy-#{session.session_id}"}
                    data-session-id={session.session_id}
                    class="btn btn-ghost btn-xs flex-shrink-0"
                    onclick="event.preventDefault(); event.stopPropagation();"
                  >
                    Copy
                  </button>
                </div>
                
    <!-- Session Name -->
                <%= if session.session_name do %>
                  <div class="mb-3">
                    <p class="text-xs text-base-content/60 mb-1">Session Name</p>
                    <p class="text-sm font-medium text-base-content line-clamp-2">
                      {session.session_name}
                    </p>
                  </div>
                <% end %>
                
    <!-- Project and Timing Info -->
                <div class="space-y-2 mb-4 pt-3 border-t border-base-300">
                  <div class="flex items-center justify-between text-xs text-base-content/70">
                    <span>Project:</span>
                    <span class="font-medium">{session.project_name || "—"}</span>
                  </div>
                  <div class="flex items-center justify-between text-xs text-base-content/70">
                    <span>Started:</span>
                    <span>{format_timestamp(session.started_at)}</span>
                  </div>
                  <div class="flex items-center justify-between text-xs text-base-content/70">
                    <span>Status:</span>
                    <% status = format_duration(session.started_at, session.ended_at) %>
                    <span class={"badge badge-xs #{if status == "Active", do: "badge-success", else: "badge-ghost"}"}>
                      {status}
                    </span>
                  </div>
                </div>
                
    <!-- Footer Action -->
                <div class="pt-3 border-t border-base-300">
                  <button
                    phx-click="start_session"
                    phx-value-agent_id={session.agent_id}
                    class="btn btn-primary btn-sm w-full"
                    onclick="event.preventDefault(); event.stopPropagation();"
                  >
                    New Session
                  </button>
                </div>
              </div>
            </.link>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp format_timestamp(nil), do: "—"

  defp format_timestamp(timestamp) when is_binary(timestamp) do
    # Handle Go time format strings
    case String.split(timestamp, " ", parts: 3) do
      [date, time | _] -> "#{date} #{String.slice(time, 0..7)}"
      _ -> timestamp
    end
  end

  defp format_duration(started_at, ended_at) when is_binary(started_at) do
    # For Go-formatted strings, we can't easily calculate duration
    # Just show if it's ended or active
    if ended_at && ended_at != "", do: "Ended", else: "Active"
  end

  defp format_duration(_, _), do: "—"
end
