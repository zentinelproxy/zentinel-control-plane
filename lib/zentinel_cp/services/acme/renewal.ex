defmodule ZentinelCp.Services.Acme.Renewal do
  @moduledoc """
  Orchestrates the full ACME certificate renewal cycle.

  1. Load/register ACME account (decrypt key or generate + register new one)
  2. Create order for domain(s)
  3. Process HTTP-01 authorizations (store token in ETS, respond to ACME, poll)
  4. Generate new cert key pair, build CSR, finalize order
  5. Download certificate chain
  6. Update certificate record with new PEM data
  7. Clean up challenge tokens
  """

  require Logger

  alias ZentinelCp.Services
  alias ZentinelCp.Services.Acme.{Crypto, ChallengeStore}
  alias ZentinelCp.Services.{Certificate, CertificateCrypto}

  @doc """
  Renews a certificate via ACME. Returns `{:ok, updated_cert}` or `{:error, reason}`.
  """
  def renew(%Certificate{} = cert) do
    acme_config = cert.acme_config || %{}
    directory_url = acme_config["directory_url"] || default_directory_url()
    email = acme_config["email"]
    domains = [cert.domain | cert.san_domains || []] |> Enum.uniq()

    with {:ok, directory} <- acme_client().get_directory(directory_url),
         {:ok, {account_key, kid, nonce}} <- ensure_account(cert, directory, email),
         {:ok, order} <-
           acme_client().new_order(directory["newOrder"], kid, account_key, nonce, domains),
         {:ok, nonce} <-
           process_authorizations(order.authorizations, kid, account_key, order.nonce),
         {:ok, {cert_pem, key_pem, _nonce}} <-
           finalize_and_download(order, kid, account_key, nonce, domains),
         {:ok, updated} <-
           Services.renew_certificate(cert, %{cert_pem: cert_pem, key_pem: key_pem}),
         {:ok, _} <-
           Services.update_certificate_acme(updated, %{
             last_renewal_at: DateTime.utc_now() |> DateTime.truncate(:second),
             last_renewal_error: nil,
             acme_account_key_encrypted: encrypt_account_key(account_key)
           }) do
      Logger.info("ACME renewal succeeded for #{cert.domain} (cert #{cert.id})")
      # Re-fetch to include all updated fields
      {:ok, Services.get_certificate!(cert.id)}
    else
      {:error, reason} = err ->
        error_msg = inspect(reason)
        Logger.error("ACME renewal failed for #{cert.domain}: #{error_msg}")

        Services.update_certificate_acme(cert, %{
          last_renewal_at: DateTime.utc_now() |> DateTime.truncate(:second),
          last_renewal_error: String.slice(error_msg, 0, 500)
        })

        err
    end
  end

  # Load existing account key or generate and register a new one
  defp ensure_account(cert, directory, email) do
    case load_account_key(cert) do
      {:ok, account_key} ->
        # Re-register (existing account returns 200)
        with {:ok, nonce} <- acme_client().new_nonce(directory["newNonce"]),
             payload = build_account_payload(email),
             {:ok, %{kid: kid, nonce: nonce}} <-
               acme_client().new_account(directory["newAccount"], account_key, nonce, payload) do
          {:ok, {account_key, kid, nonce}}
        end

      :error ->
        # Generate new account key and register
        account_key = Crypto.generate_account_key()

        with {:ok, nonce} <- acme_client().new_nonce(directory["newNonce"]),
             payload = build_account_payload(email),
             {:ok, %{kid: kid, nonce: nonce}} <-
               acme_client().new_account(directory["newAccount"], account_key, nonce, payload) do
          {:ok, {account_key, kid, nonce}}
        end
    end
  end

  defp load_account_key(%Certificate{acme_account_key_encrypted: nil}), do: :error

  defp load_account_key(%Certificate{acme_account_key_encrypted: encrypted}) do
    with {:ok, pem} <- CertificateCrypto.decrypt(encrypted),
         {:ok, key} <- Crypto.pem_to_private_key(pem) do
      {:ok, key}
    else
      _ -> :error
    end
  end

  defp encrypt_account_key(account_key) do
    account_key
    |> Crypto.private_key_to_pem()
    |> CertificateCrypto.encrypt()
  end

  defp build_account_payload(nil), do: %{"termsOfServiceAgreed" => true}

  defp build_account_payload(email) do
    %{"termsOfServiceAgreed" => true, "contact" => ["mailto:#{email}"]}
  end

  # Process all HTTP-01 authorizations
  defp process_authorizations(auth_urls, kid, account_key, nonce) do
    Enum.reduce_while(auth_urls, {:ok, nonce}, fn auth_url, {:ok, current_nonce} ->
      case process_single_authorization(auth_url, kid, account_key, current_nonce) do
        {:ok, new_nonce} -> {:cont, {:ok, new_nonce}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp process_single_authorization(auth_url, kid, account_key, nonce) do
    with {:ok, auth} <- acme_client().get_authorization(auth_url, kid, account_key, nonce) do
      if auth.status == "valid" do
        {:ok, auth.nonce}
      else
        case find_http01_challenge(auth.challenges) do
          nil ->
            {:error, :no_http01_challenge}

          challenge ->
            token = challenge["token"]
            key_auth = Crypto.key_authorization(token, account_key)

            # Store token for the HTTP-01 challenge server
            ChallengeStore.put(token, key_auth)

            with {:ok, %{nonce: nonce}} <-
                   acme_client().respond_challenge(challenge["url"], kid, account_key, auth.nonce),
                 {:ok, %{nonce: nonce}} <-
                   acme_client().poll_authorization(auth_url, kid, account_key, nonce, []) do
              ChallengeStore.delete(token)
              {:ok, nonce}
            else
              err ->
                ChallengeStore.delete(token)
                err
            end
        end
      end
    end
  end

  defp find_http01_challenge(challenges) do
    Enum.find(challenges, &(&1["type"] == "http-01"))
  end

  # Generate cert key, build CSR, finalize order, poll, and download
  defp finalize_and_download(order, kid, account_key, nonce, domains) do
    cert_key = Crypto.generate_cert_key()
    key_pem = Crypto.private_key_to_pem(cert_key)

    with {:ok, csr_der} <- Crypto.build_csr(cert_key, domains),
         {:ok, %{nonce: nonce}} <-
           acme_client().finalize_order(order.finalize_url, kid, account_key, nonce, csr_der),
         {:ok, %{certificate_url: cert_url, nonce: nonce}} <-
           acme_client().poll_order(order.order_url, kid, account_key, nonce, []),
         {:ok, %{cert_pem: cert_pem}} <-
           acme_client().download_certificate(cert_url, kid, account_key, nonce) do
      {:ok, {cert_pem, key_pem, nonce}}
    end
  end

  defp acme_client do
    Application.get_env(:zentinel_cp, :acme_client, ZentinelCp.Services.Acme.Client.HTTP)
  end

  defp default_directory_url do
    Application.get_env(:zentinel_cp, :acme, [])
    |> Keyword.get(:directory_url, "https://acme-v02.api.letsencrypt.org/directory")
  end
end
