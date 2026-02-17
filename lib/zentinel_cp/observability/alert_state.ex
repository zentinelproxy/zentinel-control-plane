defmodule ZentinelCp.Observability.AlertState do
  @moduledoc """
  Schema for alert state tracking.

  Alert state machine: `inactive` → `pending` → `firing` → `resolved`

  - `inactive` — condition not met
  - `pending` — condition met but within `for_seconds` grace period
  - `firing` — condition persisted past grace period, notification sent
  - `resolved` — condition no longer met after firing
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @states ~w(inactive pending firing resolved)

  schema "alert_states" do
    field :state, :string, default: "inactive"
    field :value, :float
    field :started_at, :utc_datetime
    field :firing_at, :utc_datetime
    field :resolved_at, :utc_datetime
    field :acknowledged_by, :binary_id
    field :acknowledged_at, :utc_datetime
    field :notification_sent, :boolean, default: false
    field :fingerprint, :string

    belongs_to :alert_rule, ZentinelCp.Observability.AlertRule

    timestamps(type: :utc_datetime)
  end

  def changeset(state, attrs) do
    state
    |> cast(attrs, [
      :alert_rule_id,
      :state,
      :value,
      :started_at,
      :firing_at,
      :resolved_at,
      :acknowledged_by,
      :acknowledged_at,
      :notification_sent,
      :fingerprint
    ])
    |> validate_required([:alert_rule_id, :state])
    |> validate_inclusion(:state, @states)
    |> foreign_key_constraint(:alert_rule_id)
  end

  def states, do: @states
end
