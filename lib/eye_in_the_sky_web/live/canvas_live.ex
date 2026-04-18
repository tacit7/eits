defmodule EyeInTheSkyWeb.CanvasLive do
  use EyeInTheSkyWeb, :live_view

  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]

  alias EyeInTheSky.Canvases
  alias EyeInTheSky.Events
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
     |> assign(:creating_canvas, false)}
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
         |> push_patch(to: ~p"/canvases/#{canvas.id}")}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("create_canvas", _params, socket) do
    {:noreply, assign(socket, :creating_canvas, false)}
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
    cs_id = parse_int(cs_id_str)
    cs = cs_id && Enum.find(socket.assigns.canvas_sessions, &(&1.id == cs_id))

    if cs do
      Canvases.remove_session(socket.assigns.active_canvas_id, cs.session_id)
      unsubscribe_session(cs.session_id)

      {:noreply,
       socket
       |> assign(:canvas_sessions, Enum.reject(socket.assigns.canvas_sessions, &(&1.id == cs_id)))
       |> assign(
         :subscribed_session_ids,
         Enum.reject(socket.assigns.subscribed_session_ids, &(&1 == cs.session_id))
       )}
    else
      {:noreply, socket}
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
    cs = Enum.find(socket.assigns.canvas_sessions, &(&1.id == cs_id))

    if cs do
      Canvases.remove_session(socket.assigns.active_canvas_id, cs.session_id)
      unsubscribe_session(cs.session_id)

      {:noreply,
       socket
       |> assign(:canvas_sessions, Enum.reject(socket.assigns.canvas_sessions, &(&1.id == cs_id)))
       |> assign(
         :subscribed_session_ids,
         Enum.reject(socket.assigns.subscribed_session_ids, &(&1 == cs.session_id))
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-full bg-base-100">
      <div class="flex items-center gap-3 px-4 py-2 border-b border-base-300 bg-base-200/70 shrink-0">
        <span class="text-secondary font-semibold text-sm">Canvas</span>
        <div class="tabs tabs-boxed tabs-xs bg-base-300">
          <%= for canvas <- @canvases do %>
            <a
              class={["tab tab-xs", if(@active_canvas_id == canvas.id, do: "tab-active")]}
              phx-click="switch_tab"
              phx-value-canvas-id={canvas.id}
            >
              {canvas.name}
            </a>
          <% end %>
          <%= if @creating_canvas do %>
            <form phx-submit="create_canvas" class="flex gap-1 ml-1">
              <input
                type="text"
                name="name"
                class="input input-xs w-28 text-base"
                placeholder="Canvas name"
                autofocus
              />
              <button type="submit" class="btn btn-primary btn-sm min-h-[44px]">+</button>
            </form>
          <% else %>
            <a
              class="tab tab-xs text-base-content/40"
              phx-click="start_new_canvas"
            >
              + New
            </a>
          <% end %>
        </div>
      </div>

      <div data-canvas-area class="relative flex-1 overflow-hidden">
        <%= for cs <- @canvas_sessions do %>
          <.live_component
            module={ChatWindowComponent}
            id={"chat-window-#{cs.id}"}
            canvas_session={cs}
          />
        <% end %>
        <%= if @canvas_sessions == [] and not is_nil(@active_canvas_id) do %>
          <div class="flex items-center justify-center h-full text-base-content/30 text-sm select-none">
            No sessions -- use "Add to Canvas" on a session card.
          </div>
        <% end %>
        <%= if @canvases == [] do %>
          <div class="flex flex-col items-center justify-center h-full gap-3 text-base-content/30 text-sm select-none">
            <.icon name="hero-squares-2x2" class="w-8 h-8" />
            <span>No canvases yet. Create one with "+ New" above.</span>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # --- Helpers ---

  defp redirect_to_first_or_stay(socket) do
    canvases = socket.assigns.canvases

    case canvases do
      [first | _] -> push_patch(socket, to: ~p"/canvases/#{first.id}")
      [] -> socket
    end
  end

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
end
