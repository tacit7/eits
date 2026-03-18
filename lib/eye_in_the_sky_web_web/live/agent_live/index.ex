defmodule EyeInTheSkyWebWeb.AgentLive.Index do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.Agents
  alias EyeInTheSkyWeb.Sessions
  import EyeInTheSkyWebWeb.Helpers.PubSubHelpers
  import EyeInTheSkyWebWeb.Components.Icons
  import EyeInTheSkyWebWeb.Components.SessionCard
  import EyeInTheSkyWebWeb.Helpers.SessionFilters

  require Logger

  @default_refresh_ms 300_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      subscribe_agents()
      subscribe_agent_working()
    end

    projects = EyeInTheSkyWeb.Projects.list_projects()

    socket =
      socket
      |> assign(:page_title, "Eye in the Sky - Agents")
      |> assign(:search_query, "")
      |> assign(:sort_by, "recent")
      |> assign(:session_filter, "all")
      |> assign(:agents, [])
      |> assign(:show_new_session_drawer, false)
      |> assign(:projects, projects)
      |> assign(:timer_ref, nil)
      |> assign(:sidebar_tab, :sessions)
      |> assign(:sidebar_project, nil)
      |> assign(:selected_ids, MapSet.new())
      |> assign(:show_delete_confirm, false)
      |> assign(:editing_session_id, nil)
      |> load_agents()
      |> schedule_refresh()

    {:ok, socket}
  end

  defp load_agents(socket) do
    include_archived = socket.assigns.session_filter == "archived"
    db_agents = Sessions.list_sessions_with_agent(include_archived: include_archived)

    # Build project lookup map from assigns
    project_map =
      socket.assigns.projects
      |> Enum.into(%{}, fn p -> {p.id, p.name} end)

    agents =
      db_agents
      |> Enum.map(fn s -> Map.put(s, :project_name, project_map[s.project_id]) end)
      |> filter_agents_by_status(socket.assigns.session_filter)
      |> filter_agents_by_search(socket.assigns.search_query)
      |> sort_agents(socket.assigns.sort_by)

    assign(socket, :agents, agents)
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_event(
        "send_direct_message",
        %{"session_id" => target_session_id, "body" => body},
        socket
      ) do
    # Fetch session once, reuse below
    with {:ok, session} <- Sessions.get_session(target_session_id) do
      channels =
        if session.project_id,
          do: EyeInTheSkyWeb.Channels.list_channels_for_project(session.project_id),
          else: EyeInTheSkyWeb.Channels.list_channels()

      global_channel = Enum.find(channels, fn c -> c.name == "#global" end)

      if global_channel do
        case EyeInTheSkyWeb.Messages.send_channel_message(%{
               channel_id: global_channel.id,
               session_id: "web-user",
               sender_role: "user",
               recipient_role: "agent",
               provider: "claude",
               body: body
             }) do
          {:ok, _message} ->
            case Agents.get_agent(session.agent_id) do
              {:ok, chat_agent} ->
                project_path = chat_agent.git_worktree_path || File.cwd!()

                prompt_with_reminder = """
                REMINDER: Use i-chat-send MCP tool to send your response to the channel.

                User message: #{body}
                """

                EyeInTheSkyWeb.Agents.AgentManager.continue_session(
                  session.id,
                  prompt_with_reminder,
                  model: "sonnet",
                  project_path: project_path
                )

                {:noreply, socket}

              _ ->
                Logger.warning("send_direct_message: agent #{session.agent_id} not found, message sent but session not continued")
                {:noreply, socket}
            end

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to send message")}
        end
      else
        {:noreply, put_flash(socket, :error, "Global channel not found")}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "Session not found")}
    end
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    effective_query = if String.length(String.trim(query)) >= 3, do: query, else: ""

    socket =
      socket
      |> assign(:search_query, effective_query)
      |> load_agents()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_session", %{"filter" => filter}, socket) do
    socket =
      socket
      |> assign(:session_filter, filter)
      |> assign(:selected_ids, MapSet.new())
      |> load_agents()

    {:noreply, socket}
  end

  @impl true
  def handle_event("sort", %{"by" => sort_by}, socket) do
    socket =
      socket
      |> assign(:sort_by, sort_by)
      |> load_agents()

    {:noreply, socket}
  end

  @impl true
  def handle_event(action, %{"session_id" => session_id}, socket)
      when action in ["archive_session", "unarchive_session", "delete_session"] do
    with {:ok, session} <- Sessions.get_session(session_id),
         {:ok, _} <- apply_session_action(action, session) do
      {:noreply, socket |> load_agents() |> put_flash(:info, "Session #{action_label(action)}")}
    else
      {:error, reason} ->
        Logger.error("#{action} failed for #{session_id}: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Failed to #{action_label(action)}")}
    end
  end

  @impl true
  def handle_event("toggle_select", %{"id" => id}, socket) do
    selected =
      if MapSet.member?(socket.assigns.selected_ids, id),
        do: MapSet.delete(socket.assigns.selected_ids, id),
        else: MapSet.put(socket.assigns.selected_ids, id)

    {:noreply, assign(socket, :selected_ids, selected)}
  end

  @impl true
  def handle_event("toggle_select_all", _params, socket) do
    all_ids = MapSet.new(socket.assigns.agents, &to_string(&1.id))

    selected =
      if MapSet.equal?(socket.assigns.selected_ids, all_ids),
        do: MapSet.new(),
        else: all_ids

    {:noreply, assign(socket, :selected_ids, selected)}
  end

  @impl true
  def handle_event("confirm_delete_selected", _params, socket) do
    {:noreply, assign(socket, :show_delete_confirm, true)}
  end

  @impl true
  def handle_event("cancel_delete_selected", _params, socket) do
    {:noreply, assign(socket, :show_delete_confirm, false)}
  end

  @impl true
  def handle_event("delete_selected", _params, socket) do
    ids = socket.assigns.selected_ids

    results =
      Enum.map(ids, fn id ->
        with {:ok, agent} <- Sessions.get_session(id),
             {:ok, _} <- Sessions.delete_session(agent) do
          :ok
        else
          _ -> :error
        end
      end)

    deleted = Enum.count(results, &(&1 == :ok))

    socket =
      socket
      |> assign(:selected_ids, MapSet.new())
      |> assign(:show_delete_confirm, false)
      |> load_agents()
      |> put_flash(:info, "Deleted #{deleted} session#{if deleted != 1, do: "s"}")

    {:noreply, socket}
  end

  @impl true
  def handle_event("navigate_dm", %{"id" => id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/dm/#{id}")}
  end

  @impl true
  def handle_event("rename_session", %{"session_id" => session_id}, socket) do
    {:noreply, assign(socket, :editing_session_id, String.to_integer(session_id))}
  end

  @impl true
  def handle_event("save_session_name", %{"session_id" => session_id, "name" => name}, socket) do
    name = String.trim(name)

    socket =
      if name != "" do
        case Sessions.get_session(session_id) do
          {:ok, session} ->
            Sessions.update_session(session, %{name: name})
            socket
          _ ->
            socket
        end
      else
        socket
      end

    {:noreply, assign(socket, :editing_session_id, nil)}
  end

  @impl true
  def handle_event("cancel_rename", _params, socket) do
    {:noreply, assign(socket, :editing_session_id, nil)}
  end

  @impl true
  def handle_event("toggle_new_session_drawer", _params, socket) do
    {:noreply, assign(socket, :show_new_session_drawer, !socket.assigns.show_new_session_drawer)}
  end

  @impl true
  def handle_event("create_new_session", params, socket) do
    project_id =
      case Integer.parse(params["project_id"] || "") do
        {id, ""} -> id
        _ -> nil
      end

    if is_nil(project_id) do
      {:noreply, put_flash(socket, :error, "Invalid project")}
    else
      create_new_session_with_project(params, project_id, socket)
    end
  end

  defp create_new_session_with_project(params, project_id, socket) do
    case EyeInTheSkyWeb.Projects.get_project(project_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Project not found")}

      project ->
        do_create_session(params, project, socket)
    end
  end

  defp do_create_session(params, project, socket) do
    agent_type = params["agent_type"] || "claude"
    model = params["model"]
    effort_level = params["effort_level"]
    max_budget_usd = parse_budget(params["max_budget_usd"])
    description = params["description"]
    agent_name = params["agent_name"] || String.slice(description || "", 0, 60)

    worktree =
      case params["worktree"] do
        nil -> nil
        "" -> nil
        v -> String.trim(v)
      end

    eits_workflow = params["eits_workflow"] || "1"

    opts = [
      agent_type: agent_type,
      model: model,
      effort_level: effort_level,
      max_budget_usd: max_budget_usd,
      project_id: project.id,
      project_path: project.path,
      description: agent_name,
      instructions: description,
      worktree: worktree,
      agent: params["agent"],
      eits_workflow: eits_workflow
    ]

    Logger.info(
      "create_new_session: model=#{model}, effort=#{inspect(effort_level)}, project_id=#{project.id}, project_path=#{project.path}"
    )

    case EyeInTheSkyWeb.Agents.AgentManager.create_agent(opts) do
      {:ok, result} ->
        Logger.info(
          "create_new_session: agent created - agent_id=#{result.agent.id}, session_id=#{result.agent.id}, session_uuid=#{result.agent.uuid}"
        )

        {:noreply,
         socket
         |> assign(:show_new_session_drawer, false)
         |> push_navigate(to: ~p"/dm/#{result.session.id}")}

      {:error, reason} ->
        Logger.error("create_new_session: failed - #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Failed to create session: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info(:refresh_agents, socket) do
    socket = socket |> load_agents() |> schedule_refresh()
    {:noreply, socket}
  end

  @impl true
  def handle_info({event, _agent}, socket)
      when event in [:agent_created, :agent_updated, :agent_deleted] do
    {:noreply, load_agents(socket)}
  end

  @impl true
  def handle_info({:agent_working, %{id: session_id}}, socket) do
    {:noreply, update_agent_status_in_list(socket, session_id, "working")}
  end

  @impl true
  def handle_info({:agent_working, _session_uuid, session_id}, socket) do
    {:noreply, update_agent_status_in_list(socket, session_id, "working")}
  end

  @impl true
  def handle_info({:agent_stopped, %{id: session_id, status: status}}, socket) do
    {:noreply, update_agent_status_in_list(socket, session_id, status || "completed")}
  end

  @impl true
  def handle_info({:agent_stopped, _session_uuid, session_id}, socket) do
    {:noreply, update_agent_status_in_list(socket, session_id, "idle")}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

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
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    updated_agents =
      socket.assigns.agents
      |> Enum.map(fn agent ->
        if agent.id == session_id do
          agent = %{agent | status: new_status}
          if new_status == "idle", do: %{agent | last_activity_at: now}, else: agent
        else
          agent
        end
      end)
      |> sort_agents(socket.assigns.sort_by)

    assign(socket, :agents, updated_agents)
  end

  defp apply_session_action("archive_session", session), do: Sessions.archive_session(session)
  defp apply_session_action("unarchive_session", session), do: Sessions.unarchive_session(session)
  defp apply_session_action("delete_session", session), do: Sessions.delete_session(session)

  defp action_label("archive_session"), do: "archived"
  defp action_label("unarchive_session"), do: "unarchived"
  defp action_label("delete_session"), do: "deleted"

  # -- Function Components --------------------------------------------------

  @filter_tabs [
    {"all", "All", "text-base-content"},
    {"active", "Active", "text-success"},
    {"completed", "Completed", "text-base-content"},
    {"archived", "Archived", "text-warning"}
  ]

  defp filter_tabs(assigns) do
    assigns = assign(assigns, :tabs, @filter_tabs)

    ~H"""
    <div class="flex items-center gap-1 bg-base-200/40 rounded-lg p-0.5">
      <button
        :for={{value, label, active_color} <- @tabs}
        phx-click="filter_session"
        phx-value-filter={value}
        class={"px-3 py-1 rounded-md text-xs font-medium transition-all duration-150 " <>
          if(@current == value,
            do: "bg-base-100 #{active_color} shadow-sm",
            else: "text-base-content/40 hover:text-base-content/60"
          )}
      >
        {label}
      </button>
    </div>
    """
  end


  # -- Render ---------------------------------------------------------------

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
            <button phx-click="toggle_new_session_drawer" class="btn btn-sm btn-primary gap-1.5 min-h-0 h-7 text-xs">
              <.icon name="hero-plus-mini" class="w-3.5 h-3.5" /> New Agent
            </button>
            <label class="swap swap-rotate btn btn-ghost btn-xs btn-circle">
              <input type="checkbox" class="theme-controller" value="dark" />
              <.icon name="hero-sun" class="swap-on w-4 h-4" />
              <.icon name="hero-moon" class="swap-off w-4 h-4" />
            </label>
          </div>
        </div>

        <div class="sticky safe-top-sticky md:top-16 z-10 bg-base-100/85 backdrop-blur-md -mx-4 sm:-mx-6 lg:-mx-8 px-4 sm:px-6 lg:px-8 py-3 border-b border-base-content/5">
          <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:gap-3">
            <form phx-change="search" class="flex-1 max-w-sm">
              <label for="search" class="sr-only">Search agents</label>
              <div class="relative">
                <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
                  <.icon name="hero-magnifying-glass-mini" class="w-4 h-4 text-base-content/25" />
                </div>
                <input
                  type="text"
                  name="query"
                  id="search"
                  value={@search_query}
                  phx-debounce="300"
                  class="input input-sm w-full pl-9 bg-base-200/50 border-base-content/8 placeholder:text-base-content/25 focus:border-primary/30 focus:bg-base-100 transition-colors text-sm"
                  placeholder="Search..."
                />
              </div>
            </form>
            <.filter_tabs current={@session_filter} />
          </div>
        </div>

        <%= if @session_filter == "archived" && @agents != [] do %>
          <div class="mt-2 flex items-center gap-3 px-2 py-1.5">
            <input
              type="checkbox"
              checked={MapSet.size(@selected_ids) == length(@agents)}
              phx-click="toggle_select_all"
              class="checkbox checkbox-xs checkbox-primary"
            />
            <%= if MapSet.size(@selected_ids) > 0 do %>
              <span class="text-[11px] text-base-content/50 font-medium">{MapSet.size(@selected_ids)} selected</span>
              <button phx-click="confirm_delete_selected" class="btn btn-ghost btn-xs text-error/70 hover:text-error hover:bg-error/10 gap-1">
                <.icon name="hero-trash-mini" class="w-3.5 h-3.5" /> Delete
              </button>
            <% else %>
              <span class="text-[11px] text-base-content/30">{length(@agents)} archived</span>
            <% end %>
          </div>
        <% end %>

        <div class="mt-2 divide-y divide-base-content/5 bg-[oklch(97%_0.005_80)] dark:bg-[hsl(60,2.1%,18.4%)] rounded-xl shadow-sm px-4">
          <%= if @agents == [] do %>
            <.empty_state id="agents-empty" title="No agents found" subtitle="Try adjusting your search or filters" />
          <% else %>
            <div :for={agent <- @agents}>
              <.session_row
                session={agent}
                select_mode={@session_filter == "archived"}
                selected={MapSet.member?(@selected_ids, to_string(agent.id))}
                project_name={agent.project_name}
                editing_session_id={@editing_session_id}
              >
                <:actions>
                  <%= if agent.id do %>
                    <a
                      href={~p"/dm/#{agent.id}"}
                      target="_blank"
                      class="hidden sm:inline-flex md:opacity-0 md:group-hover:opacity-100 min-h-[44px] min-w-[44px] items-center justify-center rounded-md text-base-content/30 hover:text-primary hover:bg-primary/10 transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
                      aria-label="Open in new tab"
                    >
                      <.icon name="hero-arrow-top-right-on-square-mini" class="w-3.5 h-3.5" />
                    </a>
                  <% end %>
                  <%= if agent.agent && agent.agent.uuid && agent.uuid do %>
                    <button
                      id={"bookmark-btn-#{agent.uuid}"}
                      type="button"
                      phx-hook="BookmarkAgent"
                      data-agent-id={agent.agent.uuid}
                      data-session-id={agent.uuid}
                      data-agent-name={agent.name || agent.agent.description || "Agent"}
                      data-agent-status={agent.status}
                      class="bookmark-button md:opacity-0 md:group-hover:opacity-100 min-h-[44px] min-w-[44px] flex items-center justify-center rounded-md text-base-content/30 hover:text-error hover:bg-error/10 transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-error"
                      aria-label="Bookmark agent"
                    >
                      <.heart class="bookmark-icon w-3.5 h-3.5" />
                    </button>
                  <% end %>
                  <%= if agent.uuid do %>
                    <%= if agent.archived_at do %>
                      <.icon_button
                        icon="hero-arrow-up-tray-mini"
                        on_click="unarchive_session"
                        aria_label="Unarchive"
                        color="info"
                        show_on_hover={false}
                        values={%{"session_id" => agent.id}}
                      />
                      <.icon_button
                        icon="hero-trash-mini"
                        on_click="delete_session"
                        aria_label="Delete"
                        color="error"
                        show_on_hover={false}
                        values={%{"session_id" => agent.id}}
                      />
                    <% else %>
                      <.icon_button
                        icon="hero-archive-box-mini"
                        on_click="archive_session"
                        aria_label="Archive"
                        color="warning"
                        class="hidden sm:flex"
                        values={%{"session_id" => agent.id}}
                      />
                    <% end %>
                  <% end %>
                </:actions>
              </.session_row>
            </div>
          <% end %>
        </div>
      </div>
    </div>

    <dialog id="delete-confirm-modal" class={"modal " <> if(@show_delete_confirm, do: "modal-open", else: "")}>
      <div class="modal-box max-w-sm">
        <h3 class="text-lg font-bold">Delete sessions</h3>
        <p class="py-4 text-sm text-base-content/70">
          Permanently delete {MapSet.size(@selected_ids)} selected session{if MapSet.size(@selected_ids) != 1, do: "s"}? This cannot be undone.
        </p>
        <div class="modal-action">
          <button phx-click="cancel_delete_selected" class="btn btn-sm btn-ghost">Cancel</button>
          <button phx-click="delete_selected" class="btn btn-sm btn-error">Delete</button>
        </div>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button phx-click="cancel_delete_selected">close</button>
      </form>
    </dialog>

    <.live_component
      module={EyeInTheSkyWebWeb.Components.NewSessionModal}
      id="new-session-modal"
      show={@show_new_session_drawer}
      projects={@projects}
      current_project={nil}
      toggle_event="toggle_new_session_drawer"
      submit_event="create_new_session"
    />
    """
  end

  defp parse_budget(nil), do: nil
  defp parse_budget(""), do: nil

  defp parse_budget(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} when f > 0 -> f
      _ -> nil
    end
  end
end
