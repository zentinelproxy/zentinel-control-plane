defmodule ZentinelCp.Nodes do
  @moduledoc """
  The Nodes context handles Zentinel proxy instance management.
  """

  import Ecto.Query, warn: false
  alias ZentinelCp.Repo
  alias ZentinelCp.Nodes.{DriftEvent, Node, NodeEvent, NodeHeartbeat, NodeRuntimeConfig}

  @stale_threshold_seconds 120

  ## Node Management

  @doc """
  Lists all nodes for a project.
  """
  def list_nodes(project_id) do
    from(n in Node,
      where: n.project_id == ^project_id,
      order_by: [asc: n.name]
    )
    |> Repo.all()
  end

  @doc """
  Lists nodes with optional filters.
  """
  def list_nodes(project_id, opts) do
    query = from(n in Node, where: n.project_id == ^project_id)

    query =
      Enum.reduce(opts, query, fn
        {:status, status}, q -> where(q, [n], n.status == ^status)
        {:labels, labels}, q -> filter_by_labels(q, labels)
        {:environment_id, nil}, q -> where(q, [n], is_nil(n.environment_id))
        {:environment_id, env_id}, q -> where(q, [n], n.environment_id == ^env_id)
        _, q -> q
      end)

    query
    |> order_by([n], asc: n.name)
    |> Repo.all()
  end

  defp filter_by_labels(query, labels) when is_map(labels) do
    Enum.reduce(labels, query, fn {key, value}, q ->
      # JSON containment check - works for both SQLite and Postgres
      where(q, [n], fragment("json_extract(?, ?) = ?", n.labels, ^"$.#{key}", ^value))
    end)
  end

  @doc """
  Gets a single node by ID.
  """
  def get_node(id), do: Repo.get(Node, id)

  @doc """
  Gets a single node by ID, raises if not found.
  """
  def get_node!(id), do: Repo.get!(Node, id)

  @doc """
  Gets a node by project and name.
  """
  def get_node_by_name(project_id, name) do
    Repo.get_by(Node, project_id: project_id, name: name)
  end

  @doc """
  Gets a node by its key hash.
  """
  def get_node_by_key(node_key) when is_binary(node_key) do
    key_hash = Node.hash_node_key(node_key)
    Repo.get_by(Node, node_key_hash: key_hash)
  end

  @doc """
  Registers a new node. Returns {:ok, node_with_key} or {:error, changeset}.
  The node_key is only available on the returned node immediately after registration.
  """
  def register_node(attrs) do
    %Node{}
    |> Node.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Records a heartbeat from a node.
  Updates the node's last_seen_at and optionally stores historical heartbeat data.
  """
  def record_heartbeat(%Node{} = node, attrs \\ %{}) do
    Repo.transaction(fn ->
      # Update node
      {:ok, updated_node} =
        node
        |> Node.heartbeat_changeset(attrs)
        |> Repo.update()

      # Record heartbeat history
      %NodeHeartbeat{}
      |> NodeHeartbeat.changeset(Map.merge(attrs, %{node_id: node.id}))
      |> Repo.insert!()

      # Extract circuit breaker statuses if present
      circuit_breakers =
        get_in(attrs, ["metrics", "circuit_breakers"]) ||
          get_in(attrs, [:metrics, :circuit_breakers]) || []

      for cb <- circuit_breakers do
        group_id = cb["upstream_group_id"] || cb[:upstream_group_id]

        if group_id do
          ZentinelCp.Services.upsert_circuit_breaker_status(%{
            upstream_group_id: group_id,
            node_id: node.id,
            state: cb["state"] || cb[:state] || "closed",
            failure_count: cb["failure_count"] || cb[:failure_count] || 0,
            success_count: cb["success_count"] || cb[:success_count] || 0,
            last_failure_at:
              parse_optional_datetime(cb["last_failure_at"] || cb[:last_failure_at]),
            last_success_at:
              parse_optional_datetime(cb["last_success_at"] || cb[:last_success_at]),
            last_trip_at: parse_optional_datetime(cb["last_trip_at"] || cb[:last_trip_at]),
            metadata: cb["metadata"] || cb[:metadata] || %{}
          })
        end
      end

      Absinthe.Subscription.publish(
        ZentinelCpWeb.Endpoint,
        updated_node,
        node_status: updated_node.project_id
      )

      updated_node
    end)
  end

  @doc """
  Authenticates a node by its key.
  Returns {:ok, node} if valid, {:error, :invalid_key} otherwise.
  """
  def authenticate_node(node_key) when is_binary(node_key) do
    case get_node_by_key(node_key) do
      nil -> {:error, :invalid_key}
      node -> {:ok, node}
    end
  end

  @doc """
  Marks stale nodes as offline.
  A node is stale if it hasn't sent a heartbeat within the threshold.
  """
  def mark_stale_nodes_offline(threshold_seconds \\ @stale_threshold_seconds) do
    cutoff = DateTime.utc_now() |> DateTime.add(-threshold_seconds, :second)

    from(n in Node,
      where: n.status == "online" and n.last_seen_at < ^cutoff
    )
    |> Repo.update_all(set: [status: "offline"])
  end

  @doc """
  Updates a node's labels.
  """
  def update_node_labels(%Node{} = node, labels) do
    node
    |> Node.labels_changeset(labels)
    |> Repo.update()
  end

  @doc """
  Deletes a node.
  """
  def delete_node(%Node{} = node) do
    Repo.delete(node)
  end

  ## Node Stats

  @doc """
  Returns node counts by status for a project.
  """
  def get_node_stats(project_id) do
    from(n in Node,
      where: n.project_id == ^project_id,
      group_by: n.status,
      select: {n.status, count(n.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Returns the total number of nodes for a project.
  """
  def count_nodes(project_id) do
    from(n in Node, where: n.project_id == ^project_id)
    |> Repo.aggregate(:count)
  end

  ## Heartbeat History

  @doc """
  Lists recent heartbeats for a node.
  """
  def list_recent_heartbeats(node_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    list_node_heartbeats(node_id, limit)
  end

  @doc """
  Lists recent heartbeats for a node.
  """
  def list_node_heartbeats(node_id, limit \\ 100) do
    from(h in NodeHeartbeat,
      where: h.node_id == ^node_id,
      order_by: [desc: h.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  ## Node Events

  @doc """
  Creates a single node event.
  """
  def create_node_event(attrs) do
    %NodeEvent{}
    |> NodeEvent.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates multiple node events in a transaction.
  """
  def create_node_events(events_attrs) when is_list(events_attrs) do
    Repo.transaction(fn ->
      Enum.map(events_attrs, fn attrs ->
        case create_node_event(attrs) do
          {:ok, event} -> event
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    end)
  end

  @doc """
  Lists recent events for a node, ordered by most recent first.
  """
  def list_node_events(node_id, limit \\ 50) do
    from(e in NodeEvent,
      where: e.node_id == ^node_id,
      order_by: [desc: e.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Cleans up old event records.
  Keeps only the most recent records per node.
  """
  def cleanup_old_events(keep_count \\ 500) do
    subquery =
      from(e in NodeEvent,
        select: %{
          id: e.id,
          row_num: over(row_number(), partition_by: e.node_id, order_by: [desc: e.inserted_at])
        }
      )

    from(e in NodeEvent,
      join: s in subquery(subquery),
      on: e.id == s.id,
      where: s.row_num > ^keep_count
    )
    |> Repo.delete_all()
  end

  ## Node Runtime Config

  @doc """
  Upserts the runtime config for a node.
  Computes a SHA256 hash of the KDL content.
  """
  def upsert_runtime_config(node_id, config_kdl) do
    config_hash =
      :crypto.hash(:sha256, config_kdl)
      |> Base.encode16(case: :lower)

    attrs = %{
      node_id: node_id,
      config_kdl: config_kdl,
      config_hash: config_hash
    }

    %NodeRuntimeConfig{}
    |> NodeRuntimeConfig.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:config_kdl, :config_hash, :updated_at]},
      conflict_target: :node_id
    )
  end

  @doc """
  Gets the runtime config for a node.
  """
  def get_runtime_config(node_id) do
    Repo.get_by(NodeRuntimeConfig, node_id: node_id)
  end

  @doc """
  Cleans up old heartbeat records.
  Keeps only the most recent records per node.
  """
  def cleanup_old_heartbeats(keep_count \\ 1000) do
    # This is a simple implementation - for production, consider a more efficient approach
    subquery =
      from(h in NodeHeartbeat,
        select: %{
          id: h.id,
          row_num: over(row_number(), partition_by: h.node_id, order_by: [desc: h.inserted_at])
        }
      )

    from(h in NodeHeartbeat,
      join: s in subquery(subquery),
      on: h.id == s.id,
      where: s.row_num > ^keep_count
    )
    |> Repo.delete_all()
  end

  ## Drift Detection

  @doc """
  Sets the expected_bundle_id for a list of node IDs.
  """
  def set_expected_bundle_for_nodes(node_ids, bundle_id) when is_list(node_ids) do
    from(n in Node, where: n.id in ^node_ids)
    |> Repo.update_all(set: [expected_bundle_id: bundle_id])
  end

  @doc """
  Lists nodes that are drifted (active_bundle_id != expected_bundle_id).
  Only considers online nodes with an expected_bundle_id set.
  """
  def list_drifted_nodes(project_id) do
    from(n in Node,
      where: n.project_id == ^project_id,
      where: n.status == "online",
      where: not is_nil(n.expected_bundle_id),
      where: n.active_bundle_id != n.expected_bundle_id or is_nil(n.active_bundle_id),
      order_by: [asc: n.name]
    )
    |> Repo.all()
  end

  @doc """
  Counts drifted nodes for a project.
  """
  def count_drifted_nodes(project_id) do
    from(n in Node,
      where: n.project_id == ^project_id,
      where: n.status == "online",
      where: not is_nil(n.expected_bundle_id),
      where: n.active_bundle_id != n.expected_bundle_id or is_nil(n.active_bundle_id)
    )
    |> Repo.aggregate(:count)
  end

  @doc """
  Returns drift statistics for a project.
  """
  def get_drift_stats(project_id) do
    total_managed =
      from(n in Node,
        where: n.project_id == ^project_id,
        where: not is_nil(n.expected_bundle_id)
      )
      |> Repo.aggregate(:count)

    drifted = count_drifted_nodes(project_id)

    %{
      total_managed: total_managed,
      drifted: drifted,
      in_sync: total_managed - drifted
    }
  end

  @doc """
  Returns drift statistics across multiple projects.
  """
  def get_fleet_drift_stats(project_ids) when is_list(project_ids) do
    if project_ids == [] do
      %{total_managed: 0, drifted: 0, in_sync: 0}
    else
      total_managed =
        from(n in Node,
          where: n.project_id in ^project_ids,
          where: not is_nil(n.expected_bundle_id)
        )
        |> Repo.aggregate(:count)

      drifted =
        from(n in Node,
          where: n.project_id in ^project_ids,
          where: n.status == "online",
          where: not is_nil(n.expected_bundle_id),
          where: n.active_bundle_id != n.expected_bundle_id or is_nil(n.active_bundle_id)
        )
        |> Repo.aggregate(:count)

      %{
        total_managed: total_managed,
        drifted: drifted,
        in_sync: total_managed - drifted
      }
    end
  end

  @doc """
  Checks if a node is drifted.
  """
  def node_drifted?(%Node{expected_bundle_id: nil}), do: false

  def node_drifted?(%Node{expected_bundle_id: expected, active_bundle_id: active}) do
    expected != active
  end

  ## Drift Events

  @doc """
  Gets a drift event by ID.
  """
  def get_drift_event(id), do: Repo.get(DriftEvent, id)

  @doc """
  Gets a drift event by ID, raises if not found.
  """
  def get_drift_event!(id), do: Repo.get!(DriftEvent, id)

  @doc """
  Creates a drift event.
  """
  def create_drift_event(attrs) do
    result =
      %DriftEvent{}
      |> DriftEvent.create_changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, event} ->
        ZentinelCp.PromEx.ZentinelPlugin.emit_drift_detected()
        broadcast_drift_event(event, :detected)

        # Async: send webhook and check auto-remediation
        Task.start(fn -> handle_drift_detected(event) end)

        result

      _ ->
        result
    end
  end

  @doc """
  Resolves a drift event with the given resolution.
  """
  def resolve_drift_event(%DriftEvent{} = event, resolution) do
    result =
      event
      |> DriftEvent.resolve_changeset(resolution)
      |> Repo.update()

    case result do
      {:ok, updated_event} ->
        ZentinelCp.PromEx.ZentinelPlugin.emit_drift_resolved(resolution)
        broadcast_drift_event(updated_event, :resolved)

        # Async: send webhook notification
        Task.start(fn -> handle_drift_resolved(updated_event) end)

        result

      _ ->
        result
    end
  end

  defp handle_drift_detected(event) do
    alias ZentinelCp.{Projects, Rollouts}
    alias ZentinelCp.Events, as: Notifications
    alias ZentinelCp.Projects.Project

    with node when not is_nil(node) <- get_node(event.node_id),
         project when not is_nil(project) <- Projects.get_project(event.project_id) do
      # Send webhook notification
      Notifications.notify_drift_detected(node, event, project)

      # Check if auto-remediation is enabled
      if Project.drift_auto_remediation?(project) do
        trigger_auto_remediation(project, node, event)
      end
    end
  end

  defp handle_drift_resolved(event) do
    alias ZentinelCp.Projects
    alias ZentinelCp.Events, as: Notifications

    with node when not is_nil(node) <- get_node(event.node_id),
         project when not is_nil(project) <- Projects.get_project(event.project_id) do
      Notifications.notify_drift_resolved(node, event, project)
    end
  end

  defp trigger_auto_remediation(project, node, event) do
    alias ZentinelCp.Rollouts

    # Create a rollout targeting just this node with the expected bundle
    attrs = %{
      project_id: project.id,
      bundle_id: event.expected_bundle_id,
      target_selector: %{"type" => "node_ids", "node_ids" => [node.id]},
      strategy: "all_at_once",
      batch_size: 1
    }

    case Rollouts.create_rollout(attrs) do
      {:ok, rollout} ->
        # Mark drift as being remediated
        resolve_drift_event(Repo.reload!(event), "rollout_started")

        # Plan and start the rollout
        case Rollouts.plan_rollout(rollout) do
          {:ok, _} ->
            require Logger

            Logger.info("Auto-remediation rollout started",
              rollout_id: rollout.id,
              node_id: node.id,
              bundle_id: event.expected_bundle_id
            )

          {:error, reason} ->
            require Logger

            Logger.warning("Auto-remediation rollout failed to plan",
              rollout_id: rollout.id,
              reason: inspect(reason)
            )
        end

      {:error, reason} ->
        require Logger

        Logger.warning("Auto-remediation rollout creation failed",
          node_id: node.id,
          reason: inspect(reason)
        )
    end
  end

  defp broadcast_drift_event(event, type) do
    # Broadcast to project-level topic for drift list page
    Phoenix.PubSub.broadcast(
      ZentinelCp.PubSub,
      "drift:#{event.project_id}",
      {:drift_event, type, event.node_id}
    )

    # Broadcast to node-level topic for node detail page
    Phoenix.PubSub.broadcast(
      ZentinelCp.PubSub,
      "node:#{event.node_id}:drift",
      {:drift_event, type, event.id}
    )
  end

  @doc """
  Gets the active (unresolved) drift event for a node.
  """
  def get_active_drift_event(node_id) do
    from(d in DriftEvent,
      where: d.node_id == ^node_id,
      where: is_nil(d.resolved_at),
      order_by: [desc: d.detected_at],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Lists drift events for a specific node.
  """
  def list_node_drift_events(node_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(d in DriftEvent,
      where: d.node_id == ^node_id,
      order_by: [desc: d.detected_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Lists drift events for a project.
  """
  def list_drift_events(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    include_resolved = Keyword.get(opts, :include_resolved, true)

    query =
      from(d in DriftEvent,
        where: d.project_id == ^project_id,
        order_by: [desc: d.detected_at],
        limit: ^limit,
        preload: [:node]
      )

    query =
      if include_resolved do
        query
      else
        where(query, [d], is_nil(d.resolved_at))
      end

    Repo.all(query)
  end

  @doc """
  Returns drift event statistics for a project.
  """
  def get_drift_event_stats(project_id) do
    active =
      from(d in DriftEvent,
        where: d.project_id == ^project_id,
        where: is_nil(d.resolved_at)
      )
      |> Repo.aggregate(:count)

    resolved_today =
      from(d in DriftEvent,
        where: d.project_id == ^project_id,
        where: not is_nil(d.resolved_at),
        where: d.resolved_at >= ^start_of_day()
      )
      |> Repo.aggregate(:count)

    %{
      active: active,
      resolved_today: resolved_today
    }
  end

  @doc """
  Returns drift event statistics across multiple projects.
  """
  def get_fleet_drift_event_stats(project_ids) when is_list(project_ids) do
    if project_ids == [] do
      %{active: 0, resolved_today: 0}
    else
      active =
        from(d in DriftEvent,
          where: d.project_id in ^project_ids,
          where: is_nil(d.resolved_at)
        )
        |> Repo.aggregate(:count)

      resolved_today =
        from(d in DriftEvent,
          where: d.project_id in ^project_ids,
          where: not is_nil(d.resolved_at),
          where: d.resolved_at >= ^start_of_day()
        )
        |> Repo.aggregate(:count)

      %{
        active: active,
        resolved_today: resolved_today
      }
    end
  end

  defp start_of_day do
    DateTime.utc_now()
    |> DateTime.to_date()
    |> DateTime.new!(~T[00:00:00], "Etc/UTC")
  end

  @doc """
  Resolves all active drift events for a node.
  """
  def resolve_node_drift_events(node_id, resolution) do
    from(d in DriftEvent,
      where: d.node_id == ^node_id,
      where: is_nil(d.resolved_at)
    )
    |> Repo.update_all(
      set: [
        resolved_at: DateTime.utc_now() |> DateTime.truncate(:second),
        resolution: resolution
      ]
    )
  end

  ## Node Groups

  alias ZentinelCp.Nodes.{NodeGroup, NodeGroupMembership}

  @doc """
  Lists all node groups for a project.
  """
  def list_node_groups(project_id) do
    from(g in NodeGroup,
      where: g.project_id == ^project_id,
      order_by: [asc: g.name],
      preload: [:nodes]
    )
    |> Repo.all()
  end

  @doc """
  Gets a node group by ID.
  """
  def get_node_group(id), do: Repo.get(NodeGroup, id)

  @doc """
  Gets a node group by ID, raises if not found.
  """
  def get_node_group!(id), do: Repo.get!(NodeGroup, id) |> Repo.preload(:nodes)

  @doc """
  Gets a node group by name within a project.
  """
  def get_node_group_by_name(project_id, name) do
    Repo.get_by(NodeGroup, project_id: project_id, name: name)
  end

  @doc """
  Creates a node group.
  """
  def create_node_group(attrs) do
    %NodeGroup{}
    |> NodeGroup.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a node group.
  """
  def update_node_group(%NodeGroup{} = group, attrs) do
    group
    |> NodeGroup.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a node group.
  """
  def delete_node_group(%NodeGroup{} = group) do
    Repo.delete(group)
  end

  @doc """
  Adds a node to a group.
  """
  def add_node_to_group(node_id, group_id) do
    %NodeGroupMembership{}
    |> NodeGroupMembership.changeset(%{node_id: node_id, node_group_id: group_id})
    |> Repo.insert()
  end

  @doc """
  Removes a node from a group.
  """
  def remove_node_from_group(node_id, group_id) do
    from(m in NodeGroupMembership,
      where: m.node_id == ^node_id,
      where: m.node_group_id == ^group_id
    )
    |> Repo.delete_all()
  end

  @doc """
  Sets the nodes in a group, replacing existing memberships.
  """
  def set_group_nodes(%NodeGroup{} = group, node_ids) when is_list(node_ids) do
    Repo.transaction(fn ->
      # Remove existing memberships
      from(m in NodeGroupMembership, where: m.node_group_id == ^group.id)
      |> Repo.delete_all()

      # Add new memberships
      Enum.each(node_ids, fn node_id ->
        %NodeGroupMembership{}
        |> NodeGroupMembership.changeset(%{node_id: node_id, node_group_id: group.id})
        |> Repo.insert!()
      end)

      Repo.preload(group, :nodes, force: true)
    end)
  end

  @doc """
  Gets nodes by group IDs.
  """
  def get_nodes_by_groups(group_ids) when is_list(group_ids) do
    from(n in Node,
      join: m in NodeGroupMembership,
      on: m.node_id == n.id,
      where: m.node_group_id in ^group_ids,
      distinct: true,
      order_by: [asc: n.name]
    )
    |> Repo.all()
  end

  ## Environment Assignment

  @doc """
  Assigns a node to an environment.
  """
  def assign_node_to_environment(node_id, environment_id) do
    node = get_node!(node_id)

    node
    |> Ecto.Changeset.change(%{environment_id: environment_id})
    |> Repo.update()
  end

  @doc """
  Removes a node from its environment.
  """
  def remove_node_from_environment(node_id) do
    assign_node_to_environment(node_id, nil)
  end

  @doc """
  Assigns multiple nodes to an environment.
  """
  def assign_nodes_to_environment(node_ids, environment_id) when is_list(node_ids) do
    from(n in Node, where: n.id in ^node_ids)
    |> Repo.update_all(set: [environment_id: environment_id])
  end

  ## Version Pinning

  @doc """
  Pins a node to a specific bundle version.
  """
  def pin_node_to_bundle(node_id, bundle_id) do
    node = get_node!(node_id)

    node
    |> Ecto.Changeset.change(%{pinned_bundle_id: bundle_id})
    |> Repo.update()
  end

  @doc """
  Unpins a node from its current bundle.
  """
  def unpin_node(node_id) do
    node = get_node!(node_id)

    node
    |> Ecto.Changeset.change(%{pinned_bundle_id: nil})
    |> Repo.update()
  end

  @doc """
  Sets version constraints for a node.
  """
  def set_node_version_constraints(node_id, opts) do
    node = get_node!(node_id)

    changes = %{
      min_bundle_version: Keyword.get(opts, :min_version),
      max_bundle_version: Keyword.get(opts, :max_version)
    }

    node
    |> Ecto.Changeset.change(changes)
    |> Repo.update()
  end

  @doc """
  Checks if a bundle version satisfies node constraints.
  """
  def bundle_satisfies_constraints?(bundle, node) do
    version = bundle.version

    min_ok =
      case node.min_bundle_version do
        nil -> true
        min -> Version.compare(version, min) in [:gt, :eq]
      end

    max_ok =
      case node.max_bundle_version do
        nil -> true
        max -> Version.compare(version, max) in [:lt, :eq]
      end

    min_ok and max_ok
  rescue
    # Version.compare can fail if versions aren't semver-compatible
    _ -> true
  end

  defp parse_optional_datetime(nil), do: nil

  defp parse_optional_datetime(%DateTime{} = dt), do: DateTime.truncate(dt, :second)

  defp parse_optional_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end

  defp parse_optional_datetime(_), do: nil
end
