defmodule ZentinelCp.Auth.NodeToken do
  @moduledoc """
  JWT generation and verification for node authentication.

  Tokens are signed with Ed25519 (OKP) keys using JOSE.
  Default expiry is 12 hours.
  """

  @default_ttl_seconds 12 * 60 * 60

  @doc """
  Generates a signed JWT for a node.

  Returns `{:ok, token_string, claims}` or `{:error, reason}`.
  """
  def generate(node, signing_key, opts \\ []) do
    ttl = Keyword.get(opts, :ttl_seconds, @default_ttl_seconds)
    now = DateTime.utc_now() |> DateTime.to_unix()

    claims = %{
      "sub" => node.id,
      "prj" => node.project_id,
      "iat" => now,
      "exp" => now + ttl,
      "kid" => signing_key.key_id
    }

    # Add org claim if node's project has an org
    claims =
      if org_id = get_org_id(node) do
        Map.put(claims, "org", org_id)
      else
        claims
      end

    jwk = build_jwk(signing_key)
    jws = %{"alg" => "EdDSA", "kid" => signing_key.key_id}

    case JOSE.JWT.sign(jwk, jws, claims) do
      {%{alg: _}, token} ->
        {:ok, JOSE.JWS.compact(token) |> elem(1), claims}

      _ ->
        {:error, :signing_failed}
    end
  end

  @doc """
  Verifies a JWT token against a signing key.

  Returns `{:ok, claims}` or `{:error, reason}`.
  """
  def verify(token, signing_key) when is_binary(token) do
    jwk = build_verify_jwk(signing_key)

    try do
      case JOSE.JWT.verify_strict(jwk, ["EdDSA"], token) do
        {true, %JOSE.JWT{fields: claims}, _jws} ->
          validate_claims(claims)

        {false, _, _} ->
          {:error, :invalid_signature}

        _ ->
          {:error, :verification_failed}
      end
    rescue
      _ -> {:error, :verification_failed}
    end
  end

  @doc """
  Extracts the key ID (kid) from a token without verifying.
  Used to look up which signing key to verify against.
  """
  def peek_kid(token) when is_binary(token) do
    try do
      case JOSE.JWT.peek_protected(token) do
        %JOSE.JWS{fields: %{"kid" => kid}} -> {:ok, kid}
        _ -> {:error, :no_kid}
      end
    rescue
      _ -> {:error, :invalid_token}
    end
  end

  @doc """
  Returns the default TTL in seconds.
  """
  def default_ttl_seconds, do: @default_ttl_seconds

  # Build a JWK from a signing key (private key for signing)
  defp build_jwk(signing_key) do
    secret = decrypt_private_key(signing_key.private_key_encrypted)
    # JOSE expects {:Ed25519, <<secret_64_bytes>>} for signing
    JOSE.JWK.from_okp({:Ed25519, secret})
  end

  # Build a JWK from a signing key (public key only, 32 bytes, for verification)
  defp build_verify_jwk(signing_key) do
    JOSE.JWK.from_okp({:Ed25519, signing_key.public_key})
  end

  defp validate_claims(claims) do
    now = DateTime.utc_now() |> DateTime.to_unix()

    cond do
      not is_integer(claims["exp"]) ->
        {:error, :missing_expiry}

      claims["exp"] <= now ->
        {:error, :token_expired}

      not is_binary(claims["sub"]) ->
        {:error, :missing_subject}

      true ->
        {:ok, claims}
    end
  end

  # For now, private keys are stored as-is (encrypted at-rest by the DB layer).
  # In production, use envelope encryption with a KMS.
  defp decrypt_private_key(encrypted), do: encrypted

  defp get_org_id(%{project: %{org_id: org_id}}) when is_binary(org_id), do: org_id
  defp get_org_id(_), do: nil
end
