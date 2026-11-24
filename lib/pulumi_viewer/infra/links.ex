defmodule PulumiViewer.Infra.Links do
  @moduledoc """
  Links resources that have the same physical ID in sources of a different kind, for example a
  bucket that Pulumi tracks and a CloudFormation stack still owns. Read on demand, never cached.
  """
  alias PulumiViewer.Infra.State
  alias PulumiViewer.Sources

  @doc "physical id => [%{source, kind, project, stack}] for every source whose kind is not `kind`."
  def index(kind, sources \\ Sources.all()) do
    sources
    |> Enum.reject(&(&1.kind == kind))
    |> Enum.flat_map(fn src ->
      case State.stacks(src) do
        {:ok, stacks} -> Enum.map(stacks, &{src, &1})
        _ -> []
      end
    end)
    |> then(
      &Task.Supervisor.async_stream_nolink(PulumiViewer.TaskSupervisor, &1, link_fun(),
        max_concurrency: 8,
        timeout: 60_000,
        on_timeout: :kill_task
      )
    )
    |> Enum.flat_map(fn
      {:ok, pairs} -> pairs
      _ -> []
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {id, l} -> {id, Enum.uniq(l)} end)
  end

  defp link_fun do
    fn {src, s} ->
      case State.checkpoint(src, s.project, s.stack) do
        {:ok, cp} ->
          for %{id: id} <- cp.resources,
              is_binary(id) and id != "",
              do: {id, %{source: src.name, kind: src.kind, project: s.project, stack: s.stack}}

        _ ->
          []
      end
    end
  end
end
