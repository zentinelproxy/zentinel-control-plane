defmodule ZentinelCp.AuditTest do
  use ZentinelCp.DataCase

  alias ZentinelCp.Audit
  alias ZentinelCp.Audit.AuditLog

  import ZentinelCp.AccountsFixtures
  import ZentinelCp.ProjectsFixtures
  import ZentinelCp.NodesFixtures

  describe "log/1" do
    test "creates an audit log entry" do
      assert {:ok, %AuditLog{} = log} =
               Audit.log(%{
                 actor_type: "system",
                 action: "test.action",
                 resource_type: "test",
                 resource_id: Ecto.UUID.generate()
               })

      assert log.actor_type == "system"
      assert log.action == "test.action"
    end

    test "validates required fields" do
      assert {:error, changeset} = Audit.log(%{})
      errors = errors_on(changeset)
      assert errors[:actor_type]
      assert errors[:action]
      assert errors[:resource_type]
    end

    test "validates actor_type inclusion" do
      assert {:error, changeset} =
               Audit.log(%{
                 actor_type: "invalid",
                 action: "test",
                 resource_type: "test"
               })

      assert %{actor_type: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "log_user_action/5" do
    test "logs action with user as actor" do
      user = user_fixture()
      project = project_fixture()
      resource_id = Ecto.UUID.generate()

      assert {:ok, log} =
               Audit.log_user_action(user, "node.deleted", "node", resource_id,
                 project_id: project.id,
                 changes: %{"status" => "deleted"},
                 metadata: %{"ip" => "127.0.0.1"}
               )

      assert log.actor_type == "user"
      assert log.actor_id == user.id
      assert log.action == "node.deleted"
      assert log.project_id == project.id
      assert log.changes == %{"status" => "deleted"}
      assert log.metadata == %{"ip" => "127.0.0.1"}
    end
  end

  describe "log_node_action/5" do
    test "logs action with node as actor" do
      node = node_fixture()

      assert {:ok, log} = Audit.log_node_action(node, "node.heartbeat", "node", node.id)
      assert log.actor_type == "node"
      assert log.actor_id == node.id
      assert log.project_id == node.project_id
    end
  end

  describe "log_system_action/4" do
    test "logs action with system as actor" do
      assert {:ok, log} = Audit.log_system_action("cleanup.completed", "heartbeat", nil)
      assert log.actor_type == "system"
      assert is_nil(log.actor_id)
    end
  end

  describe "list_audit_logs/2" do
    test "returns logs for a project" do
      project = project_fixture()
      user = user_fixture()

      {:ok, _} =
        Audit.log_user_action(user, "project.updated", "project", project.id,
          project_id: project.id
        )

      {logs, total} = Audit.list_audit_logs(project.id)
      assert length(logs) == 1
      assert total == 1
    end

    test "filters by action" do
      project = project_fixture()
      user = user_fixture()

      {:ok, _} =
        Audit.log_user_action(user, "node.created", "node", Ecto.UUID.generate(),
          project_id: project.id
        )

      {:ok, _} =
        Audit.log_user_action(user, "node.deleted", "node", Ecto.UUID.generate(),
          project_id: project.id
        )

      {logs, total} = Audit.list_audit_logs(project.id, action: "node.created")
      assert length(logs) == 1
      assert total == 1
      assert hd(logs).action == "node.created"
    end

    test "filters by resource_type" do
      project = project_fixture()
      user = user_fixture()

      {:ok, _} =
        Audit.log_user_action(user, "node.created", "node", Ecto.UUID.generate(),
          project_id: project.id
        )

      {:ok, _} =
        Audit.log_user_action(user, "bundle.created", "bundle", Ecto.UUID.generate(),
          project_id: project.id
        )

      {logs, total} = Audit.list_audit_logs(project.id, resource_type: "bundle")
      assert length(logs) == 1
      assert total == 1
      assert hd(logs).resource_type == "bundle"
    end

    test "filters by actor_type" do
      project = project_fixture()

      {:ok, _} = Audit.log_system_action("cleanup", "heartbeat", nil, project_id: project.id)

      {logs, total} = Audit.list_audit_logs(project.id, actor_type: "system")
      assert length(logs) == 1
      assert total == 1
    end
  end

  describe "list_audit_logs_for_resource/3" do
    test "returns logs for a specific resource" do
      user = user_fixture()
      resource_id = Ecto.UUID.generate()

      {:ok, _} = Audit.log_user_action(user, "node.created", "node", resource_id)
      {:ok, _} = Audit.log_user_action(user, "node.updated", "node", resource_id)
      {:ok, _} = Audit.log_user_action(user, "node.updated", "node", Ecto.UUID.generate())

      logs = Audit.list_audit_logs_for_resource("node", resource_id)
      assert length(logs) == 2
    end
  end
end
