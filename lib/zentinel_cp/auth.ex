defmodule ZentinelCp.Auth do
  @moduledoc """
  The Auth context handles signing key management and JWT token issuance
  for node authentication.
  """

  import Ecto.Query, warn: false
  alias ZentinelCp.Repo
  alias ZentinelCp.Auth.{SigningKey, NodeToken}
  alias ZentinelCp.Nodes
  alias ZentinelCp.Nodes.Node

  ## Signing Key Management

  @doc """
  Generates a new Ed25519 signing key for an org.
  """
  def create_signing_key(org_id, opts \\ []) do
    {public, secret} = :crypto.generate_key(:eddsa, :ed25519)
    # JOSE expects the full 64-byte Ed25519 secret key (seed || public)
    full_secret = secret <> public
    key_id = Keyword.get(opts, :key_id, generate_key_id())
    expires_at = Keyword.get(opts, :expires_at)

    %SigningKey{}
    |> SigningKey.create_changeset(%{
      org_id: org_id,
      key_id: key_id,
      public_key: public,
      private_key_encrypted: full_secret,
      algorithm: "Ed25519",
      active: true,
      expires_at: expires_at
    })
    |> Repo.insert()
  end

  @doc """
  Gets the active signing key for an org.
  Returns the most recently created active, non-expired key.
  """
  def get_active_signing_key(org_id) do
    now = DateTime.utc_now()

    from(k in SigningKey,
      where: k.org_id == ^org_id and k.active == true,
      where: is_nil(k.expires_at) or k.expires_at > ^now,
      order_by: [desc: k.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Gets a signing key by its key_id.
  """
  def get_signing_key_by_kid(key_id) when is_binary(key_id) do
    Repo.get_by(SigningKey, key_id: key_id)
  end

  @doc """
  Deactivates a signing key.
  """
  def deactivate_signing_key(%SigningKey{} = key) do
    key
    |> Ecto.Changeset.change(active: false)
    |> Repo.update()
  end

  @doc """
  Lists all signing keys for an org.
  """
  def list_signing_keys(org_id) do
    from(k in SigningKey,
      where: k.org_id == ^org_id,
      order_by: [desc: k.inserted_at]
    )
    |> Repo.all()
  end

  ## Token Issuance

  @doc """
  Issues a JWT token for a node.

  The node must belong to a project that has an org with an active signing key.
  Returns `{:ok, token, expires_at}` or `{:error, reason}`.
  """
  def issue_node_token(%Node{} = node) do
    node = Repo.preload(node, project: :org)

    with {:ok, org_id} <- get_node_org_id(node),
         {:ok, signing_key} <- get_key_for_org(org_id) do
      case NodeToken.generate(node, signing_key) do
        {:ok, token, claims} ->
          expires_at = DateTime.from_unix!(claims["exp"])
          issued_at = DateTime.from_unix!(claims["iat"])

          # Update node with token metadata
          node
          |> Ecto.Changeset.change(
            token_issued_at: DateTime.truncate(issued_at, :second),
            token_expires_at: DateTime.truncate(expires_at, :second),
            auth_method: "jwt"
          )
          |> Repo.update()

          {:ok, token, expires_at}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Verifies a JWT token and returns the authenticated node.

  Returns `{:ok, node}` or `{:error, reason}`.
  """
  def verify_node_token(token) when is_binary(token) do
    with {:ok, kid} <- NodeToken.peek_kid(token),
         {:ok, signing_key} <- get_key_by_kid(kid),
         {:ok, claims} <- NodeToken.verify(token, signing_key),
         {:ok, node} <- get_node_from_claims(claims) do
      {:ok, node}
    end
  end

  ## Private Helpers

  defp get_node_org_id(%Node{project: %{org_id: org_id}}) when is_binary(org_id) do
    {:ok, org_id}
  end

  defp get_node_org_id(_), do: {:error, :no_org}

  defp get_key_for_org(org_id) do
    case get_active_signing_key(org_id) do
      nil -> {:error, :no_signing_key}
      key -> {:ok, key}
    end
  end

  defp get_key_by_kid(kid) do
    case get_signing_key_by_kid(kid) do
      nil -> {:error, :unknown_key}
      %{active: false} -> {:error, :key_deactivated}
      key -> {:ok, key}
    end
  end

  defp get_node_from_claims(%{"sub" => node_id}) do
    case Nodes.get_node(node_id) do
      nil -> {:error, :node_not_found}
      node -> {:ok, node}
    end
  end

  defp get_node_from_claims(_), do: {:error, :invalid_claims}

  defp generate_key_id do
    "sk_" <> (:crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false))
  end

  @doc """
  Ensures an org has at least one active signing key.
  Creates one if none exists. Returns `{:ok, signing_key}`.
  """
  def ensure_signing_key(org_id) do
    case get_active_signing_key(org_id) do
      nil -> create_signing_key(org_id)
      key -> {:ok, key}
    end
  end
end
