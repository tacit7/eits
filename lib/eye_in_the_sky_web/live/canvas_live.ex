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
     |> assign(:creating_canvas, false)
     |> assign(:renaming_canvas_id, nil)
     |> assign(:canvas_session_counts, Canvases.count_sessions_per_canvas())}
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
       )
       |> assign(:canvas_session_counts, Canvases.count_sessions_per_canvas())}
    else
      {:noreply, socket}
    end
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
       )
       |> assign(:canvas_session_counts, Canvases.count_sessions_per_canvas())}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:canvas_session_added, _payload}, socket) do
    new_sessions = Canvases.list_canvas_sessions(socket.assigns.active_canvas_id || -1)
    existing_ids = Enum.map(socket.assigns.canvas_sessions, & &1.id)

    added =
      Enum.reject(new_sessions, &(&1.id in existing_ids))
      |> Enum.with_index(length(socket.assigns.canvas_sessions))
      |> Enum.map(fn {cs, i} ->
        if cs.pos_x == 0 and cs.pos_y == 0 and cs.width == 320 and cs.height == 260,
          do: %{cs | pos_x: 24 + i * 32, pos_y: 16 + i * 32},
          else: cs
      end)

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
      <div role="tablist" class="tabs tabs-border px-2 border-b border-base-300 bg-base-200/70 shrink-0">
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

    sessions =
      sessions
      |> Enum.with_index()
      |> Enum.map(fn {cs, i} ->
        if cs.pos_x == 0 and cs.pos_y == 0 and cs.width == 320 and cs.height == 260,
          do: %{cs | pos_x: 24 + i * 32, pos_y: 16 + i * 32},
          else: cs
      end)

    socket
    |> assign(:page_title, canvas_name <> " — Canvas")
    |> assign(:active_canvas_id, canvas_id)
    |> assign(:canvas_sessions, sessions)
    |> assign(:subscribed_session_ids, session_ids)
    |> assign(:canvas_session_counts, Canvases.count_sessions_per_canvas())
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
