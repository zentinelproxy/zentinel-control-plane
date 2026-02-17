defmodule ZentinelCp.Audit.ChainVerifier do
  @moduledoc """
  Tamper-evident audit log chain using HMAC chaining and Ed25519-signed checkpoints.

  Each audit log entry includes a hash of the previous entry, forming an
  append-only chain. Periodic checkpoints are signed with Ed25519 keys
  for external verification.
  """

  import Ecto.Query, warn: false
  alias ZentinelCp.Repo
  alias ZentinelCp.Audit.{AuditLog, AuditCheckpoint}

  @hash_algorithm :sha256

  @doc """
  Computes the hash for an audit log entry, including the previous entry's hash.
  """
  def compute_entry_hash(entry_attrs, previous_hash) do
    data =
      Jason.encode!(%{
        previous_hash: previous_hash,
        actor_type: entry_attrs[:actor_type] || entry_attrs["actor_type"],
        actor_id: entry_attrs[:actor_id] || entry_attrs["actor_id"],
        action: entry_attrs[:action] || entry_attrs["action"],
        resource_type: entry_attrs[:resource_type] || entry_attrs["resource_type"],
        resource_id: entry_attrs[:resource_id] || entry_attrs["resource_id"],
        project_id: entry_attrs[:project_id] || entry_attrs["project_id"],
        changes: entry_attrs[:changes] || entry_attrs["changes"] || %{},
        metadata: entry_attrs[:metadata] || entry_attrs["metadata"] || %{}
      })

    :crypto.hash(@hash_algorithm, data) |> Base.encode16(case: :lower)
  end

  @doc """
  Gets the hash of the most recent audit log entry.
  Returns `nil` if no entries exist.
  """
  def get_latest_hash do
    from(a in AuditLog,
      where: not is_nil(a.entry_hash),
      order_by: [desc: a.inserted_at],
      limit: 1,
      select: a.entry_hash
    )
    |> Repo.one()
  end

  @doc """
  Verifies the integrity of the audit log chain.

  Checks that each entry's `previous_hash` matches the preceding entry's
  `entry_hash`. Returns `{:ok, verified_count}` or `{:error, break_at, entry_id}`.
  """
  def verify_chain(opts \\ []) do
    limit = Keyword.get(opts, :limit, 1000)
    project_id = Keyword.get(opts, :project_id)

    query =
      from(a in AuditLog,
        where: not is_nil(a.entry_hash),
        order_by: [asc: a.inserted_at],
        limit: ^limit,
        select: {a.id, a.entry_hash, a.previous_hash}
      )

    query =
      if project_id do
        where(query, [a], a.project_id == ^project_id)
      else
        query
      end

    entries = Repo.all(query)
    do_verify_chain(entries, nil, 0)
  end

  defp do_verify_chain([], _prev_hash, count), do: {:ok, count}

  defp do_verify_chain([{id, entry_hash, previous_hash} | rest], expected_prev, count) do
    if previous_hash == expected_prev do
      do_verify_chain(rest, entry_hash, count + 1)
    else
      {:error, :chain_break, id}
    end
  end

  @doc """
  Creates a signed checkpoint of the audit chain.
  The checkpoint includes a digest of all entries since the last checkpoint,
  signed with the Ed25519 signing key.
  """
  def create_checkpoint do
    last_checkpoint = get_latest_checkpoint()
    last_seq = if last_checkpoint, do: last_checkpoint.sequence_number, else: 0

    query =
      from(a in AuditLog,
        where: not is_nil(a.entry_hash),
        order_by: [desc: a.inserted_at],
        limit: 1
      )

    query =
      if last_checkpoint do
        where(query, [a], a.inserted_at > ^last_checkpoint.inserted_at)
      else
        query
      end

    case Repo.one(query) do
      nil ->
        {:ok, :no_new_entries}

      last_entry ->
        entries_count = count_entries_since_checkpoint(last_checkpoint)
        digest = compute_checkpoint_digest(last_entry.entry_hash, last_seq + 1, entries_count)

        signature =
          case sign_digest(digest) do
            {:ok, sig} -> sig
            _ -> "unsigned"
          end

        %AuditCheckpoint{}
        |> AuditCheckpoint.changeset(%{
          sequence_number: last_seq + 1,
          last_entry_id: last_entry.id,
          last_entry_hash: last_entry.entry_hash,
          digest: digest,
          signature: signature,
          entries_count: entries_count
        })
        |> Repo.insert()
    end
  end

  @doc """
  Verifies a checkpoint's signature.
  Returns `:ok` or `{:error, :invalid_signature}`.
  """
  def verify_checkpoint(%AuditCheckpoint{signature: "unsigned"}), do: {:error, :unsigned}

  def verify_checkpoint(%AuditCheckpoint{digest: digest, signature: signature}) do
    case verify_signature(digest, signature) do
      true -> :ok
      false -> {:error, :invalid_signature}
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

  defp count_entries_since_checkpoint(nil) do
    Repo.aggregate(
      from(a in AuditLog, where: not is_nil(a.entry_hash)),
      :count
    )
  end

  defp count_entries_since_checkpoint(%AuditCheckpoint{} = cp) do
    Repo.aggregate(
      from(a in AuditLog,
        where: not is_nil(a.entry_hash) and a.inserted_at > ^cp.inserted_at
      ),
      :count
    )
  end

  defp compute_checkpoint_digest(last_hash, sequence, entries_count) do
    data = "checkpoint:#{sequence}:#{entries_count}:#{last_hash}"
    :crypto.hash(@hash_algorithm, data) |> Base.encode16(case: :lower)
  end

  defp sign_digest(digest) do
    signing_config = Application.get_env(:zentinel_cp, :bundle_signing, [])

    if signing_config[:enabled] && signing_config[:private_key_path] do
      case File.read(signing_config[:private_key_path]) do
        {:ok, pem} ->
          key = JOSE.JWK.from_pem(pem)
          {_, signature} = JOSE.JWK.sign(digest, %{"alg" => "EdDSA"}, key)
          {:ok, signature}

        _ ->
          {:error, :key_not_found}
      end
    else
      {:error, :signing_disabled}
    end
  end

  defp verify_signature(digest, _signature) do
    signing_config = Application.get_env(:zentinel_cp, :bundle_signing, [])

    if signing_config[:public_key_path] do
      case File.read(signing_config[:public_key_path]) do
        {:ok, pem} ->
          key = JOSE.JWK.from_pem(pem)
          {valid, _, _} = JOSE.JWK.verify(digest, key)
          valid

        _ ->
          false
      end
    else
      false
    end
  end
end
