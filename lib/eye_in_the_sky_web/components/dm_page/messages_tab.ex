defmodule EyeInTheSkyWeb.Components.DmPage.MessagesTab do
  @moduledoc false

  use EyeInTheSkyWeb, :html

  alias EyeInTheSkyWeb.Components.DmHelpers
  import EyeInTheSkyWeb.Components.DmHelpers, only: [to_utc_string: 1, parse_body_segments: 1]
  import EyeInTheSkyWeb.Components.DmMessageComponents,
    only: [message_body: 1, message_metrics: 1, message_attachments: 1]

  attr :messages, :list, default: []
  attr :has_more_messages, :boolean, default: false
  attr :stream, :map, default: %{show: false, content: "", tool: nil, thinking: nil}
  attr :session, :map, default: nil
  attr :agent, :map, default: nil
  attr :message_search_query, :string, default: ""
  attr :codex_raw_lines, :list, default: []

  def messages_tab(assigns) do
    ~H"""
    <div class="flex h-full flex-col" id="dm-messages-tab">
      <div class="flex-1 min-h-0 flex flex-col">
        <div
          class="px-4 py-2 overflow-y-auto flex-1 min-h-0"
          id="messages-container"
          phx-hook="AutoScroll"
          data-has-more={if @has_more_messages, do: "true", else: "false"}
          style="scrollbar-width: none; -ms-overflow-style: none; overflow-anchor: none;"
        >
          <%= if @messages == [] do %>
            <div class="flex flex-col items-center justify-center h-full py-20 text-center select-none">
              <.icon name="hero-chat-bubble-left-right" class="w-16 h-16 text-base-content/10 mb-5" />
              <p class="text-base font-medium text-base-content/40">
                {if @agent, do: @agent.name, else: "No messages yet"}
              </p>
              <p class="mt-1.5 text-xs text-base-content/25 max-w-xs">
                <%= if not is_nil(@agent) && not is_nil(@agent.git_worktree_path) do %>
                  <span class="font-mono">{Path.basename(@agent.git_worktree_path)}</span>
                  &nbsp;&mdash;
                  Send a message to start the conversation
                <% end %>
              </p>
            </div>
          <% else %>
            <div class="py-2 flex items-center justify-center gap-3">
              <%= if @has_more_messages do %>
                <button
                  phx-click="load_more_messages"
                  class="text-xs text-base-content/35 hover:text-primary transition-colors"
                  id="load-more-messages"
                >
                  Load older messages
                </button>
              <% end %>
            </div>

            <div class="space-y-1">
              <%= for message <- @messages do %>
                <.message_item message={message} />
              <% end %>
            </div>

            <%!-- Live streaming bubble --%>
            <%= if @stream.show && (@stream.content != "" || @stream.tool || @stream.thinking) do %>
              <div class="py-3 px-2" id="live-stream-bubble">
                <div class="flex items-start gap-2.5">
                  <.stream_provider_avatar session={@session} />
                  <div class="min-w-0 flex-1">
                    <span class="text-[13px] font-semibold text-primary/80">
                      {stream_provider_label(@session)}
                    </span>
                    <%= if @stream.thinking do %>
                      <div class="text-xs text-base-content/30 italic font-mono mt-1 line-clamp-3">
                        {String.slice(@stream.thinking, -200, 200)}
                      </div>
                    <% end %>
                    <%= if @stream.tool do %>
                      <div class="text-xs text-base-content/40 font-mono mt-1">
                        Using {@stream.tool}...
                      </div>
                    <% end %>
                    <%= if @stream.content not in [nil, ""] do %>
                      <div class="mt-1 text-sm text-base-content/60 whitespace-pre-wrap">
                        {String.trim_leading(@stream.content)}
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>
            <%!-- Scroll anchor: keeps list pinned to bottom on resize (keyboard open/close) --%>
            <div id="messages-scroll-anchor" style="height: 1px;"></div>
          <% end %>
        </div>
      </div>
      <%!-- Codex raw JSONL stream panel — only visible for codex sessions with data --%>
      <%= if @codex_raw_lines != [] do %>
        <details class="border-t border-base-300 shrink-0" id="codex-raw-panel">
          <summary class="px-4 py-1.5 text-[10px] font-mono text-base-content/30 cursor-pointer select-none hover:text-base-content/50 flex items-center gap-1.5">
            <.icon name="hero-code-bracket" class="w-3 h-3" />
            raw stream ({length(@codex_raw_lines)} lines)
          </summary>
          <div
            class="h-40 overflow-y-auto bg-base-300/30 px-3 py-2"
            id="codex-raw-lines"
            phx-hook="AutoScroll"
          >
            <%= for line <- Enum.reverse(@codex_raw_lines) do %>
              <div class="font-mono text-[10px] text-base-content/40 leading-relaxed truncate">
                {line}
              </div>
            <% end %>
          </div>
        </details>
      <% end %>
    </div>
    """
  end

  attr :message, :map, required: true

  defp message_item(assigns) do
    role = if assigns.message.sender_role == "user", do: :user, else: :agent
    is_dm = dm_message?(assigns.message)
    stream_type = get_in(assigns.message.metadata || %{}, ["stream_type"])
    segments = parse_body_segments(assigns.message.body)
    body_is_tool_calls = segments != [] and Enum.all?(segments, &match?({:tool_call, _, _}, &1))
    is_tool_event = stream_type in ["tool_result", "tool_use"] or body_is_tool_calls

    assigns =
      assigns
      |> assign(:role, role)
      |> assign(:is_dm, is_dm)
      |> assign(:is_tool_event, is_tool_event)

    ~H"""
    <div
      id={"dm-message-#{@message.id}"}
      phx-mounted={
        JS.transition(
          {"transition-all ease-out duration-200", "opacity-0 translate-y-1",
           "opacity-100 translate-y-0"}
        )
      }
    >
      <%= if @is_tool_event do %>
        <div class="max-w-[70%] px-1 my-0.5">
          <.message_body message={@message} compact={false} />
        </div>
      <% else %>
        <div class={["group flex items-end gap-1.5", @role == :user && "flex-row-reverse"]}>
          <div class={["max-w-[78%] flex flex-col", @role == :user && "items-end"]}>
            <div class={[
              "leading-snug break-words",
              @role == :user &&
                "px-3 py-2 bg-base-200 text-base-content rounded-2xl rounded-br-sm text-sm",
              @role == :user && @is_dm && "border border-primary/20",
              @role == :agent && "py-1 text-base-content/90"
            ]}>
              <.message_body message={@message} compact={false} />
            </div>
            <div :if={@role == :agent} class="flex items-center gap-1.5 mt-0.5 px-1">
              <span
                :if={message_model(@message)}
                class="text-[11px] font-mono px-1.5 py-0.5 rounded bg-base-content/[0.05] text-base-content/35"
              >
                {message_model(@message)}
              </span>
              <span
                :if={message_cost(@message)}
                class="text-[11px] font-mono text-base-content/30"
              >
                ${:erlang.float_to_binary(message_cost(@message) * 1.0, decimals: 4)}
              </span>
            </div>
            <.message_metrics :if={show_message_metrics?(@message)} message={@message} />
            <.message_attachments attachments={@message.attachments || []} />
            <time
              id={"msg-time-#{@message.id}"}
              class="text-[9px] text-base-content/30 mt-0.5 px-1 opacity-0 group-hover:opacity-100 [@media(hover:none)]:opacity-100 transition-opacity duration-150"
              data-utc={to_utc_string(@message.inserted_at)}
              phx-hook="LocalTime"
            />
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp normalize_provider("codex"), do: :codex
  defp normalize_provider(_), do: :claude

  attr :session, :map, default: nil

  defp stream_provider_avatar(assigns) do
    provider = if assigns.session, do: assigns.session.provider, else: "claude"
    assigns = assign(assigns, :provider, normalize_provider(provider))

    ~H"""
    <%= if @provider == :codex do %>
      <img
        src="/images/openai.svg"
        class="w-4 h-4 mt-1 flex-shrink-0 animate-pulse"
        alt="Codex"
        width="16"
        height="16"
        loading="lazy"
      />
    <% else %>
      <img
        src="/images/claude.svg"
        class="w-4 h-4 mt-1 flex-shrink-0 animate-pulse"
        alt="Claude"
        width="16"
        height="16"
        loading="lazy"
      />
    <% end %>
    """
  end

  defp stream_provider_label(nil), do: "Agent"
  defp stream_provider_label(%{provider: "codex"}), do: "Codex"
  defp stream_provider_label(%{provider: "openai"}), do: "Codex"
  defp stream_provider_label(_session), do: "Claude"

  defdelegate dm_message?(msg), to: DmHelpers
  defdelegate message_model(msg), to: DmHelpers
  defdelegate message_cost(msg), to: DmHelpers

  defp show_message_metrics?(message) do
    message.sender_role == "agent" and is_map(message.metadata) and
      not is_nil(message.metadata["total_cost_usd"])
  end

end
