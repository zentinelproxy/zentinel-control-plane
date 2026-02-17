defmodule ZentinelCp.Secrets do
  @moduledoc """
  The Secrets context manages encrypted project secrets.

  Secrets are scoped to projects and optionally environments. They can be
  referenced in service configuration using `${secrets.NAME}` syntax and
  are resolved at bundle compile time.
  """

  import Ecto.Query, warn: false
  alias ZentinelCp.Repo
  alias ZentinelCp.Secrets.{Secret, SecretCrypto, VaultConfig}

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

  ## Vault Config

  @doc """
  Gets the Vault config for a project.
  """
  def get_vault_config(project_id) do
    Repo.get_by(VaultConfig, project_id: project_id)
  end

  @doc """
  Creates a Vault config for a project.
  """
  def create_vault_config(attrs) do
    %VaultConfig{}
    |> VaultConfig.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a Vault config.
  """
  def update_vault_config(%VaultConfig{} = config, attrs) do
    config
    |> VaultConfig.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a Vault config.
  """
  def delete_vault_config(%VaultConfig{} = config) do
    Repo.delete(config)
  end

  @doc """
  Tests the Vault connection by calling the health endpoint.
  Updates the VaultConfig with the connection status.
  """
  def test_vault_connection(project_id) do
    case get_vault_config(project_id) do
      nil ->
        {:error, :not_configured}

      config ->
        with {:ok, auth_config} <- VaultConfig.decrypt_auth_config(config.auth_config) do
          vault_config_map = %{
            vault_addr: config.vault_addr,
            auth_method: config.auth_method,
            auth_config: auth_config,
            mount_path: config.mount_path,
            base_path: config.base_path,
            namespace: config.namespace
          }

          case vault_client().health(vault_config_map) do
            {:ok, health} ->
              now = DateTime.utc_now() |> DateTime.truncate(:second)
              status = if health.sealed, do: "sealed", else: "connected"

              config
              |> VaultConfig.status_changeset(%{
                last_connected_at: now,
                connection_status: status
              })
              |> Repo.update()

              {:ok, health}

            {:error, reason} ->
              config
              |> VaultConfig.status_changeset(%{connection_status: "error"})
              |> Repo.update()

              {:error, reason}
          end
        end
    end
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
      {:ok, local_map} ->
        # Merge Vault secrets if enabled (Vault wins on conflict)
        case merge_vault_secrets(local_map, project_id, config_map) do
          {:ok, merged_map} -> resolve_map(config_map, merged_map)
          error -> error
        end

      error ->
        error
    end
  end

  defp merge_vault_secrets(local_map, project_id, config_map) do
    case get_vault_config(project_id) do
      %VaultConfig{enabled: true} = vault_config ->
        referenced_names = find_references(config_map)
        missing_names = Enum.filter(referenced_names, &(not Map.has_key?(local_map, &1)))

        if missing_names == [] do
          {:ok, local_map}
        else
          with {:ok, auth_config} <- VaultConfig.decrypt_auth_config(vault_config.auth_config) do
            vault_map = %{
              vault_addr: vault_config.vault_addr,
              auth_method: vault_config.auth_method,
              auth_config: auth_config,
              mount_path: vault_config.mount_path,
              base_path: vault_config.base_path,
              namespace: vault_config.namespace
            }

            vault_secrets =
              Enum.reduce_while(missing_names, {:ok, %{}}, fn name, {:ok, acc} ->
                case vault_client().read_secret(vault_map, name) do
                  {:ok, %{"value" => value}} ->
                    {:cont, {:ok, Map.put(acc, name, value)}}

                  {:ok, data} when is_map(data) ->
                    # Use the first value if it's a flat map
                    value = data |> Map.values() |> List.first() || ""
                    {:cont, {:ok, Map.put(acc, name, value)}}

                  {:error, :not_found} ->
                    {:cont, {:ok, acc}}

                  {:error, reason} ->
                    {:halt, {:error, {:vault_error, name, reason}}}
                end
              end)

            case vault_secrets do
              {:ok, fetched} -> {:ok, Map.merge(local_map, fetched)}
              error -> error
            end
          end
        end

      _ ->
        {:ok, local_map}
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

  defp vault_client do
    Application.get_env(:zentinel_cp, :vault_client, ZentinelCp.Secrets.VaultClient.HTTP)
  end
end
