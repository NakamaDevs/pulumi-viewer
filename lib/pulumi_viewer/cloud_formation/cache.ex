defmodule PulumiViewer.CloudFormation.Cache do
  @moduledoc "60 second cache for CloudFormation responses. Only successful calls are kept."
  use GenServer

  @table __MODULE__
  @ttl_ms 60_000

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, nil}
  end

  def fetch(key, fun) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, key) do
      [{^key, value, at}] when now - at < @ttl_ms ->
        {:ok, value}

      _ ->
        with {:ok, value} <- fun.() do
          :ets.insert(@table, {key, value, now})
          {:ok, value}
        end
    end
  end

  def clear, do: :ets.delete_all_objects(@table)
end
