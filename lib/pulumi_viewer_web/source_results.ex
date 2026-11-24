defmodule PulumiViewerWeb.SourceResults do
  @moduledoc """
  Reads the stacks of every source. Each source loads on its own, so one failing source
  does not hide the others: the result is `[{source, {:ok, stacks} | {:error, message}}]`.
  """
  alias PulumiViewer.Sources

  def load do
    sources = Sources.all()

    Task.Supervisor.async_stream_nolink(
      PulumiViewer.TaskSupervisor,
      sources,
      fn s ->
        case PulumiViewer.Infra.list_stacks(s.name) do
          {:ok, stacks} -> {s, {:ok, stacks}}
          {:error, e} -> {s, {:error, PulumiViewer.error_message(e)}}
        end
      end,
      max_concurrency: 4,
      timeout: 120_000,
      on_timeout: :kill_task
    )
    |> Enum.zip(sources)
    |> Enum.map(fn
      {{:ok, r}, _} -> r
      {{:exit, :timeout}, s} -> {s, {:error, "Timed out while reading this source."}}
      {{:exit, reason}, s} -> {s, {:error, "Read failed: #{inspect(reason)}"}}
    end)
  end

  @doc "Every stack that loaded, from all sources."
  def stacks(results), do: for({_, {:ok, stacks}} <- results, st <- stacks, do: st)

  def key(%{source: src, project: p, name: n}), do: "#{src}/#{p || "_"}/#{n}"

  @doc """
  Runs `fun` for every stack, a few at a time. Returns `[{stack, result}]` in stack order;
  a stack that crashes or times out gets `{:error, message}`.
  """
  def each_stack(stacks, fun) do
    Task.Supervisor.async_stream_nolink(PulumiViewer.TaskSupervisor, stacks, fun,
      max_concurrency: 4,
      timeout: 120_000,
      on_timeout: :kill_task
    )
    |> Enum.zip(stacks)
    |> Enum.map(fn
      {{:ok, r}, st} -> {st, r}
      {{:exit, :timeout}, st} -> {st, {:error, "Timed out while reading this stack."}}
      {{:exit, reason}, st} -> {st, {:error, "Read failed: #{inspect(reason)}"}}
    end)
  end
end
