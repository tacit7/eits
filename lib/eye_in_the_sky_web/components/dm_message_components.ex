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
    is_tool_event = stream_type in ["tool_result", "tool_use"]

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

    assigns = assign(assigns, :metrics_text, metrics_text)

    ~H"""
    <%= if @metrics_text != "" do %>
      <div class="mt-1 px-1">
        <span class="text-[11px] font-mono tabular-nums text-base-content/40">
          {@metrics_text}
        </span>
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
              <span class="text-base-content/40 font-mono">{EyeInTheSkyWeb.Helpers.FileHelpers.format_size(attachment.size_bytes)}</span>
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
  attr :extra_id, :any, default: nil

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

    segments = parse_body_segments(body)
    thinking = get_in(assigns.message.metadata || %{}, ["thinking"])
    stream_type = get_in(assigns.message.metadata || %{}, ["stream_type"])
    id_prefix = if assigns.extra_id, do: "#{assigns.extra_id}-", else: ""

    assigns =
      assigns
      |> assign(:segments, segments)
      |> assign(:thinking, thinking)
      |> assign(:stream_type, stream_type)
      |> assign(:id_prefix, id_prefix)
      |> assign(:dm_info, dm_info)

    ~H"""
    <div class={[
      "space-y-1.5",
      !@compact && "mt-1",
      @compact && @stream_type != "tool_result" && "mt-0.5"
    ]}>
      <%= if @dm_info do %>
        <div class="flex items-center gap-1.5 flex-wrap mb-1">
          <span class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded bg-primary/10 text-primary/70 text-micro font-mono font-semibold">
            <.icon name="hero-cpu-chip" class="size-3" />
            {@dm_info.sender}
            <%= if @dm_info[:session_id] && @dm_info[:session_id] != "" do %>
              <span class="text-primary/40 font-normal">#{@dm_info[:session_id]}</span>
            <% end %>
          </span>
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
            <a
              href={@dm_info.url}
              target="_blank"
              rel="noopener"
              class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded bg-base-content/[0.05] text-base-content/50 hover:text-primary/80 transition-colors text-micro font-mono truncate max-w-[220px]"
              title={@dm_info.url}
            >
              <.icon name="hero-arrow-top-right-on-square" class="size-3 flex-shrink-0" />
              {URI.parse(@dm_info.url).host}{URI.parse(@dm_info.url).path}
            </a>
          <% end %>
        </div>
      <% end %>
      <details
        :if={@thinking && @thinking != ""}
        class="group rounded border-l-2 border-primary/50 bg-[var(--surface-code)] overflow-hidden"
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
      <%= if @stream_type == "tool_result" do %>
        <.tool_result_body body={@message.body} compact={@compact} />
      <% else %>
        <%= for {segment, idx} <- Enum.with_index(@segments) do %>
          <%= case segment do %>
            <% {:tool_call, name, rest} -> %>
              <.tool_widget name={name} rest={rest} compact={@compact} />
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
