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

  ## Sub-modules

    * `EyeInTheSky.Claude.CLI.Args` — argument building, normalization, and validation
    * `EyeInTheSky.Claude.CLI.Env` — OS environment construction for spawned processes
  """

  require Logger

  alias EyeInTheSky.Claude.BinaryFinder
  alias EyeInTheSky.Claude.CLI.Args
  alias EyeInTheSky.Claude.CLI.Env

  # ---------------------------------------------------------------------------
  # Types and constants
  # ---------------------------------------------------------------------------

  @type cli_opts :: keyword()
  @type spawn_result :: {:ok, port(), reference()} | {:error, term()}

  @fallback_idle_timeout_ms :infinity
  @max_buffer_bytes 4 * 1024 * 1024
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
  # Normalization & validation (delegates to Args)
  # ---------------------------------------------------------------------------

  @doc """
  Normalize key aliases and coerce types before validation.

  - `:allowed_tools` is converted to `:allowedTools`
  - String booleans `"true"`/`"false"` are coerced to actual booleans
    for `:skip_permissions` and `:verbose`
  """
  @spec normalize_opts(cli_opts()) :: cli_opts()
  defdelegate normalize_opts(opts), to: Args

  @doc """
  Validate option values. Returns `:ok` or `{:error, {key, reason}}`.

  - `:prompt` must be a non-empty binary when present (nil is allowed)
  - `:max_turns` must be a positive integer when present
  - `:permission_mode` must be a known mode or nil/""
  - Boolean keys must be actual booleans when present
  """
  @spec validate_opts(cli_opts()) :: :ok | {:error, {atom(), String.t()}}
  defdelegate validate_opts(opts), to: Args

  # ---------------------------------------------------------------------------
  # Safe logging (delegates to Args)
  # ---------------------------------------------------------------------------

  @doc """
  Returns the full CLI command as a string for debugging/inspection.

  Includes the `script` wrapper, claude binary path, and all args.
  Sensitive values (`-p`, `--system-prompt`, `--append-system-prompt`) are redacted.
  """
  @spec cmd(cli_opts()) :: {:ok, String.t()} | {:error, term()}
  def cmd(opts \\ []) do
    case find_claude_binary() do
      {:ok, claude_path} ->
        args = Args.build_args(opts)
        full = ["/usr/bin/script", "-q", "/dev/null", claude_path | Args.safe_log_args(args)]
        {:ok, Enum.join(full, " ")}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Redacts sensitive flag values from a CLI arg list for safe logging.
  """
  @spec safe_log_args([String.t()]) :: [String.t()]
  defdelegate safe_log_args(args), to: Args

  # ---------------------------------------------------------------------------
  # Arg builder (delegates to Args)
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
    * `:add_dir` - `--add-dir <path>`
    * `:plugin_dir` - `--plugin-dir <path>`
    * `:settings_file` - `--settings <file>`
    * `:name` - `--name <name>` (session display name)
    * `:sandbox` - `true` → `--sandbox` (OS-level isolation)
    * `:chrome` - `true` → `--chrome`, `false` → `--no-chrome`

  Unknown keys are silently ignored (they may be used by env/caller logic).
  """
  @spec build_args(cli_opts()) :: [String.t()]
  defdelegate build_args(caller_opts), to: Args

  @doc """
  Serializes content blocks to a JSON message suitable for Claude CLI stdin input.

  Returns `nil` when no content blocks are present (text-only message).
  When content blocks exist, returns a JSON string containing a user message
  with the text prompt and all formatted content blocks as the content array.
  """
  @spec content_blocks_json(keyword()) :: String.t() | nil
  defdelegate content_blocks_json(opts), to: Args

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
    opts = Args.normalize_opts(opts)
    merged = Keyword.filter(opts, fn {_k, v} -> v != nil end)

    case Args.validate_opts(merged) do
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
    case find_claude_binary() do
      {:ok, claude_path} ->
        args = Args.build_args(opts)

        Logger.info(
          "Spawning Claude in #{project_path}: claude #{Enum.join(Args.safe_log_args(args), " ")}"
        )

        Logger.info(
          "CLI env: CLAUDE_CODE_EFFORT_LEVEL=#{inspect(opts[:effort_level])} max_budget_usd=#{inspect(opts[:max_budget_usd])}"
        )

        {port, _handler_pid, session_ref} =
          spawn_handler(claude_path, args, Keyword.put(opts, :project_path, project_path))

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

  # Opens a port (script-wrapped or direct), pipes any multimodal content blocks,
  # then wires up the handler process. Returns {port, handler_pid, session_ref}.
  defp spawn_handler(claude_path, args, opts) do
    caller = Keyword.get(opts, :caller, self())
    session_ref = Keyword.get(opts, :session_ref, make_ref())
    idle_timeout_ms = resolve_idle_timeout(opts)
    project_path = Keyword.fetch!(opts, :project_path)

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

    port =
      if Keyword.get(opts, :use_script, true),
        do: open_script_port(claude_path, args, project_path, env),
        else: open_direct_port(claude_path, args, project_path, env)

    # Pipe multimodal content blocks to stdin before handing port to handler.
    maybe_pipe_content_blocks(port, opts)

    Port.connect(port, handler_pid)
    send(handler_pid, {:port, port})

    {port, handler_pid, session_ref}
  end

  defp resolve_idle_timeout(opts) do
    EyeInTheSky.CLI.Port.resolve_idle_timeout(opts, @fallback_idle_timeout_ms)
  end

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

  defp maybe_pipe_content_blocks(port, opts) do
    case Args.content_blocks_json(opts) do
      nil -> :ok
      json ->
        Port.command(port, json <> "\n")
        Logger.info("[CLI] Piped multimodal content blocks to stdin (#{byte_size(json)} bytes)")
    end
  end

  # ---------------------------------------------------------------------------
  # Environment (delegates to Env)
  # ---------------------------------------------------------------------------

  defp build_env(opts), do: Env.build(opts)

  # ---------------------------------------------------------------------------
  # Binary locator (cached via :persistent_term)
  # ---------------------------------------------------------------------------

  defp find_claude_binary do
    EyeInTheSky.CLI.Port.find_binary(@persistent_term_key, &BinaryFinder.find/0)
  end
end
