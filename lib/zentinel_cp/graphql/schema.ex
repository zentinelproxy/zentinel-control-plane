defmodule ZentinelCp.GraphQL.Schema do
  @moduledoc """
  GraphQL schema definition for the Zentinel Control Plane API.

  Provides type definitions and resolvers for all major resources.
  Ready for Absinthe integration when the dep is added.

  ## Resource Types
  - Project, Service, UpstreamGroup, Certificate
  - Bundle, Rollout, Node
  - AlertRule, Slo, Policy
  - Event, AuditLog

  ## Query Example (when Absinthe is wired up)
  ```graphql
  query {
    project(slug: "my-project") {
      name
      services { name routePath }
      bundles(limit: 5) { version status }
      nodes { hostname status }
    }
  }
  ```
  """

  @doc """
  Returns the GraphQL type definitions as a map.
  Used for schema introspection and documentation generation.
  """
  def type_definitions do
    %{
      query: %{
        project: %{
          args: %{id: :id, slug: :string},
          type: :project,
          resolver: {ZentinelCp.Projects, :get_project_by_slug}
        },
        projects: %{
          args: %{org_id: :id},
          type: [:project],
          resolver: {ZentinelCp.Projects, :list_projects}
        },
        services: %{
          args: %{project_id: :id},
          type: [:service],
          resolver: {ZentinelCp.Services, :list_services}
        },
        nodes: %{
          args: %{project_id: :id},
          type: [:node],
          resolver: {ZentinelCp.Nodes, :list_nodes}
        },
        bundles: %{
          args: %{project_id: :id, limit: :integer},
          type: [:bundle],
          resolver: {ZentinelCp.Bundles, :list_bundles}
        },
        rollouts: %{
          args: %{project_id: :id},
          type: [:rollout],
          resolver: {ZentinelCp.Rollouts, :list_rollouts}
        },
        alert_rules: %{
          args: %{project_id: :id},
          type: [:alert_rule],
          resolver: {ZentinelCp.Observability, :list_alert_rules}
        },
        slos: %{
          args: %{project_id: :id},
          type: [:slo],
          resolver: {ZentinelCp.Observability, :list_slos}
        },
        policies: %{
          args: %{project_id: :id},
          type: [:policy],
          resolver: {ZentinelCp.Policies, :list_policies}
        }
      },
      mutation: %{
        create_rollout: %{
          args: %{
            project_id: :id,
            bundle_id: :id,
            strategy: :string,
            target_selector: :json
          },
          type: :rollout,
          resolver: {ZentinelCp.Rollouts, :create_rollout}
        },
        pause_rollout: %{
          args: %{id: :id},
          type: :rollout,
          resolver: {ZentinelCp.Rollouts, :pause_rollout}
        },
        resume_rollout: %{
          args: %{id: :id},
          type: :rollout,
          resolver: {ZentinelCp.Rollouts, :resume_rollout}
        },
        create_bundle: %{
          args: %{project_id: :id, config_source: :string, version: :string},
          type: :bundle,
          resolver: {ZentinelCp.Bundles, :create_bundle}
        }
      },
      subscription: %{
        rollout_progress: %{
          args: %{rollout_id: :id},
          type: :rollout,
          topic: "rollout:*"
        },
        node_status: %{
          args: %{project_id: :id},
          type: :node,
          topic: "nodes:*"
        },
        alert_state: %{
          args: %{project_id: :id},
          type: :alert_state,
          topic: "alerts:*"
        }
      },
      types: %{
        project: [:id, :name, :slug, :description, :settings, :inserted_at],
        service: [:id, :name, :slug, :route_path, :upstream_url, :enabled, :position],
        node: [:id, :hostname, :status, :labels, :last_heartbeat_at],
        bundle: [:id, :version, :status, :sha256, :size_bytes, :inserted_at],
        rollout: [:id, :state, :strategy, :progress, :target_selector, :inserted_at],
        alert_rule: [:id, :name, :rule_type, :condition, :severity, :enabled],
        alert_state: [:id, :state, :value, :started_at, :firing_at, :resolved_at],
        slo: [:id, :name, :sli_type, :target, :burn_rate, :error_budget_remaining],
        policy: [:id, :name, :policy_type, :expression, :enforcement, :enabled]
      }
    }
  end

  @doc """
  Returns the list of supported query fields.
  """
  def query_fields, do: Map.keys(type_definitions().query)

  @doc """
  Returns the list of supported mutation fields.
  """
  def mutation_fields, do: Map.keys(type_definitions().mutation)

  @doc """
  Returns the list of supported subscription fields.
  """
  def subscription_fields, do: Map.keys(type_definitions().subscription)

  @doc """
  Returns all defined type names.
  """
  def type_names, do: Map.keys(type_definitions().types)
end
