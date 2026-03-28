defmodule EyeInTheSkyWeb.DmLive.SlashCommands do
  @moduledoc """
  Single source of truth for CLI slash-command metadata and parsing.

  `command_metadata/0` returns the canonical list used by both the router
  (route/2 dispatch) and the slash-autocomplete UI (via SlashItems.cli_flags/0).

  Slash commands are lines matching `/command [args]`. They are extracted from
  the message body before it reaches Claude. Each command is routed as either:

  - `{:server, {atom, value}}` — applied to LiveView state (rename, model, effort)
  - `{:session, {atom, value}}` — stored in session_cli_opts and applied to every subsequent message
  - `:unknown` — left in the message text as-is
  """

  @commands [
    # {slug, arg_type, description}
    {"plan",        :none,                                                          "Force plan-only mode, no file changes"},
    {"sandbox",     :none,                                                          "Enable OS-level sandbox isolation"},
    {"no-sandbox",  :none,                                                          "Disable sandbox"},
    {"chrome",      :none,                                                          "Enable browser automation"},
    {"no-chrome",   :none,                                                          "Disable browser automation"},
    {"permissions", {:enum, ["default", "acceptEdits", "bypassPermissions", "dontAsk", "plan", "auto"]}, "Set permission mode"},
    {"effort",      {:enum, ["low", "medium", "high", "max"]},                      "Set effort level"},
    {"model",       {:enum, ["opus", "opus[1m]", "sonnet", "sonnet[1m]", "haiku",
                             "gpt-5.4", "gpt-5.3-codex", "gpt-5.2-codex",
                             "gpt-5.2", "gpt-5.1-codex-max", "gpt-5.1-codex-mini"]}, "Set model"},
    {"max-turns",   :integer,                                                       "Limit agentic steps"},
    {"add-dir",     :path,                                                          "Add extra working directory"},
    {"mcp",         :path,                                                          "Load MCP config file"},
    {"plugin",      :path,                                                          "Load plugins from directory"},
    {"config",      :path,                                                          "Load settings from file"},
    {"agents",      :free_text,                                                     "Run as named subagent"},
    {"rename",      :free_text,                                                     "Rename this session"},
  ]

  @doc "Returns the canonical command metadata list."
  def command_metadata, do: @commands

  @doc "Maps CLI option keys (string) to slash slugs."
  def opt_key_to_slug do
    %{
      "chrome"          => "chrome",
      "permission_mode" => "permissions",
      "sandbox"         => "sandbox",
      "mcp_config"      => "mcp",
      "add_dir"         => "add-dir",
      "plugin_dir"      => "plugin",
      "settings_file"   => "config",
      "agent"           => "agents",
      "max_turns"       => "max-turns",
    }
  end

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
  def route("plan", _), do: {:session, {:plan, true}}
  def route("sandbox", _), do: {:session, {:sandbox, true}}
  def route("no-sandbox", _), do: {:session, {:_clear, :sandbox}}
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
