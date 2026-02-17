defmodule ZentinelCp.Services.BundleIntegrationTest do
  use ZentinelCp.DataCase

  alias ZentinelCp.Bundles
  alias ZentinelCp.Services.BundleIntegration

  import ZentinelCp.ProjectsFixtures
  import ZentinelCp.ServicesFixtures

  describe "create_bundle_from_services/3" do
    test "creates a bundle with generated KDL" do
      project = project_fixture()
      _s = service_fixture(%{project: project, name: "API"})

      assert {:ok, bundle} =
               BundleIntegration.create_bundle_from_services(project.id, "1.0.0")

      assert bundle.version == "1.0.0"
      assert bundle.config_source =~ "routes {"
      assert bundle.config_source =~ "/api/*"
      assert bundle.project_id == project.id
    end

    test "returns error when no enabled services" do
      project = project_fixture()

      assert {:error, :no_services} =
               BundleIntegration.create_bundle_from_services(project.id, "1.0.0")
    end

    test "passes created_by_id option" do
      project = project_fixture()
      _s = service_fixture(%{project: project})

      user_id = Ecto.UUID.generate()

      assert {:ok, bundle} =
               BundleIntegration.create_bundle_from_services(project.id, "1.0.0",
                 created_by_id: user_id
               )

      assert bundle.created_by_id == user_id
    end

    test "returns changeset error for duplicate version" do
      project = project_fixture()
      _s = service_fixture(%{project: project})

      {:ok, _} = BundleIntegration.create_bundle_from_services(project.id, "1.0.0")

      assert {:error, %Ecto.Changeset{}} =
               BundleIntegration.create_bundle_from_services(project.id, "1.0.0")
    end
  end

  describe "preview_kdl/1" do
    test "returns KDL preview without creating a bundle" do
      project = project_fixture()
      _s = service_fixture(%{project: project})

      assert {:ok, kdl} = BundleIntegration.preview_kdl(project.id)
      assert is_binary(kdl)
      assert kdl =~ "routes {"

      # No bundle should be created
      assert Bundles.list_bundles(project.id) == []
    end

    test "returns error when no services" do
      project = project_fixture()
      assert {:error, :no_services} = BundleIntegration.preview_kdl(project.id)
    end
  end
end
