defmodule EyeInTheSky.Pi.CLI do
  @moduledoc """
  Transport for the Pi harness sidecar. Transport ONLY:
  opens the Port, writes encoded ndjson, and kills the OS process.
  Request ids, preamble sequencing, and the protocol verbs abort/dispose
  are owned by EyeInTheSky.Pi.SDK.

  Unlike Claude/Codex, stdin stays OPEN for the turn's lifetime — the SDK
  writes requests to it. Emits the shared legacy wire tags
  {:claude_output, ref, line} / {:claude_exit, ref, code} (intentional shim).
  """

  require Logger

  @default_idle_timeout_ms :infinity

  @doc """
  Opens a Port on the harness. Sends nothing — the SDK drives the preamble.

  Opts: :caller (handler pid), :session_ref, :project_path, :turn_id,
  plus eits_* id opts (same keys as Codex.CLI).
  """
  @spec spawn_harness(keyword()) :: {:ok, port(), reference()} | {:error, term()}
  def spawn_harness(opts \\ []) do
    project_path = opts |> Keyword.get(:project_path, File.cwd!()) |> Path.expand()

    with true <- File.dir?(project_path) || {:error, {:invalid_project_path, project_path}},
         {:ok, {exe, args}} <- resolve_harness_command() do
      caller = Keyword.get(opts, :caller, self())
      session_ref = Keyword.get(opts, :session_ref, make_ref())
      idle_timeout_ms = EyeInTheSky.CLI.Port.resolve_idle_timeout(opts, @default_idle_timeout_ms)

      Logger.info("[Pi.CLI] Spawning harness in #{project_path}: #{exe} #{Enum.join(args, " ")}")

      port =
        Port.open(
          {:spawn_executable, exe},
          [
            :binary,
            :exit_status,
            :use_stdio,
            :stderr_to_stdout,
            {:args, args},
            {:cd, project_path},
            {:env, build_env(opts)}
          ]
        )

      EyeInTheSky.CLI.Port.spawn_handler(port, session_ref, caller, idle_timeout_ms,
        telemetry_prefix: [:eits, :pi, :cli],
        log_prefix: "Pi.CLI"
      )

      :telemetry.execute([:eits, :pi, :cli, :spawn], %{system_time: System.system_time()}, %{
        project_path: project_path
      })

      {:ok, port, session_ref}
    end
  end

  @doc "Encode and write one ndjson request line. Callable from any process."
  @spec send_ndjson(port(), map()) :: :ok | {:error, :port_closed}
  def send_ndjson(port, map) when is_port(port) and is_map(map) do
    Port.command(port, Jason.encode!(map) <> "\n")
    :ok
  rescue
    ArgumentError -> {:error, :port_closed}
  end

  @doc "Transport-level kill (SIGTERM group -> SIGKILL). No protocol semantics."
  @spec cancel(port()) :: :ok
  def cancel(port) when is_port(port), do: EyeInTheSky.CLI.Port.cancel_port(port, "Pi.CLI")

  # -- Harness resolution ------------------------------------------------------

  @doc """
  EITS_PI_HARNESS override -> priv/bin/eits-pi-harness -> `bun pi-harness/src/main.ts`.
  """
  @spec resolve_harness_command() :: {:ok, {String.t(), [String.t()]}} | {:error, term()}
  def resolve_harness_command do
    override = System.get_env("EITS_PI_HARNESS")
    compiled = Path.expand("priv/bin/eits-pi-harness")
    source = Path.expand("pi-harness/src/main.ts")

    cond do
      override && override != "" ->
        {:ok, {override, []}}

      File.exists?(compiled) ->
        {:ok, {compiled, []}}

      true ->
        with true <- File.exists?(source),
             bun when is_binary(bun) <- System.find_executable("bun") do
          {:ok, {bun, [source]}}
        else
          _ -> {:error, {:pi_harness_not_found, hint: "run scripts/build-pi-harness.sh"}}
        end
    end
  end

  # -- Environment (ALLOWLIST — spec §4) ---------------------------------------

  @base_allowlist ~w(PATH HOME TMPDIR LANG)

  @doc """
  Allowlist env for the harness. Pi is multi-provider; a strip list would leak
  provider credentials (OPENAI_API_KEY, ...) into the sidecar. Credentials come
  from ~/.pi/agent/auth.json only.
  """
  @spec build_env(keyword()) :: [{charlist(), charlist()}]
  def build_env(opts) do
    base =
      for {key, value} <- System.get_env(),
          value != "",
          key in @base_allowlist or String.starts_with?(key, "LC_"),
          do: {String.to_charlist(key), String.to_charlist(value)}

    eits_pairs = [
      {"PI_PACKAGE_DIR", System.get_env("PI_PACKAGE_DIR") || Path.expand("priv/bin/pi")},
      {"EITS_PI_TURN_ID", opts[:turn_id]},
      {"EITS_SESSION_UUID", opts[:eits_session_uuid]},
      {"EITS_SESSION_ID", opts[:eits_session_id]},
      {"EITS_AGENT_UUID", opts[:eits_agent_uuid]},
      {"EITS_AGENT_ID", opts[:eits_agent_id]},
      {"EITS_PROJECT_ID", opts[:eits_project_id]},
      {"EITS_CHANNEL_ID", opts[:eits_channel_id]},
      {"EITS_MODEL", opts[:eits_model]},
      {"EITS_URL", opts[:eits_url] || System.get_env("EITS_URL", "http://localhost:5001/api/v1")}
    ]

    Enum.reduce(eits_pairs, base, fn {k, v}, acc ->
      EyeInTheSky.CLI.Port.maybe_add_env(acc, k, v)
    end)
  end
end
