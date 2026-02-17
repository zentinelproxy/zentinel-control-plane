defmodule ZentinelCp.Webhooks.GitHubClient.HTTP do
  @moduledoc """
  HTTP implementation of GitHubClient that fetches files from the GitHub API.
  """

  @behaviour ZentinelCp.Webhooks.GitHubClient

  require Logger

  @impl true
  def fetch_file(repo, ref, path) do
    url = "https://raw.githubusercontent.com/#{repo}/#{ref}/#{path}"

    headers =
      case github_token() do
        nil -> []
        token -> [{"authorization", "token #{token}"}]
      end

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        body

      {:ok, %{status: status}} ->
        Logger.warning("Failed to fetch config from GitHub",
          repo: repo,
          ref: ref,
          path: path,
          status: status
        )

        nil

      {:error, reason} ->
        Logger.warning("GitHub fetch error",
          repo: repo,
          ref: ref,
          path: path,
          error: inspect(reason)
        )

        nil
    end
  end

  defp github_token do
    Application.get_env(:zentinel_cp, :github_webhook)[:access_token]
  end
end
