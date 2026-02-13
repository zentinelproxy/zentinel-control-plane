defmodule SentinelCp.Services.Acme.Client.HTTP do
  @moduledoc """
  HTTP implementation of the ACME client behaviour using Req and JOSE.

  Every ACME POST is a JWS (JSON Web Signature) with ES256, including
  a nonce and URL in the protected header. Account registration uses
  `jwk` in the header; subsequent requests use `kid`.
  """

  @behaviour SentinelCp.Services.Acme.Client

  alias SentinelCp.Services.Acme.Crypto

  @impl true
  def get_directory(url) do
    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def new_nonce(url) do
    case Req.head(url) do
      {:ok, %{headers: headers}} ->
        case get_header(headers, "replay-nonce") do
          nil -> {:error, :no_nonce}
          nonce -> {:ok, nonce}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def new_account(url, account_key, nonce, payload) do
    protected = %{
      "alg" => "ES256",
      "jwk" => Crypto.ec_key_to_jwk(account_key),
      "nonce" => nonce,
      "url" => url
    }

    case post_jws(url, protected, payload, account_key) do
      {:ok, %{status: status, headers: headers}} when status in [200, 201] ->
        kid = get_header(headers, "location")
        new_nonce = get_header(headers, "replay-nonce")
        {:ok, %{kid: kid, nonce: new_nonce}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:acme_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def new_order(url, kid, account_key, nonce, domains) do
    payload = %{
      "identifiers" => Enum.map(domains, &%{"type" => "dns", "value" => &1})
    }

    case post_jws_kid(url, kid, account_key, nonce, payload) do
      {:ok, %{status: 201, body: body, headers: headers}} ->
        {:ok,
         %{
           order_url: get_header(headers, "location"),
           authorizations: body["authorizations"],
           finalize_url: body["finalize"],
           nonce: get_header(headers, "replay-nonce")
         }}

      {:ok, %{status: status, body: body}} ->
        {:error, {:acme_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def get_authorization(url, kid, account_key, nonce) do
    case post_as_get(url, kid, account_key, nonce) do
      {:ok, %{status: 200, body: body, headers: headers}} ->
        {:ok,
         %{
           status: body["status"],
           challenges: body["challenges"],
           nonce: get_header(headers, "replay-nonce")
         }}

      {:ok, %{status: status, body: body}} ->
        {:error, {:acme_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def respond_challenge(url, kid, account_key, nonce) do
    case post_jws_kid(url, kid, account_key, nonce, %{}) do
      {:ok, %{status: 200, headers: headers}} ->
        {:ok, %{nonce: get_header(headers, "replay-nonce")}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:acme_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def poll_authorization(url, kid, account_key, nonce, opts \\ []) do
    max_attempts = Keyword.get(opts, :max_attempts, 10)
    delay_ms = Keyword.get(opts, :delay_ms, 2_000)

    do_poll_authorization(url, kid, account_key, nonce, max_attempts, delay_ms)
  end

  defp do_poll_authorization(_url, _kid, _key, _nonce, 0, _delay),
    do: {:error, :timeout}

  defp do_poll_authorization(url, kid, account_key, nonce, remaining, delay_ms) do
    case post_as_get(url, kid, account_key, nonce) do
      {:ok, %{status: 200, body: body, headers: headers}} ->
        new_nonce = get_header(headers, "replay-nonce")

        case body["status"] do
          "valid" ->
            {:ok, %{status: "valid", nonce: new_nonce}}

          "invalid" ->
            {:error, {:authorization_failed, body}}

          _pending ->
            Process.sleep(delay_ms)
            do_poll_authorization(url, kid, account_key, new_nonce, remaining - 1, delay_ms)
        end

      {:ok, %{status: status, body: body}} ->
        {:error, {:acme_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def finalize_order(url, kid, account_key, nonce, csr_der) do
    payload = %{
      "csr" => Base.url_encode64(csr_der, padding: false)
    }

    case post_jws_kid(url, kid, account_key, nonce, payload) do
      {:ok, %{status: 200, headers: headers}} ->
        {:ok, %{nonce: get_header(headers, "replay-nonce")}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:acme_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def poll_order(url, kid, account_key, nonce, opts \\ []) do
    max_attempts = Keyword.get(opts, :max_attempts, 10)
    delay_ms = Keyword.get(opts, :delay_ms, 2_000)

    do_poll_order(url, kid, account_key, nonce, max_attempts, delay_ms)
  end

  defp do_poll_order(_url, _kid, _key, _nonce, 0, _delay),
    do: {:error, :timeout}

  defp do_poll_order(url, kid, account_key, nonce, remaining, delay_ms) do
    case post_as_get(url, kid, account_key, nonce) do
      {:ok, %{status: 200, body: body, headers: headers}} ->
        new_nonce = get_header(headers, "replay-nonce")

        case body["status"] do
          "valid" ->
            {:ok,
             %{
               status: "valid",
               certificate_url: body["certificate"],
               nonce: new_nonce
             }}

          "invalid" ->
            {:error, {:order_failed, body}}

          _processing ->
            Process.sleep(delay_ms)
            do_poll_order(url, kid, account_key, new_nonce, remaining - 1, delay_ms)
        end

      {:ok, %{status: status, body: body}} ->
        {:error, {:acme_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def download_certificate(url, kid, account_key, nonce) do
    protected = build_kid_protected(kid, account_key, nonce, url)
    jws_body = sign_jws(protected, "", account_key)

    case Req.post(url,
           json: jws_body,
           headers: [{"content-type", "application/jose+json"}, {"accept", "application/pem-certificate-chain"}]
         ) do
      {:ok, %{status: 200, body: body, headers: headers}} ->
        cert_pem = if is_binary(body), do: body, else: Jason.encode!(body)
        {:ok, %{cert_pem: cert_pem, nonce: get_header(headers, "replay-nonce")}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:acme_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # POST-as-GET: payload is empty string per RFC 8555
  defp post_as_get(url, kid, account_key, nonce) do
    protected = build_kid_protected(kid, account_key, nonce, url)
    jws_body = sign_jws(protected, "", account_key)

    Req.post(url,
      json: jws_body,
      headers: [{"content-type", "application/jose+json"}]
    )
  end

  defp post_jws_kid(url, kid, account_key, nonce, payload) do
    protected = build_kid_protected(kid, account_key, nonce, url)
    jws_body = sign_jws(protected, payload, account_key)

    Req.post(url,
      json: jws_body,
      headers: [{"content-type", "application/jose+json"}]
    )
  end

  defp post_jws(url, protected, payload, account_key) do
    jws_body = sign_jws(protected, payload, account_key)

    Req.post(url,
      json: jws_body,
      headers: [{"content-type", "application/jose+json"}]
    )
  end

  defp build_kid_protected(kid, _account_key, nonce, url) do
    %{
      "alg" => "ES256",
      "kid" => kid,
      "nonce" => nonce,
      "url" => url
    }
  end

  defp sign_jws(protected, payload, account_key) do
    protected_b64 = protected |> Jason.encode!() |> Base.url_encode64(padding: false)

    payload_b64 =
      case payload do
        "" -> ""
        p -> p |> Jason.encode!() |> Base.url_encode64(padding: false)
      end

    signing_input = "#{protected_b64}.#{payload_b64}"

    # Sign with ES256 (ECDSA with P-256 and SHA-256)
    der_sig = :public_key.sign(signing_input, :sha256, account_key)
    # Convert DER signature to raw R||S format for JWS
    raw_sig = der_signature_to_raw(der_sig)
    sig_b64 = Base.url_encode64(raw_sig, padding: false)

    %{
      "protected" => protected_b64,
      "payload" => payload_b64,
      "signature" => sig_b64
    }
  end

  # Convert DER-encoded ECDSA signature to raw R||S (32 bytes each for P-256)
  defp der_signature_to_raw(der_sig) do
    # DER SEQUENCE { INTEGER r, INTEGER s }
    <<0x30, _seq_len::8, rest::binary>> = der_sig
    {r_bytes, rest} = parse_der_integer(rest)
    {s_bytes, _rest} = parse_der_integer(rest)
    pad_binary(r_bytes, 32) <> pad_binary(s_bytes, 32)
  end

  defp parse_der_integer(<<0x02, len::8, bytes::binary-size(len), rest::binary>>) do
    # Strip leading zero byte if present (sign byte for positive integers)
    stripped = if :binary.first(bytes) == 0 and len > 1, do: binary_part(bytes, 1, len - 1), else: bytes
    {stripped, rest}
  end

  defp pad_binary(bin, size) when byte_size(bin) > size do
    # Strip leading zero bytes
    binary_part(bin, byte_size(bin) - size, size)
  end

  defp pad_binary(bin, size) when byte_size(bin) < size do
    :binary.copy(<<0>>, size - byte_size(bin)) <> bin
  end

  defp pad_binary(bin, _size), do: bin

  defp get_header(headers, key) do
    case headers do
      %{} ->
        case Map.get(headers, key) do
          [val | _] -> val
          val when is_binary(val) -> val
          nil -> nil
        end

      list when is_list(list) ->
        Enum.find_value(list, fn
          {^key, val} -> val
          _ -> nil
        end)
    end
  end
end
