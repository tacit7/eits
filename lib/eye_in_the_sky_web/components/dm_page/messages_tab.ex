defmodule EyeInTheSkyWeb.Components.DmPage.MessagesTab do
  @moduledoc """
  LiveComponent for the DM messages tab.

  Message rows are rendered via a LiveView stream (:grouped_messages) so only
  new or changed rows are sent to the client on each PubSub event. The stream
  is managed by the parent LiveView (DmLive) via MessageGrouper + TabHelpers;
  this component receives @streams from the parent and renders the stream
  container with phx-update="stream".

  The old @messages assign and the prev_messages == new_messages cache in
  update/2 are gone. The parent LV calls stream_insert only for changed rows;
  stream updates bypass the component's update/2 entirely (LiveView sends them
  as stream diffs, not component diffs).
  """

  use Phoenix.Component

  alias EyeInTheSkyWeb.Components.DmHelpers
  import EyeInTheSkyWeb.Components.DmHelpers, only: [to_utc_string: 1, parse_body_segments: 1]

  import EyeInTheSkyWeb.Components.DmMessageComponents,
    only: [message_body: 1, message_metrics: 1, message_attachments: 1]
  import EyeInTheSkyWeb.Helpers.ViewHelpers, only: [relative_time: 1]
  import EyeInTheSkyWeb.CoreComponents, only: [icon: 1, empty_state: 1]

  alias Phoenix.LiveView.JS
  alias EyeInTheSkyWeb.Components.DmMessageComponents

  # ---------------------------------------------------------------------------
  # Function component
  # ---------------------------------------------------------------------------

  attr :streams, :map, required: true
  attr :empty, :boolean, required: true
  attr :has_more_messages, :boolean, required: true
  attr :stream, :map, required: true
  attr :session, :any, default: nil
  attr :agent, :any, default: nil
  attr :message_search_query, :string, default: ""
  attr :codex_raw_lines, :list, default: []

  def messages_tab(assigns) do
    ~H"""
    <div class="flex h-full flex-col" id="dm-messages-tab">
      <div
        class="overflow-y-auto flex-1 min-h-0"
        id="messages-container"
        phx-hook="AutoScroll"
        data-has-more={if @has_more_messages, do: "true", else: "false"}
        style="scrollbar-width: none; -ms-overflow-style: none; overflow-anchor: none;"
      >
          <%= if @empty do %>
            <.empty_state
              title={if @agent, do: @agent.name, else: "No messages yet"}
              class="flex flex-col items-center justify-center h-full py-20 text-center select-none"
              icon="hero-chat-bubble-left-right"
              icon_class="size-16 text-base-content/10 mb-5"
              title_class="text-base font-medium text-base-content/40"
              subtitle_class="mt-1.5 text-xs text-base-content/25 max-w-xs"
            >
              <:subtitle_slot :if={not is_nil(@agent) && not is_nil(@agent.git_worktree_path)}>
                <span class="font-mono">{Path.basename(@agent.git_worktree_path)}</span> &nbsp;&mdash;
                Send a message to start the conversation
              </:subtitle_slot>
            </.empty_state>
          <% else %>
            <div class="max-w-[860px] w-full mx-auto px-5 py-5">
              <div class="py-2 flex items-center justify-center gap-3">
                <%= if @has_more_messages do %>
                  <button
                    phx-click="load_more_messages"
                    phx-click-loading-class="opacity-50 pointer-events-none"
                    class="text-xs text-base-content/35 hover:text-primary transition-colors"
                    id="load-more-messages"
                    onclick="document.getElementById('messages-container').dispatchEvent(new CustomEvent('load-more-intent'))"
                  >
                    Load older messages
                  </button>
                <% end %>
              </div>

              <%!-- Stream container: each grouped row is a stream item. LiveView
                   inserts/patches rows individually; morphdom only touches changed
                   elements. The wrapper div carries the stream dom_id; the inner
                   component renders its own element with a separate internal id. --%>
              <div id="grouped-messages-stream" phx-update="stream">
                <div :for={{dom_id, item} <- @streams.grouped_messages} id={dom_id}>
                  <.tool_cluster :if={item.type == :cluster} events={item.data} meta={item.meta} />
                  <.message_item
                    :if={item.type == :message}
                    message={item.data}
                    prev_role={item.prev_role}
                    agent={@agent}
                    session={@session}
                  />
                </div>
              </div>

              <%!-- Live streaming bubble — flows naturally in the scroll container.
                   No absolute positioning, no pb-32 toggle: bubble growth is a
                   single reflow event (the div itself growing), not two
                   (bubble + padding toggle). --%>
              <%= if @stream.show && (@stream.content != "" || @stream.tool || @stream.thinking) do %>
                <div id="live-stream-bubble">
                  <div class="rounded-md bg-[var(--agent-bg)] px-3 py-2.5">
                    <div class="flex items-center gap-2 mb-2">
                      <div class="size-5 rounded-full bg-[var(--accent-soft)] border border-[var(--border-subtle)] flex items-center justify-center flex-shrink-0 overflow-hidden">
                        <.provider_avatar session={@session} class="size-3 animate-pulse" />
                      </div>
                      <span class="text-[11px] font-semibold text-primary/80 animate-pulse">
                        {stream_provider_label(@session)}
                      </span>
                    </div>
                    <div class="border-l-2 border-[var(--guide-line)] pl-3.5 ml-1.5">
                      <%= if @stream.thinking do %>
                        <div class="text-xs text-base-content/30 italic font-mono line-clamp-3">
                          {String.slice(@stream.thinking, -200, 200)}
                        </div>
                      <% end %>
                      <%= if @stream.tool do %>
                        <div class="text-xs text-base-content/40 font-mono">
                          Using {@stream.tool}...
                        </div>
                      <% end %>
                      <%= if @stream.content not in [nil, ""] do %>
                        <div class="text-[13px] leading-[1.7] text-base-content/60 whitespace-pre-wrap">
                          {String.trim_leading(@stream.content)}
                        </div>
                      <% end %>
                    </div>
                  </div>
                </div>
              <% end %>

              <%!-- Scroll anchor --%>
              <div id="messages-scroll-anchor" style="height: 1px; overflow-anchor: auto;"></div>
            </div>
          <% end %>
      </div>

      <%!-- Codex raw JSONL stream panel --%>
      <%= if @codex_raw_lines != [] do %>
        <details class="border-t border-[var(--border-subtle)] shrink-0" id="codex-raw-panel">
          <summary class="px-4 py-1.5 text-micro font-mono text-base-content/30 cursor-pointer select-none hover:text-base-content/50 flex items-center gap-1.5">
            <.icon name="hero-code-bracket" class="size-3" />
            raw stream ({length(@codex_raw_lines)} lines)
          </summary>
          <div
            class="h-40 overflow-y-auto bg-[var(--surface-code)] px-3 py-2"
            id="codex-raw-lines"
            phx-hook="AutoScroll"
          >
            <%= for line <- Enum.reverse(@codex_raw_lines) do %>
              <div class="font-mono text-micro text-base-content/40 leading-relaxed truncate">
                {line}
              </div>
            <% end %>
          </div>
        </details>
      <% end %>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Private components
  # ---------------------------------------------------------------------------

  attr :message, :map, required: true
  attr :prev_role, :any, default: nil
  attr :agent, :map, default: nil
  attr :session, :map, default: nil

  defp message_item(assigns) do
    role = if assigns.message.sender_role == "user", do: :user, else: :agent
    stream_type = get_in(assigns.message.metadata || %{}, ["stream_type"])
    segments = parse_body_segments(assigns.message.body)
    body_is_tool_calls = segments != [] and Enum.all?(segments, &match?({:tool_call, _, _}, &1))
    is_tool_event = stream_type in ["tool_result", "tool_use"] or body_is_tool_calls
    is_same_sender = assigns.prev_role != nil && assigns.prev_role == assigns.message.sender_role
    is_new_turn = assigns.prev_role != nil && assigns.prev_role != assigns.message.sender_role

    is_empty_tool_result =
      stream_type == "tool_result" and String.trim(assigns.message.body || "") == ""
    tier =
      if role == :agent,
        do: DmMessageComponents.message_tier(is_tool_event, assigns.message.body),
        else: :user

    show_header = !is_same_sender && !is_tool_event

    assigns =
      assigns
      |> assign(:role, role)
      |> assign(:is_tool_event, is_tool_event)
      |> assign(:is_same_sender, is_same_sender)
      |> assign(:is_new_turn, is_new_turn)
      |> assign(:is_empty_tool_result, is_empty_tool_result)
      |> assign(:show_header, show_header)
      |> assign(:tier, tier)

    ~H"""
    <%= if !@is_empty_tool_result do %>
      <%!-- Inter-turn divider: user → agent turn boundary --%>
      <div
        :if={@is_new_turn && @role == :agent && !@is_tool_event}
        class="my-5 mx-3 h-px bg-[var(--border-subtle)]"
      />
      <div
        id={"dm-message-#{@message.id}"}
        class={[
          cond do
            @is_tool_event -> "mt-1"
            @is_new_turn -> "mt-2"
            @is_same_sender -> "mt-1"
            true -> "mt-3"
          end
        ]}
        phx-mounted={
          JS.transition(
            {"transition-all ease-out duration-200", "opacity-0 translate-y-1",
             "opacity-100 translate-y-0"}
          )
        }
      >
        <%= if @is_tool_event do %>
          <%!-- Tool events: subordinate rendering — compact + muted --%>
          <div class="pl-[33px]">
            <.message_body message={@message} compact={true} />
          </div>
        <% else %>
          <%= if @role == :user do %>
            <%!-- ── User prompt ── --%>
            <div class="group">
              <%!-- Header row --%>
              <div :if={@show_header} class="flex items-center gap-2 mb-1.5">
                <div class="size-5 rounded-full bg-[var(--surface-card)] border border-[var(--border-subtle)] flex items-center justify-center text-[9px] font-bold text-base-content/40 flex-shrink-0 select-none">
                  U
                </div>
                <span class="text-[11px] font-semibold text-base-content/40">you</span>
                <time
                  id={"msg-time-#{@message.id}"}
                  class="text-[10px] text-base-content/25"
                  data-utc={to_utc_string(@message.inserted_at)}
                  phx-hook="LocalTime"
                />
              </div>
              <%!-- Body --%>
              <div class={[
                "px-3 py-2 bg-[var(--prompt-bg)] border border-[var(--border-subtle)] rounded-md text-[12.5px] leading-[1.5] break-words text-base-content/60",
                @show_header && "ml-7"
              ]}>
                <.message_body message={@message} compact={false} />
              </div>
              <.message_attachments attachments={@message.attachments || []} />
            </div>
          <% else %>
            <%!-- ── Agent message ── --%>
            <div class={[
              "group",
              @tier == :primary &&
                "rounded-lg border bg-[var(--surface-card,theme(colors.base-200/40))] border-base-content/[0.08] px-3 py-2.5",
              @tier == :secondary && "pl-[33px] py-1",
              @tier not in [:primary, :secondary] &&
                "rounded-lg bg-[var(--agent-bg)] hover:bg-base-content/[0.03] px-3 py-2.5 transition-colors duration-100"
            ]}>
              <%!-- Header row --%>
              <div :if={@show_header && @tier == :primary} class="flex items-center gap-2 mb-3">
                <div class="size-5 rounded-full bg-[var(--accent-soft)] border border-[var(--border-subtle)] flex items-center justify-center flex-shrink-0 overflow-hidden">
                  <.provider_avatar session={@session} />
                </div>
                <span class="text-[11px] font-semibold text-base-content/80">
                  {if @agent, do: @agent.name, else: "agent"}
                </span>
                <time
                  id={"msg-time-#{@message.id}"}
                  class="text-[10px] text-base-content/25"
                  data-utc={to_utc_string(@message.inserted_at)}
                  phx-hook="LocalTime"
                />
                <div class="ml-auto opacity-0 group-hover:opacity-100 [@media(hover:none)]:opacity-100 transition-opacity duration-150 flex items-center gap-0.5">
                  <button
                    data-copy-btn
                    data-copy-text={@message.body}
                    class="p-1 rounded text-base-content/25 hover:text-base-content/55 hover:bg-base-content/8 transition-colors"
                    title="Copy message"
                    aria-label="Copy message"
                  >
                    <.icon name="hero-clipboard-document-mini" class="size-3.5" />
                  </button>
                </div>
              </div>
              <%!-- Body --%>
              <div class={[
                "break-words",
                @tier == :primary &&
                  "border-l-2 border-[var(--guide-line)] pl-3.5 ml-1.5 text-[13px] leading-[1.7] text-base-content",
                @tier == :secondary && "text-[var(--text-secondary)] text-sm",
                @tier not in [:primary, :secondary] &&
                  "border-l-2 border-[var(--guide-line)] pl-3.5 ml-1.5 text-[13px] leading-[1.7] text-base-content"
              ]}>
                <.message_body message={@message} compact={false} />
              </div>
              <.message_attachments attachments={@message.attachments || []} />
              <%!-- Metadata footer — only on primary tier --%>
              <div
                :if={@tier == :primary && DmHelpers.has_message_metrics?(@message)}
                class="flex items-center gap-1 mt-3 pt-2 border-t border-[var(--border-subtle)]"
              >
                <.message_metrics message={@message} />
              </div>
            </div>
          <% end %>
        <% end %>
      </div>
    <% end %>
    """
  end

  # Provider avatar — single canonical impl for both static and animated sites.
  # Sources the SVG path and dark-mode class from DmHelpers; see lib/CLAUDE.md.
  attr :session, :map, default: nil
  attr :class, :string, default: "size-3"

  defp provider_avatar(assigns) do
    provider = if assigns.session, do: assigns.session.provider, else: "claude"

    assigns =
      assigns
      |> assign(:src, DmHelpers.provider_icon(provider))
      |> assign(:icon_class, DmHelpers.provider_icon_class(provider))
      |> assign(:alt, DmHelpers.stream_provider_label(assigns.session))

    ~H"""
    <img
      src={@src}
      class={[@class, @icon_class]}
      alt={@alt}
      width="12"
      height="12"
      loading="lazy"
    />
    """
  end

  defdelegate stream_provider_label(session), to: DmHelpers

  # ---------------------------------------------------------------------------
  # tool_cluster component
  # ---------------------------------------------------------------------------

  attr :events, :list, required: true
  attr :meta, :map, required: true

  defp tool_cluster(assigns) do
    ~H"""
    <details
      id={"cluster-#{List.first(@events).id}"}
      phx-hook="PreserveDetails"
      class="group my-1 w-full pl-[33px]"
    >
      <summary class="flex items-center gap-2 px-1 py-0.5 cursor-pointer list-none text-[var(--text-muted)] hover:text-[var(--text-secondary)] select-none">
        <span class="text-[var(--text-disabled)] group-open:rotate-90 transition-transform duration-100 text-[10px]">&#9658;</span>
        <span class="text-nano font-mono"><%= @meta.count %> tool events</span>
        <%= for {type, count} <- @meta.type_counts do %>
          <span class="rounded-sm px-1 py-px bg-base-content/[0.05] text-nano font-mono text-[var(--text-disabled)]">
            <%= type %> &times;<%= count %>
          </span>
        <% end %>
        <%= if @meta.duration_ms do %>
          <span class="text-nano font-mono text-[var(--text-disabled)] ml-1">~<%= div(@meta.duration_ms, 1000) %>s</span>
        <% end %>
        <span class="ml-auto text-nano text-[var(--text-disabled)]"><%= relative_time(@meta.first_at) %></span>
      </summary>
      <div class="pl-5 mt-0.5 space-y-px">
        <%= for event <- @events do %>
          <div class="max-w-full px-1">
            <.message_body message={event} compact={true} />
          </div>
        <% end %>
      </div>
    </details>
    """
  end

end
