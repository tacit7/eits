defmodule EyeInTheSky.Codex.CLI do
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

  @default_idle_timeout_ms :infinity
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

  Delegates to `EyeInTheSky.CLI.Port.cancel_port/2` which sends SIGTERM to both
  the process group and direct PID, then escalates to SIGKILL if needed.
  """
  @spec cancel(port()) :: :ok
  def cancel(port) when is_port(port) do
    EyeInTheSky.CLI.Port.cancel_port(port, "Codex.CLI")
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
    * `:bypass_sandbox` - `--dangerously-bypass-approvals-and-sandbox` (overrides full_auto)
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

    # Bypass sandbox takes precedence over full_auto
    args =
      if Keyword.get(opts, :bypass_sandbox, false) do
        args ++ ["--dangerously-bypass-approvals-and-sandbox"]
      else
        full_auto = Keyword.get(opts, :full_auto, true)
        if full_auto, do: args ++ ["--full-auto"], else: args
      end

    # Skip git repo check — allow running outside git repos
    args = args ++ ["--skip-git-repo-check"]

    # Inject EITS env vars via shell_environment_policy.set so they're
    # available to shell commands the agent runs (bypasses default filters)
    env_args =
      [
        {"EITS_SESSION_UUID", opts[:eits_session_uuid]},
        {"EITS_SESSION_ID", opts[:eits_session_id]},
        {"EITS_AGENT_UUID", opts[:eits_agent_uuid]},
        {"EITS_AGENT_ID", opts[:eits_agent_id]},
        {"EITS_PROJECT_ID", opts[:eits_project_id]},
        {"EITS_MODEL", opts[:eits_model]},
        {"EITS_URL",
         opts[:eits_url] || System.get_env("EITS_URL", "http://localhost:5001/api/v1")}
      ]
      |> Enum.filter(fn {_key, val} -> val end)
      |> Enum.flat_map(fn {key, val} ->
        ["-c", "shell_environment_policy.set.#{key}=\"#{val}\""]
      end)

    args = args ++ env_args

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
    EyeInTheSky.CLI.Port.clear_binary_cache(@persistent_term_key)
  end

  # ---------------------------------------------------------------------------
  # Port spawning
  # ---------------------------------------------------------------------------

  defp spawn_cli(opts) do
    project_path =
      opts
      |> Keyword.get(:project_path, File.cwd!())
      |> Path.expand()

    if File.dir?(project_path) do
      do_spawn(opts, project_path)
    else
      {:error, {:invalid_project_path, project_path}}
    end
  end

  defp do_spawn(opts, project_path) do
    caller = Keyword.get(opts, :caller, self())
    session_ref = Keyword.get(opts, :session_ref, make_ref())

    idle_timeout_ms = EyeInTheSky.CLI.Port.resolve_idle_timeout(opts, @default_idle_timeout_ms)

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
                EyeInTheSky.CLI.Port.handle_port_output(
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
    |> EyeInTheSky.CLI.Port.maybe_add_env("EITS_SESSION_UUID", opts[:eits_session_uuid])
    |> EyeInTheSky.CLI.Port.maybe_add_env("EITS_SESSION_ID", opts[:eits_session_id])
    |> EyeInTheSky.CLI.Port.maybe_add_env("EITS_AGENT_UUID", opts[:eits_agent_uuid])
    |> EyeInTheSky.CLI.Port.maybe_add_env("EITS_AGENT_ID", opts[:eits_agent_id])
    |> EyeInTheSky.CLI.Port.maybe_add_env("EITS_PROJECT_ID", opts[:eits_project_id])
    |> EyeInTheSky.CLI.Port.maybe_add_env("EITS_MODEL", opts[:eits_model])
    |> EyeInTheSky.CLI.Port.maybe_add_env(
      "EITS_URL",
      opts[:eits_url] || System.get_env("EITS_URL", "http://localhost:5001/api/v1")
    )
  end

  # ---------------------------------------------------------------------------
  # Binary locator (cached via :persistent_term)
  # ---------------------------------------------------------------------------

  defp find_codex_binary do
    EyeInTheSky.CLI.Port.find_binary(@persistent_term_key, &do_find_codex_binary/0)
  end

  defp do_find_codex_binary do
    cond do
      path = System.find_executable("codex") ->
        {:ok, path}

      path = EyeInTheSky.CLI.Port.find_in_standard_paths(@standard_paths) ->
        {:ok, path}

      true ->
        {:error, {:binary_not_found, checked_paths: @standard_paths}}
    end
  end
end
