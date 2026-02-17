defmodule ZentinelCp.NodesFixtures do
  @moduledoc """
  Test helpers for creating Nodes entities.
  """

  def unique_node_name, do: "node-#{System.unique_integer([:positive])}"

  def valid_node_attributes(attrs \\ %{}) do
    project = attrs[:project] || ZentinelCp.ProjectsFixtures.project_fixture()

    Enum.into(attrs, %{
      name: unique_node_name(),
      project_id: project.id,
      labels: %{"env" => "test"},
      capabilities: ["proxy"],
      version: "0.4.7"
    })
  end

  @doc """
  Creates a node and returns {node, node_key}.
  The node_key is only available at registration time.
  """
  def node_fixture(attrs \\ %{}) do
    {:ok, node} =
      attrs
      |> valid_node_attributes()
      |> ZentinelCp.Nodes.register_node()

    node
  end

  @doc """
  Creates a node and returns {node, raw_node_key} tuple.
  """
  def node_with_key_fixture(attrs \\ %{}) do
    node = node_fixture(attrs)
    # node_key is a virtual field, available only right after registration
    {node, node.node_key}
  end

  @doc """
  Creates a drift event for testing.
  """
  def drift_event_fixture(attrs \\ %{}) do
    node = attrs[:node] || node_fixture()
    project = attrs[:project] || ZentinelCp.ProjectsFixtures.project_fixture()

    {:ok, event} =
      ZentinelCp.Nodes.create_drift_event(%{
        node_id: node.id,
        project_id: project.id,
        expected_bundle_id: attrs[:expected_bundle_id] || Ecto.UUID.generate(),
        actual_bundle_id: attrs[:actual_bundle_id],
        detected_at: attrs[:detected_at] || DateTime.utc_now() |> DateTime.truncate(:second),
        severity: attrs[:severity] || "medium",
        diff_stats: attrs[:diff_stats]
      })

    event
  end
end
