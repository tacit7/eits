defmodule EyeInTheSkyWebWeb.NatsLive.Index do
  use EyeInTheSkyWebWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "nats:events")
    end

    {:ok, assign(socket, messages: [], filter: "")}
  end

  @impl true
  def handle_info({:nats_message, topic, message}, socket) do
    timestamp = DateTime.utc_now()

    # Precompute formatted message and search text to avoid repeated work
    formatted = safe_format_message(message)
    search_text = String.downcase("#{topic} #{formatted}")

    new_message = %{
      topic: to_string(topic),
      message: message,
      formatted: formatted,
      search_text: search_text,
      timestamp: timestamp,
      id: :erlang.unique_integer([:positive])
    }

    # Keep last 100 messages
    messages = [new_message | socket.assigns.messages] |> Enum.take(100)

    {:noreply, assign(socket, messages: messages)}
  end

  @impl true
  def handle_event("filter", %{"filter" => filter}, socket) do
    {:noreply, assign(socket, filter: filter)}
  end

  @impl true
  def handle_event("clear", _params, socket) do
    {:noreply, assign(socket, messages: [], filter: "")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.live_component module={EyeInTheSkyWebWeb.Components.Navbar} id="navbar" />
    <div class="p-6">
      <div class="flex items-center justify-between mb-6">
        <h1 class="text-3xl font-bold">NATS Messages</h1>
        <button
          phx-click="clear"
          class="btn btn-ghost btn-sm"
          title="Clear all messages"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="h-5 w-5"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
            />
          </svg>
          Clear
        </button>
      </div>

      <div class="mb-4">
        <input
          type="text"
          placeholder="Filter messages..."
          value={@filter}
          phx-input="filter"
          phx-debounce="300"
          name="filter"
          class="w-full px-4 py-2 border rounded"
        />
      </div>

      <%= if Enum.empty?(@messages) do %>
        <div class="text-gray-500 text-center py-8">
          No messages received yet. Waiting for NATS events...
        </div>
      <% else %>
        <div class="space-y-4">
          <%= for msg <- filter_messages(@messages, @filter) do %>
            <div id={"msg-#{msg.id}"} class="border rounded p-4 bg-white shadow">
              <div class="flex justify-between mb-2">
                <span class="font-semibold text-blue-600">{msg.topic}</span>
                <span class="text-gray-500 text-sm">
                  {Calendar.strftime(msg.timestamp, "%Y-%m-%d %H:%M:%S")}
                </span>
              </div>
              <pre class="bg-gray-100 p-3 rounded overflow-x-auto text-sm"><%= msg.formatted %></pre>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp filter_messages(messages, "") do
    messages
  end

  defp filter_messages(messages, filter) do
    filter_lower = String.downcase(filter)

    Enum.filter(messages, fn msg ->
      String.contains?(msg.search_text, filter_lower)
    end)
  end

  # Safe formatting that won't crash on non-JSON-encodable values
  defp safe_format_message(message) when is_map(message) do
    case Jason.encode(message, pretty: true) do
      {:ok, json} -> json
      {:error, _} -> inspect(message, pretty: true)
    end
  end

  defp safe_format_message(message) when is_binary(message) do
    case Jason.decode(message) do
      {:ok, decoded} ->
        case Jason.encode(decoded, pretty: true) do
          {:ok, json} -> json
          {:error, _} -> message
        end

      {:error, _} ->
        message
    end
  end

  defp safe_format_message(message) do
    inspect(message, pretty: true)
  end
end
