defmodule ZentinelCp.Policies.Violation do
  @moduledoc """
  Schema for policy violation records.

  Violations are recorded when a policy expression evaluates to false
  against a given action context. In dry_run mode, violations are logged
  but don't block the action.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "policy_violations" do
    field :resource_type, :string
    field :resource_id, :binary_id
    field :action, :string
    field :message, :string
    field :context, :map, default: %{}
    field :dry_run, :boolean, default: false

    belongs_to :policy, ZentinelCp.Policies.Policy
    belongs_to :project, ZentinelCp.Projects.Project

    timestamps(type: :utc_datetime)
  end

  def changeset(violation, attrs) do
    violation
    |> cast(attrs, [
      :policy_id,
      :project_id,
      :resource_type,
      :resource_id,
      :action,
      :message,
      :context,
      :dry_run
    ])
    |> validate_required([:policy_id, :project_id, :resource_type, :action])
    |> foreign_key_constraint(:policy_id)
    |> foreign_key_constraint(:project_id)
  end
end
