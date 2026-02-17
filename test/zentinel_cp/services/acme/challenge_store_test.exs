defmodule ZentinelCp.Services.Acme.ChallengeStoreTest do
  use ExUnit.Case, async: false

  alias ZentinelCp.Services.Acme.ChallengeStore

  # The ChallengeStore is started in the application supervisor,
  # so we just need to clean up between tests
  setup do
    :ets.delete_all_objects(:acme_challenge_tokens)
    :ok
  end

  describe "put/2 and get/1" do
    test "stores and retrieves a challenge token" do
      assert :ok = ChallengeStore.put("token-123", "key-auth-abc")
      assert {:ok, "key-auth-abc"} = ChallengeStore.get("token-123")
    end

    test "returns :error for unknown token" do
      assert :error = ChallengeStore.get("nonexistent-token")
    end

    test "overwrites existing token" do
      ChallengeStore.put("token-123", "first-value")
      ChallengeStore.put("token-123", "second-value")
      assert {:ok, "second-value"} = ChallengeStore.get("token-123")
    end
  end

  describe "delete/1" do
    test "removes a stored token" do
      ChallengeStore.put("token-to-delete", "some-value")
      assert {:ok, "some-value"} = ChallengeStore.get("token-to-delete")

      assert :ok = ChallengeStore.delete("token-to-delete")
      assert :error = ChallengeStore.get("token-to-delete")
    end

    test "returns :ok for non-existent token" do
      assert :ok = ChallengeStore.delete("never-existed")
    end
  end

  describe "TTL expiration" do
    test "expired tokens return :error" do
      # Insert with an already-expired timestamp
      :ets.insert(:acme_challenge_tokens, {"expired-token", "value", 0})
      assert :error = ChallengeStore.get("expired-token")
    end
  end
end
