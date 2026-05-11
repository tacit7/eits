defmodule EyeInTheSkyWeb.Components.DmMessageComponents.ToolWidget do
  @moduledoc false

  use EyeInTheSkyWeb, :html

  import EyeInTheSkyWeb.Components.DmHelpers

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
        else:
          "group rounded-md border border-[var(--border-subtle)] bg-[var(--surface-card)] overflow-hidden"
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
