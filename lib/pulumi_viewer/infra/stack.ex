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
    with {:ok, stacks} <- State.stacks() do
      read_all(stacks)
    end
  end

  defp read_all(stacks) do
    stacks =
      stacks
      |> Task.async_stream(
        fn s ->
          case State.checkpoint(s.project, s.stack) do
            {:ok, cp} -> {:ok, stack(s, cp)}
            # a source error (credentials, access) is shown instead of an empty list
            {:error, %PulumiViewer.CloudFormation.Error{} = e} -> {:error, e}
            _ -> {:ok, stack(s, %{resources: [], updated_at: nil, pulumi_version: nil})}
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

  defp stack(s, cp) do
    %Stack{
      key: s.key,
      project: s.project,
      name: s.stack,
      resource_count: length(cp.resources),
      updated_at: cp.updated_at,
      pulumi_version: cp.pulumi_version
    }
  end
end
