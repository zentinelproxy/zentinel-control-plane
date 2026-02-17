defmodule ZentinelCp.AccountsTest do
  use ZentinelCp.DataCase

  alias ZentinelCp.Accounts
  alias ZentinelCp.Accounts.{User, ApiKey}

  import ZentinelCp.AccountsFixtures
  import ZentinelCp.ProjectsFixtures

  describe "register_user/1" do
    test "creates a user with valid attributes" do
      attrs = valid_user_attributes()
      assert {:ok, %User{} = user} = Accounts.register_user(attrs)
      assert user.email == attrs.email
      assert user.role == "operator"
      assert is_binary(user.hashed_password)
      assert is_nil(user.confirmed_at)
    end

    test "returns error with invalid email" do
      assert {:error, changeset} =
               Accounts.register_user(%{email: "bad", password: valid_user_password()})

      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    test "returns error with short password" do
      assert {:error, changeset} =
               Accounts.register_user(%{email: unique_user_email(), password: "short"})

      assert %{password: ["should be at least 12 character(s)"]} = errors_on(changeset)
    end

    test "returns error with duplicate email" do
      attrs = valid_user_attributes()
      assert {:ok, _} = Accounts.register_user(attrs)
      assert {:error, changeset} = Accounts.register_user(attrs)
      assert %{email: ["has already been taken"]} = errors_on(changeset)
    end

    test "validates role inclusion" do
      attrs = valid_user_attributes(%{role: "superuser"})
      assert {:error, changeset} = Accounts.register_user(attrs)
      assert %{role: ["is invalid"]} = errors_on(changeset)
    end

    test "accepts valid roles" do
      for role <- ~w(admin operator reader) do
        attrs = valid_user_attributes(%{role: role})
        assert {:ok, %User{role: ^role}} = Accounts.register_user(attrs)
      end
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "returns user with correct credentials" do
      user = user_fixture()
      assert found = Accounts.get_user_by_email_and_password(user.email, valid_user_password())
      assert found.id == user.id
    end

    test "returns nil with wrong password" do
      user = user_fixture()
      refute Accounts.get_user_by_email_and_password(user.email, "wrong_password!!")
    end

    test "returns nil with unknown email" do
      refute Accounts.get_user_by_email_and_password("unknown@example.com", valid_user_password())
    end
  end

  describe "get_user!/1" do
    test "returns user by id" do
      user = user_fixture()
      assert Accounts.get_user!(user.id).id == user.id
    end

    test "raises for non-existent id" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!(Ecto.UUID.generate())
      end
    end
  end

  describe "update_user_password/3" do
    test "updates password with valid current password" do
      user = user_fixture()
      new_password = "new_password_123!"

      assert {:ok, _updated} =
               Accounts.update_user_password(user, valid_user_password(), %{
                 password: new_password
               })

      assert Accounts.get_user_by_email_and_password(user.email, new_password)
    end

    test "rejects invalid current password" do
      user = user_fixture()

      assert {:error, changeset} =
               Accounts.update_user_password(user, "wrong_password!!", %{
                 password: "new_password_123!"
               })

      assert %{current_password: ["is not valid"]} = errors_on(changeset)
    end
  end

  describe "update_user_role/2" do
    test "updates role" do
      user = user_fixture(%{role: "reader"})
      assert {:ok, updated} = Accounts.update_user_role(user, "admin")
      assert updated.role == "admin"
    end
  end

  describe "session tokens" do
    test "generate and verify session token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert is_binary(token)

      found = Accounts.get_user_by_session_token(token)
      assert found.id == user.id
    end

    test "returns nil for invalid token" do
      refute Accounts.get_user_by_session_token("invalid_token")
    end

    test "delete_user_session_token/1 invalidates token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert Accounts.get_user_by_session_token(token)

      Accounts.delete_user_session_token(token)
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "API keys" do
    test "create_api_key/1 generates key with hash" do
      user = user_fixture()
      project = project_fixture()

      assert {:ok, %ApiKey{} = api_key} =
               Accounts.create_api_key(%{
                 name: "test-key",
                 user_id: user.id,
                 project_id: project.id,
                 scopes: ["read"]
               })

      assert api_key.name == "test-key"
      assert is_binary(api_key.key)
      assert is_binary(api_key.key_hash)
      assert String.length(api_key.key_prefix) == 8
      assert api_key.scopes == ["read"]
    end

    test "get_api_key_by_key/1 returns active key" do
      api_key = api_key_fixture()
      raw_key = api_key.key

      found = Accounts.get_api_key_by_key(raw_key)
      assert found.id == api_key.id
    end

    test "get_api_key_by_key/1 returns nil for revoked key" do
      api_key = api_key_fixture()
      raw_key = api_key.key

      {:ok, _} = Accounts.revoke_api_key(api_key)
      refute Accounts.get_api_key_by_key(raw_key)
    end

    test "get_api_key_by_key/1 returns nil for expired key" do
      past = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)
      api_key = api_key_fixture(%{expires_at: past})
      raw_key = api_key.key

      refute Accounts.get_api_key_by_key(raw_key)
    end

    test "list_api_keys_for_user/1 returns user's keys" do
      user = user_fixture()
      api_key = api_key_fixture(%{user: user})

      keys = Accounts.list_api_keys_for_user(user.id)
      assert length(keys) == 1
      assert hd(keys).id == api_key.id
    end

    test "revoke_api_key/1 sets revoked_at" do
      api_key = api_key_fixture()
      assert {:ok, revoked} = Accounts.revoke_api_key(api_key)
      assert revoked.revoked_at
    end

    test "delete_api_key/1 removes key" do
      api_key = api_key_fixture()
      assert {:ok, _} = Accounts.delete_api_key(api_key)
      refute Accounts.get_api_key(api_key.id)
    end
  end

  describe "list_users/0" do
    test "returns all users" do
      user = user_fixture()
      users = Accounts.list_users()
      assert Enum.any?(users, &(&1.id == user.id))
    end
  end

  describe "delete_user/1" do
    test "deletes a user" do
      user = user_fixture()
      assert {:ok, _} = Accounts.delete_user(user)
      refute Accounts.get_user(user.id)
    end
  end
end
