defmodule ZentinelCp.Services.DiscoverySync do
  @moduledoc """
  Pure-function module for reconciling upstream targets with DNS SRV records.

  No database access — operates on in-memory data structures.
  """

  @doc """
  Reconciles current upstream targets against resolved SRV records.

  Returns a map with:
  - `:add` — list of `%{host, port, weight}` maps for new targets
  - `:remove` — list of target structs to remove
  - `:keep` — list of target structs to keep
  """
  def reconcile(current_targets, srv_records) do
    resolved = Enum.map(srv_records, &srv_to_target/1)
    resolved_set = MapSet.new(resolved, fn t -> {t.host, t.port} end)
    current_set = MapSet.new(current_targets, fn t -> {t.host, t.port} end)

    add =
      resolved
      |> Enum.filter(fn t -> not MapSet.member?(current_set, {t.host, t.port}) end)

    remove =
      current_targets
      |> Enum.filter(fn t -> not MapSet.member?(resolved_set, {t.host, t.port}) end)

    keep =
      current_targets
      |> Enum.filter(fn t -> MapSet.member?(resolved_set, {t.host, t.port}) end)

    %{add: add, remove: remove, keep: keep}
  end

  defp srv_to_target({_priority, weight, port, host}) do
    %{
      host: to_string(host),
      port: port,
      weight: max(weight, 1)
    }
  end
end
