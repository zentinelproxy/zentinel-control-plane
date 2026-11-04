defmodule ZentinelCp.MaintenanceWorkersTest do
  use ZentinelCp.DataCase, async: false

  alias ZentinelCp.{Bundles, Nodes, Repo}
  alias ZentinelCp.Bundles.Bundle
  alias ZentinelCp.Nodes.{Node, NodeHeartbeat}
  alias ZentinelCp.Services.Acme.ChallengeStore

  import ZentinelCp.NodesFixtures
  import ZentinelCp.ProjectsFixtures
  import ZentinelCp.RolloutsFixtures

  describe "periodic workers" do
    test "a running job does not block its own next run" do
      for worker <- [ZentinelCp.Rollouts.TickWorker | ZentinelCp.Application.periodic_workers()] do
        unique = worker.__opts__()[:unique]

        if unique do
          assert unique[:states], "#{inspect(worker)} must set unique states"
          refute :executing in unique[:states], "#{inspect(worker)} blocks its own reschedule"
          refute :completed in unique[:states], "#{inspect(worker)} blocks its own reschedule"
        end
      end
    end
  end

  describe "StalenessWorker" do
    test "marks a silent node offline" do
      node = node_fixture(%{project: project_fixture()})
      old = DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.truncate(:second)

      Repo.update_all(from(n in Node, where: n.id == ^node.id),
        set: [status: "online", last_seen_at: old]
      )

      assert :ok = Nodes.StalenessWorker.perform(%Oban.Job{})
      assert Nodes.get_node(node.id).status == "offline"
    end
  end

  describe "HeartbeatPruneWorker" do
    test "removes old heartbeats only" do
      node = node_fixture(%{project: project_fixture()})
      {:ok, _} = Nodes.record_heartbeat(node, %{})
      {:ok, _} = Nodes.record_heartbeat(node, %{})

      old = DateTime.utc_now() |> DateTime.add(-30 * 86_400) |> DateTime.truncate(:second)
      newest = Repo.one(from(h in NodeHeartbeat, order_by: [desc: h.id], limit: 1, select: h.id))
      Repo.update_all(from(h in NodeHeartbeat, where: h.id == ^newest), set: [inserted_at: old])

      assert Nodes.prune_heartbeats(7) == 1
      assert Repo.aggregate(NodeHeartbeat, :count) == 1
    end
  end

  describe "Bundles.collect_garbage/1" do
    setup do
      project = project_fixture()
      bundles = for _ <- 1..3, do: compiled_bundle_fixture(%{project: project})

      for {bundle, age} <- Enum.with_index(bundles, 1) do
        at = DateTime.utc_now() |> DateTime.add(-age * 3600) |> DateTime.truncate(:second)
        Repo.update_all(from(b in Bundle, where: b.id == ^bundle.id), set: [inserted_at: at])
      end

      {:ok, project: project, bundles: bundles}
    end

    test "keeps the newest bundles and removes the stored artifact", %{
      bundles: [newest, _, oldest]
    } do
      key = "gc-test/#{oldest.id}"
      :ok = Bundles.Storage.upload(key, "artifact")
      Repo.update_all(from(b in Bundle, where: b.id == ^oldest.id), set: [storage_key: key])

      assert Bundles.collect_garbage(2) == 1
      assert Bundles.get_bundle(newest.id)
      refute Bundles.get_bundle(oldest.id)
      assert {:error, _} = Bundles.Storage.download(key)
    end

    test "keeps an old bundle assigned to a node", %{project: project, bundles: [_, _, oldest]} do
      node = node_fixture(%{project: project})

      Repo.update_all(from(n in Node, where: n.id == ^node.id),
        set: [active_bundle_id: oldest.id]
      )

      assert Bundles.collect_garbage(2) == 0
      assert Bundles.get_bundle(oldest.id)
    end

    test "keeps an old bundle used by a rollout", %{project: project, bundles: [_, _, oldest]} do
      {:ok, _} =
        ZentinelCp.Rollouts.create_rollout(%{
          project_id: project.id,
          bundle_id: oldest.id,
          target_selector: %{"type" => "all"}
        })

      assert Bundles.collect_garbage(2) == 0
      assert Bundles.get_bundle(oldest.id)
    end
  end

  describe "ChallengeStore" do
    test "stores, replaces, and removes a challenge" do
      assert :ok = ChallengeStore.put("t", "a")
      assert :ok = ChallengeStore.put("t", "b")
      assert {:ok, "b"} = ChallengeStore.get("t")
      assert :ok = ChallengeStore.delete("t")
      assert :error = ChallengeStore.get("t")
    end

    test "does not return an expired challenge" do
      ChallengeStore.put("old", "a")
      past = DateTime.utc_now() |> DateTime.add(-1) |> DateTime.truncate(:second)
      Repo.update_all(ZentinelCp.Services.Acme.Challenge, set: [expires_at: past])
      assert :error = ChallengeStore.get("old")
    end
  end
end
