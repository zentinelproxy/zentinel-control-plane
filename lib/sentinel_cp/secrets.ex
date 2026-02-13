defmodule SentinelCp.Secrets do
  @moduledoc """
  The Secrets context manages encrypted project secrets.

  Secrets are scoped to projects and optionally environments. They can be
  referenced in service configuration using `${secrets.NAME}` syntax and
  are resolved at bundle compile time.
  """

  import Ecto.Query, warn: false
  alias SentinelCp.Repo
  alias SentinelCp.Secrets.{Secret, SecretCrypto}

  @secret_ref_pattern ~r/\$\{secrets\.([a-zA-Z_][a-zA-Z0-9_]*)\}/

  ## CRUD

  @doc """
  Lists secrets for a project (without decrypting values).
  """
  def list_secrets(project_id) do
    from(s in Secret,
      where: s.project_id == ^project_id,
      order_by: [asc: s.name]
    )
    |> Repo.all()
  end

  @doc """
  Lists secrets for a project filtered by environment.
  Returns secrets matching the environment or with nil environment (global).
  """
  def list_secrets(project_id, environment) do
    from(s in Secret,
      where: s.project_id == ^project_id,
      where: is_nil(s.environment) or s.environment == ^environment,
      order_by: [asc: s.name]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single secret by ID.
  """
  def get_secret(id), do: Repo.get(Secret, id)

  @doc """
  Gets a single secret by ID, raises if not found.
  """
  def get_secret!(id), do: Repo.get!(Secret, id)

  @doc """
  Creates a secret with encrypted value.
  """
  def create_secret(attrs) do
    %Secret{}
    |> Secret.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a secret. Re-encrypts value if changed.
  """
  def update_secret(%Secret{} = secret, attrs) do
    secret
    |> Secret.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a secret.
  """
  def delete_secret(%Secret{} = secret) do
    Repo.delete(secret)
  end

  @doc """
  Rotates a secret's value: updates value and sets last_rotated_at.
  """
  def rotate_secret(%Secret{} = secret, new_value) do
    secret
    |> Secret.rotate_changeset(new_value)
    |> Repo.update()
  end

  @doc """
  Decrypts a secret's value, returning `{:ok, plaintext}` or `{:error, reason}`.
  """
  def decrypt_value(%Secret{encrypted_value: encrypted}) do
    SecretCrypto.decrypt(encrypted)
  end

  ## Reference Resolution

  @doc """
  Resolves `${secrets.NAME}` references in a config map.

  Walks the map recursively, replacing secret references with decrypted values.
  Returns `{:ok, resolved_map}` or `{:error, {:missing_secret, name}}`.
  """
  def resolve_references(config_map, project_id, environment \\ nil) when is_map(config_map) do
    # Load all applicable secrets for this project/environment
    secrets =
      if environment do
        list_secrets(project_id, environment)
      else
        list_secrets(project_id)
      end

    # Build name -> decrypted value map
    secret_map =
      Enum.reduce_while(secrets, {:ok, %{}}, fn secret, {:ok, acc} ->
        case decrypt_value(secret) do
          {:ok, value} ->
            # For env-scoped secrets, the env-specific one wins over global
            {:cont, {:ok, Map.put(acc, secret.name, value)}}

          {:error, reason} ->
            {:halt, {:error, {:decryption_failed, secret.name, reason}}}
        end
      end)

    case secret_map do
      {:ok, map} -> resolve_map(config_map, map)
      error -> error
    end
  end

  @doc """
  Returns a list of secret names referenced in a config map (no decryption).
  """
  def find_references(config_map) when is_map(config_map) do
    find_refs_in_value(config_map)
    |> Enum.uniq()
  end

  ## Private

  defp resolve_map(map, secret_map) when is_map(map) do
    Enum.reduce_while(map, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      case resolve_value(value, secret_map) do
        {:ok, resolved} -> {:cont, {:ok, Map.put(acc, key, resolved)}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp resolve_value(value, secret_map) when is_binary(value) do
    refs = Regex.scan(@secret_ref_pattern, value)

    Enum.reduce_while(refs, {:ok, value}, fn [_full, name], {:ok, current} ->
      case Map.fetch(secret_map, name) do
        {:ok, secret_value} ->
          resolved = String.replace(current, "${secrets.#{name}}", secret_value)
          {:cont, {:ok, resolved}}

        :error ->
          {:halt, {:error, {:missing_secret, name}}}
      end
    end)
  end

  defp resolve_value(value, secret_map) when is_map(value) do
    resolve_map(value, secret_map)
  end

  defp resolve_value(value, secret_map) when is_list(value) do
    Enum.reduce_while(value, {:ok, []}, fn item, {:ok, acc} ->
      case resolve_value(item, secret_map) do
        {:ok, resolved} -> {:cont, {:ok, acc ++ [resolved]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp resolve_value(value, _secret_map), do: {:ok, value}

  defp find_refs_in_value(value) when is_binary(value) do
    Regex.scan(@secret_ref_pattern, value)
    |> Enum.map(fn [_full, name] -> name end)
  end

  defp find_refs_in_value(value) when is_map(value) do
    Enum.flat_map(value, fn {_key, v} -> find_refs_in_value(v) end)
  end

  defp find_refs_in_value(value) when is_list(value) do
    Enum.flat_map(value, &find_refs_in_value/1)
  end

  defp find_refs_in_value(_), do: []
end
