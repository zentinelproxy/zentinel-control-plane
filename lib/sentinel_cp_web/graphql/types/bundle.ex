defmodule SentinelCpWeb.GraphQL.Types.Bundle do
  @moduledoc false
  use Absinthe.Schema.Notation

  alias SentinelCpWeb.GraphQL.Resolvers

  object :bundle do
    field :id, non_null(:id)
    field :version, :string
    field :status, non_null(:string)

    field :sha256, :string do
      resolve(fn bundle, _, _ -> {:ok, bundle.checksum} end)
    end

    field :size_bytes, :integer
    field :inserted_at, non_null(:datetime)
  end

  input_object :create_bundle_input do
    field :project_id, non_null(:id)
    field :config_source, non_null(:string)
    field :version, non_null(:string)
  end

  object :bundle_queries do
    field :bundles, list_of(:bundle) do
      arg(:project_id, non_null(:id))
      arg(:limit, :integer, default_value: 50)
      resolve(&Resolvers.Bundles.list/3)
    end
  end

  object :bundle_mutations do
    field :create_bundle, :bundle do
      arg(:input, non_null(:create_bundle_input))
      resolve(&Resolvers.Bundles.create/3)
    end
  end
end
