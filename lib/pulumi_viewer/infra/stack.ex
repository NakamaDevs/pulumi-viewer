defmodule PulumiViewer.Infra.Stack do
  use Ash.Resource, domain: PulumiViewer.Infra, data_layer: Ash.DataLayer.Simple

  actions do
    read :read do
      primary? true
      manual PulumiViewer.Infra.Stack.Read
    end
  end

  attributes do
    attribute :key, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :project, :string, public?: true
    attribute :name, :string, public?: true
    attribute :resource_count, :integer, public?: true
    attribute :updated_at, :utc_datetime_usec, public?: true
    attribute :pulumi_version, :string, public?: true
  end
end

defmodule PulumiViewer.Infra.Stack.Read do
  use Ash.Resource.ManualRead
  alias PulumiViewer.Infra.{Stack, State}

  @impl true
  def read(_query, _data_layer_query, _opts, _context) do
    stacks =
      State.stacks()
      |> Task.async_stream(
        fn s ->
          cp =
            case State.checkpoint(s.project, s.stack),
              do: (
                {:ok, cp} -> cp
                _ -> %{resources: [], updated_at: nil, pulumi_version: nil}
              )

          %Stack{
            key: s.key,
            project: s.project,
            name: s.stack,
            resource_count: length(cp.resources),
            updated_at: cp.updated_at,
            pulumi_version: cp.pulumi_version
          }
        end, max_concurrency: 8, timeout: 30_000)
      |> Enum.map(fn {:ok, s} -> s end)

    {:ok, stacks}
  end
end
