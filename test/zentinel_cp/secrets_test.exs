defmodule ZentinelCp.SecretsTest do
  use ZentinelCp.DataCase, async: true

  alias ZentinelCp.Secrets
  alias ZentinelCp.Secrets.SecretCrypto

  import ZentinelCp.ProjectsFixtures

  describe "SecretCrypto" do
    test "encrypt/decrypt round-trip" do
      plaintext = "my-super-secret-value"
      encrypted = SecretCrypto.encrypt(plaintext)
      assert is_binary(encrypted)
      assert encrypted != plaintext

      assert {:ok, ^plaintext} = SecretCrypto.decrypt(encrypted)
    end

    test "different encryptions produce different ciphertexts" do
      plaintext = "same-value"
      encrypted1 = SecretCrypto.encrypt(plaintext)
      encrypted2 = SecretCrypto.encrypt(plaintext)
      assert encrypted1 != encrypted2

      assert {:ok, ^plaintext} = SecretCrypto.decrypt(encrypted1)
      assert {:ok, ^plaintext} = SecretCrypto.decrypt(encrypted2)
    end

    test "decrypt fails with corrupted data" do
      encrypted = SecretCrypto.encrypt("test")
      corrupted = <<0>> <> encrypted
      assert {:error, :decryption_failed} = SecretCrypto.decrypt(corrupted)
    end
  end

  describe "Secret schema" do
    test "valid name formats are accepted" do
      project = project_fixture()

      valid_names = ["DATABASE_PASSWORD", "api_token", "MySecret", "_private", "a1b2c3"]

      for name <- valid_names do
        assert {:ok, _} =
                 Secrets.create_secret(%{
                   name: name,
                   value: "test-value",
                   project_id: project.id
                 })
      end
    end

    test "invalid name formats are rejected" do
      project = project_fixture()

      invalid_names = ["123start", "has space", "has-dash", "has.dot", ""]

      for name <- invalid_names do
        result =
          Secrets.create_secret(%{
            name: name,
            value: "test-value",
            project_id: project.id
          })

        assert {:error, %Ecto.Changeset{}} = result
      end
    end
  end

  describe "CRUD operations" do
    test "create_secret/1 encrypts the value" do
      project = project_fixture()

      assert {:ok, secret} =
               Secrets.create_secret(%{
                 name: "DB_PASSWORD",
                 value: "super-secret",
                 description: "Database password",
                 project_id: project.id
               })

      assert secret.name == "DB_PASSWORD"
      assert secret.encrypted_value != nil
      assert secret.encrypted_value != "super-secret"
      # Virtual field retains value on struct, but not in DB
      reloaded = Secrets.get_secret!(secret.id)
      assert reloaded.value == nil

      # Verify we can decrypt
      assert {:ok, "super-secret"} = SecretCrypto.decrypt(secret.encrypted_value)
    end

    test "create_secret/1 with environment scoping" do
      project = project_fixture()

      assert {:ok, secret} =
               Secrets.create_secret(%{
                 name: "API_KEY",
                 value: "prod-key",
                 environment: "production",
                 project_id: project.id
               })

      assert secret.environment == "production"
    end

    test "create_secret/1 enforces unique name per project+environment" do
      project = project_fixture()

      assert {:ok, _} =
               Secrets.create_secret(%{
                 name: "UNIQUE_SECRET",
                 value: "value1",
                 environment: "production",
                 project_id: project.id
               })

      assert {:error, changeset} =
               Secrets.create_secret(%{
                 name: "UNIQUE_SECRET",
                 value: "value2",
                 environment: "production",
                 project_id: project.id
               })

      assert errors_on(changeset)[:project_id] || errors_on(changeset)[:name]
    end

    test "allows same name in different environments" do
      project = project_fixture()

      assert {:ok, _} =
               Secrets.create_secret(%{
                 name: "ENV_SECRET",
                 value: "prod-val",
                 environment: "production",
                 project_id: project.id
               })

      assert {:ok, _} =
               Secrets.create_secret(%{
                 name: "ENV_SECRET",
                 value: "dev-val",
                 environment: "development",
                 project_id: project.id
               })
    end

    test "list_secrets/1 returns project secrets" do
      project = project_fixture()

      {:ok, _s1} = Secrets.create_secret(%{name: "SECRET_A", value: "a", project_id: project.id})
      {:ok, _s2} = Secrets.create_secret(%{name: "SECRET_B", value: "b", project_id: project.id})

      secrets = Secrets.list_secrets(project.id)
      assert length(secrets) == 2
      assert Enum.map(secrets, & &1.name) == ["SECRET_A", "SECRET_B"]
    end

    test "list_secrets/2 filters by environment" do
      project = project_fixture()

      {:ok, _} = Secrets.create_secret(%{name: "GLOBAL", value: "g", project_id: project.id})

      {:ok, _} =
        Secrets.create_secret(%{
          name: "PROD_ONLY",
          value: "p",
          environment: "production",
          project_id: project.id
        })

      {:ok, _} =
        Secrets.create_secret(%{
          name: "DEV_ONLY",
          value: "d",
          environment: "development",
          project_id: project.id
        })

      prod_secrets = Secrets.list_secrets(project.id, "production")
      names = Enum.map(prod_secrets, & &1.name)
      assert "GLOBAL" in names
      assert "PROD_ONLY" in names
      refute "DEV_ONLY" in names
    end

    test "update_secret/2 re-encrypts value" do
      project = project_fixture()

      {:ok, secret} =
        Secrets.create_secret(%{name: "ROTATE_ME", value: "old", project_id: project.id})

      old_encrypted = secret.encrypted_value

      {:ok, updated} = Secrets.update_secret(secret, %{value: "new-value"})
      assert updated.encrypted_value != old_encrypted
      assert {:ok, "new-value"} = SecretCrypto.decrypt(updated.encrypted_value)
      assert updated.last_rotated_at != nil
    end

    test "delete_secret/1 removes the secret" do
      project = project_fixture()

      {:ok, secret} =
        Secrets.create_secret(%{name: "DELETE_ME", value: "val", project_id: project.id})

      assert {:ok, _} = Secrets.delete_secret(secret)
      assert Secrets.get_secret(secret.id) == nil
    end

    test "rotate_secret/2 updates value and last_rotated_at" do
      project = project_fixture()

      {:ok, secret} =
        Secrets.create_secret(%{name: "ROTATE_SECRET", value: "old", project_id: project.id})

      assert secret.last_rotated_at == nil

      {:ok, rotated} = Secrets.rotate_secret(secret, "new-rotated-value")
      assert {:ok, "new-rotated-value"} = SecretCrypto.decrypt(rotated.encrypted_value)
      assert rotated.last_rotated_at != nil
    end

    test "decrypt_value/1 returns decrypted plaintext" do
      project = project_fixture()

      {:ok, secret} =
        Secrets.create_secret(%{name: "DECRYPT_ME", value: "hello-world", project_id: project.id})

      assert {:ok, "hello-world"} = Secrets.decrypt_value(secret)
    end
  end

  describe "reference resolution" do
    test "resolve_references/3 replaces simple references" do
      project = project_fixture()

      {:ok, _} =
        Secrets.create_secret(%{
          name: "DB_HOST",
          value: "postgres.internal",
          project_id: project.id
        })

      {:ok, _} = Secrets.create_secret(%{name: "DB_PORT", value: "5432", project_id: project.id})

      config = %{
        "host" => "${secrets.DB_HOST}",
        "port" => "${secrets.DB_PORT}",
        "static" => "no-change"
      }

      assert {:ok, resolved} = Secrets.resolve_references(config, project.id)
      assert resolved["host"] == "postgres.internal"
      assert resolved["port"] == "5432"
      assert resolved["static"] == "no-change"
    end

    test "resolve_references/3 handles nested maps" do
      project = project_fixture()
      {:ok, _} = Secrets.create_secret(%{name: "TOKEN", value: "abc123", project_id: project.id})

      config = %{
        "auth" => %{
          "token" => "${secrets.TOKEN}",
          "type" => "bearer"
        }
      }

      assert {:ok, resolved} = Secrets.resolve_references(config, project.id)
      assert resolved["auth"]["token"] == "abc123"
      assert resolved["auth"]["type"] == "bearer"
    end

    test "resolve_references/3 handles multiple refs in one string" do
      project = project_fixture()
      {:ok, _} = Secrets.create_secret(%{name: "USER", value: "admin", project_id: project.id})
      {:ok, _} = Secrets.create_secret(%{name: "PASS", value: "secret", project_id: project.id})

      config = %{"url" => "postgres://${secrets.USER}:${secrets.PASS}@localhost/db"}

      assert {:ok, resolved} = Secrets.resolve_references(config, project.id)
      assert resolved["url"] == "postgres://admin:secret@localhost/db"
    end

    test "resolve_references/3 returns error for missing secret" do
      project = project_fixture()

      config = %{"key" => "${secrets.NONEXISTENT}"}

      assert {:error, {:missing_secret, "NONEXISTENT"}} =
               Secrets.resolve_references(config, project.id)
    end

    test "resolve_references/3 respects environment scoping" do
      project = project_fixture()

      {:ok, _} =
        Secrets.create_secret(%{
          name: "API_URL",
          value: "https://prod.api.com",
          environment: "production",
          project_id: project.id
        })

      config = %{"url" => "${secrets.API_URL}"}

      assert {:ok, resolved} = Secrets.resolve_references(config, project.id, "production")
      assert resolved["url"] == "https://prod.api.com"
    end

    test "find_references/1 extracts secret names" do
      config = %{
        "host" => "${secrets.DB_HOST}",
        "nested" => %{
          "token" => "${secrets.API_TOKEN}"
        },
        "static" => "no-ref"
      }

      refs = Secrets.find_references(config)
      assert "DB_HOST" in refs
      assert "API_TOKEN" in refs
      assert length(refs) == 2
    end
  end
end
