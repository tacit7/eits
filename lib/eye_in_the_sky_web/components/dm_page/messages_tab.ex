defmodule EyeInTheSkyWeb.Components.DmPage.MessagesTab do
  @moduledoc false

  use EyeInTheSkyWeb, :html

  alias EyeInTheSkyWeb.Components.DmPage.MessageToolWidget
  alias EyeInTheSkyWeb.Components.DmHelpers

  attr :messages, :list, default: []
  attr :has_more_messages, :boolean, default: false
  attr :stream, :map, default: %{show: false, content: "", tool: nil, thinking: nil}
  attr :session, :map, default: nil
  attr :agent, :map, default: nil
  attr :message_search_query, :string, default: ""

  def messages_tab(assigns) do
    ~H"""
    <div class="flex h-full flex-col" id="dm-messages-tab">
      <div class="flex-1 min-h-0 flex flex-col">
        <div
          class="px-4 py-2 overflow-y-auto flex-1 min-h-0"
          id="messages-container"
          phx-hook="AutoScroll"
          data-has-more={if @has_more_messages, do: "true", else: "false"}
          style="scrollbar-width: none; -ms-overflow-style: none;"
        >
          <%= if @messages == [] do %>
            <div class="flex flex-col items-center justify-center h-full py-20 text-center select-none">
              <.icon name="hero-chat-bubble-left-right" class="w-16 h-16 text-base-content/10 mb-5" />
              <p class="text-base font-medium text-base-content/40">
                {if @agent, do: @agent.name, else: "No messages yet"}
              </p>
              <p class="mt-1.5 text-xs text-base-content/25 max-w-xs">
                <%= if @agent && @agent.git_worktree_path do %>
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

            <div class="space-y-4">
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
                    <%= if @stream.content != "" do %>
                      <div class="mt-1 text-sm text-base-content/60 whitespace-pre-wrap">
                        {@stream.content}
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>
            <%!-- Scroll anchor: keeps list pinned to bottom on resize (keyboard open/close) --%>
            <div id="messages-scroll-anchor" style="overflow-anchor: auto; height: 1px;"></div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :message, :map, required: true

  defp message_item(assigns) do
    is_user = assigns.message.sender_role == "user"
    is_dm = dm_message?(assigns.message)
    assigns = assign(assigns, :is_user, is_user) |> assign(:is_dm, is_dm)

    ~H"""
    <div
      class={[
        "py-3 px-2 -mx-2 rounded-lg",
        @is_dm && "border-l-2 border-primary/30 pl-3 bg-primary/[0.03]"
      ]}
      id={"dm-message-#{@message.id}"}
      phx-mounted={
        JS.transition(
          {"transition-all ease-out duration-200", "opacity-0 translate-y-1",
           "opacity-100 translate-y-0"}
        )
      }
    >
      <div class="flex items-start gap-2.5">
        <%!-- Sender icon --%>
        <%= if @is_user do %>
          <div class="w-4 h-4 rounded-full mt-1 flex-shrink-0 bg-success/20 flex items-center justify-center">
            <div class="w-1.5 h-1.5 rounded-full bg-success" />
          </div>
        <% else %>
          <img
            src={provider_icon(@message.provider)}
            class={"w-4 h-4 mt-1 flex-shrink-0 #{provider_icon_class(@message.provider)}"}
            alt={@message.provider || "Agent"}
          />
        <% end %>

        <div class="min-w-0 flex-1">
          <div class="flex flex-wrap items-baseline gap-x-2 gap-y-0.5">
            <span class={[
              "text-[13px] font-semibold",
              !@is_user && "text-primary/80",
              @is_user && "text-base-content/70"
            ]}>
              {message_sender_name(@message)}
            </span>
            <%!-- DM badge --%>
            <span
              :if={@is_dm}
              class="inline-flex items-center gap-1 text-[10px] font-mono px-1.5 py-0.5 rounded bg-base-content/[0.05] text-base-content/40 uppercase tracking-wide"
            >
              <.icon name="hero-envelope-mini" class="w-2.5 h-2.5" /> dm
            </span>
            <span
              :if={!@is_user && message_model(@message)}
              class="text-[11px] font-mono px-1.5 py-0.5 rounded bg-base-content/[0.05] text-base-content/35"
            >
              {message_model(@message)}
            </span>
            <span
              :if={!@is_user && message_cost(@message)}
              class="text-[11px] font-mono text-base-content/30"
            >
              ${:erlang.float_to_binary(message_cost(@message) * 1.0, decimals: 4)}
            </span>
            <time
              id={"msg-time-#{@message.id}"}
              class="text-[11px] text-base-content/25"
              data-utc={to_utc_string(@message.inserted_at)}
              phx-hook="LocalTime"
            >
            </time>
          </div>

          <.message_body message={@message} />

          <.message_metrics :if={show_message_metrics?(@message)} message={@message} />
          <.message_attachments attachments={@message.attachments || []} />
        </div>
      </div>
    </div>
    """
  end

  attr :message, :map, required: true

  defp message_metrics(assigns) do
    ~H"""
    <div class="mt-2 flex flex-wrap gap-1.5">
      <%= if @message.metadata["total_cost_usd"] do %>
        <span
          class="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-base-content/[0.04] text-[11px] font-mono tabular-nums text-base-content/40"
          title="Total cost"
        >
          <.icon name="hero-currency-dollar-mini" class="w-3 h-3" />
          {:erlang.float_to_binary(@message.metadata["total_cost_usd"] * 1.0, decimals: 4)}
        </span>
      <% end %>

      <%= if @message.metadata["usage"] && @message.metadata["usage"]["input_tokens"] do %>
        <span
          class="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-base-content/[0.04] text-[11px] font-mono tabular-nums text-base-content/40"
          title="Input tokens"
        >
          {@message.metadata["usage"]["input_tokens"]} in
        </span>
      <% end %>

      <%= if @message.metadata["usage"] && @message.metadata["usage"]["output_tokens"] do %>
        <span
          class="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-base-content/[0.04] text-[11px] font-mono tabular-nums text-base-content/40"
          title="Output tokens"
        >
          {@message.metadata["usage"]["output_tokens"]} out
        </span>
      <% end %>

      <%= if @message.metadata["duration_ms"] do %>
        <span
          class="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-base-content/[0.04] text-[11px] font-mono tabular-nums text-base-content/40"
          title="Duration"
        >
          <.icon name="hero-clock-mini" class="w-3 h-3" />
          {:erlang.float_to_binary(@message.metadata["duration_ms"] * 1.0 / 1000, decimals: 1)}s
        </span>
      <% end %>

      <%= if @message.metadata["num_turns"] do %>
        <span
          class="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-base-content/[0.04] text-[11px] font-mono tabular-nums text-base-content/40"
          title="Number of turns"
        >
          {@message.metadata["num_turns"]} turns
        </span>
      <% end %>
    </div>
    """
  end

  attr :attachments, :list, default: []

  defp message_attachments(assigns) do
    ~H"""
    <%= if @attachments != [] do %>
      <div class="mt-2 space-y-1">
        <%= for attachment <- @attachments do %>
          <div class="flex items-center gap-2 rounded-md bg-base-content/[0.04] px-2.5 py-1.5 text-[11px] font-mono">
            <.icon name="hero-paper-clip" class="h-3 w-3 text-base-content/30" />
            <span class="text-base-content/60">{attachment.original_filename}</span>
            <span class="ml-auto text-base-content/25">{attachment.storage_path}</span>
          </div>
        <% end %>
      </div>
    <% end %>
    """
  end

  attr :message, :map, required: true

  defp message_body(assigns) do
    body =
      if dm_message?(assigns.message),
        do: strip_dm_prefix(assigns.message.body),
        else: assigns.message.body

    segments = parse_body_segments(body)
    thinking = get_in(assigns.message.metadata || %{}, ["thinking"])
    stream_type = get_in(assigns.message.metadata || %{}, ["stream_type"])

    assigns =
      assigns
      |> assign(:segments, segments)
      |> assign(:thinking, thinking)
      |> assign(:stream_type, stream_type)

    ~H"""
    <div class="mt-1 space-y-1.5">
      <details
        :if={@thinking && @thinking != ""}
        class="group rounded border-l-2 border-primary/50 bg-zinc-950/50 overflow-hidden"
      >
        <summary class="flex items-center gap-2 px-2.5 py-1.5 cursor-pointer select-none list-none hover:bg-base-content/[0.04] transition-colors">
          <.icon name="hero-sparkles" class="w-3.5 h-3.5 flex-shrink-0 text-primary/60" />
          <span class="text-[11px] font-mono font-semibold text-primary/60 uppercase tracking-wide">
            Thinking
          </span>
          <.icon
            name="hero-chevron-right"
            class="w-3 h-3 text-base-content/20 ml-auto flex-shrink-0 transition-transform group-open:rotate-90"
          />
        </summary>
        <div class="px-2.5 pb-2 pt-1 border-t border-primary/10">
          <pre class="font-mono text-xs text-base-content/40 whitespace-pre-wrap break-words leading-relaxed">{@thinking}</pre>
        </div>
      </details>
      <%= if @stream_type == "tool_result" do %>
        <.tool_result_body body={@message.body} />
      <% else %>
        <%= for {segment, idx} <- Enum.with_index(@segments) do %>
          <%= case segment do %>
            <% {:tool_call, name, rest} -> %>
              <MessageToolWidget.tool_widget name={name} rest={rest} />
            <% {:text, text} when text != "" -> %>
              <div
                id={"msg-body-#{@message.id}-#{idx}"}
                class="dm-markdown text-sm leading-relaxed text-base-content/85"
                phx-hook="MarkdownMessage"
                data-raw-body={text}
              >
              </div>
            <% _ -> %>
          <% end %>
        <% end %>
      <% end %>
    </div>
    """
  end

  attr :body, :string, default: ""

  defp tool_result_body(assigns) do
    ~H"""
    <details
      open
      class="group rounded-md border border-base-content/8 bg-base-content/[0.025] overflow-hidden"
    >
      <summary class="flex items-center gap-2 px-2.5 py-1.5 cursor-pointer select-none list-none hover:bg-base-content/[0.04] transition-colors">
        <.icon name="hero-code-bracket" class="w-3.5 h-3.5 flex-shrink-0 text-base-content/30" />
        <span class="text-[11px] font-mono font-semibold text-base-content/40 uppercase tracking-wide flex-shrink-0">
          Output
        </span>
        <.icon
          name="hero-chevron-right"
          class="w-3 h-3 text-base-content/20 ml-auto flex-shrink-0 transition-transform group-open:rotate-90"
        />
      </summary>
      <div class="px-2.5 pb-2 pt-1 border-t border-base-content/5">
        <pre class="font-mono text-[10px] text-base-content/55 whitespace-pre-wrap break-all leading-relaxed max-h-64 overflow-y-auto">{@body}</pre>
      </div>
    </details>
    """
  end

  attr :session, :map, default: nil

  defp stream_provider_avatar(assigns) do
    provider = if assigns.session, do: assigns.session.provider, else: "claude"
    assigns = assign(assigns, :provider, provider)

    ~H"""
    <%= if @provider == "codex" do %>
      <img
        src="/images/openai.svg"
        class="w-4 h-4 mt-1 flex-shrink-0 animate-pulse"
        alt="Codex"
      />
    <% else %>
      <img
        src="/images/claude.svg"
        class="w-4 h-4 mt-1 flex-shrink-0 animate-pulse"
        alt="Claude"
      />
    <% end %>
    """
  end

  defp stream_provider_label(nil), do: "Agent"
  defp stream_provider_label(%{provider: "codex"}), do: "Codex"
  defp stream_provider_label(%{provider: "openai"}), do: "Codex"
  defp stream_provider_label(_session), do: "Claude"

  defdelegate dm_message?(msg), to: DmHelpers
  defdelegate message_sender_name(msg), to: DmHelpers
  defdelegate strip_dm_prefix(body), to: DmHelpers
  defdelegate provider_icon(provider), to: DmHelpers
  defdelegate provider_icon_class(provider), to: DmHelpers

  defp message_model(%{metadata: %{"model_usage" => model_usage}}) when is_map(model_usage) do
    case Map.keys(model_usage) do
      [model_id | _] -> format_model_id(model_id)
      _ -> nil
    end
  end

  defp message_model(_), do: nil

  defp message_cost(%{metadata: %{"total_cost_usd" => cost}}) when is_number(cost), do: cost
  defp message_cost(_), do: nil

  defp format_model_id(id) when is_binary(id) do
    cond do
      String.contains?(id, "opus") -> "opus"
      String.contains?(id, "sonnet") -> "sonnet"
      String.contains?(id, "haiku") -> "haiku"
      true -> id |> String.split("-") |> Enum.take(2) |> Enum.join("-")
    end
  end

  defp format_model_id(_), do: nil

  defp show_message_metrics?(message) do
    message.sender_role == "agent" and is_map(message.metadata) and
      not is_nil(message.metadata["total_cost_usd"])
  end

  defp to_utc_string(nil), do: ""
  defp to_utc_string(ts) when is_binary(ts), do: ts
  defp to_utc_string(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp to_utc_string(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt) <> "Z"
  defp to_utc_string(_), do: ""

  defp parse_body_segments(nil), do: [{:text, ""}]

  defp parse_body_segments(body) when is_binary(body) do
    body
    |> String.trim()
    |> String.split(~r/\n\n/, trim: true)
    |> Enum.map(&parse_body_segment/1)
  end

  defp parse_body_segment(text) do
    trimmed = String.trim(text)

    cond do
      # session_reader format: > `ToolName` args...
      match = Regex.run(~r/^> `([^`]+)` ?(.*)/s, trimmed, capture: :all_but_first) ->
        [name, rest] = match
        {:tool_call, name, String.trim(rest)}

      # Tool: ToolName\n{json} format
      match = Regex.run(~r/^Tool: ([^\n]+)\n(.*)/s, trimmed, capture: :all_but_first) ->
        [name, json_rest] = match
        {:tool_call, String.trim(name), String.trim(json_rest)}

      true ->
        {:text, text}
    end
  end
end
