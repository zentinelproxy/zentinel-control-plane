defmodule SentinelCp.Repo.Migrations.AddTrafficSplitToServices do
  use Ecto.Migration

  def change do
    alter table(:services) do
      add :traffic_split, :map, default: %{}
    end
  end
end
