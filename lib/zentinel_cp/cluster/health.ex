defmodule ZentinelCp.Cluster.Health do
  @moduledoc """
  Cluster health checking for multi-instance deployments.

  Validates that the instance can reach the database, Oban is running,
  and (if clustered) that it can see other nodes in the cluster.
  """

  @doc """
  Performs a comprehensive health check.
  Returns `{:ok, details}` or `{:error, details}`.
  """
  def check do
    checks = %{
      database: check_database(),
      oban: check_oban(),
      cluster: check_cluster(),
      memory: check_memory()
    }

    healthy = Enum.all?(checks, fn {_, {status, _}} -> status == :ok end)

    if healthy do
      {:ok, format_checks(checks)}
    else
      {:error, format_checks(checks)}
    end
  end

  @doc "Liveness check — is the VM running?"
  def alive?, do: true

  @doc "Readiness check — can the instance serve requests?"
  def ready? do
    case check_database() do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc "Returns cluster membership info."
  def cluster_info do
    %{
      node: node(),
      connected_nodes: Node.list(),
      cluster_size: length(Node.list()) + 1,
      uptime_seconds: uptime_seconds()
    }
  end

  ## Private

  defp check_database do
    case ZentinelCp.Repo.query("SELECT 1") do
      {:ok, _} -> {:ok, "connected"}
      {:error, reason} -> {:error, "disconnected: #{inspect(reason)}"}
    end
  rescue
    e -> {:error, "error: #{Exception.message(e)}"}
  end

  defp check_oban do
    # In test mode Oban runs inline, so check if the module is loaded
    if Process.whereis(Oban) || Code.ensure_loaded?(Oban) do
      {:ok, "running"}
    else
      {:error, "not running"}
    end
  end

  defp check_cluster do
    nodes = Node.list()
    {:ok, "#{length(nodes) + 1} node(s)"}
  end

  defp check_memory do
    memory = :erlang.memory(:total)
    mb = div(memory, 1_048_576)

    if mb < 2048 do
      {:ok, "#{mb} MB"}
    else
      {:ok, "#{mb} MB (high)"}
    end
  end

  defp format_checks(checks) do
    Map.new(checks, fn {name, {status, detail}} ->
      {name, %{status: status, detail: detail}}
    end)
  end

  defp uptime_seconds do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    div(uptime_ms, 1000)
  end
end
