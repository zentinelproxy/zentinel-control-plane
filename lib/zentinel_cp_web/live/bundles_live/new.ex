defmodule ZentinelCpWeb.BundlesLive.New do
  use ZentinelCpWeb, :live_view

  alias ZentinelCp.{Bundles, Orgs, Projects}

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        latest_version = suggest_next_version(project.id)

        socket =
          socket
          |> assign(
            page_title: "New Bundle — #{project.name}",
            org: org,
            project: project,
            suggested_version: latest_version,
            input_mode: "paste",
            validation_result: nil,
            form_version: latest_version,
            form_config: "",
            char_count: 0,
            line_count: 1,
            drag_over: false
          )
          |> allow_upload(:config_file,
            accept: ~w(.kdl),
            max_entries: 1,
            max_file_size: 512_000
          )

        {:ok, socket}
    end
  end

  @impl true
  def handle_event("switch_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, input_mode: mode)}
  end

  @impl true
  def handle_event("validate", %{"version" => version, "config_source" => config}, socket) do
    char_count = String.length(config)
    line_count = max(1, length(String.split(config, "\n")))

    {:noreply,
     assign(socket,
       form_version: version,
       form_config: config,
       validation_result: nil,
       char_count: char_count,
       line_count: line_count
     )}
  end

  @impl true
  def handle_event("use_template", _, socket) do
    template = sample_config_template()
    char_count = String.length(template)
    line_count = length(String.split(template, "\n"))

    {:noreply,
     assign(socket,
       form_config: template,
       input_mode: "paste",
       char_count: char_count,
       line_count: line_count,
       validation_result: nil
     )}
  end

  @impl true
  def handle_event("drag_enter", _, socket) do
    {:noreply, assign(socket, drag_over: true)}
  end

  @impl true
  def handle_event("drag_leave", _, socket) do
    {:noreply, assign(socket, drag_over: false)}
  end

  @impl true
  def handle_event("drop", %{"content" => content}, socket) do
    char_count = String.length(content)
    line_count = max(1, length(String.split(content, "\n")))

    {:noreply,
     assign(socket,
       form_config: content,
       input_mode: "paste",
       char_count: char_count,
       line_count: line_count,
       drag_over: false,
       validation_result: nil
     )}
  end

  @impl true
  def handle_event("validate_config", _, socket) do
    config = get_config_source(socket)

    result =
      if String.trim(config) == "" do
        {:error, "Configuration is empty"}
      else
        {:ok, "Configuration looks valid (#{String.length(config)} characters)"}
      end

    {:noreply, assign(socket, validation_result: result)}
  end

  @impl true
  def handle_event(
        "create_bundle",
        %{"version" => version, "config_source" => pasted_config},
        socket
      ) do
    project = socket.assigns.project
    config = get_final_config(socket, pasted_config)

    if String.trim(config) == "" do
      {:noreply, put_flash(socket, :error, "Configuration source is required.")}
    else
      case Bundles.create_bundle(%{
             project_id: project.id,
             version: version,
             config_source: config
           }) do
        {:ok, bundle} ->
          show_path = bundle_show_path(socket.assigns.org, project, bundle)

          {:noreply,
           socket
           |> put_flash(:info, "Bundle created, compilation started.")
           |> push_navigate(to: show_path)}

        {:error, %Ecto.Changeset{} = changeset} ->
          errors =
            Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
            |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)

          {:noreply, put_flash(socket, :error, "Failed: #{errors}")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4 max-w-3xl">
      <h1 class="text-xl font-bold">Create Bundle</h1>

      <.k8s_section>
        <form phx-submit="create_bundle" phx-change="validate" class="space-y-6">
          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Version</span></label>
            <input
              type="text"
              name="version"
              value={@form_version}
              required
              class="input input-bordered input-sm w-full max-w-xs"
              placeholder="e.g. 1.0.0"
            />
            <label class="label">
              <span class="label-text-alt text-base-content/50">Suggested: {@suggested_version}</span>
            </label>
          </div>

          <div class="flex gap-1">
            <button
              type="button"
              phx-click="switch_mode"
              phx-value-mode="paste"
              class={["btn btn-sm", (@input_mode == "paste" && "btn-primary") || "btn-ghost"]}
            >
              Paste Config
            </button>
            <button
              type="button"
              phx-click="switch_mode"
              phx-value-mode="upload"
              class={["btn btn-sm", (@input_mode == "upload" && "btn-primary") || "btn-ghost"]}
            >
              Upload File
            </button>
            <div class="flex-1"></div>
            <button
              type="button"
              phx-click="use_template"
              class="btn btn-ghost btn-sm"
            >
              Use Template
            </button>
          </div>

          <div :if={@input_mode == "paste"} class="form-control">
            <div class="flex items-center justify-between">
              <label class="label">
                <span class="label-text font-medium">KDL Configuration</span>
              </label>
              <span class="text-xs text-base-content/50">
                {@line_count} lines, {@char_count} chars
              </span>
            </div>
            <div
              class={[
                "relative",
                @drag_over && "ring-2 ring-primary ring-offset-2 rounded"
              ]}
              phx-hook="DropZone"
              id="config-drop-zone"
            >
              <textarea
                name="config_source"
                rows="20"
                class="textarea textarea-bordered textarea-sm font-mono text-sm w-full leading-relaxed"
                placeholder="// Paste your zentinel.kdl config here, or drag and drop a .kdl file"
                phx-debounce="300"
              >{@form_config}</textarea>
            </div>
            <label class="label">
              <span class="label-text-alt text-base-content/50">
                Supports .kdl syntax. Drag and drop files or paste directly.
              </span>
            </label>
          </div>

          <div :if={@input_mode == "upload"} class="form-control">
            <label class="label"><span class="label-text font-medium">Upload .kdl File</span></label>
            <.live_file_input
              upload={@uploads.config_file}
              class="file-input file-input-bordered file-input-sm w-full max-w-xs"
            />
            <input type="hidden" name="config_source" value="" />
            <%= for entry <- @uploads.config_file.entries do %>
              <div class="flex items-center gap-2 mt-2 text-sm">
                <span class="font-mono">{entry.client_name}</span>
                <span class="text-base-content/50">({format_bytes(entry.client_size)})</span>
              </div>
            <% end %>
          </div>

          <div :if={@validation_result} class="alert">
            <div :if={match?({:ok, _}, @validation_result)} class="text-success text-sm">
              {elem(@validation_result, 1)}
            </div>
            <div :if={match?({:error, _}, @validation_result)} class="text-error text-sm">
              {elem(@validation_result, 1)}
            </div>
          </div>

          <div class="flex gap-2">
            <button type="button" class="btn btn-outline btn-sm" phx-click="validate_config">
              Validate
            </button>
            <button type="submit" class="btn btn-primary btn-sm">
              Create & Compile
            </button>
            <.link navigate={project_bundles_path(@org, @project)} class="btn btn-ghost btn-sm">
              Cancel
            </.link>
          </div>
        </form>
      </.k8s_section>
    </div>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp project_bundles_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/bundles"

  defp project_bundles_path(nil, project),
    do: ~p"/projects/#{project.slug}/bundles"

  defp bundle_show_path(%{slug: org_slug}, project, bundle),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/bundles/#{bundle.id}"

  defp bundle_show_path(nil, project, bundle),
    do: ~p"/projects/#{project.slug}/bundles/#{bundle.id}"

  defp get_config_source(socket) do
    case socket.assigns.input_mode do
      "upload" ->
        case consume_uploaded_entries(socket, :config_file, fn %{path: path}, _entry ->
               {:ok, File.read!(path)}
             end) do
          [content | _] -> content
          [] -> ""
        end

      _ ->
        socket.assigns.form_config
    end
  end

  defp get_final_config(socket, pasted_config) do
    case socket.assigns.input_mode do
      "upload" ->
        consume_uploaded_entries(socket, :config_file, fn %{path: path}, _entry ->
          {:ok, File.read!(path)}
        end)
        |> List.first("")

      _ ->
        pasted_config
    end
  end

  defp suggest_next_version(project_id) do
    case Bundles.list_bundles(project_id, limit: 1) do
      [latest | _] ->
        case Version.parse(latest.version) do
          {:ok, v} -> "#{v.major}.#{v.minor}.#{v.patch + 1}"
          :error -> "0.0.1"
        end

      [] ->
        "0.0.1"
    end
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp sample_config_template do
    """
    // Zentinel Configuration
    // See https://zentinel.io/docs/config for full reference

    // Global settings
    settings {
        log_level "info"
        metrics_port 9090
    }

    // Route definitions
    routes {
        // API routes
        route "/api/v1/*" {
            upstream "http://api-backend:8080"
            timeout 30s
            retry {
                attempts 3
                backoff "exponential"
            }
        }

        // Static assets
        route "/static/*" {
            upstream "http://cdn:80"
            cache {
                ttl 3600
                vary "Accept-Encoding"
            }
        }

        // Health check endpoint
        route "/health" {
            respond 200 "OK"
        }
    }

    // Rate limiting
    rate_limits {
        limit "api" {
            requests 100
            window 60s
            by "client_ip"
        }
    }
    """
  end
end
