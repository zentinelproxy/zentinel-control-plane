defmodule ZentinelCp.Repo.Migrations.AddServiceTypeConfigs do
  use Ecto.Migration

  def change do
    alter table(:services) do
      add :grpc, :map, default: %{}
      add :websocket, :map, default: %{}
      add :graphql, :map, default: %{}
      add :streaming, :map, default: %{}
    end
  end
end
