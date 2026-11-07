import Config

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
#     PHX_SERVER=true bin/zentinel_cp start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :zentinel_cp, ZentinelCpWeb.Endpoint, server: true
end

# Configure port from environment variable (skip in test to preserve test.exs config)
if config_env() != :test do
  config :zentinel_cp, ZentinelCpWeb.Endpoint,
    http: [port: String.to_integer(System.get_env("PORT", "4000"))]
end

# Bundle storage (S3/MinIO)
if s3_endpoint = System.get_env("S3_ENDPOINT") do
  config :zentinel_cp, ZentinelCp.Bundles.Storage,
    bucket: System.get_env("S3_BUCKET", "zentinel-bundles"),
    ex_aws_config: [
      access_key_id: System.get_env("S3_ACCESS_KEY_ID"),
      secret_access_key: System.get_env("S3_SECRET_ACCESS_KEY"),
      scheme: URI.parse(s3_endpoint).scheme <> "://",
      host: URI.parse(s3_endpoint).host,
      port: URI.parse(s3_endpoint).port,
      region: System.get_env("S3_REGION", "us-east-1")
    ]
end

# OpenTelemetry exporter (enable by setting OTEL_EXPORTER_OTLP_ENDPOINT)
if otlp_endpoint = System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT") do
  config :opentelemetry_exporter, otlp_protocol: :http_protobuf, otlp_endpoint: otlp_endpoint
  config :opentelemetry, span_processor: :batch, traces_exporter: {:opentelemetry_exporter, %{}}
end

# Bundle compiler
if zentinel_binary = System.get_env("ZENTINEL_BINARY") do
  config :zentinel_cp, ZentinelCp.Bundles.Compiler, zentinel_binary: zentinel_binary
end

# GitHub webhook secret
if webhook_secret = System.get_env("GITHUB_WEBHOOK_SECRET") do
  config :zentinel_cp, :github_webhook, secret: webhook_secret
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  # Set DATABASE_SSL=true for any database reached over a network you do not
  # control. DATABASE_CA_CERT names the CA file; otherwise the OS trust store is used.
  database_ssl =
    if System.get_env("DATABASE_SSL") in ~w(true 1) do
      ca =
        case System.get_env("DATABASE_CA_CERT") do
          nil -> [cacerts: :public_key.cacerts_get()]
          path -> [cacertfile: path]
        end

      [
        verify: :verify_peer,
        server_name_indication: String.to_charlist(URI.parse(database_url).host),
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ] ++ ca
    else
      false
    end

  config :zentinel_cp, ZentinelCp.Repo,
    ssl: database_ssl,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
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

  # Encrypts secrets stored in the database. Kept separate from SECRET_KEY_BASE
  # so that rotating sessions cannot make stored secrets unreadable.
  decode_encryption_key = fn encoded ->
    case Base.decode64(encoded) do
      {:ok, <<key::binary-32>>} -> key
      _ -> raise "encryption keys must be 32 bytes, Base64 encoded (openssl rand -base64 32)"
    end
  end

  encryption_key =
    System.get_env("ENCRYPTION_KEY") ||
      raise """
      environment variable ENCRYPTION_KEY is missing.
      You can generate one by calling: openssl rand -base64 32
      """

  old_encryption_keys =
    "ENCRYPTION_KEYS_OLD"
    |> System.get_env("")
    |> String.split(",", trim: true)

  config :zentinel_cp,
         :encryption_keys,
         Enum.map([encryption_key | old_encryption_keys], decode_encryption_key)

  host = System.get_env("PHX_HOST") || "localhost"

  config :zentinel_cp, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  port = String.to_integer(System.get_env("PORT") || "4000")

  force_ssl = System.get_env("FORCE_SSL") in ["true", "1"]
  config :zentinel_cp, :force_ssl, force_ssl

  {url_scheme, url_port} = if force_ssl, do: {"https", 443}, else: {"http", port}

  # Number of your own proxies in front of the app, for reading X-Forwarded-For.
  config :zentinel_cp,
         :trusted_proxy_count,
         String.to_integer(System.get_env("TRUSTED_PROXY_COUNT", "0"))

  # Prometheus sends this as a bearer token. Without it /metrics stays closed.
  config :zentinel_cp, :metrics_token, System.get_env("METRICS_TOKEN")

  # Webhook and notification targets on private networks are blocked by default.
  config :zentinel_cp,
         :allow_private_outbound,
         System.get_env("ALLOW_PRIVATE_OUTBOUND") in ~w(true 1)

  # Bundle signing, which also signs audit checkpoints.
  if System.get_env("BUNDLE_SIGNING_ENABLED") in ~w(true 1) do
    config :zentinel_cp, :bundle_signing,
      enabled: true,
      key_id: System.get_env("BUNDLE_SIGNING_KEY_ID", "default"),
      private_key_path:
        System.get_env("BUNDLE_SIGNING_PRIVATE_KEY_PATH") ||
          raise("BUNDLE_SIGNING_PRIVATE_KEY_PATH is required when signing is enabled"),
      public_key_path:
        System.get_env("BUNDLE_SIGNING_PUBLIC_KEY_PATH") ||
          raise("BUNDLE_SIGNING_PUBLIC_KEY_PATH is required when signing is enabled")
  end

  # Email notifications. Without a provider, email channels report a delivery error.
  case System.get_env("MAILER_ADAPTER") do
    nil ->
      config :zentinel_cp, ZentinelCp.Mailer, adapter: ZentinelCp.Mailer.NotConfigured

    "postmark" ->
      config :zentinel_cp, ZentinelCp.Mailer,
        adapter: Swoosh.Adapters.Postmark,
        api_key: System.fetch_env!("MAILER_API_KEY")

    "sendgrid" ->
      config :zentinel_cp, ZentinelCp.Mailer,
        adapter: Swoosh.Adapters.Sendgrid,
        api_key: System.fetch_env!("MAILER_API_KEY")

    "mailgun" ->
      config :zentinel_cp, ZentinelCp.Mailer,
        adapter: Swoosh.Adapters.Mailgun,
        api_key: System.fetch_env!("MAILER_API_KEY"),
        domain: System.fetch_env!("MAILER_DOMAIN")

    other ->
      raise "unknown MAILER_ADAPTER #{inspect(other)}: use postmark, sendgrid or mailgun"
  end

  config :zentinel_cp, ZentinelCpWeb.Endpoint,
    url: [host: host, port: url_port, scheme: url_scheme],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base
end
