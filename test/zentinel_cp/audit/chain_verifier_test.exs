defmodule ZentinelCp.Audit.ChainVerifierTest do
  use ZentinelCp.DataCase, async: false

  alias ZentinelCp.Audit
  alias ZentinelCp.Audit.ChainVerifier

  import ZentinelCp.AccountsFixtures

  describe "compute_entry_hash/2" do
    test "produces deterministic hashes" do
      attrs = %{
        actor_type: "user",
        action: "create",
        resource_type: "bundle",
        resource_id: "abc-123"
      }

      hash1 = ChainVerifier.compute_entry_hash(attrs, nil)
      hash2 = ChainVerifier.compute_entry_hash(attrs, nil)
      assert hash1 == hash2
    end

    test "different previous_hash produces different entry_hash" do
      attrs = %{
        actor_type: "user",
        action: "create",
        resource_type: "bundle",
        resource_id: "abc-123"
      }

      hash1 = ChainVerifier.compute_entry_hash(attrs, nil)
      hash2 = ChainVerifier.compute_entry_hash(attrs, "prev-hash")
      assert hash1 != hash2
    end

    test "different attributes produce different hashes" do
      attrs1 = %{
        actor_type: "user",
        action: "create",
        resource_type: "bundle"
      }

      attrs2 = %{
        actor_type: "user",
        action: "delete",
        resource_type: "bundle"
      }

      hash1 = ChainVerifier.compute_entry_hash(attrs1, nil)
      hash2 = ChainVerifier.compute_entry_hash(attrs2, nil)
      assert hash1 != hash2
    end
  end

  describe "audit log chain integration" do
    test "log entries include chain hashes" do
      user = user_fixture()

      {:ok, entry1} =
        Audit.log_user_action(user, "create", "bundle", Ecto.UUID.generate())

      assert entry1.entry_hash != nil
      assert entry1.previous_hash == nil

      {:ok, entry2} =
        Audit.log_user_action(user, "update", "bundle", Ecto.UUID.generate())

      assert entry2.entry_hash != nil
      assert entry2.previous_hash == entry1.entry_hash
    end

    test "chain verifies correctly for sequential entries" do
      user = user_fixture()

      for i <- 1..5 do
        Audit.log_user_action(user, "action_#{i}", "bundle", Ecto.UUID.generate())
      end

      assert {:ok, 5} = ChainVerifier.verify_chain()
    end
  end

  describe "verify_chain/1" do
    test "returns ok with count for valid chain" do
      user = user_fixture()

      for _ <- 1..3 do
        Audit.log_user_action(user, "create", "bundle", Ecto.UUID.generate())
      end

      assert {:ok, 3} = ChainVerifier.verify_chain()
    end

    test "returns ok with 0 for empty chain" do
      assert {:ok, 0} = ChainVerifier.verify_chain()
    end
  end

  describe "checkpoints" do
    test "creates a checkpoint from audit entries" do
      user = user_fixture()

      for _ <- 1..5 do
        Audit.log_user_action(user, "create", "bundle", Ecto.UUID.generate())
      end

      assert {:ok, checkpoint} = ChainVerifier.create_checkpoint()
      assert checkpoint.sequence_number == 1
      assert checkpoint.entries_count == 5
      assert checkpoint.digest != nil
      assert checkpoint.last_entry_hash != nil
    end

    test "returns :no_new_entries when no entries exist" do
      assert {:ok, :no_new_entries} = ChainVerifier.create_checkpoint()
    end

    test "lists checkpoints" do
      user = user_fixture()

      for _ <- 1..3 do
        Audit.log_user_action(user, "create", "bundle", Ecto.UUID.generate())
      end

      {:ok, _} = ChainVerifier.create_checkpoint()
      checkpoints = ChainVerifier.list_checkpoints()
      assert length(checkpoints) == 1
    end
  end

  describe "verification_status/0" do
    test "returns complete status" do
      user = user_fixture()

      for _ <- 1..3 do
        Audit.log_user_action(user, "create", "bundle", Ecto.UUID.generate())
      end

      status = ChainVerifier.verification_status()
      assert {:ok, 3} = status.chain
      assert status.verified_at != nil
    end
  end
end
