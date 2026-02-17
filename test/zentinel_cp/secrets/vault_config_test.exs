defmodule ZentinelCp.Secrets.VaultConfigTest do
  use ZentinelCp.DataCase

  alias ZentinelCp.Secrets
  alias ZentinelCp.Secrets.VaultConfig

  defp create_project(_) do
    {:ok, org} = ZentinelCp.Orgs.create_org(%{name: "Vault Org", slug: "vault-org"})

    {:ok, project} =
      ZentinelCp.Projects.create_project(%{
        name: "Vault Project",
        slug: "vault-proj",
        org_id: org.id
      })

    %{project: project}
  end

  describe "create_changeset/2" do
    setup [:create_project]

    test "valid changeset", %{project: project} do
      cs =
        VaultConfig.create_changeset(%VaultConfig{}, %{
          project_id: project.id,
          vault_addr: "http://vault:8200",
          auth_method: "token",
          auth_config_plaintext: %{"token" => "my-vault-token"}
        })

      assert cs.valid?
      assert get_change(cs, :auth_config) != nil
    end

    test "requires vault_addr", %{project: project} do
      cs =
        VaultConfig.create_changeset(%VaultConfig{}, %{
          project_id: project.id,
          auth_method: "token"
        })

      refute cs.valid?
      assert errors_on(cs)[:vault_addr]
    end

    test "validates auth_method", %{project: project} do
      cs =
        VaultConfig.create_changeset(%VaultConfig{}, %{
          project_id: project.id,
          vault_addr: "http://vault:8200",
          auth_method: "invalid"
        })

      refute cs.valid?
      assert errors_on(cs)[:auth_method]
    end
  end

  describe "encryption" do
    setup [:create_project]

    test "encrypts and decrypts auth_config", %{project: project} do
      auth = %{"token" => "hvs.my-secret-token"}

      cs =
        VaultConfig.create_changeset(%VaultConfig{}, %{
          project_id: project.id,
          vault_addr: "http://vault:8200",
          auth_config_plaintext: auth
        })

      encrypted = Ecto.Changeset.get_change(cs, :auth_config)
      assert is_binary(encrypted)
      assert {:ok, ^auth} = VaultConfig.decrypt_auth_config(encrypted)
    end

    test "decrypt_auth_config handles nil" do
      assert {:ok, %{}} = VaultConfig.decrypt_auth_config(nil)
    end
  end

  describe "CRUD via Secrets context" do
    setup [:create_project]

    test "create, get, update, delete vault config", %{project: project} do
      {:ok, config} =
        Secrets.create_vault_config(%{
          project_id: project.id,
          vault_addr: "http://vault:8200",
          auth_method: "token",
          auth_config_plaintext: %{"token" => "hvs.test"},
          mount_path: "secret"
        })

      assert config.vault_addr == "http://vault:8200"
      assert config.enabled == false

      # Get
      fetched = Secrets.get_vault_config(project.id)
      assert fetched.id == config.id

      # Update
      {:ok, updated} =
        Secrets.update_vault_config(config, %{enabled: true, vault_addr: "http://vault:8201"})

      assert updated.enabled == true
      assert updated.vault_addr == "http://vault:8201"

      # Delete
      {:ok, _} = Secrets.delete_vault_config(config)
      assert Secrets.get_vault_config(project.id) == nil
    end
  end
end
