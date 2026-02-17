defmodule ZentinelCp.Services.CertificateTest do
  use ZentinelCp.DataCase, async: true

  alias ZentinelCp.Services
  alias ZentinelCp.Services.Certificate

  import ZentinelCp.ProjectsFixtures
  import ZentinelCp.CertificateFixtures

  describe "create_certificate/1" do
    test "creates a certificate with valid PEM data" do
      project = project_fixture()

      assert {:ok, cert} =
               Services.create_certificate(%{
                 name: "My TLS Cert",
                 domain: "test.example.com",
                 cert_pem: test_cert_pem(),
                 key_pem: test_key_pem(),
                 project_id: project.id
               })

      assert cert.name == "My TLS Cert"
      assert cert.slug == "my-tls-cert"
      assert cert.domain == "test.example.com"
      assert cert.status == "active"
      assert cert.key_pem_encrypted != nil
      assert is_binary(cert.key_pem_encrypted)
      assert cert.fingerprint_sha256 != nil
      assert cert.not_before != nil
      assert cert.not_after != nil
    end

    test "extracts issuer from cert PEM" do
      project = project_fixture()

      {:ok, cert} =
        Services.create_certificate(%{
          name: "Test Cert",
          domain: "test.example.com",
          cert_pem: test_cert_pem(),
          key_pem: test_key_pem(),
          project_id: project.id
        })

      assert cert.issuer != nil
    end

    test "encrypts the private key" do
      project = project_fixture()
      key_pem = test_key_pem()

      {:ok, cert} =
        Services.create_certificate(%{
          name: "Encrypted Key",
          domain: "test.example.com",
          cert_pem: test_cert_pem(),
          key_pem: key_pem,
          project_id: project.id
        })

      # The stored encrypted key should NOT be the plaintext
      assert cert.key_pem_encrypted != key_pem

      # Decryption should recover the original
      {:ok, decrypted} = ZentinelCp.Services.CertificateCrypto.decrypt(cert.key_pem_encrypted)
      assert decrypted == key_pem
    end

    test "requires name" do
      project = project_fixture()

      assert {:error, changeset} =
               Services.create_certificate(%{
                 domain: "test.example.com",
                 cert_pem: test_cert_pem(),
                 key_pem: test_key_pem(),
                 project_id: project.id
               })

      assert "can't be blank" in errors_on(changeset).name
    end

    test "requires cert_pem" do
      project = project_fixture()

      assert {:error, changeset} =
               Services.create_certificate(%{
                 name: "No Cert PEM",
                 domain: "test.example.com",
                 key_pem: test_key_pem(),
                 project_id: project.id
               })

      assert "can't be blank" in errors_on(changeset).cert_pem
    end

    test "requires key_pem" do
      project = project_fixture()

      assert {:error, changeset} =
               Services.create_certificate(%{
                 name: "No Key",
                 domain: "test.example.com",
                 cert_pem: test_cert_pem(),
                 project_id: project.id
               })

      assert "private key is required" in errors_on(changeset).key_pem_encrypted
    end

    test "rejects invalid cert PEM" do
      project = project_fixture()

      assert {:error, changeset} =
               Services.create_certificate(%{
                 name: "Bad Cert",
                 domain: "test.example.com",
                 cert_pem: "not-a-valid-pem",
                 key_pem: test_key_pem(),
                 project_id: project.id
               })

      assert "invalid certificate PEM" in errors_on(changeset).cert_pem
    end

    test "enforces unique slug per project" do
      project = project_fixture()

      {:ok, _} =
        Services.create_certificate(%{
          name: "Dupe",
          domain: "test.example.com",
          cert_pem: test_cert_pem(),
          key_pem: test_key_pem(),
          project_id: project.id
        })

      assert {:error, changeset} =
               Services.create_certificate(%{
                 name: "Dupe",
                 domain: "test2.example.com",
                 cert_pem: test_cert_pem(),
                 key_pem: test_key_pem(),
                 project_id: project.id
               })

      assert errors_on(changeset).slug != nil
    end
  end

  describe "update_certificate/2" do
    test "updates name and auto_renew" do
      cert = certificate_fixture()

      assert {:ok, updated} =
               Services.update_certificate(cert, %{name: "Updated Name", auto_renew: true})

      assert updated.name == "Updated Name"
      assert updated.auto_renew == true
    end

    test "updates status" do
      cert = certificate_fixture()

      assert {:ok, updated} = Services.update_certificate(cert, %{status: "revoked"})
      assert updated.status == "revoked"
    end

    test "rejects invalid status" do
      cert = certificate_fixture()

      assert {:error, changeset} =
               Services.update_certificate(cert, %{status: "invalid"})

      assert errors_on(changeset).status != nil
    end
  end

  describe "list_certificates/1" do
    test "lists certificates for a project ordered by domain" do
      project = project_fixture()
      certificate_fixture(project: project, name: "Cert B", domain: "b.example.com")
      certificate_fixture(project: project, name: "Cert A", domain: "a.example.com")

      certs = Services.list_certificates(project.id)
      assert length(certs) == 2
      assert Enum.at(certs, 0).domain == "a.example.com"
      assert Enum.at(certs, 1).domain == "b.example.com"
    end

    test "returns empty list for project with no certificates" do
      project = project_fixture()
      assert Services.list_certificates(project.id) == []
    end
  end

  describe "get_certificate/1" do
    test "returns certificate by ID" do
      cert = certificate_fixture()
      assert found = Services.get_certificate(cert.id)
      assert found.id == cert.id
    end

    test "returns nil for nonexistent ID" do
      assert Services.get_certificate(Ecto.UUID.generate()) == nil
    end
  end

  describe "delete_certificate/1" do
    test "deletes a certificate" do
      cert = certificate_fixture()
      assert {:ok, _} = Services.delete_certificate(cert)
      assert Services.get_certificate(cert.id) == nil
    end
  end

  describe "expires_soon?/1" do
    test "returns true for certificate expiring within 30 days" do
      cert = %Certificate{not_after: DateTime.add(DateTime.utc_now(), 15 * 86_400, :second)}
      assert Certificate.expires_soon?(cert)
    end

    test "returns false for certificate not expiring soon" do
      cert = %Certificate{not_after: DateTime.add(DateTime.utc_now(), 365 * 86_400, :second)}
      refute Certificate.expires_soon?(cert)
    end

    test "returns false when not_after is nil" do
      cert = %Certificate{not_after: nil}
      refute Certificate.expires_soon?(cert)
    end
  end

  describe "expired?/1" do
    test "returns true for expired certificate" do
      cert = %Certificate{not_after: DateTime.add(DateTime.utc_now(), -86_400, :second)}
      assert Certificate.expired?(cert)
    end

    test "returns false for valid certificate" do
      cert = %Certificate{not_after: DateTime.add(DateTime.utc_now(), 86_400, :second)}
      refute Certificate.expired?(cert)
    end

    test "returns false when not_after is nil" do
      cert = %Certificate{not_after: nil}
      refute Certificate.expired?(cert)
    end
  end

  describe "parse_cert_pem/1" do
    test "parses a valid PEM and extracts metadata" do
      assert {:ok, meta} = Certificate.parse_cert_pem(test_cert_pem())
      assert meta.domain == "test.example.com"
      assert meta.not_before != nil
      assert meta.not_after != nil
      assert meta.fingerprint_sha256 != nil
      assert String.contains?(meta.fingerprint_sha256, ":")
    end

    test "returns error for invalid PEM" do
      assert {:error, _} = Certificate.parse_cert_pem("not-a-pem")
    end
  end
end
