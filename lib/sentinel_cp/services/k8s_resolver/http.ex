defmodule SentinelCp.Services.K8sResolver.HTTP do
  @moduledoc """
  Kubernetes Endpoints API resolver using Req.

  Supports both explicit config (`api_url` + `token`) and in-cluster
  auto-detection via service account token and `KUBERNETES_SERVICE_HOST` env var.
  """

  @behaviour SentinelCp.Services.K8sResolver

  @sa_token_path "/var/run/secrets/kubernetes.io/serviceaccount/token"
  @sa_ca_path "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"

  @impl true
  def resolve_endpoints(config) do
    with {:ok, {api_url, token}} <- resolve_auth(config) do
      namespace = config["namespace"]
      service_name = config["service_name"]
      url = "#{api_url}/api/v1/namespaces/#{namespace}/endpoints/#{service_name}"

      req_opts = [
        headers: [{"authorization", "Bearer #{token}"}],
        connect_options: ssl_options()
      ]

      case Req.get(url, req_opts) do
        {:ok, %Req.Response{status: 200, body: body}} ->
          {:ok, parse_endpoints(body, config["port_name"])}

        {:ok, %Req.Response{status: status, body: body}} ->
          message = if is_map(body), do: body["message"] || inspect(body), else: inspect(body)
          {:error, "Kubernetes API returned #{status}: #{message}"}

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
        {:ok, {config["api_url"], config["token"]}}

      in_cluster?() ->
        case File.read(@sa_token_path) do
          {:ok, token} ->
            host = System.get_env("KUBERNETES_SERVICE_HOST")
            port = System.get_env("KUBERNETES_SERVICE_PORT") || "443"
            {:ok, {"https://#{host}:#{port}", String.trim(token)}}

          {:error, reason} ->
            {:error, "Failed to read service account token: #{inspect(reason)}"}
        end

      true ->
        {:error, "No Kubernetes credentials configured and not running in-cluster"}
    end
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
