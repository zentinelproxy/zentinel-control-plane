defmodule ZentinelCpWeb.Api.InternalCaController do
  @moduledoc """
  API controller for internal CA and client certificate management.
  """
  use ZentinelCpWeb, :controller

  alias ZentinelCp.{Services, Projects, Audit}

  # --- Internal CA ---

  def show(conn, %{"project_slug" => project_slug}) do
    with {:ok, project} <- get_project(project_slug) do
      case Services.get_internal_ca(project.id) do
        nil ->
          conn |> put_status(:not_found) |> json(%{error: "No internal CA configured"})

        ca ->
          conn |> put_status(:ok) |> json(%{internal_ca: ca_to_json(ca)})
      end
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})
    end
  end

  def initialize(conn, %{"project_slug" => project_slug} = params) do
    with {:ok, project} <- get_project(project_slug) do
      attrs =
        params
        |> Map.put("project_id", project.id)

      case Services.initialize_internal_ca(attrs) do
        {:ok, ca} ->
          api_key = conn.assigns.current_api_key

          Audit.log_api_key_action(api_key, "internal_ca.initialized", "internal_ca", ca.id,
            project_id: project.id,
            changes: %{name: ca.name, algorithm: ca.key_algorithm, subject_cn: ca.subject_cn}
          )

          conn |> put_status(:created) |> json(%{internal_ca: ca_to_json(ca)})

        {:error, %Ecto.Changeset{} = changeset} ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: format_errors(changeset)})
      end
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})
    end
  end

  def destroy(conn, %{"project_slug" => project_slug}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, ca} <- get_ca(project.id),
         {:ok, _} <- Services.destroy_internal_ca(ca) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "internal_ca.destroyed", "internal_ca", ca.id,
        project_id: project.id,
        changes: %{name: ca.name}
      )

      send_resp(conn, :no_content, "")
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "No internal CA configured"})
    end
  end

  def download_ca(conn, %{"project_slug" => project_slug}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, ca} <- get_ca(project.id) do
      conn
      |> put_resp_content_type("application/x-pem-file")
      |> put_resp_header("content-disposition", "attachment; filename=\"ca.pem\"")
      |> send_resp(:ok, ca.ca_cert_pem)
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "No internal CA configured"})
    end
  end

  def download_crl(conn, %{"project_slug" => project_slug}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, ca} <- get_ca(project.id) do
      conn
      |> put_resp_content_type("application/x-pem-file")
      |> put_resp_header("content-disposition", "attachment; filename=\"crl.pem\"")
      |> send_resp(:ok, ca.crl_pem || "")
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "No internal CA configured"})
    end
  end

  # --- Issued Certificates ---

  def list_certificates(conn, %{"project_slug" => project_slug}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, ca} <- get_ca(project.id) do
      certs = Services.list_issued_certificates(ca.id)

      conn
      |> put_status(:ok)
      |> json(%{certificates: Enum.map(certs, &cert_to_json/1), total: length(certs)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "No internal CA configured"})
    end
  end

  def show_certificate(conn, %{"project_slug" => project_slug, "id" => id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, ca} <- get_ca(project.id),
         {:ok, cert} <- get_issued_cert(id, ca.id) do
      conn |> put_status(:ok) |> json(%{certificate: cert_to_json(cert)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Not found"})
    end
  end

  def issue_certificate(conn, %{"project_slug" => project_slug} = params) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, ca} <- get_ca(project.id) do
      case Services.issue_certificate(ca, params) do
        {:ok, cert} ->
          api_key = conn.assigns.current_api_key

          Audit.log_api_key_action(
            api_key,
            "issued_certificate.created",
            "issued_certificate",
            cert.id,
            project_id: project.id,
            changes: %{name: cert.name, serial: cert.serial_number, subject_cn: cert.subject_cn}
          )

          conn |> put_status(:created) |> json(%{certificate: cert_to_json(cert)})

        {:error, %Ecto.Changeset{} = changeset} ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: format_errors(changeset)})
      end
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "No internal CA configured"})
    end
  end

  def revoke_certificate(conn, %{"project_slug" => project_slug, "id" => id} = params) do
    reason = params["reason"] || "unspecified"

    with {:ok, project} <- get_project(project_slug),
         {:ok, ca} <- get_ca(project.id),
         {:ok, cert} <- get_issued_cert(id, ca.id),
         {:ok, revoked} <- Services.revoke_issued_certificate(cert, reason) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(
        api_key,
        "issued_certificate.revoked",
        "issued_certificate",
        cert.id,
        project_id: project.id,
        changes: %{reason: reason, serial: cert.serial_number}
      )

      conn |> put_status(:ok) |> json(%{certificate: cert_to_json(revoked)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Not found"})
    end
  end

  def download_certificate(conn, %{"project_slug" => project_slug, "id" => id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, ca} <- get_ca(project.id),
         {:ok, cert} <- get_issued_cert(id, ca.id) do
      # Return cert + key as JSON (key is encrypted, decrypt for download)
      {:ok, key_pem} = Services.CertificateCrypto.decrypt(cert.key_pem_encrypted)

      conn
      |> put_status(:ok)
      |> json(%{
        certificate_pem: cert.cert_pem,
        private_key_pem: key_pem,
        ca_cert_pem: ca.ca_cert_pem
      })
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Not found"})
    end
  end

  # --- Helpers ---

  defp get_project(slug) do
    case Projects.get_project_by_slug(slug) do
      nil -> {:error, :project_not_found}
      project -> {:ok, project}
    end
  end

  defp get_ca(project_id) do
    case Services.get_internal_ca(project_id) do
      nil -> {:error, :not_found}
      ca -> {:ok, ca}
    end
  end

  defp get_issued_cert(id, ca_id) do
    case Services.get_issued_certificate(id) do
      nil -> {:error, :not_found}
      %{internal_ca_id: ^ca_id} = cert -> {:ok, cert}
      _ -> {:error, :not_found}
    end
  end

  defp ca_to_json(ca) do
    %{
      id: ca.id,
      name: ca.name,
      slug: ca.slug,
      key_algorithm: ca.key_algorithm,
      subject_cn: ca.subject_cn,
      not_before: ca.not_before,
      not_after: ca.not_after,
      fingerprint_sha256: ca.fingerprint_sha256,
      next_serial: ca.next_serial,
      crl_updated_at: ca.crl_updated_at,
      status: ca.status,
      project_id: ca.project_id,
      inserted_at: ca.inserted_at,
      updated_at: ca.updated_at
    }
  end

  defp cert_to_json(cert) do
    %{
      id: cert.id,
      name: cert.name,
      slug: cert.slug,
      serial_number: cert.serial_number,
      subject_cn: cert.subject_cn,
      subject_ou: cert.subject_ou,
      not_before: cert.not_before,
      not_after: cert.not_after,
      fingerprint_sha256: cert.fingerprint_sha256,
      key_usage: cert.key_usage,
      status: cert.status,
      revoked_at: cert.revoked_at,
      revoke_reason: cert.revoke_reason,
      inserted_at: cert.inserted_at,
      updated_at: cert.updated_at
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
