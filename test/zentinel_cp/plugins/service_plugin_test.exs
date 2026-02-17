defmodule ZentinelCp.Plugins.ServicePluginTest do
  use ZentinelCp.DataCase

  alias ZentinelCp.Plugins
  alias ZentinelCp.Plugins.ServicePlugin

  import ZentinelCp.ProjectsFixtures
  import ZentinelCp.ServicesFixtures
  import ZentinelCp.PluginFixtures

  describe "attach_plugin/1" do
    test "attaches plugin to service" do
      project = project_fixture()
      service = service_fixture(%{project: project})
      plugin = plugin_fixture(%{project: project})

      assert {:ok, %ServicePlugin{} = sp} =
               Plugins.attach_plugin(%{
                 service_id: service.id,
                 plugin_id: plugin.id,
                 position: 1
               })

      assert sp.service_id == service.id
      assert sp.plugin_id == plugin.id
      assert sp.position == 1
      assert sp.enabled == true
    end

    test "prevents duplicate attachment" do
      project = project_fixture()
      service = service_fixture(%{project: project})
      plugin = plugin_fixture(%{project: project})

      {:ok, _} =
        Plugins.attach_plugin(%{service_id: service.id, plugin_id: plugin.id, position: 0})

      assert {:error, changeset} =
               Plugins.attach_plugin(%{service_id: service.id, plugin_id: plugin.id, position: 1})

      assert %{service_id: _} = errors_on(changeset)
    end

    test "allows config_override" do
      project = project_fixture()
      service = service_fixture(%{project: project})
      plugin = plugin_fixture(%{project: project, default_config: %{"timeout" => 30}})

      {:ok, sp} =
        Plugins.attach_plugin(%{
          service_id: service.id,
          plugin_id: plugin.id,
          position: 0,
          config_override: %{"timeout" => 60}
        })

      assert sp.config_override["timeout"] == 60
    end

    test "allows optional plugin_version_id" do
      project = project_fixture()
      service = service_fixture(%{project: project})
      plugin = plugin_fixture(%{project: project})
      version = plugin_version_fixture(%{plugin: plugin})

      {:ok, sp} =
        Plugins.attach_plugin(%{
          service_id: service.id,
          plugin_id: plugin.id,
          plugin_version_id: version.id,
          position: 0
        })

      assert sp.plugin_version_id == version.id
    end
  end

  describe "list_service_plugins/1" do
    test "returns plugins ordered by position" do
      project = project_fixture()
      service = service_fixture(%{project: project})
      p1 = plugin_fixture(%{project: project, name: "B Plugin"})
      p2 = plugin_fixture(%{project: project, name: "A Plugin"})

      {:ok, _} = Plugins.attach_plugin(%{service_id: service.id, plugin_id: p1.id, position: 2})
      {:ok, _} = Plugins.attach_plugin(%{service_id: service.id, plugin_id: p2.id, position: 1})

      chain = Plugins.list_service_plugins(service.id)
      assert length(chain) == 2
      assert hd(chain).position == 1
      assert hd(chain).plugin.name == "A Plugin"
    end

    test "preloads plugin and plugin_version" do
      project = project_fixture()
      service = service_fixture(%{project: project})
      plugin = plugin_fixture(%{project: project})

      {:ok, _} =
        Plugins.attach_plugin(%{service_id: service.id, plugin_id: plugin.id, position: 0})

      [sp] = Plugins.list_service_plugins(service.id)
      assert %ZentinelCp.Plugins.Plugin{} = sp.plugin
      assert sp.plugin.id == plugin.id
    end
  end

  describe "detach_plugin/1" do
    test "removes plugin from service" do
      project = project_fixture()
      service = service_fixture(%{project: project})
      plugin = plugin_fixture(%{project: project})

      {:ok, sp} =
        Plugins.attach_plugin(%{service_id: service.id, plugin_id: plugin.id, position: 0})

      assert {:ok, _} = Plugins.detach_plugin(sp)
      assert Plugins.list_service_plugins(service.id) == []
    end
  end

  describe "update_service_plugin/2" do
    test "updates position and enabled" do
      project = project_fixture()
      service = service_fixture(%{project: project})
      plugin = plugin_fixture(%{project: project})

      {:ok, sp} =
        Plugins.attach_plugin(%{service_id: service.id, plugin_id: plugin.id, position: 0})

      {:ok, updated} = Plugins.update_service_plugin(sp, %{position: 5, enabled: false})
      assert updated.position == 5
      assert updated.enabled == false
    end
  end

  describe "reorder_service_plugins/2" do
    test "batch updates positions" do
      project = project_fixture()
      service = service_fixture(%{project: project})
      p1 = plugin_fixture(%{project: project, name: "First"})
      p2 = plugin_fixture(%{project: project, name: "Second"})

      {:ok, sp1} = Plugins.attach_plugin(%{service_id: service.id, plugin_id: p1.id, position: 0})
      {:ok, sp2} = Plugins.attach_plugin(%{service_id: service.id, plugin_id: p2.id, position: 1})

      assert {:ok, :ok} =
               Plugins.reorder_service_plugins(service.id, [
                 {sp1.id, 2},
                 {sp2.id, 1}
               ])

      chain = Plugins.list_service_plugins(service.id)
      assert hd(chain).plugin.name == "Second"
      assert List.last(chain).plugin.name == "First"
    end
  end
end
