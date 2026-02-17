defmodule ZentinelCp.Plugins.PluginTest do
  use ZentinelCp.DataCase

  alias ZentinelCp.Plugins
  alias ZentinelCp.Plugins.Plugin

  import ZentinelCp.ProjectsFixtures
  import ZentinelCp.PluginFixtures

  describe "create_plugin/1" do
    test "creates with valid attributes" do
      project = project_fixture()

      assert {:ok, plugin} =
               Plugins.create_plugin(%{
                 project_id: project.id,
                 name: "Auth Validator",
                 plugin_type: "wasm",
                 description: "Validates auth tokens"
               })

      assert plugin.name == "Auth Validator"
      assert plugin.slug == "auth-validator"
      assert plugin.plugin_type == "wasm"
      assert plugin.enabled == true
      assert plugin.public == false
    end

    test "requires name and plugin_type" do
      assert {:error, changeset} = Plugins.create_plugin(%{})
      assert %{name: ["can't be blank"], plugin_type: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates plugin_type inclusion" do
      project = project_fixture()

      assert {:error, changeset} =
               Plugins.create_plugin(%{
                 project_id: project.id,
                 name: "Bad Type",
                 plugin_type: "python"
               })

      assert %{plugin_type: ["is invalid"]} = errors_on(changeset)
    end

    test "enforces unique slug within project" do
      project = project_fixture()

      {:ok, _} =
        Plugins.create_plugin(%{
          project_id: project.id,
          name: "My Plugin",
          plugin_type: "wasm"
        })

      assert {:error, changeset} =
               Plugins.create_plugin(%{
                 project_id: project.id,
                 name: "My Plugin",
                 plugin_type: "lua"
               })

      assert %{slug: ["has already been taken"]} = errors_on(changeset)
    end

    test "allows same name in different projects" do
      p1 = project_fixture()
      p2 = project_fixture()

      assert {:ok, _} =
               Plugins.create_plugin(%{
                 project_id: p1.id,
                 name: "Shared Name",
                 plugin_type: "wasm"
               })

      assert {:ok, _} =
               Plugins.create_plugin(%{
                 project_id: p2.id,
                 name: "Shared Name",
                 plugin_type: "wasm"
               })
    end

    test "creates each plugin type" do
      project = project_fixture()

      for type <- Plugin.plugin_types() do
        assert {:ok, p} =
                 Plugins.create_plugin(%{
                   project_id: project.id,
                   name: "#{type} plugin",
                   plugin_type: type
                 })

        assert p.plugin_type == type
      end
    end

    test "allows nil project_id for marketplace plugins" do
      assert {:ok, plugin} =
               Plugins.create_plugin(%{
                 name: "Global Plugin",
                 plugin_type: "wasm",
                 public: true
               })

      assert is_nil(plugin.project_id)
      assert plugin.public == true
    end
  end

  describe "update_changeset" do
    test "does not allow changing plugin_type" do
      plugin = plugin_fixture(%{plugin_type: "wasm"})

      {:ok, updated} = Plugins.update_plugin(plugin, %{plugin_type: "lua"})
      assert updated.plugin_type == "wasm"
    end

    test "updates allowed fields" do
      plugin = plugin_fixture()

      {:ok, updated} =
        Plugins.update_plugin(plugin, %{
          name: "Updated Name",
          description: "New description",
          enabled: false,
          public: true,
          author: "new-author"
        })

      assert updated.name == "Updated Name"
      assert updated.description == "New description"
      assert updated.enabled == false
      assert updated.public == true
      assert updated.author == "new-author"
    end
  end
end
