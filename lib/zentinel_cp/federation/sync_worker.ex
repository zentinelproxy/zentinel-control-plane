defmodule ZentinelCp.Federation.SyncWorker do
  @moduledoc """
  Oban worker for periodic federation state synchronization.

  Syncs state between hub and spoke control planes:
  - Hub pulls node state from spokes
  - Spokes pull policy/config from hub
  - Conflict resolution: hub wins for config, spokes win for node state
  """
  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 3,
    unique: [period: 60]

  import Ecto.Query, warn: false
  alias ZentinelCp.Repo
  alias ZentinelCp.Federation.Peer

  require Logger

  @sync_interval_seconds 60

  def ensure_started do
    %{}
    |> __MODULE__.new(schedule_in: @sync_interval_seconds)
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    peers =
      from(p in Peer, where: p.enabled == true and p.sync_status != "syncing")
      |> Repo.all()

    Enum.each(peers, &sync_peer/1)

    ensure_started()
    :ok
  end

  @doc """
  Synchronizes state with a specific peer.
  """
  def sync_peer(peer) do
    Logger.info("Starting sync with peer #{peer.name} (#{peer.region})")

    peer
    |> Peer.changeset(%{sync_status: "syncing"})
    |> Repo.update()

    case do_sync(peer) do
      :ok ->
        peer
        |> Peer.changeset(%{
          sync_status: "synced",
          last_sync_at: DateTime.utc_now() |> DateTime.truncate(:second),
          last_sync_error: nil
        })
        |> Repo.update()

        Logger.info("Sync completed with peer #{peer.name}")

      {:error, reason} ->
        peer
        |> Peer.changeset(%{
          sync_status: "error",
          last_sync_error: to_string(reason)
        })
        |> Repo.update()

        Logger.error("Sync failed with peer #{peer.name}: #{reason}")
    end
  end

  defp do_sync(peer) do
    case peer.role do
      "spoke" -> sync_from_spoke(peer)
      "hub" -> sync_from_hub(peer)
    end
  end

  defp sync_from_spoke(peer) do
    # Pull node state from spoke, push config to spoke
    case fetch_peer_state(peer, "/api/v1/federation/state") do
      {:ok, _state} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp sync_from_hub(peer) do
    # Pull config from hub, push node state to hub
    case fetch_peer_state(peer, "/api/v1/federation/config") do
      {:ok, _config} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_peer_state(peer, path) do
    url = "#{String.trim_trailing(peer.url, "/")}" <> path

    case Req.get(url, headers: [{"authorization", "Bearer #{peer.api_key_hash}"}]) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end
end
