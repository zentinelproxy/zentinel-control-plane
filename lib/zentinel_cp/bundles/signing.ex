defmodule ZentinelCp.Bundles.Signing do
  @moduledoc """
  Ed25519 bundle signing and verification.

  Signs compiled bundle artifacts so nodes can verify authenticity.
  Signing is config-driven and can be disabled.
  """

  @doc """
  Generates a new Ed25519 keypair.

  Returns `{public_key, private_key}` as raw binaries.
  """
  def generate_keypair do
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
    {public_key, private_key}
  end

  @doc """
  Signs binary data with an Ed25519 private key.

  Returns the signature as a raw binary.
  """
  def sign(data, private_key) when is_binary(data) and is_binary(private_key) do
    :crypto.sign(:eddsa, :none, data, [private_key, :ed25519])
  end

  @doc """
  Verifies an Ed25519 signature against data and public key.

  Returns `true` if the signature is valid, `false` otherwise.
  """
  def verify(data, signature, public_key)
      when is_binary(data) and is_binary(signature) and is_binary(public_key) do
    :crypto.verify(:eddsa, :none, data, signature, [public_key, :ed25519])
  end

  @doc """
  Signs a bundle if signing is enabled.

  Returns `{signature, key_id}` or `{nil, nil}` if signing is disabled.
  """
  def sign_bundle(bundle_data) when is_binary(bundle_data) do
    config = Application.get_env(:zentinel_cp, :bundle_signing, [])

    if config[:enabled] do
      private_key = load_private_key(config)
      key_id = config[:key_id] || "default"
      signature = sign(bundle_data, private_key)
      {signature, key_id}
    else
      {nil, nil}
    end
  end

  @doc """
  Verifies a bundle signature against configured or provided public key.

  Returns `{true, key_id}` if valid, `{false, key_id}` if invalid,
  or `{false, nil}` if no signature present.
  """
  def verify_bundle(bundle_data, signature, signing_key_id) do
    if is_nil(signature) or is_nil(signing_key_id) do
      {false, nil}
    else
      config = Application.get_env(:zentinel_cp, :bundle_signing, [])
      public_key = load_public_key(config)
      {verify(bundle_data, signature, public_key), signing_key_id}
    end
  end

  defp load_private_key(config) do
    cond do
      config[:private_key] ->
        config[:private_key]

      config[:private_key_path] ->
        config[:private_key_path]
        |> File.read!()
        |> String.trim()
        |> Base.decode64!()

      true ->
        raise "Bundle signing is enabled but no private key configured"
    end
  end

  defp load_public_key(config) do
    cond do
      config[:public_key] ->
        config[:public_key]

      config[:public_key_path] ->
        config[:public_key_path]
        |> File.read!()
        |> String.trim()
        |> Base.decode64!()

      true ->
        raise "Bundle verification requires a public key"
    end
  end
end
