defmodule ZentinelCp.Secrets.VaultClient.HTTP do
  @moduledoc """
  HTTP implementation of the Vault client using Req.

  Supports KV v2 secret engine and multiple auth methods:
  - Token: direct `X-Vault-Token` header
  - AppRole: login via `role_id` + `secret_id`
  - Kubernetes: login via service account JWT

  `vault_addr` is checked with `ZentinelCp.Net.UrlGuard` (`:no_local`) before
  every request and redirects are not followed. A failed response is reported to
  the caller by its status only and Vault's own error messages are logged, so
  the error a tenant sees does not carry what another server answered.

  Kubernetes auth without a configured `jwt` sends the control plane's own
  service account token, so it is used only when the operator enables it with
  `config :zentinel_cp, :vault_kubernetes_in_cluster_jwt, true`.
  """

  @behaviour ZentinelCp.Secrets.VaultClient

  require Logger

  alias ZentinelCp.Net.UrlGuard

  @impl true
  def read_secret(config, path) do
    with {:ok, token} <- authenticate(config) do
      mount = config.mount_path || "secret"
      full_path = build_path(config.base_path, path)
      url = "#{config.vault_addr}/v1/#{mount}/data/#{full_path}"

      headers = build_headers(token, config)

      case request(:get, url, headers: headers) do
        {:ok, %Req.Response{status: 200, body: %{"data" => %{"data" => data}}}} ->
          {:ok, data}

        {:ok, %Req.Response{status: 404}} ->
          {:error, :not_found}

        {:ok, %Req.Response{status: status, body: body}} ->
          failed("Vault returned #{status}", body)

        {:error, reason} ->
          request_failed("Vault request failed", reason)
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

      case request(:list, url, headers: headers) do
        {:ok, %Req.Response{status: 200, body: %{"data" => %{"keys" => keys}}}} ->
          {:ok, keys}

        {:ok, %Req.Response{status: 404}} ->
          {:ok, []}

        {:ok, %Req.Response{status: status, body: body}} ->
          failed("Vault returned #{status}", body)

        {:error, reason} ->
          request_failed("Vault request failed", reason)
      end
    end
  end

  @impl true
  def health(config) do
    url = "#{config.vault_addr}/v1/sys/health"

    case request(:get, url, headers: []) do
      {:ok, %Req.Response{status: status, body: body}}
      when status in [200, 429, 472, 473, 501, 503] and is_map(body) ->
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
        request_failed("Vault health check failed", reason)
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

    case request(:post, url, json: body) do
      {:ok, %Req.Response{status: 200, body: %{"auth" => %{"client_token" => token}}}} ->
        {:ok, token}

      {:ok, %Req.Response{status: status, body: body}} ->
        failed("AppRole login failed (#{status})", body)

      {:error, reason} ->
        request_failed("AppRole login failed", reason)
    end
  end

  defp authenticate(%{auth_method: "kubernetes", vault_addr: addr, auth_config: auth_config}) do
    mount = auth_config["mount_path"] || "kubernetes"
    url = "#{addr}/v1/auth/#{mount}/login"

    jwt = auth_config["jwt"] || in_cluster_jwt()

    if is_nil(jwt) do
      {:error, "No JWT available for Kubernetes auth"}
    else
      body = %{"role" => auth_config["role"], "jwt" => jwt}

      case request(:post, url, json: body) do
        {:ok, %Req.Response{status: 200, body: %{"auth" => %{"client_token" => token}}}} ->
          {:ok, token}

        {:ok, %Req.Response{status: status, body: body}} ->
          failed("Kubernetes auth failed (#{status})", body)

        {:error, reason} ->
          request_failed("Kubernetes auth failed", reason)
      end
    end
  end

  defp authenticate(_), do: {:error, "No valid auth method configured"}

  defp in_cluster_jwt do
    if Application.get_env(:zentinel_cp, :vault_kubernetes_in_cluster_jwt, false) do
      case File.read("/var/run/secrets/kubernetes.io/serviceaccount/token") do
        {:ok, token} -> String.trim(token)
        _ -> nil
      end
    end
  end

  defp request(method, url, opts) do
    case UrlGuard.check(url, :no_local) do
      :ok ->
        Req.request([method: method, url: url, redirect: false, retry: false] ++ opts)

      {:error, reason} ->
        {:error, {:not_allowed, "Vault address is not allowed: #{reason}"}}
    end
  end

  # A refused address keeps its own message; anything else is the transport's.
  defp request_failed(_message, {:not_allowed, reason}), do: {:error, reason}
  defp request_failed(message, reason), do: {:error, "#{message}: #{inspect(reason)}"}

  # Vault's error messages help whoever configures it, so they are logged; the
  # caller gets the status only.
  defp failed(message, body) do
    errors = if is_map(body), do: body["errors"], else: nil
    Logger.warning("#{message}: #{inspect(errors)}")
    {:error, message}
  end

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
