defmodule ZentinelCp.Services.UpstreamTarget do
  @moduledoc """
  Upstream target schema representing a single backend in an upstream group.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "upstream_targets" do
    field :host, :string
    field :port, :integer
    field :weight, :integer, default: 100
    field :max_connections, :integer
    field :enabled, :boolean, default: true

    belongs_to :upstream_group, ZentinelCp.Services.UpstreamGroup

    timestamps(type: :utc_datetime)
  end

  def changeset(target, attrs) do
    target
    |> cast(attrs, [:host, :port, :weight, :max_connections, :enabled, :upstream_group_id])
    |> validate_required([:host, :port, :upstream_group_id])
    |> validate_number(:port, greater_than: 0, less_than: 65536)
    |> validate_number(:weight, greater_than: 0)
    |> foreign_key_constraint(:upstream_group_id)
  end
end
