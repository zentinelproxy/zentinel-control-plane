defmodule ZentinelCp.Accounts do
  @moduledoc """
  The Accounts context handles user authentication and API key management.
  """

  import Ecto.Query, warn: false
  alias ZentinelCp.Repo
  alias ZentinelCp.Accounts.{User, UserToken, ApiKey}

  ## User Registration

  @doc """
  Registers a user.
  """
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.
  """
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false, validate_email: false)
  end

  ## User Authentication

  @doc """
  Gets a user by email.
  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.
  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.
  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Gets a user by id.
  """
  def get_user(id), do: Repo.get(User, id)

  ## User Settings

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.
  """
  def change_user_email(user, attrs \\ %{}) do
    User.email_changeset(user, attrs, validate_email: false)
  end

  @doc """
  Updates the user email.
  """
  def update_user_email(user, attrs) do
    user
    |> User.email_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.
  """
  def change_user_password(user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end

  @doc """
  Updates the user password.
  """
  def update_user_password(user, password, attrs) do
    changeset =
      user
      |> User.password_changeset(attrs)
      |> User.validate_current_password(password)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Updates the user role.
  """
  def update_user_role(user, role) do
    user
    |> User.role_changeset(%{role: role})
    |> Repo.update()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.by_token_and_context_query(token, "session"))
    :ok
  end

  ## API Keys

  @doc """
  Lists all API keys for a user.
  """
  def list_api_keys_for_user(user_id) do
    from(k in ApiKey, where: k.user_id == ^user_id, order_by: [desc: k.inserted_at])
    |> Repo.all()
  end

  @doc """
  Lists all API keys for a project.
  """
  def list_api_keys_for_project(project_id) do
    from(k in ApiKey, where: k.project_id == ^project_id, order_by: [desc: k.inserted_at])
    |> Repo.all()
  end

  @doc """
  Gets an API key by ID.
  """
  def get_api_key(id), do: Repo.get(ApiKey, id)

  @doc """
  Gets an API key by its raw key value.
  Returns nil if not found or if the key is invalid.
  """
  def get_api_key_by_key(raw_key) when is_binary(raw_key) do
    key_hash = ApiKey.hash_key(raw_key)

    from(k in ApiKey, where: k.key_hash == ^key_hash)
    |> Repo.one()
    |> case do
      nil -> nil
      api_key -> if ApiKey.active?(api_key), do: api_key
    end
  end

  @doc """
  Creates an API key. Returns {:ok, api_key_with_raw_key} or {:error, changeset}.
  The raw key is only available immediately after creation.
  """
  def create_api_key(attrs) do
    %ApiKey{}
    |> ApiKey.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Revokes an API key.
  """
  def revoke_api_key(%ApiKey{} = api_key) do
    api_key
    |> ApiKey.revoke_changeset()
    |> Repo.update()
  end

  @doc """
  Touches an API key (updates last_used_at).
  """
  def touch_api_key(%ApiKey{} = api_key) do
    api_key
    |> ApiKey.touch_changeset()
    |> Repo.update()
  end

  @doc """
  Deletes an API key.
  """
  def delete_api_key(%ApiKey{} = api_key) do
    Repo.delete(api_key)
  end

  ## Admin

  @doc """
  Lists all users.
  """
  def list_users do
    Repo.all(User)
  end

  @doc """
  Deletes a user.
  """
  def delete_user(%User{} = user) do
    Repo.delete(user)
  end
end
