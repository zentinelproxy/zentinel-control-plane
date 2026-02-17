defmodule ZentinelCp.Services.TrustStoreContextTest do
  use ZentinelCp.DataCase, async: true

  alias ZentinelCp.Services

  import ZentinelCp.ProjectsFixtures
  import ZentinelCp.CertificateFixtures
  import ZentinelCp.TrustStoreFixtures

  describe "create_trust_store/1" do
    test "creates a trust store with valid PEM" do
      project = project_fixture()

      assert {:ok, ts} =
               Services.create_trust_store(%{
                 name: "Internal CA",
                 certificates_pem: test_cert_pem(),
                 project_id: project.id
               })

      assert ts.name == "Internal CA"
      assert ts.slug == "internal-ca"
      assert ts.cert_count == 1
      assert ts.subjects == ["test.example.com"]
      assert ts.earliest_expiry != nil
      assert ts.latest_expiry != nil
    end

    test "rejects invalid PEM" do
      project = project_fixture()

      assert {:error, changeset} =
               Services.create_trust_store(%{
                 name: "Bad",
                 certificates_pem: "not-a-pem",
                 project_id: project.id
               })

      assert errors_on(changeset).certificates_pem != nil
    end

    test "enforces unique slug per project" do
      project = project_fixture()

      {:ok, _} =
        Services.create_trust_store(%{
          name: "Dupe",
          certificates_pem: test_cert_pem(),
          project_id: project.id
        })

      assert {:error, changeset} =
               Services.create_trust_store(%{
                 name: "Dupe",
                 certificates_pem: test_cert_pem(),
                 project_id: project.id
               })

      assert errors_on(changeset).slug != nil
    end
  end

  describe "list_trust_stores/1" do
    test "lists trust stores ordered by name" do
      project = project_fixture()
      trust_store_fixture(project: project, name: "Beta CA")
      trust_store_fixture(project: project, name: "Alpha CA")

      stores = Services.list_trust_stores(project.id)
      assert length(stores) == 2
      assert Enum.at(stores, 0).name == "Alpha CA"
      assert Enum.at(stores, 1).name == "Beta CA"
    end

    test "returns empty list when none exist" do
      project = project_fixture()
      assert Services.list_trust_stores(project.id) == []
    end
  end

  describe "get_trust_store/1" do
    test "returns trust store by ID" do
      ts = trust_store_fixture()
      assert found = Services.get_trust_store(ts.id)
      assert found.id == ts.id
    end

    test "returns nil for nonexistent ID" do
      assert Services.get_trust_store(Ecto.UUID.generate()) == nil
    end
  end

  describe "get_trust_store!/1" do
    test "returns trust store by ID" do
      ts = trust_store_fixture()
      assert found = Services.get_trust_store!(ts.id)
      assert found.id == ts.id
    end

    test "raises for nonexistent ID" do
      assert_raise Ecto.NoResultsError, fn ->
        Services.get_trust_store!(Ecto.UUID.generate())
      end
    end
  end

  describe "update_trust_store/2" do
    test "updates name and description" do
      ts = trust_store_fixture()

      assert {:ok, updated} =
               Services.update_trust_store(ts, %{name: "Updated Name", description: "New desc"})

      assert updated.name == "Updated Name"
      assert updated.description == "New desc"
    end

    test "re-extracts metadata when PEM changes" do
      ts = trust_store_fixture()
      multi_pem = test_cert_pem() <> "\n" <> test_cert_pem()

      assert {:ok, updated} =
               Services.update_trust_store(ts, %{certificates_pem: multi_pem})

      assert updated.cert_count == 2
    end
  end

  describe "delete_trust_store/1" do
    test "deletes a trust store" do
      ts = trust_store_fixture()
      assert {:ok, _} = Services.delete_trust_store(ts)
      assert Services.get_trust_store(ts.id) == nil
    end
  end
end
