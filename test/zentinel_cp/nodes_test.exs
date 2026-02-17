defmodule ZentinelCp.NodesTest do
  use ZentinelCp.DataCase

  alias ZentinelCp.Nodes
  alias ZentinelCp.Nodes.Node

  import ZentinelCp.NodesFixtures
  import ZentinelCp.ProjectsFixtures

  describe "register_node/1" do
    test "creates a node with valid attributes" do
      project = project_fixture()

      assert {:ok, %Node{} = node} =
               Nodes.register_node(%{name: "proxy-1", project_id: project.id})

      assert node.name == "proxy-1"
      assert node.status == "online"
      assert is_binary(node.node_key)
      assert is_binary(node.node_key_hash)
      assert node.registered_at
      assert node.last_seen_at
    end

    test "returns error for duplicate name within project" do
      project = project_fixture()
      assert {:ok, _} = Nodes.register_node(%{name: "proxy-1", project_id: project.id})
      assert {:error, changeset} = Nodes.register_node(%{name: "proxy-1", project_id: project.id})
      assert %{project_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "allows same name in different projects" do
      p1 = project_fixture()
      p2 = project_fixture()
      assert {:ok, _} = Nodes.register_node(%{name: "proxy-1", project_id: p1.id})
      assert {:ok, _} = Nodes.register_node(%{name: "proxy-1", project_id: p2.id})
    end

    test "validates name format" do
      project = project_fixture()

      assert {:error, changeset} =
               Nodes.register_node(%{name: "-bad-name", project_id: project.id})

      assert %{name: [_]} = errors_on(changeset)
    end
  end

  describe "authenticate_node/1" do
    test "returns {:ok, node} for valid key" do
      {node, key} = node_with_key_fixture()
      assert {:ok, found} = Nodes.authenticate_node(key)
      assert found.id == node.id
    end

    test "returns {:error, :invalid_key} for invalid key" do
      assert {:error, :invalid_key} = Nodes.authenticate_node("bogus_key")
    end
  end

  describe "record_heartbeat/2" do
    test "updates node status and records heartbeat" do
      node = node_fixture()

      assert {:ok, updated} =
               Nodes.record_heartbeat(node, %{
                 version: "0.4.8",
                 ip: "10.0.0.1",
                 health: %{"cpu" => 50},
                 metrics: %{"requests" => 1000}
               })

      assert updated.status == "online"
      assert updated.version == "0.4.8"
      assert updated.ip == "10.0.0.1"

      heartbeats = Nodes.list_node_heartbeats(node.id)
      assert length(heartbeats) == 1
      assert hd(heartbeats).health == %{"cpu" => 50}
    end
  end

  describe "mark_stale_nodes_offline/1" do
    test "marks old nodes as offline" do
      node = node_fixture()

      # Manually set last_seen_at to past
      past = DateTime.utc_now() |> DateTime.add(-300, :second) |> DateTime.truncate(:second)

      node
      |> Ecto.Changeset.change(last_seen_at: past)
      |> Repo.update!()

      {count, _} = Nodes.mark_stale_nodes_offline(120)
      assert count == 1

      updated = Nodes.get_node!(node.id)
      assert updated.status == "offline"
    end

    test "does not mark recent nodes as offline" do
      _node = node_fixture()
      {count, _} = Nodes.mark_stale_nodes_offline(120)
      assert count == 0
    end
  end

  describe "list_nodes/2" do
    test "filters by status" do
      project = project_fixture()
      _online = node_fixture(%{project: project})

      nodes = Nodes.list_nodes(project.id, status: "online")
      assert length(nodes) == 1

      nodes = Nodes.list_nodes(project.id, status: "offline")
      assert nodes == []
    end

    test "filters by labels" do
      project = project_fixture()
      _node = node_fixture(%{project: project, labels: %{"env" => "prod", "region" => "us"}})

      nodes = Nodes.list_nodes(project.id, labels: %{"env" => "prod"})
      assert length(nodes) == 1

      nodes = Nodes.list_nodes(project.id, labels: %{"env" => "staging"})
      assert nodes == []
    end
  end

  describe "update_node_labels/2" do
    test "replaces labels" do
      node = node_fixture()
      assert {:ok, updated} = Nodes.update_node_labels(node, %{"env" => "prod"})
      assert updated.labels == %{"env" => "prod"}
    end
  end

  describe "get_node_stats/1" do
    test "returns counts by status" do
      project = project_fixture()
      _node = node_fixture(%{project: project})

      stats = Nodes.get_node_stats(project.id)
      assert stats["online"] == 1
    end
  end

  describe "count_nodes/1" do
    test "returns total count" do
      project = project_fixture()
      node_fixture(%{project: project})
      node_fixture(%{project: project})

      assert Nodes.count_nodes(project.id) == 2
    end
  end

  describe "delete_node/1" do
    test "deletes a node" do
      node = node_fixture()
      assert {:ok, _} = Nodes.delete_node(node)
      refute Nodes.get_node(node.id)
    end
  end
end
