defmodule EyeInTheSkyWeb.Components.ChatWindowComponent do
  @moduledoc false
  use EyeInTheSkyWeb, :live_component

  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]
  import EyeInTheSkyWeb.Components.DmHelpers, only: [to_utc_string: 1]

  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSky.{Messages, Sessions}
  alias EyeInTheSkyWeb.Components.DmHelpers
  alias EyeInTheSkyWeb.Components.DmPage.MessageToolWidget

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
     |> assign(:messages, messages)
     |> push_event("messages-updated-" <> to_string(cs.id), %{})}
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

      <div
        data-chat-body
        class="flex-1 overflow-y-auto px-2 py-2 min-h-0"
        id={"chat-messages-#{@canvas_session.id}"}
        phx-hook="AutoScroll"
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

      <div data-chat-footer class="shrink-0 border-t border-base-300">
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
        messages = Messages.list_recent_messages(session_id, 50)
        {:noreply, assign(socket, :messages, messages)}

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
          <.chat_message_body message={@message} cs_id={@cs_id} />
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
            <.chat_message_body message={@message} cs_id={@cs_id} />
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  attr :message, :map, required: true
  attr :cs_id, :integer, required: true

  defp chat_message_body(assigns) do
    body =
      if DmHelpers.dm_message?(assigns.message),
        do: DmHelpers.strip_dm_prefix(assigns.message.body),
        else: assigns.message.body

    segments = DmHelpers.parse_body_segments(body)
    thinking = get_in(assigns.message.metadata || %{}, ["thinking"])
    stream_type = get_in(assigns.message.metadata || %{}, ["stream_type"])

    assigns =
      assigns
      |> assign(:segments, segments)
      |> assign(:thinking, thinking)
      |> assign(:stream_type, stream_type)
      |> assign(:body, body)

    ~H"""
    <div class={["space-y-1", @stream_type != "tool_result" && "mt-0.5"]}>
      <details
        :if={not is_nil(@thinking) && @thinking != ""}
        class="group rounded border-l-2 border-primary/50 bg-zinc-950/50 overflow-hidden"
      >
        <summary class="flex items-center gap-1.5 px-2 py-1 cursor-pointer select-none list-none hover:bg-base-content/[0.04] transition-colors">
          <.icon name="hero-sparkles" class="w-3 h-3 flex-shrink-0 text-primary/60" />
          <span class="text-[10px] font-mono font-semibold text-primary/60 uppercase tracking-wide">
            Thinking
          </span>
          <.icon
            name="hero-chevron-right"
            class="w-2.5 h-2.5 text-base-content/20 ml-auto flex-shrink-0 transition-transform group-open:rotate-90"
          />
        </summary>
        <div class="px-2 pb-1.5 pt-1 border-t border-primary/10">
          <pre class="font-mono text-[10px] text-base-content/40 whitespace-pre-wrap break-words leading-relaxed">{@thinking}</pre>
        </div>
      </details>
      <%= if @stream_type == "tool_result" do %>
        <.chat_tool_result_body body={@body} />
      <% else %>
        <%= for {segment, idx} <- Enum.with_index(@segments) do %>
          <%= case segment do %>
            <% {:tool_call, name, rest} -> %>
              <MessageToolWidget.tool_widget name={name} rest={rest} />
            <% {:text, text} when text != "" -> %>
              <div
                id={"msg-body-#{@cs_id}-#{@message.id}-#{idx}"}
                class="dm-markdown text-xs leading-relaxed text-base-content/85"
                phx-hook="MarkdownMessage"
                data-raw-body={text}
              />
            <% _ -> %>
          <% end %>
        <% end %>
      <% end %>
    </div>
    """
  end

  attr :body, :string, default: ""

  defp chat_tool_result_body(assigns) do
    ~H"""
    <details class="group rounded-md border border-base-content/8 bg-base-content/[0.025] overflow-hidden">
      <summary class="flex items-center gap-1.5 px-2 py-1 cursor-pointer select-none list-none hover:bg-base-content/[0.04] transition-colors">
        <.icon name="hero-code-bracket" class="w-3 h-3 flex-shrink-0 text-base-content/30" />
        <span class="text-[10px] font-mono font-semibold text-base-content/40 uppercase tracking-wide flex-shrink-0">
          Output
        </span>
        <button
          class="tool-copy-btn ml-auto mr-1 shrink-0"
          data-copy-btn
          data-copy-text={@body}
          title="Copy output"
        >
          <.icon name="hero-clipboard-document" class="w-3 h-3" />
        </button>
        <.icon
          name="hero-chevron-right"
          class="w-2.5 h-2.5 text-base-content/20 shrink-0 transition-transform group-open:rotate-90"
        />
      </summary>
      <div class="px-2 pb-1.5 pt-1 border-t border-base-content/5">
        <pre class="font-mono text-[10px] text-base-content/55 whitespace-pre-wrap break-all leading-relaxed max-h-40 overflow-y-auto">{@body}</pre>
      </div>
    </details>
    """
  end

  defp status_dot_class(nil), do: "bg-base-content/20"
  defp status_dot_class(%{status: "working"}), do: "bg-success animate-pulse"
  defp status_dot_class(%{status: "waiting"}), do: "bg-warning"
  defp status_dot_class(_), do: "bg-base-content/30"

  defp session_label(nil), do: "Unknown session"
  defp session_label(%{name: name}) when is_binary(name) and name != "", do: name
  defp session_label(%{uuid: uuid}), do: String.slice(uuid, 0, 8)
end
