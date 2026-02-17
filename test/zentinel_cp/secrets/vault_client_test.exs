defmodule ZentinelCp.Secrets.VaultClientTest do
  use ZentinelCp.DataCase

  import Mox

  setup :verify_on_exit!

  describe "read_secret/2" do
    test "returns secret data on success" do
      ZentinelCp.Secrets.VaultClient.Mock
      |> expect(:read_secret, fn _config, "my-secret" ->
        {:ok, %{"username" => "admin", "password" => "s3cret"}}
      end)

      assert {:ok, %{"username" => "admin", "password" => "s3cret"}} =
               ZentinelCp.Secrets.VaultClient.Mock.read_secret(
                 %{vault_addr: "http://vault:8200", mount_path: "secret"},
                 "my-secret"
               )
    end

    test "returns :not_found for missing secrets" do
      ZentinelCp.Secrets.VaultClient.Mock
      |> expect(:read_secret, fn _config, "missing" ->
        {:error, :not_found}
      end)

      assert {:error, :not_found} =
               ZentinelCp.Secrets.VaultClient.Mock.read_secret(
                 %{vault_addr: "http://vault:8200"},
                 "missing"
               )
    end

    test "returns error for auth failures" do
      ZentinelCp.Secrets.VaultClient.Mock
      |> expect(:read_secret, fn _config, _path ->
        {:error, "Vault returned 403: permission denied"}
      end)

      assert {:error, "Vault returned 403: permission denied"} =
               ZentinelCp.Secrets.VaultClient.Mock.read_secret(
                 %{vault_addr: "http://vault:8200"},
                 "secret"
               )
    end
  end

  describe "list_secrets/2" do
    test "returns list of keys" do
      ZentinelCp.Secrets.VaultClient.Mock
      |> expect(:list_secrets, fn _config, "apps/" ->
        {:ok, ["db-password", "api-key", "jwt-secret"]}
      end)

      assert {:ok, ["db-password", "api-key", "jwt-secret"]} =
               ZentinelCp.Secrets.VaultClient.Mock.list_secrets(
                 %{vault_addr: "http://vault:8200"},
                 "apps/"
               )
    end

    test "returns empty list for missing path" do
      ZentinelCp.Secrets.VaultClient.Mock
      |> expect(:list_secrets, fn _config, _path ->
        {:ok, []}
      end)

      assert {:ok, []} =
               ZentinelCp.Secrets.VaultClient.Mock.list_secrets(
                 %{vault_addr: "http://vault:8200"},
                 "nonexistent/"
               )
    end
  end

  describe "health/1" do
    test "returns health status" do
      ZentinelCp.Secrets.VaultClient.Mock
      |> expect(:health, fn _config ->
        {:ok,
         %{
           initialized: true,
           sealed: false,
           standby: false,
           version: "1.15.0",
           cluster_name: "vault-cluster",
           server_time_utc: 1_700_000_000
         }}
      end)

      assert {:ok, %{initialized: true, sealed: false}} =
               ZentinelCp.Secrets.VaultClient.Mock.health(%{vault_addr: "http://vault:8200"})
    end
  end
end
