defmodule EyeInTheSkyWeb.Components.DmPage.MessageToolWidget do
  @moduledoc false

  use EyeInTheSkyWeb, :html

  alias EyeInTheSkyWeb.Components.DmHelpers

  attr :name, :string, required: true
  attr :rest, :string, required: true

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

  defp tool_widget_meta(name, rest) do
    DmHelpers.tool_widget_meta(name, rest)
  end
end
