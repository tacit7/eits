defmodule EyeInTheSky.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Oban.Telemetry.attach_default_logger(:info)

    # Tauri integration: if launched by the Tauri wrapper, ELIXIRKIT_PUBSUB
    # will be set to the Rust-side PubSub URL. Otherwise run in standalone mode.
    elixirkit_pubsub = System.get_env("ELIXIRKIT_PUBSUB")

    children =
      if Application.get_env(:live_svelte, :ssr_module) != LiveSvelte.SSR.ViteJS do
        [{NodeJS.Supervisor, [path: LiveSvelte.SSR.NodeJS.server_path(), pool_size: 4]}]
      else
        []
      end

    children =
      children ++
        [
          {ElixirKit.PubSub,
           connect: elixirkit_pubsub || :ignore, on_exit: fn -> System.stop() end},
          EyeInTheSkyWeb.Telemetry,
          EyeInTheSky.Repo,
          {Ecto.Migrator,
           repos: Application.fetch_env!(:eye_in_the_sky, :ecto_repos), skip: skip_migrations?()},
          {DNSCluster,
           query: Application.get_env(:eye_in_the_sky, :dns_cluster_query) || :ignore},
          {Phoenix.PubSub, name: EyeInTheSky.PubSub},
          # Task supervisor for fire-and-forget async work
          {Task.Supervisor, name: EyeInTheSky.TaskSupervisor},
          # Unique registry for agent worker naming (:via requires unique keys)
          {Registry, keys: :unique, name: EyeInTheSky.Claude.AgentRegistry},
          # Unique registry for chat worker naming (one per channel)
          {Registry, keys: :unique, name: EyeInTheSky.Claude.ChatRegistry},
          # SDK registry for tracking running Claude CLI processes
          EyeInTheSky.Claude.SDK.Registry,
          # ETS-backed registry for tracking running Gemini stream tasks
          EyeInTheSky.Gemini.StreamHandler.Registry,
          # DynamicSupervisor for persistent agent workers
          {DynamicSupervisor,
           name: EyeInTheSky.Claude.AgentSupervisor, strategy: :one_for_one, max_children: 50},
          # DynamicSupervisor for per-channel chat workers
          {DynamicSupervisor, name: EyeInTheSky.Claude.ChatSupervisor, strategy: :one_for_one},
          # Oban job processing (includes Cron plugin for JobDispatcherWorker)
          {Oban, Application.fetch_env!(:eye_in_the_sky, Oban)},
          # React to session lifecycle events and update team member state
          EyeInTheSky.Teams.Subscriber,
          # Poll for external task changes from spawned agents
          EyeInTheSky.Tasks.Poller,
          # Poll for external message writes from spawned agents
          EyeInTheSky.Messages.Broadcaster,
          # Rate limiter ETS backend for auth endpoint throttling
          EyeInTheSky.RateLimiter,
          # In-memory timer registry for orchestrator sessions
          EyeInTheSky.OrchestratorTimers.Server,
          # IAM policy cache (ETS-backed, single-node)
          EyeInTheSky.IAM.PolicyCache,
          # Seed built-in IAM policies (idempotent; skips existing system_keys).
          # `:transient` so a crash propagates to the supervisor rather than
          # being silently swallowed.
          Supervisor.child_spec({Task, fn -> EyeInTheSky.IAM.Seeds.run() end},
            id: :iam_seeds_task, restart: :transient),
          # Start to serve requests, typically the last entry
          EyeInTheSkyWeb.Endpoint,
          # Signal the Tauri wrapper (if present) that the endpoint is up so it
          # can open the webview. No-op when ELIXIRKIT_PUBSUB is unset.
          {Task,
           fn ->
             if elixirkit_pubsub do
               ElixirKit.PubSub.broadcast("messages", "ready")
             end
           end}
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :rest_for_one, name: EyeInTheSky.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    EyeInTheSkyWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations? do
    # By default, migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
