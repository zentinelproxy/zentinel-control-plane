defmodule ZentinelCp.Rollouts.RolloutApproval do
  @moduledoc """
  Schema representing a user's approval of a rollout.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "rollout_approvals" do
    belongs_to :rollout, ZentinelCp.Rollouts.Rollout
    belongs_to :user, ZentinelCp.Accounts.User
    field :approved_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(approval, attrs) do
    approval
    |> cast(attrs, [:rollout_id, :user_id, :approved_at])
    |> validate_required([:rollout_id, :user_id, :approved_at])
    |> unique_constraint([:rollout_id, :user_id])
    |> foreign_key_constraint(:rollout_id)
    |> foreign_key_constraint(:user_id)
  end
end
