defmodule ZentinelCp.ProjectsTest do
  use ZentinelCp.DataCase

  alias ZentinelCp.Projects
  alias ZentinelCp.Projects.Project

  import ZentinelCp.ProjectsFixtures
  import ZentinelCp.OrgsFixtures

  describe "create_project/1" do
    test "creates project with valid attributes" do
      org = org_fixture()

      assert {:ok, %Project{} = project} =
               Projects.create_project(%{name: "My Project", org_id: org.id})

      assert project.name == "My Project"
      assert project.slug == "my-project"
      assert project.org_id == org.id
    end

    test "auto-generates slug from name" do
      org = org_fixture()
      assert {:ok, project} = Projects.create_project(%{name: "Hello World App", org_id: org.id})
      assert project.slug == "hello-world-app"
    end

    test "returns error for blank name" do
      org = org_fixture()
      assert {:error, changeset} = Projects.create_project(%{name: "", org_id: org.id})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "returns error for missing org_id" do
      assert {:error, changeset} = Projects.create_project(%{name: "No Org"})
      assert %{org_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "returns error for duplicate slug within same org" do
      org = org_fixture()
      assert {:ok, _} = Projects.create_project(%{name: "Duplicate", org_id: org.id})
      assert {:error, changeset} = Projects.create_project(%{name: "Duplicate", org_id: org.id})
      assert %{slug: ["has already been taken"]} = errors_on(changeset)
    end

    test "allows same slug in different orgs" do
      org1 = org_fixture()
      org2 = org_fixture()
      assert {:ok, _} = Projects.create_project(%{name: "Shared Name", org_id: org1.id})
      assert {:ok, _} = Projects.create_project(%{name: "Shared Name", org_id: org2.id})
    end
  end

  describe "get_project_by_slug/1" do
    test "returns project by slug" do
      project = project_fixture()
      found = Projects.get_project_by_slug(project.slug)
      assert found.id == project.id
    end

    test "returns nil for unknown slug" do
      refute Projects.get_project_by_slug("nonexistent")
    end
  end

  describe "list_projects/1" do
    test "returns all projects ordered by name" do
      org = org_fixture()
      _p1 = project_fixture(%{name: "Bravo", org: org})
      _p2 = project_fixture(%{name: "Alpha", org: org})

      projects = Projects.list_projects()
      names = Enum.map(projects, & &1.name)
      assert Enum.find_index(names, &(&1 == "Alpha")) < Enum.find_index(names, &(&1 == "Bravo"))
    end

    test "filters by org_id" do
      org1 = org_fixture()
      org2 = org_fixture()
      _p1 = project_fixture(%{name: "Org1 Project", org: org1})
      _p2 = project_fixture(%{name: "Org2 Project", org: org2})

      projects = Projects.list_projects(org_id: org1.id)
      assert length(projects) == 1
      assert hd(projects).name == "Org1 Project"
    end
  end

  describe "update_project/2" do
    test "updates project attributes" do
      project = project_fixture()
      assert {:ok, updated} = Projects.update_project(project, %{description: "updated"})
      assert updated.description == "updated"
    end
  end

  describe "delete_project/1" do
    test "deletes a project" do
      project = project_fixture()
      assert {:ok, _} = Projects.delete_project(project)
      refute Projects.get_project(project.id)
    end
  end
end
