defmodule SentinelCpWeb.GraphQL.Resolvers.Bundles do
  @moduledoc false
  alias SentinelCp.Audit
  alias SentinelCp.Bundles

  def list(_parent, %{project_id: project_id} = args, _resolution) do
    opts = if args[:limit], do: [limit: args[:limit]], else: []
    {:ok, Bundles.list_bundles(project_id, opts)}
  end

  def list_for_project(project, args, _resolution) do
    opts = if args[:limit], do: [limit: args[:limit]], else: []
    {:ok, Bundles.list_bundles(project.id, opts)}
  end

  def create(_parent, %{input: input}, %{context: context}) do
    case Bundles.create_bundle(input) do
      {:ok, bundle} ->
        if api_key = context[:current_api_key] do
          Audit.log_api_key_action(api_key, "create", "bundle", bundle.id,
            project_id: bundle.project_id
          )
        end

        {:ok, bundle}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, format_errors(changeset)}

      {:error, reason} ->
        {:error, to_string(reason)}
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map_join("; ", fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
  end
end
