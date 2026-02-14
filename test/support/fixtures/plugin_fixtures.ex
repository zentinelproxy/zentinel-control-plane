defmodule SentinelCp.PluginFixtures do
  @moduledoc """
  Test helpers for creating Plugin, PluginVersion, and ServicePlugin entities.
  """

  def unique_plugin_name, do: "plugin-#{System.unique_integer([:positive])}"

  def plugin_fixture(attrs \\ %{}) do
    project = attrs[:project] || SentinelCp.ProjectsFixtures.project_fixture()

    {:ok, plugin} =
      SentinelCp.Plugins.create_plugin(%{
        name: attrs[:name] || unique_plugin_name(),
        description: attrs[:description] || "A test plugin",
        plugin_type: attrs[:plugin_type] || "wasm",
        config_schema: attrs[:config_schema] || %{},
        default_config: attrs[:default_config] || %{"timeout" => 30},
        enabled: Map.get(attrs, :enabled, true),
        public: Map.get(attrs, :public, false),
        author: attrs[:author] || "test-author",
        project_id: project.id
      })

    plugin
  end

  def plugin_version_fixture(attrs \\ %{}) do
    plugin = attrs[:plugin] || plugin_fixture()
    binary = attrs[:binary] || "fake-wasm-binary-content"
    version = attrs[:version] || "1.0.0"

    {:ok, plugin_version} =
      SentinelCp.Plugins.create_plugin_version(plugin, binary, %{
        version: version,
        changelog: attrs[:changelog] || "Initial release"
      })

    plugin_version
  end

  def service_plugin_fixture(attrs \\ %{}) do
    service = attrs[:service] || SentinelCp.ServicesFixtures.service_fixture()
    plugin = attrs[:plugin] || plugin_fixture(%{project: attrs[:project]})

    {:ok, sp} =
      SentinelCp.Plugins.attach_plugin(%{
        service_id: service.id,
        plugin_id: plugin.id,
        plugin_version_id: attrs[:plugin_version_id],
        position: attrs[:position] || 0,
        enabled: Map.get(attrs, :enabled, true),
        config_override: attrs[:config_override] || %{}
      })

    sp
  end
end
