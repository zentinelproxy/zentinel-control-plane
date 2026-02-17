defmodule ZentinelCpWeb.Api.ApiKeyController do
  @moduledoc """
  API controller for API key management.

  All endpoints require `api_keys:admin` scope.
  """
  use ZentinelCpWeb, :controller

  alias ZentinelCp.{Accounts, Audit}

  @doc """
  POST /api/v1/api-keys
  Creates a new API key. The raw key is only returned in this response.
  """
  def create(conn, params) do
    current_api_key = conn.assigns.current_api_key

    attrs = %{
      name: params["name"],
      scopes: params["scopes"] || [],
      user_id: current_api_key.user_id,
      project_id: params["project_id"],
      expires_at: parse_expires_at(params["expires_at"])
    }

    case Accounts.create_api_key(attrs) do
      {:ok, api_key} ->
        Audit.log_api_key_action(current_api_key, "api_key.created", "api_key", api_key.id,
          changes: %{name: api_key.name, scopes: api_key.scopes, project_id: api_key.project_id}
        )

        conn
        |> put_status(:created)
        |> json(%{
          id: api_key.id,
          name: api_key.name,
          key: api_key.key,
          key_prefix: api_key.key_prefix,
          scopes: api_key.scopes,
          project_id: api_key.project_id,
          expires_at: api_key.expires_at,
          inserted_at: api_key.inserted_at
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: format_errors(changeset)})
    end
  end

  @doc """
  GET /api/v1/api-keys
  Lists API keys for the current user.
  """
  def index(conn, _params) do
    current_api_key = conn.assigns.current_api_key
    api_keys = Accounts.list_api_keys_for_user(current_api_key.user_id)

    conn
    |> put_status(:ok)
    |> json(%{
      api_keys: Enum.map(api_keys, &api_key_to_json/1),
      total: length(api_keys)
    })
  end

  @doc """
  GET /api/v1/api-keys/:id
  Shows API key details (never returns the raw key).
  """
  def show(conn, %{"id" => id}) do
    current_api_key = conn.assigns.current_api_key

    case Accounts.get_api_key(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "API key not found"})

      %{user_id: user_id} = api_key when user_id == current_api_key.user_id ->
        conn |> put_status(:ok) |> json(%{api_key: api_key_to_json(api_key)})

      _other ->
        conn |> put_status(:not_found) |> json(%{error: "API key not found"})
    end
  end

  @doc """
  POST /api/v1/api-keys/:id/revoke
  Revokes an API key.
  """
  def revoke(conn, %{"id" => id}) do
    current_api_key = conn.assigns.current_api_key

    with {:ok, api_key} <- get_owned_api_key(id, current_api_key.user_id),
         {:ok, revoked} <- Accounts.revoke_api_key(api_key) do
      Audit.log_api_key_action(current_api_key, "api_key.revoked", "api_key", api_key.id,
        metadata: %{name: api_key.name}
      )

      conn |> put_status(:ok) |> json(%{api_key: api_key_to_json(revoked)})
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "API key not found"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: format_errors(changeset)})
    end
  end

  @doc """
  DELETE /api/v1/api-keys/:id
  Permanently deletes an API key.
  """
  def delete(conn, %{"id" => id}) do
    current_api_key = conn.assigns.current_api_key

    with {:ok, api_key} <- get_owned_api_key(id, current_api_key.user_id),
         {:ok, _} <- Accounts.delete_api_key(api_key) do
      Audit.log_api_key_action(current_api_key, "api_key.deleted", "api_key", api_key.id,
        metadata: %{name: api_key.name}
      )

      conn
      |> put_status(:no_content)
      |> send_resp(:no_content, "")
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "API key not found"})
    end
  end

  # Helpers

  defp get_owned_api_key(id, user_id) do
    case Accounts.get_api_key(id) do
      nil -> {:error, :not_found}
      %{user_id: ^user_id} = api_key -> {:ok, api_key}
      _other -> {:error, :not_found}
    end
  end

  defp api_key_to_json(api_key) do
    %{
      id: api_key.id,
      name: api_key.name,
      key_prefix: api_key.key_prefix,
      scopes: api_key.scopes,
      project_id: api_key.project_id,
      last_used_at: api_key.last_used_at,
      expires_at: api_key.expires_at,
      revoked_at: api_key.revoked_at,
      inserted_at: api_key.inserted_at
    }
  end

  defp parse_expires_at(nil), do: nil

  defp parse_expires_at(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end

  defp parse_expires_at(_), do: nil

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
