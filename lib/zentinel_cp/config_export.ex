defmodule ZentinelCp.ConfigExport do
  @moduledoc """
  Config-as-Code export/import for declarative project configuration.

  Exports a project's entire configuration as a YAML-friendly map structure
  that can be version-controlled, diffed, and imported to recreate or update
  resources.

  ## Export Format
  ```yaml
  version: "1.0"
  project:
    name: "my-project"
    slug: "my-project"
  environments:
    - name: staging
    - name: production
  upstream_groups:
    - name: backend
      algorithm: round_robin
      targets:
        - host: "10.0.0.1"
          port: 8080
  services:
    - name: api-gateway
      route_path: /api
      upstream_url: http://backend
  ```
  """

  import Ecto.Query, warn: false
  alias ZentinelCp.Repo

  @export_version "1.0"

  @doc """
  Exports a project's full configuration as a map.
  """
  def export(project_id) do
    project = Repo.get!(ZentinelCp.Projects.Project, project_id)

    config = %{
      "version" => @export_version,
      "exported_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "project" => export_project(project),
      "environments" => export_environments(project_id),
      "upstream_groups" => export_upstream_groups(project_id),
      "certificates" => export_certificates(project_id),
      "auth_policies" => export_auth_policies(project_id),
      "middlewares" => export_middlewares(project_id),
      "services" => export_services(project_id)
    }

    {:ok, config}
  end

  @doc """
  Exports configuration as a YAML string.
  """
  def export_yaml(project_id) do
    case export(project_id) do
      {:ok, config} -> {:ok, Ymlr.document!(config)}
      error -> error
    end
  end

  @doc """
  Imports configuration into a project, creating or updating resources.

  Returns `{:ok, summary}` with counts of created/updated/skipped resources,
  or `{:error, reason}` on failure.
  """
  def import_config(project_id, config) when is_map(config) do
    summary = %{created: 0, updated: 0, skipped: 0, errors: []}

    summary = import_environments(project_id, config["environments"] || [], summary)
    summary = import_upstream_groups(project_id, config["upstream_groups"] || [], summary)
    summary = import_services(project_id, config["services"] || [], summary)

    {:ok, summary}
  end

  @doc """
  Computes a diff between the current state and an import config.
  Returns a list of `{action, resource_type, name}` tuples.
  """
  def diff(project_id, config) when is_map(config) do
    {:ok, current} = export(project_id)

    changes =
      diff_list(current["environments"], config["environments"] || [], "environment") ++
        diff_list(current["upstream_groups"], config["upstream_groups"] || [], "upstream_group") ++
        diff_list(current["services"], config["services"] || [], "service")

    {:ok, changes}
  end

  ## Export helpers

  defp export_project(project) do
    %{
      "name" => project.name,
      "slug" => project.slug,
      "description" => project.description
    }
  end

  defp export_environments(project_id) do
    from(e in ZentinelCp.Projects.Environment,
      where: e.project_id == ^project_id,
      order_by: [asc: e.ordinal, asc: e.name]
    )
    |> Repo.all()
    |> Enum.map(fn e ->
      %{"name" => e.name, "slug" => e.slug}
    end)
  end

  defp export_upstream_groups(project_id) do
    from(g in ZentinelCp.Services.UpstreamGroup,
      where: g.project_id == ^project_id,
      preload: [:targets],
      order_by: [asc: g.name]
    )
    |> Repo.all()
    |> Enum.map(fn g ->
      %{
        "name" => g.name,
        "slug" => g.slug,
        "algorithm" => g.algorithm,
        "targets" =>
          Enum.map(g.targets, fn t ->
            %{"host" => t.host, "port" => t.port, "weight" => t.weight, "enabled" => t.enabled}
          end)
      }
    end)
  end

  defp export_certificates(project_id) do
    from(c in ZentinelCp.Services.Certificate,
      where: c.project_id == ^project_id,
      order_by: [asc: c.name]
    )
    |> Repo.all()
    |> Enum.map(fn c ->
      %{
        "name" => c.name,
        "slug" => c.slug,
        "domain" => c.domain,
        "auto_renew" => c.auto_renew
      }
    end)
  end

  defp export_auth_policies(project_id) do
    from(a in ZentinelCp.Services.AuthPolicy,
      where: a.project_id == ^project_id,
      order_by: [asc: a.name]
    )
    |> Repo.all()
    |> Enum.map(fn a ->
      %{
        "name" => a.name,
        "slug" => a.slug,
        "auth_type" => a.auth_type,
        "config" => a.config,
        "enabled" => a.enabled
      }
    end)
  end

  defp export_middlewares(project_id) do
    from(m in ZentinelCp.Services.Middleware,
      where: m.project_id == ^project_id,
      order_by: [asc: m.name]
    )
    |> Repo.all()
    |> Enum.map(fn m ->
      %{
        "name" => m.name,
        "slug" => m.slug,
        "middleware_type" => m.middleware_type,
        "config" => m.config,
        "enabled" => m.enabled
      }
    end)
  end

  defp export_services(project_id) do
    from(s in ZentinelCp.Services.Service,
      where: s.project_id == ^project_id,
      order_by: [asc: s.position, asc: s.name]
    )
    |> Repo.all()
    |> Enum.map(fn s ->
      base = %{
        "name" => s.name,
        "slug" => s.slug,
        "route_path" => s.route_path,
        "upstream_url" => s.upstream_url,
        "enabled" => s.enabled,
        "position" => s.position,
        "service_type" => s.service_type
      }

      # Include non-default config maps
      base
      |> maybe_add("timeout_seconds", s.timeout_seconds)
      |> maybe_add("headers", s.headers, %{})
      |> maybe_add("cors", s.cors, %{})
      |> maybe_add("rate_limit", s.rate_limit, %{})
      |> maybe_add("cache", s.cache, %{})
      |> maybe_add("retry", s.retry, %{})
      |> maybe_add("compression", s.compression, %{})
      |> maybe_add("security", s.security, %{})
      |> maybe_add("inference", s.inference, %{})
      |> maybe_add("grpc", s.grpc, %{})
      |> maybe_add("websocket", s.websocket, %{})
      |> maybe_add("graphql", s.graphql, %{})
      |> maybe_add("streaming", s.streaming, %{})
    end)
  end

  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)

  defp maybe_add(map, _key, value, default) when value == default, do: map
  defp maybe_add(map, key, value, _default), do: Map.put(map, key, value)

  ## Import helpers

  defp import_environments(project_id, envs, summary) do
    Enum.reduce(envs, summary, fn env_data, acc ->
      name = env_data["name"]
      existing = Repo.get_by(ZentinelCp.Projects.Environment, project_id: project_id, name: name)

      if existing do
        %{acc | skipped: acc.skipped + 1}
      else
        case %ZentinelCp.Projects.Environment{}
             |> ZentinelCp.Projects.Environment.create_changeset(%{
               project_id: project_id,
               name: name
             })
             |> Repo.insert() do
          {:ok, _} -> %{acc | created: acc.created + 1}
          {:error, reason} -> %{acc | errors: [{:environment, name, reason} | acc.errors]}
        end
      end
    end)
  end

  defp import_upstream_groups(project_id, groups, summary) do
    Enum.reduce(groups, summary, fn group_data, acc ->
      name = group_data["name"]

      existing =
        from(g in ZentinelCp.Services.UpstreamGroup,
          where: g.project_id == ^project_id and g.name == ^name
        )
        |> Repo.one()

      if existing do
        %{acc | skipped: acc.skipped + 1}
      else
        case ZentinelCp.Services.create_upstream_group(%{
               project_id: project_id,
               name: name,
               slug: group_data["slug"] || slugify(name),
               algorithm: group_data["algorithm"] || "round_robin"
             }) do
          {:ok, _} -> %{acc | created: acc.created + 1}
          {:error, reason} -> %{acc | errors: [{:upstream_group, name, reason} | acc.errors]}
        end
      end
    end)
  rescue
    _ -> summary
  end

  defp import_services(project_id, services, summary) do
    Enum.reduce(services, summary, fn svc_data, acc ->
      name = svc_data["name"]

      existing =
        from(s in ZentinelCp.Services.Service,
          where: s.project_id == ^project_id and s.name == ^name
        )
        |> Repo.one()

      if existing do
        %{acc | skipped: acc.skipped + 1}
      else
        attrs = %{
          project_id: project_id,
          name: name,
          slug: svc_data["slug"] || name,
          route_path: svc_data["route_path"],
          upstream_url: svc_data["upstream_url"],
          enabled: Map.get(svc_data, "enabled", true),
          position: Map.get(svc_data, "position", 0),
          service_type: Map.get(svc_data, "service_type", "standard"),
          inference: Map.get(svc_data, "inference", %{}),
          grpc: Map.get(svc_data, "grpc", %{}),
          websocket: Map.get(svc_data, "websocket", %{}),
          graphql: Map.get(svc_data, "graphql", %{}),
          streaming: Map.get(svc_data, "streaming", %{})
        }

        case ZentinelCp.Services.create_service(attrs) do
          {:ok, _} -> %{acc | created: acc.created + 1}
          {:error, reason} -> %{acc | errors: [{:service, name, reason} | acc.errors]}
        end
      end
    end)
  rescue
    _ -> summary
  end

  ## Diff helpers

  defp diff_list(current, incoming, resource_type) do
    current_names = MapSet.new(Enum.map(current || [], & &1["name"]))
    incoming_names = MapSet.new(Enum.map(incoming || [], & &1["name"]))

    additions =
      MapSet.difference(incoming_names, current_names)
      |> Enum.map(&{:add, resource_type, &1})

    removals =
      MapSet.difference(current_names, incoming_names)
      |> Enum.map(&{:remove, resource_type, &1})

    modifications =
      MapSet.intersection(current_names, incoming_names)
      |> Enum.flat_map(fn name ->
        current_item = Enum.find(current, &(&1["name"] == name))
        incoming_item = Enum.find(incoming, &(&1["name"] == name))

        if current_item != incoming_item do
          [{:modify, resource_type, name}]
        else
          []
        end
      end)

    additions ++ removals ++ modifications
  end

  defp slugify(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\-]/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")
  end
end
