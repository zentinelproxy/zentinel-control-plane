defmodule SentinelCp.Services do
  @moduledoc """
  The Services context manages proxy service definitions.

  Services are structured representations of proxy routes that can be
  used to generate KDL configuration for bundles.
  """

  import Ecto.Query, warn: false
  alias SentinelCp.Repo
  alias SentinelCp.Services.{Service, ServiceTemplate, ProjectConfig, UpstreamGroup, UpstreamTarget, Certificate, TrustStore, AuthPolicy, OpenApiSpec, DiscoverySource, DiscoverySync, Middleware, ServiceMiddleware}
  alias SentinelCp.Secrets

  ## Services

  @doc """
  Lists services for a project, ordered by position.
  """
  def list_services(project_id, opts \\ []) do
    query =
      from(s in Service,
        where: s.project_id == ^project_id,
        order_by: [asc: s.position, asc: s.inserted_at]
      )

    query =
      Enum.reduce(opts, query, fn
        {:enabled, enabled}, q -> where(q, [s], s.enabled == ^enabled)
        {:service_type, type}, q -> where(q, [s], s.service_type == ^type)
        _, q -> q
      end)

    Repo.all(query)
  end

  @doc """
  Gets a single service by ID.
  """
  def get_service(id), do: Repo.get(Service, id)

  @doc """
  Gets a single service by ID, raises if not found.
  """
  def get_service!(id), do: Repo.get!(Service, id)

  @doc """
  Creates a service.
  """
  def create_service(attrs) do
    %Service{}
    |> Service.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a service.
  """
  def update_service(%Service{} = service, attrs) do
    service
    |> Service.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a service.
  """
  def delete_service(%Service{} = service) do
    Repo.delete(service)
  end

  @doc """
  Batch updates service positions.

  Accepts a list of `{service_id, position}` tuples.
  """
  def reorder_services(project_id, id_position_pairs) do
    Repo.transaction(fn ->
      for {id, position} <- id_position_pairs do
        from(s in Service,
          where: s.id == ^id and s.project_id == ^project_id
        )
        |> Repo.update_all(set: [position: position])
      end

      :ok
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking service changes.
  """
  def change_service(%Service{} = service, attrs \\ %{}) do
    Service.update_changeset(service, attrs)
  end

  ## Project Config

  @doc """
  Gets or creates the project config for a project.
  """
  def get_or_create_project_config(project_id) do
    case Repo.get_by(ProjectConfig, project_id: project_id) do
      nil ->
        %ProjectConfig{}
        |> ProjectConfig.changeset(%{project_id: project_id})
        |> Repo.insert()

      config ->
        {:ok, config}
    end
  end

  @doc """
  Updates the project config.
  """
  def update_project_config(%ProjectConfig{} = config, attrs) do
    config
    |> ProjectConfig.changeset(attrs)
    |> Repo.update()
  end

  ## Upstream Groups

  @doc """
  Lists upstream groups for a project, preloading targets.
  """
  def list_upstream_groups(project_id) do
    from(g in UpstreamGroup,
      where: g.project_id == ^project_id,
      order_by: [asc: g.name],
      preload: [:targets]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single upstream group by ID, preloading targets.
  """
  def get_upstream_group(id) do
    UpstreamGroup
    |> Repo.get(id)
    |> Repo.preload(:targets)
  end

  @doc """
  Gets a single upstream group by ID, raises if not found.
  """
  def get_upstream_group!(id) do
    UpstreamGroup
    |> Repo.get!(id)
    |> Repo.preload(:targets)
  end

  @doc """
  Creates an upstream group.
  """
  def create_upstream_group(attrs) do
    %UpstreamGroup{}
    |> UpstreamGroup.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an upstream group.
  """
  def update_upstream_group(%UpstreamGroup{} = group, attrs) do
    group
    |> UpstreamGroup.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an upstream group.
  """
  def delete_upstream_group(%UpstreamGroup{} = group) do
    Repo.delete(group)
  end

  @doc """
  Adds a target to an upstream group.
  """
  def add_upstream_target(attrs) do
    %UpstreamTarget{}
    |> UpstreamTarget.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an upstream target.
  """
  def update_upstream_target(%UpstreamTarget{} = target, attrs) do
    target
    |> UpstreamTarget.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Gets an upstream target by ID.
  """
  def get_upstream_target(id), do: Repo.get(UpstreamTarget, id)

  @doc """
  Removes an upstream target.
  """
  def remove_upstream_target(%UpstreamTarget{} = target) do
    Repo.delete(target)
  end

  ## Auth Policies

  @doc """
  Lists auth policies for a project, ordered by name.
  """
  def list_auth_policies(project_id) do
    from(a in AuthPolicy,
      where: a.project_id == ^project_id,
      order_by: [asc: a.name]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single auth policy by ID.
  """
  def get_auth_policy(id), do: Repo.get(AuthPolicy, id)

  @doc """
  Gets a single auth policy by ID, raises if not found.
  """
  def get_auth_policy!(id), do: Repo.get!(AuthPolicy, id)

  @doc """
  Creates an auth policy.
  """
  def create_auth_policy(attrs) do
    %AuthPolicy{}
    |> AuthPolicy.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an auth policy.
  """
  def update_auth_policy(%AuthPolicy{} = policy, attrs) do
    policy
    |> AuthPolicy.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an auth policy.
  """
  def delete_auth_policy(%AuthPolicy{} = policy) do
    Repo.delete(policy)
  end

  ## Certificates

  @doc """
  Lists certificates for a project, ordered by domain.
  """
  def list_certificates(project_id) do
    from(c in Certificate,
      where: c.project_id == ^project_id,
      order_by: [asc: c.domain]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single certificate by ID.
  """
  def get_certificate(id), do: Repo.get(Certificate, id)

  @doc """
  Gets a single certificate by ID, raises if not found.
  """
  def get_certificate!(id), do: Repo.get!(Certificate, id)

  @doc """
  Creates a certificate. Expects `key_pem` (plaintext) in attrs — it will be encrypted.
  """
  def create_certificate(attrs) do
    %Certificate{}
    |> Certificate.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a certificate (name, auto_renew, acme_config).
  """
  def update_certificate(%Certificate{} = cert, attrs) do
    cert
    |> Certificate.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Renews a certificate with new PEM data.
  """
  def renew_certificate(%Certificate{} = cert, attrs) do
    cert
    |> Certificate.renew_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a certificate.
  """
  def delete_certificate(%Certificate{} = cert) do
    Repo.delete(cert)
  end

  @doc """
  Lists certificates expiring within the given number of days.
  """
  def list_expiring_certificates(days_ahead \\ 30) do
    now = DateTime.utc_now()
    threshold = DateTime.add(now, days_ahead * 86_400, :second)

    from(c in Certificate,
      where: c.status in ["active", "expiring_soon"],
      where: c.not_after > ^now,
      where: c.not_after <= ^threshold,
      order_by: [asc: c.not_after]
    )
    |> Repo.all()
  end

  @doc """
  Lists certificates eligible for ACME auto-renewal.

  Finds certificates with `auto_renew: true`, non-empty `acme_config`,
  and expiring within the configured threshold (default 30 days).
  """
  def list_acme_renewal_candidates(days_ahead \\ 30) do
    now = DateTime.utc_now()
    threshold = DateTime.add(now, days_ahead * 86_400, :second)

    from(c in Certificate,
      where: c.auto_renew == true,
      where: c.status in ["active", "expiring_soon"],
      where: c.not_after > ^now,
      where: c.not_after <= ^threshold,
      order_by: [asc: c.not_after]
    )
    |> Repo.all()
    |> Enum.filter(&((&1.acme_config || %{}) != %{}))
  end

  @doc """
  Updates ACME-specific fields on a certificate (account key, renewal status).
  """
  def update_certificate_acme(%Certificate{} = cert, attrs) do
    cert
    |> Certificate.acme_changeset(attrs)
    |> Repo.update()
  end

  ## Trust Stores

  @doc """
  Lists trust stores for a project, ordered by name.
  """
  def list_trust_stores(project_id) do
    from(t in TrustStore,
      where: t.project_id == ^project_id,
      order_by: [asc: t.name]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single trust store by ID.
  """
  def get_trust_store(id), do: Repo.get(TrustStore, id)

  @doc """
  Gets a single trust store by ID, raises if not found.
  """
  def get_trust_store!(id), do: Repo.get!(TrustStore, id)

  @doc """
  Creates a trust store.
  """
  def create_trust_store(attrs) do
    %TrustStore{}
    |> TrustStore.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a trust store.
  """
  def update_trust_store(%TrustStore{} = trust_store, attrs) do
    trust_store
    |> TrustStore.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a trust store.
  """
  def delete_trust_store(%TrustStore{} = trust_store) do
    Repo.delete(trust_store)
  end

  ## Service Templates

  @doc """
  Lists service templates: built-ins + project-specific.
  Ensures built-in templates are seeded on first access.
  """
  def list_templates(project_id) do
    SentinelCp.Services.BuiltInTemplates.ensure_built_ins!()

    from(t in ServiceTemplate,
      where: t.is_builtin == true or t.project_id == ^project_id,
      order_by: [asc: t.category, asc: t.name]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single template by ID.
  """
  def get_template(id), do: Repo.get(ServiceTemplate, id)

  @doc """
  Gets a single template by ID, raises if not found.
  """
  def get_template!(id), do: Repo.get!(ServiceTemplate, id)

  @doc """
  Creates a service template.
  """
  def create_template(attrs) do
    %ServiceTemplate{}
    |> ServiceTemplate.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a service template.
  """
  def update_template(%ServiceTemplate{} = template, attrs) do
    template
    |> ServiceTemplate.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a service template.
  """
  def delete_template(%ServiceTemplate{} = template) do
    Repo.delete(template)
  end

  ## OpenAPI Specs

  @doc """
  Lists OpenAPI specs for a project, most recent first.
  """
  def list_openapi_specs(project_id) do
    from(s in OpenApiSpec,
      where: s.project_id == ^project_id,
      order_by: [desc: s.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single OpenAPI spec by ID.
  """
  def get_openapi_spec(id), do: Repo.get(OpenApiSpec, id)

  @doc """
  Gets a single OpenAPI spec by ID, raises if not found.
  """
  def get_openapi_spec!(id), do: Repo.get!(OpenApiSpec, id)

  @doc """
  Creates an OpenAPI spec record.
  """
  def create_openapi_spec(attrs) do
    %OpenApiSpec{}
    |> OpenApiSpec.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Deletes an OpenAPI spec.
  """
  def delete_openapi_spec(%OpenApiSpec{} = spec) do
    Repo.delete(spec)
  end

  @doc """
  Finds an OpenAPI spec by checksum within a project, for dedup on re-upload.
  """
  def get_openapi_spec_by_checksum(project_id, checksum) do
    from(s in OpenApiSpec,
      where: s.project_id == ^project_id and s.checksum == ^checksum
    )
    |> Repo.one()
  end

  @doc """
  Imports services (and optionally auth policies) from an OpenAPI spec.

  Runs in a transaction: creates auth policies first, then services with
  spec linkage and resolved auth_policy_ids.
  """
  def import_from_openapi(project_id, spec_id, selected_services, opts \\ []) do
    import_auth = Keyword.get(opts, :import_auth_policies, false)
    auth_policy_attrs = Keyword.get(opts, :auth_policy_attrs, [])

    Repo.transaction(fn ->
      # Create auth policies if requested
      policy_map =
        if import_auth do
          auth_policy_attrs
          |> Enum.reduce(%{}, fn attrs, acc ->
            attrs_with_project = Map.put(attrs, :project_id, project_id)

            case create_auth_policy(attrs_with_project) do
              {:ok, policy} -> Map.put(acc, attrs.name, policy.id)
              {:error, changeset} -> Repo.rollback({:auth_policy_error, changeset})
            end
          end)
        else
          %{}
        end

      # Create services
      services =
        Enum.map(selected_services, fn svc_attrs ->
          auth_policy_id = resolve_auth_policy_id(svc_attrs, policy_map)

          attrs =
            %{
              name: svc_attrs.name,
              route_path: svc_attrs.route_path,
              upstream_url: svc_attrs.upstream_url,
              description: svc_attrs[:description],
              openapi_spec_id: spec_id,
              openapi_path: svc_attrs.openapi_path,
              project_id: project_id
            }
            |> maybe_put(:auth_policy_id, auth_policy_id)

          case create_service(attrs) do
            {:ok, service} -> service
            {:error, changeset} -> Repo.rollback({:service_error, changeset})
          end
        end)

      %{
        services: services,
        services_count: length(services),
        auth_policies_count: map_size(policy_map)
      }
    end)
  end

  ## Discovery Sources

  @doc """
  Lists discovery sources for a project, preloading upstream_group.
  """
  def list_discovery_sources(project_id) do
    from(d in DiscoverySource,
      where: d.project_id == ^project_id,
      preload: [:upstream_group]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single discovery source by ID.
  """
  def get_discovery_source(id), do: Repo.get(DiscoverySource, id)

  @doc """
  Gets a single discovery source by ID, raises if not found.
  """
  def get_discovery_source!(id), do: Repo.get!(DiscoverySource, id)

  @doc """
  Gets the discovery source for an upstream group, if any.
  """
  def get_discovery_source_for_group(upstream_group_id) do
    from(d in DiscoverySource, where: d.upstream_group_id == ^upstream_group_id)
    |> Repo.one()
  end

  @doc """
  Creates a discovery source.
  """
  def create_discovery_source(attrs) do
    %DiscoverySource{}
    |> DiscoverySource.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a discovery source (hostname, interval, auto_sync).
  """
  def update_discovery_source(%DiscoverySource{} = source, attrs) do
    source
    |> DiscoverySource.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a discovery source.
  """
  def delete_discovery_source(%DiscoverySource{} = source) do
    Repo.delete(source)
  end

  @doc """
  Lists all discovery sources with auto_sync enabled (across all projects).
  """
  def list_auto_sync_sources do
    from(d in DiscoverySource, where: d.auto_sync == true)
    |> Repo.all()
  end

  @doc """
  Synchronizes a discovery source by resolving DNS SRV records and reconciling targets.

  Returns `{:ok, %{added: N, removed: N, kept: N}}` on success or `{:error, reason}` on failure.
  """
  def sync_discovery_source(%DiscoverySource{} = source) do
    # Mark as syncing
    {:ok, source} =
      source
      |> DiscoverySource.sync_changeset(%{last_sync_status: "syncing"})
      |> Repo.update()

    case resolve_records(source) do
      {:ok, records} ->
        group = get_upstream_group!(source.upstream_group_id)
        current_targets = group.targets || []

        result = DiscoverySync.reconcile(current_targets, records)

        # Apply additions
        for target_attrs <- result.add do
          add_upstream_target(
            Map.merge(target_attrs, %{upstream_group_id: source.upstream_group_id})
          )
        end

        # Apply removals
        for target <- result.remove do
          remove_upstream_target(target)
        end

        total_count = length(result.add) + length(result.keep)

        {:ok, source} =
          source
          |> DiscoverySource.sync_changeset(%{
            last_synced_at: DateTime.utc_now() |> DateTime.truncate(:second),
            last_sync_status: "synced",
            last_sync_error: nil,
            last_sync_targets_count: total_count
          })
          |> Repo.update()

        Phoenix.PubSub.broadcast(
          SentinelCp.PubSub,
          "discovery:#{source.id}",
          {:discovery_synced, source.id}
        )

        {:ok, %{added: length(result.add), removed: length(result.remove), kept: length(result.keep)}}

      {:error, reason} ->
        error_msg = if is_binary(reason), do: reason, else: inspect(reason)

        source
        |> DiscoverySource.sync_changeset(%{
          last_synced_at: DateTime.utc_now() |> DateTime.truncate(:second),
          last_sync_status: "error",
          last_sync_error: error_msg
        })
        |> Repo.update()

        {:error, error_msg}
    end
  end

  ## Middlewares

  @doc """
  Lists middlewares for a project, ordered by name.
  """
  def list_middlewares(project_id) do
    from(m in Middleware,
      where: m.project_id == ^project_id,
      order_by: [asc: m.name]
    )
    |> Repo.all()
  end

  @doc """
  Lists middlewares for a project filtered by type.
  """
  def list_middlewares_by_type(project_id, type) do
    from(m in Middleware,
      where: m.project_id == ^project_id and m.middleware_type == ^type,
      order_by: [asc: m.name]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single middleware by ID.
  """
  def get_middleware(id), do: Repo.get(Middleware, id)

  @doc """
  Gets a single middleware by ID, raises if not found.
  """
  def get_middleware!(id), do: Repo.get!(Middleware, id)

  @doc """
  Creates a middleware.
  """
  def create_middleware(attrs) do
    %Middleware{}
    |> Middleware.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a middleware.
  """
  def update_middleware(%Middleware{} = middleware, attrs) do
    middleware
    |> Middleware.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a middleware. Cascades to service_middlewares.
  """
  def delete_middleware(%Middleware{} = middleware) do
    Repo.delete(middleware)
  end

  ## Service Middleware Chain

  @doc """
  Lists service middlewares for a service, ordered by position, preloading middleware.
  """
  def list_service_middlewares(service_id) do
    from(sm in ServiceMiddleware,
      where: sm.service_id == ^service_id,
      order_by: [asc: sm.position],
      preload: [:middleware]
    )
    |> Repo.all()
  end

  @doc """
  Attaches a middleware to a service.
  """
  def attach_middleware(attrs) do
    %ServiceMiddleware{}
    |> ServiceMiddleware.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Detaches a middleware from a service.
  """
  def detach_middleware(%ServiceMiddleware{} = sm) do
    Repo.delete(sm)
  end

  @doc """
  Gets a service middleware by ID.
  """
  def get_service_middleware(id) do
    ServiceMiddleware
    |> Repo.get(id)
    |> Repo.preload(:middleware)
  end

  @doc """
  Gets a service middleware by service_id and middleware_id.
  """
  def get_service_middleware_by(service_id, middleware_id) do
    from(sm in ServiceMiddleware,
      where: sm.service_id == ^service_id and sm.middleware_id == ^middleware_id
    )
    |> Repo.one()
  end

  @doc """
  Updates a service middleware (position, enabled, config_override).
  """
  def update_service_middleware(%ServiceMiddleware{} = sm, attrs) do
    sm
    |> ServiceMiddleware.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Batch updates service middleware positions.

  Accepts a list of `{service_middleware_id, position}` tuples.
  """
  def reorder_service_middlewares(service_id, id_position_pairs) do
    Repo.transaction(fn ->
      for {id, position} <- id_position_pairs do
        from(sm in ServiceMiddleware,
          where: sm.id == ^id and sm.service_id == ^service_id
        )
        |> Repo.update_all(set: [position: position])
      end

      :ok
    end)
  end

  ## Topology

  @doc """
  Returns topology data for visualization: nodes, edges, and metadata.
  """
  def get_topology_data(project_id) do
    services =
      list_services(project_id)
      |> Repo.preload([:upstream_group, :auth_policy, :certificate, service_middlewares: :middleware])

    upstream_groups = list_upstream_groups(project_id)
    auth_policies = list_auth_policies(project_id)
    certificates = list_certificates(project_id)
    middlewares = list_middlewares(project_id)

    %{
      services: Enum.map(services, &service_topology_node/1),
      upstream_groups: Enum.map(upstream_groups, &upstream_group_topology_node/1),
      auth_policies: Enum.map(auth_policies, &auth_policy_topology_node/1),
      certificates: Enum.map(certificates, &certificate_topology_node/1),
      middlewares: Enum.map(middlewares, &middleware_topology_node/1),
      edges: build_topology_edges(services, upstream_groups)
    }
  end

  defp service_topology_node(service) do
    %{
      id: service.id,
      name: service.name,
      type: "service",
      status: if(service.enabled, do: "enabled", else: "disabled"),
      metadata: %{
        route_path: service.route_path,
        upstream_url: service.upstream_url,
        service_type: service.service_type
      }
    }
  end

  defp upstream_group_topology_node(group) do
    target_count = length(group.targets || [])
    healthy = Enum.count(group.targets || [], &(&1.healthy != false))

    %{
      id: group.id,
      name: group.name,
      type: "upstream_group",
      status: if(healthy == target_count, do: "healthy", else: "degraded"),
      metadata: %{
        algorithm: group.algorithm,
        target_count: target_count,
        targets: Enum.map(group.targets || [], fn t ->
          %{id: t.id, host: t.host, port: t.port, weight: t.weight}
        end)
      }
    }
  end

  defp auth_policy_topology_node(policy) do
    %{
      id: policy.id,
      name: policy.name,
      type: "auth_policy",
      status: "active",
      metadata: %{auth_type: policy.auth_type}
    }
  end

  defp certificate_topology_node(cert) do
    %{
      id: cert.id,
      name: cert.domain,
      type: "certificate",
      status: cert.status || "active",
      metadata: %{
        domain: cert.domain,
        not_after: cert.not_after && DateTime.to_iso8601(cert.not_after)
      }
    }
  end

  defp middleware_topology_node(middleware) do
    %{
      id: middleware.id,
      name: middleware.name,
      type: "middleware",
      status: if(middleware.enabled, do: "enabled", else: "disabled"),
      metadata: %{middleware_type: middleware.middleware_type}
    }
  end

  defp build_topology_edges(services, upstream_groups) do
    service_edges =
      Enum.flat_map(services, fn service ->
        edges = []

        edges =
          if service.upstream_group_id do
            [%{source: service.id, target: service.upstream_group_id, edge_type: "upstream"} | edges]
          else
            edges
          end

        edges =
          if service.auth_policy_id do
            [%{source: service.id, target: service.auth_policy_id, edge_type: "auth"} | edges]
          else
            edges
          end

        edges =
          if service.certificate_id do
            [%{source: service.id, target: service.certificate_id, edge_type: "tls"} | edges]
          else
            edges
          end

        middleware_edges =
          (service.service_middlewares || [])
          |> Enum.map(fn sm ->
            %{source: service.id, target: sm.middleware_id, edge_type: "middleware"}
          end)

        edges ++ middleware_edges
      end)

    # Target edges: upstream_group -> targets (virtual edges using target IDs)
    target_edges =
      Enum.flat_map(upstream_groups, fn group ->
        (group.targets || [])
        |> Enum.map(fn t ->
          %{source: group.id, target: "target-#{t.id}", edge_type: "target"}
        end)
      end)

    service_edges ++ target_edges
  end

  defp resolve_records(%DiscoverySource{source_type: "kubernetes"} = source) do
    case Secrets.resolve_references(source.config || %{}, source.project_id) do
      {:ok, resolved_config} ->
        k8s_resolver().resolve_endpoints(resolved_config)

      {:error, reason} ->
        {:error, "Secret resolution failed: #{inspect(reason)}"}
    end
  end

  defp resolve_records(%DiscoverySource{} = source) do
    dns_resolver().resolve_srv(source.hostname)
  end

  defp dns_resolver do
    Application.get_env(:sentinel_cp, :dns_resolver, SentinelCp.Services.DnsResolver.Inet)
  end

  defp k8s_resolver do
    Application.get_env(:sentinel_cp, :k8s_resolver, SentinelCp.Services.K8sResolver.HTTP)
  end

  defp resolve_auth_policy_id(%{security_refs: refs}, policy_map) when is_list(refs) do
    Enum.find_value(refs, fn ref -> Map.get(policy_map, ref) end)
  end

  defp resolve_auth_policy_id(_, _), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
