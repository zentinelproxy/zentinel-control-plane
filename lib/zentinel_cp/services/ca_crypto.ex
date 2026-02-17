defmodule ZentinelCp.Services.CACrypto do
  @moduledoc """
  Pure cryptographic functions for internal CA operations.

  Generates CA key pairs, self-signed CA certificates, client certificates,
  and CRLs. Uses Erlang `:public_key` and `:crypto` — no external deps.
  """

  # OID constants
  @oid_cn {2, 5, 4, 3}
  @oid_ou {2, 5, 4, 11}
  @oid_basic_constraints {2, 5, 29, 19}
  @oid_key_usage {2, 5, 29, 15}
  @oid_ext_key_usage {2, 5, 29, 37}
  @oid_authority_key_id {2, 5, 29, 35}
  @oid_subject_key_id {2, 5, 29, 14}
  @oid_client_auth {1, 3, 6, 1, 5, 5, 7, 3, 2}
  @oid_crl_number {2, 5, 29, 20}

  # Algorithm identifiers (OTP 28+ requires {:asn1_OPENTYPE, _} for typed params)
  @rsa_sha256_algo {:AlgorithmIdentifier, {1, 2, 840, 113_549, 1, 1, 11},
                    {:asn1_OPENTYPE, <<5, 0>>}}
  @ec_sha384_algo {:AlgorithmIdentifier, {1, 2, 840, 10045, 4, 3, 3}, :asn1_NOVALUE}
  @ec_sha256_algo {:AlgorithmIdentifier, {1, 2, 840, 10045, 4, 3, 2}, :asn1_NOVALUE}

  @doc """
  Generates a CA key pair for the given algorithm.

  Supported algorithms: `"EC-P384"` (default), `"RSA-2048"`.
  Returns an Erlang key record.
  """
  def generate_ca_key_pair(algorithm \\ "EC-P384")

  def generate_ca_key_pair("EC-P384") do
    :public_key.generate_key({:namedCurve, :secp384r1})
  end

  def generate_ca_key_pair("RSA-2048") do
    :public_key.generate_key({:rsa, 2048, 65537})
  end

  @doc """
  Generates a self-signed CA certificate.

  Returns PEM string. The cert includes basicConstraints (CA:TRUE, pathLen:0)
  and keyUsage (keyCertSign, cRLSign).
  """
  def generate_ca_certificate(private_key, subject_cn, validity_years \\ 10) do
    subject = build_rdn_sequence([{@oid_cn, subject_cn}])

    now = DateTime.utc_now()
    not_before = format_utc_time(now)
    not_after = format_utc_time(DateTime.add(now, validity_years * 365 * 86_400, :second))
    validity = {:Validity, {:utcTime, not_before}, {:utcTime, not_after}}

    serial = :crypto.strong_rand_bytes(8) |> :binary.decode_unsigned()
    sig_algo = signature_algorithm(private_key)
    spki = build_spki(private_key)

    # CA extensions
    extensions = [
      # basicConstraints: CA:TRUE, pathLen:0
      {:Extension, @oid_basic_constraints, true,
       :public_key.der_encode(:BasicConstraints, {:BasicConstraints, true, 0})},
      # keyUsage: keyCertSign (5) + cRLSign (6) = bits 5,6
      {:Extension, @oid_key_usage, true, encode_key_usage([:keyCertSign, :cRLSign])},
      # subjectKeyIdentifier
      {:Extension, @oid_subject_key_id, false, encode_ski(private_key)}
    ]

    tbs =
      {:TBSCertificate, :v3, serial, sig_algo, subject, validity, subject, spki, :asn1_NOVALUE,
       :asn1_NOVALUE, extensions}

    tbs_der = :public_key.der_encode(:TBSCertificate, tbs)
    signature = sign(tbs_der, private_key)

    cert = {:Certificate, tbs, sig_algo, signature}
    cert_der = :public_key.der_encode(:Certificate, cert)
    :public_key.pem_encode([{:Certificate, cert_der, :not_encrypted}])
  end

  @doc """
  Issues a client certificate signed by the CA.

  Options:
    * `:subject_ou` - Organization Unit (optional)
    * `:validity_days` - Certificate validity in days (default 365)

  Returns `{cert_pem, key_pem}`.
  """
  def issue_client_certificate(ca_key, ca_cert_der, subject_cn, serial, opts \\ []) do
    subject_ou = Keyword.get(opts, :subject_ou)
    validity_days = Keyword.get(opts, :validity_days, 365)

    # Generate client key (EC P-256 for client certs — lighter than P-384)
    client_key = :public_key.generate_key({:namedCurve, :secp256r1})

    # Build subject
    rdn_attrs = [{@oid_cn, subject_cn}]
    rdn_attrs = if subject_ou, do: rdn_attrs ++ [{@oid_ou, subject_ou}], else: rdn_attrs
    subject = build_rdn_sequence(rdn_attrs)

    # Extract issuer from CA cert
    ca_otp = :public_key.pkix_decode_cert(ca_cert_der, :otp)
    ca_tbs = elem(ca_otp, 1)
    issuer = elem(ca_tbs, 6)

    now = DateTime.utc_now()
    not_before = format_utc_time(now)
    not_after = format_utc_time(DateTime.add(now, validity_days * 86_400, :second))
    validity = {:Validity, {:utcTime, not_before}, {:utcTime, not_after}}

    sig_algo = signature_algorithm(ca_key)
    spki = build_spki(client_key)

    extensions = [
      # keyUsage: digitalSignature
      {:Extension, @oid_key_usage, true, encode_key_usage([:digitalSignature])},
      # extKeyUsage: clientAuth
      {:Extension, @oid_ext_key_usage, false,
       :public_key.der_encode(:ExtKeyUsageSyntax, [@oid_client_auth])},
      # authorityKeyIdentifier
      {:Extension, @oid_authority_key_id, false, encode_aki(ca_key)}
    ]

    tbs =
      {:TBSCertificate, :v3, serial, sig_algo, issuer, validity, subject, spki, :asn1_NOVALUE,
       :asn1_NOVALUE, extensions}

    tbs_der = :public_key.der_encode(:TBSCertificate, tbs)
    signature = sign(tbs_der, ca_key)

    cert = {:Certificate, tbs, sig_algo, signature}
    cert_der = :public_key.der_encode(:Certificate, cert)
    cert_pem = :public_key.pem_encode([{:Certificate, cert_der, :not_encrypted}])
    key_pem = private_key_to_pem(client_key)

    {cert_pem, key_pem}
  end

  @doc """
  Generates a CRL (Certificate Revocation List) signed by the CA.

  `revoked_entries` is a list of `{serial, revoked_at, reason}` tuples.
  Returns CRL PEM string.
  """
  def generate_crl(ca_key, ca_cert_der, revoked_entries) do
    ca_otp = :public_key.pkix_decode_cert(ca_cert_der, :otp)
    ca_tbs = elem(ca_otp, 1)
    issuer = elem(ca_tbs, 6)

    sig_algo = signature_algorithm(ca_key)

    now = DateTime.utc_now()
    this_update = format_utc_time(now)
    next_update = format_utc_time(DateTime.add(now, 30 * 86_400, :second))

    revoked =
      Enum.map(revoked_entries, fn {serial, revoked_at, _reason} ->
        rev_time = format_utc_time(revoked_at)
        {:TBSCertList_revokedCertificates_SEQOF, serial, {:utcTime, rev_time}, :asn1_NOVALUE}
      end)

    crl_number = System.os_time(:second)

    extensions = [
      {:Extension, @oid_crl_number, false, :public_key.der_encode(:CRLNumber, crl_number)},
      {:Extension, @oid_authority_key_id, false, encode_aki(ca_key)}
    ]

    revoked_or_novalue = if revoked == [], do: :asn1_NOVALUE, else: revoked

    tbs_crl =
      {:TBSCertList, :v2, sig_algo, issuer, {:utcTime, this_update}, {:utcTime, next_update},
       revoked_or_novalue, extensions}

    tbs_der = :public_key.der_encode(:TBSCertList, tbs_crl)
    signature = sign(tbs_der, ca_key)

    crl = {:CertificateList, tbs_crl, sig_algo, signature}
    crl_der = :public_key.der_encode(:CertificateList, crl)
    :public_key.pem_encode([{:CertificateList, crl_der, :not_encrypted}])
  end

  @doc """
  Converts a private key to PEM-encoded string.
  """
  def private_key_to_pem(key) when elem(key, 0) == :ECPrivateKey do
    entry = :public_key.pem_entry_encode(:ECPrivateKey, key)
    :public_key.pem_encode([entry])
  end

  def private_key_to_pem(key) when elem(key, 0) == :RSAPrivateKey do
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

  # --- Internal helpers ---

  defp build_rdn_sequence(attrs) do
    rdn_set =
      Enum.map(attrs, fn {oid, value} ->
        [{:AttributeTypeAndValue, oid, {:utf8String, value}}]
      end)

    {:rdnSequence, rdn_set}
  end

  defp format_utc_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%y%m%d%H%M%SZ") |> to_charlist()
  end

  defp signature_algorithm(key) when elem(key, 0) == :ECPrivateKey do
    # Check curve to pick hash
    params = elem(key, 3)

    case params do
      {:namedCurve, {1, 3, 132, 0, 34}} -> @ec_sha384_algo
      _ -> @ec_sha256_algo
    end
  end

  defp signature_algorithm(key) when elem(key, 0) == :RSAPrivateKey do
    @rsa_sha256_algo
  end

  defp digest_type(key) when elem(key, 0) == :ECPrivateKey do
    params = elem(key, 3)

    case params do
      {:namedCurve, {1, 3, 132, 0, 34}} -> :sha384
      _ -> :sha256
    end
  end

  defp digest_type(key) when elem(key, 0) == :RSAPrivateKey, do: :sha256

  defp sign(data, key) do
    :public_key.sign(data, digest_type(key), key)
  end

  defp build_spki(ec_key) when elem(ec_key, 0) == :ECPrivateKey do
    public_key_bytes = elem(ec_key, 4)
    params = elem(ec_key, 3)
    algo = {:AlgorithmIdentifier, {1, 2, 840, 10045, 2, 1}, params}
    {:SubjectPublicKeyInfo, algo, public_key_bytes}
  end

  defp build_spki(rsa_key) when elem(rsa_key, 0) == :RSAPrivateKey do
    modulus = elem(rsa_key, 2)
    pub_exp = elem(rsa_key, 3)
    algo = {:AlgorithmIdentifier, {1, 2, 840, 113_549, 1, 1, 1}, {:asn1_OPENTYPE, <<5, 0>>}}
    pub_key_der = :public_key.der_encode(:RSAPublicKey, {:RSAPublicKey, modulus, pub_exp})
    {:SubjectPublicKeyInfo, algo, pub_key_der}
  end

  defp encode_key_usage(usages) do
    :public_key.der_encode(:KeyUsage, usages)
  end

  defp encode_ski(key) do
    pub_bytes = extract_public_key_bytes(key)
    ski = :crypto.hash(:sha, pub_bytes)
    :public_key.der_encode(:SubjectKeyIdentifier, ski)
  end

  defp encode_aki(key) do
    pub_bytes = extract_public_key_bytes(key)
    key_id = :crypto.hash(:sha, pub_bytes)

    :public_key.der_encode(
      :AuthorityKeyIdentifier,
      {:AuthorityKeyIdentifier, key_id, :asn1_NOVALUE, :asn1_NOVALUE}
    )
  end

  defp extract_public_key_bytes(key) when elem(key, 0) == :ECPrivateKey do
    elem(key, 4)
  end

  defp extract_public_key_bytes(key) when elem(key, 0) == :RSAPrivateKey do
    modulus = elem(key, 2)
    pub_exp = elem(key, 3)
    :public_key.der_encode(:RSAPublicKey, {:RSAPublicKey, modulus, pub_exp})
  end
end
