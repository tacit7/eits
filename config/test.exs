import Config

config :live_svelte, ssr_module: LiveSvelte.SSR.ViteJS

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :eye_in_the_sky, EyeInTheSky.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "eits_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :eye_in_the_sky, EyeInTheSkyWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4005],
  secret_key_base: "nkJhfq4VPfLzvgOOJSPVSc2C8F1X1/VWumsFBiDAmTZDbJHzcF4i0aYV0DIyFUfG",
  server: false

# In test we don't send emails
config :eye_in_the_sky, EyeInTheSky.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Use mock CLI module for testing
config :eye_in_the_sky,
  cli_module: EyeInTheSky.Claude.MockCLI,
  codex_cli_module: EyeInTheSky.Claude.MockCLI,
  agent_manager_module: EyeInTheSky.Agents.MockAgentManager,
  # Run IAM audit writes synchronously so they complete before the Ecto sandbox owner
  # exits at the end of each test. Async writes via Task.Supervisor cause sandbox
  # "owner exited" errors and Postgrex disconnects that contaminate subsequent tests.
  iam_audit_sync: true,
  # Core-layer config keys — keeps core modules free of EyeInTheSkyWeb.Endpoint atom references
  secret_key_base: "nkJhfq4VPfLzvgOOJSPVSc2C8F1X1/VWumsFBiDAmTZDbJHzcF4i0aYV0DIyFUfG",
  server_base_url: "http://localhost:4005"

# Disable Oban queues in test (use Oban.Testing for manual testing)
config :eye_in_the_sky, Oban, testing: :manual

# Disable message notify listener in test (tested manually via handle_info)
config :eye_in_the_sky, EyeInTheSky.Messages.NotifyListener, enabled: false

# Disable API key auth in test (RequireAuth plug passes through when nil)
config :eye_in_the_sky, :api_key, nil

# Skip IAM seed task in test — sandbox is :manual; the task has no checked-out
# connection and crashes, eventually hitting the supervisor restart limit and
# tearing down the Repo before any test runs.
config :eye_in_the_sky, :run_iam_seeds, false

# Disable rate limiting in test — Hammer ETS table is global and persists across
# tests, so repeated requests from 127.0.0.1 trip the default 60 req/min limit.
config :eye_in_the_sky, :rate_limit_enabled, false
