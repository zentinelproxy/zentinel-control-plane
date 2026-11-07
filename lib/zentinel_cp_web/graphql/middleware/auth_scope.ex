defmodule ZentinelCpWeb.GraphQL.Middleware.AuthScope do
  @moduledoc """
  Enforces API key scope and project access on GraphQL fields.

  Root fields are denied unless listed here, so a new field cannot be left open
  by accident. Listing also tells this module how to find the field's project.
  """
  @behaviour Absinthe.Middleware

  alias ZentinelCp.{Access, Rollouts}

  # {required scope, where the project comes from}
  @root_fields %{
    project: {"services:read", :resolver},
    projects: {"services:read", :resolver},
    services: {"services:read", :project_arg},
    alert_rules: {"services:read", :project_arg},
    slos: {"services:read", :project_arg},
    policies: {"services:read", :project_arg},
    nodes: {"nodes:read", :project_arg},
    bundles: {"bundles:read", :project_arg},
    rollouts: {"rollouts:read", :project_arg},
    create_bundle: {"bundles:write", :project_input},
    create_rollout: {"rollouts:write", :project_input},
    pause_rollout: {"rollouts:write", :rollout_arg},
    resume_rollout: {"rollouts:write", :rollout_arg},
    swap_blue_green_slot: {"rollouts:write", :rollout_arg},
    advance_blue_green_traffic: {"rollouts:write", :rollout_arg}
  }

  @nested_fields %{
    services: "services:read",
    nodes: "nodes:read",
    bundles: "bundles:read",
    rollouts: "rollouts:read"
  }

  @impl true
  def call(%{context: context} = resolution, :root) do
    api_key = context[:current_api_key]
    field = resolution.definition.schema_node.identifier

    case Map.get(@root_fields, field) do
      nil ->
        deny(resolution, "Not authorized")

      {scope, source} ->
        cond do
          is_nil(api_key) or not Access.scope_held?(api_key, scope) ->
            deny(resolution, "Insufficient scope. Required: #{scope}")

          source == :resolver ->
            resolution

          Access.api_key_allowed?(api_key, project_id(source, resolution.arguments), scope) ->
            resolution

          true ->
            deny(resolution, "Not found")
        end
    end
  end

  def call(%{context: context} = resolution, :nested) do
    field = resolution.definition.schema_node.identifier

    case Map.get(@nested_fields, field) do
      nil ->
        resolution

      scope ->
        if Access.api_key_allowed?(context[:current_api_key], resolution.source, scope),
          do: resolution,
          else: deny(resolution, "Insufficient scope. Required: #{scope}")
    end
  end

  defp project_id(:project_arg, arguments), do: arguments[:project_id]
  defp project_id(:project_input, arguments), do: get_in(arguments, [:input, :project_id])

  defp project_id(:rollout_arg, arguments) do
    case Rollouts.get_rollout(arguments[:id]) do
      nil -> nil
      rollout -> rollout.project_id
    end
  end

  defp deny(resolution, message) do
    Absinthe.Resolution.put_result(resolution, {:error, message})
  end
end
