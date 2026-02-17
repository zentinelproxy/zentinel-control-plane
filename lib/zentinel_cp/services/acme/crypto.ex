defmodule ZentinelCp.Services.Acme.Crypto do
  @moduledoc """
  Pure cryptographic functions for ACME certificate management.

  Handles EC P-256 account keys, RSA 2048 certificate keys,
  PKCS#10 CSR generation, and JWK thumbprints (RFC 7638).
  """

  @doc """
  Generates an EC P-256 key pair for ACME account registration.
  Returns an Erlang EC private key record.
  """
  def generate_account_key do
    :public_key.generate_key({:namedCurve, :secp256r1})
  end

  @doc """
  Generates an RSA 2048-bit key pair for certificate signing requests.
  Returns an Erlang RSA private key record.
  """
  def generate_cert_key do
    :public_key.generate_key({:rsa, 2048, 65537})
  end

  @doc """
  Builds a DER-encoded PKCS#10 CSR for the given domain(s) with the given private key.

  Constructs DER bytes manually to avoid OTP version-specific ASN.1 encoding issues.

  Returns `{:ok, der_binary}` or `{:error, reason}`.
  """
  def build_csr(private_key, domains) when is_list(domains) and length(domains) > 0 do
    [primary | _] = domains

    # Build CSR info DER manually
    version = der_integer(0)
    subject = der_subject_cn(primary)
    spki = der_spki(private_key)
    attributes = der_san_attributes(domains)

    csr_info_inner = version <> subject <> spki <> attributes
    csr_info_der = der_sequence(csr_info_inner)

    # Sign and build outer CSR structure
    {sig_algo_der, digest_type} = csr_signature_info(private_key)
    signature = :public_key.sign(csr_info_der, digest_type, private_key)

    csr_der =
      der_sequence(
        csr_info_der <>
          sig_algo_der <>
          der_bitstring(signature)
      )

    {:ok, csr_der}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Computes the JWK thumbprint (RFC 7638) of an EC P-256 account key.
  Returns the base64url-encoded SHA-256 thumbprint.
  """
  def jwk_thumbprint(ec_key) do
    {x, y} = extract_ec_point(ec_key)
    x_b64 = Base.url_encode64(x, padding: false)
    y_b64 = Base.url_encode64(y, padding: false)

    # RFC 7638: lexicographic order of required members for EC keys
    json = ~s({"crv":"P-256","kty":"EC","x":"#{x_b64}","y":"#{y_b64}"})
    :crypto.hash(:sha256, json) |> Base.url_encode64(padding: false)
  end

  @doc """
  Computes the key authorization string: `token.thumbprint`.
  """
  def key_authorization(token, account_key) do
    "#{token}.#{jwk_thumbprint(account_key)}"
  end

  @doc """
  Converts a private key to PEM-encoded string.
  """
  def private_key_to_pem(key) do
    entry = :public_key.pem_entry_encode(:ECPrivateKey, key)
    :public_key.pem_encode([entry])
  rescue
    _ ->
      # Fallback for RSA keys
      entry = :public_key.pem_entry_encode(:RSAPrivateKey, key)
      :public_key.pem_encode([entry])
  end

  @doc """
  Parses a PEM-encoded private key string back to an Erlang key record.
  """
  def pem_to_private_key(pem) when is_binary(pem) do
    case :public_key.pem_decode(pem) do
      [{type, der, :not_encrypted}] ->
        {:ok, :public_key.der_decode(type, der)}

      _ ->
        {:error, :invalid_pem}
    end
  end

  @doc """
  Builds a JWK map from an EC P-256 key (for ACME JWS headers).
  """
  def ec_key_to_jwk(ec_key) do
    {x, y} = extract_ec_point(ec_key)

    %{
      "kty" => "EC",
      "crv" => "P-256",
      "x" => Base.url_encode64(x, padding: false),
      "y" => Base.url_encode64(y, padding: false)
    }
  end

  # Extract the x,y coordinates from an EC key
  defp extract_ec_point(ec_key) do
    # ECPrivateKey record: {:ECPrivateKey, version, private_key, parameters, public_key}
    public_key_bitstring = elem(ec_key, 4)
    # Uncompressed point format: 0x04 || x || y (each 32 bytes for P-256)
    <<4, x::binary-32, y::binary-32>> = public_key_bitstring
    {x, y}
  end

  # --- DER encoding helpers for CSR construction ---

  # RSA SHA-256 AlgorithmIdentifier: OID 1.2.840.113549.1.1.11 + NULL params
  @rsa_sha256_algo_der <<0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01,
                         0x0B, 0x05, 0x00>>
  # EC SHA-256 AlgorithmIdentifier: OID 1.2.840.10045.4.3.2
  @ec_sha256_algo_der <<0x30, 0x0A, 0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x04, 0x03, 0x02>>
  # RSA public key AlgorithmIdentifier: OID 1.2.840.113549.1.1.1 + NULL
  @rsa_spki_algo_der <<0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01,
                       0x01, 0x05, 0x00>>
  # EC public key AlgorithmIdentifier: OID 1.2.840.10045.2.1 + P-256 OID
  @ec_spki_algo_der <<0x30, 0x13, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01, 0x06,
                      0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07>>

  defp csr_signature_info(k) when elem(k, 0) == :ECPrivateKey, do: {@ec_sha256_algo_der, :sha256}

  defp csr_signature_info(k) when elem(k, 0) == :RSAPrivateKey,
    do: {@rsa_sha256_algo_der, :sha256}

  defp der_spki(ec_key) when elem(ec_key, 0) == :ECPrivateKey do
    pub = elem(ec_key, 4)
    der_sequence(@ec_spki_algo_der <> der_bitstring(pub))
  end

  defp der_spki(rsa_key) when elem(rsa_key, 0) == :RSAPrivateKey do
    modulus = elem(rsa_key, 2)
    pub_exp = elem(rsa_key, 3)
    pub_key_der = der_sequence(der_integer_big(modulus) <> der_integer_big(pub_exp))
    der_sequence(@rsa_spki_algo_der <> der_bitstring(pub_key_der))
  end

  defp der_subject_cn(cn) do
    cn_utf8 = der_tag(0x0C, cn)
    cn_oid = der_oid({2, 5, 4, 3})
    attr_tv = der_sequence(cn_oid <> cn_utf8)
    rdn = der_set(attr_tv)
    # RDNSequence
    der_sequence(rdn)
  end

  defp der_san_attributes(domains) do
    san_values = Enum.map(domains, fn d -> der_context_tag(2, d) end) |> IO.iodata_to_binary()
    san_ext_value = der_sequence(san_values)
    # Extension: OID 2.5.29.17 (subjectAltName), not critical, value
    san_oid = der_oid({2, 5, 29, 17})
    ext = der_sequence(san_oid <> der_octet_string(san_ext_value))
    extensions_seq = der_sequence(ext)
    # extensionRequest attribute: OID 1.2.840.113549.1.9.14
    ext_req_oid = der_oid({1, 2, 840, 113_549, 1, 9, 14})
    ext_req_value = der_set(extensions_seq)
    ext_req = der_sequence(ext_req_oid <> ext_req_value)
    # [0] IMPLICIT SET OF Attribute
    der_context_constructed(0, ext_req)
  end

  defp der_sequence(content), do: der_tag(0x30, content)
  defp der_set(content), do: der_tag(0x31, content)
  defp der_octet_string(content), do: der_tag(0x04, content)

  defp der_bitstring(content) when is_binary(content) do
    # Bit string: tag 0x03, length, 0x00 (no unused bits), then content
    inner = <<0x00>> <> content
    der_tag(0x03, inner)
  end

  defp der_integer(n) when n >= 0 and n < 128, do: <<0x02, 0x01, n::8>>

  defp der_integer_big(n) when is_integer(n) do
    bytes = :binary.encode_unsigned(n)
    # Add leading zero if high bit is set (to keep positive)
    bytes = if :binary.first(bytes) >= 128, do: <<0>> <> bytes, else: bytes
    der_tag(0x02, bytes)
  end

  defp der_oid(oid_tuple) do
    oid_list = Tuple.to_list(oid_tuple)
    [first, second | rest] = oid_list
    encoded = [first * 40 + second | Enum.map(rest, &encode_oid_component/1)]
    content = IO.iodata_to_binary(encoded)
    der_tag(0x06, content)
  end

  defp encode_oid_component(n) when n < 128, do: <<n::8>>

  defp encode_oid_component(n) do
    encode_oid_component_acc(n, [])
  end

  defp encode_oid_component_acc(n, acc) when n < 128 do
    IO.iodata_to_binary([<<n::8>> | acc])
  end

  defp encode_oid_component_acc(n, acc) do
    byte = Bitwise.bor(Bitwise.band(n, 0x7F), 0x80)
    encode_oid_component_acc(Bitwise.bsr(n, 7), [<<byte::8>> | acc])
  end

  defp der_context_tag(tag_num, content) when is_binary(content) do
    # Context-specific, primitive, implicit
    tag_byte = 0x80 + tag_num
    der_raw_tag(tag_byte, content)
  end

  defp der_context_constructed(tag_num, content) when is_binary(content) do
    # Context-specific, constructed
    tag_byte = 0xA0 + tag_num
    der_raw_tag(tag_byte, content)
  end

  defp der_tag(tag, content) when is_binary(content) do
    der_raw_tag(tag, content)
  end

  defp der_tag(tag, content) when is_binary(content) == false do
    der_raw_tag(tag, to_string(content))
  end

  defp der_raw_tag(tag, content) do
    len = byte_size(content)
    <<tag::8>> <> der_length(len) <> content
  end

  defp der_length(len) when len < 128, do: <<len::8>>

  defp der_length(len) do
    bytes = :binary.encode_unsigned(len)
    <<0x80 + byte_size(bytes)::8>> <> bytes
  end
end
