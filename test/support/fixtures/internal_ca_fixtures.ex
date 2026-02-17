defmodule ZentinelCp.InternalCaFixtures do
  @moduledoc """
  Test helpers for creating Internal CA and Issued Certificate entities.
  """

  alias ZentinelCp.Services

  def unique_ca_name, do: "test-ca-#{System.unique_integer([:positive])}"
  def unique_cert_name, do: "test-cert-#{System.unique_integer([:positive])}"

  @doc """
  Creates an internal CA fixture.

  Options:
    * `:project` — Project to associate with (default: new fixture)
    * `:name` — CA name (default: generated)
    * `:subject_cn` — Subject CN (default: "Test Internal CA")
    * `:key_algorithm` — Algorithm (default: "EC-P384")
  """
  def internal_ca_fixture(attrs \\ %{}) do
    project = attrs[:project] || ZentinelCp.ProjectsFixtures.project_fixture()

    {:ok, ca} =
      Services.initialize_internal_ca(%{
        name: attrs[:name] || unique_ca_name(),
        subject_cn: attrs[:subject_cn] || "Test Internal CA",
        key_algorithm: attrs[:key_algorithm] || "EC-P384",
        project_id: project.id
      })

    ca
  end

  @doc """
  Creates an issued certificate fixture.

  Options:
    * `:internal_ca` — Internal CA to issue from (default: new fixture)
    * `:name` — Certificate name (default: generated)
    * `:subject_cn` — Subject CN (default: "test-client.example.com")
    * `:subject_ou` — Organization Unit (default: nil)
    * `:validity_days` — Validity in days (default: 365)
  """
  def issued_certificate_fixture(attrs \\ %{}) do
    ca = attrs[:internal_ca] || internal_ca_fixture()

    {:ok, cert} =
      Services.issue_certificate(ca, %{
        name: attrs[:name] || unique_cert_name(),
        subject_cn: attrs[:subject_cn] || "test-client.example.com",
        subject_ou: attrs[:subject_ou],
        validity_days: attrs[:validity_days] || 365
      })

    cert
  end
end
