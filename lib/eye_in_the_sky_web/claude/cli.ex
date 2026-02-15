defmodule EyeInTheSkyWeb.Claude.CLI do
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

  # ---------------------------------------------------------------------------
  # Types and constants
  # ---------------------------------------------------------------------------

  @type cli_opts :: keyword()
  @type spawn_result :: {:ok, port(), reference()} | {:error, term()}

  @known_permission_modes ~w(acceptEdits bypassPermissions default delegate dontAsk plan)
  @default_idle_timeout_ms 300_000
  @standard_paths [
    "/usr/local/bin/claude",
    "/opt/homebrew/bin/claude",
    Path.expand("~/.local/bin/claude")
  ]
  @redacted_flags ~w(--system-prompt --append-system-prompt)
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
  Cancels a running Claude process by closing its port.
  """
  @spec cancel(port()) :: :ok
  def cancel(port) when is_port(port) do
    Port.close(port)
    :ok
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
         :ok <- validate_boolean(opts, :skip_permissions),
         :ok <- validate_boolean(opts, :verbose) do
      :ok
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
  Redact sensitive flag values from an args list for safe logging.

  Flags in `#{inspect(@redacted_flags)}` have their following value replaced
  with `"[REDACTED]"`.
  """
  @doc """
  Returns the full CLI command as a string for debugging/inspection.

  Includes the `script` wrapper, claude binary path, and all args.
  Sensitive values are redacted.
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

  Unknown keys are silently ignored (they may be used by env/caller logic).
  """
  @spec build_args(cli_opts()) :: [String.t()]
  def build_args(caller_opts) do
    # Filter nils from caller opts
    opts = Keyword.filter(caller_opts, fn {_k, v} -> v != nil end)
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
    args = maybe_flag(args, "--model", opts[:model])
    args = maybe_flag(args, "--max-turns", opts[:max_turns])
    args = maybe_flag(args, "--system-prompt", opts[:system_prompt])
    args = maybe_flag(args, "--append-system-prompt", opts[:append_system_prompt])
    args = maybe_flag(args, "--allowedTools", opts[:allowedTools])
    args = maybe_flag(args, "--permission-mode", opts[:permission_mode])
    args = maybe_flag(args, "--mcp-config", opts[:mcp_config])

    # Boolean flags
    # stream-json requires --verbose for proper output parsing
    verbose = opts[:verbose] || opts[:output_format] == "stream-json"
    args = if verbose, do: args ++ ["--verbose"], else: args
    args = if opts[:skip_permissions], do: args ++ ["--dangerously-skip-permissions"], else: args

    args
  end

  defp maybe_flag(args, _flag, nil), do: args
  defp maybe_flag(args, _flag, ""), do: args
  defp maybe_flag(args, flag, value), do: args ++ [flag, to_string(value)]

  # ---------------------------------------------------------------------------
  # Binary cache
  # ---------------------------------------------------------------------------

  @doc """
  Clear the cached binary path. Useful in tests.
  """
  @spec clear_binary_cache() :: :ok
  def clear_binary_cache do
    :persistent_term.erase(@persistent_term_key)
    :ok
  rescue
    ArgumentError -> :ok
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
        project_path = Keyword.get(merged, :project_path, File.cwd!())

        if !File.dir?(project_path) do
          {:error, {:invalid_project_path, project_path}}
        else
          do_spawn(merged, project_path)
        end
    end
  end

  defp do_spawn(opts, project_path) do
    caller = Keyword.get(opts, :caller, self())
    session_ref = Keyword.get(opts, :session_ref, make_ref())

    idle_timeout_ms =
      case Keyword.get(opts, :idle_timeout_ms, @default_idle_timeout_ms) do
        n when is_integer(n) and n > 0 -> n
        _ -> @default_idle_timeout_ms
      end

    case find_claude_binary() do
      {:ok, claude_path} ->
        args = build_args(opts)

        cmd_string = "claude " <> Enum.join(safe_log_args(args), " ")
        Logger.info("Spawning Claude in #{project_path}: #{cmd_string}")

        handler_pid =
          spawn_link(fn ->
            receive do
              {:port, port} -> handle_port_output(port, session_ref, caller, "", idle_timeout_ms)
            end
          end)

        env = build_env(opts)
        use_script = Keyword.get(opts, :use_script, true)

        port =
          if use_script do
            # Use script wrapper for interactive sessions (SessionWorker)
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
          else
            # Spawn Claude directly for background agents (AgentWorker)
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

  # ---------------------------------------------------------------------------
  # Environment
  # ---------------------------------------------------------------------------

  defp build_env(opts) do
    # Pass through system environment
    base_env =
      for {key, value} <- System.get_env(),
          value != "" do
        {String.to_charlist(key), String.to_charlist(value)}
      end

    env = [
      {~c"CI", ~c"true"},
      {~c"TERM", ~c"dumb"}
      | base_env
    ]

    env = maybe_add_env(env, "EITS_SESSION_ID", opts[:eits_session_id])
    env = maybe_add_env(env, "EITS_AGENT_ID", opts[:eits_agent_id])
    maybe_add_env(env, "CLAUDE_CODE_EFFORT_LEVEL", opts[:effort_level])
  end

  defp maybe_add_env(env, _key, nil), do: env
  defp maybe_add_env(env, _key, ""), do: env

  defp maybe_add_env(env, key, value) do
    env ++ [{String.to_charlist(key), String.to_charlist(to_string(value))}]
  end

  # ---------------------------------------------------------------------------
  # Port output handler
  # ---------------------------------------------------------------------------

  defp handle_port_output(port, session_ref, caller, buffer, idle_timeout_ms) do
    receive do
      {^port, {:data, data}} ->
        new_buffer = buffer <> data
        lines = String.split(new_buffer, "\n")

        {complete_lines, remaining} =
          case List.pop_at(lines, -1) do
            {last, rest} ->
              if String.ends_with?(data, "\n"),
                do: {lines, ""},
                else: {rest, last || ""}
          end

        Enum.each(complete_lines, fn line ->
          unless line == "" do
            send(caller, {:claude_output, session_ref, line})
          end
        end)

        handle_port_output(port, session_ref, caller, remaining, idle_timeout_ms)

      {^port, {:exit_status, status}} ->
        unless buffer == "" do
          send(caller, {:claude_output, session_ref, buffer})
        end

        Logger.info("Claude process exited with status #{status}")
        :telemetry.execute([:eits, :cli, :exit], %{exit_code: status}, %{})
        Logger.info("[telemetry] cli.exit exit_code=#{status}")
        send(caller, {:claude_exit, session_ref, status})
        :ok
    after
      idle_timeout_ms ->
        Logger.warning(
          "No output from Claude after #{div(idle_timeout_ms, 60_000)} minutes, timing out"
        )

        :telemetry.execute([:eits, :cli, :timeout], %{system_time: System.system_time()}, %{
          timeout_ms: idle_timeout_ms
        })

        Logger.warning("[telemetry] cli.timeout after #{div(idle_timeout_ms, 1000)}s")
        Port.close(port)
        send(caller, {:claude_exit, session_ref, :timeout})
        :ok
    end
  end

  # ---------------------------------------------------------------------------
  # Binary locator (cached via :persistent_term)
  # ---------------------------------------------------------------------------

  defp find_claude_binary do
    case :persistent_term.get(@persistent_term_key, :not_cached) do
      :not_cached ->
        case do_find_claude_binary() do
          {:ok, path} = ok ->
            :persistent_term.put(@persistent_term_key, path)
            ok

          error ->
            error
        end

      cached_path ->
        if File.exists?(cached_path) do
          {:ok, cached_path}
        else
          :persistent_term.erase(@persistent_term_key)
          find_claude_binary()
        end
    end
  end

  defp do_find_claude_binary do
    nvm_dir = System.get_env("NVM_DIR") || Path.expand("~/.nvm")

    cond do
      path = System.find_executable("claude") ->
        {:ok, path}

      path = find_in_standard_paths() ->
        {:ok, path}

      path = find_in_nvm() ->
        {:ok, path}

      true ->
        {:error, {:binary_not_found, checked_paths: @standard_paths, nvm_dir: nvm_dir}}
    end
  end

  defp find_in_standard_paths do
    @standard_paths
    |> Enum.find(&File.exists?/1)
  end

  defp find_in_nvm do
    nvm_dir = System.get_env("NVM_DIR") || Path.expand("~/.nvm")
    versions_dir = Path.join(nvm_dir, "versions/node")

    if File.dir?(versions_dir) do
      versions_dir
      |> File.ls!()
      |> Enum.filter(&semver_dir?/1)
      |> Enum.sort_by(&parse_version/1, {:desc, Version})
      |> Enum.find_value(fn dir ->
        path = Path.join([versions_dir, dir, "bin", "claude"])
        if File.exists?(path), do: path
      end)
    else
      nil
    end
  end

  defp semver_dir?("v" <> rest), do: match?({:ok, _}, Version.parse(rest))
  defp semver_dir?(_), do: false

  defp parse_version("v" <> rest) do
    case Version.parse(rest) do
      {:ok, v} -> v
      :error -> Version.parse!("0.0.0")
    end
  end
end
