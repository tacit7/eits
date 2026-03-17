# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :eye_in_the_sky_web,
  ecto_repos: [EyeInTheSkyWeb.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :eye_in_the_sky_web, EyeInTheSkyWebWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: EyeInTheSkyWebWeb.ErrorHTML, json: EyeInTheSkyWebWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: EyeInTheSkyWeb.PubSub,
  live_view: [signing_salt: "VYcRHPZn"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :eye_in_the_sky_web, EyeInTheSkyWeb.Mailer, adapter: Swoosh.Adapters.Local

# esbuild is handled by custom build.js script (for Svelte support)
# See assets/build.js and the node watcher in config/dev.exs
config :esbuild, :version, "0.25.4"

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  eye_in_the_sky_web: [
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
config :eye_in_the_sky_web, Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.PG,
  queues: [jobs: 5, default: 5],
  repo: EyeInTheSkyWeb.Repo,
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"* * * * *", EyeInTheSkyWeb.Workers.JobDispatcherWorker}
     ]}
  ]

# Web Push / VAPID configuration
config :web_push_encryption, :vapid_details,
  subject: "mailto:admin@eits.dev",
  public_key:
    "BCeer_3Bsec6cpZU-NAcYLmeF5zqinfsZBYzXoDlA62Gp8nJhtnhKI0OGdPqEJAe5b9lpHuyNZjIDIrOgCjhUIc",
  private_key: "UjvINIZfpbgbtSEyPrxK41I5Sy-uE6gtxek7Vq9W6ck"

# WebAuthn / Passkey configuration
config :wax_,
  origin: "https://eits.dev",
  rp_id: "eits.dev",
  trusted_attestation_types: [:none, :self]

# Additional allowed WebAuthn origins (e.g. ngrok tunnels). Primary origin
# above is always included; add extras via WEBAUTHN_EXTRA_ORIGINS env var.
config :eye_in_the_sky_web, :webauthn_extra_origins, []

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
