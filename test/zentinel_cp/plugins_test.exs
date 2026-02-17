defmodule ZentinelCp.PluginsTest do
  use ZentinelCp.DataCase

  alias ZentinelCp.Plugins

  import ZentinelCp.ProjectsFixtures
  import ZentinelCp.ServicesFixtures
  import ZentinelCp.PluginFixtures

  ## Plugin CRUD

  describe "list_plugins/1" do
    test "returns plugins for a project ordered by name" do
      project = project_fixture()
      _p1 = plugin_fixture(%{project: project, name: "Zeta"})
      _p2 = plugin_fixture(%{project: project, name: "Alpha"})

      plugins = Plugins.list_plugins(project.id)
      assert length(plugins) == 2
      assert hd(plugins).name == "Alpha"
    end

    test "includes public marketplace plugins" do
      project = project_fixture()
      _own = plugin_fixture(%{project: project, name: "Own Plugin"})

      {:ok, _global} =
        Plugins.create_plugin(%{
          name: "Global Plugin",
          plugin_type: "wasm",
          public: true
        })

      plugins = Plugins.list_plugins(project.id)
      assert length(plugins) == 2
    end

    test "does not include private plugins from other projects" do
      project = project_fixture()
      other = project_fixture()
      _own = plugin_fixture(%{project: project})
      _other = plugin_fixture(%{project: other})

      assert length(Plugins.list_plugins(project.id)) == 1
    end
  end

  describe "get_plugin/1" do
    test "returns plugin by id" do
      plugin = plugin_fixture()
      found = Plugins.get_plugin(plugin.id)
      assert found.id == plugin.id
    end

    test "returns nil for unknown id" do
      refute Plugins.get_plugin(Ecto.UUID.generate())
    end
  end

  describe "delete_plugin/1" do
    test "deletes a plugin" do
      plugin = plugin_fixture()
      assert {:ok, _} = Plugins.delete_plugin(plugin)
      refute Plugins.get_plugin(plugin.id)
    end

    test "cascades to service_plugins" do
      project = project_fixture()
      plugin = plugin_fixture(%{project: project})
      service = service_fixture(%{project: project})

      {:ok, sp} =
        Plugins.attach_plugin(%{service_id: service.id, plugin_id: plugin.id, position: 0})

      {:ok, _} = Plugins.delete_plugin(plugin)
      refute Plugins.get_service_plugin(sp.id)
    end
  end

  ## Marketplace

  describe "list_marketplace_plugins/1" do
    test "returns only public plugins" do
      {:ok, _public} =
        Plugins.create_plugin(%{name: "Public", plugin_type: "wasm", public: true})

      project = project_fixture()
      _private = plugin_fixture(%{project: project, public: false})

      plugins = Plugins.list_marketplace_plugins()
      assert length(plugins) == 1
      assert hd(plugins).name == "Public"
    end

    test "filters by plugin_type" do
      {:ok, _wasm} =
        Plugins.create_plugin(%{name: "Wasm One", plugin_type: "wasm", public: true})

      {:ok, _lua} =
        Plugins.create_plugin(%{name: "Lua One", plugin_type: "lua", public: true})

      wasm_plugins = Plugins.list_marketplace_plugins(plugin_type: "wasm")
      assert length(wasm_plugins) == 1
      assert hd(wasm_plugins).plugin_type == "wasm"
    end
  end

  ## KDL Generation with Plugins

  describe "KDL plugin chain generation" do
    alias ZentinelCp.Services.KdlGenerator
    alias ZentinelCp.Services.ProjectConfig

    test "generates KDL with plugin blocks" do
      project = project_fixture()
      service = service_fixture(%{project: project})
      config = %ProjectConfig{log_level: "info", metrics_port: 9090}

      plugin =
        plugin_fixture(%{
          project: project,
          name: "Auth Check",
          plugin_type: "wasm",
          default_config: %{"timeout" => 30}
        })

      version = plugin_version_fixture(%{plugin: plugin, version: "1.0.0"})

      {:ok, _} =
        Plugins.attach_plugin(%{
          service_id: service.id,
          plugin_id: plugin.id,
          plugin_version_id: version.id,
          position: 0
        })

      plugin_chain = Plugins.list_service_plugins(service.id)
      plugin_chains = %{service.id => plugin_chain}

      kdl = KdlGenerator.build_kdl([service], config, [], [], [], %{}, [], nil, plugin_chains)

      assert kdl =~ ~s(plugin "auth-check" {)
      assert kdl =~ ~s(type "wasm")
      assert kdl =~ ~s(path "plugins/auth-check/1.0.0.wasm")
      assert kdl =~ "timeout 30"
    end

    test "skips disabled service plugins" do
      project = project_fixture()
      service = service_fixture(%{project: project})
      config = %ProjectConfig{log_level: "info", metrics_port: 9090}

      plugin = plugin_fixture(%{project: project, name: "Disabled Plugin"})
      version = plugin_version_fixture(%{plugin: plugin})

      {:ok, sp} =
        Plugins.attach_plugin(%{
          service_id: service.id,
          plugin_id: plugin.id,
          plugin_version_id: version.id,
          position: 0
        })

      {:ok, _} = Plugins.update_service_plugin(sp, %{enabled: false})

      plugin_chain = Plugins.list_service_plugins(service.id)
      plugin_chains = %{service.id => plugin_chain}

      kdl = KdlGenerator.build_kdl([service], config, [], [], [], %{}, [], nil, plugin_chains)
      refute kdl =~ "plugin"
    end

    test "config_override merges over default_config" do
      project = project_fixture()
      service = service_fixture(%{project: project})
      config = %ProjectConfig{log_level: "info", metrics_port: 9090}

      plugin =
        plugin_fixture(%{
          project: project,
          name: "Override Plugin",
          default_config: %{"timeout" => 30, "retries" => 3}
        })

      version = plugin_version_fixture(%{plugin: plugin})

      {:ok, _} =
        Plugins.attach_plugin(%{
          service_id: service.id,
          plugin_id: plugin.id,
          plugin_version_id: version.id,
          position: 0,
          config_override: %{"timeout" => 60}
        })

      plugin_chain = Plugins.list_service_plugins(service.id)
      plugin_chains = %{service.id => plugin_chain}

      kdl = KdlGenerator.build_kdl([service], config, [], [], [], %{}, [], nil, plugin_chains)

      assert kdl =~ "timeout 60"
      refute kdl =~ "timeout 30"
      assert kdl =~ "retries 3"
    end

    test "no plugin chain produces same output as before" do
      project = project_fixture()
      service = service_fixture(%{project: project})
      config = %ProjectConfig{log_level: "info", metrics_port: 9090}

      kdl_without = KdlGenerator.build_kdl([service], config)
      kdl_with = KdlGenerator.build_kdl([service], config, [], [], [], %{}, [], nil, %{})

      assert kdl_without == kdl_with
    end
  end
end
