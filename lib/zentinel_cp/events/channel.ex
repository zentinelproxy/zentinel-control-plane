defmodule ZentinelCp.Events.Channel do
  @moduledoc """
  Schema for notification delivery channels.
  Supports Slack, PagerDuty, Email, Microsoft Teams, and generic webhooks.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @channel_types ~w(slack pagerduty email teams webhook)

  schema "notification_channels" do
    field :name, :string
    field :type, :string
    field :config, :map, default: %{}
    field :enabled, :boolean, default: true
    field :signing_secret, :string

    belongs_to :project, ZentinelCp.Projects.Project

    timestamps(type: :utc_datetime)
  end

  def changeset(channel, attrs) do
    channel
    |> cast(attrs, [:project_id, :name, :type, :config, :enabled, :signing_secret])
    |> validate_required([:project_id, :name, :type, :config])
    |> validate_inclusion(:type, @channel_types)
    |> validate_channel_config()
    |> maybe_generate_signing_secret()
    |> unique_constraint([:project_id, :name])
    |> foreign_key_constraint(:project_id)
  end

  defp validate_channel_config(changeset) do
    validate_change(changeset, :config, fn :config, config ->
      type = get_field(changeset, :type)
      validate_config_for_type(type, config)
    end)
  end

  defp validate_config_for_type("slack", config) do
    if Map.has_key?(config, "webhook_url") or Map.has_key?(config, :webhook_url) do
      []
    else
      [config: "slack channel requires webhook_url"]
    end
  end

  defp validate_config_for_type("pagerduty", config) do
    if Map.has_key?(config, "routing_key") or Map.has_key?(config, :routing_key) do
      []
    else
      [config: "pagerduty channel requires routing_key"]
    end
  end

  defp validate_config_for_type("email", config) do
    if Map.has_key?(config, "to") or Map.has_key?(config, :to) do
      []
    else
      [config: "email channel requires 'to' address"]
    end
  end

  defp validate_config_for_type("teams", config) do
    if Map.has_key?(config, "webhook_url") or Map.has_key?(config, :webhook_url) do
      []
    else
      [config: "teams channel requires webhook_url"]
    end
  end

  defp validate_config_for_type("webhook", config) do
    if Map.has_key?(config, "url") or Map.has_key?(config, :url) do
      []
    else
      [config: "webhook channel requires url"]
    end
  end

  defp validate_config_for_type(_, _), do: []

  defp maybe_generate_signing_secret(changeset) do
    if get_field(changeset, :signing_secret) do
      changeset
    else
      put_change(changeset, :signing_secret, generate_signing_secret())
    end
  end

  defp generate_signing_secret do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  def types, do: @channel_types
end
