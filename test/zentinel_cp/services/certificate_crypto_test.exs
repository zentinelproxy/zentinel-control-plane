defmodule ZentinelCp.Services.CertificateCryptoTest do
  use ZentinelCp.DataCase, async: true

  alias ZentinelCp.Services.CertificateCrypto

  describe "encrypt/1 and decrypt/1" do
    test "round-trips a plaintext string" do
      plaintext = "-----BEGIN PRIVATE KEY-----\nMIIEvQI...\n-----END PRIVATE KEY-----"
      encrypted = CertificateCrypto.encrypt(plaintext)

      assert is_binary(encrypted)
      assert encrypted != plaintext
      assert byte_size(encrypted) > byte_size(plaintext)

      assert {:ok, ^plaintext} = CertificateCrypto.decrypt(encrypted)
    end

    test "produces different ciphertexts for the same plaintext (random IV)" do
      plaintext = "test-key-data"
      enc1 = CertificateCrypto.encrypt(plaintext)
      enc2 = CertificateCrypto.encrypt(plaintext)

      assert enc1 != enc2
      assert {:ok, ^plaintext} = CertificateCrypto.decrypt(enc1)
      assert {:ok, ^plaintext} = CertificateCrypto.decrypt(enc2)
    end

    test "returns error for tampered ciphertext" do
      plaintext = "sensitive-data"
      encrypted = CertificateCrypto.encrypt(plaintext)

      # Flip a byte in the ciphertext portion (after IV + tag)
      <<iv::binary-12, tag::binary-16, ciphertext::binary>> = encrypted

      tampered_ciphertext =
        :binary.copy(ciphertext)
        |> then(fn c ->
          <<first, rest::binary>> = c
          <<Bitwise.bxor(first, 0xFF), rest::binary>>
        end)

      tampered = iv <> tag <> tampered_ciphertext
      assert {:error, :decryption_failed} = CertificateCrypto.decrypt(tampered)
    end

    test "handles empty string" do
      encrypted = CertificateCrypto.encrypt("")
      assert {:ok, ""} = CertificateCrypto.decrypt(encrypted)
    end

    test "handles large binary" do
      plaintext = String.duplicate("A", 10_000)
      encrypted = CertificateCrypto.encrypt(plaintext)
      assert {:ok, ^plaintext} = CertificateCrypto.decrypt(encrypted)
    end
  end
end
