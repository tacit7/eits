defmodule EyeInTheSkyWeb.Codex.CLI do
  @moduledoc """
  Codex CLI subprocess spawner.

  Spawns `codex` binary as a Port and streams JSONL stdout back to the caller
  via message passing. Mirrors Claude.CLI with Codex-specific differences:

  - Binary: `codex` (Rust binary, no `script` wrapper needed)
  - Subcommand: `exec` for execution
  - `--json` flag for JSONL output
  - `--full-auto` for autonomous mode (replaces `--dangerously-skip-permissions`)
  - `-m <model>` for model selection
  - Auth: `OPENAI_API_KEY` env var (passthrough via system env)

  ## Messages sent to caller

    * `{:claude_output, session_ref, line}` - each line of stdout
    * `{:claude_exit, session_ref, exit_code}` - process exited
  """

  require Logger

  @type cli_opts :: keyword()
  @type spawn_result :: {:ok, port(), reference()} | {:error, term()}

  @default_idle_timeout_ms 300_000
  @standard_paths [
    "/usr/local/bin/codex",
    "/opt/homebrew/bin/codex",
    Path.expand("~/.local/bin/codex"),
    Path.expand("~/.cargo/bin/codex")
  ]
  @persistent_term_key {__MODULE__, :codex_binary_path}

  # ---------------------------------------------------------------------------
  # Public spawners
  # ---------------------------------------------------------------------------

  @doc """
  Spawns a new Codex session.

  Does NOT pass a session/thread ID. Codex will generate a thread_id and return
  it in the `thread.started` event. Caller should parse the thread ID from output.
  """
  @spec spawn_new_session(String.t(), cli_opts()) :: spawn_result()
  def spawn_new_session(prompt, opts \\ []) do
    opts
    |> Keyword.put(:prompt, prompt)
    |> spawn_cli()
  end

  @doc """
  Resumes a specific session by thread ID.

  Note: Codex resume semantics may differ from Claude. If `codex exec` doesn't
  support direct resume, this passes the thread_id as context.
  """
  @spec resume_session(String.t(), String.t(), cli_opts()) :: spawn_result()
  def resume_session(session_id, prompt, opts \\ []) do
    opts
    |> Keyword.put(:prompt, prompt)
    |> Keyword.put(:resume, session_id)
    |> spawn_cli()
  end

  @doc """
  Cancels a running Codex process by killing the OS process (group and direct), then closing the port.
  """
  @spec cancel(port()) :: :ok
  def cancel(port) when is_port(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, os_pid} ->
        # Send TERM to both process group and PID directly
        # (process group for child processes, direct PID in case it's not a group leader)
        System.cmd("kill", ["-TERM", "-#{os_pid}"], stderr_to_stdout: true)
        System.cmd("kill", ["-TERM", "#{os_pid}"], stderr_to_stdout: true)
        Process.sleep(500)

        case System.cmd("kill", ["-0", "#{os_pid}"], stderr_to_stdout: true) do
          {_, 0} ->
            Logger.info("[Codex.CLI] Process #{os_pid} still alive, sending SIGKILL")
            System.cmd("kill", ["-9", "-#{os_pid}"], stderr_to_stdout: true)
            System.cmd("kill", ["-9", "#{os_pid}"], stderr_to_stdout: true)

          _ ->
            :ok
        end

      nil ->
        :ok
    end

    try do
      Port.close(port)
    rescue
      ArgumentError -> :ok
    end

    :ok
  end

  # ---------------------------------------------------------------------------
  # Arg builder
  # ---------------------------------------------------------------------------

  @doc """
  Builds a flat list of CLI args from a keyword list.

  Codex CLI: `codex exec [options] [prompt]`

  Supported keys:
    * `:prompt` (required) - the user prompt (positional arg after flags)
    * `:resume` - `--resume <thread_id>`
    * `:model` - `-m <model>`
    * `:full_auto` - `--full-auto` (default: true)
    * `:max_turns` - not directly supported by Codex; ignored
  """
  @spec build_args(cli_opts()) :: [String.t()]
  def build_args(caller_opts) do
    opts = Keyword.filter(caller_opts, fn {_k, v} -> v != nil end)

    resume_id = opts[:resume]

    # Resume uses a subcommand: codex exec resume <thread_id> [flags] [prompt]
    # New session uses: codex exec [flags] [prompt]
    base_args =
      if resume_id do
        ["exec", "resume", to_string(resume_id)]
      else
        ["exec"]
      end

    # JSON output
    args = base_args ++ ["--json"]

    # Model
    args =
      if model = opts[:model] do
        args ++ ["-m", to_string(model)]
      else
        args
      end

    # Full auto mode (default true)
    full_auto = Keyword.get(opts, :full_auto, true)
    args = if full_auto, do: args ++ ["--full-auto"], else: args

    # Skip git repo check — allow running outside git repos
    args = args ++ ["--skip-git-repo-check"]

    # Inject EITS env vars via shell_environment_policy.set so they're
    # available to shell commands the agent runs (bypasses default filters)
    args =
      Enum.reduce(
        [
          {"EITS_SESSION_UUID", opts[:eits_session_uuid]},
          {"EITS_SESSION_ID", opts[:eits_session_id]},
          {"EITS_AGENT_UUID", opts[:eits_agent_uuid]},
          {"EITS_AGENT_ID", opts[:eits_agent_id]},
          {"EITS_PROJECT_ID", opts[:eits_project_id]},
          {"EITS_MODEL", opts[:eits_model]},
          {"EITS_URL", opts[:eits_url] || "http://localhost:5000/api/v1"}
        ],
        args,
        fn {key, val}, acc ->
          if val, do: acc ++ ["-c", "shell_environment_policy.set.#{key}=#{val}"], else: acc
        end
      )

    # Prompt goes last as positional argument
    if prompt = opts[:prompt] do
      args ++ [prompt]
    else
      args
    end
  end

  # ---------------------------------------------------------------------------
  # Binary cache
  # ---------------------------------------------------------------------------

  @doc """
  Clear the cached binary path. Useful in tests.
  """
  @spec clear_binary_cache() :: :ok
  def clear_binary_cache do
    EyeInTheSkyWeb.CLI.Port.clear_binary_cache(@persistent_term_key)
  end

  # ---------------------------------------------------------------------------
  # Port spawning
  # ---------------------------------------------------------------------------

  defp spawn_cli(opts) do
    project_path =
      opts
      |> Keyword.get(:project_path, File.cwd!())
      |> Path.expand()

    if !File.dir?(project_path) do
      {:error, {:invalid_project_path, project_path}}
    else
      do_spawn(opts, project_path)
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

    case find_codex_binary() do
      {:ok, codex_path} ->
        args = build_args(opts)

        # Log flags only (omit prompt to avoid logging secrets/huge text)
        prompt = opts[:prompt] || ""

        prompt_summary =
          if prompt != "", do: " <prompt: #{String.length(prompt)} chars>", else: ""

        flags = Enum.slice(args, 0..(length(args) - 2)//1)
        cmd_string = "codex " <> Enum.join(flags, " ") <> prompt_summary
        Logger.info("[Codex.CLI] Spawning in #{project_path}: #{cmd_string}")

        handler_pid =
          spawn_link(fn ->
            receive do
              {:port, port} ->
                EyeInTheSkyWeb.CLI.Port.handle_port_output(
                  port,
                  session_ref,
                  caller,
                  "",
                  idle_timeout_ms,
                  telemetry_prefix: [:eits, :codex, :cli],
                  log_prefix: "Codex.CLI"
                )
            end
          end)

        env = build_env(opts)

        port =
          Port.open(
            {:spawn_executable, codex_path},
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

        Port.connect(port, handler_pid)
        send(handler_pid, {:port, port})

        :telemetry.execute([:eits, :codex, :cli, :spawn], %{system_time: System.system_time()}, %{
          project_path: project_path,
          model: opts[:model]
        })

        Logger.info(
          "[telemetry] codex.cli.spawn project_path=#{project_path} model=#{opts[:model]}"
        )

        {:ok, port, session_ref}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Environment
  # ---------------------------------------------------------------------------

  defp build_env(opts) do
    base_env =
      for {key, value} <- System.get_env(), value != "" do
        {String.to_charlist(key), String.to_charlist(value)}
      end

    base_env
    |> EyeInTheSkyWeb.CLI.Port.maybe_add_env("EITS_SESSION_UUID", opts[:eits_session_uuid])
    |> EyeInTheSkyWeb.CLI.Port.maybe_add_env("EITS_SESSION_ID", opts[:eits_session_id])
    |> EyeInTheSkyWeb.CLI.Port.maybe_add_env("EITS_AGENT_UUID", opts[:eits_agent_uuid])
    |> EyeInTheSkyWeb.CLI.Port.maybe_add_env("EITS_AGENT_ID", opts[:eits_agent_id])
    |> EyeInTheSkyWeb.CLI.Port.maybe_add_env("EITS_PROJECT_ID", opts[:eits_project_id])
    |> EyeInTheSkyWeb.CLI.Port.maybe_add_env("EITS_MODEL", opts[:eits_model])
    |> EyeInTheSkyWeb.CLI.Port.maybe_add_env(
      "EITS_URL",
      opts[:eits_url] || "http://localhost:5000/api/v1"
    )
  end

  # ---------------------------------------------------------------------------
  # Binary locator (cached via :persistent_term)
  # ---------------------------------------------------------------------------

  defp find_codex_binary do
    EyeInTheSkyWeb.CLI.Port.find_binary(@persistent_term_key, &do_find_codex_binary/0)
  end

  defp do_find_codex_binary do
    cond do
      path = System.find_executable("codex") ->
        {:ok, path}

      path = EyeInTheSkyWeb.CLI.Port.find_in_standard_paths(@standard_paths) ->
        {:ok, path}

      true ->
        {:error, {:binary_not_found, checked_paths: @standard_paths}}
    end
  end
end
