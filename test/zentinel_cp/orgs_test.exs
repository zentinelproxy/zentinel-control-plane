defmodule ZentinelCp.OrgsTest do
  use ZentinelCp.DataCase

  alias ZentinelCp.Orgs
  alias ZentinelCp.Orgs.{Org, OrgMembership}

  import ZentinelCp.OrgsFixtures
  import ZentinelCp.AccountsFixtures

  describe "create_org/1" do
    test "creates org with valid attributes" do
      assert {:ok, %Org{} = org} = Orgs.create_org(%{name: "My Org"})
      assert org.name == "My Org"
      assert org.slug == "my-org"
    end

    test "auto-generates slug from name" do
      assert {:ok, org} = Orgs.create_org(%{name: "Hello World Corp"})
      assert org.slug == "hello-world-corp"
    end

    test "returns error for blank name" do
      assert {:error, changeset} = Orgs.create_org(%{name: ""})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "returns error for duplicate slug" do
      assert {:ok, _} = Orgs.create_org(%{name: "Duplicate"})
      assert {:error, changeset} = Orgs.create_org(%{name: "Duplicate"})
      assert %{slug: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "create_org_with_owner/2" do
    test "creates org and adds user as admin" do
      user = user_fixture()
      assert {:ok, org} = Orgs.create_org_with_owner(%{name: "Owned Org"}, user)
      assert org.name == "Owned Org"
      assert Orgs.get_user_role(org.id, user.id) == "admin"
    end
  end

  describe "get_org_by_slug/1" do
    test "returns org by slug" do
      org = org_fixture()
      found = Orgs.get_org_by_slug(org.slug)
      assert found.id == org.id
    end

    test "returns nil for unknown slug" do
      refute Orgs.get_org_by_slug("nonexistent")
    end
  end

  describe "list_user_orgs/1" do
    test "returns orgs the user belongs to" do
      user = user_fixture()
      org1 = org_fixture(%{name: "Alpha Org"})
      org2 = org_fixture(%{name: "Bravo Org"})
      _org3 = org_fixture(%{name: "Charlie Org"})

      Orgs.add_member(org1, user, "admin")
      Orgs.add_member(org2, user, "reader")

      orgs = Orgs.list_user_orgs(user.id)
      assert length(orgs) == 2
      slugs = Enum.map(orgs, fn {org, _role} -> org.slug end)
      assert "alpha-org" in slugs
      assert "bravo-org" in slugs
    end

    test "returns role with each org" do
      user = user_fixture()
      org = org_fixture()
      Orgs.add_member(org, user, "operator")

      [{_org, role}] = Orgs.list_user_orgs(user.id)
      assert role == "operator"
    end
  end

  describe "membership management" do
    setup do
      user = user_fixture()
      org = org_fixture()
      %{user: user, org: org}
    end

    test "add_member/3 creates membership", %{user: user, org: org} do
      assert {:ok, %OrgMembership{} = m} = Orgs.add_member(org, user, "operator")
      assert m.org_id == org.id
      assert m.user_id == user.id
      assert m.role == "operator"
    end

    test "add_member/3 defaults to reader role", %{user: user, org: org} do
      assert {:ok, m} = Orgs.add_member(org, user)
      assert m.role == "reader"
    end

    test "add_member/3 rejects duplicate", %{user: user, org: org} do
      assert {:ok, _} = Orgs.add_member(org, user)
      assert {:error, _} = Orgs.add_member(org, user)
    end

    test "update_member_role/2 changes role", %{user: user, org: org} do
      {:ok, membership} = Orgs.add_member(org, user, "reader")
      assert {:ok, updated} = Orgs.update_member_role(membership, "admin")
      assert updated.role == "admin"
    end

    test "remove_member/2 removes membership", %{user: user, org: org} do
      Orgs.add_member(org, user)
      assert {1, _} = Orgs.remove_member(org, user)
      refute Orgs.get_membership(org.id, user.id)
    end

    test "list_members/1 returns all members with users", %{user: user, org: org} do
      user2 = user_fixture()
      Orgs.add_member(org, user, "admin")
      Orgs.add_member(org, user2, "reader")

      members = Orgs.list_members(org)
      assert length(members) == 2
      assert Enum.all?(members, &Ecto.assoc_loaded?(&1.user))
    end
  end

  describe "role checks" do
    setup do
      user = user_fixture()
      org = org_fixture()
      Orgs.add_member(org, user, "operator")
      %{user: user, org: org}
    end

    test "get_user_role/2 returns role", %{user: user, org: org} do
      assert Orgs.get_user_role(org.id, user.id) == "operator"
    end

    test "get_user_role/2 returns nil for non-member", %{org: org} do
      other = user_fixture()
      refute Orgs.get_user_role(org.id, other.id)
    end

    test "user_has_role?/3 checks hierarchy", %{user: user, org: org} do
      assert Orgs.user_has_role?(org.id, user.id, "reader")
      assert Orgs.user_has_role?(org.id, user.id, "operator")
      refute Orgs.user_has_role?(org.id, user.id, "admin")
    end
  end

  describe "get_or_create_default_org/0" do
    test "creates default org on first call" do
      assert {:ok, org} = Orgs.get_or_create_default_org()
      assert org.slug == "default"
      assert org.name == "Default"
    end

    test "returns existing default org on subsequent calls" do
      {:ok, org1} = Orgs.get_or_create_default_org()
      {:ok, org2} = Orgs.get_or_create_default_org()
      assert org1.id == org2.id
    end
  end

  describe "update_org/2" do
    test "updates org name" do
      org = org_fixture()
      assert {:ok, updated} = Orgs.update_org(org, %{name: "Updated Name"})
      assert updated.name == "Updated Name"
    end
  end

  describe "delete_org/1" do
    test "deletes an org" do
      org = org_fixture()
      assert {:ok, _} = Orgs.delete_org(org)
      refute Orgs.get_org(org.id)
    end
  end
end
