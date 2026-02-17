defmodule ZentinelCp.Federation do
  @moduledoc """
  The Federation context manages multi-cluster control plane topology.

  Supports hub-and-spoke federation where one hub CP coordinates
  multiple spoke CPs across regions.
  """

  import Ecto.Query, warn: false
  alias ZentinelCp.Repo
  alias ZentinelCp.Federation.{Peer, RegionalStorage, BundleReplication}

  ## Peers

  @doc "Registers a new federation peer."
  def register_peer(attrs) do
    %Peer{}
    |> Peer.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a federation peer."
  def update_peer(peer, attrs) do
    peer
    |> Peer.changeset(attrs)
    |> Repo.update()
  end

  @doc "Gets a peer by ID."
  def get_peer(id), do: Repo.get(Peer, id)

  @doc "Lists all federation peers."
  def list_peers do
    from(p in Peer, order_by: [asc: p.region, asc: p.name])
    |> Repo.all()
  end

  @doc "Lists peers by region."
  def list_peers_by_region(region) do
    from(p in Peer, where: p.region == ^region)
    |> Repo.all()
  end

  @doc "Deletes a federation peer."
  def delete_peer(peer), do: Repo.delete(peer)

  ## Regional Storage

  @doc "Configures storage for a region."
  def configure_storage(attrs) do
    %RegionalStorage{}
    |> RegionalStorage.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Gets storage config for a region."
  def get_regional_storage(region) do
    Repo.get_by(RegionalStorage, region: region)
  end

  @doc "Lists all regional storage configs."
  def list_regional_storages do
    from(s in RegionalStorage, order_by: [asc: s.region])
    |> Repo.all()
  end

  ## Bundle Replication

  @doc "Tracks a bundle replication to a region."
  def track_replication(attrs) do
    %BundleReplication{}
    |> BundleReplication.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates replication status."
  def update_replication(replication, attrs) do
    replication
    |> BundleReplication.changeset(attrs)
    |> Repo.update()
  end

  @doc "Gets replication status for a bundle across all regions."
  def bundle_replication_status(bundle_id) do
    from(r in BundleReplication,
      where: r.bundle_id == ^bundle_id,
      order_by: [asc: r.region]
    )
    |> Repo.all()
  end

  @doc "Checks if a bundle is replicated to all enabled regions."
  def bundle_fully_replicated?(bundle_id) do
    enabled_regions =
      from(s in RegionalStorage, where: s.enabled == true, select: s.region)
      |> Repo.all()

    replicated_regions =
      from(r in BundleReplication,
        where: r.bundle_id == ^bundle_id and r.status == "replicated",
        select: r.region
      )
      |> Repo.all()

    MapSet.subset?(MapSet.new(enabled_regions), MapSet.new(replicated_regions))
  end

  ## Cross-Region Orchestration

  @doc """
  Returns the region ordering for a cross-region rollout.
  """
  def region_rollout_order(strategy, regions) do
    case strategy do
      "sequential" -> regions
      "parallel" -> [regions]
      "staged" -> Enum.chunk_every(regions, max(div(length(regions), 3), 1))
      _ -> [regions]
    end
  end
end
