defmodule Mix.Tasks.Zentinel.ConfigTest do
  use ZentinelCp.DataCase, async: false

  import ZentinelCp.ProjectsFixtures

  alias ZentinelCp.Repo

  setup do
    project = project_fixture()
    %{project: project}
  end

  # ─── Export ──────────────────────────────────────────────────

  describe "zentinel.config.export" do
    test "exports valid YAML for a project", %{project: project} do
      create_environment(project, "staging")
      create_service(project, "api", "/api")

      output =
        capture_io(fn ->
          Mix.Tasks.Zentinel.Config.Export.run([project.slug])
        end)

      assert output =~ "version"
      assert output =~ project.name
      {:ok, parsed} = YamlElixir.read_from_string(output)
      assert parsed["version"] == "1.0"
      assert parsed["project"]["slug"] == project.slug
    end

    test "exports valid JSON with --format json", %{project: project} do
      create_service(project, "web", "/web")

      output =
        capture_io(fn ->
          Mix.Tasks.Zentinel.Config.Export.run([project.slug, "--format", "json"])
        end)

      assert {:ok, parsed} = Jason.decode(output)
      assert parsed["version"] == "1.0"
      assert length(parsed["services"]) == 1
    end

    test "exports to file with --output", %{project: project} do
      path =
        Path.join(System.tmp_dir!(), "test_export_#{System.unique_integer([:positive])}.yaml")

      on_exit(fn -> File.rm(path) end)

      capture_io(fn ->
        Mix.Tasks.Zentinel.Config.Export.run([project.slug, "--output", path])
      end)

      assert File.exists?(path)
      content = File.read!(path)
      {:ok, parsed} = YamlElixir.read_from_string(content)
      assert parsed["version"] == "1.0"
    end

    test "errors for missing project" do
      assert catch_exit(
               capture_io(fn ->
                 Mix.Tasks.Zentinel.Config.Export.run(["nonexistent-project"])
               end)
             ) == {:shutdown, 1}
    end
  end

  # ─── Apply ──────────────────────────────────────────────────

  describe "zentinel.config.apply" do
    test "creates resources from a config file", %{project: project} do
      config = %{
        "version" => "1.0",
        "environments" => [
          %{"name" => "staging"},
          %{"name" => "production"}
        ],
        "upstream_groups" => [],
        "services" => []
      }

      path = write_temp_json(config)
      on_exit(fn -> File.rm(path) end)

      output =
        capture_io(fn ->
          Mix.Tasks.Zentinel.Config.Apply.run([project.slug, path, "--yes"])
        end)

      assert output =~ "Created: 2"
      assert output =~ "Skipped: 0"
    end

    test "shows diff without modifying with --dry-run", %{project: project} do
      config = %{
        "environments" => [%{"name" => "new-env"}],
        "upstream_groups" => [],
        "services" => []
      }

      path = write_temp_json(config)
      on_exit(fn -> File.rm(path) end)

      output =
        capture_io(fn ->
          Mix.Tasks.Zentinel.Config.Apply.run([project.slug, path, "--dry-run"])
        end)

      assert output =~ "Dry run"
      assert output =~ "environment: new-env"

      # Verify nothing was actually created
      envs = Repo.all(ZentinelCp.Projects.Environment)
      env_names = Enum.map(envs, & &1.name)
      refute "new-env" in env_names
    end

    test "errors for missing file", %{project: project} do
      assert catch_exit(
               capture_io(fn ->
                 Mix.Tasks.Zentinel.Config.Apply.run([
                   project.slug,
                   "/nonexistent/file.json",
                   "--yes"
                 ])
               end)
             ) == {:shutdown, 1}
    end
  end

  # ─── Diff ───────────────────────────────────────────────────

  describe "zentinel.config.diff" do
    test "shows additions", %{project: project} do
      config = %{
        "environments" => [%{"name" => "new-env"}],
        "upstream_groups" => [],
        "services" => [%{"name" => "new-svc", "route_path" => "/new"}]
      }

      path = write_temp_json(config)
      on_exit(fn -> File.rm(path) end)

      output =
        capture_io(fn ->
          Mix.Tasks.Zentinel.Config.Diff.run([project.slug, path])
        end)

      assert output =~ "+ environment: new-env"
      assert output =~ "+ service: new-svc"
      assert output =~ "addition(s)"
    end

    test "shows removals", %{project: project} do
      create_environment(project, "old-env")

      config = %{
        "environments" => [],
        "upstream_groups" => [],
        "services" => []
      }

      path = write_temp_json(config)
      on_exit(fn -> File.rm(path) end)

      output =
        capture_io(fn ->
          Mix.Tasks.Zentinel.Config.Diff.run([project.slug, path])
        end)

      assert output =~ "- environment: old-env"
      assert output =~ "removal(s)"
    end

    test "shows no differences for matching config", %{project: project} do
      {:ok, current} = ZentinelCp.ConfigExport.export(project.id)

      path = write_temp_json(current)
      on_exit(fn -> File.rm(path) end)

      output =
        capture_io(fn ->
          Mix.Tasks.Zentinel.Config.Diff.run([project.slug, path])
        end)

      assert output =~ "No differences found"
    end

    test "errors for missing project" do
      path = write_temp_json(%{"environments" => []})
      on_exit(fn -> File.rm(path) end)

      assert catch_exit(
               capture_io(fn ->
                 Mix.Tasks.Zentinel.Config.Diff.run(["nonexistent-project", path])
               end)
             ) == {:shutdown, 1}
    end
  end

  # ─── Helpers ────────────────────────────────────────────────

  defp capture_io(fun) do
    ExUnit.CaptureIO.capture_io(fun)
  end

  defp create_service(project, name, route_path) do
    {:ok, service} =
      %ZentinelCp.Services.Service{}
      |> Ecto.Changeset.change(%{
        project_id: project.id,
        name: name,
        slug: name,
        route_path: route_path
      })
      |> Repo.insert()

    service
  end

  defp create_environment(project, name) do
    {:ok, env} =
      %ZentinelCp.Projects.Environment{}
      |> ZentinelCp.Projects.Environment.create_changeset(%{
        project_id: project.id,
        name: name
      })
      |> Repo.insert()

    env
  end

  defp write_temp_json(data) do
    path = Path.join(System.tmp_dir!(), "test_config_#{System.unique_integer([:positive])}.json")
    File.write!(path, Jason.encode!(data))
    path
  end
end
