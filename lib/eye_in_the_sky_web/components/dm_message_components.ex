defmodule EyeInTheSkyWeb.Components.DmMessageComponents do
  @moduledoc """
  Shared message rendering components used by MessagesTab and ChatWindowComponent.

  Public API:
    message_body/1        — renders message content (text, tool calls, tool results, thinking)
    tool_result_body/1    — renders tool result OUTPUT block
    tool_widget/1         — renders a tool call collapsible widget
    tool_widget_body/1    — renders the body inside a tool call widget
    message_metrics/1     — renders token/cost/duration metrics row
    message_attachments/1 — renders file attachment list

  Both message_body and tool_result_body accept a `compact` boolean (default false)
  that switches to smaller sizing for use in the canvas chat window.
  message_body also accepts `extra_id` to namespace element IDs when the same
  message appears in multiple components on the page (e.g. canvas windows).

  Tool widget components (tool_widget, tool_widget_body, tool_result_body) live in
  EyeInTheSkyWeb.Components.DmMessageComponents.ToolWidget and are imported here.
  """

  use EyeInTheSkyWeb, :html

  import EyeInTheSkyWeb.Components.DmHelpers
  import EyeInTheSkyWeb.Components.DmMessageComponents.ToolWidget

  # ---------------------------------------------------------------------------
  # message_tier/1
  # Classifies an agent message into a display tier:
  #   :primary   — substantial content (text body, DM) → full card treatment
  #   :secondary — tool event / tool result → plain muted row
  #   :user      — fallback / user-like agent message
  # ---------------------------------------------------------------------------

  def message_tier(message) do
    stream_type = get_in(message.metadata || %{}, ["stream_type"])
    is_tool_event = stream_type in ["tool_result", "tool_use", "output", "bash"]

    body = message.body || ""
    segments = parse_body_segments(body)
    body_is_tool_calls = segments != [] and Enum.all?(segments, &match?({:tool_call, _, _}, &1))

    classify_tier(is_tool_event or body_is_tool_calls, body)
  end

  @doc """
  Variant that accepts an already-computed `is_tool_event` flag and the raw
  body. Used by `MessagesTab.message_item/1` to avoid re-parsing segments
  and re-checking stream_type when those values are already on the assigns.
  """
  def message_tier(is_tool_event, body) when is_boolean(is_tool_event) do
    classify_tier(is_tool_event, body || "")
  end

  defp classify_tier(true, _body), do: :secondary

  defp classify_tier(false, body) do
    if String.trim(body) == "", do: :secondary, else: :primary
  end

  # ---------------------------------------------------------------------------
  # message_metrics
  # ---------------------------------------------------------------------------

  attr :message, :map, required: true

  def message_metrics(assigns) do
    metrics_text =
      case format_metrics(assigns.message.metadata) do
        "" -> fallback_metrics(assigns.message)
        text -> text
      end

    cache_pct = cache_hit_pct(get_in(assigns.message.metadata || %{}, ["usage"]))

    assigns =
      assigns
      |> assign(:metrics_text, metrics_text)
      |> assign(:cache_pct, cache_pct)

    ~H"""
    <%= if @metrics_text != "" or @cache_pct do %>
      <div class="mt-1 px-1 flex items-center gap-0">
        <%= if @metrics_text != "" do %>
          <span class="text-[11px] font-mono tabular-nums text-base-content/40">
            {@metrics_text}
          </span>
        <% end %>
        <%= if @cache_pct do %>
          <span class="inline-flex items-center gap-0.5 text-[11px] font-mono tabular-nums text-base-content/40">
            <%= if @metrics_text != "" do %>
              ·
            <% end %>
            <.icon name="hero-circle-stack" class="size-3" />
            {@cache_pct}%
          </span>
        <% end %>
      </div>
    <% end %>
    """
  end

  # Renders model · $cost when metadata has no total_cost_usd to drive
  # format_metrics/1. Mirrors the inline fallback that used to live in
  # MessagesTab.message_item/1.
  defp fallback_metrics(message) do
    [
      message_model(message),
      case message_cost(message) do
        nil -> nil
        cost -> "$#{:erlang.float_to_binary(cost * 1.0, decimals: 4)}"
      end
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp format_metrics(metadata) when is_map(metadata) do
    parts =
      [
        metadata["total_cost_usd"] &&
          "$#{:erlang.float_to_binary(metadata["total_cost_usd"] * 1.0, decimals: 4)}",
        get_in(metadata, ["usage", "input_tokens"]) &&
          "#{get_in(metadata, ["usage", "input_tokens"])} in",
        get_in(metadata, ["usage", "output_tokens"]) &&
          "#{get_in(metadata, ["usage", "output_tokens"])} out",
        metadata["duration_ms"] &&
          "#{:erlang.float_to_binary(metadata["duration_ms"] * 1.0 / 1000, decimals: 1)}s",
        metadata["num_turns"] && "#{metadata["num_turns"]} turns"
      ]
      |> Enum.reject(&is_nil/1)

    Enum.join(parts, " · ")
  end

  defp format_metrics(_), do: ""

  # Returns the cache hit percentage as an integer (e.g. 30) when
  # cache_read_input_tokens > 0, nil otherwise. Used by message_metrics/1
  # to render the hero-circle-stack icon + percentage inline.
  defp cache_hit_pct(nil), do: nil

  defp cache_hit_pct(usage) when is_map(usage) do
    read = usage["cache_read_input_tokens"] || 0
    created = usage["cache_creation_input_tokens"] || 0
    plain = usage["input_tokens"] || 0
    total = plain + read + created

    if total > 0 and read > 0 do
      round(read / total * 100)
    end
  end

  defp cache_hit_pct(_), do: nil

  # ---------------------------------------------------------------------------
  # message_attachments
  # ---------------------------------------------------------------------------

  attr :attachments, :list, default: []

  def message_attachments(assigns) do
    ~H"""
    <%= if @attachments != [] do %>
      <div class="mt-2 space-y-1">
        <%= for attachment <- @attachments do %>
          <div class="flex items-center gap-2 rounded-md bg-base-content/[0.04] px-2.5 py-1.5 text-mini hover:bg-base-content/[0.08] transition-colors group">
            <.icon name="hero-paper-clip" class="size-3 text-base-content/30" />
            <span class="text-base-content/60 truncate">{attachment.original_filename}</span>
            <%= if attachment.size_bytes do %>
              <span class="text-base-content/40 font-mono">
                {EyeInTheSkyWeb.Helpers.FileHelpers.format_size(attachment.size_bytes)}
              </span>
            <% end %>
            <button
              type="button"
              phx-click="delete_attachment"
              phx-value-id={attachment.id}
              class="ml-auto flex items-center justify-center size-5 rounded text-base-content/30 hover:text-error opacity-0 group-hover:opacity-100 transition-opacity"
              title="Delete attachment"
            >
              <.icon name="hero-x-mark-mini" class="size-3.5" />
            </button>
          </div>
        <% end %>
      </div>
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # message_body
  # ---------------------------------------------------------------------------

  attr :message, :map, required: true
  attr :compact, :boolean, default: false
  attr :flat, :boolean, default: false
  attr :extra_id, :any, default: nil
  attr :search_query, :string, default: ""

  def message_body(assigns) do
    raw_body = assigns.message.body || ""

    is_dm_body =
      dm_message?(assigns.message) or
        String.starts_with?(raw_body, "DM from:") or
        String.starts_with?(raw_body, "[DM from agent:")

    {dm_info, body} =
      if is_dm_body do
        {parse_dm_info(raw_body), strip_dm_prefix(raw_body)}
      else
        {nil, raw_body}
      end

    sender_role = assigns.message.sender_role || "agent"
    stream_type = get_in(assigns.message.metadata || %{}, ["stream_type"])

    # Only parse tool-call segments for agent/tool messages. User and system
    # prose that happens to start with "Tool:" or "> `Name`" must stay as text.
    segments =
      if sender_role in ["user", "system"],
        do: [{:text, body}],
        else: parse_body_segments(body)

    thinking = get_in(assigns.message.metadata || %{}, ["thinking"])
    id_prefix = if assigns.extra_id, do: "#{assigns.extra_id}-", else: ""

    # True when stream_type is "bash" and the body did not parse as any tool
    # call — legacy alias for a call event with a plain-text or JSON body.
    bash_fallback =
      stream_type == "bash" and
        not Enum.any?(segments, &match?({:tool_call, _, _}, &1)) and
        String.trim(body) != ""

    hook_name = get_in(assigns.message.metadata || %{}, ["hook_name"])
    exit_code = get_in(assigns.message.metadata || %{}, ["exit_code"])

    assigns =
      assigns
      |> assign(:segments, segments)
      |> assign(:thinking, thinking)
      |> assign(:stream_type, stream_type)
      |> assign(:id_prefix, id_prefix)
      |> assign(:dm_info, dm_info)
      |> assign(:bash_fallback, bash_fallback)
      |> assign(:bash_body, body)
      |> assign(:hook_name, hook_name)
      |> assign(:exit_code, exit_code)

    ~H"""
    <div class={[
      "space-y-1.5",
      !@compact && "mt-1",
      @compact && @stream_type != "tool_result" && "mt-0.5"
    ]}>
      <%= if @stream_type == "hook_failure" do %>
        <div class="flex items-start gap-2 rounded-md bg-warning/10 border border-warning/20 px-2.5 py-2">
          <.icon
            name="hero-exclamation-triangle"
            class="size-3.5 text-warning/80 mt-0.5 flex-shrink-0"
          />
          <div class="min-w-0 space-y-1">
            <p class="text-mini font-mono font-semibold text-warning/80">
              Hook failed: {@hook_name} (exit {@exit_code})
            </p>
            <%= if String.trim(@bash_body) not in ["", "(no output)"] do %>
              <pre class="text-mini text-base-content/50 font-mono whitespace-pre-wrap break-words overflow-x-auto">{@bash_body}</pre>
            <% end %>
          </div>
        </div>
      <% end %>
      <%= if @dm_info do %>
        <div class="flex items-center gap-1.5 flex-wrap mb-1">
          <%= if @dm_info[:session_id] && @dm_info[:session_id] != "" do %>
            <a
              href={"/dm/#{@dm_info[:session_id]}"}
              class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded bg-primary/10 text-primary/70 text-micro font-mono font-semibold hover:bg-primary/20 transition-colors"
            >
              <.custom_icon name="lucide-robot" class="size-3" />
              {@dm_info.sender}
              <span class="text-primary/40 font-normal">#{@dm_info[:session_id]}</span>
            </a>
          <% else %>
            <span class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded bg-primary/10 text-primary/70 text-micro font-mono font-semibold">
              <.custom_icon name="lucide-robot" class="size-3" />
              {@dm_info.sender}
            </span>
          <% end %>
          <%= if @dm_info.status do %>
            <span class={[
              "inline-flex items-center px-1.5 py-0.5 rounded text-micro font-mono font-semibold",
              @dm_info.status in ["done", "completed"] && "bg-success/15 text-success/80",
              @dm_info.status == "failed" && "bg-error/15 text-error/80",
              @dm_info.status not in ["done", "completed", "failed"] &&
                "bg-base-content/8 text-base-content/50"
            ]}>
              {@dm_info.status}
            </span>
          <% end %>
          <%= if @dm_info.url do %>
            <% parsed_uri = URI.parse(@dm_info.url) %>
            <a
              href={@dm_info.url}
              target="_blank"
              rel="noopener"
              class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded bg-base-content/[0.05] text-base-content/50 hover:text-primary/80 transition-colors text-micro font-mono truncate max-w-[220px]"
              title={@dm_info.url}
            >
              <.icon name="hero-arrow-top-right-on-square" class="size-3 flex-shrink-0" />
              {parsed_uri.host}{parsed_uri.path}
            </a>
          <% end %>
        </div>
      <% end %>
      <details
        :if={@thinking && @thinking != ""}
        id={"#{@id_prefix}thinking-#{@message.id}"}
        class="group rounded border-l-2 border-primary/50 bg-[var(--surface-code)] overflow-hidden"
        phx-hook="ExpandOnSearch"
        data-thinking={@thinking}
        data-query={@search_query}
      >
        <summary class={
          "flex items-center cursor-pointer select-none list-none hover:bg-base-content/[0.04] transition-colors " <>
            if(@compact, do: "gap-1.5 px-2 py-1", else: "gap-2 px-2.5 py-1.5")
        }>
          <.icon
            name="hero-sparkles"
            class={
              if @compact,
                do: "size-3 flex-shrink-0 text-primary/60",
                else: "size-3.5 flex-shrink-0 text-primary/60"
            }
          />
          <span class={
            "font-mono font-semibold text-primary/60 uppercase tracking-wide " <>
              if(@compact, do: "text-micro", else: "text-mini")
          }>
            Thinking
          </span>
          <.icon
            name="hero-chevron-right"
            class={
              if @compact,
                do:
                  "w-2.5 h-2.5 text-base-content/20 ml-auto flex-shrink-0 transition-transform group-open:rotate-90",
                else:
                  "size-3 text-base-content/20 ml-auto flex-shrink-0 transition-transform group-open:rotate-90"
            }
          />
        </summary>
        <div class={
          if @compact,
            do: "px-2 pb-1.5 pt-1 border-t border-[var(--border-subtle)]",
            else: "px-2.5 pb-2 pt-1 border-t border-[var(--border-subtle)]"
        }>
          <pre class={
            if @compact,
              do:
                "font-mono text-micro text-[var(--text-muted)] whitespace-pre-wrap break-words leading-relaxed",
              else:
                "font-mono text-xs text-[var(--text-muted)] whitespace-pre-wrap break-words leading-relaxed"
          }>{@thinking}</pre>
        </div>
      </details>
      <%= cond do %>
        <% @stream_type in ["tool_result", "output"] -> %>
          <%!-- "output" is a legacy alias for tool_result — both route to the output widget. --%>
          <.tool_result_body body={@message.body} compact={@compact} flat={@flat} />
        <% @bash_fallback -> %>
          <%!-- "bash" stream type with a non-tool-call body: render as a Bash call widget. --%>
          <.tool_widget name="Bash" rest={@bash_body} compact={@compact} flat={@flat} />
        <% true -> %>
          <%= for {segment, idx} <- Enum.with_index(@segments) do %>
            <%= case segment do %>
              <% {:tool_call, name, rest} -> %>
                <.tool_widget name={name} rest={rest} compact={@compact} flat={@flat} />
              <% {:text, text} when text != "" -> %>
                <div
                  id={"msg-body-#{@id_prefix}#{@message.id}-#{idx}"}
                  class={[
                    "dm-markdown leading-relaxed text-base-content/85",
                    if(@compact, do: "text-xs", else: "text-sm")
                  ]}
                  phx-hook="MarkdownMessage"
                  data-raw-body={text}
                >
                  <pre class="whitespace-pre-wrap font-sans text-inherit m-0 p-0">{text}</pre>
                </div>
              <% _ -> %>
            <% end %>
          <% end %>
      <% end %>
    </div>
    """
  end
end
