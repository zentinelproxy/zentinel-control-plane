defmodule ZentinelCp.Bundles.Sbom do
  @moduledoc """
  Generates CycloneDX 1.5 JSON SBOMs from bundle configurations.

  Extracts components from the parsed config: routes, upstreams, agents, listeners.
  """

  @spec_version "1.5"
  @bom_format "CycloneDX"

  @doc """
  Generates a CycloneDX 1.5 SBOM for a bundle.

  Returns `{:ok, sbom_map}` or `{:error, reason}`.
  """
  def generate(%{config_source: config_source, version: version, id: bundle_id} = _bundle) do
    components = extract_components(config_source)

    sbom = %{
      "bomFormat" => @bom_format,
      "specVersion" => @spec_version,
      "serialNumber" => "urn:uuid:#{bundle_id}",
      "version" => 1,
      "metadata" => %{
        "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "tools" => [
          %{
            "vendor" => "Raskell",
            "name" => "zentinel-cp",
            "version" => Application.spec(:zentinel_cp, :vsn) |> to_string()
          }
        ],
        "component" => %{
          "type" => "application",
          "name" => "zentinel-bundle",
          "version" => version,
          "bom-ref" => "bundle-#{bundle_id}"
        }
      },
      "components" => components,
      "dependencies" => build_dependencies(bundle_id, components)
    }

    {:ok, sbom}
  end

  def generate(_), do: {:error, :invalid_bundle}

  @doc """
  Returns the SBOM format identifier.
  """
  def format, do: "cyclonedx+json"

  @doc """
  Returns the content type for SBOM responses.
  """
  def content_type, do: "application/vnd.cyclonedx+json"

  ## Component Extraction

  defp extract_components(config_source) when is_binary(config_source) do
    listeners = extract_listeners(config_source)
    routes = extract_routes(config_source)
    upstreams = extract_upstreams(config_source)
    agents = extract_agents(config_source)

    listeners ++ routes ++ upstreams ++ agents
  end

  defp extract_components(_), do: []

  defp extract_listeners(source) do
    ~r/listener\s+"([^"]+)"/
    |> Regex.scan(source)
    |> Enum.map(fn [_, name] ->
      %{
        "type" => "framework",
        "name" => "listener:#{name}",
        "bom-ref" => "listener-#{name}",
        "group" => "zentinel.listeners",
        "description" => "Zentinel listener endpoint"
      }
    end)
  end

  defp extract_routes(source) do
    ~r/route\s+"([^"]+)"/
    |> Regex.scan(source)
    |> Enum.map(fn [_, name] ->
      %{
        "type" => "library",
        "name" => "route:#{name}",
        "bom-ref" => "route-#{name}",
        "group" => "zentinel.routes",
        "description" => "Zentinel routing rule"
      }
    end)
  end

  defp extract_upstreams(source) do
    ~r/upstream\s+"([^"]+)"/
    |> Regex.scan(source)
    |> Enum.map(fn [_, name] ->
      %{
        "type" => "library",
        "name" => "upstream:#{name}",
        "bom-ref" => "upstream-#{name}",
        "group" => "zentinel.upstreams",
        "description" => "Backend upstream pool"
      }
    end)
  end

  defp extract_agents(source) do
    ~r/agent\s+"([^"]+)"/
    |> Regex.scan(source)
    |> Enum.map(fn [_, name] ->
      %{
        "type" => "library",
        "name" => "agent:#{name}",
        "bom-ref" => "agent-#{name}",
        "group" => "zentinel.agents",
        "description" => "External agent process"
      }
    end)
  end

  defp build_dependencies(bundle_id, components) do
    refs = Enum.map(components, & &1["bom-ref"])

    [
      %{
        "ref" => "bundle-#{bundle_id}",
        "dependsOn" => refs
      }
    ]
  end
end
