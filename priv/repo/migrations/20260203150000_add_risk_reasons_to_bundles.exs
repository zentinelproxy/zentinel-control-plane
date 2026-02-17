defmodule ZentinelCp.Repo.Migrations.AddRiskReasonsToBundles do
  use Ecto.Migration

  def change do
    alter table(:bundles) do
      add :risk_reasons, {:array, :string}, default: []
    end
  end
end
