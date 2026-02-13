Mox.defmock(SentinelCp.Webhooks.GitHubClient.Mock,
  for: SentinelCp.Webhooks.GitHubClient
)

Mox.defmock(SentinelCp.Services.DnsResolver.Mock,
  for: SentinelCp.Services.DnsResolver
)

Mox.defmock(SentinelCp.Services.K8sResolver.Mock,
  for: SentinelCp.Services.K8sResolver
)

Mox.defmock(SentinelCp.Services.Acme.Client.Mock,
  for: SentinelCp.Services.Acme.Client
)

# Start Wallaby only if running E2E tests and ChromeDriver is available
# E2E tests require ChromeDriver to be installed
if System.get_env("WALLABY_DRIVER") != "disabled" do
  # Check common chromedriver locations on macOS and Linux
  # Prefer homebrew/system installs which are more likely to match Chrome version
  chromedriver_paths = [
    # Homebrew on Apple Silicon
    "/opt/homebrew/bin/chromedriver",
    # Homebrew on Intel Mac / Linux
    "/usr/local/bin/chromedriver",
    # Linux system install
    "/usr/bin/chromedriver",
    # User install (last resort)
    Path.expand("~/bin/chromedriver")
  ]

  chromedriver_found =
    Enum.find(chromedriver_paths, fn path ->
      File.exists?(path) && File.regular?(path)
    end)

  case chromedriver_found do
    nil ->
      # Try which as a fallback
      case System.cmd("which", ["chromedriver"], stderr_to_stdout: true) do
        {path, 0} when path != "" ->
          {:ok, _} = Application.ensure_all_started(:wallaby)

        _ ->
          IO.puts("ChromeDriver not found - E2E tests will be skipped")
      end

    path ->
      # Set chromedriver path for Wallaby (must be keyword list with :path key)
      Application.put_env(:wallaby, :chromedriver, path: path)
      {:ok, _} = Application.ensure_all_started(:wallaby)
  end
end

# Exclude e2e and integration tests by default (run with --include e2e or --include integration)
ExUnit.start(exclude: [:e2e, :integration])

# For SQLite, the sandbox mode works but without async support
# Check if the pool is configured as Sandbox, otherwise skip
repo_config = Application.get_env(:sentinel_cp, SentinelCp.Repo, [])

if repo_config[:pool] == Ecto.Adapters.SQL.Sandbox do
  Ecto.Adapters.SQL.Sandbox.mode(SentinelCp.Repo, :manual)
end
