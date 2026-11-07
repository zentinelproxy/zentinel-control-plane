defmodule ZentinelCp.Auth.EncryptionTest do
  use ZentinelCp.DataCase, async: false

  alias ZentinelCp.Auth
  alias ZentinelCp.Auth.Encryption
  alias ZentinelCp.Encrypted

  defp with_keys(keys) do
    original = Application.fetch_env(:zentinel_cp, :encryption_keys)
    Application.put_env(:zentinel_cp, :encryption_keys, keys)

    on_exit(fn ->
      case original do
        {:ok, previous} -> Application.put_env(:zentinel_cp, :encryption_keys, previous)
        :error -> Application.delete_env(:zentinel_cp, :encryption_keys)
      end
    end)
  end

  defp legacy_encrypt(plaintext, aad) do
    secret = Application.get_env(:zentinel_cp, ZentinelCpWeb.Endpoint)[:secret_key_base]
    iv = :crypto.strong_rand_bytes(12)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(
        :aes_256_gcm,
        :crypto.hash(:sha256, secret),
        iv,
        plaintext,
        aad,
        true
      )

    iv <> tag <> ciphertext
  end

  test "round trips with the configured key" do
    with_keys([:crypto.strong_rand_bytes(32)])
    encrypted = Encryption.encrypt("secret")
    refute encrypted =~ "secret"
    assert Encryption.decrypt(encrypted) == "secret"
    assert Encryption.current?(encrypted)
  end

  test "old keys still decrypt after rotation" do
    old = :crypto.strong_rand_bytes(32)
    with_keys([old])
    encrypted = Encryption.encrypt("secret")

    with_keys([:crypto.strong_rand_bytes(32), old])
    assert Encryption.decrypt(encrypted) == "secret"
    refute Encryption.current?(encrypted)
  end

  test "an unknown key cannot decrypt" do
    with_keys([:crypto.strong_rand_bytes(32)])
    encrypted = Encryption.encrypt("secret")
    with_keys([:crypto.strong_rand_bytes(32)])
    assert Encryption.decrypt(encrypted) == nil
  end

  test "data encrypted before versioning can still be read" do
    with_keys([:crypto.strong_rand_bytes(32)])
    legacy = legacy_encrypt("secret", "ZentinelCp.Auth.Encryption")
    assert Encryption.decrypt(legacy) == "secret"
    refute Encryption.current?(legacy)
  end

  test "signing keys are not stored in plaintext" do
    org = ZentinelCp.OrgsFixtures.org_fixture()
    {:ok, key} = Auth.create_signing_key(org.id)
    assert byte_size(key.private_key_encrypted) == 64

    stored =
      Repo.one(
        from(k in "org_signing_keys",
          where: k.key_id == ^key.key_id,
          select: k.private_key_encrypted
        )
      )

    refute stored == key.private_key_encrypted
    assert Encryption.encrypted?(stored)

    assert Repo.get(Auth.SigningKey, key.id).private_key_encrypted == key.private_key_encrypted
  end

  test "encrypted types return values written before encryption" do
    assert {:ok, "raw"} = Encrypted.Binary.load("raw")
    assert {:ok, "raw"} = Encrypted.String.load("raw")
    assert {:ok, %{"a" => 1}} = Encrypted.Map.load(%{"a" => 1})
  end

  test "encrypted types round trip" do
    assert {:ok, dumped} = Encrypted.Binary.dump("value")
    assert {:ok, "value"} = Encrypted.Binary.load(dumped)
    assert {:ok, dumped} = Encrypted.String.dump("value")
    assert {:ok, "value"} = Encrypted.String.load(dumped)
    assert {:ok, %{"__enc__" => _} = dumped} = Encrypted.Map.dump(%{"url" => "https://x"})
    assert {:ok, %{"url" => "https://x"}} = Encrypted.Map.load(dumped)
  end
end
