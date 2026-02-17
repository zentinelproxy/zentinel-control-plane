defmodule ZentinelCp.Secrets.Secret do
  @moduledoc """
  Secret schema - encrypted key-value secrets scoped to projects and environments.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ZentinelCp.Secrets.SecretCrypto

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @name_format ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/

  schema "secrets" do
    field :name, :string
    field :slug, :string
    field :encrypted_value, :binary
    field :value, :string, virtual: true
    field :description, :string
    field :environment, :string
    field :last_rotated_at, :utc_datetime

    belongs_to :project, ZentinelCp.Projects.Project

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a secret. Encrypts the plaintext value.
  """
  def create_changeset(secret, attrs) do
    secret
    |> cast(attrs, [:name, :value, :description, :environment, :project_id])
    |> validate_required([:name, :value, :project_id])
    |> validate_format(:name, @name_format,
      message:
        "must start with a letter or underscore and contain only letters, numbers, and underscores"
    )
    |> validate_length(:name, min: 1, max: 100)
    |> generate_slug()
    |> encrypt_value()
    |> unique_constraint([:project_id, :name, :environment],
      name: :secrets_project_name_env_index,
      error_key: :name,
      message: "already exists for this environment"
    )
    |> unique_constraint([:project_id, :name, :environment],
      name: :secrets_project_id_name_environment_index,
      error_key: :name,
      message: "already exists for this environment"
    )
    |> foreign_key_constraint(:project_id)
  end

  @doc """
  Changeset for updating a secret. Re-encrypts if value changes.
  """
  def update_changeset(secret, attrs) do
    secret
    |> cast(attrs, [:value, :description, :environment])
    |> maybe_encrypt_and_rotate()
  end

  @doc """
  Changeset for rotating a secret's value.
  """
  def rotate_changeset(secret, new_value) do
    secret
    |> cast(%{value: new_value}, [:value])
    |> validate_required([:value])
    |> encrypt_value()
    |> put_change(:last_rotated_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  defp generate_slug(changeset) do
    case get_change(changeset, :name) do
      nil ->
        changeset

      name ->
        slug =
          name
          |> String.downcase()
          |> String.replace(~r/[^a-z0-9]+/, "-")
          |> String.replace(~r/^-+|-+$/, "")
          |> String.slice(0, 50)

        put_change(changeset, :slug, slug)
    end
  end

  defp encrypt_value(changeset) do
    case get_change(changeset, :value) do
      nil ->
        changeset

      value when is_binary(value) ->
        encrypted = SecretCrypto.encrypt(value)
        put_change(changeset, :encrypted_value, encrypted)

      _ ->
        changeset
    end
  end

  defp maybe_encrypt_and_rotate(changeset) do
    case get_change(changeset, :value) do
      nil ->
        changeset

      value when is_binary(value) and value != "" ->
        encrypted = SecretCrypto.encrypt(value)

        changeset
        |> put_change(:encrypted_value, encrypted)
        |> put_change(:last_rotated_at, DateTime.utc_now() |> DateTime.truncate(:second))

      _ ->
        changeset
    end
  end
end
