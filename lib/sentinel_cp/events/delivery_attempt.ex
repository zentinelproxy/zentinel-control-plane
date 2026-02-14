defmodule SentinelCp.Events.DeliveryAttempt do
  @moduledoc """
  Schema for tracking notification delivery attempts.
  Records HTTP status, latency, errors, and retry state.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(pending delivering delivered failed dead_letter)

  schema "delivery_attempts" do
    field :status, :string, default: "pending"
    field :http_status, :integer
    field :latency_ms, :integer
    field :error, :string
    field :attempt_number, :integer, default: 1
    field :next_retry_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :request_body, :string
    field :response_body, :string

    belongs_to :event, SentinelCp.Events.Event
    belongs_to :channel, SentinelCp.Events.Channel

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [
      :event_id,
      :channel_id,
      :status,
      :http_status,
      :latency_ms,
      :error,
      :attempt_number,
      :next_retry_at,
      :completed_at,
      :request_body,
      :response_body
    ])
    |> validate_required([:event_id, :channel_id, :status, :attempt_number])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:event_id)
    |> foreign_key_constraint(:channel_id)
  end

  def complete_changeset(attempt, attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attempt
    |> cast(attrs, [:status, :http_status, :latency_ms, :error, :request_body, :response_body])
    |> put_change(:completed_at, now)
    |> validate_inclusion(:status, @statuses)
  end

  def retry_changeset(attempt, next_retry_at) do
    attempt
    |> change(%{
      status: "pending",
      attempt_number: attempt.attempt_number + 1,
      next_retry_at: next_retry_at
    })
  end

  @max_retries 10

  def max_retries, do: @max_retries

  @doc """
  Computes the next retry time using exponential backoff with jitter.
  Retry intervals: ~1m, ~2m, ~4m, ~8m, ~16m, ~32m, ~1h, ~2h, ~4h, ~8h
  """
  def next_retry_time(attempt_number) do
    base_delay = :math.pow(2, attempt_number) |> round() |> min(480)
    jitter = :rand.uniform(max(1, div(base_delay, 4)))
    delay_minutes = base_delay + jitter

    DateTime.utc_now()
    |> DateTime.add(delay_minutes * 60, :second)
    |> DateTime.truncate(:second)
  end
end
