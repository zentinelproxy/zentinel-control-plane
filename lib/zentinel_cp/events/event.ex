defmodule ZentinelCp.Events.Event do
  @moduledoc """
  Schema for structured events emitted throughout the system.

  Event type taxonomy:
  - `rollout.*` — rollout lifecycle events
  - `bundle.*` — bundle creation, promotion, revocation
  - `node.*` — node registration, drift, status changes
  - `drift.*` — configuration drift detection/resolution
  - `secret.*` — secret rotation, access
  - `security.*` — auth failures, policy violations
  - `system.*` — system-level events
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @event_prefixes ~w(rollout bundle node drift secret security system)

  schema "events" do
    field :type, :string
    field :payload, :map, default: %{}
    field :project_id, :binary_id
    field :org_id, :binary_id
    field :emitted_at, :utc_datetime

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:type, :payload, :project_id, :org_id, :emitted_at])
    |> validate_required([:type, :emitted_at])
    |> validate_event_type()
  end

  defp validate_event_type(changeset) do
    validate_change(changeset, :type, fn :type, type ->
      prefix = type |> String.split(".") |> hd()

      if prefix in @event_prefixes do
        []
      else
        [type: "must start with one of: #{Enum.join(@event_prefixes, ", ")}"]
      end
    end)
  end

  @doc """
  Checks if an event type matches a pattern.
  Supports wildcard patterns like `rollout.*`.
  """
  def matches_pattern?(event_type, pattern) do
    cond do
      pattern == "*" ->
        true

      String.ends_with?(pattern, ".*") ->
        prefix = String.trim_trailing(pattern, ".*")
        String.starts_with?(event_type, prefix <> ".")

      true ->
        event_type == pattern
    end
  end
end
