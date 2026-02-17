defmodule ZentinelCp.Audit do
  @moduledoc """
  The Audit context handles audit logging for all mutations.
  """

  import Ecto.Query, warn: false
  alias ZentinelCp.Repo
  alias ZentinelCp.Audit.{AuditLog, ChainVerifier}

  @audit_topic "audit_logs"

  @doc """
  Logs an audit event and broadcasts it via PubSub.
  Includes tamper-evident HMAC chain linking.
  """
  def log(attrs) do
    previous_hash = ChainVerifier.get_latest_hash()
    entry_hash = ChainVerifier.compute_entry_hash(attrs, previous_hash)

    attrs =
      attrs
      |> Map.put(:previous_hash, previous_hash)
      |> Map.put(:entry_hash, entry_hash)

    result =
      %AuditLog{}
      |> AuditLog.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, log_entry} ->
        Phoenix.PubSub.broadcast(ZentinelCp.PubSub, @audit_topic, {:audit_log_created, log_entry})
        {:ok, log_entry}

      error ->
        error
    end
  end

  @doc """
  Logs an audit event for a user action.
  """
  def log_user_action(user, action, resource_type, resource_id, opts \\ []) do
    log(%{
      actor_type: "user",
      actor_id: user.id,
      action: action,
      resource_type: resource_type,
      resource_id: resource_id,
      project_id: opts[:project_id],
      org_id: opts[:org_id],
      changes: opts[:changes] || %{},
      metadata: opts[:metadata] || %{}
    })
  end

  @doc """
  Logs an audit event for an API key action.
  """
  def log_api_key_action(api_key, action, resource_type, resource_id, opts \\ []) do
    log(%{
      actor_type: "api_key",
      actor_id: api_key.id,
      action: action,
      resource_type: resource_type,
      resource_id: resource_id,
      project_id: api_key.project_id || opts[:project_id],
      org_id: opts[:org_id],
      changes: opts[:changes] || %{},
      metadata: opts[:metadata] || %{}
    })
  end

  @doc """
  Logs an audit event for a node action.
  """
  def log_node_action(node, action, resource_type, resource_id, opts \\ []) do
    log(%{
      actor_type: "node",
      actor_id: node.id,
      action: action,
      resource_type: resource_type,
      resource_id: resource_id,
      project_id: node.project_id,
      org_id: opts[:org_id],
      changes: opts[:changes] || %{},
      metadata: opts[:metadata] || %{}
    })
  end

  @doc """
  Logs an audit event for a system action.
  """
  def log_system_action(action, resource_type, resource_id, opts \\ []) do
    log(%{
      actor_type: "system",
      actor_id: nil,
      action: action,
      resource_type: resource_type,
      resource_id: resource_id,
      project_id: opts[:project_id],
      org_id: opts[:org_id],
      changes: opts[:changes] || %{},
      metadata: opts[:metadata] || %{}
    })
  end

  @doc """
  Lists audit logs for a project with filtering and pagination.

  ## Options

    * `:limit` - max results (default 25)
    * `:offset` - offset for pagination (default 0)
    * `:action` - filter by action
    * `:resource_type` - filter by resource type
    * `:actor_type` - filter by actor type

  Returns `{entries, total_count}`.
  """
  def list_audit_logs(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 25)
    offset = Keyword.get(opts, :offset, 0)

    base_query =
      from(a in AuditLog,
        where: a.project_id == ^project_id,
        order_by: [desc: a.inserted_at]
      )

    filtered_query = apply_filters(base_query, opts)

    total = Repo.aggregate(filtered_query, :count)

    entries =
      filtered_query
      |> limit(^limit)
      |> offset(^offset)
      |> Repo.all()

    {entries, total}
  end

  @doc """
  Lists all audit logs across projects with filtering and pagination.

  Same options as `list_audit_logs/2` plus:
    * `:date_from` - filter from date (DateTime)
    * `:date_to` - filter to date (DateTime)

  Returns `{entries, total_count}`.
  """
  def list_all_audit_logs(opts \\ []) do
    limit = Keyword.get(opts, :limit, 25)
    offset = Keyword.get(opts, :offset, 0)

    base_query =
      from(a in AuditLog,
        order_by: [desc: a.inserted_at]
      )

    filtered_query = apply_filters(base_query, opts)

    total = Repo.aggregate(filtered_query, :count)

    entries =
      filtered_query
      |> limit(^limit)
      |> offset(^offset)
      |> Repo.all()

    {entries, total}
  end

  @doc """
  Lists audit logs for a specific resource.
  """
  def list_audit_logs_for_resource(resource_type, resource_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    from(a in AuditLog,
      where: a.resource_type == ^resource_type and a.resource_id == ^resource_id,
      order_by: [desc: a.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Subscribes to real-time audit log updates.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(ZentinelCp.PubSub, @audit_topic)
  end

  defp apply_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {:action, action}, q when is_binary(action) ->
        where(q, [a], a.action == ^action)

      {:resource_type, type}, q when is_binary(type) ->
        where(q, [a], a.resource_type == ^type)

      {:actor_type, type}, q when is_binary(type) ->
        where(q, [a], a.actor_type == ^type)

      {:actor_id, id}, q when is_binary(id) ->
        where(q, [a], a.actor_id == ^id)

      {:date_from, %DateTime{} = dt}, q ->
        where(q, [a], a.inserted_at >= ^dt)

      {:date_to, %DateTime{} = dt}, q ->
        where(q, [a], a.inserted_at <= ^dt)

      {:search, term}, q when is_binary(term) and term != "" ->
        pattern = "%#{term}%"
        where(q, [a], like(a.action, ^pattern) or like(a.resource_type, ^pattern))

      _, q ->
        q
    end)
  end

  @doc """
  Exports audit logs in the specified format.

  ## Options
  Same as `list_audit_logs/2` plus:
    * `:format` - "json" or "csv" (default "json")

  Returns `{:ok, content, filename}`.
  """
  def export_audit_logs(project_id, opts \\ []) do
    format = Keyword.get(opts, :format, "json")
    # Get all matching logs (high limit for export)
    opts = Keyword.put(opts, :limit, 10_000)

    {entries, _total} = list_audit_logs(project_id, opts)

    {content, ext} =
      case format do
        "csv" -> {entries_to_csv(entries), "csv"}
        _ -> {entries_to_json(entries), "json"}
      end

    filename = "audit-logs-#{Date.utc_today()}.#{ext}"
    {:ok, content, filename}
  end

  @doc """
  Exports all audit logs across projects.
  """
  def export_all_audit_logs(opts \\ []) do
    format = Keyword.get(opts, :format, "json")
    opts = Keyword.put(opts, :limit, 10_000)

    {entries, _total} = list_all_audit_logs(opts)

    {content, ext} =
      case format do
        "csv" -> {entries_to_csv(entries), "csv"}
        _ -> {entries_to_json(entries), "json"}
      end

    filename = "audit-logs-all-#{Date.utc_today()}.#{ext}"
    {:ok, content, filename}
  end

  defp entries_to_json(entries) do
    data = %{
      exported_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      total: length(entries),
      entries: Enum.map(entries, &entry_to_map/1)
    }

    Jason.encode!(data, pretty: true)
  end

  defp entries_to_csv(entries) do
    headers = [
      "id",
      "timestamp",
      "actor_type",
      "actor_id",
      "action",
      "resource_type",
      "resource_id",
      "project_id",
      "org_id"
    ]

    rows =
      Enum.map(entries, fn entry ->
        [
          entry.id,
          entry.inserted_at && DateTime.to_iso8601(entry.inserted_at),
          entry.actor_type,
          entry.actor_id,
          entry.action,
          entry.resource_type,
          entry.resource_id,
          entry.project_id,
          entry.org_id
        ]
      end)

    [headers | rows]
    |> Enum.map(&csv_row/1)
    |> Enum.join("\n")
  end

  defp csv_row(cells) do
    cells
    |> Enum.map(&csv_escape/1)
    |> Enum.join(",")
  end

  defp csv_escape(nil), do: ""

  defp csv_escape(val) when is_binary(val) do
    if String.contains?(val, [",", "\"", "\n"]) do
      "\"#{String.replace(val, "\"", "\"\"")}\""
    else
      val
    end
  end

  defp csv_escape(val), do: to_string(val)

  defp entry_to_map(entry) do
    %{
      id: entry.id,
      timestamp: entry.inserted_at && DateTime.to_iso8601(entry.inserted_at),
      actor_type: entry.actor_type,
      actor_id: entry.actor_id,
      action: entry.action,
      resource_type: entry.resource_type,
      resource_id: entry.resource_id,
      project_id: entry.project_id,
      org_id: entry.org_id,
      changes: entry.changes,
      metadata: entry.metadata
    }
  end
end
