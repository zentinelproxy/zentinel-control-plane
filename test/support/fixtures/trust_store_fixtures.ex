defmodule ZentinelCp.TrustStoreFixtures do
  @moduledoc """
  Test helpers for creating TrustStore entities.
  """

  def unique_trust_store_name, do: "trust-store-#{System.unique_integer([:positive])}"

  def trust_store_fixture(attrs \\ %{}) do
    project = attrs[:project] || ZentinelCp.ProjectsFixtures.project_fixture()

    {:ok, trust_store} =
      ZentinelCp.Services.create_trust_store(%{
        name: attrs[:name] || unique_trust_store_name(),
        description: attrs[:description],
        certificates_pem:
          attrs[:certificates_pem] || ZentinelCp.CertificateFixtures.test_cert_pem(),
        project_id: project.id
      })

    trust_store
  end
end
