defmodule ZentinelCp.Events.NotificationRule do
  @moduledoc """
  Schema for rules that map event patterns to notification channels.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "notification_rules" do
    field :name, :string
    field :event_pattern, :string
    field :enabled, :boolean, default: true
    field :filter, :map, default: %{}

    belongs_to :project, ZentinelCp.Projects.Project
    belongs_to :channel, ZentinelCp.Events.Channel

    timestamps(type: :utc_datetime)
  end

  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [:project_id, :name, :event_pattern, :channel_id, :enabled, :filter])
    |> validate_required([:project_id, :name, :event_pattern, :channel_id])
    |> validate_event_pattern()
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:channel_id)
  end

  defp validate_event_pattern(changeset) do
    validate_change(changeset, :event_pattern, fn :event_pattern, pattern ->
      if valid_pattern?(pattern) do
        []
      else
        [event_pattern: "must be a valid event pattern (e.g., 'rollout.*', 'bundle.created')"]
      end
    end)
  end

  defp valid_pattern?(pattern) do
    # Patterns like "rollout.*", "bundle.created", "*"
    Regex.match?(~r/^(\*|[a-z]+(\.[a-z_*]+)*)$/, pattern)
  end
end
