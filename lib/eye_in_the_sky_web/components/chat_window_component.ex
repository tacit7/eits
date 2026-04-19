defmodule EyeInTheSkyWeb.Components.ChatWindowComponent do
  @moduledoc false
  use EyeInTheSkyWeb, :live_component

  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]
  import EyeInTheSkyWeb.Components.DmHelpers, only: [to_utc_string: 1]

  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSky.{Messages, Sessions}
  alias EyeInTheSkyWeb.Components.DmHelpers
  alias EyeInTheSkyWeb.Components.DmMessageComponents

  @impl true
  def update(%{canvas_session: cs} = assigns, socket) do
    session =
      case Sessions.get_session(cs.session_id) do
        {:ok, s} -> s
        {:error, _} -> nil
      end

    messages = if session, do: Messages.list_recent_messages(cs.session_id, 50), else: []

    prev_messages = socket.assigns[:messages] || []
    prev_count = length(prev_messages)
    prev_last_id = prev_messages |> List.last() |> then(& &1 && &1.id)
    new_last_id = List.last(messages) |> then(& &1 && &1.id)
    messages_changed = length(messages) != prev_count || new_last_id != prev_last_id

    socket =
      socket
      |> assign(assigns)
      |> assign(:session, session)
      |> assign(:messages, messages)

    socket = if messages_changed, do: push_event(socket, "messages-updated-" <> to_string(cs.id), %{}), else: socket

    {:ok, socket}
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
        <div class="flex items-center gap-1.5">
          <button
            data-minimize-btn
            class="w-3 h-3 rounded-full bg-warning/70 hover:bg-warning transition-colors shrink-0"
            title="Minimize"
          />
          <button
            data-maximize-btn
            class="w-3 h-3 rounded-full bg-success/70 hover:bg-success transition-colors shrink-0"
            title="Maximize"
          />
          <button
            class="w-3 h-3 rounded-full bg-error/70 hover:bg-error transition-colors shrink-0"
            phx-click="remove_window"
            phx-value-cs-id={@canvas_session.id}
            phx-target={@myself}
            title="Remove from canvas"
          >
          </button>
        </div>
      </div>

      <div class="flex-1 relative min-h-0">
        <div
          data-chat-body
          class="absolute inset-0 overflow-y-auto px-2 py-2"
          id={"chat-messages-#{@canvas_session.id}"}
          style="scrollbar-width: none; -ms-overflow-style: none;"
        >
          <%= if @messages == [] do %>
            <div class="flex items-center justify-center h-full text-xs text-base-content/30">
              No messages yet
            </div>
          <% else %>
            <div class="space-y-2">
              <%= for message <- @messages do %>
                <.message_item message={message} cs_id={@canvas_session.id} />
              <% end %>
            </div>
          <% end %>
        </div>
        <div
          data-new-msg-pill
          class="hidden absolute bottom-2 left-1/2 -translate-x-1/2 whitespace-nowrap bg-primary text-primary-content text-[10px] font-medium px-2 py-0.5 rounded-full cursor-pointer shadow-md z-10"
        >
          &darr; new messages
        </div>
      </div>

      <div data-chat-footer class="shrink-0 border-t border-base-300">
        <.form for={%{}} phx-submit="send_message" phx-target={@myself} class="flex gap-1 p-1.5">
          <input
            type="text"
            name="body"
            class="input input-xs flex-1 bg-base-200 text-base"
            placeholder="Message..."
            autocomplete="off"
          />
          <button
            data-autoscroll-btn
            type="button"
            title="Auto-scroll"
            class="btn btn-ghost btn-xs px-1 text-base-content/30 hover:text-base-content"
          >
            <.icon name="hero-arrow-down-mini" class="w-3.5 h-3.5" />
          </button>
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
        messages = Messages.list_recent_messages(session_id, 50)
        cs_id = socket.assigns.canvas_session.id

        socket =
          socket
          |> assign(:messages, messages)
          |> push_event("messages-updated-" <> to_string(cs_id), %{})

        {:noreply, socket}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("remove_window", %{"cs-id" => cs_id}, socket) do
    if id = parse_int(cs_id) do
      send(self(), {:remove_canvas_window, id})
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

  attr :message, :map, required: true
  attr :cs_id, :integer, required: true

  defp message_item(assigns) do
    role = if assigns.message.sender_role == "user", do: :user, else: :agent
    is_dm = DmHelpers.dm_message?(assigns.message)
    stream_type = get_in(assigns.message.metadata || %{}, ["stream_type"])
    is_tool_result = stream_type == "tool_result"

    assigns =
      assign(assigns, :role, role)
      |> assign(:is_dm, is_dm)
      |> assign(:is_tool_result, is_tool_result)

    ~H"""
    <div
      class={[
        "px-1.5 -mx-1.5 rounded-lg",
        @is_tool_result && "py-0.5",
        !@is_tool_result && "py-2",
        @is_dm && "border-l-2 border-primary/30 pl-2 bg-primary/[0.03]"
      ]}
      id={"chat-msg-#{@cs_id}-#{@message.id}"}
    >
      <%= if @is_tool_result do %>
        <div class="pl-[22px]">
          <DmMessageComponents.message_body message={@message} compact={true} extra_id={@cs_id} />
        </div>
      <% else %>
        <div class="flex items-start gap-2">
          <%= if @role == :user do %>
            <div class="w-3.5 h-3.5 rounded-full mt-0.5 flex-shrink-0 bg-success/20 flex items-center justify-center">
              <div class="w-1 h-1 rounded-full bg-success" />
            </div>
          <% else %>
            <img
              src={DmHelpers.provider_icon(@message.provider)}
              class={"w-3.5 h-3.5 mt-0.5 flex-shrink-0 #{DmHelpers.provider_icon_class(@message.provider)}"}
              alt={@message.provider || "Agent"}
              width="14"
              height="14"
              loading="lazy"
            />
          <% end %>

          <div class="min-w-0 flex-1">
            <div class="flex flex-wrap items-baseline gap-x-1.5 gap-y-0.5">
              <span class={[
                "text-[11px] font-semibold",
                @role == :agent && "text-primary/80",
                @role == :user && "text-base-content/70"
              ]}>
                {DmHelpers.message_sender_name(@message)}
              </span>
              <span
                :if={@role == :agent && DmHelpers.message_model(@message)}
                class="text-[10px] font-mono px-1 py-0 rounded bg-base-content/[0.05] text-base-content/35"
              >
                {DmHelpers.message_model(@message)}
              </span>
              <time
                id={"msg-time-#{@cs_id}-#{@message.id}"}
                class="text-[10px] text-base-content/25"
                data-utc={to_utc_string(@message.inserted_at)}
                phx-hook="LocalTime"
              />
            </div>
            <DmMessageComponents.message_body message={@message} compact={true} extra_id={@cs_id} />
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp status_dot_class(nil), do: "bg-base-content/20"
  defp status_dot_class(%{status: "working"}), do: "bg-primary animate-pulse"
  defp status_dot_class(%{status: "waiting"}), do: "bg-warning"
  defp status_dot_class(%{status: "failed"}), do: "bg-error"
  defp status_dot_class(%{status: "completed"}), do: "bg-success"
  defp status_dot_class(_), do: "bg-base-content/20"

  defp session_label(nil), do: "Unknown session"
  defp session_label(%{name: name}) when is_binary(name) and name != "", do: name
  defp session_label(%{uuid: uuid}), do: String.slice(uuid, 0, 8)
end
