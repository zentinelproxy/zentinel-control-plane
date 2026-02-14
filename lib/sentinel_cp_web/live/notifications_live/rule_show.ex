defmodule SentinelCpWeb.NotificationsLive.RuleShow do
  use SentinelCpWeb, :live_view

  import SentinelCpWeb.NotificationsLive.Helpers

  alias SentinelCp.{Audit, Events, Projects}

  @impl true
  def mount(%{"project_slug" => slug, "id" => id} = params, _session, socket) do
    org = resolve_org(params)

    with project when not is_nil(project) <- Projects.get_project_by_slug(slug),
         rule when not is_nil(rule) <- Events.get_rule(id),
         rule <- SentinelCp.Repo.preload(rule, :channel),
         true <- rule.project_id == project.id do
      {:ok,
       assign(socket,
         page_title: "Rule #{rule.name} — #{project.name}",
         org: org,
         project: project,
         rule: rule
       )}
    else
      _ ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}
    end
  end

  @impl true
  def handle_event("delete", _, socket) do
    rule = socket.assigns.rule
    project = socket.assigns.project
    org = socket.assigns.org

    case Events.delete_rule(rule) do
      {:ok, _} ->
        Audit.log_user_action(
          socket.assigns.current_user,
          "delete",
          "notification_rule",
          rule.id,
          project_id: project.id
        )

        {:noreply,
         socket
         |> put_flash(:info, "Rule deleted.")
         |> push_navigate(to: rules_path(org, project))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete rule.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.detail_header
        name={@rule.name}
        resource_type="notification rule"
        back_path={rules_path(@org, @project)}
      >
        <:badge>
          <span class={["badge badge-sm", (@rule.enabled && "badge-success") || "badge-ghost"]}>
            {if @rule.enabled, do: "enabled", else: "disabled"}
          </span>
        </:badge>
        <:action>
          <.link navigate={rule_edit_path(@org, @project, @rule)} class="btn btn-outline btn-sm">
            Edit
          </.link>
          <button
            phx-click="delete"
            data-confirm="Are you sure you want to delete this rule?"
            class="btn btn-error btn-sm"
          >
            Delete
          </button>
        </:action>
      </.detail_header>

      <.k8s_section title="Details">
        <.definition_list>
          <:item label="ID"><span class="font-mono text-sm">{@rule.id}</span></:item>
          <:item label="Name">{@rule.name}</:item>
          <:item label="Event Pattern">
            <span class="font-mono text-sm">{@rule.event_pattern}</span>
          </:item>
          <:item label="Channel">
            <.link navigate={channel_show_path(@org, @project, @rule.channel)} class="link">
              {@rule.channel.name}
            </.link>
            <span class="badge badge-xs badge-outline ml-1">{@rule.channel.type}</span>
          </:item>
          <:item label="Enabled">{if @rule.enabled, do: "Yes", else: "No"}</:item>
          <:item label="Filter">
            {if @rule.filter && @rule.filter != %{}, do: Jason.encode!(@rule.filter), else: "—"}
          </:item>
          <:item label="Created">
            {Calendar.strftime(@rule.inserted_at, "%Y-%m-%d %H:%M:%S UTC")}
          </:item>
        </.definition_list>
      </.k8s_section>
    </div>
    """
  end
end
