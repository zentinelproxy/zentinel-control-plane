defmodule SentinelCpWeb.Api.AuditVerificationController do
  use SentinelCpWeb, :controller

  alias SentinelCp.Audit.ChainVerifier

  def verify(conn, _params) do
    status = ChainVerifier.verification_status()

    chain_status =
      case status.chain do
        {:ok, count} -> %{valid: true, verified_entries: count}
        {:error, :chain_break, entry_id} -> %{valid: false, break_at: entry_id}
      end

    checkpoint_status =
      case status.checkpoint_verification do
        :ok -> %{valid: true}
        {:error, reason} -> %{valid: false, reason: to_string(reason)}
      end

    json(conn, %{
      chain: chain_status,
      checkpoint: checkpoint_status,
      latest_checkpoint:
        if status.latest_checkpoint do
          %{
            sequence_number: status.latest_checkpoint.sequence_number,
            entries_count: status.latest_checkpoint.entries_count,
            created_at: status.latest_checkpoint.inserted_at
          }
        end,
      verified_at: DateTime.to_iso8601(status.verified_at)
    })
  end

  def checkpoints(conn, _params) do
    checkpoints = ChainVerifier.list_checkpoints()

    json(conn, %{
      checkpoints:
        Enum.map(checkpoints, fn cp ->
          %{
            id: cp.id,
            sequence_number: cp.sequence_number,
            entries_count: cp.entries_count,
            last_entry_hash: cp.last_entry_hash,
            digest: cp.digest,
            signature: cp.signature,
            created_at: cp.inserted_at
          }
        end)
    })
  end

  def create_checkpoint(conn, _params) do
    case ChainVerifier.create_checkpoint() do
      {:ok, :no_new_entries} ->
        json(conn, %{message: "No new entries since last checkpoint"})

      {:ok, checkpoint} ->
        conn
        |> put_status(:created)
        |> json(%{
          checkpoint: %{
            id: checkpoint.id,
            sequence_number: checkpoint.sequence_number,
            entries_count: checkpoint.entries_count,
            digest: checkpoint.digest
          }
        })

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: inspect(reason)})
    end
  end
end
