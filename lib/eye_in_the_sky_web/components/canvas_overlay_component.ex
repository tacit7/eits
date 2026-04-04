defmodule EyeInTheSkyWeb.Components.CanvasOverlayComponent do
  use EyeInTheSkyWeb, :live_component

  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]

  alias EyeInTheSkyWeb.Canvases
  alias EyeInTheSky.Events
  alias EyeInTheSkyWeb.Components.ChatWindowComponent

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:open, false)
     |> assign(:canvases, [])
     |> assign(:active_canvas_id, nil)
     |> assign(:canvas_sessions, [])
     |> assign(:subscribed_session_ids, [])
     |> assign(:creating_canvas, false)}
  end

  @impl true
  def update(%{action: :toggle}, socket), do: {:ok, toggle_open(socket)}

  def update(%{action: :open_canvas, canvas_id: canvas_id}, socket) do
    {:ok,
     socket
     |> assign(:open, true)
     |> load_canvases()
     |> activate_canvas(canvas_id)}
  end

  def update(%{action: :remove_window, canvas_session_id: cs_id}, socket) do
    cs = Enum.find(socket.assigns.canvas_sessions, &(&1.id == cs_id))

    if cs do
      Canvases.remove_session(socket.assigns.active_canvas_id, cs.session_id)
      unsubscribe_session(cs.session_id)

      {:ok,
       socket
       |> assign(:canvas_sessions, Enum.reject(socket.assigns.canvas_sessions, &(&1.id == cs_id)))
       |> assign(:subscribed_session_ids, Enum.reject(socket.assigns.subscribed_session_ids, &(&1 == cs.session_id)))}
    else
      {:ok, socket}
    end
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:canvases, fn -> Canvases.list_canvases() end)}
  end

  def handle_info({:new_dm, message}, socket) do
    {:noreply, refresh_window(socket, message.session_id)}
  end

  def handle_info({:claude_response, _ref, parsed}, socket) do
    session_id = parsed[:session_id] || parsed["session_id"]
    {:noreply, if(session_id, do: refresh_window(socket, session_id), else: socket)}
  end

  def handle_info({:session_status, session_id, _status}, socket) do
    cs = Enum.find(socket.assigns.canvas_sessions, &(&1.session_id == session_id))
    if cs, do: send_update(EyeInTheSkyWeb.Components.ChatWindowComponent, id: "chat-window-#{cs.id}", canvas_session: cs)
    {:noreply, socket}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def handle_event("toggle", _params, socket), do: {:noreply, toggle_open(socket)}

  def handle_event("open", %{"canvas-id" => id_str}, socket) do
    case parse_int(id_str) do
      nil -> {:noreply, socket}
      canvas_id -> {:noreply, socket |> assign(:open, true) |> load_canvases() |> activate_canvas(canvas_id)}
    end
  end

  def handle_event("switch_tab", %{"canvas-id" => id_str}, socket) do
    case parse_int(id_str) do
      nil -> {:noreply, socket}
      canvas_id -> {:noreply, activate_canvas(socket, canvas_id)}
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
         |> activate_canvas(canvas.id)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("create_canvas", _params, socket) do
    {:noreply, assign(socket, :creating_canvas, false)}
  end

  # cs_id arrives from JS as a string or integer — parse_int handles both
  def handle_event("window_moved", %{"id" => cs_id, "x" => x, "y" => y}, socket) do
    if id = parse_int(cs_id), do: Canvases.update_window_layout(id, %{pos_x: x, pos_y: y})
    {:noreply, socket}
  end

  def handle_event("window_resized", %{"id" => cs_id, "w" => w, "h" => h}, socket) do
    if id = parse_int(cs_id), do: Canvases.update_window_layout(id, %{width: w, height: h})
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="canvas-overlay">
    <%= if @open do %>
      <div style="position: fixed; inset: 0; z-index: 60;" class="bg-base-100/80 backdrop-blur-md flex flex-col">
        <div class="flex items-center justify-between px-4 py-2 border-b border-base-300 bg-base-200/70 shrink-0">
          <div class="flex items-center gap-3">
            <span class="text-secondary font-semibold text-sm">Canvas</span>
            <div class="tabs tabs-boxed tabs-xs bg-base-300">
              <%= for canvas <- @canvases do %>
                <a
                  class={["tab tab-xs", if(@active_canvas_id == canvas.id, do: "tab-active")]}
                  phx-click="switch_tab"
                  phx-value-canvas-id={canvas.id}
                  phx-target={@myself}
                >
                  <%= canvas.name %>
                </a>
              <% end %>
              <%= if @creating_canvas do %>
                <form phx-submit="create_canvas" phx-target={@myself} class="flex gap-1 ml-1">
                  <input type="text" name="name" class="input input-xs w-28" placeholder="Canvas name" autofocus />
                  <button type="submit" class="btn btn-primary btn-xs">+</button>
                </form>
              <% else %>
                <a
                  class="tab tab-xs text-base-content/40"
                  phx-click="start_new_canvas"
                  phx-target={@myself}
                >+ New</a>
              <% end %>
            </div>
          </div>
          <button class="btn btn-ghost btn-xs" phx-click="toggle" phx-target={@myself}>Close</button>
        </div>

        <div class="relative flex-1 overflow-hidden">
          <%= for cs <- @canvas_sessions do %>
            <.live_component
              module={ChatWindowComponent}
              id={"chat-window-#{cs.id}"}
              canvas_session={cs}
            />
          <% end %>
          <%= if @canvas_sessions == [] and @active_canvas_id != nil do %>
            <div class="flex items-center justify-center h-full text-base-content/30 text-sm select-none">
              No sessions -- use "Add to Canvas" on a session card.
            </div>
          <% end %>
        </div>
      </div>
    <% end %>
    </div>
    """
  end

  # --- Helpers ---

  defp toggle_open(socket) do
    if socket.assigns.open do
      unsubscribe_all(socket.assigns.subscribed_session_ids)
      socket |> assign(:open, false) |> assign(:subscribed_session_ids, [])
    else
      socket = socket |> load_canvases() |> assign(:open, true)
      case socket.assigns.canvases do
        [first | _] -> activate_canvas(socket, first.id)
        [] -> socket
      end
    end
  end

  defp load_canvases(socket), do: assign(socket, :canvases, Canvases.list_canvases())

  defp activate_canvas(socket, canvas_id) do
    unsubscribe_all(socket.assigns.subscribed_session_ids)
    sessions = Canvases.list_canvas_sessions(canvas_id)
    session_ids = Enum.map(sessions, & &1.session_id)
    subscribe_all(session_ids)

    sessions =
      sessions
      |> Enum.with_index()
      |> Enum.map(fn {cs, i} ->
        if cs.pos_x == 0 and cs.pos_y == 0,
          do: %{cs | pos_x: 24 + i * 32, pos_y: 16 + i * 32},
          else: cs
      end)

    socket
    |> assign(:active_canvas_id, canvas_id)
    |> assign(:canvas_sessions, sessions)
    |> assign(:subscribed_session_ids, session_ids)
  end

  defp subscribe_all(ids) do
    Enum.each(ids, fn id ->
      Events.subscribe_session(id)
      Events.subscribe_session_status(id)
    end)
  end

  defp unsubscribe_all(ids), do: Enum.each(ids, &unsubscribe_session/1)

  # Uses Events module helpers — never calls Phoenix.PubSub directly (CLAUDE.md rule)
  defp unsubscribe_session(id) do
    Events.unsubscribe_session(id)
    Events.unsubscribe_session_status(id)
  end

  defp refresh_window(socket, session_id) do
    cs = Enum.find(socket.assigns.canvas_sessions, &(&1.session_id == session_id))
    if cs, do: send_update(EyeInTheSkyWeb.Components.ChatWindowComponent, id: "chat-window-#{cs.id}", canvas_session: cs)
    socket
  end
end
