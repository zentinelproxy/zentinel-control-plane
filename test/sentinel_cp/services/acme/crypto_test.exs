defmodule SentinelCp.Services.Acme.CryptoTest do
  use ExUnit.Case, async: true

  alias SentinelCp.Services.Acme.Crypto

  describe "generate_account_key/0" do
    test "generates an EC P-256 key" do
      key = Crypto.generate_account_key()
      assert elem(key, 0) == :ECPrivateKey
      # EC key should have a public key component (index 4)
      assert is_binary(elem(key, 4))
    end

    test "generates unique keys" do
      key1 = Crypto.generate_account_key()
      key2 = Crypto.generate_account_key()
      assert elem(key1, 2) != elem(key2, 2)
    end
  end

  describe "generate_cert_key/0" do
    test "generates an RSA 2048-bit key" do
      key = Crypto.generate_cert_key()
      assert elem(key, 0) == :RSAPrivateKey
    end
  end

  describe "build_csr/2" do
    test "builds a DER-encoded CSR for a single domain" do
      key = Crypto.generate_cert_key()
      assert {:ok, csr_der} = Crypto.build_csr(key, ["example.com"])
      assert is_binary(csr_der)
      assert byte_size(csr_der) > 0
    end

    test "builds a CSR with multiple SAN domains" do
      key = Crypto.generate_cert_key()
      domains = ["example.com", "www.example.com", "api.example.com"]
      assert {:ok, csr_der} = Crypto.build_csr(key, domains)
      assert is_binary(csr_der)
    end

    test "builds a CSR with an EC key" do
      key = Crypto.generate_account_key()
      assert {:ok, csr_der} = Crypto.build_csr(key, ["example.com"])
      assert is_binary(csr_der)
    end
  end

  describe "jwk_thumbprint/1" do
    test "returns a base64url-encoded SHA-256 thumbprint" do
      key = Crypto.generate_account_key()
      thumbprint = Crypto.jwk_thumbprint(key)
      assert is_binary(thumbprint)
      # SHA-256 = 32 bytes, base64url without padding ~ 43 chars
      assert String.length(thumbprint) == 43
      # Should be valid base64url (no + or / or =)
      refute String.contains?(thumbprint, ["+", "/", "="])
    end

    test "same key produces same thumbprint" do
      key = Crypto.generate_account_key()
      assert Crypto.jwk_thumbprint(key) == Crypto.jwk_thumbprint(key)
    end

    test "different keys produce different thumbprints" do
      key1 = Crypto.generate_account_key()
      key2 = Crypto.generate_account_key()
      refute Crypto.jwk_thumbprint(key1) == Crypto.jwk_thumbprint(key2)
    end
  end

  describe "key_authorization/2" do
    test "returns token.thumbprint format" do
      key = Crypto.generate_account_key()
      token = "test-token-abc123"
      key_auth = Crypto.key_authorization(token, key)
      assert String.starts_with?(key_auth, "test-token-abc123.")
      [^token, thumbprint] = String.split(key_auth, ".", parts: 2)
      assert thumbprint == Crypto.jwk_thumbprint(key)
    end
  end

  describe "private_key_to_pem/1 and pem_to_private_key/1" do
    test "round-trips an EC key" do
      key = Crypto.generate_account_key()
      pem = Crypto.private_key_to_pem(key)
      assert String.starts_with?(pem, "-----BEGIN EC PRIVATE KEY-----")
      assert {:ok, decoded} = Crypto.pem_to_private_key(pem)
      assert elem(decoded, 0) == :ECPrivateKey
      # Private key bytes should match
      assert elem(decoded, 2) == elem(key, 2)
    end

    test "round-trips an RSA key" do
      key = Crypto.generate_cert_key()
      pem = Crypto.private_key_to_pem(key)
      assert String.starts_with?(pem, "-----BEGIN RSA PRIVATE KEY-----")
      assert {:ok, decoded} = Crypto.pem_to_private_key(pem)
      assert elem(decoded, 0) == :RSAPrivateKey
      # Modulus should match
      assert elem(decoded, 2) == elem(key, 2)
    end

    test "returns error for invalid PEM" do
      assert {:error, :invalid_pem} = Crypto.pem_to_private_key("not a pem")
    end
  end

  describe "ec_key_to_jwk/1" do
    test "returns a JWK map with required fields" do
      key = Crypto.generate_account_key()
      jwk = Crypto.ec_key_to_jwk(key)

      assert jwk["kty"] == "EC"
      assert jwk["crv"] == "P-256"
      assert is_binary(jwk["x"])
      assert is_binary(jwk["y"])
      # x and y should be 32 bytes base64url-encoded (43 chars without padding)
      assert String.length(jwk["x"]) == 43
      assert String.length(jwk["y"]) == 43
    end
  end
end
