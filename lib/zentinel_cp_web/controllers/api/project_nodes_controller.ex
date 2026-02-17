defmodule ZentinelCpWeb.Api.ProjectNodesController do
  @moduledoc """
  API controller for control plane node management.
  These endpoints are called by operators/API keys, not nodes.
  """
  use ZentinelCpWeb, :controller

  alias ZentinelCp.{Audit, Nodes, Projects}

  @doc """
  GET /api/v1/projects/:project_slug/nodes

  Lists all nodes for a project.
  """
  def index(conn, %{"project_slug" => project_slug} = params) do
    with {:ok, project} <- get_project(project_slug) do
      opts = build_filter_opts(params)
      nodes = Nodes.list_nodes(project.id, opts)

      conn
      |> put_status(:ok)
      |> json(%{
        nodes: Enum.map(nodes, &node_to_json/1),
        total: length(nodes)
      })
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})
    end
  end

  @doc """
  GET /api/v1/projects/:project_slug/nodes/:node_id

  Gets a single node.
  """
  def show(conn, %{"project_slug" => project_slug, "id" => node_id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, node} <- get_node(node_id, project.id) do
      conn
      |> put_status(:ok)
      |> json(%{node: node_to_json(node)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :node_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Node not found"})
    end
  end

  @doc """
  GET /api/v1/projects/:project_slug/nodes/stats

  Returns node statistics for a project.
  """
  def stats(conn, %{"project_slug" => project_slug}) do
    with {:ok, project} <- get_project(project_slug) do
      stats = Nodes.get_node_stats(project.id)
      total = Nodes.count_nodes(project.id)

      conn
      |> put_status(:ok)
      |> json(%{
        total: total,
        by_status: stats
      })
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})
    end
  end

  @doc """
  DELETE /api/v1/projects/:project_slug/nodes/:node_id

  Deletes a node.
  """
  def delete(conn, %{"project_slug" => project_slug, "id" => node_id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, node} <- get_node(node_id, project.id),
         {:ok, _} <- Nodes.delete_node(node) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "node.deleted", "node", node.id,
        project_id: project.id,
        metadata: %{node_name: node.name}
      )

      conn
      |> put_status(:no_content)
      |> send_resp(:no_content, "")
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :node_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Node not found"})
    end
  end

  # Private helpers

  defp get_project(slug) do
    case Projects.get_project_by_slug(slug) do
      nil -> {:error, :project_not_found}
      project -> {:ok, project}
    end
  end

  defp get_node(node_id, project_id) do
    case Nodes.get_node(node_id) do
      nil -> {:error, :node_not_found}
      %{project_id: ^project_id} = node -> {:ok, node}
      _ -> {:error, :node_not_found}
    end
  end

  defp build_filter_opts(params) do
    []
    |> maybe_add_status(params)
    |> maybe_add_labels(params)
  end

  defp maybe_add_status(opts, %{"status" => status}) when status in ~w(online offline unknown),
    do: [{:status, status} | opts]

  defp maybe_add_status(opts, _), do: opts

  defp maybe_add_labels(opts, %{"labels" => labels}) when is_map(labels),
    do: [{:labels, labels} | opts]

  defp maybe_add_labels(opts, _), do: opts

  defp node_to_json(node) do
    %{
      id: node.id,
      name: node.name,
      status: node.status,
      labels: node.labels,
      capabilities: node.capabilities,
      version: node.version,
      ip: node.ip,
      hostname: node.hostname,
      last_seen_at: node.last_seen_at,
      registered_at: node.registered_at,
      inserted_at: node.inserted_at
    }
  end
end
