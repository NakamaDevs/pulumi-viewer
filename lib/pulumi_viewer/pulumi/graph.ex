defmodule PulumiViewer.Pulumi.Graph do
  @moduledoc """
  Turns resources into xyflow nodes and edges. Positions are left at 0;
  the browser lays the graph out with ELK.
  """

  def build(resources, opts \\ []) do
    providers? = Keyword.get(opts, :providers, false)
    # every top-level resource is a child of the stack; those edges only add noise
    stack_edges? = Keyword.get(opts, :stack_edges, false)

    stack_urns =
      for r <- resources, r.type == "pulumi:pulumi:Stack", into: MapSet.new(), do: r.urn

    kept = Enum.reject(resources, &(provider?(&1) and not providers?))
    urns = MapSet.new(kept, & &1.urn)

    nodes =
      Enum.map(kept, fn r ->
        %{
          id: r.urn,
          type: "resource",
          position: %{x: 0, y: 0},
          data: %{
            label: r.name,
            type: r.type,
            package: r.package,
            module: r.module,
            id: r.id,
            protect: r.protect
          }
        }
      end)

    edges =
      Enum.flat_map(kept, fn r ->
        parent =
          if r.parent_urn && (stack_edges? or not MapSet.member?(stack_urns, r.parent_urn)),
            do: [{r.parent_urn, r.urn, "parent"}],
            else: []

        deps = Enum.map(r.dependencies, &{&1, r.urn, "dependency"})

        prov =
          if providers? and r.provider_urn, do: [{r.provider_urn, r.urn, "provider"}], else: []

        parent ++ deps ++ prov
      end)
      |> Enum.filter(fn {s, t, _} -> MapSet.member?(urns, s) and MapSet.member?(urns, t) end)
      |> Enum.uniq()
      |> Enum.map(fn {s, t, kind} ->
        %{
          id: "#{kind}:#{s}->#{t}",
          source: s,
          target: t,
          data: %{kind: kind},
          animated: kind == "dependency"
        }
      end)

    %{nodes: nodes, edges: edges}
  end

  defp provider?(r), do: String.starts_with?(r.type, "pulumi:providers:")
end
