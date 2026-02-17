defmodule ZentinelCpWeb.E2E.NodeManagementTest do
  @moduledoc """
  E2E tests for node management UI.

  Tests empty state, node list, status filter, and delete node.
  """
  use ZentinelCpWeb.FeatureCase

  @moduletag :e2e

  import Wallaby.Query

  describe "nodes list page" do
    feature "shows empty state when no nodes", %{session: session} do
      {session, context} = setup_full_context(session)

      session
      |> visit("/projects/#{context.project.slug}/nodes")
      |> assert_has(css("h1", text: "Nodes"))
      |> assert_has(css("[data-testid='empty-state']", text: "No nodes"))
    end

    feature "displays nodes when they exist", %{session: session} do
      {session, context} = setup_full_context(session)

      ZentinelCp.NodesFixtures.node_fixture(%{
        project: context.project,
        name: "web-proxy-1"
      })

      ZentinelCp.NodesFixtures.node_fixture(%{
        project: context.project,
        name: "api-proxy-2"
      })

      session
      |> visit("/projects/#{context.project.slug}/nodes")
      |> assert_has(css("h1", text: "Nodes"))
      |> assert_has(css("table"))
      |> assert_has(css("td", text: "web-proxy-1"))
      |> assert_has(css("td", text: "api-proxy-2"))
    end

    feature "shows stats cards", %{session: session} do
      {session, context} = setup_full_context(session)

      node = ZentinelCp.NodesFixtures.node_fixture(%{project: context.project})
      ZentinelCp.Nodes.record_heartbeat(node, %{health: %{"status" => "healthy"}})

      session
      |> visit("/projects/#{context.project.slug}/nodes")
      |> assert_has(css("[data-testid='stats-online']"))
      |> assert_has(css("[data-testid='stats-total']"))
    end
  end

  describe "node filtering" do
    feature "filter nodes by status", %{session: session} do
      {session, context} = setup_full_context(session)

      online_node =
        ZentinelCp.NodesFixtures.node_fixture(%{
          project: context.project,
          name: "online-proxy"
        })

      ZentinelCp.NodesFixtures.node_fixture(%{
        project: context.project,
        name: "offline-proxy"
      })

      # Make one node online
      ZentinelCp.Nodes.record_heartbeat(online_node, %{health: %{"status" => "healthy"}})

      session
      |> visit("/projects/#{context.project.slug}/nodes")
      |> assert_has(css("td", text: "online-proxy"))
      |> assert_has(css("td", text: "offline-proxy"))
      |> click(css("select[name='status'] option[value='online']"))
      |> assert_has(css("td", text: "online-proxy"))
    end
  end

  describe "node deletion" do
    feature "delete node from list", %{session: session} do
      {session, context} = setup_full_context(session)

      node =
        ZentinelCp.NodesFixtures.node_fixture(%{
          project: context.project,
          name: "deletable-proxy"
        })

      session
      |> visit("/projects/#{context.project.slug}/nodes")
      |> assert_has(css("td", text: "deletable-proxy"))
      |> click(css("button[phx-click='delete'][phx-value-id='#{node.id}']"))
      |> refute_has(css("td", text: "deletable-proxy"))
    end
  end

  describe "node details" do
    feature "view node details page", %{session: session} do
      {session, context} = setup_full_context(session)

      node =
        ZentinelCp.NodesFixtures.node_fixture(%{
          project: context.project,
          name: "detail-proxy",
          labels: %{"env" => "production", "region" => "us-east"}
        })

      session
      |> visit("/projects/#{context.project.slug}/nodes/#{node.id}")
      |> assert_has(css("h1", text: "detail-proxy"))
      |> assert_has(css("[data-testid='node-labels']", text: "production"))
    end
  end
end
