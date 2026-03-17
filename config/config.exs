# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :eye_in_the_sky,
  ecto_repos: [EyeInTheSky.Repo],
  generators: [timestamp_type: :utc_datetime]

config :elixir, :time_zone_database, Tz.TimeZoneDatabase
config :eye_in_the_sky, EyeInTheSky.Repo, types: EyeInTheSkyWeb.PostgrexTypes

# Configures the endpoint
config :eye_in_the_sky, EyeInTheSkyWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: EyeInTheSkyWeb.ErrorHTML, json: EyeInTheSkyWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: EyeInTheSky.PubSub,
  live_view: [signing_salt: "VYcRHPZn"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :eye_in_the_sky, EyeInTheSky.Mailer, adapter: Swoosh.Adapters.Local

# esbuild is handled by custom build.js script (for Svelte support)
# See assets/build.js and the node watcher in config/dev.exs
config :esbuild, :version, "0.25.4"

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  eye_in_the_sky: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Oban job processing
config :eye_in_the_sky, Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.PG,
  queues: [jobs: 5, default: 5, embeddings: 2],
  repo: EyeInTheSky.Repo,
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"* * * * *", EyeInTheSky.Workers.JobDispatcherWorker}
     ]}
  ]

# Web Push / VAPID — both keys loaded from VAPID_PUBLIC_KEY / VAPID_PRIVATE_KEY env vars (see runtime.exs)

# WebAuthn / Passkey configuration (dev/test defaults — override via WEBAUTHN_ORIGIN and WEBAUTHN_RP_ID env vars in runtime.exs)
config :wax_,
  origin: "https://eits.dev",
  rp_id: "eits.dev",
  trusted_attestation_types: [:none, :self]

# Additional allowed WebAuthn origins (e.g. ngrok tunnels). Primary origin
# above is always included; add extras via WEBAUTHN_EXTRA_ORIGINS env var.
config :eye_in_the_sky, :webauthn_extra_origins, []

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
