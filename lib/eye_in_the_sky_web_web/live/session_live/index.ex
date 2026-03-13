defmodule EyeInTheSkyWebWeb.SessionLive.Index do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.Sessions
  import EyeInTheSkyWebWeb.Components.SessionCard, only: [session_row: 1]

  @per_page 20

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "agents")
    end

    sessions = Sessions.list_session_overview_rows(limit: @per_page, offset: 0)
    total = Sessions.count_session_overview_rows()
    projects = EyeInTheSkyWeb.Projects.list_projects()

    socket =
      socket
      |> assign(:page_title, "Session Overview")
      |> assign(:projects, projects)
      |> assign(:page, 1)
      |> assign(:has_more, length(sessions) < total)
      |> assign(:total_sessions, total)
      |> assign(:show_new_session_modal, false)
      |> stream(:sessions, sessions, dom_id: fn s -> "si-#{s.session_uuid}" end)

    {:ok, socket}
  end

  @impl true
  def handle_event("load_more", _params, socket) do
    if socket.assigns.has_more do
      next_page = socket.assigns.page + 1
      offset = (next_page - 1) * @per_page
      total = socket.assigns.total_sessions

      new_sessions = Sessions.list_session_overview_rows(limit: @per_page, offset: offset)

      socket =
        socket
        |> assign(:page, next_page)
        |> assign(:has_more, offset + length(new_sessions) < total)

      socket =
        Enum.reduce(new_sessions, socket, fn session, acc ->
          stream_insert(acc, :sessions, session)
        end)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("navigate_dm", %{"id" => id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/dm/#{id}")}
  end

  @impl true
  def handle_event("noop", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("toggle_new_session_modal", _params, socket) do
    {:noreply, assign(socket, :show_new_session_modal, !socket.assigns.show_new_session_modal)}
  end

  @impl true
  def handle_event("create_new_session", params, socket) do
    model = params["model"]
    effort_level = params["effort_level"]
    project_id = String.to_integer(params["project_id"])
    description = params["description"]
    agent_name = String.slice(description || "", 0, 60)

    project = EyeInTheSkyWeb.Projects.get_project!(project_id)

    opts = [
      model: model,
      effort_level: effort_level,
      project_id: project_id,
      project_path: project.path,
      description: agent_name,
      instructions: description,
      agent: params["agent"]
    ]

    case EyeInTheSkyWeb.Claude.AgentManager.create_agent(opts) do
      {:ok, _result} ->
        sessions = Sessions.list_session_overview_rows(limit: @per_page, offset: 0)
        total = Sessions.count_session_overview_rows()

        socket =
          socket
          |> assign(:show_new_session_modal, false)
          |> assign(:page, 1)
          |> assign(:has_more, length(sessions) < total)
          |> assign(:total_sessions, total)
          |> stream(:sessions, sessions, reset: true)
          |> put_flash(:info, "Session launched")

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create session: #{inspect(reason)}")}
    end
  end

  # Real-time: reload sessions list when agents change
  @impl true
  def handle_info({_event, _agent}, socket) do
    sessions = Sessions.list_session_overview_rows(limit: socket.assigns.page * @per_page, offset: 0)
    total = Sessions.count_session_overview_rows()

    socket =
      socket
      |> assign(:page, 1)
      |> assign(:has_more, length(sessions) < total)
      |> assign(:total_sessions, total)
      |> stream(:sessions, sessions, reset: true, dom_id: fn s -> "si-#{s.session_uuid}" end)

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-base-100 min-h-full px-4 sm:px-6 lg:px-8">
      <div class="max-w-4xl mx-auto">
        <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between py-5">
          <span class="text-[11px] font-mono tabular-nums text-base-content/45 tracking-wider uppercase">
            {@total_sessions} sessions
          </span>
          <div class="flex w-full sm:w-auto items-center gap-2">
            <button
              phx-click="toggle_new_session_modal"
              class="btn btn-sm btn-primary gap-1.5 min-h-0 h-8 sm:h-7 text-xs w-full sm:w-auto"
            >
              <.icon name="hero-plus-mini" class="w-3.5 h-3.5" /> New Agent
            </button>
          </div>
        </div>

        <div class="mt-2 rounded-xl shadow-sm">
          <div
            id="sessions-list"
            phx-update="stream"
            class="divide-y divide-base-content/5 bg-[oklch(97%_0.005_80)] dark:bg-[hsl(60,2.1%,18.4%)] rounded-xl px-4"
          >
            <div :for={{dom_id, session} <- @streams.sessions} id={dom_id}>
              <.session_row
                session={%{
                  id: session.session_id,
                  uuid: session.session_uuid,
                  name: session.session_name,
                  status: session.status,
                  started_at: session.started_at,
                  ended_at: session.ended_at,
                  model_name: session.model_name,
                  model_provider: session.model_provider,
                  model_version: session.model_version
                }}
                project_name={session.project_name}
                click_event="navigate_dm"
              />
            </div>
          </div>
        </div>

        <div
          id="sessions-infinite-scroll-sentinel"
          phx-hook="InfiniteScroll"
          data-has-more={to_string(@has_more)}
          data-page={@page}
          class="py-6 flex justify-center"
        >
          <%= if @has_more do %>
            <span class="loading loading-spinner loading-sm text-base-content/30"></span>
          <% end %>
        </div>
      </div>
    </div>

    <.live_component
      module={EyeInTheSkyWebWeb.Components.NewSessionModal}
      id="new-session-modal"
      show={@show_new_session_modal}
      projects={@projects}
      current_project={nil}
      toggle_event="toggle_new_session_modal"
      submit_event="create_new_session"
    />
    """
  end
end
