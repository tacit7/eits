defmodule EyeInTheSkyWeb.SessionLive.Index do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSky.Sessions
  import EyeInTheSkyWeb.Components.SessionCard, only: [session_row: 1]
  import EyeInTheSkyWeb.Helpers.AgentCreationHelpers, only: [build_opts: 2]
  import EyeInTheSkyWeb.Helpers.PubSubHelpers
  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]

  @per_page 20

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      subscribe_agents()
    end

    sessions = Sessions.list_session_overview_rows(limit: @per_page, offset: 0)
    total = Sessions.count_session_overview_rows()
    projects = EyeInTheSky.Projects.list_projects()

    socket =
      socket
      |> assign(:page_title, "Session Overview")
      |> assign(:projects, projects)
      |> assign(:page, 1)
      |> assign(:has_more, length(sessions) < total)
      |> assign(:total_sessions, total)
      |> assign(:show_new_session_modal, false)
      |> assign(:editing_session_id, nil)
      |> stream(:sessions, sessions, dom_id: fn s -> "si-#{s.uuid}" end)

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
  def handle_event("rename_session", %{"session_id" => session_id}, socket) do
    session_id_int = parse_int(session_id)

    case session_id_int do
      nil ->
        {:noreply, socket}

      id ->
        socket = assign(socket, :editing_session_id, id)

        socket =
          case Sessions.get_session_overview_row(id) do
            {:ok, row} -> stream_insert(socket, :sessions, row)
            _ -> socket
          end

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("save_session_name", %{"session_id" => session_id, "name" => name}, socket) do
    name = String.trim(name)

    if name != "" do
      case Sessions.get_session(session_id) do
        {:ok, session} -> Sessions.update_session(session, %{name: name})
        _ -> :noop
      end
    end

    socket =
      socket
      |> assign(:editing_session_id, nil)
      |> reload_sessions()

    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_rename", _params, socket) do
    editing_id = socket.assigns.editing_session_id
    socket = assign(socket, :editing_session_id, nil)

    socket =
      if editing_id do
        case Sessions.get_session_overview_row(editing_id) do
          {:ok, row} -> stream_insert(socket, :sessions, row)
          _ -> socket
        end
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("archive_session", %{"session_id" => session_id}, socket) do
    with {:ok, session} <- Sessions.get_session(session_id),
         {:ok, _} <- Sessions.archive_session(session) do
      socket =
        socket
        |> reload_sessions()
        |> put_flash(:info, "Session archived")

      {:noreply, socket}
    else
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to archive session")}
    end
  end

  @impl true
  def handle_event("delete_session", %{"session_id" => session_id}, socket) do
    with {:ok, session} <- Sessions.get_session(session_id),
         {:ok, _} <- Sessions.delete_session(session) do
      socket =
        socket
        |> reload_sessions()
        |> put_flash(:info, "Session deleted")

      {:noreply, socket}
    else
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to delete session")}
    end
  end

  @impl true
  def handle_event("toggle_new_session_modal", _params, socket) do
    {:noreply, assign(socket, :show_new_session_modal, !socket.assigns.show_new_session_modal)}
  end

  @impl true
  def handle_event("create_new_session", params, socket) do
    project_id = parse_int(params["project_id"])
    description = params["description"]

    case project_id do
      nil ->
        {:noreply, put_flash(socket, :error, "Invalid project")}

      pid ->
        agent_name = params["agent_name"] || String.slice(description || "", 0, 60)

        project = EyeInTheSky.Projects.get_project!(pid)

        opts =
          build_opts(params,
            project_path: project.path,
            description: agent_name,
            instructions: description
          )
          |> Keyword.put(:project_id, pid)

        case AgentManager.create_agent(opts) do
          {:ok, _result} ->
            socket =
              socket
              |> assign(:show_new_session_modal, false)
              |> assign(:page, 1)
              |> reload_sessions()
              |> put_flash(:info, "Session launched")

            {:noreply, socket}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to create session: #{inspect(reason)}")}
        end
    end
  end

  # Real-time: update a single row when a session changes — avoids a full stream
  # reset (which causes heavy DOM churn and can disrupt the new-session modal).
  # Two payload shapes arrive on this event:
  #   - Session struct (from session_updated/session_started): id == session_id
  #   - Agent struct (from agent_updated): id == agent_id, session_id is never
  #     populated in practice because the changeset does not cast it
  # Only Session payloads can be targeted; Agent payloads fall back to full reload.
  @impl true
  def handle_info({:agent_updated, %EyeInTheSky.Sessions.Session{id: session_id}}, socket) do
    case Sessions.get_session_overview_row(session_id) do
      {:ok, row} ->
        {:noreply, stream_insert(socket, :sessions, row)}

      {:error, :not_found} ->
        {:noreply, reload_sessions(socket)}
    end
  end

  def handle_info({:agent_updated, _agent}, socket) do
    {:noreply, reload_sessions(socket)}
  end

  # Full reload for creates/deletes since counts and ordering can shift.
  @impl true
  def handle_info({event, _agent}, socket)
      when event in [:agent_created, :agent_deleted] do
    {:noreply, reload_sessions(socket)}
  end

  defp reload_sessions(socket) do
    current_page = socket.assigns.page
    sessions = Sessions.list_session_overview_rows(limit: current_page * @per_page, offset: 0)
    total = Sessions.count_session_overview_rows()

    socket
    |> assign(:has_more, length(sessions) < total)
    |> assign(:total_sessions, total)
    |> stream(:sessions, sessions, reset: true)
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
              class="btn btn-sm btn-primary gap-1.5 min-h-0 h-11 sm:h-7 text-xs w-full sm:w-auto"
            >
              <.icon name="hero-plus-mini" class="w-3.5 h-3.5" /> New Agent
            </button>
          </div>
        </div>

        <div class="mt-2 rounded-xl shadow-sm">
          <div
            id="sessions-list"
            phx-update="stream"
            class="divide-y divide-base-content/5 bg-base-100 rounded-xl px-4"
          >
            <div :for={{dom_id, session} <- @streams.sessions} id={dom_id}>
              <.session_row
                session={session}
                project_name={session.project_name}
                click_event="navigate_dm"
                editing_session_id={@editing_session_id}
              >
                <:actions>
                  <div class="relative dropdown dropdown-end transition-all md:opacity-0 md:group-hover:opacity-100">
                    <button
                      tabindex="0"
                      type="button"
                      class="min-h-[44px] min-w-[44px] flex items-center justify-center rounded-md text-base-content/35 hover:text-base-content/70 hover:bg-base-content/5 transition-colors"
                      aria-label="More options"
                      phx-click="noop"
                    >
                      <.icon name="hero-ellipsis-horizontal-mini" class="w-4 h-4" />
                    </button>
                    <ul
                      tabindex="0"
                      class="dropdown-content z-50 menu menu-xs bg-base-200 border border-base-content/10 rounded-lg shadow-lg w-44 p-1"
                    >
                      <%= if session.id do %>
                        <li>
                          <a href={~p"/dm/#{session.id}"} target="_blank" class="flex items-center gap-2">
                            <.icon name="hero-arrow-top-right-on-square-mini" class="w-3.5 h-3.5" />
                            Open in new tab
                          </a>
                        </li>
                      <% end %>
                      <li>
                        <button
                          type="button"
                          phx-click="rename_session"
                          phx-value-session_id={session.id}
                          class="flex items-center gap-2"
                        >
                          <.icon name="hero-pencil-square-mini" class="w-3.5 h-3.5" />
                          Rename
                        </button>
                      </li>
                      <li>
                        <button
                          type="button"
                          phx-click="archive_session"
                          phx-value-session_id={session.id}
                          class="flex items-center gap-2 text-warning"
                        >
                          <.icon name="hero-archive-box-mini" class="w-3.5 h-3.5" />
                          Archive
                        </button>
                      </li>
                    </ul>
                  </div>
                </:actions>
              </.session_row>
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
      module={EyeInTheSkyWeb.Components.NewSessionModal}
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
