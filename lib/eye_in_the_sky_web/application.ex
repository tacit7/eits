defmodule EyeInTheSkyWeb.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Oban.Telemetry.attach_default_logger(:info)

    children = [
      # Disabled SSR - server module not built
      # {NodeJS.Supervisor, [path: LiveSvelte.SSR.NodeJS.server_path(), pool_size: 4]},
      EyeInTheSkyWebWeb.Telemetry,
      EyeInTheSkyWeb.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:eye_in_the_sky_web, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster,
       query: Application.get_env(:eye_in_the_sky_web, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: EyeInTheSkyWeb.PubSub},
      # Task supervisor for fire-and-forget async work
      {Task.Supervisor, name: EyeInTheSkyWeb.TaskSupervisor},
      # Registry for per-session worker lookups (duplicate keys: ref + session_id)
      {Registry, keys: :duplicate, name: EyeInTheSkyWeb.Claude.Registry},
      # Unique registry for agent worker naming (:via requires unique keys)
      {Registry, keys: :unique, name: EyeInTheSkyWeb.Claude.AgentRegistry},
      # Unique registry for chat worker naming (one per channel)
      {Registry, keys: :unique, name: EyeInTheSkyWeb.Claude.ChatRegistry},
      # SDK registry for tracking running Claude CLI processes
      EyeInTheSkyWeb.Claude.SDK.Registry,
      # DynamicSupervisor for per-session workers
      {DynamicSupervisor, name: EyeInTheSkyWeb.Claude.SessionSupervisor, strategy: :one_for_one},
      # DynamicSupervisor for persistent agent workers
      {DynamicSupervisor, name: EyeInTheSkyWeb.Claude.AgentSupervisor, strategy: :one_for_one},
      # DynamicSupervisor for per-channel chat workers
      {DynamicSupervisor, name: EyeInTheSkyWeb.Claude.ChatSupervisor, strategy: :one_for_one},
      # Claude CLI session coordinator
      EyeInTheSkyWeb.Claude.SessionManager,
      # Oban job processing (includes Cron plugin for JobDispatcherWorker)
      {Oban, Application.fetch_env!(:eye_in_the_sky_web, Oban)},
      # Poll for external task changes (Go MCP i-todo writes)
      EyeInTheSkyWeb.Tasks.Poller,
      # Poll for external message writes (Go MCP, spawned agents)
      EyeInTheSkyWeb.Messages.Broadcaster,
      # Start to serve requests, typically the last entry
      EyeInTheSkyWebWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: EyeInTheSkyWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    EyeInTheSkyWebWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
