defmodule ZentinelCp.Services.ServiceTemplateTest do
  use ZentinelCp.DataCase

  alias ZentinelCp.Services
  alias ZentinelCp.Services.ServiceTemplate

  import ZentinelCp.ProjectsFixtures
  import ZentinelCp.ServiceTemplateFixtures

  describe "create_template/1" do
    test "creates a template with valid attributes" do
      project = project_fixture()

      assert {:ok, %ServiceTemplate{} = template} =
               Services.create_template(%{
                 name: "REST API",
                 description: "REST API template",
                 category: "api",
                 template_data: %{"route_path" => "/api/*"},
                 project_id: project.id
               })

      assert template.name == "REST API"
      assert template.slug == "rest-api"
      assert template.category == "api"
      assert template.template_data == %{"route_path" => "/api/*"}
      assert template.is_builtin == false
    end

    test "returns error for missing required fields" do
      assert {:error, changeset} = Services.create_template(%{})
      errors = errors_on(changeset)
      assert errors[:name]
      assert errors[:category]
    end

    test "validates category" do
      project = project_fixture()

      assert {:error, changeset} =
               Services.create_template(%{
                 name: "Bad Category",
                 category: "invalid",
                 project_id: project.id
               })

      assert %{category: ["is invalid"]} = errors_on(changeset)
    end

    test "returns error for duplicate slug in same project" do
      project = project_fixture()

      {:ok, _} =
        Services.create_template(%{
          name: "My Template",
          category: "api",
          project_id: project.id
        })

      assert {:error, changeset} =
               Services.create_template(%{
                 name: "My Template",
                 category: "web",
                 project_id: project.id
               })

      assert %{slug: ["has already been taken"]} = errors_on(changeset)
    end

    test "allows same name in different projects" do
      p1 = project_fixture()
      p2 = project_fixture()

      assert {:ok, _} =
               Services.create_template(%{name: "API", category: "api", project_id: p1.id})

      assert {:ok, _} =
               Services.create_template(%{name: "API", category: "api", project_id: p2.id})
    end
  end

  describe "list_templates/1" do
    test "returns project-specific and built-in templates" do
      project = project_fixture()
      _custom = template_fixture(%{project: project, name: "Custom API"})

      templates = Services.list_templates(project.id)
      custom_count = Enum.count(templates, fn t -> !t.is_builtin end)
      builtin_count = Enum.count(templates, fn t -> t.is_builtin end)

      assert custom_count >= 1
      assert builtin_count >= 11
    end

    test "does not return templates from other projects" do
      p1 = project_fixture()
      p2 = project_fixture()
      _t1 = template_fixture(%{project: p1, name: "P1 Template"})
      _t2 = template_fixture(%{project: p2, name: "P2 Template"})

      templates = Services.list_templates(p1.id)
      custom = Enum.filter(templates, fn t -> !t.is_builtin end)
      assert length(custom) == 1
      assert hd(custom).name == "P1 Template"
    end
  end

  describe "get_template/1" do
    test "returns template by id" do
      template = template_fixture()
      found = Services.get_template(template.id)
      assert found.id == template.id
    end

    test "returns nil for unknown id" do
      refute Services.get_template(Ecto.UUID.generate())
    end
  end

  describe "update_template/2" do
    test "updates a template" do
      template = template_fixture()

      assert {:ok, updated} =
               Services.update_template(template, %{
                 name: "Updated Name",
                 description: "Updated desc"
               })

      assert updated.name == "Updated Name"
      assert updated.description == "Updated desc"
    end

    test "validates on update" do
      template = template_fixture()

      assert {:error, changeset} =
               Services.update_template(template, %{category: "invalid"})

      assert %{category: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "delete_template/1" do
    test "deletes a template" do
      template = template_fixture()
      assert {:ok, _} = Services.delete_template(template)
      refute Services.get_template(template.id)
    end
  end

  describe "built-in templates" do
    test "ensure_built_ins! creates 11 built-in templates" do
      ZentinelCp.Services.BuiltInTemplates.ensure_built_ins!()

      project = project_fixture()
      templates = Services.list_templates(project.id)
      builtins = Enum.filter(templates, fn t -> t.is_builtin end)

      assert length(builtins) == 11

      categories = Enum.map(builtins, & &1.category) |> Enum.sort()
      assert "api" in categories
      assert "web" in categories
      assert "websocket" in categories
      assert "static" in categories
      assert "auth" in categories
      assert "utility" in categories
      assert "inference" in categories
      assert "grpc" in categories
      assert "graphql" in categories
      assert "streaming" in categories
    end

    test "ensure_built_ins! is idempotent" do
      ZentinelCp.Services.BuiltInTemplates.ensure_built_ins!()
      ZentinelCp.Services.BuiltInTemplates.ensure_built_ins!()

      project = project_fixture()
      templates = Services.list_templates(project.id)
      builtins = Enum.filter(templates, fn t -> t.is_builtin end)

      assert length(builtins) == 11
    end
  end
end
