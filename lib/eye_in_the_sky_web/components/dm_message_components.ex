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
  """

  use EyeInTheSkyWeb, :html

  import EyeInTheSkyWeb.Components.DmHelpers

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
    assigns = assign(assigns, :metrics_text, format_metrics(assigns.message.metadata))

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
          <div class="flex items-center gap-2 rounded-md bg-base-content/[0.04] px-2.5 py-1.5 text-mini font-mono">
            <.icon name="hero-paper-clip" class="size-3 text-base-content/30" />
            <span class="text-base-content/60">{attachment.original_filename}</span>
            <span class="ml-auto text-base-content/25">{attachment.storage_path}</span>
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
              </div>
            <% _ -> %>
          <% end %>
        <% end %>
      <% end %>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # tool_card_shell — shared outer chrome for tool_widget + tool_result_body
  #
  # Owns the <details> wrapper, <summary> wrapper, optional copy button, and
  # trailing chevron. Two modes:
  #   compact = true  → strip-row styling, body slot is wrapped in an indent rule
  #   compact = false → bordered card styling, body slot rendered raw
  # ---------------------------------------------------------------------------

  attr :compact, :boolean, default: false
  attr :copy_text, :string, default: nil
  attr :copy_title, :string, default: "Copy"
  slot :summary, required: true
  slot :inner_block, required: true

  defp tool_card_shell(assigns) do
    ~H"""
    <details class={
      if @compact,
        do: "group my-px",
        else: "group rounded-md border border-[var(--border-subtle)] bg-[var(--surface-card)] overflow-hidden"
    }>
      <summary class={
        if @compact,
          do:
            "flex items-center gap-1.5 py-0.5 px-1 rounded cursor-pointer select-none list-none hover:bg-base-content/[0.04] transition-colors",
          else:
            "flex items-center gap-2 px-2.5 py-1.5 cursor-pointer select-none list-none hover:bg-[var(--border-subtle)] transition-colors"
      }>
        {render_slot(@summary)}
        <button
          :if={!@compact && @copy_text}
          class="tool-copy-btn ml-auto mr-1 shrink-0"
          data-copy-btn
          data-copy-text={@copy_text}
          title={@copy_title}
        >
          <.icon name="hero-clipboard-document" class="size-3.5" />
        </button>
        <.icon
          name="hero-chevron-right"
          class={
            if @compact,
              do:
                "w-2.5 h-2.5 text-base-content/15 flex-shrink-0 ml-auto transition-transform group-open:rotate-90",
              else: "size-3 text-base-content/20 shrink-0 transition-transform group-open:rotate-90"
          }
        />
      </summary>
      <%= if @compact do %>
        <div class="pl-3 mt-0.5 border-l border-[var(--border-subtle)]">
          {render_slot(@inner_block)}
        </div>
      <% else %>
        {render_slot(@inner_block)}
      <% end %>
    </details>
    """
  end

  # ---------------------------------------------------------------------------
  # tool_result_body
  # ---------------------------------------------------------------------------

  attr :body, :string, default: ""
  attr :compact, :boolean, default: false

  def tool_result_body(assigns) do
    trimmed = String.trim(assigns.body || "")
    line_count = if trimmed == "", do: 0, else: trimmed |> String.split("\n") |> length()

    assigns =
      assigns
      |> assign(:body_blank, trimmed == "")
      |> assign(:line_count, line_count)

    ~H"""
    <.tool_card_shell
      :if={!@body_blank}
      compact={@compact}
      copy_text={@body}
      copy_title="Copy output"
    >
      <:summary>
        <.icon
          name="hero-code-bracket"
          class={
            if @compact,
              do: "size-2.5 flex-shrink-0 text-base-content/20",
              else: "size-3.5 flex-shrink-0 text-base-content/30"
          }
        />
        <span class={
          if @compact,
            do:
              "text-micro font-mono font-semibold text-base-content/30 flex-shrink-0 uppercase tracking-wide",
            else:
              "text-mini font-mono font-semibold text-base-content/40 uppercase tracking-wide flex-shrink-0"
        }>
          Output
        </span>
        <span
          :if={@compact}
          class="text-micro font-mono text-base-content/25 flex-shrink-0"
        >
          {@line_count} {if @line_count == 1, do: "line", else: "lines"}
        </span>
      </:summary>
      <%= if @compact do %>
        <pre class="font-mono text-micro text-[var(--code-text)] whitespace-pre-wrap break-all leading-relaxed max-h-40 overflow-y-auto">{@body}</pre>
      <% else %>
        <div class="px-2.5 pb-2 pt-1 border-t border-[var(--border-subtle)]">
          <pre class="font-mono text-xs text-[var(--code-text)] whitespace-pre-wrap break-all leading-relaxed max-h-64 overflow-y-auto">{@body}</pre>
        </div>
      <% end %>
    </.tool_card_shell>
    """
  end

  # ---------------------------------------------------------------------------
  # tool_widget
  # ---------------------------------------------------------------------------

  attr :name, :string, required: true
  attr :rest, :string, required: true
  attr :compact, :boolean, default: false

  def tool_widget(assigns) do
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
    <.tool_card_shell compact={@compact} copy_text={@rest} copy_title="Copy input">
      <:summary>
        <.icon
          name={@icon}
          class={
            if @compact,
              do: "size-2.5 flex-shrink-0 text-base-content/20",
              else: "size-3.5 flex-shrink-0 text-base-content/35"
          }
        />
        <span class={
          if @compact,
            do:
              "text-micro font-mono font-semibold text-base-content/30 flex-shrink-0 uppercase tracking-wide",
            else:
              "text-mini font-mono font-semibold text-base-content/45 uppercase tracking-wide flex-shrink-0"
        }>
          {@label}
        </span>
        <span
          :if={@detail != "" && !@wrap_detail}
          class={
            if @compact,
              do: "text-micro font-mono text-base-content/25 truncate flex-1 min-w-0",
              else: "text-mini font-mono text-base-content/35 truncate flex-1 min-w-0"
          }
        >
          {@detail}
        </span>
      </:summary>
      <.tool_widget_body name={@name} rest={@rest} detail={@detail} input={@input} />
    </.tool_card_shell>
    """
  end

  # ---------------------------------------------------------------------------
  # tool_widget_body
  # ---------------------------------------------------------------------------

  attr :name, :string, required: true
  attr :rest, :string, required: true
  attr :detail, :string, required: true
  attr :input, :any, default: nil

  def tool_widget_body(assigns) do
    assigns = assign(assigns, :body_type, classify_body_type(assigns))

    ~H"""
    <%= case @body_type do %>
      <% :bash -> %>
        <div class="px-2.5 pb-2 pt-1 border-t border-[var(--border-subtle)]">
          <pre class="bg-[var(--surface-code)] rounded px-2 py-1.5 font-mono text-xs text-[var(--code-text)] whitespace-pre-wrap break-all leading-relaxed">{(@input && @input["command"]) || @detail}</pre>
        </div>
      <% :edit -> %>
        <div class="px-2.5 pb-2 pt-1 border-t border-[var(--border-subtle)] space-y-1.5">
          <div class="font-mono text-xs text-base-content/40 pb-0.5">{@input["file_path"]}</div>
          <pre class="bg-red-950/30 text-red-400/70 rounded px-2 py-1 font-mono text-xs whitespace-pre-wrap break-all leading-relaxed max-h-32 overflow-y-auto">{String.slice(@input["old_string"] || "", 0..500)}</pre>
          <pre class="bg-green-950/30 text-green-400/70 rounded px-2 py-1 font-mono text-xs whitespace-pre-wrap break-all leading-relaxed max-h-32 overflow-y-auto">{String.slice(@input["new_string"] || "", 0..500)}</pre>
        </div>
      <% :write -> %>
        <div class="px-2.5 pb-2 pt-1 border-t border-[var(--border-subtle)] space-y-1">
          <div class="font-mono text-xs text-[var(--text-ghost)] pb-0.5">{@input["file_path"]}</div>
          <pre class="bg-[var(--surface-code)] rounded px-2 py-1.5 font-mono text-xs text-[var(--code-text)] whitespace-pre-wrap break-all leading-relaxed max-h-48 overflow-y-auto">{String.slice(@input["content"] || "", 0..500)}{if String.length(@input["content"] || "") > 500, do: "\n…", else: ""}</pre>
        </div>
      <% :speak -> %>
        <div class="px-2.5 pb-2 pt-1 border-t border-[var(--border-subtle)]">
          <pre class="bg-[var(--surface-code)] rounded px-2 py-1.5 text-mini text-[var(--text-secondary)] whitespace-pre-wrap break-all leading-relaxed">{@detail}</pre>
        </div>
      <% :json -> %>
        <div class="px-2.5 pb-2 pt-1 border-t border-[var(--border-subtle)]">
          <pre class="font-mono text-xs text-[var(--text-muted)] whitespace-pre-wrap break-all leading-relaxed max-h-40 overflow-y-auto">{Jason.encode!(@input, pretty: true)}</pre>
        </div>
      <% :text -> %>
        <div class="px-2.5 pb-2 pt-1 border-t border-[var(--border-subtle)]">
          <pre class="font-mono text-xs text-[var(--text-muted)] whitespace-pre-wrap break-all leading-relaxed">{@rest}</pre>
        </div>
      <% :none -> %>
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # classify_body_type helpers
  # ---------------------------------------------------------------------------

  defp classify_body_type(assigns) do
    cond do
      bash_body?(assigns) -> :bash
      edit_body?(assigns) -> :edit
      write_body?(assigns) -> :write
      speak_body?(assigns) -> :speak
      json_body?(assigns) -> :json
      text_body?(assigns) -> :text
      true -> :none
    end
  end

  defp bash_body?(assigns), do: assigns.name == "Bash" and assigns.rest != ""

  defp edit_body?(assigns) do
    assigns.name == "Edit" and is_map(assigns.input) and
      Map.has_key?(assigns.input, "old_string")
  end

  defp write_body?(assigns) do
    assigns.name == "Write" and is_map(assigns.input) and
      Map.has_key?(assigns.input, "content")
  end

  defp speak_body?(assigns),
    do: String.ends_with?(assigns.name, "i-speak") and assigns.detail != ""

  defp json_body?(assigns) do
    is_map(assigns.input) and map_size(assigns.input) > 0 and
      assigns.name not in ["Read", "Glob", "Grep", "WebSearch", "Task"]
  end

  defp text_body?(assigns), do: assigns.rest != "" and assigns.rest != assigns.detail
end
