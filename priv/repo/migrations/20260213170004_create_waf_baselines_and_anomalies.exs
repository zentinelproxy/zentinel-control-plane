defmodule ZentinelCp.Repo.Migrations.CreateWafBaselinesAndAnomalies do
  use Ecto.Migration

  def change do
    create table(:waf_baselines, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :service_id, references(:services, type: :binary_id, on_delete: :nilify_all)
      add :metric_type, :string, null: false
      add :period, :string, default: "hourly"
      add :mean, :float
      add :stddev, :float
      add :sample_count, :integer, default: 0
      add :last_computed_at, :utc_datetime
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:waf_baselines, [:project_id, :service_id, :metric_type, :period],
             name: :waf_baselines_project_service_metric_period
           )

    create table(:waf_anomalies, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :service_id, references(:services, type: :binary_id, on_delete: :nilify_all)
      add :anomaly_type, :string, null: false
      add :severity, :string, default: "medium"
      add :status, :string, default: "active"
      add :detected_at, :utc_datetime, null: false
      add :resolved_at, :utc_datetime
      add :description, :string
      add :observed_value, :float
      add :expected_mean, :float
      add :expected_stddev, :float
      add :deviation_sigma, :float
      add :evidence, :map, default: %{}
      add :acknowledged_by, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:waf_anomalies, [:project_id, :detected_at])
    create index(:waf_anomalies, [:status])
  end
end
