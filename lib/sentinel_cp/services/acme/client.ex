defmodule SentinelCp.Services.Acme.Client do
  @moduledoc """
  Behaviour for ACME (RFC 8555) client operations.

  Covers the full certificate issuance flow: directory discovery,
  account registration, order creation, authorization, challenge
  response, finalization, and certificate download.
  """

  @type account_key :: tuple()
  @type directory :: map()
  @type nonce :: String.t()
  @type url :: String.t()
  @type kid :: String.t()

  @callback get_directory(url()) :: {:ok, directory()} | {:error, term()}

  @callback new_nonce(url()) :: {:ok, nonce()} | {:error, term()}

  @callback new_account(url(), account_key(), nonce(), map()) ::
              {:ok, %{kid: kid(), nonce: nonce()}} | {:error, term()}

  @callback new_order(url(), kid(), account_key(), nonce(), [String.t()]) ::
              {:ok, %{order_url: url(), authorizations: [url()], finalize_url: url(), nonce: nonce()}}
              | {:error, term()}

  @callback get_authorization(url(), kid(), account_key(), nonce()) ::
              {:ok, %{status: String.t(), challenges: [map()], nonce: nonce()}}
              | {:error, term()}

  @callback respond_challenge(url(), kid(), account_key(), nonce()) ::
              {:ok, %{nonce: nonce()}} | {:error, term()}

  @callback poll_authorization(url(), kid(), account_key(), nonce(), keyword()) ::
              {:ok, %{status: String.t(), nonce: nonce()}} | {:error, term()}

  @callback finalize_order(url(), kid(), account_key(), nonce(), binary()) ::
              {:ok, %{nonce: nonce()}} | {:error, term()}

  @callback poll_order(url(), kid(), account_key(), nonce(), keyword()) ::
              {:ok, %{status: String.t(), certificate_url: url() | nil, nonce: nonce()}}
              | {:error, term()}

  @callback download_certificate(url(), kid(), account_key(), nonce()) ::
              {:ok, %{cert_pem: String.t(), nonce: nonce()}} | {:error, term()}
end
