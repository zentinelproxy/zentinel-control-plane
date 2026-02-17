defmodule Mix.Tasks.Zentinel.Config.Apply do
  @moduledoc """
  Applies a configuration file to a project, creating or updating resources.

  ## Usage

      mix zentinel.config.apply <project_slug> <file> [options]

  ## Options

    * `--dry-run` - Show diff without applying changes
    * `--yes` - Skip confirmation prompt

  ## Examples

      mix zentinel.config.apply my-project config.yaml
      mix zentinel.config.apply my-project config.json --yes
      mix zentinel.config.apply my-project config.yaml --dry-run
  """

  use Mix.Task

  @shortdoc "Apply a configuration file to a project"

  @switches [dry_run: :boolean, yes: :boolean]
  @aliases [y: :yes]

  @impl Mix.Task
  def run(args) do
    {opts, argv, _} = OptionParser.parse(args, switches: @switches, aliases: @aliases)

    case argv do
      [slug, file] ->
        Mix.Task.run("app.start")
        apply_config(slug, file, opts)

      _ ->
        Mix.shell().error(
          "Usage: mix zentinel.config.apply <project_slug> <file> [--dry-run] [--yes]"
        )

        exit({:shutdown, 1})
    end
  end

  defp apply_config(slug, file, opts) do
    project = resolve_project!(slug)
    config = parse_config_file!(file)

    {:ok, changes} = ZentinelCp.ConfigExport.diff(project.id, config)

    case changes do
      [] ->
        Mix.shell().info("No changes detected.")

      changes ->
        print_changes(changes)

        if Keyword.get(opts, :dry_run, false) do
          Mix.shell().info("\nDry run — no changes applied.")
        else
          if Keyword.get(opts, :yes, false) || confirm?() do
            do_apply(project, config)
          else
            Mix.shell().info("Aborted.")
          end
        end
    end
  end

  defp do_apply(project, config) do
    {:ok, summary} = ZentinelCp.ConfigExport.import_config(project.id, config)

    Mix.shell().info("\nApplied successfully:")
    Mix.shell().info("  Created: #{summary.created}")
    Mix.shell().info("  Updated: #{summary.updated}")
    Mix.shell().info("  Skipped: #{summary.skipped}")

    if summary.errors != [] do
      Mix.shell().error("  Errors:  #{length(summary.errors)}")

      for {type, name, reason} <- summary.errors do
        Mix.shell().error("    #{type} #{name}: #{inspect(reason)}")
      end
    end
  end

  defp print_changes(changes) do
    Mix.shell().info("Changes detected:\n")

    for {action, resource_type, name} <- changes do
      prefix =
        case action do
          :add -> "  + "
          :remove -> "  - "
          :modify -> "  ~ "
        end

      Mix.shell().info("#{prefix}#{resource_type}: #{name}")
    end
  end

  defp confirm? do
    Mix.shell().yes?("\nApply these changes?")
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
        # Try YAML first, fall back to JSON
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
