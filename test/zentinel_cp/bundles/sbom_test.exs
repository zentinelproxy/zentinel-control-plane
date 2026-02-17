defmodule ZentinelCp.Bundles.SbomTest do
  use ZentinelCp.DataCase

  alias ZentinelCp.Bundles.Sbom

  @sample_config """
  system {
    workers 4
  }
  listeners {
    listener "http" address="0.0.0.0:8080"
    listener "https" address="0.0.0.0:8443"
  }
  upstreams {
    upstream "backend" {
      target "127.0.0.1:9000"
    }
    upstream "api" {
      target "127.0.0.1:9001"
    }
  }
  routes {
    route "web" {
      matches { path-prefix "/" }
      upstream "backend"
    }
    route "api" {
      matches { path-prefix "/api" }
      upstream "api"
    }
  }
  agents {
    agent "waf" {
      endpoint "unix:///var/run/waf.sock"
    }
  }
  """

  defp bundle(config \\ @sample_config) do
    %{
      id: Ecto.UUID.generate(),
      version: "1.0.0",
      config_source: config,
      project_id: Ecto.UUID.generate()
    }
  end

  describe "generate/1" do
    test "generates valid CycloneDX 1.5 SBOM" do
      assert {:ok, sbom} = Sbom.generate(bundle())

      assert sbom["bomFormat"] == "CycloneDX"
      assert sbom["specVersion"] == "1.5"
      assert is_binary(sbom["serialNumber"])
      assert sbom["version"] == 1
    end

    test "includes metadata with tool info" do
      {:ok, sbom} = Sbom.generate(bundle())

      assert sbom["metadata"]["component"]["type"] == "application"
      assert sbom["metadata"]["component"]["version"] == "1.0.0"
      assert length(sbom["metadata"]["tools"]) == 1
    end

    test "extracts listeners as components" do
      {:ok, sbom} = Sbom.generate(bundle())
      components = sbom["components"]

      listener_names =
        components
        |> Enum.filter(&(&1["group"] == "zentinel.listeners"))
        |> Enum.map(& &1["name"])

      assert "listener:http" in listener_names
      assert "listener:https" in listener_names
    end

    test "extracts routes as components" do
      {:ok, sbom} = Sbom.generate(bundle())
      components = sbom["components"]

      route_names =
        components |> Enum.filter(&(&1["group"] == "zentinel.routes")) |> Enum.map(& &1["name"])

      assert "route:web" in route_names
      assert "route:api" in route_names
    end

    test "extracts upstreams as components" do
      {:ok, sbom} = Sbom.generate(bundle())
      components = sbom["components"]

      upstream_names =
        components
        |> Enum.filter(&(&1["group"] == "zentinel.upstreams"))
        |> Enum.map(& &1["name"])

      assert "upstream:backend" in upstream_names
      assert "upstream:api" in upstream_names
    end

    test "extracts agents as components" do
      {:ok, sbom} = Sbom.generate(bundle())
      components = sbom["components"]

      agent_names =
        components |> Enum.filter(&(&1["group"] == "zentinel.agents")) |> Enum.map(& &1["name"])

      assert "agent:waf" in agent_names
    end

    test "builds dependency graph" do
      {:ok, sbom} = Sbom.generate(bundle())
      deps = sbom["dependencies"]

      assert length(deps) == 1
      [root_dep] = deps
      assert String.starts_with?(root_dep["ref"], "bundle-")
      # Components = 2 listeners + routes + upstreams + agents (regex may match references too)
      assert length(root_dep["dependsOn"]) == length(sbom["components"])
    end

    test "handles minimal config" do
      {:ok, sbom} = Sbom.generate(bundle("system { workers 1 }"))
      assert sbom["components"] == []
    end

    test "handles empty config" do
      {:ok, sbom} = Sbom.generate(bundle(""))
      assert sbom["components"] == []
    end
  end

  describe "format/0" do
    test "returns cyclonedx format" do
      assert Sbom.format() == "cyclonedx+json"
    end
  end

  describe "content_type/0" do
    test "returns correct MIME type" do
      assert Sbom.content_type() == "application/vnd.cyclonedx+json"
    end
  end
end
