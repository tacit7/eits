defmodule EyeInTheSkyWebWeb.Components.DmPage.MessagesTab do
  @moduledoc false

  use EyeInTheSkyWebWeb, :html

  attr :messages, :list, default: []
  attr :has_more_messages, :boolean, default: false
  attr :show_live_stream, :boolean, default: false
  attr :stream_content, :string, default: ""
  attr :stream_tool, :string, default: nil
  attr :stream_thinking, :string, default: nil
  attr :session, :map, default: nil
  attr :agent, :map, default: nil
  attr :message_search_query, :string, default: ""

  def messages_tab(assigns) do
    ~H"""
    <div class="flex h-full flex-col" id="dm-messages-tab">
      <div class="flex-1 min-h-0 flex flex-col">
        <%!-- Search bar --%>
        <div class="px-4 pt-2 pb-1 flex-shrink-0">
          <form phx-change="search_messages" phx-submit="search_messages" class="relative">
            <.icon
              name="hero-magnifying-glass"
              class="absolute left-2.5 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-base-content/30 pointer-events-none"
            />
            <input
              type="text"
              name="query"
              value={@message_search_query}
              placeholder="Search messages..."
              autocomplete="off"
              phx-debounce="300"
              class="w-full pl-8 pr-7 py-1.5 text-xs rounded-lg bg-base-content/[0.05] border border-base-content/8 focus:outline-none focus:ring-1 focus:ring-primary/30 focus:border-primary/30 placeholder:text-base-content/25 text-base-content/70 transition-colors"
            />
            <%= if @message_search_query != "" do %>
              <button
                type="button"
                phx-click="search_messages"
                phx-value-query=""
                class="absolute right-2 top-1/2 -translate-y-1/2 text-base-content/30 hover:text-base-content/60 transition-colors"
              >
                <.icon name="hero-x-mark" class="w-3.5 h-3.5" />
              </button>
            <% end %>
          </form>
          <%= if @message_search_query != "" do %>
            <p class="mt-1 text-[10px] text-base-content/30">
              {length(@messages)} result{if length(@messages) == 1, do: "", else: "s"}
            </p>
          <% end %>
        </div>

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
            <%= if @show_live_stream && (@stream_content != "" || @stream_tool || @stream_thinking) do %>
              <div class="py-3 px-2" id="live-stream-bubble">
                <div class="flex items-start gap-2.5">
                  <.stream_provider_avatar session={@session} />
                  <div class="min-w-0 flex-1">
                    <span class="text-[13px] font-semibold text-primary/80">
                      {stream_provider_label(@session)}
                    </span>
                    <%= if @stream_thinking do %>
                      <div class="text-xs text-base-content/30 italic font-mono mt-1 line-clamp-3">
                        {String.slice(@stream_thinking, -200, 200)}
                      </div>
                    <% end %>
                    <%= if @stream_tool do %>
                      <div class="text-xs text-base-content/40 font-mono mt-1">
                        Using {@stream_tool}...
                      </div>
                    <% end %>
                    <%= if @stream_content != "" do %>
                      <div class="mt-1 text-sm text-base-content/60 whitespace-pre-wrap">
                        {@stream_content}
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
        "py-3 px-2 -mx-2 rounded-lg opacity-0",
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
        class="group rounded border-l-2 border-purple-500/50 bg-zinc-950/50 overflow-hidden"
      >
        <summary class="flex items-center gap-2 px-2.5 py-1.5 cursor-pointer select-none list-none hover:bg-base-content/[0.04] transition-colors">
          <.icon name="hero-sparkles" class="w-3.5 h-3.5 flex-shrink-0 text-purple-400/60" />
          <span class="text-[11px] font-mono font-semibold text-purple-400/60 uppercase tracking-wide">
            Thinking
          </span>
          <.icon
            name="hero-chevron-right"
            class="w-3 h-3 text-base-content/20 ml-auto flex-shrink-0 transition-transform group-open:rotate-90"
          />
        </summary>
        <div class="px-2.5 pb-2 pt-1 border-t border-purple-500/10">
          <pre class="font-mono text-xs text-base-content/40 whitespace-pre-wrap break-words leading-relaxed">{@thinking}</pre>
        </div>
      </details>
      <%= if @stream_type == "tool_result" do %>
        <.tool_result_body body={@message.body} />
      <% else %>
        <%= for {segment, idx} <- Enum.with_index(@segments) do %>
          <%= case segment do %>
            <% {:tool_call, name, rest} -> %>
              <.tool_widget name={name} rest={rest} />
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

  attr :name, :string, required: true
  attr :rest, :string, required: true

  defp tool_widget(assigns) do
    {icon, label, detail} = tool_widget_meta(assigns.name, assigns.rest)

    input =
      case Jason.decode(assigns.rest) do
        {:ok, map} when is_map(map) -> map
        _ -> nil
      end

    wrap_detail = label == "i-speak"

    assigns =
      assigns
      |> assign(:icon, icon)
      |> assign(:label, label)
      |> assign(:detail, detail)
      |> assign(:input, input)
      |> assign(:wrap_detail, wrap_detail)

    ~H"""
    <details class="group rounded-md border border-base-content/8 bg-base-content/[0.025] overflow-hidden">
      <summary class="flex items-center gap-2 px-2.5 py-1.5 cursor-pointer select-none list-none hover:bg-base-content/[0.04] transition-colors">
        <.icon name={@icon} class="w-3.5 h-3.5 flex-shrink-0 text-base-content/35" />
        <span class="text-[11px] font-mono font-semibold text-base-content/45 uppercase tracking-wide flex-shrink-0">
          {@label}
        </span>
        <span
          :if={@detail != "" && !@wrap_detail}
          class="text-[11px] font-mono text-base-content/35 truncate flex-1 min-w-0"
        >
          {@detail}
        </span>
        <.icon
          name="hero-chevron-right"
          class="w-3 h-3 text-base-content/20 ml-auto flex-shrink-0 transition-transform group-open:rotate-90"
        />
      </summary>
      <.tool_widget_body name={@name} rest={@rest} detail={@detail} input={@input} />
    </details>
    """
  end

  attr :name, :string, required: true
  attr :rest, :string, required: true
  attr :detail, :string, required: true
  attr :input, :any, default: nil

  defp tool_widget_body(assigns) do
    body_type =
      cond do
        assigns.name == "Bash" and assigns.rest != "" ->
          :bash

        assigns.name == "Edit" and is_map(assigns.input) and
            Map.has_key?(assigns.input, "old_string") ->
          :edit

        assigns.name == "Write" and is_map(assigns.input) and
            Map.has_key?(assigns.input, "content") ->
          :write

        String.ends_with?(assigns.name, "i-speak") and assigns.detail != "" ->
          :speak

        is_map(assigns.input) and map_size(assigns.input) > 0 and
            assigns.name not in ["Read", "Glob", "Grep", "WebSearch", "Task"] ->
          :json

        assigns.rest != "" and assigns.rest != assigns.detail ->
          :text

        true ->
          :none
      end

    assigns = assign(assigns, :body_type, body_type)

    ~H"""
    <%= case @body_type do %>
      <% :bash -> %>
        <div class="px-2.5 pb-2 pt-1 border-t border-base-content/5">
          <pre class="bg-base-200 rounded px-2 py-1.5 font-mono text-[10px] text-base-content/70 whitespace-pre-wrap break-all leading-relaxed">{(@input && @input["command"]) || @detail}</pre>
        </div>
      <% :edit -> %>
        <div class="px-2.5 pb-2 pt-1 border-t border-base-content/5 space-y-1.5">
          <div class="font-mono text-[10px] text-base-content/40 pb-0.5">{@input["file_path"]}</div>
          <pre class="bg-red-950/30 text-red-400/70 rounded px-2 py-1 font-mono text-[10px] whitespace-pre-wrap break-all leading-relaxed max-h-32 overflow-y-auto">{String.slice(@input["old_string"] || "", 0..500)}</pre>
          <pre class="bg-green-950/30 text-green-400/70 rounded px-2 py-1 font-mono text-[10px] whitespace-pre-wrap break-all leading-relaxed max-h-32 overflow-y-auto">{String.slice(@input["new_string"] || "", 0..500)}</pre>
        </div>
      <% :write -> %>
        <div class="px-2.5 pb-2 pt-1 border-t border-base-content/5 space-y-1">
          <div class="font-mono text-[10px] text-base-content/40 pb-0.5">{@input["file_path"]}</div>
          <pre class="bg-base-200 rounded px-2 py-1.5 font-mono text-[10px] text-base-content/55 whitespace-pre-wrap break-all leading-relaxed max-h-48 overflow-y-auto">{String.slice(@input["content"] || "", 0..500)}{if String.length(@input["content"] || "") > 500, do: "\n…", else: ""}</pre>
        </div>
      <% :speak -> %>
        <div class="px-2.5 pb-2 pt-1 border-t border-base-content/5">
          <pre class="bg-base-200 rounded px-2 py-1.5 text-[11px] text-base-content/70 whitespace-pre-wrap break-all leading-relaxed">{@detail}</pre>
        </div>
      <% :json -> %>
        <div class="px-2.5 pb-2 pt-1 border-t border-base-content/5">
          <pre class="font-mono text-[10px] text-base-content/40 whitespace-pre-wrap break-all leading-relaxed max-h-40 overflow-y-auto">{Jason.encode!(@input, pretty: true)}</pre>
        </div>
      <% :text -> %>
        <div class="px-2.5 pb-2 pt-1 border-t border-base-content/5">
          <pre class="font-mono text-[10px] text-base-content/45 whitespace-pre-wrap break-all leading-relaxed">{@rest}</pre>
        </div>
      <% :none -> %>
    <% end %>
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

  defp dm_message?(%{from_session_id: id}) when is_integer(id), do: true

  defp dm_message?(%{metadata: %{"from_session_uuid" => uuid}})
       when is_binary(uuid) and uuid != "",
       do: true

  defp dm_message?(_), do: false

  defp message_sender_name(%{sender_role: "user"}), do: "You"

  defp message_sender_name(%{metadata: %{"sender_name" => name}} = _msg)
       when is_binary(name) and name != "" do
    name
  end

  defp message_sender_name(%{from_session_id: id}) when is_integer(id) do
    "session:#{id}"
  end

  defp message_sender_name(message), do: message.provider || "Agent"

  defp strip_dm_prefix(body) when is_binary(body) do
    case Regex.run(~r/^DM from:[^\(]+\(session:[^\)]+\) (.+)$/s, body) do
      [_, content] -> content
      _ -> body
    end
  end

  defp strip_dm_prefix(body), do: body

  defp provider_icon("openai"), do: "/images/openai.svg"
  defp provider_icon("codex"), do: "/images/openai.svg"
  defp provider_icon(_), do: "/images/claude.svg"

  defp provider_icon_class("openai"), do: "dark:invert"
  defp provider_icon_class("codex"), do: "dark:invert"
  defp provider_icon_class(_), do: ""

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

  defp tool_widget_meta("Bash", rest) do
    command =
      with {:ok, %{"command" => cmd}} <- Jason.decode(rest) do
        cmd
      else
        _ ->
          case Regex.run(~r/^`(.+?)`/s, rest, capture: :all_but_first) do
            [cmd] -> cmd
            _ -> rest
          end
      end

    {"hero-command-line", "Bash", command}
  end

  defp tool_widget_meta("Read", rest) do
    path = with {:ok, %{"file_path" => p}} <- Jason.decode(rest), do: p, else: (_ -> rest)
    {"hero-document-text", "Read", path}
  end

  defp tool_widget_meta("Write", rest) do
    path = with {:ok, %{"file_path" => p}} <- Jason.decode(rest), do: p, else: (_ -> rest)
    {"hero-pencil-square", "Write", path}
  end

  defp tool_widget_meta("Edit", rest) do
    path = with {:ok, %{"file_path" => p}} <- Jason.decode(rest), do: p, else: (_ -> rest)
    {"hero-pencil-square", "Edit", path}
  end

  defp tool_widget_meta("Glob", rest) do
    pat = with {:ok, %{"pattern" => p}} <- Jason.decode(rest), do: p, else: (_ -> rest)
    {"hero-folder-open", "Glob", pat}
  end

  defp tool_widget_meta("Task", rest) do
    prompt =
      with {:ok, %{"prompt" => p}} <- Jason.decode(rest) do
        String.slice(p, 0..80) <> if(String.length(p) > 81, do: "…", else: "")
      else
        _ -> rest
      end

    {"hero-cpu-chip", "Task", prompt}
  end

  defp tool_widget_meta("Grep", rest) do
    case Jason.decode(rest) do
      {:ok, %{"pattern" => pat} = input} ->
        path = input["path"] || ""
        detail = [pat, path] |> Enum.reject(&(&1 == "")) |> Enum.join(" ")
        {"hero-magnifying-glass", "Grep", detail}

      _ ->
        case Regex.run(~r/^`([^`]+)`\s*(.*)/s, rest, capture: :all_but_first) do
          [pattern, path] ->
            detail = [pattern, path] |> Enum.reject(&(&1 == "")) |> Enum.join(" ")
            {"hero-magnifying-glass", "Grep", detail}

          _ ->
            {"hero-magnifying-glass", "Grep", rest}
        end
    end
  end

  defp tool_widget_meta("WebSearch", rest) do
    query = with {:ok, %{"query" => q}} <- Jason.decode(rest), do: q, else: (_ -> rest)
    {"hero-globe-alt", "WebSearch", query}
  end

  defp tool_widget_meta(name, rest) when is_binary(name) and binary_part(name, 0, 4) == "mcp_" do
    short = name |> String.split("__") |> List.last()

    {icon, detail} =
      case {short, Jason.decode(rest)} do
        {"i-speak", {:ok, %{"message" => msg}}} ->
          {"hero-speaker-wave", msg}

        {"i-speak", _} ->
          msg =
            rest
            |> String.replace_prefix("message: ", "")
            |> String.split(~r/,\s*(?:voice|rate):\s*/)
            |> List.first()
            |> String.trim()

          {"hero-speaker-wave", msg}

        {_, {:ok, input}} when is_map(input) ->
          summary =
            input
            |> Map.to_list()
            |> Enum.take(2)
            |> Enum.filter(fn {_k, v} -> is_binary(v) or is_number(v) or is_atom(v) end)
            |> Enum.map(fn {k, v} -> "#{k}: #{String.slice(to_string(v), 0..40)}" end)
            |> Enum.join(", ")

          {"hero-puzzle-piece", if(summary == "", do: rest, else: summary)}

        _ ->
          {"hero-puzzle-piece", rest}
      end

    {icon, short, detail}
  end

  defp tool_widget_meta(name, rest) do
    {"hero-wrench-screwdriver", name, rest}
  end
end
