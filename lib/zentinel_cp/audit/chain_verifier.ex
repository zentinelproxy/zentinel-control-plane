defmodule ZentinelCp.Audit.ChainVerifier do
  @moduledoc """
  Tamper-evident audit log chain using SHA-256 hash chaining and Ed25519-signed checkpoints.

  Each audit log entry includes a hash of the previous entry, forming an
  append-only chain. Periodic checkpoints are signed with Ed25519 keys
  for external verification.
  """

  import Ecto.Query, warn: false
  alias ZentinelCp.Repo
  alias ZentinelCp.Audit.{AuditLog, AuditCheckpoint}
  alias ZentinelCp.Bundles.Signing
  alias ZentinelCp.Repo.Dialect

  @hash_algorithm :sha256
  @hash_version 2
  @batch_size 1000
  # Arbitrary, distinct from the leader election lock.
  @chain_lock_id 728_394_562

  @doc """
  Appends an entry to the chain.

  Reading the chain head and inserting must be atomic or concurrent writers
  fork the chain, so this holds a lock until the transaction ends.
  """
  def append(attrs) do
    changeset = AuditLog.changeset(%AuditLog{}, attrs)

    if changeset.valid? do
      Repo.transaction(fn ->
        lock_chain()
        {sequence, previous_hash} = chain_head()

        entry =
          changeset
          |> Ecto.Changeset.put_change(:chain_sequence, sequence + 1)
          |> Ecto.Changeset.put_change(:hash_version, @hash_version)
          |> Ecto.Changeset.put_change(:previous_hash, previous_hash)
          |> Ecto.Changeset.put_change(:inserted_at, now())

        entry_hash =
          entry |> Ecto.Changeset.apply_changes() |> compute_entry_hash(previous_hash)

        case entry |> Ecto.Changeset.put_change(:entry_hash, entry_hash) |> Repo.insert() do
          {:ok, inserted} -> inserted
          {:error, failed} -> Repo.rollback(failed)
        end
      end)
    else
      {:error, %{changeset | action: :insert}}
    end
  end

  @doc """
  Computes the hash for an audit log entry, including the previous entry's hash.

  Field values are canonicalized so that a value hashes identically before
  insert and after being read back from a JSON column.
  """
  def compute_entry_hash(%AuditLog{} = entry, previous_hash) do
    entry |> Map.from_struct() |> compute_entry_hash(previous_hash)
  end

  def compute_entry_hash(entry_attrs, previous_hash) do
    inserted_at = entry_attrs[:inserted_at]

    data =
      canonical_json([
        previous_hash,
        entry_attrs[:chain_sequence],
        inserted_at && DateTime.to_iso8601(inserted_at),
        entry_attrs[:org_id],
        entry_attrs[:project_id],
        entry_attrs[:actor_type],
        entry_attrs[:actor_id],
        entry_attrs[:action],
        entry_attrs[:resource_type],
        entry_attrs[:resource_id],
        entry_attrs[:changes] || %{},
        entry_attrs[:metadata] || %{}
      ])

    :crypto.hash(@hash_algorithm, data) |> Base.encode16(case: :lower)
  end

  @doc """
  Gets the hash of the most recent audit log entry.
  Returns `nil` if no entries exist.
  """
  def get_latest_hash do
    {_sequence, hash} = chain_head()
    hash
  end

  @doc """
  Verifies the integrity of the audit log chain.

  Each entry's hash is recomputed, which detects edited rows. Each entry's
  `previous_hash` is compared with its predecessor, which detects deleted or
  reordered rows. Rows from before hash version #{@hash_version} can only have
  their links checked.

  With `:project_id`, only the hashes of that project's entries are checked:
  the chain is global, so a project's entries are not adjacent links.

  Options: `:limit` caps the entries checked (default: all).
  Returns `{:ok, verified_count}`, `{:error, :chain_break, entry_id}` or
  `{:error, :hash_mismatch, entry_id}`.
  """
  def verify_chain(opts \\ []) do
    state = %{
      after_sequence: nil,
      expected_previous: nil,
      count: 0,
      limit: Keyword.get(opts, :limit),
      project_id: Keyword.get(opts, :project_id)
    }

    verify_batches(state)
  end

  defp verify_batches(%{limit: limit, count: count}) when count == limit, do: {:ok, count}

  defp verify_batches(state) do
    case next_batch(state) do
      [] ->
        {:ok, state.count}

      entries ->
        case verify_entries(entries, state) do
          {:cont, state} -> verify_batches(state)
          {:error, _reason, _id} = error -> error
        end
    end
  end

  defp next_batch(state) do
    size = if state.limit, do: min(@batch_size, state.limit - state.count), else: @batch_size

    query =
      from(a in AuditLog,
        where: not is_nil(a.entry_hash),
        order_by: [asc: a.chain_sequence],
        limit: ^size
      )

    query =
      if state.after_sequence,
        do: where(query, [a], a.chain_sequence > ^state.after_sequence),
        else: query

    query =
      if state.project_id,
        do: where(query, [a], a.project_id == ^state.project_id),
        else: query

    Repo.all(query)
  end

  defp verify_entries(entries, state) do
    Enum.reduce_while(entries, {:cont, state}, fn entry, {:cont, state} ->
      cond do
        is_nil(state.project_id) and entry.previous_hash != state.expected_previous ->
          {:halt, {:error, :chain_break, entry.id}}

        not hash_valid?(entry) ->
          {:halt, {:error, :hash_mismatch, entry.id}}

        true ->
          {:cont,
           {:cont,
            %{
              state
              | after_sequence: entry.chain_sequence,
                expected_previous: entry.entry_hash,
                count: state.count + 1
            }}}
      end
    end)
  end

  defp hash_valid?(%AuditLog{hash_version: @hash_version} = entry) do
    compute_entry_hash(entry, entry.previous_hash) == entry.entry_hash
  end

  defp hash_valid?(%AuditLog{}), do: true

  @doc """
  Creates a signed checkpoint of the audit chain.
  The checkpoint records the chain head, signed with the Ed25519 signing key,
  so that deleting the newest entries can be detected.
  """
  def create_checkpoint do
    last_checkpoint = get_latest_checkpoint()
    last_seq = if last_checkpoint, do: last_checkpoint.sequence_number, else: 0
    checkpointed_through = checkpointed_sequence(last_checkpoint)

    query =
      from(a in AuditLog,
        where: not is_nil(a.entry_hash) and a.chain_sequence > ^checkpointed_through,
        order_by: [desc: a.chain_sequence],
        limit: 1
      )

    case Repo.one(query) do
      nil ->
        {:ok, :no_new_entries}

      last_entry ->
        entries_count = last_entry.chain_sequence - checkpointed_through
        digest = compute_checkpoint_digest(last_entry.entry_hash, last_seq + 1, entries_count)

        %AuditCheckpoint{}
        |> AuditCheckpoint.changeset(%{
          sequence_number: last_seq + 1,
          last_entry_id: last_entry.id,
          last_entry_hash: last_entry.entry_hash,
          digest: digest,
          signature: sign_digest(digest),
          entries_count: entries_count
        })
        |> Repo.insert()
    end
  end

  @doc """
  Verifies a checkpoint: its signature, its digest, and that the entry it
  recorded is still in the log with the same hash.

  Returns `:ok` or `{:error, reason}`.
  """
  def verify_checkpoint(%AuditCheckpoint{signature: "unsigned"}), do: {:error, :unsigned}

  def verify_checkpoint(%AuditCheckpoint{} = checkpoint) do
    expected =
      compute_checkpoint_digest(
        checkpoint.last_entry_hash,
        checkpoint.sequence_number,
        checkpoint.entries_count
      )

    cond do
      expected != checkpoint.digest -> {:error, :digest_mismatch}
      not signature_valid?(checkpoint) -> {:error, :invalid_signature}
      not checkpoint_entry_present?(checkpoint) -> {:error, :entry_missing}
      true -> :ok
    end
  end

  @doc """
  Gets the latest checkpoint.
  """
  def get_latest_checkpoint do
    from(c in AuditCheckpoint,
      order_by: [desc: c.sequence_number],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Lists all checkpoints for verification.
  """
  def list_checkpoints(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    from(c in AuditCheckpoint,
      order_by: [desc: c.sequence_number],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Returns the full chain verification status.
  """
  def verification_status do
    chain_result = verify_chain()
    latest_checkpoint = get_latest_checkpoint()

    checkpoint_result =
      if latest_checkpoint do
        verify_checkpoint(latest_checkpoint)
      else
        {:error, :no_checkpoints}
      end

    %{
      chain: chain_result,
      latest_checkpoint: latest_checkpoint,
      checkpoint_verification: checkpoint_result,
      verified_at: DateTime.utc_now()
    }
  end

  ## Private

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp lock_chain do
    if Application.get_env(:zentinel_cp, :audit_chain_lock, true) do
      Dialect.advisory_xact_lock(@chain_lock_id)
    end

    :ok
  end

  defp chain_head do
    query =
      from(a in AuditLog,
        where: not is_nil(a.entry_hash),
        order_by: [desc: a.chain_sequence],
        limit: 1,
        select: {a.chain_sequence, a.entry_hash}
      )

    Repo.one(query) || {0, nil}
  end

  defp checkpointed_sequence(nil), do: 0

  defp checkpointed_sequence(%AuditCheckpoint{last_entry_id: entry_id}) do
    Repo.one(from(a in AuditLog, where: a.id == ^entry_id, select: a.chain_sequence)) || 0
  end

  defp checkpoint_entry_present?(%AuditCheckpoint{} = checkpoint) do
    Repo.exists?(
      from(a in AuditLog,
        where: a.id == ^checkpoint.last_entry_id and a.entry_hash == ^checkpoint.last_entry_hash
      )
    )
  end

  defp canonical_json(value) do
    value |> Jason.encode!() |> Jason.decode!() |> canonicalize() |> Jason.encode!()
  end

  # Maps become sorted pairs, because key order is not preserved by jsonb.
  # Whole floats become integers, because jsonb may return 1.0e20 as an integer.
  defp canonicalize(map) when is_map(map) do
    map |> Enum.sort_by(&elem(&1, 0)) |> Enum.map(fn {k, v} -> [k, canonicalize(v)] end)
  end

  defp canonicalize(list) when is_list(list), do: Enum.map(list, &canonicalize/1)

  defp canonicalize(float) when is_float(float) and trunc(float) == float, do: trunc(float)

  defp canonicalize(value), do: value

  defp compute_checkpoint_digest(last_hash, sequence, entries_count) do
    data = "checkpoint:#{sequence}:#{entries_count}:#{last_hash}"
    :crypto.hash(@hash_algorithm, data) |> Base.encode16(case: :lower)
  end

  defp sign_digest(digest) do
    case Signing.sign_bundle(digest) do
      {nil, nil} -> "unsigned"
      {signature, _key_id} -> Base.encode64(signature)
    end
  end

  defp signature_valid?(%AuditCheckpoint{digest: digest, signature: signature}) do
    with {:ok, decoded} <- Base.decode64(signature),
         {true, _key_id} <- Signing.verify_bundle(digest, decoded, "audit") do
      true
    else
      _ -> false
    end
  end
end
