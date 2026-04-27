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
      data-session-id={@canvas_session.session_id}
      phx-hook="ChatWindowHook"
      style={"position: absolute; left: #{@canvas_session.pos_x}px; top: #{@canvas_session.pos_y}px; width: #{@canvas_session.width}px; height: #{@canvas_session.height}px; resize: both; overflow: auto;"}
      class="bg-base-100 rounded-xl shadow-2xl border border-base-300 flex flex-col"
    >
      <div
        data-drag-handle
        class="flex items-center justify-between px-3 py-2 bg-base-200 border-b border-base-300 rounded-t-xl cursor-move select-none shrink-0"
      >
        <div class="flex items-center gap-2 min-w-0">
          <img
            src={DmHelpers.provider_icon(@session && @session.provider)}
            class={[
              "size-3.5 shrink-0",
              DmHelpers.provider_icon_class(@session && @session.provider),
              @session && @session.status == "working" && "animate-pulse"
            ]}
            alt={(@session && @session.provider) || "agent"}
          />
          <span class="text-xs font-medium truncate">{session_label(@session)}</span>
        </div>
        <div class="flex items-center gap-1.5">
          <button
            data-minimize-btn
            class="size-3 rounded-full bg-warning/70 hover:bg-warning transition-colors shrink-0"
            title="Minimize"
          />
          <button
            data-maximize-btn
            class="size-3 rounded-full bg-success/70 hover:bg-success transition-colors shrink-0"
            title="Maximize"
          />
          <button
            class="size-3 rounded-full bg-error/70 hover:bg-error transition-colors shrink-0"
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
            <div class="space-y-1">
              <%= for message <- @messages do %>
                <.message_item message={message} cs_id={@canvas_session.id} agent_name={session_label(@session)} />
              <% end %>
            </div>
          <% end %>
          <%= if @session && @session.status == "working" do %>
            <div class="flex items-center gap-1.5 px-1 pt-2 pb-1">
              <img
                src={DmHelpers.provider_icon(@session.provider)}
                class={["size-4 shrink-0", DmHelpers.provider_icon_class(@session.provider), "animate-pulse"]}
                alt="working"
              />
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
            <.icon name="hero-arrow-down-mini" class="size-3.5" />
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
  attr :agent_name, :string, required: true

  defp message_item(assigns) do
    role = if assigns.message.sender_role == "user", do: :user, else: :agent
    is_dm = DmHelpers.dm_message?(assigns.message)
    stream_type = get_in(assigns.message.metadata || %{}, ["stream_type"])

    # Tool events: explicit stream_type OR body that parses entirely as tool calls
    segments = DmHelpers.parse_body_segments(assigns.message.body)
    body_is_tool_calls = segments != [] and Enum.all?(segments, &match?({:tool_call, _, _}, &1))
    is_tool_event = stream_type in ["tool_result", "tool_use"] or body_is_tool_calls

    assigns =
      assign(assigns, :role, role)
      |> assign(:is_dm, is_dm)
      |> assign(:is_tool_event, is_tool_event)

    ~H"""
    <div id={"chat-msg-#{@cs_id}-#{@message.id}"} class="mb-1">
      <%= if @is_tool_event do %>
        <div class="max-w-[70%] px-1 my-0.5">
          <DmMessageComponents.message_body message={@message} compact={true} extra_id={@cs_id} />
        </div>
      <% else %>
        <div class={["group flex items-end gap-1.5", @role == :user && "flex-row-reverse"]}>
          <div class={["max-w-[78%] flex flex-col", @role == :user && "items-end"]}>
            <div class={[
              "text-sm leading-snug break-words",
              @role == :user && "px-3 py-2 bg-base-200 text-base-content rounded-2xl rounded-br-sm",
              @role == :agent && "py-1 text-base-content/90",
              @is_dm && @role == :user && "border border-primary/20"
            ]}>
              <DmMessageComponents.message_body message={@message} compact={true} extra_id={@cs_id} />
            </div>
            <time
              id={"msg-time-#{@cs_id}-#{@message.id}"}
              class="text-[9px] text-base-content/30 mt-0.5 px-1 opacity-0 group-hover:opacity-100 transition-opacity duration-150"
              data-utc={to_utc_string(@message.inserted_at)}
              phx-hook="LocalTime"
            />
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp session_label(nil), do: "Unknown session"
  defp session_label(%{name: name}) when is_binary(name) and name != "", do: name
  defp session_label(%{uuid: uuid}), do: String.slice(uuid, 0, 8)
end
