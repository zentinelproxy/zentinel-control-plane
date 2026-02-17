defmodule ZentinelCp.Repo.Migrations.AddDeliveryAttemptBodies do
  use Ecto.Migration

  def change do
    alter table(:delivery_attempts) do
      add :request_body, :text
      add :response_body, :text
    end
  end
end
