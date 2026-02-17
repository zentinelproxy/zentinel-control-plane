defmodule ZentinelCp.Bundles do
  @moduledoc """
  The Bundles context handles bundle lifecycle management.

  Bundles are immutable, content-addressed configuration artifacts that are
  compiled from KDL config, stored in S3/MinIO, and distributed to nodes.
  """

  import Ecto.Query, warn: false
  alias ZentinelCp.Bundles.{Bundle, Diff}
  alias ZentinelCp.Repo

  @doc """
  Creates a bundle and enqueues compilation.

  Automatically links the new bundle to the latest compiled bundle
  for the same project as its parent.
  """
  def create_bundle(attrs) do
    attrs = maybe_link_parent(attrs)
    changeset = Bundle.create_changeset(%Bundle{}, attrs)

    case Repo.insert(changeset) do
      {:ok, bundle} ->
        enqueue_compilation(bundle)
        {:ok, bundle}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp maybe_link_parent(attrs) do
    project_id = attrs[:project_id] || attrs["project_id"]

    if project_id do
      case get_latest_bundle(project_id) do
        %Bundle{id: parent_id} -> Map.put(attrs, :parent_bundle_id, parent_id)
        nil -> attrs
      end
    else
      attrs
    end
  end

  @doc """
  Lists bundles for a project, ordered by most recent first.
  """
  def list_bundles(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    query =
      from(b in Bundle,
        where: b.project_id == ^project_id,
        order_by: [desc: b.inserted_at],
        limit: ^limit,
        offset: ^offset
      )

    query =
      Enum.reduce(opts, query, fn
        {:status, status}, q -> where(q, [b], b.status == ^status)
        _, q -> q
      end)

    Repo.all(query)
  end

  @doc """
  Gets a bundle by ID.
  """
  def get_bundle(id), do: Repo.get(Bundle, id)

  @doc """
  Gets a bundle by ID, raises if not found.
  """
  def get_bundle!(id), do: Repo.get!(Bundle, id)

  @doc """
  Gets the latest compiled bundle for a project.
  """
  def get_latest_bundle(project_id) do
    from(b in Bundle,
      where: b.project_id == ^project_id and b.status == "compiled",
      order_by: [desc: b.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Updates a bundle's compilation results.
  """
  def update_compilation(bundle, attrs) do
    bundle
    |> Bundle.compilation_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Marks a bundle as a specific status.
  """
  def update_status(bundle, status) do
    bundle
    |> Bundle.status_changeset(status)
    |> Repo.update()
  end

  @doc """
  Updates a bundle's SBOM data.
  """
  def update_bundle_sbom(bundle, sbom) do
    bundle
    |> Bundle.compilation_changeset(%{sbom: sbom, sbom_format: "cyclonedx+json"})
    |> Repo.update()
  end

  @doc """
  Updates a bundle's risk level and reasons.
  """
  def update_risk(bundle, risk_level, risk_reasons) do
    bundle
    |> Bundle.compilation_changeset(%{risk_level: risk_level, risk_reasons: risk_reasons})
    |> Repo.update()
  end

  @doc """
  Assigns a bundle to one or more nodes as their staged bundle.
  """
  def assign_bundle_to_nodes(bundle, node_ids) when is_list(node_ids) do
    {count, _} =
      from(n in ZentinelCp.Nodes.Node,
        where: n.id in ^node_ids and n.project_id == ^bundle.project_id
      )
      |> Repo.update_all(set: [staged_bundle_id: bundle.id])

    {:ok, count}
  end

  @doc """
  Counts bundles by status for a project.
  """
  def count_bundles(project_id) do
    from(b in Bundle,
      where: b.project_id == ^project_id,
      group_by: b.status,
      select: {b.status, count(b.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Revokes a compiled bundle, preventing further distribution.

  Clears `staged_bundle_id` on any nodes that have this bundle staged.
  Only compiled bundles can be revoked.
  """
  def revoke_bundle(%Bundle{status: "compiled"} = bundle) do
    Repo.transaction(fn ->
      {:ok, revoked} = update_status(bundle, "revoked")

      # Clear staged_bundle_id on nodes that have this bundle staged
      from(n in ZentinelCp.Nodes.Node,
        where: n.staged_bundle_id == ^bundle.id
      )
      |> Repo.update_all(set: [staged_bundle_id: nil])

      revoked
    end)
  end

  def revoke_bundle(%Bundle{}), do: {:error, :invalid_state}

  @doc """
  Deletes a bundle (only if pending or failed).
  """
  def delete_bundle(%Bundle{status: status} = bundle) when status in ["pending", "failed"] do
    Repo.delete(bundle)
  end

  def delete_bundle(%Bundle{}) do
    {:error, :cannot_delete_active_bundle}
  end

  @doc """
  Gets a bundle by ID with its parent bundle preloaded.
  """
  def get_bundle_with_parent(id) do
    Bundle
    |> Repo.get(id)
    |> Repo.preload(:parent_bundle)
  end

  @doc """
  Returns the chronologically previous compiled bundle for the same project.
  """
  def get_previous_bundle(bundle, project_id) do
    from(b in Bundle,
      where: b.project_id == ^project_id,
      where: b.status == "compiled",
      where: b.id != ^bundle.id,
      where:
        b.inserted_at < ^bundle.inserted_at or
          (b.inserted_at == ^bundle.inserted_at and b.id < ^bundle.id),
      order_by: [desc: b.inserted_at, desc: b.id],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Returns bundle version history for a project with diff summaries.

  Lists compiled and failed bundles ordered by insertion time (newest first).
  For each consecutive pair, precomputes diff stats and semantic summaries.

  Returns `{bundles, diff_summaries}` where `diff_summaries` is a map of
  `bundle_id => %{stats: ..., semantic: ...}`.
  """
  def list_bundle_history(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    bundles =
      from(b in Bundle,
        where: b.project_id == ^project_id,
        where: b.status in ["compiled", "failed", "superseded", "revoked"],
        order_by: [desc: b.inserted_at, desc: b.id],
        limit: ^limit
      )
      |> Repo.all()

    diff_summaries = compute_diff_summaries(bundles)

    {bundles, diff_summaries}
  end

  defp compute_diff_summaries(bundles) do
    bundles
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(%{}, fn [newer, older], acc ->
      config_diff = Diff.config_diff(older, newer)
      stats = Diff.diff_stats(config_diff)
      semantic = Diff.semantic_diff(older, newer)

      Map.put(acc, newer.id, %{stats: stats, semantic: semantic})
    end)
  end

  # Enqueue compilation via Oban
  defp enqueue_compilation(bundle) do
    %{bundle_id: bundle.id}
    |> ZentinelCp.Bundles.CompileWorker.new()
    |> Oban.insert()
  end

  ## Config Validation Rules

  alias ZentinelCp.Bundles.{BundlePromotion, ConfigValidationRule, ConfigValidator}
  alias ZentinelCp.Projects.Environment

  @doc """
  Lists all config validation rules for a project.
  """
  def list_validation_rules(project_id) do
    from(r in ConfigValidationRule,
      where: r.project_id == ^project_id,
      order_by: [asc: r.name]
    )
    |> Repo.all()
  end

  @doc """
  Gets a validation rule by ID.
  """
  def get_validation_rule(id), do: Repo.get(ConfigValidationRule, id)

  @doc """
  Gets a validation rule by ID, raises if not found.
  """
  def get_validation_rule!(id), do: Repo.get!(ConfigValidationRule, id)

  @doc """
  Creates a config validation rule.
  """
  def create_validation_rule(attrs) do
    %ConfigValidationRule{}
    |> ConfigValidationRule.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a config validation rule.
  """
  def update_validation_rule(%ConfigValidationRule{} = rule, attrs) do
    rule
    |> ConfigValidationRule.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a config validation rule.
  """
  def delete_validation_rule(%ConfigValidationRule{} = rule) do
    Repo.delete(rule)
  end

  @doc """
  Validates a bundle's config against project validation rules.

  Returns `{:ok, warnings}` if validation passes.
  Returns `{:error, errors, warnings}` if validation fails.
  """
  def validate_bundle_config(%Bundle{} = bundle) do
    rules = list_validation_rules(bundle.project_id)
    config_source = bundle.config_source || ""

    ConfigValidator.validate(config_source, rules)
  end

  @doc """
  Validates config source against project validation rules.
  """
  def validate_config(project_id, config_source) when is_binary(config_source) do
    rules = list_validation_rules(project_id)
    ConfigValidator.validate(config_source, rules)
  end

  ## Bundle Promotions

  @doc """
  Lists all promotions for a bundle.
  """
  def list_bundle_promotions(bundle_id) do
    from(p in BundlePromotion,
      where: p.bundle_id == ^bundle_id,
      preload: [:environment],
      order_by: [asc: p.promoted_at]
    )
    |> Repo.all()
  end

  @doc """
  Checks if a bundle has been promoted to an environment.
  """
  def bundle_promoted_to?(bundle_id, environment_id) do
    from(p in BundlePromotion,
      where: p.bundle_id == ^bundle_id and p.environment_id == ^environment_id
    )
    |> Repo.exists?()
  end

  @doc """
  Promotes a bundle to an environment.

  Returns `{:ok, promotion}` or `{:error, reason}`.
  """
  def promote_bundle(bundle_id, environment_id, opts \\ []) do
    promoted_by_id = Keyword.get(opts, :promoted_by_id)

    attrs = %{
      bundle_id: bundle_id,
      environment_id: environment_id,
      promoted_by_id: promoted_by_id
    }

    %BundlePromotion{}
    |> BundlePromotion.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Promotes a bundle to the next environment in the pipeline.

  Validates that the bundle is already promoted to the current environment.
  Returns `{:ok, promotion}` or `{:error, reason}`.
  """
  def promote_bundle_to_next(%Bundle{} = bundle, %Environment{} = current_env, opts \\ []) do
    alias ZentinelCp.Projects

    with {:ok, _} <- validate_promotion_from(bundle, current_env),
         next_env when not is_nil(next_env) <- Projects.get_next_environment(current_env) do
      promote_bundle(bundle.id, next_env.id, opts)
    else
      nil -> {:error, :no_next_environment}
      error -> error
    end
  end

  defp validate_promotion_from(bundle, environment) do
    if bundle_promoted_to?(bundle.id, environment.id) do
      {:ok, :valid}
    else
      {:error, :not_promoted_to_current_environment}
    end
  end

  @doc """
  Lists bundles promoted to a specific environment.
  """
  def list_bundles_for_environment(environment_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(b in Bundle,
      join: p in BundlePromotion,
      on: p.bundle_id == b.id,
      where: p.environment_id == ^environment_id,
      where: b.status == "compiled",
      order_by: [desc: p.promoted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Gets the latest bundle promoted to an environment.
  """
  def get_latest_promoted_bundle(environment_id) do
    from(b in Bundle,
      join: p in BundlePromotion,
      on: p.bundle_id == b.id,
      where: p.environment_id == ^environment_id,
      where: b.status == "compiled",
      order_by: [desc: p.promoted_at],
      limit: 1
    )
    |> Repo.one()
  end
end
