defmodule SentinelCp.Repo.Migrations.AddSecurityAndTransformFields do
  use Ecto.Migration

  def change do
    alter table(:services) do
      add :security, :map, default: %{}
      add :request_transform, :map, default: %{}
      add :response_transform, :map, default: %{}
    end

    alter table(:project_configs) do
      add :default_security, :map, default: %{}
    end
  end
end
