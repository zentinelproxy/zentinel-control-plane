import Config

# Configure your database (SQLite for tests)
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :sentinel_cp, SentinelCp.Repo,
  database: Path.expand("../sentinel_cp_test#{System.get_env("MIX_TEST_PARTITION")}.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# Enable server for E2E tests (Wallaby requires the server to be running)
config :sentinel_cp, SentinelCpWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "mweJf2rSnJcf9V7CCs4PuqhL5GB97+9ODEFraHiqbGuEA2AOh1jd0PWGlMIhr6Kv",
  server: true

# In test we don't send emails
config :sentinel_cp, SentinelCp.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Disable Oban queues during tests (use Oban.Testing)
config :sentinel_cp, Oban, testing: :inline

# Mark test environment (used to skip async notifications)
config :sentinel_cp, :env, :test

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Bundle signing disabled in test (individual tests can override)
config :sentinel_cp, :bundle_signing, enabled: false

# GitHub webhook test secret
config :sentinel_cp, :github_webhook, secret: "test_webhook_secret"

# Use mock GitHub client in tests
config :sentinel_cp, :github_client, SentinelCp.Webhooks.GitHubClient.Mock

# Use mock DNS resolver in tests
config :sentinel_cp, :dns_resolver, SentinelCp.Services.DnsResolver.Mock

# Wallaby E2E test configuration
config :wallaby,
  otp_app: :sentinel_cp,
  driver: Wallaby.Chrome,
  base_url: "http://localhost:4002",
  screenshot_on_failure: true,
  screenshot_dir: "tmp/screenshots",
  max_wait_time: 5_000,
  # Run in headless mode for CI environments
  chrome: [
    headless: System.get_env("CI") == "true"
  ]
