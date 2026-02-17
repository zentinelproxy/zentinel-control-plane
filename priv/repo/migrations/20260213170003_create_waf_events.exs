defmodule ZentinelCp.Repo.Migrations.CreateWafEvents do
  use Ecto.Migration

  def change do
    create table(:waf_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :service_id, references(:services, type: :binary_id, on_delete: :nilify_all)
      add :node_id, references(:nodes, type: :binary_id, on_delete: :nilify_all)
      add :timestamp, :utc_datetime_usec, null: false
      add :rule_type, :string, null: false
      add :rule_id, :string
      add :action, :string, null: false
      add :severity, :string
      add :client_ip, :string
      add :method, :string
      add :path, :string
      add :matched_data, :string
      add :user_agent, :string
      add :geo_country, :string
      add :request_headers, :map, default: %{}
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:waf_events, [:project_id, :timestamp])
    create index(:waf_events, [:service_id, :timestamp])
    create index(:waf_events, [:client_ip])
    create index(:waf_events, [:rule_type])
  end
end
