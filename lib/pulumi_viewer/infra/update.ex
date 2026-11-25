defmodule PulumiViewer.Infra.Update do
  use Ash.Resource, domain: PulumiViewer.Infra, data_layer: Ash.DataLayer.Simple

  actions do
    read :for_stack do
      argument :project, :string
      argument :source, :string
      argument :stack, :string, allow_nil?: false
      manual PulumiViewer.Infra.Update.Read
    end
  end

  attributes do
    attribute :version, :integer, primary_key?: true, allow_nil?: false, public?: true
    attribute :kind, :string, public?: true
    attribute :result, :string, public?: true
    attribute :message, :string, public?: true
    attribute :started_at, :utc_datetime, public?: true
    attribute :duration_s, :integer, public?: true
    attribute :changes, :map, public?: true
    attribute :resources, {:array, :map}, public?: true
  end
end

defmodule PulumiViewer.Infra.Update.Read do
  use Ash.Resource.ManualRead
  alias PulumiViewer.Infra.{State, Update}

  @impl true
  def read(query, _dlq, _opts, _ctx) do
    {:ok,
     State.updates(query.arguments[:source], query.arguments[:project], query.arguments.stack)
     |> Enum.map(&struct(Update, &1))}
  end
end
