defmodule ZentinelCp.Services.UpstreamGroupTest do
  use ZentinelCp.DataCase

  alias ZentinelCp.Services
  alias ZentinelCp.Services.{UpstreamGroup, UpstreamTarget}

  import ZentinelCp.ProjectsFixtures
  import ZentinelCp.UpstreamGroupFixtures

  describe "create_upstream_group/1" do
    test "creates a group with valid attributes" do
      project = project_fixture()

      assert {:ok, %UpstreamGroup{} = group} =
               Services.create_upstream_group(%{
                 project_id: project.id,
                 name: "API Backends",
                 algorithm: "round_robin"
               })

      assert group.name == "API Backends"
      assert group.slug == "api-backends"
      assert group.algorithm == "round_robin"
    end

    test "auto-generates slug from name" do
      project = project_fixture()

      {:ok, group} =
        Services.create_upstream_group(%{
          project_id: project.id,
          name: "My Cool Group!",
          algorithm: "round_robin"
        })

      assert group.slug == "my-cool-group"
    end

    test "returns error for invalid algorithm" do
      project = project_fixture()

      assert {:error, changeset} =
               Services.create_upstream_group(%{
                 project_id: project.id,
                 name: "Bad Alg",
                 algorithm: "invalid"
               })

      assert errors_on(changeset)[:algorithm]
    end

    test "returns error for duplicate slug within project" do
      project = project_fixture()

      {:ok, _} =
        Services.create_upstream_group(%{
          project_id: project.id,
          name: "My Group",
          algorithm: "round_robin"
        })

      assert {:error, changeset} =
               Services.create_upstream_group(%{
                 project_id: project.id,
                 name: "My Group",
                 algorithm: "round_robin"
               })

      assert %{slug: ["has already been taken"]} = errors_on(changeset)
    end

    test "allows same name in different projects" do
      p1 = project_fixture()
      p2 = project_fixture()

      assert {:ok, _} =
               Services.create_upstream_group(%{
                 project_id: p1.id,
                 name: "Backends",
                 algorithm: "round_robin"
               })

      assert {:ok, _} =
               Services.create_upstream_group(%{
                 project_id: p2.id,
                 name: "Backends",
                 algorithm: "round_robin"
               })
    end
  end

  describe "list_upstream_groups/1" do
    test "returns groups for a project" do
      project = project_fixture()
      _g1 = upstream_group_fixture(%{project: project, name: "Group A"})
      _g2 = upstream_group_fixture(%{project: project, name: "Group B"})

      groups = Services.list_upstream_groups(project.id)
      assert length(groups) == 2
      assert hd(groups).name == "Group A"
    end

    test "does not include groups from other projects" do
      project = project_fixture()
      other = project_fixture()
      _g1 = upstream_group_fixture(%{project: project})
      _g2 = upstream_group_fixture(%{project: other})

      groups = Services.list_upstream_groups(project.id)
      assert length(groups) == 1
    end

    test "preloads targets" do
      group = upstream_group_fixture()
      _target = upstream_target_fixture(%{group: group})

      [loaded] = Services.list_upstream_groups(group.project_id)
      assert length(loaded.targets) == 1
    end
  end

  describe "update_upstream_group/2" do
    test "updates a group" do
      group = upstream_group_fixture()

      assert {:ok, updated} =
               Services.update_upstream_group(group, %{
                 name: "Updated",
                 algorithm: "least_conn"
               })

      assert updated.name == "Updated"
      assert updated.algorithm == "least_conn"
    end

    test "validates algorithm on update" do
      group = upstream_group_fixture()

      assert {:error, changeset} =
               Services.update_upstream_group(group, %{algorithm: "invalid"})

      assert errors_on(changeset)[:algorithm]
    end
  end

  describe "delete_upstream_group/1" do
    test "deletes a group" do
      group = upstream_group_fixture()
      assert {:ok, _} = Services.delete_upstream_group(group)
      refute Services.get_upstream_group(group.id)
    end

    test "cascade deletes targets" do
      group = upstream_group_fixture()
      target = upstream_target_fixture(%{group: group})

      {:ok, _} = Services.delete_upstream_group(group)
      refute Services.get_upstream_target(target.id)
    end
  end

  describe "add_upstream_target/1" do
    test "adds a target to a group" do
      group = upstream_group_fixture()

      assert {:ok, %UpstreamTarget{} = target} =
               Services.add_upstream_target(%{
                 upstream_group_id: group.id,
                 host: "api1.internal",
                 port: 8080,
                 weight: 100
               })

      assert target.host == "api1.internal"
      assert target.port == 8080
    end

    test "validates port range" do
      group = upstream_group_fixture()

      assert {:error, changeset} =
               Services.add_upstream_target(%{
                 upstream_group_id: group.id,
                 host: "bad.host",
                 port: 0
               })

      assert errors_on(changeset)[:port]
    end

    test "validates weight > 0" do
      group = upstream_group_fixture()

      assert {:error, changeset} =
               Services.add_upstream_target(%{
                 upstream_group_id: group.id,
                 host: "bad.host",
                 port: 8080,
                 weight: 0
               })

      assert errors_on(changeset)[:weight]
    end
  end

  describe "remove_upstream_target/1" do
    test "removes a target" do
      target = upstream_target_fixture()
      assert {:ok, _} = Services.remove_upstream_target(target)
      refute Services.get_upstream_target(target.id)
    end
  end
end
