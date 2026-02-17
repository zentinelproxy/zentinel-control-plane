defmodule ZentinelCp.Repo.Migrations.AddInferenceToServices do
  use Ecto.Migration

  def change do
    alter table(:services) do
      add :service_type, :string, default: "standard"
      add :inference, :map, default: %{}
    end

    create index(:services, [:project_id, :service_type])
  end
end
