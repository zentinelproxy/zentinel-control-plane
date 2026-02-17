defmodule ZentinelCp.Simulator.Fleet do
  @moduledoc """
  Fleet simulator for spawning and managing multiple simulated nodes.

  ## Usage

      # Spawn 10 simulated nodes
      {:ok, nodes} = ZentinelCp.Simulator.Fleet.spawn_nodes("my-project", 10)

      # Spawn with custom configuration
      {:ok, nodes} = ZentinelCp.Simulator.Fleet.spawn_nodes("my-project", 5,
        heartbeat_interval_ms: 5_000,
        failure_rate: 0.1
      )

      # Get all node states
      states = ZentinelCp.Simulator.Fleet.get_all_states(nodes)

      # Stop all nodes
      ZentinelCp.Simulator.Fleet.stop_all(nodes)
  """

  alias ZentinelCp.Simulator.Node

  @doc """
  Spawns multiple simulated nodes for a project.

  ## Options
    - `base_url` - Control plane URL (default: "http://localhost:4000")
    - `name_prefix` - Prefix for node names (default: "sim-node")
    - `poll_interval_ms` - Polling interval (default: 5000)
    - `heartbeat_interval_ms` - Heartbeat interval (default: 10000)
    - `apply_delay_ms` - Bundle apply delay (default: 1000)
    - `failure_rate` - Probability of bundle apply failure (default: 0.0)
  """
  def spawn_nodes(project_slug, count, opts \\ []) do
    base_url = Keyword.get(opts, :base_url, "http://localhost:4000")
    name_prefix = Keyword.get(opts, :name_prefix, "sim-node")

    config = [
      poll_interval_ms: Keyword.get(opts, :poll_interval_ms, 5_000),
      heartbeat_interval_ms: Keyword.get(opts, :heartbeat_interval_ms, 10_000),
      apply_delay_ms: Keyword.get(opts, :apply_delay_ms, 1_000),
      failure_rate: Keyword.get(opts, :failure_rate, 0.0)
    ]

    nodes =
      for i <- 1..count do
        name = "#{name_prefix}-#{i}"

        {:ok, pid} =
          Node.start_link(
            project_slug: project_slug,
            name: name,
            base_url: base_url,
            config: config
          )

        {name, pid}
      end

    {:ok, nodes}
  end

  @doc """
  Gets the state of all nodes.
  """
  def get_all_states(nodes) do
    Enum.map(nodes, fn {name, pid} ->
      try do
        {name, Node.get_state(pid)}
      catch
        :exit, _ -> {name, :stopped}
      end
    end)
  end

  @doc """
  Gets a summary of node states.
  """
  def get_summary(nodes) do
    states = get_all_states(nodes)

    %{
      total: length(states),
      connected: Enum.count(states, fn {_, s} -> is_map(s) and s.status == :connected end),
      disconnected: Enum.count(states, fn {_, s} -> is_map(s) and s.status == :disconnected end),
      initializing: Enum.count(states, fn {_, s} -> is_map(s) and s.status == :initializing end),
      stopped: Enum.count(states, fn {_, s} -> s == :stopped end)
    }
  end

  @doc """
  Stops all nodes.
  """
  def stop_all(nodes) do
    Enum.each(nodes, fn {_name, pid} ->
      try do
        Node.stop(pid)
      catch
        :exit, _ -> :ok
      end
    end)

    :ok
  end

  @doc """
  Triggers a failure on a random subset of nodes.
  """
  def trigger_random_failures(nodes, count) do
    nodes
    |> Enum.shuffle()
    |> Enum.take(count)
    |> Enum.each(fn {_name, pid} ->
      Node.trigger_failure(pid)
    end)
  end
end
