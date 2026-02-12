defmodule SentinelCp.Services.DiscoverySyncWorker do
  @moduledoc """
  Oban worker that periodically syncs DNS-based discovery sources.

  Checks all auto_sync sources and triggers sync when the configured
  interval has elapsed since the last sync.
  """
  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 1,
    unique: [period: 30]

  require Logger

  alias SentinelCp.Services

  @default_interval_seconds 30

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.debug("DiscoverySyncWorker: checking discovery sources")

    sources = Services.list_auto_sync_sources()

    for source <- sources do
      if sync_due?(source) do
        case Services.sync_discovery_source(source) do
          {:ok, result} ->
            Logger.info(
              "DiscoverySyncWorker: synced #{source.hostname} — " <>
                "added: #{result.added}, removed: #{result.removed}, kept: #{result.kept}"
            )

          {:error, reason} ->
            Logger.warning("DiscoverySyncWorker: failed to sync #{source.hostname}: #{reason}")
        end
      end
    end

    reschedule()
    :ok
  end

  defp sync_due?(%{last_synced_at: nil}), do: true

  defp sync_due?(source) do
    elapsed = DateTime.diff(DateTime.utc_now(), source.last_synced_at, :second)
    elapsed >= source.sync_interval_seconds
  end

  defp reschedule do
    oban_config = Application.get_env(:sentinel_cp, Oban, [])

    unless oban_config[:testing] do
      %{}
      |> __MODULE__.new(schedule_in: @default_interval_seconds)
      |> Oban.insert()
    end
  end

  @doc """
  Starts the discovery sync worker if not already running.
  Called during application startup.
  """
  def ensure_started do
    oban_config = Application.get_env(:sentinel_cp, Oban, [])

    unless oban_config[:testing] do
      %{}
      |> __MODULE__.new()
      |> Oban.insert()
    end
  end
end
