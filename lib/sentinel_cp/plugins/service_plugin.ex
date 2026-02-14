defmodule SentinelCp.Plugins.ServicePlugin do
  @moduledoc """
  Join schema linking a plugin to a service with position ordering.

  Each record represents one plugin attached to a service's plugin chain.
  The `position` field controls execution order, `config_override` allows
  per-service customization, and `plugin_version_id` pins a specific version
  (nil means use latest).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "service_plugins" do
    field :position, :integer, default: 0
    field :enabled, :boolean, default: true
    field :config_override, :map, default: %{}

    belongs_to :service, SentinelCp.Services.Service
    belongs_to :plugin, SentinelCp.Plugins.Plugin
    belongs_to :plugin_version, SentinelCp.Plugins.PluginVersion

    timestamps(type: :utc_datetime)
  end

  def changeset(service_plugin, attrs) do
    service_plugin
    |> cast(attrs, [
      :position,
      :enabled,
      :config_override,
      :service_id,
      :plugin_id,
      :plugin_version_id
    ])
    |> validate_required([:service_id, :plugin_id])
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> unique_constraint([:service_id, :plugin_id])
    |> foreign_key_constraint(:service_id)
    |> foreign_key_constraint(:plugin_id)
    |> foreign_key_constraint(:plugin_version_id)
  end
end
