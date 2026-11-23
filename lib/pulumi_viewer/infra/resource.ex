defmodule PulumiViewer.Infra.Resource do
  use Ash.Resource, domain: PulumiViewer.Infra, data_layer: Ash.DataLayer.Simple

  actions do
    read :for_stack do
      argument :project, :string
      argument :stack, :string, allow_nil?: false
      manual PulumiViewer.Infra.Resource.Read
    end
  end

  attributes do
    attribute :urn, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :name, :string, public?: true
    attribute :type, :string, public?: true
    attribute :package, :string, public?: true
    attribute :module, :string, public?: true
    attribute :id, :string, public?: true
    attribute :custom, :boolean, public?: true
    attribute :protect, :boolean, public?: true
    attribute :parent_urn, :string, public?: true
    attribute :provider_urn, :string, public?: true
    attribute :dependencies, {:array, :string}, public?: true
    attribute :inputs, :map, public?: true
    attribute :outputs, :map, public?: true
  end
end

defmodule PulumiViewer.Infra.Resource.Read do
  use Ash.Resource.ManualRead
  alias PulumiViewer.Infra.{Resource, State}

  @impl true
  def read(query, _dlq, _opts, _ctx) do
    with {:ok, cp} <- State.checkpoint(query.arguments[:project], query.arguments.stack) do
      {:ok, Enum.map(cp.resources, &struct(Resource, wrap(&1)))}
    end
  end

  # outputs/inputs may be a masked string at the top level; Ash expects maps
  defp wrap(r), do: %{r | inputs: as_map(r.inputs), outputs: as_map(r.outputs)}
  defp as_map(m) when is_map(m), do: m
  defp as_map(v), do: %{"value" => v}
end
