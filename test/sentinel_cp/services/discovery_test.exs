defmodule SentinelCp.Services.DiscoveryTest do
  use SentinelCp.DataCase

  import Mox
  import SentinelCp.ProjectsFixtures
  import SentinelCp.UpstreamGroupFixtures

  alias SentinelCp.Services
  alias SentinelCp.Services.{DiscoverySource, DiscoverySync}

  setup :verify_on_exit!

  # --- DiscoverySync (pure reconciliation) ---

  describe "DiscoverySync.reconcile/2" do
    test "adds new targets from SRV records" do
      current = []
      srv_records = [{10, 50, 8080, ~c"api1.internal"}, {10, 100, 8081, ~c"api2.internal"}]

      result = DiscoverySync.reconcile(current, srv_records)

      assert length(result.add) == 2
      assert %{host: "api1.internal", port: 8080, weight: 50} in result.add
      assert %{host: "api2.internal", port: 8081, weight: 100} in result.add
      assert result.remove == []
      assert result.keep == []
    end

    test "removes targets not in SRV records" do
      t1 = %{id: "t1", host: "old.internal", port: 8080}
      t2 = %{id: "t2", host: "api1.internal", port: 8080}
      current = [t1, t2]
      srv_records = [{10, 50, 8080, ~c"api1.internal"}]

      result = DiscoverySync.reconcile(current, srv_records)

      assert result.add == []
      assert result.remove == [t1]
      assert result.keep == [t2]
    end

    test "keeps existing targets that match SRV records" do
      t1 = %{id: "t1", host: "api1.internal", port: 8080}
      current = [t1]
      srv_records = [{10, 50, 8080, ~c"api1.internal"}]

      result = DiscoverySync.reconcile(current, srv_records)

      assert result.add == []
      assert result.remove == []
      assert result.keep == [t1]
    end

    test "handles mixed add/remove/keep" do
      t1 = %{id: "t1", host: "keep.internal", port: 8080}
      t2 = %{id: "t2", host: "remove.internal", port: 9090}
      current = [t1, t2]

      srv_records = [
        {10, 50, 8080, ~c"keep.internal"},
        {10, 75, 3000, ~c"new.internal"}
      ]

      result = DiscoverySync.reconcile(current, srv_records)

      assert length(result.add) == 1
      assert %{host: "new.internal", port: 3000, weight: 75} in result.add
      assert result.remove == [t2]
      assert result.keep == [t1]
    end

    test "maps SRV weight 0 to 1" do
      result = DiscoverySync.reconcile([], [{10, 0, 8080, ~c"zero.internal"}])

      assert [%{weight: 1}] = result.add
    end

    test "handles empty SRV records (removes all)" do
      t1 = %{id: "t1", host: "api.internal", port: 8080}
      result = DiscoverySync.reconcile([t1], [])

      assert result.add == []
      assert result.remove == [t1]
      assert result.keep == []
    end

    test "handles both empty" do
      result = DiscoverySync.reconcile([], [])

      assert result.add == []
      assert result.remove == []
      assert result.keep == []
    end
  end

  # --- DiscoverySource schema ---

  describe "DiscoverySource.changeset/2" do
    test "valid changeset" do
      changeset =
        DiscoverySource.changeset(%DiscoverySource{}, %{
          hostname: "_http._tcp.api.internal",
          upstream_group_id: Ecto.UUID.generate(),
          project_id: Ecto.UUID.generate()
        })

      assert changeset.valid?
    end

    test "requires hostname" do
      changeset =
        DiscoverySource.changeset(%DiscoverySource{}, %{
          upstream_group_id: Ecto.UUID.generate(),
          project_id: Ecto.UUID.generate()
        })

      assert %{hostname: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires upstream_group_id" do
      changeset =
        DiscoverySource.changeset(%DiscoverySource{}, %{
          hostname: "_http._tcp.api.internal",
          project_id: Ecto.UUID.generate()
        })

      assert %{upstream_group_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates source_type inclusion" do
      changeset =
        DiscoverySource.changeset(%DiscoverySource{}, %{
          hostname: "_http._tcp.api.internal",
          source_type: "consul",
          upstream_group_id: Ecto.UUID.generate(),
          project_id: Ecto.UUID.generate()
        })

      assert %{source_type: _} = errors_on(changeset)
    end

    test "validates sync_interval_seconds >= 10" do
      changeset =
        DiscoverySource.changeset(%DiscoverySource{}, %{
          hostname: "_http._tcp.api.internal",
          sync_interval_seconds: 5,
          upstream_group_id: Ecto.UUID.generate(),
          project_id: Ecto.UUID.generate()
        })

      assert %{sync_interval_seconds: _} = errors_on(changeset)
    end
  end

  describe "DiscoverySource.update_changeset/2" do
    test "updates hostname and interval" do
      source = %DiscoverySource{hostname: "_old._tcp.api.internal", sync_interval_seconds: 60}

      changeset =
        DiscoverySource.update_changeset(source, %{
          hostname: "_new._tcp.api.internal",
          sync_interval_seconds: 120
        })

      assert changeset.valid?
      assert get_change(changeset, :hostname) == "_new._tcp.api.internal"
      assert get_change(changeset, :sync_interval_seconds) == 120
    end

    test "validates sync_interval_seconds on update" do
      source = %DiscoverySource{hostname: "_http._tcp.api.internal", sync_interval_seconds: 60}

      changeset = DiscoverySource.update_changeset(source, %{sync_interval_seconds: 3})

      assert %{sync_interval_seconds: _} = errors_on(changeset)
    end
  end

  describe "DiscoverySource.sync_changeset/2" do
    test "updates sync status" do
      source = %DiscoverySource{last_sync_status: "pending"}

      changeset =
        DiscoverySource.sync_changeset(source, %{
          last_sync_status: "synced",
          last_synced_at: DateTime.utc_now() |> DateTime.truncate(:second),
          last_sync_targets_count: 3
        })

      assert changeset.valid?
    end

    test "validates sync status inclusion" do
      source = %DiscoverySource{last_sync_status: "pending"}

      changeset = DiscoverySource.sync_changeset(source, %{last_sync_status: "unknown"})

      assert %{last_sync_status: _} = errors_on(changeset)
    end
  end

  # --- DiscoverySource schema (kubernetes) ---

  describe "DiscoverySource.changeset/2 kubernetes" do
    test "valid kubernetes changeset with config" do
      changeset =
        DiscoverySource.changeset(%DiscoverySource{}, %{
          source_type: "kubernetes",
          config: %{"namespace" => "default", "service_name" => "my-api"},
          upstream_group_id: Ecto.UUID.generate(),
          project_id: Ecto.UUID.generate()
        })

      assert changeset.valid?
    end

    test "kubernetes requires namespace in config" do
      changeset =
        DiscoverySource.changeset(%DiscoverySource{}, %{
          source_type: "kubernetes",
          config: %{"service_name" => "my-api"},
          upstream_group_id: Ecto.UUID.generate(),
          project_id: Ecto.UUID.generate()
        })

      assert %{config: _} = errors_on(changeset)
    end

    test "kubernetes requires service_name in config" do
      changeset =
        DiscoverySource.changeset(%DiscoverySource{}, %{
          source_type: "kubernetes",
          config: %{"namespace" => "default"},
          upstream_group_id: Ecto.UUID.generate(),
          project_id: Ecto.UUID.generate()
        })

      assert %{config: _} = errors_on(changeset)
    end

    test "kubernetes does not require hostname" do
      changeset =
        DiscoverySource.changeset(%DiscoverySource{}, %{
          source_type: "kubernetes",
          config: %{"namespace" => "default", "service_name" => "my-api"},
          upstream_group_id: Ecto.UUID.generate(),
          project_id: Ecto.UUID.generate()
        })

      assert changeset.valid?
      refute Map.has_key?(errors_on(changeset), :hostname)
    end

    test "kubernetes accepts optional config fields" do
      changeset =
        DiscoverySource.changeset(%DiscoverySource{}, %{
          source_type: "kubernetes",
          config: %{
            "namespace" => "production",
            "service_name" => "my-api",
            "api_url" => "https://k8s.example.com",
            "token" => "my-token",
            "port_name" => "http"
          },
          upstream_group_id: Ecto.UUID.generate(),
          project_id: Ecto.UUID.generate()
        })

      assert changeset.valid?
    end
  end

  # --- Context CRUD ---

  describe "create_discovery_source/1" do
    test "creates with valid attrs" do
      project = project_fixture()
      group = upstream_group_fixture(%{project: project})

      assert {:ok, %DiscoverySource{} = source} =
               Services.create_discovery_source(%{
                 hostname: "_http._tcp.api.internal",
                 upstream_group_id: group.id,
                 project_id: project.id
               })

      assert source.hostname == "_http._tcp.api.internal"
      assert source.source_type == "dns_srv"
      assert source.auto_sync == true
      assert source.sync_interval_seconds == 60
      assert source.last_sync_status == "pending"
    end

    test "enforces unique upstream_group_id" do
      project = project_fixture()
      group = upstream_group_fixture(%{project: project})

      {:ok, _} =
        Services.create_discovery_source(%{
          hostname: "_http._tcp.api.internal",
          upstream_group_id: group.id,
          project_id: project.id
        })

      assert {:error, changeset} =
               Services.create_discovery_source(%{
                 hostname: "_http._tcp.other.internal",
                 upstream_group_id: group.id,
                 project_id: project.id
               })

      assert %{upstream_group_id: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "get_discovery_source_for_group/1" do
    test "returns source for group" do
      project = project_fixture()
      group = upstream_group_fixture(%{project: project})

      {:ok, source} =
        Services.create_discovery_source(%{
          hostname: "_http._tcp.api.internal",
          upstream_group_id: group.id,
          project_id: project.id
        })

      assert found = Services.get_discovery_source_for_group(group.id)
      assert found.id == source.id
    end

    test "returns nil when no source exists" do
      group = upstream_group_fixture()
      assert Services.get_discovery_source_for_group(group.id) == nil
    end
  end

  describe "list_discovery_sources/1" do
    test "returns sources for project" do
      project = project_fixture()
      g1 = upstream_group_fixture(%{project: project, name: "G1"})
      g2 = upstream_group_fixture(%{project: project, name: "G2"})

      {:ok, _} =
        Services.create_discovery_source(%{
          hostname: "_http._tcp.g1.internal",
          upstream_group_id: g1.id,
          project_id: project.id
        })

      {:ok, _} =
        Services.create_discovery_source(%{
          hostname: "_http._tcp.g2.internal",
          upstream_group_id: g2.id,
          project_id: project.id
        })

      sources = Services.list_discovery_sources(project.id)
      assert length(sources) == 2
    end

    test "does not include sources from other projects" do
      p1 = project_fixture()
      p2 = project_fixture()
      g1 = upstream_group_fixture(%{project: p1})
      g2 = upstream_group_fixture(%{project: p2})

      {:ok, _} =
        Services.create_discovery_source(%{
          hostname: "_http._tcp.p1.internal",
          upstream_group_id: g1.id,
          project_id: p1.id
        })

      {:ok, _} =
        Services.create_discovery_source(%{
          hostname: "_http._tcp.p2.internal",
          upstream_group_id: g2.id,
          project_id: p2.id
        })

      assert length(Services.list_discovery_sources(p1.id)) == 1
    end
  end

  describe "update_discovery_source/2" do
    test "updates hostname and interval" do
      project = project_fixture()
      group = upstream_group_fixture(%{project: project})

      {:ok, source} =
        Services.create_discovery_source(%{
          hostname: "_http._tcp.old.internal",
          upstream_group_id: group.id,
          project_id: project.id
        })

      assert {:ok, updated} =
               Services.update_discovery_source(source, %{
                 hostname: "_http._tcp.new.internal",
                 sync_interval_seconds: 120
               })

      assert updated.hostname == "_http._tcp.new.internal"
      assert updated.sync_interval_seconds == 120
    end
  end

  describe "delete_discovery_source/1" do
    test "deletes the source" do
      project = project_fixture()
      group = upstream_group_fixture(%{project: project})

      {:ok, source} =
        Services.create_discovery_source(%{
          hostname: "_http._tcp.api.internal",
          upstream_group_id: group.id,
          project_id: project.id
        })

      assert {:ok, _} = Services.delete_discovery_source(source)
      assert Services.get_discovery_source(source.id) == nil
    end
  end

  describe "list_auto_sync_sources/0" do
    test "returns only auto_sync sources" do
      project = project_fixture()
      g1 = upstream_group_fixture(%{project: project, name: "Auto"})
      g2 = upstream_group_fixture(%{project: project, name: "Manual"})

      {:ok, _} =
        Services.create_discovery_source(%{
          hostname: "_http._tcp.auto.internal",
          auto_sync: true,
          upstream_group_id: g1.id,
          project_id: project.id
        })

      {:ok, _} =
        Services.create_discovery_source(%{
          hostname: "_http._tcp.manual.internal",
          auto_sync: false,
          upstream_group_id: g2.id,
          project_id: project.id
        })

      sources = Services.list_auto_sync_sources()
      assert length(sources) == 1
      assert hd(sources).hostname == "_http._tcp.auto.internal"
    end
  end

  # --- Sync orchestrator ---

  describe "sync_discovery_source/1" do
    test "adds targets from SRV records" do
      project = project_fixture()
      group = upstream_group_fixture(%{project: project})

      {:ok, source} =
        Services.create_discovery_source(%{
          hostname: "_http._tcp.api.internal",
          upstream_group_id: group.id,
          project_id: project.id
        })

      SentinelCp.Services.DnsResolver.Mock
      |> expect(:resolve_srv, fn "_http._tcp.api.internal" ->
        {:ok, [{10, 50, 8080, ~c"api1.svc"}, {10, 100, 8081, ~c"api2.svc"}]}
      end)

      assert {:ok, result} = Services.sync_discovery_source(source)
      assert result.added == 2
      assert result.removed == 0
      assert result.kept == 0

      # Verify targets were created
      updated_group = Services.get_upstream_group!(group.id)
      assert length(updated_group.targets) == 2
      hosts = Enum.map(updated_group.targets, & &1.host) |> Enum.sort()
      assert hosts == ["api1.svc", "api2.svc"]

      # Verify source status updated
      updated_source = Services.get_discovery_source!(source.id)
      assert updated_source.last_sync_status == "synced"
      assert updated_source.last_sync_targets_count == 2
      assert updated_source.last_synced_at != nil
      assert updated_source.last_sync_error == nil
    end

    test "removes targets not in SRV records" do
      project = project_fixture()
      group = upstream_group_fixture(%{project: project})

      # Pre-create a target that should be removed
      {:ok, _} =
        Services.add_upstream_target(%{
          upstream_group_id: group.id,
          host: "old.svc",
          port: 9090,
          weight: 100
        })

      {:ok, source} =
        Services.create_discovery_source(%{
          hostname: "_http._tcp.api.internal",
          upstream_group_id: group.id,
          project_id: project.id
        })

      SentinelCp.Services.DnsResolver.Mock
      |> expect(:resolve_srv, fn "_http._tcp.api.internal" ->
        {:ok, [{10, 50, 8080, ~c"new.svc"}]}
      end)

      assert {:ok, result} = Services.sync_discovery_source(source)
      assert result.added == 1
      assert result.removed == 1
      assert result.kept == 0

      updated_group = Services.get_upstream_group!(group.id)
      assert length(updated_group.targets) == 1
      assert hd(updated_group.targets).host == "new.svc"
    end

    test "keeps existing targets that match" do
      project = project_fixture()
      group = upstream_group_fixture(%{project: project})

      {:ok, _} =
        Services.add_upstream_target(%{
          upstream_group_id: group.id,
          host: "stable.svc",
          port: 8080,
          weight: 100
        })

      {:ok, source} =
        Services.create_discovery_source(%{
          hostname: "_http._tcp.api.internal",
          upstream_group_id: group.id,
          project_id: project.id
        })

      SentinelCp.Services.DnsResolver.Mock
      |> expect(:resolve_srv, fn "_http._tcp.api.internal" ->
        {:ok, [{10, 50, 8080, ~c"stable.svc"}]}
      end)

      assert {:ok, result} = Services.sync_discovery_source(source)
      assert result.added == 0
      assert result.removed == 0
      assert result.kept == 1
    end

    test "sets error status on DNS failure" do
      project = project_fixture()
      group = upstream_group_fixture(%{project: project})

      {:ok, source} =
        Services.create_discovery_source(%{
          hostname: "_http._tcp.bad.internal",
          upstream_group_id: group.id,
          project_id: project.id
        })

      SentinelCp.Services.DnsResolver.Mock
      |> expect(:resolve_srv, fn "_http._tcp.bad.internal" ->
        {:error, :nxdomain}
      end)

      assert {:error, _reason} = Services.sync_discovery_source(source)

      updated_source = Services.get_discovery_source!(source.id)
      assert updated_source.last_sync_status == "error"
      assert updated_source.last_sync_error != nil
    end

    test "handles empty SRV response (removes all targets)" do
      project = project_fixture()
      group = upstream_group_fixture(%{project: project})

      {:ok, _} =
        Services.add_upstream_target(%{
          upstream_group_id: group.id,
          host: "api.svc",
          port: 8080,
          weight: 100
        })

      {:ok, source} =
        Services.create_discovery_source(%{
          hostname: "_http._tcp.empty.internal",
          upstream_group_id: group.id,
          project_id: project.id
        })

      SentinelCp.Services.DnsResolver.Mock
      |> expect(:resolve_srv, fn "_http._tcp.empty.internal" ->
        {:ok, []}
      end)

      assert {:ok, result} = Services.sync_discovery_source(source)
      assert result.added == 0
      assert result.removed == 1
      assert result.kept == 0

      updated_group = Services.get_upstream_group!(group.id)
      assert updated_group.targets == []
    end
  end

  # --- K8s CRUD ---

  describe "create_discovery_source/1 kubernetes" do
    test "creates kubernetes source with config" do
      project = project_fixture()
      group = upstream_group_fixture(%{project: project})

      assert {:ok, %DiscoverySource{} = source} =
               Services.create_discovery_source(%{
                 source_type: "kubernetes",
                 config: %{"namespace" => "default", "service_name" => "my-api"},
                 upstream_group_id: group.id,
                 project_id: project.id
               })

      assert source.source_type == "kubernetes"
      assert source.config["namespace"] == "default"
      assert source.config["service_name"] == "my-api"
    end
  end

  # --- K8s Sync ---

  describe "sync_discovery_source/1 kubernetes" do
    test "syncs kubernetes source using K8s resolver" do
      project = project_fixture()
      group = upstream_group_fixture(%{project: project})

      {:ok, source} =
        Services.create_discovery_source(%{
          source_type: "kubernetes",
          config: %{"namespace" => "default", "service_name" => "my-api"},
          upstream_group_id: group.id,
          project_id: project.id
        })

      SentinelCp.Services.K8sResolver.Mock
      |> expect(:resolve_endpoints, fn config ->
        assert config["namespace"] == "default"
        assert config["service_name"] == "my-api"
        {:ok, [{0, 1, 8080, ~c"10.0.0.1"}, {0, 1, 8080, ~c"10.0.0.2"}]}
      end)

      assert {:ok, result} = Services.sync_discovery_source(source)
      assert result.added == 2
      assert result.removed == 0
      assert result.kept == 0

      updated_group = Services.get_upstream_group!(group.id)
      assert length(updated_group.targets) == 2
      ips = Enum.map(updated_group.targets, & &1.host) |> Enum.sort()
      assert ips == ["10.0.0.1", "10.0.0.2"]
    end

    test "sets error on K8s resolver failure" do
      project = project_fixture()
      group = upstream_group_fixture(%{project: project})

      {:ok, source} =
        Services.create_discovery_source(%{
          source_type: "kubernetes",
          config: %{"namespace" => "default", "service_name" => "bad-svc"},
          upstream_group_id: group.id,
          project_id: project.id
        })

      SentinelCp.Services.K8sResolver.Mock
      |> expect(:resolve_endpoints, fn _config ->
        {:error, "Kubernetes API returned 404: endpoints not found"}
      end)

      assert {:error, _reason} = Services.sync_discovery_source(source)

      updated_source = Services.get_discovery_source!(source.id)
      assert updated_source.last_sync_status == "error"
      assert updated_source.last_sync_error != nil
    end
  end

  # --- Worker ---

  describe "DiscoverySyncWorker" do
    alias SentinelCp.Services.DiscoverySyncWorker

    test "perform syncs due sources" do
      project = project_fixture()
      group = upstream_group_fixture(%{project: project})

      {:ok, _source} =
        Services.create_discovery_source(%{
          hostname: "_http._tcp.worker.internal",
          auto_sync: true,
          upstream_group_id: group.id,
          project_id: project.id
        })

      SentinelCp.Services.DnsResolver.Mock
      |> expect(:resolve_srv, fn "_http._tcp.worker.internal" ->
        {:ok, [{10, 50, 8080, ~c"worker.svc"}]}
      end)

      assert :ok = DiscoverySyncWorker.perform(%Oban.Job{})

      updated_group = Services.get_upstream_group!(group.id)
      assert length(updated_group.targets) == 1
    end

    test "skips sources with auto_sync disabled" do
      project = project_fixture()
      group = upstream_group_fixture(%{project: project})

      {:ok, _source} =
        Services.create_discovery_source(%{
          hostname: "_http._tcp.disabled.internal",
          auto_sync: false,
          upstream_group_id: group.id,
          project_id: project.id
        })

      # No mock expectation — should not be called
      assert :ok = DiscoverySyncWorker.perform(%Oban.Job{})

      updated_group = Services.get_upstream_group!(group.id)
      assert updated_group.targets == []
    end

    test "skips sources not yet due" do
      project = project_fixture()
      group = upstream_group_fixture(%{project: project})

      {:ok, source} =
        Services.create_discovery_source(%{
          hostname: "_http._tcp.notdue.internal",
          auto_sync: true,
          sync_interval_seconds: 300,
          upstream_group_id: group.id,
          project_id: project.id
        })

      # Mark as recently synced
      source
      |> DiscoverySource.sync_changeset(%{
        last_synced_at: DateTime.utc_now() |> DateTime.truncate(:second),
        last_sync_status: "synced"
      })
      |> SentinelCp.Repo.update!()

      # No mock expectation — should not be called since interval hasn't elapsed
      assert :ok = DiscoverySyncWorker.perform(%Oban.Job{})
    end
  end
end
