defmodule ZentinelCp.Services.OpenApiSpecTest do
  use ZentinelCp.DataCase, async: true

  alias ZentinelCp.Services
  alias ZentinelCp.Services.OpenApiParser
  alias ZentinelCp.OpenApiFixtures
  alias ZentinelCp.ProjectsFixtures

  describe "list_openapi_specs/1" do
    test "returns specs for a project" do
      project = ProjectsFixtures.project_fixture()
      _spec1 = OpenApiFixtures.openapi_spec_fixture(%{project: project, name: "first"})
      _spec2 = OpenApiFixtures.openapi_spec_fixture(%{project: project, name: "second"})

      specs = Services.list_openapi_specs(project.id)
      assert length(specs) == 2
    end

    test "does not return specs from other projects" do
      project1 = ProjectsFixtures.project_fixture()
      project2 = ProjectsFixtures.project_fixture()
      OpenApiFixtures.openapi_spec_fixture(%{project: project1})

      assert Services.list_openapi_specs(project2.id) == []
    end
  end

  describe "get_openapi_spec/1" do
    test "returns spec by id" do
      spec = OpenApiFixtures.openapi_spec_fixture()
      found = Services.get_openapi_spec(spec.id)
      assert found.id == spec.id
    end

    test "returns nil for nonexistent id" do
      assert Services.get_openapi_spec(Ecto.UUID.generate()) == nil
    end
  end

  describe "create_openapi_spec/1" do
    test "creates spec with valid attributes" do
      project = ProjectsFixtures.project_fixture()

      attrs = %{
        name: "test-spec",
        file_name: "test.json",
        openapi_version: "3.0.3",
        spec_version: "1.0.0",
        spec_data: OpenApiFixtures.petstore_spec_map(),
        checksum: "abc123",
        paths_count: 2,
        project_id: project.id
      }

      assert {:ok, spec} = Services.create_openapi_spec(attrs)
      assert spec.name == "test-spec"
      assert spec.file_name == "test.json"
      assert spec.status == "active"
      assert spec.paths_count == 2
    end

    test "fails without required fields" do
      assert {:error, changeset} = Services.create_openapi_spec(%{})
      assert errors_on(changeset) |> Map.has_key?(:name)
      assert errors_on(changeset) |> Map.has_key?(:file_name)
      assert errors_on(changeset) |> Map.has_key?(:spec_data)
      assert errors_on(changeset) |> Map.has_key?(:checksum)
      assert errors_on(changeset) |> Map.has_key?(:project_id)
    end

    test "validates status inclusion" do
      project = ProjectsFixtures.project_fixture()

      attrs = %{
        name: "test",
        file_name: "test.json",
        spec_data: %{},
        checksum: "abc",
        status: "invalid",
        project_id: project.id
      }

      assert {:error, changeset} = Services.create_openapi_spec(attrs)
      assert errors_on(changeset) |> Map.has_key?(:status)
    end
  end

  describe "delete_openapi_spec/1" do
    test "deletes spec" do
      spec = OpenApiFixtures.openapi_spec_fixture()
      assert {:ok, _} = Services.delete_openapi_spec(spec)
      assert Services.get_openapi_spec(spec.id) == nil
    end
  end

  describe "get_openapi_spec_by_checksum/2" do
    test "finds spec by checksum" do
      spec = OpenApiFixtures.openapi_spec_fixture(%{checksum: "unique-checksum-123"})
      found = Services.get_openapi_spec_by_checksum(spec.project_id, "unique-checksum-123")
      assert found.id == spec.id
    end

    test "returns nil for non-matching checksum" do
      spec = OpenApiFixtures.openapi_spec_fixture()
      assert Services.get_openapi_spec_by_checksum(spec.project_id, "nonexistent") == nil
    end

    test "scoped to project" do
      _spec = OpenApiFixtures.openapi_spec_fixture(%{checksum: "check123"})
      other_project = ProjectsFixtures.project_fixture()
      assert Services.get_openapi_spec_by_checksum(other_project.id, "check123") == nil
    end
  end

  describe "import_from_openapi/4" do
    test "creates services from selected items" do
      project = ProjectsFixtures.project_fixture()
      spec = OpenApiFixtures.openapi_spec_fixture(%{project: project})

      {:ok, parsed} = OpenApiParser.parse(OpenApiFixtures.petstore_spec_map())
      selected = OpenApiParser.extract_services(parsed)

      assert {:ok, result} = Services.import_from_openapi(project.id, spec.id, selected)
      assert result.services_count == 2
      assert result.auth_policies_count == 0

      services = Services.list_services(project.id)
      assert length(services) == 2
      assert Enum.all?(services, &(&1.openapi_spec_id == spec.id))
      assert Enum.all?(services, &is_binary(&1.openapi_path))
    end

    test "creates auth policies when import_auth_policies is true" do
      project = ProjectsFixtures.project_fixture()
      spec = OpenApiFixtures.openapi_spec_fixture(%{project: project})

      {:ok, parsed} = OpenApiParser.parse(OpenApiFixtures.petstore_spec_map())
      selected = OpenApiParser.extract_services(parsed)
      auth_attrs = OpenApiParser.extract_auth_policies(parsed)

      assert {:ok, result} =
               Services.import_from_openapi(project.id, spec.id, selected,
                 import_auth_policies: true,
                 auth_policy_attrs: auth_attrs
               )

      assert result.auth_policies_count == 2
      policies = Services.list_auth_policies(project.id)
      assert length(policies) == 2
    end

    test "links services to auth policies via security_refs" do
      project = ProjectsFixtures.project_fixture()
      spec = OpenApiFixtures.openapi_spec_fixture(%{project: project})

      {:ok, parsed} = OpenApiParser.parse(OpenApiFixtures.petstore_spec_map())
      selected = OpenApiParser.extract_services(parsed)
      auth_attrs = OpenApiParser.extract_auth_policies(parsed)

      {:ok, result} =
        Services.import_from_openapi(project.id, spec.id, selected,
          import_auth_policies: true,
          auth_policy_attrs: auth_attrs
        )

      # The /pets path has security: bearerAuth, so its service should be linked
      pets_service = Enum.find(result.services, &(&1.openapi_path == "/pets"))
      assert pets_service.auth_policy_id != nil

      bearer_policy =
        Enum.find(Services.list_auth_policies(project.id), &(&1.name == "bearerAuth"))

      assert pets_service.auth_policy_id == bearer_policy.id
    end

    test "handles subset selection" do
      project = ProjectsFixtures.project_fixture()
      spec = OpenApiFixtures.openapi_spec_fixture(%{project: project})

      {:ok, parsed} = OpenApiParser.parse(OpenApiFixtures.petstore_spec_map())
      all_services = OpenApiParser.extract_services(parsed)
      selected = Enum.take(all_services, 1)

      assert {:ok, result} = Services.import_from_openapi(project.id, spec.id, selected)
      assert result.services_count == 1
    end
  end
end
