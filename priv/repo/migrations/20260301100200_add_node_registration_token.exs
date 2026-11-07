defmodule ZentinelCp.Repo.Migrations.AddNodeRegistrationToken do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :node_registration_token_hash, :string
    end
  end
end
