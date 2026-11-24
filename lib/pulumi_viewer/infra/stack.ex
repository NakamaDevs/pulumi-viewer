defmodule PulumiViewer.Infra.Stack do
  use Ash.Resource,
    domain: PulumiViewer.Infra,
    data_layer: Ash.DataLayer.Simple,
    # the optional source argument picks one of the configured sources
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
    source = PulumiViewer.Storage.source(query.arguments[:source])

    with true <- source != nil || {:error, :unknown_source},
         {:ok, stacks} <- source_stacks(source) do
      read_all(source.name, stacks)
    end
  end

  defp source_stacks(source) do
    case State.stacks(source.name) do
      {:error, %PulumiViewer.CloudFormation.Error{} = e} -> {:error, e}
      other -> other
    end
  end

  defp read_all(source, stacks) do
    stacks =
      stacks
      |> Task.async_stream(
        fn s ->
          case State.checkpoint(source, s.project, s.stack) do
            {:ok, cp} -> {:ok, stack(source, s, cp)}
            # a source error (credentials, access) is shown instead of an empty list
            {:error, %PulumiViewer.CloudFormation.Error{} = e} -> {:error, e}
            _ -> {:ok, stack(source, s, %{resources: [], updated_at: nil, pulumi_version: nil})}
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

  defp stack(source, s, cp) do
    %Stack{
      key: source <> "/" <> s.key,
      source: source,
      project: s.project,
      name: s.stack,
      resource_count: length(cp.resources),
      updated_at: cp.updated_at,
      pulumi_version: cp.pulumi_version
    }
  end
end
