defmodule ZentinelCp.Repo.Migrations.AddSourceRefFields do
  use Ecto.Migration

  def change do
    alter table(:bundles) do
      add :source_type, :string, default: "api"
      add :source_ref, :string
      add :source_branch, :string
      add :source_repo, :string
    end

    alter table(:projects) do
      add :github_repo, :string
      add :github_branch, :string, default: "main"
      add :config_path, :string, default: "zentinel.kdl"
    end

    create index(:projects, [:github_repo])
  end
end
