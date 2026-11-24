defmodule PulumiViewer.ResourceTree do
  @moduledoc """
  Parent/child rows for the resource list, like the parent and child resources of the
  Aspire dashboard: each row has a depth, a has-children flag and a collapsed flag.
  """

  @doc "Rows in tree order, sorted by name. Children of a collapsed URN are left out."
  def flatten(resources, collapsed \\ MapSet.new()) do
    urns = MapSet.new(resources, & &1.urn)

    by_parent =
      Enum.group_by(resources, fn r ->
        if r.parent_urn in urns and r.parent_urn != r.urn, do: r.parent_urn, else: nil
      end)

    by_parent = Map.new(by_parent, fn {k, v} -> {k, Enum.sort_by(v, &{&1.name, &1.urn})} end)
    walk(Map.get(by_parent, nil, []), by_parent, collapsed, 0, MapSet.new())
  end

  defp walk(nodes, by_parent, collapsed, depth, seen) do
    Enum.flat_map(nodes, fn r ->
      if r.urn in seen do
        []
      else
        kids = Map.get(by_parent, r.urn, [])
        hidden? = r.urn in collapsed

        row = %{
          resource: r,
          depth: depth,
          children?: kids != [],
          collapsed?: hidden? and kids != []
        }

        if hidden?,
          do: [row],
          else: [row | walk(kids, by_parent, collapsed, depth + 1, MapSet.put(seen, r.urn))]
      end
    end)
  end

  @doc "Keeps rows whose name, type or physical ID contains `q`, plus their ancestors."
  def filter(rows, q) when q in [nil, ""], do: rows

  def filter(rows, q) do
    q = String.downcase(q)

    hit? = fn %{resource: r} ->
      String.contains?(String.downcase("#{r.name} #{r.type} #{r.id}"), q)
    end

    # walk backwards: a row is kept when it matches or a kept row below it is deeper
    {kept, _} =
      rows
      |> Enum.reverse()
      |> Enum.reduce({[], nil}, fn row, {acc, need} ->
        cond do
          hit?.(row) -> {[row | acc], min_depth(need, row.depth)}
          need != nil and row.depth < need -> {[row | acc], row.depth}
          true -> {acc, need}
        end
      end)

    kept
  end

  defp min_depth(nil, d), do: d
  defp min_depth(n, d), do: min(n, d)
end
