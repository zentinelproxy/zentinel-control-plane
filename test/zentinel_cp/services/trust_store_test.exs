defmodule ZentinelCp.Services.TrustStoreTest do
  use ZentinelCp.DataCase, async: true

  alias ZentinelCp.Services.TrustStore

  import ZentinelCp.CertificateFixtures

  describe "parse_pem_bundle/1" do
    test "parses a valid single-cert PEM" do
      assert {:ok, meta} = TrustStore.parse_pem_bundle(test_cert_pem())
      assert meta.cert_count == 1
      assert length(meta.subjects) == 1
      assert hd(meta.subjects) == "test.example.com"
      assert meta.earliest_expiry != nil
      assert meta.latest_expiry != nil
    end

    test "parses a multi-cert PEM bundle" do
      pem = test_cert_pem() <> "\n" <> test_cert_pem()
      assert {:ok, meta} = TrustStore.parse_pem_bundle(pem)
      assert meta.cert_count == 2
      assert length(meta.subjects) == 2
    end

    test "returns error for empty PEM" do
      assert {:error, _} = TrustStore.parse_pem_bundle("")
    end

    test "returns error for non-certificate PEM" do
      assert {:error, _} = TrustStore.parse_pem_bundle("not-a-pem")
    end

    test "returns error for PEM with only private key" do
      assert {:error, _} = TrustStore.parse_pem_bundle(test_key_pem())
    end
  end

  describe "create_changeset/2" do
    test "valid changeset with PEM" do
      changeset =
        TrustStore.create_changeset(%TrustStore{}, %{
          name: "Internal CA",
          certificates_pem: test_cert_pem(),
          project_id: Ecto.UUID.generate()
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :slug) == "internal-ca"
      assert Ecto.Changeset.get_change(changeset, :cert_count) == 1
      assert Ecto.Changeset.get_change(changeset, :subjects) == ["test.example.com"]
    end

    test "requires name" do
      changeset =
        TrustStore.create_changeset(%TrustStore{}, %{
          certificates_pem: test_cert_pem(),
          project_id: Ecto.UUID.generate()
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).name
    end

    test "requires certificates_pem" do
      changeset =
        TrustStore.create_changeset(%TrustStore{}, %{
          name: "Test",
          project_id: Ecto.UUID.generate()
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).certificates_pem
    end

    test "rejects invalid PEM" do
      changeset =
        TrustStore.create_changeset(%TrustStore{}, %{
          name: "Bad PEM",
          certificates_pem: "not-a-valid-pem",
          project_id: Ecto.UUID.generate()
        })

      refute changeset.valid?
      assert errors_on(changeset).certificates_pem != nil
    end

    test "generates slug from name" do
      changeset =
        TrustStore.create_changeset(%TrustStore{}, %{
          name: "My Internal CA Bundle",
          certificates_pem: test_cert_pem(),
          project_id: Ecto.UUID.generate()
        })

      assert Ecto.Changeset.get_change(changeset, :slug) == "my-internal-ca-bundle"
    end
  end

  describe "update_changeset/2" do
    test "updates name" do
      ts = %TrustStore{name: "Old", certificates_pem: test_cert_pem()}

      changeset = TrustStore.update_changeset(ts, %{name: "New Name"})
      assert changeset.valid?
    end

    test "re-validates PEM when changed" do
      ts = %TrustStore{name: "Test", certificates_pem: test_cert_pem()}

      changeset = TrustStore.update_changeset(ts, %{certificates_pem: "invalid"})
      refute changeset.valid?
      assert errors_on(changeset).certificates_pem != nil
    end

    test "re-extracts metadata when PEM changes" do
      ts = %TrustStore{name: "Test", certificates_pem: test_cert_pem()}
      new_pem = test_cert_pem() <> "\n" <> test_cert_pem()

      changeset = TrustStore.update_changeset(ts, %{certificates_pem: new_pem})
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :cert_count) == 2
    end
  end
end
