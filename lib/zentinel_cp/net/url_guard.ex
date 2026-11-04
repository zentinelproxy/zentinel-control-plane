defmodule ZentinelCp.Net.UrlGuard do
  @moduledoc """
  Checks URLs supplied by tenants before the control plane requests them, so a
  tenant cannot use it to reach internal services or cloud metadata endpoints.

  Policies:

    * `:public` - the host must resolve only to public addresses. For webhooks and
      other notification targets.
    * `:no_local` - also allows private networks, where a tenant's own services
      live, and blocks loopback and link-local addresses. For health checks.

  Set `config :zentinel_cp, :allow_private_outbound, true` to disable the checks
  in a deployment where these targets are legitimate. The address is resolved
  again when the request is made, so this narrows but does not remove the risk of
  DNS rebinding; restrict egress at the network as well.
  """

  import Bitwise

  @doc "Returns `:ok`, or `{:error, reason}` if the URL must not be requested."
  def check(url, policy \\ :public)

  def check(url, policy) when is_binary(url) do
    if Application.get_env(:zentinel_cp, :allow_private_outbound, false) do
      :ok
    else
      with {:ok, host} <- parse(url),
           {:ok, addresses} <- resolve(host) do
        if Enum.all?(addresses, &allowed?(&1, policy)),
          do: :ok,
          else: {:error, :forbidden_address}
      end
    end
  end

  def check(_url, _policy), do: {:error, :invalid_url}

  defp parse(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and host not in [nil, ""] ->
        {:ok, host}

      _ ->
        {:error, :invalid_url}
    end
  end

  defp resolve(host) do
    charlist = String.to_charlist(host)

    case :inet.parse_address(charlist) do
      {:ok, address} ->
        {:ok, [address]}

      {:error, _} ->
        addresses =
          for family <- [:inet, :inet6],
              {:ok, found} <- [:inet.getaddrs(charlist, family)],
              address <- found,
              do: address

        if addresses == [], do: {:error, :unresolvable_host}, else: {:ok, addresses}
    end
  end

  defp allowed?(address, :public), do: not local?(address) and not private?(address)
  defp allowed?(address, :no_local), do: not local?(address)

  defp local?({127, _, _, _}), do: true
  defp local?({0, _, _, _}), do: true
  defp local?({169, 254, _, _}), do: true
  defp local?({0, 0, 0, 0, 0, 0, 0, 0}), do: true
  defp local?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp local?({segment, _, _, _, _, _, _, _}) when (segment &&& 0xFFC0) == 0xFE80, do: true
  # An IPv4 address mapped into IPv6 is judged as the IPv4 address.
  defp local?({0, 0, 0, 0, 0, 0xFFFF, high, low}), do: local?(ipv4(high, low))
  defp local?(_), do: false

  defp private?({10, _, _, _}), do: true
  defp private?({172, b, _, _}) when b in 16..31, do: true
  defp private?({192, 168, _, _}), do: true
  defp private?({100, b, _, _}) when b in 64..127, do: true
  defp private?({segment, _, _, _, _, _, _, _}) when (segment &&& 0xFE00) == 0xFC00, do: true
  defp private?({0, 0, 0, 0, 0, 0xFFFF, high, low}), do: private?(ipv4(high, low))
  defp private?(_), do: false

  defp ipv4(high, low), do: {high >>> 8, high &&& 0xFF, low >>> 8, low &&& 0xFF}
end
