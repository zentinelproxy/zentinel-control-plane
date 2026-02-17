defmodule ZentinelCp.Webhooks.GitHubClient do
  @moduledoc """
  Behaviour for fetching file content from GitHub repositories.
  """

  @callback fetch_file(repo :: String.t(), ref :: String.t(), path :: String.t()) ::
              String.t() | nil

  @doc """
  Returns the configured GitHub client module.
  """
  def impl do
    Application.get_env(:zentinel_cp, :github_client, ZentinelCp.Webhooks.GitHubClient.HTTP)
  end
end
