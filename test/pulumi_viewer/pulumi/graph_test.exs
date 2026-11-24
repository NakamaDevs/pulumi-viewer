defmodule PulumiViewer.Pulumi.GraphTest do
  use ExUnit.Case, async: true
  alias PulumiViewer.Pulumi.{Checkpoint, Graph}

  setup do
    {:ok, cp} = Checkpoint.parse(File.read!("test/fixtures/state/.pulumi/stacks/demo/dev.json"))
    %{graph: Graph.build(cp.resources, stack_edges: true), resources: cp.resources}
  end

  test "hides parent edges from the root stack by default", %{resources: resources} do
    g = Graph.build(resources)
    refute Enum.any?(g.edges, &(&1.source =~ "pulumi:pulumi:Stack"))
    assert Enum.any?(g.edges, &(&1.data.kind == "dependency"))
  end

  test "one node per resource, providers hidden by default", %{graph: g} do
    labels = Enum.map(g.nodes, & &1.data.label) |> Enum.sort()
    assert labels == ["assets", "assets-policy", "demo-dev"]
  end

  test "parent edges and dependency edges are typed", %{graph: g} do
    kinds = g.edges |> Enum.map(&{&1.data.kind, &1.source =~ "Stack" or &1.source =~ "BucketV2"})
    assert {"parent", true} in kinds
    assert {"dependency", true} in kinds
    assert Enum.all?(g.edges, &(&1.id && &1.source && &1.target))
  end

  test "includes providers when asked" do
    {:ok, cp} = Checkpoint.parse(File.read!("test/fixtures/state/.pulumi/stacks/demo/dev.json"))
    g = Graph.build(cp.resources, providers: true)
    assert length(g.nodes) == 4
    assert Enum.any?(g.edges, &(&1.data.kind == "provider"))
  end
end
