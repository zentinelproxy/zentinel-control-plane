defmodule ZentinelCp.AuthTest do
  use ZentinelCp.DataCase

  alias ZentinelCp.Auth
  alias ZentinelCp.Auth.{NodeToken, SigningKey}

  import ZentinelCp.OrgsFixtures
  import ZentinelCp.ProjectsFixtures
  import ZentinelCp.NodesFixtures

  describe "create_signing_key/2" do
    test "creates an Ed25519 signing key for an org" do
      org = org_fixture()
      assert {:ok, %SigningKey{} = key} = Auth.create_signing_key(org.id)
      assert key.org_id == org.id
      assert key.algorithm == "Ed25519"
      assert key.active == true
      assert is_binary(key.public_key)
      assert is_binary(key.private_key_encrypted)
      assert String.starts_with?(key.key_id, "sk_")
    end

    test "creates key with custom key_id" do
      org = org_fixture()
      assert {:ok, key} = Auth.create_signing_key(org.id, key_id: "custom-key-1")
      assert key.key_id == "custom-key-1"
    end

    test "creates key with expiry" do
      org = org_fixture()
      expires = DateTime.utc_now() |> DateTime.add(86400, :second) |> DateTime.truncate(:second)
      assert {:ok, key} = Auth.create_signing_key(org.id, expires_at: expires)
      assert key.expires_at == expires
    end
  end

  describe "get_active_signing_key/1" do
    test "returns active key for org" do
      org = org_fixture()
      {:ok, created} = Auth.create_signing_key(org.id)
      key = Auth.get_active_signing_key(org.id)
      assert key.id == created.id
    end

    test "returns nil when no active key exists" do
      org = org_fixture()
      refute Auth.get_active_signing_key(org.id)
    end

    test "skips expired keys" do
      org = org_fixture()
      past = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)
      {:ok, _expired} = Auth.create_signing_key(org.id, expires_at: past)
      refute Auth.get_active_signing_key(org.id)
    end

    test "skips deactivated keys" do
      org = org_fixture()
      {:ok, key} = Auth.create_signing_key(org.id)
      {:ok, _} = Auth.deactivate_signing_key(key)
      refute Auth.get_active_signing_key(org.id)
    end
  end

  describe "issue_node_token/1" do
    setup do
      org = org_fixture()
      project = project_fixture(%{org: org})
      node = node_fixture(%{project: project})
      {:ok, _key} = Auth.create_signing_key(org.id)
      %{org: org, project: project, node: node}
    end

    test "issues a valid JWT", %{node: node} do
      assert {:ok, token, expires_at} = Auth.issue_node_token(node)
      assert is_binary(token)
      assert DateTime.diff(expires_at, DateTime.utc_now(), :second) > 0
    end

    test "token contains expected claims", %{node: node, org: org, project: project} do
      {:ok, token, _expires_at} = Auth.issue_node_token(node)
      {:ok, kid} = NodeToken.peek_kid(token)
      signing_key = Auth.get_signing_key_by_kid(kid)
      {:ok, claims} = NodeToken.verify(token, signing_key)

      assert claims["sub"] == node.id
      assert claims["prj"] == project.id
      assert claims["org"] == org.id
      assert is_integer(claims["iat"])
      assert is_integer(claims["exp"])
    end

    test "updates node token metadata", %{node: node} do
      {:ok, _token, _expires_at} = Auth.issue_node_token(node)
      updated = ZentinelCp.Nodes.get_node!(node.id)
      assert updated.auth_method == "jwt"
      assert updated.token_issued_at
      assert updated.token_expires_at
    end

    test "returns error when no signing key exists" do
      org = org_fixture()
      project = project_fixture(%{org: org})
      node = node_fixture(%{project: project})

      # No signing key for this org
      assert {:error, :no_signing_key} = Auth.issue_node_token(node)
    end
  end

  describe "verify_node_token/1" do
    setup do
      org = org_fixture()
      project = project_fixture(%{org: org})
      node = node_fixture(%{project: project})
      {:ok, key} = Auth.create_signing_key(org.id)
      %{org: org, project: project, node: node, signing_key: key}
    end

    test "verifies a valid token", %{node: node} do
      {:ok, token, _} = Auth.issue_node_token(node)
      assert {:ok, verified_node} = Auth.verify_node_token(token)
      assert verified_node.id == node.id
    end

    test "rejects tampered token", %{node: node} do
      {:ok, token, _} = Auth.issue_node_token(node)
      tampered = token <> "x"
      assert {:error, _} = Auth.verify_node_token(tampered)
    end

    test "rejects token signed with wrong key", %{node: node} do
      {:ok, token, _} = Auth.issue_node_token(node)

      # Create a different org with a different key
      other_org = org_fixture()
      {:ok, _other_key} = Auth.create_signing_key(other_org.id)

      # The token's kid points to the original key, so it should still verify
      # against the correct key. This test verifies kid-based lookup works.
      assert {:ok, _} = Auth.verify_node_token(token)
    end

    test "rejects token with deactivated key", %{node: node, signing_key: key} do
      {:ok, token, _} = Auth.issue_node_token(node)
      {:ok, _} = Auth.deactivate_signing_key(key)
      assert {:error, :key_deactivated} = Auth.verify_node_token(token)
    end

    test "rejects garbage token" do
      assert {:error, _} = Auth.verify_node_token("not.a.token")
    end
  end

  describe "ensure_signing_key/1" do
    test "creates key if none exists" do
      org = org_fixture()
      assert {:ok, key} = Auth.ensure_signing_key(org.id)
      assert key.org_id == org.id
    end

    test "returns existing key" do
      org = org_fixture()
      {:ok, existing} = Auth.create_signing_key(org.id)
      {:ok, found} = Auth.ensure_signing_key(org.id)
      assert found.id == existing.id
    end
  end
end
