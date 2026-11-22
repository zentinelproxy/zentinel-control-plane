defmodule ZentinelCp.Net.OutboundChecksTest do
  @moduledoc """
  Addresses a project configures for service discovery and Vault are checked
  before the control plane requests them, and the control plane's own
  Kubernetes credentials are used only when the operator allows it. Every case
  here fails before a request is sent, so no server is needed.
  """
  use ExUnit.Case, async: false

  alias ZentinelCp.Services.ConsulResolver
  alias ZentinelCp.Services.K8sResolver
  alias ZentinelCp.Secrets.VaultClient

  setup do
    previous = Application.get_env(:zentinel_cp, :allow_private_outbound)
    Application.put_env(:zentinel_cp, :allow_private_outbound, false)
    on_exit(fn -> Application.put_env(:zentinel_cp, :allow_private_outbound, previous) end)
  end

  describe "Consul discovery" do
    test "refuses a loopback or link-local address" do
      for addr <- ["http://127.0.0.1:8500", "http://169.254.169.254"] do
        assert {:error, "Consul address is not allowed: " <> _} =
                 ConsulResolver.HTTP.resolve_service(%{
                   "consul_addr" => addr,
                   "service_name" => "web"
                 })
      end
    end

    test "refuses an address with a query or fragment" do
      for addr <- ["http://10.0.0.5:8500/x?", "http://10.0.0.5:8500/#x"] do
        assert {:error, "Consul address must not contain a query or fragment"} =
                 ConsulResolver.HTTP.resolve_service(%{
                   "consul_addr" => addr,
                   "service_name" => "web"
                 })
      end
    end
  end

  describe "Kubernetes discovery" do
    test "refuses a namespace or service name that is not a Kubernetes name" do
      base = %{"api_url" => "https://10.0.0.1:6443", "token" => "t"}

      assert {:error, "namespace is not a valid Kubernetes name"} =
               K8sResolver.HTTP.resolve_endpoints(
                 Map.merge(base, %{"namespace" => "kube-system/secrets?", "service_name" => "web"})
               )

      assert {:error, "service_name is not a valid Kubernetes name"} =
               K8sResolver.HTTP.resolve_endpoints(
                 Map.merge(base, %{"namespace" => "default", "service_name" => "../secrets"})
               )
    end

    test "refuses a loopback API URL" do
      assert {:error, "Kubernetes API URL is not allowed: " <> _} =
               K8sResolver.HTTP.resolve_endpoints(%{
                 "api_url" => "https://127.0.0.1:6443",
                 "token" => "t",
                 "namespace" => "default",
                 "service_name" => "web"
               })
    end

    test "does not fall back to the control plane's own service account by default" do
      refute Application.get_env(:zentinel_cp, :k8s_discovery_in_cluster, false)

      assert {:error, "No Kubernetes credentials configured and not running in-cluster"} =
               K8sResolver.HTTP.resolve_endpoints(%{
                 "namespace" => "default",
                 "service_name" => "web"
               })
    end
  end

  describe "Vault" do
    test "refuses a loopback or link-local address" do
      for addr <- ["http://127.0.0.1:8200", "http://169.254.169.254"] do
        config = %{
          vault_addr: addr,
          auth_method: "token",
          auth_config: %{"token" => "t"},
          mount_path: nil,
          base_path: nil
        }

        assert {:error, "Vault address is not allowed: " <> _} =
                 VaultClient.HTTP.read_secret(config, "x")
      end
    end

    test "does not send the control plane's own service account token by default" do
      refute Application.get_env(:zentinel_cp, :vault_kubernetes_in_cluster_jwt, false)

      config = %{
        vault_addr: "https://vault.example.com",
        auth_method: "kubernetes",
        auth_config: %{"role" => "r"},
        mount_path: nil,
        base_path: nil
      }

      assert {:error, "No JWT available for Kubernetes auth"} =
               VaultClient.HTTP.read_secret(config, "x")
    end
  end
end
