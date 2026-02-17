defmodule ZentinelCp.Services.DiscoverySource do
  @moduledoc """
  Schema for DNS-based service discovery sources.

  A discovery source attaches to an upstream group and periodically resolves
  SRV records to reconcile upstream targets automatically.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @source_types ~w(dns_srv kubernetes consul)
  @sync_statuses ~w(pending syncing synced error)

  schema "discovery_sources" do
    field :source_type, :string, default: "dns_srv"
    field :hostname, :string
    field :config, :map, default: %{}
    field :sync_interval_seconds, :integer, default: 60
    field :auto_sync, :boolean, default: true
    field :last_synced_at, :utc_datetime
    field :last_sync_status, :string, default: "pending"
    field :last_sync_error, :string
    field :last_sync_targets_count, :integer, default: 0

    belongs_to :upstream_group, ZentinelCp.Services.UpstreamGroup
    belongs_to :project, ZentinelCp.Projects.Project

    timestamps(type: :utc_datetime)
  end

  def changeset(source, attrs) do
    source
    |> cast(attrs, [
      :source_type,
      :hostname,
      :config,
      :sync_interval_seconds,
      :auto_sync,
      :upstream_group_id,
      :project_id
    ])
    |> validate_required([:upstream_group_id, :project_id])
    |> validate_inclusion(:source_type, @source_types)
    |> validate_source_type_fields()
    |> validate_number(:sync_interval_seconds, greater_than_or_equal_to: 10)
    |> unique_constraint(:upstream_group_id)
    |> foreign_key_constraint(:upstream_group_id)
    |> foreign_key_constraint(:project_id)
  end

  def update_changeset(source, attrs) do
    source
    |> cast(attrs, [:hostname, :config, :sync_interval_seconds, :auto_sync])
    |> validate_source_type_fields()
    |> validate_number(:sync_interval_seconds, greater_than_or_equal_to: 10)
  end

  defp validate_source_type_fields(changeset) do
    source_type = get_field(changeset, :source_type)

    case source_type do
      "kubernetes" ->
        changeset
        |> validate_k8s_config()

      "consul" ->
        changeset
        |> validate_consul_config()

      _ ->
        # dns_srv (default)
        validate_required(changeset, [:hostname])
    end
  end

  defp validate_k8s_config(changeset) do
    config = get_field(changeset, :config) || %{}

    changeset
    |> validate_k8s_required_key(config, "namespace")
    |> validate_k8s_required_key(config, "service_name")
  end

  defp validate_k8s_required_key(changeset, config, key) do
    if is_binary(config[key]) and config[key] != "" do
      changeset
    else
      add_error(changeset, :config, "must include #{key}")
    end
  end

  defp validate_consul_config(changeset) do
    config = get_field(changeset, :config) || %{}

    changeset
    |> validate_consul_required_key(config, "consul_addr")
    |> validate_consul_required_key(config, "service_name")
  end

  defp validate_consul_required_key(changeset, config, key) do
    if is_binary(config[key]) and config[key] != "" do
      changeset
    else
      add_error(changeset, :config, "must include #{key}")
    end
  end

  def sync_changeset(source, attrs) do
    source
    |> cast(attrs, [
      :last_synced_at,
      :last_sync_status,
      :last_sync_error,
      :last_sync_targets_count
    ])
    |> validate_inclusion(:last_sync_status, @sync_statuses)
  end
end
