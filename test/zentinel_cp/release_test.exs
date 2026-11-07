defmodule ZentinelCp.ReleaseTest do
  use ZentinelCp.DataCase, async: false

  import ExUnit.CaptureIO

  alias ZentinelCp.{Accounts, Orgs, Release}
  alias ZentinelCp.Accounts.User

  @password "a-long-unique-password-1"

  describe "create_first_admin/2" do
    test "creates an admin and a default org" do
      capture_io(fn ->
        assert :ok = Release.create_first_admin("root@example.com", @password)
      end)

      user = Accounts.get_user_by_email("root@example.com")
      assert user.role == "admin"
      assert [{org, "admin"}] = Orgs.list_user_orgs(user.id)
      assert org.name == "Default"
    end

    test "does nothing without credentials, and creates no default account" do
      capture_io(fn -> assert :no_credentials = Release.create_first_admin(nil, nil) end)
      assert Repo.aggregate(User, :count) == 0
    end

    test "does not recreate an admin once any user exists" do
      ZentinelCp.AccountsFixtures.user_fixture()

      assert :already_bootstrapped = Release.create_first_admin("root@example.com", @password)
      refute Accounts.get_user_by_email("root@example.com")
    end

    test "refuses a weak password" do
      assert_raise RuntimeError, fn -> Release.create_first_admin("root@example.com", "short") end
    end
  end

  describe "SecretRotation" do
    test "moves stored secrets to the current key" do
      org = ZentinelCp.OrgsFixtures.org_fixture()
      old = :crypto.strong_rand_bytes(32)
      on_exit(fn -> Application.delete_env(:zentinel_cp, :encryption_keys) end)

      Application.put_env(:zentinel_cp, :encryption_keys, [old])
      {:ok, key} = ZentinelCp.Auth.create_signing_key(org.id)
      plaintext = key.private_key_encrypted

      new = :crypto.strong_rand_bytes(32)
      Application.put_env(:zentinel_cp, :encryption_keys, [new, old])
      ZentinelCp.SecretRotation.run()

      Application.put_env(:zentinel_cp, :encryption_keys, [new])
      assert Repo.get(ZentinelCp.Auth.SigningKey, key.id).private_key_encrypted == plaintext
    end
  end
end
