defmodule ZentinelCpWeb.OpenApiLive.Import do
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Audit, Orgs, Projects, Services}
  alias ZentinelCp.Services.OpenApiParser

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        socket =
          socket
          |> assign(
            page_title: "Import OpenAPI — #{project.name}",
            org: org,
            project: project,
            step: :upload,
            specs: Services.list_openapi_specs(project.id),
            parsed: nil,
            extracted_services: [],
            extracted_auth_policies: [],
            selected_indices: MapSet.new(),
            import_auth: true,
            upstream_override: "",
            spec_info: nil,
            diff: nil,
            import_result: nil,
            error_message: nil
          )
          |> allow_upload(:spec_file,
            accept: ~w(.yaml .yml .json),
            max_entries: 1,
            max_file_size: 2_048_000
          )

        {:ok, socket}
    end
  end

  @impl true
  def handle_event("parse_spec", _params, socket) do
    project = socket.assigns.project

    case consume_uploaded_entries(socket, :spec_file, fn %{path: path}, entry ->
           content = File.read!(path)
           {:ok, {content, entry.client_name}}
         end) do
      [{content, file_name}] ->
        handle_parse(socket, content, file_name, project)

      [] ->
        {:noreply, assign(socket, error_message: "Please select a file to upload.")}
    end
  end

  @impl true
  def handle_event("toggle_service", %{"index" => idx_str}, socket) do
    idx = String.to_integer(idx_str)
    selected = socket.assigns.selected_indices

    selected =
      if MapSet.member?(selected, idx),
        do: MapSet.delete(selected, idx),
        else: MapSet.put(selected, idx)

    {:noreply, assign(socket, selected_indices: selected)}
  end

  @impl true
  def handle_event("select_all", _params, socket) do
    all = 0..(length(socket.assigns.extracted_services) - 1) |> MapSet.new()
    {:noreply, assign(socket, selected_indices: all)}
  end

  @impl true
  def handle_event("deselect_all", _params, socket) do
    {:noreply, assign(socket, selected_indices: MapSet.new())}
  end

  @impl true
  def handle_event("toggle_auth_policies", _params, socket) do
    {:noreply, assign(socket, import_auth: !socket.assigns.import_auth)}
  end

  @impl true
  def handle_event("update_upstream", %{"upstream_url" => url}, socket) do
    parsed = socket.assigns.parsed
    opts = if url != "", do: [upstream_url: url], else: []
    services = OpenApiParser.extract_services(parsed, opts)

    {:noreply, assign(socket, upstream_override: url, extracted_services: services)}
  end

  @impl true
  def handle_event("confirm_import", _params, socket) do
    project = socket.assigns.project
    user = socket.assigns.current_user

    selected =
      socket.assigns.extracted_services
      |> Enum.with_index()
      |> Enum.filter(fn {_svc, idx} -> MapSet.member?(socket.assigns.selected_indices, idx) end)
      |> Enum.map(fn {svc, _idx} -> svc end)

    if selected == [] do
      {:noreply, assign(socket, error_message: "Please select at least one service to import.")}
    else
      # Create spec record
      parsed = socket.assigns.parsed
      spec_info = socket.assigns.spec_info
      content = Jason.encode!(parsed)
      checksum = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

      spec_attrs = %{
        name: spec_info.title,
        file_name: spec_info.file_name,
        openapi_version: parsed.openapi_version,
        spec_version: spec_info.version,
        spec_data: socket.assigns.parsed,
        checksum: checksum,
        paths_count: map_size(parsed.paths),
        project_id: project.id
      }

      with {:ok, spec} <- Services.create_openapi_spec(spec_attrs),
           {:ok, result} <-
             Services.import_from_openapi(project.id, spec.id, selected,
               import_auth_policies: socket.assigns.import_auth,
               auth_policy_attrs: socket.assigns.extracted_auth_policies
             ) do
        Audit.log_user_action(user, "import", "openapi_spec", spec.id,
          project_id: project.id,
          metadata: %{
            services_count: result.services_count,
            auth_policies_count: result.auth_policies_count
          }
        )

        {:noreply,
         assign(socket,
           step: :done,
           import_result: result,
           error_message: nil
         )}
      else
        {:error, {:auth_policy_error, changeset}} ->
          {:noreply,
           assign(socket, error_message: "Auth policy error: #{format_errors(changeset)}")}

        {:error, {:service_error, changeset}} ->
          {:noreply, assign(socket, error_message: "Service error: #{format_errors(changeset)}")}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, error_message: "Error: #{format_errors(changeset)}")}
      end
    end
  end

  @impl true
  def handle_event("back_to_upload", _params, socket) do
    {:noreply,
     assign(socket,
       step: :upload,
       parsed: nil,
       extracted_services: [],
       extracted_auth_policies: [],
       selected_indices: MapSet.new(),
       spec_info: nil,
       diff: nil,
       error_message: nil,
       import_result: nil,
       upstream_override: ""
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.table_toolbar>
        <:filters>
          <h1 class="text-xl font-bold">Import from OpenAPI</h1>
        </:filters>
        <:actions>
          <.link navigate={services_path(@org, @project)} class="btn btn-ghost btn-sm">
            Back to Services
          </.link>
        </:actions>
      </.table_toolbar>

      <div :if={@error_message} class="alert alert-error">
        {@error_message}
      </div>

      {render_step(assigns)}
    </div>
    """
  end

  defp render_step(%{step: :upload} = assigns) do
    ~H"""
    <.k8s_section title="Upload OpenAPI Specification">
      <form id="upload-form" phx-submit="parse_spec" class="space-y-4">
        <div class="form-control">
          <label class="label">
            <span class="label-text font-medium">Spec File (.json, .yaml, .yml)</span>
          </label>
          <.live_file_input
            upload={@uploads.spec_file}
            class="file-input file-input-bordered file-input-sm w-full max-w-md"
          />
          <%= for entry <- @uploads.spec_file.entries do %>
            <div class="flex items-center gap-2 mt-2 text-sm">
              <span class="font-mono">{entry.client_name}</span>
              <span class="text-base-content/50">({format_bytes(entry.client_size)})</span>
            </div>
            <%= for err <- upload_errors(@uploads.spec_file, entry) do %>
              <p class="text-error text-sm mt-1">{upload_error_to_string(err)}</p>
            <% end %>
          <% end %>
        </div>

        <button type="submit" class="btn btn-primary btn-sm">
          Parse & Preview
        </button>
      </form>
    </.k8s_section>

    <div :if={@specs != []}>
      <.k8s_section title="Previously Imported Specs">
        <table class="table table-sm">
          <thead class="bg-base-300">
            <tr>
              <th class="text-xs uppercase">Name</th>
              <th class="text-xs uppercase">File</th>
              <th class="text-xs uppercase">Version</th>
              <th class="text-xs uppercase">Paths</th>
              <th class="text-xs uppercase">Status</th>
              <th class="text-xs uppercase">Imported</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={spec <- @specs}>
              <td class="font-medium">{spec.name}</td>
              <td class="font-mono text-sm">{spec.file_name}</td>
              <td class="text-sm">{spec.spec_version}</td>
              <td class="text-sm">{spec.paths_count}</td>
              <td>
                <span class={[
                  "badge badge-sm",
                  spec.status == "active" && "badge-success",
                  spec.status == "superseded" && "badge-warning"
                ]}>
                  {spec.status}
                </span>
              </td>
              <td class="text-sm">
                {Calendar.strftime(spec.inserted_at, "%Y-%m-%d %H:%M")}
              </td>
            </tr>
          </tbody>
        </table>
      </.k8s_section>
    </div>
    """
  end

  defp render_step(%{step: :preview} = assigns) do
    ~H"""
    <.k8s_section title="Spec Info">
      <div class="flex flex-wrap gap-4 text-sm">
        <div>
          <span class="font-medium">Title:</span> {@spec_info.title}
        </div>
        <div>
          <span class="font-medium">Version:</span> {@spec_info.version}
        </div>
        <div>
          <span class="font-medium">OpenAPI:</span> {@parsed.openapi_version}
        </div>
        <div :if={@spec_info.server_url}>
          <span class="font-medium">Server:</span>
          <span class="font-mono">{@spec_info.server_url}</span>
        </div>
        <div>
          <span class="font-medium">Paths:</span> {map_size(@parsed.paths)}
        </div>
      </div>
    </.k8s_section>

    <div :if={@diff}>
      <.k8s_section title="Re-import Changes">
        <div class="flex gap-4 text-sm">
          <span class="text-success">+ {length(@diff.added)} added</span>
          <span class="text-error">- {length(@diff.removed)} removed</span>
          <span class="text-base-content/60">= {length(@diff.unchanged)} unchanged</span>
        </div>
      </.k8s_section>
    </div>

    <.k8s_section title="Upstream URL Override">
      <form phx-change="update_upstream" class="flex items-end gap-3">
        <div class="form-control flex-1">
          <input
            type="text"
            name="upstream_url"
            value={@upstream_override}
            placeholder="Leave blank to use spec server URL"
            class="input input-bordered input-sm w-full max-w-md"
          />
        </div>
      </form>
    </.k8s_section>

    <.k8s_section title="Services to Import">
      <div class="flex items-center gap-2 mb-3">
        <button phx-click="select_all" class="btn btn-ghost btn-xs">Select All</button>
        <button phx-click="deselect_all" class="btn btn-ghost btn-xs">Deselect All</button>
        <span class="text-sm text-base-content/60">
          {MapSet.size(@selected_indices)} of {length(@extracted_services)} selected
        </span>
      </div>

      <div class="overflow-x-auto">
        <table class="table table-sm">
          <thead class="bg-base-300">
            <tr>
              <th class="w-8"></th>
              <th class="text-xs uppercase">Path</th>
              <th class="text-xs uppercase">Name</th>
              <th class="text-xs uppercase">Methods</th>
              <th class="text-xs uppercase">Description</th>
              <th class="text-xs uppercase">Security</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={{svc, idx} <- Enum.with_index(@extracted_services)}>
              <td>
                <input
                  type="checkbox"
                  class="checkbox checkbox-sm"
                  checked={MapSet.member?(@selected_indices, idx)}
                  phx-click="toggle_service"
                  phx-value-index={idx}
                />
              </td>
              <td class="font-mono text-sm">{svc.openapi_path}</td>
              <td class="text-sm">{svc.name}</td>
              <td class="text-sm">
                <div class="flex gap-1 flex-wrap">
                  <span :for={m <- svc.methods} class="badge badge-xs badge-outline">{m}</span>
                </div>
              </td>
              <td class="text-sm max-w-xs truncate">{svc[:description]}</td>
              <td class="text-sm">
                <span :for={ref <- svc.security_refs} class="badge badge-xs badge-info mr-1">
                  {ref}
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </.k8s_section>

    <div :if={@extracted_auth_policies != []}>
      <.k8s_section title="Auth Policies">
        <div class="flex items-center gap-3 mb-3">
          <label class="label cursor-pointer gap-2">
            <span class="label-text">Import auth policies from spec</span>
            <input
              type="checkbox"
              class="toggle toggle-sm toggle-primary"
              checked={@import_auth}
              phx-click="toggle_auth_policies"
            />
          </label>
        </div>
        <div :if={@import_auth} class="overflow-x-auto">
          <table class="table table-sm">
            <thead class="bg-base-300">
              <tr>
                <th class="text-xs uppercase">Name</th>
                <th class="text-xs uppercase">Type</th>
                <th class="text-xs uppercase">Description</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={policy <- @extracted_auth_policies}>
                <td class="font-medium">{policy.name}</td>
                <td>
                  <span class="badge badge-sm badge-outline">{policy.auth_type}</span>
                </td>
                <td class="text-sm">{policy[:description]}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </.k8s_section>
    </div>

    <div class="flex gap-2">
      <button
        phx-click="confirm_import"
        class="btn btn-primary btn-sm"
        disabled={MapSet.size(@selected_indices) == 0}
      >
        Import Selected ({MapSet.size(@selected_indices)})
      </button>
      <button phx-click="back_to_upload" class="btn btn-ghost btn-sm">Back</button>
    </div>
    """
  end

  defp render_step(%{step: :done} = assigns) do
    ~H"""
    <.k8s_section title="Import Complete">
      <div class="space-y-2">
        <p class="text-success font-medium">
          Successfully imported {@import_result.services_count} service(s).
        </p>
        <p :if={@import_result.auth_policies_count > 0} class="text-sm">
          Created {@import_result.auth_policies_count} auth policy/policies.
        </p>
      </div>
      <div class="mt-4 flex gap-2">
        <.link navigate={services_path(@org, @project)} class="btn btn-primary btn-sm">
          View Services
        </.link>
        <button phx-click="back_to_upload" class="btn btn-ghost btn-sm">Import Another</button>
      </div>
    </.k8s_section>
    """
  end

  # --- Private helpers ---

  defp handle_parse(socket, content, file_name, project) do
    with {:ok, raw} <- OpenApiParser.decode_spec_file(content, file_name),
         {:ok, parsed} <- OpenApiParser.parse(raw) do
      opts =
        if socket.assigns.upstream_override != "",
          do: [upstream_url: socket.assigns.upstream_override],
          else: []

      services = OpenApiParser.extract_services(parsed, opts)
      auth_policies = OpenApiParser.extract_auth_policies(parsed)

      spec_info = %{
        title: get_in(parsed.info, ["title"]) || file_name,
        version: get_in(parsed.info, ["version"]) || "unknown",
        file_name: file_name,
        server_url: get_server_url(parsed.servers)
      }

      # Check for re-import
      raw_content = Jason.encode!(parsed)
      checksum = :crypto.hash(:sha256, raw_content) |> Base.encode16(case: :lower)
      existing = Services.get_openapi_spec_by_checksum(project.id, checksum)

      diff =
        if existing do
          {:ok, old_parsed} = OpenApiParser.parse(existing.spec_data)
          OpenApiParser.diff_specs(old_parsed, parsed)
        end

      all_selected = 0..(length(services) - 1) |> MapSet.new()

      {:noreply,
       assign(socket,
         step: :preview,
         parsed: parsed,
         extracted_services: services,
         extracted_auth_policies: auth_policies,
         selected_indices: all_selected,
         spec_info: spec_info,
         diff: diff,
         error_message: nil
       )}
    else
      {:error, msg} ->
        {:noreply, assign(socket, error_message: msg)}
    end
  end

  defp get_server_url([%{"url" => url} | _]), do: url
  defp get_server_url(_), do: nil

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp services_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/services"

  defp services_path(nil, project),
    do: ~p"/projects/#{project.slug}/services"

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp upload_error_to_string(:too_large), do: "File is too large (max 2 MB)"

  defp upload_error_to_string(:not_accepted),
    do: "Invalid file type. Accepted: .json, .yaml, .yml"

  defp upload_error_to_string(:too_many_files), do: "Only one file at a time"
  defp upload_error_to_string(err), do: "Upload error: #{inspect(err)}"

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
    |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
  end
end
