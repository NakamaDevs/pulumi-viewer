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
    attribute :error, :string, public?: true
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
    results =
      Task.Supervisor.async_stream_nolink(
        PulumiViewer.TaskSupervisor,
        stacks,
        fn s ->
          case State.checkpoint(src, s.project, s.stack) do
            {:ok, cp} -> {:ok, stack(src, s, cp)}
            # credentials or access: the whole source fails, with a clear message
            {:error, %PulumiViewer.CloudFormation.Error{source?: true} = e} -> {:error, e}
            # one stack failed (deleted, denied for this stack, unreadable): show its message
            {:error, e} -> {:ok, failed(src, s, PulumiViewer.error_message(e))}
            _ -> {:ok, failed(src, s, nil)}
          end
        end,
        max_concurrency: 8,
        timeout: 60_000,
        on_timeout: :kill_task
      )
      |> Enum.zip(stacks)
      |> Enum.map(fn
        {{:ok, r}, _} -> r
        {{:exit, :timeout}, s} -> {:ok, failed(src, s, "Timed out while reading this stack.")}
        {{:exit, reason}, s} -> {:ok, failed(src, s, "Read failed: #{inspect(reason)}")}
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(results, &elem(&1, 1))}
      error -> error
    end
  end

  defp failed(src, s, msg) do
    %{stack(src, s, %{resources: [], updated_at: nil, pulumi_version: nil}) | error: msg}
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
