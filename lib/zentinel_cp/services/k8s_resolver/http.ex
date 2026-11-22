defmodule ZentinelCp.Services.K8sResolver.HTTP do
  @moduledoc """
  Kubernetes Endpoints API resolver using Req.

  Supports explicit config (`api_url` + `token`). The control plane's own
  service account (in-cluster auto-detection via its token and
  `KUBERNETES_SERVICE_HOST`) is used only when the operator enables it with
  `config :zentinel_cp, :k8s_discovery_in_cluster, true`, since any project
  that configures discovery would otherwise read Endpoints with the control
  plane's permissions.

  `api_url` is checked with `ZentinelCp.Net.UrlGuard` (`:no_local`), redirects
  are not followed, and a failed response is reported by its status only, so
  the error a tenant sees does not carry what another server answered.
  """

  alias ZentinelCp.Net.UrlGuard

  @behaviour ZentinelCp.Services.K8sResolver

  @sa_token_path "/var/run/secrets/kubernetes.io/serviceaccount/token"
  @sa_ca_path "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"

  @impl true
  def resolve_endpoints(config) do
    with {:ok, namespace} <- dns_label(config["namespace"], "namespace"),
         {:ok, service_name} <- dns_label(config["service_name"], "service_name"),
         {:ok, {api_url, token, guard?}} <- resolve_auth(config),
         url =
           "#{String.trim_trailing(api_url, "/")}/api/v1/namespaces/#{namespace}/endpoints/#{service_name}",
         :ok <- check_url(url, guard?) do
      req_opts = [
        headers: [{"authorization", "Bearer #{token}"}],
        connect_options: ssl_options(),
        redirect: false,
        retry: false
      ]

      case Req.get(url, req_opts) do
        {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
          {:ok, parse_endpoints(body, config["port_name"])}

        {:ok, %Req.Response{status: 200}} ->
          {:error, "Kubernetes API returned a body that is not an Endpoints object"}

        {:ok, %Req.Response{status: status}} ->
          {:error, "Kubernetes API returned #{status}"}

        {:error, reason} ->
          {:error, "Kubernetes API request failed: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  Parses a Kubernetes Endpoints API response body into SRV-compatible tuples.

  Returns `{0, 1, port, ip_charlist}` for each address/port combination.
  Optionally filters ports by `port_name`.
  """
  def parse_endpoints(body, port_name \\ nil) do
    subsets = body["subsets"] || []

    Enum.flat_map(subsets, fn subset ->
      addresses = subset["addresses"] || []
      ports = filter_ports(subset["ports"] || [], port_name)

      for addr <- addresses,
          port_entry <- ports do
        ip = addr["ip"]
        port = port_entry["port"]
        {0, 1, port, to_charlist(ip)}
      end
    end)
  end

  defp filter_ports(ports, nil), do: ports
  defp filter_ports(ports, ""), do: ports

  defp filter_ports(ports, port_name) do
    filtered = Enum.filter(ports, fn p -> p["name"] == port_name end)
    if filtered == [], do: ports, else: filtered
  end

  defp resolve_auth(config) do
    cond do
      is_binary(config["api_url"]) and config["api_url"] != "" and
        is_binary(config["token"]) and config["token"] != "" ->
        {:ok, {config["api_url"], config["token"], true}}

      in_cluster?() and in_cluster_allowed?() ->
        case File.read(@sa_token_path) do
          {:ok, token} ->
            host = System.get_env("KUBERNETES_SERVICE_HOST")
            port = System.get_env("KUBERNETES_SERVICE_PORT") || "443"
            {:ok, {"https://#{host}:#{port}", String.trim(token), false}}

          {:error, reason} ->
            {:error, "Failed to read service account token: #{inspect(reason)}"}
        end

      true ->
        {:error, "No Kubernetes credentials configured and not running in-cluster"}
    end
  end

  # The service account's API server is the operator's own, not a tenant's URL.
  defp check_url(_url, false), do: :ok

  defp check_url(url, true) do
    case UrlGuard.check(url, :no_local) do
      :ok -> :ok
      {:error, reason} -> {:error, "Kubernetes API URL is not allowed: #{reason}"}
    end
  end

  # A namespace or service name is a DNS-1123 label, so it cannot add path
  # segments or a query to the request.
  defp dns_label(value, field) when is_binary(value) do
    if Regex.match?(~r/\A[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?\z/, value),
      do: {:ok, value},
      else: {:error, "#{field} is not a valid Kubernetes name"}
  end

  defp dns_label(_value, field), do: {:error, "#{field} is not a valid Kubernetes name"}

  defp in_cluster_allowed? do
    Application.get_env(:zentinel_cp, :k8s_discovery_in_cluster, false)
  end

  defp in_cluster? do
    System.get_env("KUBERNETES_SERVICE_HOST") != nil and File.exists?(@sa_token_path)
  end

  defp ssl_options do
    if File.exists?(@sa_ca_path) do
      [transport_opts: [cacertfile: @sa_ca_path]]
    else
      []
    end
  end
end
