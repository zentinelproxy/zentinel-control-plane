defmodule ZentinelCp.OrgsFixtures do
  @moduledoc """
  Test helpers for creating Orgs entities.
  """

  def unique_org_name, do: "org-#{System.unique_integer([:positive])}"

  def valid_org_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: unique_org_name()
    })
  end

  def org_fixture(attrs \\ %{}) do
    {:ok, org} =
      attrs
      |> valid_org_attributes()
      |> ZentinelCp.Orgs.create_org()

    org
  end

  def org_with_owner_fixture(attrs \\ %{}) do
    user = attrs[:user] || ZentinelCp.AccountsFixtures.user_fixture()
    org_attrs = Map.drop(attrs, [:user])

    {:ok, org} =
      org_attrs
      |> valid_org_attributes()
      |> ZentinelCp.Orgs.create_org_with_owner(user)

    {org, user}
  end
end
