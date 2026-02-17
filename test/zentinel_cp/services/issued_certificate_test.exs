defmodule ZentinelCp.Services.IssuedCertificateTest do
  use ZentinelCp.DataCase

  alias ZentinelCp.Services.IssuedCertificate

  describe "create_changeset/2" do
    test "valid attrs produce valid changeset" do
      attrs = %{
        name: "Client Cert",
        serial_number: 1,
        subject_cn: "client.example.com",
        cert_pem: "-----BEGIN CERTIFICATE-----\ntest\n-----END CERTIFICATE-----",
        key_pem_encrypted: <<1, 2, 3>>,
        internal_ca_id: Ecto.UUID.generate()
      }

      changeset = IssuedCertificate.create_changeset(%IssuedCertificate{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :slug) == "client-cert"
    end

    test "requires mandatory fields" do
      changeset = IssuedCertificate.create_changeset(%IssuedCertificate{}, %{})
      refute changeset.valid?

      errors = errors_on(changeset)
      assert "can't be blank" in errors.name
      assert "can't be blank" in errors.serial_number
      assert "can't be blank" in errors.subject_cn
      assert "can't be blank" in errors.cert_pem
      assert "can't be blank" in errors.key_pem_encrypted
      assert "can't be blank" in errors.internal_ca_id
    end

    test "generates slug from name" do
      changeset =
        IssuedCertificate.create_changeset(%IssuedCertificate{}, %{
          name: "Service A Client",
          serial_number: 1,
          subject_cn: "service-a",
          cert_pem: "pem",
          key_pem_encrypted: <<1>>,
          internal_ca_id: Ecto.UUID.generate()
        })

      assert Ecto.Changeset.get_change(changeset, :slug) == "service-a-client"
    end
  end

  describe "revoke_changeset/2" do
    test "sets status to revoked" do
      cert = %IssuedCertificate{status: "active"}
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      changeset =
        IssuedCertificate.revoke_changeset(cert, %{
          revoked_at: now,
          revoke_reason: "keyCompromise"
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :status) == "revoked"
      assert Ecto.Changeset.get_change(changeset, :revoke_reason) == "keyCompromise"
    end

    test "requires revoked_at" do
      cert = %IssuedCertificate{status: "active"}
      changeset = IssuedCertificate.revoke_changeset(cert, %{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).revoked_at
    end
  end
end
