defmodule ZentinelCp.Services.InternalCaContextTest do
  use ZentinelCp.DataCase

  import ZentinelCp.ProjectsFixtures

  alias ZentinelCp.Services

  describe "initialize_internal_ca/1" do
    test "creates CA with encrypted key and extracted metadata" do
      project = project_fixture()

      {:ok, ca} =
        Services.initialize_internal_ca(%{
          name: "Test CA",
          subject_cn: "Test Internal CA",
          key_algorithm: "EC-P384",
          project_id: project.id
        })

      assert ca.name == "Test CA"
      assert ca.subject_cn == "Test Internal CA"
      assert ca.key_algorithm == "EC-P384"
      assert ca.status == "active"
      assert ca.next_serial == 1

      # Key is encrypted
      assert is_binary(ca.ca_key_encrypted)
      assert byte_size(ca.ca_key_encrypted) > 0

      # Cert PEM is valid
      assert String.starts_with?(ca.ca_cert_pem, "-----BEGIN CERTIFICATE-----")

      # Metadata extracted
      assert ca.not_before != nil
      assert ca.not_after != nil
      assert ca.fingerprint_sha256 != nil
    end

    test "enforces one CA per project" do
      project = project_fixture()

      {:ok, _ca} =
        Services.initialize_internal_ca(%{
          name: "First CA",
          subject_cn: "CA1",
          project_id: project.id
        })

      {:error, changeset} =
        Services.initialize_internal_ca(%{
          name: "Second CA",
          subject_cn: "CA2",
          project_id: project.id
        })

      assert "already has an internal CA" in errors_on(changeset).project_id
    end

    test "works with RSA-2048" do
      project = project_fixture()

      {:ok, ca} =
        Services.initialize_internal_ca(%{
          name: "RSA CA",
          subject_cn: "RSA Test CA",
          key_algorithm: "RSA-2048",
          project_id: project.id
        })

      assert ca.key_algorithm == "RSA-2048"
    end
  end

  describe "get_internal_ca/1" do
    test "returns CA when it exists" do
      project = project_fixture()

      {:ok, ca} =
        Services.initialize_internal_ca(%{
          name: "My CA",
          subject_cn: "Test CA",
          project_id: project.id
        })

      found = Services.get_internal_ca(project.id)
      assert found.id == ca.id
    end

    test "returns nil when no CA exists" do
      project = project_fixture()
      assert Services.get_internal_ca(project.id) == nil
    end
  end

  describe "issue_certificate/2" do
    test "issues a certificate with serial increment" do
      project = project_fixture()

      {:ok, ca} =
        Services.initialize_internal_ca(%{
          name: "My CA",
          subject_cn: "Test CA",
          project_id: project.id
        })

      {:ok, cert1} =
        Services.issue_certificate(ca, %{
          name: "Client 1",
          subject_cn: "client1.example.com"
        })

      assert cert1.serial_number == 1
      assert cert1.subject_cn == "client1.example.com"
      assert cert1.status == "active"
      assert String.starts_with?(cert1.cert_pem, "-----BEGIN CERTIFICATE-----")
      assert is_binary(cert1.key_pem_encrypted)
      assert cert1.not_before != nil
      assert cert1.not_after != nil
      assert cert1.fingerprint_sha256 != nil

      # Second cert gets serial 2
      {:ok, cert2} =
        Services.issue_certificate(ca, %{
          name: "Client 2",
          subject_cn: "client2.example.com"
        })

      assert cert2.serial_number == 2

      # CA's next_serial was incremented
      updated_ca = Services.get_internal_ca(project.id)
      assert updated_ca.next_serial == 3
    end

    test "issues certificate with OU" do
      project = project_fixture()

      {:ok, ca} =
        Services.initialize_internal_ca(%{
          name: "My CA",
          subject_cn: "Test CA",
          project_id: project.id
        })

      {:ok, cert} =
        Services.issue_certificate(ca, %{
          name: "Client OU",
          subject_cn: "client.example.com",
          subject_ou: "Engineering"
        })

      assert cert.subject_ou == "Engineering"
    end
  end

  describe "revoke_issued_certificate/2" do
    test "revokes certificate and regenerates CRL" do
      project = project_fixture()

      {:ok, ca} =
        Services.initialize_internal_ca(%{
          name: "My CA",
          subject_cn: "Test CA",
          project_id: project.id
        })

      {:ok, cert} =
        Services.issue_certificate(ca, %{
          name: "Revoke Me",
          subject_cn: "revoke.example.com"
        })

      {:ok, revoked} = Services.revoke_issued_certificate(cert, "keyCompromise")

      assert revoked.status == "revoked"
      assert revoked.revoked_at != nil
      assert revoked.revoke_reason == "keyCompromise"

      # CRL was regenerated
      updated_ca = Services.get_internal_ca(project.id)
      assert updated_ca.crl_pem != nil
      assert String.starts_with?(updated_ca.crl_pem, "-----BEGIN X509 CRL-----")
      assert updated_ca.crl_updated_at != nil
    end
  end

  describe "destroy_internal_ca/1" do
    test "deletes CA and cascades to issued certs" do
      project = project_fixture()

      {:ok, ca} =
        Services.initialize_internal_ca(%{
          name: "My CA",
          subject_cn: "Test CA",
          project_id: project.id
        })

      {:ok, _cert} =
        Services.issue_certificate(ca, %{
          name: "Client",
          subject_cn: "client.example.com"
        })

      {:ok, _} = Services.destroy_internal_ca(ca)

      assert Services.get_internal_ca(project.id) == nil
      assert Services.list_issued_certificates(ca.id) == []
    end
  end

  describe "list_issued_certificates/1" do
    test "returns certs ordered by serial number" do
      project = project_fixture()

      {:ok, ca} =
        Services.initialize_internal_ca(%{
          name: "My CA",
          subject_cn: "Test CA",
          project_id: project.id
        })

      {:ok, _} = Services.issue_certificate(ca, %{name: "C1", subject_cn: "c1"})
      {:ok, _} = Services.issue_certificate(ca, %{name: "C2", subject_cn: "c2"})
      {:ok, _} = Services.issue_certificate(ca, %{name: "C3", subject_cn: "c3"})

      certs = Services.list_issued_certificates(ca.id)
      serials = Enum.map(certs, & &1.serial_number)
      assert serials == [1, 2, 3]
    end
  end
end
