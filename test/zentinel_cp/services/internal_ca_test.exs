defmodule ZentinelCp.Services.InternalCaTest do
  use ZentinelCp.DataCase

  alias ZentinelCp.Services.InternalCa

  describe "create_changeset/2" do
    test "valid attrs produce valid changeset" do
      attrs = %{
        name: "My CA",
        subject_cn: "Test CA",
        key_algorithm: "EC-P384",
        ca_cert_pem: "-----BEGIN CERTIFICATE-----\ntest\n-----END CERTIFICATE-----",
        ca_key_encrypted: <<1, 2, 3>>,
        project_id: Ecto.UUID.generate()
      }

      changeset = InternalCa.create_changeset(%InternalCa{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :slug) == "my-ca"
    end

    test "requires name, subject_cn, ca_cert_pem, ca_key_encrypted, project_id" do
      changeset = InternalCa.create_changeset(%InternalCa{}, %{})
      refute changeset.valid?

      errors = errors_on(changeset)
      assert "can't be blank" in errors.name
      assert "can't be blank" in errors.subject_cn
      assert "can't be blank" in errors.ca_cert_pem
      assert "can't be blank" in errors.ca_key_encrypted
      assert "can't be blank" in errors.project_id
    end

    test "validates key_algorithm inclusion" do
      attrs = %{
        name: "CA",
        subject_cn: "CN",
        ca_cert_pem: "pem",
        ca_key_encrypted: <<1>>,
        key_algorithm: "INVALID",
        project_id: Ecto.UUID.generate()
      }

      changeset = InternalCa.create_changeset(%InternalCa{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).key_algorithm
    end

    test "generates slug from name" do
      changeset =
        InternalCa.create_changeset(%InternalCa{}, %{
          name: "My Test CA",
          subject_cn: "CN",
          ca_cert_pem: "pem",
          ca_key_encrypted: <<1>>,
          project_id: Ecto.UUID.generate()
        })

      assert Ecto.Changeset.get_change(changeset, :slug) == "my-test-ca"
    end
  end

  describe "update_changeset/2" do
    test "updates name and status" do
      ca = %InternalCa{name: "Old", status: "active"}
      changeset = InternalCa.update_changeset(ca, %{name: "New", status: "rotated"})
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :name) == "New"
      assert Ecto.Changeset.get_change(changeset, :status) == "rotated"
    end

    test "validates status inclusion" do
      ca = %InternalCa{name: "Test", status: "active"}
      changeset = InternalCa.update_changeset(ca, %{status: "invalid"})
      refute changeset.valid?
    end
  end

  describe "crl_changeset/2" do
    test "updates CRL fields" do
      ca = %InternalCa{}
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      changeset = InternalCa.crl_changeset(ca, %{crl_pem: "crl-data", crl_updated_at: now})
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :crl_pem) == "crl-data"
    end
  end

  describe "serial_changeset/2" do
    test "updates next_serial" do
      ca = %InternalCa{next_serial: 1}
      changeset = InternalCa.serial_changeset(ca, %{next_serial: 2})
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :next_serial) == 2
    end
  end
end
