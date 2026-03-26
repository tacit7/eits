defmodule EyeInTheSkyWeb.DmLive.SlashCommands do
  @moduledoc """
  Parses inline slash commands from DM message bodies.

  Slash commands are lines matching `/command [args]`. They are extracted from
  the message body before it reaches Claude. Each command is routed as either:

  - `{:server, {atom, value}}` — applied to LiveView state (rename, model, effort)
  - `{:cli, {atom, value}}` — passed as CLI flags to AgentManager.continue_session
  - `:unknown` — left in the message text as-is
  """

  @slash_pattern ~r/^\/(\S+)(?:\s+(.+?))?$/m

  @doc """
  Parses slash commands from a message body.

  Returns `{server_commands, cli_opts, clean_body}` where:
  - `server_commands` — list of `{atom, value}` tuples for LiveView state updates
  - `cli_opts` — keyword list of CLI flag options
  - `clean_body` — remaining message text with slash command lines removed
  """
  @spec parse(String.t()) :: {[{atom(), String.t()}], keyword(), String.t()}
  def parse(body) do
    lines = String.split(body, "\n")

    {server_cmds, cli_opts, text_lines} =
      Enum.reduce(lines, {[], [], []}, fn line, {scmds, copts, texts} ->
        trimmed = String.trim(line)

        case Regex.run(@slash_pattern, trimmed, capture: :all_but_first) do
          [cmd | rest] ->
            arg = List.first(rest) |> then(&if(&1 == "", do: nil, else: &1))

            case route(cmd, arg) do
              {:server, cmd_tuple} -> {scmds ++ [cmd_tuple], copts, texts}
              {:cli, cli_opt} -> {scmds, copts ++ [cli_opt], texts}
              :unknown -> {scmds, copts, texts ++ [line]}
            end

          nil ->
            {scmds, copts, texts ++ [line]}
        end
      end)

    {server_cmds, cli_opts, Enum.join(text_lines, "\n")}
  end

  # ---------------------------------------------------------------------------
  # Routing
  # ---------------------------------------------------------------------------

  # Server-side commands: handled directly in LiveView, not forwarded to Claude
  @doc false
  def route("rename", name) when is_binary(name), do: {:server, {:rename, name}}
  def route("model", model) when is_binary(model), do: {:server, {:model, model}}
  def route("effort", level) when is_binary(level), do: {:server, {:effort, level}}

  # CLI flag commands: translated to keyword list opts for continue_session
  def route("plan", _), do: {:cli, {:permission_mode, "plan"}}
  def route("sandbox", _), do: {:cli, {:sandbox, true}}
  # no-op: --no-sandbox only applies to remote-control mode; sandbox is off by default.
  # Still consumed so it doesn't leak into the message text.
  def route("no-sandbox", _), do: {:cli, {:_noop, true}}
  def route("chrome", _), do: {:cli, {:chrome, true}}
  def route("no-chrome", _), do: {:cli, {:chrome, false}}

  def route("permissions", mode) when is_binary(mode),
    do: {:cli, {:permission_mode, mode}}

  def route("mcp", file) when is_binary(file), do: {:cli, {:mcp_config, file}}
  def route("add-dir", path) when is_binary(path), do: {:cli, {:add_dir, path}}
  def route("plugin", path) when is_binary(path), do: {:cli, {:plugin_dir, path}}
  def route("config", file) when is_binary(file), do: {:cli, {:settings_file, file}}
  def route("agents", name) when is_binary(name), do: {:cli, {:agent, name}}

  def route("max-turns", n) when is_binary(n) do
    case Integer.parse(n) do
      {int, ""} -> {:cli, {:max_turns, int}}
      _ -> :unknown
    end
  end

  def route(_, _), do: :unknown
end
