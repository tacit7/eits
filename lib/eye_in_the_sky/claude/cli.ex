defmodule EyeInTheSky.Claude.CLI do
  @moduledoc """
  Claude CLI subprocess spawner.

  Spawns `claude` binary as a Port with pseudo-TTY via `script` wrapper
  and streams stdout back to the caller via message passing.

  ## Spawning

  All public functions accept a keyword list of options that map directly
  to CLI flags via `build_args/1`. Callers describe what they want; this
  module figures out the flags.

  ## Messages sent to caller

    * `{:claude_output, session_ref, line}` - each line of stdout
    * `{:claude_exit, session_ref, exit_code}` - process exited
  """

  require Logger

  alias EyeInTheSky.Claude.BinaryFinder

  # ---------------------------------------------------------------------------
  # Types and constants
  # ---------------------------------------------------------------------------

  @type cli_opts :: keyword()
  @type spawn_result :: {:ok, port(), reference()} | {:error, term()}

  @known_permission_modes ~w(acceptEdits bypassPermissions default delegate dontAsk plan)
  @fallback_idle_timeout_ms :infinity
  @max_buffer_bytes 4 * 1024 * 1024
  @redacted_flags ~w(-p --system-prompt --append-system-prompt)
  @persistent_term_key {__MODULE__, :claude_binary_path}

  # ---------------------------------------------------------------------------
  # Public spawners
  # ---------------------------------------------------------------------------

  @doc """
  Spawns a new Claude session.

  Does NOT pass --session-id flag. Claude will generate a UUID and return it
  in the output. Caller should parse the session ID from Claude's response.
  """
  @spec spawn_new_session(String.t(), cli_opts()) :: spawn_result()
  def spawn_new_session(prompt, opts \\ []) do
    opts
    |> Keyword.put(:prompt, prompt)
    |> spawn_cli()
  end

  @doc """
  Resumes a specific session by UUID (passes `--resume` flag).
  """
  @spec resume_session(String.t(), String.t(), cli_opts()) :: spawn_result()
  def resume_session(session_id, prompt, opts \\ []) do
    opts
    |> Keyword.put(:prompt, prompt)
    |> Keyword.put(:resume, session_id)
    |> spawn_cli()
  end

  @doc """
  Cancels a running Claude process by killing the OS process group, then closing the port.

  Port.close/1 alone only closes file descriptors; the subprocess may keep running.
  Delegates to `EyeInTheSky.CLI.Port.cancel_port/2` which sends SIGTERM to both
  the process group and direct PID, then escalates to SIGKILL if needed.
  """
  @spec cancel(port()) :: :ok
  def cancel(port) when is_port(port) do
    EyeInTheSky.CLI.Port.cancel_port(port, "CLI")
  end

  # ---------------------------------------------------------------------------
  # Normalization & validation
  # ---------------------------------------------------------------------------

  @doc """
  Normalize key aliases and coerce types before validation.

  - `:allowed_tools` is converted to `:allowedTools`
  - String booleans `"true"`/`"false"` are coerced to actual booleans
    for `:skip_permissions` and `:verbose`
  """
  @spec normalize_opts(cli_opts()) :: cli_opts()
  def normalize_opts(opts) do
    opts
    |> normalize_allowed_tools()
    |> coerce_booleans([:skip_permissions, :verbose])
  end

  defp normalize_allowed_tools(opts) do
    case Keyword.pop(opts, :allowed_tools) do
      {nil, rest} -> rest
      {val, rest} -> Keyword.put_new(rest, :allowedTools, val)
    end
  end

  defp coerce_booleans(opts, keys) do
    Enum.reduce(keys, opts, fn key, acc ->
      case Keyword.fetch(acc, key) do
        {:ok, "true"} -> Keyword.put(acc, key, true)
        {:ok, "false"} -> Keyword.put(acc, key, false)
        _ -> acc
      end
    end)
  end

  @doc """
  Validate option values. Returns `:ok` or `{:error, {key, reason}}`.

  - `:prompt` must be a non-empty binary when present (nil is allowed)
  - `:max_turns` must be a positive integer when present
  - `:permission_mode` must be a known mode or nil/""
  - Boolean keys must be actual booleans when present
  """
  @spec validate_opts(cli_opts()) :: :ok | {:error, {atom(), String.t()}}
  def validate_opts(opts) do
    with :ok <- validate_prompt(opts[:prompt]),
         :ok <- validate_max_turns(opts[:max_turns]),
         :ok <- validate_permission_mode(opts[:permission_mode]),
         :ok <- validate_boolean(opts, :skip_permissions) do
      validate_boolean(opts, :verbose)
    end
  end

  defp validate_prompt(nil), do: :ok
  defp validate_prompt(p) when is_binary(p) and byte_size(p) > 0, do: :ok
  defp validate_prompt(""), do: {:error, {:prompt, "must be a non-empty string"}}
  defp validate_prompt(_), do: {:error, {:prompt, "must be a non-empty string"}}

  defp validate_max_turns(nil), do: :ok
  defp validate_max_turns(n) when is_integer(n) and n > 0, do: :ok
  defp validate_max_turns(_), do: {:error, {:max_turns, "must be a positive integer"}}

  defp validate_permission_mode(nil), do: :ok
  defp validate_permission_mode(""), do: :ok

  defp validate_permission_mode(mode) when is_binary(mode) do
    if mode in @known_permission_modes,
      do: :ok,
      else: {:error, {:permission_mode, "unknown mode: #{mode}"}}
  end

  defp validate_permission_mode(_), do: {:error, {:permission_mode, "must be a string"}}

  defp validate_boolean(opts, key) do
    case Keyword.fetch(opts, key) do
      :error -> :ok
      {:ok, v} when is_boolean(v) -> :ok
      {:ok, _} -> {:error, {key, "must be a boolean"}}
    end
  end

  # ---------------------------------------------------------------------------
  # Safe logging
  # ---------------------------------------------------------------------------

  @doc """
  Returns the full CLI command as a string for debugging/inspection.

  Includes the `script` wrapper, claude binary path, and all args.
  Sensitive values (flags in `#{inspect(@redacted_flags)}`) are redacted.
  """
  @spec cmd(cli_opts()) :: {:ok, String.t()} | {:error, term()}
  def cmd(opts \\ []) do
    case find_claude_binary() do
      {:ok, claude_path} ->
        args = build_args(opts)
        full = ["/usr/bin/script", "-q", "/dev/null", claude_path | safe_log_args(args)]
        {:ok, Enum.join(full, " ")}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec safe_log_args([String.t()]) :: [String.t()]
  def safe_log_args([]), do: []

  def safe_log_args([flag, _value | rest]) when flag in @redacted_flags,
    do: [flag, "[REDACTED]" | safe_log_args(rest)]

  def safe_log_args([head | rest]), do: [head | safe_log_args(rest)]

  # ---------------------------------------------------------------------------
  # Arg builder
  # ---------------------------------------------------------------------------

  # Normalize model names from simple identifiers to full Claude model identifiers.
  # Maps EITS's simple model names to current Claude API model identifiers:
  # - "haiku" -> "claude-haiku-4-5"
  # - "sonnet" -> "claude-sonnet-4-6"
  # - "opus" -> "claude-opus-4-6"
  # Other model names are passed through unchanged.
  @spec normalize_model_name(String.t() | nil) :: String.t() | nil
  defp normalize_model_name(nil), do: nil

  defp normalize_model_name(model) when is_binary(model) do
    case String.downcase(model) do
      "haiku" -> "claude-haiku-4-5"
      "sonnet" -> "claude-sonnet-4-6"
      "opus" -> "claude-opus-4-6"
      _ -> model
    end
  end

  @doc """
  Builds a flat list of CLI args from a keyword list.

  Supported keys (all optional unless noted):

    * `:prompt` (required) - the user prompt, becomes `-p <prompt>`
    * `:session_id` - `--session-id <id>` (for new sessions)
    * `:resume` - `--resume <session_id>`
    * `:model` - `--model <model>`
    * `:output_format` - `--output-format <fmt>` (default: "stream-json")
    * `:verbose` - `--verbose` (forced true when output_format is "stream-json")
    * `:skip_permissions` - `--dangerously-skip-permissions` (default: true)
    * `:max_turns` - `--max-turns <n>`
    * `:system_prompt` - `--system-prompt <text>`
    * `:append_system_prompt` - `--append-system-prompt <text>`
    * `:allowedTools` - `--allowedTools <csv>`
    * `:permission_mode` - `--permission-mode <mode>`
    * `:mcp_config` - `--mcp-config <path>`
    * `:add_dir` - `--add-dir <path>`
    * `:plugin_dir` - `--plugin-dir <path>`
    * `:settings_file` - `--settings <file>`
    * `:name` - `--name <name>` (session display name)
    * `:sandbox` - `true` → `--sandbox` (OS-level isolation; off by default, --no-sandbox is remote-control only)
    * `:chrome` - `true` → `--chrome`, `false` → `--no-chrome`

  Unknown keys are silently ignored (they may be used by env/caller logic).
  """
  @spec build_args(cli_opts()) :: [String.t()]
  def build_args(caller_opts) do
    # Filter nils from caller opts (nil = "not specified", allows DB/fallback to win)
    caller = Keyword.filter(caller_opts, fn {_k, v} -> v != nil end)

    # Three-way merge: hardcoded fallbacks < DB settings < caller opts
    opts =
      [output_format: "stream-json"]
      |> Keyword.merge(cli_db_defaults())
      |> Keyword.merge(caller)

    args = []

    # Session mode flags (mutually exclusive: resume > new)
    args =
      cond do
        resume_id = opts[:resume] ->
          args ++ ["--resume", to_string(resume_id)]

        session_id = opts[:session_id] ->
          args ++ ["--session-id", to_string(session_id)]

        true ->
          args
      end

    # Prompt
    args = args ++ ["-p", opts[:prompt]]

    # Value flags
    args = maybe_flag(args, "--output-format", opts[:output_format])
    args = maybe_flag(args, "--model", normalize_model_name(opts[:model]))
    args = maybe_flag(args, "--max-turns", opts[:max_turns])
    args = maybe_flag(args, "--system-prompt", opts[:system_prompt])
    args = maybe_flag(args, "--append-system-prompt", opts[:append_system_prompt])
    args = maybe_flag(args, "--allowedTools", opts[:allowedTools])
    args = maybe_flag(args, "--permission-mode", opts[:permission_mode])
    args = maybe_flag(args, "--mcp-config", opts[:mcp_config])
    args = maybe_flag(args, "--thinking-budget-tokens", opts[:thinking_budget])
    args = maybe_flag(args, "--max-budget-usd", opts[:max_budget_usd])
    args = maybe_flag(args, "--agent", opts[:agent])
    args = maybe_flag(args, "--add-dir", opts[:add_dir])
    args = maybe_flag(args, "--plugin-dir", opts[:plugin_dir])
    args = maybe_flag(args, "--settings", opts[:settings_file])
    args = maybe_flag(args, "--name", opts[:name])

    # Boolean flags — use maybe_bool_flag/3 for consistency with maybe_flag/3
    # stream-json requires --verbose for proper output parsing
    verbose = opts[:verbose] || opts[:output_format] == "stream-json"
    # --sandbox enables OS-level isolation; --no-sandbox is remote-control only (sandbox off by default)
    args =
      args
      |> maybe_bool_flag("--verbose", verbose)
      |> maybe_bool_flag("--dangerously-skip-permissions", opts[:skip_permissions])
      |> maybe_bool_flag("--sandbox", opts[:sandbox] == true)
      |> maybe_bool_flag("--chrome", opts[:chrome] == true)
      |> maybe_bool_flag("--no-chrome", opts[:chrome] == false)
      |> maybe_bool_flag("--include-partial-messages", opts[:include_partial_messages])

    # When multimodal content blocks are present, switch to stdin input mode.
    # do_spawn reads :content_blocks_json from opts and pipes it via stdin.
    args =
      if has_content_blocks?(opts) do
        args ++ ["--input-format", "stream-json"]
      else
        args
      end

    args
  end

  @doc """
  Serializes content blocks to a JSON message suitable for Claude CLI stdin input.

  Returns `nil` when no content blocks are present (text-only message).
  When content blocks exist, returns a JSON string containing a user message
  with the text prompt and all formatted content blocks as the content array.
  """
  @spec content_blocks_json(keyword()) :: String.t() | nil
  def content_blocks_json(opts) do
    case Keyword.get(opts, :content_blocks, []) do
      [] ->
        nil

      blocks when is_list(blocks) ->
        prompt = Keyword.get(opts, :prompt, "")

        content = [%{"type" => "text", "text" => prompt} | blocks]
        message = %{"type" => "user", "content" => content}
        Jason.encode!(message)
    end
  end

  defp has_content_blocks?(opts) do
    case Keyword.get(opts, :content_blocks, []) do
      [] -> false
      blocks when is_list(blocks) -> true
      _ -> false
    end
  end

  defp maybe_pipe_content_blocks(port, opts) do
    case content_blocks_json(opts) do
      nil -> :ok
      json ->
        Port.command(port, json <> "\n")
        Logger.info("[CLI] Piped multimodal content blocks to stdin (#{byte_size(json)} bytes)")
    end
  end

  defp maybe_flag(args, _flag, nil), do: args
  defp maybe_flag(args, _flag, ""), do: args
  defp maybe_flag(args, flag, value), do: args ++ [flag, to_string(value)]

  defp maybe_bool_flag(args, _flag, falsy) when falsy in [nil, false], do: args
  defp maybe_bool_flag(args, flag, _truthy), do: args ++ [flag]

  defp cli_db_defaults do
    alias EyeInTheSky.Settings
    alias EyeInTheSky.Utils.ToolHelpers

    [
      model: Settings.get("model"),
      permission_mode: Settings.get("permission_mode"),
      max_turns: ToolHelpers.parse_int(Settings.get("max_turns")),
      output_format: Settings.get("output_format"),
      skip_permissions: parse_setting_boolean(Settings.get("skip_permissions"))
    ]
    |> Keyword.filter(fn {_k, v} -> v != nil end)
  rescue
    DBConnection.ConnectionError ->
      Logger.warning("[cli_db_defaults] DB unavailable, using empty defaults")
      []
  end

  defp parse_setting_boolean(nil), do: nil
  defp parse_setting_boolean("true"), do: true
  defp parse_setting_boolean("false"), do: false
  defp parse_setting_boolean(_), do: nil

  # ---------------------------------------------------------------------------
  # Binary cache
  # ---------------------------------------------------------------------------

  @doc """
  Clear the cached binary path. Useful in tests.
  """
  @spec clear_binary_cache() :: :ok
  def clear_binary_cache do
    EyeInTheSky.CLI.Port.clear_binary_cache(@persistent_term_key)
  end

  # ---------------------------------------------------------------------------
  # Port spawning (single path)
  # ---------------------------------------------------------------------------

  defp spawn_cli(opts) do
    opts = normalize_opts(opts)
    merged = Keyword.filter(opts, fn {_k, v} -> v != nil end)

    case validate_opts(merged) do
      {:error, _} = err ->
        err

      :ok ->
        project_path =
          merged
          |> Keyword.get(:project_path, File.cwd!())
          |> Path.expand()

        if File.dir?(project_path) do
          do_spawn(merged, project_path)
        else
          {:error, {:invalid_project_path, project_path}}
        end
    end
  end

  defp do_spawn(opts, project_path) do
    caller = Keyword.get(opts, :caller, self())
    session_ref = Keyword.get(opts, :session_ref, make_ref())
    idle_timeout_ms = resolve_idle_timeout(opts)

    case find_claude_binary() do
      {:ok, claude_path} ->
        args = build_args(opts)

        cmd_string = "claude " <> Enum.join(safe_log_args(args), " ")
        Logger.info("Spawning Claude in #{project_path}: #{cmd_string}")

        Logger.info(
          "CLI env: CLAUDE_CODE_EFFORT_LEVEL=#{inspect(opts[:effort_level])} max_budget_usd=#{inspect(opts[:max_budget_usd])}"
        )

        handler_pid =
          spawn_link(fn ->
            receive do
              {:port, port} ->
                EyeInTheSky.CLI.Port.handle_port_output(
                  port,
                  session_ref,
                  caller,
                  "",
                  idle_timeout_ms,
                  telemetry_prefix: [:eits, :cli],
                  log_prefix: "CLI",
                  max_buffer_bytes: @max_buffer_bytes
                )
            end
          end)

        env = build_env(opts)
        use_script = Keyword.get(opts, :use_script, true)

        port =
          if use_script,
            do: open_script_port(claude_path, args, project_path, env),
            else: open_direct_port(claude_path, args, project_path, env)

        # When multimodal content blocks are present, pipe the JSON user message
        # to stdin before handing the port to the handler. This feeds Claude CLI
        # the structured content via --input-format stream-json.
        maybe_pipe_content_blocks(port, opts)

        Port.connect(port, handler_pid)
        send(handler_pid, {:port, port})

        :telemetry.execute([:eits, :cli, :spawn], %{system_time: System.system_time()}, %{
          project_path: project_path,
          use_script: Keyword.get(opts, :use_script, true),
          model: opts[:model]
        })

        Logger.info("[telemetry] cli.spawn project_path=#{project_path} model=#{opts[:model]}")

        {:ok, port, session_ref}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Resolves the idle timeout from settings and caller opts.
  defp resolve_idle_timeout(opts) do
    EyeInTheSky.CLI.Port.resolve_idle_timeout(opts, @fallback_idle_timeout_ms)
  end

  # Opens a port using the `script` wrapper for interactive sessions.
  defp open_script_port(claude_path, args, project_path, env) do
    script_args = ["-q", "/dev/null", claude_path] ++ args

    Port.open(
      {:spawn_executable, "/usr/bin/script"},
      [
        :binary,
        :exit_status,
        :use_stdio,
        :stderr_to_stdout,
        {:args, script_args},
        {:cd, project_path},
        {:env, env}
      ]
    )
  end

  # Spawns Claude directly without the script wrapper (used by AgentWorker).
  defp open_direct_port(claude_path, args, project_path, env) do
    Port.open(
      {:spawn_executable, claude_path},
      [
        :binary,
        :exit_status,
        :use_stdio,
        :stderr_to_stdout,
        {:args, args},
        {:cd, project_path},
        {:env, env}
      ]
    )
  end

  # ---------------------------------------------------------------------------
  # Environment
  # ---------------------------------------------------------------------------

  defp build_env(opts) do
    # Strip vars that prevent nested Claude sessions from starting, and
    # ANTHROPIC_API_KEY so spawned processes use Max plan OAuth instead of
    # a (potentially empty) API key that may be in the server's environment.
    blocked_vars = ~w[CLAUDECODE CLAUDE_CODE_ENTRYPOINT ANTHROPIC_API_KEY]

    # Pass through system environment
    base_env =
      for {key, value} <- System.get_env(),
          value != "",
          key not in blocked_vars do
        {String.to_charlist(key), String.to_charlist(value)}
      end

    env = [
      {~c"CI", ~c"true"},
      {~c"TERM", ~c"dumb"}
      | base_env
    ]

    env = maybe_add_env(env, "EITS_SESSION_ID", opts[:eits_session_id])
    env = maybe_add_env(env, "EITS_AGENT_ID", opts[:eits_agent_id])
    env = maybe_add_env(env, "EITS_WORKFLOW", opts[:eits_workflow] || "1")
    maybe_add_env(env, "CLAUDE_CODE_EFFORT_LEVEL", opts[:effort_level])
  end

  defp maybe_add_env(env, key, value) do
    EyeInTheSky.CLI.Port.maybe_add_env(env, key, value)
  end

  # ---------------------------------------------------------------------------
  # Binary locator (cached via :persistent_term)
  # ---------------------------------------------------------------------------

  defp find_claude_binary do
    EyeInTheSky.CLI.Port.find_binary(@persistent_term_key, &BinaryFinder.find/0)
  end
end
