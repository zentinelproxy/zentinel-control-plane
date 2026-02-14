defmodule SentinelCpWeb.GraphQL.Middleware.AuthScope do
  @moduledoc """
  Absinthe middleware that enforces API key scope checks on GraphQL fields.
  """
  @behaviour Absinthe.Middleware

  @scope_map %{
    # Queries
    project: "services:read",
    projects: "services:read",
    services: "services:read",
    alert_rules: "services:read",
    slos: "services:read",
    policies: "services:read",
    nodes: "nodes:read",
    bundles: "bundles:read",
    rollouts: "rollouts:read",
    # Mutations
    create_bundle: "bundles:write",
    create_rollout: "rollouts:write",
    pause_rollout: "rollouts:write",
    resume_rollout: "rollouts:write"
  }

  @impl true
  def call(%{context: context} = resolution, _config) do
    api_key = context[:current_api_key]
    field = resolution.definition.schema_node.identifier

    required_scope = Map.get(@scope_map, field)

    cond do
      # No scope mapping means no restriction
      is_nil(required_scope) ->
        resolution

      # Legacy keys with empty scopes get full access
      api_key && api_key.scopes == [] ->
        resolution

      # Check if the key has the required scope
      api_key && required_scope in api_key.scopes ->
        resolution

      true ->
        Absinthe.Resolution.put_result(
          resolution,
          {:error, "Insufficient scope. Required: #{required_scope}"}
        )
    end
  end
end
