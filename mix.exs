defmodule ZentinelCp.MixProject do
  use Mix.Project

  def project do
    [
      app: :zentinel_cp,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      hex: [ignore_advisories: ignored_advisories()]
    ]
  end

  # Advisories that do not affect this application. No patched release exists
  # for any of them. Review this list when updating dependencies.
  defp ignored_advisories do
    [
      # esaml: XXE. SamlValidator rejects DTDs and non-UTF-8 input before parsing.
      "EEF-CVE-2026-28809",
      # esaml: atom exhaustion while parsing. SamlValidator rejects any name that
      # is not already an atom before parsing.
      "EEF-CVE-2026-105270",
      # esaml: atom exhaustion from LogoutResponse status codes. Logout is unused.
      "EEF-CVE-2026-86696",
      # esaml: unbounded decompression. Responses use the POST binding, which is
      # not compressed, and their size is capped.
      "EEF-CVE-2026-93471",
      # cowboy and cowlib are only present because esaml depends on them. HTTP is
      # served by Bandit, so their HTTP parsers never see a request.
      "EEF-CVE-2026-115701",
      "EEF-CVE-2026-113431",
      "EEF-CVE-2026-43966",
      # hackney and tesla are test-only dependencies of wallaby.
      "EEF-CVE-2026-115693",
      "EEF-CVE-2026-47069",
      "EEF-CVE-2026-47071",
      "EEF-CVE-2026-47075",
      "EEF-CVE-2026-47076",
      "EEF-CVE-2026-48594",
      "EEF-CVE-2026-48595",
      "EEF-CVE-2026-48596",
      "EEF-CVE-2026-48597",
      "EEF-CVE-2026-48598"
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {ZentinelCp.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [
        precommit: :test,
        "test.unit": :test,
        "test.integration": :test,
        "test.e2e": :test,
        "test.all": :test
      ]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      # Phoenix
      {:phoenix, "~> 1.8.3"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:ecto_sqlite3, "~> 0.17"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.13"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.9.1"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.16"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.3.1"},
      {:bandit, "~> 1.5"},

      # Background jobs
      {:oban, "~> 2.19"},

      # Object storage (S3/MinIO)
      {:ex_aws, "~> 2.5"},
      {:ex_aws_s3, "~> 2.5"},

      # Security
      {:argon2_elixir, "~> 4.1"},
      {:plug_crypto, "~> 2.1"},
      {:jose, "~> 1.11"},
      {:nimble_totp, "~> 1.0"},
      {:openid_connect, "~> 1.0"},
      {:esaml, "~> 4.6"},

      # Observability
      {:prom_ex, "~> 1.11"},
      {:logger_json, "~> 7.0"},
      {:opentelemetry, "~> 1.4"},
      {:opentelemetry_api, "~> 1.3"},
      {:opentelemetry_exporter, "~> 1.7"},
      {:opentelemetry_phoenix, "~> 1.2"},
      {:opentelemetry_ecto, "~> 1.2"},

      # GraphQL
      {:absinthe, "~> 1.7"},
      {:absinthe_plug, "~> 1.5"},
      {:absinthe_phoenix, "~> 2.0"},

      # Utilities
      {:typed_struct, "~> 0.3"},
      {:nimble_options, "~> 1.1"},
      {:yaml_elixir, "~> 2.11"},
      {:ymlr, "~> 5.0"},

      # Dev/Test tools
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_machina, "~> 2.8", only: :test},
      {:mox, "~> 1.2", only: :test},
      {:wallaby, "~> 0.30", only: :test, runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "test.unit": [
        "ecto.create --quiet",
        "ecto.migrate --quiet",
        "test --exclude e2e --exclude integration"
      ],
      "test.integration": [
        "ecto.create --quiet",
        "ecto.migrate --quiet",
        "test --only integration"
      ],
      "test.e2e": ["ecto.create --quiet", "ecto.migrate --quiet", "test --only e2e"],
      "test.all": [
        "ecto.create --quiet",
        "ecto.migrate --quiet",
        "test --include e2e --include integration"
      ],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind zentinel_cp", "esbuild zentinel_cp"],
      "assets.deploy": [
        "tailwind zentinel_cp --minify",
        "esbuild zentinel_cp --minify",
        "phx.digest"
      ],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
