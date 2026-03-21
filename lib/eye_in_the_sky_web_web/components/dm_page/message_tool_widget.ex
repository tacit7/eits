defmodule EyeInTheSkyWebWeb.Components.DmPage.MessageToolWidget do
  @moduledoc false

  use EyeInTheSkyWebWeb, :html

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
