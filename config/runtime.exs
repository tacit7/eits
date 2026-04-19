import Config
import Dotenvy

# Load env files with local overrides:
# .env.local > .env, and explicit shell env overrides both.
runtime_env = source!([".env", ".env.local", System.get_env()])
get_env = fn key -> runtime_env[key] end

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
#     PHX_SERVER=true bin/eye_in_the_sky start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if get_env.("PHX_SERVER") in ~w(true 1) do
  config :eye_in_the_sky, EyeInTheSkyWeb.Endpoint, server: true
end

# Gitea webhook HMAC secret — required for signature verification in all envs
config :eye_in_the_sky, :gitea_webhook_secret, get_env.("GITEA_WEBHOOK_SECRET") || ""

# VAPID keys — loaded from env vars. Required in prod, optional in dev.
if vapid_private = get_env.("VAPID_PRIVATE_KEY") do
  config :web_push_encryption, :vapid_details,
    subject: "mailto:admin@eits.dev",
    public_key: get_env.("VAPID_PUBLIC_KEY"),
    private_key: vapid_private
else
  if config_env() == :prod do
    raise "VAPID_PRIVATE_KEY environment variable is required in production"
  end
end

# REST API key — set EITS_API_KEY to require bearer auth on /api/v1.
# Leave unset to disable auth (dev default).
# Generate with: mix eits.gen.api_key
if config_env() != :test do
  config :eye_in_the_sky, :api_key, get_env.("EITS_API_KEY")
end

# Disable passkey auth — set DISABLE_AUTH=true to skip LiveView session auth.
# NOTE: Tauri POC — prod guard removed so the bundled desktop app can bypass
# auth. DO NOT set DISABLE_AUTH=true in any deployment where the app is
# network-reachable.
config :eye_in_the_sky, :disable_auth, get_env.("DISABLE_AUTH") in ~w(true 1)

# WebAuthn — extra allowed origins (comma-separated).
webauthn_extra_raw =
  get_env.("WEBAUTHN_EXTRA_ORIGINS")

if webauthn_extra_raw do
  origins =
    webauthn_extra_raw
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))

  if origins != [] do
    config :eye_in_the_sky, :webauthn_extra_origins, origins
  end
end

# WebAuthn primary origin — configurable via WEBAUTHN_ORIGIN. Required in prod.
# Dev/test falls back to the compile-time default in config.exs ("https://eits.dev").
if webauthn_origin = get_env.("WEBAUTHN_ORIGIN") do
  config :wax_, origin: webauthn_origin
else
  if config_env() == :prod do
    raise """
    environment variable WEBAUTHN_ORIGIN is missing.
    Set it to your app's origin, e.g.: https://eits.dev
    """
  end
end

# WebAuthn RP ID — configurable via WEBAUTHN_RP_ID. Required in prod.
# Dev/test falls back to the compile-time default in config.exs ("eits.dev").
if webauthn_rp_id = get_env.("WEBAUTHN_RP_ID") do
  config :wax_, rp_id: webauthn_rp_id
else
  if config_env() == :prod do
    raise """
    environment variable WEBAUTHN_RP_ID is missing.
    Set it to your app's RP ID (the registrable domain), e.g.: eits.dev
    """
  end
end

database_url = get_env.("DATABASE_URL")

if config_env() == :dev && database_url do
  dev_repo_opts = [
    url: database_url,
    pool_size: String.to_integer(get_env.("POOL_SIZE") || "5"),
    prepare: :unnamed
  ]

  # SSL: explicit DATABASE_SSL=false disables it; Supabase requires it; local skips it.
  dev_repo_opts =
    cond do
      get_env.("DATABASE_SSL") == "false" ->
        Keyword.put(dev_repo_opts, :ssl, false)

      match?(%URI{host: host} when is_binary(host), URI.parse(database_url)) &&
          String.contains?(URI.parse(database_url).host, "supabase.com") ->
        Keyword.put(dev_repo_opts, :ssl, verify: :verify_none)

      true ->
        dev_repo_opts
    end

  config :eye_in_the_sky, EyeInTheSky.Repo, dev_repo_opts
end

if config_env() == :prod do
  database_url =
    database_url ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if get_env.("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :eye_in_the_sky, EyeInTheSky.Repo,
    url: database_url,
    pool_size: String.to_integer(get_env.("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6,
    ssl: [verify: :verify_none],
    prepare: :unnamed

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    get_env.("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = get_env.("PHX_HOST") || "eits.dev"
  port = String.to_integer(get_env.("PORT") || "4000")

  config :eye_in_the_sky, :dns_cluster_query, get_env.("DNS_CLUSTER_QUERY")

  # Build check_origin list from PHX_HOST + any WEBAUTHN_EXTRA_ORIGINS.
  # Use "//host" format (scheme-agnostic) so it works correctly behind
  # reverse proxies regardless of how the Origin header arrives.
  extra_origins =
    case webauthn_extra_raw do
      nil -> []
      raw -> raw |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
    end

  allowed_origins = ["//#{host}" | extra_origins]

  config :eye_in_the_sky, EyeInTheSkyWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    check_origin: allowed_origins,
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base,
    # PHX_DISABLE_FORCE_SSL=1 turns off HSTS + HTTPS redirect. Needed for the
    # Tauri bundle serving over http://localhost:5050 inside a WebView.
    force_ssl:
      if(get_env.("PHX_DISABLE_FORCE_SSL") == "1",
        do: nil,
        else: [hsts: true, rewrite_on: [:x_forwarded_proto]]
      )

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :eye_in_the_sky, EyeInTheSkyWeb.Endpoint,
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
  #     config :eye_in_the_sky, EyeInTheSkyWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :eye_in_the_sky, EyeInTheSky.Mailer,
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
