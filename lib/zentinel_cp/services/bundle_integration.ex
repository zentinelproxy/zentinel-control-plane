defmodule ZentinelCp.Services.BundleIntegration do
  @moduledoc """
  Integrates structured services with the bundle compilation pipeline.

  Generates KDL from services and creates bundles for compilation.
  Resolves secret references before KDL generation.
  """

  alias ZentinelCp.Bundles
  alias ZentinelCp.Secrets
  alias ZentinelCp.Services.KdlGenerator

  @doc """
  Creates a bundle from the project's service definitions.

  Generates KDL configuration from enabled services, resolves any
  `${secrets.NAME}` references, then creates a bundle and enqueues compilation.

  Returns `{:ok, bundle}` or `{:error, reason}`.
  """
  def create_bundle_from_services(project_id, version, opts \\ []) do
    environment = Keyword.get(opts, :environment)

    case KdlGenerator.generate(project_id, resolve_secrets: {project_id, environment}) do
      {:ok, kdl} ->
        attrs = %{
          project_id: project_id,
          version: version,
          config_source: kdl
        }

        attrs =
          if created_by_id = Keyword.get(opts, :created_by_id) do
            Map.put(attrs, :created_by_id, created_by_id)
          else
            attrs
          end

        Bundles.create_bundle(attrs)

      {:error, :no_services} ->
        {:error, :no_services}

      {:error, {:missing_secret, name}} ->
        {:error, {:missing_secret, name}}
    end
  end

  @doc """
  Generates a KDL preview without creating a bundle.

  Returns `{:ok, kdl_string}` or `{:error, :no_services}`.
  """
  def preview_kdl(project_id) do
    KdlGenerator.generate(project_id)
  end

  @doc """
  Resolves secret references in a service config map.

  This is used by KdlGenerator to resolve `${secrets.NAME}` patterns
  in config map values before generating KDL.
  """
  def resolve_secret_refs(config_map, project_id, environment \\ nil)
      when is_map(config_map) do
    Secrets.resolve_references(config_map, project_id, environment)
  end
end
