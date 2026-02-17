defmodule ZentinelCp.Rollouts.HealthChecker do
  @moduledoc """
  Executes custom health check endpoints during rollout verification.
  """

  require Logger

  alias ZentinelCp.Rollouts.HealthCheckEndpoint

  @doc """
  Checks all provided health check endpoints.

  Returns `{:ok, results}` where results is a list of check results.
  Each result is `{endpoint, :pass | {:fail, reason}}`.
  """
  def check_all(endpoints) when is_list(endpoints) do
    results =
      endpoints
      |> Enum.filter(& &1.enabled)
      |> Enum.map(fn endpoint ->
        result = check(endpoint)
        {endpoint, result}
      end)

    {:ok, results}
  end

  @doc """
  Checks a single health check endpoint.

  Returns `:pass` or `{:fail, reason}`.
  """
  def check(%HealthCheckEndpoint{} = endpoint) do
    url = endpoint.url
    method = String.downcase(endpoint.method) |> String.to_atom()
    timeout = endpoint.timeout_ms
    expected_status = endpoint.expected_status
    expected_body = endpoint.expected_body_contains
    headers = build_headers(endpoint.headers)

    Logger.debug("Health check #{endpoint.name}: #{method} #{url}")

    case do_request(method, url, headers, timeout) do
      {:ok, status, body} ->
        check_response(status, body, expected_status, expected_body)

      {:error, reason} ->
        {:fail, "Request failed: #{inspect(reason)}"}
    end
  rescue
    e ->
      {:fail, "Exception: #{Exception.message(e)}"}
  end

  @doc """
  Returns true if all results passed.
  """
  def all_passed?(results) when is_list(results) do
    Enum.all?(results, fn {_endpoint, result} -> result == :pass end)
  end

  @doc """
  Returns the failed checks from results.
  """
  def failed_checks(results) when is_list(results) do
    Enum.filter(results, fn {_endpoint, result} -> result != :pass end)
  end

  defp build_headers(headers) when is_map(headers) do
    Enum.map(headers, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)
  end

  defp build_headers(_), do: []

  defp do_request(method, url, headers, timeout) do
    url_charlist = String.to_charlist(url)

    request =
      case method do
        :get -> {url_charlist, headers}
        :head -> {url_charlist, headers}
        :post -> {url_charlist, headers, ~c"application/json", ""}
      end

    http_opts = [timeout: timeout, connect_timeout: min(timeout, 5000)]

    case :httpc.request(method, request, http_opts, body_format: :binary) do
      {:ok, {{_, status, _}, _resp_headers, body}} ->
        {:ok, status, to_string(body)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp check_response(status, body, expected_status, expected_body) do
    status_ok = status == expected_status

    body_ok =
      case expected_body do
        nil -> true
        "" -> true
        pattern -> String.contains?(body, pattern)
      end

    cond do
      not status_ok ->
        {:fail, "Expected status #{expected_status}, got #{status}"}

      not body_ok ->
        {:fail, "Response body does not contain expected content"}

      true ->
        :pass
    end
  end
end
