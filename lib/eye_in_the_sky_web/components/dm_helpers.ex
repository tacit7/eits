defmodule EyeInTheSkyWeb.Components.DmHelpers do
  @moduledoc """
  Pure helper functions for the DM page component.

  All functions are stateless transformations -- no assigns, no HEEx.
  Imported by DmPage so existing template call-sites require no changes.
  """

  # ---------------------------------------------------------------------------
  # Message classification
  # ---------------------------------------------------------------------------

  def dm_message?(%{from_session_id: id}) when is_integer(id), do: true

  def dm_message?(%{metadata: %{"from_session_uuid" => uuid}})
      when is_binary(uuid) and uuid != "",
      do: true

  def dm_message?(_), do: false

  def message_sender_name(%{sender_role: "user"}), do: "You"

  def message_sender_name(%{metadata: %{"sender_name" => name}} = _msg)
      when is_binary(name) and name != "" do
    name
  end

  def message_sender_name(%{from_session_id: id}) when is_integer(id) do
    "session:#{id}"
  end

  def message_sender_name(message), do: message.provider || "Agent"

  # New format: [DM from agent: <name>]\n<body>\n\nReply: eits dm --to <id> --message ""
  # Legacy format: DM from:<name> (session:<uuid>) <body>

  def strip_dm_prefix(body) when is_binary(body) do
    cond do
      # New bracketed format — strip header and reply footer
      match = Regex.run(~r/^\[DM from agent: [^\]]+\]\n(.*?)(?:\n\nReply: eits dm --to \d+ --message "")?$/s, body) ->
        [_, content] = match
        String.trim(content)

      # Legacy format
      match = Regex.run(~r/^DM from:[^\(]+\(session:[^\)]+\)\s*(.*)$/s, body) ->
        [_, content] = match
        String.trim(content)

      true ->
        body
    end
  end

  def strip_dm_prefix(body), do: body

  def parse_dm_info(body) when is_binary(body) do
    cond do
      # New format: [DM from agent: <name>]\n...\n\nReply: eits dm --to <id> --message ""
      match = Regex.run(~r/^\[DM from agent: ([^\]]+)\]\n(.*?)(?:\n\nReply: eits dm --to (\d+) --message "")?$/s, body) ->
        case match do
          [_, sender, rest, session_id] ->
            rest = String.trim(rest)
            {status, url} = extract_dm_status_and_url(rest)
            %{sender: String.trim(sender), status: status, url: url, session_id: session_id, format: :agent}

          [_, sender, rest] ->
            rest = String.trim(rest)
            {status, url} = extract_dm_status_and_url(rest)
            %{sender: String.trim(sender), status: status, url: url, session_id: nil, format: :agent}
        end

      # Legacy format: DM from:<name> (session:<uuid>) <body>
      match = Regex.run(~r/^DM from:([^\(]+)\(session:[^\)]+\)\s*(.*)/s, body) ->
        [_, sender, rest] = match
        rest = String.trim(rest)
        {status, url} = extract_dm_status_and_url(rest)
        %{sender: String.trim(sender), status: status, url: url, session_id: nil, format: :legacy}

      true ->
        nil
    end
  end

  def parse_dm_info(_), do: nil

  defp extract_dm_status_and_url(text) do
    cond do
      match = Regex.run(~r/(?:^|\s)(done|completed|failed|error):\s*(https?:\/\/\S+)/i, text) ->
        [_, status, url] = match
        {String.downcase(status), url}

      match = Regex.run(~r/(https?:\/\/\S+)/, text) ->
        [_, url] = match
        {nil, url}

      true ->
        {nil, nil}
    end
  end

  def show_message_metrics?(message) do
    message.sender_role == "agent" and is_map(message.metadata) and
      not is_nil(message.metadata["total_cost_usd"])
  end

  # ---------------------------------------------------------------------------
  # Provider / icon helpers
  # ---------------------------------------------------------------------------

  def provider_icon("openai"), do: "/images/openai.svg"
  def provider_icon("codex"), do: "/images/openai.svg"
  def provider_icon(_), do: "/images/claude.svg"

  def provider_icon_class("openai"), do: "dark:invert"
  def provider_icon_class("codex"), do: "dark:invert"
  def provider_icon_class(_), do: ""

  def stream_provider_label(nil), do: "Agent"
  def stream_provider_label(%{provider: "codex"}), do: "Codex"
  def stream_provider_label(%{provider: "openai"}), do: "Codex"
  def stream_provider_label(_session), do: "Claude"

  # ---------------------------------------------------------------------------
  # Message model / cost extraction
  # ---------------------------------------------------------------------------

  def message_model(%{metadata: %{"model_usage" => model_usage}}) when is_map(model_usage) do
    case Map.keys(model_usage) do
      [model_id | _] -> format_model_id(model_id)
      _ -> nil
    end
  end

  def message_model(_), do: nil

  def message_cost(%{metadata: %{"total_cost_usd" => cost}}) when is_number(cost), do: cost
  def message_cost(_), do: nil

  def format_model_id(id) when is_binary(id) do
    cond do
      String.contains?(id, "opus") -> "opus"
      String.contains?(id, "sonnet") -> "sonnet"
      String.contains?(id, "haiku") -> "haiku"
      true -> id |> String.split("-") |> Enum.take(2) |> Enum.join("-")
    end
  end

  def format_model_id(_), do: nil

  # ---------------------------------------------------------------------------
  # Display name formatters
  # ---------------------------------------------------------------------------

  def model_display_name("claude-opus-4-7"), do: "Opus 4.7"
  def model_display_name("claude-opus-4-6"), do: "Opus 4.6"
  def model_display_name("claude-opus-4-5-20251101"), do: "Opus 4.5"
  def model_display_name("claude-opus-4-1-20250805"), do: "Opus 4.1"
  def model_display_name("claude-sonnet-4-6"), do: "Sonnet 4.6"
  def model_display_name("claude-sonnet-4-5-20250929"), do: "Sonnet 4.5"
  def model_display_name("claude-haiku-4-5-20251001"), do: "Haiku 4.5"
  # backward compat for sessions storing old slugs
  def model_display_name("opus"), do: "Opus 4.7"
  def model_display_name("opus[1m]"), do: "Opus 4.6 (1M)"
  def model_display_name("sonnet"), do: "Sonnet 4.6"
  def model_display_name("sonnet[1m]"), do: "Sonnet 4.5 (1M)"
  def model_display_name("haiku"), do: "Haiku 4.5"
  def model_display_name("gpt-5.4"), do: "gpt-5.4"
  def model_display_name("gpt-5.3-codex"), do: "gpt-5.3-codex"
  def model_display_name("gpt-5.2-codex"), do: "gpt-5.2-codex"
  def model_display_name("gpt-5.2"), do: "gpt-5.2"
  def model_display_name("gpt-5.1-codex-max"), do: "gpt-5.1-codex-max"
  def model_display_name("gpt-5.1-codex-mini"), do: "gpt-5.1-codex-mini"
  def model_display_name(other), do: other

  def effort_display_name("low"), do: "Low"
  def effort_display_name("medium"), do: "Medium"
  def effort_display_name("high"), do: "High"
  def effort_display_name("max"), do: "Max"
  def effort_display_name(_), do: "Medium"

  # ---------------------------------------------------------------------------
  # Number / size / time formatters
  # ---------------------------------------------------------------------------

  defdelegate format_size(bytes), to: EyeInTheSkyWeb.Helpers.FileHelpers

  def format_number(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end

  def format_number(_), do: "0"

  def to_utc_string(nil), do: ""
  def to_utc_string(ts) when is_binary(ts), do: ts
  def to_utc_string(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  def to_utc_string(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt) <> "Z"
  def to_utc_string(_), do: ""

  def format_checkpoint_time(nil), do: "—"

  def format_checkpoint_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%b %-d, %H:%M")
  end

  def format_checkpoint_time(_), do: "—"

  # ---------------------------------------------------------------------------
  # Text extraction
  # ---------------------------------------------------------------------------

  def extract_title(nil), do: "Untitled"

  def extract_title(body) when is_binary(body) do
    body
    |> String.trim()
    |> String.split("\n")
    |> List.first()
    |> String.replace(~r/^#+\s*/, "")
    |> String.slice(0..50)
    |> then(fn text ->
      if String.length(text) >= 50, do: text <> "...", else: text
    end)
  end

  def extract_commit_title(nil), do: "No message"

  def extract_commit_title(message) when is_binary(message) do
    message
    |> String.trim()
    |> String.split("\n")
    |> List.first()
    |> String.slice(0..60)
    |> then(fn text ->
      if String.length(text) >= 60, do: text <> "...", else: text
    end)
  end

  # ---------------------------------------------------------------------------
  # Tool widget parsing
  # ---------------------------------------------------------------------------

  @tool_meta %{
    "Bash" => {"hero-command-line", "Bash", "command"},
    "Read" => {"hero-document-text", "Read", "file_path"},
    "Write" => {"hero-pencil-square", "Write", "file_path"},
    "Edit" => {"hero-pencil-square", "Edit", "file_path"},
    "Glob" => {"hero-folder-open", "Glob", "pattern"},
    "Task" => {"hero-cpu-chip", "Task", "prompt"},
    "Grep" => {"hero-magnifying-glass", "Grep", "pattern"},
    "WebSearch" => {"hero-globe-alt", "WebSearch", "query"}
  }

  defp extract_param(rest, key) do
    case Jason.decode(rest) do
      {:ok, %{^key => val}} -> val
      _ -> rest
    end
  end

  def parse_body_segments(nil), do: [{:text, ""}]

  def parse_body_segments(body) when is_binary(body) do
    body
    |> String.trim()
    |> String.split(~r/\n\n/, trim: true)
    |> Enum.map(&parse_body_segment/1)
  end

  def parse_body_segment(text) do
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

  def tool_widget_meta("Bash", rest) do
    command =
      case Jason.decode(rest) do
        {:ok, %{"command" => cmd}} ->
          cmd

        _ ->
          case Regex.run(~r/^`(.+?)`/s, rest, capture: :all_but_first) do
            [cmd] -> cmd
            _ -> rest
          end
      end

    {"hero-command-line", "Bash", command}
  end

  def tool_widget_meta("Task", rest) do
    prompt =
      case Jason.decode(rest) do
        {:ok, %{"prompt" => p}} ->
          String.slice(p, 0..80) <> if(String.length(p) > 81, do: "…", else: "")

        _ ->
          rest
      end

    {"hero-cpu-chip", "Task", prompt}
  end

  def tool_widget_meta("Grep", rest) do
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

  def tool_widget_meta(name, rest) when is_binary(name) and binary_part(name, 0, 4) == "mcp_" do
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
            |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{String.slice(to_string(v), 0..40)}" end)

          {"hero-puzzle-piece", if(summary == "", do: rest, else: summary)}

        _ ->
          {"hero-puzzle-piece", rest}
      end

    {icon, short, detail}
  end

  def tool_widget_meta(name, rest) do
    case Map.get(@tool_meta, name) do
      {icon, label, key} -> {icon, label, extract_param(rest, key)}
      nil -> {"hero-wrench-screwdriver", name, rest}
    end
  end
end
