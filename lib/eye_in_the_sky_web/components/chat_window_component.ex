defmodule EyeInTheSkyWeb.Components.ChatWindowComponent do
  @moduledoc false
  use EyeInTheSkyWeb, :live_component

  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]

  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSky.{Messages, Sessions}

  @impl true
  def update(%{canvas_session: cs} = assigns, socket) do
    session =
      case Sessions.get_session(cs.session_id) do
        {:ok, s} -> s
        {:error, _} -> nil
      end

    messages = if session, do: Messages.list_recent_messages(cs.session_id, 50), else: []

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:session, session)
     |> assign(:messages, messages)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={"chat-window-#{@canvas_session.id}"}
      data-chat-window
      data-cs-id={@canvas_session.id}
      phx-hook="ChatWindowHook"
      style={"position: absolute; left: #{@canvas_session.pos_x}px; top: #{@canvas_session.pos_y}px; width: #{@canvas_session.width}px; height: #{@canvas_session.height}px; resize: both; overflow: auto; z-index: 1;"}
      class="bg-base-100 rounded-xl shadow-2xl border border-base-300 flex flex-col"
    >
      <div
        data-drag-handle
        class="flex items-center justify-between px-3 py-2 bg-base-200 border-b border-base-300 rounded-t-xl cursor-move select-none shrink-0"
      >
        <div class="flex items-center gap-2 min-w-0">
          <span class={["w-2 h-2 rounded-full inline-block shrink-0", status_dot_class(@session)]}>
          </span>
          <span class="text-xs font-medium truncate">{session_label(@session)}</span>
        </div>
        <button
          class="w-3 h-3 rounded-full bg-error/70 hover:bg-error transition-colors shrink-0"
          phx-click="remove_window"
          phx-value-cs-id={@canvas_session.id}
          phx-target={@myself}
          title="Remove from canvas"
        >
        </button>
      </div>

      <div class="flex-1 overflow-y-auto p-2 space-y-1.5 text-xs min-h-0">
        <%= for msg <- @messages do %>
          <div class={if msg.sender_role == "user", do: "chat chat-end", else: "chat chat-start"}>
            <div class={[
              "chat-bubble text-xs py-1 px-2",
              if(msg.sender_role == "user", do: "chat-bubble-primary", else: "bg-base-200")
            ]}>
              {msg.body}
            </div>
          </div>
        <% end %>
      </div>

      <div class="shrink-0 border-t border-base-300">
        <.form for={%{}} phx-submit="send_message" phx-target={@myself} class="flex gap-1 p-1.5">
          <input
            type="text"
            name="body"
            class="input input-xs flex-1 bg-base-200 text-base"
            placeholder="Message..."
            autocomplete="off"
          />
          <button type="submit" class="btn btn-primary btn-xs px-2">&#8593;</button>
        </.form>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("send_message", %{"body" => ""}, socket), do: {:noreply, socket}

  def handle_event("send_message", %{"body" => body}, socket) do
    session_id = socket.assigns.canvas_session.session_id
    provider = if(socket.assigns.session, do: socket.assigns.session.provider) || "claude"

    case Messages.send_message(%{
           session_id: session_id,
           sender_role: "user",
           recipient_role: "agent",
           provider: provider,
           body: body
         }) do
      {:ok, _} ->
        AgentManager.continue_session(session_id, body, [])
        {:noreply, socket}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("remove_window", %{"cs-id" => cs_id}, socket) do
    if id = parse_int(cs_id) do
      send_update(EyeInTheSkyWeb.Components.CanvasOverlayComponent,
        id: "canvas-overlay",
        action: :remove_window,
        canvas_session_id: id
      )
    end

    {:noreply, socket}
  end

  def handle_event("window_moved", %{"id" => cs_id, "x" => x, "y" => y}, socket) do
    if id = parse_int(cs_id),
      do: EyeInTheSky.Canvases.update_window_layout(id, %{pos_x: x, pos_y: y})

    {:noreply, socket}
  end

  def handle_event("window_resized", %{"id" => cs_id, "w" => w, "h" => h}, socket) do
    if id = parse_int(cs_id),
      do: EyeInTheSky.Canvases.update_window_layout(id, %{width: w, height: h})

    {:noreply, socket}
  end

  defp status_dot_class(nil), do: "bg-base-content/20"
  defp status_dot_class(%{status: "working"}), do: "bg-success"
  defp status_dot_class(%{status: "waiting"}), do: "bg-warning"
  defp status_dot_class(_), do: "bg-base-content/30"

  defp session_label(nil), do: "Unknown session"
  defp session_label(%{name: name}) when is_binary(name) and name != "", do: name
  defp session_label(%{uuid: uuid}), do: String.slice(uuid, 0, 8)
end
