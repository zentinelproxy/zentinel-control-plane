defmodule ZentinelCp.Services.ServiceMiddleware do
  @moduledoc """
  Join schema linking a middleware to a service with position ordering.

  Each record represents one middleware attached to a service's middleware chain.
  The `position` field controls execution order, and `config_override` allows
  per-service customization of the middleware's base config.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "service_middlewares" do
    field :position, :integer, default: 0
    field :enabled, :boolean, default: true
    field :config_override, :map, default: %{}

    belongs_to :service, ZentinelCp.Services.Service
    belongs_to :middleware, ZentinelCp.Services.Middleware

    timestamps(type: :utc_datetime)
  end

  def changeset(service_middleware, attrs) do
    service_middleware
    |> cast(attrs, [:position, :enabled, :config_override, :service_id, :middleware_id])
    |> validate_required([:service_id, :middleware_id])
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> unique_constraint([:service_id, :middleware_id])
    |> foreign_key_constraint(:service_id)
    |> foreign_key_constraint(:middleware_id)
  end
end
