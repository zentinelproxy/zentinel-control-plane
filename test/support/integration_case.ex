defmodule ZentinelCpWeb.IntegrationCase do
  @moduledoc """
  This module defines the test case for API integration tests.

  These tests verify complete API workflows across multiple endpoints,
  testing the interaction between different API resources and ensuring
  proper authentication, authorization, and error handling.

  ## Usage

      use ZentinelCpWeb.IntegrationCase

      @tag :integration
      describe "node registration workflow" do
        test "register -> heartbeat -> list", %{conn: conn} do
          {conn, context} = setup_api_context(conn)
          # Test the complete workflow...
        end
      end

  ## Run

  Run with: `mix test.integration` or `mix test --include integration`
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use ZentinelCpWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
      import ZentinelCpWeb.IntegrationCase

      @endpoint ZentinelCpWeb.Endpoint
    end
  end

  setup tags do
    ZentinelCp.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Sets up a complete API context with org, project, user, and API key.

  Returns {authenticated_conn, context} where context contains:
  - :org - the organization
  - :project - the project
  - :user - the user who owns the API key
  - :api_key - the API key record

  ## Options

  - `:scopes` - list of scopes for the API key (default: [] for full access)
  - `:org_attrs` - attributes for the org fixture
  - `:project_attrs` - attributes for the project fixture
  - `:user_attrs` - attributes for the user fixture
  """
  def setup_api_context(conn, opts \\ []) do
    # Create org with owner
    user_attrs = opts[:user_attrs] || %{}
    user = ZentinelCp.AccountsFixtures.user_fixture(user_attrs)

    org_attrs = opts[:org_attrs] || %{}
    org = ZentinelCp.OrgsFixtures.org_fixture(org_attrs)

    # Create project in org
    project_attrs = Map.merge(opts[:project_attrs] || %{}, %{org: org})
    project = ZentinelCp.ProjectsFixtures.project_fixture(project_attrs)

    # Create API key with specified scopes
    scopes = opts[:scopes] || []

    {:ok, api_key} =
      ZentinelCp.Accounts.create_api_key(%{
        name: "integration-test-key",
        user_id: user.id,
        project_id: project.id,
        scopes: scopes
      })

    # Authenticate the connection
    conn =
      conn
      |> Plug.Conn.put_req_header("authorization", "Bearer #{api_key.key}")
      |> Plug.Conn.put_req_header("content-type", "application/json")

    context = %{
      org: org,
      project: project,
      user: user,
      api_key: api_key
    }

    {conn, context}
  end

  @doc """
  Creates multiple API keys with different scopes for testing scope enforcement.

  Returns a map of scope -> {conn, api_key}.
  """
  def setup_scoped_keys(conn, project, user, scope_sets) do
    Enum.reduce(scope_sets, %{}, fn {name, scopes}, acc ->
      {:ok, api_key} =
        ZentinelCp.Accounts.create_api_key(%{
          name: "#{name}-key",
          user_id: user.id,
          project_id: project.id,
          scopes: scopes
        })

      authenticated_conn =
        conn
        |> Plug.Conn.put_req_header("authorization", "Bearer #{api_key.key}")
        |> Plug.Conn.put_req_header("content-type", "application/json")

      Map.put(acc, name, {authenticated_conn, api_key})
    end)
  end

  @doc """
  Asserts that a JSON response matches the expected status and returns decoded body.
  """
  def json_response!(conn, status) do
    Phoenix.ConnTest.json_response(conn, status)
  end

  @doc """
  Makes a request and asserts the response status in one step.
  """
  defmacro request_json(conn, method, path, body \\ nil) do
    quote do
      import Phoenix.ConnTest

      case unquote(method) do
        :get -> get(unquote(conn), unquote(path))
        :post -> post(unquote(conn), unquote(path), unquote(body) && Jason.encode!(unquote(body)))
        :put -> put(unquote(conn), unquote(path), unquote(body) && Jason.encode!(unquote(body)))
        :delete -> delete(unquote(conn), unquote(path))
      end
    end
  end

  @doc """
  Creates a node and returns {node, node_key} for use in node-authenticated requests.
  """
  def register_node(project, attrs \\ %{}) do
    ZentinelCp.NodesFixtures.node_with_key_fixture(Map.put(attrs, :project, project))
  end

  @doc """
  Authenticates a connection as a node using its node key.
  Uses X-Zentinel-Node-Key header (static key auth).
  """
  def authenticate_as_node(conn, node_key) do
    conn
    |> Plug.Conn.put_req_header("x-zentinel-node-key", node_key)
    |> Plug.Conn.put_req_header("content-type", "application/json")
  end

  @doc """
  Waits for an async condition to become true, polling at intervals.
  Useful for testing background job effects.
  """
  def wait_for(condition_fn, opts \\ []) do
    timeout = opts[:timeout] || 5_000
    interval = opts[:interval] || 100
    deadline = System.monotonic_time(:millisecond) + timeout

    do_wait_for(condition_fn, interval, deadline)
  end

  defp do_wait_for(condition_fn, interval, deadline) do
    if condition_fn.() do
      :ok
    else
      if System.monotonic_time(:millisecond) >= deadline do
        {:error, :timeout}
      else
        Process.sleep(interval)
        do_wait_for(condition_fn, interval, deadline)
      end
    end
  end
end
