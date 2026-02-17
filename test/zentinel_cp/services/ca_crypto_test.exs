defmodule ZentinelCp.Services.CACryptoTest do
  use ExUnit.Case, async: true

  alias ZentinelCp.Services.CACrypto

  describe "generate_ca_key_pair/1" do
    test "generates EC P-384 key" do
      key = CACrypto.generate_ca_key_pair("EC-P384")
      assert elem(key, 0) == :ECPrivateKey
      # P-384 public key = 0x04 || x(48 bytes) || y(48 bytes) = 97 bytes
      assert byte_size(elem(key, 4)) == 97
    end

    test "generates RSA 2048 key" do
      key = CACrypto.generate_ca_key_pair("RSA-2048")
      assert elem(key, 0) == :RSAPrivateKey
    end

    test "defaults to EC P-384" do
      key = CACrypto.generate_ca_key_pair()
      assert elem(key, 0) == :ECPrivateKey
    end
  end

  describe "generate_ca_certificate/3" do
    test "generates a valid self-signed CA certificate with EC key" do
      key = CACrypto.generate_ca_key_pair("EC-P384")
      pem = CACrypto.generate_ca_certificate(key, "Test CA", 5)

      assert String.starts_with?(pem, "-----BEGIN CERTIFICATE-----")
      assert String.contains?(pem, "-----END CERTIFICATE-----")

      # Parse and verify
      [{:Certificate, der, _}] = :public_key.pem_decode(pem)
      cert = :public_key.pkix_decode_cert(der, :otp)
      tbs = elem(cert, 1)

      # Check subject CN
      {:rdnSequence, rdn_seq} = elem(tbs, 6)
      cn = extract_cn(rdn_seq)
      assert cn == "Test CA"

      # Check extensions for basicConstraints CA:TRUE
      extensions = elem(tbs, 10)
      assert is_list(extensions)

      bc_ext = Enum.find(extensions, fn {:Extension, oid, _, _} -> oid == {2, 5, 29, 19} end)
      assert bc_ext != nil
    end

    test "generates a valid CA certificate with RSA key" do
      key = CACrypto.generate_ca_key_pair("RSA-2048")
      pem = CACrypto.generate_ca_certificate(key, "RSA CA")

      assert String.starts_with?(pem, "-----BEGIN CERTIFICATE-----")
      [{:Certificate, der, _}] = :public_key.pem_decode(pem)
      cert = :public_key.pkix_decode_cert(der, :otp)
      tbs = elem(cert, 1)
      {:rdnSequence, rdn_seq} = elem(tbs, 6)
      assert extract_cn(rdn_seq) == "RSA CA"
    end
  end

  describe "issue_client_certificate/5" do
    test "issues a certificate signed by the CA" do
      ca_key = CACrypto.generate_ca_key_pair("EC-P384")
      ca_pem = CACrypto.generate_ca_certificate(ca_key, "Test CA")
      [{:Certificate, ca_der, _}] = :public_key.pem_decode(ca_pem)

      {cert_pem, key_pem} =
        CACrypto.issue_client_certificate(ca_key, ca_der, "client.example.com", 1)

      assert String.starts_with?(cert_pem, "-----BEGIN CERTIFICATE-----")
      assert String.starts_with?(key_pem, "-----BEGIN EC PRIVATE KEY-----")

      # Parse client cert
      [{:Certificate, client_der, _}] = :public_key.pem_decode(cert_pem)
      client_cert = :public_key.pkix_decode_cert(client_der, :otp)
      client_tbs = elem(client_cert, 1)

      # Check subject CN
      {:rdnSequence, rdn_seq} = elem(client_tbs, 6)
      assert extract_cn(rdn_seq) == "client.example.com"

      # Check serial
      assert elem(client_tbs, 2) == 1

      # Check extensions include extKeyUsage with clientAuth
      extensions = elem(client_tbs, 10)
      eku_ext = Enum.find(extensions, fn {:Extension, oid, _, _} -> oid == {2, 5, 29, 37} end)
      assert eku_ext != nil
    end

    test "issues certificate with OU" do
      ca_key = CACrypto.generate_ca_key_pair("EC-P384")
      ca_pem = CACrypto.generate_ca_certificate(ca_key, "Test CA")
      [{:Certificate, ca_der, _}] = :public_key.pem_decode(ca_pem)

      {cert_pem, _key_pem} =
        CACrypto.issue_client_certificate(ca_key, ca_der, "client.example.com", 2,
          subject_ou: "Engineering"
        )

      [{:Certificate, client_der, _}] = :public_key.pem_decode(cert_pem)
      client_cert = :public_key.pkix_decode_cert(client_der, :otp)
      client_tbs = elem(client_cert, 1)
      {:rdnSequence, rdn_seq} = elem(client_tbs, 6)

      ou = extract_ou(rdn_seq)
      assert ou == "Engineering"
    end

    test "issues certificate with RSA CA" do
      ca_key = CACrypto.generate_ca_key_pair("RSA-2048")
      ca_pem = CACrypto.generate_ca_certificate(ca_key, "RSA CA")
      [{:Certificate, ca_der, _}] = :public_key.pem_decode(ca_pem)

      {cert_pem, _key_pem} =
        CACrypto.issue_client_certificate(ca_key, ca_der, "rsa-client", 1)

      assert String.starts_with?(cert_pem, "-----BEGIN CERTIFICATE-----")
    end
  end

  describe "generate_crl/3" do
    test "generates a CRL with revoked entries" do
      ca_key = CACrypto.generate_ca_key_pair("EC-P384")
      ca_pem = CACrypto.generate_ca_certificate(ca_key, "Test CA")
      [{:Certificate, ca_der, _}] = :public_key.pem_decode(ca_pem)

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      revoked = [{1, now, "keyCompromise"}, {3, now, "unspecified"}]

      crl_pem = CACrypto.generate_crl(ca_key, ca_der, revoked)

      assert String.starts_with?(crl_pem, "-----BEGIN X509 CRL-----")
      assert String.contains?(crl_pem, "-----END X509 CRL-----")
    end

    test "generates an empty CRL" do
      ca_key = CACrypto.generate_ca_key_pair("EC-P384")
      ca_pem = CACrypto.generate_ca_certificate(ca_key, "Test CA")
      [{:Certificate, ca_der, _}] = :public_key.pem_decode(ca_pem)

      crl_pem = CACrypto.generate_crl(ca_key, ca_der, [])

      assert String.starts_with?(crl_pem, "-----BEGIN X509 CRL-----")
    end
  end

  describe "PEM round-trip" do
    test "EC key round-trips through PEM" do
      key = CACrypto.generate_ca_key_pair("EC-P384")
      pem = CACrypto.private_key_to_pem(key)
      {:ok, decoded} = CACrypto.pem_to_private_key(pem)

      assert elem(decoded, 0) == :ECPrivateKey
      assert elem(decoded, 1) == elem(key, 1)
    end

    test "RSA key round-trips through PEM" do
      key = CACrypto.generate_ca_key_pair("RSA-2048")
      pem = CACrypto.private_key_to_pem(key)
      {:ok, decoded} = CACrypto.pem_to_private_key(pem)

      assert elem(decoded, 0) == :RSAPrivateKey
      assert elem(decoded, 2) == elem(key, 2)
    end

    test "returns error for invalid PEM" do
      assert {:error, :invalid_pem} = CACrypto.pem_to_private_key("not-a-pem")
    end
  end

  # Helpers for extracting CN/OU from RDN sequence
  defp extract_cn(rdn_seq) do
    rdn_seq
    |> List.flatten()
    |> Enum.find_value(fn
      {:AttributeTypeAndValue, {2, 5, 4, 3}, {:utf8String, value}} -> to_string(value)
      _ -> nil
    end)
  end

  defp extract_ou(rdn_seq) do
    rdn_seq
    |> List.flatten()
    |> Enum.find_value(fn
      {:AttributeTypeAndValue, {2, 5, 4, 11}, {:utf8String, value}} -> to_string(value)
      _ -> nil
    end)
  end
end
