defmodule PulumiViewer.Infra.Stack do
  use Ash.Resource,
    domain: PulumiViewer.Infra,
    data_layer: Ash.DataLayer.Simple,
    primary_read_warning?: false

  actions do
    read :read do
      primary? true
      argument :source, :string
      manual PulumiViewer.Infra.Stack.Read
    end
  end

  attributes do
    attribute :key, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :source, :string, public?: true
    attribute :kind, :atom, public?: true
    attribute :environment, :term, public?: true
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
  def read(query, _data_layer_query, _opts, _context) do
    with {:ok, src} <- State.source(query.arguments[:source]),
         {:ok, stacks} <- State.stacks(src) do
      read_all(src, stacks)
    end
  end

  defp read_all(src, stacks) do
    stacks =
      stacks
      |> Task.async_stream(
        fn s ->
          case State.checkpoint(src, s.project, s.stack) do
            {:ok, cp} -> {:ok, stack(src, s, cp)}
            # a source error (credentials, access) is shown instead of an empty list
            {:error, %PulumiViewer.CloudFormation.Error{} = e} -> {:error, e}
            _ -> {:ok, stack(src, s, %{resources: [], updated_at: nil, pulumi_version: nil})}
          end
        end,
        max_concurrency: 8,
        timeout: 60_000
      )
      |> Enum.map(fn {:ok, r} -> r end)

    case Enum.find(stacks, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(stacks, &elem(&1, 1))}
      error -> error
    end
  end

  defp stack(src, s, cp) do
    %Stack{
      key: src.name <> ":" <> s.key,
      source: src.name,
      kind: src.kind,
      environment: PulumiViewer.Environment.of(src.kind, s.stack),
      project: s.project,
      name: s.stack,
      resource_count: length(cp.resources),
      updated_at: cp.updated_at,
      pulumi_version: cp.pulumi_version
    }
  end
end
