defmodule ZentinelCp.Analytics.WafEvent do
  @moduledoc """
  Schema for WAF (Web Application Firewall) security events.

  Stores blocked/logged/challenged requests detected by WAF rules.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @rule_types ~w(sqli xss rfi lfi rce scanner custom)
  @actions ~w(blocked logged challenged)
  @severities ~w(critical high medium low)

  schema "waf_events" do
    belongs_to :project, ZentinelCp.Projects.Project
    belongs_to :service, ZentinelCp.Services.Service
    belongs_to :node, ZentinelCp.Nodes.Node

    field :timestamp, :utc_datetime_usec
    field :rule_type, :string
    field :rule_id, :string
    field :action, :string
    field :severity, :string
    field :client_ip, :string
    field :method, :string
    field :path, :string
    field :matched_data, :string
    field :user_agent, :string
    field :geo_country, :string
    field :request_headers, :map, default: %{}
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :project_id,
      :service_id,
      :node_id,
      :timestamp,
      :rule_type,
      :rule_id,
      :action,
      :severity,
      :client_ip,
      :method,
      :path,
      :matched_data,
      :user_agent,
      :geo_country,
      :request_headers,
      :metadata
    ])
    |> validate_required([:project_id, :timestamp, :rule_type, :action])
    |> validate_inclusion(:rule_type, @rule_types)
    |> validate_inclusion(:action, @actions)
    |> validate_inclusion(:severity, @severities ++ [nil])
    |> foreign_key_constraint(:project_id)
  end

  def rule_types, do: @rule_types
  def actions, do: @actions
  def severities, do: @severities
end
