defmodule ZentinelCp.Cluster.LeaderElection do
  @moduledoc """
  Leader election for singleton workers using PostgreSQL advisory locks.

  In a multi-instance deployment, only the leader instance should run
  singleton workers like SchedulerWorker, DriftWorker, etc.

  Uses PostgreSQL advisory locks for leader election. Falls back to
  "always leader" in SQLite mode (single-instance dev/test).

  ## Usage

      if LeaderElection.leader?() do
        # Start singleton workers
      end
  """

  use GenServer
  require Logger

  # Arbitrary unique lock ID
  @lock_id 728_394_561
  @check_interval_ms 15_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns whether this instance is the current leader."
  def leader? do
    try do
      GenServer.call(__MODULE__, :leader?, 5_000)
    catch
      # If GenServer not running, assume leader (single-instance)
      :exit, _ -> true
    end
  end

  @doc "Returns the node name of the current instance."
  def node_name, do: node()

  @impl GenServer
  def init(_opts) do
    state = %{
      leader: true,
      adapter: detect_adapter()
    }

    if state.adapter == :postgresql do
      Process.send_after(self(), :try_acquire, 1_000)
    end

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:leader?, _from, state) do
    {:reply, state.leader, state}
  end

  @impl GenServer
  def handle_info(:try_acquire, %{adapter: :postgresql} = state) do
    is_leader = try_acquire_lock()
    Process.send_after(self(), :try_acquire, @check_interval_ms)

    if is_leader != state.leader do
      if is_leader do
        Logger.info("This instance acquired leadership")
      else
        Logger.info("This instance lost leadership")
      end
    end

    {:noreply, %{state | leader: is_leader}}
  end

  def handle_info(:try_acquire, state) do
    {:noreply, state}
  end

  ## Private

  defp detect_adapter do
    case Application.get_env(:zentinel_cp, :ecto_adapter) do
      Ecto.Adapters.Postgres -> :postgresql
      _ -> :sqlite
    end
  end

  defp try_acquire_lock do
    case ZentinelCp.Repo.query("SELECT pg_try_advisory_lock($1)", [@lock_id]) do
      {:ok, %{rows: [[true]]}} -> true
      _ -> false
    end
  rescue
    # Default to leader on error
    _ -> true
  end
end
