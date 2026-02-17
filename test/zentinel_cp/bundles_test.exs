defmodule ZentinelCp.BundlesTest do
  use ZentinelCp.DataCase

  alias ZentinelCp.Bundles
  alias ZentinelCp.Bundles.Bundle

  import ZentinelCp.ProjectsFixtures
  import ZentinelCp.NodesFixtures

  @valid_kdl """
  system {
    workers 4
  }
  listeners {
    listener "http" address="0.0.0.0:8080"
  }
  """

  defp bundle_fixture(attrs \\ %{}) do
    project = attrs[:project] || project_fixture()

    {:ok, bundle} =
      Bundles.create_bundle(%{
        project_id: project.id,
        version: attrs[:version] || "1.0.#{System.unique_integer([:positive])}",
        config_source: attrs[:config_source] || @valid_kdl
      })

    bundle
  end

  describe "create_bundle/1" do
    test "creates a bundle with valid attributes" do
      project = project_fixture()

      assert {:ok, %Bundle{} = bundle} =
               Bundles.create_bundle(%{
                 project_id: project.id,
                 version: "1.0.0",
                 config_source: @valid_kdl
               })

      assert bundle.version == "1.0.0"
      assert bundle.status == "pending"
      assert bundle.config_source == @valid_kdl
    end

    test "returns error for missing required fields" do
      assert {:error, changeset} = Bundles.create_bundle(%{})
      errors = errors_on(changeset)
      assert errors[:version]
      assert errors[:config_source]
      assert errors[:project_id]
    end

    test "returns error for duplicate version within project" do
      project = project_fixture()

      {:ok, _} =
        Bundles.create_bundle(%{
          project_id: project.id,
          version: "1.0.0",
          config_source: @valid_kdl
        })

      assert {:error, changeset} =
               Bundles.create_bundle(%{
                 project_id: project.id,
                 version: "1.0.0",
                 config_source: @valid_kdl
               })

      assert %{project_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "allows same version in different projects" do
      p1 = project_fixture()
      p2 = project_fixture()

      assert {:ok, _} =
               Bundles.create_bundle(%{
                 project_id: p1.id,
                 version: "1.0.0",
                 config_source: @valid_kdl
               })

      assert {:ok, _} =
               Bundles.create_bundle(%{
                 project_id: p2.id,
                 version: "1.0.0",
                 config_source: @valid_kdl
               })
    end
  end

  describe "list_bundles/2" do
    test "returns bundles for a project" do
      project = project_fixture()
      _b1 = bundle_fixture(%{project: project, version: "1.0.0"})
      _b2 = bundle_fixture(%{project: project, version: "2.0.0"})

      bundles = Bundles.list_bundles(project.id)
      assert length(bundles) == 2
    end

    test "filters by status" do
      project = project_fixture()
      _bundle = bundle_fixture(%{project: project})

      # Oban inline mode runs the compile worker synchronously,
      # which changes status from "pending" to "failed" (no zentinel binary in test)
      bundles = Bundles.list_bundles(project.id, status: "failed")
      assert length(bundles) == 1

      bundles = Bundles.list_bundles(project.id, status: "compiled")
      assert bundles == []
    end
  end

  describe "get_bundle/1" do
    test "returns bundle by id" do
      bundle = bundle_fixture()
      found = Bundles.get_bundle(bundle.id)
      assert found.id == bundle.id
    end

    test "returns nil for unknown id" do
      refute Bundles.get_bundle(Ecto.UUID.generate())
    end
  end

  describe "get_latest_bundle/1" do
    test "returns latest compiled bundle" do
      project = project_fixture()
      bundle = bundle_fixture(%{project: project})

      # Not compiled yet, should return nil
      refute Bundles.get_latest_bundle(project.id)

      # Mark as compiled
      {:ok, _} = Bundles.update_status(bundle, "compiled")
      latest = Bundles.get_latest_bundle(project.id)
      assert latest.id == bundle.id
    end
  end

  describe "update_compilation/2" do
    test "updates compilation results" do
      bundle = bundle_fixture()

      assert {:ok, updated} =
               Bundles.update_compilation(bundle, %{
                 status: "compiled",
                 checksum: "abc123",
                 size_bytes: 1024,
                 storage_key: "bundles/test/123.tar.zst",
                 manifest: %{"files" => []}
               })

      assert updated.status == "compiled"
      assert updated.checksum == "abc123"
      assert updated.size_bytes == 1024
    end
  end

  describe "assign_bundle_to_nodes/2" do
    test "assigns bundle to nodes" do
      project = project_fixture()
      bundle = bundle_fixture(%{project: project})
      node1 = node_fixture(%{project: project})
      node2 = node_fixture(%{project: project})

      assert {:ok, 2} = Bundles.assign_bundle_to_nodes(bundle, [node1.id, node2.id])

      updated = ZentinelCp.Nodes.get_node!(node1.id)
      assert updated.staged_bundle_id == bundle.id
    end

    test "only assigns to nodes in same project" do
      project = project_fixture()
      other_project = project_fixture()
      bundle = bundle_fixture(%{project: project})
      node = node_fixture(%{project: other_project})

      assert {:ok, 0} = Bundles.assign_bundle_to_nodes(bundle, [node.id])
    end
  end

  describe "delete_bundle/1" do
    test "deletes pending bundle" do
      bundle = bundle_fixture()
      assert {:ok, _} = Bundles.delete_bundle(bundle)
      refute Bundles.get_bundle(bundle.id)
    end

    test "deletes failed bundle" do
      bundle = bundle_fixture()
      {:ok, failed} = Bundles.update_status(bundle, "failed")
      assert {:ok, _} = Bundles.delete_bundle(failed)
    end

    test "refuses to delete compiled bundle" do
      bundle = bundle_fixture()
      {:ok, compiled} = Bundles.update_status(bundle, "compiled")
      assert {:error, :cannot_delete_active_bundle} = Bundles.delete_bundle(compiled)
    end
  end

  describe "version history" do
    test "create_bundle auto-links parent_bundle_id to latest compiled bundle" do
      project = project_fixture()

      # First bundle — no parent
      {:ok, b1} =
        Bundles.create_bundle(%{
          project_id: project.id,
          version: "1.0.0",
          config_source: @valid_kdl
        })

      assert is_nil(b1.parent_bundle_id)

      # Mark b1 as compiled
      {:ok, _} = Bundles.update_status(b1, "compiled")

      # Second bundle — should auto-link to b1
      {:ok, b2} =
        Bundles.create_bundle(%{
          project_id: project.id,
          version: "2.0.0",
          config_source: @valid_kdl
        })

      assert b2.parent_bundle_id == b1.id
    end

    test "create_bundle sets nil parent for first bundle" do
      project = project_fixture()

      {:ok, bundle} =
        Bundles.create_bundle(%{
          project_id: project.id,
          version: "1.0.0",
          config_source: @valid_kdl
        })

      assert is_nil(bundle.parent_bundle_id)
    end

    test "list_bundle_history returns bundles with diff summaries" do
      project = project_fixture()

      {:ok, b1} =
        Bundles.create_bundle(%{
          project_id: project.id,
          version: "1.0.0",
          config_source: "system { workers 2 }"
        })

      {:ok, _} = Bundles.update_status(b1, "compiled")

      {:ok, b2} =
        Bundles.create_bundle(%{
          project_id: project.id,
          version: "2.0.0",
          config_source: "system { workers 4 }"
        })

      {:ok, _} = Bundles.update_status(b2, "compiled")

      {bundles, diff_summaries} = Bundles.list_bundle_history(project.id)

      assert length(bundles) == 2
      versions = Enum.map(bundles, & &1.version)
      assert "1.0.0" in versions
      assert "2.0.0" in versions

      # The newer bundle (first in list) should have a diff summary
      newer = hd(bundles)
      assert Map.has_key?(diff_summaries, newer.id)

      summary = diff_summaries[newer.id]
      assert is_map(summary.stats)
      assert is_map(summary.semantic)
    end

    test "get_bundle_with_parent preloads parent" do
      project = project_fixture()

      {:ok, b1} =
        Bundles.create_bundle(%{
          project_id: project.id,
          version: "1.0.0",
          config_source: @valid_kdl
        })

      {:ok, _} = Bundles.update_status(b1, "compiled")

      {:ok, b2} =
        Bundles.create_bundle(%{
          project_id: project.id,
          version: "2.0.0",
          config_source: @valid_kdl
        })

      loaded = Bundles.get_bundle_with_parent(b2.id)
      assert loaded.parent_bundle.id == b1.id
    end

    test "get_previous_bundle returns chronologically previous compiled bundle" do
      project = project_fixture()

      {:ok, b1} =
        Bundles.create_bundle(%{
          project_id: project.id,
          version: "1.0.0",
          config_source: @valid_kdl
        })

      # Set b1 to compiled with an earlier timestamp to ensure ordering
      past = DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)

      b1
      |> Ecto.Changeset.change(%{status: "compiled", inserted_at: past})
      |> ZentinelCp.Repo.update!()

      {:ok, b2} =
        Bundles.create_bundle(%{
          project_id: project.id,
          version: "2.0.0",
          config_source: @valid_kdl
        })

      {:ok, b2} = Bundles.update_status(b2, "compiled")

      previous = Bundles.get_previous_bundle(b2, project.id)
      assert previous.id == b1.id

      # First bundle should have no previous
      b1 = ZentinelCp.Repo.get!(ZentinelCp.Bundles.Bundle, b1.id)
      assert is_nil(Bundles.get_previous_bundle(b1, project.id))
    end
  end

  describe "revoke_bundle/1" do
    test "revokes a compiled bundle" do
      bundle = bundle_fixture()
      {:ok, compiled} = Bundles.update_status(bundle, "compiled")

      assert {:ok, revoked} = Bundles.revoke_bundle(compiled)
      assert revoked.status == "revoked"
    end

    test "returns error for non-compiled bundles" do
      bundle = bundle_fixture()
      # bundle is pending/failed after compile worker runs inline
      reloaded = Bundles.get_bundle!(bundle.id)
      assert {:error, :invalid_state} = Bundles.revoke_bundle(reloaded)
    end

    test "clears staged_bundle_id on nodes with the revoked bundle" do
      project = project_fixture()
      bundle = bundle_fixture(%{project: project})
      {:ok, compiled} = Bundles.update_status(bundle, "compiled")

      node = node_fixture(%{project: project})
      {:ok, 1} = Bundles.assign_bundle_to_nodes(compiled, [node.id])

      # Verify staged
      assert ZentinelCp.Nodes.get_node!(node.id).staged_bundle_id == compiled.id

      # Revoke
      assert {:ok, _revoked} = Bundles.revoke_bundle(compiled)

      # Staged bundle cleared
      assert is_nil(ZentinelCp.Nodes.get_node!(node.id).staged_bundle_id)
    end

    test "revoked bundle excluded from get_latest_bundle" do
      project = project_fixture()
      bundle = bundle_fixture(%{project: project})
      {:ok, compiled} = Bundles.update_status(bundle, "compiled")

      assert Bundles.get_latest_bundle(project.id).id == compiled.id

      {:ok, _revoked} = Bundles.revoke_bundle(compiled)

      refute Bundles.get_latest_bundle(project.id)
    end
  end
end
