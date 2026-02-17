defmodule ZentinelCp.Plugins.PluginVersionTest do
  use ZentinelCp.DataCase

  alias ZentinelCp.Plugins

  import ZentinelCp.PluginFixtures

  describe "create_plugin_version/3" do
    test "creates version with valid binary" do
      plugin = plugin_fixture()
      binary = "fake-wasm-binary"

      assert {:ok, version} =
               Plugins.create_plugin_version(plugin, binary, %{
                 version: "1.0.0",
                 changelog: "Initial release"
               })

      assert version.version == "1.0.0"
      assert version.checksum != nil
      assert version.file_size == byte_size(binary)
      assert version.storage_key =~ "plugins/#{plugin.id}/1.0.0.wasm"
      assert version.changelog == "Initial release"
    end

    test "enforces unique version per plugin" do
      plugin = plugin_fixture()

      {:ok, _} =
        Plugins.create_plugin_version(plugin, "binary-v1", %{version: "1.0.0"})

      assert {:error, changeset} =
               Plugins.create_plugin_version(plugin, "binary-v1-dup", %{version: "1.0.0"})

      errors = errors_on(changeset)
      assert Map.has_key?(errors, :plugin_id) or Map.has_key?(errors, :version)
    end

    test "validates semver format" do
      plugin = plugin_fixture()

      assert {:error, changeset} =
               Plugins.create_plugin_version(plugin, "binary", %{version: "not-semver"})

      assert %{version: ["must be valid semver" <> _]} = errors_on(changeset)
    end

    test "accepts semver with prerelease suffix" do
      plugin = plugin_fixture()

      assert {:ok, version} =
               Plugins.create_plugin_version(plugin, "binary", %{version: "1.0.0-beta.1"})

      assert version.version == "1.0.0-beta.1"
    end

    test "uses correct extension for lua plugins" do
      plugin = plugin_fixture(%{plugin_type: "lua"})

      {:ok, version} =
        Plugins.create_plugin_version(plugin, "lua-code", %{version: "1.0.0"})

      assert version.storage_key =~ ".lua"
    end
  end

  describe "list_plugin_versions/1" do
    test "returns all versions for a plugin" do
      plugin = plugin_fixture()

      {:ok, _v1} = Plugins.create_plugin_version(plugin, "b1", %{version: "1.0.0"})
      {:ok, _v2} = Plugins.create_plugin_version(plugin, "b2", %{version: "2.0.0"})

      versions = Plugins.list_plugin_versions(plugin.id)
      assert length(versions) == 2
      version_strings = Enum.map(versions, & &1.version)
      assert "1.0.0" in version_strings
      assert "2.0.0" in version_strings
    end
  end

  describe "get_latest_version/1" do
    test "returns a version when versions exist" do
      plugin = plugin_fixture()

      {:ok, v1} = Plugins.create_plugin_version(plugin, "b1", %{version: "1.0.0"})

      latest = Plugins.get_latest_version(plugin.id)
      assert latest.id == v1.id
    end

    test "returns nil when no versions exist" do
      plugin = plugin_fixture()
      assert Plugins.get_latest_version(plugin.id) == nil
    end
  end

  describe "delete_plugin_version/1" do
    test "deletes version" do
      version = plugin_version_fixture()
      assert {:ok, _} = Plugins.delete_plugin_version(version)
      assert Plugins.get_plugin_version(version.id) == nil
    end
  end
end
