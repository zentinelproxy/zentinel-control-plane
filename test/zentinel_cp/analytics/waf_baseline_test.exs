defmodule ZentinelCp.Analytics.WafBaselineTest do
  use ZentinelCp.DataCase

  alias ZentinelCp.Analytics
  alias ZentinelCp.Analytics.WafBaseline

  defp create_project(_) do
    {:ok, org} = ZentinelCp.Orgs.create_org(%{name: "BL Org", slug: "bl-org"})

    {:ok, project} =
      ZentinelCp.Projects.create_project(%{name: "BL Project", slug: "bl-proj", org_id: org.id})

    %{project: project}
  end

  describe "changeset/2" do
    setup [:create_project]

    test "valid changeset", %{project: project} do
      cs =
        WafBaseline.changeset(%WafBaseline{}, %{
          project_id: project.id,
          metric_type: "total_blocks",
          period: "hourly",
          mean: 10.5,
          stddev: 3.2,
          sample_count: 168
        })

      assert cs.valid?
    end

    test "validates metric_type", %{project: project} do
      cs =
        WafBaseline.changeset(%WafBaseline{}, %{
          project_id: project.id,
          metric_type: "invalid_metric",
          period: "hourly"
        })

      refute cs.valid?
      assert errors_on(cs)[:metric_type]
    end

    test "validates period", %{project: project} do
      cs =
        WafBaseline.changeset(%WafBaseline{}, %{
          project_id: project.id,
          metric_type: "total_blocks",
          period: "weekly"
        })

      refute cs.valid?
      assert errors_on(cs)[:period]
    end
  end

  describe "CRUD" do
    setup [:create_project]

    test "upsert_waf_baseline/1 creates and updates", %{project: project} do
      attrs = %{
        project_id: project.id,
        metric_type: "total_blocks",
        period: "hourly",
        mean: 10.0,
        stddev: 3.0,
        sample_count: 100,
        last_computed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      {:ok, baseline} = Analytics.upsert_waf_baseline(attrs)
      assert baseline.mean == 10.0

      baselines = Analytics.get_waf_baselines(project.id)
      assert length(baselines) == 1
    end
  end
end
