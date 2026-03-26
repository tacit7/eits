defmodule EyeInTheSkyWeb.DmLive.SlashCommands do
  @moduledoc """
  Parses inline slash commands from DM message bodies.

  Slash commands are lines matching `/command [args]`. They are extracted from
  the message body before it reaches Claude. Each command is routed as either:

  - `{:server, {atom, value}}` — applied to LiveView state (rename, model, effort)
  - `{:session, {atom, value}}` — stored in session_cli_opts and applied to every subsequent message
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
  @spec parse(String.t()) :: {[{atom(), String.t()}], [{atom(), term()}], String.t()}
  def parse(body) do
    lines = String.split(body, "\n")

    {server_cmds, session_opts, text_lines} =
      Enum.reduce(lines, {[], [], []}, fn line, {scmds, sopts, texts} ->
        trimmed = String.trim(line)

        case Regex.run(@slash_pattern, trimmed, capture: :all_but_first) do
          [cmd | rest] ->
            arg = List.first(rest) |> then(&if(&1 == "", do: nil, else: &1))

            case route(cmd, arg) do
              {:server, cmd_tuple} -> {scmds ++ [cmd_tuple], sopts, texts}
              {:session, sess_opt} -> {scmds, sopts ++ [sess_opt], texts}
              :unknown -> {scmds, sopts, texts ++ [line]}
            end

          nil ->
            {scmds, sopts, texts ++ [line]}
        end
      end)

    {server_cmds, session_opts, Enum.join(text_lines, "\n")}
  end

  # ---------------------------------------------------------------------------
  # Routing
  # ---------------------------------------------------------------------------

  # Server-side commands: handled directly in LiveView, not forwarded to Claude
  @doc false
  def route("rename", name) when is_binary(name), do: {:server, {:rename, name}}
  def route("model", model) when is_binary(model), do: {:server, {:model, model}}
  def route("effort", level) when is_binary(level), do: {:server, {:effort, level}}

  # Session-level CLI flags: stored in session_cli_opts and applied to every message
  def route("plan", _), do: {:session, {:permission_mode, "plan"}}
  def route("sandbox", _), do: {:session, {:sandbox, true}}
  # no-op: --no-sandbox only applies to remote-control mode; sandbox is off by default.
  # Still consumed so it doesn't leak into the message text.
  def route("no-sandbox", _), do: {:session, {:_noop, true}}
  def route("chrome", _), do: {:session, {:chrome, true}}
  def route("no-chrome", _), do: {:session, {:chrome, false}}

  def route("permissions", mode) when is_binary(mode),
    do: {:session, {:permission_mode, mode}}

  def route("mcp", file) when is_binary(file), do: {:session, {:mcp_config, file}}
  def route("add-dir", path) when is_binary(path), do: {:session, {:add_dir, path}}
  def route("plugin", path) when is_binary(path), do: {:session, {:plugin_dir, path}}
  def route("config", file) when is_binary(file), do: {:session, {:settings_file, file}}
  def route("agents", name) when is_binary(name), do: {:session, {:agent, name}}

  def route("max-turns", n) when is_binary(n) do
    case Integer.parse(n) do
      {int, ""} -> {:session, {:max_turns, int}}
      _ -> :unknown
    end
  end

  def route(_, _), do: :unknown
end
