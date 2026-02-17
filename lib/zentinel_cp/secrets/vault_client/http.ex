defmodule ZentinelCp.Secrets.VaultClient.HTTP do
  @moduledoc """
  HTTP implementation of the Vault client using Req.

  Supports KV v2 secret engine and multiple auth methods:
  - Token: direct `X-Vault-Token` header
  - AppRole: login via `role_id` + `secret_id`
  - Kubernetes: login via service account JWT
  """

  @behaviour ZentinelCp.Secrets.VaultClient

  @impl true
  def read_secret(config, path) do
    with {:ok, token} <- authenticate(config) do
      mount = config.mount_path || "secret"
      full_path = build_path(config.base_path, path)
      url = "#{config.vault_addr}/v1/#{mount}/data/#{full_path}"

      headers = build_headers(token, config)

      case Req.get(url, headers: headers) do
        {:ok, %Req.Response{status: 200, body: %{"data" => %{"data" => data}}}} ->
          {:ok, data}

        {:ok, %Req.Response{status: 404}} ->
          {:error, :not_found}

        {:ok, %Req.Response{status: status, body: body}} ->
          errors = if is_map(body), do: body["errors"] || [], else: [inspect(body)]
          {:error, "Vault returned #{status}: #{Enum.join(errors, ", ")}"}

        {:error, reason} ->
          {:error, "Vault request failed: #{inspect(reason)}"}
      end
    end
  end

  @impl true
  def list_secrets(config, path) do
    with {:ok, token} <- authenticate(config) do
      mount = config.mount_path || "secret"
      full_path = build_path(config.base_path, path)
      url = "#{config.vault_addr}/v1/#{mount}/metadata/#{full_path}"

      headers = build_headers(token, config)

      case Req.request(method: :list, url: url, headers: headers) do
        {:ok, %Req.Response{status: 200, body: %{"data" => %{"keys" => keys}}}} ->
          {:ok, keys}

        {:ok, %Req.Response{status: 404}} ->
          {:ok, []}

        {:ok, %Req.Response{status: status, body: body}} ->
          errors = if is_map(body), do: body["errors"] || [], else: [inspect(body)]
          {:error, "Vault returned #{status}: #{Enum.join(errors, ", ")}"}

        {:error, reason} ->
          {:error, "Vault request failed: #{inspect(reason)}"}
      end
    end
  end

  @impl true
  def health(config) do
    url = "#{config.vault_addr}/v1/sys/health"

    case Req.get(url, headers: []) do
      {:ok, %Req.Response{status: status, body: body}}
      when status in [200, 429, 472, 473, 501, 503] ->
        {:ok,
         %{
           initialized: body["initialized"],
           sealed: body["sealed"],
           standby: body["standby"],
           server_time_utc: body["server_time_utc"],
           version: body["version"],
           cluster_name: body["cluster_name"]
         }}

      {:ok, %Req.Response{status: status}} ->
        {:error, "Vault health check returned #{status}"}

      {:error, reason} ->
        {:error, "Vault health check failed: #{inspect(reason)}"}
    end
  end

  defp authenticate(%{auth_method: "token", auth_config: %{"token" => token}}),
    do: {:ok, token}

  defp authenticate(%{auth_method: "approle", vault_addr: addr, auth_config: auth_config}) do
    url = "#{addr}/v1/auth/approle/login"

    body = %{
      "role_id" => auth_config["role_id"],
      "secret_id" => auth_config["secret_id"]
    }

    case Req.post(url, json: body) do
      {:ok, %Req.Response{status: 200, body: %{"auth" => %{"client_token" => token}}}} ->
        {:ok, token}

      {:ok, %Req.Response{status: status, body: body}} ->
        errors = if is_map(body), do: body["errors"] || [], else: [inspect(body)]
        {:error, "AppRole login failed (#{status}): #{Enum.join(errors, ", ")}"}

      {:error, reason} ->
        {:error, "AppRole login failed: #{inspect(reason)}"}
    end
  end

  defp authenticate(%{auth_method: "kubernetes", vault_addr: addr, auth_config: auth_config}) do
    mount = auth_config["mount_path"] || "kubernetes"
    url = "#{addr}/v1/auth/#{mount}/login"

    jwt =
      auth_config["jwt"] ||
        case File.read("/var/run/secrets/kubernetes.io/serviceaccount/token") do
          {:ok, token} -> String.trim(token)
          _ -> nil
        end

    if is_nil(jwt) do
      {:error, "No JWT available for Kubernetes auth"}
    else
      body = %{"role" => auth_config["role"], "jwt" => jwt}

      case Req.post(url, json: body) do
        {:ok, %Req.Response{status: 200, body: %{"auth" => %{"client_token" => token}}}} ->
          {:ok, token}

        {:ok, %Req.Response{status: status, body: body}} ->
          errors = if is_map(body), do: body["errors"] || [], else: [inspect(body)]
          {:error, "Kubernetes auth failed (#{status}): #{Enum.join(errors, ", ")}"}

        {:error, reason} ->
          {:error, "Kubernetes auth failed: #{inspect(reason)}"}
      end
    end
  end

  defp authenticate(_), do: {:error, "No valid auth method configured"}

  defp build_headers(token, config) do
    headers = [{"X-Vault-Token", token}]

    case config do
      %{namespace: ns} when is_binary(ns) and ns != "" ->
        [{"X-Vault-Namespace", ns} | headers]

      _ ->
        headers
    end
  end

  defp build_path(nil, path), do: path
  defp build_path("", path), do: path
  defp build_path(base, path), do: "#{String.trim_trailing(base, "/")}/#{path}"
end
