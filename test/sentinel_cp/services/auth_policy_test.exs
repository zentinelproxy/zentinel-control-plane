defmodule SentinelCp.Services.AuthPolicyTest do
  use SentinelCp.DataCase

  alias SentinelCp.Services
  alias SentinelCp.Services.AuthPolicy

  import SentinelCp.ProjectsFixtures
  import SentinelCp.AuthPolicyFixtures

  describe "create_auth_policy/1" do
    test "creates auth policy with valid attributes" do
      project = project_fixture()

      assert {:ok, %AuthPolicy{} = policy} =
               Services.create_auth_policy(%{
                 project_id: project.id,
                 name: "JWT Validator",
                 auth_type: "jwt",
                 config: %{"issuer" => "https://auth.example.com", "audience" => "my-api"}
               })

      assert policy.name == "JWT Validator"
      assert policy.slug == "jwt-validator"
      assert policy.auth_type == "jwt"
      assert policy.config["issuer"] == "https://auth.example.com"
      assert policy.enabled == true
    end

    test "auto-generates slug from name" do
      project = project_fixture()

      {:ok, policy} =
        Services.create_auth_policy(%{
          project_id: project.id,
          name: "My API Key Policy!",
          auth_type: "api_key"
        })

      assert policy.slug == "my-api-key-policy"
    end

    test "validates auth_type inclusion" do
      project = project_fixture()

      assert {:error, changeset} =
               Services.create_auth_policy(%{
                 project_id: project.id,
                 name: "Bad Type",
                 auth_type: "invalid"
               })

      assert %{auth_type: ["is invalid"]} = errors_on(changeset)
    end

    test "validates required fields" do
      assert {:error, changeset} = Services.create_auth_policy(%{})
      errors = errors_on(changeset)
      assert errors[:name]
      assert errors[:auth_type]
      assert errors[:project_id]
    end

    test "enforces unique slug within project" do
      project = project_fixture()

      {:ok, _} =
        Services.create_auth_policy(%{
          project_id: project.id,
          name: "JWT Policy",
          auth_type: "jwt"
        })

      assert {:error, changeset} =
               Services.create_auth_policy(%{
                 project_id: project.id,
                 name: "JWT Policy",
                 auth_type: "jwt"
               })

      assert %{slug: ["has already been taken"]} = errors_on(changeset)
    end

    test "allows same name in different projects" do
      p1 = project_fixture()
      p2 = project_fixture()

      assert {:ok, _} =
               Services.create_auth_policy(%{
                 project_id: p1.id,
                 name: "JWT",
                 auth_type: "jwt"
               })

      assert {:ok, _} =
               Services.create_auth_policy(%{
                 project_id: p2.id,
                 name: "JWT",
                 auth_type: "jwt"
               })
    end

    test "creates each auth type" do
      project = project_fixture()

      for type <- ~w(jwt api_key basic forward_auth mtls) do
        assert {:ok, policy} =
                 Services.create_auth_policy(%{
                   project_id: project.id,
                   name: "#{type} policy",
                   auth_type: type
                 })

        assert policy.auth_type == type
      end
    end
  end

  describe "list_auth_policies/1" do
    test "returns policies for a project ordered by name" do
      project = project_fixture()
      _p1 = auth_policy_fixture(%{project: project, name: "Zeta"})
      _p2 = auth_policy_fixture(%{project: project, name: "Alpha"})

      policies = Services.list_auth_policies(project.id)
      assert length(policies) == 2
      assert hd(policies).name == "Alpha"
    end

    test "does not include policies from other projects" do
      project = project_fixture()
      other = project_fixture()
      _p1 = auth_policy_fixture(%{project: project})
      _p2 = auth_policy_fixture(%{project: other})

      assert length(Services.list_auth_policies(project.id)) == 1
    end
  end

  describe "get_auth_policy/1" do
    test "returns policy by id" do
      policy = auth_policy_fixture()
      found = Services.get_auth_policy(policy.id)
      assert found.id == policy.id
    end

    test "returns nil for unknown id" do
      refute Services.get_auth_policy(Ecto.UUID.generate())
    end
  end

  describe "update_auth_policy/2" do
    test "updates an auth policy" do
      policy = auth_policy_fixture()

      assert {:ok, updated} =
               Services.update_auth_policy(policy, %{
                 name: "Updated Policy",
                 config: %{"issuer" => "https://new.example.com"}
               })

      assert updated.name == "Updated Policy"
      assert updated.config["issuer"] == "https://new.example.com"
    end

    test "validates auth_type on update" do
      policy = auth_policy_fixture()

      assert {:error, changeset} =
               Services.update_auth_policy(policy, %{auth_type: "invalid"})

      assert %{auth_type: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "delete_auth_policy/1" do
    test "deletes an auth policy" do
      policy = auth_policy_fixture()
      assert {:ok, _} = Services.delete_auth_policy(policy)
      refute Services.get_auth_policy(policy.id)
    end
  end
end
