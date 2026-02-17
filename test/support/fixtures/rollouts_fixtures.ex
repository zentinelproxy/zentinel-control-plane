defmodule ZentinelCp.RolloutsFixtures do
  @moduledoc """
  Test helpers for creating Rollouts entities.
  """

  alias ZentinelCp.{Rollouts, Bundles}

  @valid_kdl """
  system {
    workers 4
  }
  listeners {
    listener "http" address="0.0.0.0:8080"
  }
  """

  def compiled_bundle_fixture(attrs \\ %{}) do
    project = attrs[:project] || ZentinelCp.ProjectsFixtures.project_fixture()

    {:ok, bundle} =
      Bundles.create_bundle(%{
        project_id: project.id,
        version: attrs[:version] || "1.0.#{System.unique_integer([:positive])}",
        config_source: attrs[:config_source] || @valid_kdl
      })

    # Force status to compiled (compile worker may fail in test without zentinel binary)
    {:ok, bundle} = Bundles.update_status(bundle, "compiled")
    bundle
  end

  def rollout_fixture(attrs \\ %{}) do
    project = attrs[:project] || ZentinelCp.ProjectsFixtures.project_fixture()
    bundle = attrs[:bundle] || compiled_bundle_fixture(%{project: project})

    create_attrs =
      %{
        project_id: project.id,
        bundle_id: bundle.id,
        target_selector: attrs[:target_selector] || %{"type" => "all"},
        strategy: attrs[:strategy] || "rolling",
        batch_size: attrs[:batch_size] || 1,
        progress_deadline_seconds: attrs[:progress_deadline_seconds] || 600
      }
      |> maybe_put(:max_unavailable, attrs[:max_unavailable])
      |> maybe_put(:health_gates, attrs[:health_gates])
      |> maybe_put(:created_by_id, attrs[:created_by_id])
      |> maybe_put(:canary_analysis_config, attrs[:canary_analysis_config])
      |> maybe_put(:blue_green_config, attrs[:blue_green_config])
      |> maybe_put(:auto_rollback, attrs[:auto_rollback])
      |> maybe_put(:rollback_threshold, attrs[:rollback_threshold])
      |> maybe_put(:validation_period_seconds, attrs[:validation_period_seconds])

    {:ok, rollout} = Rollouts.create_rollout(create_attrs)

    rollout
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
