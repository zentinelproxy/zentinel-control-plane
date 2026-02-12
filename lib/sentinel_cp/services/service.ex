defmodule SentinelCp.Services.Service do
  @moduledoc """
  Service schema representing a proxy service (route + upstream + policies).

  Each service maps to a `route` block in generated KDL configuration.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "services" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :enabled, :boolean, default: true
    field :position, :integer, default: 0
    field :route_path, :string
    field :upstream_url, :string
    field :respond_status, :integer
    field :respond_body, :string
    field :timeout_seconds, :integer
    field :retry, :map, default: %{}
    field :cache, :map, default: %{}
    field :rate_limit, :map, default: %{}
    field :health_check, :map, default: %{}
    field :headers, :map, default: %{}
    field :cors, :map, default: %{}
    field :access_control, :map, default: %{}
    field :compression, :map, default: %{}
    field :path_rewrite, :map, default: %{}
    field :security, :map, default: %{}
    field :request_transform, :map, default: %{}
    field :response_transform, :map, default: %{}
    field :redirect_url, :string

    belongs_to :project, SentinelCp.Projects.Project
    belongs_to :upstream_group, SentinelCp.Services.UpstreamGroup
    belongs_to :certificate, SentinelCp.Services.Certificate
    belongs_to :auth_policy, SentinelCp.Services.AuthPolicy

    timestamps(type: :utc_datetime)
  end

  def create_changeset(service, attrs) do
    service
    |> cast(attrs, [
      :name,
      :description,
      :enabled,
      :position,
      :route_path,
      :upstream_url,
      :respond_status,
      :respond_body,
      :timeout_seconds,
      :retry,
      :cache,
      :rate_limit,
      :health_check,
      :headers,
      :cors,
      :access_control,
      :compression,
      :path_rewrite,
      :security,
      :request_transform,
      :response_transform,
      :redirect_url,
      :upstream_group_id,
      :certificate_id,
      :auth_policy_id,
      :project_id
    ])
    |> validate_required([:name, :route_path, :project_id])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_route_path()
    |> validate_route_type()
    |> generate_slug()
    |> validate_slug()
    |> unique_constraint([:project_id, :slug], error_key: :slug)
    |> foreign_key_constraint(:project_id)
  end

  def update_changeset(service, attrs) do
    service
    |> cast(attrs, [
      :name,
      :description,
      :enabled,
      :position,
      :route_path,
      :upstream_url,
      :respond_status,
      :respond_body,
      :timeout_seconds,
      :retry,
      :cache,
      :rate_limit,
      :health_check,
      :headers,
      :cors,
      :access_control,
      :compression,
      :path_rewrite,
      :security,
      :request_transform,
      :response_transform,
      :redirect_url,
      :upstream_group_id,
      :certificate_id,
      :auth_policy_id
    ])
    |> validate_required([:name, :route_path])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_route_path()
    |> validate_route_type()
  end

  defp validate_route_path(changeset) do
    validate_format(changeset, :route_path, ~r/^\//, message: "must start with /")
  end

  defp validate_route_type(changeset) do
    upstream = get_field(changeset, :upstream_url)
    respond_status = get_field(changeset, :respond_status)
    redirect_url = get_field(changeset, :redirect_url)
    upstream_group_id = get_field(changeset, :upstream_group_id)

    set_count =
      [present?(upstream), present?(respond_status), present?(redirect_url), present?(upstream_group_id)]
      |> Enum.count(& &1)

    cond do
      set_count > 1 ->
        add_error(
          changeset,
          :upstream_url,
          "must set exactly one of upstream_url, respond_status, redirect_url, or upstream_group_id"
        )

      set_count == 0 ->
        add_error(
          changeset,
          :upstream_url,
          "must set either upstream_url, respond_status, redirect_url, or upstream_group_id"
        )

      true ->
        changeset
    end
  end

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_), do: true

  defp generate_slug(changeset) do
    case get_change(changeset, :name) do
      nil ->
        changeset

      name ->
        slug =
          name
          |> String.downcase()
          |> String.replace(~r/[^a-z0-9]+/, "-")
          |> String.replace(~r/^-+|-+$/, "")
          |> String.slice(0, 50)

        put_change(changeset, :slug, slug)
    end
  end

  defp validate_slug(changeset) do
    changeset
    |> validate_required([:slug])
    |> validate_format(:slug, ~r/^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$/,
      message: "must contain only lowercase letters, numbers, and hyphens"
    )
    |> validate_length(:slug, min: 1, max: 50)
  end
end
