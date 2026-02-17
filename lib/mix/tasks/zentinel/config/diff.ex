defmodule Mix.Tasks.Zentinel.Config.Diff do
  @moduledoc """
  Shows the diff between a project's current configuration and a config file.

  ## Usage

      mix zentinel.config.diff <project_slug> <file>

  ## Examples

      mix zentinel.config.diff my-project config.yaml
      mix zentinel.config.diff my-project config.json
  """

  use Mix.Task

  @shortdoc "Diff project configuration against a file"

  @impl Mix.Task
  def run(args) do
    {_opts, argv, _} = OptionParser.parse(args, switches: [])

    case argv do
      [slug, file] ->
        Mix.Task.run("app.start")
        diff(slug, file)

      _ ->
        Mix.shell().error("Usage: mix zentinel.config.diff <project_slug> <file>")
        exit({:shutdown, 1})
    end
  end

  defp diff(slug, file) do
    project = resolve_project!(slug)
    config = parse_config_file!(file)

    {:ok, changes} = ZentinelCp.ConfigExport.diff(project.id, config)

    case changes do
      [] ->
        Mix.shell().info("No differences found.")

      changes ->
        Mix.shell().info("Differences:\n")

        for {action, resource_type, name} <- changes do
          line =
            case action do
              :add -> IO.ANSI.format([:green, "  + #{resource_type}: #{name}"])
              :remove -> IO.ANSI.format([:red, "  - #{resource_type}: #{name}"])
              :modify -> IO.ANSI.format([:yellow, "  ~ #{resource_type}: #{name}"])
            end

          Mix.shell().info(line)
        end

        additions = Enum.count(changes, fn {a, _, _} -> a == :add end)
        removals = Enum.count(changes, fn {a, _, _} -> a == :remove end)
        modifications = Enum.count(changes, fn {a, _, _} -> a == :modify end)

        Mix.shell().info(
          "\n#{additions} addition(s), #{removals} removal(s), #{modifications} modification(s)"
        )
    end
  end

  defp resolve_project!(slug) do
    case ZentinelCp.Projects.get_project_by_slug(slug) do
      nil ->
        Mix.shell().error("Project not found: #{slug}")
        exit({:shutdown, 1})

      project ->
        project
    end
  end

  defp parse_config_file!(path) do
    unless File.exists?(path) do
      Mix.shell().error("File not found: #{path}")
      exit({:shutdown, 1})
    end

    content = File.read!(path)

    cond do
      String.ends_with?(path, [".yml", ".yaml"]) ->
        case YamlElixir.read_from_string(content) do
          {:ok, parsed} ->
            parsed

          {:error, reason} ->
            Mix.shell().error("Failed to parse YAML: #{inspect(reason)}")
            exit({:shutdown, 1})
        end

      String.ends_with?(path, ".json") ->
        case Jason.decode(content) do
          {:ok, parsed} ->
            parsed

          {:error, reason} ->
            Mix.shell().error("Failed to parse JSON: #{inspect(reason)}")
            exit({:shutdown, 1})
        end

      true ->
        case YamlElixir.read_from_string(content) do
          {:ok, parsed} ->
            parsed

          {:error, _} ->
            case Jason.decode(content) do
              {:ok, parsed} ->
                parsed

              {:error, _} ->
                Mix.shell().error("Unable to parse file as YAML or JSON: #{path}")
                exit({:shutdown, 1})
            end
        end
    end
  end
end
