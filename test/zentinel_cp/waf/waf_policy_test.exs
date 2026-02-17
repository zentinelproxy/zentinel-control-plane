defmodule ZentinelCp.Waf.WafPolicyTest do
  use ZentinelCp.DataCase

  alias ZentinelCp.Waf.WafPolicy

  describe "create_changeset/2" do
    test "valid attrs" do
      project = ZentinelCp.ProjectsFixtures.project_fixture()

      changeset =
        WafPolicy.create_changeset(%WafPolicy{}, %{
          name: "Test Policy",
          mode: "block",
          sensitivity: "medium",
          enabled_categories: ["sqli", "xss"],
          project_id: project.id
        })

      assert changeset.valid?
    end

    test "generates slug from name" do
      project = ZentinelCp.ProjectsFixtures.project_fixture()

      changeset =
        WafPolicy.create_changeset(%WafPolicy{}, %{
          name: "My WAF Policy",
          mode: "block",
          sensitivity: "medium",
          project_id: project.id
        })

      assert Ecto.Changeset.get_change(changeset, :slug) == "my-waf-policy"
    end

    test "requires name and project_id" do
      changeset = WafPolicy.create_changeset(%WafPolicy{}, %{})
      refute changeset.valid?
      errors = errors_on(changeset)
      assert Map.has_key?(errors, :name)
      assert Map.has_key?(errors, :project_id)
    end

    test "validates mode inclusion" do
      project = ZentinelCp.ProjectsFixtures.project_fixture()

      changeset =
        WafPolicy.create_changeset(%WafPolicy{}, %{
          name: "Bad Mode",
          mode: "invalid",
          sensitivity: "medium",
          project_id: project.id
        })

      refute changeset.valid?
      assert %{mode: _} = errors_on(changeset)
    end

    test "validates sensitivity inclusion" do
      project = ZentinelCp.ProjectsFixtures.project_fixture()

      changeset =
        WafPolicy.create_changeset(%WafPolicy{}, %{
          name: "Bad Sens",
          mode: "block",
          sensitivity: "ultra",
          project_id: project.id
        })

      refute changeset.valid?
      assert %{sensitivity: _} = errors_on(changeset)
    end

    test "validates enabled_categories values" do
      project = ZentinelCp.ProjectsFixtures.project_fixture()

      changeset =
        WafPolicy.create_changeset(%WafPolicy{}, %{
          name: "Bad Cats",
          mode: "block",
          sensitivity: "medium",
          enabled_categories: ["sqli", "invalid_cat"],
          project_id: project.id
        })

      refute changeset.valid?
      assert %{enabled_categories: _} = errors_on(changeset)
    end

    test "validates max_body_size is positive" do
      project = ZentinelCp.ProjectsFixtures.project_fixture()

      changeset =
        WafPolicy.create_changeset(%WafPolicy{}, %{
          name: "Bad Size",
          mode: "block",
          sensitivity: "medium",
          max_body_size: -1,
          project_id: project.id
        })

      refute changeset.valid?
      assert %{max_body_size: _} = errors_on(changeset)
    end
  end

  describe "update_changeset/2" do
    test "updates fields without requiring project_id" do
      changeset =
        WafPolicy.update_changeset(%WafPolicy{name: "Old", mode: "block", sensitivity: "low"}, %{
          mode: "detect_only",
          sensitivity: "high"
        })

      assert changeset.valid?
    end

    test "does not regenerate slug on update" do
      changeset =
        WafPolicy.update_changeset(
          %WafPolicy{name: "Old", slug: "old", mode: "block", sensitivity: "medium"},
          %{name: "New Name"}
        )

      # slug should not change on update (no generate_slug call)
      refute Ecto.Changeset.get_change(changeset, :slug)
    end
  end
end
