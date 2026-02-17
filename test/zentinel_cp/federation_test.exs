defmodule ZentinelCp.FederationTest do
  use ZentinelCp.DataCase, async: false

  alias ZentinelCp.Federation
  alias ZentinelCp.Federation.{Peer, RegionalStorage, BundleReplication}

  import ZentinelCp.ProjectsFixtures

  # ─── 17.1 Federation Peers ──────────────────────────────────────

  describe "peer schema" do
    test "creates a valid spoke peer" do
      changeset =
        Peer.changeset(%Peer{}, %{
          name: "US East Spoke",
          url: "https://spoke-us-east.zentinel.example.com",
          role: "spoke",
          region: "us-east-1"
        })

      assert changeset.valid?
    end

    test "creates a valid hub peer" do
      changeset =
        Peer.changeset(%Peer{}, %{
          name: "Hub",
          url: "https://hub.zentinel.example.com",
          role: "hub",
          region: "us-west-2"
        })

      assert changeset.valid?
    end

    test "validates role" do
      changeset =
        Peer.changeset(%Peer{}, %{
          name: "Bad Role",
          url: "https://example.com",
          role: "invalid",
          region: "us-east-1"
        })

      assert "is invalid" in errors_on(changeset).role
    end

    test "validates URL format" do
      changeset =
        Peer.changeset(%Peer{}, %{
          name: "Bad URL",
          url: "not-a-url",
          role: "spoke",
          region: "us-east-1"
        })

      assert "has invalid format" in errors_on(changeset).url
    end

    test "validates sync status" do
      changeset =
        Peer.changeset(%Peer{}, %{
          name: "Bad Status",
          url: "https://example.com",
          role: "spoke",
          region: "us-east-1",
          sync_status: "magic"
        })

      assert "is invalid" in errors_on(changeset).sync_status
    end
  end

  describe "peer CRUD" do
    test "registers, lists, and deletes peers" do
      {:ok, peer} =
        Federation.register_peer(%{
          name: "CRUD Peer",
          url: "https://crud-peer.example.com",
          role: "spoke",
          region: "eu-west-1"
        })

      assert [fetched] = Federation.list_peers()
      assert fetched.id == peer.id
      assert fetched.sync_status == "pending"

      {:ok, _} = Federation.delete_peer(peer)
      assert [] == Federation.list_peers()
    end

    test "updates a peer" do
      {:ok, peer} =
        Federation.register_peer(%{
          name: "Update Peer",
          url: "https://update-peer.example.com",
          role: "spoke",
          region: "ap-southeast-1"
        })

      {:ok, updated} = Federation.update_peer(peer, %{sync_status: "synced"})
      assert updated.sync_status == "synced"
    end

    test "lists peers by region" do
      {:ok, _} =
        Federation.register_peer(%{
          name: "EU Peer",
          url: "https://eu.example.com",
          role: "spoke",
          region: "eu-west-1"
        })

      {:ok, _} =
        Federation.register_peer(%{
          name: "US Peer",
          url: "https://us.example.com",
          role: "spoke",
          region: "us-east-1"
        })

      eu_peers = Federation.list_peers_by_region("eu-west-1")
      assert length(eu_peers) == 1
      assert hd(eu_peers).name == "EU Peer"
    end

    test "enforces unique URLs" do
      {:ok, _} =
        Federation.register_peer(%{
          name: "Peer 1",
          url: "https://unique-url.example.com",
          role: "spoke",
          region: "us-east-1"
        })

      {:error, changeset} =
        Federation.register_peer(%{
          name: "Peer 2",
          url: "https://unique-url.example.com",
          role: "spoke",
          region: "us-west-2"
        })

      assert errors_on(changeset).url != nil
    end
  end

  # ─── 17.2 Regional Storage ─────────────────────────────────────

  describe "regional storage" do
    test "creates a valid storage config" do
      changeset =
        RegionalStorage.changeset(%RegionalStorage{}, %{
          region: "us-east-1",
          bucket: "zentinel-bundles-us-east",
          endpoint: "https://s3.us-east-1.amazonaws.com"
        })

      assert changeset.valid?
    end

    test "configures and retrieves regional storage" do
      {:ok, storage} =
        Federation.configure_storage(%{
          region: "eu-west-1",
          bucket: "zentinel-bundles-eu",
          endpoint: "https://s3.eu-west-1.amazonaws.com"
        })

      assert fetched = Federation.get_regional_storage("eu-west-1")
      assert fetched.id == storage.id
      assert fetched.bucket == "zentinel-bundles-eu"
    end

    test "lists all regional storages" do
      {:ok, _} =
        Federation.configure_storage(%{
          region: "us-east-1",
          bucket: "b1",
          endpoint: "https://s3.us-east-1.amazonaws.com"
        })

      {:ok, _} =
        Federation.configure_storage(%{
          region: "eu-west-1",
          bucket: "b2",
          endpoint: "https://s3.eu-west-1.amazonaws.com"
        })

      storages = Federation.list_regional_storages()
      assert length(storages) == 2
    end
  end

  # ─── 17.2 Bundle Replication ────────────────────────────────────

  describe "bundle replication" do
    setup do
      project = project_fixture()
      bundle = bundle_fixture(project)
      %{project: project, bundle: bundle}
    end

    test "tracks replication to a region", %{bundle: bundle} do
      {:ok, replication} =
        Federation.track_replication(%{
          bundle_id: bundle.id,
          region: "us-east-1"
        })

      assert replication.status == "pending"
      assert replication.region == "us-east-1"
    end

    test "updates replication status", %{bundle: bundle} do
      {:ok, replication} =
        Federation.track_replication(%{
          bundle_id: bundle.id,
          region: "eu-west-1"
        })

      {:ok, updated} =
        Federation.update_replication(replication, %{
          status: "replicated",
          replicated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      assert updated.status == "replicated"
    end

    test "gets replication status for a bundle", %{bundle: bundle} do
      {:ok, _} =
        Federation.track_replication(%{bundle_id: bundle.id, region: "us-east-1"})

      {:ok, _} =
        Federation.track_replication(%{bundle_id: bundle.id, region: "eu-west-1"})

      statuses = Federation.bundle_replication_status(bundle.id)
      assert length(statuses) == 2
    end

    test "bundle_fully_replicated? checks all enabled regions", %{bundle: bundle} do
      # No regions configured = fully replicated (vacuously true)
      assert Federation.bundle_fully_replicated?(bundle.id)

      # Add a region
      {:ok, _} =
        Federation.configure_storage(%{
          region: "us-east-1",
          bucket: "b1",
          endpoint: "https://s3.us-east-1.amazonaws.com"
        })

      # Not yet replicated
      refute Federation.bundle_fully_replicated?(bundle.id)

      # Track replication as complete
      {:ok, _} =
        Federation.track_replication(%{
          bundle_id: bundle.id,
          region: "us-east-1",
          status: "replicated"
        })

      assert Federation.bundle_fully_replicated?(bundle.id)
    end

    test "validates replication statuses" do
      changeset =
        BundleReplication.changeset(%BundleReplication{}, %{
          bundle_id: Ecto.UUID.generate(),
          region: "us-east-1",
          status: "invalid"
        })

      assert "is invalid" in errors_on(changeset).status
    end
  end

  # ─── 17.3 Cross-Region Orchestration ────────────────────────────

  describe "cross-region orchestration" do
    test "sequential ordering returns regions in order" do
      regions = ["us-east-1", "eu-west-1", "ap-southeast-1"]
      order = Federation.region_rollout_order("sequential", regions)
      assert order == ["us-east-1", "eu-west-1", "ap-southeast-1"]
    end

    test "parallel ordering groups all regions" do
      regions = ["us-east-1", "eu-west-1", "ap-southeast-1"]
      order = Federation.region_rollout_order("parallel", regions)
      assert order == [["us-east-1", "eu-west-1", "ap-southeast-1"]]
    end

    test "staged ordering creates batches" do
      regions = ["r1", "r2", "r3", "r4", "r5", "r6"]
      order = Federation.region_rollout_order("staged", regions)
      assert length(order) >= 2
      assert List.flatten(order) == regions
    end
  end

  # ─── Helpers ─────────────────────────────────────────────────────

  defp bundle_fixture(project) do
    {:ok, bundle} =
      ZentinelCp.Bundles.create_bundle(%{
        project_id: project.id,
        version: "fed-test-#{System.unique_integer([:positive])}",
        config_source: "test config",
        source_type: "api"
      })

    bundle
  end
end
