defmodule ZentinelCp.Projects.PromotionRule do
  @moduledoc """
  Schema for cross-environment promotion automation rules.

  Defines conditions under which a successfully deployed bundle
  in one environment should be automatically promoted to the next.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "promotion_rules" do
    field :auto_promote, :boolean, default: false
    field :delay_minutes, :integer, default: 0
    field :conditions, :map, default: %{}
    field :enabled, :boolean, default: true

    belongs_to :project, ZentinelCp.Projects.Project
    belongs_to :source_env, ZentinelCp.Projects.Environment
    belongs_to :target_env, ZentinelCp.Projects.Environment

    timestamps(type: :utc_datetime)
  end

  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [
      :project_id,
      :source_env_id,
      :target_env_id,
      :auto_promote,
      :delay_minutes,
      :conditions,
      :enabled
    ])
    |> validate_required([:project_id, :source_env_id, :target_env_id])
    |> validate_number(:delay_minutes, greater_than_or_equal_to: 0)
    |> validate_different_environments()
    |> unique_constraint([:project_id, :source_env_id, :target_env_id])
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:source_env_id)
    |> foreign_key_constraint(:target_env_id)
  end

  defp validate_different_environments(changeset) do
    source = get_field(changeset, :source_env_id)
    target = get_field(changeset, :target_env_id)

    if source && target && source == target do
      add_error(changeset, :target_env_id, "must be different from source environment")
    else
      changeset
    end
  end
end
