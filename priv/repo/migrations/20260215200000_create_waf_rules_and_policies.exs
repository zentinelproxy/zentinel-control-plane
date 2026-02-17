defmodule ZentinelCp.Repo.Migrations.CreateWafRulesAndPolicies do
  use Ecto.Migration

  def change do
    create table(:waf_rules, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :rule_id, :string, null: false
      add :name, :string, null: false
      add :description, :text
      add :category, :string, null: false
      add :severity, :string, null: false, default: "medium"
      add :default_action, :string, null: false, default: "block"
      add :targets, {:array, :string}, default: []
      add :tags, {:array, :string}, default: []
      add :is_builtin, :boolean, default: true
      add :phase, :string, default: "request"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:waf_rules, [:rule_id])
    create index(:waf_rules, [:category])
    create index(:waf_rules, [:severity])

    create table(:waf_policies, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :enabled, :boolean, default: true
      add :mode, :string, null: false, default: "block"
      add :sensitivity, :string, null: false, default: "medium"
      add :enabled_categories, {:array, :string}, default: []
      add :default_action, :string, null: false, default: "block"
      add :max_body_size, :integer
      add :max_header_size, :integer
      add :max_uri_length, :integer
      add :allowed_content_types, {:array, :string}, default: []

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:waf_policies, [:project_id, :slug])
    create index(:waf_policies, [:project_id])

    create table(:waf_policy_rule_overrides, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :action, :string, null: false
      add :note, :text

      add :waf_policy_id, references(:waf_policies, type: :binary_id, on_delete: :delete_all),
        null: false

      add :waf_rule_id, references(:waf_rules, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:waf_policy_rule_overrides, [:waf_policy_id, :waf_rule_id])
    create index(:waf_policy_rule_overrides, [:waf_policy_id])

    alter table(:services) do
      add :waf_policy_id, references(:waf_policies, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:services, [:waf_policy_id])
  end
end
