# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Register .kdl MIME type for file uploads
config :mime, :types, %{
  "text/plain" => ["kdl"]
}

config :zentinel_cp,
  ecto_repos: [ZentinelCp.Repo],
  generators: [timestamp_type: :utc_datetime],
  # Default to SQLite3 for dev/test, override in prod
  ecto_adapter: Ecto.Adapters.SQLite3

# Configure the endpoint
config :zentinel_cp, ZentinelCpWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ZentinelCpWeb.ErrorHTML, json: ZentinelCpWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ZentinelCp.PubSub,
  live_view: [signing_salt: "RDyF3POG"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :zentinel_cp, ZentinelCp.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  zentinel_cp: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  zentinel_cp: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Oban background job configuration
# Default to SQLite Lite engine for dev/test, override in prod for Postgres
config :zentinel_cp, Oban,
  engine: Oban.Engines.Lite,
  repo: ZentinelCp.Repo,
  queues: [
    default: 10,
    rollouts: 5,
    maintenance: 2
  ]

# Bundle signing configuration
# Disabled by default. Enable in production with Ed25519 key pair.
config :zentinel_cp, :bundle_signing,
  enabled: false,
  key_id: nil,
  private_key_path: nil,
  public_key_path: nil

# GitHub webhook configuration
config :zentinel_cp, :github_webhook,
  secret: nil,
  default_branch: "main"

# ACME / Let's Encrypt configuration
config :zentinel_cp, :acme, directory_url: "https://acme-v02.api.letsencrypt.org/directory"

# OpenTelemetry (disabled by default, enable via OTEL_EXPORTER_OTLP_ENDPOINT in runtime.exs)
config :opentelemetry, span_processor: :batch, traces_exporter: :none

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
