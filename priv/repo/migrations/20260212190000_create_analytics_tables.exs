defmodule ZentinelCp.Repo.Migrations.CreateAnalyticsTables do
  use Ecto.Migration

  def change do
    create table(:service_metrics, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :service_id, references(:services, type: :binary_id, on_delete: :delete_all),
        null: false

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :period_start, :utc_datetime, null: false
      add :period_seconds, :integer, default: 60, null: false
      add :request_count, :integer, default: 0, null: false
      add :error_count, :integer, default: 0, null: false
      add :latency_p50_ms, :integer
      add :latency_p95_ms, :integer
      add :latency_p99_ms, :integer
      add :bandwidth_in_bytes, :bigint, default: 0
      add :bandwidth_out_bytes, :bigint, default: 0
      add :status_2xx, :integer, default: 0
      add :status_3xx, :integer, default: 0
      add :status_4xx, :integer, default: 0
      add :status_5xx, :integer, default: 0
      add :top_paths, :map, default: %{}
      add :top_consumers, :map, default: %{}

      timestamps()
    end

    create index(:service_metrics, [:project_id, :period_start])
    create index(:service_metrics, [:service_id, :period_start])

    create table(:request_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :service_id, references(:services, type: :binary_id, on_delete: :delete_all),
        null: false

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :node_id, references(:nodes, type: :binary_id, on_delete: :nilify_all)
      add :timestamp, :utc_datetime_usec, null: false
      add :method, :string
      add :path, :string
      add :status, :integer
      add :latency_ms, :integer
      add :client_ip, :string
      add :user_agent, :string
      add :request_size, :integer
      add :response_size, :integer

      timestamps()
    end

    create index(:request_logs, [:service_id, :timestamp])
    create index(:request_logs, [:project_id, :timestamp])
  end
end
