defmodule ZentinelCp.Plugins do
  @moduledoc """
  Context for plugin management: CRUD, versioning, service attachment,
  marketplace listing, and bundle integration.
  """

  import Ecto.Query
  alias ZentinelCp.Repo
  alias ZentinelCp.Plugins.{Plugin, PluginVersion, ServicePlugin}
  alias ZentinelCp.Bundles.{Compiler, Storage}

  ## Plugin CRUD

  @doc """
  Lists plugins for a project plus public marketplace plugins, ordered by name.
  """
  def list_plugins(project_id) do
    from(p in Plugin,
      where: p.project_id == ^project_id or (is_nil(p.project_id) and p.public == true),
      order_by: [asc: p.name]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single plugin by ID, preloading latest version.
  """
  def get_plugin(id) do
    Plugin
    |> Repo.get(id)
    |> maybe_preload_latest_version()
  end

  @doc """
  Gets a single plugin by ID, raises if not found.
  """
  def get_plugin!(id) do
    Plugin
    |> Repo.get!(id)
    |> maybe_preload_latest_version()
  end

  defp maybe_preload_latest_version(nil), do: nil

  defp maybe_preload_latest_version(%Plugin{} = plugin) do
    latest = get_latest_version(plugin.id)
    Map.put(plugin, :plugin_versions, if(latest, do: [latest], else: []))
  end

  @doc """
  Creates a plugin.
  """
  def create_plugin(attrs) do
    %Plugin{}
    |> Plugin.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a plugin.
  """
  def update_plugin(%Plugin{} = plugin, attrs) do
    plugin
    |> Plugin.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a plugin. Cascades to versions and service_plugins via DB.
  Cleans up S3 storage for all versions.
  """
  def delete_plugin(%Plugin{} = plugin) do
    versions = list_plugin_versions(plugin.id)

    for v <- versions do
      Storage.delete(v.storage_key)
    end

    Repo.delete(plugin)
  end

  ## Plugin Versions

  @doc """
  Lists versions for a plugin, ordered by inserted_at desc.
  """
  def list_plugin_versions(plugin_id) do
    from(v in PluginVersion,
      where: v.plugin_id == ^plugin_id,
      order_by: [desc: v.inserted_at, desc: v.id]
    )
    |> Repo.all()
  end

  @doc """
  Gets a plugin version by ID.
  """
  def get_plugin_version(id), do: Repo.get(PluginVersion, id)

  @doc """
  Gets the latest version for a plugin (most recent by inserted_at).
  """
  def get_latest_version(plugin_id) do
    from(v in PluginVersion,
      where: v.plugin_id == ^plugin_id,
      order_by: [desc: v.inserted_at, desc: v.id],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Creates a plugin version by uploading binary content to S3.

  Accepts base64-encoded binary, computes SHA256 checksum, uploads to S3,
  and creates the DB record.
  """
  def create_plugin_version(%Plugin{} = plugin, binary_content, attrs)
      when is_binary(binary_content) do
    checksum = Compiler.checksum(binary_content)
    file_size = byte_size(binary_content)
    version = attrs[:version] || attrs["version"]
    ext = plugin_extension(plugin.plugin_type)
    storage_key = "plugins/#{plugin.id}/#{version}.#{ext}"

    case Storage.upload(storage_key, binary_content) do
      :ok ->
        version_attrs =
          Map.merge(
            %{
              plugin_id: plugin.id,
              storage_key: storage_key,
              checksum: checksum,
              file_size: file_size
            },
            normalize_attrs(attrs)
          )

        %PluginVersion{}
        |> PluginVersion.changeset(version_attrs)
        |> Repo.insert()

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Deletes a plugin version from S3 and DB.
  """
  def delete_plugin_version(%PluginVersion{} = version) do
    Storage.delete(version.storage_key)
    Repo.delete(version)
  end

  ## Service Plugin Chain

  @doc """
  Lists service plugins for a service, ordered by position, preloading plugin and version.
  """
  def list_service_plugins(service_id) do
    from(sp in ServicePlugin,
      where: sp.service_id == ^service_id,
      order_by: [asc: sp.position],
      preload: [:plugin, :plugin_version]
    )
    |> Repo.all()
  end

  @doc """
  Attaches a plugin to a service.
  """
  def attach_plugin(attrs) do
    %ServicePlugin{}
    |> ServicePlugin.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Detaches a plugin from a service.
  """
  def detach_plugin(%ServicePlugin{} = sp) do
    Repo.delete(sp)
  end

  @doc """
  Gets a service plugin by ID with preloads.
  """
  def get_service_plugin(id) do
    ServicePlugin
    |> Repo.get(id)
    |> Repo.preload([:plugin, :plugin_version])
  end

  @doc """
  Gets a service plugin by service_id and plugin_id.
  """
  def get_service_plugin_by(service_id, plugin_id) do
    from(sp in ServicePlugin,
      where: sp.service_id == ^service_id and sp.plugin_id == ^plugin_id
    )
    |> Repo.one()
  end

  @doc """
  Updates a service plugin (position, enabled, config_override, plugin_version_id).
  """
  def update_service_plugin(%ServicePlugin{} = sp, attrs) do
    sp
    |> ServicePlugin.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Batch updates service plugin positions.

  Accepts a list of `{service_plugin_id, position}` tuples.
  """
  def reorder_service_plugins(service_id, id_position_pairs) do
    Repo.transaction(fn ->
      for {id, position} <- id_position_pairs do
        from(sp in ServicePlugin,
          where: sp.id == ^id and sp.service_id == ^service_id
        )
        |> Repo.update_all(set: [position: position])
      end

      :ok
    end)
  end

  ## Marketplace

  @doc """
  Lists public marketplace plugins, optionally filtered by type.
  """
  def list_marketplace_plugins(opts \\ []) do
    query =
      from(p in Plugin,
        where: p.public == true,
        order_by: [asc: p.name]
      )

    query =
      case opts[:plugin_type] do
        nil -> query
        type -> from(p in query, where: p.plugin_type == ^type)
      end

    Repo.all(query)
  end

  ## Bundle Integration

  @doc """
  Collects plugin files for bundle compilation.

  Returns `[{path, binary_content}]` for all enabled plugins attached
  to services in the given project. Deduplicates by plugin+version.
  """
  def collect_plugin_files(project_id) do
    # Get all services for this project
    service_ids =
      from(s in ZentinelCp.Services.Service,
        where: s.project_id == ^project_id and s.enabled == true,
        select: s.id
      )
      |> Repo.all()

    if service_ids == [] do
      []
    else
      # Get all enabled service_plugins for these services
      service_plugins =
        from(sp in ServicePlugin,
          where: sp.service_id in ^service_ids and sp.enabled == true,
          preload: [:plugin, :plugin_version]
        )
        |> Repo.all()

      # Deduplicate and collect files
      service_plugins
      |> Enum.map(fn sp ->
        version = sp.plugin_version || get_latest_version(sp.plugin_id)
        {sp.plugin, version}
      end)
      |> Enum.reject(fn {_plugin, version} -> is_nil(version) end)
      |> Enum.uniq_by(fn {plugin, version} -> {plugin.id, version.id} end)
      |> Enum.flat_map(fn {plugin, version} ->
        ext = plugin_extension(plugin.plugin_type)
        path = "plugins/#{plugin.slug}/#{version.version}.#{ext}"

        case Storage.download(version.storage_key) do
          {:ok, binary} -> [{path, binary}]
          _ -> []
        end
      end)
    end
  end

  ## Private helpers

  defp plugin_extension("wasm"), do: "wasm"
  defp plugin_extension("lua"), do: "lua"
  defp plugin_extension(_), do: "bin"

  defp normalize_attrs(attrs) when is_map(attrs) do
    attrs
    |> Enum.into(%{}, fn
      {k, v} when is_atom(k) -> {k, v}
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
    end)
  end
end
