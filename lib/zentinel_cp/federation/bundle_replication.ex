defmodule ZentinelCp.Federation.BundleReplication do
  @moduledoc """
  Schema for tracking bundle replication across regions.

  Tracks whether each bundle has been replicated to each regional
  storage endpoint. Supports statuses: pending, replicating, replicated, failed.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(pending replicating replicated failed)

  schema "bundle_replications" do
    field :region, :string
    field :status, :string, default: "pending"
    field :replicated_at, :utc_datetime
    field :error, :string

    belongs_to :bundle, ZentinelCp.Bundles.Bundle

    timestamps(type: :utc_datetime)
  end

  def changeset(replication, attrs) do
    replication
    |> cast(attrs, [:bundle_id, :region, :status, :replicated_at, :error])
    |> validate_required([:bundle_id, :region])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:bundle_id, :region])
    |> foreign_key_constraint(:bundle_id)
  end

  def statuses, do: @statuses
end
