defmodule ZentinelCp.Analytics.RequestLog do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "request_logs" do
    belongs_to :service, ZentinelCp.Services.Service
    belongs_to :project, ZentinelCp.Projects.Project
    belongs_to :node, ZentinelCp.Nodes.Node

    field :timestamp, :utc_datetime_usec
    field :method, :string
    field :path, :string
    field :status, :integer
    field :latency_ms, :integer
    field :client_ip, :string
    field :user_agent, :string
    field :request_size, :integer
    field :response_size, :integer

    timestamps()
  end

  def changeset(log, attrs) do
    log
    |> cast(attrs, [
      :service_id,
      :project_id,
      :node_id,
      :timestamp,
      :method,
      :path,
      :status,
      :latency_ms,
      :client_ip,
      :user_agent,
      :request_size,
      :response_size
    ])
    |> validate_required([:service_id, :project_id, :timestamp])
  end
end
