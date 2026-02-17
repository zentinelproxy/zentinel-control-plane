defmodule ZentinelCp.Repo.Migrations.AddServicePolicyFields do
  use Ecto.Migration

  def change do
    alter table(:services) do
      add :cors, :map, default: %{}
      add :access_control, :map, default: %{}
      add :compression, :map, default: %{}
      add :path_rewrite, :map, default: %{}
      add :redirect_url, :string
    end

    alter table(:project_configs) do
      add :default_cors, :map, default: %{}
      add :default_compression, :map, default: %{}
      add :global_access_control, :map, default: %{}
    end
  end
end
