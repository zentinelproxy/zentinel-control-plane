defmodule ZentinelCp.Webhooks do
  @moduledoc """
  Webhook verification and processing for GitHub push events.
  """

  require Logger

  alias ZentinelCp.{Bundles, Projects, Audit}

  @doc """
  Verifies a GitHub webhook signature using HMAC-SHA256.

  Returns `true` if the signature is valid, `false` otherwise.
  """
  def verify_signature(payload, signature) when is_binary(payload) and is_binary(signature) do
    secret = webhook_secret()

    if is_nil(secret) or secret == "" do
      false
    else
      expected = "sha256=" <> hmac_sha256(secret, payload)
      Plug.Crypto.secure_compare(expected, signature)
    end
  end

  def verify_signature(_payload, _signature), do: false

  @doc """
  Processes a GitHub push event payload.

  Looks up the project by repo name, checks branch match, and creates a bundle
  with source tracking if the push contains relevant file changes.

  Returns:
    - `{:ok, bundle}` if a bundle was created
    - `{:ok, :ignored}` if the push was irrelevant (wrong branch, no project, etc.)
    - `{:error, reason}` on failure
  """
  def process_github_push(payload) do
    repo = get_in(payload, ["repository", "full_name"])
    branch = extract_branch(payload["ref"])
    head_sha = get_in(payload, ["head_commit", "id"])

    Logger.info("Processing GitHub push",
      repo: repo,
      branch: branch,
      commit: head_sha
    )

    with {:ok, project} <- find_project(repo),
         true <- branch_matches?(project, branch),
         config_source <- extract_config_source(payload, project) do
      if config_source do
        create_git_bundle(project, config_source, %{
          ref: head_sha,
          branch: branch,
          repo: repo
        })
      else
        {:ok, :ignored}
      end
    else
      {:error, :project_not_found} ->
        Logger.debug("No project found for repo", repo: repo)
        {:ok, :ignored}

      false ->
        Logger.debug("Branch mismatch, ignoring push", repo: repo, branch: branch)
        {:ok, :ignored}
    end
  end

  defp find_project(nil), do: {:error, :project_not_found}

  defp find_project(repo) do
    case Projects.get_project_by_github_repo(repo) do
      nil -> {:error, :project_not_found}
      project -> {:ok, project}
    end
  end

  defp branch_matches?(project, branch) do
    expected = project.github_branch || "main"
    branch == expected
  end

  defp extract_branch("refs/heads/" <> branch), do: branch
  defp extract_branch(_), do: nil

  defp extract_config_source(payload, project) do
    config_path = project.config_path || "zentinel.kdl"
    changed_files = extract_changed_files(payload)

    if config_path_changed?(changed_files, config_path) do
      repo = get_in(payload, ["repository", "full_name"])
      ref = get_in(payload, ["head_commit", "id"])
      ZentinelCp.Webhooks.GitHubClient.impl().fetch_file(repo, ref, config_path)
    else
      nil
    end
  end

  defp extract_changed_files(payload) do
    commits = payload["commits"] || []

    Enum.flat_map(commits, fn commit ->
      (commit["added"] || []) ++ (commit["modified"] || []) ++ (commit["removed"] || [])
    end)
    |> Enum.uniq()
  end

  defp config_path_changed?(changed_files, config_path) do
    Enum.any?(changed_files, fn file ->
      file == config_path or String.starts_with?(file, Path.dirname(config_path) <> "/")
    end)
  end

  defp create_git_bundle(project, config_source, source) do
    version = "git-#{String.slice(source.ref, 0, 8)}"

    attrs = %{
      project_id: project.id,
      version: version,
      config_source: config_source,
      source_type: "git",
      source_ref: source.ref,
      source_branch: source.branch,
      source_repo: source.repo
    }

    case Bundles.create_bundle(attrs) do
      {:ok, bundle} ->
        Audit.log_system_action("webhook.bundle_created", "bundle", bundle.id,
          project_id: project.id,
          changes: %{
            version: version,
            source_ref: source.ref,
            source_branch: source.branch,
            source_repo: source.repo
          }
        )

        {:ok, bundle}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp hmac_sha256(secret, payload) do
    :crypto.mac(:hmac, :sha256, secret, payload)
    |> Base.encode16(case: :lower)
  end

  defp webhook_secret do
    Application.get_env(:zentinel_cp, :github_webhook)[:secret]
  end
end
