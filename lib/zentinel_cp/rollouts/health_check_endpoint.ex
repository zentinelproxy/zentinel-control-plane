defmodule ZentinelCp.Rollouts.HealthCheckEndpoint do
  @moduledoc """
  Schema for custom health check endpoints.

  Health check endpoints are called during the rollout verification phase
  to validate that the deployment is healthy beyond the standard metrics.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @methods ~w(GET POST HEAD)

  schema "health_check_endpoints" do
    field :name, :string
    field :url, :string
    field :method, :string, default: "GET"
    field :timeout_ms, :integer, default: 5000
    field :expected_status, :integer, default: 200
    field :expected_body_contains, :string
    field :headers, :map, default: %{}
    field :enabled, :boolean, default: true

    belongs_to :project, ZentinelCp.Projects.Project

    timestamps(type: :utc_datetime)
  end

  @doc """
  Returns the list of valid HTTP methods.
  """
  def methods, do: @methods

  @doc """
  Changeset for creating a health check endpoint.
  """
  def create_changeset(endpoint, attrs) do
    endpoint
    |> cast(attrs, [
      :name,
      :url,
      :method,
      :timeout_ms,
      :expected_status,
      :expected_body_contains,
      :headers,
      :enabled,
      :project_id
    ])
    |> validate_required([:name, :url, :project_id])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_url(:url)
    |> validate_inclusion(:method, @methods)
    |> validate_number(:timeout_ms, greater_than: 0, less_than_or_equal_to: 60_000)
    |> validate_number(:expected_status, greater_than_or_equal_to: 100, less_than: 600)
    |> foreign_key_constraint(:project_id)
  end

  @doc """
  Changeset for updating a health check endpoint.
  """
  def update_changeset(endpoint, attrs) do
    endpoint
    |> cast(attrs, [
      :name,
      :url,
      :method,
      :timeout_ms,
      :expected_status,
      :expected_body_contains,
      :headers,
      :enabled
    ])
    |> validate_required([:name, :url])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_url(:url)
    |> validate_inclusion(:method, @methods)
    |> validate_number(:timeout_ms, greater_than: 0, less_than_or_equal_to: 60_000)
    |> validate_number(:expected_status, greater_than_or_equal_to: 100, less_than: 600)
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn _, url ->
      case URI.parse(url) do
        %URI{scheme: scheme, host: host}
        when scheme in ["http", "https"] and is_binary(host) and host != "" ->
          []

        _ ->
          [{field, "must be a valid HTTP(S) URL"}]
      end
    end)
  end
end
