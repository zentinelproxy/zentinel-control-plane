defmodule ZentinelCp.Audit.ChainVerifierTest do
  use ZentinelCp.DataCase, async: false

  alias ZentinelCp.Audit
  alias ZentinelCp.Audit.{AuditLog, ChainVerifier}
  alias ZentinelCp.Bundles.Signing

  import ZentinelCp.AccountsFixtures

  defp log_entries(user, count) do
    for i <- 1..count do
      {:ok, entry} = Audit.log_user_action(user, "action_#{i}", "bundle", Ecto.UUID.generate())
      entry
    end
  end

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

    test "detects an edited entry" do
      user = user_fixture()
      entries = log_entries(user, 3)
      edited = Enum.at(entries, 1)

      Repo.update_all(from(a in AuditLog, where: a.id == ^edited.id), set: [action: "forged"])

      assert {:error, :hash_mismatch, id} = ChainVerifier.verify_chain()
      assert id == edited.id
    end

    test "detects a deleted entry" do
      user = user_fixture()
      entries = log_entries(user, 3)

      Repo.delete_all(from(a in AuditLog, where: a.id == ^Enum.at(entries, 1).id))

      assert {:error, :chain_break, id} = ChainVerifier.verify_chain()
      assert id == Enum.at(entries, 2).id
    end

    test "verifies entries whose JSON was normalized by the database" do
      user = user_fixture()

      {:ok, _} =
        Audit.log(%{
          actor_type: "user",
          actor_id: user.id,
          action: "create",
          resource_type: "bundle",
          metadata: %{
            zebra: 1.0,
            nested: %{b: [1, %{a: true}], a: nil},
            at: ~U[2026-01-01 00:00:00Z]
          }
        })

      assert {:ok, 1} = ChainVerifier.verify_chain()
    end

    test "checks more than one batch" do
      user = user_fixture()
      log_entries(user, 3)
      assert {:ok, 2} = ChainVerifier.verify_chain(limit: 2)
      assert {:ok, 3} = ChainVerifier.verify_chain()
    end

    test "verifies a single project without reporting false breaks" do
      user = user_fixture()
      project_id = ZentinelCp.ProjectsFixtures.project_fixture().id

      {:ok, _} = Audit.log_user_action(user, "a", "bundle", Ecto.UUID.generate())

      {:ok, _} =
        Audit.log_user_action(user, "b", "bundle", Ecto.UUID.generate(), project_id: project_id)

      assert {:ok, 1} = ChainVerifier.verify_chain(project_id: project_id)
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

  describe "signed checkpoints" do
    setup do
      {public_key, private_key} = Signing.generate_keypair()
      original = Application.get_env(:zentinel_cp, :bundle_signing)

      Application.put_env(:zentinel_cp, :bundle_signing,
        enabled: true,
        key_id: "test",
        private_key: private_key,
        public_key: public_key
      )

      on_exit(fn -> Application.put_env(:zentinel_cp, :bundle_signing, original) end)
      log_entries(user_fixture(), 2)
      :ok
    end

    test "a valid signed checkpoint verifies" do
      {:ok, checkpoint} = ChainVerifier.create_checkpoint()
      assert checkpoint.signature != "unsigned"
      assert :ok = ChainVerifier.verify_checkpoint(checkpoint)
    end

    test "a forged signature is rejected" do
      {:ok, checkpoint} = ChainVerifier.create_checkpoint()
      forged = %{checkpoint | signature: Base.encode64(:crypto.strong_rand_bytes(64))}
      assert {:error, :invalid_signature} = ChainVerifier.verify_checkpoint(forged)
    end

    test "rewriting the checkpointed entry's hash is detected" do
      {:ok, checkpoint} = ChainVerifier.create_checkpoint()

      Repo.update_all(from(a in AuditLog, where: a.id == ^checkpoint.last_entry_id),
        set: [entry_hash: "rewritten"]
      )

      assert {:error, :entry_missing} = ChainVerifier.verify_checkpoint(checkpoint)
    end

    test "a later checkpoint only counts new entries" do
      {:ok, _} = ChainVerifier.create_checkpoint()
      assert {:ok, :no_new_entries} = ChainVerifier.create_checkpoint()
      log_entries(user_fixture(), 1)
      assert {:ok, %{entries_count: 1, sequence_number: 2}} = ChainVerifier.create_checkpoint()
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
