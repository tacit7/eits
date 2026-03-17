import Config
import Dotenvy

# Load .env file if present (dev/local overrides)
source!([".env", System.get_env()])

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/eye_in_the_sky_web start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :eye_in_the_sky_web, EyeInTheSkyWebWeb.Endpoint, server: true
end

# Gitea webhook HMAC secret — required for signature verification in all envs
config :eye_in_the_sky_web, :gitea_webhook_secret, System.get_env("GITEA_WEBHOOK_SECRET", "")

# VAPID private key — loaded from env in all envs (never hardcoded)
config :web_push_encryption, :vapid_details,
  subject: "mailto:admin@eits.dev",
  public_key:
    System.get_env("VAPID_PUBLIC_KEY") ||
      "BCeer_3Bsec6cpZU-NAcYLmeF5zqinfsZBYzXoDlA62Gp8nJhtnhKI0OGdPqEJAe5b9lpHuyNZjIDIrOgCjhUIc",
  private_key:
    System.get_env("VAPID_PRIVATE_KEY") ||
      raise("VAPID_PRIVATE_KEY environment variable is not set")

# REST API key — set EITS_API_KEY to require bearer auth on /api/v1.
# Leave unset to disable auth (dev default).
# Generate with: mix eits.gen.api_key
if config_env() != :test do
  config :eye_in_the_sky_web, :api_key, System.get_env("EITS_API_KEY")
end

# Disable passkey auth — set DISABLE_AUTH=true to skip LiveView session auth (dev only)
if config_env() != :prod do
  config :eye_in_the_sky_web, :disable_auth, System.get_env("DISABLE_AUTH") in ~w(true 1)
end

# WebAuthn — extra allowed origins (comma-separated). Read directly from
# parsed .env to work around dotenvy not setting new system env vars.
webauthn_extra_raw =
  System.get_env("WEBAUTHN_EXTRA_ORIGINS") ||
    (case Dotenvy.source([".env"]) do
       {:ok, env} -> env["WEBAUTHN_EXTRA_ORIGINS"]
       _ -> nil
     end)

if webauthn_extra_raw do
  origins =
    webauthn_extra_raw
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))

  if origins != [] do
    config :eye_in_the_sky_web, :webauthn_extra_origins, origins
  end
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :eye_in_the_sky_web, EyeInTheSkyWeb.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :eye_in_the_sky_web, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :eye_in_the_sky_web, EyeInTheSkyWebWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base,
    force_ssl: [hsts: true, rewrite_on: [:x_forwarded_proto]]

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :eye_in_the_sky_web, EyeInTheSkyWebWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :eye_in_the_sky_web, EyeInTheSkyWebWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :eye_in_the_sky_web, EyeInTheSkyWeb.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
