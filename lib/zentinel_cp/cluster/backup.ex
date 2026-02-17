defmodule ZentinelCp.Cluster.Backup do
  @moduledoc """
  Disaster recovery and backup utilities.

  Provides project export for reconstruction, runbook generation,
  and backup status tracking.
  """

  import Ecto.Query, warn: false
  alias ZentinelCp.Repo

  @doc """
  Generates a full system inventory for disaster recovery runbooks.
  Returns a map containing the current system state overview.
  """
  def system_inventory do
    %{
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      projects: count_resource("projects"),
      services: count_resource("services"),
      nodes: count_resource("nodes"),
      bundles: count_resource("bundles"),
      active_rollouts: count_active_rollouts(),
      environments: count_resource("environments"),
      upstream_groups: count_resource("upstream_groups"),
      policies: count_resource("policies"),
      slos: count_resource("slos"),
      alert_rules: count_resource("alert_rules"),
      federation_peers: count_resource("federation_peers"),
      cluster_info: ZentinelCp.Cluster.Health.cluster_info()
    }
  end

  @doc """
  Exports all project configurations for full system reconstruction.
  Returns a list of `{project_slug, config}` tuples.
  """
  def export_all_projects do
    from(p in ZentinelCp.Projects.Project, order_by: [asc: p.name])
    |> Repo.all()
    |> Enum.map(fn project ->
      case ZentinelCp.ConfigExport.export(project.id) do
        {:ok, config} -> {project.slug, config}
        _ -> {project.slug, %{error: "export failed"}}
      end
    end)
  end

  @doc """
  Generates a disaster recovery runbook based on current state.
  """
  def generate_runbook do
    inventory = system_inventory()

    """
    # Zentinel CP Disaster Recovery Runbook
    Generated: #{inventory.generated_at}

    ## System Overview
    - Projects: #{inventory.projects}
    - Services: #{inventory.services}
    - Nodes: #{inventory.nodes}
    - Active Rollouts: #{inventory.active_rollouts}
    - Environments: #{inventory.environments}

    ## Recovery Steps

    ### 1. Database Recovery
    - Restore PostgreSQL from latest backup
    - Verify data integrity: `mix ecto.migrate`
    - Check row counts match inventory above

    ### 2. Bundle Storage Recovery
    - Verify S3/MinIO bucket accessibility
    - Check bundle count matches: #{inventory.bundles}
    - Validate bundle signatures

    ### 3. Application Recovery
    - Deploy latest application release
    - Configure environment variables (DATABASE_URL, S3 credentials)
    - Start application: `mix phx.server`
    - Verify health endpoint: GET /health

    ### 4. Verification
    - Check all #{inventory.nodes} nodes reconnect
    - Verify active rollouts resume (#{inventory.active_rollouts} active)
    - Test API key authentication
    - Validate Oban job processing

    ## RTO/RPO Targets
    - RTO: 1 hour (application restore)
    - RPO: depends on backup frequency (recommend WAL archiving for near-zero)

    ## Cluster Information
    - Node: #{inspect(inventory.cluster_info.node)}
    - Cluster Size: #{inventory.cluster_info.cluster_size}
    - Uptime: #{inventory.cluster_info.uptime_seconds}s
    """
  end

  ## Private

  defp count_resource(table) do
    case Repo.query("SELECT COUNT(*) FROM #{table}") do
      {:ok, %{rows: [[count]]}} -> count
      _ -> 0
    end
  rescue
    _ -> 0
  end

  defp count_active_rollouts do
    case Repo.query(
           "SELECT COUNT(*) FROM rollouts WHERE state IN ('pending', 'in_progress', 'paused')"
         ) do
      {:ok, %{rows: [[count]]}} -> count
      _ -> 0
    end
  rescue
    _ -> 0
  end
end
