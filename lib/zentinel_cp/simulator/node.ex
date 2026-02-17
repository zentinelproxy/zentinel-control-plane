defmodule ZentinelCp.Simulator.Node do
  @moduledoc """
  Simulated Zentinel node for testing the control plane.

  This GenServer simulates a real Zentinel node by:
  - Registering with the control plane
  - Sending periodic heartbeats
  - Polling for bundle updates
  - Simulating bundle activation (success/failure)

  ## Usage

      # Start a simulated node
      {:ok, pid} = ZentinelCp.Simulator.Node.start_link(
        project_slug: "my-project",
        name: "sim-node-1",
        base_url: "http://localhost:4000"
      )

      # Check node state
      ZentinelCp.Simulator.Node.get_state(pid)

      # Stop the node
      ZentinelCp.Simulator.Node.stop(pid)
  """
  use GenServer
  require Logger

  defstruct [
    :project_slug,
    :name,
    :base_url,
    :node_id,
    :node_key,
    :current_bundle,
    :staged_bundle,
    :status,
    :config,
    :error
  ]

  @default_config %{
    poll_interval_ms: 5_000,
    heartbeat_interval_ms: 10_000,
    apply_delay_ms: 1_000,
    failure_rate: 0.0,
    version: "2025.01-sim",
    capabilities: ["config_v1", "metrics_v1"]
  }

  ## Client API

  def start_link(opts) do
    name = Keyword.get(opts, :process_name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def stop(pid) do
    GenServer.stop(pid)
  end

  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  def trigger_failure(pid) do
    GenServer.cast(pid, :trigger_failure)
  end

  ## GenServer callbacks

  @impl true
  def init(opts) do
    config = Map.merge(@default_config, Map.new(Keyword.get(opts, :config, [])))

    state = %__MODULE__{
      project_slug: Keyword.fetch!(opts, :project_slug),
      name: Keyword.fetch!(opts, :name),
      base_url: Keyword.get(opts, :base_url, "http://localhost:4000"),
      status: :initializing,
      config: config
    }

    # Register immediately
    send(self(), :register)

    {:ok, state}
  end

  @impl true
  def handle_info(:register, state) do
    case register_node(state) do
      {:ok, node_id, node_key} ->
        Logger.info("[Simulator] Node #{state.name} registered with ID: #{node_id}")

        new_state = %{state | node_id: node_id, node_key: node_key, status: :connected}

        # Start heartbeat and polling
        schedule_heartbeat(state.config.heartbeat_interval_ms)
        schedule_poll(state.config.poll_interval_ms)

        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("[Simulator] Node #{state.name} failed to register: #{inspect(reason)}")
        # Retry after delay
        Process.send_after(self(), :register, 5_000)
        {:noreply, %{state | status: :disconnected, error: reason}}
    end
  end

  @impl true
  def handle_info(:heartbeat, %{status: :connected} = state) do
    case send_heartbeat(state) do
      :ok ->
        schedule_heartbeat(state.config.heartbeat_interval_ms)
        {:noreply, state}

      {:error, reason} ->
        Logger.warning("[Simulator] Node #{state.name} heartbeat failed: #{inspect(reason)}")
        schedule_heartbeat(state.config.heartbeat_interval_ms)
        {:noreply, %{state | error: reason}}
    end
  end

  @impl true
  def handle_info(:heartbeat, state) do
    # Not connected, skip heartbeat
    schedule_heartbeat(state.config.heartbeat_interval_ms)
    {:noreply, state}
  end

  @impl true
  def handle_info(:poll, %{status: :connected} = state) do
    case poll_for_bundle(state) do
      {:ok, :no_update} ->
        schedule_poll(state.config.poll_interval_ms)
        {:noreply, state}

      {:ok, bundle_info} ->
        Logger.info(
          "[Simulator] Node #{state.name} received new bundle: #{bundle_info.bundle_id}"
        )

        send(self(), {:apply_bundle, bundle_info})
        schedule_poll(state.config.poll_interval_ms)
        {:noreply, state}

      {:error, reason} ->
        Logger.warning("[Simulator] Node #{state.name} poll failed: #{inspect(reason)}")
        schedule_poll(state.config.poll_interval_ms)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:poll, state) do
    schedule_poll(state.config.poll_interval_ms)
    {:noreply, state}
  end

  @impl true
  def handle_info({:apply_bundle, bundle_info}, state) do
    # Simulate bundle application delay
    Process.sleep(state.config.apply_delay_ms)

    if :rand.uniform() < state.config.failure_rate do
      Logger.error(
        "[Simulator] Node #{state.name} failed to apply bundle #{bundle_info.bundle_id}"
      )

      # Report failure (would call API)
      {:noreply, state}
    else
      Logger.info(
        "[Simulator] Node #{state.name} successfully applied bundle #{bundle_info.bundle_id}"
      )

      # Report success (would call API)
      {:noreply, %{state | current_bundle: bundle_info.bundle_id, staged_bundle: nil}}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast(:trigger_failure, state) do
    {:noreply, %{state | status: :disconnected, error: :simulated_failure}}
  end

  ## Private helpers

  defp register_node(state) do
    url = "#{state.base_url}/api/v1/projects/#{state.project_slug}/nodes/register"

    body =
      Jason.encode!(%{
        name: state.name,
        version: state.config.version,
        capabilities: state.config.capabilities,
        labels: %{simulator: "true", env: "dev"},
        hostname: "sim-#{state.name}.local"
      })

    case Req.post(url, body: body, headers: [{"content-type", "application/json"}]) do
      {:ok, %{status: 201, body: body}} ->
        {:ok, body["node_id"], body["node_key"]}

      {:ok, %{status: status, body: body}} ->
        {:error, "Registration failed with status #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp send_heartbeat(state) do
    url = "#{state.base_url}/api/v1/nodes/#{state.node_id}/heartbeat"

    body =
      Jason.encode!(%{
        health: %{status: "healthy", uptime_s: 3600},
        metrics: %{requests_total: :rand.uniform(10000), connections_active: :rand.uniform(100)},
        active_bundle_id: state.current_bundle,
        staged_bundle_id: state.staged_bundle,
        version: state.config.version
      })

    headers = [
      {"content-type", "application/json"},
      {"x-zentinel-node-key", state.node_key}
    ]

    case Req.post(url, body: body, headers: headers) do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, %{status: status, body: body}} ->
        {:error, "Heartbeat failed: #{status} - #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp poll_for_bundle(state) do
    url = "#{state.base_url}/api/v1/nodes/#{state.node_id}/bundles/latest"

    headers = [{"x-zentinel-node-key", state.node_key}]

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: %{"no_update" => true}}} ->
        {:ok, :no_update}

      {:ok, %{status: 200, body: body}} ->
        {:ok, %{bundle_id: body["bundle_id"], artifact_url: body["artifact_url"]}}

      {:ok, %{status: status, body: body}} ->
        {:error, "Poll failed: #{status} - #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp schedule_heartbeat(interval_ms) do
    Process.send_after(self(), :heartbeat, interval_ms)
  end

  defp schedule_poll(interval_ms) do
    Process.send_after(self(), :poll, interval_ms)
  end
end
