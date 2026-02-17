defmodule ZentinelCpWeb.Api.CertificateController do
  @moduledoc """
  API controller for TLS certificate management.
  """
  use ZentinelCpWeb, :controller

  alias ZentinelCp.{Services, Projects, Audit}

  def index(conn, %{"project_slug" => project_slug}) do
    with {:ok, project} <- get_project(project_slug) do
      certs = Services.list_certificates(project.id)

      conn
      |> put_status(:ok)
      |> json(%{
        certificates: Enum.map(certs, &cert_to_json/1),
        total: length(certs)
      })
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})
    end
  end

  def show(conn, %{"project_slug" => project_slug, "id" => id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, cert} <- get_cert(id, project.id) do
      conn
      |> put_status(:ok)
      |> json(%{certificate: cert_to_json(cert)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Certificate not found"})
    end
  end

  def create(conn, %{"project_slug" => project_slug} = params) do
    with {:ok, project} <- get_project(project_slug),
         attrs <- Map.put(params, "project_id", project.id),
         {:ok, cert} <- Services.create_certificate(attrs) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "certificate.created", "certificate", cert.id,
        project_id: project.id,
        changes: %{name: cert.name, domain: cert.domain}
      )

      conn
      |> put_status(:created)
      |> json(%{certificate: cert_to_json(cert)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: format_errors(changeset)})
    end
  end

  def update(conn, %{"project_slug" => project_slug, "id" => id} = params) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, cert} <- get_cert(id, project.id),
         {:ok, updated} <- Services.update_certificate(cert, params) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "certificate.updated", "certificate", cert.id,
        project_id: project.id,
        changes: %{name: updated.name}
      )

      conn
      |> put_status(:ok)
      |> json(%{certificate: cert_to_json(updated)})
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Certificate not found"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: format_errors(changeset)})
    end
  end

  def delete(conn, %{"project_slug" => project_slug, "id" => id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, cert} <- get_cert(id, project.id),
         {:ok, _deleted} <- Services.delete_certificate(cert) do
      api_key = conn.assigns.current_api_key

      Audit.log_api_key_action(api_key, "certificate.deleted", "certificate", cert.id,
        project_id: project.id,
        changes: %{name: cert.name, domain: cert.domain}
      )

      send_resp(conn, :no_content, "")
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Certificate not found"})
    end
  end

  def download(conn, %{"project_slug" => project_slug, "id" => id}) do
    with {:ok, project} <- get_project(project_slug),
         {:ok, cert} <- get_cert(id, project.id) do
      conn
      |> put_resp_content_type("application/x-pem-file")
      |> put_resp_header("content-disposition", "attachment; filename=\"#{cert.slug}.pem\"")
      |> send_resp(:ok, cert.cert_pem)
    else
      {:error, :project_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Certificate not found"})
    end
  end

  # Helpers

  defp get_project(slug) do
    case Projects.get_project_by_slug(slug) do
      nil -> {:error, :project_not_found}
      project -> {:ok, project}
    end
  end

  defp get_cert(id, project_id) do
    case Services.get_certificate(id) do
      nil -> {:error, :not_found}
      %{project_id: ^project_id} = cert -> {:ok, cert}
      _ -> {:error, :not_found}
    end
  end

  defp cert_to_json(cert) do
    %{
      id: cert.id,
      name: cert.name,
      slug: cert.slug,
      domain: cert.domain,
      san_domains: cert.san_domains,
      ca_chain_pem: cert.ca_chain_pem,
      issuer: cert.issuer,
      not_before: cert.not_before,
      not_after: cert.not_after,
      fingerprint_sha256: cert.fingerprint_sha256,
      auto_renew: cert.auto_renew,
      acme_config: cert.acme_config,
      status: cert.status,
      project_id: cert.project_id,
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
