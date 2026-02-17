defmodule ZentinelCp.Rollouts.FreezeWindow do
  @moduledoc """
  Schema for deployment freeze windows.

  Calendar-based freeze windows prevent rollout creation during specified periods.
  Supports per-environment freezes and emergency override capability.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "freeze_windows" do
    field :name, :string
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime
    field :reason, :string
    field :created_by_id, :binary_id

    belongs_to :project, ZentinelCp.Projects.Project
    belongs_to :environment, ZentinelCp.Projects.Environment

    timestamps(type: :utc_datetime)
  end

  def changeset(window, attrs) do
    window
    |> cast(attrs, [
      :project_id,
      :environment_id,
      :name,
      :starts_at,
      :ends_at,
      :reason,
      :created_by_id
    ])
    |> validate_required([:project_id, :name, :starts_at, :ends_at])
    |> validate_window_range()
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:environment_id)
  end

  defp validate_window_range(changeset) do
    starts_at = get_field(changeset, :starts_at)
    ends_at = get_field(changeset, :ends_at)

    if starts_at && ends_at && DateTime.compare(ends_at, starts_at) != :gt do
      add_error(changeset, :ends_at, "must be after starts_at")
    else
      changeset
    end
  end

  @doc """
  Checks if a given datetime falls within this freeze window.
  """
  def active?(%__MODULE__{starts_at: starts_at, ends_at: ends_at}, datetime \\ nil) do
    dt = datetime || DateTime.utc_now()

    DateTime.compare(dt, starts_at) in [:gt, :eq] and
      DateTime.compare(dt, ends_at) in [:lt, :eq]
  end
end
