defmodule EyeInTheSkyWeb.CanvasLive do
  use EyeInTheSkyWeb, :live_view

  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]

  alias EyeInTheSky.Canvases
  alias EyeInTheSky.Events
  alias EyeInTheSky.Sessions
  alias EyeInTheSkyWeb.Components.ChatWindowComponent

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Canvas")
     |> assign(:sidebar_tab, :canvas)
     |> assign(:canvases, Canvases.list_canvases())
     |> assign(:active_canvas_id, nil)
     |> assign(:canvas_sessions, [])
     |> assign(:subscribed_session_ids, [])
     |> assign(:creating_canvas, false)
     |> assign(:renaming_canvas_id, nil)
     |> assign(:canvas_session_counts, Canvases.count_sessions_per_canvas())
     |> assign(:show_session_picker, false)
     |> assign(:session_search, "")
     |> assign(:filtered_sessions, [])}
  end

  @impl true
  def handle_params(%{"id" => id_str}, _url, socket) do
    case parse_int(id_str) do
      nil ->
        {:noreply, redirect_to_first_or_stay(socket)}

      canvas_id ->
        {:noreply, activate_canvas(socket, canvas_id)}
    end
  end

  def handle_params(_params, _url, socket) do
    {:noreply, redirect_to_first_or_stay(socket)}
  end

  @impl true
  def handle_event("switch_tab", %{"canvas-id" => id_str}, socket) do
    case parse_int(id_str) do
      nil -> {:noreply, socket}
      canvas_id -> {:noreply, push_patch(socket, to: ~p"/canvases/#{canvas_id}")}
    end
  end

  def handle_event("start_new_canvas", _params, socket) do
    {:noreply, assign(socket, :creating_canvas, true)}
  end

  def handle_event("create_canvas", %{"name" => name}, socket) when name != "" do
    case Canvases.create_canvas(%{name: name}) do
      {:ok, canvas} ->
        {:noreply,
         socket
         |> assign(:canvases, socket.assigns.canvases ++ [canvas])
         |> assign(:creating_canvas, false)
         |> assign(:canvas_session_counts, Canvases.count_sessions_per_canvas())
         |> push_patch(to: ~p"/canvases/#{canvas.id}")}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("create_canvas", _params, socket) do
    {:noreply, assign(socket, :creating_canvas, false)}
  end

  def handle_event("start_rename", %{"canvas-id" => id_str}, socket) do
    {:noreply, assign(socket, :renaming_canvas_id, parse_int(id_str))}
  end

  def handle_event("rename_canvas", %{"canvas-id" => id_str, "name" => name}, socket)
      when name != "" do
    if id = parse_int(id_str) do
      case Canvases.rename_canvas(id, name) do
        {:ok, updated} ->
          canvases = Enum.map(socket.assigns.canvases, fn c ->
            if c.id == id, do: updated, else: c
          end)
          socket =
            if socket.assigns.active_canvas_id == id do
              assign(socket, :page_title, updated.name <> " — Canvas")
            else
              socket
            end
          {:noreply, socket |> assign(:canvases, canvases) |> assign(:renaming_canvas_id, nil)}

        {:error, _} ->
          {:noreply, assign(socket, :renaming_canvas_id, nil)}
      end
    else
      {:noreply, assign(socket, :renaming_canvas_id, nil)}
    end
  end

  def handle_event("rename_canvas", _params, socket) do
    {:noreply, assign(socket, :renaming_canvas_id, nil)}
  end

  def handle_event("cancel_rename", _params, socket) do
    {:noreply, assign(socket, :renaming_canvas_id, nil)}
  end

  def handle_event("window_moved", %{"id" => cs_id, "x" => x, "y" => y}, socket) do
    if id = parse_int(cs_id), do: Canvases.update_window_layout(id, %{pos_x: x, pos_y: y})
    {:noreply, socket}
  end

  def handle_event("window_resized", %{"id" => cs_id, "w" => w, "h" => h}, socket) do
    if id = parse_int(cs_id), do: Canvases.update_window_layout(id, %{width: w, height: h})
    {:noreply, socket}
  end

  def handle_event("remove_window", %{"canvas-session-id" => cs_id_str}, socket) do
    {:noreply, remove_canvas_session(socket, parse_int(cs_id_str))}
  end

  def handle_event("delete_canvas", %{"canvas-id" => id_str}, socket) do
    case parse_int(id_str) do
      nil ->
        {:noreply, socket}

      canvas_id ->
        case Canvases.delete_canvas(canvas_id) do
          {:ok, _} ->
            canvases = Enum.reject(socket.assigns.canvases, &(&1.id == canvas_id))
            socket = assign(socket, :canvases, canvases)

            socket =
              if socket.assigns.active_canvas_id == canvas_id do
                case canvases do
                  [] ->
                    unsubscribe_all(socket.assigns.subscribed_session_ids)

                    socket
                    |> assign(:page_title, "Canvas")
                    |> assign(:active_canvas_id, nil)
                    |> assign(:canvas_sessions, [])
                    |> assign(:subscribed_session_ids, [])
                    |> push_patch(to: ~p"/canvases")

                  _ ->
                    redirect_to_first_or_stay(socket)
                end
              else
                socket
              end

            {:noreply, socket}

          {:error, _} ->
            {:noreply, socket}
        end
    end
  end

  def handle_event("tidy_layout", _params, socket) do
    canvas_id = socket.assigns.active_canvas_id
    Canvases.reset_canvas_layout(canvas_id)
    sessions = Canvases.list_canvas_sessions(canvas_id)

    sessions =
      sessions
      |> Enum.with_index()
      |> Enum.map(fn {cs, i} ->
        %{cs | pos_x: 24 + i * 40, pos_y: 24 + i * 40, width: 320, height: 260}
      end)

    {:noreply, assign(socket, :canvas_sessions, sessions)}
  end

  def handle_event("open_session_picker", _params, socket) do
    canvas_session_ids = Enum.map(socket.assigns.canvas_sessions, & &1.session_id)
    all = Sessions.list_sessions()
    filtered = Enum.reject(all, &(&1.id in canvas_session_ids))

    {:noreply,
     socket
     |> assign(:show_session_picker, true)
     |> assign(:session_search, "")
     |> assign(:filtered_sessions, filtered)}
  end

  def handle_event("close_session_picker", _params, socket) do
    {:noreply, assign(socket, :show_session_picker, false)}
  end

  def handle_event("search_sessions", %{"query" => q}, socket) do
    canvas_session_ids = Enum.map(socket.assigns.canvas_sessions, & &1.session_id)
    q_down = String.downcase(q)

    filtered =
      Sessions.list_sessions()
      |> Enum.reject(&(&1.id in canvas_session_ids))
      |> Enum.filter(&String.contains?(String.downcase(&1.name || ""), q_down))

    {:noreply,
     socket
     |> assign(:session_search, q)
     |> assign(:filtered_sessions, filtered)}
  end

  def handle_event("pick_session", %{"session-id" => sid_str}, socket) do
    case parse_int(sid_str) do
      nil ->
        {:noreply, socket}

      session_id ->
        Canvases.add_session(socket.assigns.active_canvas_id, session_id)
        {:noreply, assign(socket, :show_session_picker, false)}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:new_dm, message}, socket) do
    {:noreply, refresh_window(socket, message.session_id)}
  end

  def handle_info({:claude_response, _ref, parsed}, socket) do
    session_id = parsed[:session_id] || parsed["session_id"]
    {:noreply, if(session_id, do: refresh_window(socket, session_id), else: socket)}
  end

  def handle_info({:session_status, session_id, _status}, socket) do
    cs = Enum.find(socket.assigns.canvas_sessions, &(&1.session_id == session_id))

    if cs do
      send_update(ChatWindowComponent,
        id: "chat-window-#{cs.id}",
        canvas_session: cs
      )
    end

    {:noreply, socket}
  end

  def handle_info({:remove_canvas_window, cs_id}, socket) do
    {:noreply, remove_canvas_session(socket, cs_id)}
  end

  def handle_info({:canvas_session_added, _payload}, socket) do
    new_sessions = Canvases.list_canvas_sessions(socket.assigns.active_canvas_id || -1)
    existing_ids = Enum.map(socket.assigns.canvas_sessions, & &1.id)

    added =
      Enum.reject(new_sessions, &(&1.id in existing_ids))
      |> apply_default_positions(length(socket.assigns.canvas_sessions))

    new_session_ids = Enum.map(added, & &1.session_id)
    subscribe_all(new_session_ids)

    {:noreply,
     socket
     |> assign(:canvas_sessions, socket.assigns.canvas_sessions ++ added)
     |> assign(
       :subscribed_session_ids,
       socket.assigns.subscribed_session_ids ++ new_session_ids
     )
     |> assign(:canvas_session_counts, Canvases.count_sessions_per_canvas())}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-full bg-base-100">
      <.canvas_tabs
        canvases={@canvases}
        active_canvas_id={@active_canvas_id}
        canvas_sessions={@canvas_sessions}
        canvas_session_counts={@canvas_session_counts}
        renaming_canvas_id={@renaming_canvas_id}
        creating_canvas={@creating_canvas}
      />
      <.canvas_area
        canvases={@canvases}
        canvas_sessions={@canvas_sessions}
        active_canvas_id={@active_canvas_id}
      />
      <.session_picker_modal
        :if={@show_session_picker}
        session_search={@session_search}
        filtered_sessions={@filtered_sessions}
      />
    </div>
    """
  end

  defp canvas_tabs(assigns) do
    ~H"""
    <div id="canvas-tablist" role="tablist" phx-hook="CanvasStatusHook" class="tabs tabs-border px-2 border-b border-base-300 bg-base-200/70 shrink-0">
      <button
        onclick="history.length > 1 ? history.back() : window.location.href = '/'"
        class="btn btn-ghost btn-xs px-1.5 self-center mr-1 text-base-content/50 hover:text-base-content"
        aria-label="Go back"
        title="Go back"
      >
        <.icon name="hero-arrow-left" class="w-4 h-4" />
      </button>
      <%= for canvas <- @canvases do %>
        <%= if @renaming_canvas_id == canvas.id do %>
          <form
            id={"rename-canvas-form-#{canvas.id}"}
            phx-submit="rename_canvas"
            phx-value-canvas-id={canvas.id}
            class="flex items-center px-1"
          >
            <input
              type="text"
              name="name"
              value={canvas.name}
              class="input input-xs w-28 text-base"
              phx-keydown="cancel_rename"
              phx-key="Escape"
              phx-blur={JS.dispatch("submit", to: "#rename-canvas-form-#{canvas.id}")}
              autofocus
            />
          </form>
        <% else %>
          <a
            role="tab"
            id={"canvas-tab-#{canvas.id}"}
            data-canvas-id={canvas.id}
            phx-hook="CanvasTabHook"
            class={["tab tab-sm", if(@active_canvas_id == canvas.id, do: "tab-active")]}
            phx-click="switch_tab"
            phx-value-canvas-id={canvas.id}
          >
            {canvas.name}
            <span
              :if={Map.get(@canvas_session_counts, canvas.id, 0) > 0}
              class="badge badge-xs badge-ghost ml-1"
            >{Map.get(@canvas_session_counts, canvas.id, 0)}</span>
            <button
              :if={@active_canvas_id == canvas.id}
              type="button"
              phx-click.stop="delete_canvas"
              phx-value-canvas-id={canvas.id}
              phx-confirm="Delete canvas and all its windows?"
              class="ml-1 opacity-50 hover:opacity-100"
            >
              <.icon name="hero-trash-mini" class="w-3 h-3" />
            </button>
          </a>
        <% end %>
      <% end %>
      <%= if @creating_canvas do %>
        <form phx-submit="create_canvas" class="flex items-center gap-1 px-2">
          <input
            type="text"
            name="name"
            class="input input-xs w-28 text-base"
            placeholder="Canvas name"
            autofocus
          />
          <button type="submit" class="btn btn-primary btn-xs min-h-[44px]">+</button>
        </form>
      <% else %>
        <a
          role="tab"
          class="tab tab-sm text-base-content/40"
          phx-click="start_new_canvas"
        >
          + New
        </a>
      <% end %>
      <span id="canvas-ws-badge" class="badge badge-warning badge-sm gap-1 self-center mx-2 hidden">
        <span class="loading loading-spinner loading-xs"></span> Reconnecting...
      </span>
      <button
        :if={not is_nil(@active_canvas_id)}
        phx-click={JS.dispatch("palette:open-command", to: "#command-palette", detail: %{commandId: "canvas-add-session"})}
        class="ml-auto btn btn-ghost btn-xs text-base-content/40 hover:text-base-content flex items-center gap-1"
        title="Add session to canvas"
      >
        <.icon name="hero-plus-mini" class="w-3.5 h-3.5" />
      </button>
      <button
        :if={@canvas_sessions != [] and not is_nil(@active_canvas_id)}
        phx-hook="CanvasLayoutHook"
        id="layout-2up"
        data-layout-btn="2up"
        phx-update="ignore"
        class="btn btn-ghost btn-xs px-1.5 text-base-content/50 hover:text-base-content"
        title="2-up layout"
      >
        <.icon name="hero-view-columns" class="w-4 h-4" />
      </button>
      <button
        :if={@canvas_sessions != [] and not is_nil(@active_canvas_id)}
        phx-hook="CanvasLayoutHook"
        id="layout-4up"
        data-layout-btn="4up"
        phx-update="ignore"
        class="btn btn-ghost btn-xs px-1.5 text-base-content/50 hover:text-base-content"
        title="4-up layout"
      >
        <.icon name="hero-squares-2x2" class="w-4 h-4" />
      </button>
      <button
        :if={@canvas_sessions != [] and not is_nil(@active_canvas_id)}
        phx-click="tidy_layout"
        class="mr-2 btn btn-ghost btn-xs text-base-content/40 hover:text-base-content flex items-center gap-1"
        title="Tidy windows"
      >
        <.icon name="hero-squares-2x2-mini" class="w-3.5 h-3.5" />
      </button>
    </div>
    """
  end

  defp canvas_area(assigns) do
    ~H"""
    <div data-canvas-area id="canvas-area" phx-hook="CanvasPanHook" class="relative flex-1 overflow-hidden">
      <%= for cs <- @canvas_sessions do %>
        <.live_component
          module={ChatWindowComponent}
          id={"chat-window-#{cs.id}"}
          canvas_session={cs}
        />
      <% end %>
      <%= if @canvas_sessions == [] and not is_nil(@active_canvas_id) do %>
        <div class="flex flex-col items-center justify-center h-full gap-2 select-none">
          <.icon name="hero-squares-2x2" class="w-10 h-10 text-base-content/20" />
          <span class="text-base-content/40 text-sm font-medium">No sessions on this canvas</span>
          <span class="text-base-content/30 text-xs">Go to Sessions and use Add to Canvas to attach one.</span>
          <.link navigate={~p"/sessions"} class="btn btn-sm btn-ghost text-base-content/40 mt-1">Go to Sessions</.link>
        </div>
      <% end %>
      <%= if @canvases == [] do %>
        <div class="flex flex-col items-center justify-center h-full gap-3 text-base-content/30 text-sm select-none">
          <.icon name="hero-squares-2x2" class="w-8 h-8" />
          <span>No canvases yet. Create one with "+ New" above.</span>
        </div>
      <% end %>
    </div>
    """
  end

  defp session_picker_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center">
      <div class="absolute inset-0 bg-base-300/60" phx-click="close_session_picker"></div>
      <div class="relative z-10 card bg-base-100 shadow-xl w-96 max-h-[70vh] flex flex-col">
        <div class="card-body p-4 flex flex-col gap-3 min-h-0">
          <div class="flex items-center justify-between shrink-0">
            <h3 class="font-semibold text-sm">Add Session to Canvas</h3>
            <button type="button" phx-click="close_session_picker" class="btn btn-ghost btn-xs btn-circle">
              <.icon name="hero-x-mark-mini" class="w-4 h-4" />
            </button>
          </div>
          <form phx-change="search_sessions" class="shrink-0">
            <input
              type="text"
              placeholder="Search sessions..."
              value={@session_search}
              phx-debounce="200"
              name="query"
              class="input input-sm w-full"
              autofocus
            />
          </form>
          <div class="overflow-y-auto flex flex-col gap-0.5 min-h-0">
            <%= for s <- @filtered_sessions do %>
              <button
                type="button"
                phx-click="pick_session"
                phx-value-session-id={s.id}
                class="btn btn-ghost btn-sm justify-start gap-2 text-left w-full"
              >
                <span class="truncate flex-1 text-left">{s.name || "Session #{s.id}"}</span>
                <span class={["badge badge-xs shrink-0", session_status_class(s.status)]}>{s.status}</span>
              </button>
            <% end %>
            <%= if @filtered_sessions == [] do %>
              <p class="text-center text-base-content/40 text-xs py-4">No sessions found</p>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- Helpers ---

  defp remove_canvas_session(socket, cs_id) do
    cs = cs_id && Enum.find(socket.assigns.canvas_sessions, &(&1.id == cs_id))

    if cs do
      Canvases.remove_session(socket.assigns.active_canvas_id, cs.session_id)
      unsubscribe_session(cs.session_id)

      socket
      |> assign(:canvas_sessions, Enum.reject(socket.assigns.canvas_sessions, &(&1.id == cs_id)))
      |> assign(
        :subscribed_session_ids,
        Enum.reject(socket.assigns.subscribed_session_ids, &(&1 == cs.session_id))
      )
      |> assign(:canvas_session_counts, Canvases.count_sessions_per_canvas())
    else
      socket
    end
  end

  defp apply_default_positions(sessions, offset \\ 0) do
    sessions
    |> Enum.with_index(offset)
    |> Enum.map(fn {cs, i} ->
      if cs.pos_x == 0 and cs.pos_y == 0 and cs.width == 320 and cs.height == 260,
        do: %{cs | pos_x: 24 + i * 32, pos_y: 16 + i * 32},
        else: cs
    end)
  end

  defp redirect_to_first_or_stay(socket) do
    canvases = socket.assigns.canvases

    case canvases do
      [first | _] -> push_patch(socket, to: ~p"/canvases/#{first.id}")
      [] -> socket
    end
  end

  defp activate_canvas(socket, canvas_id) do
    if prev = socket.assigns.active_canvas_id, do: Events.unsubscribe_canvas(prev)
    unsubscribe_all(socket.assigns.subscribed_session_ids)
    sessions = Canvases.list_canvas_sessions(canvas_id)
    session_ids = Enum.map(sessions, & &1.session_id)
    subscribe_all(session_ids)
    Events.subscribe_canvas(canvas_id)

    canvas_name =
      case Canvases.get_canvas(canvas_id) do
        {:ok, c} -> c.name
        _ -> "Canvas"
      end

    sessions = apply_default_positions(sessions)

    socket
    |> assign(:page_title, canvas_name <> " — Canvas")
    |> assign(:active_canvas_id, canvas_id)
    |> assign(:canvas_sessions, sessions)
    |> assign(:subscribed_session_ids, session_ids)
    |> assign(:canvas_session_counts, Canvases.count_sessions_per_canvas())
    |> assign(:show_session_picker, false)
    |> assign(:filtered_sessions, [])
    |> assign(:session_search, "")
  end

  defp subscribe_all(ids) do
    Enum.each(ids, fn id ->
      Events.subscribe_session(id)
      Events.subscribe_session_status(id)
    end)
  end

  defp unsubscribe_all(ids), do: Enum.each(ids, &unsubscribe_session/1)

  defp unsubscribe_session(id) do
    Events.unsubscribe_session(id)
    Events.unsubscribe_session_status(id)
  end

  defp refresh_window(socket, session_id) do
    cs = Enum.find(socket.assigns.canvas_sessions, &(&1.session_id == session_id))

    if cs do
      send_update(ChatWindowComponent,
        id: "chat-window-#{cs.id}",
        canvas_session: cs
      )
    end

    socket
  end

  defp session_status_class("working"), do: "badge-primary"
  defp session_status_class("waiting"), do: "badge-warning"
  defp session_status_class("completed"), do: "badge-success"
  defp session_status_class("failed"), do: "badge-error"
  defp session_status_class(_), do: "badge-ghost"
end
