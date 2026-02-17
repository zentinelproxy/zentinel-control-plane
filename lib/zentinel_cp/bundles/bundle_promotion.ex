defmodule ZentinelCp.Bundles.BundlePromotion do
  @moduledoc """
  BundlePromotion schema tracking which environments a bundle has been promoted to.

  A bundle can only be deployed to an environment if it has been promoted to that
  environment (or a later one in the promotion pipeline).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "bundle_promotions" do
    field :promoted_by_id, :binary_id
    field :promoted_at, :utc_datetime

    belongs_to :bundle, ZentinelCp.Bundles.Bundle
    belongs_to :environment, ZentinelCp.Projects.Environment

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a bundle promotion.
  """
  def create_changeset(promotion, attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    promotion
    |> cast(attrs, [:bundle_id, :environment_id, :promoted_by_id])
    |> validate_required([:bundle_id, :environment_id])
    |> put_change(:promoted_at, now)
    |> unique_constraint([:bundle_id, :environment_id],
      error_key: :environment_id,
      message: "bundle already promoted to this environment"
    )
    |> foreign_key_constraint(:bundle_id)
    |> foreign_key_constraint(:environment_id)
  end
end
