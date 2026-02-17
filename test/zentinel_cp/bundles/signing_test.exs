defmodule ZentinelCp.Bundles.SigningTest do
  use ExUnit.Case, async: true

  alias ZentinelCp.Bundles.Signing

  describe "generate_keypair/0" do
    test "returns a public/private key pair" do
      {public_key, private_key} = Signing.generate_keypair()

      assert is_binary(public_key)
      assert is_binary(private_key)
      assert byte_size(public_key) == 32
      assert byte_size(private_key) == 32
    end

    test "generates unique keypairs" do
      {pub1, _priv1} = Signing.generate_keypair()
      {pub2, _priv2} = Signing.generate_keypair()

      assert pub1 != pub2
    end
  end

  describe "sign/2 and verify/3" do
    test "signs data and verifies with correct key" do
      {public_key, private_key} = Signing.generate_keypair()
      data = "bundle contents here"

      signature = Signing.sign(data, private_key)

      assert is_binary(signature)
      assert Signing.verify(data, signature, public_key)
    end

    test "verification fails with wrong public key" do
      {_public_key, private_key} = Signing.generate_keypair()
      {wrong_public_key, _wrong_private_key} = Signing.generate_keypair()
      data = "bundle contents here"

      signature = Signing.sign(data, private_key)

      refute Signing.verify(data, signature, wrong_public_key)
    end

    test "verification fails with tampered data" do
      {public_key, private_key} = Signing.generate_keypair()
      data = "bundle contents here"

      signature = Signing.sign(data, private_key)

      refute Signing.verify("tampered data", signature, public_key)
    end

    test "verification fails with tampered signature" do
      {public_key, private_key} = Signing.generate_keypair()
      data = "bundle contents here"

      signature = Signing.sign(data, private_key)
      tampered_sig = :crypto.strong_rand_bytes(byte_size(signature))

      refute Signing.verify(data, tampered_sig, public_key)
    end
  end

  describe "sign_bundle/1" do
    setup do
      original_config = Application.get_env(:zentinel_cp, :bundle_signing)
      on_exit(fn -> Application.put_env(:zentinel_cp, :bundle_signing, original_config || []) end)
      :ok
    end

    test "returns signature and key_id when enabled" do
      {_public_key, private_key} = Signing.generate_keypair()

      Application.put_env(:zentinel_cp, :bundle_signing,
        enabled: true,
        key_id: "test-key-1",
        private_key: private_key
      )

      {signature, key_id} = Signing.sign_bundle("bundle data")

      assert is_binary(signature)
      assert key_id == "test-key-1"
    end

    test "returns nil when disabled" do
      Application.put_env(:zentinel_cp, :bundle_signing, enabled: false)

      {signature, key_id} = Signing.sign_bundle("bundle data")

      assert is_nil(signature)
      assert is_nil(key_id)
    end

    test "returns nil when config missing" do
      Application.put_env(:zentinel_cp, :bundle_signing, [])

      {signature, key_id} = Signing.sign_bundle("bundle data")

      assert is_nil(signature)
      assert is_nil(key_id)
    end
  end

  describe "verify_bundle/3" do
    setup do
      original_config = Application.get_env(:zentinel_cp, :bundle_signing)
      on_exit(fn -> Application.put_env(:zentinel_cp, :bundle_signing, original_config || []) end)
      :ok
    end

    test "verifies a valid signed bundle" do
      {public_key, private_key} = Signing.generate_keypair()

      Application.put_env(:zentinel_cp, :bundle_signing,
        enabled: true,
        key_id: "test-key-1",
        private_key: private_key,
        public_key: public_key
      )

      data = "bundle data"
      {signature, key_id} = Signing.sign_bundle(data)

      assert {true, "test-key-1"} = Signing.verify_bundle(data, signature, key_id)
    end

    test "rejects tampered bundle" do
      {public_key, private_key} = Signing.generate_keypair()

      Application.put_env(:zentinel_cp, :bundle_signing,
        enabled: true,
        key_id: "test-key-1",
        private_key: private_key,
        public_key: public_key
      )

      data = "bundle data"
      {signature, key_id} = Signing.sign_bundle(data)

      assert {false, "test-key-1"} = Signing.verify_bundle("tampered", signature, key_id)
    end

    test "returns false for unsigned bundles" do
      assert {false, nil} = Signing.verify_bundle("data", nil, nil)
    end
  end
end
